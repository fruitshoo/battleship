@tool
extends Node3D
class_name DeckAreaAuthoring

const HANDLE_NAME := "__DeckAreaEditableSurface"
const HANDLE_META := "deck_area_authoring_handle"
const POINTS_NAME := "Points"
const DEFAULT_POINTS := [
	Vector3(-0.28, 0.0, -1.0),
	Vector3(0.28, 0.0, -1.0),
	Vector3(1.0, 0.0, -0.48),
	Vector3(1.0, 0.0, 0.48),
	Vector3(0.28, 0.0, 1.0),
	Vector3(-0.28, 0.0, 1.0),
	Vector3(-1.0, 0.0, 0.48),
	Vector3(-1.0, 0.0, -0.48),
]

@export var show_editor_surface := true:
	set(value):
		show_editor_surface = value
		_refresh_handle_deferred()
@export var create_points_from_shape := false:
	set(value):
		create_points_from_shape = false
		if value:
			_create_points_from_current_shape()
			_refresh_handle_deferred()
@export_range(0.12, 0.65, 0.01) var editor_alpha := 0.34:
	set(value):
		editor_alpha = value
		_material = null
		_refresh_handle_deferred()
@export_range(0.0, 0.16, 0.01) var editor_lift := 0.04:
	set(value):
		editor_lift = value
		_refresh_handle_deferred()

var _refresh_queued := false
var _refresh_timer := 0.0
var _visualizer_visible := true
var _mesh: ArrayMesh = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		_remove_handle()
		set_process(false)
		return
	set_process(true)
	_refresh_handle_deferred()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_refresh_handle_deferred()


func _exit_tree() -> void:
	_remove_handle()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_refresh_timer += delta
	if _refresh_timer >= 0.25:
		_refresh_timer = 0.0
		_refresh_handle()


func set_editor_deck_visual_visible(visible: bool) -> void:
	_visualizer_visible = visible
	_refresh_handle_deferred()


func _refresh_handle_deferred() -> void:
	if not Engine.is_editor_hint() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_handle")


func _refresh_handle() -> void:
	_refresh_queued = false
	if not Engine.is_editor_hint():
		_remove_handle()
		return
	var handle := _ensure_handle()
	handle.mesh = _build_mesh()
	handle.material_override = _get_material()
	handle.position = Vector3.UP * editor_lift
	handle.rotation = Vector3.ZERO
	handle.scale = Vector3.ONE
	handle.visible = show_editor_surface and _visualizer_visible and _is_configured()


func _ensure_handle() -> MeshInstance3D:
	var handle := get_node_or_null(HANDLE_NAME) as MeshInstance3D
	if is_instance_valid(handle):
		return handle
	handle = MeshInstance3D.new()
	handle.name = HANDLE_NAME
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	handle.set_meta(HANDLE_META, true)
	add_child(handle, false, Node.INTERNAL_MODE_BACK)
	return handle


func _remove_handle() -> void:
	var handle := get_node_or_null(HANDLE_NAME)
	if is_instance_valid(handle):
		handle.free()


func _is_configured() -> bool:
	if _get_point_markers().size() >= 3:
		return true
	if not is_equal_approx(scale.x, 1.0) or not is_equal_approx(scale.z, 1.0):
		return true
	return bool(get_meta("use_authored_deck_area", false))


func _build_mesh() -> ArrayMesh:
	var point_positions := _get_point_positions()
	if point_positions.size() >= 3:
		return _build_mesh_from_points(point_positions)
	if _mesh != null:
		return _mesh
	_mesh = _build_mesh_from_points(DEFAULT_POINTS)
	return _mesh


func _build_mesh_from_points(points: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var polygon := PackedVector2Array()
	for point_variant in points:
		var point := point_variant as Vector3
		vertices.append(point)
		polygon.append(Vector2(point.x, point.z))
	var triangulated := Geometry2D.triangulate_polygon(polygon)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = triangulated
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _get_point_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for marker in _get_point_markers():
		positions.append(marker.position)
	return positions


func _get_point_markers() -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var points_root := get_node_or_null(POINTS_NAME)
	if not is_instance_valid(points_root):
		return markers
	for child in points_root.get_children():
		if child is Marker3D:
			markers.append(child as Marker3D)
	return markers


func _create_points_from_current_shape() -> void:
	if not Engine.is_editor_hint():
		return
	var points_root := _ensure_points_root()
	for child in points_root.get_children():
		child.free()
	var basis_scale := Vector3(scale.x, scale.y, scale.z)
	for index in range(DEFAULT_POINTS.size()):
		var marker := Marker3D.new()
		marker.name = "Point_%02d" % index
		var point: Vector3 = DEFAULT_POINTS[index]
		marker.position = Vector3(point.x * basis_scale.x, point.y * basis_scale.y, point.z * basis_scale.z)
		points_root.add_child(marker)
		_assign_owner(marker)
	scale = Vector3.ONE
	set_meta("use_authored_deck_area", true)
	_assign_owner(points_root)


func _ensure_points_root() -> Node3D:
	var points_root := get_node_or_null(POINTS_NAME) as Node3D
	if is_instance_valid(points_root):
		return points_root
	points_root = Node3D.new()
	points_root.name = POINTS_NAME
	add_child(points_root)
	_assign_owner(points_root)
	return points_root


func _assign_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_instance_valid(node):
		return
	var edited_root := get_tree().edited_scene_root if is_inside_tree() else null
	if is_instance_valid(edited_root):
		node.owner = edited_root


func _get_material() -> StandardMaterial3D:
	if _material != null:
		return _material
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.42, 0.82, 1.0, editor_alpha)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	_material.emission = Color(0.42, 0.82, 1.0, 1.0)
	_material.emission_energy_multiplier = 0.35
	return _material
