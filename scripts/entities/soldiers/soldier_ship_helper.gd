extends RefCounted
class_name SoldierShipHelper

const SoldierShipSpatialCacheHelper = preload("res://scripts/entities/soldiers/soldier_ship_spatial_cache_helper.gd")
const SoldierDeckZoneHelper = preload("res://scripts/entities/soldiers/soldier_deck_zone_helper.gd")

const DECK_BOUNDS_EDGE_INSET := 0.36


static func find_nearest_enemy(soldier) -> Node3D:
	if NodeContractHelper.is_sinking_or_dying(soldier.get("owned_ship")):
		return null
	var home_ship: Variant = soldier.get("home_ship")
	var is_player_boarder: bool = soldier.team == "player" and is_instance_valid(home_ship) and home_ship != soldier.owned_ship
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
		var other_owned_ship = other.get_owned_ship_node() if other.has_method("get_owned_ship_node") else other.get("owned_ship")
		if NodeContractHelper.is_sinking_or_dying(other_owned_ship):
			continue
		if other.get_team_tag() == soldier.team:
			continue
		if SoldierCaptainGuardHelper.should_defer_player_captain_target(soldier, other):
			continue
		if not SoldierDeckZoneHelper.can_share_combat_zone(soldier, other):
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

	if soldier.is_melee_only:
		return nearest_on_ship

	if not _can_scan_cross_ship_ranged_targets(soldier):
		return nearest_on_ship if nearest_on_ship else nearest_global

	if soldier.has_method("_allow_cross_ship_enemy_scan") and soldier._allow_cross_ship_enemy_scan() == false:
		if is_player_boarder and nearest_ranged_on_ship:
			return nearest_ranged_on_ship
		return nearest_on_ship if nearest_on_ship else nearest_global

	var ship_scan_data: Dictionary = SoldierShipSpatialCacheHelper.get_ship_enemy_scan_data(soldier)
	var nearby_target_ships: Array = ship_scan_data.get("nearby_target_ships", ship_scan_data.get("nearby_enemy_ships", []))
	for other_ship_variant in nearby_target_ships:
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
			if SoldierCaptainGuardHelper.should_defer_player_captain_target(soldier, other):
				continue
			var cross_owned_ship = other.get_owned_ship_node() if other.has_method("get_owned_ship_node") else other.get("owned_ship")
			if NodeContractHelper.is_sinking_or_dying(cross_owned_ship):
				continue
			var pos_diff_xz := Vector2(soldier.global_position.x - other.global_position.x, soldier.global_position.z - other.global_position.z)
			var dist_sq_xz: float = pos_diff_xz.length_squared()
			if dist_sq_xz > detection_range_sq:
				continue

			if dist_sq_xz < nearest_distance_global:
				nearest_distance_global = dist_sq_xz
				nearest_global = other

	if is_player_boarder and nearest_ranged_on_ship:
		return nearest_ranged_on_ship
	if soldier.is_melee_only:
		return nearest_on_ship if nearest_on_ship else nearest_global
	return nearest_on_ship if nearest_on_ship else nearest_global


static func _can_scan_cross_ship_ranged_targets(soldier) -> bool:
	if soldier.is_melee_only:
		return false
	if soldier.is_ranged_only:
		return true
	var bow_variant: Variant = soldier.get("weapon_bow")
	if is_instance_valid(bow_variant):
		return true
	var weapon_variant: Variant = soldier.get("current_weapon")
	if is_instance_valid(weapon_variant) and weapon_variant.get("max_range") != null:
		return float(weapon_variant.get("max_range")) > 5.0
	return false


static func find_nearest_hostile_on_owned_ship(soldier) -> Node3D:
	if not is_instance_valid(soldier.owned_ship):
		return null
	if NodeContractHelper.is_sinking_or_dying(soldier.owned_ship):
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
		var other_owned_ship = other.get_owned_ship_node() if other.has_method("get_owned_ship_node") else other.get("owned_ship")
		if NodeContractHelper.is_sinking_or_dying(other_owned_ship):
			continue
		if other.get_team_tag() == soldier.team:
			continue
		if SoldierCaptainGuardHelper.should_defer_player_captain_target(soldier, other):
			continue
		if not SoldierDeckZoneHelper.can_share_combat_zone(soldier, other):
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


