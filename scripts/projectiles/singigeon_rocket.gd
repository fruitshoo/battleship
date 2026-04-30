extends Area3D

## 신기전 로켓 (Singigeon Rocket)
## 발키리 스타일: 지향사격 기반 다연장 로켓 (짧은 미세 보정만 적용).

@export var speed: float = 32.0
@export var turn_rate_deg: float = 120.0
@export var burst_phase_duration: float = 0.12
@export var burst_turn_rate_deg: float = 70.0
@export var terminal_turn_rate_deg: float = 240.0
@export var burst_wobble_deg: float = 9.0
@export var terminal_wobble_deg: float = 2.0
@export var wobble_frequency: float = 11.0
@export var damage: float = 2.5 # 함선 데미지 하향 (5.0 -> 2.5)
@export var personnel_damage_mult: float = 5.0 # 병사 데미지 배수 하향 (25 -> 5)
@export var lifetime: float = 3.0
@export var lock_on_delay: float = 0.12
@export var retarget_radius: float = 16.0
@export var proximity_hit_radius: float = 1.2
@export var homing_duration: float = 0.35
@export var max_homing_distance: float = 14.0
@export var allow_retarget: bool = false
@export var prefer_personnel_targets: bool = false
@export_range(0.03, 0.3) var retarget_scan_interval: float = 0.08
@export_range(0.01, 0.12) var collision_check_interval: float = 0.03
@export_range(0.25, 2.0) var collision_check_distance: float = 0.9

var team: String = "player"
var shooter: Node3D = null # 이 로켓을 쏜 선박 (오사 방지용)
var target_node: Node3D = null
var launch_direction: Vector3 = Vector3.ZERO

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var has_exploded: bool = false
var _velocity: Vector3 = Vector3.ZERO
var _life_left: float = 0.0
var _lock_on_left: float = 0.0
var _homing_left: float = 0.0
var _retarget_scan_left: float = 0.0
var _target_group: String = "enemy"
var _target_collision_mask: int = 4
var _cached_upgrade_manager: Node = null
var _age: float = 0.0
var _wobble_seed: float = 0.0
var _collision_check_left: float = 0.0
var _last_collision_check_pos: Vector3 = Vector3.ZERO
var _last_faced_dir: Vector3 = Vector3.ZERO

func _ready() -> void:
	pool_reset()


