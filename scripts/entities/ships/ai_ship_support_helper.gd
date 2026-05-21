extends RefCounted
class_name AIShipSupportHelper

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")

const SupportFleetFormationHelper = preload("res://scripts/entities/ships/support_fleet_formation_helper.gd")
const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const AIShipRuntimeHelper = preload("res://scripts/entities/ships/ai_ship_runtime_helper.gd")
const ShipAIIntentHelper = preload("res://scripts/entities/ships/ship_ai_intent_helper.gd")

const SUPPORT_FORMATION_SPACING := 10.0
const SUPPORT_COLUMN_FORMATION_SPACING := 14.0
const SUPPORT_JOIN_SPACING := 14.0
const SUPPORT_COLUMN_JOIN_SPACING := 18.0
const SUPPORT_JOIN_CATCHUP_SPEED_BONUS := 5.0
const SUPPORT_JOIN_CATCHUP_SPEED_MULT := 2.2
const SUPPORT_JOIN_ROWING_WIND_FLOOR := 0.9
const SUPPORT_FLEET_SLOT_INDEX_META := "support_fleet_slot_index"
const SUPPORT_FLEET_ORDER_META := "support_fleet_order"
const SUPPORT_FLEET_SLOT_ROLE_META := "support_squadron_slot_role"
const SUPPORT_TRAIL_POINTS_META := "support_trail_points"
const SUPPORT_ANCHOR_POS_META := "support_anchor_position"
const SUPPORT_ANCHOR_FWD_META := "support_anchor_forward"
const SUPPORT_IDLE_ORBIT_TIME_META := "support_idle_orbit_time"
const SUPPORT_JOIN_STAGE_META := "support_join_stage"
const SUPPORT_JOIN_STAGE_REAR_LANE := 0
const SUPPORT_JOIN_STAGE_SIDE_LANE := 1
const SUPPORT_JOIN_STAGE_FINAL_SLOT := 2
const SUPPORT_JOIN_REAR_LANE_SETTLE_DISTANCE := 11.5
const SUPPORT_JOIN_SIDE_LANE_SETTLE_DISTANCE := 10.0
const SUPPORT_JOIN_FINAL_SETTLE_DISTANCE := 8.5
const SUPPORT_JOIN_FINAL_SETTLE_DISTANCE_HEAVY := 5.5
const SUPPORT_JOIN_SIDE_LANE_MIN_LATERAL := 4.0
const SUPPORT_SLOT_SPEED_GAIN := 0.31
const SUPPORT_SLOT_BRAKE_GAIN := 0.55
const SUPPORT_MAX_CATCHUP_SPEED := 3.25
const SUPPORT_MAX_BRAKE_SPEED := 5.0
const SUPPORT_SPEED_RESPONSE := 2.25
const SUPPORT_LATERAL_SEP_SCALE := 0.18
const SUPPORT_FORMUP_DISTANCE := 1.75
const SUPPORT_FORMUP_SPEED_GAIN := 0.32
const SUPPORT_MAX_FORMUP_SPEED := 3.85
const SUPPORT_FORMATION_SETTLE_DISTANCE := 10.0
const SUPPORT_WING_LATERAL_SETTLE_TOLERANCE := 2.4
const SUPPORT_WING_LATERAL_FORMUP_GAIN := 0.46
const SUPPORT_WING_FORMUP_SPEED_SCALE := 1.32
const SUPPORT_WING_DIRECT_STEER_GAIN := 0.72
const SUPPORT_FORMATION_TURN_COMMIT_ANGLE := 1.45
const SUPPORT_COLUMN_TURN_ASSIST_START_ANGLE := 0.24
const SUPPORT_COLUMN_TURN_ASSIST_FULL_ANGLE := 0.92
const SUPPORT_COLUMN_TURN_POSITION_BLEND := 0.82
const SUPPORT_COLUMN_TURN_FORWARD_BLEND := 0.9
const SUPPORT_COLUMN_TURN_MODE_START_RUDDER := 16.0
const SUPPORT_COLUMN_TURN_MODE_FULL_RUDDER := 30.0
const SUPPORT_COLUMN_TURN_MODE_MIN_BLEND := 0.16
const SUPPORT_HEADING_CORRECTION_GAIN := 0.07
const SUPPORT_MAX_HEADING_CORRECTION := 0.42
const SUPPORT_TURN_BRAKE_START_ANGLE := 0.38
const SUPPORT_TURN_BRAKE_FULL_ANGLE := 1.1
const SUPPORT_COLUMN_TURN_BRAKE_MIN_MULT := 0.58
const SUPPORT_SPREAD_TURN_BRAKE_MIN_MULT := 0.68
const SUPPORT_COLUMN_TURN_AUTHORITY_BONUS := 0.34
const SUPPORT_SPREAD_TURN_AUTHORITY_BONUS := 0.22
const SUPPORT_PANOKSEON_CATCHUP_SPEED_SCALE := 0.78
const SUPPORT_PANOKSEON_FORMUP_SPEED_SCALE := 0.86
const SUPPORT_PANOKSEON_BRAKE_START_SCALE := 0.74
const SUPPORT_PANOKSEON_BRAKE_FULL_SCALE := 0.84
const SUPPORT_PANOKSEON_COLUMN_TURN_BRAKE_MIN_MULT := 0.48
const SUPPORT_PANOKSEON_SPREAD_TURN_BRAKE_MIN_MULT := 0.56
const SUPPORT_PANOKSEON_COLUMN_TURN_AUTHORITY_BONUS := 0.46
const SUPPORT_PANOKSEON_SPREAD_TURN_AUTHORITY_BONUS := 0.3
const SUPPORT_PRE_AVOID_LOOKAHEAD := 0.88
const SUPPORT_PRE_AVOID_LOOKAHEAD_SPEED_SCALE := 0.06
const SUPPORT_PRE_AVOID_TRIGGER_PAD := 4.2
const SUPPORT_PRE_AVOID_PANOKSEON_EXTRA_PAD := 1.8
const SUPPORT_PRE_AVOID_MAX_LATERAL_OFFSET := 4.8
const SUPPORT_PRE_AVOID_BASE_BRAKE_MULT := 0.54
const SUPPORT_PRE_AVOID_PANOKSEON_BRAKE_MULT := 0.42
const SUPPORT_PRE_AVOID_MIN_FORWARD_ALIGNMENT := -0.15
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
const SUPPORT_ASSIST_SOFT_RECALL_DISTANCE := 36.0
const SUPPORT_ASSIST_RECALL_DISTANCE := 42.0
const SUPPORT_ASSIST_LEASH_DISTANCE := 54.0
const SUPPORT_ASSIST_SPEED_RESPONSE := 1.85
const SUPPORT_ASSIST_EMERGENCY_THREAT_RANGE := 76.0
const SUPPORT_ASSIST_EMERGENCY_RECALL_DISTANCE := 168.0
const SUPPORT_ASSIST_EMERGENCY_LEASH_DISTANCE := 188.0
const SUPPORT_ASSIST_EMERGENCY_SPEED_RESPONSE := 2.3
const SUPPORT_ASSIST_BOSS_BREACH_RECALL_DISTANCE := 112.0
const SUPPORT_ASSIST_BOSS_BREACH_LEASH_DISTANCE := 136.0
const SUPPORT_ASSIST_SEPARATION_RADIUS := 10.0
const SUPPORT_ASSIST_SEPARATION_PAD := 3.4
const SUPPORT_ASSIST_PANOKSEON_SEPARATION_EXTRA_PAD := 1.8
const SUPPORT_ASSIST_SEPARATION_FORCE := 1.1
const SUPPORT_ASSIST_ROWING_WIND_FLOOR := 0.78
const SUPPORT_ASSIST_EMERGENCY_ROWING_WIND_FLOOR := 0.86
const SUPPORT_ASSIST_ROWING_SPEED_BONUS := 0.24
const SUPPORT_ASSIST_EMERGENCY_ROWING_SPEED_BONUS := 0.36
const SUPPORT_ASSIST_TARGET_ID_META := "support_assist_target_id"
const SUPPORT_ASSIST_LOCK_TIMER_META := "support_assist_lock_timer"
const SUPPORT_ASSIST_EVAL_TIMER_META := "support_assist_eval_timer"
const SUPPORT_ASSIST_LANE_SIDE_META := "support_assist_lane_side"
const SUPPORT_ASSIST_TARGET_LOCK_DURATION := 3.25
const SUPPORT_ASSIST_TARGET_LOCK_DURATION_BOSS_BREACH := 4.75
const SUPPORT_ASSIST_SWITCH_MARGIN := 10.0
const SUPPORT_ASSIST_SWITCH_MARGIN_BOSS_BREACH := 18.0
const SUPPORT_ASSIST_EVAL_INTERVAL := 0.12
const SUPPORT_ASSIST_EVAL_INTERVAL_EMERGENCY := 0.07
const SUPPORT_ASSIST_EVAL_INTERVAL_BOSS_BREACH := 0.05
const SUPPORT_ASSIST_TARGET_SHARE_CAPACITY := 1
const SUPPORT_ASSIST_TARGET_DANGER_CAPACITY := 2
const SUPPORT_ASSIST_TARGET_BOARDING_CAPACITY := 3
const SUPPORT_ASSIST_TARGET_SHARE_PENALTY := 16.0
const SUPPORT_ASSIST_TARGET_SHARE_PENALTY_EMERGENCY := 8.0
const SUPPORT_ASSIST_TARGET_SHARE_LEASH_PAD := 18.0
const SUPPORT_BOARDING_CONTACT_PAD := 0.85
const SUPPORT_RESCUE_BOARDING_START_PAD := SUPPORT_BOARDING_CONTACT_PAD
const SUPPORT_LIMBO_PILOT_STALE_FRAMES := 8
const LEGACY_CAPTURE_LIMBO_PILOT_STALE_FRAMES := 8
const LEGACY_CAPTURE_GUARD_TARGET_ID_META := "legacy_capture_guard_target_id"
const LEGACY_CAPTURE_GUARD_LANE_SIDE_META := "legacy_capture_guard_lane_side"
const LEGACY_CAPTURE_GUARD_SEPARATION_RADIUS := 9.0
const LEGACY_CAPTURE_GUARD_SEPARATION_FORCE := 0.9
const LEGACY_CAPTURE_GUARD_SPEED_RESPONSE := 1.72
const LEGACY_CAPTURE_GUARD_ROWING_WIND_FLOOR := 0.78

static var _support_roster_cache_frame: int = -1
static var _support_roster_cache: Dictionary = {}

static func continue_support_motion(ship, delta: float) -> void:
	if delta <= 0.0 or not is_instance_valid(ship):
		return
	var is_support_ship: bool = PlayerFleetRoleHelper.is_support_ship(ship)
	var is_legacy_captured_ship: bool = PlayerFleetRoleHelper.is_legacy_captured_ship(ship) and not is_support_ship
	if not is_support_ship and not is_legacy_captured_ship:
		ship._update_support_ai_idle_visuals()
		return

	var movement_target: Node3D = _get_support_flagship(ship) if is_support_ship else (ship.target as Node3D if is_instance_valid(ship.target) else null)
	var speed: float = maxf(float(ship.current_speed), 0.0)
	if speed > 0.1:
		var speed_ratio: float = clampf(speed / maxf(float(ship.max_speed), 0.01), 0.0, 1.0)
		var turn_scale: float = float(ship.ai_turn_authority)
		var actual_turn: float = (float(ship.rudder_angle) / 45.0) * float(ship.turn_rate) * ship.get_rudder_turn_multiplier() * speed_ratio * float(ship.turn_mult) * turn_scale * delta
		var max_turn_this_frame: float = float(ship.ai_max_turn_rate) * delta
		actual_turn = clampf(actual_turn, -max_turn_this_frame, max_turn_this_frame)
		ship.rotation.y -= deg_to_rad(actual_turn)

		var wind_floor := SUPPORT_JOIN_ROWING_WIND_FLOOR if is_support_ship and ship.get_meta("support_joining", false) == true else 0.6
		var wind_mult: float = AIShipRuntimeHelper._calculate_sail_drive_multiplier(ship, wind_floor)
		var forward_vec: Vector3 = Vector3(-sin(ship.rotation.y), 0.0, -cos(ship.rotation.y))
		var velocity: Vector3 = forward_vec * speed * wind_mult
		velocity += ship.separation_force
		velocity += ship.consume_collision_impulse_velocity(delta)
		velocity += ship._calculate_collision_repulsion() * delta

		var prev_pos: Vector3 = ship.global_position
		var next_pos: Vector3 = prev_pos + velocity * delta
		if is_instance_valid(movement_target):
			var target_guard_ratio: float = SUPPORT_TARGET_GUARD_RATIO if is_support_ship else 0.94
			next_pos = ship._apply_ship_collision_guard(movement_target, prev_pos, next_pos, target_guard_ratio, velocity.length(), false)
		next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, movement_target)
		ship.global_position = next_pos
		if is_support_ship:
			_record_support_trail_point(ship)

	ship._update_rudder_visual()
	ship._apply_bobbing_effect()
	ship._set_wake_state(speed > 0.4, clampf(speed / maxf(float(ship.max_speed), 0.01), 0.0, 1.0), 0.0, 0.0)

