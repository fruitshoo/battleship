extends RefCounted
class_name ChaserShipNavigationHelper

const ShipCombatModeHelper = preload("res://scripts/entities/ships/ship_combat_mode_helper.gd")
const ShipMovementIntent = preload("res://scripts/entities/ships/ship_movement_intent.gd")
const ShipBoardingNavigationHelper = preload("res://scripts/entities/ships/ship_boarding_navigation_helper.gd")
const ShipBoardingSlot = preload("res://scripts/entities/ships/ship_boarding_slot.gd")
const ShipBoardingMetaHelper = preload("res://scripts/entities/ships/ship_boarding_meta_helper.gd")

const META_AUTHORING_MOVEMENT_MODE := "enemy_authoring_movement_mode"
const META_AUTHORING_MOVEMENT_SPEED_MIN := "enemy_authoring_movement_speed_min"
const META_AUTHORING_MOVEMENT_SPEED_MAX := "enemy_authoring_movement_speed_max"
const META_AUTHORING_MOVEMENT_SPRINT := "enemy_authoring_movement_sprint"

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
	return ShipCombatModeHelper.can_board(node)


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
	return ShipCombatModeHelper.is_gunner(ship)


static func _can_board(ship) -> bool:
	return _can_board_node(ship)


static func _preferred_range(ship) -> float:
	return ShipCombatModeHelper.preferred_range(ship)


static func _range_tolerance(ship) -> float:
	return ShipCombatModeHelper.range_tolerance(ship)


static func _retreat_range(ship) -> float:
	return ShipCombatModeHelper.retreat_distance(ship)


static func _authoring_movement_mode(ship) -> String:
	if not is_instance_valid(ship):
		return ""
	return str(ship.get_meta(META_AUTHORING_MOVEMENT_MODE, "")).strip_edges()


static func _navigation_mode(intent: Dictionary, fallback: String = "") -> String:
	return ShipMovementIntent.get_mode(intent, fallback)


static func _apply_authoring_movement_params(ship, desired_speed_mult: float, permit_sprint: bool) -> Dictionary:
	var next_speed := desired_speed_mult
	if is_instance_valid(ship):
		var has_min: bool = ship.has_meta(META_AUTHORING_MOVEMENT_SPEED_MIN)
		var has_max: bool = ship.has_meta(META_AUTHORING_MOVEMENT_SPEED_MAX)
		if has_min or has_max:
			var speed_min := float(ship.get_meta(META_AUTHORING_MOVEMENT_SPEED_MIN, next_speed))
			var speed_max := float(ship.get_meta(META_AUTHORING_MOVEMENT_SPEED_MAX, next_speed))
			if speed_min > speed_max:
				var swapped_speed := speed_min
				speed_min = speed_max
				speed_max = swapped_speed
			next_speed = clampf(next_speed, speed_min, speed_max)
		if ship.has_meta(META_AUTHORING_MOVEMENT_SPRINT) and ship.get_meta(META_AUTHORING_MOVEMENT_SPRINT, false) != true:
			permit_sprint = false
	return {
		ShipMovementIntent.DESIRED_SPEED_MULT: next_speed,
		ShipMovementIntent.PERMIT_SPRINT: permit_sprint,
	}


static func _build_authoring_movement_intent(ship, target_pos: Vector3, desired_point: Vector3, heading_point: Vector3, dist_to_target: float, desired_speed_mult: float, permit_sprint: bool, dir_to_target: Vector3, mode: String) -> Dictionary:
	var movement_params := _apply_authoring_movement_params(ship, desired_speed_mult, permit_sprint)
	return ShipMovementIntent.build(
		target_pos,
		desired_point,
		heading_point,
		dist_to_target,
		float(movement_params.get(ShipMovementIntent.DESIRED_SPEED_MULT, desired_speed_mult)),
		movement_params.get(ShipMovementIntent.PERMIT_SPRINT, permit_sprint) == true,
		dir_to_target,
		mode
	)


