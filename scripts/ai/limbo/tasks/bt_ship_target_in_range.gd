@tool
extends BTCondition
class_name BTShipTargetInRange


@export var target_var: StringName = ShipAILimboKeys.VAR_TARGET
@export var min_range: float = 0.0
@export var max_range: float = 80.0

var _min_range_sq := 0.0
var _max_range_sq := 0.0


func _generate_name() -> String:
	return "ShipTargetInRange %.1f..%.1f %s" % [
		min_range,
		max_range,
		LimboUtility.decorate_var(target_var),
	]


func _setup() -> void:
	_min_range_sq = maxf(0.0, min_range) * maxf(0.0, min_range)
	_max_range_sq = maxf(0.0, max_range) * maxf(0.0, max_range)


func _tick(_delta: float) -> Status:
	var agent_3d := agent as Node3D
	if not is_instance_valid(agent_3d):
		return FAILURE
	var target := blackboard.get_var(target_var, null) as Node3D
	if not is_instance_valid(target):
		return FAILURE
	var distance_sq := agent_3d.global_position.distance_squared_to(target.global_position)
	return SUCCESS if distance_sq >= _min_range_sq and distance_sq <= _max_range_sq else FAILURE
