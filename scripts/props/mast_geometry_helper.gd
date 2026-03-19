extends RefCounted


static func capture_base_state(mast: Node3D) -> void:
	if is_instance_valid(mast.mast_mesh):
		mast._base_mast_mesh_position = mast.mast_mesh.position
		mast._base_mast_mesh_scale = mast.mast_mesh.scale
	if is_instance_valid(mast.sail_visual):
		mast._base_sail_visual_position = mast.sail_visual.position
	if is_instance_valid(mast.yardarm_mesh):
		mast._base_yardarm_mesh_position = mast.yardarm_mesh.position
		mast._base_yardarm_mesh_scale = mast.yardarm_mesh.scale
	if is_instance_valid(mast.sail_mesh):
		mast._base_sail_mesh_position = mast.sail_mesh.position
	if is_instance_valid(mast.flag):
		mast._base_flag_position = mast.flag.position
	if is_instance_valid(mast.sail_model_root):
		mast._base_model_root_position = mast.sail_model_root.position
		mast._base_model_root_scale = mast.sail_model_root.scale
	if is_instance_valid(mast.yardarm_model_root):
		mast._base_yardarm_model_position = mast.yardarm_model_root.position
		mast._base_yardarm_model_scale = mast.yardarm_model_root.scale
	if is_instance_valid(mast.mast_model_root):
		mast._base_mast_model_position = mast.mast_model_root.position
		mast._base_mast_model_scale = mast.mast_model_root.scale
		mast._base_mast_model_bounds = compute_mesh_tree_aabb(mast.mast_model_root)
		mast._has_mast_model_bounds = mast._base_mast_model_bounds.size.y > 0.001
	mast._base_mast_top_y = get_current_mast_top_y(mast, 1.0)


static func apply_mast_geometry(mast: Node3D) -> void:
	if is_instance_valid(mast.mast_mesh) and mast.mast_mesh.mesh is CylinderMesh:
		var mast_cylinder: CylinderMesh = mast.mast_mesh.mesh as CylinderMesh
		var base_bottom_y: float = mast._base_mast_mesh_position.y - (mast_cylinder.height * mast._base_mast_mesh_scale.y * 0.5)
		var new_half_height: float = mast_cylinder.height * mast._base_mast_mesh_scale.y * mast.mast_height_scale * 0.5
		mast.mast_mesh.scale = Vector3(
			mast._base_mast_mesh_scale.x,
			mast._base_mast_mesh_scale.y * mast.mast_height_scale,
			mast._base_mast_mesh_scale.z
		)
		mast.mast_mesh.position = mast._base_mast_mesh_position
		mast.mast_mesh.position.y = base_bottom_y + new_half_height
	if is_instance_valid(mast.mast_model_root):
		mast.mast_model_root.scale = Vector3(
			mast._base_mast_model_scale.x,
			mast._base_mast_model_scale.y * mast.mast_height_scale,
			mast._base_mast_model_scale.z
		)
		mast.mast_model_root.position = mast._base_mast_model_position
		if mast._has_mast_model_bounds:
			var model_bottom_y: float = mast._base_mast_model_position.y + (mast._base_mast_model_bounds.position.y * mast._base_mast_model_scale.y)
			mast.mast_model_root.position.y = model_bottom_y - (mast._base_mast_model_bounds.position.y * mast.mast_model_root.scale.y)
	var mast_top_delta: float = get_current_mast_top_y(mast, mast.mast_height_scale) - mast._base_mast_top_y
	if is_instance_valid(mast.sail_visual):
		mast.sail_visual.position = mast._base_sail_visual_position
		mast.sail_visual.position.y += mast_top_delta