static func process_support_ai(ship, delta: float, motion_delta: float = -1.0) -> void:
	var step_delta: float = delta if motion_delta < 0.0 else maxf(motion_delta, 0.0)
	var is_support_ship: bool = PlayerFleetRoleHelper.is_support_ship(ship)
	var is_legacy_captured_ship: bool = PlayerFleetRoleHelper.is_legacy_captured_ship(ship) and not is_support_ship
	var movement_target: Node3D = _get_support_flagship(ship) if is_support_ship else (ship.target as Node3D if is_instance_valid(ship.target) else null)
	if not is_instance_valid(movement_target) or _is_ship_disabled(movement_target):
		ship._find_player()
		movement_target = _get_support_flagship(ship) if is_support_ship else (ship.target as Node3D if is_instance_valid(ship.target) else null)
		if not is_instance_valid(movement_target) or _is_ship_disabled(movement_target):
			if is_support_ship and _has_support_anchor(ship):
				_process_support_idle_patrol(ship, delta)
			return

	if is_support_ship:
		_record_support_anchor(ship, movement_target)
		_record_support_trail_point(movement_target)

	var minions: Array = _get_support_roster(ship, is_support_ship)
	var my_index: int = minions.find(ship)
	if my_index == -1:
		my_index = 0

	var offset: Vector3 = _get_support_offset(ship, my_index, is_support_ship)
	var player_fwd: Vector3 = -movement_target.global_transform.basis.z
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

	var target_pos = movement_target.to_global(offset)
	target_pos += sep_force

	var dist_to_target = ship.global_position.distance_to(target_pos)
	var player_speed = movement_target.get("current_speed")
	if player_speed == null:
		player_speed = 0.0
	var support_lead_ship: Node3D = movement_target
	var support_lead_fwd: Vector3 = player_fwd
	var support_lead_speed: float = float(player_speed)
	var support_assist_target: Node3D = null
	var support_formation_value: int = SupportFleetStateHelper.get_effective_formation(ship) if is_support_ship else 0
	var is_spread_support_formation: bool = is_support_ship and support_formation_value != 0
	var is_heavy_support: bool = is_support_ship and PlayerFleetRoleHelper.is_heavy_support(ship)
	var support_column_turn_blend: float = 0.0
	var support_column_turn_angle: float = 0.0
	var support_column_turn_mode: bool = false
	var support_slot_lateral_error: float = 0.0
	var support_pre_avoid_brake_mult: float = 1.0
	var support_pre_avoid_hazard: float = 0.0
	var support_pre_avoid_lateral: float = 0.0
	var legacy_capture_limbo_payload := _get_recent_legacy_capture_limbo_payload(ship) if is_legacy_captured_ship else {}
	var legacy_capture_limbo_mode := str(legacy_capture_limbo_payload.get("mode", "")).strip_edges()
	var legacy_capture_guard_target := legacy_capture_limbo_payload.get("target", null) as Node3D

	var to_target_vec = target_pos - ship.global_position
	var direction = to_target_vec.normalized()
	var rel_depth = to_target_vec.dot(player_fwd)
	var dist_to_player = ship.global_position.distance_to(movement_target.global_position)
	var is_joining_support: bool = ship.has_meta("support_joining") and ship.get_meta("support_joining") == true
	if is_support_ship:
		var support_spacing: float = SUPPORT_COLUMN_FORMATION_SPACING if support_formation_value == SupportFleetFormationHelper.FORMATION_COLUMN else SUPPORT_FORMATION_SPACING
		var support_formation_step: Dictionary = _build_support_formation_step(
			ship,
			movement_target,
			minions,
			my_index,
			support_spacing,
			player_fwd,
			player_right,
			float(player_speed)
		)
		target_pos = support_formation_step.get("target_pos", target_pos)
		support_lead_fwd = support_formation_step.get("lead_fwd", support_lead_fwd)
		support_lead_speed = float(support_formation_step.get("lead_speed", support_lead_speed))
		support_column_turn_blend = float(support_formation_step.get("column_turn_blend", support_column_turn_blend))
		support_column_turn_angle = float(support_formation_step.get("column_turn_angle", support_column_turn_angle))
		support_column_turn_mode = support_formation_step.get("column_turn_mode", support_column_turn_mode) == true
		var support_lead_variant: Variant = support_formation_step.get("lead_ship", support_lead_ship)
		if support_lead_variant is Node3D:
			support_lead_ship = support_lead_variant as Node3D
		var support_pre_avoidance: Dictionary = _calculate_support_pre_avoidance(
			ship,
			minions,
			movement_target,
			target_pos,
			maxf(maxf(ship.current_speed, float(ship._last_ai_speed)), maxf(float(player_speed), support_lead_speed)),
			is_heavy_support
		)
		var support_pre_avoid_offset: Vector3 = support_pre_avoidance.get("position_offset", Vector3.ZERO)
		if support_pre_avoid_offset.length_squared() > 0.0001:
			target_pos += support_pre_avoid_offset
		support_pre_avoid_brake_mult = float(support_pre_avoidance.get("brake_mult", 1.0))
		support_pre_avoid_hazard = float(support_pre_avoidance.get("hazard", 0.0))
		support_pre_avoid_lateral = float(support_pre_avoidance.get("lateral", 0.0))
		support_assist_target = _get_support_assist_target(ship, movement_target, delta)
		to_target_vec = target_pos - ship.global_position
		if to_target_vec.length_squared() > 0.0001:
			direction = to_target_vec.normalized()
		rel_depth = to_target_vec.dot(support_lead_fwd)
		dist_to_player = ship.global_position.distance_to(movement_target.global_position)
		if is_joining_support:
			var join_step: Dictionary = _build_support_join_step(ship, minions, my_index, support_formation_value, support_lead_fwd, support_spacing)
			target_pos = join_step.get("target_pos", target_pos)
			support_lead_fwd = join_step.get("lead_fwd", support_lead_fwd)
			support_column_turn_mode = false
		target_pos += sep_force * 0.15
		to_target_vec = target_pos - ship.global_position
		if to_target_vec.length_squared() > 0.0001:
			direction = to_target_vec.normalized()
		var dist_to_join_target: float = ship.global_position.distance_to(target_pos)
		dist_to_player = ship.global_position.distance_to(movement_target.global_position)
		var join_stage := int(ship.get_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_FINAL_SLOT))
		var join_settle_distance := SUPPORT_JOIN_FINAL_SETTLE_DISTANCE
		if join_stage == SUPPORT_JOIN_STAGE_REAR_LANE:
			join_settle_distance = SUPPORT_JOIN_REAR_LANE_SETTLE_DISTANCE
		elif join_stage == SUPPORT_JOIN_STAGE_SIDE_LANE:
			join_settle_distance = SUPPORT_JOIN_SIDE_LANE_SETTLE_DISTANCE
		elif is_heavy_support:
			join_settle_distance = SUPPORT_JOIN_FINAL_SETTLE_DISTANCE_HEAVY
		if join_stage == SUPPORT_JOIN_STAGE_FINAL_SLOT and dist_to_join_target <= join_settle_distance:
			ship.set_meta("support_joining", false)
			if ship.has_meta(SUPPORT_JOIN_STAGE_META):
				ship.remove_meta(SUPPORT_JOIN_STAGE_META)
			is_joining_support = false
	dist_to_target = ship.global_position.distance_to(target_pos)
	if is_support_ship and not is_joining_support and is_instance_valid(support_assist_target):
		if _try_start_support_boarding(ship, support_assist_target, delta):
			return
		_process_support_assist_ai(ship, delta, support_assist_target, minions, my_index, step_delta)
		return
	if is_legacy_captured_ship and legacy_capture_limbo_mode == ShipAILimboKeys.ALLY_MODE_GUARD_THREAT and is_instance_valid(legacy_capture_guard_target):
		_process_captured_guard_ai(ship, delta, legacy_capture_guard_target, minions, my_index, step_delta)
		return

	var target_final_speed = player_speed
	var legacy_capture_regrouping: bool = is_legacy_captured_ship and legacy_capture_limbo_mode == ShipAILimboKeys.ALLY_MODE_REGROUP
	if is_joining_support:
		var join_stage := int(ship.get_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_FINAL_SLOT))
		target_final_speed = _calculate_support_join_speed(ship, float(player_speed), dist_to_target, join_stage, is_heavy_support)
	elif is_support_ship:
		var speed_step: Dictionary = _compute_support_follow_speed(
			ship,
			support_lead_fwd,
			to_target_vec,
			rel_depth,
			dist_to_target,
			support_lead_speed,
			support_pre_avoid_brake_mult,
			is_spread_support_formation,
			is_heavy_support
		)
		target_final_speed = float(speed_step.get("target_speed", target_final_speed))
		support_slot_lateral_error = float(speed_step.get("slot_lateral_error", support_slot_lateral_error))
	elif legacy_capture_regrouping:
		target_final_speed = maxf(player_speed + 2.4, ship.move_speed * 1.55)
	elif dist_to_player < 10.0:
		target_final_speed = 0.0
	elif rel_depth < -0.5:
		var brake_factor = clamp(abs(rel_depth) / 10.0, 0.0, 0.9)
		target_final_speed = player_speed * (1.0 - brake_factor)
	else:
		var lag_factor = clamp(rel_depth / 60.0, 0.0, 1.0)
		var sync_speed_mult = lerp(1.0, 1.3, lag_factor)
		target_final_speed = max(player_speed * sync_speed_mult, ship.move_speed * 0.8)

	var target_head_rot = atan2(-direction.x, -direction.z)
	var player_head_rot = ship.rotation.y
	if is_instance_valid(movement_target) and "rotation" in movement_target:
		player_head_rot = movement_target.rotation.y
	if is_support_ship:
		var heading_step: Dictionary = _compute_support_heading(
			ship,
			support_lead_ship,
			support_lead_fwd,
			to_target_vec,
			direction,
			dist_to_target,
			target_final_speed,
			support_lead_speed,
			support_slot_lateral_error,
			is_spread_support_formation,
			player_head_rot
		)
		target_head_rot = float(heading_step.get("target_head_rot", target_head_rot))
		player_head_rot = float(heading_step.get("player_head_rot", player_head_rot))
		target_final_speed = float(heading_step.get("target_speed", target_final_speed))

	var support_turn_angle: float = 0.0
	if is_support_ship:
		var turn_brake_step: Dictionary = _apply_support_turn_brake(
			ship,
			target_head_rot,
			target_final_speed,
			support_formation_value,
			support_column_turn_blend,
			is_heavy_support
		)
		target_final_speed = float(turn_brake_step.get("target_speed", target_final_speed))
		support_turn_angle = float(turn_brake_step.get("turn_angle", support_turn_angle))

	var speed_response: float = SUPPORT_SPEED_RESPONSE if is_support_ship else (1.55 if legacy_capture_regrouping else 1.2)
	ship._last_ai_speed = lerp(ship._last_ai_speed, target_final_speed, delta * speed_response)
	var final_move_speed = ship._last_ai_speed
	ship.current_speed = maxf(final_move_speed, 0.0)

	var rotation_blend = clamp(dist_to_target / 15.0, 0.0, 1.0)
	if is_spread_support_formation:
		var lateral_rotation_blend := clampf(
			(support_slot_lateral_error - SUPPORT_WING_LATERAL_SETTLE_TOLERANCE) / maxf(SUPPORT_FORMATION_SETTLE_DISTANCE, 0.001),
			0.0,
			0.92
		)
		rotation_blend = maxf(rotation_blend, lateral_rotation_blend)
	var blended_target_rot = lerp_angle(player_head_rot, target_head_rot, rotation_blend)
	var angle_diff = wrapf(blended_target_rot - ship.rotation.y, -PI, PI)
	var desired_rudder = clamp(-rad_to_deg(angle_diff) * 2.0, -45.0, 45.0)
	var rudder_speed_adjusted = 120.0 * ship.get_rudder_response_multiplier()
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	if final_move_speed > 0.1:
		var speed_ratio = final_move_speed / ship.max_speed
		var turn_authority_mult: float = 1.0
		if is_support_ship and support_turn_angle > (SUPPORT_TURN_BRAKE_START_ANGLE * (SUPPORT_PANOKSEON_BRAKE_START_SCALE if is_heavy_support else 1.0)):
			var turn_boost_start_angle: float = SUPPORT_TURN_BRAKE_START_ANGLE * (SUPPORT_PANOKSEON_BRAKE_START_SCALE if is_heavy_support else 1.0)
			var turn_boost_full_angle: float = SUPPORT_TURN_BRAKE_FULL_ANGLE * (SUPPORT_PANOKSEON_BRAKE_FULL_SCALE if is_heavy_support else 1.0)
			var turn_boost_blend: float = clampf(
				(support_turn_angle - turn_boost_start_angle) / maxf(turn_boost_full_angle - turn_boost_start_angle, 0.001),
				0.0,
				1.0
			)
			var max_turn_bonus: float
			if support_formation_value == SupportFleetFormationHelper.FORMATION_COLUMN:
				max_turn_bonus = SUPPORT_PANOKSEON_COLUMN_TURN_AUTHORITY_BONUS if is_heavy_support else SUPPORT_COLUMN_TURN_AUTHORITY_BONUS
			else:
				max_turn_bonus = SUPPORT_PANOKSEON_SPREAD_TURN_AUTHORITY_BONUS if is_heavy_support else SUPPORT_SPREAD_TURN_AUTHORITY_BONUS
			turn_authority_mult += max_turn_bonus * turn_boost_blend
			if support_column_turn_blend > 0.0:
				var column_turn_bonus: float = SUPPORT_PANOKSEON_COLUMN_TURN_AUTHORITY_BONUS if is_heavy_support else SUPPORT_COLUMN_TURN_AUTHORITY_BONUS
				turn_authority_mult += column_turn_bonus * 0.35 * support_column_turn_blend
		var actual_turn = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * turn_authority_mult * step_delta
		ship.rotation.y -= deg_to_rad(actual_turn)
	else:
		if dist_to_target <= 1.5:
			ship.rotation.y = lerp_angle(ship.rotation.y, player_head_rot, step_delta * 3.0)

	var wind_floor := SUPPORT_JOIN_ROWING_WIND_FLOOR if is_support_ship and is_joining_support else 0.6
	var wind_mult = AIShipRuntimeHelper._calculate_sail_drive_multiplier(ship, wind_floor)
	final_move_speed *= wind_mult
	var forward_vec = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	var velocity = forward_vec * final_move_speed
	velocity += ship.separation_force
	velocity += ship._calculate_collision_repulsion() * step_delta

	var prev_pos = ship.global_position
	var next_pos = prev_pos + velocity * step_delta
	if is_instance_valid(movement_target):
		var target_guard_ratio: float = SUPPORT_TARGET_GUARD_RATIO if is_support_ship else 0.94
		next_pos = ship._apply_ship_collision_guard(movement_target, prev_pos, next_pos, target_guard_ratio, velocity.length(), false)
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, movement_target)
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
		ship.set_meta("support_debug_turn_angle", support_turn_angle)
		ship.set_meta("support_debug_turn_blend", support_column_turn_blend)
		ship.set_meta("support_debug_turn_mode", support_column_turn_mode)
		ship.set_meta("support_debug_pre_avoid_hazard", support_pre_avoid_hazard)
		ship.set_meta("support_debug_pre_avoid_lateral", support_pre_avoid_lateral)
		ShipBoardingMetaHelper.set_support_debug_mode(ship, ShipBoardingMetaHelper.SUPPORT_DEBUG_TRAIL)
		_draw_support_limbo_debug(ship)
	elif is_legacy_captured_ship:
		_draw_legacy_capture_limbo_debug(ship)

