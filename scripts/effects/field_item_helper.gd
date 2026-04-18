extends RefCounted
class_name FieldItemHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")


static func get_current_magnet_radius(item: Node, base_radius: float, cached_upgrade_manager: Node = null) -> float:
	var meta_bonus := 0.0
	if is_instance_valid(item):
		var meta_manager = item.get_node_or_null("/root/MetaManager")
		if is_instance_valid(meta_manager) and meta_manager.has_method("get_collection_radius_bonus"):
			meta_bonus = float(meta_manager.get_collection_radius_bonus())

	var upgrade_manager := cached_upgrade_manager
	if not is_instance_valid(upgrade_manager) and is_instance_valid(item):
		upgrade_manager = item.get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("get_supply_bonus_stats"):
		var supply_stats: Dictionary = upgrade_manager.get_supply_bonus_stats()
		return base_radius + meta_bonus + float(supply_stats.get("radius_bonus", 0.0))
	return base_radius + meta_bonus


static func sample_ocean_surface(item: Node3D, ocean: Node, sample_distance: float = 0.85) -> Dictionary:
	if not is_instance_valid(item) or not is_instance_valid(ocean) or not ocean.has_method("get_wave_height"):
		return {
			"height": 0.0,
			"tilt": Vector2.ZERO,
		}
	var center := item.global_position if item.is_inside_tree() else item.position
	var center_height: float = float(ocean.call("get_wave_height", center))
	var right_height: float = float(ocean.call("get_wave_height", center + Vector3(sample_distance, 0.0, 0.0)))
	var forward_height: float = float(ocean.call("get_wave_height", center + Vector3(0.0, 0.0, sample_distance)))
	return {
		"height": center_height,
		"tilt": Vector2(
			(right_height - center_height) / sample_distance,
			(forward_height - center_height) / sample_distance
		),
	}


static func find_closest_player_ship(item: Node3D, search_radius: float, search_radius_multiplier: float = 1.5) -> Node3D:
	if not is_instance_valid(item) or not item.is_inside_tree():
		return null

	var closest_dist := INF
	var closest_ship: Node3D = null
	for candidate in EntityRegistry.get_ships_by_team("player"):
		var player_ship := candidate as Node3D
		if not is_instance_valid(player_ship) or not player_ship.is_inside_tree():
			continue
		if NodeContractHelper.is_sinking_or_dying(player_ship):
			continue

		var dist := item.global_position.distance_to(player_ship.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_ship = player_ship

	if closest_dist <= search_radius * search_radius_multiplier:
		return closest_ship
	return null


static func get_ship_from_node(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.is_in_group("player"):
		return node as Node3D

	var parent := node.get_parent()
	if is_instance_valid(parent) and parent.is_in_group("player"):
		return parent as Node3D

	if node is CollisionShape3D or node is Area3D:
		var area_parent := node.get_parent()
		if is_instance_valid(area_parent) and area_parent.is_in_group("player"):
			return area_parent as Node3D

	if is_instance_valid(node.owner) and node.owner.is_in_group("player"):
		return node.owner as Node3D

	return null


static func get_ship_edge_distance(item: Node3D, ship: Node3D) -> float:
	if not is_instance_valid(item):
		return INF
	return get_ship_edge_distance_from_position(item.global_position, ship)


static func get_ship_edge_distance_from_position(world_position: Vector3, ship: Node3D) -> float:
	if not is_instance_valid(ship):
		return INF
	var offset := world_position - ship.global_position
	offset.y = 0.0
	var center_distance := offset.length()
	if center_distance <= 0.0001:
		return 0.0
	if ship.has_method("get_directional_collision_radius"):
		return center_distance - float(ship.call("get_directional_collision_radius", offset))
	return center_distance - NodeContractHelper.get_base_collision_radius_value(ship)


static func get_ship_side_anchor(item: Node3D, ship: Node3D, lift_to_deck: bool = false, inset: float = 0.25, lift_height: float = 0.75) -> Vector3:
	if not is_instance_valid(item) or not is_instance_valid(ship):
		return Vector3.ZERO

	var offset := item.global_position - ship.global_position
	offset.y = 0.0
	var dir := offset.normalized() if offset.length_squared() > 0.0001 else -ship.global_transform.basis.z.normalized()
	var radius := 1.5
	if ship.has_method("get_directional_collision_radius"):
		radius = maxf(0.5, float(ship.call("get_directional_collision_radius", dir)))
	else:
		radius = maxf(0.5, NodeContractHelper.get_base_collision_radius_value(ship))

	var anchor := ship.global_position + dir * maxf(radius - inset, 0.5)
	anchor.y = maxf(item.global_position.y, ship.global_position.y + lift_height) if lift_to_deck else item.global_position.y
	return anchor


static func move_item_toward_ship_side_anchor(item: Node3D, ship: Node3D, move_distance: float, inset: float = 0.25) -> bool:
	if not is_instance_valid(item) or not is_instance_valid(ship) or move_distance <= 0.0:
		return false

	var pull_target := get_ship_side_anchor(item, ship, false, inset)
	var pull_delta := pull_target - item.global_position
	var distance_to_anchor := pull_delta.length()
	if distance_to_anchor <= 0.0001:
		return false

	item.global_position += pull_delta.normalized() * minf(move_distance, distance_to_anchor)
	return true


static func is_item_close_to_ship_edge(item: Node3D, ship: Node3D, margin: float) -> bool:
	return get_ship_edge_distance(item, ship) <= margin
