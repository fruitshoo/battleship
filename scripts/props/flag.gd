@tool
extends Node3D

## Self-contained flag object.
## `flag.tscn` owns the pole and cloth. Variant scenes under `flags/` should mostly edit
## cloth-facing values: color, shape, size, and textures.

enum Shape {RECTANGLE, TRIANGLE, MASK, SWALLOWTAIL}
enum WindMode {FREE_ROTATE, FIXED_FLUTTER}

const MIN_AUTO_POLE_HEIGHT := 1.15
const POLE_HEIGHT_PER_FLAG_HEIGHT := 2.7

@export var flag_kind: String = "":
	set(value):
		flag_kind = value.strip_edges().to_lower()

@export_group("Cloth")
@export var color: Color = Color(0.9, 0.1, 0.1):
	set(value):
		color = value
		_update_material()

@export var flag_shape: Shape = Shape.RECTANGLE:
	set(value):
		flag_shape = value
		_update_material()

@export var flag_size: Vector2 = Vector2(1.5, 1.0):
	set(value):
		flag_size = Vector2(maxf(value.x, 0.05), maxf(value.y, 0.05))
		_update_dimensions()

@export var flag_texture: Texture2D:
	set(value):
		flag_texture = value
		_use_flag_texture = value != null
		_update_material()

@export var emblem_texture: Texture2D:
	set(value):
		emblem_texture = value
		_use_emblem_texture = value != null
		_update_material()

@export var emblem_color: Color = Color(1.0, 0.92, 0.55, 1.0):
	set(value):
		emblem_color = value
		_update_material()

@export_range(0.0, 1.0, 0.01) var emblem_strength: float = 1.0:
	set(value):
		emblem_strength = value
		_update_material()

@export_range(0.0, 0.5, 0.01) var swallowtail_depth: float = 0.24:
	set(value):
		swallowtail_depth = value
		_update_material()

@export_range(0.0, 0.8, 0.01) var swallowtail_gap: float = 0.42:
	set(value):
		swallowtail_gap = value
		_update_material()

@export_group("Wind")
@export var wind_mode: WindMode = WindMode.FREE_ROTATE

@export_range(0.0, 10.0, 0.1) var wave_speed: float = 5.0:
	set(value):
		wave_speed = value
		_update_material()

@export_range(0.0, 1.0, 0.01) var wave_strength: float = 0.25:
	set(value):
		wave_strength = value
		_update_material()

@export_range(0.0, 5.0, 0.05) var side_drag: float = 1.0:
	set(value):
		side_drag = value
		_update_material()

@onready var pole_mesh: MeshInstance3D = get_node_or_null("Pole") as MeshInstance3D
@onready var flag_mesh: MeshInstance3D = get_node_or_null("FlagMesh") as MeshInstance3D

var _use_flag_texture := false
var _use_emblem_texture := false
var _authored_cloth_transform := Transform3D.IDENTITY
var _has_authored_cloth_transform := false


func _ready() -> void:
	_capture_authored_cloth_transform()
	_update_dimensions()
	_update_material()


func set_team_color(team: String) -> void:
	color = Color(0.9, 0.1, 0.1) if team == "player" else Color(0.1, 0.1, 0.1)


func set_flag_kind(kind: String) -> void:
	flag_kind = kind


func get_flag_kind() -> String:
	return flag_kind


func set_flag_texture(next_texture: Texture2D) -> void:
	flag_texture = next_texture


func get_flag_texture() -> Texture2D:
	return flag_texture


func is_using_flag_texture() -> bool:
	return _use_flag_texture and flag_texture != null


func set_emblem_texture(next_texture: Texture2D) -> void:
	emblem_texture = next_texture


func get_flag_shape_name() -> String:
	match flag_shape:
		Shape.TRIANGLE:
			return "triangle"
		Shape.MASK:
			return "mask"
		Shape.SWALLOWTAIL:
			return "swallowtail"
		_:
			return "rectangle"


func get_wind_mode_name() -> String:
	match wind_mode:
		WindMode.FIXED_FLUTTER:
			return "fixed_flutter"
		_:
			return "free_rotate"


func has_visible_yard() -> bool:
	return false


func get_streamer_count() -> int:
	return 0


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cloth := _get_flag_mesh()
	if not is_instance_valid(cloth):
		return
	var wind_manager := get_node_or_null("/root/WindManager")
	if not is_instance_valid(wind_manager):
		return
	if not wind_manager.has_method("get_wind_strength"):
		return
	var wind_strength: float = float(wind_manager.get_wind_strength())
	if wind_mode == WindMode.FREE_ROTATE and wind_manager.has_method("get_wind_direction"):
		var wind_dir: Vector2 = wind_manager.get_wind_direction()
		var wind_3d := Vector3(wind_dir.x, 0.0, wind_dir.y).normalized()
		if wind_3d.length_squared() > 0.01:
			_apply_free_rotation(cloth, wind_3d)
	_apply_wave_instance_params(
		cloth,
		wave_speed * (0.75 + wind_strength),
		wave_strength * (0.4 + wind_strength * 0.8)
	)


