extends RefCounted

const SAIL_DOWNWIND_START := -0.45
const SAIL_DOWNWIND_FULL := 0.78
const SAIL_TAILWIND_BONUS_START := 0.45
const SAIL_TAILWIND_BONUS_FULL := 1.0
const SAIL_BROAD_REACH_START := -0.45
const SAIL_BROAD_REACH_FULL := 0.18
const SAIL_BROAD_REACH_FADE_START := 0.78
const SAIL_BROAD_REACH_FADE_FULL := 1.0
const SAIL_DOWNWIND_WEIGHT := 0.78
const SAIL_TAILWIND_WEIGHT := 0.22
const SAIL_BROAD_REACH_WEIGHT := 0.16
const SAIL_BEAM_REACH_START := -0.24
const SAIL_BEAM_REACH_FULL := 0.08
const SAIL_BEAM_REACH_FADE_START := 0.68
const SAIL_BEAM_REACH_FADE_FULL := 1.0
const SAIL_BEAM_REACH_WEIGHT := 0.42
const SAIL_REACH_BOOST_START := 0.24
const SAIL_REACH_BOOST_FULL := 0.56
const SAIL_REACH_BOOST_FADE_START := 0.92
const SAIL_REACH_BOOST_FADE_FULL := 1.0
const SAIL_REACH_BOOST_WEIGHT := 0.18
const SAIL_REACH_DRIVE_CAP := 1.08
const SAIL_TRIM_ERROR_GOOD_DEG := 8.0
const SAIL_TRIM_ERROR_BAD_DEG := 50.0
const SAIL_TRIM_QUALITY_FLOOR := 0.12
const WIND_STRENGTH_DEFAULT_MIN := 0.72
const WIND_STRENGTH_DEFAULT_MAX := 0.88
const WIND_SPEED_MULT_MIN := 0.92
const WIND_SPEED_MULT_MAX := 1.08

static func auto_adjust_sail(ship, delta: float) -> void:
	if not is_instance_valid(ship._cached_wind_manager) or not ship._cached_wind_manager.has_method("get_wind_direction"):
		return
	var wind_dir: Vector2 = ship._cached_wind_manager.get_wind_direction()
	var wind_angle: float = rad_to_deg(atan2(wind_dir.x, -wind_dir.y))
	var ship_angle_ccw: float = rad_to_deg(ship.rotation.y)
	var rel_wind_angle: float = wrapf(wind_angle + ship_angle_ccw, -180.0, 180.0)
	var target_sail_angle: float = clamp(rel_wind_angle / 2.0, -90.0, 90.0)
	var auto_turn_speed: float = maxf(30.0, float(ship.sail_turn_speed) * 1.5)
	ship.sail_angle = move_toward(ship.sail_angle, target_sail_angle, auto_turn_speed * delta)