static func get_clamped_ship_deck_local(soldier, ship: Node3D, local_position: Vector3, edge_inset: float = DECK_BOUNDS_EDGE_INSET) -> Vector3:
	if SoldierDeckZoneHelper.is_roof(soldier) and ship.has_method("clamp_roof_boarding_landing_local"):
		return ship.call("clamp_roof_boarding_landing_local", local_position)
	return get_clamped_main_deck_local(ship, local_position, edge_inset)


static func get_random_wander_deck_local(soldier, ship: Node3D, edge_inset: float = DECK_BOUNDS_EDGE_INSET) -> Vector3:
	var half_ext: Vector2 = get_ship_deck_half_extents(soldier, ship)
	if half_ext.x <= 0.01 or half_ext.y <= 0.01:
		return get_clamped_ship_deck_local(soldier, ship, Vector3.ZERO, edge_inset)

	var safe_half_z := maxf(0.08, half_ext.y - minf(edge_inset, maxf(0.0, half_ext.y - 0.08)))
	var random_z := randf_range(-safe_half_z, safe_half_z)
	var half_width := get_ship_deck_half_width_at_z(ship, random_z, half_ext.x)
	var safe_half_width := maxf(0.08, half_width - minf(edge_inset, maxf(0.0, half_width - 0.08)))
	var deck_height: float = ship.get("deck_height") if is_instance_valid(ship) and ship.get("deck_height") != null else 0.4
	var local_position := Vector3(randf_range(-safe_half_width, safe_half_width), deck_height, random_z)
	if SoldierDeckZoneHelper.is_roof(soldier) and ship.has_method("clamp_roof_boarding_landing_local"):
		return ship.call("clamp_roof_boarding_landing_local", local_position)
	return local_position


static func get_clamped_main_deck_local(ship: Node3D, local_position: Vector3, edge_inset: float = DECK_BOUNDS_EDGE_INSET, deck_half_extents: Vector2 = Vector2.ZERO) -> Vector3:
	var d_height: float = ship.get("deck_height") if "deck_height" in ship else 0.4
	var half_ext: Vector2 = deck_half_extents
	if half_ext.x <= 0.01 or half_ext.y <= 0.01:
		half_ext = get_ship_deck_half_extents(null, ship)
	var safe_half_z := maxf(0.08, half_ext.y - minf(edge_inset, maxf(0.0, half_ext.y - 0.08)))
	var clamped_z := clampf(local_position.z, -safe_half_z, safe_half_z)
	var half_width := get_ship_deck_half_width_at_z(ship, clamped_z, half_ext.x)
	var safe_half_width := maxf(0.08, half_width - minf(edge_inset, maxf(0.0, half_width - 0.08)))
	return Vector3(
		clampf(local_position.x, -safe_half_width, safe_half_width),
		d_height,
		clamped_z
	)


static func _get_ship_soldier_parent(ship: Node3D) -> Node:
	var soldiers_node: Node = NodeContractHelper.get_soldiers_container(ship)
	if is_instance_valid(soldiers_node):
		return soldiers_node
	return ship


static func get_ship_deck_half_extents(soldier, ship: Node3D) -> Vector2:
	return SoldierShipSpatialCacheHelper.resolve_ship_deck_half_extents(soldier, ship)


static func get_ship_deck_half_width_at_z(ship: Node3D, local_z: float, fallback_width: float) -> float:
	if is_instance_valid(ship) and ship.has_method("get_deck_half_width_at_z"):
		return maxf(0.08, float(ship.call("get_deck_half_width_at_z", local_z)))
	return maxf(0.08, fallback_width)
