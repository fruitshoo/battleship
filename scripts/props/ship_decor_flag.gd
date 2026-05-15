@tool
extends Node3D

enum WindMode { FREE_ROTATE, FIXED_FLUTTER }
enum PinMode { LEFT, TOP, LEFT_AND_TOP }

@export var flag_kind: String = "":
	set(value):
		flag_kind = value.strip_edges().to_lower()
@export var color: Color = Color(0.86, 0.72, 0.38, 1.0):
	set(value):
		color = value
		_apply_material_settings()
@export var shape_name: String = "mask":
	set(value):
		shape_name = value.strip_edges().to_lower()
@export var flag_texture: Texture2D:
	set(value):
		flag_texture = value
		_use_flag_texture = value != null
		_apply_material_settings()
@export var wind_mode: WindMode = WindMode.FREE_ROTATE:
	set(value):
		wind_mode = value
		free_rotate_with_wind = value == WindMode.FREE_ROTATE
@export_range(0.0, 10.0, 0.1) var wave_speed: float = 4.2:
	set(value):
		wave_speed = value
		_apply_material_settings()
@export_range(0.0, 1.0, 0.01) var wave_strength: float = 0.13:
	set(value):
		wave_strength = value
		_apply_material_settings()
@export_range(0.0, 1.0, 0.01) var side_drag: float = 0.08:
	set(value):
		side_drag = value
		_apply_material_settings()
@export var pin_mode: PinMode = PinMode.LEFT:
	set(value):
		pin_mode = value
		_apply_material_settings()
@export_range(0.02, 1.0, 0.01) var wind_update_interval: float = 0.15
@export_range(1.0, 20.0, 0.5) var wind_turn_speed: float = 8.0
@export var free_rotate_with_wind: bool = true

@onready var panel: MeshInstance3D = get_node_or_null("Panel") as MeshInstance3D

var _authored_panel_transform := Transform3D.IDENTITY
var _authored_cloth_size := Vector2.ONE
var _has_authored_panel_transform := false
var _cached_wind_manager: Node = null
var _wind_update_left: float = 0.0
var _target_wind_3d := Vector3.ZERO
var _current_wind_3d := Vector3.ZERO
var _use_flag_texture := false


func _ready() -> void:
	_capture_authored_panel_transform()
	_capture_authored_material_settings()
	_apply_material_settings()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or wind_mode != WindMode.FREE_ROTATE or not free_rotate_with_wind:
		return
	_wind_update_left -= delta
	if _wind_update_left <= 0.0:
		_wind_update_left = maxf(wind_update_interval, 0.02)
		_update_target_wind_direction()
	_update_wind_rotation(delta)


func _capture_authored_panel_transform() -> void:
	var cloth := _get_panel()
	if not is_instance_valid(cloth):
		return
	_authored_panel_transform = cloth.transform
	if cloth.mesh is PlaneMesh:
		_authored_cloth_size = (cloth.mesh as PlaneMesh).size
	_has_authored_panel_transform = true


func _capture_authored_material_settings() -> void:
	var cloth := _get_panel()
	if not is_instance_valid(cloth):
		return
	var material := _ensure_panel_material(cloth)
	if material == null:
		return
	var authored_color = material.get_shader_parameter("base_color")
	if authored_color is Color:
		color = authored_color
	var authored_flag_texture = material.get_shader_parameter("flag_texture")
	if authored_flag_texture is Texture2D:
		flag_texture = authored_flag_texture
	var authored_use_flag_texture = material.get_shader_parameter("use_flag_texture")
	_use_flag_texture = bool(authored_use_flag_texture) and flag_texture != null
	var authored_wave_speed = material.get_shader_parameter("wave_speed")
	if authored_wave_speed != null:
		wave_speed = float(authored_wave_speed)
	var authored_wave_strength = material.get_shader_parameter("wave_strength")
	if authored_wave_strength != null:
		wave_strength = float(authored_wave_strength)
	var authored_side_drag = material.get_shader_parameter("side_drag")
	if authored_side_drag != null:
		side_drag = float(authored_side_drag)
	var authored_pin_mode = material.get_shader_parameter("pin_mode")
	if authored_pin_mode != null:
		pin_mode = int(authored_pin_mode) as PinMode


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


