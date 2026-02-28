extends Node3D

## 함포 (Cannon)
## 범위 내 적을 탐지하고 자동으로 발사 (Area3D 대신 직접 탐지)

@export var cannonball_scene: PackedScene = preload("res://scenes/projectiles/cannonball.tscn")
@export var muzzle_flash_scene: PackedScene = preload("res://scenes/effects/muzzle_flash.tscn")
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
			if is_instance_valid(AudioManager):
				AudioManager.play_sfx("cannon_reload", global_position, randf_range(0.9, 1.1))
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
	var current_range = detection_range
	if is_instance_valid(UpgradeManager):
		var powder_lv = UpgradeManager.current_levels.get("black_powder", 0)
		current_range *= (1.0 + 0.15 * powder_lv)
	return current_range

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var current_range = _get_current_range()
	var min_dist_sq: float = current_range * current_range
	
	var enemy_group = "enemy" if team == "player" else "player"
	var enemies = get_tree().get_nodes_in_group(enemy_group)
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		var dist_sq = global_position.distance_squared_to(enemy.global_position)
		if dist_sq > min_dist_sq:
			continue
		
		if not _is_within_arc(enemy):
			continue
			
		if _is_ship_occupied_by_friendly(enemy):
			continue
				
		min_dist_sq = dist_sq
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
		if child.get("team") == "player" and child.get("current_state") != 4: # 4 = DEAD
			return true
	return false


func _get_current_cooldown() -> float:
	var um = UpgradeManager if is_instance_valid(UpgradeManager) else null
	var cd = fire_cooldown
	if um:
		var train_lv = um.current_levels.get("training", 0)
		cd *= (1.0 - 0.1 * train_lv)
	
	# 함대 보너스 적용 (곱연산)
	cd *= fleet_cooldown_mult
	return cd


func fire(target_enemy: Node3D) -> void:
	if not cannonball_scene: return
	
	# 발사 준비(도화선) 시작
	is_preparing = true
	prepare_timer = prepare_time
	current_target = target_enemy
	
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("cannon_fuse", global_position)


func _execute_fire() -> void:
	is_preparing = false
	
	# 최종 발사 직전 다시 한번 타겟 유효성 검증
	if not _is_target_valid(current_target):
		current_target = null
		return
		
	# 사운드 재생
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("cannon_fire", global_position, randf_range(0.9, 1.1))
		
	# 화면 흔들림 (Screen Shake) - 플레이어 대포일 경우만 (오래봐도 안 피로하게 아주 약하게)
	if team == "player":
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake"):
			cam.shake(0.15, 0.1) # 진동 세기 0.15, 지속시간 0.1초 (기존 0.5/0.25에서 대폭 완화)
	
	# 쿨타임 시작
	cooldown_timer = _get_current_cooldown()
	
	var ball = cannonball_scene.instantiate()
	get_tree().root.add_child(ball)
	
	ball.global_position = muzzle.global_position
	
	# 데미지 계산 (속성 반영)
	var base_dmg = 10.0 # 대포알 기본 데미지
	var range_mult = 1.0 # 사거리/수명 배율
	if is_instance_valid(UpgradeManager):
		var iron_lv = UpgradeManager.current_levels.get("iron_armor", 0)
		base_dmg *= (1.0 + 0.25 * iron_lv)
		
		var powder_lv = UpgradeManager.current_levels.get("black_powder", 0)
		range_mult = 1.0 + 0.15 * powder_lv
	
	# 함대 보너스 적용 (곱연산)
	base_dmg *= fleet_damage_mult
	ball.damage = base_dmg
	
	if ball.has_method("set_lifetime_multiplier"):
		ball.set_lifetime_multiplier(range_mult)
	
	# 예측 사격: 적의 예상 위치를 향해 발사
	var dist = global_position.distance_to(current_target.global_position)
	
	var time_to_hit = dist / 80.0
	
	var enemy_speed = 3.5
	if "move_speed" in current_target: enemy_speed = current_target.move_speed
	var enemy_dir = - current_target.global_transform.basis.z
	var enemy_velocity = enemy_dir * enemy_speed
	
	var predicted_pos = current_target.global_position + enemy_velocity * time_to_hit
	ball.direction = (predicted_pos - muzzle.global_position).normalized()
	ball.target_node = current_target
	ball.look_at(ball.global_position + ball.direction, Vector3.UP)

	# 머즐 플래시(발포 화염) 이펙트 생성 (ball.direction이 계산된 후 생성)
	if muzzle_flash_scene:
		var flash = muzzle_flash_scene.instantiate()
		get_tree().root.add_child(flash)
		# 위치는 즉시 적용
		flash.global_position = muzzle.global_position
		# 발사 방향(월드 좌표)을 파티클에 직접 주입 — 100% 안 뒤집힘 보장
		if flash.has_method("set_fire_direction"):
			flash.set_fire_direction(ball.direction)
			
		
	# 머즐 연기 생성
	if muzzle_smoke_scene:
		var smoke = muzzle_smoke_scene.instantiate()
		get_tree().root.add_child(smoke)
		smoke.global_position = muzzle.global_position
		smoke.look_at(smoke.global_position + ball.direction, Vector3.UP)
		if smoke is GPUParticles3D:
			smoke.emitting = true
