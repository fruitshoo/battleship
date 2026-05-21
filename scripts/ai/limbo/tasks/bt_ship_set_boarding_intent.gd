@tool
extends BTAction
class_name BTShipSetBoardingIntent

const ShipAIPerceptionHelper = preload("res://scripts/ai/limbo/ship_ai_perception_helper.gd")

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
	if not ShipCombatModeHelper.can_be_boarded(target, agent_3d):
		return SUCCESS
	if not _should_publish_boarding_intent(agent_3d):
		return SUCCESS

	var target_distance := ShipAIPerceptionHelper.get_target_distance(agent_3d, target)
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
	if not ShipAIPerceptionHelper.is_enemy_ship(agent_3d):
		return false
	if not ShipAIPerceptionHelper.can_ship_board(agent_3d):
		return false
	return not ShipAIPerceptionHelper.is_ship_gunner(agent_3d)


func _get_boarding_attempt_distance(agent_3d: Node3D, target: Node3D) -> float:
	return ShipContactGeometry.get_boarding_attempt_distance(agent_3d, target, default_boarding_break_distance)
