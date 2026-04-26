extends RefCounted
class_name SoldierShipHelper

const SoldierShipSpatialCacheHelper = preload("res://scripts/entities/soldiers/soldier_ship_spatial_cache_helper.gd")


static func find_nearest_enemy(soldier) -> Node3D:
	var home_ship: Variant = soldier.get("home_ship")
	var is_player_boarder: bool = soldier.team == "player" and is_instance_valid(home_ship) and home_ship != soldier.owned_ship
	var ship_scan_data: Dictionary = SoldierShipSpatialCacheHelper.get_ship_enemy_scan_data(soldier)
	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	var nearest_local_boarder := find_nearest_hostile_on_owned_ship(soldier)
	if nearest_local_boarder != null and not is_player_boarder:
		return nearest_local_boarder

	var local_soldiers: Array = []
	if is_instance_valid(soldier.owned_ship):
		var local_center: Vector3 = soldier.owned_ship.to_local(soldier.global_position)
		local_soldiers = SoldierShipSpatialCacheHelper.get_ship_deck_bucket_candidates(soldier.owned_ship, opposing_team, local_center, soldier.detection_range)
	else:
		local_soldiers = soldier.get_soldiers_cached(soldier.get_tree())
	var nearest_on_ship: Node3D = null
	var nearest_distance_on_ship: float = INF
	var nearest_ranged_on_ship: Node3D = null
	var nearest_distance_ranged_on_ship: float = INF

	var nearest_global: Node3D = null
	var nearest_distance_global: float = INF
	var detection_range_sq: float = soldier.detection_range * soldier.detection_range

	for other in local_soldiers:
		if other == soldier or not is_instance_valid(other):
			continue
		if SoldierStateHelper.is_dead_soldier(other):
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
		if is_player_boarder and other.has_method("is_ranged_only_value") and other.is_ranged_only_value() and dist_sq_xz < nearest_distance_ranged_on_ship:
			nearest_distance_ranged_on_ship = dist_sq_xz
			nearest_ranged_on_ship = other
		if soldier.is_melee_only:
			continue
		if dist_sq_xz < nearest_distance_global:
			nearest_distance_global = dist_sq_xz
			nearest_global = other

	if soldier.has_method("_allow_cross_ship_enemy_scan") and soldier._allow_cross_ship_enemy_scan() == false:
		if is_player_boarder and nearest_ranged_on_ship:
			return nearest_ranged_on_ship
		if soldier.is_melee_only:
			return nearest_on_ship if nearest_on_ship else nearest_global
		return nearest_on_ship if nearest_on_ship else nearest_global

	var nearby_enemy_ships: Array = ship_scan_data.get("nearby_enemy_ships", [])
	for other_ship_variant in nearby_enemy_ships:
		var other_ship: Node3D = SoldierShipSpatialCacheHelper.get_valid_node3d(other_ship_variant)
		if other_ship == null or other_ship == soldier.owned_ship:
			continue
		if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
			continue
		if soldier.has_method("_should_hold_defensive_deck_position_against") and soldier._should_hold_defensive_deck_position_against(other_ship):
			continue
		var candidate_center_local: Vector3 = other_ship.to_local(soldier.global_position)
		var ship_soldiers: Array = SoldierShipSpatialCacheHelper.get_ship_deck_bucket_candidates(other_ship, opposing_team, candidate_center_local, soldier.detection_range)
		for other in ship_soldiers:
			if not is_instance_valid(other):
				continue
			if SoldierStateHelper.is_dead_soldier(other) or other.get_team_tag() == soldier.team:
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


static func find_nearest_hostile_on_owned_ship(soldier) -> Node3D:
	if not is_instance_valid(soldier.owned_ship):
		return null
	var nearest: Node3D = null
	var nearest_distance_sq: float = INF
	var detection_range_sq: float = soldier.detection_range * soldier.detection_range
	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	var soldier_local: Vector3 = soldier.owned_ship.to_local(soldier.global_position)
	var hostile_on_ship: Array = SoldierShipSpatialCacheHelper.get_ship_deck_bucket_candidates(soldier.owned_ship, opposing_team, soldier_local, soldier.detection_range)
	for other in hostile_on_ship:
		if other == soldier or not is_instance_valid(other):
			continue
		if SoldierStateHelper.is_dead_soldier(other):
			continue
		if other.get_team_tag() == soldier.team:
			continue
		var dist_sq_xz := Vector2(
			soldier.global_position.x - other.global_position.x,
			soldier.global_position.z - other.global_position.z
		).length_squared()
		if dist_sq_xz > detection_range_sq:
			continue
		if dist_sq_xz < nearest_distance_sq:
			nearest_distance_sq = dist_sq_xz
			nearest = other
	return nearest


