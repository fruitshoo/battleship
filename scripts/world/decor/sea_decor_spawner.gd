extends Node

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")

const DEFAULT_DECOR_SCENES: Array[PackedScene] = [
	preload("res://scenes/world/decor/sea_rock_cluster.tscn"),
]

@export var decor_scenes: Array[PackedScene] = []
@export var enabled: bool = true
@export_range(0, 32, 1) var max_active_decor: int = 10
@export var initial_spawn_delay: float = 1.8
@export var spawn_interval: float = 6.5
@export var min_spawn_distance: float = 65.0
@export var max_spawn_distance: float = 135.0
@export var despawn_distance: float = 320.0
@export var min_ship_clearance: float = 38.0
@export var min_site_clearance: float = 42.0
@export var min_decor_spacing: float = 36.0
@export_range(0.0, 1.0, 0.05) var forward_spawn_bias: float = 0.78
@export_range(15.0, 180.0, 5.0) var forward_spawn_arc_degrees: float = 115.0
@export_range(1, 64, 1) var spawn_attempt_count: int = 24

var _timer: float = 0.0
var _active_decor: Array[Node3D] = []
var _player: Node3D = null


func _ready() -> void:
	_timer = initial_spawn_delay


func _process(delta: float) -> void:
	if not enabled or _env_flag_enabled("BATTLESHIP_DISABLE_SEA_DECOR"):
		return
	if not is_instance_valid(_player):
		_find_player()
		if not is_instance_valid(_player):
			return
	_cleanup_active_decor()
	if _active_decor.size() >= max_active_decor:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval * randf_range(0.72, 1.34)
		_spawn_decor_near_player()


func _find_player() -> void:
	for ship in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(ship):
			continue
		if ship.get("is_player_controlled") != null and ship.get("is_player_controlled") == true:
			_player = ship as Node3D
			return
		if str(ship.name) == "PlayerShip":
			_player = ship as Node3D
			return
	_player = null


func _spawn_decor_near_player() -> Node3D:
	if not is_instance_valid(_player):
		return null
	var spawn_pos := _pick_spawn_position()
	if spawn_pos == Vector3.INF:
		return null
	var decor_scene := _pick_decor_scene()
	if not is_instance_valid(decor_scene):
		return null
	var decor := decor_scene.instantiate() as Node3D
	if not is_instance_valid(decor):
		return null
	get_parent().add_child(decor)
	decor.global_position = spawn_pos
	decor.rotation.y = randf_range(0.0, TAU)
	var scale_jitter := randf_range(0.82, 1.22)
	decor.scale = Vector3.ONE * scale_jitter
	decor.add_to_group("sea_decor")
	_active_decor.append(decor)
	return decor


func _pick_spawn_position() -> Vector3:
	if not is_instance_valid(_player):
		return Vector3.INF
	var forward := _get_player_forward_flat()
	for _attempt in range(spawn_attempt_count):
		var angle := randf_range(-PI, PI)
		if randf() < forward_spawn_bias:
			angle = deg_to_rad(randf_range(-forward_spawn_arc_degrees, forward_spawn_arc_degrees))
		var direction := forward.rotated(Vector3.UP, angle).normalized()
		var distance := randf_range(min_spawn_distance, max_spawn_distance)
		var pos := _player.global_position + direction * distance
		pos.y = 0.0
		if _is_spawn_position_clear(pos):
			return pos
	return Vector3.INF


func _get_player_forward_flat() -> Vector3:
	if not is_instance_valid(_player):
		return Vector3.FORWARD
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		return Vector3.FORWARD
	return forward.normalized()


func _is_spawn_position_clear(pos: Vector3) -> bool:
	for ship_node in EntityRegistry.get_ships():
		var ship := ship_node as Node3D
		if not is_instance_valid(ship):
			continue
		var ship_pos := ship.global_position
		ship_pos.y = 0.0
		if ship_pos.distance_to(pos) < min_ship_clearance:
			return false
	for site_node in get_tree().get_nodes_in_group("sea_site"):
		var site := site_node as Node3D
		if not is_instance_valid(site):
			continue
		var site_pos := site.global_position
		site_pos.y = 0.0
		if site_pos.distance_to(pos) < min_site_clearance:
			return false
	for decor in _active_decor:
		if not is_instance_valid(decor):
			continue
		var decor_pos := decor.global_position
		decor_pos.y = 0.0
		if decor_pos.distance_to(pos) < min_decor_spacing:
			return false
	return true


func _cleanup_active_decor() -> void:
	for i in range(_active_decor.size() - 1, -1, -1):
		var decor := _active_decor[i]
		if not is_instance_valid(decor):
			_active_decor.remove_at(i)
			continue
		if is_instance_valid(_player):
			var decor_pos := decor.global_position
			var player_pos := _player.global_position
			decor_pos.y = 0.0
			player_pos.y = 0.0
			if decor_pos.distance_to(player_pos) > despawn_distance:
				decor.queue_free()
				_active_decor.remove_at(i)


func debug_spawn_decor(distance: float = 32.0, lateral: float = 0.0) -> Node3D:
	if not is_instance_valid(_player):
		_find_player()
	if not is_instance_valid(_player):
		return null
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var decor_scene := _pick_decor_scene()
	if not is_instance_valid(decor_scene):
		return null
	var decor := decor_scene.instantiate() as Node3D
	if not is_instance_valid(decor):
		return null
	get_parent().add_child(decor)
	decor.global_position = _player.global_position + forward * distance + right * lateral
	decor.global_position.y = 0.0
	decor.add_to_group("sea_decor")
	_active_decor.append(decor)
	return decor


func _pick_decor_scene() -> PackedScene:
	var scenes: Array = decor_scenes
	if scenes.is_empty():
		scenes = DEFAULT_DECOR_SCENES
	if scenes.is_empty():
		return null
	var decor_scene: Variant = scenes.pick_random()
	if decor_scene is PackedScene:
		return decor_scene as PackedScene
	return null


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
