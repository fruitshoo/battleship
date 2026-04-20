extends RefCounted
class_name ShipBoardingNavigationHelper



static func get_ship_deck_half_extents(ship) -> Vector2:
	if not is_instance_valid(ship):
		return Vector2(2.0, 3.5)
	if ship.has_method("get_deck_half_extents"):
		var ext: Variant = ship.call("get_deck_half_extents")
		if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
			return ext
	if ship.has_method("get_collision_half_extents"):
		var ext: Variant = ship.call("get_collision_half_extents")
		if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
			return ext
	return Vector2(
		float(ship.get("base_collision_radius")) * float(ship.get("width_multiplier")),
		float(ship.get("base_collision_radius")) * float(ship.get("length_multiplier"))
	)


static func build_side_follow(
	ship,
	target_node: Node3D,
	target_pos: Vector3,
	target_forward: Vector3,
	target_right: Vector3,
	rel_forward: float,
	rel_side: float,
	collision_dist: float,
	dist_to_target: float,
	tight_hold: bool = false
) -> Dictionary:
	var side_sign: float = ShipBoardingMetaHelper.get_side_sign(ship)
	if absf(side_sign) < 0.5:
		side_sign = 1.0 if rel_side >= 0.0 else -1.0
	ShipBoardingMetaHelper.set_side_sign(ship, side_sign)
	ShipBoardingMetaHelper.remove_meta_key(ship, ShipBoardingMetaHelper.KEY_SLOT_ID)

	var my_half_ext: Vector2 = get_ship_deck_half_extents(ship)
	var target_half_ext: Vector2 = get_ship_deck_half_extents(target_node)
	var combined_half_width: float = my_half_ext.x + target_half_ext.x
	var side_offset_dist: float = clampf(
		maxf(collision_dist * (0.72 if tight_hold else 0.88), combined_half_width * (0.68 if tight_hold else 0.74)),
		maxf(2.9 if tight_hold else 3.1, combined_half_width * (0.54 if tight_hold else 0.60)),
		maxf(8.6, combined_half_width * 1.6)
	)
	var side_anchor: Vector3 = target_pos + target_right * side_sign * side_offset_dist
	var along_track_offset: float
	if tight_hold:
		var target_track_offset: float = 0.75
		along_track_offset = clampf(
			lerpf(rel_forward, target_track_offset, 0.82),
			0.0,
			1.35
		)
	else:
		along_track_offset = clampf(
			(ship.global_position - side_anchor).dot(target_forward),
			-0.35,
			2.4
		)
	var heading_lead: float = 3.5 if tight_hold else 12.0
	var desired_speed_mult: float
	if tight_hold:
		desired_speed_mult = 0.72
		if rel_forward > 2.0:
			desired_speed_mult = 0.56
		elif rel_forward < -0.2:
			desired_speed_mult = 0.88
	else:
		desired_speed_mult = 1.02 if dist_to_target > ship.max_boarding_distance + 1.0 else 0.92
	var desired_point: Vector3 = side_anchor + target_forward * along_track_offset
	var parallel_heading_point: Vector3 = side_anchor + target_forward * (along_track_offset + heading_lead)
	var heading_point: Vector3 = parallel_heading_point
	var to_desired: Vector3 = desired_point - ship.global_position
	to_desired.y = 0.0
	if not tight_hold and to_desired.length_squared() > 0.01:
		var desired_distance: float = to_desired.length()
		var route_heading_point: Vector3 = ship.global_position + to_desired.normalized() * clampf(desired_distance, 4.0, 10.0)
		var align_blend: float = clampf(1.0 - ((desired_distance - 1.8) / 5.5), 0.0, 1.0)
		heading_point = route_heading_point.lerp(parallel_heading_point, align_blend)
	return ShipMovementIntent.build_partial(
		desired_point,
		heading_point,
		desired_speed_mult,
		false if tight_hold else dist_to_target > 10.0,
		"side"
	)


static func build_contact_settle(
	ship,
	target_pos: Vector3,
	target_forward: Vector3,
	target_right: Vector3,
	rel_forward: float,
	rel_side: float,
	collision_dist: float,
	dist_to_target: float
) -> Dictionary:
	var side_sign: float = ShipBoardingMetaHelper.get_side_sign(ship)
	if absf(side_sign) < 0.5:
		side_sign = 1.0 if rel_side >= 0.0 else -1.0
	ShipBoardingMetaHelper.set_side_sign(ship, side_sign)
	ShipBoardingMetaHelper.remove_meta_key(ship, ShipBoardingMetaHelper.KEY_SLOT_ID)

	var current_forward: Vector3 = -ship.global_transform.basis.z
	current_forward.y = 0.0
	if current_forward.length_squared() <= 0.001:
		current_forward = target_forward
	else:
		current_forward = current_forward.normalized()

	var desired_side: float = side_sign * clampf(collision_dist * 0.86, 3.4, maxf(8.8, collision_dist * 0.95))
	var desired_along: float = clampf(rel_forward, -0.7, 1.4)
	var desired_point: Vector3 = target_pos + target_right * desired_side + target_forward * desired_along
	var correction: Vector3 = desired_point - ship.global_position
	correction.y = 0.0
	if correction.length() < 0.45:
		desired_point = ship.global_position + current_forward * 2.0

	return ShipMovementIntent.build_partial(
		desired_point,
		ship.global_position + current_forward * 9.0,
		0.56 if dist_to_target > ship.max_boarding_distance else 0.34,
		false,
		"contact_settle"
	)


static func build_rear_recovery(
	ship,
	target_node: Node3D,
	target_pos: Vector3,
	target_forward: Vector3,
	target_right: Vector3,
	rel_side: float,
	collision_dist: float,
	dist_to_target: float
) -> Dictionary:
	var side_sign: float = ShipBoardingMetaHelper.get_side_sign(ship)
	if absf(side_sign) < 0.5:
		side_sign = 1.0 if rel_side >= 0.0 else -1.0
	ShipBoardingMetaHelper.set_side_sign(ship, side_sign)
	ShipBoardingMetaHelper.set_slot_id(ship, ShipBoardingMetaHelper.SLOT_REAR_RECOVER_SIDE)

	var my_half_ext: Vector2 = get_ship_deck_half_extents(ship)
	var target_half_ext: Vector2 = get_ship_deck_half_extents(target_node)
	var combined_half_width: float = my_half_ext.x + target_half_ext.x
	var side_offset_dist: float = clampf(
		maxf(collision_dist * 0.98, combined_half_width * 0.82),
		maxf(3.2, combined_half_width * 0.68),
		maxf(9.4, combined_half_width * 1.75)
	)
	var track_offset: float = clampf(target_half_ext.y * 0.12, 0.45, 1.9)
	var side_anchor: Vector3 = target_pos + target_right * side_sign * side_offset_dist
	var desired_point: Vector3 = side_anchor + target_forward * track_offset
	return ShipMovementIntent.build_partial(
		desired_point,
		side_anchor + target_forward * (track_offset + 10.0),
		0.98 if dist_to_target > 9.0 else 0.78,
		dist_to_target > 10.0,
		"rear"
	)
