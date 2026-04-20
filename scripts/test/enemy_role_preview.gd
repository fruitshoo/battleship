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


func _process(_delta: float) -> void:
	_refresh_debug_labels()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_clear_existing_preview_enemies()
	_spawn_role_ships()


func _clear_existing_preview_enemies() -> void:
	PreviewHarnessHelper.clear_preview_enemies(self, "role_preview_spawn")


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

	PreviewHarnessHelper.add_billboard_label(ship, label_text, Vector3(0.0, 6.0, 0.0), Color(1.0, 0.95, 0.8, 1.0), 48)
	var debug_label := PreviewHarnessHelper.add_billboard_label(ship, "", Vector3(0.0, 4.8, 0.0), Color(0.86, 0.98, 1.0, 1.0), 24)
	debug_label.name = "DebugLabel"


func _refresh_debug_labels() -> void:
	for child in get_children():
		if not (child is Node3D) or not child.has_meta("role_preview_spawn"):
			continue
		var debug_label: Label3D = child.get_node_or_null("DebugLabel")
		if not is_instance_valid(debug_label):
			continue
		debug_label.text = _build_debug_text(child)


func _build_debug_text(ship: Node) -> String:
	return PreviewStateSnapshotHelper.build_enemy_role_text(
		ship.call("is_gunner_role") == true,
		float(ship.get("preferred_combat_range")),
		ship.call("can_board_targets") == true,
		ship.call("can_use_fire_pot_attack") == true
	)
