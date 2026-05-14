extends Node
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const DEBUG_SPAWNER_LOGS := false
const ENEMY_SPAWN_RULES_DATA_PATH := "res://data/enemy_spawn_rules.json"
const BOSS_WAVE_SPAWN_STAGGER_SECONDS := 0.75

## 적 생성 관리자 (Enemy Spawner)
## 플레이어 주변 화면 밖에서 적을 주기적으로 생성

@export var enemy_scene: PackedScene = preload("res://scenes/ships/enemy_ship.tscn")
@export var enemy_melee_scene: PackedScene = preload("res://scenes/ships/enemy_melee_ship.tscn")
@export var enemy_gunner_scene: PackedScene = preload("res://scenes/ships/enemy_gunner_ship.tscn")
@export var enemy_firepot_scene: PackedScene = preload("res://scenes/ships/enemy_firepot_ship.tscn")
@export var spawn_interval: float = 5.2 # 생성 주기 (초)
@export var min_spawn_distance: float = 50.0 # 최소 생성 거리 (화면 안으로 더 빨리 들어오게 조정)
@export var max_spawn_distance: float = 70.0 # 최대 생성 거리
@export var max_enemies: int = 3 # 최대 적 수
@export var max_distance_limit: float = 115.0 # 재배치 거리
@export var reposition_check_interval: float = 1.0 # 재배치 체크 주기
@export var pressure_reposition_min_distance: float = 42.0
@export var pressure_reposition_max_distance: float = 56.0
@export var boss_reposition_distance_limit: float = 86.0
@export var boss_pressure_reposition_min_distance: float = 34.0
@export var boss_pressure_reposition_max_distance: float = 46.0

@export var boss_scene: PackedScene = preload("res://scenes/ships/boss_ship.tscn")

var timer: float = 0.0
var reposition_timer: float = 0.0
var player: Node3D = null
var boss_spawned: bool = false
var defeated_boss_count: int = 0
var elite_spawn_timer: float = 150.0 # 2분 30초 주기
var elite_spawn_interval: float = 150.0
var elite_spawn_count: int = 0
var max_elite_spawns: int = 3 # 2:30/5:00/7:30 중간 보스 웨이브 수
var elite_spawn_wave_counts: Array[int] = [1, 2, 2]
var elite_spawn_allow_overlap: bool = true
var boss_waves: Array[Dictionary] = []
var triggered_boss_wave_ids: Dictionary = {}
var pending_boss_wave_spawns: Array[Dictionary] = []
var active_final_boss_wave_member_ids: Dictionary = {}
var regular_spawn_stopped: bool = false
var start_time: int = 0
var blockade_spacing: float = 15.0
var fleet_templates: Dictionary = {
	"light": [],
	"heavy": [],
	"mixed": [],
}
var spawn_recipes: Dictionary = {}
var encounter_profiles: Dictionary = {}
var active_encounter_profile: String = ""
var scenario_triggers: Array[Dictionary] = []
var triggered_scenario_ids: Dictionary = {}
var fleet_progression: Array[Dictionary] = [
	{"start_time": 0.0, "end_time": 120.0, "light_weight": 0.8, "mixed_weight": 0.2, "heavy_weight": 0.0},
	{"start_time": 120.0, "end_time": 330.0, "light_weight": 0.45, "mixed_weight": 0.45, "heavy_weight": 0.10},
	{"start_time": 330.0, "end_time": 9999.0, "light_weight": 0.20, "mixed_weight": 0.50, "heavy_weight": 0.30},
]
var cannon_chance_start_time: float = 75.0
var cannon_chance_ramp_duration: float = 165.0
var cannon_chance_max: float = 0.45
var mid_boss_escort_layout: Array[Dictionary] = [
	{"ship_type": "sekibune_cannon", "role": "gunline", "lateral": -12.0, "back": 8.0, "hold_radius": 42.0, "break_radius": 52.0},
	{"ship_type": "kobayabune_melee", "role": "vanguard", "lateral": 12.0, "back": 10.0, "hold_radius": 34.0, "break_radius": 44.0},
]


func trigger_boss_event(ship_type_name: String = "atakebune_final") -> Node3D:
	regular_spawn_stopped = true
	print("[Warning] 보스 등장 이벤트 시작! 일반 적 스폰 중단")
	
	# 기존 배들은 침몰시키지 않고 그대로 둡니다 (유저 피드백 반영)
	# var enemies = get_tree().get_nodes_in_group("enemy")
	# for enemy in enemies:
	# 	if not enemy.is_in_group("boss") and enemy.has_method("die"):
	# 		enemy.die()
	
	# 보스 소환
	return _spawn_boss(ship_type_name)


func _spawn_boss(ship_type_name: String = "atakebune_final") -> Node3D:
	if not boss_scene or boss_spawned or not is_instance_valid(player):
		return null
	# 플레이어 전방 50m 지점에 소환
	var player_forward = - player.global_transform.basis.z
	var spawn_pos = player.global_position + (player_forward * 50.0)
	spawn_pos.y = 0
	var boss := _spawn_boss_ship(ship_type_name, spawn_pos, false, true)
	if is_instance_valid(boss):
		print("[Boss] 최종 보스 소환 완료!")
	return boss


