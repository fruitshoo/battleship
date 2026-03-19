extends GPUParticles3D
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

## 원샷 파티클 — 재생 즉시 emit을 시작하고, 수명이 다하면 자동으로 노드를 제거합니다.
## muzzle_smoke, hit_effect, slash_effect, rocket_explosion 등 일회성 GPUParticles3D에 공용으로 사용합니다.

func _ready() -> void:
	if _is_prewarm_mode():
		emitting = false
		for child in get_children():
			if child is GPUParticles3D:
				child.emitting = false
		return

	if not VfxBudget.allow_spawn(get_tree(), _budget_key(), global_position, _budget_limit(), _budget_distance()):
		queue_free()
		return

	emitting = true
	# 자식 파티클도 함께 emit
	var max_life = lifetime
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = true
			max_life = max(max_life, child.lifetime)
	get_tree().create_timer(max_life + 0.3).timeout.connect(queue_free)

func _is_prewarm_mode() -> bool:
	var n: Node = self
	while is_instance_valid(n):
		if n.has_meta("prewarm_mode") and bool(n.get_meta("prewarm_mode")):
			return true
		n = n.get_parent()
	return false

func _budget_key() -> String:
	match name:
		"WaterExplosion":
			return "water_explosion"
		"MuzzleSmoke":
			return "muzzle_smoke"
		"HitEffect":
			return "hit_effect"
		"BloodMist":
			return "blood_mist"
		"RocketExplosion":
			return "rocket_explosion"
	return name.to_snake_case()

func _budget_limit() -> int:
	match name:
		"WaterExplosion":
			return 4
		"MuzzleSmoke":
			return 5
		"HitEffect":
			return 8
		"BloodMist":
			return 5
		"RocketExplosion":
			return 5
	return 6

func _budget_distance() -> float:
	match name:
		"WaterExplosion":
			return 70.0
		"MuzzleSmoke":
			return 65.0
		"HitEffect":
			return 55.0
		"BloodMist":
			return 45.0
		"RocketExplosion":
			return 90.0
	return 60.0
