extends Node
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const DEBUG_SPAWNER_LOGS := false

## 적 생성 관리자 (Enemy Spawner)
## 플레이어 주변 화면 밖에서 적을 주기적으로 생성

@export var enemy_scene: PackedScene = preload("res://scenes/enemy_ship.tscn")
@export var spawn_interval: float = 5.2 # 생성 주기 (초)
@export var min_spawn_distance: float = 50.0 # 최소 생성 거리 (화면 안으로 더 빨리 들어오게 조정)
@export var max_spawn_distance: float = 70.0 # 최대 생성 거리
@export var max_enemies: int = 3 # 최대 적 수
@export var current_boarders: int = 1 # 레벨에 따른 도선 병사 수
@export var max_distance_limit: float = 115.0 # 재배치 거리
@export var reposition_check_interval: float = 1.0 # 재배치 체크 주기

@export var boss_scene: PackedScene = preload("res://scenes/entities/boss_ship.tscn")

var timer: float = 0.0
var reposition_timer: float = 0.0
var player: Node3D = null
var boss_spawned: bool = false
var elite_spawn_timer: float = 120.0 # 2분 주기
var elite_spawn_interval: float = 120.0
var elite_spawn_count: int = 0
var max_elite_spawns: int = 4 # 2/4/6/8분에만 중간 보스 등장
var regular_spawn_stopped: bool = false
var start_time: int = 0


func trigger_boss_event() -> void:
	regular_spawn_stopped = true
	print("[Warning] 보스 등장 이벤트 시작! 일반 적 스폰 중단")
	
	# 기존 배들은 침몰시키지 않고 그대로 둡니다 (유저 피드백 반영)
	# var enemies = get_tree().get_nodes_in_group("enemy")
	# for enemy in enemies:
	# 	if not enemy.is_in_group("boss") and enemy.has_method("die"):
	# 		enemy.die()
	
	# 보스 소환
	_spawn_boss()


func _spawn_boss() -> void:
	if not boss_scene or boss_spawned: return
	boss_spawned = true
	
	var boss = boss_scene.instantiate()
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


func set_difficulty(new_interval: float, new_max: int, new_boarders: int = 2) -> void:
	spawn_interval = new_interval
	max_enemies = new_max
	current_boarders = new_boarders
	# timer가 너무 길게 남았으면 즉시 단축
	if timer > spawn_interval:
		timer = spawn_interval

func _ready() -> void:
	timer = spawn_interval
	reposition_timer = reposition_check_interval
	elite_spawn_timer = elite_spawn_interval
	elite_spawn_count = 0
	_find_player()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		_find_player()
		return
		
	# 1. 적 생성 주기 관리
	var enemies = SceneGroupCache.get_nodes(get_tree(), "enemy")
	var elite_count = SceneGroupCache.get_nodes(get_tree(), "elite").size()
	
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
	player = SceneGroupCache.get_first(get_tree(), "player") as Node3D

