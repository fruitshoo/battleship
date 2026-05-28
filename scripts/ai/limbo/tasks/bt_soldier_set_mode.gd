@tool
extends BTAction


const SoldierAILimboKeysScript = preload("res://scripts/ai/limbo/soldier_ai_limbo_keys.gd")


@export var target_var: StringName = SoldierAILimboKeysScript.VAR_TARGET
@export var target_distance_var: StringName = SoldierAILimboKeysScript.VAR_TARGET_DISTANCE
@export var mode_var: StringName = SoldierAILimboKeysScript.VAR_MODE
@export var point_var: StringName = SoldierAILimboKeysScript.VAR_POINT
@export var reason_var: StringName = SoldierAILimboKeysScript.VAR_REASON


func _generate_name() -> String:
	return "SoldierSetMode -> %s" % LimboUtility.decorate_var(mode_var)


func _tick(_delta: float) -> Status:
	var soldier := agent as Node3D
	if not is_instance_valid(soldier):
		return FAILURE

	var target := blackboard.get_var(target_var, null) as Node3D
	var target_distance: float = float(blackboard.get_var(target_distance_var, INF))
	var mode: String = SoldierAILimboKeysScript.MODE_WANDER
	var point: Vector3 = Vector3.INF
	var reason := "wander"

	var attack_range: float = _get_attack_range(soldier)

	if mode == SoldierAILimboKeysScript.MODE_WANDER and is_instance_valid(target):
		if target_distance <= attack_range:
			mode = SoldierAILimboKeysScript.MODE_ATTACK_TARGET
			reason = "target_in_range"
		else:
			mode = SoldierAILimboKeysScript.MODE_MOVE_TO_TARGET
			reason = "target_visible"

	blackboard.set_var(mode_var, mode)
	blackboard.set_var(point_var, point)
	blackboard.set_var(reason_var, reason)
	soldier.set_meta(SoldierAILimboKeysScript.META_MODE, mode)
	soldier.set_meta(SoldierAILimboKeysScript.META_REASON, reason)
	soldier.set_meta(SoldierAILimboKeysScript.META_FRAME, Engine.get_physics_frames())
	if point != Vector3.INF:
		soldier.set_meta(SoldierAILimboKeysScript.META_POINT, point)
	elif soldier.has_meta(SoldierAILimboKeysScript.META_POINT):
		soldier.remove_meta(SoldierAILimboKeysScript.META_POINT)
	if not is_instance_valid(target):
		soldier.set_meta(SoldierAILimboKeysScript.META_TARGET_ID, 0)
	return SUCCESS


func _get_attack_range(soldier: Node) -> float:
	var current_weapon_value: Variant = soldier.get("current_weapon")
	if is_instance_valid(current_weapon_value) and current_weapon_value.get("attack_range") != null:
		return float(current_weapon_value.get("attack_range"))
	return 1.2