static func is_ship_pair_in_melee_range(soldier, other_ship: Node3D) -> bool:
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return false
	var pair_geometry: Dictionary = SoldierShipSpatialCacheHelper.get_ship_pair_geometry(soldier, other_ship)
	var ship_diff_xz_sq: float = INF
	if not pair_geometry.is_empty():
		ship_diff_xz_sq = float(pair_geometry.get("ship_diff_xz_sq", INF))
	else:
		var ship_diff_xz := Vector2(
			soldier.owned_ship.global_position.x - other_ship.global_position.x,
			soldier.owned_ship.global_position.z - other_ship.global_position.z
		)
		ship_diff_xz_sq = ship_diff_xz.length_squared()
	var ship_pair_distance: float = get_cross_ship_engage_ship_distance(soldier, other_ship)
	return ship_diff_xz_sq <= (ship_pair_distance * ship_pair_distance)


static func get_cross_ship_engage_ship_distance(soldier, other_ship: Node3D) -> float:
	var base_distance: float = soldier.CROSS_SHIP_ENGAGE_SHIP_DISTANCE
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return base_distance

	var pair_geometry: Dictionary = SoldierShipSpatialCacheHelper.get_ship_pair_geometry(soldier, other_ship)
	if pair_geometry.is_empty():
		var my_half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
		var other_half_ext: Vector2 = get_ship_deck_half_extents(soldier, other_ship)
		var combined_length: float = my_half_ext.y + other_half_ext.y
		var size_bonus: float = maxf(0.0, combined_length - 3.4) * 0.6
		return base_distance + clampf(size_bonus, 0.0, 15.0)
	return base_distance + float(pair_geometry.get("ship_distance_bonus", 0.0))


static func get_cross_ship_engage_max_distance(soldier, other_ship: Node3D) -> float:
	var base_distance: float = soldier.CROSS_SHIP_ENGAGE_MAX_DISTANCE
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return base_distance

	var pair_geometry: Dictionary = SoldierShipSpatialCacheHelper.get_ship_pair_geometry(soldier, other_ship)
	if pair_geometry.is_empty():
		var my_half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
		var other_half_ext: Vector2 = get_ship_deck_half_extents(soldier, other_ship)
		var combined_width: float = my_half_ext.x + other_half_ext.x
		var combined_length: float = my_half_ext.y + other_half_ext.y
		var width_bonus: float = maxf(0.0, combined_width - 2.4) * 0.6
		var length_bonus: float = maxf(0.0, combined_length - 3.4) * 0.5
		return base_distance + clampf(width_bonus + length_bonus, 0.0, 20.0)
	return base_distance + float(pair_geometry.get("max_distance_bonus", 0.0))


