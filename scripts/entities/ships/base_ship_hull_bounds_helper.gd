extends RefCounted
class_name BaseShipHullBoundsHelper

const NODE_PROXIMITY_AREA := NodeContractHelper.SHIP_NODE_PROXIMITY_AREA
const NODE_HIT_AREA := NodeContractHelper.SHIP_NODE_HIT_AREA


static func refresh_collision_bounds_from_hull(ship) -> void:
	var hull_ext: Vector2 = compute_hull_half_extents(ship)
	if hull_ext.x <= 0.01 or hull_ext.y <= 0.01:
		hull_ext = ship.get_collision_half_extents()
		
	ship._hull_half_extents = hull_ext
	sync_contact_area_shapes_from_hull(ship)
	
	if not ship.auto_fit_collision_to_hull:
		ship._sync_profile_from_runtime()
		return
		
	var padded := Vector2(
		(hull_ext.x + ship.collision_padding) * ship.auto_fit_scale,
		(hull_ext.y + ship.collision_padding) * ship.auto_fit_scale
	)
	var base: float = maxf(padded.x, padded.y)
	if base <= 0.01:
		return
		
	ship.base_collision_radius = base
	ship.width_multiplier = clampf(padded.x / base, 0.1, 3.0)
	ship.length_multiplier = clampf(padded.y / base, 0.1, 3.0)
	ship._sync_profile_from_runtime()


static func sync_contact_area_shapes_from_hull(ship) -> void:
	if not ship.auto_fit_contact_areas_to_hull:
		return
	if ship._hull_half_extents.x <= 0.01 or ship._hull_half_extents.y <= 0.01:
		return

	var hit_size := Vector3(
		maxf(0.8, ship._hull_half_extents.x * 2.0 + 0.12),
		get_contact_area_height(ship, NODE_HIT_AREA),
		maxf(1.2, ship._hull_half_extents.y * 2.0 + 0.12)
	)
	var proximity_size := Vector3(
		hit_size.x + 0.6,
		hit_size.y + 0.2,
		hit_size.z + 0.8
	)
	fit_contact_area_box_shape(ship, NODE_HIT_AREA, hit_size)
	fit_contact_area_box_shape(ship, NODE_PROXIMITY_AREA, proximity_size)


static func get_contact_area_height(ship, area_name: String) -> float:
	var existing_height := 0.0
	var area: Area3D = ship.get_contact_area(area_name)
	if area is Area3D:
		var shape_node := ShipContactGeometry.get_contact_area_collision_shape(area)
		if shape_node is CollisionShape3D and shape_node.shape is BoxShape3D:
			existing_height = (shape_node.shape as BoxShape3D).size.y
	return maxf(maxf(existing_height, ship.deck_height + 2.0), 2.0)


static func fit_contact_area_box_shape(ship, area_name: String, size: Vector3) -> void:
	var area: Area3D = ship.get_contact_area(area_name)
	if not (area is Area3D):
		return
	var shape_node := ShipContactGeometry.get_contact_area_collision_shape(area)
	if not (shape_node is CollisionShape3D):
		return

	var box_shape: BoxShape3D = null
	if shape_node.shape is BoxShape3D:
		box_shape = (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
	else:
		box_shape = BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	var shape_position := shape_node.position
	shape_position.y = maxf(0.0, ship.deck_height * 0.5)
	shape_node.position = shape_position


static func sync_contact_area_layers(ship, layer_override: int = -1) -> void:
	var current_layer: int = layer_override
	if current_layer < 0:
		var layer_val: Variant = ship.get("collision_layer")
		current_layer = int(layer_val) if layer_val != null else ship._get_team_collision_layer(ship.get_team_tag())
	var proximity_area: Area3D = ship.get_proximity_area()
	if proximity_area is Area3D:
		proximity_area.set_deferred("collision_layer", current_layer)
		proximity_area.set_deferred("collision_mask", get_opposing_team_collision_layer(ship.get_team_tag()))

	var hit_area: Area3D = ship.get_hit_area()
	if hit_area is Area3D:
		hit_area.set_deferred("collision_layer", current_layer)
		hit_area.set_deferred("collision_mask", 0)


static func set_contact_areas_enabled(ship, enabled: bool) -> void:
	set_contact_area_enabled(ship, NODE_PROXIMITY_AREA, enabled)
	set_contact_area_enabled(ship, NODE_HIT_AREA, enabled)


static func set_contact_area_enabled(ship, area_name: String, enabled: bool) -> void:
	var area: Area3D = ship.get_contact_area(area_name)
	if area is Area3D:
		area.set_deferred("monitoring", enabled)
		area.set_deferred("monitorable", enabled)
		var shape_node := ShipContactGeometry.get_contact_area_collision_shape(area)
		if shape_node is CollisionShape3D:
			shape_node.set_deferred("disabled", not enabled)


static func get_opposing_team_collision_layer(team_name: String) -> int:
	return 4 if team_name == "player" else 2


static func compute_hull_half_extents(ship) -> Vector2:
	if not ship.is_inside_tree():
		return Vector2.ZERO
		
	var meshes: Array[MeshInstance3D] = []
	collect_hull_bounds_mesh_instances(ship, meshes)
	if meshes.is_empty():
		return Vector2.ZERO
		
	var preferred: Array[MeshInstance3D] = []
	var fallback: Array[MeshInstance3D] = []
	for mesh in meshes:
		if not is_instance_valid(mesh) or mesh.mesh == null:
			continue
		var lname: String = mesh.name.to_lower()
		if is_excluded_hull_bounds_mesh_name(lname):
			continue
		fallback.append(mesh)
		if lname.contains("hull") or lname.contains("shell") or lname.contains("castle"):
			preferred.append(mesh)
			
	var targets: Array[MeshInstance3D] = preferred if not preferred.is_empty() else fallback
	if targets.is_empty():
		return Vector2.ZERO
		
	var half_width := 0.0
	var half_length := 0.0
	for mesh in targets:
		var aabb: AABB = mesh.get_aabb()
		for corner in get_hull_bounds_aabb_corners(aabb):
			var local_pt: Vector3 = ship.to_local(mesh.to_global(corner))
			half_width = maxf(half_width, absf(local_pt.x))
			half_length = maxf(half_length, absf(local_pt.z))
			
	if half_width <= 0.01 or half_length <= 0.01:
		return Vector2.ZERO
	return Vector2(half_width, half_length)


static func collect_hull_bounds_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		if child.get_child_count() > 0:
			collect_hull_bounds_mesh_instances(child, out)


static func is_excluded_hull_bounds_mesh_name(name_lc: String) -> bool:
	return name_lc.contains("mast") \
		or name_lc.contains("cannon") \
		or name_lc.contains("rudder") \
		or name_lc.contains("oar") \
		or name_lc.contains("blade") \
		or name_lc.contains("shaft") \
		or name_lc.contains("wake") \
		or name_lc.contains("rope")


static func get_hull_bounds_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	return [
		Vector3(p.x, p.y, p.z),
		Vector3(p.x + s.x, p.y, p.z),
		Vector3(p.x, p.y + s.y, p.z),
		Vector3(p.x, p.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z),
		Vector3(p.x + s.x, p.y, p.z + s.z),
		Vector3(p.x, p.y + s.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z + s.z)
	]
