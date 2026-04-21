@tool
extends BTAction
class_name BTSupportShipSetMode


@export var flagship_var: StringName = ShipAILimboKeys.VAR_TARGET
@export var support_mode_var: StringName = ShipAILimboKeys.VAR_SUPPORT_MODE
@export var support_target_var: StringName = ShipAILimboKeys.VAR_SUPPORT_TARGET
@export var support_reason_var: StringName = ShipAILimboKeys.VAR_SUPPORT_REASON
@export var threat_range: float = 34.0
@export var emergency_threat_range: float = 76.0
@export var boss_breach_range: float = 58.0
@export var regroup_distance: float = 132.0


func _generate_name() -> String:
	return "SupportShipSetMode -> %s" % LimboUtility.decorate_var(support_mode_var)


func _tick(_delta: float) -> Status:
	var support_ship := agent as Node3D
	if not is_instance_valid(support_ship):
		return FAILURE

	var flagship := blackboard.get_var(flagship_var, null) as Node3D
	if not is_instance_valid(flagship):
		_clear_support_mode(support_ship)
		return FAILURE

	var mode := ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP
	var support_target: Node3D = flagship
	var reason := "formation"
	var deck_emergency := _is_player_deck_emergency(flagship)
	var support_distance := support_ship.global_position.distance_to(flagship.global_position)

	if deck_emergency:
		mode = ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP
		reason = "flagship_deck_emergency"
	elif support_distance > regroup_distance:
		mode = ShipAILimboKeys.SUPPORT_MODE_REGROUP
		reason = "outside_recall"
	else:
		var boss_breach := _find_boss_breach_target(support_ship, flagship, boss_breach_range)
		var boss_target := boss_breach.get("target", null) as Node3D
		if is_instance_valid(boss_target):
			mode = ShipAILimboKeys.SUPPORT_MODE_BREACH_BOSS
			support_target = boss_target
			reason = str(boss_breach.get("reason", "boss_close_pressure")).strip_edges()
		elif _is_formation_hold_enabled(support_ship):
			reason = "formation_hold"
		else:
			var screen_target := _find_screen_threat(support_ship, flagship, threat_range)
			if is_instance_valid(screen_target):
				mode = ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT
				support_target = screen_target
				reason = "nearby_threat"

	if deck_emergency:
		var emergency_threat := _find_screen_threat(support_ship, flagship, emergency_threat_range)
		if is_instance_valid(emergency_threat):
			reason = "flagship_deck_emergency_with_threat"

	blackboard.set_var(support_mode_var, mode)
	blackboard.set_var(support_target_var, support_target)
	blackboard.set_var(support_reason_var, reason)
	support_ship.set_meta(ShipAILimboKeys.META_SUPPORT_MODE, mode)
	support_ship.set_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, support_target.get_instance_id())
	support_ship.set_meta(ShipAILimboKeys.META_SUPPORT_FRAME, Engine.get_physics_frames())
	support_ship.set_meta(ShipAILimboKeys.META_SUPPORT_REASON, reason)
	return SUCCESS


func _clear_support_mode(support_ship: Node3D) -> void:
	for key in [
		ShipAILimboKeys.META_SUPPORT_MODE,
		ShipAILimboKeys.META_SUPPORT_TARGET_ID,
		ShipAILimboKeys.META_SUPPORT_FRAME,
		ShipAILimboKeys.META_SUPPORT_REASON,
	]:
		if support_ship.has_meta(key):
			support_ship.remove_meta(key)


func _find_screen_threat(support_ship: Node3D, flagship: Node3D, max_range: float) -> Node3D:
	var best_target: Node3D = null
	var best_score := INF
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		var enemy_3d := enemy as Node3D
		if not is_instance_valid(enemy_3d) or enemy_3d == support_ship:
			continue
		if _is_ship_disabled(enemy_3d):
			continue
		var flagship_distance := flagship.global_position.distance_to(enemy_3d.global_position)
		var is_boarding_flagship := _get_boarding_target(enemy_3d) == flagship
		if flagship_distance > max_range and not is_boarding_flagship:
			continue
		var support_distance := support_ship.global_position.distance_to(enemy_3d.global_position)
		var score := flagship_distance + support_distance * 0.35
		if is_boarding_flagship:
			score -= 30.0
		if score < best_score:
			best_score = score
			best_target = enemy_3d
	return best_target