func set_difficulty(new_interval: float, new_max: int) -> void:
	spawn_interval = new_interval
	max_enemies = new_max
	# timer가 너무 길게 남았으면 즉시 단축
	if timer > spawn_interval:
		timer = spawn_interval

func _ready() -> void:
	_load_enemy_spawn_rules_data()
	timer = spawn_interval
	reposition_timer = reposition_check_interval
	elite_spawn_timer = elite_spawn_interval
	elite_spawn_count = 0
	defeated_boss_count = 0
	triggered_scenario_ids.clear()
	triggered_boss_wave_ids.clear()
	pending_boss_wave_spawns.clear()
	active_final_boss_wave_member_ids.clear()
	start_time = Time.get_ticks_msec()
	_find_player()

func _process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_process(delta)
	PhysicsFrameProfiler.end("enemy_spawner_process", profile_start)


func _profiled_process(delta: float) -> void:
	if not is_instance_valid(player):
		_find_player()
		return

	_process_scenario_triggers()
	_process_boss_waves()
	_process_pending_boss_wave_spawns(delta)
		
	# 1. 적 생성 주기 관리
	var enemies = EntityRegistry.get_ships_by_team("enemy")
	var elite_count = _count_elite_enemy_ships()
	
	if not regular_spawn_stopped:
		# 1-1. 엘리트 소환 주기 체크
		if boss_waves.is_empty() and elite_spawn_count < max_elite_spawns and (elite_spawn_allow_overlap or elite_count == 0):
			elite_spawn_timer -= delta
			if elite_spawn_timer <= 0:
				elite_spawn_timer = elite_spawn_interval
				elite_spawn_count += 1
				_spawn_elite_wave(_get_elite_wave_ship_count(elite_spawn_count))
		
		# 1-2. 일반 적 스폰 (엘리트가 있으면 최대 적 수 제한을 낮춰서 긴장감 조절)
		var effective_max = max_enemies if elite_count == 0 else int(max_enemies * 0.6)
		if enemies.size() < effective_max:
			timer -= delta
			if timer <= 0:
				timer = compute_next_interval()
				_spawn_enemy()
	
	# 2. 너무 멀어진 적 재배치 (Tension 유지) - 타이머 기반으로 분산 체크
	reposition_timer -= delta
	if reposition_timer <= 0.0:
		reposition_timer = reposition_check_interval
		if not enemies.is_empty():
			_check_enemy_reposition_incremental(enemies)

func _check_enemy_reposition_incremental(enemies: Array) -> void:
	if not is_instance_valid(player):
		return
	var candidates: Array[Dictionary] = []
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node3D
		if not is_instance_valid(enemy):
			continue
		if enemy.get("is_dying") == true or enemy.get("is_sinking") == true or enemy.get("is_boarding") == true:
			continue
		if enemy.get("is_derelict") == true:
			continue
		var dist: float = enemy.global_position.distance_to(player.global_position)
		var limit: float = boss_reposition_distance_limit if _is_boss_pressure_ship(enemy) else max_distance_limit
		if dist <= limit:
			continue
		candidates.append({
			"enemy": enemy,
			"dist": dist,
			"boss": _is_boss_pressure_ship(enemy),
		})
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("boss", false)) != bool(b.get("boss", false)):
			return bool(a.get("boss", false))
		return float(a.get("dist", 0.0)) > float(b.get("dist", 0.0))
	)
	var check_count: int = min(5, candidates.size())
	for index in range(check_count):
		var entry: Dictionary = candidates[index]
		var enemy := entry.get("enemy") as Node3D
		if is_instance_valid(enemy):
			_reposition_enemy_for_pressure(enemy)


func compute_next_interval() -> float:
	# 약간의 랜덤성 추가 (±20%)
	return spawn_interval * randf_range(0.8, 1.2)


func _reposition_enemy_for_pressure(enemy: Node3D) -> void:
	var is_boss: bool = _is_boss_pressure_ship(enemy)
	var spawn_pos: Vector3 = _get_pressure_reposition_position(is_boss)
	enemy.global_position = spawn_pos
	if enemy.has_method("look_at"):
		enemy.look_at(player.global_position, Vector3.UP)
	if "target" in enemy:
		enemy.set("target", player)
	_prime_enemy_momentum(enemy, is_boss)
	if DEBUG_SPAWNER_LOGS:
		var label: String = "보스" if is_boss else "적함"
		print("[Spawner] 화면 밖 %s을 압박 위치로 재배치했습니다." % label)


func _get_pressure_reposition_position(is_boss: bool = false) -> Vector3:
	var player_forward: Vector3 = -player.global_transform.basis.z if is_instance_valid(player) else Vector3.FORWARD
	player_forward.y = 0.0
	if player_forward.length_squared() <= 0.0001:
		player_forward = Vector3.FORWARD
	else:
		player_forward = player_forward.normalized()
	var player_right: Vector3 = player_forward.cross(Vector3.UP)
	if player_right.length_squared() <= 0.0001:
		player_right = Vector3.RIGHT
	else:
		player_right = player_right.normalized()
	var min_dist: float = boss_pressure_reposition_min_distance if is_boss else pressure_reposition_min_distance
	var max_dist: float = boss_pressure_reposition_max_distance if is_boss else pressure_reposition_max_distance
	var angle_limit: float = deg_to_rad(34.0 if is_boss else 44.0)
	var distance: float = randf_range(min_dist, max_dist)
	var angle: float = randf_range(-angle_limit, angle_limit)
	var pressure_dir: Vector3 = (player_forward * cos(angle) + player_right * sin(angle)).normalized()
	var best_pos: Vector3 = player.global_position + pressure_dir * distance
	best_pos.y = 0.0
	for _attempt in range(5):
		if _is_position_safe(best_pos, 22.0 if is_boss else 20.0):
			return best_pos
		distance += 4.0
		best_pos = player.global_position + pressure_dir * distance
		best_pos.y = 0.0
	return best_pos