static func _build_boarding_slots(ship, target_node: Node3D, target_pos: Vector3, target_forward: Vector3, target_right: Vector3) -> Array:
	var collision_dist: float = ship.get_collision_distance_to(target_node)
	var my_half_ext: Vector2 = ShipBoardingNavigationHelper.get_ship_deck_half_extents(ship)
	var target_half_ext: Vector2 = ShipBoardingNavigationHelper.get_ship_deck_half_extents(target_node)
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
		ShipBoardingSlot.build(
			ShipBoardingSlot.PORT_BOW,
			1.0,
			target_pos + target_right * side_offset_dist + target_forward * bow_lead_dist,
			target_pos + target_right * side_offset_dist + target_forward * (bow_lead_dist + 15.0),
			bow_bias
		),
		ShipBoardingSlot.build(
			ShipBoardingSlot.STARBOARD_BOW,
			-1.0,
			target_pos - target_right * side_offset_dist + target_forward * bow_lead_dist,
			target_pos - target_right * side_offset_dist + target_forward * (bow_lead_dist + 15.0),
			bow_bias
		),
		ShipBoardingSlot.build(
			ShipBoardingSlot.PORT_MID,
			1.0,
			target_pos + target_right * side_offset_dist + target_forward * mid_lead_dist,
			target_pos + target_right * side_offset_dist + target_forward * (mid_lead_dist + 12.0),
			mid_bias
		),
		ShipBoardingSlot.build(
			ShipBoardingSlot.STARBOARD_MID,
			-1.0,
			target_pos - target_right * side_offset_dist + target_forward * mid_lead_dist,
			target_pos - target_right * side_offset_dist + target_forward * (mid_lead_dist + 12.0),
			mid_bias
		),
	]


static func _score_boarding_slot(ship, target_node: Node3D, slot: Dictionary) -> float:
	var slot_point: Vector3 = ShipBoardingSlot.get_point(slot)
	var slot_id: String = ShipBoardingSlot.get_id(slot)
	var score: float = ship.global_position.distance_to(slot_point) - ShipBoardingSlot.get_bias(slot)
	var current_slot_id: String = ShipBoardingMetaHelper.get_slot_id(ship)
	var current_side_sign: float = ShipBoardingMetaHelper.get_side_sign(ship)
	var slot_side_sign: float = ShipBoardingSlot.get_side_sign(slot)
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

		if ShipBoardingMetaHelper.get_slot_id(other) == slot_id:
			score += 12.0

	return score


static func _classify_boarding_approach(rel_forward: float, rel_side: float) -> String:
	var abs_forward: float = absf(rel_forward)
	var abs_side: float = absf(rel_side)
	if abs_side >= maxf(2.6, abs_forward * 0.55):
		return ShipBoardingMetaHelper.APPROACH_SIDE
	if rel_forward <= -1.4:
		return ShipBoardingMetaHelper.APPROACH_REAR
	return ShipBoardingMetaHelper.APPROACH_FRONT


static func _classify_boarding_approach_smoothed(ship, rel_forward: float, rel_side: float) -> String:
	var current_mode: String = ShipBoardingMetaHelper.get_approach_mode(ship)
	var abs_forward: float = absf(rel_forward)
	var abs_side: float = absf(rel_side)

	if current_mode == ShipBoardingMetaHelper.APPROACH_REAR:
		if abs_side >= maxf(2.4, abs_forward * 0.50):
			return ShipBoardingMetaHelper.APPROACH_SIDE
		if rel_forward <= -0.6:
			return ShipBoardingMetaHelper.APPROACH_REAR
	elif current_mode == ShipBoardingMetaHelper.APPROACH_SIDE:
		if abs_side >= maxf(1.6, abs_forward * 0.38):
			return ShipBoardingMetaHelper.APPROACH_SIDE
	elif current_mode == ShipBoardingMetaHelper.APPROACH_FRONT:
		if rel_forward > -0.4 and abs_side < maxf(3.2, abs_forward * 0.82):
			return ShipBoardingMetaHelper.APPROACH_FRONT

	return _classify_boarding_approach(rel_forward, rel_side)


static func _is_bow_sector_approach(rel_forward: float, rel_side: float, collision_dist: float) -> bool:
	if rel_forward <= maxf(1.4, collision_dist * 0.16):
		return false
	var abs_side: float = absf(rel_side)
	var side_limit: float = minf(maxf(3.6, rel_forward * 1.05 + 0.8), maxf(4.8, collision_dist * 0.68))
	return abs_side <= side_limit


