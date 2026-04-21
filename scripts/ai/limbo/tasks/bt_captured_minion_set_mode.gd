@tool
extends BTAction
class_name BTCapturedMinionSetMode


@export var flagship_var: StringName = ShipAILimboKeys.VAR_TARGET
@export var ally_mode_var: StringName = ShipAILimboKeys.VAR_ALLY_MODE
@export var ally_target_var: StringName = ShipAILimboKeys.VAR_ALLY_TARGET
@export var ally_reason_var: StringName = ShipAILimboKeys.VAR_ALLY_REASON
@export var threat_range: float = 28.0
@export var threat_leash_distance: float = 56.0
@export var regroup_distance: float = 34.0


func _generate_name() -> String:
	return "CapturedMinionSetMode -> %s" % LimboUtility.decorate_var(ally_mode_var)


func _tick(_delta: float) -> Status:
	var captured_minion := agent as Node3D
	if not is_instance_valid(captured_minion):
		return FAILURE

	var flagship := blackboard.get_var(flagship_var, null) as Node3D
	if not is_instance_valid(flagship):
		_clear_ally_mode(captured_minion)
		return FAILURE

	var mode := ShipAILimboKeys.ALLY_MODE_FOLLOW_FLAGSHIP
	var ally_target: Node3D = flagship
	var reason := "formation"
	var dist_to_flagship := captured_minion.global_position.distance_to(flagship.global_position)

	if dist_to_flagship > regroup_distance:
		mode = ShipAILimboKeys.ALLY_MODE_REGROUP
		reason = "outside_recall"
	else:
		var guard_target := _find_guard_target(captured_minion, flagship)
		if is_instance_valid(guard_target):
			mode = ShipAILimboKeys.ALLY_MODE_GUARD_THREAT
			ally_target = guard_target
			reason = "nearby_threat"
			if _get_boarding_target(guard_target) == flagship:
				reason = "flagship_boarder"

	blackboard.set_var(ally_mode_var, mode)
	blackboard.set_var(ally_target_var, ally_target)
	blackboard.set_var(ally_reason_var, reason)
	captured_minion.set_meta(ShipAILimboKeys.META_ALLY_MODE, mode)
	captured_minion.set_meta(ShipAILimboKeys.META_ALLY_TARGET_ID, ally_target.get_instance_id())
	captured_minion.set_meta(ShipAILimboKeys.META_ALLY_FRAME, Engine.get_physics_frames())
	captured_minion.set_meta(ShipAILimboKeys.META_ALLY_REASON, reason)
	return SUCCESS


func _clear_ally_mode(captured_minion: Node3D) -> void:
	for key in [
		ShipAILimboKeys.META_ALLY_MODE,
		ShipAILimboKeys.META_ALLY_TARGET_ID,
		ShipAILimboKeys.META_ALLY_FRAME,
		ShipAILimboKeys.META_ALLY_REASON,
	]:
		if captured_minion.has_meta(key):
			captured_minion.remove_meta(key)


func _find_guard_target(captured_minion: Node3D, flagship: Node3D) -> Node3D:
	var best_target: Node3D = null
	var best_score := INF
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		var enemy_3d := enemy as Node3D
		if not is_instance_valid(enemy_3d) or enemy_3d == captured_minion:
			continue
		if _is_ship_disabled(enemy_3d):
			continue
		var flagship_distance := flagship.global_position.distance_to(enemy_3d.global_position)
		var minion_distance := captured_minion.global_position.distance_to(enemy_3d.global_position)
		var is_boarding_flagship := _get_boarding_target(enemy_3d) == flagship
		if flagship_distance > threat_range and not is_boarding_flagship:
			continue
		if minion_distance > threat_leash_distance and not is_boarding_flagship:
			continue
		var score := flagship_distance + minion_distance * 0.35
		if is_boarding_flagship:
			score -= 28.0
		elif flagship_distance <= threat_range * 0.5:
			score -= 4.0
		if score < best_score:
			best_score = score
			best_target = enemy_3d
	return best_target


func _get_boarding_target(ship: Node3D) -> Node3D:
	if ship.has_method("get_boarding_target_ship"):
		return ship.call("get_boarding_target_ship") as Node3D
	var target_value: Variant = ship.get("boarding_target")
	return target_value as Node3D


func _is_ship_disabled(ship: Node3D) -> bool:
	if ship.has_method("is_combat_disabled") and ship.call("is_combat_disabled") == true:
		return true
	if ship.has_method("is_sinking_or_dying") and ship.call("is_sinking_or_dying") == true:
		return true
	return ship.get("is_sinking") == true \
		or ship.get("is_dying") == true \
		or ship.get("is_dead") == true \
		or ship.get("is_derelict") == true
