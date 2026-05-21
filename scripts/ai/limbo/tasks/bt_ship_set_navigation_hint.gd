@tool
extends BTAction
class_name BTShipSetNavigationHint

const ShipAIPerceptionHelper = preload("res://scripts/ai/limbo/ship_ai_perception_helper.gd")

@export var target_var: StringName = ShipAILimboKeys.VAR_TARGET
@export var intent_var: StringName = ShipAILimboKeys.VAR_INTENT
@export var stance_var: StringName = ShipAILimboKeys.VAR_STANCE
@export var pressure_var: StringName = ShipAILimboKeys.VAR_PRESSURE
@export var desired_point_var: StringName = ShipAILimboKeys.VAR_NAV_DESIRED_POINT
@export var heading_point_var: StringName = ShipAILimboKeys.VAR_NAV_HEADING_POINT
@export var speed_mult_var: StringName = ShipAILimboKeys.VAR_NAV_SPEED_MULT
@export var permit_sprint_var: StringName = ShipAILimboKeys.VAR_NAV_PERMIT_SPRINT
@export var mode_var: StringName = ShipAILimboKeys.VAR_NAV_MODE
@export var default_preferred_range: float = 14.0
@export var default_range_tolerance: float = 2.5
@export var default_retreat_range: float = 8.0


func _generate_name() -> String:
	return "ShipSetNavigationHint -> %s" % LimboUtility.decorate_var(desired_point_var)


