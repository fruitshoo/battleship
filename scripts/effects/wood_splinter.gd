extends Node3D
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

@onready var cubes: GPUParticles3D = $Cubes
@onready var planks: GPUParticles3D = $Planks
var _life_left: float = 0.0
var _active: bool = false

func _ready() -> void:
	pool_reset()



func pool_capacity() -> int:
	return 14

func pool_activate() -> void:
	if not VfxBudget.allow_spawn(get_tree(), "wood_splinter", global_position, 3, 60.0):
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
	_life_left = 1.5

func pool_reset() -> void:
	_active = false
	_life_left = 0.0
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

## 데미지량에 비례해 스폰될 파편의 양을 조절합니다.
func set_amount_by_damage(damage: float) -> void:
	if not cubes or not planks: return
	
	var total: int = 4
	if damage >= 30.0:
		total = randi_range(6, 9) # 더욱 하향
	elif damage >= 10.0:
		total = randi_range(3, 5) # 더욱 하향
	elif damage > 3.0:
		total = randi_range(2, 3) # 더욱 하향
		
	# 큰 박스(Planks) 비중을 더 줄여 부하 최소화
	cubes.amount = max(1, int(total * 0.8))
	planks.amount = max(1, int(total * 0.2))
	
	var scale_mult = clamp(damage / 10.0, 0.4, 1.0) # 최대 배율 소폭 하향
	var cubes_mat = _ensure_local_process_material(cubes)
	if cubes_mat:
		cubes_mat.scale_min = 0.2 * scale_mult # 0.3 -> 0.2
		cubes_mat.scale_max = 0.5 * scale_mult # 0.8 -> 0.5
	var planks_mat = _ensure_local_process_material(planks)
	if planks_mat:
		planks_mat.scale_min = 0.2 * scale_mult # 0.3 -> 0.2
		planks_mat.scale_max = 0.7 * scale_mult # 1.0 -> 0.7

func _ensure_local_process_material(particles: GPUParticles3D) -> ParticleProcessMaterial:
	if not particles or not (particles.process_material is ParticleProcessMaterial):
		return null
	var mat := particles.process_material as ParticleProcessMaterial
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		particles.process_material = mat
	return mat