static func calculate_separation(ship) -> Vector3:
	if ship.get_meta("derelict_nonblocking", false) == true:
		return Vector3.ZERO

	var force = Vector3.ZERO
	var neighbors = ship._get_ships_cached(ship.get_tree())
	var _max_checks = min(neighbors.size(), 12)
	for other in neighbors:
		if other == ship or not is_instance_valid(other) or (other.has_method("is_sinking_or_dying") and other.is_sinking_or_dying()):
			continue
		if other.get_meta("derelict_nonblocking", false) == true:
			continue
		if ship.has_method("is_boarding_ship") and ship.is_boarding_ship() and other == ship.get_boarding_target_ship():
			continue
		if other.has_method("get_boarding_attacker_ship") and other.get_boarding_attacker_ship() == ship:
			continue
		var is_my_boarding_approach_target := false
		if ship.has_method("can_board_targets") and ship.call("can_board_targets") == true:
			var is_gunner: bool = ship.has_method("is_gunner_role") and ship.call("is_gunner_role") == true
			if not is_gunner:
				var explicit_boarding_target: Node3D = ship.get_boarding_target_ship() if ship.has_method("get_boarding_target_ship") else null
				if explicit_boarding_target == other:
					is_my_boarding_approach_target = true
				elif ship.get("target") == other and ShipCombatModeHelper.can_be_boarded(other, ship):
					var attempt_distance: float = ShipContactGeometry.get_boarding_attempt_distance(ship, other)
					is_my_boarding_approach_target = ship.global_position.distance_to(other.global_position) <= attempt_distance
		if is_my_boarding_approach_target:
			continue
		var offset = other.global_position - ship.global_position
		offset.y = 0.0
		var dist_sq = offset.length_squared()
		if dist_sq <= 0.01:
			continue
		var dist = sqrt(dist_sq)
		var coll_dist = ship.get_collision_distance_to(other)
		var is_enemy_attacker = false
		if other.has_method("is_enemy_team") and other.is_enemy_team():
			is_enemy_attacker = (other.get("target") == ship or (other.has_method("get_boarding_target_ship") and other.get_boarding_target_ship() == ship))
		if is_enemy_attacker and dist < coll_dist + 1.0:
			continue
		var separation_trigger_dist = coll_dist + 0.12
		if dist < separation_trigger_dist:
			var push_dir = -offset / max(dist, 0.001)
			var ratio = (separation_trigger_dist - dist) / max(separation_trigger_dist, 0.001)
			var strength = pow(ratio, 2.0)
			force += push_dir * strength * 1.8 * BaseShipCollisionHelper.get_collision_movement_share(ship, other)
	return force

static func get_boarding_drag_multiplier(ship) -> float:
	var drag = 1.0
	var neighbors = ship._get_ships_cached(ship.get_tree())
	for other in neighbors:
		if other.has_method("has_boarding_rope_link_to") and other.call("has_boarding_rope_link_to", ship) == true:
			drag *= 0.6
		elif other.has_method("is_boarding_ship") and other.is_boarding_ship() and other.has_method("get_boarding_target_ship") and other.get_boarding_target_ship() == ship and not other.has_method("has_boarding_rope_link_to"):
			drag *= 0.6
	return maxf(0.1, drag)