static func _build_support_formation_step(
	ship,
	movement_target: Node3D,
	minions: Array,
	my_index: int,
	support_spacing: float,
	player_fwd: Vector3,
	player_right: Vector3,
	player_speed: float
) -> Dictionary:
	var support_lead_ship: Node3D = SupportFleetFormationHelper.get_support_lead_ship(ship, minions, my_index)
	_record_support_trail_point(support_lead_ship)
	var support_lead_speed: float = _get_ship_speed(support_lead_ship, player_speed)
	var support_goal: Dictionary = SupportFleetFormationHelper.get_support_chain_goal(ship, minions, my_index, support_spacing)
	var target_pos: Vector3 = support_goal.get("position", ship.global_position)
	var support_lead_fwd: Vector3 = support_goal.get("forward", _get_ship_forward_flat(support_lead_ship))
	var column_turn_blend := 0.0
	var column_turn_angle := 0.0
	var column_turn_mode := false

	if SupportFleetStateHelper.get_effective_formation(ship) == SupportFleetFormationHelper.FORMATION_COLUMN and is_instance_valid(support_lead_ship):
		var column_turn_step: Dictionary = _apply_support_column_turn_assist(
			ship,
			movement_target,
			support_lead_ship,
			target_pos,
			support_lead_fwd,
			support_spacing,
			my_index,
			minions.size(),
			player_fwd,
			player_right,
			player_speed
		)
		target_pos = column_turn_step.get("target_pos", target_pos)
		support_lead_fwd = column_turn_step.get("lead_fwd", support_lead_fwd)
		support_lead_speed = float(column_turn_step.get("lead_speed", support_lead_speed))
		column_turn_blend = float(column_turn_step.get("column_turn_blend", column_turn_blend))
		column_turn_angle = float(column_turn_step.get("column_turn_angle", column_turn_angle))
		column_turn_mode = column_turn_step.get("column_turn_mode", column_turn_mode) == true
		var lead_variant: Variant = column_turn_step.get("lead_ship", support_lead_ship)
		if lead_variant is Node3D:
			support_lead_ship = lead_variant as Node3D

	return {
		"target_pos": target_pos,
		"lead_ship": support_lead_ship,
		"lead_fwd": support_lead_fwd,
		"lead_speed": support_lead_speed,
		"column_turn_blend": column_turn_blend,
		"column_turn_angle": column_turn_angle,
		"column_turn_mode": column_turn_mode,
	}


static func _apply_support_column_turn_assist(
	ship,
	movement_target: Node3D,
	support_lead_ship: Node3D,
	target_pos: Vector3,
	support_lead_fwd: Vector3,
	support_spacing: float,
	my_index: int,
	roster_size: int,
	player_fwd: Vector3,
	player_right: Vector3,
	player_speed: float
) -> Dictionary:
	var flagship_turn_fwd: Vector3 = player_fwd if player_fwd.length_squared() > 0.0001 else _get_ship_forward_flat(movement_target)
	var trail_head_rot: float = atan2(-support_lead_fwd.x, -support_lead_fwd.z)
	var flagship_head_rot: float = atan2(-flagship_turn_fwd.x, -flagship_turn_fwd.z)
	var column_turn_angle: float = absf(wrapf(flagship_head_rot - trail_head_rot, -PI, PI))
	var flagship_rudder_abs: float = absf(float(movement_target.get("rudder_angle"))) if movement_target.get("rudder_angle") != null else 0.0
	var turn_mode_blend: float = clampf(
		(flagship_rudder_abs - SUPPORT_COLUMN_TURN_MODE_START_RUDDER) / maxf(SUPPORT_COLUMN_TURN_MODE_FULL_RUDDER - SUPPORT_COLUMN_TURN_MODE_START_RUDDER, 0.001),
		0.0,
		1.0
	)
	var column_turn_blend := 0.0
	var next_target_pos := target_pos
	var next_lead_fwd := support_lead_fwd
	var next_lead_ship: Node3D = support_lead_ship
	var next_lead_speed: float = _get_ship_speed(support_lead_ship, player_speed)

	if column_turn_angle > SUPPORT_COLUMN_TURN_ASSIST_START_ANGLE:
		column_turn_blend = clampf(
			(column_turn_angle - SUPPORT_COLUMN_TURN_ASSIST_START_ANGLE) / maxf(SUPPORT_COLUMN_TURN_ASSIST_FULL_ANGLE - SUPPORT_COLUMN_TURN_ASSIST_START_ANGLE, 0.001),
			0.0,
			1.0
		)
		var live_follow_distance: float = SupportFleetFormationHelper.get_follow_distance(ship, support_lead_ship, support_spacing)
		var direct_goal: Vector3 = support_lead_ship.global_position - flagship_turn_fwd * live_follow_distance
		direct_goal.y = ship.global_position.y
		next_target_pos = next_target_pos.lerp(direct_goal, column_turn_blend * SUPPORT_COLUMN_TURN_POSITION_BLEND)
		var blended_lead_fwd: Vector3 = next_lead_fwd.lerp(flagship_turn_fwd, column_turn_blend * SUPPORT_COLUMN_TURN_FORWARD_BLEND)
		blended_lead_fwd.y = 0.0
		if blended_lead_fwd.length_squared() > 0.0001:
			next_lead_fwd = blended_lead_fwd.normalized()

	turn_mode_blend = maxf(turn_mode_blend, column_turn_blend)
	var column_turn_mode: bool = turn_mode_blend >= SUPPORT_COLUMN_TURN_MODE_MIN_BLEND
	if column_turn_mode:
		var turn_slot_offset: Vector3 = SupportFleetFormationHelper.get_support_fleet_offset(ship, my_index, support_spacing, roster_size)
		var flagship_follow_distance: float = maxf(turn_slot_offset.z, support_spacing + float(my_index) * support_spacing * 0.9)
		var flagship_goal: Dictionary = SupportFleetFormationHelper.get_trail_goal(movement_target, flagship_follow_distance, flagship_turn_fwd, SUPPORT_TRAIL_POINTS_META)
		var flagship_goal_fwd: Vector3 = flagship_goal.get("forward", flagship_turn_fwd)
		var flagship_goal_right: Vector3 = flagship_goal_fwd.cross(Vector3.UP).normalized()
		if flagship_goal_right.length_squared() <= 0.0001:
			flagship_goal_right = player_right
		var direct_column_goal: Vector3 = flagship_goal.get("position", movement_target.global_position) + flagship_goal_right * turn_slot_offset.x
		direct_column_goal.y = ship.global_position.y
		next_target_pos = next_target_pos.lerp(direct_column_goal, clampf(turn_mode_blend * 0.92, 0.0, 0.92))
		next_lead_ship = movement_target
		next_lead_speed = player_speed
		next_lead_fwd = flagship_goal_fwd if flagship_goal_fwd.length_squared() > 0.0001 else flagship_turn_fwd

	return {
		"target_pos": next_target_pos,
		"lead_ship": next_lead_ship,
		"lead_fwd": next_lead_fwd,
		"lead_speed": next_lead_speed,
		"column_turn_blend": column_turn_blend,
		"column_turn_angle": column_turn_angle,
		"column_turn_mode": column_turn_mode,
	}


static func _build_support_join_step(ship, minions: Array, my_index: int, support_formation_value: int, fallback_lead_fwd: Vector3, support_spacing: float) -> Dictionary:
	var support_join_spacing: float = SUPPORT_COLUMN_JOIN_SPACING if support_formation_value == SupportFleetFormationHelper.FORMATION_COLUMN else SUPPORT_JOIN_SPACING
	var join_goal: Dictionary = SupportFleetFormationHelper.get_support_chain_goal(ship, minions, my_index, support_join_spacing)
	if support_formation_value == SupportFleetFormationHelper.FORMATION_WING:
		var join_stage := int(ship.get_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_REAR_LANE))
		var final_goal := SupportFleetFormationHelper.get_support_chain_goal(ship, minions, my_index, support_spacing)
		var final_pos: Vector3 = final_goal.get("position", ship.global_position)
		var final_fwd: Vector3 = final_goal.get("forward", fallback_lead_fwd)
		if final_fwd.length_squared() <= 0.0001:
			final_fwd = fallback_lead_fwd
		final_fwd.y = 0.0
		if final_fwd.length_squared() > 0.0001:
			final_fwd = final_fwd.normalized()
		var final_right := final_fwd.cross(Vector3.UP)
		final_right.y = 0.0
		if final_right.length_squared() <= 0.0001:
			final_right = Vector3.RIGHT
		else:
			final_right = final_right.normalized()

		if join_stage <= SUPPORT_JOIN_STAGE_REAR_LANE:
			var rear_lane_goal := SupportFleetFormationHelper.get_support_join_chain_goal(ship, minions, my_index, support_join_spacing)
			var rear_lane_pos: Vector3 = rear_lane_goal.get("position", ship.global_position)
			if ship.global_position.distance_to(rear_lane_pos) > SUPPORT_JOIN_REAR_LANE_SETTLE_DISTANCE:
				ship.set_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_REAR_LANE)
				return {
					"target_pos": rear_lane_pos,
					"lead_fwd": rear_lane_goal.get("forward", fallback_lead_fwd),
				}
			var final_lateral: float = (final_pos - rear_lane_pos).dot(final_right)
			ship.set_meta(
				SUPPORT_JOIN_STAGE_META,
				SUPPORT_JOIN_STAGE_SIDE_LANE if absf(final_lateral) >= SUPPORT_JOIN_SIDE_LANE_MIN_LATERAL else SUPPORT_JOIN_STAGE_FINAL_SLOT
			)
			join_stage = int(ship.get_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_FINAL_SLOT))
		if join_stage == SUPPORT_JOIN_STAGE_SIDE_LANE:
			var rear_lane_goal := SupportFleetFormationHelper.get_support_join_chain_goal(ship, minions, my_index, support_join_spacing)
			var rear_lane_pos: Vector3 = rear_lane_goal.get("position", ship.global_position)
			var side_lane_pos := rear_lane_pos + final_right * (final_pos - rear_lane_pos).dot(final_right)
			side_lane_pos.y = ship.global_position.y
			if ship.global_position.distance_to(side_lane_pos) > SUPPORT_JOIN_SIDE_LANE_SETTLE_DISTANCE:
				ship.set_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_SIDE_LANE)
				return {
					"target_pos": side_lane_pos,
					"lead_fwd": rear_lane_goal.get("forward", final_fwd),
				}
			ship.set_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_FINAL_SLOT)
		join_goal = final_goal
	else:
		ship.set_meta(SUPPORT_JOIN_STAGE_META, SUPPORT_JOIN_STAGE_FINAL_SLOT)
	return {
		"target_pos": join_goal.get("position", ship.global_position),
		"lead_fwd": join_goal.get("forward", fallback_lead_fwd),
	}


