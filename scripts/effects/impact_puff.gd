extends GPUParticles3D

const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

@export_enum("muzzle", "hit") var preset: String = "muzzle"

@onready var secondary_puff: GPUParticles3D = get_node_or_null("SecondaryPuff")

var _budget_key_value: String = "muzzle_smoke"
var _budget_limit_value: int = 5
var _budget_distance_value: float = 65.0
var _emit_secondary: bool = false
var _life_left: float = 0.0
var _active: bool = false
var _intensity_scale: float = 1.0

func _ready() -> void:
	_apply_preset()
	pool_reset()
	if _is_prewarm_mode():
		return

func set_preset(value: String) -> void:
	preset = value
	if is_node_ready():
		_apply_preset()

func configure_as_muzzle() -> void:
	set_preset("muzzle")

func configure_as_hit() -> void:
	set_preset("hit")

func set_intensity(scale: float) -> void:
	_intensity_scale = clampf(scale, 0.6, 1.8)
	if is_node_ready():
		_apply_preset()

func pool_capacity() -> int:
	return 18

func pool_activate() -> void:
	_apply_preset()
	if not VfxBudget.allow_spawn(get_tree(), _budget_key_value, global_position, _budget_limit_value, _budget_distance_value):
		ScenePool.release(self)
		return
	_active = true
	visible = true
	set_process(true)
	restart()
	emitting = true
	var max_life := lifetime
	if is_instance_valid(secondary_puff):
		secondary_puff.visible = _emit_secondary
		secondary_puff.restart()
		secondary_puff.emitting = _emit_secondary
		if _emit_secondary:
			max_life = max(max_life, secondary_puff.lifetime)
	_life_left = max_life + 0.3

func pool_reset() -> void:
	_active = false
	_life_left = 0.0
	_intensity_scale = 1.0
	set_process(false)
	emitting = false
	visible = false
	if is_instance_valid(secondary_puff):
		secondary_puff.visible = false
		secondary_puff.emitting = false

func _process(delta: float) -> void:
	if not _active:
		return
	_life_left -= delta
	if _life_left <= 0.0:
		ScenePool.release(self)

func _is_prewarm_mode() -> bool:
	var n: Node = self
	while is_instance_valid(n):
		if n.has_meta("prewarm_mode") and bool(n.get_meta("prewarm_mode")):
			return true
		n = n.get_parent()
	return false

func _apply_preset() -> void:
	match preset:
		"hit":
			_apply_hit_preset()
		_:
			_apply_muzzle_preset()

func _apply_muzzle_preset() -> void:
	var intensity: float = _intensity_scale
	var size_scale: float = lerpf(0.9, 1.35, inverse_lerp(0.6, 1.8, intensity))
	_budget_key_value = "muzzle_smoke"
	_budget_limit_value = 5
	_budget_distance_value = 65.0

	amount = clampi(int(round(8.0 * intensity)), 6, 16)
	lifetime = 1.0 + (0.18 * intensity)
	explosiveness = 0.95
	randomness = 0.12

	var main_mat := _ensure_process_material(self)
	if main_mat:
		main_mat.direction = Vector3(0, 0, -1)
		main_mat.spread = 26.0
		main_mat.initial_velocity_min = 3.2 * intensity
		main_mat.initial_velocity_max = 6.8 * intensity
		main_mat.gravity = Vector3(0, 0.3, 0)
		main_mat.damping_min = 2.0
		main_mat.damping_max = 4.0
		main_mat.scale_min = 0.95 * size_scale
		main_mat.scale_max = 2.2 * size_scale
		main_mat.color = Color(0.95, 0.92, 0.88, 0.72)

	var main_mesh := _ensure_quad_material(self)
	if main_mesh:
		main_mesh.size = Vector2(2.0, 2.0) * size_scale
		main_mesh.material.emission = Color(0.9, 0.85, 0.75, 1.0)
		main_mesh.material.emission_energy_multiplier = 0.24 + (0.18 * intensity)

	if is_instance_valid(secondary_puff):
		_emit_secondary = true
		secondary_puff.amount = clampi(int(round(4.0 * intensity)), 3, 8)
		secondary_puff.lifetime = 0.3 + (0.08 * intensity)
		secondary_puff.explosiveness = 1.0
		secondary_puff.randomness = 0.15
		var secondary_mat := _ensure_process_material(secondary_puff)
		if secondary_mat:
			secondary_mat.direction = Vector3(0, 0, -1)
			secondary_mat.spread = 16.0
			secondary_mat.initial_velocity_min = 2.2 * intensity
			secondary_mat.initial_velocity_max = 5.0 * intensity
			secondary_mat.gravity = Vector3(0, 0.1, 0)
			secondary_mat.damping_min = 3.0
			secondary_mat.damping_max = 5.0
			secondary_mat.scale_min = 0.55 * size_scale
			secondary_mat.scale_max = 1.15 * size_scale
			secondary_mat.color = Color(1.0, 0.88, 0.72, 0.72)
		var secondary_mesh := _ensure_quad_material(secondary_puff)
		if secondary_mesh:
			secondary_mesh.size = Vector2(1.2, 1.2) * size_scale
			secondary_mesh.material.emission = Color(1.0, 0.82, 0.54, 1.0)
			secondary_mesh.material.emission_energy_multiplier = 0.35 + (0.16 * intensity)

