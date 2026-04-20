@tool
extends BTAction
class_name BTShipSetBoardingIntent


@export var target_var: StringName = ShipAILimboKeys.VAR_TARGET
@export var boarding_intent_var: StringName = ShipAILimboKeys.VAR_BOARDING_INTENT
@export var default_boarding_break_distance: float = 12.0


func _generate_name() -> String:
	return "ShipSetBoardingIntent -> %s" % LimboUtility.decorate_var(boarding_intent_var)


func _tick(_delta: float) -> Status:
	var agent_3d := agent as Node3D
	if not is_instance_valid(agent_3d):
		return FAILURE

	_clear_boarding_intent(agent_3d)
	blackboard.set_var(boarding_intent_var, "")
	var target := blackboard.get_var(target_var, null) as Node3D
	if not is_instance_valid(target):
		return FAILURE
	if not _should_publish_boarding_intent(agent_3d):
		return SUCCESS

	var target_distance := agent_3d.global_position.distance_to(target.global_position)
	var attempt_distance := _get_boarding_attempt_distance(agent_3d, target)
	var boarding_intent := ShipAILimboKeys.BOARDING_READY if target_distance <= attempt_distance else ShipAILimboKeys.BOARDING_APPROACH

	blackboard.set_var(boarding_intent_var, boarding_intent)
	agent_3d.set_meta(ShipAILimboKeys.META_BOARDING_INTENT, boarding_intent)
	agent_3d.set_meta(ShipAILimboKeys.META_BOARDING_TARGET_ID, target.get_instance_id())
	agent_3d.set_meta(ShipAILimboKeys.META_BOARDING_FRAME, Engine.get_physics_frames())
	agent_3d.set_meta(ShipAILimboKeys.META_BOARDING_DISTANCE, target_distance)
	agent_3d.set_meta(ShipAILimboKeys.META_BOARDING_ATTEMPT_DISTANCE, attempt_distance)
	return SUCCESS


func _clear_boarding_intent(agent_3d: Node3D) -> void:
	for key in [
		ShipAILimboKeys.META_BOARDING_INTENT,
		ShipAILimboKeys.META_BOARDING_TARGET_ID,
		ShipAILimboKeys.META_BOARDING_FRAME,
		ShipAILimboKeys.META_BOARDING_DISTANCE,
		ShipAILimboKeys.META_BOARDING_ATTEMPT_DISTANCE,
	]:
		if agent_3d.has_meta(key):
			agent_3d.remove_meta(key)


func _should_publish_boarding_intent(agent_3d: Node3D) -> bool:
	if not _is_enemy_team(agent_3d):
		return false
	if not _can_board(agent_3d):
		return false
	return not _is_gunner(agent_3d)


func _get_boarding_attempt_distance(agent_3d: Node3D, target: Node3D) -> float:
	return ShipContactGeometry.get_boarding_attempt_distance(agent_3d, target, default_boarding_break_distance)


func _is_enemy_team(agent_3d: Node3D) -> bool:
	if agent_3d.has_method("get_team_tag"):
		return str(agent_3d.call("get_team_tag")) == "enemy"
	if "team" in agent_3d:
		return str(agent_3d.get("team")) == "enemy"
	return true


func _is_gunner(agent_3d: Node3D) -> bool:
	if agent_3d.has_method("is_gunner_role"):
		return agent_3d.call("is_gunner_role") == true
	if "combat_role" in agent_3d:
		return int(agent_3d.get("combat_role")) == 1
	return false


func _can_board(agent_3d: Node3D) -> bool:
	if agent_3d.has_method("can_board_targets"):
		return agent_3d.call("can_board_targets") == true
	if "allow_boarding" in agent_3d:
		return agent_3d.get("allow_boarding") == true
	return false