static func get_cross_ship_contact_point_local(soldier, other_ship: Node3D) -> Vector3:
	if not is_instance_valid(soldier.owned_ship) or not is_instance_valid(other_ship):
		return Vector3.INF
	var pair_geometry: Dictionary = SoldierShipSpatialCacheHelper.get_ship_pair_geometry(soldier, other_ship)
	if not pair_geometry.is_empty():
		var cached_contact: Variant = pair_geometry.get("contact_local", Vector3.INF)
		if cached_contact is Vector3:
			return cached_contact as Vector3

	var half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
	var contact_span_ratio: float = 0.72
	if half_ext.x >= 3.2 or half_ext.y >= 5.6:
		contact_span_ratio = 0.84
	var other_local: Vector3 = soldier.owned_ship.to_local(other_ship.global_position)
	var use_side_edge: bool = absf(other_local.x / maxf(half_ext.x, 0.01)) > absf(other_local.z / maxf(half_ext.y, 0.01))
	var contact_local := Vector3.ZERO

	if use_side_edge:
		var x_sign: float = 1.0 if other_local.x >= 0.0 else -1.0
		contact_local.x = x_sign * half_ext.x
		contact_local.z = clampf(other_local.z, -half_ext.y * contact_span_ratio, half_ext.y * contact_span_ratio)
	else:
		var z_sign: float = 1.0 if other_local.z >= 0.0 else -1.0
		contact_local.x = clampf(other_local.x, -half_ext.x * contact_span_ratio, half_ext.x * contact_span_ratio)
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
	var pair_geometry: Dictionary = SoldierShipSpatialCacheHelper.get_ship_pair_geometry(soldier, other_ship)
	var contact_local: Vector3 = get_cross_ship_contact_point_local(soldier, other_ship)
	if contact_local == Vector3.INF:
		return false
	var soldier_local: Vector3 = soldier.owned_ship.to_local(soldier.global_position)
	var diff_xz := Vector2(soldier_local.x - contact_local.x, soldier_local.z - contact_local.z)
	var zone_radius: float = 3.0
	if not pair_geometry.is_empty():
		var size_pressure: float = float(pair_geometry.get("size_pressure", 0.0))
		var max_distance_bonus: float = float(pair_geometry.get("max_distance_bonus", 0.0))
		zone_radius = clampf(
			(float(soldier.CROSS_SHIP_ENGAGE_MAX_DISTANCE) + max_distance_bonus) * 0.35 + size_pressure * 0.16,
			3.0,
			12.0
		)
	else:
		var my_half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
		var other_half_ext: Vector2 = get_ship_deck_half_extents(soldier, other_ship)
		var size_pressure_fallback: float = maxf(0.0, (my_half_ext.x + other_half_ext.x + my_half_ext.y + other_half_ext.y) - 10.0)
		zone_radius = clampf(
			get_cross_ship_engage_max_distance(soldier, other_ship) * 0.35 + size_pressure_fallback * 0.16,
			3.0,
			12.0
		)
	return diff_xz.length_squared() <= (zone_radius * zone_radius)


static func find_cross_ship_muster_target(soldier) -> Vector3:
	if not is_instance_valid(soldier.owned_ship):
		return Vector3.INF
	var owned_team: String = soldier.owned_ship.get_team_tag() if soldier.owned_ship.has_method("get_team_tag") else str(soldier.owned_ship.get("team"))
	if owned_team != soldier.team:
		return Vector3.INF
	if soldier.is_ranged_only:
		return Vector3.INF
	if not (soldier.is_melee_only or soldier.crew_role == "spearman" or soldier.crew_role == "general" or soldier.crew_role == "fire_pot" or soldier.is_captain):
		return Vector3.INF

	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	var ship_scan_data: Dictionary = SoldierShipSpatialCacheHelper.get_ship_enemy_scan_data(soldier)
	var opposing_ships: Array = ship_scan_data.get("nearby_enemy_ships", [])
	if ship_scan_data.is_empty():
		opposing_ships = soldier.get_ships_cached(soldier.get_tree(), opposing_team)
	var best_ship: Node3D = null
	var best_distance_sq: float = INF

	for other_ship in opposing_ships:
		if not is_instance_valid(other_ship) or other_ship == soldier.owned_ship:
			continue
		if other_ship.has_method("is_sinking_or_dying") and other_ship.is_sinking_or_dying():
			continue
		if soldier.has_method("_should_hold_defensive_deck_position_against") and soldier._should_hold_defensive_deck_position_against(other_ship):
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

	var ship: Node3D = soldier.owned_ship
	var target_parent: Node = _get_ship_soldier_parent(ship)
	if is_instance_valid(target_parent) and soldier.get_parent() != target_parent:
		soldier.reparent(target_parent, true)

	var local_pos: Vector3 = ship.to_local(soldier.global_position)
	var deck_pos: Vector3 = get_clamped_ship_deck_local(soldier, ship, local_pos)
	if not local_pos.is_equal_approx(deck_pos):
		soldier.global_position = ship.to_global(deck_pos)


static func get_clamped_ship_deck_local(soldier, ship: Node3D, local_position: Vector3) -> Vector3:
	var d_height: float = ship.get("deck_height") if "deck_height" in ship else 0.4
	var half_ext: Vector2 = get_ship_deck_half_extents(soldier, ship)
	return Vector3(
		clampf(local_position.x, -half_ext.x, half_ext.x),
		d_height,
		clampf(local_position.z, -half_ext.y, half_ext.y)
	)


static func _get_ship_soldier_parent(ship: Node3D) -> Node:
	var soldiers_node: Node = NodeContractHelper.get_soldiers_container(ship)
	if is_instance_valid(soldiers_node):
		return soldiers_node
	return ship


static func get_ship_deck_half_extents(soldier, ship: Node3D) -> Vector2:
	return SoldierShipSpatialCacheHelper.resolve_ship_deck_half_extents(soldier, ship)