func _apply_hit_preset() -> void:
	var intensity: float = _intensity_scale
	var size_scale: float = lerpf(0.9, 1.3, inverse_lerp(0.6, 1.8, intensity))
	_budget_key_value = "hit_effect"
	_budget_limit_value = 8
	_budget_distance_value = 55.0

	amount = clampi(int(round(2.0 * intensity)), 2, 5)
	lifetime = 0.10 + (0.05 * intensity)
	explosiveness = 1.0
	randomness = 0.15

	var main_mat := _ensure_process_material(self)
	if main_mat:
		main_mat.direction = Vector3(0, 1, 0)
		main_mat.spread = 62.0
		main_mat.initial_velocity_min = 1.2 * intensity
		main_mat.initial_velocity_max = 3.0 * intensity
		main_mat.gravity = Vector3(0, 0.2, 0)
		main_mat.damping_min = 1.0
		main_mat.damping_max = 2.0
		main_mat.scale_min = 0.8 * size_scale
		main_mat.scale_max = 1.65 * size_scale
		main_mat.color = Color(0.82, 0.28, 0.14, 0.95)

	var main_mesh := _ensure_quad_material(self)
	if main_mesh:
		main_mesh.size = Vector2(1.2, 1.2) * size_scale
		main_mesh.material.emission = Color(0.95, 0.28, 0.2, 1.0)
		main_mesh.material.emission_energy_multiplier = 0.48 + (0.14 * intensity)

	if is_instance_valid(secondary_puff):
		_emit_secondary = true
		secondary_puff.amount = clampi(int(round(6.0 * intensity)), 5, 12)
		secondary_puff.lifetime = 0.38 + (0.10 * intensity)
		secondary_puff.explosiveness = 0.9
		secondary_puff.randomness = 0.7
		var secondary_mat := _ensure_process_material(secondary_puff)
		if secondary_mat:
			secondary_mat.direction = Vector3(0, 1, 0)
			secondary_mat.spread = 60.0
			secondary_mat.initial_velocity_min = 1.1 * intensity
			secondary_mat.initial_velocity_max = 2.8 * intensity
			secondary_mat.gravity = Vector3(0, 0.2, 0)
			secondary_mat.damping_min = 1.0
			secondary_mat.damping_max = 2.0
			secondary_mat.scale_min = 0.85 * size_scale
			secondary_mat.scale_max = 1.7 * size_scale
			secondary_mat.color = Color(0.5, 0.0, 0.0, 0.7)
		var secondary_mesh := _ensure_quad_material(secondary_puff)
		if secondary_mesh:
			secondary_mesh.size = Vector2(1.25, 1.25) * size_scale
			secondary_mesh.material.emission = Color(0.95, 0.28, 0.2, 1.0)
			secondary_mesh.material.emission_energy_multiplier = 0.48 + (0.14 * intensity)

func _ensure_process_material(particles: GPUParticles3D) -> ParticleProcessMaterial:
	if not is_instance_valid(particles):
		return null
	if not (particles.process_material is ParticleProcessMaterial):
		return null
	var mat := particles.process_material as ParticleProcessMaterial
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		particles.process_material = mat
	return mat

func _ensure_quad_material(particles: GPUParticles3D) -> QuadMesh:
	if not is_instance_valid(particles):
		return null
	var quad := particles.draw_pass_1 as QuadMesh
	if quad == null:
		return null
	if not quad.resource_local_to_scene:
		quad = quad.duplicate()
		quad.resource_local_to_scene = true
		particles.draw_pass_1 = quad
	if quad.material is StandardMaterial3D and not quad.material.resource_local_to_scene:
		var mat := (quad.material as StandardMaterial3D).duplicate()
		mat.resource_local_to_scene = true
		quad.material = mat
	return quad
