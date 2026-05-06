extends RefCounted
class_name SupportFleetFormationHelper

const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SUPPORT_FLEET_SLOT_ROLE_META := "support_squadron_slot_role"
const SUPPORT_FLEET_SQUADRON_META := "support_squadron_id"
const SUPPORT_FLEET_SLOT_INDEX_META := "support_fleet_slot_index"

const ROLE_SCREEN_LEAD := "screen_lead"
const ROLE_SCREEN_FLANK := "screen_flank"
const ROLE_RESCUE_REAR := "rescue_rear"
const ROLE_ARTILLERY_LEAD := "artillery_lead"
const ROLE_ARTILLERY_SCREEN_LEFT := "artillery_screen_left"
const ROLE_ARTILLERY_SCREEN_RIGHT := "artillery_screen_right"
const ROLE_ARTILLERY_SCREEN_FRONT_LEFT := "artillery_screen_front_left"
const ROLE_ARTILLERY_SCREEN_FRONT_RIGHT := "artillery_screen_front_right"
const ROLE_ARTILLERY_SCREEN_REAR_LEFT := "artillery_screen_rear_left"
const ROLE_ARTILLERY_SCREEN_REAR_RIGHT := "artillery_screen_rear_right"

const FORMATION_COLUMN := 0
const FORMATION_WING := 1
const FORMATION_WEDGE := 2 # Legacy value, normalized to FORMATION_WING.

const FOLLOW_DISTANCE_PAD := 2.0
const GENERIC_LATERAL_PAD := 1.6
const ARTILLERY_LATERAL_PAD := 2.35
const ROLE_EXTRA_TRAIL_PAD := 1.1
const ROLE_ANCHOR_FLAGSHIP := "flagship"
const ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN := "squadron_lead_in_column"
const GENERATED_WING_FIRST_ROW_TRAIL_SCALE := 0.42
const GENERATED_WING_ROW_TRAIL_SCALE := 0.36
const GENERATED_WING_LATERAL_ROW_SCALE := 0.72
const GENERATED_CENTER_TAIL_TRAIL_PAD := 0.35
const WING_SCREEN_TURN_CLEAR_START_RUDDER := 10.0
const WING_SCREEN_TURN_CLEAR_FULL_RUDDER := 34.0
const WING_SCREEN_TURN_TRAIL_BACK := 0.96
const WING_SCREEN_TURN_OUTER_WIDEN := 0.30
const WING_SCREEN_TURN_INNER_WIDEN := 0.55

