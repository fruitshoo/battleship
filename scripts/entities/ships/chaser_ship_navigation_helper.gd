extends RefCounted
class_name ChaserShipNavigationHelper

static func _is_gunner(ship) -> bool:
	if ship.has_method("is_gunner_role"):
		return bool(ship.call("is_gunner_role"))
	return int(ship.combat_role) == int(ship.CombatRole.GUNNER)


static func _can_board(ship) -> bool:
	if ship.has_method("can_board_targets"):
		return bool(ship.call("can_board_targets"))
	return bool(ship.allow_boarding)


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
		if other.get("team") != ship.team:
			continue
		var other_can_board: bool = bool(other.get("allow_boarding"))
		if other.has_method("can_board_targets"):
			other_can_board = bool(other.call("can_board_targets"))
		if other_can_board != true:
			continue
		if other.get("target") != target_node:
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
	if rel_forward <= -1.4:
		return "rear"
	if abs_side >= maxf(2.6, abs_forward * 0.65):
		return "side"
	return "front"


static func _classify_boarding_approach_smoothed(ship, rel_forward: float, rel_side: float) -> String:
	var current_mode: String = str(ship.get_meta("boarding_approach_mode", ""))
	var abs_forward: float = absf(rel_forward)
	var abs_side: float = absf(rel_side)

	if current_mode == "rear":
		if rel_forward <= -0.6:
			return "rear"
	elif current_mode == "side":
		if abs_side >= maxf(2.0, abs_forward * 0.52):
			return "side"
	elif current_mode == "front":
		if rel_forward > -0.4 and abs_side < maxf(3.2, abs_forward * 0.82):
			return "front"

	return _classify_boarding_approach(rel_forward, rel_side)


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
		maxf(collision_dist * (0.58 if tight_hold else 0.86), combined_half_width * (0.58 if tight_hold else 0.72)),
		maxf(2.4 if tight_hold else 2.9, combined_half_width * (0.46 if tight_hold else 0.58)),
		maxf(8.6, combined_half_width * 1.6)
	)
	var side_anchor: Vector3 = target_pos + target_right * side_sign * side_offset_dist
	var along_track_offset: float
	if tight_hold:
		var target_track_offset: float = 0.35
		along_track_offset = clampf(
			lerpf(rel_forward, target_track_offset, 0.82),
			0.0,
			1.0
		)
	else:
		along_track_offset = clampf(
			(ship.global_position - side_anchor).dot(target_forward),
			-1.2,
			6.4
		)
	var heading_lead: float = 3.5 if tight_hold else 12.0
	var desired_speed_mult: float
	if tight_hold:
		desired_speed_mult = 0.66
		if rel_forward > 1.2:
			desired_speed_mult = 0.40
		elif rel_forward < -0.2:
			desired_speed_mult = 0.84
	else:
		desired_speed_mult = 0.98 if dist_to_target > ship.max_boarding_distance + 1.0 else 0.88
	return {
		"desired_point": side_anchor + target_forward * along_track_offset,
		"heading_point": side_anchor + target_forward * (along_track_offset + heading_lead),
		"desired_speed_mult": desired_speed_mult,
		"permit_sprint": false if tight_hold else dist_to_target > 10.0,
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
		if other.get("team") != ship.team:
			continue
		if other.get("is_dying") == true or other.get("is_sinking") == true:
			continue
		var is_same_target: bool = other.get("target") == target_node or other.get("boarding_target") == target_node
		if not is_same_target:
			continue
		var other_dist: float = other.global_position.distance_to(target_node.global_position)
		if other_dist <= dist_to_target - 1.25:
			return true
		if other.get("is_boarding") == true and other.get("boarding_target") == target_node:
			return true
	return false


static func build_navigation(ship, target_node: Node3D) -> Dictionary:
	var target_pos: Vector3 = target_node.global_position
	var dist_to_target: float = ship.global_position.distance_to(target_pos)
	var target_deck_contested: bool = _is_target_deck_contested(target_node)
	var target_deck_overrun: bool = _is_target_deck_overrun(target_node)
	var yield_overrun_target: bool = target_deck_overrun and _has_closer_allied_attacker(ship, target_node, dist_to_target)

	if dist_to_target >= 25.0:
		var target_speed = target_node.get("current_speed")
		if target_speed:
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
			ship.set_meta("boarding_approach_mode", approach_mode)
			var collision_dist: float = ship.get_collision_distance_to(target_node)
			var post_impact_follow_timer: float = float(ship.get_meta("post_impact_follow_timer", 0.0))
			var current_side_sign: float = float(ship.get_meta("boarding_side_sign", 0.0))
			var side_alignment_locked: bool = false
			if post_impact_follow_timer <= 0.0 and absf(current_side_sign) > 0.5:
				if absf(rel_side) >= collision_dist * 0.42 and absf(rel_forward) <= 8.0:
					approach_mode = "side"
			if ship.has_method("_is_side_boarding_approach") and bool(ship.call("_is_side_boarding_approach", target_node)):
				if dist_to_target <= ship.boarding_break_distance - 0.4:
					var refreshed_timer: float = maxf(post_impact_follow_timer, 2.0)
					ship.set_meta("post_impact_follow_timer", refreshed_timer)
					post_impact_follow_timer = refreshed_timer
					side_alignment_locked = true

			if target_deck_contested and approach_mode != "rear" and dist_to_target <= ship.max_boarding_distance + 2.0:
				approach_mode = "side"
				side_alignment_locked = true
				post_impact_follow_timer = maxf(post_impact_follow_timer, 1.6)
				ship.set_meta("post_impact_follow_timer", post_impact_follow_timer)

			if post_impact_follow_timer > 0.0:
				var follow_nav: Dictionary = _build_side_follow_navigation(ship, target_node, target_pos, target_forward, target_right, rel_forward, rel_side, collision_dist, dist_to_target, true)
				desired_point = follow_nav["desired_point"]
				heading_point = follow_nav["heading_point"]
				desired_speed_mult = follow_nav["desired_speed_mult"]
				permit_sprint = follow_nav["permit_sprint"]
			elif approach_mode == "rear":
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
