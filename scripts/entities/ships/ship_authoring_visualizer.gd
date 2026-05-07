@tool
extends Node3D
class_name ShipAuthoringVisualizer

const VISUAL_ROOT_NAME := "__AuthoringVisuals"
const DECK_VISUAL_NAME := "DeckAreaVisual"
const DECK_AREA := "DeckArea"
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
@export var mirror_boarding_anchors := true:
	set(value):
		mirror_boarding_anchors = value
		_anchor_mirror_cache.clear()
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
var _anchor_mirror_cache := {}


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

	_sync_mirrored_boarding_anchors()
	if show_deck_area:
		_add_deck_visual(visual_root, wanted_visuals)
	else:
		_set_deck_area_authoring_surface_visible(false)
	_add_marker_visuals(visual_root, wanted_visuals, CANNON_SLOTS, Color(1.0, 0.78, 0.18, 0.82), "Cannon")
	_add_marker_visuals(visual_root, wanted_visuals, WEAPON_SLOTS, Color(1.0, 0.32, 0.42, 0.82), "Weapon")
	_add_marker_visuals(visual_root, wanted_visuals, BOARDING_ANCHORS, Color(0.25, 0.82, 1.0, 0.82), "Boarding")
	_add_marker_visuals(visual_root, wanted_visuals, CREW_SLOTS, Color(0.35, 1.0, 0.45, 0.82), "Crew")
	_remove_stale_visuals(visual_root, wanted_visuals)


func _remove_visuals() -> void:
	_set_deck_area_authoring_surface_visible(false)
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
		if is_inside_tree() and marker.is_inside_tree():
			visual.global_transform = marker.global_transform
			visual.global_position += Vector3.UP * marker_vertical_offset
		else:
			visual.transform = _get_transform_relative_to_ancestor(marker, self)
			visual.position += Vector3.UP * marker_vertical_offset


func _add_deck_visual(visual_root: Node3D, wanted_visuals: Dictionary) -> void:
	var deck_mesh: Mesh = PlaneMesh.new()
	var deck_transform := Transform3D.IDENTITY
	var deck_area := get_node_or_null(DECK_AREA) as Node3D
	var has_authored_deck := is_instance_valid(deck_area) and ShipAuthoringHelper.get_deck_area_half_extents(get_parent()).length_squared() > 0.0001
	if has_authored_deck:
		if deck_area.has_method("set_editor_deck_visual_visible"):
			deck_area.call("set_editor_deck_visual_visible", true)
			return
		deck_mesh = _create_deck_area_mesh()
		deck_transform = deck_area.transform
		deck_transform.origin.y += 0.04
	else:
		_set_deck_area_authoring_surface_visible(false)
		var hull_bounds := _get_hull_local_bounds()
		if not bool(hull_bounds.get("has_bounds", false)):
			return
		var min_pos: Vector3 = hull_bounds["min"]
		var max_pos: Vector3 = hull_bounds["max"]
		var size_x := maxf(0.2, max_pos.x - min_pos.x)
		var size_z := maxf(0.2, max_pos.z - min_pos.z)
		deck_mesh.size = Vector2(size_x, size_z)
		deck_transform.origin = Vector3(
			(min_pos.x + max_pos.x) * 0.5,
			max_pos.y + 0.04,
			(min_pos.z + max_pos.z) * 0.5
		)

	wanted_visuals[DECK_VISUAL_NAME] = true
	var visual := _get_or_create_visual(visual_root, DECK_VISUAL_NAME)
	visual.mesh = deck_mesh
	if visual.get_meta("authoring_visual_kind", "") != "DeckArea":
		visual.material_override = _create_material(Color(0.42, 0.82, 1.0, 0.34))
		visual.set_meta("authoring_visual_kind", "DeckArea")
	visual.transform = deck_transform


func _set_deck_area_authoring_surface_visible(visible: bool) -> void:
	var deck_area := get_node_or_null(DECK_AREA)
	if is_instance_valid(deck_area) and deck_area.has_method("set_editor_deck_visual_visible"):
		deck_area.call("set_editor_deck_visual_visible", visible)


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


func _create_deck_area_mesh() -> Mesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var end_width := ShipAuthoringHelper.DECK_AREA_END_WIDTH_RATIO
	var full_width_z := ShipAuthoringHelper.DECK_AREA_FULL_WIDTH_Z_RATIO
	vertices.append_array([
		Vector3(-end_width, 0.0, -1.0),
		Vector3(end_width, 0.0, -1.0),
		Vector3(-1.0, 0.0, -full_width_z),
		Vector3(1.0, 0.0, -full_width_z),
		Vector3(-1.0, 0.0, full_width_z),
		Vector3(1.0, 0.0, full_width_z),
		Vector3(-end_width, 0.0, 1.0),
		Vector3(end_width, 0.0, 1.0),
	])
	indices.append_array([
		0, 1, 2,
		1, 3, 2,
		2, 3, 4,
		3, 5, 4,
		4, 5, 6,
		5, 7, 6,
	])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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