static func update_movement(ship, delta: float) -> void:
	var target_speed: float = calculate_sail_speed(ship)
	var is_exhausted_rowing := false
	var is_actively_rowing: bool = ship.is_rowing
	var rowing_direction: int = _get_rowing_direction(ship)
	var is_reverse_rowing: bool = (is_actively_rowing or is_exhausted_rowing) and rowing_direction < 0
	var rowing_efficiency: float = get_furled_sail_rowing_efficiency_multiplier(ship)
	var effective_rowing_speed: float = maxf(0.0, float(ship.rowing_speed) + get_furled_sail_rowing_speed_bonus(ship))
	if is_reverse_rowing:
		var reverse_ratio := float(ship.reverse_rowing_speed_ratio) if "reverse_rowing_speed_ratio" in ship else 0.35
		var exhausted_ratio := float(ship.exhausted_rowing_speed_ratio) if is_exhausted_rowing else 1.0
		target_speed = -effective_rowing_speed * reverse_ratio * exhausted_ratio * rowing_efficiency
	else:
		if is_actively_rowing:
			target_speed += effective_rowing_speed * rowing_efficiency
		elif is_exhausted_rowing:
			target_speed += effective_rowing_speed * float(ship.exhausted_rowing_speed_ratio) * rowing_efficiency
	var ramming_boost_active: bool = ship.has_method("is_ramming_boost_active") and ship.call("is_ramming_boost_active") == true
	if ramming_boost_active and not is_reverse_rowing and ship.has_method("get_ramming_boost_target_speed"):
		target_speed = maxf(target_speed, float(ship.call("get_ramming_boost_target_speed")))
	target_speed *= ship.get_shiphandling_multiplier()
	target_speed *= get_boarding_drag_multiplier(ship)
	target_speed *= ship.speed_mult
	var forward = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	if target_speed > ship.current_speed:
		var accel: float = ship.acceleration
		if ramming_boost_active and "ramming_boost_acceleration_multiplier" in ship:
			accel *= maxf(1.0, float(ship.ramming_boost_acceleration_multiplier))
		if (is_actively_rowing or is_exhausted_rowing) and "rowing_acceleration_mult" in ship:
			accel *= float(ship.rowing_acceleration_mult) * rowing_efficiency
			if is_reverse_rowing and "reverse_rowing_acceleration_mult" in ship:
				accel *= float(ship.reverse_rowing_acceleration_mult)
			if is_exhausted_rowing:
				accel *= 0.75
		ship.current_speed = move_toward(ship.current_speed, target_speed, accel * delta)
	else:
		var decel: float = ship.deceleration
		if is_reverse_rowing and "reverse_rowing_acceleration_mult" in ship:
			decel *= float(ship.reverse_rowing_acceleration_mult)
		ship.current_speed = move_toward(ship.current_speed, target_speed, decel * delta)
	var velocity = forward * ship.current_speed
	var sep = calculate_separation(ship)
	velocity += sep
	velocity += ship._calculate_boarding_pull_velocity(delta)
	velocity += ship.consume_collision_impulse_velocity(delta)
	velocity += ship._calculate_collision_repulsion() * delta
	var prev_pos: Vector3 = ship.global_position
	ship.global_position = BaseShipCollisionHelper.apply_movement_collision_guards(ship, prev_pos, prev_pos + velocity * delta, null, maxf(absf(ship.current_speed), velocity.length()))
	var motion_speed := absf(ship.current_speed)
	var wake_active = motion_speed > 0.5 or sep.length() > 0.2
	var wake_speed_ratio = clampf(motion_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0)
	var wake_turn_ratio = clampf(ship.rudder_angle / 45.0, -1.0, 1.0)
	ship._set_wake_state(wake_active, wake_speed_ratio, wake_turn_ratio, clampf(sep.length() / 2.0, 0.0, 1.0))

static func update_steering(ship, delta: float) -> void:
	var motion_speed := absf(ship.current_speed)
	if motion_speed < 0.1:
		return
	var speed_ratio = clampf(motion_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0)
	var turn_authority: float = float(ship.player_rudder_turn_authority) if "player_rudder_turn_authority" in ship else 1.0
	if ship.current_speed < 0.0 and "reverse_rudder_turn_authority_mult" in ship:
		turn_authority *= float(ship.reverse_rudder_turn_authority_mult)
	if ship.has_method("get_ramming_boost_turn_multiplier"):
		turn_authority *= float(ship.call("get_ramming_boost_turn_multiplier"))
	var direction_sign := -1.0 if ship.current_speed < 0.0 else 1.0
	var actual_turn = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * turn_authority * direction_sign * delta
	ship.rotation.y -= deg_to_rad(actual_turn)

