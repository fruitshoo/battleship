extends Node3D

const ENEMY_FIREPOT_SCENE := preload("res://scenes/ships/enemy_firepot_ship.tscn")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const PreviewStateSnapshotHelper = preload("res://scripts/test/preview_state_snapshot_helper.gd")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var row_forward_offset: float = -12.0
@export var column_spacing: float = 8.5
@export var too_close_distance: float = 4.5
@export var in_range_distance: float = 11.0
@export var too_far_distance: float = 22.0


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(_delta: float) -> void:
	_refresh_debug_labels()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_clear_existing_preview_enemies()
	_spawn_firepot_scenarios()


func _clear_existing_preview_enemies() -> void:
	PreviewHarnessHelper.clear_preview_enemies(self, "firepot_preview_spawn")


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

	PreviewHarnessHelper.assign_preview_target(enemy, player if assign_target else null)
	PreviewHarnessHelper.reset_preview_fire_pot_cooldown(enemy)

	if not keep_tosser:
		var handled := PreviewHarnessHelper.set_preview_fire_pot_enabled(enemy, false)
		if not handled:
			_remove_fire_pot_role(enemy)

	PreviewHarnessHelper.add_billboard_label(enemy, label_text, Vector3(0.0, 6.0, 0.0), Color(1.0, 0.95, 0.8, 1.0))
	var debug_label := PreviewHarnessHelper.add_billboard_label(enemy, "", Vector3(0.0, 4.8, 0.0), Color(0.86, 0.98, 1.0, 1.0), 24)
	debug_label.name = "DebugLabel"


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


func _refresh_debug_labels() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	for child in get_children():
		if not (child is Node3D) or not child.has_meta("firepot_preview_spawn"):
			continue
		var debug_label: Label3D = child.get_node_or_null("DebugLabel")
		if not is_instance_valid(debug_label):
			continue
		debug_label.text = _build_debug_text(child as Node3D, player)


func _build_debug_text(enemy: Node3D, player: Node3D) -> String:
	var has_target := false
	var in_range := false
	var has_tosser := false
	var cooldown := 0.0

	if "target" in enemy:
		has_target = is_instance_valid(enemy.target)
	if "fire_pot_cooldown_timer" in enemy:
		cooldown = float(enemy.fire_pot_cooldown_timer)

	if is_instance_valid(player):
		var dist: float = enemy.global_position.distance_to(player.global_position)
		in_range = dist >= 7.0 and dist <= 18.0

	has_tosser = PreviewHarnessHelper.has_preview_crew_role(enemy, "fire_pot")
	if not has_tosser:
		var soldiers_node := enemy.get_node_or_null("Soldiers")
		if is_instance_valid(soldiers_node):
			for soldier in soldiers_node.get_children():
				if not is_instance_valid(soldier):
					continue
				if str(soldier.get("crew_role")) == "fire_pot" and int(soldier.get("current_state")) != 4:
					has_tosser = true
					break

	return PreviewStateSnapshotHelper.build_firepot_text(has_target, in_range, has_tosser, cooldown)
