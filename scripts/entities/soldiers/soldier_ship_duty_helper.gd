extends RefCounted
class_name SoldierShipDutyHelper


static func find_ship_duty_target(soldier) -> Vector3:
	var owned_ship: Node3D = soldier.get_owned_ship_node() if soldier.has_method("get_owned_ship_node") else null
	if not is_instance_valid(owned_ship):
		return Vector3.INF
	var owned_team: String = owned_ship.get_team_tag() if owned_ship.has_method("get_team_tag") else str(owned_ship.get("team"))
	if owned_team != soldier.team:
		return Vector3.INF
	if soldier.current_target != null:
		return Vector3.INF
	if soldier.is_captain:
		return Vector3.INF
	if owned_ship.deck_is_contested == true or owned_ship.deck_is_overrun == true:
		return Vector3.INF

	var half_ext: Vector2 = SoldierShipHelper.get_ship_deck_half_extents(soldier, owned_ship)
	var gunnery_ratio: float = float(owned_ship.gunnery_crew_ratio)
	var handling_ratio: float = float(owned_ship.shiphandling_crew_ratio)
	var current_speed: float = owned_ship.get_current_speed_value()
	var rowing_active: bool = "is_rowing" in owned_ship and owned_ship.get("is_rowing") == true
	var rudder_angle: float = float(owned_ship.rudder_angle)
	var bias_sign: float = -1.0 if int(soldier.get_instance_id()) % 2 == 0 else 1.0
	var local_target: Vector3 = Vector3.INF

	if (soldier.has_method("is_ranged_only_value") and soldier.is_ranged_only_value() or soldier.crew_role == "general" or soldier.crew_role == "fire_pot") and gunnery_ratio >= 0.45:
		var side_sign: float = _get_enemy_side_sign(soldier, bias_sign)
		var lane_index: int = int(soldier.get_instance_id()) % 5
		var lane_offset: float = clampf((float(lane_index) - 2.0) * 0.45, -half_ext.y * 0.42, half_ext.y * 0.42)
		local_target = Vector3(side_sign * half_ext.x * 0.76, 0.0, lane_offset)
	elif handling_ratio >= 0.45:
		var duty_lane: int = int(soldier.get_instance_id()) % 5
		var duty_offset: float = clampf((float(duty_lane) - 2.0) * 0.55, -half_ext.y * 0.58, half_ext.y * 0.58)
		if rowing_active:
			local_target = Vector3(bias_sign * half_ext.x * 0.72, 0.0, duty_offset)
		elif absf(rudder_angle) >= 7.5:
			local_target = Vector3(bias_sign * half_ext.x * 0.32, 0.0, half_ext.y * 0.82)
		elif current_speed > 1.2:
			local_target = Vector3(bias_sign * half_ext.x * 0.22, 0.0, half_ext.y * 0.35)

	if local_target == Vector3.INF:
		return Vector3.INF

	var ship_local_pos: Vector3 = owned_ship.to_local(soldier.global_position)
	var local_diff: Vector2 = Vector2(ship_local_pos.x - local_target.x, ship_local_pos.z - local_target.z)
	if local_diff.length_squared() <= 1.2:
		return Vector3.INF

	var target_global: Vector3 = owned_ship.to_global(local_target)
	target_global.y = soldier.global_position.y
	return target_global


static func _get_enemy_side_sign(soldier, fallback_sign: float) -> float:
	var owned_ship: Node3D = soldier.get_owned_ship_node() if soldier.has_method("get_owned_ship_node") else null
	if not is_instance_valid(owned_ship):
		return fallback_sign
	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	var opposing_ships: Array = soldier.get_ships_cached(soldier.get_tree(), opposing_team)
	var best_ship: Node3D = null
	var best_distance_sq: float = INF
	for other_ship in opposing_ships:
		if not is_instance_valid(other_ship):
			continue
		if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
			continue
		var planar_delta: Vector3 = other_ship.global_position - owned_ship.global_position
		planar_delta.y = 0.0
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best_ship = other_ship
	if not is_instance_valid(best_ship):
		return fallback_sign
	var enemy_local: Vector3 = owned_ship.to_local(best_ship.global_position)
	if absf(enemy_local.x) <= 0.2:
		return fallback_sign
	return 1.0 if enemy_local.x >= 0.0 else -1.0
