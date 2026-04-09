extends Node3D

const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")

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
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_clear_existing_preview_enemies()
	_apply_target_deck_state()
	_spawn_navigation_scenarios()


func _clear_existing_preview_enemies() -> void:
	PreviewHarnessHelper.clear_preview_enemies(self, "boarding_navigation_preview_spawn")


func _apply_target_deck_state() -> void:
	var player: Node = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return
	player.set("deck_is_contested", target_deck_state != TargetDeckState.CLEAR)
	player.set("deck_is_overrun", target_deck_state == TargetDeckState.OVERRUN)

	var label: Label3D = player.get_node_or_null("BoardingStateLabel")
	if not is_instance_valid(label):
		label = PreviewHarnessHelper.add_billboard_label(player, "", Vector3(0.0, 7.5, 0.0), Color(0.92, 1.0, 0.92, 1.0))
		label.name = "BoardingStateLabel"
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

	PreviewHarnessHelper.add_billboard_label(enemy, label_text, Vector3(0.0, 6.0, 0.0), Color(1.0, 0.95, 0.8, 1.0))


func _get_target_state_name() -> String:
	match target_deck_state:
		TargetDeckState.CONTESTED:
			return "Contested"
		TargetDeckState.OVERRUN:
			return "Overrun"
		_:
			return "Clear"