func _spawn_enemy() -> void:
	if not enemy_scene:
		return
		
	# 80% 확률로 차단진(Blockade) 스폰, 20% 확률로 단일 스폰
	var spawn_count = 1
	var is_blockade = false
	if randf() < 0.8:
		spawn_count = randi_range(2, 3)
		is_blockade = true
		
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
	
	var existing_enemy_count: int = SceneGroupCache.get_nodes(get_tree(), "enemy").size()
	for i in range(spawn_count):
		# 최대 적 수 초과 체크
		if existing_enemy_count >= max_enemies:
			break
			
		var enemy = enemy_scene.instantiate()
		
		# 시간 경과에 따른 함종 결정
		var elapsed_sec = (Time.get_ticks_msec() - start_time) / 1000.0
		var cannon_chance = clamp((elapsed_sec - 75.0) / 165.0, 0.0, 0.45)
		
		# JSON 기반 함종 할당
		# 근접형은 더 작은 kobayabune, 원거리형은 sekibune, 엘리트는 atakebune
		if randf() > cannon_chance:
			if "ship_type" in enemy: enemy.ship_type = "kobayabune_melee"
		else:
			if "ship_type" in enemy: enemy.ship_type = "sekibune_cannon"
		
		# 차단진일 경우 가로로 배치 (간격 15m)
		var spawn_pos = center_pos
		if is_blockade and spawn_count > 1:
			var offset_multiplier = i - (spawn_count - 1) / 2.0
			spawn_pos += blockade_right * (offset_multiplier * 15.0)
			
		# 초기 회전: 아직 트리에 없을 수 있으므로 look_at_from_position() 사용
		if is_instance_valid(player):
			enemy.look_at_from_position(spawn_pos, player.global_position, Vector3.UP)
		else:
			enemy.position = spawn_pos
		
		# Main 씬에 추가
		get_parent().add_child(enemy)
		enemy.global_position = spawn_pos
		_prime_enemy_momentum(enemy)
		existing_enemy_count += 1
		
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
	var allies = SceneGroupCache.get_nodes(get_tree(), "player")
	
	for ally in allies:
		if not is_instance_valid(ally): continue
		# distance_squared_to가 연산이 더 빠름
		if pos.distance_squared_to(ally.global_position) < safe_sq:
			return false
			
	return true


func _spawn_elite_ship() -> void:
	if not boss_scene: return
	
	# 중간 보스는 보스 베이스(Atakebune)를 사용하되 tier 1로 설정
	var elite = boss_scene.instantiate()
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


func debug_spawn_mid_boss() -> void:
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return
	_spawn_elite_ship()


func debug_spawn_final_boss() -> void:
	if not is_instance_valid(player):
		_find_player()
	if not is_instance_valid(player):
		return
	trigger_boss_event()


func _push_boss_hp_to_hud(boss_ship: Node) -> void:
	if not is_instance_valid(boss_ship):
		return
	var lm: Node = get_tree().root.find_child("LevelManager", true, false)
	if not is_instance_valid(lm):
		var lm_nodes = SceneGroupCache.get_nodes(get_tree(), "level_manager")
		if lm_nodes.size() > 0:
			lm = lm_nodes[0]
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

	var escort_layout: Array[Dictionary] = [
		{"ship_type": "sekibune_cannon", "lateral": -12.0, "back": 8.0},
		{"ship_type": "kobayabune_melee", "lateral": 12.0, "back": 10.0},
	]

	for escort_info in escort_layout:
		var escort = enemy_scene.instantiate()
		if not is_instance_valid(escort):
			continue
		if "ship_type" in escort:
			escort.ship_type = String(escort_info.get("ship_type", "kobayabune_melee"))

		var escort_pos: Vector3 = flagship_pos
		escort_pos += player_right * float(escort_info.get("lateral", 0.0))
		escort_pos += player_forward * -float(escort_info.get("back", 0.0))
		escort_pos.y = 0.0

		get_parent().add_child(escort)
		escort.global_position = escort_pos
		escort.look_at(player.global_position, Vector3.UP)
		_prime_enemy_momentum(escort)

func debug_spawn_ship(ship_type_name: String, distance: float = 22.0, lateral_offset: float = 0.0) -> Node3D:
	if not enemy_scene or not is_instance_valid(player):
		return null

	var enemy = enemy_scene.instantiate()
	if "ship_type" in enemy:
		enemy.ship_type = ship_type_name

	var player_forward = -player.global_transform.basis.z
	var player_right = player_forward.cross(Vector3.UP).normalized()
	var spawn_pos = player.global_position + player_forward * distance + player_right * lateral_offset
	spawn_pos.y = 0.0

	get_parent().add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.look_at(player.global_position, Vector3.UP)
	_prime_enemy_momentum(enemy)
	print("[DEBUG] 적 테스트 소환: %s" % ship_type_name)
	return enemy

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
