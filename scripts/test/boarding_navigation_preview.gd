extends Node3D

const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")

enum TargetDeckState {
	CLEAR,
	CONTESTED,
	OVERRUN,
}

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var target_deck_state: TargetDeckState = TargetDeckState.CLEAR
@export var front_distance: float = 13.0
@export var side_distance: float = 9.0
@export var rear_distance: float = 11.0


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	_open_debug_panel()
	_disable_regular_spawns()
	_clear_existing_preview_enemies()
	_apply_target_deck_state()
	_spawn_navigation_scenarios()


func _open_debug_panel() -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud) or not auto_open_debug_panel:
		return
	var panel: Variant = hud.get("sail_debug_panel")
	if panel is Control:
		panel.visible = true
		if hud.has_method("_update_sail_debug_toggle_button_text"):
			hud.call("_update_sail_debug_toggle_button_text")
		if hud.has_method("_sync_debug_tools_panel_state"):
			hud.call("_sync_debug_tools_panel_state")


func _disable_regular_spawns() -> void:
	var level_manager: Node = get_node_or_null("LevelManager")
	if is_instance_valid(level_manager):
		if "boss_spawn_time" in level_manager:
			level_manager.set("boss_spawn_time", 99999.0)
		if "survival_victory_time" in level_manager:
			level_manager.set("survival_victory_time", 99999.0)

	var spawner: Node = get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		return
	if stop_regular_spawns and "regular_spawn_stopped" in spawner:
		spawner.set("regular_spawn_stopped", true)
	if "elite_spawn_count" in spawner and "max_elite_spawns" in spawner:
		spawner.set("elite_spawn_count", int(spawner.get("max_elite_spawns")))


func _clear_existing_preview_enemies() -> void:
	for child in get_children():
		if child is Node3D and child.is_in_group("enemy") and child.has_meta("boarding_navigation_preview_spawn"):
			child.queue_free()


func _apply_target_deck_state() -> void:
	var player: Node = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return
	player.set("deck_is_contested", target_deck_state != TargetDeckState.CLEAR)
	player.set("deck_is_overrun", target_deck_state == TargetDeckState.OVERRUN)

	var label: Label3D = player.get_node_or_null("BoardingStateLabel")
	if not is_instance_valid(label):
		label = Label3D.new()
		label.name = "BoardingStateLabel"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.outline_size = 8
		label.modulate = Color(0.92, 1.0, 0.92, 1.0)
		label.position = Vector3(0.0, 7.5, 0.0)
		player.add_child(label)
	label.text = "Target Deck: %s" % _get_target_state_name()


func _spawn_navigation_scenarios() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return

	var forward := -player.global_basis.z.normalized()
	var right := player.global_basis.x.normalized()

	_spawn_enemy("Front", player.global_position + forward * front_distance, player)
	_spawn_enemy("Port", player.global_position + right * side_distance + forward * 1.4, player)
	_spawn_enemy("Rear", player.global_position - forward * rear_distance, player)
	_spawn_enemy("Starboard", player.global_position - right * side_distance + forward * 1.4, player)


func _spawn_enemy(label_text: String, world_pos: Vector3, player: Node3D) -> void:
	var enemy := ENEMY_MELEE_SCENE.instantiate()
	if enemy == null:
		return

	add_child(enemy)
	enemy.set_meta("boarding_navigation_preview_spawn", true)
	enemy.global_position = world_pos
	enemy.look_at(player.global_position, Vector3.UP)

	if "target" in enemy:
		enemy.target = player

	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color(1.0, 0.95, 0.8, 1.0)
	label.position = Vector3(0.0, 6.0, 0.0)
	enemy.add_child(label)


func _get_target_state_name() -> String:
	match target_deck_state:
		TargetDeckState.CONTESTED:
			return "Contested"
		TargetDeckState.OVERRUN:
			return "Overrun"
		_:
			return "Clear"
