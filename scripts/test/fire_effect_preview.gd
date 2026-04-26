extends Node3D

@export var auto_open_debug_panel: bool = false
@export var stop_regular_spawns: bool = true
@export var preview_burn_duration: float = 120.0


func _ready() -> void:
	call_deferred("_configure_preview")


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	var player_ship: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player_ship):
		return

	if "is_burning" in player_ship:
		player_ship.set("is_burning", true)
	if "fire_build_up" in player_ship and "fire_threshold" in player_ship:
		player_ship.set("fire_build_up", float(player_ship.get("fire_threshold")))
	if "burn_timer" in player_ship:
		player_ship.set("burn_timer", preview_burn_duration)
	if "fire_effect_offset" in player_ship:
		player_ship.set("fire_effect_offset", Vector3(0.0, 0.55, -0.25))
	if "fire_effect_scale" in player_ship:
		player_ship.set("fire_effect_scale", 1.6)
	if player_ship.has_method("_update_fire_effect"):
		player_ship.call("_update_fire_effect")

	PreviewHarnessHelper.add_billboard_label(
		player_ship,
		"Fire VFX Preview",
		Vector3(0.0, 7.8, 0.0),
		Color(1.0, 0.74, 0.34, 1.0),
		34
	)
