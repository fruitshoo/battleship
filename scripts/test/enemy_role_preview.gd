extends Node3D

const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")
const ENEMY_GUNNER_SCENE := preload("res://scenes/ships/enemy_gunner_ship.tscn")
const ENEMY_FIREPOT_SCENE := preload("res://scenes/ships/enemy_firepot_ship.tscn")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var role_spacing: float = 14.0
@export var role_forward_offset: float = -10.0


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

	_clear_existing_preview_enemies()
	_spawn_role_ships()


func _clear_existing_preview_enemies() -> void:
	for child in get_children():
		if child is Node3D and child.is_in_group("enemy") and child.has_meta("role_preview_spawn"):
			child.queue_free()


func _spawn_role_ships() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return

	var forward := -player.global_basis.z.normalized()
	var right := player.global_basis.x.normalized()
	var center := player.global_position + forward * role_forward_offset

	_spawn_role_ship("Melee", ENEMY_MELEE_SCENE, center - right * role_spacing, player)
	_spawn_role_ship("Gunner", ENEMY_GUNNER_SCENE, center, player)
	_spawn_role_ship("Firepot", ENEMY_FIREPOT_SCENE, center + right * role_spacing, player)


func _spawn_role_ship(label_text: String, scene: PackedScene, world_pos: Vector3, player: Node3D) -> void:
	var ship := scene.instantiate()
	if ship == null:
		return

	add_child(ship)
	ship.set_meta("role_preview_spawn", true)
	if ship is Node3D:
		ship.global_position = world_pos
		ship.look_at(player.global_position, Vector3.UP)

	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(1.0, 0.95, 0.8, 1.0)
	label.position = Vector3(0.0, 6.0, 0.0)
	ship.add_child(label)
