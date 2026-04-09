extends RefCounted
class_name PreviewHarnessHelper


static func setup_common(root: Node, auto_open_debug_panel: bool, stop_regular_spawns: bool) -> void:
	_open_debug_panel(root, auto_open_debug_panel)
	_disable_regular_spawns(root, stop_regular_spawns)


static func _open_debug_panel(root: Node, should_open: bool) -> void:
	if not should_open:
		return
	var hud: Node = root.get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return
	var panel: Variant = hud.get("sail_debug_panel")
	if panel is Control:
		panel.visible = true
		if hud.has_method("_update_sail_debug_toggle_button_text"):
			hud.call("_update_sail_debug_toggle_button_text")
		if hud.has_method("_sync_debug_tools_panel_state"):
			hud.call("_sync_debug_tools_panel_state")


static func _disable_regular_spawns(root: Node, stop_regular_spawns: bool) -> void:
	var level_manager: Node = root.get_node_or_null("LevelManager")
	if is_instance_valid(level_manager):
		if "boss_spawn_time" in level_manager:
			level_manager.set("boss_spawn_time", 99999.0)
		if "survival_victory_time" in level_manager:
			level_manager.set("survival_victory_time", 99999.0)

	var spawner: Node = root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		return
	if stop_regular_spawns and "regular_spawn_stopped" in spawner:
		spawner.set("regular_spawn_stopped", true)
	if "elite_spawn_count" in spawner and "max_elite_spawns" in spawner:
		spawner.set("elite_spawn_count", int(spawner.get("max_elite_spawns")))


static func clear_preview_enemies(root: Node, meta_name: String) -> void:
	for child in root.get_children():
		if child is Node3D and child.is_in_group("enemy") and child.has_meta(meta_name):
			child.queue_free()


static func add_billboard_label(parent: Node, text: String, position: Vector3, modulate: Color, font_size: int = 40) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.outline_size = 8
	label.modulate = modulate
	label.position = position
	parent.add_child(label)
	return label
