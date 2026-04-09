extends RefCounted
class_name SoldierShipHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")


static func find_nearest_enemy(soldier) -> Node3D:
	var local_soldiers: Array = []
	if is_instance_valid(soldier.owned_ship):
		local_soldiers = EntityRegistry.get_soldiers_by_ship(soldier.owned_ship)
	if local_soldiers.is_empty():
		local_soldiers = soldier.get_soldiers_cached(soldier.get_tree())
	var nearest_on_ship: Node3D = null
	var nearest_distance_on_ship: float = INF
	var nearest_ranged_on_ship: Node3D = null
	var nearest_distance_ranged_on_ship: float = INF

	var nearest_global: Node3D = null
	var nearest_distance_global: float = INF
	var is_player_boarder: bool = soldier.team == "player" and is_instance_valid(soldier.home_ship) and soldier.home_ship != soldier.owned_ship

	var detection_range_sq: float = soldier.detection_range * soldier.detection_range

	for other in local_soldiers:
		if other == soldier or not is_instance_valid(other):
			continue
		if other.has_method("get_current_state_value") and other.get_current_state_value() == soldier.State.DEAD:
			continue
		if other.get_team_tag() == soldier.team:
			continue

		var pos_diff_xz := Vector2(soldier.global_position.x - other.global_position.x, soldier.global_position.z - other.global_position.z)
		var dist_sq_xz: float = pos_diff_xz.length_squared()
		if dist_sq_xz > detection_range_sq:
			continue

		if dist_sq_xz < nearest_distance_on_ship:
			nearest_distance_on_ship = dist_sq_xz
			nearest_on_ship = other
		if is_player_boarder and other.get("is_ranged_only") == true and dist_sq_xz < nearest_distance_ranged_on_ship:
			nearest_distance_ranged_on_ship = dist_sq_xz
			nearest_ranged_on_ship = other
		if soldier.is_melee_only:
			continue
		if dist_sq_xz < nearest_distance_global:
			nearest_distance_global = dist_sq_xz
			nearest_global = other

	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	var opposing_ships: Array = EntityRegistry.get_ships_by_team(opposing_team)
	for other_ship in opposing_ships:
		if not is_instance_valid(other_ship) or other_ship == soldier.owned_ship:
			continue
		if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
			continue
		if is_instance_valid(soldier.owned_ship):
			var ship_diff_xz := Vector2(
				soldier.owned_ship.global_position.x - other_ship.global_position.x,
				soldier.owned_ship.global_position.z - other_ship.global_position.z
			)
			if ship_diff_xz.length_squared() > 1600.0:
				continue

		var ship_soldiers: Array = EntityRegistry.get_soldiers_by_ship(other_ship)
		if ship_soldiers.is_empty():
			continue
		for other in ship_soldiers:
			if not is_instance_valid(other):
				continue
			if (other.has_method("get_current_state_value") and other.get_current_state_value() == soldier.State.DEAD) or other.get_team_tag() == soldier.team:
				continue

			var pos_diff_xz := Vector2(soldier.global_position.x - other.global_position.x, soldier.global_position.z - other.global_position.z)
			var dist_sq_xz: float = pos_diff_xz.length_squared()
			if dist_sq_xz > detection_range_sq:
				continue

			var is_ranged: bool = soldier.is_ranged_only or (soldier.current_weapon and soldier.current_weapon.get("max_range") != null and soldier.current_weapon.get("max_range") > 5.0)
			var can_cross_ship_engage: bool = false
			if is_instance_valid(soldier.owned_ship):
				var engage_distance: float = get_cross_ship_engage_max_distance(soldier, other_ship)
				var self_in_contact_zone: bool = is_in_cross_ship_contact_zone(soldier, other_ship)
				var other_in_contact_zone: bool = true
				if other.has_method("_is_in_cross_ship_contact_zone"):
					other_in_contact_zone = other.call("_is_in_cross_ship_contact_zone", soldier.owned_ship) == true
				can_cross_ship_engage = (
					is_ship_pair_in_melee_range(soldier, other_ship)
					and self_in_contact_zone
					and other_in_contact_zone
					and dist_sq_xz < (engage_distance * engage_distance)
				)
			else:
				can_cross_ship_engage = dist_sq_xz < 16.0

			if is_ranged or can_cross_ship_engage:
				if dist_sq_xz < nearest_distance_global:
					nearest_distance_global = dist_sq_xz
					nearest_global = other

	if is_player_boarder and nearest_ranged_on_ship:
		return nearest_ranged_on_ship
	if soldier.is_melee_only:
		return nearest_on_ship if nearest_on_ship else nearest_global
	return nearest_on_ship if nearest_on_ship else nearest_global


static func is_ship_pair_in_melee_range(soldier, other_ship: Node3D) -> bool:
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return false
	var ship_diff_xz := Vector2(
		soldier.owned_ship.global_position.x - other_ship.global_position.x,
		soldier.owned_ship.global_position.z - other_ship.global_position.z
	)
	var ship_pair_distance: float = get_cross_ship_engage_ship_distance(soldier, other_ship)
	return ship_diff_xz.length_squared() <= (ship_pair_distance * ship_pair_distance)


static func get_cross_ship_engage_ship_distance(soldier, other_ship: Node3D) -> float:
	var base_distance: float = soldier.CROSS_SHIP_ENGAGE_SHIP_DISTANCE
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return base_distance

	var my_half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
	var other_half_ext: Vector2 = get_ship_deck_half_extents(soldier, other_ship)
	var combined_length: float = my_half_ext.y + other_half_ext.y
	var size_bonus: float = maxf(0.0, combined_length - 3.4) * 0.6
	return base_distance + clampf(size_bonus, 0.0, 15.0)