func _is_boss_pressure_ship(enemy: Node) -> bool:
	return is_instance_valid(enemy) and enemy.is_in_group("boss")

func _find_player() -> void:
	player = EntityRegistry.get_first_ship_by_team("player") as Node3D

func _count_elite_enemy_ships() -> int:
	var enemy_ships: Array = EntityRegistry.get_ships_by_team("enemy")
	var elite_count := 0
	for ship in enemy_ships:
		if is_instance_valid(ship) and ship.is_in_group("elite"):
			elite_count += 1
	return elite_count

func _get_elite_wave_ship_count(wave_number: int) -> int:
	if elite_spawn_wave_counts.is_empty():
		return 1
	var index: int = clampi(wave_number - 1, 0, elite_spawn_wave_counts.size() - 1)
	return maxi(1, int(elite_spawn_wave_counts[index]))


func has_data_driven_boss_waves() -> bool:
	return not boss_waves.is_empty()


func _process_boss_waves() -> void:
	if boss_waves.is_empty():
		return
	var elapsed_sec: float = _get_elapsed_spawn_time()
	for wave in boss_waves:
		var wave_id := str(wave.get("id", "")).strip_edges()
		if wave_id.is_empty() or triggered_boss_wave_ids.has(wave_id):
			continue
		if elapsed_sec < float(wave.get("time", 0.0)):
			continue
		triggered_boss_wave_ids[wave_id] = true
		_spawn_boss_wave(wave)


func _process_pending_boss_wave_spawns(delta: float) -> void:
	if pending_boss_wave_spawns.is_empty():
		return
	if not _can_process_pending_boss_spawns():
		pending_boss_wave_spawns.clear()
		return
	for index in range(pending_boss_wave_spawns.size()):
		var entry: Dictionary = pending_boss_wave_spawns[index]
		entry["delay"] = float(entry.get("delay", 0.0)) - delta
		pending_boss_wave_spawns[index] = entry
	for index in range(pending_boss_wave_spawns.size()):
		var entry: Dictionary = pending_boss_wave_spawns[index]
		if float(entry.get("delay", 0.0)) > 0.0:
			continue
		pending_boss_wave_spawns.remove_at(index)
		_spawn_queued_boss_wave_ship(entry)
		return


func _can_process_pending_boss_spawns() -> bool:
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return false
	return player.get("is_sinking") != true \
		and player.get("is_dying") != true \
		and player.get("is_dead") != true


func _spawn_boss_wave(wave: Dictionary) -> Array[Node3D]:
	var spawned: Array[Node3D] = []
	if not boss_scene:
		return spawned
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return spawned

	var is_final_wave: bool = bool(wave.get("final", false))
	if is_final_wave and boss_spawned:
		return spawned
	if bool(wave.get("stop_regular_spawns", false)):
		regular_spawn_stopped = true

	var wave_ships_variant: Variant = wave.get("ships", [])
	if typeof(wave_ships_variant) != TYPE_ARRAY:
		return spawned
	var wave_ships: Array = wave_ships_variant as Array
	var total_ship_count := 0
	for ship_variant in wave_ships:
		if typeof(ship_variant) != TYPE_DICTIONARY:
			continue
		var ship_info: Dictionary = ship_variant as Dictionary
		total_ship_count += maxi(1, int(ship_info.get("count", 1)))
	if total_ship_count <= 0:
		return spawned

	var center_pos: Vector3 = _get_biased_spawn_position()
	var player_forward: Vector3 = -player.global_transform.basis.z
	player_forward.y = 0.0
	if player_forward.length_squared() <= 0.0001:
		player_forward = Vector3.FORWARD
	else:
		player_forward = player_forward.normalized()
	var player_right: Vector3 = player_forward.cross(Vector3.UP)
	if player_right.length_squared() <= 0.0001:
		player_right = Vector3.RIGHT
	else:
		player_right = player_right.normalized()

	var spawned_index := 0
	for ship_variant in wave_ships:
		if typeof(ship_variant) != TYPE_DICTIONARY:
			continue
		var ship_info: Dictionary = ship_variant as Dictionary
		var ship_type_name := str(ship_info.get("ship_type", "")).strip_edges()
		if ship_type_name.is_empty():
			continue
		var ship_count: int = maxi(1, int(ship_info.get("count", 1)))
		var lateral_spacing: float = maxf(1.0, float(ship_info.get("lateral_spacing", 28.0)))
		var group_delay: float = maxf(0.0, float(ship_info.get("delay", ship_info.get("spawn_delay", 0.0))))
		for local_index in range(ship_count):
			var lateral_offset := 0.0
			if total_ship_count > 1:
				lateral_offset = (float(spawned_index) - float(total_ship_count - 1) * 0.5) * lateral_spacing
			var spawn_pos: Vector3 = center_pos + player_right * lateral_offset
			spawn_pos += player_forward * -absf(lateral_offset) * 0.18
			spawn_pos.y = 0.0
			var escort_layout := _get_boss_wave_escort_layout(total_ship_count, spawned_index) if bool(ship_info.get("escorts", false)) else []
			var spawn_entry := {
				"ship_type": ship_type_name,
				"spawn_pos": spawn_pos,
				"spawn_escorts": not escort_layout.is_empty(),
				"is_final_wave": is_final_wave,
				"allow_final_wave_member": is_final_wave,
				"escort_layout": escort_layout,
				"wave_id": str(wave.get("id", ""))
			}
			var spawn_delay: float = group_delay + BOSS_WAVE_SPAWN_STAGGER_SECONDS * float(spawned_index)
			if spawn_delay <= 0.0:
				var boss_ship := _spawn_queued_boss_wave_ship(spawn_entry)
				if is_instance_valid(boss_ship):
					spawned.append(boss_ship)
			else:
				spawn_entry["delay"] = spawn_delay
				pending_boss_wave_spawns.append(spawn_entry)
			spawned_index += 1

	if is_final_wave and not spawned.is_empty():
		_notify_data_driven_boss_wave_started(wave)
	if spawned_index > 0:
		print("[BossWave] %s 출현: %d척%s" % [
			str(wave.get("id", "")),
			spawned_index,
			" (분산 스폰)" if spawned_index > spawned.size() else ""
		])
	return spawned