static func _calculate_support_join_speed(ship, player_speed: float, dist_to_target: float, join_stage: int, is_heavy_support: bool) -> float:
	var move_speed: float = float(ship.move_speed) if "move_speed" in ship else 4.0
	var catchup_speed: float = maxf(
		player_speed + SUPPORT_JOIN_CATCHUP_SPEED_BONUS,
		move_speed * SUPPORT_JOIN_CATCHUP_SPEED_MULT
	)
	if is_heavy_support:
		catchup_speed = minf(catchup_speed, maxf(player_speed + 3.4, move_speed * 1.75))
	if join_stage == SUPPORT_JOIN_STAGE_REAR_LANE:
		return catchup_speed

	var near_speed: float = maxf(player_speed * 0.92, move_speed * (0.58 if is_heavy_support else 0.68))
	var slow_radius: float = 28.0 if is_heavy_support else 22.0
	var settle_radius: float = SUPPORT_JOIN_FINAL_SETTLE_DISTANCE_HEAVY if is_heavy_support else SUPPORT_JOIN_FINAL_SETTLE_DISTANCE
	if join_stage == SUPPORT_JOIN_STAGE_SIDE_LANE:
		slow_radius = 24.0 if is_heavy_support else 19.0
		settle_radius = SUPPORT_JOIN_SIDE_LANE_SETTLE_DISTANCE
	var catchup_blend: float = clampf(
		(dist_to_target - settle_radius) / maxf(slow_radius - settle_radius, 0.001),
		0.0,
		1.0
	)
	return lerpf(near_speed, catchup_speed, catchup_blend)


static func _compute_support_follow_speed(
	ship,
	support_lead_fwd: Vector3,
	to_target_vec: Vector3,
	rel_depth: float,
	dist_to_target: float,
	support_lead_speed: float,
	support_pre_avoid_brake_mult: float,
	is_spread_support_formation: bool,
	is_heavy_support: bool
) -> Dictionary:
	var slot_depth_error: float = rel_depth
	var slot_lateral_error: float = absf(to_target_vec.dot(support_lead_fwd.cross(Vector3.UP).normalized()))
	var speed_offset := 0.0
	var max_catchup_speed: float = SUPPORT_MAX_CATCHUP_SPEED * (SUPPORT_PANOKSEON_CATCHUP_SPEED_SCALE if is_heavy_support else 1.0)
	var max_formup_speed: float = SUPPORT_MAX_FORMUP_SPEED * (SUPPORT_PANOKSEON_FORMUP_SPEED_SCALE if is_heavy_support else 1.0)
	if is_spread_support_formation:
		max_formup_speed *= SUPPORT_WING_FORMUP_SPEED_SCALE
	if slot_depth_error >= 0.0:
		speed_offset = minf(slot_depth_error * SUPPORT_SLOT_SPEED_GAIN, max_catchup_speed)
	else:
		if dist_to_target <= SUPPORT_DIRECT_STEER_DISTANCE and slot_lateral_error <= SUPPORT_BRAKE_LATERAL_TOLERANCE:
			speed_offset = -minf(absf(slot_depth_error) * SUPPORT_SLOT_BRAKE_GAIN, SUPPORT_MAX_BRAKE_SPEED)
	var formup_speed := 0.0
	if dist_to_target > SUPPORT_FORMUP_DISTANCE:
		formup_speed = minf((dist_to_target - SUPPORT_FORMUP_DISTANCE) * SUPPORT_FORMUP_SPEED_GAIN, max_formup_speed)
	if is_spread_support_formation and slot_lateral_error > SUPPORT_WING_LATERAL_SETTLE_TOLERANCE:
		var lateral_formup_speed: float = minf(
			(slot_lateral_error - SUPPORT_WING_LATERAL_SETTLE_TOLERANCE) * SUPPORT_WING_LATERAL_FORMUP_GAIN,
			max_formup_speed
		)
		formup_speed = maxf(formup_speed, lateral_formup_speed)
	var target_speed: float = maxf(maxf(support_lead_speed + speed_offset, formup_speed), 0.0)
	if is_spread_support_formation \
			and dist_to_target <= SUPPORT_FORMATION_SETTLE_DISTANCE \
			and slot_lateral_error <= SUPPORT_WING_LATERAL_SETTLE_TOLERANCE:
		var settle_cap := maxf(support_lead_speed + minf(dist_to_target * 0.12, 0.9), ship.move_speed * 0.52)
		target_speed = min(target_speed, settle_cap)
	if dist_to_target <= 2.0:
		target_speed = lerp(target_speed, support_lead_speed, 0.85)
	target_speed *= support_pre_avoid_brake_mult
	return {
		"target_speed": target_speed,
		"slot_lateral_error": slot_lateral_error,
	}


static func _compute_support_heading(
	ship,
	support_lead_ship: Node3D,
	support_lead_fwd: Vector3,
	to_target_vec: Vector3,
	direction: Vector3,
	dist_to_target: float,
	target_final_speed: float,
	support_lead_speed: float,
	support_slot_lateral_error: float,
	is_spread_support_formation: bool,
	player_head_rot: float
) -> Dictionary:
	var lead_head_rot: float = player_head_rot
	if support_lead_fwd.length_squared() > 0.0001:
		lead_head_rot = atan2(-support_lead_fwd.x, -support_lead_fwd.z)
	elif is_instance_valid(support_lead_ship):
		lead_head_rot = support_lead_ship.rotation.y
	var lead_right: Vector3 = support_lead_fwd.cross(Vector3.UP).normalized()
	var lateral_error: float = to_target_vec.dot(lead_right)
	var heading_correction: float = clamp(-lateral_error * SUPPORT_HEADING_CORRECTION_GAIN, -SUPPORT_MAX_HEADING_CORRECTION, SUPPORT_MAX_HEADING_CORRECTION)
	var resolved_player_head_rot := lead_head_rot
	var aligned_head_rot: float = lead_head_rot + heading_correction
	var direct_head_rot: float = atan2(-direction.x, -direction.z)
	var target_head_rot: float
	var resolved_target_speed := target_final_speed
	if is_spread_support_formation:
		var align_weight: float = clampf((dist_to_target - SUPPORT_FORMATION_SETTLE_DISTANCE) / SUPPORT_FORMATION_SETTLE_DISTANCE, 0.0, 1.0)
		if support_slot_lateral_error > SUPPORT_WING_LATERAL_SETTLE_TOLERANCE:
			var direct_steer_weight := clampf(
				(support_slot_lateral_error - SUPPORT_WING_LATERAL_SETTLE_TOLERANCE) / maxf(SUPPORT_FORMATION_SETTLE_DISTANCE, 0.001),
				0.0,
				1.0
			)
			align_weight *= 1.0 - direct_steer_weight * SUPPORT_WING_DIRECT_STEER_GAIN
		target_head_rot = lerp_angle(direct_head_rot, aligned_head_rot, align_weight)
		var align_angle_diff: float = absf(wrapf(aligned_head_rot - ship.rotation.y, -PI, PI))
		if dist_to_target <= SUPPORT_FORMATION_SETTLE_DISTANCE and align_angle_diff > SUPPORT_FORMATION_TURN_COMMIT_ANGLE:
			target_head_rot = lerp_angle(ship.rotation.y, direct_head_rot, 0.72)
			resolved_target_speed = min(resolved_target_speed, maxf(support_lead_speed * 0.82, ship.move_speed * 0.48))
	elif dist_to_target > SUPPORT_DIRECT_STEER_DISTANCE:
		target_head_rot = lerp_angle(aligned_head_rot, direct_head_rot, 0.75)
	else:
		target_head_rot = aligned_head_rot
	return {
		"target_head_rot": target_head_rot,
		"player_head_rot": resolved_player_head_rot,
		"target_speed": resolved_target_speed,
	}


static func _apply_support_turn_brake(
	ship,
	target_head_rot: float,
	target_final_speed: float,
	support_formation_value: int,
	support_column_turn_blend: float,
	is_heavy_support: bool
) -> Dictionary:
	var turn_brake_start_angle: float = SUPPORT_TURN_BRAKE_START_ANGLE * (SUPPORT_PANOKSEON_BRAKE_START_SCALE if is_heavy_support else 1.0)
	var turn_brake_full_angle: float = SUPPORT_TURN_BRAKE_FULL_ANGLE * (SUPPORT_PANOKSEON_BRAKE_FULL_SCALE if is_heavy_support else 1.0)
	var support_turn_angle: float = absf(wrapf(target_head_rot - ship.rotation.y, -PI, PI))
	var resolved_target_speed := target_final_speed
	if support_turn_angle > turn_brake_start_angle:
		var turn_brake_blend: float = clampf(
			(support_turn_angle - turn_brake_start_angle) / maxf(turn_brake_full_angle - turn_brake_start_angle, 0.001),
			0.0,
			1.0
		)
		var min_turn_speed_mult: float
		if support_formation_value == SupportFleetFormationHelper.FORMATION_COLUMN:
			min_turn_speed_mult = SUPPORT_PANOKSEON_COLUMN_TURN_BRAKE_MIN_MULT if is_heavy_support else SUPPORT_COLUMN_TURN_BRAKE_MIN_MULT
		else:
			min_turn_speed_mult = SUPPORT_PANOKSEON_SPREAD_TURN_BRAKE_MIN_MULT if is_heavy_support else SUPPORT_SPREAD_TURN_BRAKE_MIN_MULT
		var turn_speed_mult: float = lerpf(1.0, min_turn_speed_mult, turn_brake_blend)
		if support_column_turn_blend > 0.0:
			var column_turn_floor: float = SUPPORT_PANOKSEON_COLUMN_TURN_BRAKE_MIN_MULT if is_heavy_support else SUPPORT_COLUMN_TURN_BRAKE_MIN_MULT
			turn_speed_mult = minf(turn_speed_mult, lerpf(1.0, column_turn_floor, support_column_turn_blend))
		resolved_target_speed *= turn_speed_mult
	return {
		"target_speed": resolved_target_speed,
		"turn_angle": support_turn_angle,
	}


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

	var order_fallback: int = int(ship.get_meta(SUPPORT_FLEET_ORDER_META, 0))
	var order_index: int = int(ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, order_fallback))
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

static func _process_support_assist_ai(ship, delta: float, assist_target: Node3D, minions: Array, my_index: int, motion_delta: float = -1.0) -> void:
	if not is_instance_valid(assist_target) or _is_ship_disabled(assist_target):
		return
	var step_delta: float = delta if motion_delta < 0.0 else maxf(motion_delta, 0.0)
	var emergency_assist: bool = _is_player_deck_emergency(_get_support_flagship(ship))
	var rescue_assist: bool = _is_support_rescue_target(ship, assist_target)
	var boss_breach_assist: bool = _is_support_boss_breach_target(ship, assist_target)

	var nav: Dictionary = _build_support_assist_navigation(ship, assist_target, my_index)
	var desired_point: Vector3 = ShipMovementIntent.get_desired_point(nav, assist_target.global_position)
	var heading_point: Vector3 = ShipMovementIntent.get_heading_point(nav, desired_point)
	var dist_to_target: float = ShipMovementIntent.get_dist_to_target(nav, ship.global_position.distance_to(assist_target.global_position))
	var desired_speed_mult: float = ShipMovementIntent.get_desired_speed_mult(nav)
	var pre_avoidance: Dictionary = _calculate_support_pre_avoidance(
		ship,
		minions,
		assist_target,
		desired_point,
		maxf(maxf(ship.current_speed, float(ship._last_ai_speed)), _get_ship_speed(assist_target, 0.0)),
		PlayerFleetRoleHelper.is_heavy_support(ship)
	)
	var pre_avoidance_offset: Vector3 = pre_avoidance.get("position_offset", Vector3.ZERO)
	if pre_avoidance_offset.length_squared() > 0.001:
		desired_point += pre_avoidance_offset
		heading_point = desired_point
		desired_speed_mult *= float(pre_avoidance.get("brake_mult", 1.0))

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
	var close_turn_blend: float = 0.0
	if ship.ai_close_turn_soft_radius > 0.01:
		close_turn_blend = clamp(1.0 - (dist_to_target / ship.ai_close_turn_soft_radius), 0.0, 1.0)
	var close_turn_factor: float = lerp(1.0, ship.ai_close_turn_scale, close_turn_blend)

	var leak_speed_mult: float = clamp(1.0 - (ship.leaking_rate * 0.05), 0.3, 1.0)
	var desired_speed: float = ship.move_speed * leak_speed_mult * desired_speed_mult * ship.get_shiphandling_multiplier()
	var rowing_speed_mult := _get_support_assist_rowing_speed_multiplier(dist_to_target, emergency_assist)
	if rescue_assist:
		desired_speed *= 1.08
	elif boss_breach_assist:
		desired_speed *= 1.12
	desired_speed *= rowing_speed_mult
	var assist_speed_response: float = SUPPORT_ASSIST_EMERGENCY_SPEED_RESPONSE if emergency_assist else SUPPORT_ASSIST_SPEED_RESPONSE
	var assist_accel_mult: float = 1.65 if rescue_assist else (1.55 if boss_breach_assist else (1.45 if emergency_assist else 1.0))
	var wind_floor := _get_support_assist_rowing_wind_floor(emergency_assist)
	var max_turn_rate_mult: float = 0.9 if rescue_assist else (0.88 if boss_breach_assist else (0.82 if emergency_assist else 0.68))
	_apply_role_navigation_motion(
		ship,
		delta,
		target_rotation_y,
		desired_speed,
		assist_speed_response,
		assist_accel_mult,
		wind_floor,
		close_turn_factor,
		max_turn_rate_mult,
		local_sep,
		assist_target,
		0.9,
		null,
		0.0,
		assist_target,
		0.45,
		true,
		true,
		step_delta
	)
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
	_draw_support_limbo_debug(ship)


