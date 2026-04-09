extends Node3D

const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var enemy_lateral_offset: float = 5.5
@export var enemy_forward_offset: float = -1.0


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if is_instance_valid(hud) and auto_open_debug_panel:
		var panel: Variant = hud.get("sail_debug_panel")
		if panel is Control:
			panel.visible = true
			if hud.has_method("_update_sail_debug_toggle_button_text"):
				hud.call("_update_sail_debug_toggle_button_text")
			if hud.has_method("_sync_debug_tools_panel_state"):
				hud.call("_sync_debug_tools_panel_state")

	var level_manager: Node = get_node_or_null("LevelManager")
	if is_instance_valid(level_manager):
		if "boss_spawn_time" in level_manager:
			level_manager.set("boss_spawn_time", 99999.0)
		if "survival_victory_time" in level_manager:
			level_manager.set("survival_victory_time", 99999.0)

	var spawner: Node = get_node_or_null("EnemySpawner")
	if is_instance_valid(spawner):
		if stop_regular_spawns and "regular_spawn_stopped" in spawner:
			spawner.set("regular_spawn_stopped", true)
		if "elite_spawn_count" in spawner and "max_elite_spawns" in spawner:
			spawner.set("elite_spawn_count", int(spawner.get("max_elite_spawns")))

	_clear_existing_preview_enemy()
	_spawn_boarding_enemy()


func _clear_existing_preview_enemy() -> void:
	for child in get_children():
		if child is Node3D and child.is_in_group("enemy") and child.has_meta("boarding_preview_spawn"):
			child.queue_free()


func _spawn_boarding_enemy() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return

	var enemy := ENEMY_MELEE_SCENE.instantiate()
	if enemy == null:
		return

	add_child(enemy)
	enemy.set_meta("boarding_preview_spawn", true)

	var right := player.global_basis.x.normalized()
	var forward := -player.global_basis.z.normalized()
	enemy.global_position = player.global_position + right * enemy_lateral_offset + forward * enemy_forward_offset
	enemy.look_at(player.global_position, Vector3.UP)

	var label := Label3D.new()
	label.text = "Boarding Target"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(1.0, 0.92, 0.8, 1.0)
	label.position = Vector3(0.0, 6.0, 0.0)
	enemy.add_child(label)