func _spawn_queued_boss_wave_ship(entry: Dictionary) -> Node3D:
	var ship_type_name := str(entry.get("ship_type", "")).strip_edges()
	if ship_type_name.is_empty():
		return null
	var spawn_pos_variant: Variant = entry.get("spawn_pos", Vector3.ZERO)
	var spawn_pos: Vector3 = spawn_pos_variant if spawn_pos_variant is Vector3 else Vector3.ZERO
	var escort_layout: Array = entry.get("escort_layout", []) as Array
	return _spawn_boss_ship(
		ship_type_name,
		spawn_pos,
		bool(entry.get("spawn_escorts", false)),
		bool(entry.get("is_final_wave", false)),
		escort_layout,
		bool(entry.get("allow_final_wave_member", false))
	)


func _spawn_elite_wave(ship_count: int) -> Array[Node3D]:
	var spawned: Array[Node3D] = []
	var wave_count: int = maxi(1, ship_count)
	var center_pos: Vector3 = _get_biased_spawn_position()
	var player_forward: Vector3 = -player.global_transform.basis.z if is_instance_valid(player) else Vector3.FORWARD
	player_forward.y = 0.0
	if player_forward.length_squared() <= 0.0001:
		player_forward = Vector3.FORWARD
	else:
		player_forward = player_forward.normalized()
	var player_right: Vector3 = player_forward.cross(Vector3.UP)
	if player_right.length_squared() <= 0.0001:
		player_right = Vector3.RIGHT
	else:
		player_right = player_right.normalized()

	for index in range(wave_count):
		var lateral_offset: float = 0.0
		if wave_count > 1:
			lateral_offset = (float(index) - float(wave_count - 1) * 0.5) * 28.0
		var spawn_pos: Vector3 = center_pos + player_right * lateral_offset
		spawn_pos += player_forward * -absf(lateral_offset) * 0.18
		spawn_pos.y = 0.0
		var elite := _spawn_elite_ship(spawn_pos, index == 0)
		if is_instance_valid(elite):
			spawned.append(elite)
	return spawned

func _spawn_enemy() -> void:
	if not enemy_scene:
		return

	var existing_enemy_count: int = EntityRegistry.count_ships_by_team("enemy")
	var remaining_slots: int = max(0, max_enemies - existing_enemy_count)
	if remaining_slots <= 0:
		return

	var fleet_template: Array[Dictionary] = _pick_fleet_template(remaining_slots)
	if fleet_template.is_empty():
		fleet_template.append(_build_default_spawn_slot_info())

	_spawn_enemy_from_template(fleet_template, remaining_slots)


