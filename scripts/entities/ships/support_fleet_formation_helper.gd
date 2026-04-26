extends RefCounted
class_name SupportFleetFormationHelper

const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SUPPORT_FLEET_SLOT_ROLE_META := "support_squadron_slot_role"
const SUPPORT_FLEET_SQUADRON_META := "support_squadron_id"

const ROLE_SCREEN_LEAD := "screen_lead"
const ROLE_SCREEN_FLANK := "screen_flank"
const ROLE_RESCUE_REAR := "rescue_rear"
const ROLE_ARTILLERY_LEAD := "artillery_lead"
const ROLE_ARTILLERY_SCREEN_LEFT := "artillery_screen_left"
const ROLE_ARTILLERY_SCREEN_RIGHT := "artillery_screen_right"

const FORMATION_COLUMN := 0
const FORMATION_WING := 1
const FORMATION_WEDGE := 2 # Legacy value, normalized to FORMATION_WING.

const FOLLOW_DISTANCE_PAD := 2.0
const GENERIC_LATERAL_PAD := 1.6
const ARTILLERY_LATERAL_PAD := 2.35
const ROLE_EXTRA_TRAIL_PAD := 1.1


static func get_support_fleet_offset(ship, my_index: int, spacing: float, roster_size: int = -1) -> Vector3:
	var role_name := _get_support_slot_role(ship)
	if role_name.is_empty() or not _is_named_support_role(role_name):
		return _get_generic_support_formation_offset(ship, my_index, spacing, roster_size)

	var formation_value := _get_formation_value(ship)
	var base_spacing := maxf(spacing, _get_ship_spacing_hint(ship))
	var trail_distance := _get_role_spacing_value(base_spacing, role_name, formation_value)
	var lateral_distance := _get_role_lateral_distance(ship, ship.target as Node3D, base_spacing, role_name, formation_value, my_index)
	return Vector3(lateral_distance, 0.0, trail_distance)


static func get_support_join_offset(ship, my_index: int) -> Vector3:
	return get_support_fleet_offset(ship, my_index, 18.0)


static func get_support_lead_ship(ship, minions: Array, my_index: int) -> Node3D:
	if _get_formation_value(ship) == FORMATION_COLUMN:
		return _get_generic_support_lead_ship(ship, minions, my_index)
	if not _is_named_support_role(_get_support_slot_role(ship)):
		return _get_generic_support_lead_ship(ship, minions, my_index)
	var role_anchor := _resolve_role_anchor_ship(ship, minions)
	if is_instance_valid(role_anchor):
		return role_anchor
	return _get_generic_support_lead_ship(ship, minions, my_index)


static func get_support_chain_goal(ship, minions: Array, my_index: int, trailing_distance: float) -> Dictionary:
	var flagship_anchor := _get_flagship_anchor(ship)
	if not is_instance_valid(flagship_anchor):
		return {"position": ship.global_position, "forward": Vector3.FORWARD}

	var role_name := _get_support_slot_role(ship)
	if role_name.is_empty() or not _is_named_support_role(role_name):
		return _get_generic_support_chain_goal(ship, minions, my_index, trailing_distance)

	var anchor_ship := get_support_lead_ship(ship, minions, my_index)
	if not is_instance_valid(anchor_ship):
		return _get_generic_support_chain_goal(ship, minions, my_index, trailing_distance)

	var formation_value := _get_formation_value(ship)
	var anchor_fwd := get_ship_forward_flat(anchor_ship)
	var follow_distance := _get_role_follow_distance(ship, anchor_ship, trailing_distance, role_name, formation_value)
	var anchor_goal := get_trail_goal(anchor_ship, follow_distance, anchor_fwd, "support_trail_points")
	var goal_fwd: Vector3 = anchor_goal.get("forward", anchor_fwd)
	var goal_right := goal_fwd.cross(Vector3.UP)
	goal_right.y = 0.0
	if goal_right.length_squared() <= 0.0001:
		goal_right = Vector3.RIGHT
	else:
		goal_right = goal_right.normalized()
	var lateral_distance := _get_role_lateral_distance(ship, anchor_ship, trailing_distance, role_name, formation_value, my_index)
	var goal_pos: Vector3 = anchor_goal.get("position", ship.global_position) + goal_right * lateral_distance
	goal_pos.y = ship.global_position.y
	return {
		"position": goal_pos,
		"forward": goal_fwd,
	}


