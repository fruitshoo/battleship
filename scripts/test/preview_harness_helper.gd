extends RefCounted
class_name PreviewHarnessHelper

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")


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
	var level_manager: Node = LevelManagerRegistry.get_level_manager(root.get_tree())
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


static func assign_preview_target(ship: Node, target_ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("set_preview_target"):
		ship.call("set_preview_target", target_ship)
		return true
	elif "target" in ship:
		ship.target = target_ship
		return true
	return false


static func apply_preview_deck_state(ship: Node, is_contested: bool, is_overrun: bool = false) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("set_preview_deck_state"):
		ship.call("set_preview_deck_state", is_contested, is_overrun)
		return true
	else:
		ship.set("deck_is_contested", is_contested)
		ship.set("deck_is_overrun", is_overrun)
		return true
	return false


static func reset_preview_fire_pot_cooldown(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("reset_preview_fire_pot_cooldown"):
		ship.call("reset_preview_fire_pot_cooldown")
		return true
	elif "fire_pot_cooldown_timer" in ship:
		ship.fire_pot_cooldown_timer = 0.0
		return true
	return false


static func unlock_preview_enemy_fire_pot(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	ship.set_meta("enemy_fire_pot_unlocked", true)
	return true


static func set_preview_fire_pot_enabled(ship: Node, enabled: bool) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("set_preview_fire_pot_enabled"):
		ship.call("set_preview_fire_pot_enabled", enabled)
		return true
	return false


static func has_preview_crew_role(ship: Node, role_name: String) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("has_active_crew_role"):
		return ship.call("has_active_crew_role", role_name) == true
	return false


static func set_preview_deck_light_enabled(ship: Node, enabled: bool) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("set_preview_deck_light_enabled"):
		ship.call("set_preview_deck_light_enabled", enabled)
		return true
	if "enable_deck_light" in ship:
		ship.set("enable_deck_light", enabled)
		if ship.has_method("_refresh_deck_light"):
			ship.call("_refresh_deck_light")
		return true
	return false


static func add_billboard_label(parent: Node, text: String, position: Vector3, modulate: Color, font_size: int = 40, style_kind: String = "") -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	var resolved_style_kind := style_kind
	if resolved_style_kind.is_empty():
		resolved_style_kind = "hint" if font_size <= 28 else "callout"
	match resolved_style_kind:
		"marker":
			NavalUiTheme.style_world_marker(label, font_size, modulate)
		"hint":
			NavalUiTheme.style_world_hint(label, font_size, modulate)
		_:
			NavalUiTheme.style_world_callout(label, font_size, modulate)
	parent.add_child(label)
	return label
