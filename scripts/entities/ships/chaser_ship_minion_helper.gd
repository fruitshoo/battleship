extends RefCounted
class_name ChaserShipMinionHelper

const SUPPORT_FORMATION_SPACING := 10.0
const SUPPORT_JOIN_SPACING := 14.0
const SUPPORT_FLEET_ORDER_META := "support_fleet_order"
const SUPPORT_TRAIL_POINTS_META := "support_trail_points"
const SUPPORT_SLOT_SPEED_GAIN := 0.42
const SUPPORT_SLOT_BRAKE_GAIN := 0.55
const SUPPORT_MAX_CATCHUP_SPEED := 4.5
const SUPPORT_MAX_BRAKE_SPEED := 5.0
const SUPPORT_SPEED_RESPONSE := 3.0
const SUPPORT_LATERAL_SEP_SCALE := 0.18
const SUPPORT_FORMUP_DISTANCE := 1.75
const SUPPORT_FORMUP_SPEED_GAIN := 0.44
const SUPPORT_MAX_FORMUP_SPEED := 5.2
const SUPPORT_HEADING_CORRECTION_GAIN := 0.07
const SUPPORT_MAX_HEADING_CORRECTION := 0.42
const SUPPORT_TARGET_GUARD_RATIO := 0.84
const SUPPORT_DIRECT_STEER_DISTANCE := 7.0
const SUPPORT_BRAKE_LATERAL_TOLERANCE := 2.5
const SUPPORT_TRAIL_POINT_DISTANCE := 1.8
const SUPPORT_TRAIL_MAX_POINTS := 96