static func get_support_join_chain_goal(ship, minions: Array, my_index: int, trailing_distance: float) -> Dictionary:
	var flagship_anchor := _get_flagship_anchor(ship)
	if not is_instance_valid(flagship_anchor):
		return {"position": ship.global_position, "forward": Vector3.FORWARD}

	var flagship_fwd := get_ship_forward_flat(flagship_anchor)
	var stage_distance := maxf(trailing_distance, _get_ship_spacing_hint(ship)) * (float(my_index) + 1.0)
	var stage_goal := get_trail_goal(flagship_anchor, stage_distance, flagship_fwd, "support_trail_points")
	var goal_pos: Vector3 = stage_goal.get("position", flagship_anchor.global_position - flagship_fwd * stage_distance)
	goal_pos.y = ship.global_position.y
	return {
		"position": goal_pos,
		"forward": stage_goal.get("forward", flagship_fwd),
	}


static func should_hold_line_during_free_assist(ship) -> bool:
	if not is_instance_valid(ship):
		return false
	if _get_support_slot_role(ship) == ROLE_ARTILLERY_LEAD:
		return true
	var ship_type_value: Variant = ship.get("ship_type")
	return str(ship_type_value).strip_edges().to_lower() == "panokseon_ally"


static func record_trail_point(node: Node3D, point_distance: float, max_points: int, meta_key: String) -> void:
	if not is_instance_valid(node):
		return
	var points: Array = node.get_meta(meta_key, [])
	var current_pos: Vector3 = node.global_position
	if points.is_empty():
		points.append(current_pos)
	else:
		var last_point: Variant = points[points.size() - 1]
		if last_point is Vector3 and Vector3(last_point).distance_to(current_pos) >= point_distance:
			points.append(current_pos)
	while points.size() > max_points:
		points.remove_at(0)
	node.set_meta(meta_key, points)


static func get_trail_goal(lead_ship: Node3D, trailing_distance: float, fallback_forward: Vector3, meta_key: String) -> Dictionary:
	if not is_instance_valid(lead_ship):
		return {"position": Vector3.ZERO, "forward": fallback_forward}
	var trail_points: Array = lead_ship.get_meta(meta_key, [])
	if trail_points.is_empty():
		return {"position": lead_ship.global_position - fallback_forward * trailing_distance, "forward": fallback_forward}

	var remaining_distance: float = trailing_distance
	var segment_end: Vector3 = lead_ship.global_position
	for i in range(trail_points.size() - 1, -1, -1):
		var trail_point: Variant = trail_points[i]
		if not (trail_point is Vector3):
			continue
		var segment_start: Vector3 = trail_point
		var segment: Vector3 = segment_end - segment_start
		segment.y = 0.0
		var segment_length: float = segment.length()
		if segment_length <= 0.001:
			segment_end = segment_start
			continue
		var segment_forward: Vector3 = segment / segment_length
		if remaining_distance <= segment_length:
			return {
				"position": segment_end - segment_forward * remaining_distance,
				"forward": segment_forward,
			}
		remaining_distance -= segment_length
		segment_end = segment_start

	return {"position": segment_end, "forward": fallback_forward}


static func get_ship_forward_flat(node: Node3D) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.FORWARD
	var fwd: Vector3 = -node.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return fwd.normalized()


static func get_follow_distance(follower_ship: Node3D, lead_ship: Node3D, minimum_spacing: float) -> float:
	if not is_instance_valid(follower_ship) or not is_instance_valid(lead_ship):
		return minimum_spacing
	if follower_ship.has_method("get_collision_distance_to"):
		var safe_follow_distance: float = float(follower_ship.call("get_collision_distance_to", lead_ship)) + FOLLOW_DISTANCE_PAD
		return maxf(minimum_spacing, safe_follow_distance)
	var safe_distance := ShipContactGeometry.get_collision_distance_between(follower_ship, lead_ship) + FOLLOW_DISTANCE_PAD
	return maxf(minimum_spacing, safe_distance)


static func _get_generic_support_chain_goal(ship, minions: Array, my_index: int, trailing_distance: float) -> Dictionary:
	var flagship_anchor := _get_flagship_anchor(ship)
	if not is_instance_valid(flagship_anchor):
		return {"position": ship.global_position, "forward": Vector3.FORWARD}
	var formation_value := _get_formation_value(ship)
	if formation_value != 0:
		var flagship_fwd := get_ship_forward_flat(flagship_anchor)
		var offset: Vector3 = _get_generic_support_formation_offset(ship, my_index, trailing_distance, minions.size())
		var anchor_goal := get_trail_goal(flagship_anchor, maxf(offset.z, 0.0), flagship_fwd, "support_trail_points")
		var anchor_pos: Vector3 = anchor_goal.get("position", flagship_anchor.global_position)
		var anchor_fwd: Vector3 = anchor_goal.get("forward", flagship_fwd)
		var anchor_right: Vector3 = anchor_fwd.cross(Vector3.UP)
		anchor_right.y = 0.0
		if anchor_right.length_squared() <= 0.0001:
			anchor_right = flagship_anchor.global_transform.basis.x
			anchor_right.y = 0.0
		if anchor_right.length_squared() <= 0.0001:
			anchor_right = Vector3.RIGHT
		else:
			anchor_right = anchor_right.normalized()
		var goal_pos: Vector3 = anchor_pos + anchor_right * offset.x
		goal_pos.y = ship.global_position.y
		return {
			"position": goal_pos,
			"forward": anchor_fwd,
		}
	var lead_ship: Node3D = _get_generic_support_lead_ship(ship, minions, my_index)
	var lead_fwd: Vector3 = get_ship_forward_flat(lead_ship)
	var follow_distance: float = get_follow_distance(ship, lead_ship, trailing_distance)
	return get_trail_goal(lead_ship, follow_distance, lead_fwd, "support_trail_points")


