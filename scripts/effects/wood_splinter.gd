extends Node3D

const DEFAULT_BUDGET_KEY := "wood_splinter"
const DEFAULT_BUDGET_MAX_PER_FRAME := 3
const DEFAULT_BUDGET_MAX_DISTANCE := 60.0
const DEFAULT_LIFETIME := 1.5

@onready var cubes: GPUParticles3D = $Cubes
@onready var planks: GPUParticles3D = $Planks
var _life_left: float = 0.0
var _active: bool = false
var _configured_damage: float = 4.0
var _impact_direction: Vector3 = Vector3.UP
var _budget_key: String = DEFAULT_BUDGET_KEY
var _budget_max_per_frame: int = DEFAULT_BUDGET_MAX_PER_FRAME
var _budget_max_distance: float = DEFAULT_BUDGET_MAX_DISTANCE
var _budget_reserved: bool = false

static func spawn_burst(
	tree: SceneTree,
	scene: PackedScene,
	position: Vector3,
	damage: float,
	impact_direction: Vector3 = Vector3.ZERO,
	budget_key: String = DEFAULT_BUDGET_KEY,
	budget_max_per_frame: int = DEFAULT_BUDGET_MAX_PER_FRAME,
	budget_max_distance: float = DEFAULT_BUDGET_MAX_DISTANCE,
	budget_reserved: bool = false
) -> Node3D:
	if tree == null or scene == null:
		return null
	var resolved_key := budget_key if not budget_key.strip_edges().is_empty() else DEFAULT_BUDGET_KEY
	var resolved_max_per_frame := maxi(budget_max_per_frame, 1)
	if not budget_reserved and not VfxBudget.allow_spawn(tree, resolved_key, position, resolved_max_per_frame, budget_max_distance):
		return null

	var splinter := ScenePool.acquire(tree, scene)
	if not is_instance_valid(splinter):
		return null
	tree.root.add_child(splinter)
	if splinter is Node3D:
		var splinter_3d := splinter as Node3D
		splinter_3d.global_position = position
		splinter_3d.rotation.y = randf() * TAU
	if splinter.has_method("configure_burst"):
		splinter.configure_burst(damage, impact_direction, resolved_key, resolved_max_per_frame, budget_max_distance, true)
	elif splinter.has_method("set_amount_by_damage"):
		splinter.set_amount_by_damage(damage)
	if splinter.has_method("pool_activate"):
		splinter.pool_activate()
	return splinter as Node3D

func _ready() -> void:
	pool_reset()



func pool_capacity() -> int:
	return 14

func pool_activate() -> void:
	if not _budget_reserved and not VfxBudget.allow_spawn(get_tree(), _budget_key, global_position, _budget_max_per_frame, _budget_max_distance):
		ScenePool.release(self)
		return
	_active = true
	visible = true
	set_process(true)
	if cubes:
		cubes.restart()
		cubes.emitting = true
	if planks:
		planks.restart()
		planks.emitting = true
	_life_left = DEFAULT_LIFETIME

func pool_reset() -> void:
	_active = false
	_life_left = 0.0
	_reset_burst_config()
	set_process(false)
	visible = false
	if cubes:
		cubes.emitting = false
	if planks:
		planks.emitting = false

func _process(delta: float) -> void:
	if not _active:
		return
	_life_left -= delta
	if _life_left <= 0.0:
		ScenePool.release(self)

func configure_burst(
	damage: float,
	impact_direction: Vector3 = Vector3.ZERO,
	budget_key: String = DEFAULT_BUDGET_KEY,
	budget_max_per_frame: int = DEFAULT_BUDGET_MAX_PER_FRAME,
	budget_max_distance: float = DEFAULT_BUDGET_MAX_DISTANCE,
	budget_reserved: bool = false
) -> void:
	_budget_key = budget_key if not budget_key.strip_edges().is_empty() else DEFAULT_BUDGET_KEY
	_budget_max_per_frame = maxi(budget_max_per_frame, 1)
	_budget_max_distance = budget_max_distance
	_budget_reserved = budget_reserved
	_impact_direction = impact_direction.normalized() if impact_direction.length_squared() > 0.001 else Vector3.UP
	set_amount_by_damage(damage)

func set_impact_direction(impact_direction: Vector3) -> void:
	if impact_direction.length_squared() <= 0.001:
		_impact_direction = Vector3.UP
		return
	_impact_direction = impact_direction.normalized()
	_apply_particle_shape()

## 데미지량에 비례해 스폰될 파편의 양을 조절합니다.
func set_amount_by_damage(damage: float) -> void:
	_configured_damage = maxf(damage, 0.0)
	_apply_particle_shape()

func _apply_particle_shape() -> void:
	if not cubes or not planks:
		return

	var damage_factor := clampf(_configured_damage / 34.0, 0.0, 1.0)
	var total: int = 4
	if _configured_damage >= 30.0:
		total = randi_range(8, 11)
	elif _configured_damage >= 10.0:
		total = randi_range(5, 8)
	elif _configured_damage > 3.0:
		total = randi_range(3, 5)
	else:
		total = randi_range(2, 3)

	cubes.amount = max(1, int(round(total * 0.72)))
	planks.amount = max(1, total - cubes.amount)

	var burst_direction := _get_particle_direction()
	var scale_mult := clampf(_configured_damage / 12.0, 0.38, 1.15)
	var cubes_mat := _ensure_local_process_material(cubes)
	if cubes_mat:
		cubes_mat.direction = burst_direction
		cubes_mat.spread = lerpf(62.0, 38.0, damage_factor)
		cubes_mat.initial_velocity_min = lerpf(3.5, 7.0, damage_factor)
		cubes_mat.initial_velocity_max = lerpf(7.0, 15.0, damage_factor)
		cubes_mat.scale_min = 0.18 * scale_mult
		cubes_mat.scale_max = 0.52 * scale_mult
	var planks_mat := _ensure_local_process_material(planks)
	if planks_mat:
		planks_mat.direction = burst_direction
		planks_mat.spread = lerpf(54.0, 30.0, damage_factor)
		planks_mat.initial_velocity_min = lerpf(3.0, 6.0, damage_factor)
		planks_mat.initial_velocity_max = lerpf(6.0, 13.0, damage_factor)
		planks_mat.scale_min = 0.22 * scale_mult
		planks_mat.scale_max = 0.78 * scale_mult

func _get_particle_direction() -> Vector3:
	if _impact_direction == Vector3.UP:
		return Vector3.UP
	var lateral := Vector3(_impact_direction.x, 0.0, _impact_direction.z)
	if lateral.length_squared() <= 0.001:
		return Vector3.UP
	return (lateral.normalized() * 0.62 + Vector3.UP).normalized()

func _reset_burst_config() -> void:
	_configured_damage = 4.0
	_impact_direction = Vector3.UP
	_budget_key = DEFAULT_BUDGET_KEY
	_budget_max_per_frame = DEFAULT_BUDGET_MAX_PER_FRAME
	_budget_max_distance = DEFAULT_BUDGET_MAX_DISTANCE
	_budget_reserved = false

func _ensure_local_process_material(particles: GPUParticles3D) -> ParticleProcessMaterial:
	if not particles or not (particles.process_material is ParticleProcessMaterial):
		return null
	var mat := particles.process_material as ParticleProcessMaterial
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		particles.process_material = mat
	return mat
