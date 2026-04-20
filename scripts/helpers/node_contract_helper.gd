extends RefCounted
class_name NodeContractHelper

const SHIP_NODE_SOLDIERS := "Soldiers"
const SHIP_NODE_PROXIMITY_AREA := "ProximityArea"
const SHIP_NODE_HIT_AREA := "HitArea"
const SHIP_NODE_CANNONS := "Cannons"
const SHIP_NODE_SPEAR_RAIL := "SpearRail"
const SHIP_NODE_HULL_DEFENSE_VISUALS := "HullDefenseVisuals"
const SHIP_NODE_SINGIGEON_LAUNCHER := "SingijeonLauncher"
const SHIP_NODE_JANGGUN_LAUNCHER := "JanggunLauncher"
const SHIP_CONTACT_AREA_NAMES := [
	SHIP_NODE_HIT_AREA,
	SHIP_NODE_PROXIMITY_AREA,
]

static func get_team_tag(node: Node, fallback: String = "") -> String:
	if not is_instance_valid(node):
		return fallback
	if node.has_method("get_team_tag"):
		return node.get_team_tag()
	if "team" in node:
		var team_value: Variant = node.get("team")
		if team_value != null:
			return str(team_value)
	return fallback


static func is_team(node: Node, team_name: String) -> bool:
	return get_team_tag(node) == team_name