func get_flag_shape_name() -> String:
	return shape_name if not shape_name.is_empty() else "mask"


func get_wind_mode_name() -> String:
	match wind_mode:
		WindMode.FIXED_FLUTTER:
			return "fixed_flutter"
		_:
			return "free_rotate"


func has_visible_yard() -> bool:
	return has_node("HorizontalRod")


func get_streamer_count() -> int:
	return 0


func _apply_material_settings() -> void:
	if not is_inside_tree():
		return
	var cloth := _get_panel()
	if not is_instance_valid(cloth):
		return
	var material := _ensure_panel_material(cloth)
	if material == null:
		return
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("flag_texture", flag_texture)
	material.set_shader_parameter("use_flag_texture", _use_flag_texture and flag_texture != null)
	material.set_shader_parameter("wave_speed", wave_speed)
	material.set_shader_parameter("wave_strength", wave_strength)
	material.set_shader_parameter("side_drag", side_drag)
	material.set_shader_parameter("pin_mode", int(pin_mode))


func _ensure_panel_material(cloth: MeshInstance3D) -> ShaderMaterial:
	var override_mat := cloth.get_surface_override_material(0)
	if override_mat is ShaderMaterial:
		return override_mat as ShaderMaterial
	var active_mat := cloth.get_active_material(0)
	if active_mat is ShaderMaterial:
		var duplicated := (active_mat as ShaderMaterial).duplicate() as ShaderMaterial
		cloth.set_surface_override_material(0, duplicated)
		return duplicated
	return null


func _update_target_wind_direction() -> void:
	var wind_manager := _get_wind_manager()
	if not is_instance_valid(wind_manager) or not wind_manager.has_method("get_wind_direction"):
		return
	var wind_dir: Vector2 = wind_manager.get_wind_direction()
	var wind_3d := Vector3(wind_dir.x, 0.0, wind_dir.y).normalized()
	if wind_3d.length_squared() <= 0.01:
		return
	_target_wind_3d = wind_3d
	if _current_wind_3d.length_squared() <= 0.01:
		_current_wind_3d = _target_wind_3d


func _update_wind_rotation(delta: float) -> void:
	var cloth := _get_panel()
	if not is_instance_valid(cloth):
		return
	if _target_wind_3d.length_squared() <= 0.01:
		return
	var turn_alpha := clampf(wind_turn_speed * delta, 0.0, 1.0)
	_current_wind_3d = _current_wind_3d.slerp(_target_wind_3d, turn_alpha).normalized()
	_apply_free_rotation(cloth, _current_wind_3d)


func _apply_free_rotation(cloth: MeshInstance3D, wind_3d: Vector3) -> void:
	var authored_pos := _get_authored_panel_position()
	var attach_height := authored_pos.y
	var root_scale := global_transform.basis.get_scale().abs()
	var horizontal_scale := maxf(root_scale.x, root_scale.z)
	var center_offset := maxf(_authored_cloth_size.x * horizontal_scale, 0.05) * 0.5
	var target_basis := Basis.looking_at(wind_3d, Vector3.UP)
	var cloth_basis := target_basis * Basis(Vector3.UP, PI / 2.0)
	cloth.global_basis = (cloth_basis * _get_authored_panel_basis()).scaled(root_scale)
	cloth.global_position = global_transform * Vector3(0.0, attach_height, 0.0) + wind_3d * center_offset


func _get_authored_panel_position() -> Vector3:
	if _has_authored_panel_transform:
		return _authored_panel_transform.origin
	return Vector3(_authored_cloth_size.x * 0.5, _authored_cloth_size.y * 1.5, 0.0)


func _get_authored_panel_basis() -> Basis:
	if _has_authored_panel_transform:
		return _authored_panel_transform.basis
	return Basis.IDENTITY


func _get_panel() -> MeshInstance3D:
	if is_instance_valid(panel):
		return panel
	panel = get_node_or_null("Panel") as MeshInstance3D
	return panel


func _get_wind_manager() -> Node:
	if is_instance_valid(_cached_wind_manager):
		return _cached_wind_manager
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	return _cached_wind_manager
