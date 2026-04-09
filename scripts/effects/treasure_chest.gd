extends Node3D
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")

## 보물 상자 (Treasure Chest)
## 플레이어가 닿으면 특별한 업그레이드 보상을 제공

@export var collection_range: float = 4.0

var _is_collected: bool = false

func _ready() -> void:
	add_to_group("treasure_chest")
	# 부유 효과 (Tween)
	var tween = create_tween().set_loops()
	tween.tween_property(self , "position:y", 0.5, 1.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self , "position:y", 0.0, 1.5).set_trans(Tween.TRANS_SINE)
	
	# 회전 효과
	var rot_tween = create_tween().set_loops()
	rot_tween.tween_property(self , "rotation:y", rotation.y + TAU, 4.0)

func _process(_delta: float) -> void:
	if _is_collected: return
	
	# 플레이어 탐지 (Area3D가 없으므로 거리 체크)
	var p = EntityRegistry.get_first_ship_by_team("player") as Node3D
	if is_instance_valid(p) and global_position.distance_to(p.global_position) < collection_range:
		_collect()

func _collect() -> void:
	_is_collected = true
	
	# 시스템 알림
	print("[Treasure] 보물 상자 획득!")
	
	# 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("treasure_collect")
	
	# 레벨 매니저를 통해 업그레이드 메뉴 호출 (보물 상자 전용)
	var lm = LevelManagerRegistry.get_level_manager(get_tree())
	if lm and lm.has_method("_show_upgrade_ui"):
		# 보물 상자는 5개의 선택지 제공 및 특별 보너스
		lm.call_deferred("_show_upgrade_ui", 5)
	
	# 파티클 효과 (필요 시) 생성 후 제거
	queue_free()