static func _process_captured_guard_ai(ship, delta: float, guard_target: Node3D, minions: Array, my_index: int, motion_delta: float = -1.0) -> void:
	if not is_instance_valid(guard_target) or _is_ship_disabled(guard_target):
		return
	var step_delta: float = delta if motion_delta < 0.0 else maxf(motion_delta, 0.0)
	var emergency_guard: bool = is_instance_valid(ship.target) \
		and guard_target.has_method("get_boarding_target_ship") \
		and guard_target.call("get_boarding_target_ship") == ship.target

	var nav: Dictionary = _build_captured_guard_navigation(ship, guard_target, my_index)
	var desired_point: Vector3 = ShipMovementIntent.get_desired_point(nav, guard_target.global_position)
	var heading_point: Vector3 = ShipMovementIntent.get_heading_point(nav, desired_point)
	var dist_to_target: float = ShipMovementIntent.get_dist_to_target(nav, ship.global_position.distance_to(guard_target.global_position))
	var desired_speed_mult: float = ShipMovementIntent.get_desired_speed_mult(nav)

	var move_vector: Vector3 = desired_point - ship.global_position
	move_vector.y = 0.0
	var move_dir: Vector3 = move_vector.normalized() if move_vector.length_squared() > 0.001 else Vector3.ZERO
	var local_sep: Vector3 = _calculate_captured_guard_separation(ship, minions, guard_target)
	if local_sep.length_squared() > 0.001:
		move_dir = local_sep.normalized() if move_dir == Vector3.ZERO else (move_dir + local_sep).normalized()

	var heading_vector: Vector3 = heading_point - ship.global_position
	heading_vector.y = 0.0
	if heading_vector.length_squared() <= 0.001:
		heading_vector = move_dir if move_dir.length_squared() > 0.001 else _get_ship_forward_flat(guard_target)
	var target_rotation_y: float = atan2(-heading_vector.x, -heading_vector.z)
	var close_turn_blend: float = 0.0
	if ship.ai_close_turn_soft_radius > 0.01:
		close_turn_blend = clamp(1.0 - (dist_to_target / ship.ai_close_turn_soft_radius), 0.0, 1.0)
	var close_turn_factor: float = lerp(1.0, ship.ai_close_turn_scale, close_turn_blend)

	var leak_speed_mult: float = clamp(1.0 - (ship.leaking_rate * 0.05), 0.3, 1.0)
	var desired_speed: float = ship.move_speed * leak_speed_mult * desired_speed_mult * ship.get_shiphandling_multiplier()
	if emergency_guard:
		desired_speed *= 1.08
	var secondary_guard_target: Node3D = ship.target as Node3D if is_instance_valid(ship.target) else null
	_apply_role_navigation_motion(
		ship,
		delta,
		target_rotation_y,
		desired_speed,
		LEGACY_CAPTURE_GUARD_SPEED_RESPONSE + (0.18 if emergency_guard else 0.0),
		1.35 if emergency_guard else 1.2,
		LEGACY_CAPTURE_GUARD_ROWING_WIND_FLOOR,
		close_turn_factor,
		0.74 if emergency_guard else 0.62,
		local_sep,
		guard_target,
		0.9,
		secondary_guard_target,
		0.86,
		guard_target,
		0.35,
		false,
		false,
		step_delta
	)
	_draw_legacy_capture_limbo_debug(ship)


static func _apply_role_navigation_motion(
	ship,
	delta: float,
	target_rotation_y: float,
	desired_speed: float,
	speed_response: float,
	accel_mult: float,
	wind_floor: float,
	close_turn_factor: float,
	max_turn_rate_mult: float,
	local_sep: Vector3,
	primary_guard_target: Node3D,
	primary_guard_ratio: float,
	secondary_guard_target: Node3D = null,
	secondary_guard_ratio: float = 0.0,
	neighbor_guard_target: Node3D = null,
	collision_repulsion_scale: float = 0.0,
	record_support_trail: bool = false,
	apply_leak_damage: bool = false,
	motion_delta: float = -1.0
) -> void:
	var step_delta: float = delta if motion_delta < 0.0 else maxf(motion_delta, 0.0)
	var angle_diff: float = wrapf(target_rotation_y - ship.rotation.y, -PI, PI)
	var desired_rudder: float = clamp(-rad_to_deg(angle_diff) * ship.ai_rudder_gain, -40.0, 40.0)
	desired_rudder *= close_turn_factor
	var rudder_speed_adjusted: float = ship.ai_rudder_response_speed * ship.get_rudder_response_multiplier()
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	ship._last_ai_speed = lerp(float(ship._last_ai_speed), desired_speed, delta * speed_response)
	if ship._last_ai_speed > ship.current_speed:
		ship.current_speed = move_toward(ship.current_speed, ship._last_ai_speed, ship.acceleration * accel_mult * delta)
	else:
		ship.current_speed = move_toward(ship.current_speed, ship._last_ai_speed, ship.deceleration * delta)

	if ship.current_speed > 0.1:
		var speed_ratio: float = clamp(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0)
		var turn_scale: float = ship.ai_turn_authority * close_turn_factor
		var actual_turn: float = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * turn_scale * step_delta
		var max_turn_this_frame: float = ship.ai_max_turn_rate * max_turn_rate_mult * step_delta
		actual_turn = clamp(actual_turn, -max_turn_this_frame, max_turn_this_frame)
		ship.rotation.y -= deg_to_rad(actual_turn)

	var wind_mult: float = AIShipRuntimeHelper._calculate_sail_drive_multiplier(ship, wind_floor) * ship.get_shiphandling_multiplier()
	var forward_vec: Vector3 = Vector3(-sin(ship.rotation.y), 0.0, -cos(ship.rotation.y))
	var velocity: Vector3 = forward_vec * ship.current_speed * wind_mult
	velocity += local_sep
	if collision_repulsion_scale > 0.0:
		velocity += ship._calculate_collision_repulsion() * collision_repulsion_scale * step_delta

	var prev_pos: Vector3 = ship.global_position
	var next_pos: Vector3 = prev_pos + velocity * step_delta
	if is_instance_valid(primary_guard_target):
		next_pos = ship._apply_ship_collision_guard(primary_guard_target, prev_pos, next_pos, primary_guard_ratio, velocity.length(), false)
	if is_instance_valid(secondary_guard_target):
		next_pos = ship._apply_ship_collision_guard(secondary_guard_target, prev_pos, next_pos, secondary_guard_ratio, velocity.length(), false)
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, neighbor_guard_target)
	ship.global_position = next_pos
	if record_support_trail:
		_record_support_trail_point(ship)

	ship._update_rudder_visual()
	if apply_leak_damage and ship.leaking_rate > 0:
		ship.take_damage(ship.leaking_rate * delta)
	ship._apply_bobbing_effect()
	ship._set_wake_state(ship.current_speed > 0.4, clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0), 0.0, 0.0)


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


static func try_interrupt_boarding_for_flagship_rescue(ship) -> bool:
	if not is_instance_valid(ship):
		return false
	if not PlayerFleetRoleHelper.is_support_ship(ship):
		return false
	if ship.get_team_tag() != "player":
		return false
	if ship.get("is_boarding") != true:
		return false
	var player_ship := _get_support_flagship(ship)
	if not is_instance_valid(player_ship):
		return false
	var limbo_payload := _get_recent_support_limbo_payload(ship)
	var limbo_target := limbo_payload.get("target", null) as Node3D
	var limbo_rescue_mode := str(limbo_payload.get("mode", "")) == ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP
	var limbo_rescue_player := limbo_rescue_mode and (not is_instance_valid(limbo_target) or limbo_target == player_ship)
	var current_boarding_target := ship.get("boarding_target") as Node3D
	var rescue_boarding_active := current_boarding_target == player_ship \
		and ShipBoardingMetaHelper.is_boarding_purpose(ship, SupportBoardingHelper.SUPPORT_RESCUE_BOARDING_PURPOSE)
	if rescue_boarding_active:
		return false
	var current_target_team: String = ""
	if is_instance_valid(current_boarding_target):
		current_target_team = current_boarding_target.get_team_tag() if current_boarding_target.has_method("get_team_tag") else str(current_boarding_target.get("team"))
	var enemy_boarding_active := is_instance_valid(current_boarding_target) and current_target_team == "enemy"
	if not _is_player_deck_emergency(player_ship) and not limbo_rescue_player and not enemy_boarding_active:
		return false
	if ship.has_method("_cancel_boarding"):
		ship.call("_cancel_boarding")
	else:
		ship.set("is_boarding", false)
		ship.set("boarding_target", null)
		ShipBoardingMetaHelper.clear_boarding_link_meta(ship)
	_clear_support_assist_target_lock(ship)
	if _is_player_deck_emergency(player_ship) or limbo_rescue_player:
		_set_support_assist_target_lock(ship, player_ship)
	ShipBoardingMetaHelper.set_support_debug_mode(ship, ShipBoardingMetaHelper.SUPPORT_DEBUG_ASSIST)
	return true


