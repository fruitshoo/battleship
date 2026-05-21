extends RefCounted
class_name AIShipBoardingHelper

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")


const BOARDING_MOTION_SETTLE_DURATION := 1.35
const LATCHED_CORRECTION_BLEND := 0.42
const LATCHED_PULL_BLEND := 0.62
const BOARDING_CONTACT_DISTANCE_PAD := 0.85
const BOARDING_CONTACT_ANCHOR_EDGE_MARGIN := 0.18
const NEIGHBOR_GUARD_BROAD_PHASE_SCALE := 1.35
const NEIGHBOR_GUARD_BROAD_PHASE_PAD := 1.5

static func process_boarding(ship, delta: float) -> void:
	if not is_instance_valid(ship.boarding_target):
		if ship.get_team_tag() == "player":
			if ship.has_method("_cancel_boarding"):
				ship._cancel_boarding()
			else:
				ship.is_boarding = false
			return
		ship.die()
		return
	var target_pos = ship.boarding_target.global_position
	var flat_to_target = target_pos - ship.global_position
	flat_to_target.y = 0.0
	var dist_to_target = flat_to_target.length()
	var rope_link_active: bool = _has_active_boarding_rope_link(ship, ship.boarding_target)
	if dist_to_target > _get_effective_boarding_distance(ship, ship.boarding_target) and not rope_link_active:
		ship._process_boarding_common(delta)
		ship._apply_bobbing_effect()
		return

	var motion := _build_boarding_motion(ship, ship.boarding_target, target_pos, flat_to_target, dist_to_target)
	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(ship)
	var motion_settle: float = _update_motion_settle(ship, delta)
	var heading_dir: Vector3 = ShipBoardingMotion.get_heading_dir(motion)
	var target_rot = atan2(-heading_dir.x, -heading_dir.z)
	var turn_response: float = _get_boarding_turn_response(contact_mode, ShipBoardingMotion.is_parallel_hold(motion), motion_settle)
	ship.rotation.y = lerp_angle(ship.rotation.y, target_rot, minf(delta * turn_response, 1.0))

	var desired_boarding_speed: float = ShipBoardingMotion.get_desired_speed(motion)
	var speed_change_rate: float = ship.acceleration if desired_boarding_speed > ship.current_speed else ship.deceleration
	speed_change_rate *= lerpf(0.78, 1.12, motion_settle)
	ship.current_speed = move_toward(ship.current_speed, desired_boarding_speed, speed_change_rate * delta)

	var correction_velocity: Vector3 = ShipBoardingMotion.get_correction_velocity(motion)
	var correction_blend: float = lerpf(0.72, 1.0, motion_settle)
	if rope_link_active:
		correction_blend *= LATCHED_CORRECTION_BLEND
	correction_velocity *= correction_blend
	var approach_velocity: Vector3 = heading_dir * ship.current_speed + correction_velocity
	var pull_blend: float = LATCHED_PULL_BLEND if rope_link_active else lerpf(0.25, 0.7, motion_settle)
	var pull_velocity = ship._calculate_boarding_pull_velocity(delta) * pull_blend
	var prev_pos = ship.global_position
	var next_pos = prev_pos + (approach_velocity + pull_velocity) * delta
	if is_instance_valid(ship.boarding_target):
		var guard_ratio: float = 0.92
		next_pos = apply_ship_collision_guard(ship, ship.boarding_target, prev_pos, next_pos, guard_ratio, approach_velocity.length())
	next_pos = apply_neighbor_ship_guards(ship, prev_pos, next_pos, ship.boarding_target)
	ship.global_position = next_pos

	ship._apply_bobbing_effect()
	ship._process_boarding_common(delta)


