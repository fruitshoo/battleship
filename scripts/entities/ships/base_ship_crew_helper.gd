extends RefCounted
class_name BaseShipCrewHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")

static func update_crew_allocation_state(ship, delta: float) -> void:
	ship._crew_allocation_eval_left -= delta
	if ship._crew_allocation_eval_left > 0.0:
		return
	ship._crew_allocation_eval_left = ship.crew_allocation_eval_interval

	var available_crew: int = estimate_available_crew_count(ship)
	if available_crew <= 0:
		ship.combat_crew_alloc = 0
		ship.shiphandling_crew_alloc = 0
		ship.gunnery_crew_alloc = 0
		ship.combat_crew_ratio = 0.0
		ship.shiphandling_crew_ratio = 0.0
		ship.gunnery_crew_ratio = 0.0
		return

	var combat_ratio_target: float = 0.2
	var shiphandling_ratio_target: float = 0.5
	var gunnery_ratio_target: float = 0.3

	if ship.deck_is_contested or ship.deck_is_overrun or ship.is_boarding or ship.deck_hostile_boarder_count > 0:
		combat_ratio_target = 0.7
		shiphandling_ratio_target = 0.2
		gunnery_ratio_target = 0.1
	elif is_in_gunnery_posture(ship):
		combat_ratio_target = 0.2
		shiphandling_ratio_target = 0.3
		gunnery_ratio_target = 0.5

	ship.combat_crew_alloc = clampi(int(round(available_crew * combat_ratio_target)), 0, available_crew)
	ship.shiphandling_crew_alloc = clampi(int(round(available_crew * shiphandling_ratio_target)), 0, max(0, available_crew - ship.combat_crew_alloc))
	ship.gunnery_crew_alloc = max(0, available_crew - ship.combat_crew_alloc - ship.shiphandling_crew_alloc)

	ship.combat_crew_ratio = float(ship.combat_crew_alloc) / float(available_crew)
	ship.shiphandling_crew_ratio = float(ship.shiphandling_crew_alloc) / float(available_crew)
	ship.gunnery_crew_ratio = float(ship.gunnery_crew_alloc) / float(available_crew)


static func get_shiphandling_multiplier(ship) -> float:
	var t: float = clampf((ship.shiphandling_crew_ratio - 0.2) / 0.3, 0.0, 1.0)
	return lerpf(0.65, 1.0, t)


static func get_gunnery_reload_multiplier(ship) -> float:
	var t: float = clampf((ship.gunnery_crew_ratio - 0.1) / 0.4, 0.0, 1.0)
	return lerpf(1.35, 0.72, t)


static func get_combat_effectiveness_multiplier(ship) -> float:
	var t: float = clampf((ship.combat_crew_ratio - 0.2) / 0.5, 0.0, 1.0)
	return lerpf(0.8, 1.25, t)


static func get_effective_boarding_interval(ship) -> float:
	return maxf(0.45, ship.boarding_interval / get_combat_effectiveness_multiplier(ship))


static func get_effective_boarding_capture_duration(ship, attacker_ship: Node = null) -> float:
	var attacker_combat_mult: float = 1.0
	if is_instance_valid(attacker_ship) and attacker_ship.has_method("get_combat_effectiveness_multiplier"):
		attacker_combat_mult = float(attacker_ship.call("get_combat_effectiveness_multiplier"))
	var defender_combat_mult: float = maxf(0.01, get_combat_effectiveness_multiplier(ship))
	var duration_mult: float = defender_combat_mult / maxf(0.01, attacker_combat_mult)
	return clampf(ship.boarding_capture_duration * duration_mult, 1.2, 16.0)


static func estimate_available_crew_count(ship) -> int:
	var soldiers: Array = EntityRegistry.get_soldiers_by_ship(ship)
	if not soldiers.is_empty():
		var alive_count: int = 0
		var own_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else str(ship.get("team"))
		for child in soldiers:
			if not is_instance_valid(child):
				continue
			if child.has_method("get_team_tag") and child.get_team_tag() != own_team:
				continue
			if child.has_method("is_dead") and child.is_dead():
				continue
			alive_count += 1
		if alive_count > 0:
			return alive_count
	if ship.get("current_crew_count") != null:
		return max(0, int(ship.get("current_crew_count")))
	if ship.get("max_crew_count") != null:
		return max(0, int(ship.get("max_crew_count")))
	if ship.get("max_crew") != null:
		return max(0, int(ship.get("max_crew")))
	return 0


static func is_in_gunnery_posture(ship) -> bool:
	var cannon_range: float = get_ship_cannon_range_for_allocation(ship)
	if cannon_range <= 0.01:
		return false
	var nearest_enemy_dist: float = get_nearest_enemy_ship_distance_for_allocation(ship)
	if nearest_enemy_dist <= 0.0:
		return false
	return nearest_enemy_dist <= cannon_range * 1.15


static func get_ship_cannon_range_for_allocation(ship) -> float:
	var max_range: float = 0.0
	var stack: Array[Node] = [ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.has_method("_get_current_range"):
			max_range = maxf(max_range, float(node.call("_get_current_range")))
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return max_range


static func get_nearest_enemy_ship_distance_for_allocation(ship) -> float:
	var own_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else str(ship.get("team"))
	var nearest_distance_sq: float = INF
	var opposing_team: String = "enemy" if own_team == "player" else "player"
	var all_ships: Array = EntityRegistry.get_ships_by_team(opposing_team)
	for other in all_ships:
		if not is_instance_valid(other) or other == ship:
			continue
		if other.has_method("is_combat_disabled") and other.is_combat_disabled():
			continue
		var planar_delta: Vector3 = other.global_position - ship.global_position
		planar_delta.y = 0.0
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
	if nearest_distance_sq == INF:
		return -1.0
	return sqrt(nearest_distance_sq)
