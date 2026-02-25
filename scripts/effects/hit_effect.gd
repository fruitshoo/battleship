extends GPUParticles3D

func _ready() -> void:
	emitting = true
	# 파티클 수명이 다하면 노드 자동 제거
	get_tree().create_timer(lifetime + 0.5).timeout.connect(queue_free)
