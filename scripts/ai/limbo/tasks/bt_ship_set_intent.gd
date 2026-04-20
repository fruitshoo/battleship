@tool
extends BTAction
class_name BTShipSetIntent

const ShipAILimboKeys = preload("res://scripts/ai/limbo/ship_ai_limbo_keys.gd")

@export var intent: StringName = &"engage"
@export var intent_var: StringName = ShipAILimboKeys.VAR_INTENT
@export var target_var: StringName = ShipAILimboKeys.VAR_TARGET


func _generate_name() -> String:
	return "ShipSetIntent %s" % String(intent)


func _tick(_delta: float) -> Status:
	if not is_instance_valid(agent):
		return FAILURE
	var intent_name := String(intent)
	blackboard.set_var(intent_var, intent_name)
	agent.set_meta(ShipAILimboKeys.META_INTENT, intent_name)

	var target := blackboard.get_var(target_var, null) as Node
	if is_instance_valid(target):
		agent.set_meta(ShipAILimboKeys.META_TARGET_ID, target.get_instance_id())
	return SUCCESS