static func process_minion_ai(ship, delta: float) -> void:
	if not is_instance_valid(ship.target):
		ship._find_player()
		return

	var is_support_ship: bool = bool(ship.get_meta("support_fleet_ship", false))
	var minions: Array = _get_minion_roster(ship, is_support_ship)
	var my_index: int = minions.find(ship)
	if my_index == -1:
		my_index = 0

	var offset: Vector3 = _get_minion_offset(ship, my_index, is_support_ship)
	var player_fwd: Vector3 = -ship.target.global_transform.basis.z
	player_fwd.y = 0.0
	if player_fwd.length_squared() <= 0.0001:
		player_fwd = Vector3.FORWARD
	else:
		player_fwd = player_fwd.normalized()
	var player_right: Vector3 = player_fwd.cross(Vector3.UP).normalized()

	var sep_force = Vector3.ZERO
	for other in minions:
		if other != ship and is_instance_valid(other):
			var dist = ship.global_position.distance_to(other.global_position)
			if dist < 12.0 and dist > 0.1:
				var push_dir = (ship.global_position - other.global_position).normalized()
				var strength = (1.0 - (dist / 12.0)) * 5.0
				sep_force += push_dir * strength
	if is_support_ship:
		# Keep support ships from pushing each other forward/backward in line.
		sep_force = player_right * sep_force.dot(player_right) * SUPPORT_LATERAL_SEP_SCALE

	var target_pos = ship.target.to_global(offset)
	target_pos += sep_force

	var dist_to_target = ship.global_position.distance_to(target_pos)
	var player_speed = ship.target.get("current_speed")
	if player_speed == null:
		player_speed = 0.0
	var support_lead_ship: Node3D = ship.target
	var support_lead_fwd: Vector3 = player_fwd
	var support_lead_speed: float = float(player_speed)

	var to_target_vec = target_pos - ship.global_position
	var direction = to_target_vec.normalized()
	var rel_depth = to_target_vec.dot(player_fwd)
	var dist_to_player = ship.global_position.distance_to(ship.target.global_position)
	var is_joining_support: bool = ship.has_meta("support_joining") and bool(ship.get_meta("support_joining"))
	if is_support_ship:
		support_lead_ship = _get_support_lead_ship(ship, minions, my_index)
		_record_support_trail_point(support_lead_ship)
		support_lead_speed = _get_ship_speed(support_lead_ship, float(player_speed))
		var support_goal: Dictionary = _get_support_chain_goal(ship, minions, my_index, SUPPORT_FORMATION_SPACING)
		target_pos = support_goal.get("position", ship.global_position)
		support_lead_fwd = support_goal.get("forward", _get_ship_forward_flat(support_lead_ship))
		to_target_vec = target_pos - ship.global_position
		if to_target_vec.length_squared() > 0.0001:
			direction = to_target_vec.normalized()
		rel_depth = to_target_vec.dot(support_lead_fwd)
		dist_to_player = ship.global_position.distance_to(ship.target.global_position)
	if is_joining_support:
		var join_goal: Dictionary = _get_support_chain_goal(ship, minions, my_index, SUPPORT_JOIN_SPACING)
		target_pos = join_goal.get("position", ship.global_position)
		support_lead_fwd = join_goal.get("forward", support_lead_fwd)
		target_pos += sep_force * 0.15
		to_target_vec = target_pos - ship.global_position
		if to_target_vec.length_squared() > 0.0001:
			direction = to_target_vec.normalized()
		var dist_to_join_target: float = ship.global_position.distance_to(target_pos)
		dist_to_player = ship.global_position.distance_to(ship.target.global_position)
		if dist_to_join_target <= 14.0 or dist_to_player <= 20.0:
			ship.set_meta("support_joining", false)
			is_joining_support = false
	dist_to_target = ship.global_position.distance_to(target_pos)

	var target_final_speed = player_speed
	if is_joining_support:
		target_final_speed = maxf(player_speed + 3.0, ship.move_speed * 1.9)
	elif is_support_ship:
		var slot_depth_error: float = rel_depth
		var slot_lateral_error: float = absf(to_target_vec.dot(support_lead_fwd.cross(Vector3.UP).normalized()))
		var speed_offset: float = 0.0
		if slot_depth_error >= 0.0:
			speed_offset = min(slot_depth_error * SUPPORT_SLOT_SPEED_GAIN, SUPPORT_MAX_CATCHUP_SPEED)
		else:
			if dist_to_target <= SUPPORT_DIRECT_STEER_DISTANCE and slot_lateral_error <= SUPPORT_BRAKE_LATERAL_TOLERANCE:
				speed_offset = -min(abs(slot_depth_error) * SUPPORT_SLOT_BRAKE_GAIN, SUPPORT_MAX_BRAKE_SPEED)
		var formup_speed: float = 0.0
		if dist_to_target > SUPPORT_FORMUP_DISTANCE:
			formup_speed = min((dist_to_target - SUPPORT_FORMUP_DISTANCE) * SUPPORT_FORMUP_SPEED_GAIN, SUPPORT_MAX_FORMUP_SPEED)
		target_final_speed = maxf(maxf(support_lead_speed + speed_offset, formup_speed), 0.0)
		if dist_to_target <= 2.0:
			target_final_speed = lerp(target_final_speed, support_lead_speed, 0.85)
	elif dist_to_player < 10.0:
		target_final_speed = 0.0
	elif rel_depth < -0.5:
		var brake_factor = clamp(abs(rel_depth) / 10.0, 0.0, 0.9)
		target_final_speed = player_speed * (1.0 - brake_factor)
	else:
		var lag_factor = clamp(rel_depth / 60.0, 0.0, 1.0)
		var sync_speed_mult = lerp(1.0, 1.3, lag_factor)
		target_final_speed = max(player_speed * sync_speed_mult, ship.move_speed * 0.8)

	var speed_response: float = SUPPORT_SPEED_RESPONSE if is_support_ship else 1.2
	ship._last_ai_speed = lerp(ship._last_ai_speed, target_final_speed, delta * speed_response)
	var final_move_speed = ship._last_ai_speed
	ship.current_speed = maxf(final_move_speed, 0.0)

	var target_head_rot = atan2(-direction.x, -direction.z)
	var player_head_rot = ship.rotation.y
	if ship.target and "rotation" in ship.target:
		player_head_rot = ship.target.rotation.y
	if is_support_ship:
		var lead_head_rot: float = player_head_rot
		if support_lead_fwd.length_squared() > 0.0001:
			lead_head_rot = atan2(-support_lead_fwd.x, -support_lead_fwd.z)
		elif is_instance_valid(support_lead_ship):
			lead_head_rot = support_lead_ship.rotation.y
		var lead_right: Vector3 = support_lead_fwd.cross(Vector3.UP).normalized()
		var lateral_error: float = to_target_vec.dot(lead_right)
		var heading_correction: float = clamp(-lateral_error * SUPPORT_HEADING_CORRECTION_GAIN, -SUPPORT_MAX_HEADING_CORRECTION, SUPPORT_MAX_HEADING_CORRECTION)
		player_head_rot = lead_head_rot
		var aligned_head_rot: float = lead_head_rot + heading_correction
		if dist_to_target > SUPPORT_DIRECT_STEER_DISTANCE:
			target_head_rot = lerp_angle(aligned_head_rot, atan2(-direction.x, -direction.z), 0.75)
		else:
			target_head_rot = aligned_head_rot

	var rotation_blend = clamp(dist_to_target / 15.0, 0.0, 1.0)
	var blended_target_rot = lerp_angle(player_head_rot, target_head_rot, rotation_blend)
	var angle_diff = wrapf(blended_target_rot - ship.rotation.y, -PI, PI)
	var desired_rudder = clamp(-rad_to_deg(angle_diff) * 2.0, -45.0, 45.0)
	var rudder_speed_adjusted = 120.0
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	if final_move_speed > 0.1:
		var speed_ratio = final_move_speed / ship.max_speed
		var actual_turn = (ship.rudder_angle / 45.0) * ship.turn_rate * speed_ratio * ship.turn_mult * delta
		ship.rotation.y -= deg_to_rad(actual_turn)
	else:
		if dist_to_target <= 1.5:
			ship.rotation.y = lerp_angle(ship.rotation.y, player_head_rot, delta * 3.0)

	var wind_mult = ChaserShipAiHelper._calculate_sail_drive_multiplier(ship, 0.6)
	final_move_speed *= wind_mult
	var forward_vec = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	var velocity = forward_vec * final_move_speed
	velocity += ship.separation_force
	velocity += ship._calculate_collision_repulsion() * delta

	var prev_pos = ship.global_position
	var next_pos = prev_pos + velocity * delta
	if is_instance_valid(ship.target):
		var target_guard_ratio: float = SUPPORT_TARGET_GUARD_RATIO if is_support_ship else 0.94
		next_pos = ship._apply_ship_collision_guard(ship.target, prev_pos, next_pos, target_guard_ratio, velocity.length(), false)
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, ship.target)
	ship.global_position = next_pos
	if is_support_ship:
		_record_support_trail_point(ship)

	ship._update_rudder_visual()
	ship._apply_bobbing_effect()
	ship._set_wake_state(dist_to_target > 2.0 or player_speed > 1.0, clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0), 0.0, 0.0)
	if is_support_ship:
		ship.set_meta("support_debug_lead_name", support_lead_ship.name if is_instance_valid(support_lead_ship) else "none")
		ship.set_meta("support_debug_target_pos", target_pos)
		ship.set_meta("support_debug_slot_dist", dist_to_target)
		ship.set_meta("support_debug_rel_depth", rel_depth)
		ship.set_meta("support_debug_player_speed", float(player_speed))
		ship.set_meta("support_debug_lead_speed", float(support_lead_speed))
		ship.set_meta("support_debug_target_speed", float(target_final_speed))

