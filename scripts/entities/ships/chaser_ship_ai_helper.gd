extends RefCounted
class_name ChaserShipAiHelper


static var _cached_ships_list: Array = []
static var _last_ships_cache_frame: int = -1
const LIMBO_AI_BOARDING_INTENT_STALE_FRAMES := 4

static func _is_true(value: Variant) -> bool:
	return value == true

static func _is_gunner(ship) -> bool:
	return ShipCombatModeHelper.is_gunner(ship)


static func _can_board(ship) -> bool:
	return ShipCombatModeHelper.can_board(ship)


static func _target_ship(ship) -> Node3D:
	if not is_instance_valid(ship):
		return null
	if ship.has_method("get_target_ship"):
		return ship.get_target_ship()
	if "target" in ship:
		return ship.get("target")
	return null


static func _is_sinking_or_dying(node: Node) -> bool:
	if not is_instance_valid(node):
		return true
	if node.has_method("is_sinking_or_dying"):
		return node.is_sinking_or_dying()
	return _is_true(node.get("is_dying")) or _is_true(node.get("is_sinking"))


static func _is_player_controlled(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	return ShipTargetingHelper.is_player_controlled_ship(node)


static func _calculate_sail_drive_multiplier(ship, floor_ratio: float = 0.45) -> float:
	if not is_instance_valid(ship._cached_wind_manager):
		return 1.0
	if not ship._cached_wind_manager.has_method("get_wind_direction") or not ship._cached_wind_manager.has_method("get_wind_strength"):
		return 1.0

	var wind_dir: Vector2 = ship._cached_wind_manager.get_wind_direction()
	var wind_strength: float = ship._cached_wind_manager.get_wind_strength()
	var ship_angle_rad: float = ship.rotation.y
	var sail_world_rad: float = ship_angle_rad - deg_to_rad(ship.sail_angle)
	var sail_normal: Vector2 = -Vector2(sin(sail_world_rad), cos(sail_world_rad))
	var ship_forward: Vector2 = Vector2(-sin(ship_angle_rad), -cos(ship_angle_rad))
	var wind_force: float = max(0.0, wind_dir.dot(sail_normal))
	var forward_component: float = max(0.0, sail_normal.dot(ship_forward))
	var thrust: float = wind_force * forward_component
	var sail_efficiency: float = clamp((thrust * wind_strength) / 0.6, 0.0, 1.0)
	return lerp(floor_ratio, 1.05, sail_efficiency)


static func get_ships_cached(_tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_ships_cache_frame:
		_cached_ships_list = EntityRegistry.get_ships()
		_last_ships_cache_frame = current_frame
	return _cached_ships_list


static func configure_logic_throttle(ship) -> void:
	var seed_value: int = abs(hash("%s:%s:%s" % [str(ship.get_instance_id()), ship.ship_type, ship.formation_role_name]))
	var phase: float = float(seed_value % 1000) / 1000.0
	var jitter_sign: float = -1.0 if (seed_value % 2) == 0 else 1.0
	var jitter_scale: float = float(seed_value % 500) / 500.0
	var jitter: float = ship.ai_logic_update_jitter * jitter_sign * jitter_scale
	ship._ai_logic_update_interval_runtime = clampf(ship.ai_logic_update_interval + jitter, 0.06, 0.5)
	ship._ai_separation_update_interval_runtime = get_separation_update_interval_runtime(ship, seed_value)
	ship.logic_timer = ship._ai_logic_update_interval_runtime * phase
	ship.separation_timer = ship._ai_separation_update_interval_runtime * phase


static func get_logic_update_interval_for_ship(ship) -> float:
	return ship._ai_logic_update_interval_runtime * get_load_multiplier(ship)


static func get_separation_update_interval_for_ship(ship) -> float:
	return ship._ai_separation_update_interval_runtime * get_load_multiplier(ship)


static func get_load_multiplier(ship) -> float:
	var ship_count: int = EntityRegistry.count_ships()
	var projectile_count: int = EntityRegistry.count_projectiles()
	var load_multiplier: float = 1.0
	if ship_count > 12:
		load_multiplier += minf(0.45, float(ship_count - 12) * 0.03)
	if projectile_count > 18:
		load_multiplier += minf(0.25, float(projectile_count - 18) * 0.01)
	if ship.team == "player":
		load_multiplier *= 0.9
	if _is_gunner(ship):
		load_multiplier *= 1.05
	return clampf(load_multiplier, 0.75, 1.6)


static func get_separation_update_interval_runtime(ship, seed_value: int) -> float:
	var base_interval: float = clampf(ship.ai_separation_update_interval, 0.05, 0.35)
	var role_adjust: float = 0.0
	if _is_gunner(ship):
		role_adjust = 0.02
	elif ShipCombatModeHelper.is_charger(ship):
		role_adjust = -0.01
	var phase_jitter: float = float(seed_value % 7) * 0.005
	return clampf(base_interval + role_adjust + phase_jitter, 0.05, 0.35)


static func calculate_separation(ship) -> Vector3:
	if _is_true(ship.get_meta("derelict_nonblocking", false)):
		return Vector3.ZERO

	var force := Vector3.ZERO
	var neighbors := get_ships_cached(ship.get_tree())
	var count := 0
	var max_checks: int = min(neighbors.size(), 15)
	for i in range(max_checks):
		var other = neighbors[i]
		if other == ship or not is_instance_valid(other) or _is_true(other.get("is_dying")):
			continue
		if _is_true(other.get_meta("derelict_nonblocking", false)):
			continue
		if ship.is_boarding and other == ship.boarding_target:
			continue
		if other.has_method("get_boarding_attacker_ship") and other.get_boarding_attacker_ship() == ship:
			continue

		var offset: Vector3 = ship.global_position - other.global_position
		offset.y = 0.0
		var dist_sq: float = offset.length_squared()
		if dist_sq <= 0.01:
			continue

		var dist := sqrt(dist_sq)
		var coll_dist: float = ship.get_collision_distance_to(other)
		if ShipCombatModeHelper.is_charger(ship) and is_instance_valid(_target_ship(ship)) and other == _target_ship(ship) and dist < coll_dist + 1.2:
			continue
		var separation_trigger_dist: float = coll_dist + (0.18 * ship.separation_pad_scale)

		if dist < separation_trigger_dist:
			var push_dir := offset.normalized()
			var ratio: float = (separation_trigger_dist - dist) / max(separation_trigger_dist, 0.001)
			var strength: float = pow(ratio, 2.0)
			force += push_dir * strength
			count += 1

	if count > 0:
		force = (force / count) * 1.8

	return force


static func process_physics(ship, delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if ship.has_method("is_combat_disabled") and ship.is_combat_disabled():
		return

	update_wave_sounds(ship, delta)

	ship.logic_timer -= delta
	var do_logic_update = false
	if ship.logic_timer <= 0:
		ship.logic_timer = _get_logic_update_interval(ship)
		do_logic_update = true
	ship.separation_timer -= delta
	if ship.separation_timer <= 0.0:
		ship.separation_timer = _get_separation_update_interval(ship)
		if ship.team == "player" and ShipAllyRoleHelper.is_support_ship(ship):
			ship.separation_force = Vector3.ZERO
		else:
			ship.separation_force = calculate_separation(ship)
	if ship.has_meta(ShipBoardingMetaHelper.KEY_POST_IMPACT_FOLLOW_TIMER):
		var follow_timer: float = maxf(0.0, ShipBoardingMetaHelper.get_post_impact_follow_timer(ship) - delta)
		if follow_timer <= 0.0:
			ShipBoardingMetaHelper.remove_meta_key(ship, ShipBoardingMetaHelper.KEY_POST_IMPACT_FOLLOW_TIMER)
		else:
			ShipBoardingMetaHelper.set_post_impact_follow_timer(ship, follow_timer)
	if ship.has_meta("boarding_impact_grace_timer"):
		var impact_grace_timer: float = maxf(0.0, float(ship.get_meta("boarding_impact_grace_timer")) - delta)
		if impact_grace_timer <= 0.0:
			ship.remove_meta("boarding_impact_grace_timer")
			if ship.has_meta("boarding_impact_target_id"):
				ship.remove_meta("boarding_impact_target_id")
		else:
			ship.set_meta("boarding_impact_grace_timer", impact_grace_timer)

	if ship.is_derelict:
		var wind_manager = ship.get_node_or_null("/root/WindManager")
		if is_instance_valid(wind_manager):
			var wind_dir_v2: Vector2 = wind_manager.wind_direction
			var wind_dir = Vector3(wind_dir_v2.x, 0, wind_dir_v2.y)
			var wind_force = wind_manager.wind_strength * 0.4
			ship.position += wind_dir * wind_force * delta

			var target_rot = atan2(-wind_dir.x, -wind_dir.z)
			ship.rotation.y = lerp_angle(ship.rotation.y, target_rot, delta * 0.5)
			ship._set_wake_state(false)

		if do_logic_update:
			ship._check_offscreen_despawn()
		return

	ship.update_crew_allocation_state(delta)

	if do_logic_update:
		update_logic_throttled(ship)

	if ship.get_team_tag() == "player":
		if ship.is_boarding:
			if ChaserShipMinionHelper.try_interrupt_boarding_for_flagship_rescue(ship):
				ship._process_minion_ai(delta)
				return
			ship._process_boarding(delta)
			return
		ship._process_minion_ai(delta)
		return

	if ship.is_boarding:
		ship._process_boarding(delta)
		return

	if not is_instance_valid(_target_ship(ship)):
		ship._set_wake_state(false)
		return
	var current_target: Node3D = _target_ship(ship)

	var nav := ChaserShipNavigationHelper.build_navigation(ship, current_target)
	var target_pos: Vector3 = ShipMovementIntent.get_target_pos(nav, current_target.global_position)
	var desired_point: Vector3 = ShipMovementIntent.get_desired_point(nav, current_target.global_position)
	var heading_point: Vector3 = ShipMovementIntent.get_heading_point(nav, desired_point)
	var dist_to_target: float = ShipMovementIntent.get_dist_to_target(nav, ship.global_position.distance_to(current_target.global_position))
	var desired_speed_mult: float = ShipMovementIntent.get_desired_speed_mult(nav)
	var permit_sprint: bool = ShipMovementIntent.get_permit_sprint(nav)
	var dir_to_target: Vector3 = ShipMovementIntent.get_dir_to_target(nav, Vector3.ZERO)

	var boarding_attempt_distance: float = ShipContactGeometry.get_boarding_attempt_distance(ship, current_target)
	if not _is_gunner(ship) and _can_board(ship) and dist_to_target <= boarding_attempt_distance:
		var can_use_limbo_boarding_intent := true
		if ship.get("limbo_ai_pilot_enabled") == true:
			var boarding_frame := int(ship.get_meta(ShipAILimboKeys.META_BOARDING_FRAME, -1000000))
			if Engine.get_physics_frames() - boarding_frame <= LIMBO_AI_BOARDING_INTENT_STALE_FRAMES:
				var boarding_target_id := int(ship.get_meta(ShipAILimboKeys.META_BOARDING_TARGET_ID, 0))
				var boarding_intent := str(ship.get_meta(ShipAILimboKeys.META_BOARDING_INTENT, "")).strip_edges()
				can_use_limbo_boarding_intent = boarding_target_id == current_target.get_instance_id() and boarding_intent == ShipAILimboKeys.BOARDING_READY
		if can_use_limbo_boarding_intent:
			var can_side_board: bool = ship.has_method("_is_side_boarding_approach") and ship.call("_is_side_boarding_approach", current_target)
			var can_force_head_on: bool = ship.has_method("_can_force_head_on_boarding") and ship.call("_can_force_head_on_boarding", current_target)
			var can_force_cleanup: bool = ship.has_method("_can_force_cleanup_boarding") and ship.call("_can_force_cleanup_boarding", current_target)
			var can_latched_board: bool = ship.has_method("_can_start_boarding_latched") and ship.call("_can_start_boarding_latched", current_target, dist_to_target, can_side_board, can_force_head_on, can_force_cleanup, delta)
			var direct_board_pad: float = 0.35
			if ship.has_method("get_team_tag") and ship.call("get_team_tag") == "enemy":
				direct_board_pad += 0.15
			var direct_board_distance: float = ship.max_boarding_distance + direct_board_pad
			if ship.has_method("get_collision_distance_to"):
				direct_board_distance = maxf(direct_board_distance, float(ship.call("get_collision_distance_to", current_target)) + 0.85)
			var can_direct_board: bool = (can_side_board or can_force_head_on or can_force_cleanup) and dist_to_target <= direct_board_distance
			var impact_confirmed: bool = ship.has_method("_has_recent_boarding_impact") and ship.call("_has_recent_boarding_impact", current_target)
			if (can_latched_board or can_direct_board) and impact_confirmed:
				if ship.has_method("_board_ship"):
					ship.call("_board_ship", current_target)
					if ship.is_boarding:
						ship._process_boarding(delta)
						return
		elif ship.has_method("_decay_boarding_latch"):
			ship.call("_decay_boarding_latch", current_target, delta)
	elif ship.has_method("_decay_boarding_latch"):
		ship.call("_decay_boarding_latch", current_target, delta)

	var move_vector = desired_point - ship.global_position
	move_vector.y = 0.0
	var move_dir = move_vector.normalized() if move_vector.length_squared() > 0.001 else Vector3.ZERO
	var base_move_dir: Vector3 = move_dir
	if ship.separation_force.length_squared() > 0.001:
		if move_dir == Vector3.ZERO:
			move_dir = ship.separation_force.normalized()
		else:
			move_dir = (move_dir + ship.separation_force * 1.5).normalized()

	var heading_vector = heading_point - ship.global_position
	heading_vector.y = 0.0
	if heading_vector.length_squared() <= 0.001:
		heading_vector = move_dir if move_dir.length_squared() > 0.001 else dir_to_target
	var target_rotation_y = atan2(-heading_vector.x, -heading_vector.z)
	var angle_diff = wrapf(target_rotation_y - ship.rotation.y, -PI, PI)
	var desired_rudder = clamp(-rad_to_deg(angle_diff) * ship.ai_rudder_gain, -40.0, 40.0)
	var close_turn_blend = 0.0
	if ship.ai_close_turn_soft_radius > 0.01:
		close_turn_blend = clamp(1.0 - (dist_to_target / ship.ai_close_turn_soft_radius), 0.0, 1.0)
	var close_turn_factor = lerp(1.0, ship.ai_close_turn_scale, close_turn_blend)
	desired_rudder *= close_turn_factor
	var rudder_speed_adjusted = ship.ai_rudder_response_speed * ship.get_rudder_response_multiplier()
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	var leak_speed_mult = clamp(1.0 - (ship.leaking_rate * 0.05), 0.3, 1.0)
	var desired_speed = ship.move_speed * leak_speed_mult * desired_speed_mult * ship.get_shiphandling_multiplier()

	if not _is_gunner(ship) and dist_to_target < 4.4:
		var slow_factor = clamp((dist_to_target - 1.4) / 3.0, 0.88, 1.0)
		desired_speed *= slow_factor
		ship.is_sprinting = false
	else:
		if ship.team == "enemy" and permit_sprint:
			if not ship.is_sprinting and dist_to_target > 10.0 and dist_to_target < 28.0 and ship.stamina > 30.0:
				ship.is_sprinting = true
			if ship.is_sprinting and (ship.stamina <= 0.0 or dist_to_target <= 8.0):
				ship.is_sprinting = false

			if ship.is_sprinting:
				ship.stamina = max(0.0, ship.stamina - 20.0 * delta)
				desired_speed *= ship.sprint_multiplier
			else:
				ship.stamina = min(ship.max_stamina, ship.stamina + 15.0 * delta)
		else:
			ship.is_sprinting = false
			ship.stamina = min(ship.max_stamina, ship.stamina + 18.0 * delta)

	if desired_speed > ship.current_speed:
		ship.current_speed = move_toward(ship.current_speed, desired_speed, ship.acceleration * delta)
	else:
		ship.current_speed = move_toward(ship.current_speed, desired_speed, ship.deceleration * delta)

	var wind_mult: float = _calculate_sail_drive_multiplier(ship) * ship.get_shiphandling_multiplier()
	if ship.current_speed > 0.1:
		var speed_ratio = clamp(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0)
		var turn_scale = ship.ai_turn_authority * close_turn_factor
		var actual_turn = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * turn_scale * delta
		var max_turn_this_frame = ship.ai_max_turn_rate * delta
		actual_turn = clamp(actual_turn, -max_turn_this_frame, max_turn_this_frame)
		ship.rotation.y -= deg_to_rad(actual_turn)

	var forward_vec = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	var velocity = forward_vec * ship.current_speed * wind_mult
	velocity += ship.separation_force
	velocity += ship._calculate_boarding_pull_velocity(delta)
	var collision_repulsion = ship._calculate_collision_repulsion()
	if not _is_gunner(ship) and dist_to_target < ship.max_boarding_distance + 1.2:
		var to_target_flat = ship.target.global_position - ship.global_position
		to_target_flat.y = 0.0
		if to_target_flat.length_squared() > 0.001:
			var approach_dot = forward_vec.normalized().dot(to_target_flat.normalized())
			if approach_dot > 0.3:
				collision_repulsion *= 0.35
	velocity += collision_repulsion * delta
	_draw_ai_intent_debug(
		ship,
		current_target,
		nav,
		target_pos,
		desired_point,
		heading_point,
		base_move_dir,
		move_dir,
		heading_vector,
		velocity,
		collision_repulsion,
		dist_to_target,
		desired_speed_mult,
		desired_rudder,
		permit_sprint,
		boarding_attempt_distance
	)

	var prev_pos = ship.global_position
	var next_pos = prev_pos + velocity * delta
	# Allow visible impact with the target, but stop the AI from tunneling so deep
	# that ships overlap past the midline before the collision reads as a hit.
	if is_instance_valid(current_target):
		next_pos = ship._apply_ship_collision_guard(current_target, prev_pos, next_pos, 0.88, velocity.length())
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, current_target)
	ship.global_position = next_pos

	ship._update_rudder_visual()
	if ship.leaking_rate > 0:
		ship.take_damage(ship.leaking_rate * delta)
	ship._apply_bobbing_effect()
	if not ship.is_dying:
		ship.rotation.z += ship.tilt_offset
	ship._set_wake_state(ship.current_speed > 0.4, clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0), 0.0, 0.0)


static func _draw_ai_intent_debug(
	ship,
	current_target: Node3D,
	nav: Dictionary,
	target_pos: Vector3,
	desired_point: Vector3,
	heading_point: Vector3,
	base_move_dir: Vector3,
	move_dir: Vector3,
	heading_vector: Vector3,
	velocity: Vector3,
	collision_repulsion: Vector3,
	dist_to_target: float,
	desired_speed_mult: float,
	desired_rudder: float,
	permit_sprint: bool,
	boarding_attempt_distance: float
) -> void:
	if not DebugDrawBridge.is_channel_enabled(DebugDrawBridge.CHANNEL_AI_INTENT) or not DebugDrawBridge.can_draw():
		return
	if not (ship is Node3D) or not is_instance_valid(current_target):
		return

	var ship_3d := ship as Node3D
	var origin: Vector3 = ship_3d.global_position
	var mode := ShipMovementIntent.get_mode(nav, "pursuit")
	if mode.is_empty():
		mode = "pursuit"
	var color := _get_ai_intent_color(mode)
	var target_color := Color(1.0, 0.22, 0.12, 0.9)
	var desired_color := Color(0.28, 0.92, 1.0, 0.92)
	var heading_color := Color(1.0, 0.82, 0.24, 0.9)
	var velocity_color := Color(0.42, 1.0, 0.36, 0.86)
	var separation_color := Color(1.0, 0.36, 0.78, 0.86)
	var duration := 0.0

	DebugDrawBridge.draw_marker(target_pos, target_color, "", duration, 0.18, 1.0)
	DebugDrawBridge.draw_marker(desired_point, desired_color, "", duration, 0.22, 1.0)
	DebugDrawBridge.draw_marker(heading_point, heading_color, "", duration, 0.18, 1.45)
	DebugDrawBridge.draw_line_raised(origin, desired_point, 1.15, desired_color, duration, 0.035)

	if base_move_dir.length_squared() > 0.001:
		var base_end: Vector3 = origin + base_move_dir.normalized() * clampf(origin.distance_to(desired_point), 2.5, 8.0)
		DebugDrawBridge.draw_arrow(origin + Vector3.UP * 1.55, base_end + Vector3.UP * 1.55, color, duration, 0.45, 0.035)
	if move_dir.length_squared() > 0.001 and move_dir.distance_squared_to(base_move_dir) > 0.02:
		var adjusted_end: Vector3 = origin + move_dir.normalized() * 5.5
		DebugDrawBridge.draw_arrow(origin + Vector3.UP * 1.85, adjusted_end + Vector3.UP * 1.85, velocity_color, duration, 0.42, 0.032)
	if heading_vector.length_squared() > 0.001:
		var heading_end: Vector3 = origin + heading_vector.normalized() * 5.0
		DebugDrawBridge.draw_arrow(origin + Vector3.UP * 2.15, heading_end + Vector3.UP * 2.15, heading_color, duration, 0.4, 0.03)
	var separation_force: Vector3 = ship.separation_force
	if separation_force.length_squared() > 0.001:
		var separation_end: Vector3 = origin + separation_force.normalized() * clampf(separation_force.length() * 5.0, 1.5, 5.5)
		DebugDrawBridge.draw_arrow(origin + Vector3.UP * 2.45, separation_end + Vector3.UP * 2.45, separation_color, duration, 0.36, 0.03)
	if collision_repulsion.length_squared() > 0.001:
		var repulsion_end: Vector3 = origin + collision_repulsion.normalized() * clampf(collision_repulsion.length(), 1.2, 4.5)
		DebugDrawBridge.draw_arrow(origin + Vector3.UP * 2.75, repulsion_end + Vector3.UP * 2.75, Color(1.0, 0.18, 0.12, 0.86), duration, 0.34, 0.03)
	if velocity.length_squared() > 0.001:
		var velocity_end: Vector3 = origin + velocity.normalized() * clampf(velocity.length(), 1.5, 6.0)
		DebugDrawBridge.draw_line(origin + Vector3.UP * 0.72, velocity_end + Vector3.UP * 0.72, velocity_color, duration, 0.026)

	if _can_board(ship) and boarding_attempt_distance > 0.1 and dist_to_target <= boarding_attempt_distance + 5.0:
		var boarding_color := Color(0.25, 1.0, 0.64, 0.7) if dist_to_target <= boarding_attempt_distance else Color(1.0, 0.58, 0.16, 0.62)
		DebugDrawBridge.draw_circle_xz(current_target.global_position, boarding_attempt_distance, boarding_color, 1.25, duration, 72, 0.026)

	var approach_mode := ShipBoardingMetaHelper.get_approach_mode(ship, "-")
	var slot_id := ShipBoardingMetaHelper.get_slot_id(ship, "")
	var approach_text := " | %s" % approach_mode if approach_mode != "-" else ""
	var slot_text := " | slot %s" % slot_id if not slot_id.is_empty() else ""
	var limbo_text := _get_limbo_debug_text(ship)
	DebugDrawBridge.draw_text(
		origin + Vector3.UP * 3.15,
		"%s | %s | %.1fm | spd x%.2f | rud %.0f%s%s%s" % [
			ship_3d.name,
			mode,
			dist_to_target,
			desired_speed_mult,
			desired_rudder,
			" | sprint" if permit_sprint else "",
			approach_text + slot_text,
			limbo_text
		],
		color,
		duration,
		17
	)


static func _get_limbo_debug_text(ship) -> String:
	if not is_instance_valid(ship):
		return ""
	if ship.get("limbo_ai_pilot_enabled") != true:
		return ""
	var stance := str(ship.get_meta(ShipAILimboKeys.META_STANCE, ""))
	var range_intent := str(ship.get_meta(ShipAILimboKeys.META_INTENT, ""))
	var phase := str(ship.get_meta(ShipAILimboKeys.META_PRESSURE_PHASE, ""))
	var weapon_intent := str(ship.get_meta(ShipAILimboKeys.META_WEAPON_INTENT, ""))
	var special_intent := str(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT, ""))
	var boarding_intent := str(ship.get_meta(ShipAILimboKeys.META_BOARDING_INTENT, ""))
	if stance.is_empty() and range_intent.is_empty() and phase.is_empty() and weapon_intent.is_empty() and special_intent.is_empty() and boarding_intent.is_empty():
		return ""
	var pressure := clampf(float(ship.get_meta(ShipAILimboKeys.META_PRESSURE, 0.0)), 0.0, 1.0)
	var distance := float(ship.get_meta(ShipAILimboKeys.META_TARGET_DISTANCE, 0.0))
	return "\nLimboAI %s | range:%s | weapon:%s | special:%s | board:%s | phase:%s | p:%.2f | %.1fm" % [
		stance if not stance.is_empty() else "-",
		range_intent if not range_intent.is_empty() else "-",
		weapon_intent if not weapon_intent.is_empty() else "-",
		special_intent if not special_intent.is_empty() else "-",
		boarding_intent if not boarding_intent.is_empty() else "-",
		phase if not phase.is_empty() else "-",
		pressure,
		distance,
	]