func _spawn_enemy_from_template(fleet_template: Array[Dictionary], remaining_slots: int = 999) -> void:
	if not enemy_scene or fleet_template.is_empty():
		return

	var spawn_count: int = min(fleet_template.size(), remaining_slots)
	var is_blockade: bool = spawn_count > 1
	var formation_type: String = str(fleet_template[0].get("formation_type", "line_abreast")) if spawn_count > 0 else "line_abreast"

	# 스폰 위치 그룹의 중심점 계산 (전방 편향)
	var center_pos = _get_biased_spawn_position()
	var player_forward = - player.global_transform.basis.z if player else Vector3.FORWARD
	player_forward.y = 0.0
	if player_forward.length_squared() <= 0.0001:
		player_forward = Vector3.FORWARD
	else:
		player_forward = player_forward.normalized()
	var to_player_dir = (player.global_position - center_pos) if is_instance_valid(player) else -player_forward
	to_player_dir.y = 0.0
	if to_player_dir.length_squared() <= 0.0001:
		to_player_dir = -player_forward
	else:
		to_player_dir = to_player_dir.normalized()
	var blockade_right = to_player_dir.cross(Vector3.UP).normalized()
	
	for i in range(spawn_count):
		var slot_info: Dictionary = _get_spawn_slot_info(fleet_template, i)
		if slot_info.is_empty():
			slot_info = _build_default_spawn_slot_info()
		var enemy_scene_for_slot: PackedScene = _pick_enemy_scene_for_slot(slot_info)
		if not is_instance_valid(enemy_scene_for_slot):
			enemy_scene_for_slot = enemy_scene
		var enemy = enemy_scene_for_slot.instantiate()
		_apply_spawn_slot_info(enemy, slot_info)
		
		# 차단진일 경우 가로로 배치 (간격 15m)
		var spawn_pos = center_pos
		if is_blockade and spawn_count > 1:
			spawn_pos += _get_formation_offset(formation_type, i, spawn_count, blockade_right, player_forward)
			
		# 초기 회전: 아직 트리에 없을 수 있으므로 look_at_from_position() 사용
		if is_instance_valid(player):
			enemy.look_at_from_position(spawn_pos, player.global_position, Vector3.UP)
		else:
			enemy.position = spawn_pos
		
		# Main 씬에 추가
		get_parent().add_child(enemy)
		enemy.global_position = spawn_pos
		EnemySpawnerFleetHelper.apply_authoring_runtime_overrides(enemy, slot_info)
		_prime_enemy_momentum(enemy)


## 스폰 위치 계산 (플레이어 전방 집중 및 부하 선박 회피)
func _get_biased_spawn_position() -> Vector3:
	var best_pos: Vector3
	var speed_ratio: float = 0.0
	if is_instance_valid(player) and "current_speed" in player and "max_speed" in player:
		speed_ratio = clampf(float(player.current_speed) / maxf(float(player.max_speed), 0.01), 0.0, 1.0)
	var dynamic_min_dist: float = lerpf(min_spawn_distance, 42.0, speed_ratio)
	var dynamic_max_dist: float = lerpf(max_spawn_distance, 58.0, speed_ratio)
	
	# 갤리선 전투 테마: 무조건 전방에서 스폰 (정면 돌파 유도)
	for i in range(5):
		var player_heading = player.rotation.y
		# 전방 ±55도 범위 내에서 무작위 각도
		var angle = player_heading + randf_range(-deg_to_rad(55), deg_to_rad(55))
		
		var distance = randf_range(dynamic_min_dist, dynamic_max_dist)
		var offset = Vector3(cos(angle), 0, sin(angle)) * distance
		best_pos = player.global_position + offset
		best_pos.y = 0 # 배는 물 위에
		
		# 해당 위치가 전체 아군(플레이어+나포함)과 안전 거리를 유지하는지 확인
		if _is_position_safe(best_pos, 25.0):
			return best_pos
			
	# 반복 실패 시 최후의 수단: 가장 마지막 위치를 더 멀리 밀어냄
	var fallback_offset = (best_pos - player.global_position).normalized() * 60.0
	best_pos += fallback_offset
	return best_pos

## 특정 위치가 모든 아군 배(플레이어+나포함)로부터 일정 거리(min_dist) 이상 떨어져 있는지 확인
func _is_position_safe(pos: Vector3, min_dist: float) -> bool:
	var safe_sq = min_dist * min_dist
	var allies = EntityRegistry.get_ships_by_team("player")
	
	for ally in allies:
		if not is_instance_valid(ally): continue
		# distance_squared_to가 연산이 더 빠름
		if pos.distance_squared_to(ally.global_position) < safe_sq:
			return false
			
	return true


func _spawn_elite_ship(spawn_pos_override: Variant = null, spawn_escorts: bool = true, ship_type_name: String = "atakebune_mid") -> Node3D:
	# 스폰 위치 (전역 좌표로 변환)
	var spawn_pos = _get_biased_spawn_position()
	if spawn_pos_override is Vector3:
		spawn_pos = spawn_pos_override
	var elite := _spawn_boss_ship(ship_type_name, spawn_pos, spawn_escorts, false)
	if is_instance_valid(elite):
		print("[Event] 중간 보스 편대 출현!")
	return elite


func _get_boss_wave_escort_layout(ship_count: int, local_index: int) -> Array:
	if mid_boss_escort_layout.is_empty():
		return []
	if ship_count <= 1:
		return mid_boss_escort_layout
	return [mid_boss_escort_layout[local_index % mid_boss_escort_layout.size()]]


func _spawn_boss_ship(ship_type_name: String, spawn_pos: Vector3, spawn_escorts: bool = false, marks_final_boss: bool = false, escort_layout_override: Array = [], allow_final_wave_member: bool = false) -> Node3D:
	if not boss_scene:
		return null
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return null
	if marks_final_boss and boss_spawned and not allow_final_wave_member:
		return null

	var boss_ship = boss_scene.instantiate()
	if boss_ship.has_method("set_team"):
		boss_ship.set_team("enemy")
	if "ship_type" in boss_ship:
		boss_ship.ship_type = ship_type_name
	if marks_final_boss:
		boss_spawned = true

	get_parent().add_child(boss_ship)
	boss_ship.global_position = spawn_pos
	boss_ship.look_at(player.global_position, Vector3.UP)
	_prime_enemy_momentum(boss_ship, true)
	_push_boss_hp_to_hud(boss_ship)
	_start_boss_audio(boss_ship)
	if marks_final_boss and allow_final_wave_member:
		_register_final_boss_wave_member(boss_ship)
	if spawn_escorts:
		_spawn_elite_escorts(boss_ship, escort_layout_override)
	return boss_ship


