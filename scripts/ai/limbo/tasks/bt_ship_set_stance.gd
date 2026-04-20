@tool
extends BTAction
class_name BTShipSetStance

const ShipAILimboKeys = preload("res://scripts/ai/limbo/ship_ai_limbo_keys.gd")

@export var range_intent_var: StringName = ShipAILimboKeys.VAR_INTENT
@export var pressure_phase_var: StringName = ShipAILimboKeys.VAR_PRESSURE_PHASE
@export var stance_var: StringName = ShipAILimboKeys.VAR_STANCE


func _generate_name() -> String:
	return "ShipSetStance -> %s" % LimboUtility.decorate_var(stance_var)


func _tick(_delta: float) -> Status:
	if not is_instance_valid(agent):
		return FAILURE

	var range_intent := str(blackboard.get_var(range_intent_var, ShipAILimboKeys.INTENT_ENGAGE))
	var pressure_phase := str(blackboard.get_var(pressure_phase_var, ShipAILimboKeys.PHASE_STABLE))
	var stance := _get_stance(range_intent, pressure_phase)
	blackboard.set_var(stance_var, stance)
	agent.set_meta(ShipAILimboKeys.META_STANCE, stance)
	return SUCCESS


func _get_stance(range_intent: String, pressure_phase: String) -> String:
	if range_intent == ShipAILimboKeys.INTENT_HOLD:
		return ShipAILimboKeys.STANCE_WITHDRAW
	if pressure_phase == ShipAILimboKeys.PHASE_DESPERATE:
		return ShipAILimboKeys.STANCE_DESPERATE_PUSH
	if range_intent == ShipAILimboKeys.INTENT_CLOSE_DISTANCE:
		return ShipAILimboKeys.STANCE_CLOSE_DISTANCE
	if pressure_phase == ShipAILimboKeys.PHASE_DAMAGED:
		return ShipAILimboKeys.STANCE_ORBIT_PRESSURE
	return ShipAILimboKeys.STANCE_BOMBARD
