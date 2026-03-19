extends GPUParticles3D

const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

@export_enum("splash", "small", "sink") var preset: String = "splash"

@onready var secondary_burst: GPUParticles3D = get_node_or_null("SecondaryBurst")

var _budget_key_value: String = "water_explosion"
var _budget_limit_value: int = 4
var _budget_distance_value: float = 70.0
var _emit_secondary: bool = false
var _life_left: float = 0.0
var _active: bool = false

func _ready() -> void:
	_apply_preset()
	pool_reset()
	if _is_prewarm_mode():
		return

func configure_as_splash() -> void:
	preset = "splash"
	if is_node_ready():
		_apply_preset()

func configure_as_small() -> void:
	preset = "small"
	if is_node_ready():
		_apply_preset()

func configure_as_sink() -> void:
	preset = "sink"
	if is_node_ready():
		_apply_preset()

func pool_capacity() -> int:
	return 14

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
	if is_instance_valid(secondary_burst):
		secondary_burst.visible = _emit_secondary
		secondary_burst.restart()
		secondary_burst.emitting = _emit_secondary
		if _emit_secondary:
			max_life = max(max_life, secondary_burst.lifetime)
	_life_left = max_life + 0.4

func pool_reset() -> void:
	_active = false
	_life_left = 0.0
	set_process(false)
	emitting = false
	visible = false
	if is_instance_valid(secondary_burst):
		secondary_burst.visible = false
		secondary_burst.emitting = false

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
		"small":
			_apply_small_preset()
		"sink":
			_apply_sink_preset()
		_:
			_apply_splash_preset()

func _apply_splash_preset() -> void:
	_budget_key_value = "water_explosion"
	_budget_limit_value = 4
	_budget_distance_value = 70.0

	amount = 10
	lifetime = 1.0
	explosiveness = 0.95
	randomness = 0.5
	scale = Vector3.ONE

	var main_mat := _ensure_process_material(self)
	if main_mat:
		main_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		main_mat.emission_sphere_radius = 0.5
		main_mat.direction = Vector3(0, 1, 0)
		main_mat.spread = 40.0
		main_mat.initial_velocity_min = 4.0
		main_mat.initial_velocity_max = 7.0
		main_mat.gravity = Vector3(0, -10, 0)
		main_mat.damping_min = 2.0
		main_mat.damping_max = 4.0
		main_mat.scale_min = 0.0
		main_mat.scale_max = 1.2

	var quad := _ensure_quad_mesh(self)
	if quad:
		quad.size = Vector2(1.5, 1.5)

	if is_instance_valid(secondary_burst):
		_emit_secondary = false
		secondary_burst.amount = 1
		secondary_burst.lifetime = 0.8

func _apply_small_preset() -> void:
	_apply_splash_preset()
	_budget_key_value = "water_explosion_small"
	_budget_limit_value = 2
	_budget_distance_value = 60.0
	amount = 6
	lifetime = 0.7
	var main_mat := _ensure_process_material(self)
	if main_mat:
		main_mat.emission_sphere_radius = 0.25
		main_mat.spread = 30.0
		main_mat.initial_velocity_min = 2.5
		main_mat.initial_velocity_max = 4.2
		main_mat.gravity = Vector3(0, -8, 0)
		main_mat.scale_max = 0.85
	var quad := _ensure_quad_mesh(self)
	if quad:
		quad.size = Vector2(1.0, 1.0)

func _apply_sink_preset() -> void:
	_budget_key_value = "ship_sinking_bubbles"
	_budget_limit_value = 2
	_budget_distance_value = 85.0

	amount = 18
	lifetime = 1.4
	explosiveness = 0.88
	randomness = 0.55

	var main_mat := _ensure_process_material(self)
	if main_mat:
		main_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		main_mat.emission_sphere_radius = 0.9
		main_mat.direction = Vector3(0, 1, 0)
		main_mat.spread = 55.0
		main_mat.initial_velocity_min = 2.4
		main_mat.initial_velocity_max = 4.8
		main_mat.gravity = Vector3(0, -4.5, 0)
		main_mat.damping_min = 1.6
		main_mat.damping_max = 3.2
		main_mat.scale_min = 0.0
		main_mat.scale_max = 1.35

	var quad := _ensure_quad_mesh(self)
	if quad:
		quad.size = Vector2(1.7, 1.7)

	if is_instance_valid(secondary_burst):
		_emit_secondary = true
		secondary_burst.amount = 14
		secondary_burst.lifetime = 2.1
		secondary_burst.explosiveness = 0.75
		secondary_burst.randomness = 0.45
		var secondary_mat := _ensure_process_material(secondary_burst)
		if secondary_mat:
			secondary_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			secondary_mat.emission_sphere_radius = 1.1
			secondary_mat.direction = Vector3(0, 1, 0)
			secondary_mat.spread = 25.0
			secondary_mat.initial_velocity_min = 1.2
			secondary_mat.initial_velocity_max = 2.4
			secondary_mat.gravity = Vector3(0, -1.5, 0)
			secondary_mat.damping_min = 0.8
			secondary_mat.damping_max = 1.8
			secondary_mat.scale_min = 0.0
			secondary_mat.scale_max = 0.9
		var secondary_quad := _ensure_quad_mesh(secondary_burst)
		if secondary_quad:
			secondary_quad.size = Vector2(1.0, 1.0)

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

func _ensure_quad_mesh(particles: GPUParticles3D) -> QuadMesh:
	if not is_instance_valid(particles):
		return null
	var quad := particles.draw_pass_1 as QuadMesh
	if quad == null:
		return null
	if not quad.resource_local_to_scene:
		quad = quad.duplicate()
		quad.resource_local_to_scene = true
		particles.draw_pass_1 = quad
	return quad