static func calculate_sail_speed(ship) -> float:
	if not is_instance_valid(ship._cached_wind_manager) or not ship._cached_wind_manager.has_method("get_wind_direction") or not ship._cached_wind_manager.has_method("get_wind_strength"):
		return 0.0
	var sail_drive_ratio: float = get_sail_drive_ratio(ship)
	var wind_dir: Vector2 = ship._cached_wind_manager.get_wind_direction()
	var wind_str: float = ship._cached_wind_manager.get_wind_strength()
	var wind_speed_mult: float = _calculate_wind_speed_multiplier(ship._cached_wind_manager, wind_str)
	var ship_angle_rad: float = ship.rotation.y
	var sail_world_rad: float = ship_angle_rad - deg_to_rad(ship.sail_angle)
	var sail_normal: Vector2 = -Vector2(sin(sail_world_rad), cos(sail_world_rad))
	var dot_prod: float = wind_dir.dot(sail_normal)
	var wind_force: float = max(0.0, dot_prod)
	var ship_forward := Vector2(-sin(ship_angle_rad), -cos(ship_angle_rad))
	var forward_component: float = sail_normal.dot(ship_forward)
	var trim_drive: float = wind_force * max(0.0, forward_component)
	var wind_along_ship: float = wind_dir.dot(ship_forward)
	var sail_trim_quality: float = _calculate_sail_trim_quality(ship, wind_dir, ship_angle_rad)
	var broad_angle_drive: float = _calculate_broad_sail_drive(wind_along_ship, trim_drive, sail_trim_quality)
	var thrust: float = broad_angle_drive * sail_drive_ratio
	var minimum_thrust: float = get_misaligned_sail_min_thrust(ship, sail_drive_ratio)
	var effective_thrust: float = maxf(thrust, minimum_thrust)
	ship._current_wind_intake = clampf(maxf(wind_force, broad_angle_drive) * sail_drive_ratio, 0.0, 1.0)
	if Input.is_action_just_pressed("ui_accept"):
		print("=== Physics Debug ===")
		print("Wind Dir: ", wind_dir)
		print("Wind Strength: ", wind_str)
		print("Wind Speed Mult: ", wind_speed_mult)
		print("Sail Angle: ", ship.sail_angle, " deg")
		print("Sail Drive Ratio: ", sail_drive_ratio)
		print("Sail Arrow (Normal): ", sail_normal)
		print("Ship Forward: ", ship_forward)
		print("Dot Product (wind·sail): ", dot_prod)
		print("Wind Force: ", wind_force)
		print("Forward Component: ", forward_component)
		print("Wind Along Ship: ", wind_along_ship)
		print("Trim Drive: ", trim_drive)
		print("Sail Trim Quality: ", sail_trim_quality)
		print("Broad Angle Drive: ", broad_angle_drive)
		print("Thrust: ", thrust)
		print("Minimum Thrust: ", minimum_thrust)
		print("Effective Thrust: ", effective_thrust)
		print("Current Speed: ", ship.current_speed)
		print("=====================")
	return effective_thrust * ship.max_speed * wind_speed_mult * ship.sail_efficiency_mult

static func _calculate_broad_sail_drive(wind_along_ship: float, trim_drive: float, sail_trim_quality: float = 1.0) -> float:
	var downwind_drive: float = smoothstep(SAIL_DOWNWIND_START, SAIL_DOWNWIND_FULL, wind_along_ship)
	var tailwind_drive: float = smoothstep(SAIL_TAILWIND_BONUS_START, SAIL_TAILWIND_BONUS_FULL, wind_along_ship)
	var broad_reach_drive: float = smoothstep(SAIL_BROAD_REACH_START, SAIL_BROAD_REACH_FULL, wind_along_ship)
	broad_reach_drive *= 1.0 - smoothstep(SAIL_BROAD_REACH_FADE_START, SAIL_BROAD_REACH_FADE_FULL, wind_along_ship)
	var beam_reach_drive: float = smoothstep(SAIL_BEAM_REACH_START, SAIL_BEAM_REACH_FULL, wind_along_ship)
	beam_reach_drive *= 1.0 - smoothstep(SAIL_BEAM_REACH_FADE_START, SAIL_BEAM_REACH_FADE_FULL, wind_along_ship)
	var side_wind_component: float = sqrt(maxf(0.0, 1.0 - wind_along_ship * wind_along_ship))
	var reach_boost: float = smoothstep(SAIL_REACH_BOOST_START, SAIL_REACH_BOOST_FULL, wind_along_ship)
	reach_boost *= 1.0 - smoothstep(SAIL_REACH_BOOST_FADE_START, SAIL_REACH_BOOST_FADE_FULL, wind_along_ship)
	reach_boost *= side_wind_component * SAIL_REACH_BOOST_WEIGHT
	var angle_drive: float = (
		downwind_drive * SAIL_DOWNWIND_WEIGHT
		+ tailwind_drive * SAIL_TAILWIND_WEIGHT
		+ broad_reach_drive * SAIL_BROAD_REACH_WEIGHT
		+ beam_reach_drive * SAIL_BEAM_REACH_WEIGHT
		+ reach_boost
	)
	angle_drive *= clampf(sail_trim_quality, 0.0, 1.0)
	return clampf(maxf(trim_drive, angle_drive), 0.0, SAIL_REACH_DRIVE_CAP)