static func _get_generic_support_formation_offset(ship, my_index: int, spacing: float, roster_size: int = -1) -> Vector3:
	var formation_value := _get_formation_value(ship)
	var effective_roster_size: int = roster_size if roster_size >= 0 else (my_index + 1)
	var base_spacing: float = maxf(spacing, 0.01)
	if effective_roster_size <= 1:
		return Vector3(0.0, 0.0, base_spacing)
	var row: float = floor(my_index / 2.0) + 1.0
	var has_center_tail: bool = effective_roster_size % 2 == 1 and my_index == effective_roster_size - 1
	if has_center_tail:
		return Vector3(0.0, 0.0, base_spacing * (row + 0.35))
	var side: float = 1.0 if my_index % 2 == 0 else -1.0
	match formation_value:
		FORMATION_WING:
			var lateral: float = base_spacing * 1.18 * row
			var trailing: float = base_spacing * 0.58 + (row - 1.0) * base_spacing * 0.18
			return Vector3(lateral * side, 0.0, trailing)
		_:
			return Vector3(0.0, 0.0, base_spacing + (my_index * base_spacing))


static func _get_generic_support_lead_ship(ship, minions: Array, my_index: int) -> Node3D:
	if my_index <= 0:
		return _get_flagship_anchor(ship)
	for i in range(my_index - 1, -1, -1):
		var candidate = minions[i]
		if is_instance_valid(candidate):
			return candidate
	return _get_flagship_anchor(ship)


static func _resolve_role_anchor_ship(ship, minions: Array) -> Node3D:
	if not is_instance_valid(ship):
		return null
	var flagship_anchor := _get_flagship_anchor(ship)
	var role_name := _get_support_slot_role(ship)
	if not _is_named_support_role(role_name):
		return null
	if _get_formation_value(ship) == FORMATION_WING:
		return flagship_anchor
	if role_name == ROLE_ARTILLERY_SCREEN_LEFT or role_name == ROLE_ARTILLERY_SCREEN_RIGHT:
		var squadron_id := _get_support_squadron_id(ship)
		var lead_ship := _find_squadron_lead(minions, squadron_id)
		if is_instance_valid(lead_ship) and lead_ship != ship:
			return lead_ship
		return flagship_anchor
	if role_name == ROLE_SCREEN_LEAD or role_name == ROLE_SCREEN_FLANK or role_name == ROLE_RESCUE_REAR or role_name == ROLE_ARTILLERY_LEAD:
		return flagship_anchor
	return null


static func _find_squadron_lead(minions: Array, squadron_id: String) -> Node3D:
	for candidate in minions:
		if not is_instance_valid(candidate):
			continue
		if _get_support_slot_role(candidate) != ROLE_ARTILLERY_LEAD:
			continue
		if not squadron_id.is_empty() and _get_support_squadron_id(candidate) != squadron_id:
			continue
		return candidate as Node3D
	return null


static func _get_role_follow_distance(ship, anchor_ship: Node3D, trailing_distance: float, role_name: String, formation_value: int) -> float:
	var base_spacing := maxf(trailing_distance, _get_ship_spacing_hint(ship))
	var desired_spacing := _get_role_spacing_value(base_spacing, role_name, formation_value)
	if role_name == ROLE_ARTILLERY_LEAD:
		desired_spacing += ROLE_EXTRA_TRAIL_PAD
	return get_follow_distance(ship, anchor_ship, desired_spacing)


static func _get_role_lateral_distance(ship, anchor_ship: Node3D, spacing: float, role_name: String, formation_value: int, my_index: int) -> float:
	var flagship := _get_flagship_anchor(ship)
	var rescue_lane: bool = role_name == ROLE_ARTILLERY_LEAD and is_instance_valid(flagship) and (flagship.get("deck_is_overrun") == true or flagship.get("deck_is_contested") == true or int(flagship.get("deck_hostile_boarder_count")) > 0)
	var lateral_scale: float = 0.92 if rescue_lane else _get_role_lateral_scale(role_name, formation_value)
	if absf(lateral_scale) <= 0.001:
		return 0.0
	var side_sign: float = (1.0 if int(ship.get_instance_id()) % 2 == 0 else -1.0) if rescue_lane else _get_role_side_sign(role_name, my_index)
	var pair_spacing := _get_pair_lateral_spacing(ship, anchor_ship, role_name)
	var minimum_spacing := maxf(spacing * 0.68, pair_spacing)
	return minimum_spacing * lateral_scale * side_sign


