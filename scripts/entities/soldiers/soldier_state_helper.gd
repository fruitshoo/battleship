extends RefCounted
class_name SoldierStateHelper

const FALLBACK_DEAD_STATE_VALUE := 4


static func is_alive_soldier(soldier: Node) -> bool:
	return is_instance_valid(soldier) and not is_dead_soldier(soldier)


static func is_dead_soldier(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return true
	if soldier.has_method("is_dead_soldier"):
		return soldier.call("is_dead_soldier") == true
	if soldier.has_method("is_dead"):
		return soldier.call("is_dead") == true
	var state_value: Variant = _get_state_value(soldier)
	return is_state_value_dead(soldier, state_value)


static func is_incapacitated_soldier(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("is_incapacitated_soldier"):
		return soldier.call("is_incapacitated_soldier") == true
	return is_dead_soldier(soldier) and soldier.get_meta("incapacitated", false) == true


static func can_act(soldier: Node) -> bool:
	return is_alive_soldier(soldier)


static func can_be_targeted(soldier: Node) -> bool:
	return is_alive_soldier(soldier)


static func is_state_value_dead(soldier: Node, state_value: Variant) -> bool:
	if state_value == null:
		return false
	if is_instance_valid(soldier) and soldier.has_method("is_state_value_dead"):
		return soldier.call("is_state_value_dead", state_value) == true
	return int(state_value) == FALLBACK_DEAD_STATE_VALUE


static func _get_state_value(soldier: Node) -> Variant:
	if not is_instance_valid(soldier):
		return null
	if soldier.has_method("get_current_state_value"):
		return soldier.call("get_current_state_value")
	if "current_state" in soldier:
		return soldier.get("current_state")
	return null
