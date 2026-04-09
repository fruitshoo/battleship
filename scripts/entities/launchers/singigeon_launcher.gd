extends Node3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const DEBUG_COMBAT_LOGS := false

## 신기전 발사기 (Singigeon Launcher)
## 로켓 화살을 전방으로 발사. 레벨에 따라 발수 증가.

@export var rocket_scene: PackedScene = preload("res://scenes/projectiles/singigeon_rocket.tscn")
@export var fire_cooldown: float = 4.0
@export var detection_range: float = 24.0
@export var shot_count: int = 1 # 레벨에 따라 2/3/4
@export var spread_angle: float = 0.0 # 레벨에 따라 점진적 확산각 증가
@export var burst_interval: float = 0.08
@export var retarget_radius: float = 16.0
@export var lock_on_delay: float = 0.12
@export var projectile_speed: float = 32.0
@export_range(0.05, 1.0) var target_scan_interval: float = 0.2
@export_range(1.0, 6.0) var target_tracking_scan_multiplier: float = 2.8
@export var team: String = "player" # "player" or "enemy"

var cooldown_timer: float = 0.0
var _target_scan_left: float = 0.0
var _cached_target: Variant = null
var _cached_upgrade_manager: Node = null
var _cached_cooldown_mult: float = 1.0
var _owner_ship: Node = null

func _enemy_team_tag() -> String:
	return "enemy" if team == "player" else "player"

