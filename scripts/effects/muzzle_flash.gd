extends GPUParticles3D

## 머즐 플래시(발포 화염) 이펙트 스크립트
## 빛을 순식간에 어둡게 만들고 이펙트가 끝나면 자동으로 노드를 제거합니다.

@onready var flash_light: OmniLight3D = $FlashLight

func _ready() -> void:
	emitting = true
	
	# 라이트 페이드 아웃 애니메이션
	if flash_light:
		var tween = create_tween()
		tween.tween_property(flash_light, "light_energy", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 파티클 수명 + 약간의 여유 뒤에 자동 제거
	get_tree().create_timer(lifetime + 0.1).timeout.connect(queue_free)

## 대포에서 발사 방향을 주입받아 이펙트 회전을 맞춥니다.
func set_fire_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)