static func _calculate_sail_trim_quality(ship, wind_dir: Vector2, ship_angle_rad: float) -> float:
	var wind_angle: float = rad_to_deg(atan2(wind_dir.x, -wind_dir.y))
	var ship_angle_ccw: float = rad_to_deg(ship_angle_rad)
	var rel_wind_angle: float = wrapf(wind_angle + ship_angle_ccw, -180.0, 180.0)
	var ideal_sail_angle: float = clamp(rel_wind_angle / 2.0, -90.0, 90.0)
	var sail_angle_value: float = float(ship.sail_angle) if "sail_angle" in ship else ideal_sail_angle
	var trim_error: float = absf(wrapf(sail_angle_value - ideal_sail_angle, -180.0, 180.0))
	var quality_drop: float = smoothstep(SAIL_TRIM_ERROR_GOOD_DEG, SAIL_TRIM_ERROR_BAD_DEG, trim_error)
	return lerpf(1.0, SAIL_TRIM_QUALITY_FLOOR, quality_drop)

static func _calculate_wind_speed_multiplier(wind_manager, wind_strength: float) -> float:
	var min_strength := WIND_STRENGTH_DEFAULT_MIN
	var max_strength := WIND_STRENGTH_DEFAULT_MAX
	if is_instance_valid(wind_manager):
		var configured_min = wind_manager.get("min_wind_strength")
		var configured_max = wind_manager.get("max_wind_strength")
		if configured_min != null:
			min_strength = float(configured_min)
		if configured_max != null:
			max_strength = float(configured_max)
	if max_strength <= min_strength + 0.001:
		return lerpf(WIND_SPEED_MULT_MIN, WIND_SPEED_MULT_MAX, clampf(wind_strength, 0.0, 1.0))
	var strength_ratio := clampf((wind_strength - min_strength) / (max_strength - min_strength), 0.0, 1.0)
	return lerpf(WIND_SPEED_MULT_MIN, WIND_SPEED_MULT_MAX, strength_ratio)

static func get_misaligned_sail_min_thrust(ship, sail_drive_ratio: float) -> float:
	if sail_drive_ratio <= 0.001:
		return 0.0
	if "sail_furled" in ship and ship.get("sail_furled") == true:
		return 0.0
	var minimum_ratio := 0.0
	if "misaligned_sail_min_thrust_ratio" in ship and ship.get("misaligned_sail_min_thrust_ratio") != null:
		minimum_ratio = clampf(float(ship.get("misaligned_sail_min_thrust_ratio")), 0.0, 0.35)
	return minimum_ratio * clampf(sail_drive_ratio, 0.0, 1.0)

static func get_sail_drive_ratio(ship) -> float:
	if ship.has_method("get_effective_sail_deployment"):
		return clampf(float(ship.call("get_effective_sail_deployment")), 0.0, 1.0)
	var deployed_ratio := 1.0
	if "sail_deployed_ratio" in ship and ship.get("sail_deployed_ratio") != null:
		deployed_ratio = clampf(float(ship.get("sail_deployed_ratio")), 0.0, 1.0)
	var residual_drive := 0.0
	if "furled_sail_drive_ratio" in ship and ship.get("furled_sail_drive_ratio") != null:
		residual_drive = clampf(float(ship.get("furled_sail_drive_ratio")), 0.0, 1.0)
	return clampf(lerpf(residual_drive, 1.0, deployed_ratio), 0.0, 1.0)

static func get_furled_sail_rowing_efficiency_multiplier(ship) -> float:
	if "sail_furled" in ship and ship.get("sail_furled") == true:
		if "furled_sail_rowing_efficiency_multiplier" in ship and ship.get("furled_sail_rowing_efficiency_multiplier") != null:
			return maxf(1.0, float(ship.get("furled_sail_rowing_efficiency_multiplier")))
	return 1.0

