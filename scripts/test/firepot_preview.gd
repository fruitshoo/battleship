extends Node3D

const ENEMY_FIREPOT_SCENE := preload("res://scenes/ships/enemy_firepot_ship.tscn")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var row_forward_offset: float = -12.0
@export var column_spacing: float = 8.5
@export var too_close_distance: float = 4.5
@export var in_range_distance: float = 11.0
@export var too_far_distance: float = 22.0


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	_open_debug_panel()
	_disable_regular_spawns()
	_clear_existing_preview_enemies()
	_spawn_firepot_scenarios()


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
		if child is Node3D and child.is_in_group("enemy") and child.has_meta("firepot_preview_spawn"):
			child.queue_free()


func _spawn_firepot_scenarios() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return

	var forward := -player.global_basis.z.normalized()
	var right := player.global_basis.x.normalized()
	var center := player.global_position + forward * row_forward_offset

	_spawn_scenario("No Target", center - right * (column_spacing * 2.0), player, in_range_distance, false, true)
	_spawn_scenario("Too Close", center - right * column_spacing, player, too_close_distance, true, true)
	_spawn_scenario("In Range", center, player, in_range_distance, true, true)
	_spawn_scenario("No Tosser", center + right * column_spacing, player, in_range_distance, true, false)
	_spawn_scenario("Too Far", center + right * (column_spacing * 2.0), player, too_far_distance, true, true)


func _spawn_scenario(label_text: String, anchor: Vector3, player: Node3D, distance_to_player: float, assign_target: bool, keep_tosser: bool) -> void:
	var enemy := ENEMY_FIREPOT_SCENE.instantiate()
	if enemy == null:
		return

	add_child(enemy)
	enemy.set_meta("firepot_preview_spawn", true)

	var direction := (anchor - player.global_position).normalized()
	if direction.length_squared() <= 0.001:
		direction = -player.global_basis.z.normalized()
	enemy.global_position = player.global_position + direction * distance_to_player
	enemy.look_at(player.global_position, Vector3.UP)

	if "target" in enemy:
		enemy.target = player if assign_target else null
	if "fire_pot_cooldown_timer" in enemy:
		enemy.fire_pot_cooldown_timer = 0.0

	if not keep_tosser:
		_remove_fire_pot_role(enemy)

	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color(1.0, 0.95, 0.8, 1.0)
	label.position = Vector3(0.0, 6.0, 0.0)
	enemy.add_child(label)


func _remove_fire_pot_role(enemy: Node) -> void:
	var soldiers_node := enemy.get_node_or_null("Soldiers")
	if not is_instance_valid(soldiers_node):
		return
	for soldier in soldiers_node.get_children():
		if not is_instance_valid(soldier):
			continue
		if str(soldier.get("crew_role")) != "fire_pot":
			continue
		if soldier.has_method("apply_crew_role"):
			soldier.apply_crew_role("general")
		else:
			soldier.set("crew_role", "general")
			soldier.set_meta("crew_role", "general")
