extends Node3D

const PLAYER_SHIP_SCENE = preload("res://scenes/ships/player_ship.tscn")

@export var auto_quit_delay_seconds: float = 0.05


func _ready() -> void:
	var ship := PLAYER_SHIP_SCENE.instantiate()
	_strip_probe_components(ship)
	add_child(ship)
	call_deferred("_quit_after_probe")


func _strip_probe_components(ship: Node3D) -> void:
	if _env_flag_enabled("BATTLESHIP_PROBE_STRIP_SOLDIERS"):
		_free_child_by_name(ship, "Soldiers")
	if _env_flag_enabled("BATTLESHIP_PROBE_STRIP_WAKE"):
		_free_child_by_name(ship, "WakeTrail")
	if _env_flag_enabled("BATTLESHIP_PROBE_STRIP_HULL"):
		for child in ship.get_children():
			if child is Node and str(child.name).contains("Hull"):
				ship.remove_child(child)
				child.free()


func _free_child_by_name(parent: Node, child_name: String) -> void:
	var child := parent.get_node_or_null(child_name)
	if not is_instance_valid(child):
		return
	parent.remove_child(child)
	child.free()


func _quit_after_probe() -> void:
	if auto_quit_delay_seconds > 0.0:
		await get_tree().create_timer(auto_quit_delay_seconds).timeout
	get_tree().quit(0)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
