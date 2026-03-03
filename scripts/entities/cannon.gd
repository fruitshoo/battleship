extends Node3D

## 함포 (Cannon)
## 범위 내 적을 탐지하고 자동으로 발사 (Area3D 대신 직접 탐지)

@export var cannonball_scene: PackedScene = preload("res://scenes/projectiles/cannonball.tscn")
@export var muzzle_smoke_scene: PackedScene = preload("res://scenes/effects/muzzle_smoke.tscn")
@export var fire_cooldown: float = 2.0
@export var detection_range: float = 25.0
@export var detection_arc: float = 25.0 # 탐지 각도 (±25도)
@export var team: String = "player" # "player" or "enemy"

@onready var muzzle: Marker3D = $Muzzle

var cooldown_timer: float = 0.0

var is_preparing: bool = false
var prepare_timer: float = 0.0
@export var prepare_time: float = 0.15 # 0.8에서 타격감을 위해 0.15초로 단축
var current_target: Node3D = null
var _search_tick: int = 0

# 함대 업그레이드 보너스 (나포함 전용)
var fleet_damage_mult: float = 1.0
var fleet_cooldown_mult: float = 1.0

# 함수(수명 주기별) 성능을 위한 업그레이드 수치 캐싱
var _cached_range_mult: float = 1.0
var _cached_cd_mult: float = 1.0
var _cached_dmg_mult: float = 1.0

func _ready() -> void:
	# 초기 업그레이드 적용
	_update_cached_stats()
	# 업그레이드 발생 시그널 연결
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_signal("upgrade_applied"):
		upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id == "cannon":
		_update_cached_stats()

func _update_cached_stats() -> void:
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and "current_levels" in upgrade_manager and "UPGRADES" in upgrade_manager:
		var cannon_lv = upgrade_manager.current_levels.get("cannon", 0)
		var stat_lv = int(cannon_lv / 2)
		var s = upgrade_manager.UPGRADES.get("cannon", {}).get("stats", {})
		
		_cached_range_mult = 1.0 + (s.get("range_pct_per_stat", 15) / 100.0) * stat_lv
		_cached_cd_mult = maxf(0.5, 1.0 - (s.get("cd_pct_per_stat", 10) / 100.0) * stat_lv)
		_cached_dmg_mult = 1.0 + (s.get("dmg_pct_per_stat", 25) / 100.0) * stat_lv

func set_fleet_bonus(dmg_mult: float, cd_mult: float) -> void:
	fleet_damage_mult = dmg_mult
	fleet_cooldown_mult = cd_mult
	print("[Cannon] 함대 보너스 설정: 데미지x%.1f, 쿨다운x%.1f" % [dmg_mult, cd_mult])


func _process(delta: float) -> void:
	# 0. 부모 배의 상태 체크: 배가 침몰 중이거나 유령선(폐선)이면 발사 불가
	var ship = get_parent()
	if is_instance_valid(ship):
		if ship.get("is_dying") or ship.get("is_sinking") or ship.get("is_derelict"):
			is_preparing = false
			current_target = null
			return

	if is_preparing:
		# 발사 대기 중에도 타겟이 유효한지 실시간 체크
		if not _is_target_valid(current_target):
			is_preparing = false
			current_target = null
			return
			
		prepare_timer -= delta
		if prepare_timer <= 0:
			_execute_fire()
		return
		
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			# 장전 완료 사운드 (금속 철컥/쿵 소리)
			var audio_manager = get_node_or_null("/root/AudioManager")
			if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
				audio_manager.play_sfx("cannon_reload", global_position, randf_range(0.9, 1.1))
		return
	
	# 10프레임마다 또는 타겟이 없을 때만 타겟 탐지 (성능 최적화)
	_search_tick += 1
	if _search_tick >= 10 or not is_instance_valid(current_target):
		_search_tick = 0
		_update_target()
	
	if is_instance_valid(current_target):
		# 사거리 및 각도 재검증 (타겟이 범위를 벗어났는지 확인)
		if not _is_target_valid(current_target):
			current_target = null
		else:
			fire(current_target)

func _get_current_range() -> float:
	return detection_range * _cached_range_mult

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var current_range = _get_current_range()
	# 최대 탐지 거리의 제곱값 초기화 (이보다 먼 타겟은 무시)
	var max_range_sq: float = current_range * current_range
	# 현재까지 찾은 가장 '매력적인' 타겟의 가중치 적용 거리
	var best_score_sq: float = INF
	
	var enemy_group = "enemy" if team == "player" else "player"
	var enemies = get_tree().get_nodes_in_group(enemy_group)
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		# 실제 물리적 거리 스퀘어 계산
		var real_dist_sq = global_position.distance_squared_to(enemy.global_position)
		
		# 실제 거리가 최대 사거리를 벗어나면 무조건 패스
		if real_dist_sq > max_range_sq:
			continue
		
		if not _is_within_arc(enemy):
			continue
			
		if _is_ship_occupied_by_friendly(enemy):
			continue
			
		# [핵심 로직] 타겟 점수 계산 (실제 거리를 기반으로 패널티 부여)
		var score_sq = real_dist_sq
		
		# 타겟 배에 적군이 한 명도 없다면 (빈 배거나 곧 빈 배가 될 배),
		# 거리에 엄청난 페널티(예: 10배 거리)를 주어 우선순위를 대폭 낮춤
		if not _is_ship_occupied_by_enemy(enemy):
			score_sq *= 100.0 # 스퀘어 값이므로 100배 = 거리 10배
				
		# 점수가 가장 낮은(가장 매력적인) 타겟 갱신
		if score_sq < best_score_sq:
			best_score_sq = score_sq
			nearest_enemy = enemy
	
	current_target = nearest_enemy

