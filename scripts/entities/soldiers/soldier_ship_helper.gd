extends RefCounted
class_name SoldierShipHelper


static func find_nearest_enemy(soldier) -> Node3D:
	var all_soldiers = soldier.get_soldiers_cached(soldier.get_tree())
	var nearest_on_ship: Node3D = null
	var nearest_distance_on_ship: float = INF
	var nearest_ranged_on_ship: Node3D = null
	var nearest_distance_ranged_on_ship: float = INF

	var nearest_global: Node3D = null
	var nearest_distance_global: float = INF
	var is_player_boarder: bool = soldier.team == "player" and is_instance_valid(soldier.home_ship) and soldier.home_ship != soldier.owned_ship

	var detection_range_sq: float = soldier.detection_range * soldier.detection_range

	for other in all_soldiers:
		if other == soldier or not is_instance_valid(other):
			continue

		if other.get("current_state") == soldier.State.DEAD:
			continue

		if other.get("team") == soldier.team:
			continue

		var other_ship = other.get("owned_ship")
		if is_instance_valid(other_ship) and (other_ship.get("is_dying") == true or other_ship.get("is_sinking") == true):
			continue

		if is_instance_valid(soldier.owned_ship) and is_instance_valid(other_ship) and soldier.owned_ship != other_ship:
			var ship_diff_xz := Vector2(
				soldier.owned_ship.global_position.x - other_ship.global_position.x,
				soldier.owned_ship.global_position.z - other_ship.global_position.z
			)
			if ship_diff_xz.length_squared() > 1600.0:
				continue

		var pos_diff_xz := Vector2(soldier.global_position.x - other.global_position.x, soldier.global_position.z - other.global_position.z)
		var dist_sq_xz: float = pos_diff_xz.length_squared()
		if dist_sq_xz > detection_range_sq:
			continue

		if is_instance_valid(soldier.owned_ship) and other_ship == soldier.owned_ship:
			if dist_sq_xz < nearest_distance_on_ship:
				nearest_distance_on_ship = dist_sq_xz
				nearest_on_ship = other
			if is_player_boarder and other.get("is_ranged_only") == true and dist_sq_xz < nearest_distance_ranged_on_ship:
				nearest_distance_ranged_on_ship = dist_sq_xz
				nearest_ranged_on_ship = other

		var is_ranged: bool = soldier.is_ranged_only or (soldier.current_weapon and soldier.current_weapon.get("max_range") != null and soldier.current_weapon.get("max_range") > 5.0)
		var can_cross_ship_engage: bool = false
		if is_instance_valid(soldier.owned_ship) and is_instance_valid(other_ship) and soldier.owned_ship != other_ship:
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
	if str(soldier.owned_ship.get("team")) != soldier.team:
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
		if other_ship.get("is_dying") == true or other_ship.get("is_sinking") == true:
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


static func find_ship_duty_target(soldier) -> Vector3:
	if not is_instance_valid(soldier.owned_ship):
		return Vector3.INF
	if str(soldier.owned_ship.get("team")) != soldier.team:
		return Vector3.INF
	if soldier.current_target != null:
		return Vector3.INF
	if soldier.is_captain:
		return Vector3.INF
	if soldier.owned_ship.get("deck_is_contested") == true or soldier.owned_ship.get("deck_is_overrun") == true:
		return Vector3.INF

	var half_ext: Vector2 = get_ship_deck_half_extents(soldier, soldier.owned_ship)
	var gunnery_ratio: float = float(soldier.owned_ship.get("gunnery_crew_ratio")) if soldier.owned_ship.get("gunnery_crew_ratio") != null else 0.0
	var handling_ratio: float = float(soldier.owned_ship.get("shiphandling_crew_ratio")) if soldier.owned_ship.get("shiphandling_crew_ratio") != null else 0.0
	var current_speed: float = float(soldier.owned_ship.get("current_speed")) if soldier.owned_ship.get("current_speed") != null else 0.0
	var rowing_active: bool = soldier.owned_ship.get("is_rowing") == true
	var rudder_angle: float = float(soldier.owned_ship.get("rudder_angle")) if soldier.owned_ship.get("rudder_angle") != null else 0.0
	var bias_sign: float = -1.0 if int(soldier.get_instance_id()) % 2 == 0 else 1.0
	var local_target: Vector3 = Vector3.INF

	if (soldier.is_ranged_only or soldier.crew_role == "general" or soldier.crew_role == "fire_pot") and gunnery_ratio >= 0.45:
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

	var ship_local_pos: Vector3 = soldier.owned_ship.to_local(soldier.global_position)
	var local_diff: Vector2 = Vector2(ship_local_pos.x - local_target.x, ship_local_pos.z - local_target.z)
	if local_diff.length_squared() <= 1.2:
		return Vector3.INF

	var target_global: Vector3 = soldier.owned_ship.to_global(local_target)
	target_global.y = soldier.global_position.y
	return target_global


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


static func _get_enemy_side_sign(soldier, fallback_sign: float) -> float:
	var opposing_team: String = "enemy" if soldier.team == "player" else "player"
	var opposing_ships: Array = soldier.get_ships_cached(soldier.get_tree(), opposing_team)
	var best_ship: Node3D = null
	var best_distance_sq: float = INF
	for other_ship in opposing_ships:
		if not is_instance_valid(other_ship):
			continue
		if other_ship.get("is_dying") == true or other_ship.get("is_sinking") == true:
			continue
		var planar_delta: Vector3 = other_ship.global_position - soldier.owned_ship.global_position
		planar_delta.y = 0.0
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best_ship = other_ship
	if not is_instance_valid(best_ship):
		return fallback_sign
	var enemy_local: Vector3 = soldier.owned_ship.to_local(best_ship.global_position)
	if absf(enemy_local.x) <= 0.2:
		return fallback_sign
	return 1.0 if enemy_local.x >= 0.0 else -1.0
