extends RefCounted
class_name ChaserShipMinionHelper


const SUPPORT_FORMATION_SPACING := 10.0
const SUPPORT_JOIN_SPACING := 14.0
const SUPPORT_FLEET_ORDER_META := "support_fleet_order"
const SUPPORT_TRAIL_POINTS_META := "support_trail_points"
const SUPPORT_ANCHOR_POS_META := "support_anchor_position"
const SUPPORT_ANCHOR_FWD_META := "support_anchor_forward"
const SUPPORT_IDLE_ORBIT_TIME_META := "support_idle_orbit_time"
const SUPPORT_SLOT_SPEED_GAIN := 0.31
const SUPPORT_SLOT_BRAKE_GAIN := 0.55
const SUPPORT_MAX_CATCHUP_SPEED := 3.25
const SUPPORT_MAX_BRAKE_SPEED := 5.0
const SUPPORT_SPEED_RESPONSE := 2.25
const SUPPORT_LATERAL_SEP_SCALE := 0.18
const SUPPORT_FORMUP_DISTANCE := 1.75
const SUPPORT_FORMUP_SPEED_GAIN := 0.32
const SUPPORT_MAX_FORMUP_SPEED := 3.85
const SUPPORT_HEADING_CORRECTION_GAIN := 0.07
const SUPPORT_MAX_HEADING_CORRECTION := 0.42
const SUPPORT_TARGET_GUARD_RATIO := 0.84
const SUPPORT_DIRECT_STEER_DISTANCE := 7.0
const SUPPORT_BRAKE_LATERAL_TOLERANCE := 2.5
const SUPPORT_TRAIL_POINT_DISTANCE := 1.8
const SUPPORT_TRAIL_MAX_POINTS := 96
const SUPPORT_IDLE_ORBIT_RADIUS := 11.0
const SUPPORT_IDLE_ORBIT_SPEED := 0.65
const SUPPORT_IDLE_SPEED_RESPONSE := 2.4
const SUPPORT_ASSIST_THREAT_RANGE := 34.0
const SUPPORT_ASSIST_CLOSE_RANGE := 22.0
const SUPPORT_ASSIST_SOFT_RECALL_DISTANCE := 32.0
const SUPPORT_ASSIST_RECALL_DISTANCE := 36.0
const SUPPORT_ASSIST_LEASH_DISTANCE := 46.0
const SUPPORT_ASSIST_SPEED_RESPONSE := 1.85
const SUPPORT_ASSIST_EMERGENCY_THREAT_RANGE := 58.0
const SUPPORT_ASSIST_EMERGENCY_RECALL_DISTANCE := 80.0
const SUPPORT_ASSIST_EMERGENCY_LEASH_DISTANCE := 92.0
const SUPPORT_ASSIST_EMERGENCY_SPEED_RESPONSE := 2.05
const SUPPORT_ASSIST_SEPARATION_RADIUS := 10.0
const SUPPORT_ASSIST_SEPARATION_FORCE := 1.1
const SUPPORT_ASSIST_ROWING_WIND_FLOOR := 0.78
const SUPPORT_ASSIST_EMERGENCY_ROWING_WIND_FLOOR := 0.82
const SUPPORT_ASSIST_ROWING_SPEED_BONUS := 0.24
const SUPPORT_ASSIST_EMERGENCY_ROWING_SPEED_BONUS := 0.30
const SUPPORT_ASSIST_TARGET_ID_META := "support_assist_target_id"
const SUPPORT_ASSIST_LOCK_TIMER_META := "support_assist_lock_timer"
const SUPPORT_ASSIST_LANE_SIDE_META := "support_assist_lane_side"
const SUPPORT_ASSIST_TARGET_LOCK_DURATION := 3.25
const SUPPORT_ASSIST_SWITCH_MARGIN := 10.0
const SUPPORT_BOARDING_CONTACT_PAD := 0.85
const SUPPORT_RESCUE_BOARDING_START_PAD := SUPPORT_BOARDING_CONTACT_PAD