static func _can_support_board_target(ship, assist_target: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(assist_target):
		return false
	if not PlayerFleetRoleHelper.is_support_ship(ship):
		return false
	if ship.get_team_tag() != "player":
		return false
	if ship.is_boarding:
		return false
	if _is_ship_disabled(assist_target):
		return false
	var target_team: String = assist_target.get_team_tag() if assist_target.has_method("get_team_tag") else str(assist_target.get("team"))
	var rescue_boarding: bool = _is_support_rescue_target(ship, assist_target)
	if not rescue_boarding:
		return false
	if target_team != "player":
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
	var player_ship: Node3D = _get_support_flagship(ship)
	var emergency_assist: bool = _is_player_deck_emergency(player_ship)
	var rescue_assist: bool = _is_support_rescue_target(ship, assist_target)
	var boss_breach_assist: bool = _is_support_boss_breach_target(ship, assist_target)
	var player_fwd: Vector3 = _get_ship_forward_flat(player_ship) if is_instance_valid(player_ship) else _get_ship_forward_flat(ship)
	var player_right: Vector3 = player_fwd.cross(Vector3.UP)
	if player_right.length_squared() <= 0.0001:
		player_right = Vector3.RIGHT
	else:
		player_right = player_right.normalized()

	var target_id: int = assist_target.get_instance_id()
	var current_target_id: int = int(ship.get_meta(SUPPORT_ASSIST_TARGET_ID_META, 0))
	var lane_assignment := _get_support_assist_lane_assignment(ship, my_index)
	var assigned_lane_side: float = float(lane_assignment.get("side", 0.0))
	var support_role_name := str(ship.get_meta(SUPPORT_FLEET_SLOT_ROLE_META, "")).strip_edges().to_lower()
	var screen_assist_role := support_role_name == "screen_lead" or support_role_name == "screen_flank"
	var lane_side: float = assigned_lane_side
	if absf(lane_side) < 0.5 and current_target_id == target_id:
		lane_side = float(ship.get_meta(SUPPORT_ASSIST_LANE_SIDE_META, 0.0))
	if absf(lane_side) < 0.5:
		var rel_to_player: Vector3 = ship.global_position - player_ship.global_position if is_instance_valid(player_ship) else ship.global_position - assist_target.global_position
		rel_to_player.y = 0.0
		lane_side = signf(rel_to_player.dot(player_right))
		if absf(lane_side) < 0.5:
			lane_side = 1.0 if (my_index % 2) == 0 else -1.0
	ship.set_meta(SUPPORT_ASSIST_LANE_SIDE_META, lane_side)
	ship.set_meta(SUPPORT_ASSIST_TARGET_ID_META, target_id)

	var pair_index: int = int(lane_assignment.get("rank", int(floor(float(my_index) / 2.0))))
	var collision_distance: float = ship.get_collision_distance_to(assist_target)
	var lane_distance: float = 0.0
	var rear_bias: float = 0.0
	if rescue_assist:
		lane_distance = maxf(4.0, collision_distance * 0.92) + float(pair_index) * 0.8
		rear_bias = float(pair_index) * 0.4
	elif boss_breach_assist:
		lane_distance = maxf(4.8, collision_distance * 0.86) + float(pair_index) * 0.65
		rear_bias = 0.55 + float(pair_index) * 0.28
	else:
		var lane_base: float = 8.0 if emergency_assist else (9.0 if screen_assist_role else 11.0)
		var lane_step: float = 1.6 if emergency_assist else (1.4 if screen_assist_role else 2.5)
		var lane_clearance: float = 1.6 if emergency_assist else (2.4 if screen_assist_role else 3.2)
		lane_distance = maxf(lane_base + float(pair_index) * lane_step, collision_distance + lane_clearance)
		rear_bias = (0.8 + float(pair_index) * 0.8) if emergency_assist else (0.0 if screen_assist_role else (2.4 + float(pair_index) * 1.2))
	var desired_point: Vector3 = assist_target.global_position
	if boss_breach_assist and is_instance_valid(player_ship):
		var breach_axis: Vector3 = assist_target.global_position - player_ship.global_position
		breach_axis.y = 0.0
		if breach_axis.length_squared() <= 0.001:
			breach_axis = player_fwd
		else:
			breach_axis = breach_axis.normalized()
		var breach_right: Vector3 = breach_axis.cross(Vector3.UP)
		if breach_right.length_squared() <= 0.0001:
			breach_right = player_right
		else:
			breach_right = breach_right.normalized()
		var flagship_collision: float = ship.get_collision_distance_to(player_ship)
		var flagship_target_distance: float = player_ship.global_position.distance_to(assist_target.global_position)
		var stand_off: float = maxf(collision_distance + 6.0, 11.0)
		var advance: float = clampf(flagship_target_distance * 0.42, 5.5, 14.0)
		advance = minf(advance, maxf(flagship_target_distance - stand_off, 4.8))
		var boss_lane_distance: float = maxf(7.8, flagship_collision + 2.8) + float(pair_index) * 1.15
		desired_point = player_ship.global_position + breach_axis * advance
		desired_point += breach_right * lane_side * boss_lane_distance
		desired_point -= breach_axis * (1.1 + float(pair_index) * 0.45)
	elif is_instance_valid(player_ship):
		var threat_axis: Vector3 = assist_target.global_position - player_ship.global_position
		threat_axis.y = 0.0
		if threat_axis.length_squared() <= 0.001:
			threat_axis = player_fwd
		else:
			threat_axis = threat_axis.normalized()
		var flagship_target_distance: float = player_ship.global_position.distance_to(assist_target.global_position)
		var stand_off: float = maxf(collision_distance + (4.0 if emergency_assist else (5.2 if screen_assist_role else 6.0)), 8.0 if emergency_assist else (10.0 if screen_assist_role else 11.0))
		var advance: float = clampf(
			flagship_target_distance * (0.30 if emergency_assist else (0.34 if screen_assist_role else 0.24)),
			3.8 if emergency_assist else (5.6 if screen_assist_role else 4.8),
			9.5 if emergency_assist else (13.0 if screen_assist_role else 11.5)
		)
		advance = minf(advance, maxf(flagship_target_distance - stand_off, 3.4))
		desired_point = player_ship.global_position + threat_axis * advance
		desired_point += player_right * lane_side * lane_distance
		desired_point -= player_fwd * rear_bias
	else:
		desired_point += player_right * lane_side * lane_distance
		desired_point -= player_fwd * rear_bias
	desired_point.y = ship.global_position.y

	if is_instance_valid(player_ship) and not rescue_assist:
		var player_clearance: float = maxf(6.4, ship.get_collision_distance_to(player_ship) + 1.4) if boss_breach_assist else maxf(10.0, ship.get_collision_distance_to(player_ship) + 3.0)
		var from_player: Vector3 = desired_point - player_ship.global_position
		from_player.y = 0.0
		if from_player.length_squared() < player_clearance * player_clearance:
			desired_point = player_ship.global_position + from_player.normalized() * player_clearance if from_player.length_squared() > 0.001 else player_ship.global_position + player_right * lane_side * player_clearance
			desired_point.y = ship.global_position.y

	var dist_to_lane: float = ship.global_position.distance_to(desired_point)
	var heading_point: Vector3 = assist_target.global_position
	if boss_breach_assist or dist_to_lane > (9.0 if emergency_assist else 13.0):
		heading_point = desired_point
	var desired_speed_mult: float = clampf(
		dist_to_lane / (9.0 if rescue_assist else (8.5 if boss_breach_assist else (11.0 if emergency_assist else 16.0))),
		0.42 if rescue_assist else (0.44 if boss_breach_assist else (0.35 if emergency_assist else 0.24)),
		1.22 if rescue_assist else (1.28 if boss_breach_assist else (1.18 if emergency_assist else 0.92))
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


static func _get_support_assist_lane_assignment(ship, my_index: int) -> Dictionary:
	var slot_index := my_index
	if is_instance_valid(ship):
		slot_index = int(ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, my_index))
	var normalized_index := maxi(maxi(slot_index, my_index), 0)
	var role_name := ""
	if is_instance_valid(ship):
		role_name = str(ship.get_meta(SUPPORT_FLEET_SLOT_ROLE_META, "")).strip_edges().to_lower()
	match role_name:
		"screen_lead":
			return {"side": -1.0, "rank": 0}
		"screen_flank":
			return {"side": 1.0, "rank": 0}
		"artillery_screen_left":
			return {"side": -1.0, "rank": 1}
		"artillery_screen_right":
			return {"side": 1.0, "rank": 1}
		"artillery_screen_front_left":
			return {"side": -1.0, "rank": 1}
		"artillery_screen_front_right":
			return {"side": 1.0, "rank": 1}
		"artillery_screen_rear_left":
			return {"side": -1.0, "rank": 2}
		"artillery_screen_rear_right":
			return {"side": 1.0, "rank": 2}
		"artillery_lead":
			return {"side": 1.0 if normalized_index % 2 == 0 else -1.0, "rank": 1}
		"rescue_rear":
			return {"side": 1.0 if normalized_index % 2 == 0 else -1.0, "rank": 2}
		_:
			return {
				"side": 1.0 if normalized_index % 2 == 0 else -1.0,
				"rank": int(floor(float(normalized_index) / 2.0)),
			}


static func _build_captured_guard_navigation(ship, guard_target: Node3D, my_index: int) -> Dictionary:
	var flagship: Node3D = ship.target if is_instance_valid(ship.target) else null
	var flagship_fwd: Vector3 = _get_ship_forward_flat(flagship) if is_instance_valid(flagship) else _get_ship_forward_flat(ship)
	var flagship_right: Vector3 = flagship_fwd.cross(Vector3.UP)
	if flagship_right.length_squared() <= 0.0001:
		flagship_right = Vector3.RIGHT
	else:
		flagship_right = flagship_right.normalized()

	var target_id: int = guard_target.get_instance_id()
	var current_target_id: int = int(ship.get_meta(LEGACY_CAPTURE_GUARD_TARGET_ID_META, 0))
	var lane_side: float = float(ship.get_meta(LEGACY_CAPTURE_GUARD_LANE_SIDE_META, 0.0))
	if current_target_id != target_id or absf(lane_side) < 0.5:
		var rel_to_guard: Vector3 = ship.global_position - guard_target.global_position
		rel_to_guard.y = 0.0
		lane_side = signf(rel_to_guard.dot(flagship_right))
		if absf(lane_side) < 0.5:
			lane_side = 1.0 if (my_index % 2) == 0 else -1.0
		ship.set_meta(LEGACY_CAPTURE_GUARD_LANE_SIDE_META, lane_side)
	ship.set_meta(LEGACY_CAPTURE_GUARD_TARGET_ID_META, target_id)

	var pair_index: int = int(floor(float(my_index) / 2.0))
	var collision_distance: float = ship.get_collision_distance_to(guard_target)
	var is_boarding_flagship: bool = is_instance_valid(flagship) \
		and guard_target.has_method("get_boarding_target_ship") \
		and guard_target.call("get_boarding_target_ship") == flagship
	var lane_base: float = 6.0 if is_boarding_flagship else 8.5
	var rear_bias: float = 1.4 if is_boarding_flagship else 3.2
	var lane_clearance: float = 0.9 if is_boarding_flagship else 2.4
	var lane_distance: float = maxf(lane_base + float(pair_index) * 1.4, collision_distance + lane_clearance)

	var desired_point: Vector3 = guard_target.global_position
	desired_point += flagship_right * lane_side * lane_distance
	desired_point -= flagship_fwd * (rear_bias + float(pair_index) * 0.75)
	desired_point.y = ship.global_position.y

	if is_instance_valid(flagship):
		var player_clearance: float = maxf(8.0, ship.get_collision_distance_to(flagship) + 2.0)
		var from_player: Vector3 = desired_point - flagship.global_position
		from_player.y = 0.0
		if from_player.length_squared() < player_clearance * player_clearance:
			desired_point = flagship.global_position + from_player.normalized() * player_clearance if from_player.length_squared() > 0.001 else flagship.global_position + flagship_right * lane_side * player_clearance
			desired_point.y = ship.global_position.y

	var dist_to_lane: float = ship.global_position.distance_to(desired_point)
	var heading_point: Vector3 = guard_target.global_position if dist_to_lane <= 10.0 else desired_point
	var desired_speed_mult: float = clampf(dist_to_lane / (8.5 if is_boarding_flagship else 13.0), 0.4 if is_boarding_flagship else 0.34, 1.14 if is_boarding_flagship else 0.98)
	var dir_to_target: Vector3 = guard_target.global_position - ship.global_position
	dir_to_target.y = 0.0
	if dir_to_target.length_squared() > 0.001:
		dir_to_target = dir_to_target.normalized()
	return ShipMovementIntent.build(
		guard_target.global_position,
		desired_point,
		heading_point,
		ship.global_position.distance_to(guard_target.global_position),
		desired_speed_mult,
		is_boarding_flagship,
		dir_to_target,
		"legacy_capture_guard"
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
		var separation_radius := _get_support_assist_separation_radius(ship, other as Node3D)
		if dist <= 0.1 or dist >= separation_radius:
			continue
		var radius_scale := clampf(separation_radius / maxf(SUPPORT_ASSIST_SEPARATION_RADIUS, 0.001), 1.0, 1.8)
		var strength: float = pow((separation_radius - dist) / separation_radius, 2.0)
		force += offset.normalized() * strength * SUPPORT_ASSIST_SEPARATION_FORCE * radius_scale
		count += 1
	if is_instance_valid(assist_target):
		var target_offset: Vector3 = ship.global_position - assist_target.global_position
		target_offset.y = 0.0
		var target_dist: float = target_offset.length()
		var collision_dist: float = ship.get_collision_distance_to(assist_target)
		var target_separation_radius: float = collision_dist + SUPPORT_ASSIST_SEPARATION_PAD
		if target_dist > 0.1 and target_dist < target_separation_radius:
			var strength: float = (target_separation_radius - target_dist) / maxf(target_separation_radius, 0.001)
			force += target_offset.normalized() * strength * SUPPORT_ASSIST_SEPARATION_FORCE
			count += 1
	return force / max(count, 1)


static func _get_support_assist_separation_radius(ship, other_ship: Node3D) -> float:
	if not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return SUPPORT_ASSIST_SEPARATION_RADIUS
	var separation_radius := maxf(
		SUPPORT_ASSIST_SEPARATION_RADIUS,
		ShipContactGeometry.get_collision_distance_between(ship, other_ship) + SUPPORT_ASSIST_SEPARATION_PAD
	)
	if PlayerFleetRoleHelper.is_heavy_support(ship) or PlayerFleetRoleHelper.is_heavy_support(other_ship):
		separation_radius += SUPPORT_ASSIST_PANOKSEON_SEPARATION_EXTRA_PAD
	return separation_radius


static func _calculate_captured_guard_separation(ship, minions: Array, guard_target: Node3D) -> Vector3:
	var force: Vector3 = Vector3.ZERO
	var count: int = 0
	for other in minions:
		if other == ship or not is_instance_valid(other):
			continue
		var offset: Vector3 = ship.global_position - other.global_position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist <= 0.1 or dist >= LEGACY_CAPTURE_GUARD_SEPARATION_RADIUS:
			continue
		var strength: float = pow((LEGACY_CAPTURE_GUARD_SEPARATION_RADIUS - dist) / LEGACY_CAPTURE_GUARD_SEPARATION_RADIUS, 2.0)
		force += offset.normalized() * strength * LEGACY_CAPTURE_GUARD_SEPARATION_FORCE
		count += 1
	if is_instance_valid(guard_target):
		var target_offset: Vector3 = ship.global_position - guard_target.global_position
		target_offset.y = 0.0
		var target_dist: float = target_offset.length()
		var collision_dist: float = ship.get_collision_distance_to(guard_target)
		if target_dist > 0.1 and target_dist < collision_dist + 1.6:
			var strength: float = (collision_dist + 1.6 - target_dist) / maxf(collision_dist + 1.6, 0.001)
			force += target_offset.normalized() * strength * LEGACY_CAPTURE_GUARD_SEPARATION_FORCE
			count += 1
	return force / max(count, 1)

static func _get_support_roster(ship, support_only: bool) -> Array:
	var roster_flagship: Node3D = SupportFleetStateHelper.get_support_owner_flagship(ship) if support_only else null
	if support_only:
		var current_frame: int = Engine.get_physics_frames()
		if current_frame != _support_roster_cache_frame:
			_support_roster_cache_frame = current_frame
			_support_roster_cache.clear()
		var cache_key: int = roster_flagship.get_instance_id() if is_instance_valid(roster_flagship) else 0
		if _support_roster_cache.has(cache_key):
			return _support_roster_cache[cache_key]

	var roster: Array = []
	var roster_candidates: Array = ship.get_support_ships_cached(ship.get_tree()) if support_only else ship.get_minions_cached(ship.get_tree())
	for candidate_ship in roster_candidates:
		if not is_instance_valid(candidate_ship):
			continue
		var is_roster_support := PlayerFleetRoleHelper.is_support_ship(candidate_ship)
		if support_only and not is_roster_support:
			continue
		if not support_only and is_roster_support:
			continue
		if support_only and is_instance_valid(roster_flagship) and not SupportFleetStateHelper.is_support_owned_by_flagship(candidate_ship, roster_flagship):
			continue
		roster.append(candidate_ship)
	if support_only:
		roster.sort_custom(func(a, b):
			var order_a: int = int(a.get_meta(SUPPORT_FLEET_ORDER_META, a.get_instance_id()))
			var order_b: int = int(b.get_meta(SUPPORT_FLEET_ORDER_META, b.get_instance_id()))
			var slot_a: int = int(a.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, order_a))
			var slot_b: int = int(b.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, order_b))
			if slot_a != slot_b:
				return slot_a < slot_b
			return order_a < order_b
		)
		var support_cache_key: int = roster_flagship.get_instance_id() if is_instance_valid(roster_flagship) else 0
		_support_roster_cache[support_cache_key] = roster
	return roster

