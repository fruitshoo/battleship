@tool
extends BTAction


const SoldierShipHelper = preload("res://scripts/entities/soldiers/soldier_ship_helper.gd")
const SoldierShipDutyHelper = preload("res://scripts/entities/soldiers/soldier_ship_duty_helper.gd")
const SoldierAILimboKeysScript = preload("res://scripts/ai/limbo/soldier_ai_limbo_keys.gd")


@export var target_var: StringName = SoldierAILimboKeysScript.VAR_TARGET
@export var target_distance_var: StringName = SoldierAILimboKeysScript.VAR_TARGET_DISTANCE
@export var mode_var: StringName = SoldierAILimboKeysScript.VAR_MODE
@export var point_var: StringName = SoldierAILimboKeysScript.VAR_POINT
@export var reason_var: StringName = SoldierAILimboKeysScript.VAR_REASON
@export_range(0.0, 1.0, 0.01) var ship_duty_priority_threshold: float = 0.45
@export var allow_cross_ship_muster: bool = true
@export var allow_ship_duty: bool = true
@export var prefer_active_boarding_muster: bool = false


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
	var active_boarding_muster_target: Vector3 = _find_active_boarding_muster_target(soldier) if prefer_active_boarding_muster else Vector3.INF

	var prioritize_ship_duty := active_boarding_muster_target == Vector3.INF and allow_ship_duty and _should_prioritize_ship_duty_before_enemy(soldier)
	if prioritize_ship_duty:
		var duty_target: Vector3 = SoldierShipDutyHelper.find_ship_duty_target(soldier)
		if duty_target != Vector3.INF:
			mode = SoldierAILimboKeysScript.MODE_SHIP_DUTY
			point = duty_target
			reason = "priority_ship_duty"
			target = null

	if mode == SoldierAILimboKeysScript.MODE_WANDER and is_instance_valid(target):
		var attack_range: float = _get_attack_range(soldier)
		if target_distance <= attack_range:
			mode = SoldierAILimboKeysScript.MODE_ATTACK_TARGET
			reason = "target_in_range"
		else:
			mode = SoldierAILimboKeysScript.MODE_MOVE_TO_TARGET
			reason = "target_visible"
	elif mode == SoldierAILimboKeysScript.MODE_WANDER:
		var muster_target: Vector3 = active_boarding_muster_target
		if muster_target == Vector3.INF and allow_cross_ship_muster:
			muster_target = SoldierShipHelper.find_cross_ship_muster_target(soldier)
		if muster_target != Vector3.INF:
			mode = SoldierAILimboKeysScript.MODE_MUSTER_CROSS_SHIP
			point = muster_target
			reason = "boarding_muster" if active_boarding_muster_target != Vector3.INF else "cross_ship_contact"
		else:
			if allow_ship_duty:
				var duty_target: Vector3 = SoldierShipDutyHelper.find_ship_duty_target(soldier)
				if duty_target != Vector3.INF:
					mode = SoldierAILimboKeysScript.MODE_SHIP_DUTY
					point = duty_target
					reason = "ship_duty"

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


func _should_prioritize_ship_duty_before_enemy(soldier: Node) -> bool:
	var state_value: Variant = soldier.get("current_state")
	var state_int: int = int(state_value) if state_value != null else -1
	var idle_value: int = int(soldier.State.IDLE)
	var wander_value: int = int(soldier.State.WANDER)
	if state_int != idle_value and state_int != wander_value:
		return false
	var owned_ship_value: Variant = soldier.get("owned_ship")
	if not is_instance_valid(owned_ship_value):
		return false
	var owned_ship := owned_ship_value as Node
	var gunnery_ratio: float = float(owned_ship.get("gunnery_crew_ratio")) if owned_ship.get("gunnery_crew_ratio") != null else 0.0
	return gunnery_ratio >= ship_duty_priority_threshold


func _get_attack_range(soldier: Node) -> float:
	var current_weapon_value: Variant = soldier.get("current_weapon")
	if is_instance_valid(current_weapon_value) and current_weapon_value.get("attack_range") != null:
		return float(current_weapon_value.get("attack_range"))
	return 1.2


func _find_active_boarding_muster_target(soldier: Node3D) -> Vector3:
	var target_ship := _get_active_boarding_target_ship(soldier)
	if not is_instance_valid(target_ship):
		return Vector3.INF
	return SoldierShipHelper.get_cross_ship_contact_point_global(soldier, target_ship)


func _get_active_boarding_target_ship(soldier: Node3D) -> Node3D:
	var owned_ship_value: Variant = soldier.get("owned_ship")
	var owned_ship := owned_ship_value as Node3D
	if not is_instance_valid(owned_ship):
		return null

	var boarding_status: String = str(soldier.get("boarding_status")).strip_edges().to_lower()
	if boarding_status == "returning":
		var home_ship_value: Variant = soldier.get("home_ship")
		var home_ship := home_ship_value as Node3D
		if is_instance_valid(home_ship) and home_ship != owned_ship and _has_active_boarding_link_between(owned_ship, home_ship):
			return home_ship
		return null

	var boarding_target := _get_boarding_target_ship(owned_ship)
	if is_instance_valid(boarding_target):
		var is_boarding_flag: bool = owned_ship.get("is_boarding") == true if owned_ship.get("is_boarding") != null else false
		if is_boarding_flag or _has_active_boarding_link_between(owned_ship, boarding_target):
			return boarding_target
	return null


func _get_boarding_target_ship(ship: Node3D) -> Node3D:
	if not is_instance_valid(ship):
		return null
	if ship.has_method("get_boarding_target_ship"):
		return ship.call("get_boarding_target_ship") as Node3D
	var target_value: Variant = ship.get("boarding_target")
	return target_value as Node3D if is_instance_valid(target_value) else null


func _has_active_boarding_link_between(ship_a: Node3D, ship_b: Node3D) -> bool:
	return _ship_has_active_boarding_link_to(ship_a, ship_b) or _ship_has_active_boarding_link_to(ship_b, ship_a)


func _ship_has_active_boarding_link_to(from_ship: Node3D, to_ship: Node3D) -> bool:
	if not is_instance_valid(from_ship) or not is_instance_valid(to_ship):
		return false
	if from_ship.has_method("has_boarding_rope_link_to"):
		return from_ship.call("has_boarding_rope_link_to", to_ship) == true
	var target_ship := _get_boarding_target_ship(from_ship)
	if target_ship != to_ship:
		return false
	var rope_flag: Variant = from_ship.get("_initial_rope_deployed")
	return rope_flag == true
