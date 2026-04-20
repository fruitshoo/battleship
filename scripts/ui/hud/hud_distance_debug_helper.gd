class_name HudDistanceDebugHelper
extends RefCounted

const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")


static func toggle_distance_debug(hud) -> void:
	DistanceDebugVisualizer.set_runtime_enabled(not DistanceDebugVisualizer.runtime_enabled)
	ensure_distance_debug_visualizer(hud)
	if not DistanceDebugVisualizer.runtime_enabled and is_instance_valid(hud.debug_distance_label):
		hud.debug_distance_label.visible = false
		hud.debug_distance_label.text = ""


static func ensure_distance_debug_visualizer(hud) -> void:
	if not is_instance_valid(hud.player_ship):
		return
	var scene_root: Node = hud.get_tree().current_scene if is_instance_valid(hud.get_tree().current_scene) else hud.get_tree().root
	if not is_instance_valid(scene_root):
		return
	var existing: Node = scene_root.get_node_or_null("DistanceDebugVisualizer")
	if is_instance_valid(existing):
		if existing is DistanceDebugVisualizer:
			existing.tracked_ship = hud.player_ship
		return
	var visualizer := DistanceDebugVisualizer.new()
	visualizer.name = "DistanceDebugVisualizer"
	visualizer.tracked_ship = hud.player_ship
	scene_root.add_child(visualizer)


static func update_distance_debug_display(hud) -> void:
	if not OS.is_debug_build():
		return
	if not DistanceDebugVisualizer.runtime_enabled:
		if is_instance_valid(hud.debug_distance_label):
			hud.debug_distance_label.visible = false
		return
	if not HudLookupHelper.ensure_player_ship(hud):
		return
	ensure_distance_debug_visualizer(hud)
	var target: Node3D = find_nearest_enemy_ship_for_distance_debug(hud)
	var cannon_range: float = get_player_cannon_range_for_debug(hud)
	if not is_instance_valid(target):
		if is_instance_valid(hud.debug_distance_label):
			hud.debug_distance_label.visible = true
			hud.debug_distance_label.text = "포 사거리 %.1fm | 근처 적선 없음" % cannon_range
		return
	var planar_distance: float = get_planar_distance(hud.player_ship.global_position, target.global_position)
	var collision_distance: float = 0.0
	if hud.player_ship.has_method("get_collision_distance_to"):
		collision_distance = float(hud.player_ship.call("get_collision_distance_to", target))
	var melee_distance: float = get_ship_pair_melee_distance_debug(hud, hud.player_ship, target)
	var gap_distance: float = planar_distance - collision_distance
	var cannon_state: String = "IN" if cannon_range > 0.01 and planar_distance <= cannon_range else "OUT"
	var cannon_efficiency: float = get_cannon_efficiency_for_debug(hud, planar_distance)
	var dist_color := Color.WHITE
	if planar_distance <= 2.0:
		dist_color = Color(1.0, 0.3, 0.3)
	elif planar_distance < hud.CANNON_CLOSE_RANGE_FALLOFF_DISTANCE:
		dist_color = Color(1.0, 0.6, 0.2)
	elif planar_distance <= cannon_range:
		dist_color = Color(0.4, 1.0, 0.4)
	else:
		dist_color = Color(0.7, 0.7, 0.7)

	if is_instance_valid(hud.debug_distance_label):
		hud.debug_distance_label.visible = true
		hud.debug_distance_label.add_theme_color_override("font_color", dist_color)
		hud.debug_distance_label.text = "포 %.1fm [%s %.0f%%] | 거리 %.1fm | 선체 %.1fm (여유 %.1f) | 병사 %.1fm" % [
			cannon_range,
			cannon_state,
			cannon_efficiency * 100.0,
			planar_distance,
			collision_distance,
			gap_distance,
			melee_distance,
		]


static func find_nearest_enemy_ship_for_distance_debug(hud) -> Node3D:
	if not is_instance_valid(hud.player_ship):
		return null
	var all_ships: Array = EntityRegistry.get_ships_by_team("enemy")
	var nearest_ship: Node3D = null
	var nearest_distance_sq: float = INF
	for ship in all_ships:
		if not is_instance_valid(ship) or ship == hud.player_ship:
			continue
		if NodeContractHelper.get_team_tag(ship) == NodeContractHelper.get_team_tag(hud.player_ship):
			continue
		if NodeContractHelper.is_sinking_or_dying(ship):
			continue
		var planar_delta := Vector2(
			ship.global_position.x - hud.player_ship.global_position.x,
			ship.global_position.z - hud.player_ship.global_position.z
		)
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
			nearest_ship = ship
	return nearest_ship


static func get_planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func get_ship_pair_melee_distance_debug(hud, player: Node3D, other_ship: Node3D) -> float:
	var base_distance: float = 16.5
	var my_half_ext: Vector2 = get_ship_deck_half_extents_for_debug(player)
	var other_half_ext: Vector2 = get_ship_deck_half_extents_for_debug(other_ship)
	var combined_length: float = my_half_ext.y + other_half_ext.y
	var size_bonus: float = maxf(0.0, combined_length - 3.4) * 0.6
	return base_distance + clampf(size_bonus, 0.0, 15.0)


static func get_player_cannon_range_for_debug(hud) -> float:
	if not is_instance_valid(hud.player_ship):
		return 0.0
	var max_range: float = 0.0
	var stack: Array[Node] = [hud.player_ship]
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


static func get_cannon_efficiency_for_debug(hud, planar_distance: float) -> float:
	if planar_distance >= hud.CANNON_CLOSE_RANGE_FALLOFF_DISTANCE:
		return 1.0
	var t: float = clampf(planar_distance / hud.CANNON_CLOSE_RANGE_FALLOFF_DISTANCE, 0.0, 1.0)
	return lerpf(hud.CANNON_CLOSE_RANGE_MIN_MULTIPLIER, 1.0, t)


static func get_ship_deck_half_extents_for_debug(ship: Node3D) -> Vector2:
	if is_instance_valid(ship) and ship.has_method("get_deck_half_extents"):
		var ext: Variant = ship.call("get_deck_half_extents")
		if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
			return ext
	var radius: float = NodeContractHelper.get_base_collision_radius_value(ship)
	var w_mult: float = NodeContractHelper.get_collision_width_multiplier_value(ship)
	var l_mult: float = NodeContractHelper.get_collision_length_multiplier_value(ship)
	return Vector2(
		maxf(0.4, radius * w_mult * 0.85),
		maxf(0.8, radius * l_mult * 0.85)
	)
