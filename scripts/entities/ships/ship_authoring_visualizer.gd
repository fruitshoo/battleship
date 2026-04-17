@tool
extends Node3D
class_name ShipAuthoringVisualizer

const VISUAL_ROOT_NAME := "__AuthoringVisuals"
const DECK_VISUAL_NAME := "DeckAreaVisual"
const CANNON_SLOTS := "CannonSlots"
const WEAPON_SLOTS := "WeaponSlots"
const BOARDING_ANCHORS := "BoardingAnchors"
const CREW_SLOTS := "CrewSlots"

@export var show_visuals := true:
	set(value):
		show_visuals = value
		_refresh_visuals_deferred()
@export var show_deck_area := true:
	set(value):
		show_deck_area = value
		_refresh_visuals_deferred()
@export_range(0.05, 0.6, 0.01) var marker_size := 0.18:
	set(value):
		marker_size = value
		_refresh_visuals_deferred()
@export_range(0.0, 0.5, 0.01) var marker_vertical_offset := 0.08:
	set(value):
		marker_vertical_offset = value
		_refresh_visuals_deferred()

var _refresh_timer := 0.0
var _refresh_queued := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		_remove_visuals()
		return
	set_process(true)
	_refresh_visuals_deferred()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_refresh_visuals_deferred()


func _exit_tree() -> void:
	_remove_visuals()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		_refresh_visuals()


func _refresh_visuals_deferred() -> void:
	if not Engine.is_editor_hint() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_visuals")


func _refresh_visuals() -> void:
	_refresh_queued = false
	if not Engine.is_editor_hint():
		_remove_visuals()
		return
	if not show_visuals:
		_remove_visuals()
		return

	var visual_root := _ensure_visual_root()
	var wanted_visuals := {}

	if show_deck_area:
		_add_deck_visual(visual_root, wanted_visuals)
	_add_marker_visuals(visual_root, wanted_visuals, CANNON_SLOTS, Color(1.0, 0.78, 0.18, 0.82), "Cannon")
	_add_marker_visuals(visual_root, wanted_visuals, WEAPON_SLOTS, Color(1.0, 0.32, 0.42, 0.82), "Weapon")
	_add_marker_visuals(visual_root, wanted_visuals, BOARDING_ANCHORS, Color(0.25, 0.82, 1.0, 0.82), "Boarding")
	_add_marker_visuals(visual_root, wanted_visuals, CREW_SLOTS, Color(0.35, 1.0, 0.45, 0.82), "Crew")
	_remove_stale_visuals(visual_root, wanted_visuals)


func _remove_visuals() -> void:
	var visual_root := get_node_or_null(VISUAL_ROOT_NAME)
	if not is_instance_valid(visual_root):
		return
	for child in visual_root.get_children():
		child.free()
	visual_root.free()


func _ensure_visual_root() -> Node3D:
	var visual_root := get_node_or_null(VISUAL_ROOT_NAME) as Node3D
	if is_instance_valid(visual_root):
		return visual_root
	visual_root = Node3D.new()
	visual_root.name = VISUAL_ROOT_NAME
	add_child(visual_root, false, Node.INTERNAL_MODE_BACK)
	return visual_root


func _remove_stale_visuals(visual_root: Node3D, wanted_visuals: Dictionary) -> void:
	for child in visual_root.get_children():
		if not wanted_visuals.has(str(child.name)):
			child.free()


func _add_marker_visuals(visual_root: Node3D, wanted_visuals: Dictionary, container_name: String, color: Color, name_prefix: String) -> void:
	var container := get_node_or_null(container_name)
	if not is_instance_valid(container):
		return
	var markers: Array[Marker3D] = []
	_collect_markers(container, markers)
	for marker in markers:
		var visual_name := "%s_%s" % [name_prefix, marker.name]
		wanted_visuals[visual_name] = true
		var visual := _get_or_create_visual(visual_root, visual_name)
		if visual.get_meta("authoring_visual_kind", "") != container_name:
			visual.mesh = _create_marker_mesh(container_name)
			visual.material_override = _create_material(color)
			visual.set_meta("authoring_visual_kind", container_name)
		visual.global_transform = marker.global_transform
		visual.global_position += Vector3.UP * marker_vertical_offset


