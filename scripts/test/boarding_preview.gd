extends Node3D

const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const PreviewStateSnapshotHelper = preload("res://scripts/test/preview_state_snapshot_helper.gd")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var enemy_lateral_offset: float = 5.5
@export var enemy_forward_offset: float = -1.0


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(_delta: float) -> void:
	_refresh_debug_labels()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_clear_existing_preview_enemy()
	_spawn_boarding_enemy()


func _clear_existing_preview_enemy() -> void:
	PreviewHarnessHelper.clear_preview_enemies(self, "boarding_preview_spawn")


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
	PreviewHarnessHelper.assign_preview_target(enemy, player)

	PreviewHarnessHelper.add_billboard_label(enemy, "Boarding Target", Vector3(0.0, 6.0, 0.0), Color(1.0, 0.92, 0.8, 1.0), 48)
	var debug_label := PreviewHarnessHelper.add_billboard_label(enemy, "", Vector3(0.0, 4.8, 0.0), Color(0.86, 0.98, 1.0, 1.0), 24)
	debug_label.name = "DebugLabel"


func _refresh_debug_labels() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	for child in get_children():
		if not (child is Node3D) or not child.has_meta("boarding_preview_spawn"):
			continue
		var debug_label: Label3D = child.get_node_or_null("DebugLabel")
		if not is_instance_valid(debug_label):
			continue
		debug_label.text = _build_debug_text(child, player)


func _build_debug_text(enemy: Node3D, player: Node3D) -> String:
	var has_target := is_instance_valid(enemy.get("target"))
	var planar_distance := PreviewStateSnapshotHelper.planar_distance(player, enemy)
	return PreviewStateSnapshotHelper.build_boarding_preview_text(
		has_target,
		planar_distance,
		bool(enemy.get("is_boarding")),
		float(enemy.get("boarding_prep_timer"))
	)