func _enter_tree() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	EntityRegistry.register_projectile(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_projectile(self)

func pool_capacity() -> int:
	return 100

func pool_reset() -> void:
	global_position = start_pos
	monitoring = false
	monitorable = false
	has_exploded = false
	_life_left = lifetime
	_lock_on_left = maxf(0.0, lock_on_delay)
	_homing_left = maxf(0.0, homing_duration)
	_age = 0.0
	_wobble_seed = randf() * TAU
	_configure_team_filters()
	_cached_upgrade_manager = get_node_or_null("/root/UpgradeManager")

	var init_dir = launch_direction
	if init_dir.length_squared() < 0.001:
		if _is_valid_target(target_node):
			init_dir = NodeContractHelper.get_projectile_aim_point(target_node, 0.65) - global_position
		else:
			target_node = null
		if init_dir.length_squared() < 0.001 and start_pos.distance_squared_to(target_pos) > 0.01:
			init_dir = target_pos - start_pos
		if init_dir.length_squared() < 0.001:
			init_dir = -global_transform.basis.z
	if init_dir.length_squared() < 0.001:
		init_dir = Vector3.FORWARD
	_velocity = init_dir.normalized() * speed
	_collision_check_left = 0.0
	_last_collision_check_pos = global_position
	_face_velocity(true)
	var trail = get_node_or_null("RocketTrail") as GPUParticles3D
	if is_instance_valid(trail):
		var enable_trail = VfxBudget.allow_spawn(get_tree(), "rocket_trail", global_position, 8, 75.0)
		if VfxBudget.get_continuous_effect_scale() <= 0.42:
			enable_trail = false
		trail.visible = enable_trail
		trail.emitting = enable_trail

func restart_flight() -> void:
	pool_reset()
	
	# 발사 사운드 재생 (01, 02, 03 무작위 선택)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		var rand = randf()
		var sfx_name = "rocket_launch_01"
		if rand > 0.66: sfx_name = "rocket_launch_03"
		elif rand > 0.33: sfx_name = "rocket_launch_02"
		
		audio_manager.play_sfx(sfx_name, global_position, randf_range(0.9, 1.1))
	
func _physics_process(delta: float) -> void:
	if has_exploded:
		return

	_age += delta
	_life_left -= delta
	if _life_left <= 0.0:
		_finish_flight()
		ScenePool.release(self)
		return

	if _lock_on_left > 0.0:
		_lock_on_left -= delta
	else:
		_homing_left = maxf(0.0, _homing_left - delta)
	if allow_retarget and _retarget_scan_left > 0.0:
		_retarget_scan_left -= delta

	var current_dir = _velocity.normalized()
	var desired_dir = current_dir
	var in_burst_phase = _age < burst_phase_duration
	var active_turn_rate = turn_rate_deg
	if in_burst_phase:
		active_turn_rate = burst_turn_rate_deg
		var base_dir = launch_direction
		if base_dir.length_squared() < 0.0001:
			base_dir = current_dir
		desired_dir = _apply_wobble(base_dir.normalized(), burst_wobble_deg, _age)
	elif _lock_on_left <= 0.0 and _homing_left > 0.0:
		active_turn_rate = terminal_turn_rate_deg
		var homing_target = _resolve_homing_target()
		if is_instance_valid(homing_target):
			var aim_point = NodeContractHelper.get_projectile_aim_point(homing_target, 0.65)
			var to_target = aim_point - global_position
			if to_target.length_squared() > 0.0001 and to_target.length_squared() <= max_homing_distance * max_homing_distance:
				desired_dir = _apply_wobble(to_target.normalized(), terminal_wobble_deg, _age)

	var turn_weight = clampf(deg_to_rad(active_turn_rate) * delta, 0.0, 1.0)
	current_dir = current_dir.slerp(desired_dir, turn_weight).normalized()
	_velocity = current_dir * speed

	var prev_pos = global_position
	global_position += _velocity * delta
	_face_velocity()

	if _should_run_collision_check(prev_pos, delta):
		var hit_node = _raycast_hit(_last_collision_check_pos, global_position)
		_last_collision_check_pos = global_position
		_collision_check_left = collision_check_interval
		if hit_node:
			_on_hit(hit_node)
			return

	if _is_valid_target(target_node) and _lock_on_left <= 0.0:
		var target_aim_point: Vector3 = NodeContractHelper.get_projectile_aim_point(target_node, 0.65)
		if global_position.distance_squared_to(target_aim_point) <= proximity_hit_radius * proximity_hit_radius:
			_on_hit(target_node)

func _apply_wobble(dir: Vector3, wobble_deg: float, age: float) -> Vector3:
	if wobble_deg <= 0.01:
		return dir
	var wobble = sin(age * wobble_frequency + _wobble_seed) * deg_to_rad(wobble_deg)
	var wobbled = dir.rotated(Vector3.UP, wobble)
	if wobbled.length_squared() <= 0.0001:
		return dir
	return wobbled.normalized()

func _face_velocity(force: bool = false) -> void:
	if _velocity.length_squared() <= 0.0001:
		return
	var dir = _velocity.normalized()
	if not force and _last_faced_dir.length_squared() > 0.0001 and dir.dot(_last_faced_dir) >= 0.9992:
		return
	_last_faced_dir = dir
	var look_target = global_position + _velocity
	var up_vec = Vector3.UP
	if absf(dir.y) > 0.999:
		up_vec = Vector3.RIGHT
	look_at(look_target, up_vec)

func _should_run_collision_check(prev_pos: Vector3, delta: float) -> bool:
	_collision_check_left -= delta
	if _collision_check_left <= 0.0:
		return true
	if _last_collision_check_pos.distance_squared_to(global_position) >= collision_check_distance * collision_check_distance:
		return true
	# 급선회/초기 가속 구간에서는 충돌 누락을 줄이기 위해 한 번 더 보수적으로 체크한다.
	if prev_pos.distance_squared_to(global_position) >= 1.44:
		return true
	return false

func _resolve_homing_target() -> Node3D:
	if not is_instance_valid(target_node):
		target_node = null
	if _is_valid_target(target_node):
		return target_node
	if not allow_retarget:
		return null
	if _retarget_scan_left > 0.0:
		return null
	_retarget_scan_left = retarget_scan_interval

	var best_target: Node3D = null
	var best_dist_sq: float = retarget_radius * retarget_radius

	if prefer_personnel_targets:
		for candidate in EntityRegistry.get_soldiers():
			if not (candidate is Node3D):
				continue
			var soldier := candidate as Node3D
			if not _is_valid_soldier_target(soldier):
				continue
			var dist_sq: float = global_position.distance_squared_to(NodeContractHelper.get_projectile_aim_point(soldier, 0.5))
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_target = soldier
		if is_instance_valid(best_target):
			target_node = best_target
			return best_target

	for candidate in EntityRegistry.get_ships():
		if not (candidate is Node3D):
			continue
		var ship := candidate as Node3D
		if not _is_valid_ship_target(ship):
			continue

		var dist_sq: float = global_position.distance_squared_to(NodeContractHelper.get_projectile_aim_point(ship, 0.65))
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_target = ship

	target_node = best_target
	return best_target

func _is_valid_ship_target(ship: Variant) -> bool:
	if not is_instance_valid(ship):
		return false
	if not (ship is Node3D):
		return false
	var ship_3d := ship as Node3D
	if ship_3d.is_queued_for_deletion():
		return false
	if not ship_3d.is_inside_tree():
		return false
	if shooter and (ship_3d == shooter or ship_3d.get_parent() == shooter):
		return false
	if ship_3d.has_method("is_derelict_ship") and ship_3d.is_derelict_ship():
		return false
	if NodeContractHelper.is_sinking_or_dying(ship_3d):
		return false

	var team_tag = NodeContractHelper.get_team_tag(ship_3d)
	if team_tag == _target_group:
		return true
	if ship_3d.is_in_group(_target_group):
		return true
	return HitTargetResolver.resolve_team_tag(ship_3d) == _target_group

func _is_valid_soldier_target(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	if not (node is CharacterBody3D):
		return false
	if node.is_queued_for_deletion():
		return false
	if not (node as Node3D).is_inside_tree():
		return false
	if NodeContractHelper.get_team_tag(node) != _target_group:
		return false
	if NodeContractHelper.get_current_state_value(node) == 4:
		return false
	return true

func _is_valid_target(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	return _is_valid_ship_target(node) or _is_valid_soldier_target(node)

func _raycast_hit(from_pos: Vector3, to_pos: Vector3) -> Node:
	var world = get_world_3d()
	if not world:
		return null
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = _target_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [self]
	var result = world.direct_space_state.intersect_ray(query)
	if DebugDrawBridge.projectile_debug_enabled:
		if result.is_empty():
			DebugDrawBridge.draw_line(from_pos, to_pos, Color(0.35, 1.0, 0.65, 0.32), 0.08, 0.022)
		else:
			var hit_pos: Vector3 = result.get("position", to_pos)
			DebugDrawBridge.draw_hit_ray(from_pos, to_pos, hit_pos, true, _debug_hit_label(result.get("collider")), 1.2)
	if result.is_empty():
		return null
	return result.get("collider")

func _on_hit(target: Variant) -> void:
	if has_exploded: return
	if not is_instance_valid(target):
		return

	var active_target_soldier: Variant = target_node
	if prefer_personnel_targets and _is_valid_soldier_target(active_target_soldier):
		var struck_ship: Node = HitTargetResolver.resolve_ship_from_node(target)
		var target_ship_variant: Variant = NodeContractHelper.get_owned_ship_node(active_target_soldier)
		if struck_ship != null and target_ship_variant is Node and struck_ship == target_ship_variant and not _is_valid_soldier_target(target):
			return

	var hit_obj: Variant = target
	if not _is_valid_target(hit_obj):
		hit_obj = HitTargetResolver.resolve_ship_from_node(target)
	if not is_instance_valid(hit_obj) or not _is_valid_target(hit_obj):
		return

	var primary_target: Node3D = hit_obj as Node3D
	_draw_rocket_impact_debug(primary_target)
	_finish_flight(primary_target)
	ScenePool.release(self)

func _apply_damage(target_node: Variant, scale: float = 1.0) -> void:
	if not is_instance_valid(target_node): return

	# 데미지 보정 (블랙 파우더 업그레이드 등)
	var dmg_mult = 1.0
	var upgrade_manager = _cached_upgrade_manager
	if is_instance_valid(upgrade_manager) and "current_levels" in upgrade_manager:
		var singigeon_lv = upgrade_manager.current_levels.get("singigeon", 0)
		dmg_mult += (0.15 * singigeon_lv) # 레벨당 데미지 15% 증가

	if target_node.has_method("take_damage"):
		var final_damage = damage * dmg_mult * scale
		if target_node is CharacterBody3D or target_node.is_in_group("soldiers"):
			final_damage *= personnel_damage_mult

		var source_id = "singigeon" if team == "player" else ""
		target_node.take_damage(final_damage, global_position, source_id)
	elif target_node.has_method("die"):
		target_node.die()

func _finish_flight(primary_target: Node3D = null) -> void:
	if has_exploded:
		return
	has_exploded = true

	if is_instance_valid(primary_target):
		_apply_damage(primary_target, 1.0)

	# 트레일 중단
	var trail = get_node_or_null("RocketTrail")
	if trail:
		trail.emitting = false
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(primary_target) and is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("impact_wood", global_position, randf_range(0.7, 0.9))


func _draw_rocket_impact_debug(primary_target: Node3D) -> void:
	if not DebugDrawBridge.projectile_debug_enabled:
		return
	var label := "rocket"
	if is_instance_valid(primary_target):
		label = "rocket %s" % primary_target.name
	DebugDrawBridge.draw_marker(global_position, Color(1.0, 0.22, 0.08, 0.98), label, 1.6, 0.32, 0.45)


func _debug_hit_label(target: Variant) -> String:
	if target is Node:
		return (target as Node).name
	return "hit"

func _configure_team_filters() -> void:
	if team == "player":
		_target_group = "enemy"
		_target_collision_mask = 4
	else:
		_target_group = "player"
		_target_collision_mask = 2