func _is_enemy_ship(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var resolved = HitTargetResolver.resolve_team_tag(node)
	if not resolved.is_empty():
		return resolved == _enemy_team_tag()
	return node.is_in_group(_enemy_team_tag())

func _ready() -> void:
	_cached_upgrade_manager = get_node_or_null("/root/UpgradeManager")
	_owner_ship = _resolve_owner_ship()
	_target_scan_left = randf_range(0.0, target_scan_interval)
	_update_cached_stats()
	if is_instance_valid(_cached_upgrade_manager) and _cached_upgrade_manager.has_signal("upgrade_applied"):
		_cached_upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id == "singigeon":
		_update_cached_stats()

func _update_cached_stats() -> void:
	_cached_cooldown_mult = 1.0
	if not is_instance_valid(_cached_upgrade_manager):
		return
	if "current_levels" in _cached_upgrade_manager:
		var singigeon_lv = _cached_upgrade_manager.current_levels.get("singigeon", 0)
		_cached_cooldown_mult = maxf(0.5, 1.0 - 0.05 * singigeon_lv)

func _process(delta: float) -> void:
	if not _is_owner_combat_ready():
		_cached_target = null
		return
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return

	_target_scan_left -= delta
	if _target_scan_left <= 0.0 or not _is_target_valid(_cached_target):
		_cached_target = _find_nearest_enemy()
		_target_scan_left = _get_target_scan_interval(_is_target_valid(_cached_target))

	if _is_target_valid(_cached_target):
		var target_node := _cached_target as Node3D
		var current_cooldown = fire_cooldown * _cached_cooldown_mult
		fire(target_node, current_cooldown)

func _get_target_scan_interval(has_valid_target: bool) -> float:
	var base_interval: float = target_scan_interval
	if has_valid_target:
		base_interval *= target_tracking_scan_multiplier
	return base_interval + randf_range(0.0, 0.05)

func _resolve_owner_ship() -> Node:
	var node: Node = get_parent()
	while is_instance_valid(node):
		if node.is_in_group("ships"):
			return node
		if "is_sinking" in node and "is_dying" in node:
			return node
		node = node.get_parent()
	return null

func _is_owner_combat_ready() -> bool:
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	if not is_instance_valid(_owner_ship):
		return true
	if _owner_ship.get("is_dying") or _owner_ship.get("is_sinking") or _owner_ship.get("is_derelict"):
		return false
	var owner_hp = _owner_ship.get("hull_hp")
	if owner_hp != null and float(owner_hp) <= 0.0:
		return false
	return true

func _is_target_valid(target: Variant) -> bool:
	if not is_instance_valid(target):
		return false
	if not (target is Node3D):
		return false
	var target_node := target as Node3D
	if target_node.is_queued_for_deletion():
		return false
	if target_node == get_parent():
		return false
	if target_node.get("is_derelict") == true or target_node.get("is_sinking") == true or target_node.get("is_dying") == true:
		return false
	var target_hp = target_node.get("hull_hp")
	if target_hp != null and float(target_hp) <= 0.0:
		return false
	if not _is_enemy_ship(target_node):
		return false
	return global_position.distance_squared_to(target_node.global_position) <= detection_range * detection_range


func _find_nearest_enemy() -> Node3D:
	var enemies = EntityRegistry.get_ships_by_team(_enemy_team_tag())
	var nearest: Node3D = null
	var min_dist_sq: float = detection_range * detection_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		var enemy_ship := enemy as Node3D
		if not _is_enemy_ship(enemy_ship):
			continue
		
		# 자기 자신(부모 배)은 무시
		if get_parent() == enemy_ship: continue
		
		# 빈 배(폐선)는 타겟에서 제외
		if enemy_ship.get("is_derelict") == true: continue
		if enemy_ship.get("is_sinking") == true: continue
		if enemy_ship.get("is_dying") == true: continue
		var enemy_hp = enemy_ship.get("hull_hp")
		if enemy_hp != null and float(enemy_hp) <= 0.0:
			continue
		
		var dist_sq = global_position.distance_squared_to(enemy_ship.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			nearest = enemy_ship
	
	return nearest


func fire(target: Node3D, cooldown_override: float = -1.0) -> void:
	if not rocket_scene:
		return
	if not _is_owner_combat_ready():
		return
	cooldown_timer = cooldown_override if cooldown_override > 0 else fire_cooldown
	var muzzle = get_node_or_null("Muzzle")
	
	# MLRS 스타일: 연사 (Sequential Fire)
	for i in range(shot_count):
		if not _is_owner_combat_ready() or not is_inside_tree():
			break
		
		var current_target := target
		if not _is_target_valid(current_target):
			current_target = _find_nearest_enemy()
			if not _is_target_valid(current_target):
				break
			target = current_target
		
		var rocket = rocket_scene.instantiate()
		var side_offset = 0.3 if i % 2 == 0 else -0.3
		var spawn_base = muzzle.global_position if is_instance_valid(muzzle) else (global_position + Vector3(0, 0.5, 0))
		var spawn_pos = spawn_base + (basis.x * side_offset)
		
		# 발사체 초기값 전달
		var spread_t = 0.0
		if shot_count > 1:
			spread_t = lerpf(-spread_angle, spread_angle, float(i) / float(shot_count - 1))
		var jitter = randf_range(-1.0, 1.0)
		var predicted_pos = _predict_target_position(current_target, spawn_pos)
		predicted_pos = _sanitize_aim_point(predicted_pos, spawn_pos)
		var lead_dir = (predicted_pos - spawn_pos).normalized()
		var launch_dir = lead_dir.rotated(Vector3.UP, deg_to_rad(spread_t + jitter)).normalized()

		rocket.start_pos = spawn_pos
		rocket.target_pos = predicted_pos + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
		if "target_node" in rocket:
			rocket.target_node = current_target
		if "launch_direction" in rocket:
			rocket.launch_direction = launch_dir
		if "speed" in rocket:
			rocket.speed = projectile_speed
		if "burst_phase_duration" in rocket:
			rocket.burst_phase_duration = 0.10 + 0.02 * float(i)
		if "burst_turn_rate_deg" in rocket:
			rocket.burst_turn_rate_deg = 70.0
		if "terminal_turn_rate_deg" in rocket:
			rocket.terminal_turn_rate_deg = 250.0
		if "burst_wobble_deg" in rocket:
			rocket.burst_wobble_deg = 8.0 + 1.0 * float(i)
		if "terminal_wobble_deg" in rocket:
			rocket.terminal_wobble_deg = 1.5
		if "homing_duration" in rocket:
			rocket.homing_duration = maxf(float(rocket.homing_duration), 0.75)
		if "proximity_hit_radius" in rocket:
			rocket.proximity_hit_radius = maxf(float(rocket.proximity_hit_radius), 1.5)
		if "retarget_radius" in rocket:
			rocket.retarget_radius = retarget_radius
		if "lock_on_delay" in rocket:
			rocket.lock_on_delay = lock_on_delay + 0.02 * float(i)
		
		# 발사 주체 (팀/쏜 사람) 전달
		if "team" in rocket:
			rocket.team = self.team
		if "shooter" in rocket:
			rocket.shooter = _owner_ship if is_instance_valid(_owner_ship) else get_parent() # 발사기가 붙어있는 배
		
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
	spread_angle = 3.5 + float(level) * 0.7
	burst_interval = maxf(0.04, 0.10 - float(level) * 0.008)
	if DEBUG_COMBAT_LOGS:
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
	lead_pos.y = maxf(target_pos.y, from_pos.y)
	return lead_pos

func _sanitize_aim_point(pos: Vector3, from_pos: Vector3) -> Vector3:
	var safe = pos
	# 침몰/파도 영향으로 수면 아래 좌표를 받더라도 수면 위 조준을 유지
	var min_y = maxf(0.2, from_pos.y)
	safe.y = maxf(safe.y, min_y)
	return safe
