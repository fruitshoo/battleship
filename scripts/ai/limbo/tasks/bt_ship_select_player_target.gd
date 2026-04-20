@tool
extends BTAction
class_name BTShipSelectPlayerTarget


@export var target_var: StringName = ShipAILimboKeys.VAR_TARGET


func _generate_name() -> String:
	return "ShipSelectPlayerTarget -> %s" % LimboUtility.decorate_var(target_var)


func _tick(_delta: float) -> Status:
	if not is_instance_valid(agent):
		return FAILURE
	var target := ShipTargetingHelper.select_player_target_for(agent)
	if not is_instance_valid(target):
		return FAILURE
	blackboard.set_var(target_var, target)
	agent.set_meta(ShipAILimboKeys.META_TARGET_ID, target.get_instance_id())
	return SUCCESS