func _register_final_boss_wave_member(boss_ship: Node3D) -> void:
	if not is_instance_valid(boss_ship):
		return
	var boss_id := boss_ship.get_instance_id()
	active_final_boss_wave_member_ids[boss_id] = true
	boss_ship.set_meta("final_boss_wave_member", true)
	if boss_ship.has_signal("boss_died"):
		boss_ship.connect("boss_died", Callable(self, "_on_final_boss_wave_member_died").bind(boss_id), CONNECT_ONE_SHOT)


func _on_final_boss_wave_member_died(boss_id: int) -> void:
	active_final_boss_wave_member_ids.erase(boss_id)
	call_deferred("_check_final_boss_wave_victory")


func _check_final_boss_wave_victory() -> void:
	_cleanup_final_boss_wave_members()
	if not active_final_boss_wave_member_ids.is_empty() or _has_pending_final_boss_wave_spawns():
		return
	var lm: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(lm) and lm.has_method("show_victory"):
		if "hud" in lm and is_instance_valid(lm.hud) and lm.hud.has_method("show_gust_warning_message"):
			lm.hud.show_gust_warning_message("최종 보스 함대 격파!", 2.4)
		lm.show_victory()


func _cleanup_final_boss_wave_members() -> void:
	for boss_id_variant in active_final_boss_wave_member_ids.keys():
		var boss_id := int(boss_id_variant)
		var boss := NodeContractHelper.get_instance_node(boss_id)
		if not is_instance_valid(boss) or boss.get("is_dying") == true or boss.get("is_sinking") == true:
			active_final_boss_wave_member_ids.erase(boss_id)


func _has_pending_final_boss_wave_spawns() -> bool:
	for entry in pending_boss_wave_spawns:
		if bool(entry.get("is_final_wave", false)):
			return true
	return false


func _notify_data_driven_boss_wave_started(wave: Dictionary) -> void:
	var lm: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if not is_instance_valid(lm) or not lm.has_method("notify_data_driven_boss_wave_started"):
		return
	lm.call_deferred(
		"notify_data_driven_boss_wave_started",
		str(wave.get("id", "")),
		float(wave.get("time", 0.0)),
		bool(wave.get("final", false))
	)


func debug_spawn_mid_boss() -> Node3D:
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return null
	return _spawn_elite_ship()


func debug_spawn_fleet(fleet_class: String) -> void:
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return
	var fleet_template: Array[Dictionary] = _pick_fleet_template_by_class(fleet_class, 99)
	if fleet_template.is_empty():
		push_warning("[EnemySpawner] 디버그 편대 스폰 실패: %s" % fleet_class)
		return
	_spawn_enemy_from_template(fleet_template, fleet_template.size())


func debug_spawn_recipe(recipe_name: String, authoring_meta: Variant = null) -> void:
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return
	var fleet_template: Array[Dictionary] = EnemySpawnerFleetHelper.pick_fleet_template_by_recipe(self, recipe_name, 99)
	fleet_template = EnemySpawnerFleetHelper.apply_authoring_to_template(fleet_template, authoring_meta)
	if fleet_template.is_empty():
		push_warning("[EnemySpawner] 디버그 레시피 스폰 실패: %s" % recipe_name)
		return
	_spawn_enemy_from_template(fleet_template, fleet_template.size())


func debug_set_encounter_profile(profile_name: String) -> bool:
	return _set_encounter_profile(profile_name)


func debug_run_scenario_trigger(trigger_id: String) -> bool:
	return EnemySpawnerFleetHelper.run_scenario_trigger_by_id(self, trigger_id)


func debug_spawn_final_boss() -> Node3D:
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return null
	for wave in boss_waves:
		if bool(wave.get("final", false)):
			var wave_id := str(wave.get("id", "debug_final_boss"))
			triggered_boss_wave_ids[wave_id] = true
			var spawned := _spawn_boss_wave(wave)
			return spawned[0] if not spawned.is_empty() else null
	return trigger_boss_event()


func _push_boss_hp_to_hud(boss_ship: Node) -> void:
	if not is_instance_valid(boss_ship):
		return
	var lm: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(lm) and lm.has_method("update_boss_hp"):
		var current_hp: float = float(boss_ship.get("hull_hp"))
		var maximum_hp: float = float(boss_ship.get("max_hull_hp"))
		lm.call_deferred("update_boss_hp", current_hp, maximum_hp)


