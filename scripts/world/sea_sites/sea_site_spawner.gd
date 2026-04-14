extends Node

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")

const DEFAULT_STATIC_SITE_SCENES: Array[PackedScene] = [
	preload("res://scenes/world/sea_sites/reef_marker_site.tscn"),
	preload("res://scenes/world/sea_sites/tiny_islet_site.tscn"),
	preload("res://scenes/world/sea_sites/temporary_outpost_site.tscn"),
]

@export var drifting_supply_site_scene: PackedScene = preload("res://scenes/world/sea_sites/drifting_supply_site.tscn")
@export var static_site_scenes: Array[PackedScene] = []
@export var enabled: bool = true
@export var max_active_sites: int = 2
@export var initial_spawn_delay: float = 18.0
@export var spawn_interval: float = 70.0
@export var min_spawn_distance: float = 70.0
@export var max_spawn_distance: float = 125.0
@export var despawn_distance: float = 190.0
@export var min_ship_clearance: float = 24.0
@export var wind_spawn_bias_enabled: bool = true
@export_range(-1.0, 1.0, 0.05) var min_spawn_wind_alignment: float = -0.35
@export_range(1, 64, 1) var wind_bias_relax_attempts: int = 10
@export_range(1, 64, 1) var spawn_attempt_count: int = 18

var _timer: float = 0.0
var _active_sites: Array[Node3D] = []
var _player: Node3D = null


func _ready() -> void:
	_timer = initial_spawn_delay


func _process(delta: float) -> void:
	if not enabled or _env_flag_enabled("BATTLESHIP_DISABLE_SEA_BONUS"):
		return
	if not is_instance_valid(_player):
		_find_player()
		if not is_instance_valid(_player):
			return
	_cleanup_active_sites()
	if _active_sites.size() >= max_active_sites:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval * randf_range(0.82, 1.28)
		_spawn_site_near_player()


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


func _spawn_site_near_player() -> Node3D:
	if not is_instance_valid(_player):
		return null
	var spawn_pos := _pick_spawn_position()
	if spawn_pos == Vector3.INF:
		return null
	var site_scene := _pick_site_scene()
	if not is_instance_valid(site_scene):
		return null
	var site := site_scene.instantiate() as Node3D
	if not is_instance_valid(site):
		return null
	get_parent().add_child(site)
	site.global_position = spawn_pos
	site.rotation.y = randf_range(0.0, TAU)
	_active_sites.append(site)
	return site


func _pick_spawn_position() -> Vector3:
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var wind_dir := _get_wind_direction_flat()
	var fallback_pos := Vector3.INF

	for attempt in range(spawn_attempt_count):
		var angle := randf_range(-PI, PI)
		if randf() < 0.65:
			angle = randf_range(-PI * 0.75, PI * 0.75)
		var direction := forward.rotated(Vector3.UP, angle).normalized()
		var distance := randf_range(min_spawn_distance, max_spawn_distance)
		var pos := _player.global_position + direction * distance
		pos.y = 0.0
		if _is_spawn_position_clear(pos):
			if fallback_pos == Vector3.INF:
				fallback_pos = pos
			if _is_spawn_direction_wind_friendly(direction, wind_dir, attempt):
				return pos
	return fallback_pos


func _get_wind_direction_flat() -> Vector3:
	if not wind_spawn_bias_enabled:
		return Vector3.ZERO
	var wind_manager := get_node_or_null("/root/WindManager")
	if not is_instance_valid(wind_manager) or not wind_manager.has_method("get_wind_direction"):
		return Vector3.ZERO
	var wind_2d: Vector2 = wind_manager.call("get_wind_direction")
	if wind_2d.length_squared() <= 0.001:
		return Vector3.ZERO
	return Vector3(wind_2d.x, 0.0, wind_2d.y).normalized()


func _is_spawn_direction_wind_friendly(direction: Vector3, wind_dir: Vector3, attempt: int) -> bool:
	if not wind_spawn_bias_enabled or wind_dir.length_squared() <= 0.001:
		return true
	if attempt >= wind_bias_relax_attempts:
		return true
	var flat_dir := direction
	flat_dir.y = 0.0
	if flat_dir.length_squared() <= 0.001:
		return true
	return flat_dir.normalized().dot(wind_dir.normalized()) >= min_spawn_wind_alignment


func _is_spawn_position_clear(pos: Vector3) -> bool:
	for ship_node in EntityRegistry.get_ships():
		var ship := ship_node as Node3D
		if not is_instance_valid(ship):
			continue
		var ship_pos: Vector3 = ship.global_position
		ship_pos.y = 0.0
		if ship_pos.distance_to(pos) < min_ship_clearance:
			return false
	for site in _active_sites:
		if not is_instance_valid(site):
			continue
		var site_pos := site.global_position
		site_pos.y = 0.0
		if site_pos.distance_to(pos) < min_spawn_distance * 0.65:
			return false
	return true


func _cleanup_active_sites() -> void:
	for i in range(_active_sites.size() - 1, -1, -1):
		var site := _active_sites[i]
		if not is_instance_valid(site):
			_active_sites.remove_at(i)
			continue
		if is_instance_valid(_player):
			var site_pos := site.global_position
			var player_pos := _player.global_position
			site_pos.y = 0.0
			player_pos.y = 0.0
			if site_pos.distance_to(player_pos) > despawn_distance:
				site.queue_free()
				_active_sites.remove_at(i)


func debug_spawn_site(distance: float = 24.0, lateral: float = 0.0) -> Node3D:
	if not is_instance_valid(_player):
		_find_player()
	if not is_instance_valid(_player):
		return null
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var site_scene := _pick_site_scene()
	if not is_instance_valid(site_scene):
		return null
	var site := site_scene.instantiate() as Node3D
	if not is_instance_valid(site):
		return null
	get_parent().add_child(site)
	site.global_position = _player.global_position + forward * distance + right * lateral
	site.global_position.y = 0.0
	_active_sites.append(site)
	return site


func debug_spawn_cache(distance: float = 24.0, lateral: float = 0.0) -> Node3D:
	return debug_spawn_site(distance, lateral)


func _pick_site_scene() -> PackedScene:
	var scenes: Array = static_site_scenes
	if scenes.is_empty():
		scenes = DEFAULT_STATIC_SITE_SCENES
	if scenes.is_empty():
		return drifting_supply_site_scene
	var site_scene: Variant = scenes.pick_random()
	if site_scene is PackedScene:
		return site_scene as PackedScene
	return drifting_supply_site_scene


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