func _add_deck_visual(visual_root: Node3D, wanted_visuals: Dictionary) -> void:
	var hull_bounds := _get_hull_local_bounds()
	if not bool(hull_bounds.get("has_bounds", false)):
		return
	var min_pos: Vector3 = hull_bounds["min"]
	var max_pos: Vector3 = hull_bounds["max"]
	var size_x := maxf(0.2, max_pos.x - min_pos.x)
	var size_z := maxf(0.2, max_pos.z - min_pos.z)
	var center := Vector3(
		(min_pos.x + max_pos.x) * 0.5,
		max_pos.y + 0.04,
		(min_pos.z + max_pos.z) * 0.5
	)

	var deck_mesh := PlaneMesh.new()
	deck_mesh.size = Vector2(size_x, size_z)

	wanted_visuals[DECK_VISUAL_NAME] = true
	var visual := _get_or_create_visual(visual_root, DECK_VISUAL_NAME)
	visual.mesh = deck_mesh
	if visual.get_meta("authoring_visual_kind", "") != "DeckArea":
		visual.material_override = _create_material(Color(0.9, 0.95, 1.0, 0.18))
		visual.set_meta("authoring_visual_kind", "DeckArea")
	visual.position = center


func _get_or_create_visual(visual_root: Node3D, visual_name: String) -> MeshInstance3D:
	var visual := visual_root.get_node_or_null(visual_name) as MeshInstance3D
	if is_instance_valid(visual):
		return visual
	visual = MeshInstance3D.new()
	visual.name = visual_name
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual_root.add_child(visual, false, Node.INTERNAL_MODE_BACK)
	return visual


func _create_marker_mesh(container_name: String) -> Mesh:
	if container_name == CANNON_SLOTS or container_name == WEAPON_SLOTS:
		var box := BoxMesh.new()
		box.size = Vector3(marker_size * 1.25, marker_size * 0.75, marker_size * 1.25)
		return box
	if container_name == BOARDING_ANCHORS:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = marker_size * 0.45
		cylinder.bottom_radius = marker_size * 0.45
		cylinder.height = marker_size * 1.7
		cylinder.radial_segments = 12
		return cylinder
	var sphere := SphereMesh.new()
	sphere.radius = marker_size * 0.55
	sphere.height = marker_size * 1.1
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere


func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 0.35
	return material


func _collect_markers(node: Node, out: Array[Marker3D]) -> void:
	for child in node.get_children():
		if child is Marker3D:
			out.append(child as Marker3D)
		elif str(child.name) != VISUAL_ROOT_NAME:
			_collect_markers(child, out)


func _get_hull_local_bounds() -> Dictionary:
	var hull_node := get_parent().get_node_or_null("Hull") if is_instance_valid(get_parent()) else null
	if not (hull_node is MeshInstance3D):
		return {"has_bounds": false}
	var mesh_instance := hull_node as MeshInstance3D
	var aabb := mesh_instance.get_aabb()
	var transform_to_authoring := global_transform.affine_inverse() * mesh_instance.global_transform
	var bounds := {
		"has_bounds": true,
		"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF),
	}
	for corner in _get_aabb_corners(aabb):
		var local_corner: Vector3 = transform_to_authoring * corner
		bounds["min"] = (bounds["min"] as Vector3).min(local_corner)
		bounds["max"] = (bounds["max"] as Vector3).max(local_corner)
	return bounds


func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var min_pos := aabb.position
	var max_pos := aabb.position + aabb.size
	return [
		Vector3(min_pos.x, min_pos.y, min_pos.z),
		Vector3(max_pos.x, min_pos.y, min_pos.z),
		Vector3(min_pos.x, max_pos.y, min_pos.z),
		Vector3(max_pos.x, max_pos.y, min_pos.z),
		Vector3(min_pos.x, min_pos.y, max_pos.z),
		Vector3(max_pos.x, min_pos.y, max_pos.z),
		Vector3(min_pos.x, max_pos.y, max_pos.z),
		Vector3(max_pos.x, max_pos.y, max_pos.z),
	]
