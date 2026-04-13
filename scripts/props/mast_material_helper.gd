extends RefCounted

const DEFAULT_SAIL_MATERIAL = preload("res://resources/materials/sail_material.tres")


static func apply_sail_material_settings(mast: Node3D, burn_mask_c: Texture2D) -> void:
	for mesh in mast._get_sail_meshes():
		var mat: ShaderMaterial = ensure_sail_material(mast, mesh)
		if mat == null:
			continue
		apply_deform_bounds(mesh, mat)
		apply_sail_shader_parameters(mast, mat, burn_mask_c)


static func ensure_sail_material(mast: Node3D, mesh: MeshInstance3D) -> ShaderMaterial:
	var override_mat: ShaderMaterial = mesh.material_override as ShaderMaterial
	var owner_id: int = mast.get_instance_id()
	if override_mat != null and override_mat.shader != null:
		if override_mat.has_meta("mast_owner_id") and int(override_mat.get_meta("mast_owner_id")) == owner_id:
			return override_mat
	var source_mat: ShaderMaterial = override_mat
	if source_mat == null:
		source_mat = mesh.get_active_material(0) as ShaderMaterial
	if source_mat == null:
		source_mat = DEFAULT_SAIL_MATERIAL
	if source_mat == null:
		return null
	var instance_mat: ShaderMaterial = source_mat.duplicate() as ShaderMaterial
	instance_mat.set_meta("mast_owner_id", owner_id)
	instance_mat.render_priority = 20
	mesh.material_override = instance_mat
	return instance_mat


static func apply_deform_bounds(mesh: MeshInstance3D, mat: ShaderMaterial) -> void:
	if mesh.mesh == null:
		return
	var aabb: AABB = mesh.mesh.get_aabb()
	var size: Vector3 = aabb.size
	size.x = max(size.x, 0.001)
	size.y = max(size.y, 0.001)
	size.z = max(size.z, 0.001)
	mat.set_shader_parameter("deform_bounds_min", aabb.position)
	mat.set_shader_parameter("deform_bounds_size", size)


static func apply_sail_shader_parameters(mast: Node3D, mat: ShaderMaterial, burn_mask_c: Texture2D) -> void:
	mat.set_shader_parameter("use_sail_texture", mast.use_sail_texture and mast.sail_texture != null)
	mat.set_shader_parameter("sail_texture", mast.sail_texture)
	mat.set_shader_parameter("burn_mask_texture_c", burn_mask_c)
	mat.set_shader_parameter("swap_uv_axes", mast.swap_sail_uv_axes)
	mat.set_shader_parameter("flip_u", mast.flip_sail_u)
	mat.set_shader_parameter("flip_v", mast.flip_sail_v)
	var visual_sail_damage: float = min(clamp(mast.sail_damage, 0.0, 1.0), 0.5)
	mat.set_shader_parameter("sail_damage", visual_sail_damage)
	mat.set_shader_parameter("burn_amount", mast.burn_amount)
	mat.set_shader_parameter("hole_alpha_strength", mast.hole_alpha_strength)
	mat.set_shader_parameter("damage_seed", mast._damage_seed)
	mat.set_shader_parameter("sail_uv_scale", mast.sail_uv_scale)
	mat.set_shader_parameter("sail_uv_offset", mast.sail_uv_offset)
	mat.set_shader_parameter("bottom_width_scale", mast.sail_bottom_width_scale)
