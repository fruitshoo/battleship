extends Node

## 적 생성 관리자 (Enemy Spawner)
## 플레이어 주변 화면 밖에서 적을 주기적으로 생성

@export var enemy_scene: PackedScene = preload("res://scenes/enemy_ship.tscn")
@export var spawn_interval: float = 6.0 # 생성 주기 (초)
@export var min_spawn_distance: float = 40.0 # 최소 생성 거리
@export var max_spawn_distance: float = 60.0 # 최대 생성 거리
@export var max_enemies: int = 20 # 최대 적 수
@export var current_enemy_speed: float = 3.0 # 레벨에 따른 적 속도
@export var current_enemy_hp: float = 3.0 # 레벨에 따른 적 체력
@export var current_boarders: int = 1 # 레벨에 따른 도선 병사 수
@export var max_distance_limit: float = 120.0 # 재배치 거리
@export var reposition_check_interval: float = 1.0 # 재배치 체크 주기

@export var boss_scene: PackedScene = preload("res://scenes/entities/boss_ship.tscn")

var timer: float = 0.0
var reposition_timer: float = 0.0
var player: Node3D = null
var boss_spawned: bool = false
var elite_spawn_timer: float = 180.0 # 3분 주기
var regular_spawn_stopped: bool = false


func trigger_boss_event() -> void:
	regular_spawn_stopped = true
	print("🚨 보스 등장 이벤트 시작! 일반 적 스폰 중단")
	
	# 모든 일반 적 제거 (선택사항 - 더 극적인 연출을 위해)
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not enemy.is_in_group("boss") and enemy.has_method("die"):
			enemy.die()
	
	# 보스 소환
	_spawn_boss()


func _spawn_boss() -> void:
	if not boss_scene or boss_spawned: return
	boss_spawned = true
	
	var boss = boss_scene.instantiate()
	# 플레이어 전방 50m 지점에 소환
	var player_forward = - player.global_transform.basis.z
	var spawn_pos = player.global_position + (player_forward * 50.0)
	spawn_pos.y = 0
	
	get_parent().add_child(boss)
	boss.global_position = spawn_pos
	boss.look_at(player.global_position, Vector3.UP)
	print("👑 최종 보스 소환 완료!")


func set_difficulty(new_interval: float, new_max: int, new_speed: float, new_hp: float = 5.0, new_boarders: int = 2) -> void:
	spawn_interval = new_interval
	max_enemies = new_max
	current_enemy_speed = new_speed
	current_enemy_hp = new_hp
	current_boarders = new_boarders
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
	var elite_count = get_tree().get_nodes_in_group("elite").size()
	
	if not regular_spawn_stopped:
		# 1-1. 엘리트 소환 주기 체크
		elite_spawn_timer -= delta
		if elite_spawn_timer <= 0:
			elite_spawn_timer = 180.0
			_spawn_elite_ship()
		
		# 1-2. 일반 적 스폰 (엘리트가 있으면 최대 적 수 제한을 낮춰서 긴장감 조절)
		var effective_max = max_enemies if elite_count == 0 else int(max_enemies * 0.6)
		if enemies.size() < effective_max:
			timer -= delta
			if timer <= 0:
				timer = compute_next_interval()
				_spawn_enemy()
	
	# 2. 너무 멀어진 적 재배치 (Tension 유지) - 부하 분산을 위해 매 프레임 조금씩 체크
	if not enemies.is_empty():
		_check_enemy_reposition_incremental(enemies)

func _check_enemy_reposition_incremental(enemies: Array) -> void:
	# 한 프레임에 최대 3개까지만 체크
	var check_count = min(3, enemies.size())
	for i in range(check_count):
		# 랜덤하게 하나 골라 체크 (순차적으로 하려면 index 관리가 필요하므로 간단히 랜덤 선택)
		var enemy = enemies.pick_random()
		if not is_instance_valid(enemy) or enemy.get("is_dying"): continue
		
		var dist = enemy.global_position.distance_to(player.global_position)
		if dist > max_distance_limit:
			var spawn_pos = _get_biased_spawn_position()
			enemy.global_position = spawn_pos
			if enemy.has_method("look_at"):
				enemy.look_at(player.global_position, Vector3.UP)


func compute_next_interval() -> float:
	# 약간의 랜덤성 추가 (±20%)
	return spawn_interval * randf_range(0.8, 1.2)

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

func _spawn_enemy() -> void:
	if not enemy_scene:
		return
		
	var enemy = enemy_scene.instantiate()
	
	# 스폰 위치 계산 (전방 편향)
	var spawn_pos = _get_biased_spawn_position()
	enemy.position = spawn_pos
	
	# Main 씬에 추가
	get_parent().add_child(enemy)
	
	# 초기 회전: 플레이어를 바라보게
	enemy.look_at(player.global_position, Vector3.UP)
	
	# 레벨 기반 스탯 설정
	if "move_speed" in enemy:
		enemy.move_speed = current_enemy_speed
	if "hp" in enemy:
		enemy.hp = current_enemy_hp
	if "boarders_count" in enemy:
		enemy.boarders_count = current_boarders


## 스폰 위치 계산 (플레이어 전방 70% 편향)
func _get_biased_spawn_position() -> Vector3:
	var angle: float
	
	if randf() < 0.7:
		# 70% 확률: 플레이어 전방 ±60도 범위
		var player_heading = player.rotation.y
		angle = player_heading + randf_range(-deg_to_rad(60), deg_to_rad(60))
	else:
		# 30% 확률: 완전 랜덤
		angle = randf() * TAU
	
	var distance = randf_range(min_spawn_distance, max_spawn_distance)
	var offset = Vector3(cos(angle), 0, sin(angle)) * distance
	var spawn_pos = player.global_position + offset
	spawn_pos.y = 0 # 배는 물 위에
	return spawn_pos


func _spawn_elite_ship() -> void:
	if not enemy_scene: return
	
	# 엘리트는 일반 적 베이스지만 elite_ship.gd 스크립트를 동적으로 붙이거나 
	# (여유가 있다면) 전용 씬을 사용. 여기서는 일반 적을 인스턴스화 후 스크립트 교체 방식 사용.
	var enemy = enemy_scene.instantiate()
	
	# 수동으로 스크립트 설정 (elite_ship.gd는 chaser_ship.gd를 확장함)
	var elite_script = load("res://scripts/entities/elite_ship.gd")
	enemy.set_script(elite_script)
	
	# 스폰 위치 (전방 먼 곳)
	var spawn_pos = _get_biased_spawn_position()
	enemy.position = spawn_pos
	
	get_parent().add_child(enemy)
	enemy.look_at(player.global_position, Vector3.UP)
	
	# 엘리트 전용 메타데이터 (필요 시)
	print("🚨 엘리트 함선(중간보스) 출현!")
