extends Node3D

## 신기전 발사기 (Singigeon Launcher)
## 로켓 화살을 전방으로 발사. 레벨에 따라 발수 증가.

@export var rocket_scene: PackedScene = preload("res://scenes/effects/singigeon_rocket.tscn")
@export var fire_cooldown: float = 4.0
@export var detection_range: float = 30.0
@export var shot_count: int = 1 # 레벨에 따라 1/3/5
@export var spread_angle: float = 0.0 # 레벨에 따라 0/8/12
@export var team: String = "player" # "player" or "enemy"

var cooldown_timer: float = 0.0


func _process(delta: float) -> void:
	var um = UpgradeManager if is_instance_valid(UpgradeManager) else null
	var current_cooldown = fire_cooldown
	if um:
		var train_lv = um.current_levels.get("training", 0)
		current_cooldown = fire_cooldown * (1.0 - 0.1 * train_lv)
		
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	# 가장 가까운 적 찾기
	var nearest = _find_nearest_enemy()
	if nearest:
		fire(nearest, current_cooldown)


func _find_nearest_enemy() -> Node3D:
	var enemy_group = "enemy" if team == "player" else "player"
	var enemies = get_tree().get_nodes_in_group(enemy_group)
	var nearest: Node3D = null
	var min_dist: float = detection_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
	
	return nearest


func fire(target: Node3D, cooldown_override: float = -1.0) -> void:
	if not rocket_scene: return
	cooldown_timer = cooldown_override if cooldown_override > 0 else fire_cooldown
	
	# MLRS 스타일: 연사 (Sequential Fire)
	for i in range(shot_count):
		if not is_instance_valid(target): break
		
		var rocket = rocket_scene.instantiate()
		var side_offset = 0.3 if i % 2 == 0 else -0.3
		var spawn_pos = global_position + Vector3(0, 0.5, 0) + (basis.x * side_offset)
		
		# 포물선 비행을 위해 위치 데이터 전달
		rocket.start_pos = spawn_pos
		rocket.target_pos = target.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		
		# 발사 주체 (팀) 전달
		if "team" in rocket:
			rocket.team = self.team
		
		get_tree().root.add_child(rocket)
		rocket.global_position = spawn_pos
		
		# 발사 사운드
		if is_instance_valid(AudioManager):
			AudioManager.play_sfx("rocket_launch", global_position)
		
		# 연사 간격 (0.12초)
		await get_tree().create_timer(0.12).timeout


## 업그레이드 시 호출
func upgrade_to_level(level: int) -> void:
	match level:
		1:
			shot_count = 1
			spread_angle = 0.0
		2:
			shot_count = 3
			spread_angle = 8.0
		3:
			shot_count = 5
			spread_angle = 12.0
	print("🚀 신기전 Lv.%d (%d발, ±%.0f°)" % [level, shot_count, spread_angle])