static func _get_support_offset(ship, my_index: int, is_support_ship: bool) -> Vector3:
	if is_support_ship:
		var support_spacing: float = SUPPORT_COLUMN_FORMATION_SPACING if SupportFleetStateHelper.get_effective_formation(ship) == SupportFleetFormationHelper.FORMATION_COLUMN else SUPPORT_FORMATION_SPACING
		return SupportFleetFormationHelper.get_support_fleet_offset(ship, my_index, support_spacing)

	var offset: Vector3 = Vector3.ZERO
	var base_spacing: float = 10.0
	var formation_dist: float = base_spacing + (my_index * base_spacing)
	var formation_value: int = 0 if int(ship.fleet_formation) == 0 else 1

	match formation_value:
		0:
			offset = Vector3(0, 0, formation_dist)
		1:
			var side: int = 1 if my_index % 2 == 0 else -1
			var row: float = floor(my_index / 2.0) + 1
			offset = Vector3(base_spacing * side * row, 0, base_spacing * row)
	return offset

static func _get_support_assist_target(ship, player_ship: Node3D, delta: float) -> Node3D:
	if not is_instance_valid(ship) or not is_instance_valid(player_ship):
		return null
	var limbo_payload := _get_recent_support_limbo_payload(ship)
	var has_limbo_decision := not limbo_payload.is_empty()
	var limbo_mode := str(limbo_payload.get("mode", ""))
	var limbo_target := limbo_payload.get("target", null) as Node3D
	var deck_emergency: bool = _is_player_deck_emergency(player_ship)
	var pilot_rescue_mode: bool = limbo_mode == ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP \
		and (not is_instance_valid(limbo_target) or limbo_target == player_ship)
	if pilot_rescue_mode:
		deck_emergency = true
	var recall_distance: float = SUPPORT_ASSIST_EMERGENCY_RECALL_DISTANCE if deck_emergency else SUPPORT_ASSIST_RECALL_DISTANCE
	var leash_distance: float = SUPPORT_ASSIST_EMERGENCY_LEASH_DISTANCE if deck_emergency else SUPPORT_ASSIST_LEASH_DISTANCE
	var threat_range: float = SUPPORT_ASSIST_EMERGENCY_THREAT_RANGE if deck_emergency else SUPPORT_ASSIST_THREAT_RANGE
	var eval_interval: float = SUPPORT_ASSIST_EVAL_INTERVAL_EMERGENCY if deck_emergency else SUPPORT_ASSIST_EVAL_INTERVAL
	var switch_margin: float = SUPPORT_ASSIST_SWITCH_MARGIN
	var lock_duration: float = SUPPORT_ASSIST_TARGET_LOCK_DURATION
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
	var eval_timer: float = maxf(0.0, float(ship.get_meta(SUPPORT_ASSIST_EVAL_TIMER_META, 0.0)) - delta)
	ship.set_meta(SUPPORT_ASSIST_LOCK_TIMER_META, lock_timer)
	ship.set_meta(SUPPORT_ASSIST_EVAL_TIMER_META, eval_timer)
	var deck_contested: bool = player_ship.get("deck_is_contested") == true or player_ship.get("deck_is_overrun") == true
	var deck_overrun: bool = player_ship.get("deck_is_overrun") == true
	var formation_hold_enabled: bool = _is_support_formation_hold_enabled(ship)
	var line_holder_free_assist: bool = SupportFleetFormationHelper.should_hold_line_during_free_assist(ship)
	var player_boarding_attacker: Node3D = null
	if player_ship.has_method("get_boarding_attacker_ship"):
		player_boarding_attacker = player_ship.call("get_boarding_attacker_ship")
	if has_limbo_decision:
		match limbo_mode:
			ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP:
				if support_dist_to_player <= leash_distance:
					_set_support_assist_target_lock(ship, player_ship, lock_duration)
					return player_ship
				_clear_support_assist_target_lock(ship)
				return null
			ShipAILimboKeys.SUPPORT_MODE_BREACH_BOSS:
				_clear_support_assist_target_lock(ship)
				return null
			ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT:
				if formation_hold_enabled and is_instance_valid(player_boarding_attacker) and limbo_target != player_boarding_attacker:
					_clear_support_assist_target_lock(ship)
					return null
				if line_holder_free_assist and limbo_target != player_boarding_attacker:
					_clear_support_assist_target_lock(ship)
					return null
				if is_instance_valid(limbo_target) and not _is_ship_disabled(limbo_target):
					var pilot_target_dist: float = ship.global_position.distance_to(limbo_target.global_position)
					if pilot_target_dist <= leash_distance:
						_set_support_assist_target_lock(ship, limbo_target, lock_duration)
						return limbo_target
				_clear_support_assist_target_lock(ship)
				return null
			ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP, ShipAILimboKeys.SUPPORT_MODE_REGROUP:
				_clear_support_assist_target_lock(ship)
				return null
	if pilot_rescue_mode and support_dist_to_player <= leash_distance:
		_set_support_assist_target_lock(ship, player_ship, lock_duration)
		return player_ship
	if _is_support_rescue_target(ship, player_ship):
		if support_dist_to_player <= leash_distance:
			_set_support_assist_target_lock(ship, player_ship, lock_duration)
			return player_ship
	if formation_hold_enabled:
		var hold_boarding_attacker: Node3D = player_boarding_attacker
		if is_instance_valid(hold_boarding_attacker) and not _is_ship_disabled(hold_boarding_attacker):
			var hold_support_dist: float = ship.global_position.distance_to(hold_boarding_attacker.global_position)
			if hold_support_dist <= leash_distance:
				_set_support_assist_target_lock(ship, hold_boarding_attacker, lock_duration)
				return hold_boarding_attacker
		_clear_support_assist_target_lock(ship)
		return null
	if line_holder_free_assist:
		if is_instance_valid(player_boarding_attacker) and not _is_ship_disabled(player_boarding_attacker):
			var line_holder_attacker_dist: float = ship.global_position.distance_to(player_boarding_attacker.global_position)
			if line_holder_attacker_dist <= leash_distance:
				_set_support_assist_target_lock(ship, player_boarding_attacker, lock_duration)
				return player_boarding_attacker
		_clear_support_assist_target_lock(ship)
		return null
	if not deck_emergency and support_dist_to_player > SUPPORT_ASSIST_SOFT_RECALL_DISTANCE and not is_instance_valid(player_boarding_attacker):
		_clear_support_assist_target_lock(ship)
		return null
	if limbo_mode == ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT and is_instance_valid(limbo_target):
		var pilot_screen_dist: float = ship.global_position.distance_to(limbo_target.global_position)
		if pilot_screen_dist <= leash_distance:
			_set_support_assist_target_lock(ship, limbo_target, lock_duration)
			return limbo_target
	var cached_target: Node3D = NodeContractHelper.get_instance_node3d(locked_target_id) if locked_target_id != 0 else null
	if eval_timer > 0.0:
		if is_instance_valid(cached_target) and not _is_ship_disabled(cached_target):
			if cached_target == player_ship:
				if support_dist_to_player <= leash_distance:
					return cached_target
			else:
				var cached_support_dist: float = ship.global_position.distance_to(cached_target.global_position)
				if cached_support_dist <= leash_distance:
					return cached_target
		elif locked_target_id == 0:
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
		score += _get_support_assist_assignment_penalty(
			ship,
			player_ship,
			enemy,
			leash_distance,
			deck_emergency,
			deck_contested,
			deck_overrun,
			is_boarding_player,
			is_close_threat
		)
		if enemy.get_instance_id() == locked_target_id:
			locked_target = enemy
			locked_score = score
			if lock_timer > 0.0:
				score -= switch_margin
		if score < best_score:
			best_score = score
			best_target = enemy

	var boarding_attacker: Node3D = player_boarding_attacker
	if is_instance_valid(boarding_attacker) and not _is_ship_disabled(boarding_attacker):
		var support_dist_to_attacker: float = ship.global_position.distance_to(boarding_attacker.global_position)
		if support_dist_to_attacker <= leash_distance:
			_set_support_assist_target_lock(ship, boarding_attacker, lock_duration)
			ship.set_meta(SUPPORT_ASSIST_EVAL_TIMER_META, eval_interval)
			return boarding_attacker

	if is_instance_valid(locked_target) and lock_timer > 0.0:
		ship.set_meta(SUPPORT_ASSIST_EVAL_TIMER_META, eval_interval)
		return locked_target
	if is_instance_valid(locked_target) and is_instance_valid(best_target) and locked_target != best_target:
		if locked_score <= best_score + switch_margin:
			_set_support_assist_target_lock(ship, locked_target, lock_duration)
			ship.set_meta(SUPPORT_ASSIST_EVAL_TIMER_META, eval_interval)
			return locked_target
	if is_instance_valid(best_target):
		_set_support_assist_target_lock(ship, best_target, lock_duration)
	else:
		_clear_support_assist_target_lock(ship)
	ship.set_meta(SUPPORT_ASSIST_EVAL_TIMER_META, eval_interval)
	return best_target


static func _get_support_assist_assignment_penalty(
	ship,
	player_ship: Node3D,
	candidate: Node3D,
	leash_distance: float,
	deck_emergency: bool,
	deck_contested: bool,
	deck_overrun: bool,
	is_boarding_player: bool,
	is_close_threat: bool
) -> float:
	if not is_instance_valid(ship) or not is_instance_valid(player_ship) or not is_instance_valid(candidate):
		return 0.0
	var candidate_id: int = candidate.get_instance_id()
	var owner_flagship: Node3D = SupportFleetStateHelper.get_support_owner_flagship(ship)
	if not is_instance_valid(owner_flagship):
		owner_flagship = player_ship
	var assigned_count: int = 0
	for allied_ship in EntityRegistry.get_ships_by_team("player"):
		var support_ship := allied_ship as Node3D
		if not is_instance_valid(support_ship) or support_ship == ship:
			continue
		if not PlayerFleetRoleHelper.is_support_ship(support_ship):
			continue
		if _is_ship_disabled(support_ship):
			continue
		if is_instance_valid(owner_flagship) and not SupportFleetStateHelper.is_support_owned_by_flagship(support_ship, owner_flagship):
			continue
		if int(support_ship.get_meta(SUPPORT_ASSIST_TARGET_ID_META, 0)) != candidate_id:
			continue
		if support_ship.global_position.distance_to(candidate.global_position) > leash_distance + SUPPORT_ASSIST_TARGET_SHARE_LEASH_PAD:
			continue
		assigned_count += 1
	if assigned_count <= 0:
		return 0.0

	var target_capacity: int = SUPPORT_ASSIST_TARGET_SHARE_CAPACITY
	if is_boarding_player:
		target_capacity = SUPPORT_ASSIST_TARGET_BOARDING_CAPACITY
	elif deck_emergency or deck_overrun or _is_boss_ship(candidate):
		target_capacity = SUPPORT_ASSIST_TARGET_DANGER_CAPACITY
	elif deck_contested and is_close_threat:
		target_capacity = SUPPORT_ASSIST_TARGET_DANGER_CAPACITY
	var overflow: int = assigned_count - target_capacity + 1
	if overflow <= 0:
		return 0.0
	var penalty_base: float = SUPPORT_ASSIST_TARGET_SHARE_PENALTY_EMERGENCY if deck_emergency or is_boarding_player else SUPPORT_ASSIST_TARGET_SHARE_PENALTY
	return float(overflow) * penalty_base


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
	if not PlayerFleetRoleHelper.is_support_ship(ship):
		return false
	if not is_instance_valid(ship.target) or assist_target != ship.target:
		return false
	var target_team: String = assist_target.get_team_tag() if assist_target.has_method("get_team_tag") else str(assist_target.get("team"))
	if target_team != "player":
		return false
	var limbo_payload := _get_recent_support_limbo_payload(ship)
	var limbo_target := limbo_payload.get("target", null) as Node3D
	if str(limbo_payload.get("mode", "")) == ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP \
		and (not is_instance_valid(limbo_target) or limbo_target == assist_target):
		return true
	if assist_target.get("deck_is_overrun") == true:
		return true
	var hostile_count: int = int(assist_target.get("deck_hostile_boarder_count")) if assist_target.get("deck_hostile_boarder_count") != null else 0
	var deck_contested: bool = assist_target.get("deck_is_contested") == true
	return hostile_count > 0 and deck_contested


