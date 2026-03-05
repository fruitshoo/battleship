extends Node3D

## 신기전 발사기 (Singigeon Launcher)
## 로켓 화살을 전방으로 발사. 레벨에 따라 발수 증가.

@export var rocket_scene: PackedScene = preload("res://scenes/projectiles/singigeon_rocket.tscn")
@export var fire_cooldown: float = 4.0
@export var detection_range: float = 30.0
@export var shot_count: int = 1 # 레벨에 따라 2/3/4
@export var spread_angle: float = 0.0 # 레벨에 따라 점진적 확산각 증가
@export var burst_interval: float = 0.08
@export var retarget_radius: float = 16.0
@export var lock_on_delay: float = 0.12
@export var projectile_speed: float = 32.0
@export var team: String = "player" # "player" or "enemy"

var cooldown_timer: float = 0.0


func _process(delta: float) -> void:
	var um = get_node_or_null("/root/UpgradeManager")
	var current_cooldown = fire_cooldown
	if is_instance_valid(um) and "current_levels" in um:
		var singigeon_lv = um.current_levels.get("singigeon", 0)
		current_cooldown = fire_cooldown * maxf(0.5, 1.0 - 0.05 * singigeon_lv)
		
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	# 가장 가까운 적 찾기
	var nearest = _find_nearest_enemy()
	if nearest:
		fire(nearest, current_cooldown)


func _find_nearest_enemy() -> Node3D:
	var enemy_group = "enemy" if team == "player" else "player"
	var enemies = get_tree().get_nodes_in_group(enemy_group)
	var nearest: Node3D = null
	var min_dist: float = detection_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		
		# 자기 자신(부모 배)은 무시
		if get_parent() == enemy: continue
		
		# 빈 배(폐선)는 타겟에서 제외
		if enemy.get("is_derelict") == true: continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
	
	return nearest


func fire(target: Node3D, cooldown_override: float = -1.0) -> void:
	if not rocket_scene: return
	cooldown_timer = cooldown_override if cooldown_override > 0 else fire_cooldown
	var muzzle = get_node_or_null("Muzzle")
	var base_forward = -global_transform.basis.z
	
	# MLRS 스타일: 연사 (Sequential Fire)
	for i in range(shot_count):
		if not is_instance_valid(target): break
		
		var rocket = rocket_scene.instantiate()
		var side_offset = 0.3 if i % 2 == 0 else -0.3
		var spawn_base = muzzle.global_position if is_instance_valid(muzzle) else (global_position + Vector3(0, 0.5, 0))
		var spawn_pos = spawn_base + (basis.x * side_offset)
		
		# 발사체 초기값 전달
		var spread_t = 0.0
		if shot_count > 1:
			spread_t = lerpf(-spread_angle, spread_angle, float(i) / float(shot_count - 1))
		var jitter = randf_range(-1.0, 1.0)
		var predicted_pos = _predict_target_position(target, spawn_pos)
		var lead_dir = (predicted_pos - spawn_pos).normalized()
		var launch_dir = lead_dir.rotated(Vector3.UP, deg_to_rad(spread_t + jitter)).normalized()

		rocket.start_pos = spawn_pos
		rocket.target_pos = predicted_pos + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
		if "target_node" in rocket:
			rocket.target_node = target
		if "launch_direction" in rocket:
			rocket.launch_direction = launch_dir
		if "speed" in rocket:
			rocket.speed = projectile_speed
		if "retarget_radius" in rocket:
			rocket.retarget_radius = retarget_radius
		if "lock_on_delay" in rocket:
			rocket.lock_on_delay = lock_on_delay + 0.02 * float(i)
		
		# 발사 주체 (팀/쏜 사람) 전달
		if "team" in rocket:
			rocket.team = self.team
		if "shooter" in rocket:
			rocket.shooter = get_parent() # 발사기가 붙어있는 배
		
		# 위치 미리 설정 (트리 진입 전)
		rocket.position = spawn_pos
		get_tree().root.add_child.call_deferred(rocket)
		
		# 발사 사운드
		var audio_manager = get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("rocket_launch", global_position)
		
		# 연사 간격
		await get_tree().create_timer(burst_interval).timeout


## 업그레이드 시 호출
func upgrade_to_level(level: int) -> void:
	# 발키리 스타일: 짧은 간격 다연장 + 확산 후 유도
	if level <= 2:
		shot_count = 2
	elif level <= 4:
		shot_count = 3
	else:
		shot_count = 4
	spread_angle = 6.0 + float(level) * 1.2
	burst_interval = maxf(0.04, 0.10 - float(level) * 0.008)
	print("[Launcher] 신기전 Lv.%d (%d발, ±%.0f°)" % [level, shot_count, spread_angle])


func _predict_target_position(target: Node3D, from_pos: Vector3) -> Vector3:
	if not is_instance_valid(target):
		return from_pos + (-global_transform.basis.z) * 10.0

	var target_pos = target.global_position
	var to_target = target_pos - from_pos
	var dist = maxf(0.1, to_target.length())
	var t_flight = dist / maxf(1.0, projectile_speed)

	var target_speed = 0.0
	if "current_speed" in target:
		target_speed = float(target.current_speed)
	elif "move_speed" in target:
		target_speed = float(target.move_speed)

	var target_fwd = -target.global_transform.basis.z
	target_fwd.y = 0.0
	if target_fwd.length_squared() > 0.001:
		target_fwd = target_fwd.normalized()

	# 완전 선행 예측은 빗나감이 커서 70%만 반영
	var lead_pos = target_pos + target_fwd * target_speed * t_flight * 0.7
	lead_pos.y = target_pos.y
	return lead_pos
