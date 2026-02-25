extends Node3D

## 함포 (Cannon)
## 범위 내 적을 탐지하고 자동으로 발사 (Area3D 대신 직접 탐지)

@export var cannonball_scene: PackedScene = preload("res://scenes/effects/cannonball.tscn")
@export var muzzle_flash_scene: PackedScene = preload("res://scenes/effects/muzzle_flash.tscn")
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
	
	# 직접 적 탐지 (Area3D 사용 안 함 — 동적 인스턴스에서도 확실히 작동)
	var nearest_enemy: Node3D = null
	var min_dist: float = detection_range
	
	var enemy_group = "enemy" if team == "player" else "player"
	var enemies = get_tree().get_nodes_in_group(enemy_group)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist > detection_range:
			continue
		
		# 대포가 바라보는 방향 기준 각도 체크
		var to_enemy = (enemy.global_position - global_position).normalized()
		var forward = - global_transform.basis.z
		var dot = forward.dot(to_enemy)
		var angle = rad_to_deg(acos(clamp(dot, -1.0, 1.0)))
		
		if angle < detection_arc and dist < min_dist:
			min_dist = dist
			nearest_enemy = enemy
	
	if nearest_enemy:
		fire(nearest_enemy)


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
	var base_dmg = 25.0 # 대포알 기본 데미지 상향
	if is_instance_valid(UpgradeManager):
		var iron_lv = UpgradeManager.current_levels.get("iron_armor", 0)
		base_dmg *= (1.0 + 0.25 * iron_lv)
	ball.damage = base_dmg
	
	# 예측 사격: 적의 예상 위치를 향해 발사
	var dist = global_position.distance_to(current_target.global_position)
	
	# 거리 기반 자동 포도탄(Grapeshot) 전환 (15m 이내)
	if dist <= 15.0:
		ball.is_grapeshot = true
	
	var time_to_hit = dist / 100.0
	
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
