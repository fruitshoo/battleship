extends RefCounted

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
			force += push_dir * strength * 1.8
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
	var is_exhausted_rowing: bool = ship.is_rowing and ship.rowing_locked
	var is_actively_rowing: bool = ship.is_rowing and not ship.rowing_locked and ship.rowing_stamina > 0.0
	if is_actively_rowing:
		target_speed += ship.rowing_speed
	elif is_exhausted_rowing:
		target_speed += ship.rowing_speed * float(ship.exhausted_rowing_speed_ratio)
	target_speed *= ship.get_shiphandling_multiplier()
	target_speed *= get_boarding_drag_multiplier(ship)
	target_speed *= ship.speed_mult
	var forward = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	if target_speed > ship.current_speed:
		var accel: float = ship.acceleration
		if (is_actively_rowing or is_exhausted_rowing) and "rowing_acceleration_mult" in ship:
			accel *= float(ship.rowing_acceleration_mult)
			if is_exhausted_rowing:
				accel *= 0.75
		ship.current_speed = move_toward(ship.current_speed, target_speed, accel * delta)
	else:
		ship.current_speed = move_toward(ship.current_speed, target_speed, ship.deceleration * delta)
	var velocity = forward * ship.current_speed
	var sep = calculate_separation(ship)
	velocity += sep
	velocity += ship._calculate_boarding_pull() * delta
	velocity += ship._calculate_collision_repulsion() * delta
	ship.position += velocity * delta
	var wake_active = ship.current_speed > 0.5 or sep.length() > 0.2
	var wake_speed_ratio = clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0)
	var wake_turn_ratio = clampf(ship.rudder_angle / 45.0, -1.0, 1.0)
	ship._set_wake_state(wake_active, wake_speed_ratio, wake_turn_ratio, clampf(sep.length() / 2.0, 0.0, 1.0))

static func update_steering(ship, delta: float) -> void:
	if ship.current_speed < 0.1:
		return
	var speed_ratio = ship.current_speed / ship.max_speed
	var turn_authority: float = float(ship.player_rudder_turn_authority) if "player_rudder_turn_authority" in ship else 1.0
	var actual_turn = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * turn_authority * delta
	ship.rotation.y -= deg_to_rad(actual_turn)

static func calculate_sail_speed(ship) -> float:
	if not is_instance_valid(ship._cached_wind_manager) or not ship._cached_wind_manager.has_method("get_wind_direction") or not ship._cached_wind_manager.has_method("get_wind_strength"):
		return 0.0
	var wind_dir: Vector2 = ship._cached_wind_manager.get_wind_direction()
	var wind_str: float = ship._cached_wind_manager.get_wind_strength()
	var ship_angle_rad = ship.rotation.y
	var sail_world_rad = ship_angle_rad - deg_to_rad(ship.sail_angle)
	var sail_normal = -Vector2(sin(sail_world_rad), cos(sail_world_rad))
	var dot_prod = wind_dir.dot(sail_normal)
	var wind_force = max(0.0, dot_prod)
	var ship_forward = Vector2(-sin(ship_angle_rad), -cos(ship_angle_rad))
	var forward_component = sail_normal.dot(ship_forward)
	var thrust = wind_force * max(0.0, forward_component)
	ship._current_wind_intake = wind_force
	if Input.is_action_just_pressed("ui_accept"):
		print("=== Physics Debug ===")
		print("Wind Dir: ", wind_dir)
		print("Sail Angle: ", ship.sail_angle, " deg")
		print("Sail Arrow (Normal): ", sail_normal)
		print("Ship Forward: ", ship_forward)
		print("Dot Product (wind·sail): ", dot_prod)
		print("Wind Force: ", wind_force)
		print("Forward Component: ", forward_component)
		print("Thrust: ", thrust)
		print("Current Speed: ", ship.current_speed)
		print("=====================")
	return thrust * ship.max_speed * wind_str * ship.sail_efficiency_mult * ship.get_shiphandling_multiplier()

static func update_oar_visual(ship, delta: float) -> void:
	var has_oars = ship.oar_pivot_left or ship.oar_pivot_right
	if not has_oars:
		return
	var is_exhausted_rowing: bool = ship.is_rowing and ship.rowing_locked
	var is_actively_rowing: bool = ship.is_rowing and not ship.rowing_locked and ship.rowing_stamina > 0.0
	var is_moving_fast: bool = ship.current_speed > 1.0
	if is_actively_rowing or is_exhausted_rowing or is_moving_fast:
		var row_speed = 2.2 if is_actively_rowing else (1.45 if is_exhausted_rowing else 1.2)
		ship._oar_time += delta * row_speed
		var sweep_angle = sin(ship._oar_time) * 0.2
		var twist_angle = sin(ship._oar_time * 2.0) * 0.1
		if ship.oar_pivot_left:
			ship.oar_pivot_left.rotation.x = sweep_angle
			ship.oar_pivot_left.rotation.z = twist_angle
		if ship.oar_pivot_right:
			ship.oar_pivot_right.rotation.x = sweep_angle
			ship.oar_pivot_right.rotation.z = -twist_angle
	else:
		if ship.oar_pivot_left:
			ship.oar_pivot_left.rotation.x = lerp_angle(ship.oar_pivot_left.rotation.x, 0.0, delta * 2.0)
			ship.oar_pivot_left.rotation.z = lerp_angle(ship.oar_pivot_left.rotation.z, 0.0, delta * 2.0)
		if ship.oar_pivot_right:
			ship.oar_pivot_right.rotation.x = lerp_angle(ship.oar_pivot_right.rotation.x, 0.0, delta * 2.0)
			ship.oar_pivot_right.rotation.z = lerp_angle(ship.oar_pivot_right.rotation.z, 0.0, delta * 2.0)

static func update_rowing_stamina(ship, delta: float) -> void:
	if ship.is_rowing and not ship.rowing_locked and ship.rowing_stamina > 0:
		ship.rowing_stamina -= ship.stamina_drain_rate * delta
		ship.rowing_stamina = max(0.0, ship.rowing_stamina)
		if ship.rowing_stamina <= 0:
			ship.rowing_locked = true
	if ship.rowing_stamina < ship.max_rowing_stamina and (not ship.is_rowing or ship.rowing_locked):
		ship.rowing_stamina += ship.stamina_recovery_rate * delta
		ship.rowing_stamina = min(ship.max_rowing_stamina, ship.rowing_stamina)
		if ship.rowing_locked and ship.rowing_stamina >= ship.stamina_recovery_unlock_threshold:
			ship.rowing_locked = false
