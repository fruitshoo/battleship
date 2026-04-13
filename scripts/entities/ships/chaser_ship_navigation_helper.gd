extends RefCounted
class_name ChaserShipNavigationHelper

static func _is_true(value: Variant) -> bool:
	return value == true

static func _team_tag(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_method("get_team_tag"):
		return node.get_team_tag()
	if "team" in node:
		return str(node.get("team"))
	return ""


static func _is_sinking_or_dying(node: Node) -> bool:
	if not is_instance_valid(node):
		return true
	if node.has_method("is_sinking_or_dying"):
		return node.is_sinking_or_dying()
	return _is_true(node.get("is_dying")) or _is_true(node.get("is_sinking"))


static func _is_boarding_ship(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_boarding_ship"):
		return node.is_boarding_ship()
	return _is_true(node.get("is_boarding"))


static func _boarding_target_ship(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_boarding_target_ship"):
		return node.get_boarding_target_ship()
	if "boarding_target" in node:
		return node.get("boarding_target")
	return null


static func _target_ship(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_target_ship"):
		return node.get_target_ship()
	if "target" in node:
		return node.get("target")
	return null


static func _can_board_node(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("can_board_targets"):
		return node.call("can_board_targets") == true
	return _is_true(node.get("allow_boarding"))


static func _current_speed(node: Node) -> float:
	if not is_instance_valid(node):
		return 0.0
	if node.has_method("get_current_speed_value"):
		return float(node.get_current_speed_value())
	if "current_speed" in node:
		var speed: Variant = node.get("current_speed")
		return float(speed) if speed != null else 0.0
	return 0.0

static func _is_gunner(ship) -> bool:
	if ship.has_method("is_gunner_role"):
		return ship.call("is_gunner_role") == true
	return int(ship.combat_role) == int(ship.CombatRole.GUNNER)


static func _can_board(ship) -> bool:
	return _can_board_node(ship)


static func _preferred_range(ship) -> float:
	if ship.has_method("get_preferred_engagement_range"):
		return float(ship.call("get_preferred_engagement_range"))
	return float(ship.preferred_combat_range)


static func _range_tolerance(ship) -> float:
	if ship.has_method("get_engagement_range_tolerance"):
		return float(ship.call("get_engagement_range_tolerance"))
	return float(ship.combat_range_tolerance)


static func _retreat_range(ship) -> float:
	if ship.has_method("get_retreat_engagement_distance"):
		return float(ship.call("get_retreat_engagement_distance"))
	return float(ship.retreat_distance)


static func _get_ship_deck_half_extents(ship) -> Vector2:
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


static func _build_boarding_slots(ship, target_node: Node3D, target_pos: Vector3, target_forward: Vector3, target_right: Vector3) -> Array:
	var collision_dist: float = ship.get_collision_distance_to(target_node)
	var my_half_ext: Vector2 = _get_ship_deck_half_extents(ship)
	var target_half_ext: Vector2 = _get_ship_deck_half_extents(target_node)
	var combined_half_width: float = my_half_ext.x + target_half_ext.x
	var side_offset_dist: float = clampf(
		maxf(collision_dist * 0.86, combined_half_width * 0.72),
		maxf(2.9, combined_half_width * 0.58),
		maxf(8.6, combined_half_width * 1.6)
	)
	var bow_lead_dist: float = clampf(collision_dist * 0.68, 4.8, 7.2)
	var mid_lead_dist: float = clampf(collision_dist * 0.40, 2.8, 5.0)
	var rel_forward: float = (ship.global_position - target_pos).dot(target_forward)
	var bow_bias: float = 0.15 if rel_forward < -2.0 else 0.0
	var mid_bias: float = 0.05 if rel_forward >= -1.0 else 0.0

	return [
		{
			"id": "port_bow",
			"side_sign": 1.0,
			"point": target_pos + target_right * side_offset_dist + target_forward * bow_lead_dist,
			"heading": target_pos + target_right * side_offset_dist + target_forward * (bow_lead_dist + 15.0),
			"bias": bow_bias,
		},
		{
			"id": "starboard_bow",
			"side_sign": - 1.0,
			"point": target_pos - target_right * side_offset_dist + target_forward * bow_lead_dist,
			"heading": target_pos - target_right * side_offset_dist + target_forward * (bow_lead_dist + 15.0),
			"bias": bow_bias,
		},
		{
			"id": "port_mid",
			"side_sign": 1.0,
			"point": target_pos + target_right * side_offset_dist + target_forward * mid_lead_dist,
			"heading": target_pos + target_right * side_offset_dist + target_forward * (mid_lead_dist + 12.0),
			"bias": mid_bias,
		},
		{
			"id": "starboard_mid",
			"side_sign": - 1.0,
			"point": target_pos - target_right * side_offset_dist + target_forward * mid_lead_dist,
			"heading": target_pos - target_right * side_offset_dist + target_forward * (mid_lead_dist + 12.0),
			"bias": mid_bias,
		},
	]


static func _score_boarding_slot(ship, target_node: Node3D, slot: Dictionary) -> float:
	var slot_point: Vector3 = slot["point"]
	var slot_id: String = str(slot["id"])
	var score: float = ship.global_position.distance_to(slot_point) - float(slot["bias"])
	var current_slot_id: String = str(ship.get_meta("boarding_slot_id", ""))
	var current_side_sign: float = float(ship.get_meta("boarding_side_sign", 0.0))
	var slot_side_sign: float = float(slot["side_sign"])
	var ship_forward: Vector3 = - ship.global_transform.basis.z
	ship_forward.y = 0.0
	if ship_forward.length_squared() > 0.001:
		ship_forward = ship_forward.normalized()
	var to_slot: Vector3 = slot_point - ship.global_position
	to_slot.y = 0.0
	if to_slot.length_squared() > 0.001 and ship_forward.length_squared() > 0.001:
		var slot_alignment: float = ship_forward.dot(to_slot.normalized())
		score += (1.0 - clampf(slot_alignment, -1.0, 1.0)) * 4.5
		var target_dist: float = ship.global_position.distance_to(target_node.global_position)
		if target_dist < 15.0 and slot_alignment < 0.55:
			score += (0.55 - slot_alignment) * 9.0

	if absf(current_side_sign) > 0.5 and signf(current_side_sign) != signf(slot_side_sign):
		score += 2.5

	if current_slot_id == slot_id:
		score -= 2.5

	var neighbors: Array = ship.get_ships_cached(ship.get_tree())
	for other_variant in neighbors:
		var other = other_variant
		if other == ship or not is_instance_valid(other):
			continue
		if _team_tag(other) != _team_tag(ship):
			continue
		var other_can_board: bool = _can_board_node(other)
		if other_can_board != true:
			continue
		if _target_ship(other) != target_node:
			continue

		var other_dist: float = other.global_position.distance_to(slot_point)
		if other_dist < 11.0:
			score += (11.0 - other_dist) * 4.2

		if str(other.get_meta("boarding_slot_id", "")) == slot_id:
			score += 12.0

	return score


static func _classify_boarding_approach(rel_forward: float, rel_side: float) -> String:
	var abs_forward: float = absf(rel_forward)
	var abs_side: float = absf(rel_side)
	if abs_side >= maxf(2.6, abs_forward * 0.55):
		return "side"
	if rel_forward <= -1.4:
		return "rear"
	return "front"


static func _classify_boarding_approach_smoothed(ship, rel_forward: float, rel_side: float) -> String:
	var current_mode: String = str(ship.get_meta("boarding_approach_mode", ""))
	var abs_forward: float = absf(rel_forward)
	var abs_side: float = absf(rel_side)

	if current_mode == "rear":
		if abs_side >= maxf(2.4, abs_forward * 0.50):
			return "side"
		if rel_forward <= -0.6:
			return "rear"
	elif current_mode == "side":
		if abs_side >= maxf(1.6, abs_forward * 0.38):
			return "side"
	elif current_mode == "front":
		if rel_forward > -0.4 and abs_side < maxf(3.2, abs_forward * 0.82):
			return "front"

	return _classify_boarding_approach(rel_forward, rel_side)


static func _is_bow_sector_approach(rel_forward: float, rel_side: float, collision_dist: float) -> bool:
	if rel_forward <= maxf(1.4, collision_dist * 0.16):
		return false
	var abs_side: float = absf(rel_side)
	var side_limit: float = minf(maxf(3.6, rel_forward * 1.05 + 0.8), maxf(4.8, collision_dist * 0.68))
	return abs_side <= side_limit


static func _build_side_follow_navigation(ship, target_node: Node3D, target_pos: Vector3, target_forward: Vector3, target_right: Vector3, rel_forward: float, rel_side: float, collision_dist: float, dist_to_target: float, tight_hold: bool = false) -> Dictionary:
	var side_sign: float = float(ship.get_meta("boarding_side_sign", 0.0))
	if absf(side_sign) < 0.5:
		side_sign = 1.0 if rel_side >= 0.0 else -1.0
	ship.set_meta("boarding_side_sign", side_sign)
	if ship.has_meta("boarding_slot_id"):
		ship.remove_meta("boarding_slot_id")

	var my_half_ext: Vector2 = _get_ship_deck_half_extents(ship)
	var target_half_ext: Vector2 = _get_ship_deck_half_extents(target_node)
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
	return {
		"desired_point": desired_point,
		"heading_point": heading_point,
		"desired_speed_mult": desired_speed_mult,
		"permit_sprint": false if tight_hold else dist_to_target > 10.0,
	}


static func _build_contact_settle_navigation(ship, target_pos: Vector3, target_forward: Vector3, target_right: Vector3, rel_forward: float, rel_side: float, collision_dist: float, dist_to_target: float) -> Dictionary:
	var side_sign: float = float(ship.get_meta("boarding_side_sign", 0.0))
	if absf(side_sign) < 0.5:
		side_sign = 1.0 if rel_side >= 0.0 else -1.0
	ship.set_meta("boarding_side_sign", side_sign)
	if ship.has_meta("boarding_slot_id"):
		ship.remove_meta("boarding_slot_id")

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

	return {
		"desired_point": desired_point,
		"heading_point": ship.global_position + current_forward * 9.0,
		"desired_speed_mult": 0.56 if dist_to_target > ship.max_boarding_distance else 0.34,
		"permit_sprint": false,
	}


static func _build_rear_recovery_navigation(ship, target_node: Node3D, target_pos: Vector3, target_forward: Vector3, target_right: Vector3, rel_side: float, collision_dist: float, dist_to_target: float) -> Dictionary:
	var side_sign: float = float(ship.get_meta("boarding_side_sign", 0.0))
	if absf(side_sign) < 0.5:
		side_sign = 1.0 if rel_side >= 0.0 else -1.0
	ship.set_meta("boarding_side_sign", side_sign)
	ship.set_meta("boarding_slot_id", "rear_recover_side")

	var my_half_ext: Vector2 = _get_ship_deck_half_extents(ship)
	var target_half_ext: Vector2 = _get_ship_deck_half_extents(target_node)
	var combined_half_width: float = my_half_ext.x + target_half_ext.x
	var side_offset_dist: float = clampf(
		maxf(collision_dist * 0.98, combined_half_width * 0.82),
		maxf(3.2, combined_half_width * 0.68),
		maxf(9.4, combined_half_width * 1.75)
	)
	var track_offset: float = clampf(target_half_ext.y * 0.12, 0.45, 1.9)
	var side_anchor: Vector3 = target_pos + target_right * side_sign * side_offset_dist
	var desired_point: Vector3 = side_anchor + target_forward * track_offset
	return {
		"desired_point": desired_point,
		"heading_point": side_anchor + target_forward * (track_offset + 10.0),
		"desired_speed_mult": 0.98 if dist_to_target > 9.0 else 0.78,
		"permit_sprint": dist_to_target > 10.0,
	}


static func _choose_boarding_slot(ship, target_node: Node3D, target_pos: Vector3, target_forward: Vector3, target_right: Vector3) -> Dictionary:
	var slots: Array = _build_boarding_slots(ship, target_node, target_pos, target_forward, target_right)
	var current_slot_id: String = str(ship.get_meta("boarding_slot_id", ""))
	var best_slot: Dictionary = {}
	var best_score: float = INF
	var current_slot: Dictionary = {}
	var current_slot_score: float = INF

	for slot_variant in slots:
		var slot: Dictionary = slot_variant
		var slot_score: float = _score_boarding_slot(ship, target_node, slot)
		if slot_score < best_score:
			best_score = slot_score
			best_slot = slot
		if str(slot["id"]) == current_slot_id:
			current_slot = slot
			current_slot_score = slot_score

	if not current_slot.is_empty() and current_slot_score <= best_score + 2.5:
		return current_slot
	return best_slot


static func _is_target_deck_contested(target_node: Node3D) -> bool:
	return target_node.get("deck_is_contested") == true


static func _is_target_deck_overrun(target_node: Node3D) -> bool:
	return target_node.get("deck_is_overrun") == true or target_node.get("is_derelict") == true


static func _has_closer_allied_attacker(ship, target_node: Node3D, dist_to_target: float) -> bool:
	if not ship.has_method("get_ships_cached"):
		return false
	var tree: SceneTree = ship.get_tree()
	if tree == null:
		return false
	var neighbors: Array = ship.get_ships_cached(tree)
	for other_variant in neighbors:
		var other = other_variant
		if other == ship or not is_instance_valid(other):
			continue
		if _team_tag(other) != _team_tag(ship):
			continue
		if _is_sinking_or_dying(other):
			continue
		var is_same_target: bool = _target_ship(other) == target_node or _boarding_target_ship(other) == target_node
		if not is_same_target:
			continue
		var other_dist: float = other.global_position.distance_to(target_node.global_position)
		if other_dist <= dist_to_target - 1.25:
			return true
		if _is_boarding_ship(other) and _boarding_target_ship(other) == target_node:
			return true
	return false


static func build_navigation(ship, target_node: Node3D) -> Dictionary:
	var target_pos: Vector3 = target_node.global_position
	var dist_to_target: float = ship.global_position.distance_to(target_pos)
	var target_deck_contested: bool = _is_target_deck_contested(target_node)
	var target_deck_overrun: bool = _is_target_deck_overrun(target_node)
	var yield_overrun_target: bool = target_deck_overrun and _has_closer_allied_attacker(ship, target_node, dist_to_target)

	if dist_to_target >= 25.0:
		var target_speed: float = _current_speed(target_node)
		if target_speed > 0.0:
			var lead_forward = Vector3(-sin(target_node.rotation.y), 0, -cos(target_node.rotation.y))
			var time_to_reach = min(dist_to_target / ship.move_speed, 3.0)
			target_pos += lead_forward * target_speed * time_to_reach

	var desired_point: Vector3 = target_pos
	var heading_point: Vector3 = target_pos
	var desired_speed_mult: float = 1.0
	var permit_sprint: bool = true

	var to_target_flat: Vector3 = target_pos - ship.global_position
	to_target_flat.y = 0.0
	if to_target_flat.length_squared() <= 0.001:
		to_target_flat = - ship.global_transform.basis.z
	var dir_to_target: Vector3 = to_target_flat.normalized()

	if yield_overrun_target:
		var standoff_distance: float = maxf(ship.max_boarding_distance + 3.5, 12.0)
		desired_point = target_pos - dir_to_target * standoff_distance
		heading_point = target_pos
		desired_speed_mult = 0.42 if dist_to_target > standoff_distance + 1.5 else 0.16
		permit_sprint = false
		return {
			"target_pos": target_pos,
			"desired_point": desired_point,
			"heading_point": heading_point,
			"dist_to_target": dist_to_target,
			"desired_speed_mult": desired_speed_mult,
			"permit_sprint": permit_sprint,
			"dir_to_target": dir_to_target
		}

	if _is_gunner(ship):
		permit_sprint = false
		var preferred_range: float = _preferred_range(ship)
		var tolerance: float = _range_tolerance(ship)
		var retreat_range: float = _retreat_range(ship)
		if dist_to_target > preferred_range + tolerance:
			desired_point = target_pos - dir_to_target * preferred_range
			desired_speed_mult = 0.95
		elif dist_to_target < retreat_range:
			desired_point = ship.global_position - dir_to_target * max(retreat_range - dist_to_target + 4.0, 4.0)
			heading_point = desired_point
			desired_speed_mult = 0.9
		else:
			desired_point = ship.global_position
			heading_point = target_pos
			desired_speed_mult = 0.18
	elif _can_board(ship) and dist_to_target < 18.0:
		var target_forward: Vector3 = - target_node.global_transform.basis.z
		target_forward.y = 0.0
		if target_forward.length_squared() > 0.001:
			target_forward = target_forward.normalized()
			var target_right: Vector3 = target_forward.cross(Vector3.UP).normalized()
			var rel_vector: Vector3 = ship.global_position - target_pos
			rel_vector.y = 0.0
			var rel_forward: float = rel_vector.dot(target_forward)
			var rel_side: float = rel_vector.dot(target_right)
			var approach_mode: String = _classify_boarding_approach_smoothed(ship, rel_forward, rel_side)
			var collision_dist: float = ship.get_collision_distance_to(target_node)
			var bow_sector_approach: bool = _is_bow_sector_approach(rel_forward, rel_side, collision_dist)
			if bow_sector_approach and approach_mode == "side":
				approach_mode = "front"
			ship.set_meta("boarding_approach_mode", approach_mode)
			var post_impact_follow_timer: float = float(ship.get_meta("post_impact_follow_timer", 0.0))
			var current_side_sign: float = float(ship.get_meta("boarding_side_sign", 0.0))
			var side_alignment_locked: bool = false
			if not bow_sector_approach and post_impact_follow_timer <= 0.0 and absf(current_side_sign) > 0.5:
				if absf(rel_side) >= collision_dist * 0.30 and absf(rel_forward) <= 10.0:
					approach_mode = "side"
					ship.set_meta("boarding_approach_mode", approach_mode)
			if not bow_sector_approach and ship.has_method("_is_side_boarding_approach") and ship.call("_is_side_boarding_approach", target_node) == true:
				if dist_to_target <= ship.boarding_break_distance - 0.4:
					var refreshed_timer: float = maxf(post_impact_follow_timer, 2.0)
					ship.set_meta("post_impact_follow_timer", refreshed_timer)
					post_impact_follow_timer = refreshed_timer
					side_alignment_locked = true

			if target_deck_contested and not bow_sector_approach and approach_mode != "rear" and dist_to_target <= ship.max_boarding_distance + 2.0:
				approach_mode = "side"
				ship.set_meta("boarding_approach_mode", approach_mode)
				side_alignment_locked = true
				post_impact_follow_timer = maxf(post_impact_follow_timer, 1.6)
				ship.set_meta("post_impact_follow_timer", post_impact_follow_timer)

			if post_impact_follow_timer > 0.0 and not bow_sector_approach:
				var follow_nav: Dictionary = _build_side_follow_navigation(ship, target_node, target_pos, target_forward, target_right, rel_forward, rel_side, collision_dist, dist_to_target, true)
				desired_point = follow_nav["desired_point"]
				heading_point = follow_nav["heading_point"]
				desired_speed_mult = follow_nav["desired_speed_mult"]
				permit_sprint = follow_nav["permit_sprint"]
			elif approach_mode == "side" and dist_to_target <= ship.max_boarding_distance + 1.35:
				var settle_nav: Dictionary = _build_contact_settle_navigation(ship, target_pos, target_forward, target_right, rel_forward, rel_side, collision_dist, dist_to_target)
				desired_point = settle_nav["desired_point"]
				heading_point = settle_nav["heading_point"]
				desired_speed_mult = settle_nav["desired_speed_mult"]
				permit_sprint = settle_nav["permit_sprint"]
			elif approach_mode == "rear":
				if dist_to_target <= ship.max_boarding_distance + 6.0:
					var rear_recovery_nav: Dictionary = _build_rear_recovery_navigation(ship, target_node, target_pos, target_forward, target_right, rel_side, collision_dist, dist_to_target)
					desired_point = rear_recovery_nav["desired_point"]
					heading_point = rear_recovery_nav["heading_point"]
					desired_speed_mult = rear_recovery_nav["desired_speed_mult"]
					permit_sprint = rear_recovery_nav["permit_sprint"]
				else:
					var slot: Dictionary = _choose_boarding_slot(ship, target_node, target_pos, target_forward, target_right)
					if not slot.is_empty():
						ship.set_meta("boarding_slot_id", str(slot["id"]))
						ship.set_meta("boarding_side_sign", float(slot["side_sign"]))
						desired_point = slot["point"]
						heading_point = slot["heading"]
					desired_speed_mult = 1.04 if dist_to_target > ship.max_boarding_distance + 1.0 else 0.94
					permit_sprint = dist_to_target > 7.0
			elif approach_mode == "side":
				var side_nav: Dictionary = _build_side_follow_navigation(ship, target_node, target_pos, target_forward, target_right, rel_forward, rel_side, collision_dist, dist_to_target, side_alignment_locked)
				desired_point = side_nav["desired_point"]
				heading_point = side_nav["heading_point"]
				desired_speed_mult = side_nav["desired_speed_mult"]
				permit_sprint = side_nav["permit_sprint"]
			else:
				var front_impact_offset: float = clampf(collision_dist * 0.55, 3.0, 5.0)
				if ship.has_meta("boarding_slot_id"):
					ship.remove_meta("boarding_slot_id")
				if ship.has_meta("boarding_side_sign"):
					ship.remove_meta("boarding_side_sign")
				desired_point = target_pos + target_forward * front_impact_offset
				heading_point = desired_point
				desired_speed_mult = 1.0
				permit_sprint = dist_to_target > 9.0

			if target_deck_contested:
				desired_speed_mult = minf(desired_speed_mult, 0.72 if dist_to_target > ship.max_boarding_distance + 1.0 else 0.58)
				permit_sprint = false
			elif target_deck_overrun:
				desired_speed_mult = minf(desired_speed_mult, 0.78)
				permit_sprint = false
			elif dist_to_target <= ship.max_boarding_distance + 3.0:
				var final_approach_blend: float = clampf((ship.max_boarding_distance + 3.0 - dist_to_target) / 3.0, 0.0, 1.0)
				desired_speed_mult = minf(desired_speed_mult, lerpf(0.88, 0.62, final_approach_blend))
				permit_sprint = false
	else:
		if ship.has_meta("boarding_slot_id"):
			ship.remove_meta("boarding_slot_id")
		if ship.has_meta("boarding_side_sign"):
			ship.remove_meta("boarding_side_sign")
		if ship.has_meta("boarding_approach_mode"):
			ship.remove_meta("boarding_approach_mode")

	return {
		"target_pos": target_pos,
		"desired_point": desired_point,
		"heading_point": heading_point,
		"dist_to_target": dist_to_target,
		"desired_speed_mult": desired_speed_mult,
		"permit_sprint": permit_sprint,
		"dir_to_target": dir_to_target
	}
