@tool
extends BTAction
class_name BTShipSetWeaponIntent


@export var target_var: StringName = ShipAILimboKeys.VAR_TARGET
@export var range_intent_var: StringName = ShipAILimboKeys.VAR_INTENT
@export var stance_var: StringName = ShipAILimboKeys.VAR_STANCE
@export var pressure_var: StringName = ShipAILimboKeys.VAR_PRESSURE
@export var weapon_intent_var: StringName = ShipAILimboKeys.VAR_WEAPON_INTENT
@export var special_attack_intent_var: StringName = ShipAILimboKeys.VAR_SPECIAL_ATTACK_INTENT
@export var fire_pot_min_range: float = 7.0
@export var fire_pot_max_range: float = 18.0


func _generate_name() -> String:
	return "ShipSetWeaponIntent -> %s" % LimboUtility.decorate_var(weapon_intent_var)


func _tick(_delta: float) -> Status:
	var agent_3d := agent as Node3D
	if not is_instance_valid(agent_3d):
		return FAILURE

	_clear_weapon_intent(agent_3d)
	_clear_blackboard_intents()
	var target := blackboard.get_var(target_var, null) as Node3D
	if not is_instance_valid(target):
		return FAILURE

	var stance := str(blackboard.get_var(stance_var, "")).strip_edges()
	var range_intent := str(blackboard.get_var(range_intent_var, ShipAILimboKeys.INTENT_ENGAGE)).strip_edges()
	var pressure := clampf(float(blackboard.get_var(pressure_var, 0.0)), 0.0, 1.0)
	var target_distance := agent_3d.global_position.distance_to(target.global_position)
	_publish_special_attack_intent(agent_3d, target, target_distance)
	if not _should_publish_weapon_intent(agent_3d):
		return SUCCESS

	var weapon_intent := _get_weapon_intent(stance, range_intent, pressure)
	blackboard.set_var(weapon_intent_var, weapon_intent)
	agent_3d.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, weapon_intent)
	agent_3d.set_meta(ShipAILimboKeys.META_WEAPON_TARGET_ID, target.get_instance_id())
	agent_3d.set_meta(ShipAILimboKeys.META_WEAPON_FRAME, Engine.get_physics_frames())
	agent_3d.set_meta(ShipAILimboKeys.META_WEAPON_PRESSURE, pressure)
	return SUCCESS


func _get_weapon_intent(stance: String, range_intent: String, pressure: float) -> String:
	if stance == ShipAILimboKeys.STANCE_WITHDRAW or range_intent == ShipAILimboKeys.INTENT_HOLD:
		return ShipAILimboKeys.WEAPON_HOLD_FIRE
	if stance == ShipAILimboKeys.STANCE_DESPERATE_PUSH or pressure >= 0.95:
		return ShipAILimboKeys.WEAPON_DESPERATE_VOLLEY
	if stance == ShipAILimboKeys.STANCE_ORBIT_PRESSURE or stance == ShipAILimboKeys.STANCE_CLOSE_DISTANCE:
		return ShipAILimboKeys.WEAPON_RANGED_PRESSURE
	return ShipAILimboKeys.WEAPON_BROADSIDE_READY


func _clear_weapon_intent(agent_3d: Node3D) -> void:
	for key in [
		ShipAILimboKeys.META_WEAPON_INTENT,
		ShipAILimboKeys.META_WEAPON_TARGET_ID,
		ShipAILimboKeys.META_WEAPON_FRAME,
		ShipAILimboKeys.META_WEAPON_PRESSURE,
		ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT,
		ShipAILimboKeys.META_SPECIAL_ATTACK_TARGET_ID,
		ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME,
		ShipAILimboKeys.META_SPECIAL_ATTACK_DISTANCE,
	]:
		if agent_3d.has_meta(key):
			agent_3d.remove_meta(key)


func _clear_blackboard_intents() -> void:
	blackboard.set_var(weapon_intent_var, "")
	blackboard.set_var(special_attack_intent_var, "")


func _publish_special_attack_intent(agent_3d: Node3D, target: Node3D, target_distance: float) -> void:
	if not _can_use_fire_pot_attack(agent_3d):
		return
	var special_intent := _get_fire_pot_intent(target_distance)
	blackboard.set_var(special_attack_intent_var, special_intent)
	agent_3d.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT, special_intent)
	agent_3d.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_TARGET_ID, target.get_instance_id())
	agent_3d.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, Engine.get_physics_frames())
	agent_3d.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_DISTANCE, target_distance)


func _get_fire_pot_intent(target_distance: float) -> String:
	if target_distance > fire_pot_max_range:
		return ShipAILimboKeys.SPECIAL_CLOSE_DISTANCE
	if target_distance < fire_pot_min_range:
		return ShipAILimboKeys.SPECIAL_HOLD
	return ShipAILimboKeys.SPECIAL_FIRE_POT_READY


func _should_publish_weapon_intent(agent_3d: Node3D) -> bool:
	if not _is_enemy_team(agent_3d):
		return false
	if _can_board(agent_3d) and not _is_gunner(agent_3d):
		return false
	return true


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


func _can_use_fire_pot_attack(agent_3d: Node3D) -> bool:
	if agent_3d.has_method("can_use_fire_pot_attack"):
		return agent_3d.call("can_use_fire_pot_attack") == true
	return false
