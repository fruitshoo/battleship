extends Node3D
class_name SoldierWeapon

## 병사가 사용하는 무기의 베이스 클래스

@export var damage: float = 10.0
@export var attack_range: float = 1.2
@export var attack_cooldown: float = 1.0

# 병사가 공격할 때 호출하는 함수 (자식에서 오버라이드 됨)
func attack(_target: Node3D, _attacker: Node3D) -> void:
	pass

# 씬에 있는 무기 메쉬의 가시성을 설정하는 헬퍼
func set_visual_visible(make_visible: bool) -> void:
	if has_node("Visual"):
		$Visual.visible = make_visible