static func process_minion_ai(ship, delta: float) -> void:
	var is_support_ship: bool = ShipAllyRoleHelper.is_support_ship(ship)
	if not is_instance_valid(ship.target) or _is_ship_disabled(ship.target):
		ship._find_player()
		if not is_instance_valid(ship.target) or _is_ship_disabled(ship.target):
			if is_support_ship and _has_support_anchor(ship):
				_process_support_idle_patrol(ship, delta)
			return

	if is_support_ship:
		_record_support_anchor(ship, ship.target)

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
	var support_assist_target: Node3D = null

	var to_target_vec = target_pos - ship.global_position
	var direction = to_target_vec.normalized()
	var rel_depth = to_target_vec.dot(player_fwd)
	var dist_to_player = ship.global_position.distance_to(ship.target.global_position)
	var is_joining_support: bool = ship.has_meta("support_joining") and ship.get_meta("support_joining") == true
	if is_support_ship:
		support_lead_ship = _get_support_lead_ship(ship, minions, my_index)
		_record_support_trail_point(support_lead_ship)
		support_lead_speed = _get_ship_speed(support_lead_ship, float(player_speed))
		var support_goal: Dictionary = _get_support_chain_goal(ship, minions, my_index, SUPPORT_FORMATION_SPACING)
		target_pos = support_goal.get("position", ship.global_position)
		support_lead_fwd = support_goal.get("forward", _get_ship_forward_flat(support_lead_ship))
		support_assist_target = _get_support_assist_target(ship, ship.target, delta)
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
	if is_support_ship and not is_joining_support and is_instance_valid(support_assist_target):
		if _try_start_support_boarding(ship, support_assist_target, delta):
			return
		_process_support_assist_ai(ship, delta, support_assist_target, minions, my_index)
		return

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
	var rudder_speed_adjusted = 120.0 * ship.get_rudder_response_multiplier()
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	if final_move_speed > 0.1:
		var speed_ratio = final_move_speed / ship.max_speed
		var actual_turn = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * delta
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
		ShipBoardingMetaHelper.set_support_debug_mode(ship, ShipBoardingMetaHelper.SUPPORT_DEBUG_TRAIL)

static func _is_ship_disabled(node: Node3D) -> bool:
	if not is_instance_valid(node):
		return true
	if node.has_method("is_sinking_or_dying"):
		return node.is_sinking_or_dying()
	var is_sinking: Variant = node.get("is_sinking")
	var is_dying: Variant = node.get("is_dying")
	return is_sinking == true or is_dying == true

static func _record_support_anchor(ship, target_ship: Node3D) -> void:
	if not is_instance_valid(target_ship):
		return
	var anchor_pos: Vector3 = target_ship.global_position
	anchor_pos.y = ship.global_position.y
	ship.set_meta(SUPPORT_ANCHOR_POS_META, anchor_pos)
	ship.set_meta(SUPPORT_ANCHOR_FWD_META, _get_ship_forward_flat(target_ship))

static func _has_support_anchor(ship) -> bool:
	if not ship.has_meta(SUPPORT_ANCHOR_POS_META):
		return false
	var anchor_pos: Variant = ship.get_meta(SUPPORT_ANCHOR_POS_META, null)
	return anchor_pos is Vector3