static func get_furled_sail_rowing_speed_bonus(ship) -> float:
	if "sail_furled" in ship and ship.get("sail_furled") == true:
		if "furled_sail_rowing_speed_bonus" in ship and ship.get("furled_sail_rowing_speed_bonus") != null:
			return maxf(0.0, float(ship.get("furled_sail_rowing_speed_bonus")))
	return 0.0

static func get_furled_sail_rowing_stamina_cost_multiplier(ship) -> float:
	if "sail_furled" in ship and ship.get("sail_furled") == true:
		if "furled_sail_rowing_stamina_cost_multiplier" in ship and ship.get("furled_sail_rowing_stamina_cost_multiplier") != null:
			return clampf(float(ship.get("furled_sail_rowing_stamina_cost_multiplier")), 0.0, 1.0)
	return 1.0

static func _get_rowing_direction(ship) -> int:
	if "rowing_direction" in ship and int(ship.rowing_direction) < 0:
		return -1
	return 1

static func update_oar_visual(ship, delta: float) -> void:
	var left_oars := _get_oar_pivots(ship, true)
	var right_oars := _get_oar_pivots(ship, false)
	if left_oars.is_empty() and right_oars.is_empty():
		return
	var is_exhausted_rowing := false
	var is_actively_rowing: bool = ship.is_rowing
	var is_moving_fast: bool = absf(ship.current_speed) > 1.0
	if is_actively_rowing or is_exhausted_rowing or is_moving_fast:
		var row_speed = 2.2 if is_actively_rowing else (1.45 if is_exhausted_rowing else 1.2)
		if _get_rowing_direction(ship) < 0:
			row_speed *= -0.72
		ship._oar_time += delta * row_speed
		for i in range(left_oars.size()):
			_apply_sculling_oar_motion(left_oars[i], ship._oar_time + float(i) * 0.24, 1.0)
		for i in range(right_oars.size()):
			_apply_sculling_oar_motion(right_oars[i], ship._oar_time + float(i) * 0.24 + 0.12, -1.0)
	else:
		for pivot in left_oars:
			_relax_oar_pivot(pivot, delta)
		for pivot in right_oars:
			_relax_oar_pivot(pivot, delta)

static func _get_oar_pivots(ship, left_side: bool) -> Array:
	var pivots: Array = ship.oar_pivots_left if left_side and "oar_pivots_left" in ship else []
	if not left_side:
		pivots = ship.oar_pivots_right if "oar_pivots_right" in ship else []
	if not pivots.is_empty():
		return pivots
	var fallback: Node3D = ship.oar_pivot_left if left_side else ship.oar_pivot_right
	return [fallback] if is_instance_valid(fallback) else []

static func _apply_sculling_oar_motion(pivot: Node3D, phase: float, side_sign: float) -> void:
	if not is_instance_valid(pivot):
		return
	var sweep_angle := sin(phase) * 0.34
	var lift_angle := cos(phase * 2.0) * 0.055 - 0.025
	var feather_angle := sin(phase + PI * 0.35) * 0.16
	pivot.rotation.x = lift_angle
	pivot.rotation.y = feather_angle * side_sign
	pivot.rotation.z = sweep_angle * side_sign

static func _relax_oar_pivot(pivot: Node3D, delta: float) -> void:
	if not is_instance_valid(pivot):
		return
	pivot.rotation.x = lerp_angle(pivot.rotation.x, 0.0, delta * 2.0)
	pivot.rotation.y = lerp_angle(pivot.rotation.y, 0.0, delta * 2.0)
	pivot.rotation.z = lerp_angle(pivot.rotation.z, 0.0, delta * 2.0)

static func update_rowing_stamina(ship, _delta: float) -> void:
	ship.rowing_locked = false
	ship.rowing_stamina = ship.max_rowing_stamina
