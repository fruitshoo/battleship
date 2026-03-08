extends Node3D
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

@onready var cubes: GPUParticles3D = $Cubes
@onready var planks: GPUParticles3D = $Planks

func _ready() -> void:
	if not VfxBudget.allow_spawn(get_tree(), "wood_splinter", global_position, 3, 60.0):
		queue_free()
		return
	if cubes: cubes.emitting = true
	if planks: planks.emitting = true
	
	get_tree().create_timer(1.5).timeout.connect(queue_free)

## 데미지량에 비례해 스폰될 파편의 양을 조절합니다.
func set_amount_by_damage(damage: float) -> void:
	if not cubes or not planks: return
	
	var total: int = 5
	if damage >= 30.0:
		total = randi_range(16, 24)
	elif damage >= 10.0:
		total = randi_range(8, 12)
	elif damage > 3.0:
		total = randi_range(4, 7)
		
	cubes.amount = max(1, int(total * 0.8))
	planks.amount = max(1, int(total * 0.2))
	
	var scale_mult = clamp(damage / 10.0, 0.4, 1.2)
	var cubes_mat = _ensure_local_process_material(cubes)
	if cubes_mat:
		cubes_mat.scale_min = 0.3 * scale_mult
		cubes_mat.scale_max = 0.8 * scale_mult
	var planks_mat = _ensure_local_process_material(planks)
	if planks_mat:
		planks_mat.scale_min = 0.3 * scale_mult
		planks_mat.scale_max = 1.0 * scale_mult

func _ensure_local_process_material(particles: GPUParticles3D) -> ParticleProcessMaterial:
	if not particles or not (particles.process_material is ParticleProcessMaterial):
		return null
	var mat := particles.process_material as ParticleProcessMaterial
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		particles.process_material = mat
	return mat
