extends Node3D

const ROCK_SHADER := preload("res://assets/shaders/sea_rock_procedural.gdshader")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

@export var hazard_enabled: bool = true
@export_range(2.0, 18.0, 0.25) var hazard_radius: float = 6.4
@export_range(1.0, 8.0, 0.25) var hazard_height: float = 4.0
@export_range(0.0, 40.0, 0.5) var contact_damage: float = 7.0
@export_range(0.1, 4.0, 0.05) var damage_cooldown: float = 1.2
@export_range(0.0, 14.0, 0.25) var push_strength: float = 5.5
@export_range(0.0, 12.0, 0.25) var speed_drag_per_second: float = 4.0

var _rock_meshes: Array[MeshInstance3D] = []
var _warm_material: ShaderMaterial = null
var _cool_material: ShaderMaterial = null
var _hazard_area: Area3D = null
var _damage_cooldowns: Dictionary = {}


func _ready() -> void:
	_build_procedural_materials()
	_collect_rock_meshes(self)
	_apply_procedural_materials()
	_setup_hazard_area()
	set_physics_process(hazard_enabled)


func set_rock_view_fade_alpha(_alpha: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_physics_process(delta)
	PhysicsFrameProfiler.end("sea_rock_physics", profile_start)


func _profiled_physics_process(delta: float) -> void:
	if not hazard_enabled or not is_instance_valid(_hazard_area):
		return
	_tick_damage_cooldowns(delta)
	var ships := {}
	for area in _hazard_area.get_overlapping_areas():
		var ship := _resolve_ship_from_area(area)
		if is_instance_valid(ship):
			ships[ship.get_instance_id()] = ship
	for ship in ships.values():
		_apply_soft_contact(ship as Node3D, delta)


func _collect_rock_meshes(root: Node) -> void:
	if root is MeshInstance3D:
		_rock_meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_rock_meshes(child)


func _build_procedural_materials() -> void:
	_warm_material = ShaderMaterial.new()
	_warm_material.shader = ROCK_SHADER
	_warm_material.set_shader_parameter("rock_dark", Color(0.08, 0.1, 0.085, 1.0))
	_warm_material.set_shader_parameter("rock_mid", Color(0.2, 0.22, 0.18, 1.0))
	_warm_material.set_shader_parameter("pattern_scale", 1.05)
	_warm_material.set_shader_parameter("wet_darkening", 0.34)
	_warm_material.set_shader_parameter("roughness_value", 0.94)

	_cool_material = ShaderMaterial.new()
	_cool_material.shader = ROCK_SHADER
	_cool_material.set_shader_parameter("rock_dark", Color(0.07, 0.095, 0.095, 1.0))
	_cool_material.set_shader_parameter("rock_mid", Color(0.17, 0.21, 0.2, 1.0))
	_cool_material.set_shader_parameter("pattern_scale", 1.25)
	_cool_material.set_shader_parameter("wet_darkening", 0.38)
	_cool_material.set_shader_parameter("roughness_value", 0.96)


func _apply_procedural_materials() -> void:
	for mesh in _rock_meshes:
		if not is_instance_valid(mesh):
			continue
		mesh.material_override = _cool_material if _uses_cool_material(mesh) else _warm_material


func _uses_cool_material(mesh: MeshInstance3D) -> bool:
	var mesh_name := mesh.name.to_lower()
	return mesh_name.contains("spire") or mesh_name == "submergedbaseb"


func _setup_hazard_area() -> void:
	if not hazard_enabled or is_instance_valid(_hazard_area):
		return
	_hazard_area = Area3D.new()
	_hazard_area.name = "RockHazardArea"
	_hazard_area.monitoring = true
	_hazard_area.monitorable = false
	_hazard_area.collision_layer = 0
	_hazard_area.collision_mask = 2 | 4
	add_child(_hazard_area)

	var shape := CollisionShape3D.new()
	shape.name = "RockHazardShape"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = hazard_radius
	cylinder.height = hazard_height
	shape.shape = cylinder
	shape.position.y = hazard_height * 0.5 - 0.25
	_hazard_area.add_child(shape)


func _tick_damage_cooldowns(delta: float) -> void:
	var expired: Array[int] = []
	for ship_id_variant in _damage_cooldowns.keys():
		var ship_id := int(ship_id_variant)
		var remaining := float(_damage_cooldowns.get(ship_id, 0.0)) - delta
		if remaining <= 0.0:
			expired.append(ship_id)
		else:
			_damage_cooldowns[ship_id] = remaining
	for ship_id in expired:
		_damage_cooldowns.erase(ship_id)


func _resolve_ship_from_area(area: Area3D) -> Node3D:
	if not is_instance_valid(area):
		return null
	if not area.is_in_group("ship_hitbox") and not area.is_in_group("ship_proximity"):
		return null
	var parent := area.get_parent()
	if parent is Node3D and parent.has_method("take_damage"):
		return parent as Node3D
	return null


func _apply_soft_contact(ship: Node3D, delta: float) -> void:
	if not is_instance_valid(ship) or not ship.is_inside_tree():
		return
	if ship.get("is_sinking") == true or ship.get("is_dying") == true:
		return
	var away := ship.global_position - global_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = -ship.global_transform.basis.z
		away.y = 0.0
	var dir := away.normalized() if away.length_squared() > 0.001 else Vector3.FORWARD
	var effective_radius := _get_effective_hazard_radius()
	var distance := maxf(0.01, away.length())
	var contact_weight := clampf(1.0 - distance / maxf(effective_radius, 0.01), 0.15, 1.0)

	var push := dir * push_strength * contact_weight * delta
	ship.global_position += push
	if ship.get("base_y") != null:
		ship.global_position.y = float(ship.get("base_y"))

	if ship.get("current_speed") != null:
		var current_speed := float(ship.get("current_speed"))
		ship.set("current_speed", maxf(0.0, current_speed - speed_drag_per_second * contact_weight * delta))

	var ship_id := ship.get_instance_id()
	if _damage_cooldowns.has(ship_id):
		return
	_damage_cooldowns[ship_id] = damage_cooldown
	if contact_damage > 0.0 and ship.has_method("take_damage"):
		ship.call("take_damage", contact_damage, ship.global_position, "rock")
	if ship.has_method("_flash_damage"):
		ship.call("_flash_damage", contact_damage)


func _get_effective_hazard_radius() -> float:
	var scale := global_transform.basis.get_scale()
	return hazard_radius * maxf(maxf(absf(scale.x), absf(scale.z)), 0.01)