static func _process_support_idle_patrol(ship, delta: float) -> void:
	var anchor_variant: Variant = ship.get_meta(SUPPORT_ANCHOR_POS_META, null)
	if not (anchor_variant is Vector3):
		ship.current_speed = move_toward(float(ship.current_speed), 0.0, delta * 2.0)
		ship._set_wake_state(false)
		return

	var anchor_pos: Vector3 = anchor_variant
	var anchor_fwd_variant: Variant = ship.get_meta(SUPPORT_ANCHOR_FWD_META, Vector3.FORWARD)
	var anchor_fwd: Vector3 = anchor_fwd_variant if anchor_fwd_variant is Vector3 else Vector3.FORWARD
	anchor_fwd.y = 0.0
	if anchor_fwd.length_squared() <= 0.0001:
		anchor_fwd = Vector3.FORWARD
	else:
		anchor_fwd = anchor_fwd.normalized()
	var anchor_right: Vector3 = anchor_fwd.cross(Vector3.UP).normalized()

	var order_index: int = int(ship.get_meta(SUPPORT_FLEET_ORDER_META, 0))
	var orbit_time: float = float(ship.get_meta(SUPPORT_IDLE_ORBIT_TIME_META, 0.0)) + delta
	ship.set_meta(SUPPORT_IDLE_ORBIT_TIME_META, orbit_time)
	var orbit_angle: float = orbit_time * SUPPORT_IDLE_ORBIT_SPEED + (float(order_index) * 1.35)
	var orbit_radius: float = SUPPORT_IDLE_ORBIT_RADIUS + float(order_index) * 3.0
	var target_pos: Vector3 = anchor_pos
	target_pos += anchor_right * cos(orbit_angle) * orbit_radius
	target_pos += anchor_fwd * sin(orbit_angle) * orbit_radius * 0.75
	target_pos.y = ship.global_position.y

	var to_target: Vector3 = target_pos - ship.global_position
	to_target.y = 0.0
	var dist_to_target: float = to_target.length()
	var desired_dir: Vector3 = to_target.normalized() if dist_to_target > 0.001 else anchor_fwd
	var target_heading: float = atan2(-desired_dir.x, -desired_dir.z)
	var angle_diff: float = wrapf(target_heading - ship.rotation.y, -PI, PI)
	var desired_rudder: float = clamp(-rad_to_deg(angle_diff) * 2.0, -40.0, 40.0)
	var rudder_speed_adjusted: float = 120.0 * ship.get_rudder_response_multiplier()
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	var desired_speed: float = clampf(dist_to_target * 0.45, 1.4, ship.move_speed * 0.65)
	ship._last_ai_speed = lerp(ship._last_ai_speed, desired_speed, delta * SUPPORT_IDLE_SPEED_RESPONSE)
	ship.current_speed = maxf(ship._last_ai_speed, 0.0)

	var speed_ratio: float = ship.current_speed / maxf(ship.max_speed, 0.01)
	var actual_turn: float = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * delta
	ship.rotation.y -= deg_to_rad(actual_turn)

	var forward_vec: Vector3 = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	var velocity: Vector3 = forward_vec * ship.current_speed
	var prev_pos: Vector3 = ship.global_position
	var next_pos: Vector3 = prev_pos + velocity * delta
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos)
	ship.global_position = next_pos
	_record_support_trail_point(ship)
	ship._update_rudder_visual()
	ship._apply_bobbing_effect()
	ship._set_wake_state(ship.current_speed > 0.4, clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0), 0.0, 0.0)
	ship.set_meta("support_debug_lead_name", "anchor")
	ship.set_meta("support_debug_target_pos", target_pos)
	ship.set_meta("support_debug_slot_dist", dist_to_target)
	ship.set_meta("support_debug_rel_depth", 0.0)
	ship.set_meta("support_debug_player_speed", 0.0)
	ship.set_meta("support_debug_lead_speed", 0.0)
	ship.set_meta("support_debug_target_speed", desired_speed)

