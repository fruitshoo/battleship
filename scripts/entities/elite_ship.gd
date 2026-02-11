extends "res://scripts/entities/chaser_ship.gd"

## 엘리트 함선 (Elite Ship / Mid-Boss)
## 추격선보다 강하고 거대하며, 처치 시 보물 상자를 드랍함.

@export var chest_scene: PackedScene = preload("res://scenes/effects/treasure_chest.tscn")

func _ready() -> void:
	super._ready()
	add_to_group("elite")
	
	# 엘리트 특성 부여
	max_hp *= 3.0
	hp = max_hp
	move_speed *= 0.8 # 덩치가 커서 조금 느림
	
	# 시각적으로 크게 만듦
	scale = Vector3(1.8, 1.8, 1.8)
	
	# 색상 변경 등을 위해 메쉬 마테리얼 조정 (필요 시)
	_apply_elite_visuals()

func _apply_elite_visuals() -> void:
	# 시각적 구분 (황금색 띠 또는 붉은 입자 등)
	# 여기서는 간단하게 스케일만 키워도 효과가 크지만, 
	# 나중에 입자 효과를 추가하면 더 좋음.
	pass

func die() -> void:
	if is_dying: return
	
	# 보물 상자 드랍
	_drop_treasure_chest()
	
	super.die()

func _drop_treasure_chest() -> void:
	if not chest_scene: return
	
	var chest = chest_scene.instantiate()
	get_tree().root.add_child(chest)
	chest.global_position = global_position
	chest.global_position.y = 0 # 해수면
	
	print("💎 엘리트 격침! 보물 상자 드랍.")
