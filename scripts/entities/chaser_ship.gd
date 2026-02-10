extends Node3D

## 추적선 (Chaser Ship)
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var move_speed: float = 3.5 # 플레이어보다 약간 빠르게? (4.0 -> 3.5 너프)
@export var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
@export var boarders_count: int = 2 # 도선시킬 병사 수

@export var hp: float = 1.0 # 체력 (대포 한 방)

var target: Node3D = null

func die() -> void:
	# 점수 추가
	var lm = get_tree().root.find_child("LevelManager", true, false)
	if lm and lm.has_method("add_score"):
		lm.add_score(100)
		
	# 파괴 효과 (추후 구현)
	queue_free()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		_find_player()
		return
	
	# 1. 플레이어 바라보기
	look_at(target.global_position, Vector3.UP)
	
	# 2. 전진 (단순 등속)
	var dir = global_position.direction_to(target.global_position)
	dir.y = 0 # 수평 이동만
	global_position += dir * move_speed * delta


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]


## 충돌 감지 (Area3D signal 연결 필요)
func _on_body_entered(body: Node3D) -> void:
	# 플레이어와 충돌했는지 확인 (StaticBody/CharacterBody 등)
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		_board_ship(body)

func _on_area_entered(area: Area3D) -> void:
	# 플레이어의 감지 영역(ProximityArea)과 충돌했는지 확인
	# ProximityArea의 부모가 PlayerShip인지 확인
	var parent = area.get_parent()
	if parent and parent.is_in_group("player"):
		_board_ship(parent)


func _board_ship(target_ship: Node3D) -> void:
	# 대상이 진짜 배인지 확인 (충돌체가 배의 자식일 수 있음)
	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not ship_node.is_in_group("player"):
			return # 배가 아니면 무시

	# 병사 소환
	if soldier_scene:
		# Soldiers 노드 찾기 (없으면 배 자체에 붙임)
		var soldiers_root = ship_node.get_node_or_null("Soldiers")
		if not soldiers_root:
			soldiers_root = ship_node
		
		for i in range(boarders_count):
			var soldier = soldier_scene.instantiate()
			soldiers_root.add_child(soldier)
			
			# 적 팀 설정
			soldier.set_team("enemy")
			
			# 위치 설정 (배의 로컬 좌표계로 변환하거나 global로 설정 후 parent)
			# add_child 후 global_position 설정이 안전
			# 충돌 지점 근처나 배 위 랜덤 위치
			var random_offset = Vector3(randf_range(-1, 1), 1.0, randf_range(-2, 2))
			soldier.global_position = ship_node.global_position + random_offset
	
	# 쾅! 이펙트 (추후 구현)
	# ...
	
	# 자폭 (침몰)
	queue_free()
