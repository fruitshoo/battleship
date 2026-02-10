extends Node

## 레벨 매니저 (Level Manager)
## 게임 시간 경과에 따라 난이도(레벨)를 관리하고 스포너에게 지시

signal level_up(new_level: int)
signal score_changed(new_score: int)
signal enemy_destroyed_count(count: int)

@export var level_duration: float = 30.0 # 레벨업 간격 (초)
@export var max_level: int = 10
@export var hud: CanvasLayer = null

var current_level: int = 1
var current_score: int = 0
var current_time: float = 0.0

# 레벨별 난이도 설정
var level_data = {
	1: {"spawn_interval": 5.0, "max_enemies": 3, "enemy_speed": 3.5},
	2: {"spawn_interval": 4.5, "max_enemies": 5, "enemy_speed": 3.7},
	3: {"spawn_interval": 4.0, "max_enemies": 8, "enemy_speed": 4.0},
	4: {"spawn_interval": 3.5, "max_enemies": 12, "enemy_speed": 4.3},
	5: {"spawn_interval": 3.0, "max_enemies": 15, "enemy_speed": 4.6},
	6: {"spawn_interval": 2.5, "max_enemies": 20, "enemy_speed": 5.0},
	7: {"spawn_interval": 2.0, "max_enemies": 25, "enemy_speed": 5.5},
	8: {"spawn_interval": 1.5, "max_enemies": 30, "enemy_speed": 6.0},
	9: {"spawn_interval": 1.0, "max_enemies": 40, "enemy_speed": 7.0},
	10: {"spawn_interval": 0.5, "max_enemies": 50, "enemy_speed": 8.0}
}

# 참조
@export var enemy_spawner: Node = null

func _ready() -> void:
	# 초기 HUD 업데이트
	if hud:
		hud.update_level(current_level)
		hud.update_score(current_score)

func _process(delta: float) -> void:
	current_time += delta
	
	# 레벨업 체크
	var calculated_level = int(current_time / level_duration) + 1
	calculated_level = min(calculated_level, max_level)
	
	if calculated_level > current_level:
		_set_level(calculated_level)
	
	# 주기적으로 적 수 체크 (HUD용)
	if Engine.get_process_frames() % 30 == 0:
		_update_enemy_count_ui()

func _update_enemy_count_ui() -> void:
	if hud:
		var count = get_tree().get_nodes_in_group("enemy").size()
		hud.update_enemy_count(count)

func add_score(points: int) -> void:
	current_score += points
	score_changed.emit(current_score)
	if hud:
		hud.update_score(current_score)

func _set_level(new_level: int) -> void:
	current_level = new_level
	level_up.emit(current_level)
	if hud:
		hud.update_level(current_level)
	print("Level Up! Current Level: %d" % current_level)
	
	_update_difficulty()


func _update_difficulty() -> void:
	if not enemy_spawner:
		return
		
	var data = level_data.get(current_level, level_data[max_level])
	
	# 스포너 설정 업데이트
	if enemy_spawner.has_method("set_difficulty"):
		enemy_spawner.set_difficulty(data["spawn_interval"], data["max_enemies"], data["enemy_speed"])
	else:
		# 직접 프로퍼티 수정 (fallback)
		enemy_spawner.spawn_interval = data["spawn_interval"]
		enemy_spawner.max_enemies = data["max_enemies"]
		if "enemy_speed" in enemy_spawner:
			enemy_spawner.enemy_speed = data["enemy_speed"]
