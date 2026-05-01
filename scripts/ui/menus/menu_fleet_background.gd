extends Node3D

@export var camera_target: Vector3 = Vector3(-1.1, 1.5, 0.0)
@export var camera_drift_degrees: float = 1.2
@export var bob_height: float = 0.08
@export var roll_degrees: float = 1.8
@export var pitch_degrees: float = 0.9

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var camera: Camera3D = $Camera3D
@onready var ocean: MeshInstance3D = $OceanPlane
@onready var fleet_root: Node3D = $Fleet

var _base_camera_position: Vector3
var _ship_base_transforms: Dictionary = {}
var _water_material: ShaderMaterial = null
var _menu_environment: Environment = null


func _ready() -> void:
	_base_camera_position = camera.position if is_instance_valid(camera) else Vector3.ZERO
	_cache_ship_transforms()
	_prepare_menu_environment()
	_prepare_camera_attributes()
	_prepare_ocean_material()
	set_process(true)


func _process(_delta: float) -> void:
	var time := Time.get_ticks_msec() * 0.001
	_update_camera(time)
	_update_fleet_bob(time)
	_update_ocean_focus()


func _cache_ship_transforms() -> void:
	if not is_instance_valid(fleet_root):
		return
	for child in fleet_root.get_children():
		if child is Node3D:
			_ship_base_transforms[child] = (child as Node3D).transform


func _prepare_ocean_material() -> void:
	if not is_instance_valid(ocean):
		return
	var material: Material = ocean.material_override
	if material == null and ocean.mesh != null:
		material = ocean.mesh.surface_get_material(0)
	if material is ShaderMaterial:
		_water_material = (material as ShaderMaterial).duplicate()
		ocean.material_override = _water_material
		_water_material.set_shader_parameter("sea_height", 0.42)
		_water_material.set_shader_parameter("sea_choppy", 3.2)
		_water_material.set_shader_parameter("sea_speed", 0.55)
		_water_material.set_shader_parameter("distance_haze_strength", 0.30)
		_water_material.set_shader_parameter("haze_radius", 140.0)


func _prepare_menu_environment() -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	_menu_environment = world_environment.environment.duplicate(true) as Environment
	world_environment.environment = _menu_environment
	if is_instance_valid(camera):
		camera.environment = _menu_environment
	_set_object_property_if_available(_menu_environment, "fog_enabled", true)
	_set_object_property_if_available(_menu_environment, "fog_light_color", Color(0.64, 0.76, 0.84, 1.0))
	_set_object_property_if_available(_menu_environment, "fog_sun_scatter", 0.22)
	_set_object_property_if_available(_menu_environment, "fog_density", 0.0062)
	_set_object_property_if_available(_menu_environment, "fog_sky_affect", 0.44)
	_set_object_property_if_available(_menu_environment, "fog_depth_begin", 18.0)
	_set_object_property_if_available(_menu_environment, "fog_depth_end", 92.0)
	_set_object_property_if_available(_menu_environment, "glow_strength", 0.24)
	_set_object_property_if_available(_menu_environment, "adjustment_enabled", true)
	_set_object_property_if_available(_menu_environment, "adjustment_brightness", 0.96)
	_set_object_property_if_available(_menu_environment, "adjustment_contrast", 0.88)
	_set_object_property_if_available(_menu_environment, "adjustment_saturation", 0.86)


func _prepare_camera_attributes() -> void:
	if not is_instance_valid(camera):
		return
	var attributes := CameraAttributesPhysical.new()
	_set_object_property_if_available(attributes, "frustum_focus_distance", 20.0)
	_set_object_property_if_available(attributes, "frustum_focus_width", 9.5)
	_set_object_property_if_available(attributes, "dof_blur_far_enabled", true)
	_set_object_property_if_available(attributes, "dof_blur_far_distance", 24.0)
	_set_object_property_if_available(attributes, "dof_blur_far_transition", 18.0)
	_set_object_property_if_available(attributes, "dof_blur_amount", 0.08)
	camera.attributes = attributes


func _set_object_property_if_available(target: Object, property_name: StringName, value: Variant) -> void:
	if target == null:
		return
	for property in target.get_property_list():
		if property.get("name", "") == property_name:
			target.set(property_name, value)
			return


func _update_camera(time: float) -> void:
	if not is_instance_valid(camera):
		return
	var drift := Vector3(
		sin(time * 0.16) * 0.22,
		cos(time * 0.13) * 0.05,
		cos(time * 0.11) * 0.16
	)
	camera.position = _base_camera_position + drift
	var target := camera_target + Vector3(sin(time * 0.10) * 0.18, cos(time * 0.14) * 0.04, 0.0)
	camera.look_at(target, Vector3.UP)
	camera.rotation_degrees.z = sin(time * 0.12) * camera_drift_degrees


func _update_fleet_bob(time: float) -> void:
	for ship_node in _ship_base_transforms.keys():
		if not is_instance_valid(ship_node):
			continue
		var ship := ship_node as Node3D
		var base_transform: Transform3D = _ship_base_transforms[ship_node]
		var phase := float(ship.get_instance_id() % 37) * 0.17
		ship.transform = base_transform
		ship.position.y += sin(time * 0.72 + phase) * bob_height
		ship.rotation_degrees.x += sin(time * 0.54 + phase) * pitch_degrees
		ship.rotation_degrees.z += cos(time * 0.62 + phase) * roll_degrees


func _update_ocean_focus() -> void:
	if _water_material == null:
		return
	_water_material.set_shader_parameter("player_center_ws", Vector3.ZERO)