static func _get_minion_roster(ship, support_only: bool) -> Array:
	var roster: Array = []
	var all_minions: Array = ship.get_minions_cached(ship.get_tree())
	for minion in all_minions:
		if not is_instance_valid(minion):
			continue
		if support_only and bool(minion.get_meta("support_fleet_ship", false)) == false:
			continue
		roster.append(minion)
	if support_only:
		roster.sort_custom(func(a, b):
			return int(a.get_meta(SUPPORT_FLEET_ORDER_META, a.get_instance_id())) < int(b.get_meta(SUPPORT_FLEET_ORDER_META, b.get_instance_id()))
		)
	return roster

static func _get_minion_offset(ship, my_index: int, is_support_ship: bool) -> Vector3:
	if is_support_ship:
		return _get_support_fleet_offset(my_index)

	var offset: Vector3 = Vector3.ZERO
	var base_spacing: float = 10.0
	var formation_dist: float = base_spacing + (my_index * base_spacing)

	match int(ship.fleet_formation):
		0:
			offset = Vector3(0, 0, formation_dist)
		1:
			var side: int = 1 if my_index % 2 == 0 else -1
			var row: float = floor(my_index / 2.0) + 1
			offset = Vector3(base_spacing * side * row, 0, base_spacing * row)
	return offset

