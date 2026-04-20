@tool
extends BTAction
class_name LimboAISmokeTickTask

@export var tick_meta_name: StringName = &"limbo_smoke_ticks"


func _generate_name() -> String:
	return "SmokeTick"


func _tick(_delta: float) -> Status:
	if not is_instance_valid(agent):
		return FAILURE
	var ticks := int(agent.get_meta(tick_meta_name, 0))
	agent.set_meta(tick_meta_name, ticks + 1)
	return SUCCESS
