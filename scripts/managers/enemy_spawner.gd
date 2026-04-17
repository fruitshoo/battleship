extends Node
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const EnemySpawnerFleetHelper = preload("res://scripts/managers/enemy_spawner_fleet_helper.gd")
const DEBUG_SPAWNER_LOGS := false
const ENEMY_SPAWN_RULES_DATA_PATH := "res://data/enemy_spawn_rules.json"

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
@export var current_boarders: int = 1 # 레벨에 따른 도선 병사 수
@export var max_distance_limit: float = 115.0 # 재배치 거리
@export var reposition_check_interval: float = 1.0 # 재배치 체크 주기

@export var boss_scene: PackedScene = preload("res://scenes/ships/boss_ship.tscn")

var timer: float = 0.0
var reposition_timer: float = 0.0
var player: Node3D = null
var boss_spawned: bool = false
var elite_spawn_timer: float = 150.0 # 2분 30초 주기
var elite_spawn_interval: float = 150.0
var elite_spawn_count: int = 0
var max_elite_spawns: int = 3 # 2:30/5:00/7:30에만 중간 보스 등장
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
	{"start_time": 120.0, "end_time": 300.0, "light_weight": 0.45, "mixed_weight": 0.45, "heavy_weight": 0.10},
	{"start_time": 300.0, "end_time": 9999.0, "light_weight": 0.20, "mixed_weight": 0.50, "heavy_weight": 0.30},
]
var cannon_chance_start_time: float = 75.0
var cannon_chance_ramp_duration: float = 165.0
var cannon_chance_max: float = 0.45
var mid_boss_escort_layout: Array[Dictionary] = [
	{"ship_type": "sekibune_cannon", "role": "gunline", "lateral": -12.0, "back": 8.0},
	{"ship_type": "kobayabune_melee", "role": "vanguard", "lateral": 12.0, "back": 10.0},
]


func trigger_boss_event() -> Node3D:
	regular_spawn_stopped = true
	print("[Warning] 보스 등장 이벤트 시작! 일반 적 스폰 중단")
	
	# 기존 배들은 침몰시키지 않고 그대로 둡니다 (유저 피드백 반영)
	# var enemies = get_tree().get_nodes_in_group("enemy")
	# for enemy in enemies:
	# 	if not enemy.is_in_group("boss") and enemy.has_method("die"):
	# 		enemy.die()
	
	# 보스 소환
	return _spawn_boss()


func _spawn_boss() -> Node3D:
	if not boss_scene or boss_spawned:
		return null
	boss_spawned = true
	
	var boss = boss_scene.instantiate()
	if boss.has_method("set_team"):
		boss.set_team("enemy")
	if "ship_type" in boss:
		boss.ship_type = "atakebune_final" # 최종 보스 설정
	# 플레이어 전방 50m 지점에 소환
	var player_forward = - player.global_transform.basis.z
	var spawn_pos = player.global_position + (player_forward * 50.0)
	spawn_pos.y = 0
	
	get_parent().add_child(boss)
	boss.global_position = spawn_pos
	boss.look_at(player.global_position, Vector3.UP)
	_prime_enemy_momentum(boss, true)
	_push_boss_hp_to_hud(boss)
	print("[Boss] 최종 보스 소환 완료!")
	return boss


func set_difficulty(new_interval: float, new_max: int, new_boarders: int = 2) -> void:
	spawn_interval = new_interval
	max_enemies = new_max
	current_boarders = new_boarders
	# timer가 너무 길게 남았으면 즉시 단축
	if timer > spawn_interval:
		timer = spawn_interval

func _ready() -> void:
	_load_enemy_spawn_rules_data()
	timer = spawn_interval
	reposition_timer = reposition_check_interval
	elite_spawn_timer = elite_spawn_interval
	elite_spawn_count = 0
	triggered_scenario_ids.clear()
	start_time = Time.get_ticks_msec()
	_find_player()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		_find_player()
		return

	_process_scenario_triggers()
		
	# 1. 적 생성 주기 관리
	var enemies = EntityRegistry.get_ships_by_team("enemy")
	var elite_count = _count_elite_enemy_ships()
	
	if not regular_spawn_stopped:
		# 1-1. 엘리트 소환 주기 체크
		if elite_spawn_count < max_elite_spawns:
			elite_spawn_timer -= delta
			if elite_spawn_timer <= 0:
				elite_spawn_timer = elite_spawn_interval
				elite_spawn_count += 1
				_spawn_elite_ship()
		
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
	# 한 프레임에 최대 5개까지만 체크
	var check_count = min(5, enemies.size())
	for i in range(check_count):
		# 랜덤하게 하나 골라 체크 (순차적으로 하려면 index 관리가 필요하므로 간단히 랜덤 선택)
		var enemy = enemies.pick_random()
		if not is_instance_valid(enemy) or enemy.get("is_dying") or enemy.get("is_boarding"): continue
		
		# 도선 중이 아닌 배 중에서 거리가 너무 멀어진 배 찾기
		var dist = enemy.global_position.distance_to(player.global_position)
		if dist > max_distance_limit:
			# 앞쪽에 다시 스폰 (거리 리셋, 기차놀이 방지)
			var spawn_pos = _get_biased_spawn_position()
			var player_forward = - player.global_transform.basis.z if player else Vector3.FORWARD
			player_forward.y = 0.0
			if player_forward.length_squared() <= 0.0001:
				player_forward = Vector3.FORWARD
			else:
				player_forward = player_forward.normalized()
			
			# 약간의 위치 오프셋 추가 (다른 배와 겹침 방지)
			var offset_right = player_forward.cross(Vector3.UP).normalized()
			spawn_pos += offset_right * randf_range(-15.0, 15.0)
			
			enemy.global_position = spawn_pos
			
			if enemy.has_method("look_at") and is_instance_valid(player):
				enemy.look_at(player.global_position, Vector3.UP)
			
				if DEBUG_SPAWNER_LOGS:
					print("[Spawner] 멀어진 적함을 플레이어 전방 차단진으로 재배치(Recycle) 했습니다.")


