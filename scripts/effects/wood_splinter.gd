extends Node3D

@onready var cubes: GPUParticles3D = $Cubes
@onready var planks: GPUParticles3D = $Planks
@onready var dust_puff: GPUParticles3D = get_node_or_null("DustPuff")

func _ready() -> void:
	if cubes: cubes.emitting = true
	if planks: planks.emitting = true
	if dust_puff: dust_puff.emitting = true
	
	get_tree().create_timer(1.5).timeout.connect(queue_free)

## 데미지량에 비례해 스폰될 파편의 양을 조절합니다.
func set_amount_by_damage(damage: float) -> void:
	if not cubes or not planks: return
	
	var total: int = 5
	if damage >= 30.0:
		total = randi_range(30, 50)
	elif damage >= 10.0:
		total = randi_range(15, 20)
	elif damage > 3.0:
		total = randi_range(8, 12)
		
	cubes.amount = max(1, int(total * 0.8))
	planks.amount = max(1, int(total * 0.2))
	
	var scale_mult = clamp(damage / 10.0, 0.4, 1.2)
	if cubes.process_material is ParticleProcessMaterial:
		cubes.process_material = cubes.process_material.duplicate()
		cubes.process_material.scale_min = 0.3 * scale_mult
		cubes.process_material.scale_max = 0.8 * scale_mult
	if planks.process_material is ParticleProcessMaterial:
		planks.process_material = planks.process_material.duplicate()
		planks.process_material.scale_min = 0.3 * scale_mult
		planks.process_material.scale_max = 1.0 * scale_mult
	
	# DustPuff 크기도 데미지에 비례
	if dust_puff and dust_puff.process_material is ParticleProcessMaterial:
		dust_puff.process_material = dust_puff.process_material.duplicate()
		dust_puff.process_material.scale_min = 1.5 * scale_mult
		dust_puff.process_material.scale_max = 3.0 * scale_mult