static func _get_pair_lateral_spacing(ship, anchor_ship: Node3D, role_name: String) -> float:
	var ship_half := _get_ship_half_extents(ship)
	var anchor_half := _get_ship_half_extents(anchor_ship)
	var pad := ARTILLERY_LATERAL_PAD if role_name.begins_with("artillery_") else GENERIC_LATERAL_PAD
	return ship_half.x + anchor_half.x + pad


static func _get_ship_half_extents(ship: Node3D) -> Vector2:
	if not is_instance_valid(ship):
		return Vector2(1.8, 3.2)
	if ship.has_method("get_collision_half_extents"):
		var extents: Variant = ship.call("get_collision_half_extents")
		if extents is Vector2:
			return extents
	if ship.has_method("get_deck_half_extents"):
		var deck_extents: Variant = ship.call("get_deck_half_extents")
		if deck_extents is Vector2:
			return deck_extents
	return ShipContactGeometry.get_soft_collision_half_extents(ship)


static func _get_ship_spacing_hint(ship) -> float:
	var half_extents := _get_ship_half_extents(ship)
	return maxf(10.0, half_extents.y * 0.92 + half_extents.x * 0.55)


static func _get_role_spacing_value(base_spacing: float, role_name: String, formation_value: int) -> float:
	match role_name:
		ROLE_ARTILLERY_LEAD:
			return base_spacing * (1.46 if formation_value == FORMATION_WING else 1.18)
		ROLE_ARTILLERY_SCREEN_LEFT, ROLE_ARTILLERY_SCREEN_RIGHT:
			return base_spacing * (1.62 if formation_value == FORMATION_WING else 1.02 if formation_value == FORMATION_COLUMN else 0.9)
		ROLE_RESCUE_REAR:
			return base_spacing * (2.05 if formation_value == FORMATION_WING else 1.75)
		ROLE_SCREEN_FLANK:
			return base_spacing * (0.9 if formation_value == FORMATION_WING else 0.96)
		ROLE_SCREEN_LEAD:
			return base_spacing * (0.9 if formation_value == FORMATION_WING else 0.92)
		_:
			return base_spacing


static func _get_role_lateral_scale(role_name: String, formation_value: int) -> float:
	if formation_value != FORMATION_WING:
		return 0.0
	match role_name:
		ROLE_SCREEN_LEAD, ROLE_SCREEN_FLANK:
			return 0.98
		ROLE_ARTILLERY_LEAD:
			return 0.42
		ROLE_ARTILLERY_SCREEN_LEFT, ROLE_ARTILLERY_SCREEN_RIGHT:
			return 1.36
		_:
			return 0.0


static func _get_role_side_sign(role_name: String, my_index: int) -> float:
	match role_name:
		ROLE_SCREEN_LEAD:
			return -1.0
		ROLE_SCREEN_FLANK:
			return 1.0
		ROLE_ARTILLERY_LEAD:
			return 1.0
		ROLE_ARTILLERY_SCREEN_LEFT:
			return -1.0
		ROLE_ARTILLERY_SCREEN_RIGHT:
			return 1.0
		_:
			return 0.0


static func _is_named_support_role(role_name: String) -> bool:
	match role_name:
		ROLE_SCREEN_LEAD, ROLE_SCREEN_FLANK, ROLE_RESCUE_REAR, ROLE_ARTILLERY_LEAD, ROLE_ARTILLERY_SCREEN_LEFT, ROLE_ARTILLERY_SCREEN_RIGHT:
			return true
		_:
			return false


static func _get_formation_value(ship) -> int:
	return SupportFleetStateHelper.get_effective_formation(ship)
static func _get_support_slot_role(ship) -> String:
	if not is_instance_valid(ship):
		return ""
	return str(ship.get_meta(SUPPORT_FLEET_SLOT_ROLE_META, "")).strip_edges().to_lower()
static func _get_support_squadron_id(ship) -> String:
	if not is_instance_valid(ship):
		return ""
	return str(ship.get_meta(SUPPORT_FLEET_SQUADRON_META, "")).strip_edges().to_lower()
static func _get_flagship_anchor(ship) -> Node3D:
	if not is_instance_valid(ship):
		return null
	var owner_flagship := SupportFleetStateHelper.get_support_owner_flagship(ship)
	if is_instance_valid(owner_flagship):
		return owner_flagship
	return ship.target as Node3D if is_instance_valid(ship.target) else null