func _tick(_delta: float) -> Status:
	var agent_3d := agent as Node3D
	if not is_instance_valid(agent_3d):
		return FAILURE

	_clear_navigation_hint(agent_3d)
	var target := blackboard.get_var(target_var, null) as Node3D
	if not is_instance_valid(target):
		return FAILURE

	var stance := str(blackboard.get_var(stance_var, "")).strip_edges()
	if stance.is_empty():
		return SUCCESS
	var is_gunner := ShipAIPerceptionHelper.is_ship_gunner(agent_3d)
	var can_board := ShipAIPerceptionHelper.can_ship_board(agent_3d)
	if can_board and not is_gunner and ShipCombatModeHelper.can_be_boarded(target, agent_3d):
		return SUCCESS

	var snapshot := ShipAIPerceptionHelper.build_engagement_snapshot(agent_3d, target, default_preferred_range, default_range_tolerance, default_retreat_range)
	var target_pos: Vector3 = snapshot.get(ShipAIPerceptionHelper.KEY_LED_TARGET_POSITION, target.global_position)
	var to_target := target_pos - agent_3d.global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.001:
		to_target = -agent_3d.global_transform.basis.z
	var dir_to_target := to_target.normalized()
	var target_distance := float(snapshot.get(ShipAIPerceptionHelper.KEY_TARGET_DISTANCE, 0.0))
	var preferred_range := float(snapshot.get(ShipAIPerceptionHelper.KEY_PREFERRED_RANGE, default_preferred_range))
	var range_tolerance := float(snapshot.get(ShipAIPerceptionHelper.KEY_RANGE_TOLERANCE, default_range_tolerance))
	var retreat_range := float(snapshot.get(ShipAIPerceptionHelper.KEY_RETREAT_RANGE, default_retreat_range))
	var pressure := clampf(float(blackboard.get_var(pressure_var, 0.0)), 0.0, 1.0)
	var range_intent := str(blackboard.get_var(intent_var, ShipAILimboKeys.INTENT_ENGAGE))

	var desired_point := agent_3d.global_position
	var heading_point := target.global_position
	var speed_mult := 0.18
	var permit_sprint := false
	var mode := "limbo_bombard"
	var has_hint := true

	match stance:
		ShipAILimboKeys.STANCE_WITHDRAW:
			var retreat_step: float = maxf(retreat_range - target_distance + 4.5, 4.5)
			desired_point = agent_3d.global_position - dir_to_target * retreat_step
			heading_point = target.global_position if is_gunner else desired_point
			speed_mult = 0.88
			mode = "limbo_withdraw"
		ShipAILimboKeys.STANCE_CLOSE_DISTANCE:
			desired_point = target_pos - dir_to_target * preferred_range
			heading_point = target.global_position
			speed_mult = lerpf(0.98, 1.10, pressure)
			permit_sprint = target_distance > preferred_range + range_tolerance + 2.0
			mode = "limbo_close_distance"
		ShipAILimboKeys.STANCE_ORBIT_PRESSURE:
			var orbit_dir := _get_orbit_dir(agent_3d, dir_to_target)
			if orbit_dir.length_squared() <= 0.001:
				has_hint = false
			else:
				var orbit_radius: float = lerpf(3.2, 6.0, pressure)
				if target_distance > preferred_range + range_tolerance:
					desired_point = target_pos - dir_to_target * preferred_range + orbit_dir * orbit_radius
				elif target_distance < retreat_range:
					desired_point = agent_3d.global_position - dir_to_target * 3.0 + orbit_dir * (orbit_radius * 0.65)
				else:
					desired_point = agent_3d.global_position + orbit_dir * orbit_radius
				heading_point = target.global_position
				speed_mult = lerpf(0.34, 0.58, pressure)
				mode = "limbo_orbit_pressure"
		ShipAILimboKeys.STANCE_DESPERATE_PUSH:
			var push_range: float = maxf(retreat_range + 1.2, preferred_range * 0.72)
			desired_point = target_pos - dir_to_target * push_range
			heading_point = target.global_position
			speed_mult = 1.06
			permit_sprint = target_distance > 10.0 and target_distance < 28.0
			mode = "limbo_desperate_push"
		ShipAILimboKeys.STANCE_BOMBARD:
			if target_distance > preferred_range + range_tolerance:
				desired_point = target_pos - dir_to_target * preferred_range
				speed_mult = 0.95
				mode = "limbo_bombard_close"
			elif target_distance < retreat_range:
				desired_point = agent_3d.global_position - dir_to_target * maxf(retreat_range - target_distance + 4.0, 4.0)
				heading_point = desired_point
				speed_mult = 0.9
				mode = "limbo_bombard_retreat"
		_:
			has_hint = range_intent == ShipAILimboKeys.INTENT_CLOSE_DISTANCE
			if has_hint:
				desired_point = target_pos - dir_to_target * preferred_range
				speed_mult = 1.0
				mode = "limbo_close_distance"

	if not has_hint:
		return SUCCESS

	blackboard.set_var(desired_point_var, desired_point)
	blackboard.set_var(heading_point_var, heading_point)
	blackboard.set_var(speed_mult_var, speed_mult)
	blackboard.set_var(permit_sprint_var, permit_sprint)
	blackboard.set_var(mode_var, mode)
	agent_3d.set_meta(ShipAILimboKeys.META_NAV_TARGET_ID, target.get_instance_id())
	agent_3d.set_meta(ShipAILimboKeys.META_NAV_FRAME, Engine.get_physics_frames())
	agent_3d.set_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT, desired_point)
	agent_3d.set_meta(ShipAILimboKeys.META_NAV_HEADING_POINT, heading_point)
	agent_3d.set_meta(ShipAILimboKeys.META_NAV_SPEED_MULT, speed_mult)
	agent_3d.set_meta(ShipAILimboKeys.META_NAV_PERMIT_SPRINT, permit_sprint)
	agent_3d.set_meta(ShipAILimboKeys.META_NAV_MODE, mode)
	return SUCCESS


func _clear_navigation_hint(agent_3d: Node3D) -> void:
	for key in [
		ShipAILimboKeys.META_NAV_TARGET_ID,
		ShipAILimboKeys.META_NAV_FRAME,
		ShipAILimboKeys.META_NAV_DESIRED_POINT,
		ShipAILimboKeys.META_NAV_HEADING_POINT,
		ShipAILimboKeys.META_NAV_SPEED_MULT,
		ShipAILimboKeys.META_NAV_PERMIT_SPRINT,
		ShipAILimboKeys.META_NAV_MODE,
	]:
		if agent_3d.has_meta(key):
			agent_3d.remove_meta(key)


func _get_orbit_dir(agent_3d: Node3D, dir_to_target: Vector3) -> Vector3:
	var orbit_side_sign := -1.0 if int(agent_3d.get_instance_id()) % 2 == 0 else 1.0
	var orbit_dir := Vector3(-dir_to_target.z, 0.0, dir_to_target.x) * orbit_side_sign
	return orbit_dir.normalized() if orbit_dir.length_squared() > 0.001 else Vector3.ZERO