func _find_boss_breach_target(support_ship: Node3D, flagship: Node3D, max_range: float) -> Dictionary:
	var flagship_boarding_target := _get_boarding_target(flagship)
	var flagship_auto_raid_target := _get_auto_raid_target(flagship)
	var flagship_manual_boarding_target := _get_manual_boarding_target(flagship)
	var flagship_focus_target := _get_target_ship(flagship)
	var best_target: Node3D = null
	var best_reason := ""
	var best_score := INF
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		var enemy_3d := enemy as Node3D
		if not is_instance_valid(enemy_3d) or enemy_3d == support_ship:
			continue
		if _is_ship_disabled(enemy_3d) or not _is_boss_ship(enemy_3d):
			continue
		var flagship_distance := flagship.global_position.distance_to(enemy_3d.global_position)
		var support_distance := support_ship.global_position.distance_to(enemy_3d.global_position)
		var flagship_boarding_boss := flagship_boarding_target == enemy_3d or flagship_auto_raid_target == enemy_3d
		var flagship_manual_boss := flagship_manual_boarding_target == enemy_3d
		var flagship_focus_boss := flagship_focus_target == enemy_3d
		var boss_boarding_flagship := _get_boarding_target(enemy_3d) == flagship
		var boss_close_pressure := flagship_distance <= max_range
		if not flagship_boarding_boss and not flagship_manual_boss and not flagship_focus_boss and not boss_boarding_flagship and not boss_close_pressure:
			continue
		var reason := "boss_close_pressure"
		var score := flagship_distance + support_distance * 0.18
		if flagship_boarding_boss:
			reason = "flagship_boss_boarding"
			score -= 34.0
		elif flagship_manual_boss:
			reason = "flagship_manual_boarding"
			score -= 32.0
		elif boss_boarding_flagship:
			reason = "boss_boarding_flagship"
			score -= 26.0
		elif flagship_focus_boss:
			reason = "flagship_boss_focus"
			score -= 16.0
		else:
			score -= 8.0
		if score < best_score:
			best_score = score
			best_target = enemy_3d
			best_reason = reason
	if not is_instance_valid(best_target):
		return {}
	return {
		"target": best_target,
		"reason": best_reason,
	}


func _is_player_deck_emergency(flagship: Node3D) -> bool:
	var hostile_count := 0
	var hostile_value: Variant = flagship.get("deck_hostile_boarder_count")
	if hostile_value != null:
		hostile_count = int(hostile_value)
	return flagship.get("deck_is_overrun") == true \
		or flagship.get("deck_is_contested") == true \
		or hostile_count > 0


func _is_formation_hold_enabled(support_ship: Node3D) -> bool:
	var hold_value: Variant = support_ship.get("support_hold_formation")
	if hold_value != null:
		return hold_value == true
	return support_ship.get_meta("support_hold_formation", false) == true


func _get_boarding_target(ship: Node3D) -> Node3D:
	if ship.has_method("get_boarding_target_ship"):
		return ship.call("get_boarding_target_ship") as Node3D
	var target_value: Variant = ship.get("boarding_target")
	return target_value as Node3D


func _get_auto_raid_target(ship: Node3D) -> Node3D:
	var auto_raid_value: Variant = ship.get("auto_raid_target")
	return auto_raid_value as Node3D


func _get_manual_boarding_target(ship: Node3D) -> Node3D:
	var manual_value: Variant = ship.get("manual_boarding_target")
	return manual_value as Node3D


func _get_target_ship(ship: Node3D) -> Node3D:
	if ship.has_method("get_target_ship"):
		return ship.call("get_target_ship") as Node3D
	var target_value: Variant = ship.get("target")
	return target_value as Node3D


func _is_boss_ship(ship: Node3D) -> bool:
	if ship.is_in_group("boss"):
		return true
	var ship_type_value: Variant = ship.get("ship_type")
	return str(ship_type_value).to_lower().contains("atakebune")


func _is_ship_disabled(ship: Node3D) -> bool:
	if ship.has_method("is_combat_disabled") and ship.call("is_combat_disabled") == true:
		return true
	if ship.has_method("is_sinking_or_dying") and ship.call("is_sinking_or_dying") == true:
		return true
	return ship.get("is_sinking") == true \
		or ship.get("is_dying") == true \
		or ship.get("is_dead") == true \
		or ship.get("is_derelict") == true