static func get_cross_ship_engage_max_distance(soldier, other_ship: Node3D) -> float:
	var base_distance: float = soldier.CROSS_SHIP_ENGAGE_MAX_DISTANCE
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return base_distance

	var my_half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
	var other_half_ext: Vector2 = get_ship_deck_half_extents(soldier, other_ship)
	var combined_width: float = my_half_ext.x + other_half_ext.x
	var combined_length: float = my_half_ext.y + other_half_ext.y
	var width_bonus: float = maxf(0.0, combined_width - 2.4) * 0.6
	var length_bonus: float = maxf(0.0, combined_length - 3.4) * 0.5
	return base_distance + clampf(width_bonus + length_bonus, 0.0, 20.0)


static func get_cross_ship_contact_point_local(soldier, other_ship: Node3D) -> Vector3:
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return Vector3.INF

	var half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
	var other_local: Vector3 = soldier.owned_ship.to_local(other_ship.global_position)
	var use_side_edge: bool = absf(other_local.x / maxf(half_ext.x, 0.01)) > absf(other_local.z / maxf(half_ext.y, 0.01))
	var contact_local := Vector3.ZERO

	if use_side_edge:
		var x_sign: float = 1.0 if other_local.x >= 0.0 else -1.0
		contact_local.x = x_sign * half_ext.x
		contact_local.z = clampf(other_local.z, -half_ext.y * 0.72, half_ext.y * 0.72)
	else:
		var z_sign: float = 1.0 if other_local.z >= 0.0 else -1.0
		contact_local.x = clampf(other_local.x, -half_ext.x * 0.72, half_ext.x * 0.72)
		contact_local.z = z_sign * half_ext.y

	return contact_local


static func get_cross_ship_contact_point_global(soldier, other_ship: Node3D) -> Vector3:
	var contact_local: Vector3 = get_cross_ship_contact_point_local(soldier, other_ship)
	if contact_local == Vector3.INF:
		return Vector3.INF
	var target_global: Vector3 = soldier.owned_ship.to_global(contact_local)
	target_global.y = soldier.global_position.y
	return target_global


static func is_in_cross_ship_contact_zone(soldier, other_ship: Node3D) -> bool:
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return false
	var contact_local: Vector3 = get_cross_ship_contact_point_local(soldier, other_ship)
	if contact_local == Vector3.INF:
		return false
	var soldier_local: Vector3 = soldier.owned_ship.to_local(soldier.global_position)
	var diff_xz := Vector2(soldier_local.x - contact_local.x, soldier_local.z - contact_local.z)
	var zone_radius: float = clampf(get_cross_ship_engage_max_distance(soldier, other_ship) * 0.35, 3.0, 9.0)
	return diff_xz.length_squared() <= (zone_radius * zone_radius)


static func find_cross_ship_muster_target(soldier) -> Vector3:
	if not is_instance_valid(soldier.owned_ship):
		return Vector3.INF
	if soldier.owned_ship.get_team_tag() != soldier.team:
		return Vector3.INF
	if soldier.is_ranged_only:
		return Vector3.INF
	if not (soldier.is_melee_only or soldier.crew_role == "spearman" or soldier.crew_role == "general" or soldier.crew_role == "fire_pot" or soldier.is_captain):
		return Vector3.INF

	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	var opposing_ships: Array = soldier.get_ships_cached(soldier.get_tree(), opposing_team)
	var best_ship: Node3D = null
	var best_distance_sq: float = INF

	for other_ship in opposing_ships:
		if not is_instance_valid(other_ship) or other_ship == soldier.owned_ship:
			continue
		if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
			continue
		if not is_ship_pair_in_melee_range(soldier, other_ship):
			continue
		if is_in_cross_ship_contact_zone(soldier, other_ship):
			continue
		var ship_diff_xz := Vector2(
			soldier.owned_ship.global_position.x - other_ship.global_position.x,
			soldier.owned_ship.global_position.z - other_ship.global_position.z
		)
		var ship_distance_sq: float = ship_diff_xz.length_squared()
		if ship_distance_sq < best_distance_sq:
			best_distance_sq = ship_distance_sq
			best_ship = other_ship

	if not is_instance_valid(best_ship):
		return Vector3.INF
	return get_cross_ship_contact_point_global(soldier, best_ship)

static func keep_within_owned_ship_bounds(soldier) -> void:
	if not is_instance_valid(soldier.owned_ship):
		return

	var d_height: float = soldier.owned_ship.get("deck_height") if "deck_height" in soldier.owned_ship else 0.4
	if soldier.position.y != d_height:
		soldier.position.y = d_height

	var half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
	soldier.position.x = clampf(soldier.position.x, -half_ext.x, half_ext.x)
	soldier.position.z = clampf(soldier.position.z, -half_ext.y, half_ext.y)


static func get_ship_deck_half_extents(_soldier, ship: Node3D) -> Vector2:
	if is_instance_valid(ship) and ship.has_method("get_deck_half_extents"):
		var ext: Variant = ship.call("get_deck_half_extents")
		if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
			return ext

	var radius: float = ship.get("base_collision_radius") if "base_collision_radius" in ship else 4.5
	var w_mult: float = ship.get("width_multiplier") if "width_multiplier" in ship else 1.0
	var l_mult: float = ship.get("length_multiplier") if "length_multiplier" in ship else 1.0
	return Vector2(
		maxf(0.4, radius * w_mult * 0.85),
		maxf(0.8, radius * l_mult * 0.85)
	)