static func _process_support_assist_ai(ship, delta: float, assist_target: Node3D, minions: Array, my_index: int) -> void:
	if not is_instance_valid(assist_target) or _is_ship_disabled(assist_target):
		return
	var emergency_assist: bool = _is_player_deck_emergency(ship.target)

	var nav: Dictionary = _build_support_assist_navigation(ship, assist_target, my_index)
	var desired_point: Vector3 = ShipMovementIntent.get_desired_point(nav, assist_target.global_position)
	var heading_point: Vector3 = ShipMovementIntent.get_heading_point(nav, desired_point)
	var dist_to_target: float = ShipMovementIntent.get_dist_to_target(nav, ship.global_position.distance_to(assist_target.global_position))
	var desired_speed_mult: float = ShipMovementIntent.get_desired_speed_mult(nav)

	var move_vector: Vector3 = desired_point - ship.global_position
	move_vector.y = 0.0
	var move_dir: Vector3 = move_vector.normalized() if move_vector.length_squared() > 0.001 else Vector3.ZERO
	var local_sep: Vector3 = _calculate_support_assist_separation(ship, minions, assist_target)
	if local_sep.length_squared() > 0.001:
		move_dir = local_sep.normalized() if move_dir == Vector3.ZERO else (move_dir + local_sep).normalized()

	var heading_vector: Vector3 = heading_point - ship.global_position
	heading_vector.y = 0.0
	if heading_vector.length_squared() <= 0.001:
		heading_vector = move_dir if move_dir.length_squared() > 0.001 else _get_ship_forward_flat(assist_target)
	var target_rotation_y: float = atan2(-heading_vector.x, -heading_vector.z)
	var angle_diff: float = wrapf(target_rotation_y - ship.rotation.y, -PI, PI)
	var desired_rudder: float = clamp(-rad_to_deg(angle_diff) * ship.ai_rudder_gain, -40.0, 40.0)
	var close_turn_blend: float = 0.0
	if ship.ai_close_turn_soft_radius > 0.01:
		close_turn_blend = clamp(1.0 - (dist_to_target / ship.ai_close_turn_soft_radius), 0.0, 1.0)
	var close_turn_factor: float = lerp(1.0, ship.ai_close_turn_scale, close_turn_blend)
	desired_rudder *= close_turn_factor
	var rudder_speed_adjusted: float = ship.ai_rudder_response_speed * ship.get_rudder_response_multiplier()
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	var leak_speed_mult: float = clamp(1.0 - (ship.leaking_rate * 0.05), 0.3, 1.0)
	var desired_speed: float = ship.move_speed * leak_speed_mult * desired_speed_mult * ship.get_shiphandling_multiplier()
	var rowing_speed_mult := _get_support_assist_rowing_speed_multiplier(dist_to_target, emergency_assist)
	desired_speed *= rowing_speed_mult
	var assist_speed_response: float = SUPPORT_ASSIST_EMERGENCY_SPEED_RESPONSE if emergency_assist else SUPPORT_ASSIST_SPEED_RESPONSE
	ship._last_ai_speed = lerp(float(ship._last_ai_speed), desired_speed, delta * assist_speed_response)
	var assist_accel_mult: float = 1.45 if emergency_assist else 1.0
	if ship._last_ai_speed > ship.current_speed:
		ship.current_speed = move_toward(ship.current_speed, ship._last_ai_speed, ship.acceleration * assist_accel_mult * delta)
	else:
		ship.current_speed = move_toward(ship.current_speed, ship._last_ai_speed, ship.deceleration * delta)

	var wind_floor := _get_support_assist_rowing_wind_floor(emergency_assist)
	var wind_mult: float = ChaserShipAiHelper._calculate_sail_drive_multiplier(ship, wind_floor) * ship.get_shiphandling_multiplier()
	if ship.current_speed > 0.1:
		var speed_ratio: float = clamp(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0)
		var turn_scale: float = ship.ai_turn_authority * close_turn_factor
		var actual_turn: float = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * turn_scale * delta
		var max_turn_this_frame: float = ship.ai_max_turn_rate * (0.82 if emergency_assist else 0.68) * delta
		actual_turn = clamp(actual_turn, -max_turn_this_frame, max_turn_this_frame)
		ship.rotation.y -= deg_to_rad(actual_turn)

	var forward_vec: Vector3 = Vector3(-sin(ship.rotation.y), 0.0, -cos(ship.rotation.y))
	var velocity: Vector3 = forward_vec * ship.current_speed * wind_mult
	velocity += local_sep
	velocity += ship._calculate_collision_repulsion() * 0.45 * delta

	var prev_pos: Vector3 = ship.global_position
	var next_pos: Vector3 = prev_pos + velocity * delta
	next_pos = ship._apply_ship_collision_guard(assist_target, prev_pos, next_pos, 0.9, velocity.length(), false)
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, assist_target)
	ship.global_position = next_pos
	_record_support_trail_point(ship)

	ship._update_rudder_visual()
	if ship.leaking_rate > 0:
		ship.take_damage(ship.leaking_rate * delta)
	ship._apply_bobbing_effect()
	ship._set_wake_state(ship.current_speed > 0.4, clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0), 0.0, 0.0)
	ship.set_meta("support_debug_lead_name", assist_target.name)
	ship.set_meta("support_debug_target_pos", desired_point)
	ship.set_meta("support_debug_slot_dist", ship.global_position.distance_to(desired_point))
	ship.set_meta("support_debug_rel_depth", 0.0)
	ship.set_meta("support_debug_player_speed", 0.0)
	ship.set_meta("support_debug_lead_speed", _get_ship_speed(assist_target, 0.0))
	ship.set_meta("support_debug_target_speed", desired_speed)
	ship.set_meta("support_debug_rowing_speed_mult", rowing_speed_mult)
	ship.set_meta("support_debug_wind_floor", wind_floor)
	ship.set_meta("support_debug_assist_target", assist_target.name)
	ShipBoardingMetaHelper.set_support_debug_mode(ship, ShipBoardingMetaHelper.SUPPORT_DEBUG_ASSIST)


static func _get_support_assist_rowing_speed_multiplier(dist_to_target: float, emergency_assist: bool) -> float:
	var distance_blend := clampf((dist_to_target - 10.0) / 28.0, 0.0, 1.0)
	var max_bonus := SUPPORT_ASSIST_EMERGENCY_ROWING_SPEED_BONUS if emergency_assist else SUPPORT_ASSIST_ROWING_SPEED_BONUS
	return 1.0 + (max_bonus * distance_blend)


static func _get_support_assist_rowing_wind_floor(emergency_assist: bool) -> float:
	return SUPPORT_ASSIST_EMERGENCY_ROWING_WIND_FLOOR if emergency_assist else SUPPORT_ASSIST_ROWING_WIND_FLOOR


