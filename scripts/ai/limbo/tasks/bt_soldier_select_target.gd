@tool
extends BTAction


const SoldierAILimboKeysScript = preload("res://scripts/ai/limbo/soldier_ai_limbo_keys.gd")


@export var target_var: StringName = SoldierAILimboKeysScript.VAR_TARGET
@export var target_distance_var: StringName = SoldierAILimboKeysScript.VAR_TARGET_DISTANCE


func _generate_name() -> String:
	return "SoldierSelectTarget -> %s" % LimboUtility.decorate_var(target_var)


func _tick(_delta: float) -> Status:
	var soldier := agent as Node3D
	if not is_instance_valid(soldier):
		return FAILURE

	var target: Node3D = null
	if soldier.has_method("find_nearest_enemy"):
		target = soldier.call("find_nearest_enemy") as Node3D
	var target_distance: float = INF
	if is_instance_valid(target):
		target_distance = _get_planar_distance(soldier.global_position, target.global_position)

	blackboard.set_var(target_var, target)
	blackboard.set_var(target_distance_var, target_distance)
	soldier.set_meta(SoldierAILimboKeysScript.META_TARGET_ID, target.get_instance_id() if is_instance_valid(target) else 0)
	soldier.set_meta(SoldierAILimboKeysScript.META_TARGET_DISTANCE, target_distance)
	return SUCCESS


func _get_planar_distance(from_point: Vector3, to_point: Vector3) -> float:
	return Vector2(from_point.x - to_point.x, from_point.z - to_point.z).length()
