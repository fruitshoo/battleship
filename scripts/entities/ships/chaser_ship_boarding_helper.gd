extends RefCounted
class_name ChaserShipBoardingHelper

static func process_boarding(ship, delta: float) -> void:
	if not is_instance_valid(ship.boarding_target):
		ship.die()
		return
	var target_pos = ship.boarding_target.global_position
	var flat_to_target = target_pos - ship.global_position
	flat_to_target.y = 0.0
	var dist_to_target = flat_to_target.length()

	var look_dir = flat_to_target.normalized() if dist_to_target > 0.001 else Vector3.FORWARD
	var target_rot = atan2(-look_dir.x, -look_dir.z)
	ship.rotation.y = lerp_angle(ship.rotation.y, target_rot, delta * 2.0)

	var desired_boarding_speed := 0.0
	if dist_to_target > (ship.max_boarding_distance - 0.6):
		desired_boarding_speed = clamp((dist_to_target - (ship.max_boarding_distance - 0.6)) * 1.6, 1.1, ship.move_speed * 0.9)
	elif dist_to_target > 6.5:
		desired_boarding_speed = 0.9
	ship.current_speed = move_toward(ship.current_speed, desired_boarding_speed, ship.acceleration * 2.0 * delta)

	var approach_velocity = look_dir * ship.current_speed
	var pull_force = ship._calculate_boarding_pull()
	var prev_pos = ship.global_position
	var next_pos = prev_pos + (approach_velocity + pull_force * delta) * delta
	if is_instance_valid(ship.boarding_target):
		next_pos = apply_ship_collision_guard(ship, ship.boarding_target, prev_pos, next_pos, 0.975, approach_velocity.length())
	next_pos = apply_neighbor_ship_guards(ship, prev_pos, next_pos, ship.boarding_target)
	ship.global_position = next_pos

	ship._apply_bobbing_effect()
	ship._process_boarding_common(delta)


static func apply_neighbor_ship_guards(ship, prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null) -> Vector3:
	var corrected_pos = proposed_pos
	var neighbors = ship.get_ships_cached(ship.get_tree())
	var check_count = 0

	for other in neighbors:
		if other == ship or not is_instance_valid(other):
			continue
		if other == excluded_ship:
			continue
		if other.has_method("is_sinking_or_dying") and other.is_sinking_or_dying():
			continue
		if bool(other.get_meta("derelict_nonblocking", false)):
			continue

		var use_support_guard: bool = _is_support_fleet_pair(ship, other)
		var safe_ratio: float = 0.84 if use_support_guard else 0.99
		var probe_ratio: float = 1.08 if use_support_guard else 1.25
		var safe_probe = ship.get_collision_distance_to(other) * probe_ratio
		var diff = corrected_pos - other.global_position
		diff.y = 0.0
		if diff.length_squared() > safe_probe * safe_probe:
			continue

		var ship_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else "enemy"
		var other_team: String = other.get_team_tag() if other.has_method("get_team_tag") else "enemy"
		var emit_collision_event: bool = ship_team != other_team
		corrected_pos = apply_ship_collision_guard(ship, other, prev_pos, corrected_pos, safe_ratio, ship.current_speed, emit_collision_event)
		check_count += 1
		if check_count >= 6:
			break

	return corrected_pos


static func apply_ship_collision_guard(ship, other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = 0.94, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	if not is_instance_valid(other_ship):
		return proposed_pos
	if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
		return proposed_pos
	if bool(other_ship.get_meta("derelict_nonblocking", false)):
		return proposed_pos

	var target_pos = other_ship.global_position
	var safe_dist = ship.get_collision_distance_to(other_ship) * safe_ratio
	if safe_dist <= 0.01:
		return proposed_pos

	var from_2d = Vector2(prev_pos.x - target_pos.x, prev_pos.z - target_pos.z)
	var to_2d = Vector2(proposed_pos.x - target_pos.x, proposed_pos.z - target_pos.z)
	var move_2d = to_2d - from_2d
	var a = move_2d.dot(move_2d)

	if a > 0.00001:
		var b = 2.0 * from_2d.dot(move_2d)
		var c = from_2d.dot(from_2d) - safe_dist * safe_dist
		if c > 0.0:
			var disc = b * b - 4.0 * a * c
			if disc >= 0.0:
				var sqrt_disc = sqrt(disc)
				var t = (-b - sqrt_disc) / (2.0 * a)
				if t >= 0.0 and t <= 1.0:
					var hit_t = maxf(0.0, t - 0.02)
					var hit_pos = prev_pos.lerp(proposed_pos, hit_t)
					var n2 = Vector2(hit_pos.x - target_pos.x, hit_pos.z - target_pos.z)
					if n2.length_squared() < 0.0001:
						n2 = Vector2(-sin(ship.rotation.y), -cos(ship.rotation.y))
					n2 = n2.normalized()
					hit_pos.x = target_pos.x + n2.x * safe_dist
					hit_pos.z = target_pos.z + n2.y * safe_dist
					if emit_collision_event:
						emit_guarded_collision(ship, other_ship, impact_speed_hint)
					soften_collision_speed(ship)
					return hit_pos

	var diff = proposed_pos - target_pos
	diff.y = 0.0
	var dist = diff.length()
	if dist < safe_dist:
		var n = diff.normalized() if dist > 0.001 else Vector3(-sin(ship.rotation.y), 0.0, -cos(ship.rotation.y))
		proposed_pos.x = target_pos.x + n.x * safe_dist
		proposed_pos.z = target_pos.z + n.z * safe_dist
		if emit_collision_event:
			emit_guarded_collision(ship, other_ship, impact_speed_hint)
		soften_collision_speed(ship)

	return proposed_pos


static func emit_guarded_collision(ship, other_ship: Node3D, impact_speed_hint: float) -> void:
	if not is_instance_valid(other_ship):
		return
	var can_board: bool = ship.has_method("can_board_targets") and ship.can_board_targets()
	var current_target: Node3D = ship.get_target_ship() if ship.has_method("get_target_ship") else null
	if can_board and current_target == other_ship:
		var rel_vector: Vector3 = ship.global_position - other_ship.global_position
		rel_vector.y = 0.0
		var target_forward: Vector3 = -other_ship.global_transform.basis.z
		target_forward.y = 0.0
		if target_forward.length_squared() > 0.001:
			target_forward = target_forward.normalized()
			var target_right: Vector3 = target_forward.cross(Vector3.UP).normalized()
			var rel_side: float = rel_vector.dot(target_right)
			var side_sign: float = float(ship.get_meta("boarding_side_sign", 0.0))
			if absf(side_sign) < 0.5:
				side_sign = 1.0 if rel_side >= 0.0 else -1.0
			ship.set_meta("boarding_side_sign", side_sign)
		ship.set_meta("post_impact_follow_timer", 2.1)
	var impact_speed = maxf(impact_speed_hint, ship.min_ramming_speed * 0.72)
	ship.apply_ramming_damage(other_ship, impact_speed)
	if other_ship.has_method("apply_ramming_damage"):
		other_ship.call("apply_ramming_damage", ship, impact_speed)


static func soften_collision_speed(ship) -> void:
	ship.current_speed = min(ship.current_speed, ship.move_speed * 0.84)


static func _is_support_fleet_pair(ship, other_ship: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return false
	if (ship.has_method("is_player_team") and not ship.is_player_team()) or (other_ship.has_method("is_player_team") and not other_ship.is_player_team()):
		return false
	return bool(ship.get_meta("support_fleet_ship", false)) and bool(other_ship.get_meta("support_fleet_ship", false))