static func _choose_boarding_slot(ship, target_node: Node3D, target_pos: Vector3, target_forward: Vector3, target_right: Vector3) -> Dictionary:
	var slots: Array = _build_boarding_slots(ship, target_node, target_pos, target_forward, target_right)
	var current_slot_id: String = ShipBoardingMetaHelper.get_slot_id(ship)
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
		if ShipBoardingSlot.get_id(slot) == current_slot_id:
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
	var movement_mode := _authoring_movement_mode(ship)

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
		return _build_authoring_movement_intent(
			ship,
			target_pos,
			desired_point,
			heading_point,
			dist_to_target,
			desired_speed_mult,
			permit_sprint,
			dir_to_target,
			movement_mode if not movement_mode.is_empty() else "yield_overrun"
		)

	if _is_gunner(ship):
		if movement_mode.is_empty():
			movement_mode = "gunner_standoff"
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
			if bow_sector_approach and approach_mode == ShipBoardingMetaHelper.APPROACH_SIDE:
				approach_mode = ShipBoardingMetaHelper.APPROACH_FRONT
			ShipBoardingMetaHelper.set_approach_mode(ship, approach_mode)
			var post_impact_follow_timer: float = ShipBoardingMetaHelper.get_post_impact_follow_timer(ship)
			var current_side_sign: float = ShipBoardingMetaHelper.get_side_sign(ship)
			var side_alignment_locked: bool = false
			if not bow_sector_approach and post_impact_follow_timer <= 0.0 and absf(current_side_sign) > 0.5:
				if absf(rel_side) >= collision_dist * 0.30 and absf(rel_forward) <= 10.0:
					approach_mode = ShipBoardingMetaHelper.APPROACH_SIDE
					ShipBoardingMetaHelper.set_approach_mode(ship, approach_mode)
			if not bow_sector_approach and ship.has_method("_is_side_boarding_approach") and ship.call("_is_side_boarding_approach", target_node) == true:
				if dist_to_target <= ship.boarding_break_distance - 0.4:
					var refreshed_timer: float = maxf(post_impact_follow_timer, 2.0)
					ShipBoardingMetaHelper.set_post_impact_follow_timer(ship, refreshed_timer)
					post_impact_follow_timer = refreshed_timer
					side_alignment_locked = true

			if target_deck_contested and not bow_sector_approach and approach_mode != ShipBoardingMetaHelper.APPROACH_REAR and dist_to_target <= ship.max_boarding_distance + 2.0:
				approach_mode = ShipBoardingMetaHelper.APPROACH_SIDE
				ShipBoardingMetaHelper.set_approach_mode(ship, approach_mode)
				side_alignment_locked = true
				post_impact_follow_timer = maxf(post_impact_follow_timer, 1.6)
				ShipBoardingMetaHelper.set_post_impact_follow_timer(ship, post_impact_follow_timer)

			if post_impact_follow_timer > 0.0 and not bow_sector_approach:
				var follow_nav: Dictionary = ShipBoardingNavigationHelper.build_side_follow(ship, target_node, target_pos, target_forward, target_right, rel_forward, rel_side, collision_dist, dist_to_target, true)
				desired_point = ShipMovementIntent.get_desired_point(follow_nav, desired_point)
				heading_point = ShipMovementIntent.get_heading_point(follow_nav, heading_point)
				desired_speed_mult = ShipMovementIntent.get_desired_speed_mult(follow_nav, desired_speed_mult)
				permit_sprint = ShipMovementIntent.get_permit_sprint(follow_nav, permit_sprint)
				movement_mode = _navigation_mode(follow_nav, movement_mode)
			elif approach_mode == ShipBoardingMetaHelper.APPROACH_SIDE and dist_to_target <= ship.max_boarding_distance + 1.35:
				var settle_nav: Dictionary = ShipBoardingNavigationHelper.build_contact_settle(ship, target_pos, target_forward, target_right, rel_forward, rel_side, collision_dist, dist_to_target)
				desired_point = ShipMovementIntent.get_desired_point(settle_nav, desired_point)
				heading_point = ShipMovementIntent.get_heading_point(settle_nav, heading_point)
				desired_speed_mult = ShipMovementIntent.get_desired_speed_mult(settle_nav, desired_speed_mult)
				permit_sprint = ShipMovementIntent.get_permit_sprint(settle_nav, permit_sprint)
				movement_mode = _navigation_mode(settle_nav, movement_mode)
			elif approach_mode == ShipBoardingMetaHelper.APPROACH_REAR:
				if dist_to_target <= ship.max_boarding_distance + 6.0:
					var rear_recovery_nav: Dictionary = ShipBoardingNavigationHelper.build_rear_recovery(ship, target_node, target_pos, target_forward, target_right, rel_side, collision_dist, dist_to_target)
					desired_point = ShipMovementIntent.get_desired_point(rear_recovery_nav, desired_point)
					heading_point = ShipMovementIntent.get_heading_point(rear_recovery_nav, heading_point)
					desired_speed_mult = ShipMovementIntent.get_desired_speed_mult(rear_recovery_nav, desired_speed_mult)
					permit_sprint = ShipMovementIntent.get_permit_sprint(rear_recovery_nav, permit_sprint)
					movement_mode = _navigation_mode(rear_recovery_nav, movement_mode)
				else:
					var slot: Dictionary = _choose_boarding_slot(ship, target_node, target_pos, target_forward, target_right)
					if not slot.is_empty():
						ShipBoardingMetaHelper.set_slot_id(ship, ShipBoardingSlot.get_id(slot))
						ShipBoardingMetaHelper.set_side_sign(ship, ShipBoardingSlot.get_side_sign(slot))
						desired_point = ShipBoardingSlot.get_point(slot, desired_point)
						heading_point = ShipBoardingSlot.get_heading(slot, heading_point)
					desired_speed_mult = 1.04 if dist_to_target > ship.max_boarding_distance + 1.0 else 0.94
					permit_sprint = dist_to_target > 7.0
			elif approach_mode == ShipBoardingMetaHelper.APPROACH_SIDE:
				var side_nav: Dictionary = ShipBoardingNavigationHelper.build_side_follow(ship, target_node, target_pos, target_forward, target_right, rel_forward, rel_side, collision_dist, dist_to_target, side_alignment_locked)
				desired_point = ShipMovementIntent.get_desired_point(side_nav, desired_point)
				heading_point = ShipMovementIntent.get_heading_point(side_nav, heading_point)
				desired_speed_mult = ShipMovementIntent.get_desired_speed_mult(side_nav, desired_speed_mult)
				permit_sprint = ShipMovementIntent.get_permit_sprint(side_nav, permit_sprint)
				movement_mode = _navigation_mode(side_nav, movement_mode)
			else:
				var front_impact_offset: float = clampf(collision_dist * 0.55, 3.0, 5.0)
				ShipBoardingMetaHelper.remove_meta_key(ship, ShipBoardingMetaHelper.KEY_SLOT_ID)
				ShipBoardingMetaHelper.remove_meta_key(ship, ShipBoardingMetaHelper.KEY_SIDE_SIGN)
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
		ShipBoardingMetaHelper.clear_navigation_meta(ship)

	if ship.get("limbo_ai_pilot_enabled") == true:
		var boarding_nav_locked: bool = _can_board(ship) and dist_to_target <= ship.boarding_break_distance + 1.5
		var nav_hint_target_id := int(ship.get_meta(ShipAILimboKeys.META_NAV_TARGET_ID, 0))
		var nav_hint_frame := int(ship.get_meta(ShipAILimboKeys.META_NAV_FRAME, -1000000))
		var nav_hint_is_current := Engine.get_physics_frames() - nav_hint_frame <= 4
		var nav_hint_matches_target := nav_hint_target_id == target_node.get_instance_id()
		if not boarding_nav_locked and nav_hint_is_current and nav_hint_matches_target:
			var hint_desired_point: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT, null)
			var hint_heading_point: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_HEADING_POINT, null)
			var hint_speed_mult: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_SPEED_MULT, null)
			var hint_permit_sprint: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_PERMIT_SPRINT, null)
			var hint_mode := str(ship.get_meta(ShipAILimboKeys.META_NAV_MODE, "")).strip_edges()
			if hint_desired_point is Vector3:
				desired_point = hint_desired_point
			if hint_heading_point is Vector3:
				heading_point = hint_heading_point
			if hint_speed_mult != null:
				desired_speed_mult = maxf(desired_speed_mult, float(hint_speed_mult))
			if hint_permit_sprint != null:
				permit_sprint = hint_permit_sprint == true
			if not hint_mode.is_empty():
				movement_mode = hint_mode

	return _build_authoring_movement_intent(
		ship,
		target_pos,
		desired_point,
		heading_point,
		dist_to_target,
		desired_speed_mult,
		permit_sprint,
		dir_to_target,
		movement_mode
	)