func compute_next_interval() -> float:
	# 약간의 랜덤성 추가 (±20%)
	return spawn_interval * randf_range(0.8, 1.2)

func _find_player() -> void:
	player = EntityRegistry.get_first_ship_by_team("player") as Node3D

func _count_elite_enemy_ships() -> int:
	var enemy_ships: Array = EntityRegistry.get_ships_by_team("enemy")
	var elite_count := 0
	for ship in enemy_ships:
		if is_instance_valid(ship) and ship.is_in_group("elite"):
			elite_count += 1
	return elite_count

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
		
		# 레벨 기반 스탯 설정 (이동 속도와 HP는 함선 씬 고유 스탯을 사용하도록 수정)
		if "boarders_count" in enemy:
			enemy.boarders_count = current_boarders


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


func _spawn_elite_ship() -> Node3D:
	if not boss_scene:
		return null
	
	# 중간 보스는 보스 베이스(Atakebune)를 사용하되 tier 1로 설정
	var elite = boss_scene.instantiate()
	if elite.has_method("set_team"):
		elite.set_team("enemy")
	if "ship_type" in elite:
		# 중간 보스 성격의 엘리트 함선
		elite.ship_type = "atakebune_mid"
		
	# 스폰 위치 (전역 좌표로 변환)
	var spawn_pos = _get_biased_spawn_position()
	get_parent().add_child(elite)
	elite.global_position = spawn_pos
	elite.look_at(player.global_position, Vector3.UP)
	_prime_enemy_momentum(elite, true)
	_push_boss_hp_to_hud(elite)
	_spawn_elite_escorts(spawn_pos)
	
	print("[Event] 중간 보스 편대 출현!")
	return elite


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
	return trigger_boss_event()


func _push_boss_hp_to_hud(boss_ship: Node) -> void:
	if not is_instance_valid(boss_ship):
		return
	var lm: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(lm) and lm.has_method("update_boss_hp"):
		var current_hp: float = float(boss_ship.get("hull_hp"))
		var maximum_hp: float = float(boss_ship.get("max_hull_hp"))
		lm.call_deferred("update_boss_hp", current_hp, maximum_hp)


func _spawn_elite_escorts(flagship_pos: Vector3) -> void:
	if not enemy_scene or not is_instance_valid(player):
		return

	var player_forward: Vector3 = -player.global_transform.basis.z
	player_forward.y = 0.0
	if player_forward.length_squared() <= 0.0001:
		player_forward = Vector3.FORWARD
	else:
		player_forward = player_forward.normalized()
	var player_right: Vector3 = player_forward.cross(Vector3.UP).normalized()

	for escort_info in mid_boss_escort_layout:
		var escort_scene: PackedScene = _pick_enemy_scene_for_slot(escort_info)
		if not is_instance_valid(escort_scene):
			escort_scene = enemy_scene
		var escort = escort_scene.instantiate()
		if not is_instance_valid(escort):
			continue
		_apply_spawn_slot_info(escort, escort_info)

		var escort_pos: Vector3 = flagship_pos
		escort_pos += player_right * float(escort_info.get("lateral", 0.0))
		escort_pos += player_forward * -float(escort_info.get("back", 0.0))
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
	var authoring := EnemySpawnerFleetHelper.normalize_authoring_meta(authoring_meta)
	if not authoring.is_empty():
		slot_info[EnemySpawnerFleetHelper.AUTHORING] = authoring
	var debug_scene: PackedScene = _pick_enemy_scene_for_slot(slot_info)
	if not is_instance_valid(debug_scene):
		debug_scene = enemy_scene
	var enemy = debug_scene.instantiate()
	_apply_spawn_slot_info(enemy, slot_info)

	var player_forward = -player.global_transform.basis.z
	var player_right = player_forward.cross(Vector3.UP).normalized()
	var spawn_pos = player.global_position + player_forward * distance + player_right * lateral_offset
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
