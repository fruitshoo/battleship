extends Node3D

## 함포 (Cannon)
## 범위 내 적을 탐지하고 자동으로 발사 (Area3D 대신 직접 탐지)

@export var cannonball_scene: PackedScene = preload("res://scenes/projectiles/cannonball.tscn")
@export var muzzle_flash_scene: PackedScene = preload("res://scenes/effects/muzzle_flash.tscn")
@export var shockwave_scene: PackedScene = preload("res://scenes/effects/shockwave.tscn")
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


func _process(delta: float) -> void:
	if is_preparing:
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

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var min_dist_sq: float = detection_range * detection_range
	
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
	if not is_instance_valid(target): return false
	if global_position.distance_squared_to(target.global_position) > detection_range * detection_range: return false
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
	
	if not is_instance_valid(current_target) or current_target.get("is_dead") == true:
		return # 타겟이 그동안 죽거나 사라졌다면 발사 취소
		
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
	if is_instance_valid(UpgradeManager):
		var iron_lv = UpgradeManager.current_levels.get("iron_armor", 0)
		base_dmg *= (1.0 + 0.25 * iron_lv)
	ball.damage = base_dmg
	
	# 예측 사격: 적의 예상 위치를 향해 발사
	var dist = global_position.distance_to(current_target.global_position)
	
	# 거리 기반 자동 포도탄(Grapeshot) 전환 (제거됨 - 일반탄 고정)
	
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
			
	# 머즐 쇼크웨이브 생성
	if shockwave_scene:
		var wave = shockwave_scene.instantiate()
		get_tree().root.add_child(wave)
		wave.global_position = muzzle.global_position
		# 총구 방향으로 비스듬히 눕히기
		wave.look_at(wave.global_position + ball.direction, Vector3.UP)
		
	# 머즐 연기 생성
	if muzzle_smoke_scene:
		var smoke = muzzle_smoke_scene.instantiate()
		get_tree().root.add_child(smoke)
		smoke.global_position = muzzle.global_position
		smoke.look_at(smoke.global_position + ball.direction, Vector3.UP)
		if smoke is GPUParticles3D:
			smoke.emitting = true