func _start_boss_audio(boss_ship: Node3D) -> void:
	if not is_instance_valid(boss_ship):
		return
	var audio_manager := get_node_or_null("/root/AudioManager")
	if not is_instance_valid(audio_manager):
		return
	if audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("boss_horn", boss_ship.global_position)
	if audio_manager.has_method("set_boss_battle_music"):
		audio_manager.set_boss_battle_music(true)
	if boss_ship.has_signal("boss_died"):
		boss_ship.connect("boss_died", Callable(self, "_on_boss_died").bind(boss_ship.get_instance_id()), CONNECT_ONE_SHOT)


func _on_boss_died(_boss_id: int) -> void:
	defeated_boss_count += 1
	var lm: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(lm) and lm.get("enemy_fire_pot_unlocked") != null:
		lm.set("enemy_fire_pot_unlocked", true)
	call_deferred("_stop_boss_audio_if_no_active_boss")


func _stop_boss_audio_if_no_active_boss() -> void:
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		if not is_instance_valid(enemy):
			continue
		if not enemy.is_in_group("boss"):
			continue
		if enemy.get("is_dying") == true or enemy.get("is_sinking") == true:
			continue
		return
	var audio_manager := get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("set_boss_battle_music"):
		audio_manager.set_boss_battle_music(false)


func _spawn_elite_escorts(flagship: Node3D, escort_layout_override: Array = []) -> void:
	if not enemy_scene or not is_instance_valid(player) or not is_instance_valid(flagship):
		return

	var flagship_forward: Vector3 = -flagship.global_transform.basis.z
	flagship_forward.y = 0.0
	if flagship_forward.length_squared() <= 0.0001:
		flagship_forward = Vector3.FORWARD
	else:
		flagship_forward = flagship_forward.normalized()
	var flagship_right: Vector3 = flagship_forward.cross(Vector3.UP).normalized()
	var flagship_pos: Vector3 = flagship.global_position
	var escort_layout := escort_layout_override
	if escort_layout.is_empty():
		escort_layout = mid_boss_escort_layout

	for escort_info_variant in escort_layout:
		if typeof(escort_info_variant) != TYPE_DICTIONARY:
			continue
		var escort_info: Dictionary = escort_info_variant as Dictionary
		var escort_scene: PackedScene = _pick_enemy_scene_for_slot(escort_info)
		if not is_instance_valid(escort_scene):
			escort_scene = enemy_scene
		var escort = escort_scene.instantiate()
		if not is_instance_valid(escort):
			continue
		_apply_spawn_slot_info(escort, escort_info)
		escort.set_meta("boss_escort_target_id", flagship.get_instance_id())
		escort.set_meta("boss_escort_lateral", float(escort_info.get("lateral", 0.0)))
		escort.set_meta("boss_escort_back", float(escort_info.get("back", 0.0)))
		escort.set_meta("boss_escort_hold_radius", float(escort_info.get("hold_radius", 34.0)))
		escort.set_meta("boss_escort_break_radius", float(escort_info.get("break_radius", 44.0)))

		var escort_pos: Vector3 = flagship_pos
		escort_pos += flagship_right * float(escort_info.get("lateral", 0.0))
		escort_pos += flagship_forward * -float(escort_info.get("back", 0.0))
		escort_pos.y = 0.0

		get_parent().add_child(escort)
		escort.global_position = escort_pos
		EnemySpawnerFleetHelper.apply_authoring_runtime_overrides(escort, escort_info)
		escort.look_at(player.global_position, Vector3.UP)
		_prime_enemy_momentum(escort)


