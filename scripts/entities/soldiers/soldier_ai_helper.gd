extends RefCounted
const SoldierCombatHelper = preload("res://scripts/entities/soldiers/soldier_combat_helper.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const WANDER_TURN_SPEED := 7.0
const MOVE_TURN_SPEED := 10.0
const ATTACK_TURN_SPEED := 16.0
const TURN_TARGET_DISTANCE_EPSILON_SQ := 0.09
const TURN_ANGLE_DEADZONE := PI / 60.0
const ATTACK_VALIDATION_NEAR_INTERVAL := 0.12
const ATTACK_VALIDATION_CROSS_SHIP_INTERVAL := 0.16
const ATTACK_VALIDATION_FAR_LOD_INTERVAL := 0.22
const ATTACK_VALIDATION_JITTER := 0.05
const OWNED_SHIP_HOSTILE_SWITCH_RATIO := 0.58

static func state_idle(soldier, delta: float, run_heavy_logic: bool) -> void:
	if soldier.has_method("_is_far_lod_sleep_candidate") and soldier._is_far_lod_sleep_candidate():
		soldier.velocity = Vector3.ZERO
		if soldier.wander_timer > 0.0:
			soldier.wander_timer -= delta
		else:
			soldier.wander_timer = randf_range(1.5, 3.0)
		return
	if _should_run_routine_support_step(soldier, delta, run_heavy_logic):
		var support_profile_start := PhysicsFrameProfiler.begin()
		if soldier.has_method("_try_assist_incapacitated_ally") and soldier._try_assist_incapacitated_ally(delta, 0.72, WANDER_TURN_SPEED):
			PhysicsFrameProfiler.end("soldier_idle_support", support_profile_start)
			return
		if _try_move_to_active_ship_duty_target(soldier, 0.75, delta, WANDER_TURN_SPEED):
			PhysicsFrameProfiler.end("soldier_idle_support", support_profile_start)
			return
		PhysicsFrameProfiler.end("soldier_idle_support", support_profile_start)
	if run_heavy_logic:
		var heavy_profile_start := PhysicsFrameProfiler.begin()
		if _try_priority_ship_duty_before_enemy(soldier, 0.78, delta, WANDER_TURN_SPEED):
			PhysicsFrameProfiler.end("soldier_idle_heavy", heavy_profile_start)
			return
		var enemy = soldier.find_nearest_enemy()
		if enemy:
			if soldier.is_stationary:
				soldier.current_target = enemy
				PhysicsFrameProfiler.end("soldier_idle_heavy", heavy_profile_start)
				return

			soldier.current_target = enemy
			soldier._change_state(soldier.State.MOVE)
			PhysicsFrameProfiler.end("soldier_idle_heavy", heavy_profile_start)
			return

		if soldier.has_method("_find_cross_ship_muster_target"):
			var muster_target: Vector3 = soldier._find_cross_ship_muster_target()
			if muster_target != Vector3.INF:
				_move_toward_point(soldier, muster_target, 0.9, delta, WANDER_TURN_SPEED)
				PhysicsFrameProfiler.end("soldier_idle_heavy", heavy_profile_start)
				return

		if soldier.has_method("_find_ship_duty_target"):
			var duty_target: Vector3 = soldier._find_ship_duty_target()
			if duty_target != Vector3.INF:
				_move_toward_point(soldier, duty_target, 0.75, delta, WANDER_TURN_SPEED)
				PhysicsFrameProfiler.end("soldier_idle_heavy", heavy_profile_start)
				return
		PhysicsFrameProfiler.end("soldier_idle_heavy", heavy_profile_start)
	soldier.velocity = Vector3.ZERO
	if soldier.wander_timer > 0:
		soldier.wander_timer -= delta
	else:
		start_wander(soldier)

static func state_wander(soldier, delta_or_run_heavy_logic: Variant = 0.016, run_heavy_logic: bool = false) -> void:
	var delta := 0.016
	if typeof(delta_or_run_heavy_logic) == TYPE_BOOL:
		run_heavy_logic = bool(delta_or_run_heavy_logic)
	else:
		delta = float(delta_or_run_heavy_logic)

	if soldier.has_method("_is_far_lod_sleep_candidate") and soldier._is_far_lod_sleep_candidate():
		soldier.velocity = Vector3.ZERO
		soldier.wander_timer = randf_range(1.5, 3.0)
		soldier._change_state(soldier.State.IDLE)
		return
	if _should_run_routine_support_step(soldier, delta, run_heavy_logic):
		var support_profile_start := PhysicsFrameProfiler.begin()
		if soldier.has_method("_try_assist_incapacitated_ally") and soldier._try_assist_incapacitated_ally(delta, 0.68, WANDER_TURN_SPEED):
			PhysicsFrameProfiler.end("soldier_wander_support", support_profile_start)
			return

		if _try_move_to_active_ship_duty_target(soldier, 0.7, delta, WANDER_TURN_SPEED):
			PhysicsFrameProfiler.end("soldier_wander_support", support_profile_start)
			return
		PhysicsFrameProfiler.end("soldier_wander_support", support_profile_start)

	if run_heavy_logic:
		var heavy_profile_start := PhysicsFrameProfiler.begin()
		if _try_priority_ship_duty_before_enemy(soldier, 0.74, delta, WANDER_TURN_SPEED):
			PhysicsFrameProfiler.end("soldier_wander_heavy", heavy_profile_start)
			return

		var enemy = soldier.find_nearest_enemy()
		if enemy:
			if soldier.is_stationary:
				soldier.current_target = enemy
				soldier._change_state(soldier.State.IDLE)
				PhysicsFrameProfiler.end("soldier_wander_heavy", heavy_profile_start)
				return

			var dist = soldier.global_position.distance_to(enemy.global_position)
			if dist < 8.0:
				soldier.current_target = enemy
				soldier._change_state(soldier.State.MOVE)
				PhysicsFrameProfiler.end("soldier_wander_heavy", heavy_profile_start)
				return

		if soldier.has_method("_find_cross_ship_muster_target"):
			var muster_target: Vector3 = soldier._find_cross_ship_muster_target()
			if muster_target != Vector3.INF:
				_move_toward_point(soldier, muster_target, 0.85, delta, WANDER_TURN_SPEED)
				PhysicsFrameProfiler.end("soldier_wander_heavy", heavy_profile_start)
				return

		if soldier.has_method("_find_ship_duty_target"):
			var duty_target: Vector3 = soldier._find_ship_duty_target()
			if duty_target != Vector3.INF:
				_move_toward_point(soldier, duty_target, 0.7, delta, WANDER_TURN_SPEED)
				PhysicsFrameProfiler.end("soldier_wander_heavy", heavy_profile_start)
				return
		PhysicsFrameProfiler.end("soldier_wander_heavy", heavy_profile_start)
	if not is_instance_valid(soldier.owned_ship):
		soldier._change_state(soldier.State.IDLE)
		return
	if "_routine_wander_step_timer" in soldier and soldier.has_method("_get_routine_wander_step_interval"):
		var interval: float = float(soldier.call("_get_routine_wander_step_interval"))
		if interval > 0.0:
			soldier._routine_wander_step_timer -= delta
			if soldier._routine_wander_step_timer > 0.0:
				soldier.velocity = Vector3.ZERO
				return
			soldier._routine_wander_step_timer = interval + randf_range(0.0, interval * 0.18)

	var move_profile_start := PhysicsFrameProfiler.begin()
	var current_local: Vector3 = soldier.owned_ship.to_local(soldier.global_position)
	var target_local: Vector3 = soldier.wander_target_local
	var wander_diff := Vector2(current_local.x - target_local.x, current_local.z - target_local.z)
	var wander_dist = wander_diff.length()

	if wander_dist < 0.2:
		soldier.velocity = Vector3.ZERO
		soldier.wander_timer = randf_range(1.0, 3.0)
		soldier._change_state(soldier.State.IDLE)
		PhysicsFrameProfiler.end("soldier_wander_move", move_profile_start)
		return

	_move_toward_owned_ship_local_point(soldier, target_local, 0.5, delta, WANDER_TURN_SPEED)
	PhysicsFrameProfiler.end("soldier_wander_move", move_profile_start)

static func _try_priority_ship_duty_before_enemy(soldier, speed_scale: float, delta: float, turn_speed: float) -> bool:
	if not soldier.has_method("_find_ship_duty_target"):
		return false
	var owned_ship_value: Variant = soldier.get("owned_ship")
	if not is_instance_valid(owned_ship_value):
		return false
	var owned_ship := owned_ship_value as Node
	var gunnery_ratio: float = float(owned_ship.get("gunnery_crew_ratio")) if owned_ship.get("gunnery_crew_ratio") != null else 0.0
	if gunnery_ratio < 0.45:
		return false
	var enemy = soldier.find_nearest_enemy()
	if is_instance_valid(enemy):
		var attack_range: float = soldier.current_weapon.attack_range if soldier.current_weapon and "attack_range" in soldier.current_weapon else 1.2
		var dist_xz := Vector2(
			soldier.global_position.x - enemy.global_position.x,
			soldier.global_position.z - enemy.global_position.z
		).length()
		if dist_xz <= attack_range:
			return false
	var duty_target: Vector3 = soldier._find_ship_duty_target()
	if duty_target == Vector3.INF:
		return false
	_move_toward_point(soldier, duty_target, speed_scale, delta, turn_speed)
	return true


static func _should_run_routine_support_step(soldier, delta: float, run_heavy_logic: bool) -> bool:
	if soldier.has_method("_should_run_routine_support_step"):
		return soldier.call("_should_run_routine_support_step", delta, run_heavy_logic) == true
	return true


static func start_wander(soldier) -> void:
	if not is_instance_valid(soldier.owned_ship):
		return

	var half_ext = soldier._get_ship_deck_half_extents(soldier.owned_ship)
	var random_x = randf_range(-half_ext.x, half_ext.x)
	var random_z = randf_range(-half_ext.y, half_ext.y)

	soldier.wander_target_local = Vector3(random_x, 0.0, random_z)
	soldier._change_state(soldier.State.WANDER)
static func state_move(soldier, delta: float = 0.016) -> void:
	if soldier.is_stationary:
		soldier._change_state(soldier.State.IDLE)
		return

	if _retarget_owned_ship_hostile(soldier):
		return

	if not is_instance_valid(soldier.current_target):
		_clear_target_and_try_muster_or_idle(soldier, 1.0, delta, MOVE_TURN_SPEED)
		return

	if SoldierStateHelper.is_dead_soldier(soldier.current_target):
		_clear_target_and_try_muster_or_idle(soldier, 1.0, delta, MOVE_TURN_SPEED)
		return

	var target_node := soldier.current_target as Node3D
	if not is_instance_valid(target_node) or not target_node.is_inside_tree():
		_clear_target_and_try_muster_or_idle(soldier, 1.0, delta, MOVE_TURN_SPEED)
		return

	var target_ship = soldier.current_target.get_owned_ship_node() if soldier.current_target.has_method("get_owned_ship_node") else null
	if is_instance_valid(target_ship) and target_ship != soldier.owned_ship:
		if target_ship.has_method("is_sinking_or_dying") and target_ship.is_sinking_or_dying():
			_clear_target_and_try_muster_or_idle(soldier, 1.0, delta, MOVE_TURN_SPEED)
			return

	var pos_self_2d = Vector2(soldier.global_position.x, soldier.global_position.z)
	var pos_target_2d = Vector2(soldier.current_target.global_position.x, soldier.current_target.global_position.z)
	var distance_xz = pos_self_2d.distance_to(pos_target_2d)

	if is_instance_valid(soldier.owned_ship) and target_ship != soldier.owned_ship:
		if soldier.has_method("_should_hold_defensive_deck_position_against") and soldier._should_hold_defensive_deck_position_against(target_ship):
			soldier.current_target = null
			soldier._change_state(soldier.State.IDLE)
			return
		if not soldier._is_ship_pair_in_melee_range(target_ship):
			soldier._change_state(soldier.State.IDLE)
			return
		if soldier.has_method("_is_in_cross_ship_contact_zone") and soldier._is_in_cross_ship_contact_zone(target_ship) == false:
			if soldier.has_method("_get_stable_cross_ship_contact_point_global") or soldier.has_method("_get_cross_ship_contact_point_global"):
				var muster_target: Vector3 = Vector3.INF
				if soldier.has_method("_get_stable_cross_ship_contact_point_global"):
					muster_target = soldier._get_stable_cross_ship_contact_point_global(target_ship)
				else:
					muster_target = soldier._get_cross_ship_contact_point_global(target_ship)
				if muster_target != Vector3.INF:
					_move_toward_point(soldier, muster_target, 1.0, delta, MOVE_TURN_SPEED)
					return
		var engage_distance: float = soldier._get_cross_ship_engage_max_distance(target_ship)
		if distance_xz > engage_distance:
			soldier._change_state(soldier.State.IDLE)
			return

	if distance_xz > soldier.detection_range:
		soldier.current_target = null
		soldier._change_state(soldier.State.IDLE)
		return

	var attack_range = soldier.current_weapon.attack_range if soldier.current_weapon and "attack_range" in soldier.current_weapon else 1.2
	if distance_xz <= attack_range:
		soldier._change_state(soldier.State.ATTACK)
		return
	if is_instance_valid(soldier.owned_ship) and is_instance_valid(target_ship) and target_ship != soldier.owned_ship:
		if soldier.has_method("_is_in_cross_ship_contact_zone") and soldier._is_in_cross_ship_contact_zone(target_ship):
			_hold_cross_ship_contact_edge(soldier, target_node, delta)
			return

	var target_pos = target_node.global_position
	var direction = (target_pos - soldier.global_position).normalized()
	soldier.velocity = direction * soldier.move_speed
	soldier.move_and_slide()

	if direction.length_squared() > 0.01:
		var target_look = soldier.global_position + direction
		target_look.y = soldier.global_position.y
		turn_toward_position(soldier, target_look, MOVE_TURN_SPEED, delta)


static func state_attack(soldier, delta: float = 0.016) -> void:
	if not is_instance_valid(soldier.current_target):
		soldier._change_state(soldier.State.IDLE)
		return

	if SoldierStateHelper.is_dead_soldier(soldier.current_target) or soldier.current_target.get_team_tag() == soldier.team:
		_clear_target_and_try_muster_or_idle(soldier, 0.95, delta, ATTACK_TURN_SPEED)
		return

	var target_node := soldier.current_target as Node3D
	if not is_instance_valid(target_node) or not target_node.is_inside_tree():
		_clear_target_and_try_muster_or_idle(soldier, 0.95, delta, ATTACK_TURN_SPEED)
		return

	var should_run_full_validation := true
	if "attack_validation_timer" in soldier:
		soldier.attack_validation_timer -= delta
		should_run_full_validation = soldier.attack_validation_timer <= 0.0
	if should_run_full_validation:
		var validation_interval := _get_attack_validation_interval(soldier)
		if "attack_validation_interval_runtime" in soldier:
			soldier.attack_validation_interval_runtime = validation_interval
		if "attack_validation_timer" in soldier:
			soldier.attack_validation_timer = validation_interval + randf_range(0.0, ATTACK_VALIDATION_JITTER)
		var validate_profile_start := PhysicsFrameProfiler.begin()
		if _validate_attack_state(soldier, target_node, delta):
			PhysicsFrameProfiler.end("soldier_attack_validate", validate_profile_start)
		else:
			PhysicsFrameProfiler.end("soldier_attack_validate", validate_profile_start)
			return

	soldier.velocity = Vector3.ZERO
	var turn_profile_start := PhysicsFrameProfiler.begin()
	turn_toward_position(
		soldier,
		Vector3(target_node.global_position.x, soldier.global_position.y, target_node.global_position.z),
		ATTACK_TURN_SPEED,
		delta
	)
	PhysicsFrameProfiler.end("soldier_attack_turn", turn_profile_start)

	if soldier.attack_timer <= 0:
		var swing_profile_start := PhysicsFrameProfiler.begin()
		if soldier.current_target.has_method("get_hull_ratio"):
			soldier._perform_special_attack(soldier.current_target)
		else:
			soldier._perform_attack()
		soldier.attack_timer = SoldierCombatHelper.get_effective_attack_cooldown(soldier)
		PhysicsFrameProfiler.end("soldier_attack_swing", swing_profile_start)


static func _validate_attack_state(soldier, target_node: Node3D, delta: float) -> bool:
	if _retarget_owned_ship_hostile(soldier):
		return false
	if not is_instance_valid(soldier.current_target):
		soldier._change_state(soldier.State.IDLE)
		return false
	if SoldierStateHelper.is_dead_soldier(soldier.current_target) or soldier.current_target.get_team_tag() == soldier.team:
		_clear_target_and_try_muster_or_idle(soldier, 0.95, delta, ATTACK_TURN_SPEED)
		return false
	target_node = soldier.current_target as Node3D
	if not is_instance_valid(target_node) or not target_node.is_inside_tree():
		_clear_target_and_try_muster_or_idle(soldier, 0.95, delta, ATTACK_TURN_SPEED)
		return false
	var target_ship = soldier.current_target.get_owned_ship_node() if soldier.current_target.has_method("get_owned_ship_node") else null
	if is_instance_valid(target_ship) and target_ship != soldier.owned_ship:
		if target_ship.has_method("is_sinking_or_dying") and target_ship.is_sinking_or_dying():
			_clear_target_and_try_muster_or_idle(soldier, 0.95, delta, ATTACK_TURN_SPEED)
			return false

	var flat_dx: float = soldier.global_position.x - target_node.global_position.x
	var flat_dz: float = soldier.global_position.z - target_node.global_position.z
	var distance_xz_sq: float = flat_dx * flat_dx + flat_dz * flat_dz

	if is_instance_valid(soldier.owned_ship) and target_ship != soldier.owned_ship:
		if soldier.has_method("_should_hold_defensive_deck_position_against") and soldier._should_hold_defensive_deck_position_against(target_ship):
			soldier.current_target = null
			soldier._change_state(soldier.State.IDLE)
			return false
		if not soldier._is_ship_pair_in_melee_range(target_ship):
			soldier._change_state(soldier.State.IDLE)
			return false
		if soldier.has_method("_is_in_cross_ship_contact_zone") and soldier._is_in_cross_ship_contact_zone(target_ship) == false:
			soldier._change_state(soldier.State.MOVE)
			return false

	var attack_range = soldier.current_weapon.attack_range if soldier.current_weapon and "attack_range" in soldier.current_weapon else 1.2
	var max_attack_distance: float = attack_range * 1.2
	if distance_xz_sq > max_attack_distance * max_attack_distance:
		soldier._change_state(soldier.State.MOVE)
		return false
	return true


static func _get_attack_validation_interval(soldier) -> float:
	if soldier.get("_lod_is_combat_priority") == false:
		return ATTACK_VALIDATION_FAR_LOD_INTERVAL
	var target_ship = soldier.current_target.get_owned_ship_node() if is_instance_valid(soldier.current_target) and soldier.current_target.has_method("get_owned_ship_node") else null
	if is_instance_valid(target_ship) and target_ship != soldier.owned_ship:
		return ATTACK_VALIDATION_CROSS_SHIP_INTERVAL
	return ATTACK_VALIDATION_NEAR_INTERVAL


static func _hold_cross_ship_contact_edge(soldier, target_node: Node3D, delta: float) -> void:
	soldier.velocity = Vector3.ZERO
	var look_target := Vector3(target_node.global_position.x, soldier.global_position.y, target_node.global_position.z)
	turn_toward_position(soldier, look_target, MOVE_TURN_SPEED, delta)


static func _move_toward_point(soldier, target_pos: Vector3, speed_scale: float = 1.0, delta: float = 0.016, turn_speed: float = MOVE_TURN_SPEED) -> void:
	if _move_toward_owned_ship_global_point(soldier, target_pos, speed_scale, delta, turn_speed):
		return
	var flat_target := Vector3(target_pos.x, soldier.global_position.y, target_pos.z)
	var diff: Vector3 = flat_target - soldier.global_position
	diff.y = 0.0
	if diff.length_squared() <= 0.04:
		soldier.velocity = Vector3.ZERO
		soldier.move_and_slide()
		return

	var direction: Vector3 = diff.normalized()
	soldier.velocity = direction * soldier.move_speed * speed_scale
	soldier.move_and_slide()

	if direction.length_squared() > 0.01:
		turn_toward_position(soldier, flat_target, turn_speed, delta)


static func _move_toward_owned_ship_global_point(soldier, target_pos: Vector3, speed_scale: float, delta: float, turn_speed: float) -> bool:
	if not is_instance_valid(soldier.owned_ship):
		return false
	var target_local: Vector3 = soldier.owned_ship.to_local(target_pos)
	return _move_toward_owned_ship_local_point(soldier, target_local, speed_scale, delta, turn_speed)


static func _move_toward_owned_ship_local_point(soldier, target_local: Vector3, speed_scale: float, delta: float, turn_speed: float) -> bool:
	if not is_instance_valid(soldier.owned_ship):
		return false
	var ship := soldier.owned_ship as Node3D
	var current_local: Vector3 = ship.to_local(soldier.global_position)
	var diff_xz := Vector2(target_local.x - current_local.x, target_local.z - current_local.z)
	if diff_xz.length_squared() <= 0.04:
		soldier.velocity = Vector3.ZERO
		return true

	var step := maxf(0.0, soldier.move_speed * speed_scale * delta)
	var next_xz := Vector2(current_local.x, current_local.z).move_toward(Vector2(target_local.x, target_local.z), step)
	var next_local := Vector3(next_xz.x, current_local.y, next_xz.y)
	soldier.global_position = ship.to_global(next_local)
	soldier.velocity = Vector3.ZERO

	var look_target := ship.to_global(Vector3(target_local.x, current_local.y, target_local.z))
	turn_toward_position(soldier, look_target, turn_speed, delta)
	return true


static func _try_muster_to_cross_ship_contact(soldier, speed_scale: float = 1.0, delta: float = 0.016, turn_speed: float = MOVE_TURN_SPEED) -> bool:
	if not soldier.has_method("_find_cross_ship_muster_target"):
		return false
	var muster_target: Vector3 = soldier._find_cross_ship_muster_target()
	if muster_target == Vector3.INF:
		return false
	_move_toward_point(soldier, muster_target, speed_scale, delta, turn_speed)
	return true


static func _clear_target_and_try_muster_or_idle(soldier, speed_scale: float, delta: float, turn_speed: float) -> void:
	soldier.current_target = null
	if _try_muster_to_cross_ship_contact(soldier, speed_scale, delta, turn_speed):
		return
	soldier._change_state(soldier.State.IDLE)


static func _try_move_to_active_ship_duty_target(soldier, speed_scale: float, delta: float, turn_speed: float) -> bool:
	if not soldier.has_method("_get_active_ship_duty_target"):
		return false
	var duty_target: Vector3 = soldier._get_active_ship_duty_target()
	if duty_target == Vector3.INF:
		return false
	_move_toward_point(soldier, duty_target, speed_scale, delta, turn_speed)
	return true


static func turn_toward_position(soldier, target_pos: Vector3, turn_speed: float, delta: float) -> void:
	var parent_node := soldier.get_parent() as Node3D
	var local_target: Vector3 = parent_node.to_local(target_pos) if is_instance_valid(parent_node) else target_pos
	var local_origin: Vector3 = soldier.position if is_instance_valid(parent_node) else soldier.global_position
	var flat_dir: Vector3 = local_target - local_origin
	flat_dir.y = 0.0
	if flat_dir.length_squared() <= TURN_TARGET_DISTANCE_EPSILON_SQ:
		return

	var target_yaw := atan2(-flat_dir.x, -flat_dir.z)
	var yaw_delta := wrapf(target_yaw - soldier.rotation.y, -PI, PI)
	if absf(yaw_delta) <= TURN_ANGLE_DEADZONE:
		return
	var step := clampf(1.0 - exp(-turn_speed * maxf(delta, 0.0)), 0.0, 1.0)
	var current_rotation: Vector3 = soldier.rotation
	current_rotation.x = 0.0
	current_rotation.y = lerp_angle(current_rotation.y, target_yaw, step)
	current_rotation.z = 0.0
	soldier.rotation = current_rotation


static func _retarget_owned_ship_hostile(soldier) -> bool:
	if not soldier.has_method("find_nearest_hostile_on_owned_ship"):
		return false
	if not is_instance_valid(soldier.owned_ship):
		return false
	var owned_team: String = soldier.owned_ship.get_team_tag() if soldier.owned_ship.has_method("get_team_tag") else str(soldier.owned_ship.get("team"))
	if owned_team != soldier.team:
		return false
	var boarder: Node3D = soldier.find_nearest_hostile_on_owned_ship()
	if not is_instance_valid(boarder):
		return false
	if soldier.current_target == boarder:
		return false
	if _should_keep_current_owned_ship_hostile_target(soldier, boarder):
		return false
	soldier.current_target = boarder
	soldier._change_state(soldier.State.MOVE)
	return true


static func _should_keep_current_owned_ship_hostile_target(soldier, nearest_boarder: Node3D) -> bool:
	var current := soldier.current_target as Node3D
	if not is_instance_valid(current) or not current.is_inside_tree():
		return false
	if SoldierStateHelper.is_dead_soldier(current):
		return false
	if _get_target_owned_ship(current) != soldier.owned_ship:
		return false
	var current_team: String = current.get_team_tag() if current.has_method("get_team_tag") else str(current.get("team"))
	if current_team == soldier.team:
		return false
	var current_dist_sq: float = _get_planar_distance_sq(soldier, current)
	var nearest_dist_sq: float = _get_planar_distance_sq(soldier, nearest_boarder)
	return nearest_dist_sq >= current_dist_sq * OWNED_SHIP_HOSTILE_SWITCH_RATIO


static func _get_target_owned_ship(target: Node) -> Node3D:
	if not is_instance_valid(target):
		return null
	if target.has_method("get_owned_ship_node"):
		return target.call("get_owned_ship_node") as Node3D
	var owned_value: Variant = target.get("owned_ship")
	return owned_value as Node3D if is_instance_valid(owned_value) else null


static func _get_planar_distance_sq(from_node: Node3D, to_node: Node3D) -> float:
	if not is_instance_valid(from_node) or not is_instance_valid(to_node):
		return INF
	var dx: float = from_node.global_position.x - to_node.global_position.x
	var dz: float = from_node.global_position.z - to_node.global_position.z
	return dx * dx + dz * dz