static func is_sinking_or_dying(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_sinking_or_dying"):
		return node.is_sinking_or_dying()
	var sinking := false
	if "is_sinking" in node:
		sinking = sinking or node.get("is_sinking") == true
	if "is_dying" in node:
		sinking = sinking or node.get("is_dying") == true
	return sinking


static func get_current_state_value(node: Node) -> int:
	if not is_instance_valid(node):
		return -1
	if node.has_method("get_current_state_value"):
		return int(node.get_current_state_value())
	if "current_state" in node:
		var state_value: Variant = node.get("current_state")
		if state_value != null:
			return int(state_value)
	return -1


static func get_current_speed_value(node: Node) -> float:
	if not is_instance_valid(node):
		return 0.0
	if node.has_method("get_current_speed_value"):
		return float(node.get_current_speed_value())
	if "current_speed" in node:
		var speed_value: Variant = node.get("current_speed")
		if speed_value != null:
			return float(speed_value)
	return 0.0


static func get_owned_ship_node(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_owned_ship_node"):
		return node.get_owned_ship_node()
	if "owned_ship" in node:
		var owned_ship_value: Variant = node.get("owned_ship")
		if is_instance_valid(owned_ship_value) and owned_ship_value is Node3D:
			return owned_ship_value
	return null


static func get_projectile_aim_point(node: Node, vertical_offset: float = 0.5) -> Vector3:
	if not is_instance_valid(node) or not (node is Node3D):
		return Vector3.ZERO
	var node_3d := node as Node3D
	if node_3d.is_inside_tree() and node.has_method("get_projectile_aim_point"):
		return node.call("get_projectile_aim_point", vertical_offset)

	var aim_point := node_3d.global_position if node_3d.is_inside_tree() else node_3d.position
	if node_3d.is_in_group("soldiers") or node.has_method("is_dead_soldier"):
		aim_point.y += maxf(0.0, vertical_offset)
		return aim_point

	if node.get("deck_height") != null or node.get("hull_hp") != null or node.has_method("get_hull_hp_value"):
		var deck_height_value := 0.4
		if node.get("deck_height") != null:
			deck_height_value = float(node.get("deck_height"))
		aim_point.y += maxf(0.55, deck_height_value + maxf(0.0, vertical_offset))
		return aim_point

	aim_point.y += maxf(0.0, vertical_offset)
	return aim_point


static func get_boarding_target_ship(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_boarding_target_ship"):
		return node.get_boarding_target_ship()
	if "boarding_target" in node:
		var target_value: Variant = node.get("boarding_target")
		if is_instance_valid(target_value) and target_value is Node3D:
			return target_value
	return null


static func get_target_ship(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_target_ship"):
		return node.get_target_ship()
	if "target" in node:
		var target_value: Variant = node.get("target")
		if is_instance_valid(target_value) and target_value is Node3D:
			return target_value
	return null


static func get_soldiers_container(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_soldiers_container"):
		var container: Variant = node.call("get_soldiers_container")
		return container as Node if container is Node else null
	return node.get_node_or_null(SHIP_NODE_SOLDIERS)


static func get_cannons_container(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_cannons_container"):
		var container: Variant = node.call("get_cannons_container")
		return container as Node3D if container is Node3D else null
	var fallback := node.find_child(SHIP_NODE_CANNONS, true, false)
	return fallback as Node3D if fallback is Node3D else null


static func ensure_cannons_container(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("ensure_cannons_container"):
		var container: Variant = node.call("ensure_cannons_container")
		return container as Node3D if container is Node3D else null
	var existing := get_cannons_container(node)
	if existing is Node3D:
		return existing
	var created := Node3D.new()
	created.name = SHIP_NODE_CANNONS
	node.add_child(created)
	return created


static func clear_hull_defense_upgrade_nodes(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.has_method("clear_hull_defense_upgrade_nodes"):
		node.call("clear_hull_defense_upgrade_nodes")
		return
	var old_rail := node.get_node_or_null(SHIP_NODE_SPEAR_RAIL)
	if is_instance_valid(old_rail):
		old_rail.queue_free()
	var visuals := node.get_node_or_null(SHIP_NODE_HULL_DEFENSE_VISUALS)
	if is_instance_valid(visuals):
		visuals.queue_free()
	if node.has_meta("spear_rail_damage"):
		node.remove_meta("spear_rail_damage")


static func clear_singigeon_launcher(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.has_method("clear_singigeon_launcher"):
		node.call("clear_singigeon_launcher")
		return
	var launcher := node.get_node_or_null(SHIP_NODE_SINGIGEON_LAUNCHER)
	if is_instance_valid(launcher):
		launcher.queue_free()


static func install_janggun_launcher(node: Node, launcher_scene: PackedScene, local_position: Vector3 = Vector3(0.0, 0.8, 2.0)) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("install_janggun_launcher"):
		var mounted: Variant = node.call("install_janggun_launcher", launcher_scene, local_position)
		return mounted as Node3D if mounted is Node3D else null
	var existing := node.get_node_or_null(SHIP_NODE_JANGGUN_LAUNCHER)
	if existing is Node3D:
		return existing as Node3D
	if launcher_scene == null:
		return null
	var launcher := launcher_scene.instantiate()
	if not (launcher is Node3D):
		if is_instance_valid(launcher):
			launcher.queue_free()
		return null
	launcher.name = SHIP_NODE_JANGGUN_LAUNCHER
	node.add_child(launcher)
	var launcher_node := launcher as Node3D
	launcher_node.position = local_position
	return launcher_node


static func get_proximity_area(node: Node) -> Area3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_proximity_area"):
		var area: Variant = node.call("get_proximity_area")
		return area as Area3D if area is Area3D else null
	var fallback := node.get_node_or_null(SHIP_NODE_PROXIMITY_AREA)
	return fallback as Area3D if fallback is Area3D else null


static func get_hit_area(node: Node) -> Area3D:
	if not is_instance_valid(node):
		return null
	if node.has_method("get_hit_area"):
		var area: Variant = node.call("get_hit_area")
		return area as Area3D if area is Area3D else null
	var fallback := node.get_node_or_null(SHIP_NODE_HIT_AREA)
	return fallback as Area3D if fallback is Area3D else null


static func get_base_collision_radius_value(node: Node) -> float:
	if not is_instance_valid(node):
		return 4.5
	if node.has_method("get_base_collision_radius_value"):
		return float(node.get_base_collision_radius_value())
	if "base_collision_radius" in node:
		var value: Variant = node.get("base_collision_radius")
		if value != null:
			return float(value)
	return 4.5


static func get_collision_width_multiplier_value(node: Node) -> float:
	if not is_instance_valid(node):
		return 1.0
	if node.has_method("get_collision_width_multiplier_value"):
		return float(node.get_collision_width_multiplier_value())
	if "width_multiplier" in node:
		var value: Variant = node.get("width_multiplier")
		if value != null:
			return float(value)
	return 1.0


static func get_collision_length_multiplier_value(node: Node) -> float:
	if not is_instance_valid(node):
		return 1.0
	if node.has_method("get_collision_length_multiplier_value"):
		return float(node.get_collision_length_multiplier_value())
	if "length_multiplier" in node:
		var value: Variant = node.get("length_multiplier")
		if value != null:
			return float(value)
	return 1.0


static func is_player_controlled_ship(node: Node) -> bool:
	return ShipAllyRoleHelper.is_player_flagship(node)
