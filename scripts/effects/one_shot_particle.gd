extends GPUParticles3D

## 원샷 파티클 — 재생 즉시 emit을 시작하고, 수명이 다하면 자동으로 노드를 제거합니다.
## muzzle_smoke, hit_effect, slash_effect, rocket_explosion 등 일회성 GPUParticles3D에 공용으로 사용합니다.

func _ready() -> void:
	emitting = true
	# 자식 파티클도 함께 emit
	var max_life = lifetime
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = true
			max_life = max(max_life, child.lifetime)
	get_tree().create_timer(max_life + 0.3).timeout.connect(queue_free)