static func _is_support_boss_breach_target(ship, assist_target: Node3D) -> bool:
	return false


static func _is_boss_ship(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.is_in_group("boss"):
		return true
	var ship_type_value: Variant = ship.get("ship_type")
	return str(ship_type_value).to_lower().contains("atakebune")


static func _is_support_formation_hold_enabled(ship) -> bool:
	return SupportFleetStateHelper.is_effective_hold_enabled(ship)


static func _get_support_flagship(ship) -> Node3D:
	if not is_instance_valid(ship):
		return null
	var owner_flagship := SupportFleetStateHelper.get_support_owner_flagship(ship)
	if is_instance_valid(owner_flagship):
		return owner_flagship
	return ship.target as Node3D if is_instance_valid(ship.target) else null


static func _get_recent_support_limbo_payload(ship) -> Dictionary:
	if not is_instance_valid(ship):
		return {}
	var support_intent := ShipAIIntentHelper.get_limbo_support_intent(ship, SUPPORT_LIMBO_PILOT_STALE_FRAMES)
	if support_intent.is_empty():
		return {}
	var target_id := int(support_intent.get(ShipAIIntentHelper.KEY_TARGET_ID, 0))
	var support_target: Node3D = null
	if target_id != 0:
		support_target = NodeContractHelper.get_instance_node3d(target_id)
	return {
		"mode": str(support_intent.get(ShipAIIntentHelper.KEY_MODE, "")).strip_edges(),
		"target": support_target,
		"frame": int(support_intent.get(ShipAIIntentHelper.KEY_FRAME, -1000000)),
		"reason": str(support_intent.get(ShipAIIntentHelper.KEY_REASON, "")).strip_edges(),
	}


static func _get_recent_legacy_capture_limbo_payload(ship) -> Dictionary:
	if not is_instance_valid(ship):
		return {}
	if not PlayerFleetRoleHelper.is_legacy_captured_ship(ship) or PlayerFleetRoleHelper.is_support_ship(ship):
		return {}
	var legacy_capture_intent := ShipAIIntentHelper.get_limbo_legacy_capture_intent(ship, LEGACY_CAPTURE_LIMBO_PILOT_STALE_FRAMES)
	if legacy_capture_intent.is_empty():
		return {}
	var target_id := int(legacy_capture_intent.get(ShipAIIntentHelper.KEY_TARGET_ID, 0))
	var legacy_capture_target: Node3D = null
	if target_id != 0:
		legacy_capture_target = NodeContractHelper.get_instance_node3d(target_id)
	return {
		"mode": str(legacy_capture_intent.get(ShipAIIntentHelper.KEY_MODE, "")).strip_edges(),
		"target": legacy_capture_target,
		"frame": int(legacy_capture_intent.get(ShipAIIntentHelper.KEY_FRAME, -1000000)),
		"reason": str(legacy_capture_intent.get(ShipAIIntentHelper.KEY_REASON, "")).strip_edges(),
	}


static func _draw_support_limbo_debug(ship) -> void:
	if not DebugDrawBridge.is_channel_enabled(DebugDrawBridge.CHANNEL_AI_INTENT) or not DebugDrawBridge.can_draw():
		return
	if not (ship is Node3D):
		return
	var payload := _get_recent_support_limbo_payload(ship)
	var mode := str(payload.get("mode", "")).strip_edges()
	if mode.is_empty():
		return
	var support_target := payload.get("target", null) as Node3D
	var reason := str(payload.get("reason", "")).strip_edges()
	var color := _get_support_limbo_color(mode)
	var label := "LimboAI support:%s\nreason:%s target:%s" % [
		mode,
		reason if not reason.is_empty() else "-",
		support_target.name if is_instance_valid(support_target) else "-",
	]
	DebugDrawBridge.draw_text(ship.global_position + Vector3.UP * 4.0, label, color, 0.0, 15)
	if is_instance_valid(support_target):
		DebugDrawBridge.draw_line_raised(ship.global_position, support_target.global_position, 2.55, color, 0.0, 0.03)
		DebugDrawBridge.draw_marker(support_target.global_position, color, mode, 0.0, 0.22, 1.7)


static func _draw_legacy_capture_limbo_debug(ship) -> void:
	if not DebugDrawBridge.is_channel_enabled(DebugDrawBridge.CHANNEL_AI_INTENT) or not DebugDrawBridge.can_draw():
		return
	if not (ship is Node3D):
		return
	var payload := _get_recent_legacy_capture_limbo_payload(ship)
	var mode := str(payload.get("mode", "")).strip_edges()
	if mode.is_empty():
		return
	var legacy_capture_target := payload.get("target", null) as Node3D
	var reason := str(payload.get("reason", "")).strip_edges()
	var color := _get_legacy_capture_limbo_color(mode)
	var label := "LimboAI legacy-capture:%s\nreason:%s target:%s" % [
		mode,
		reason if not reason.is_empty() else "-",
		legacy_capture_target.name if is_instance_valid(legacy_capture_target) else "-",
	]
	DebugDrawBridge.draw_text(ship.global_position + Vector3.UP * 3.8, label, color, 0.0, 14)
	if is_instance_valid(legacy_capture_target):
		DebugDrawBridge.draw_line_raised(ship.global_position, legacy_capture_target.global_position, 2.05, color, 0.0, 0.026)
		DebugDrawBridge.draw_marker(legacy_capture_target.global_position, color, mode, 0.0, 0.18, 1.35)


static func _get_support_limbo_color(mode: String) -> Color:
	match mode:
		ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP:
			return Color(0.24, 1.0, 0.58, 0.94)
		ShipAILimboKeys.SUPPORT_MODE_BREACH_BOSS:
			return Color(1.0, 0.36, 0.18, 0.94)
		ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT:
			return Color(1.0, 0.58, 0.18, 0.94)
		ShipAILimboKeys.SUPPORT_MODE_REGROUP:
			return Color(0.35, 0.72, 1.0, 0.94)
		_:
			return Color(0.78, 1.0, 0.38, 0.94)


static func _get_legacy_capture_limbo_color(mode: String) -> Color:
	match mode:
		ShipAILimboKeys.ALLY_MODE_GUARD_THREAT:
			return Color(1.0, 0.68, 0.18, 0.92)
		ShipAILimboKeys.ALLY_MODE_REGROUP:
			return Color(0.42, 0.82, 1.0, 0.92)
		_:
			return Color(0.76, 1.0, 0.52, 0.9)


static func _set_support_assist_target_lock(ship, assist_target: Node3D, lock_duration: float = SUPPORT_ASSIST_TARGET_LOCK_DURATION) -> void:
	var previous_target_id: int = int(ship.get_meta(SUPPORT_ASSIST_TARGET_ID_META, 0))
	if previous_target_id != assist_target.get_instance_id() and ship.has_meta(SUPPORT_ASSIST_LANE_SIDE_META):
		ship.remove_meta(SUPPORT_ASSIST_LANE_SIDE_META)
	ship.set_meta(SUPPORT_ASSIST_TARGET_ID_META, assist_target.get_instance_id())
	ship.set_meta(SUPPORT_ASSIST_LOCK_TIMER_META, maxf(lock_duration, 0.0))

static func _clear_support_assist_target_lock(ship) -> void:
	if ship.has_meta(SUPPORT_ASSIST_TARGET_ID_META):
		ship.remove_meta(SUPPORT_ASSIST_TARGET_ID_META)
	if ship.has_meta(SUPPORT_ASSIST_LOCK_TIMER_META):
		ship.remove_meta(SUPPORT_ASSIST_LOCK_TIMER_META)
	if ship.has_meta(SUPPORT_ASSIST_LANE_SIDE_META):
		ship.remove_meta(SUPPORT_ASSIST_LANE_SIDE_META)


static func _calculate_support_pre_avoidance(
	ship,
	minions: Array,
	flagship: Node3D,
	target_pos: Vector3,
	planning_speed: float,
	is_heavy_support: bool
) -> Dictionary:
	if not is_instance_valid(ship):
		return {"position_offset": Vector3.ZERO, "brake_mult": 1.0, "hazard": 0.0, "lateral": 0.0}
	var to_target: Vector3 = target_pos - ship.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return {"position_offset": Vector3.ZERO, "brake_mult": 1.0, "hazard": 0.0, "lateral": 0.0}
	var planned_dir: Vector3 = to_target.normalized()
	var planned_right: Vector3 = planned_dir.cross(Vector3.UP).normalized()
	if planned_right.length_squared() <= 0.0001:
		planned_right = Vector3.RIGHT
	var lookahead_time: float = SUPPORT_PRE_AVOID_LOOKAHEAD + minf(planning_speed * SUPPORT_PRE_AVOID_LOOKAHEAD_SPEED_SCALE, 0.42)
	var projected_self: Vector3 = ship.global_position + planned_dir * maxf(planning_speed, ship.current_speed) * lookahead_time
	var lateral_offset := Vector3.ZERO
	var brake_mult: float = 1.0
	var max_hazard: float = 0.0
	var candidate_ships: Array = minions.duplicate()
	if is_instance_valid(flagship) and not candidate_ships.has(flagship):
		candidate_ships.append(flagship)
	for candidate in candidate_ships:
		if candidate == ship or not is_instance_valid(candidate) or _is_ship_disabled(candidate):
			continue
		if not (candidate is Node3D):
			continue
		var candidate_ship := candidate as Node3D
		var to_candidate: Vector3 = candidate_ship.global_position - ship.global_position
		to_candidate.y = 0.0
		if to_candidate.length_squared() <= 0.0001:
			continue
		var forward_alignment: float = planned_dir.dot(to_candidate.normalized())
		if forward_alignment < SUPPORT_PRE_AVOID_MIN_FORWARD_ALIGNMENT:
			continue
		var candidate_dir: Vector3 = _get_ship_forward_flat(candidate_ship)
		var candidate_speed: float = _get_ship_speed(candidate_ship, 0.0)
		var projected_candidate: Vector3 = candidate_ship.global_position + candidate_dir * candidate_speed * lookahead_time
		var predicted_diff: Vector3 = projected_self - projected_candidate
		predicted_diff.y = 0.0
		var predicted_dist: float = predicted_diff.length()
		var safe_distance: float = ShipContactGeometry.get_collision_distance_between(ship, candidate_ship) + SUPPORT_PRE_AVOID_TRIGGER_PAD
		if is_heavy_support or PlayerFleetRoleHelper.is_heavy_support(candidate_ship):
			safe_distance += SUPPORT_PRE_AVOID_PANOKSEON_EXTRA_PAD
		var trigger_distance: float = safe_distance * 1.12
		if predicted_dist >= trigger_distance:
			continue
		var hazard: float = clampf((trigger_distance - predicted_dist) / maxf(trigger_distance, 0.001), 0.0, 1.0)
		max_hazard = maxf(max_hazard, hazard)
		var min_brake_mult: float = SUPPORT_PRE_AVOID_PANOKSEON_BRAKE_MULT if is_heavy_support else SUPPORT_PRE_AVOID_BASE_BRAKE_MULT
		brake_mult = minf(brake_mult, lerpf(1.0, min_brake_mult, hazard))
		var side_sign: float = signf(predicted_diff.dot(planned_right))
		if absf(side_sign) < 0.5:
			side_sign = 1.0 if ship.get_instance_id() < candidate_ship.get_instance_id() else -1.0
		lateral_offset += planned_right * side_sign * hazard * SUPPORT_PRE_AVOID_MAX_LATERAL_OFFSET
	if lateral_offset.length_squared() > 0.0001:
		lateral_offset = lateral_offset.limit_length(SUPPORT_PRE_AVOID_MAX_LATERAL_OFFSET * (1.2 if is_heavy_support else 1.0))
	return {
		"position_offset": lateral_offset,
		"brake_mult": brake_mult,
		"hazard": max_hazard,
		"lateral": lateral_offset.dot(planned_right),
	}


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
	SupportFleetFormationHelper.record_trail_point(
		node,
		SUPPORT_TRAIL_POINT_DISTANCE,
		SUPPORT_TRAIL_MAX_POINTS,
		SUPPORT_TRAIL_POINTS_META
	)
