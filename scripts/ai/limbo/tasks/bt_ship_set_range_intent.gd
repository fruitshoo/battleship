@tool
extends BTAction
class_name BTShipSetRangeIntent

const ShipAIPerceptionHelper = preload("res://scripts/ai/limbo/ship_ai_perception_helper.gd")

@export var target_var: StringName = ShipAILimboKeys.VAR_TARGET
@export var intent_var: StringName = ShipAILimboKeys.VAR_INTENT
@export var target_distance_var: StringName = ShipAILimboKeys.VAR_TARGET_DISTANCE
@export var default_preferred_range: float = 35.0
@export var default_range_tolerance: float = 5.0


func _generate_name() -> String:
	return "ShipSetRangeIntent %s -> %s" % [
		LimboUtility.decorate_var(target_var),
		LimboUtility.decorate_var(intent_var),
	]


func _tick(_delta: float) -> Status:
	var agent_3d := agent as Node3D
	if not is_instance_valid(agent_3d):
		return FAILURE
	var target := blackboard.get_var(target_var, null) as Node3D
	if not is_instance_valid(target):
		return FAILURE

	var target_distance := ShipAIPerceptionHelper.get_target_distance(agent_3d, target)
	var preferred_range := ShipAIPerceptionHelper.get_orbit_preferred_range(agent_3d, default_preferred_range)
	var range_tolerance := ShipAIPerceptionHelper.get_range_tolerance(agent_3d, default_range_tolerance)
	var intent := _get_intent_for_distance(target_distance, preferred_range, range_tolerance)

	blackboard.set_var(target_distance_var, target_distance)
	blackboard.set_var(intent_var, intent)
	agent_3d.set_meta(ShipAILimboKeys.META_TARGET_DISTANCE, target_distance)
	agent_3d.set_meta(ShipAILimboKeys.META_INTENT, intent)
	agent_3d.set_meta(ShipAILimboKeys.META_TARGET_ID, target.get_instance_id())
	return SUCCESS


func _get_intent_for_distance(target_distance: float, preferred_range: float, range_tolerance: float) -> String:
	if target_distance > preferred_range + range_tolerance:
		return ShipAILimboKeys.INTENT_CLOSE_DISTANCE
	if target_distance < maxf(0.0, preferred_range - range_tolerance):
		return ShipAILimboKeys.INTENT_HOLD
	return ShipAILimboKeys.INTENT_ENGAGE