func _load_enemy_spawn_rules_data() -> void:
	if not FileAccess.file_exists(ENEMY_SPAWN_RULES_DATA_PATH):
		return

	var file: FileAccess = FileAccess.open(ENEMY_SPAWN_RULES_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[EnemySpawner] enemy_spawn_rules.json을 열 수 없어 기본값을 사용합니다.")
		return

	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[EnemySpawner] enemy_spawn_rules.json 파싱 실패. 기본값을 사용합니다.")
		return

	var root: Dictionary = parsed as Dictionary
	_apply_enemy_spawn_rules_root(root)


func _apply_enemy_spawn_rules_root(root: Dictionary) -> void:
	EnemySpawnerFleetHelper.apply_enemy_spawn_rules_root(self, root)


func _build_default_spawn_slot_info() -> Dictionary:
	return EnemySpawnerFleetHelper.build_default_spawn_slot_info(self)


func _apply_spawn_slot_info(enemy: Node, slot_info: Dictionary) -> void:
	EnemySpawnerFleetHelper.apply_spawn_slot_info(enemy, slot_info)


func _pick_fleet_template(remaining_slots: int) -> Array[Dictionary]:
	return EnemySpawnerFleetHelper.pick_fleet_template(self, remaining_slots)


func _pick_fleet_template_by_class(fleet_class: String, remaining_slots: int) -> Array[Dictionary]:
	return EnemySpawnerFleetHelper.pick_fleet_template_by_class(self, fleet_class, remaining_slots)


func _get_spawn_slot_info(template: Array[Dictionary], index: int) -> Dictionary:
	return EnemySpawnerFleetHelper.get_spawn_slot_info(template, index)


func _parse_fleet_templates(raw_templates: Dictionary) -> Dictionary:
	return EnemySpawnerFleetHelper.parse_fleet_templates(raw_templates)


func _get_formation_offset(formation_type: String, index: int, spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	return EnemySpawnerFleetHelper.get_formation_offset(self, formation_type, index, spawn_count, right_dir, forward_dir)


func _get_line_abreast_offset(index: int, spawn_count: int, right_dir: Vector3) -> Vector3:
	return EnemySpawnerFleetHelper.get_line_abreast_offset(self, index, spawn_count, right_dir)


func _get_column_offset(index: int, spawn_count: int, forward_dir: Vector3) -> Vector3:
	return EnemySpawnerFleetHelper.get_column_offset(self, index, spawn_count, forward_dir)


func _get_wedge_offset(index: int, spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	return EnemySpawnerFleetHelper.get_wedge_offset(self, index, spawn_count, right_dir, forward_dir)


func _get_escort_offset(index: int, spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	return EnemySpawnerFleetHelper.get_escort_offset(self, index, spawn_count, right_dir, forward_dir)


func _get_echelon_offset(index: int, _spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	return EnemySpawnerFleetHelper.get_echelon_offset(self, index, _spawn_count, right_dir, forward_dir)


func _parse_fleet_progression(raw_progression: Array) -> Array[Dictionary]:
	return EnemySpawnerFleetHelper.parse_fleet_progression(raw_progression)


func _pick_fleet_class_for_time() -> String:
	return EnemySpawnerFleetHelper.pick_fleet_class_for_time(self)


func _pick_weighted_fleet_class(weights: Dictionary) -> String:
	return EnemySpawnerFleetHelper.pick_weighted_fleet_class(weights)


func _process_scenario_triggers() -> void:
	EnemySpawnerFleetHelper.process_scenario_triggers(self)


func _set_encounter_profile(profile_name: String) -> bool:
	return EnemySpawnerFleetHelper.set_encounter_profile(self, profile_name)


func _get_elapsed_spawn_time() -> float:
	var lm: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(lm) and "current_time" in lm:
		return maxf(0.0, float(lm.get("current_time")))
	if start_time <= 0:
		return 0.0
	return (Time.get_ticks_msec() - start_time) / 1000.0

func debug_spawn_ship(ship_type_name: String, distance: float = 22.0, lateral_offset: float = 0.0, authoring_meta: Variant = null) -> Node3D:
	if not enemy_scene or not is_instance_valid(player):
		return null

	var slot_info: Dictionary = {
		"ship_type": ship_type_name,
		"role": _infer_role_for_ship_type(ship_type_name)
	}
	var authoring: Dictionary = EnemySpawnerFleetHelper.normalize_authoring_meta(authoring_meta)
	if not authoring.is_empty():
		slot_info[EnemySpawnerFleetHelper.AUTHORING] = authoring
	var debug_scene: PackedScene = _pick_enemy_scene_for_slot(slot_info)
	if not is_instance_valid(debug_scene):
		debug_scene = enemy_scene
	var enemy: Node3D = debug_scene.instantiate() as Node3D
	_apply_spawn_slot_info(enemy, slot_info)

	var player_forward: Vector3 = -player.global_transform.basis.z
	var player_right: Vector3 = player_forward.cross(Vector3.UP).normalized()
	var spawn_pos: Vector3 = player.global_position + player_forward * distance + player_right * lateral_offset
	spawn_pos.y = 0.0

	get_parent().add_child(enemy)
	enemy.global_position = spawn_pos
	EnemySpawnerFleetHelper.apply_authoring_runtime_overrides(enemy, slot_info)
	enemy.look_at(player.global_position, Vector3.UP)
	_prime_enemy_momentum(enemy)
	print("[DEBUG] 적 테스트 소환: %s" % ship_type_name)
	return enemy

func _pick_enemy_scene_for_slot(slot_info: Dictionary) -> PackedScene:
	return EnemySpawnerFleetHelper.pick_enemy_scene(self, slot_info)

func _infer_role_for_ship_type(ship_type_name: String) -> String:
	return EnemySpawnerFleetHelper.infer_role_for_ship_type(ship_type_name)

func _prime_enemy_momentum(enemy: Node3D, heavy_spawn: bool = false) -> void:
	if not is_instance_valid(enemy):
		return
	var base_move_speed: float = 0.0
	if enemy.get("move_speed") != null:
		base_move_speed = float(enemy.get("move_speed"))
	elif enemy.get("max_speed") != null:
		base_move_speed = float(enemy.get("max_speed"))
	var player_speed: float = 0.0
	if is_instance_valid(player) and player.get("current_speed") != null:
		player_speed = float(player.get("current_speed"))
	var spawn_speed_floor: float = base_move_speed * (0.55 if not heavy_spawn else 0.45)
	var inherited_speed: float = player_speed * 0.8
	var initial_speed: float = maxf(spawn_speed_floor, inherited_speed)
	initial_speed = minf(initial_speed, maxf(base_move_speed * (1.1 if not heavy_spawn else 1.0), 0.1))
	if "current_speed" in enemy:
		enemy.current_speed = initial_speed
	if "_last_ai_speed" in enemy:
		enemy._last_ai_speed = initial_speed
	if "stamina" in enemy and "max_stamina" in enemy:
		enemy.stamina = maxf(float(enemy.stamina), float(enemy.max_stamina) * 0.85)
	if "rudder_angle" in enemy:
		enemy.rudder_angle = 0.0