const ROLE_SPECS := {
	ROLE_SCREEN_LEAD: {
		"anchor": ROLE_ANCHOR_FLAGSHIP,
		"wing_side": -1.0,
		"wing_lateral": 1.28,
		"wing_spacing": -0.68,
		"column_spacing": 0.92,
		"lateral_pad": GENERIC_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
	ROLE_SCREEN_FLANK: {
		"anchor": ROLE_ANCHOR_FLAGSHIP,
		"wing_side": 1.0,
		"wing_lateral": 1.28,
		"wing_spacing": -0.68,
		"column_spacing": 0.96,
		"lateral_pad": GENERIC_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
	ROLE_RESCUE_REAR: {
		"anchor": ROLE_ANCHOR_FLAGSHIP,
		"wing_side": 0.0,
		"wing_lateral": 0.0,
		"wing_spacing": 1.42,
		"column_spacing": 1.75,
		"lateral_pad": GENERIC_LATERAL_PAD,
		"hold_line": false,
	},
	ROLE_ARTILLERY_LEAD: {
		"anchor": ROLE_ANCHOR_FLAGSHIP,
		"wing_side": 0.0,
		"wing_lateral": 0.0,
		"wing_spacing": 0.86,
		"column_spacing": 1.18,
		"lateral_pad": ARTILLERY_LATERAL_PAD,
		"extra_trail_pad": 0.35,
		"rescue_lane": true,
		"rescue_lateral": 0.92,
		"hold_line": true,
	},
	ROLE_ARTILLERY_SCREEN_LEFT: {
		"anchor": ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN,
		"wing_side": -1.0,
		"wing_lateral": 1.18,
		"wing_spacing": -0.36,
		"column_spacing": 1.02,
		"lateral_pad": ARTILLERY_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
	ROLE_ARTILLERY_SCREEN_RIGHT: {
		"anchor": ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN,
		"wing_side": 1.0,
		"wing_lateral": 1.18,
		"wing_spacing": -0.36,
		"column_spacing": 1.02,
		"lateral_pad": ARTILLERY_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
	ROLE_ARTILLERY_SCREEN_FRONT_LEFT: {
		"anchor": ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN,
		"wing_side": -1.0,
		"wing_lateral": 1.08,
		"wing_spacing": -0.36,
		"column_spacing": 1.02,
		"lateral_pad": ARTILLERY_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
	ROLE_ARTILLERY_SCREEN_FRONT_RIGHT: {
		"anchor": ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN,
		"wing_side": 1.0,
		"wing_lateral": 1.08,
		"wing_spacing": -0.36,
		"column_spacing": 1.02,
		"lateral_pad": ARTILLERY_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
	ROLE_ARTILLERY_SCREEN_REAR_LEFT: {
		"anchor": ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN,
		"wing_side": -1.0,
		"wing_lateral": 1.08,
		"wing_spacing": 0.66,
		"column_spacing": 1.16,
		"lateral_pad": ARTILLERY_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
	ROLE_ARTILLERY_SCREEN_REAR_RIGHT: {
		"anchor": ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN,
		"wing_side": 1.0,
		"wing_lateral": 1.08,
		"wing_spacing": 0.66,
		"column_spacing": 1.16,
		"lateral_pad": ARTILLERY_LATERAL_PAD,
		"wing_direct_depth": true,
		"hold_line": false,
	},
}


static func get_support_fleet_offset(ship, my_index: int, spacing: float, roster_size: int = -1) -> Vector3:
	var role_name := _get_support_slot_role(ship)
	if role_name.is_empty() or not _is_named_support_role(role_name):
		return _get_generic_support_formation_offset(ship, my_index, spacing, roster_size)

	var formation_value := _get_formation_value(ship)
	var base_spacing := maxf(spacing, _get_ship_spacing_hint(ship))
	var trail_distance := _get_role_spacing_value(base_spacing, role_name, formation_value)
	var lateral_distance := _get_role_lateral_distance(ship, _get_flagship_anchor(ship), base_spacing, role_name, formation_value, my_index)
	return Vector3(lateral_distance, 0.0, trail_distance)


static func get_support_join_offset(ship, my_index: int) -> Vector3:
	return get_support_fleet_offset(ship, my_index, 18.0)


static func get_support_lead_ship(ship, minions: Array, my_index: int) -> Node3D:
	var role_name := _get_support_slot_role(ship)
	var flagship_anchor := _get_flagship_anchor(ship)
	if _should_follow_flagship_directly(ship, role_name) and is_instance_valid(flagship_anchor):
		return flagship_anchor
	var formation_value := _get_formation_value(ship)
	if formation_value == FORMATION_COLUMN:
		return _get_generic_support_lead_ship(ship, minions, my_index)
	if not _is_named_support_role(role_name):
		if is_instance_valid(flagship_anchor):
			return flagship_anchor
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
	var role_spec := _get_role_spec(_get_support_slot_role(ship))
	if role_spec.get("hold_line", false) == true:
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
	var generated_slot := _get_generated_support_slot(ship, my_index, spacing, roster_size, formation_value)
	return Vector3(
		float(generated_slot.get("lateral", 0.0)),
		0.0,
		float(generated_slot.get("trailing", maxf(spacing, 0.01)))
	)


static func _get_generated_support_slot(ship, my_index: int, spacing: float, roster_size: int, formation_value: int) -> Dictionary:
	var index: int = maxi(my_index, 0)
	var effective_roster_size: int = maxi(roster_size, index + 1) if roster_size >= 0 else index + 1
	var base_spacing: float = maxf(maxf(spacing, _get_ship_spacing_hint(ship)), 0.01)
	if formation_value == FORMATION_COLUMN:
		return {
			"row": float(index + 1),
			"side": 0.0,
			"lateral": 0.0,
			"trailing": base_spacing * (float(index) + 1.0),
		}
	if effective_roster_size <= 1:
		return {
			"row": 1.0,
			"side": 0.0,
			"lateral": 0.0,
			"trailing": base_spacing,
		}
	var row: float = floor(float(index) / 2.0) + 1.0
	var has_center_tail: bool = effective_roster_size % 2 == 1 and index == effective_roster_size - 1
	if has_center_tail:
		return {
			"row": row + GENERATED_CENTER_TAIL_TRAIL_PAD,
			"side": 0.0,
			"lateral": 0.0,
			"trailing": base_spacing * (row + GENERATED_CENTER_TAIL_TRAIL_PAD),
		}
	var side: float = 1.0 if index % 2 == 0 else -1.0
	var lateral: float = _get_generated_lateral_distance(ship, base_spacing, row)
	var trailing: float = base_spacing * (
		GENERATED_WING_FIRST_ROW_TRAIL_SCALE
		+ maxf(row - 1.0, 0.0) * GENERATED_WING_ROW_TRAIL_SCALE
	)
	return {
		"row": row,
		"side": side,
		"lateral": lateral * side,
		"trailing": trailing,
	}


static func _get_generated_lateral_distance(ship, base_spacing: float, row: float) -> float:
	var half_extents := _get_ship_half_extents(ship)
	var lane_spacing := maxf(base_spacing, half_extents.x * 2.0 + GENERIC_LATERAL_PAD)
	var lateral_row_scale: float = 1.0 + maxf(row - 1.0, 0.0) * GENERATED_WING_LATERAL_ROW_SCALE
	return lane_spacing * lateral_row_scale


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
	var anchor_mode := str(_get_role_spec(role_name).get("anchor", ROLE_ANCHOR_FLAGSHIP))
	if anchor_mode == ROLE_ANCHOR_SQUADRON_LEAD_IN_COLUMN:
		var squadron_id := _get_support_squadron_id(ship)
		var lead_ship := _find_squadron_lead(minions, squadron_id)
		if is_instance_valid(lead_ship) and lead_ship != ship:
			return lead_ship
		return flagship_anchor
	return flagship_anchor


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
	var role_spec := _get_role_spec(role_name)
	desired_spacing += float(role_spec.get("extra_trail_pad", 0.0))
	if formation_value == FORMATION_WING and _is_screen_role(role_name):
		desired_spacing += base_spacing * WING_SCREEN_TURN_TRAIL_BACK * _get_flagship_turn_clearance_blend(ship)
	if formation_value == FORMATION_WING and role_spec.get("wing_direct_depth", false) == true:
		return desired_spacing
	return get_follow_distance(ship, anchor_ship, desired_spacing)


static func _get_role_lateral_distance(ship, anchor_ship: Node3D, spacing: float, role_name: String, formation_value: int, my_index: int) -> float:
	var flagship := _get_flagship_anchor(ship)
	var role_spec := _get_role_spec(role_name)
	var rescue_lane: bool = role_spec.get("rescue_lane", false) == true and is_instance_valid(flagship) and (flagship.get("deck_is_overrun") == true or flagship.get("deck_is_contested") == true or int(flagship.get("deck_hostile_boarder_count")) > 0)
	var lateral_scale: float = float(role_spec.get("rescue_lateral", 0.92)) if rescue_lane else _get_role_lateral_scale(role_name, formation_value)
	if absf(lateral_scale) <= 0.001:
		return 0.0
	var side_sign: float = _get_rescue_lane_side_sign(ship, role_name, my_index) if rescue_lane else _get_role_side_sign(role_name, my_index)
	var pair_spacing := _get_pair_lateral_spacing(ship, anchor_ship, role_name)
	var minimum_spacing := maxf(spacing * 0.68, pair_spacing)
	if formation_value == FORMATION_WING and _is_screen_role(role_name):
		var turn_clearance_blend := _get_flagship_turn_clearance_blend(ship)
		if turn_clearance_blend > 0.0:
			var turn_side := _get_flagship_turn_side(ship)
			var widen_scale := WING_SCREEN_TURN_INNER_WIDEN if side_sign == turn_side else WING_SCREEN_TURN_OUTER_WIDEN
			minimum_spacing += spacing * widen_scale * turn_clearance_blend
	return minimum_spacing * lateral_scale * side_sign


static func _get_rescue_lane_side_sign(ship, role_name: String, my_index: int) -> float:
	var role_side := _get_role_side_sign(role_name, my_index)
	if absf(role_side) > 0.001:
		return role_side
	var slot_index := my_index
	if is_instance_valid(ship):
		slot_index = int(ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, my_index))
	return 1.0 if slot_index % 2 == 0 else -1.0


static func _get_pair_lateral_spacing(ship, anchor_ship: Node3D, role_name: String) -> float:
	var ship_half := _get_ship_half_extents(ship)
	var anchor_half := _get_ship_half_extents(anchor_ship)
	var role_spec := _get_role_spec(role_name)
	var fallback_pad := ARTILLERY_LATERAL_PAD if role_name.begins_with("artillery_") else GENERIC_LATERAL_PAD
	var pad := float(role_spec.get("lateral_pad", fallback_pad))
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
	var role_spec := _get_role_spec(role_name)
	if role_spec.is_empty():
		return base_spacing
	var spacing_key := "wing_spacing" if formation_value == FORMATION_WING else "column_spacing"
	return base_spacing * float(role_spec.get(spacing_key, 1.0))


static func _get_role_lateral_scale(role_name: String, formation_value: int) -> float:
	if formation_value != FORMATION_WING:
		return 0.0
	return float(_get_role_spec(role_name).get("wing_lateral", 0.0))


static func _get_role_side_sign(role_name: String, my_index: int) -> float:
	return float(_get_role_spec(role_name).get("wing_side", 0.0))


static func _is_screen_role(role_name: String) -> bool:
	return role_name == ROLE_SCREEN_LEAD or role_name == ROLE_SCREEN_FLANK


static func _get_flagship_turn_clearance_blend(ship) -> float:
	var flagship := _get_flagship_anchor(ship)
	if not is_instance_valid(flagship):
		return 0.0
	var rudder_abs: float = absf(float(flagship.get("rudder_angle"))) if flagship.get("rudder_angle") != null else 0.0
	return clampf(
		(rudder_abs - WING_SCREEN_TURN_CLEAR_START_RUDDER) / maxf(WING_SCREEN_TURN_CLEAR_FULL_RUDDER - WING_SCREEN_TURN_CLEAR_START_RUDDER, 0.001),
		0.0,
		1.0
	)


static func _get_flagship_turn_side(ship) -> float:
	var flagship := _get_flagship_anchor(ship)
	if not is_instance_valid(flagship) or flagship.get("rudder_angle") == null:
		return 0.0
	var rudder_value := float(flagship.get("rudder_angle"))
	if absf(rudder_value) <= 0.01:
		return 0.0
	return 1.0 if rudder_value > 0.0 else -1.0


static func _should_follow_flagship_directly(ship, role_name: String) -> bool:
	return role_name == ROLE_ARTILLERY_LEAD or ShipAllyRoleHelper.is_panokseon_support(ship)


static func _is_named_support_role(role_name: String) -> bool:
	return ROLE_SPECS.has(role_name)


static func _get_role_spec(role_name: String) -> Dictionary:
	return ROLE_SPECS.get(role_name, {})


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