func _is_target_valid(target: Node3D) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	
	# 침몰 중이거나 체력이 없는 배는 타겟에서 제외
	var is_dying = target.get("is_dying") == true
	var is_sinking = target.get("is_sinking") == true
	var is_dead_hp = target.get("hp") != null and target.get("hp") <= 0
	
	if is_dying or is_sinking or is_dead_hp:
		return false
		
	# 그룹 체크 (침몰 시 그룹에서 빠짐)
	var enemy_group = "enemy" if team == "player" else "player"
	if not target.is_in_group(enemy_group):
		return false
		
	var current_range = _get_current_range()
	if global_position.distance_squared_to(target.global_position) > current_range * current_range: return false
	if not _is_within_arc(target): return false
	
	# 도선 중이거나 폐선인 배인지 최종 체크
	if target.get("is_derelict") == true: return false
	var attacker = target.get("boarding_attacker")
	if is_instance_valid(attacker) and attacker.get("team") == team:
		return false
		
	if _is_ship_occupied_by_friendly(target): return false
	return true

func _is_within_arc(target: Node3D) -> bool:
	var to_target = (target.global_position - global_position).normalized()
	var forward = - global_transform.basis.z
	var dot = forward.dot(to_target)
	var angle = rad_to_deg(acos(clamp(dot, -1.0, 1.0)))
	return angle < detection_arc


## 아군 오사 방지를 위해 배에 아군이 있는지 체크
func _is_ship_occupied_by_friendly(target_ship: Node3D) -> bool:
	var soldiers_node = target_ship.get_node_or_null("Soldiers")
	if not soldiers_node: return false
	
	for child in soldiers_node.get_children():
		# 살아있는 아군 병사가 한 명이라도 있으면 True
		if child.get("team") == team and child.get("current_state") != 4: # 4 = DEAD
			return true
	return false

## 타겟 우선순위를 위해 배에 적군이 있는지 체크
func _is_ship_occupied_by_enemy(target_ship: Node3D) -> bool:
	var soldiers_node = target_ship.get_node_or_null("Soldiers")
	if not soldiers_node: return false
	
	var enemy_team = "enemy" if team == "player" else "player"
	for child in soldiers_node.get_children():
		# 살아있는 적군 병사가 한 명이라도 있으면 True
		if child.get("team") == enemy_team and child.get("current_state") != 4: # 4 = DEAD
			return true
	return false


func _get_current_cooldown() -> float:
	# 캐시된 업그레이드 배율 * 함대 배율
	return fire_cooldown * _cached_cd_mult * fleet_cooldown_mult


func fire(target_enemy: Node3D) -> void:
	if not cannonball_scene: return
	
	# 발사 준비(도화선) 시작
	is_preparing = true
	prepare_timer = prepare_time
	current_target = target_enemy
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cannon_fuse", global_position)


func _execute_fire() -> void:
	is_preparing = false
	
	# 최종 발사 직전 다시 한번 타겟 유효성 검증
	if not _is_target_valid(current_target):
		current_target = null
		return
		
	# 사운드 재생
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cannon_fire", global_position, randf_range(0.9, 1.1))
		
	# 화면 흔들림 (Screen Shake) - 플레이어 대포일 경우만 (오래봐도 안 피로하게 아주 약하게)
	if team == "player":
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake"):
			cam.shake(0.15, 0.1) # 진동 세기 0.15, 지속시간 0.1초 (기존 0.5/0.25에서 대폭 완화)
	
	# 쿨타임 시작
	cooldown_timer = _get_current_cooldown()
	
	var ball = cannonball_scene.instantiate()
	ball.position = muzzle.global_position
	ball.team = team
	get_tree().root.add_child.call_deferred(ball)
	
	# 데미지 계산 (캐싱된 속성 반영 + 함대 보너스)
	var base_dmg = 15.0 # 대포알 기준 데미지
	base_dmg *= _cached_dmg_mult * fleet_damage_mult
	ball.damage = base_dmg

	
	if ball.has_method("set_lifetime_multiplier"):
		ball.set_lifetime_multiplier(_cached_range_mult)
	
	# 예측 사격: 적의 예상 위치를 향해 발사
	var dist = global_position.distance_to(current_target.global_position)
	
	var time_to_hit = dist / 50.0 # 탄속 50.0으로 동기화 (기존 80.0 오류 수정)
	
	var enemy_speed = 3.5
	if "move_speed" in current_target: enemy_speed = current_target.move_speed
	var enemy_dir = - current_target.global_transform.basis.z
	var enemy_velocity = enemy_dir * enemy_speed
	
	var predicted_pos = current_target.global_position + enemy_velocity * time_to_hit
	ball.direction = (predicted_pos - muzzle.global_position).normalized()
	if ball.direction.is_zero_approx(): ball.direction = - global_transform.basis.z
	ball.target_node = current_target
	# look_at() 대신 Basis 직접 계산
	ball.basis = Basis.looking_at(ball.direction, Vector3.UP)

	# 머즐 연기 생성
	if muzzle_smoke_scene:
		var smoke = muzzle_smoke_scene.instantiate()
		smoke.position = muzzle.global_position
		# Basis.looking_at 안전 가드
		var smoke_dir = ball.direction if not ball.direction.is_zero_approx() else Vector3.FORWARD
		smoke.basis = Basis.looking_at(smoke_dir, Vector3.UP)
		get_tree().root.add_child.call_deferred(smoke)
		if smoke is GPUParticles3D:
			smoke.emitting = true
