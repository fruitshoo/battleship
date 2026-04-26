extends GPUParticles3D


@onready var secondary_puff: GPUParticles3D = get_node_or_null("SecondaryPuff")

var _budget_key_value: String = "hit_effect"
var _budget_limit_value: int = 8
var _budget_distance_value: float = 55.0
var _emit_secondary: bool = false
var _life_left: float = 0.0
var _active: bool = false
var _intensity_scale: float = 1.0

func _ready() -> void:
	_apply_hit_effect()
	pool_reset()
	if _is_prewarm_mode():
		return

func set_intensity(scale: float) -> void:
	_intensity_scale = clampf(scale, 0.6, 1.8)
	if is_node_ready():
		_apply_hit_effect()

func pool_capacity() -> int:
	return 18

func pool_activate() -> void:
	_apply_hit_effect()
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
		if n.has_meta("prewarm_mode") and n.get_meta("prewarm_mode") == true:
			return true
		n = n.get_parent()
	return false

func _apply_hit_effect() -> void:
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
