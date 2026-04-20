extends Node3D

const ENEMY_GUNNER_SCENE := preload("res://scenes/ships/enemy_gunner_ship.tscn")
const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")

@export var auto_open_debug_panel: bool = true
@export var auto_enable_distance_debug: bool = true
@export var stop_regular_spawns: bool = true
@export var close_distance: float = 5.0
@export var ideal_distance: float = 13.0
@export var edge_padding: float = -0.5
@export var out_padding: float = 6.0
@export var lateral_spacing: float = 6.5


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(_delta: float) -> void:
	_refresh_debug_labels()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_enable_distance_debug()
	_clear_existing_preview_enemies()
	_spawn_range_scenarios()
	_ensure_player_debug_label()


func _enable_distance_debug() -> void:
	if not auto_enable_distance_debug:
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return
	if hud.has_method("_toggle_distance_debug") and not DistanceDebugVisualizer.runtime_enabled:
		hud.call("_toggle_distance_debug")


func _clear_existing_preview_enemies() -> void:
	PreviewHarnessHelper.clear_preview_enemies(self, "cannon_range_preview_spawn")


func _spawn_range_scenarios() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return

	var player_range: float = _get_ship_cannon_range(player)
	var edge_distance: float = maxf(close_distance + 1.0, player_range + edge_padding)
	var out_distance: float = maxf(edge_distance + 1.0, player_range + out_padding)

	var forward := -player.global_basis.z.normalized()
	var right := player.global_basis.x.normalized()
	var center := player.global_position

	_spawn_enemy("Close", center + forward * close_distance - right * lateral_spacing * 1.5, player)
	_spawn_enemy("Ideal", center + forward * ideal_distance - right * lateral_spacing * 0.5, player)
	_spawn_enemy("Edge", center + forward * edge_distance + right * lateral_spacing * 0.5, player)
	_spawn_enemy("Out", center + forward * out_distance + right * lateral_spacing * 1.5, player)


func _spawn_enemy(label_text: String, world_pos: Vector3, player: Node3D) -> void:
	var enemy := ENEMY_GUNNER_SCENE.instantiate()
	if enemy == null:
		return

	add_child(enemy)
	enemy.set_meta("cannon_range_preview_spawn", true)
	enemy.global_position = world_pos
	enemy.look_at(player.global_position, Vector3.UP)

	PreviewHarnessHelper.assign_preview_target(enemy, player)

	PreviewHarnessHelper.add_billboard_label(enemy, label_text, Vector3(0.0, 6.2, 0.0), Color(1.0, 0.95, 0.8, 1.0))
	var debug_label := PreviewHarnessHelper.add_billboard_label(enemy, "", Vector3(0.0, 4.9, 0.0), Color(0.86, 0.98, 1.0, 1.0), 24)
	debug_label.name = "DebugLabel"


func _ensure_player_debug_label() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return
	var label: Label3D = player.get_node_or_null("CannonRangeLabel")
	if not is_instance_valid(label):
		label = PreviewHarnessHelper.add_billboard_label(player, "", Vector3(0.0, 8.0, 0.0), Color(0.96, 1.0, 0.86, 1.0), 28)
		label.name = "CannonRangeLabel"


func _refresh_debug_labels() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return

	var player_label: Label3D = player.get_node_or_null("CannonRangeLabel")
	if is_instance_valid(player_label):
		player_label.text = _build_player_debug_text(player)

	for child in get_children():
		if not (child is Node3D) or not child.has_meta("cannon_range_preview_spawn"):
			continue
		var debug_label: Label3D = child.get_node_or_null("DebugLabel")
		if not is_instance_valid(debug_label):
			continue
		debug_label.text = _build_enemy_debug_text(player, child as Node3D)


func _build_player_debug_text(player: Node3D) -> String:
	var range_value: float = _get_ship_cannon_range(player)
	var active_cannons: int = _count_active_cannons(player)
	var total_cannons: int = _count_total_cannons(player)
	return PreviewStateSnapshotHelper.build_cannon_player_text(range_value, active_cannons, total_cannons)


func _build_enemy_debug_text(player: Node3D, enemy: Node3D) -> String:
	var range_value: float = _get_ship_cannon_range(player)
	var planar_distance := PreviewStateSnapshotHelper.planar_distance(player, enemy)
	return PreviewStateSnapshotHelper.build_cannon_enemy_text(planar_distance, range_value)


func _get_ship_cannon_range(ship: Node) -> float:
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


func _count_total_cannons(ship: Node) -> int:
	var count: int = 0
	var stack: Array[Node] = [ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.has_method("_get_current_range"):
			count += 1
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return count


func _count_active_cannons(ship: Node) -> int:
	var count: int = 0
	var stack: Array[Node] = [ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.has_method("_get_current_range") and node is Node3D:
			var node3d := node as Node3D
			if node3d.visible and node.is_processing():
				count += 1
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return count