static func _try_start_support_boarding(ship, assist_target: Node3D, delta: float) -> bool:
	if not _can_support_board_target(ship, assist_target):
		return false
	if ship.has_method("_can_start_boarding_latched"):
		var dist_to_target: float = ship.global_position.distance_to(assist_target.global_position)
		var can_side_board: bool = ship.has_method("_is_side_boarding_approach") and ship.call("_is_side_boarding_approach", assist_target) == true
		var can_cleanup_board: bool = ship.has_method("_can_force_cleanup_boarding") and ship.call("_can_force_cleanup_boarding", assist_target) == true
		ship.call("_can_start_boarding_latched", assist_target, dist_to_target, can_side_board, false, can_cleanup_board, delta)

	_start_support_boarding_link(ship, assist_target)
	if ship.is_boarding and ship.has_method("_process_boarding"):
		ship._process_boarding(delta)
	return ship.is_boarding


static func _can_support_board_target(ship, assist_target: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(assist_target):
		return false
	if not ShipAllyRoleHelper.is_support_ship(ship):
		return false
	if ship.get_team_tag() != "player":
		return false
	if ship.is_boarding:
		return false
	if _is_ship_disabled(assist_target):
		return false
	var target_team: String = assist_target.get_team_tag() if assist_target.has_method("get_team_tag") else str(assist_target.get("team"))
	var rescue_boarding: bool = _is_support_rescue_target(ship, assist_target)
	if rescue_boarding:
		if target_team != "player":
			return false
	else:
		if target_team != "enemy":
			return false
		if assist_target.get("is_derelict") == true:
			return false
	if ship.has_method("get_alive_crew_count") and ship.get_alive_crew_count() <= 1:
		return false

	var center_distance: float = ship.global_position.distance_to(assist_target.global_position)
	var collision_distance: float = ship.max_boarding_distance
	if ship.has_method("get_collision_distance_to"):
		collision_distance = float(ship.get_collision_distance_to(assist_target))
	var contact_pad: float = SUPPORT_RESCUE_BOARDING_START_PAD if rescue_boarding else SUPPORT_BOARDING_CONTACT_PAD
	var contact_boarding_limit: float = maxf(ship.max_boarding_distance, collision_distance + contact_pad)
	if center_distance > contact_boarding_limit:
		return false

	# Rescue boarding is an emergency docking action. Once the support ship is
	# close enough, let boarding motion settle the exact angle instead of
	# falling back to ranged support while the flagship deck is being overrun.
	if rescue_boarding:
		return true
	if ship.has_method("_is_side_boarding_approach") and ship._is_side_boarding_approach(assist_target):
		return true
	if ship.has_method("_can_force_cleanup_boarding") and ship._can_force_cleanup_boarding(assist_target):
		return true
	return false


static func _start_support_boarding_link(ship, assist_target: Node3D) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(assist_target):
		return
	var rescue_boarding: bool = _is_support_rescue_target(ship, assist_target)
	ship.is_boarding = true
	ship.boarding_target = assist_target
	ShipBoardingMetaHelper.set_boarding_purpose(ship, SupportBoardingHelper.get_boarding_purpose(rescue_boarding))
	if ship.has_method("_is_side_boarding_approach") and ship._is_side_boarding_approach(assist_target):
		ShipBoardingMetaHelper.set_contact_mode(ship, ShipBoardingMetaHelper.CONTACT_SIDE)
	else:
		ShipBoardingMetaHelper.set_contact_mode(ship, ShipBoardingMetaHelper.CONTACT_CLEANUP)

	var hold_forward: Vector3 = -ship.global_transform.basis.z
	hold_forward.y = 0.0
	if hold_forward.length_squared() > 0.001:
		ShipBoardingMetaHelper.set_hold_forward(ship, hold_forward.normalized())
	if not rescue_boarding and assist_target.has_method("set_boarding_attacker_ship"):
		assist_target.set_boarding_attacker_ship(ship)
	if ship.has_method("_clear_ropes"):
		ship._clear_ropes()
	ship.boarding_timer = 0.0
	ship.boarding_prep_timer = 0.0
	ship.boarding_contact_timer = 0.0
	ship.boarding_hook_timer = 0.0
	ship.boarding_secondary_rope_timer = 0.0
	ShipBoardingMetaHelper.set_motion_settle_timer(ship, 0.0)
	ship._initial_rope_deployed = false
	ship._full_rope_deployed = false
	if ship.has_method("_clear_boarding_latch"):
		ship._clear_boarding_latch()
	ShipBoardingMetaHelper.set_support_debug_mode(ship, ShipBoardingMetaHelper.SUPPORT_DEBUG_BOARDING)
	ship.set_meta("support_debug_assist_target", assist_target.name)

static func _build_support_assist_navigation(ship, assist_target: Node3D, my_index: int) -> Dictionary:
	var player_ship: Node3D = ship.target if is_instance_valid(ship.target) else null
	var emergency_assist: bool = _is_player_deck_emergency(player_ship)
	var rescue_assist: bool = _is_support_rescue_target(ship, assist_target)
	var player_fwd: Vector3 = _get_ship_forward_flat(player_ship) if is_instance_valid(player_ship) else _get_ship_forward_flat(ship)
	var player_right: Vector3 = player_fwd.cross(Vector3.UP)
	if player_right.length_squared() <= 0.0001:
		player_right = Vector3.RIGHT
	else:
		player_right = player_right.normalized()

	var target_id: int = assist_target.get_instance_id()
	var current_target_id: int = int(ship.get_meta(SUPPORT_ASSIST_TARGET_ID_META, 0))
	var lane_side: float = float(ship.get_meta(SUPPORT_ASSIST_LANE_SIDE_META, 0.0))
	if current_target_id != target_id or absf(lane_side) < 0.5:
		var rel_to_player: Vector3 = ship.global_position - player_ship.global_position if is_instance_valid(player_ship) else ship.global_position - assist_target.global_position
		rel_to_player.y = 0.0
		lane_side = signf(rel_to_player.dot(player_right))
		if absf(lane_side) < 0.5:
			lane_side = 1.0 if (my_index % 2) == 0 else -1.0
		ship.set_meta(SUPPORT_ASSIST_LANE_SIDE_META, lane_side)
	ship.set_meta(SUPPORT_ASSIST_TARGET_ID_META, target_id)

	var pair_index: int = int(floor(float(my_index) / 2.0))
	var collision_distance: float = ship.get_collision_distance_to(assist_target)
	var lane_distance: float = 0.0
	var rear_bias: float = 0.0
	if rescue_assist:
		lane_distance = maxf(4.0, collision_distance * 0.92) + float(pair_index) * 0.8
		rear_bias = float(pair_index) * 0.4
	else:
		var lane_base: float = 8.0 if emergency_assist else 11.0
		var lane_step: float = 1.6 if emergency_assist else 2.5
		var lane_clearance: float = 1.6 if emergency_assist else 3.2
		lane_distance = maxf(lane_base + float(pair_index) * lane_step, collision_distance + lane_clearance)
		rear_bias = (0.8 + float(pair_index) * 0.8) if emergency_assist else (2.4 + float(pair_index) * 1.2)
	var desired_point: Vector3 = assist_target.global_position
	desired_point += player_right * lane_side * lane_distance
	desired_point -= player_fwd * rear_bias
	desired_point.y = ship.global_position.y

	if is_instance_valid(player_ship) and not rescue_assist:
		var player_clearance: float = maxf(10.0, ship.get_collision_distance_to(player_ship) + 3.0)
		var from_player: Vector3 = desired_point - player_ship.global_position
		from_player.y = 0.0
		if from_player.length_squared() < player_clearance * player_clearance:
			desired_point = player_ship.global_position + from_player.normalized() * player_clearance if from_player.length_squared() > 0.001 else player_ship.global_position + player_right * lane_side * player_clearance
			desired_point.y = ship.global_position.y

	var dist_to_lane: float = ship.global_position.distance_to(desired_point)
	var heading_point: Vector3 = assist_target.global_position
	if dist_to_lane > (9.0 if emergency_assist else 13.0):
		heading_point = desired_point
	var desired_speed_mult: float = clampf(
		dist_to_lane / (9.0 if rescue_assist else (11.0 if emergency_assist else 16.0)),
		0.42 if rescue_assist else (0.35 if emergency_assist else 0.24),
		1.22 if rescue_assist else (1.18 if emergency_assist else 0.92)
	)
	var dir_to_target: Vector3 = assist_target.global_position - ship.global_position
	dir_to_target.y = 0.0
	if dir_to_target.length_squared() > 0.001:
		dir_to_target = dir_to_target.normalized()
	return ShipMovementIntent.build(
		assist_target.global_position,
		desired_point,
		heading_point,
		ship.global_position.distance_to(assist_target.global_position),
		desired_speed_mult,
		emergency_assist,
		dir_to_target,
		"support_assist"
	)

static func _calculate_support_assist_separation(ship, minions: Array, assist_target: Node3D) -> Vector3:
	var force: Vector3 = Vector3.ZERO
	var count: int = 0
	for other in minions:
		if other == ship or not is_instance_valid(other):
			continue
		var offset: Vector3 = ship.global_position - other.global_position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist <= 0.1 or dist >= SUPPORT_ASSIST_SEPARATION_RADIUS:
			continue
		var strength: float = pow((SUPPORT_ASSIST_SEPARATION_RADIUS - dist) / SUPPORT_ASSIST_SEPARATION_RADIUS, 2.0)
		force += offset.normalized() * strength * SUPPORT_ASSIST_SEPARATION_FORCE
		count += 1
	if is_instance_valid(assist_target):
		var target_offset: Vector3 = ship.global_position - assist_target.global_position
		target_offset.y = 0.0
		var target_dist: float = target_offset.length()
		var collision_dist: float = ship.get_collision_distance_to(assist_target)
		if target_dist > 0.1 and target_dist < collision_dist + 2.0:
			var strength: float = (collision_dist + 2.0 - target_dist) / maxf(collision_dist + 2.0, 0.001)
			force += target_offset.normalized() * strength * SUPPORT_ASSIST_SEPARATION_FORCE
			count += 1
	return force / max(count, 1)

static func _get_minion_roster(ship, support_only: bool) -> Array:
	var roster: Array = []
	var all_minions: Array = ship.get_minions_cached(ship.get_tree())
	for minion in all_minions:
		if not is_instance_valid(minion):
			continue
		var is_roster_support := ShipAllyRoleHelper.is_support_ship(minion)
		if support_only and not is_roster_support:
			continue
		if not support_only and is_roster_support:
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

static func _get_support_assist_target(ship, player_ship: Node3D, delta: float) -> Node3D:
	if not is_instance_valid(ship) or not is_instance_valid(player_ship):
		return null
	var deck_emergency: bool = _is_player_deck_emergency(player_ship)
	var recall_distance: float = SUPPORT_ASSIST_EMERGENCY_RECALL_DISTANCE if deck_emergency else SUPPORT_ASSIST_RECALL_DISTANCE
	var leash_distance: float = SUPPORT_ASSIST_EMERGENCY_LEASH_DISTANCE if deck_emergency else SUPPORT_ASSIST_LEASH_DISTANCE
	var threat_range: float = SUPPORT_ASSIST_EMERGENCY_THREAT_RANGE if deck_emergency else SUPPORT_ASSIST_THREAT_RANGE
	var support_dist_to_player: float = ship.global_position.distance_to(player_ship.global_position)
	if support_dist_to_player > recall_distance:
		_clear_support_assist_target_lock(ship)
		return null

	var best_target: Node3D = null
	var best_score: float = INF
	var locked_target: Node3D = null
	var locked_score: float = INF
	var locked_target_id: int = int(ship.get_meta(SUPPORT_ASSIST_TARGET_ID_META, 0))
	var lock_timer: float = maxf(0.0, float(ship.get_meta(SUPPORT_ASSIST_LOCK_TIMER_META, 0.0)) - delta)
	ship.set_meta(SUPPORT_ASSIST_LOCK_TIMER_META, lock_timer)
	var deck_contested: bool = player_ship.get("deck_is_contested") == true or player_ship.get("deck_is_overrun") == true
	var deck_overrun: bool = player_ship.get("deck_is_overrun") == true
	var player_boarding_attacker: Node3D = null
	if player_ship.has_method("get_boarding_attacker_ship"):
		player_boarding_attacker = player_ship.call("get_boarding_attacker_ship")
	if _is_support_rescue_target(ship, player_ship):
		if support_dist_to_player <= leash_distance:
			_set_support_assist_target_lock(ship, player_ship)
			return player_ship
	if not deck_emergency and support_dist_to_player > SUPPORT_ASSIST_SOFT_RECALL_DISTANCE and not is_instance_valid(player_boarding_attacker):
		_clear_support_assist_target_lock(ship)
		return null
	if _is_support_formation_hold_enabled(ship):
		var hold_boarding_attacker: Node3D = player_boarding_attacker
		if is_instance_valid(hold_boarding_attacker) and not _is_ship_disabled(hold_boarding_attacker):
			var hold_support_dist: float = ship.global_position.distance_to(hold_boarding_attacker.global_position)
			if hold_support_dist <= leash_distance:
				_set_support_assist_target_lock(ship, hold_boarding_attacker)
				return hold_boarding_attacker
		_clear_support_assist_target_lock(ship)
		return null
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		if not is_instance_valid(enemy):
			continue
		if _is_ship_disabled(enemy):
			continue
		if enemy.get("is_derelict") == true:
			continue
		var offset: Vector3 = enemy.global_position - player_ship.global_position
		offset.y = 0.0
		var dist: float = offset.length()
		var is_boarding_player: bool = enemy.has_method("get_boarding_target_ship") and enemy.call("get_boarding_target_ship") == player_ship
		var is_close_threat: bool = dist <= SUPPORT_ASSIST_CLOSE_RANGE
		if dist > threat_range and not is_boarding_player:
			continue
		var support_dist: float = ship.global_position.distance_to(enemy.global_position)
		if support_dist > leash_distance and not is_boarding_player:
			continue
		var score: float = (dist * 0.55 + support_dist * 0.2) if deck_emergency else (dist + support_dist * 0.35)
		if is_boarding_player:
			score -= 34.0 if deck_emergency else 18.0
		elif deck_overrun:
			score -= 22.0
		elif deck_contested:
			score -= 12.0
		elif is_close_threat:
			score -= 4.0
		if enemy.get_instance_id() == locked_target_id:
			locked_target = enemy
			locked_score = score
			if lock_timer > 0.0:
				score -= SUPPORT_ASSIST_SWITCH_MARGIN
		if score < best_score:
			best_score = score
			best_target = enemy

	var boarding_attacker: Node3D = player_boarding_attacker
	if is_instance_valid(boarding_attacker) and not _is_ship_disabled(boarding_attacker):
		var support_dist_to_attacker: float = ship.global_position.distance_to(boarding_attacker.global_position)
		if support_dist_to_attacker <= leash_distance:
			_set_support_assist_target_lock(ship, boarding_attacker)
			return boarding_attacker

	if is_instance_valid(locked_target) and lock_timer > 0.0:
		return locked_target
	if is_instance_valid(locked_target) and is_instance_valid(best_target) and locked_target != best_target:
		if locked_score <= best_score + SUPPORT_ASSIST_SWITCH_MARGIN:
			_set_support_assist_target_lock(ship, locked_target)
			return locked_target
	if is_instance_valid(best_target):
		_set_support_assist_target_lock(ship, best_target)
	else:
		_clear_support_assist_target_lock(ship)
	return best_target


static func _is_player_deck_emergency(player_ship: Node3D) -> bool:
	if not is_instance_valid(player_ship):
		return false
	var hostile_count: int = 0
	if player_ship.get("deck_hostile_boarder_count") != null:
		hostile_count = int(player_ship.get("deck_hostile_boarder_count"))
	return player_ship.get("deck_is_overrun") == true \
		or player_ship.get("deck_is_contested") == true \
		or hostile_count > 0


static func _is_support_rescue_target(ship, assist_target: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(assist_target):
		return false
	if not ShipAllyRoleHelper.is_support_ship(ship):
		return false
	if not is_instance_valid(ship.target) or assist_target != ship.target:
		return false
	var target_team: String = assist_target.get_team_tag() if assist_target.has_method("get_team_tag") else str(assist_target.get("team"))
	if target_team != "player":
		return false
	if assist_target.get("deck_is_overrun") == true:
		return true
	var hostile_count: int = int(assist_target.get("deck_hostile_boarder_count")) if assist_target.get("deck_hostile_boarder_count") != null else 0
	var deck_contested: bool = assist_target.get("deck_is_contested") == true
	return hostile_count > 0 and deck_contested


static func _is_support_formation_hold_enabled(ship) -> bool:
	if not is_instance_valid(ship):
		return false
	if "support_hold_formation" in ship:
		return ship.get("support_hold_formation") == true
	return ship.get_meta("support_hold_formation", false) == true


static func _set_support_assist_target_lock(ship, assist_target: Node3D) -> void:
	var previous_target_id: int = int(ship.get_meta(SUPPORT_ASSIST_TARGET_ID_META, 0))
	if previous_target_id != assist_target.get_instance_id() and ship.has_meta(SUPPORT_ASSIST_LANE_SIDE_META):
		ship.remove_meta(SUPPORT_ASSIST_LANE_SIDE_META)
	ship.set_meta(SUPPORT_ASSIST_TARGET_ID_META, assist_target.get_instance_id())
	ship.set_meta(SUPPORT_ASSIST_LOCK_TIMER_META, SUPPORT_ASSIST_TARGET_LOCK_DURATION)

static func _clear_support_assist_target_lock(ship) -> void:
	if ship.has_meta(SUPPORT_ASSIST_TARGET_ID_META):
		ship.remove_meta(SUPPORT_ASSIST_TARGET_ID_META)
	if ship.has_meta(SUPPORT_ASSIST_LOCK_TIMER_META):
		ship.remove_meta(SUPPORT_ASSIST_LOCK_TIMER_META)
	if ship.has_meta(SUPPORT_ASSIST_LANE_SIDE_META):
		ship.remove_meta(SUPPORT_ASSIST_LANE_SIDE_META)

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