static func _get_ai_intent_color(mode: String) -> Color:
	match mode:
		"gunner_standoff":
			return Color(1.0, 0.62, 0.2, 0.94)
		"side":
			return Color(0.28, 0.92, 1.0, 0.94)
		"contact_settle":
			return Color(0.46, 1.0, 0.64, 0.94)
		"rear":
			return Color(0.55, 0.72, 1.0, 0.94)
		"yield_overrun":
			return Color(1.0, 0.42, 0.9, 0.94)
		_:
			return Color(0.86, 1.0, 0.36, 0.94)


static func update_logic_throttled(ship) -> void:
	if not is_instance_valid(_target_ship(ship)) or _is_sinking_or_dying(_target_ship(ship)):
		ship.target = null
		find_player(ship)


static func _get_logic_update_interval(ship) -> float:
	if ship.has_method("get_ai_logic_update_interval"):
		return maxf(0.06, float(ship.call("get_ai_logic_update_interval")))
	return 0.2


static func _get_separation_update_interval(ship) -> float:
	if ship.has_method("get_ai_separation_update_interval"):
		return maxf(0.05, float(ship.call("get_ai_separation_update_interval")))
	return 0.12


static func find_player(ship) -> void:
	ship.target = ShipTargetingHelper.select_player_target_for(ship)


static func update_wave_sounds(ship, delta: float) -> void:
	if ship.is_dying or ship.is_derelict:
		return

	var speed = ship.move_speed
	if not is_instance_valid(ship.target):
		speed = 0.0

	if speed > 0.5:
		ship._wave_timer -= delta
		if ship._wave_timer <= 0:
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
				ship._cached_audio_manager.play_sfx("wave_splash", ship.global_position, randf_range(0.8, 1.2), 3.0)
			var speed_mod = clamp(speed / 5.0, 0.4, 1.5)
			ship._wave_timer = randf_range(2.0, 4.5) / speed_mod
