extends RefCounted

const SAIL_SMOKE_SCALE := Vector3(0.38, 0.38, 0.38)
const SAIL_SMOKE_POSITION := Vector3(0.0, 3.2, -0.08)
const SAIL_SMOKE_THRESHOLD := 0.12
const SAIL_SMOKE_BASE_AMOUNT := 3


static func ensure_sail_smoke(mast: Node3D, smoke_scene: PackedScene) -> Node3D:
	if is_instance_valid(mast._sail_smoke_instance):
		return mast._sail_smoke_instance
	if smoke_scene == null:
		return null
	var smoke_root: Node3D = smoke_scene.instantiate() as Node3D
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
	var smoke_particles: GPUParticles3D = get_smoke_particles(smoke_root)
	configure_smoke_particles(smoke_particles)
	return mast._sail_smoke_instance


static func update_sail_smoke(mast: Node3D, smoke_scene: PackedScene) -> void:
	var should_emit: bool = mast.burn_amount >= SAIL_SMOKE_THRESHOLD
	if not should_emit:
		stop_sail_smoke(mast)
		return
	var smoke_root: Node3D = ensure_sail_smoke(mast, smoke_scene)
	if not is_instance_valid(smoke_root):
		return
	var smoke_particles: GPUParticles3D = get_smoke_particles(smoke_root)
	if not is_instance_valid(smoke_particles):
		return
	smoke_particles.amount = SAIL_SMOKE_BASE_AMOUNT + int(round(mast.burn_amount * 3.0))
	smoke_particles.emitting = true


static func get_smoke_particles(smoke_root: Node3D) -> GPUParticles3D:
	return smoke_root.get_node_or_null("SmokeParticles") as GPUParticles3D


static func configure_smoke_particles(smoke_particles: GPUParticles3D) -> void:
	if not is_instance_valid(smoke_particles):
		return
	smoke_particles.amount = SAIL_SMOKE_BASE_AMOUNT
	smoke_particles.lifetime = 1.8
	smoke_particles.randomness = 0.45
	smoke_particles.fixed_fps = 16


static func stop_sail_smoke(mast: Node3D) -> void:
	if not is_instance_valid(mast._sail_smoke_instance):
		return
	var existing_particles: GPUParticles3D = get_smoke_particles(mast._sail_smoke_instance)
	if is_instance_valid(existing_particles):
		existing_particles.emitting = false
