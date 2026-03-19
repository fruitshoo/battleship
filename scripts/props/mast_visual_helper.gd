extends RefCounted

const DEFAULT_SAIL_MATERIAL := preload("res://resources/materials/sail_material.tres")
const SAIL_SMOKE_SCALE := Vector3(0.38, 0.38, 0.38)
const SAIL_SMOKE_POSITION := Vector3(0.0, 3.2, -0.08)
const SAIL_SMOKE_THRESHOLD := 0.12
const SAIL_SMOKE_BASE_AMOUNT := 3

# Sail material / burn state
#
# This helper intentionally keeps all sail visual state in one place so `mast.gd`
# can focus on scene geometry and transform logic.

static func apply_sail_material_settings(mast: Node3D, burn_mask_a: Texture2D, burn_mask_b: Texture2D, burn_mask_c: Texture2D) -> void:
	for mesh in mast._get_sail_meshes():
		var mat := ensure_sail_material(mast, mesh)
		if mat == null:
			continue
		apply_deform_bounds(mesh, mat)
		_apply_sail_shader_parameters(mast, mat, burn_mask_a, burn_mask_b, burn_mask_c)

# Sail smoke
static func ensure_sail_smoke(mast: Node3D, smoke_scene: PackedScene) -> Node3D:
	if is_instance_valid(mast._sail_smoke_instance):
		return mast._sail_smoke_instance
	if smoke_scene == null:
		return null
	var smoke_root := smoke_scene.instantiate() as Node3D
	if smoke_root == null:
		return null
	smoke_root.name = "SailSmoke"
	smoke_root.scale = SAIL_SMOKE_SCALE
	smoke_root.position = SAIL_SMOKE_POSITION
	if is_instance_valid(mast.sail_visual):
		mast.sail_visual.add_child(smoke_root)
	else:
		mast.add_child(smoke_root)
	mast._sail_smoke_instance = smoke_root
	var smoke_particles := _get_smoke_particles(smoke_root)
	_configure_smoke_particles(smoke_particles)
	return mast._sail_smoke_instance

static func update_sail_smoke(mast: Node3D, smoke_scene: PackedScene) -> void:
	var should_emit: bool = mast.burn_amount >= SAIL_SMOKE_THRESHOLD
	if not should_emit:
		_stop_sail_smoke(mast)
		return
	var smoke_root := ensure_sail_smoke(mast, smoke_scene)
	if not is_instance_valid(smoke_root):
		return
	var smoke_particles := _get_smoke_particles(smoke_root)
	if not is_instance_valid(smoke_particles):
		return
	smoke_particles.amount = SAIL_SMOKE_BASE_AMOUNT + int(round(mast.burn_amount * 3.0))
	smoke_particles.emitting = true

# Sail material instance ownership
static func ensure_sail_material(mast: Node3D, mesh: MeshInstance3D) -> ShaderMaterial:
	var override_mat := mesh.material_override as ShaderMaterial
	var owner_id := mast.get_instance_id()
	if override_mat != null and override_mat.shader != null:
		if override_mat.has_meta("mast_owner_id") and int(override_mat.get_meta("mast_owner_id")) == owner_id:
			return override_mat
	var source_mat := override_mat
	if source_mat == null:
		source_mat = mesh.get_active_material(0) as ShaderMaterial
	if source_mat == null:
		source_mat = DEFAULT_SAIL_MATERIAL
	if source_mat == null:
		return null
	var instance_mat := source_mat.duplicate() as ShaderMaterial
	instance_mat.set_meta("mast_owner_id", owner_id)
	mesh.material_override = instance_mat
	return instance_mat

static func apply_deform_bounds(mesh: MeshInstance3D, mat: ShaderMaterial) -> void:
	if mesh.mesh == null:
		return
	var aabb := mesh.mesh.get_aabb()
	var size := aabb.size
	size.x = max(size.x, 0.001)
	size.y = max(size.y, 0.001)
	size.z = max(size.z, 0.001)
	mat.set_shader_parameter("deform_bounds_min", aabb.position)
	mat.set_shader_parameter("deform_bounds_size", size)

static func _apply_sail_shader_parameters(mast: Node3D, mat: ShaderMaterial, burn_mask_a: Texture2D, burn_mask_b: Texture2D, burn_mask_c: Texture2D) -> void:
	mat.set_shader_parameter("use_sail_texture", mast.use_sail_texture and mast.sail_texture != null)
	mat.set_shader_parameter("sail_texture", mast.sail_texture)
	mat.set_shader_parameter("burn_mask_texture_a", burn_mask_a)
	mat.set_shader_parameter("burn_mask_texture_b", burn_mask_b)
	mat.set_shader_parameter("burn_mask_texture_c", burn_mask_c)
	mat.set_shader_parameter("swap_uv_axes", mast.swap_sail_uv_axes)
	mat.set_shader_parameter("flip_u", mast.flip_sail_u)
	mat.set_shader_parameter("flip_v", mast.flip_sail_v)
	mat.set_shader_parameter("sail_damage", mast.sail_damage)
	mat.set_shader_parameter("burn_amount", mast.burn_amount)
	mat.set_shader_parameter("hole_alpha_strength", mast.hole_alpha_strength)
	mat.set_shader_parameter("damage_seed", mast._damage_seed)
	mat.set_shader_parameter("sail_uv_scale", mast.sail_uv_scale)
	mat.set_shader_parameter("sail_uv_offset", mast.sail_uv_offset)
	mat.set_shader_parameter("bottom_width_scale", mast.sail_bottom_width_scale)

static func _get_smoke_particles(smoke_root: Node3D) -> GPUParticles3D:
	return smoke_root.get_node_or_null("SmokeParticles") as GPUParticles3D

static func _configure_smoke_particles(smoke_particles: GPUParticles3D) -> void:
	if not is_instance_valid(smoke_particles):
		return
	smoke_particles.amount = SAIL_SMOKE_BASE_AMOUNT
	smoke_particles.lifetime = 1.8
	smoke_particles.randomness = 0.45
	smoke_particles.fixed_fps = 16

static func _stop_sail_smoke(mast: Node3D) -> void:
	if not is_instance_valid(mast._sail_smoke_instance):
		return
	var existing_particles := _get_smoke_particles(mast._sail_smoke_instance)
	if is_instance_valid(existing_particles):
		existing_particles.emitting = false