static func _get_support_fleet_offset(my_index: int) -> Vector3:
	var trailing: float = SUPPORT_FORMATION_SPACING + (my_index * SUPPORT_FORMATION_SPACING)
	return Vector3(0.0, 0.0, trailing)

static func _get_support_join_offset(my_index: int) -> Vector3:
	var trailing: float = 18.0 + (my_index * SUPPORT_JOIN_SPACING)
	return Vector3(0.0, 0.0, trailing)

static func _get_support_chain_goal(ship, minions: Array, my_index: int, trailing_distance: float) -> Dictionary:
	if not is_instance_valid(ship.target):
		return {"position": ship.global_position, "forward": Vector3.FORWARD}
	var lead_ship: Node3D = _get_support_lead_ship(ship, minions, my_index)
	var lead_fwd: Vector3 = _get_ship_forward_flat(lead_ship)
	var follow_distance: float = _get_support_follow_distance(ship, lead_ship, trailing_distance)
	return _get_support_trail_goal(lead_ship, follow_distance, lead_fwd)

static func _get_support_follow_distance(follower_ship: Node3D, lead_ship: Node3D, minimum_spacing: float) -> float:
	if not is_instance_valid(follower_ship) or not is_instance_valid(lead_ship):
		return minimum_spacing
	if follower_ship.has_method("get_collision_distance_to"):
		var safe_follow_distance: float = float(follower_ship.call("get_collision_distance_to", lead_ship)) + 2.0
		return maxf(minimum_spacing, safe_follow_distance)
	return minimum_spacing

static func _get_support_lead_ship(ship, minions: Array, my_index: int) -> Node3D:
	if my_index <= 0:
		return ship.target
	for i in range(my_index - 1, -1, -1):
		var candidate = minions[i]
		if is_instance_valid(candidate):
			return candidate
	return ship.target

static func _get_ship_forward_flat(node: Node3D) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.FORWARD
	var fwd: Vector3 = -node.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return fwd.normalized()

static func _get_ship_speed(node: Node3D, fallback: float) -> float:
	if not is_instance_valid(node):
		return fallback
	var speed = node.get("current_speed")
	if speed == null:
		return fallback
	return float(speed)

static func _record_support_trail_point(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var points: Array = node.get_meta(SUPPORT_TRAIL_POINTS_META, [])
	var current_pos: Vector3 = node.global_position
	if points.is_empty():
		points.append(current_pos)
	else:
		var last_point: Variant = points[points.size() - 1]
		if last_point is Vector3 and Vector3(last_point).distance_to(current_pos) >= SUPPORT_TRAIL_POINT_DISTANCE:
			points.append(current_pos)
	while points.size() > SUPPORT_TRAIL_MAX_POINTS:
		points.remove_at(0)
	node.set_meta(SUPPORT_TRAIL_POINTS_META, points)

static func _get_support_trail_goal(lead_ship: Node3D, trailing_distance: float, fallback_forward: Vector3) -> Dictionary:
	if not is_instance_valid(lead_ship):
		return {"position": Vector3.ZERO, "forward": fallback_forward}
	var trail_points: Array = lead_ship.get_meta(SUPPORT_TRAIL_POINTS_META, [])
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
				"forward": segment_forward
			}
		remaining_distance -= segment_length
		segment_end = segment_start

	return {"position": segment_end, "forward": fallback_forward}