static func apply_sail_geometry(mast: Node3D) -> void:
	var target_size: Vector2 = Vector2(max(mast.sail_size.x, 0.1), max(mast.sail_size.y, 0.1))
	if is_instance_valid(mast.yardarm_mesh):
		mast.yardarm_mesh.position = mast._base_yardarm_mesh_position + mast.yardarm_offset
		mast.yardarm_mesh.scale = Vector3(
			mast._base_yardarm_mesh_scale.x * mast.yardarm_scale.x,
			mast._base_yardarm_mesh_scale.y * mast.yardarm_scale.y,
			mast._base_yardarm_mesh_scale.z * mast.yardarm_scale.z
		)
	var default_mesh: MeshInstance3D = mast.sail_mesh if is_instance_valid(mast.sail_mesh) else mast.get_node_or_null("SailVisual/SailMesh") as MeshInstance3D
	if is_instance_valid(default_mesh) and default_mesh.mesh is PlaneMesh:
		var plane_mesh: PlaneMesh = default_mesh.mesh.duplicate() as PlaneMesh
		plane_mesh.size = target_size
		default_mesh.mesh = plane_mesh
		var top_anchor_y: float = mast._base_sail_mesh_position.y + (mast.BASE_SAIL_SIZE.y * 0.5)
		default_mesh.position = mast._base_sail_mesh_position
		default_mesh.position.y = top_anchor_y - (target_size.y * 0.5)
		default_mesh.position += mast.sail_offset
	if is_instance_valid(mast.flag):
		var flag_top_anchor_y: float = mast._base_sail_mesh_position.y + (mast.BASE_SAIL_SIZE.y * 0.5)
		var base_flag_offset: float = mast._base_flag_position.y - flag_top_anchor_y
		mast.flag.position = mast._base_flag_position
		mast.flag.position.y = flag_top_anchor_y + base_flag_offset
		mast.flag.position += mast.sail_offset
	var model_root: Node3D = mast.sail_model_root if is_instance_valid(mast.sail_model_root) else mast.get_node_or_null("SailVisual/sail2") as Node3D
	if is_instance_valid(model_root):
		model_root.scale = Vector3(
			mast._base_model_root_scale.x * (target_size.x / mast.BASE_SAIL_SIZE.x),
			mast._base_model_root_scale.y * (target_size.y / mast.BASE_SAIL_SIZE.y),
			mast._base_model_root_scale.z
		)
		model_root.position = mast._base_model_root_position
		model_root.position.y -= (target_size.y - mast.BASE_SAIL_SIZE.y) * 0.5
		model_root.position += mast.sail_offset
	var yardarm_root: Node3D = mast.yardarm_model_root if is_instance_valid(mast.yardarm_model_root) else mast.get_node_or_null("SailVisual/yardarm2") as Node3D
	if is_instance_valid(yardarm_root):
		yardarm_root.position = mast._base_yardarm_model_position + mast.yardarm_offset
		yardarm_root.scale = Vector3(
			mast._base_yardarm_model_scale.x * mast.yardarm_scale.x,
			mast._base_yardarm_model_scale.y * mast.yardarm_scale.y,
			mast._base_yardarm_model_scale.z * mast.yardarm_scale.z
		)
	for mesh in get_sail_meshes(mast):
		var mat: ShaderMaterial = mast._ensure_sail_material(mesh)
		if mat != null:
			mast._apply_deform_bounds(mesh, mat)


static func get_current_mast_top_y(mast: Node3D, height_scale: float) -> float:
	if is_instance_valid(mast.mast_mesh) and mast.mast_mesh.mesh is CylinderMesh:
		var mast_cylinder: CylinderMesh = mast.mast_mesh.mesh as CylinderMesh
		var base_bottom_y: float = mast._base_mast_mesh_position.y - (mast_cylinder.height * mast._base_mast_mesh_scale.y * 0.5)
		return base_bottom_y + (mast_cylinder.height * mast._base_mast_mesh_scale.y * height_scale)
	if mast._has_mast_model_bounds:
		var scaled_top: float = mast._base_mast_model_position.y + (mast._base_mast_model_bounds.position.y + mast._base_mast_model_bounds.size.y) * (mast._base_mast_model_scale.y * height_scale)
		return scaled_top
	return mast._base_sail_visual_position.y


static func get_sail_meshes(mast: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var default_mesh: MeshInstance3D = mast.sail_mesh if is_instance_valid(mast.sail_mesh) else mast.get_node_or_null("SailVisual/SailMesh") as MeshInstance3D
	if is_instance_valid(default_mesh):
		meshes.append(default_mesh)
	var model_root: Node3D = mast.sail_model_root if is_instance_valid(mast.sail_model_root) else mast.get_node_or_null("SailVisual/sail2") as Node3D
	if is_instance_valid(model_root):
		var model_mesh: MeshInstance3D = find_first_mesh_instance(model_root)
		if is_instance_valid(model_mesh):
			meshes.append(model_mesh)
	return meshes


static func find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = find_first_mesh_instance(child)
		if is_instance_valid(found):
			return found
	return null


static func compute_mesh_tree_aabb(root: Node3D) -> AABB:
	var found_any: bool = false
	var combined: AABB = AABB()
	for child in collect_mesh_instances(root):
		if child.mesh == null:
			continue
		var child_aabb: AABB = child.mesh.get_aabb()
		var global_corners: Array[Vector3] = aabb_corners(child_aabb)
		for i in range(global_corners.size()):
			var local_point: Vector3 = root.to_local(child.to_global(global_corners[i]))
			if not found_any:
				combined = AABB(local_point, Vector3.ZERO)
				found_any = true
			else:
				combined = combined.expand(local_point)
	return combined if found_any else AABB()


static func collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		meshes.append_array(collect_mesh_instances(child))
	return meshes


static func aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p: Vector3 = aabb.position
	var s: Vector3 = aabb.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]