func _sync_mirrored_boarding_anchors() -> void:
	if not mirror_boarding_anchors:
		return
	var container := get_node_or_null(BOARDING_ANCHORS)
	if not is_instance_valid(container):
		return
	var markers_by_name := {}
	for child in container.get_children():
		if child is Marker3D:
			markers_by_name[str(child.name)] = child
	for suffix in ["Forward", "Mid", "Rear"]:
		var left_marker := markers_by_name.get("Left%s" % suffix, null) as Marker3D
		var right_marker := markers_by_name.get("Right%s" % suffix, null) as Marker3D
		if not is_instance_valid(left_marker) or not is_instance_valid(right_marker):
			continue
		_sync_mirrored_anchor_pair(left_marker, right_marker)


func _sync_mirrored_anchor_pair(left_marker: Marker3D, right_marker: Marker3D) -> void:
	if not left_marker.is_inside_tree() or not right_marker.is_inside_tree():
		return
	var pair_key := "%s|%s" % [left_marker.get_path(), right_marker.get_path()]
	var left_pos := left_marker.position
	var right_pos := right_marker.position
	var cached: Dictionary = _anchor_mirror_cache.get(pair_key, {})
	if cached.is_empty():
		_anchor_mirror_cache[pair_key] = {
			"left": left_pos,
			"right": right_pos,
		}
		return

	var previous_left: Vector3 = cached.get("left", left_pos)
	var previous_right: Vector3 = cached.get("right", right_pos)
	var left_changed := not left_pos.is_equal_approx(previous_left)
	var right_changed := not right_pos.is_equal_approx(previous_right)
	if left_changed and not right_changed:
		right_marker.position = _mirror_anchor_position(left_pos)
	elif right_changed and not left_changed:
		left_marker.position = _mirror_anchor_position(right_pos)
	elif left_changed and right_changed:
		right_marker.position = _mirror_anchor_position(left_pos)
	_anchor_mirror_cache[pair_key] = {
		"left": left_marker.position,
		"right": right_marker.position,
	}


func _mirror_anchor_position(position: Vector3) -> Vector3:
	return Vector3(-position.x, position.y, position.z)


func _get_hull_local_bounds() -> Dictionary:
	var parent_node := get_parent()
	if not is_instance_valid(parent_node):
		return {"has_bounds": false}
	var hull_node := _find_hull_bounds_source(parent_node)
	if not is_instance_valid(hull_node):
		return {"has_bounds": false}
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_hull_mesh_instances(hull_node, mesh_instances)
	if mesh_instances.is_empty():
		return {"has_bounds": false}
	var bounds := {
		"has_bounds": false,
		"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF),
	}
	for mesh_instance in mesh_instances:
		if not is_instance_valid(mesh_instance.mesh):
			continue
		var aabb := mesh_instance.get_aabb()
		var transform_to_authoring := _get_transform_between_nodes(mesh_instance, self, parent_node)
		for corner in _get_aabb_corners(aabb):
			var local_corner: Vector3 = transform_to_authoring * corner
			bounds["min"] = (bounds["min"] as Vector3).min(local_corner)
			bounds["max"] = (bounds["max"] as Vector3).max(local_corner)
			bounds["has_bounds"] = true
	return bounds


func _find_hull_bounds_source(parent_node: Node) -> Node:
	var hull_node := parent_node.get_node_or_null("Hull")
	if is_instance_valid(hull_node):
		return hull_node
	hull_node = parent_node.get_node_or_null("HullModel")
	if is_instance_valid(hull_node):
		return hull_node
	for child in parent_node.get_children():
		if child == self:
			continue
		if child is Node3D and str(child.name).contains("Hull"):
			return child
	return null


func _collect_hull_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_hull_mesh_instances(child, out)


func _get_transform_between_nodes(from_node: Node3D, to_node: Node3D, common_ancestor: Node) -> Transform3D:
	if is_instance_valid(from_node) and is_instance_valid(to_node) and from_node.is_inside_tree() and to_node.is_inside_tree():
		return to_node.global_transform.affine_inverse() * from_node.global_transform
	if not (common_ancestor is Node3D):
		return Transform3D.IDENTITY
	var from_transform := _get_transform_relative_to_ancestor(from_node, common_ancestor as Node3D)
	var to_transform := _get_transform_relative_to_ancestor(to_node, common_ancestor as Node3D)
	return to_transform.affine_inverse() * from_transform


func _get_transform_relative_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	if not is_instance_valid(node) or not is_instance_valid(ancestor):
		return Transform3D.IDENTITY
	if node.is_inside_tree() and ancestor.is_inside_tree():
		return ancestor.global_transform.affine_inverse() * node.global_transform
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while is_instance_valid(current) and current != ancestor:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	if current != ancestor:
		return Transform3D.IDENTITY
	return transform


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