static func _has_active_boarding_rope_link(ship, target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if ship.has_method("has_boarding_rope_link_to"):
		return ship.call("has_boarding_rope_link_to", target_ship) == true
	return ship.get("_initial_rope_deployed") == true


static func _get_effective_boarding_distance(ship, target_ship: Node3D) -> float:
	if not is_instance_valid(target_ship):
		return ship.max_boarding_distance
	if not ship.has_method("get_collision_distance_to"):
		return ship.max_boarding_distance
	var contact_distance: float = float(ship.call("get_collision_distance_to", target_ship))
	return maxf(ship.max_boarding_distance, contact_distance + BOARDING_CONTACT_DISTANCE_PAD)


static func store_boarding_contact_anchor(ship, target_ship: Node3D) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(target_ship):
		return
	var rel_vector: Vector3 = ship.global_position - target_ship.global_position
	rel_vector.y = 0.0
	if rel_vector.length_squared() <= 0.001:
		return
	var contact_dist: float = ship.get_collision_distance_to(target_ship) if ship.has_method("get_collision_distance_to") else rel_vector.length()
	var contact_world: Vector3 = target_ship.global_position + rel_vector.normalized() * minf(rel_vector.length(), maxf(0.01, contact_dist * 0.5))
	var anchor_local: Vector3 = target_ship.to_local(contact_world)
	var deck_half: Vector2 = _get_target_deck_half_extents(target_ship)
	if deck_half.x > 0.01 and deck_half.y > 0.01:
		var side_limit: float = maxf(0.12, deck_half.x * (1.0 - BOARDING_CONTACT_ANCHOR_EDGE_MARGIN))
		var length_limit: float = maxf(0.18, deck_half.y * (1.0 - BOARDING_CONTACT_ANCHOR_EDGE_MARGIN))
		anchor_local.x = clampf(anchor_local.x, -side_limit, side_limit)
		anchor_local.z = clampf(anchor_local.z, -length_limit, length_limit)
	if target_ship.get("deck_height") != null:
		anchor_local.y = float(target_ship.get("deck_height"))
	ShipBoardingMetaHelper.set_contact_anchor_local(ship, anchor_local)


static func _get_target_deck_half_extents(target_ship: Node3D) -> Vector2:
	if is_instance_valid(target_ship) and target_ship.has_method("get_deck_half_extents"):
		var deck_half: Variant = target_ship.call("get_deck_half_extents")
		if typeof(deck_half) == TYPE_VECTOR2:
			return deck_half as Vector2
	if is_instance_valid(target_ship) and target_ship.has_method("get_collision_half_extents"):
		var collision_half: Variant = target_ship.call("get_collision_half_extents")
		if typeof(collision_half) == TYPE_VECTOR2:
			return collision_half as Vector2
	return Vector2(2.5, 4.0)


static func _update_motion_settle(ship, delta: float) -> float:
	var timer: float = ShipBoardingMetaHelper.get_motion_settle_timer(ship) + delta
	ShipBoardingMetaHelper.set_motion_settle_timer(ship, timer)
	var t: float = clampf(timer / BOARDING_MOTION_SETTLE_DURATION, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _get_boarding_turn_response(contact_mode: String, parallel_hold: bool, motion_settle: float) -> float:
	var max_response: float = 1.25 if parallel_hold else 0.95
	if contact_mode == ShipBoardingMetaHelper.CONTACT_HEAD_ON:
		max_response = 0.82
	elif contact_mode == ShipBoardingMetaHelper.CONTACT_CLEANUP:
		max_response = 0.72
	return lerpf(0.45, max_response, motion_settle)


static func _build_boarding_motion(ship, target_ship: Node3D, target_pos: Vector3, flat_to_target: Vector3, dist_to_target: float) -> Dictionary:
	var fallback_dir: Vector3 = flat_to_target.normalized() if dist_to_target > 0.001 else Vector3.FORWARD
	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(ship)
	var parallel_hold: bool = contact_mode == ShipBoardingMetaHelper.CONTACT_SIDE
	if contact_mode.is_empty() and ship.has_method("_is_side_boarding_approach"):
		parallel_hold = ship.call("_is_side_boarding_approach", target_ship) == true
	if not parallel_hold:
		return _build_contact_hold_motion(ship, fallback_dir, dist_to_target)

	var target_forward: Vector3 = -target_ship.global_transform.basis.z
	target_forward.y = 0.0
	if target_forward.length_squared() <= 0.001:
		target_forward = fallback_dir
	else:
		target_forward = target_forward.normalized()
	var target_right: Vector3 = target_forward.cross(Vector3.UP).normalized()
	var rel_vector: Vector3 = ship.global_position - target_pos
	rel_vector.y = 0.0
	var rel_side: float = rel_vector.dot(target_right)
	var side_sign: float = ShipBoardingMetaHelper.get_side_sign(ship)
	if absf(side_sign) < 0.5:
		side_sign = 1.0 if rel_side >= 0.0 else -1.0
		ShipBoardingMetaHelper.set_side_sign(ship, side_sign)

	var collision_dist: float = ship.get_collision_distance_to(target_ship)
	var max_hold_dist: float = maxf(4.0, ship.max_boarding_distance - 0.45)
	var min_hold_dist: float = minf(max_hold_dist, maxf(3.8, collision_dist * 0.68))
	var side_hold_dist: float = clampf(collision_dist * 0.88, min_hold_dist, max_hold_dist)
	var along_offset: float = clampf(rel_vector.dot(target_forward), -0.8, 1.6)
	var desired_point: Vector3 = target_pos + target_right * side_sign * side_hold_dist + target_forward * along_offset
	var correction: Vector3 = desired_point - ship.global_position
	correction.y = 0.0
	var correction_velocity := Vector3.ZERO
	if correction.length_squared() > 0.01:
		correction_velocity = correction.normalized() * minf(ship.move_speed * 0.34, correction.length() * 1.25)

	var target_speed: float = 0.0
	if target_ship.has_method("get_current_speed_value"):
		target_speed = float(target_ship.call("get_current_speed_value"))
	elif "current_speed" in target_ship:
		target_speed = float(target_ship.get("current_speed"))
	var desired_speed: float = clampf(maxf(target_speed * 0.82, 0.6), 0.0, ship.move_speed * 0.6)
	return ShipBoardingMotion.build(target_forward, desired_speed, correction_velocity, true)


static func _build_contact_hold_motion(ship, fallback_dir: Vector3, dist_to_target: float) -> Dictionary:
	var hold_forward: Vector3 = ShipBoardingMetaHelper.get_hold_forward(ship)
	if hold_forward.length_squared() <= 0.001:
		hold_forward = -ship.global_transform.basis.z
		hold_forward.y = 0.0
	if hold_forward.length_squared() <= 0.001:
		hold_forward = fallback_dir
	else:
		hold_forward = hold_forward.normalized()

	var correction_velocity := Vector3.ZERO
	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(ship)
	var target_ship: Node3D = ship.get("boarding_target") as Node3D
	if contact_mode in [ShipBoardingMetaHelper.CONTACT_HEAD_ON, ShipBoardingMetaHelper.CONTACT_CLEANUP] and is_instance_valid(target_ship) and ShipBoardingMetaHelper.has_contact_anchor(ship):
		var anchor_local: Vector3 = ShipBoardingMetaHelper.get_contact_anchor_local(ship)
		var anchor_global: Vector3 = target_ship.to_global(anchor_local)
		var to_anchor: Vector3 = anchor_global - ship.global_position
		to_anchor.y = 0.0
		if to_anchor.length_squared() > 0.01:
			var anchor_correction_speed: float = clampf(to_anchor.length() * 1.45, 0.0, ship.move_speed * 0.42)
			correction_velocity = to_anchor.normalized() * anchor_correction_speed
	else:
		var desired_contact_dist: float = ship.max_boarding_distance - 0.75
		if dist_to_target > desired_contact_dist and fallback_dir.length_squared() > 0.001:
			var correction_speed: float = clampf((dist_to_target - desired_contact_dist) * 1.05, 0.0, ship.move_speed * 0.32)
			correction_velocity = fallback_dir.normalized() * correction_speed

	return ShipBoardingMotion.build(hold_forward, 0.0, correction_velocity, false)


static func apply_neighbor_ship_guards(ship, prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null) -> Vector3:
	var corrected_pos = proposed_pos
	var neighbors = ship.get_ships_cached(ship.get_tree())
	var check_count = 0
	var ship_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else "enemy"
	var ship_guard_radius := _get_neighbor_guard_broad_radius(ship)

	for other in neighbors:
		if other == ship or not is_instance_valid(other):
			continue
		if other == excluded_ship:
			continue
		if other.has_method("is_sinking_or_dying") and other.is_sinking_or_dying():
			continue
		if other.get_meta("derelict_nonblocking", false) == true:
			continue

		var diff = corrected_pos - other.global_position
		diff.y = 0.0
		var broad_probe := (ship_guard_radius + _get_neighbor_guard_broad_radius(other)) * NEIGHBOR_GUARD_BROAD_PHASE_SCALE + NEIGHBOR_GUARD_BROAD_PHASE_PAD
		if diff.length_squared() > broad_probe * broad_probe:
			continue

		var use_support_guard: bool = _is_support_fleet_pair(ship, other)
		var safe_ratio: float = 0.84 if use_support_guard else 0.99
		var probe_ratio: float = 1.08 if use_support_guard else 1.25
		var safe_probe = ship.get_collision_distance_to(other) * probe_ratio
		if diff.length_squared() > safe_probe * safe_probe:
			continue

		var other_team: String = other.get_team_tag() if other.has_method("get_team_tag") else "enemy"
		var emit_collision_event: bool = ship_team != other_team
		corrected_pos = apply_ship_collision_guard(ship, other, prev_pos, corrected_pos, safe_ratio, ship.current_speed, emit_collision_event)
		check_count += 1
		if check_count >= 6:
			break

	return corrected_pos


static func _get_neighbor_guard_broad_radius(ship) -> float:
	var base_radius := NodeContractHelper.get_base_collision_radius_value(ship)
	var width_mult := NodeContractHelper.get_collision_width_multiplier_value(ship)
	var length_mult := NodeContractHelper.get_collision_length_multiplier_value(ship)
	return maxf(0.5, base_radius * maxf(width_mult, length_mult))


static func apply_ship_collision_guard(ship, other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = 0.94, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	if not is_instance_valid(other_ship):
		return proposed_pos
	if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
		return proposed_pos
	if other_ship.get_meta("derelict_nonblocking", false) == true:
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
					var target_hit_pos: Vector3 = hit_pos
					target_hit_pos.x = target_pos.x + n2.x * safe_dist
					target_hit_pos.z = target_pos.z + n2.y * safe_dist
					var correction: Vector3 = target_hit_pos - hit_pos
					hit_pos += correction * _get_guard_correction_share(ship, other_ship, correction.length())
					if emit_collision_event:
						emit_guarded_collision(ship, other_ship, impact_speed_hint)
					soften_collision_speed(ship, other_ship)
					return hit_pos

	var diff = proposed_pos - target_pos
	diff.y = 0.0
	var dist = diff.length()
	if dist < safe_dist:
		var n = diff.normalized() if dist > 0.001 else Vector3(-sin(ship.rotation.y), 0.0, -cos(ship.rotation.y))
		var target_proposed_pos: Vector3 = proposed_pos
		target_proposed_pos.x = target_pos.x + n.x * safe_dist
		target_proposed_pos.z = target_pos.z + n.z * safe_dist
		var correction: Vector3 = target_proposed_pos - proposed_pos
		proposed_pos += correction * _get_guard_correction_share(ship, other_ship, correction.length())
		if emit_collision_event:
			emit_guarded_collision(ship, other_ship, impact_speed_hint)
		soften_collision_speed(ship, other_ship)

	return proposed_pos


static func _get_guard_correction_share(ship, other_ship: Node3D, correction_length: float) -> float:
	if ship.get("boarding_target") == other_ship:
		return 1.0
	return BaseShipCollisionHelper.get_guard_correction_share(ship, other_ship, correction_length)


static func emit_guarded_collision(ship, other_ship: Node3D, impact_speed_hint: float) -> void:
	if not is_instance_valid(other_ship):
		return
	var can_board: bool = ship.has_method("can_board_targets") and ship.can_board_targets()
	var current_target: Node3D = ship.get_target_ship() if ship.has_method("get_target_ship") else null
	if can_board and current_target == other_ship:
		store_boarding_contact_anchor(ship, other_ship)
		var rel_vector: Vector3 = ship.global_position - other_ship.global_position
		rel_vector.y = 0.0
		var target_forward: Vector3 = -other_ship.global_transform.basis.z
		target_forward.y = 0.0
		if target_forward.length_squared() > 0.001:
			target_forward = target_forward.normalized()
			var target_right: Vector3 = target_forward.cross(Vector3.UP).normalized()
			var rel_side: float = rel_vector.dot(target_right)
			var side_sign: float = ShipBoardingMetaHelper.get_side_sign(ship)
			if absf(side_sign) < 0.5:
				side_sign = 1.0 if rel_side >= 0.0 else -1.0
			ShipBoardingMetaHelper.set_side_sign(ship, side_sign)
		ShipBoardingMetaHelper.set_post_impact_follow_timer(ship, 2.1)
		if ship.has_method("_mark_boarding_impact"):
			ship.call("_mark_boarding_impact", other_ship)
	var impact_speed = maxf(impact_speed_hint, ship.min_ramming_speed * 0.72)
	BaseShipCollisionHelper.try_spawn_strong_collision_effects(ship, other_ship, impact_speed)
	if ship.has_method("apply_ramming_damage"):
		ship.apply_ramming_damage(other_ship, impact_speed)
	if other_ship.has_method("apply_ramming_damage"):
		other_ship.call("apply_ramming_damage", ship, impact_speed)


static func soften_collision_speed(ship, other_ship: Node3D = null) -> void:
	var max_ratio := 0.84
	if is_instance_valid(other_ship):
		var my_mass := BaseShipCollisionHelper.get_ship_mass_scale(ship)
		var other_mass := BaseShipCollisionHelper.get_ship_mass_scale(other_ship)
		max_ratio = clampf(0.84 - maxf(other_mass - my_mass, 0.0) * 0.08, 0.55, 0.88)
	ship.current_speed = min(ship.current_speed, ship.move_speed * max_ratio)


static func _is_support_fleet_pair(ship, other_ship: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return false
	if (ship.has_method("is_player_team") and not ship.is_player_team()) or (other_ship.has_method("is_player_team") and not other_ship.is_player_team()):
		return false
	return PlayerFleetRoleHelper.is_support_ship(ship) and PlayerFleetRoleHelper.is_support_ship(other_ship)