func _update_dimensions() -> void:
	if not is_inside_tree():
		return
	var cloth := _get_flag_mesh()
	if is_instance_valid(cloth) and cloth.mesh is PlaneMesh:
		var plane_mesh := (cloth.mesh as PlaneMesh).duplicate() as PlaneMesh
		plane_mesh.size = flag_size
		cloth.mesh = plane_mesh
	var pole := _get_pole_mesh()
	if is_instance_valid(pole) and pole.mesh is CylinderMesh:
		var cylinder_mesh := (pole.mesh as CylinderMesh).duplicate() as CylinderMesh
		var pole_height := _get_auto_pole_height()
		cylinder_mesh.height = pole_height
		pole.mesh = cylinder_mesh
		pole.position.y = pole_height * 0.5


func _update_material() -> void:
	if not is_inside_tree():
		return
	var cloth := _get_flag_mesh()
	if not is_instance_valid(cloth):
		return
	var material := _ensure_flag_material(cloth)
	_configure_flag_material(material)
	cloth.set_instance_shader_parameter("albedo", color)
	cloth.set_instance_shader_parameter("is_triangular", flag_shape == Shape.TRIANGLE)
	cloth.set_instance_shader_parameter("is_swallowtail", flag_shape == Shape.SWALLOWTAIL)
	_apply_wave_instance_params(cloth, wave_speed, wave_strength)


func _configure_flag_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("flag_texture", flag_texture)
	material.set_shader_parameter("use_flag_texture", _use_flag_texture and flag_texture != null)
	material.set_shader_parameter("emblem_texture", emblem_texture)
	material.set_shader_parameter("use_emblem_texture", _use_emblem_texture and emblem_texture != null)
	material.set_shader_parameter("emblem_color", emblem_color)
	material.set_shader_parameter("emblem_strength", emblem_strength)
	material.set_shader_parameter("shape_mask_texture", null)
	material.set_shader_parameter("use_shape_mask", false)
	material.set_shader_parameter("attachment_edge", 0)
	material.set_shader_parameter("swallowtail_depth", swallowtail_depth)
	material.set_shader_parameter("swallowtail_gap", swallowtail_gap)
	material.set_shader_parameter("uv_scale", Vector2.ONE)
	material.set_shader_parameter("uv_offset", Vector2.ZERO)
	material.set_shader_parameter("flip_u", false)
	material.set_shader_parameter("flip_v", false)
	material.set_shader_parameter("wave_speed", wave_speed)
	material.set_shader_parameter("wave_strength", wave_strength)
	material.set_shader_parameter("side_drag", side_drag)


func _apply_wave_instance_params(mesh: MeshInstance3D, current_wave_speed: float, current_wave_strength: float) -> void:
	mesh.set_instance_shader_parameter("wave_speed", current_wave_speed)
	mesh.set_instance_shader_parameter("wave_strength", current_wave_strength)
	mesh.set_instance_shader_parameter("side_drag", side_drag)


func _apply_free_rotation(cloth: MeshInstance3D, wind_3d: Vector3) -> void:
	var target_basis := Basis.looking_at(wind_3d, Vector3.UP)
	var cloth_basis := target_basis * Basis(Vector3.UP, PI / 2.0)
	cloth.global_basis = cloth_basis * _get_authored_cloth_basis()
	cloth.global_position = global_transform * _get_authored_cloth_position() + wind_3d * (flag_size.x * 0.5)


func _ensure_flag_material(cloth: MeshInstance3D) -> ShaderMaterial:
	var active_mat := cloth.get_active_material(0)
	if active_mat is ShaderMaterial:
		var duplicated := (active_mat as ShaderMaterial).duplicate() as ShaderMaterial
		cloth.set_surface_override_material(0, duplicated)
		return duplicated
	var override_mat := cloth.get_surface_override_material(0)
	if override_mat is ShaderMaterial:
		return override_mat as ShaderMaterial
	return null


func _get_auto_pole_height() -> float:
	return maxf(MIN_AUTO_POLE_HEIGHT, flag_size.y * POLE_HEIGHT_PER_FLAG_HEIGHT)


func _capture_authored_cloth_transform() -> void:
	var cloth := _get_flag_mesh()
	if not is_instance_valid(cloth):
		return
	_authored_cloth_transform = cloth.transform
	_has_authored_cloth_transform = true


func _get_authored_cloth_position() -> Vector3:
	if _has_authored_cloth_transform:
		return _authored_cloth_transform.origin
	return Vector3(flag_size.x * 0.5, _get_auto_pole_height() - flag_size.y * 0.5, 0.0)


func _get_authored_cloth_basis() -> Basis:
	if _has_authored_cloth_transform:
		return _authored_cloth_transform.basis
	return Basis.IDENTITY


func _get_flag_mesh() -> MeshInstance3D:
	if is_instance_valid(flag_mesh):
		return flag_mesh
	flag_mesh = get_node_or_null("FlagMesh") as MeshInstance3D
	return flag_mesh


func _get_pole_mesh() -> MeshInstance3D:
	if is_instance_valid(pole_mesh):
		return pole_mesh
	pole_mesh = get_node_or_null("Pole") as MeshInstance3D
	return pole_mesh
