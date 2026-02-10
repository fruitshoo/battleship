extends Node3D

## 메인 전장 초기화 스크립트

func _ready() -> void:
	# 초기 바람 설정 (서풍)
	if is_instance_valid(WindManager):
		WindManager.set_wind_angle(90.0)
		WindManager.set_wind_strength(0.7)
	
	print("=== 해전 게임 (Vampire Survivors Style) 시작 ===")
	print("조작법:")
	print("- Q/E: 돛 각도 조절")
	print("- A/D: 배 방향 조절 (러더)")
	print("- W/S: 노 젓기 (저속 추진)")
	print("- 적 배와 충돌 시 도선 전투가 발생합니다!")
