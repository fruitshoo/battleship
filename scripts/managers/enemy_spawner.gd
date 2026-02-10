extends Node

## 적 생성 관리자 (Enemy Spawner)
## 플레이어 주변 화면 밖에서 적을 주기적으로 생성

@export var enemy_scene: PackedScene = preload("res://scenes/enemy_ship.tscn")
@export var spawn_interval: float = 5.0 # 생성 주기 (초)
@export var min_spawn_distance: float = 40.0 # 최소 생성 거리
@export var max_spawn_distance: float = 60.0 # 최대 생성 거리
@export var max_enemies: int = 20 # 최대 적 수
@export var current_enemy_speed: float = 3.5 # 레벨에 따른 적 속도
@export var max_distance_limit: float = 120.0 # 이 거리보다 멀어지면 텔레포트 (Vampire Survivors 스타일)
@export var reposition_check_interval: float = 1.0 # 재배치 체크 주기

var timer: float = 0.0
var reposition_timer: float = 0.0
var player: Node3D = null

## 외부(LevelManager)에서 난이도 조절용
func set_difficulty(new_interval: float, new_max: int, new_speed: float) -> void:
	spawn_interval = new_interval
	max_enemies = new_max
	current_enemy_speed = new_speed
	# timer가 너무 길게 남았으면 즉시 단축
	if timer > spawn_interval:
		timer = spawn_interval

func _ready() -> void:
	timer = spawn_interval
	reposition_timer = reposition_check_interval
	_find_player()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		_find_player()
		return
		
	# 1. 적 생성 주기 관리
	var enemies = get_tree().get_nodes_in_group("enemy")
	if enemies.size() < max_enemies:
		timer -= delta
		if timer <= 0:
			timer = compute_next_interval()
			_spawn_enemy()
	
	# 2. 너무 멀어진 적 재배치 (Tension 유지)
	reposition_timer -= delta
	if reposition_timer <= 0:
		reposition_timer = reposition_check_interval
		_check_enemy_reposition(enemies)

func _check_enemy_reposition(enemies: Array) -> void:
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		
		var dist = enemy.global_position.distance_to(player.global_position)
		if dist > max_distance_limit:
			# 플레이어 주변 랜덤 위치로 텔레포트
			var angle = randf() * TAU
			var distance = randf_range(min_spawn_distance + 10.0, max_spawn_distance + 10.0) # 약간 더 멀리서 나타나게
			var offset = Vector3(cos(angle), 0, sin(angle)) * distance
			
			enemy.global_position = player.global_position + offset
			enemy.look_at(player.global_position, Vector3.UP)
			# print("Enemy repositioned: ", enemy.name)


func compute_next_interval() -> float:
	# 시간이 지날수록(또는 적이 많을수록) 빨라지게 할 수도 있음
	# 일단 고정
	return spawn_interval

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

func _spawn_enemy() -> void:
	if not enemy_scene:
		return
		
	var enemy = enemy_scene.instantiate()
	
	# 랜덤 위치 계산 (플레이어 주변 원형)
	var angle = randf() * TAU # 0 ~ 2PI
	var distance = randf_range(min_spawn_distance, max_spawn_distance)
	
	var offset = Vector3(cos(angle), 0, sin(angle)) * distance
	var spawn_pos = player.global_position + offset
	spawn_pos.y = 0 # 배는 물 위에
	
	enemy.position = spawn_pos
	
	# Main 씬(이 노드의 부모)에 추가
	get_parent().add_child(enemy)
	
	# 초기 회전: 플레이어를 바라보게
	enemy.look_at(player.global_position, Vector3.UP)
	
	# 레벨 기반 속도 설정
	if "move_speed" in enemy:
		enemy.move_speed = current_enemy_speed
