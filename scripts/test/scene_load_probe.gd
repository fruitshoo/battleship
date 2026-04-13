extends Node

@export var auto_quit_delay_seconds: float = 0.05


func _ready() -> void:
	auto_quit_delay_seconds = _get_auto_quit_delay_seconds(auto_quit_delay_seconds)
	var scene_path := _get_probe_scene_path()
	var loaded_resource: Resource = load(scene_path)
	if loaded_resource == null:
		push_error("SceneLoadProbe failed to load %s" % scene_path)
		get_tree().quit(1)
		return
	if _should_instantiate() and loaded_resource is PackedScene:
		var instance := (loaded_resource as PackedScene).instantiate()
		add_child(instance)
	call_deferred("_quit_after_probe")


func _get_probe_scene_path() -> String:
	var value := OS.get_environment("BATTLESHIP_PROBE_SCENE_PATH").strip_edges()
	if value.is_empty():
		return "res://scenes/ships/player_ship.tscn"
	return value


func _should_instantiate() -> bool:
	return _env_flag_enabled("BATTLESHIP_PROBE_INSTANTIATE")


func _quit_after_probe() -> void:
	if auto_quit_delay_seconds > 0.0:
		await get_tree().create_timer(auto_quit_delay_seconds).timeout
	get_tree().quit(0)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"


func _get_auto_quit_delay_seconds(default_value: float) -> float:
	var value := OS.get_environment("BATTLESHIP_PROBE_AUTO_QUIT_DELAY").strip_edges()
	if value.is_empty():
		return default_value
	return maxf(0.0, value.to_float())
