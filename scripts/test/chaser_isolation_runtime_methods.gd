@tool
extends "res://scripts/entities/ships/base_ship.gd"


@export var team: String = "enemy"
@export var move_speed: float = 3.5
@export var soldier_scene: PackedScene
@export var cannon_scene: PackedScene
@export var hull_scene: PackedScene
@export var preferred_soldier_type: String = "general"
enum CombatRole {CHARGER, GUNNER}
@export var combat_role: CombatRole = CombatRole.CHARGER
@export_range(4.0, 30.0) var preferred_combat_range: float = 14.0
@export_range(0.5, 8.0) var combat_range_tolerance: float = 2.5
@export_range(2.0, 20.0) var retreat_distance: float = 8.0
@export var allow_boarding: bool = true
@export var formation_role_name: String = ""
@export var ship_type: String = "sekibune_melee"
var has_cannons: bool = true
var target: Node3D = null
var fire_pot_scene: PackedScene = null
var cached_lm: Node = null
var _cached_wind_manager: Node = null


func _update_editor_hull() -> void:
	var type_lower = ship_type.to_lower()
	var h_path = "res://scenes/ships/hulls/sekibune_hull.tscn"
	if type_lower.contains("kobayabune"):
		h_path = "res://scenes/ships/hulls/kobayabune_hull.tscn"
	elif type_lower.contains("panokseon"):
		h_path = "res://scenes/ships/hulls/panok_hull.tscn"
	elif type_lower.contains("atakebune"):
		h_path = "res://scenes/ships/hulls/atakebune_hull.tscn"
	elif type_lower.contains("maengseon"):
		h_path = "res://scenes/ships/hulls/maengseon_hull.tscn"
	var new_hull = load(h_path)
	if new_hull:
		var inst = new_hull.instantiate()
		inst.name = "EditorHull"
		add_child(inst)
		_cache_hull_references(self)


func _ready() -> void:
	_apply_default_combat_profile_for_ship_type()
	if Engine.is_editor_hint():
		return
	var stats := load_ship_stats(ship_type)
	if not stats.is_empty():
		if stats.has("hull_hp"):
			max_hull_hp = stats["hull_hp"]
	_apply_formation_role_profile()
	var runtime_hull_scene: PackedScene = hull_scene
	var type_lower := ship_type.to_lower()
	if type_lower.contains("kobayabune"):
		runtime_hull_scene = load("res://scenes/ships/hulls/kobayabune_hull.tscn")
	elif type_lower.contains("atakebune"):
		runtime_hull_scene = load("res://scenes/ships/hulls/atakebune_hull.tscn")
	elif type_lower.contains("sekibune"):
		runtime_hull_scene = load("res://scenes/ships/hulls/sekibune_hull.tscn")
	elif type_lower.contains("panokseon"):
		runtime_hull_scene = load("res://scenes/ships/hulls/panok_hull.tscn")
	elif type_lower.contains("maengseon"):
		runtime_hull_scene = load("res://scenes/ships/hulls/maengseon_hull.tscn")
	if is_instance_valid(runtime_hull_scene):
		var hull_inst = runtime_hull_scene.instantiate()
		add_child(hull_inst)
	super._ready()
	_find_player()
	if not has_cannons:
		_remove_all_cannons()
	add_to_group("ships")
	set_team(team)
	_setup_soldiers()
	_find_player()
	cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	_sync_contact_area_layers()
	_set_contact_areas_enabled(true)
	_configure_ai_logic_throttle()


func _setup_soldiers() -> void:
	if not soldier_scene:
		return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node:
		return
	for child in soldiers_node.get_children():
		child.queue_free()
	for _i in range(4):
		_spawn_one_soldier(team)


func _spawn_one_soldier(s_team: String, _soldier_type_override: String = "") -> void:
	var s = soldier_scene.instantiate()
	$Soldiers.add_child(s)
	s.set_team(s_team)


func _equip_minion_cannons() -> void:
	if not cannon_scene:
		return
	_remove_all_cannons()
	for i in range(3):
		var cannon = cannon_scene.instantiate()
		cannon.name = "FleetCannon_" + str(i)
		add_child(cannon)


func _remove_all_cannons() -> void:
	pass


func _find_player() -> void:
	pass


func _apply_default_combat_profile_for_ship_type() -> void:
	pass


func _apply_formation_role_profile() -> void:
	pass


func _set_contact_areas_enabled(_enabled: bool = true) -> void:
	pass


func _sync_contact_area_layers(_layer_override: int = -1) -> void:
	pass


func _configure_ai_logic_throttle() -> void:
	pass
