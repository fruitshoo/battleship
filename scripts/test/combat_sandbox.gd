extends Node3D

const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")

@export var auto_open_debug_panel: bool = true
@export var auto_enable_distance_debug: bool = false
@export var stop_regular_spawns: bool = true
@export var spawn_light_fleet_on_start: bool = false
@export var spawn_mixed_fleet_on_start: bool = false
@export var spawn_heavy_fleet_on_start: bool = false


func _ready() -> void:
	call_deferred("_configure_sandbox")


func _configure_sandbox() -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if is_instance_valid(hud):
		if auto_open_debug_panel and hud.get("sail_debug_panel") != null:
			var panel: Variant = hud.get("sail_debug_panel")
			if panel is Control:
				panel.visible = true
				if hud.has_method("_update_sail_debug_toggle_button_text"):
					hud.call("_update_sail_debug_toggle_button_text")
				if hud.has_method("_sync_debug_tools_panel_state"):
					hud.call("_sync_debug_tools_panel_state")
		if auto_enable_distance_debug and hud.has_method("_toggle_distance_debug"):
			if not DistanceDebugVisualizer.runtime_enabled:
				hud.call("_toggle_distance_debug")

	var level_manager: Node = LevelManagerRegistry.get_level_manager(get_tree())
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
		if spawn_light_fleet_on_start and spawner.has_method("debug_spawn_fleet"):
			spawner.call("debug_spawn_fleet", "light")
		if spawn_mixed_fleet_on_start and spawner.has_method("debug_spawn_fleet"):
			spawner.call("debug_spawn_fleet", "mixed")
		if spawn_heavy_fleet_on_start and spawner.has_method("debug_spawn_fleet"):
			spawner.call("debug_spawn_fleet", "heavy")
