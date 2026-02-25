extends Node3D

@onready var cubes: GPUParticles3D = $Cubes
@onready var planks: GPUParticles3D = $Planks

func _ready() -> void:
	# 파티클 동시 발생
	if cubes: cubes.emitting = true
	if planks: planks.emitting = true
	
	# 안전하게 파티클 수명(1.2초)보다 약간 긴 타이머로 삭제 처리
	get_tree().create_timer(1.5).timeout.connect(queue_free)

## 데미지량에 비례해 스폰될 파편의 양을 조절합니다.
func set_amount_by_damage(damage: float) -> void:
	if not cubes or not planks: return
	
	var total: int = 5 # 기본 가벼운 스침 (데미지 1~3 기준)
	
	if damage >= 30.0:
		total = randi_range(30, 50) # 크리티컬, 폭발
	elif damage >= 10.0:
		total = randi_range(15, 20) # 일반포격 (15뎀 등)
	elif damage > 3.0:
		total = randi_range(8, 12) # 약간 강한 화살이나 스침
		
	# 80% 큐브, 20% 긴 널빤지로 분배
	cubes.amount = max(1, int(total * 0.8))
	planks.amount = max(1, int(total * 0.2))
	
	# 크기 축소: 가벼운 데미지면 파편들 크기도 작게 만들어 돛 피격 시 배가 부서지는 착각을 방지
	var scale_mult = clamp(damage / 10.0, 0.4, 1.2)
	if cubes.process_material is ParticleProcessMaterial:
		cubes.process_material.scale_min = 0.3 * scale_mult
		cubes.process_material.scale_max = 0.8 * scale_mult
	if planks.process_material is ParticleProcessMaterial:
		planks.process_material.scale_min = 0.3 * scale_mult
		planks.process_material.scale_max = 1.0 * scale_mult
