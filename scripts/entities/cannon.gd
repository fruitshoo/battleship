extends Node3D

## 함포 (Cannon)
## 범위 내 적을 탐지하고 자동으로 발사 (Area3D 대신 직접 탐지)

@export var cannonball_scene: PackedScene = preload("res://scenes/effects/cannonball.tscn")
@export var fire_cooldown: float = 2.0
@export var detection_range: float = 25.0
@export var detection_arc: float = 25.0 # 탐지 각도 (±25도)
@export var team: String = "player" # "player" or "enemy"

@onready var muzzle: Marker3D = $Muzzle

var cooldown_timer: float = 0.0


func _process(delta: float) -> void:
	var um = UpgradeManager if is_instance_valid(UpgradeManager) else null
	var current_cooldown = fire_cooldown
	if um:
		var train_lv = um.current_levels.get("training", 0)
		current_cooldown *= (1.0 - 0.1 * train_lv)
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	# 직접 적 탐지 (Area3D 사용 안 함 — 동적 인스턴스에서도 확실히 작동)
	var nearest_enemy: Node3D = null
	var min_dist: float = detection_range
	
	var enemy_group = "enemy" if team == "player" else "player"
	var enemies = get_tree().get_nodes_in_group(enemy_group)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		
		var dist = global_position.distance_to(enemy.global_position)
		if dist > detection_range:
			continue
		
		# 대포가 바라보는 방향 기준 각도 체크
		var to_enemy = (enemy.global_position - global_position).normalized()
		var forward = - global_transform.basis.z
		var dot = forward.dot(to_enemy)
		var angle = rad_to_deg(acos(clamp(dot, -1.0, 1.0)))
		
		if angle < detection_arc and dist < min_dist:
			min_dist = dist
			nearest_enemy = enemy
	
	if nearest_enemy:
		fire(nearest_enemy)


func fire(target_enemy: Node3D) -> void:
	if not cannonball_scene: return
	
	# 사운드 재생
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("cannon_fire", global_position)
	
	# 쿨타임 시작
	cooldown_timer = fire_cooldown # Changed from current_cooldown = fire_interval to match existing variable names
	
	var ball = cannonball_scene.instantiate()
	get_tree().root.add_child(ball)
	
	ball.global_position = muzzle.global_position
	
	# 데미지 계산 (속성 반영)
	var base_dmg = 25.0 # 대포알 기본 데미지 상향
	if is_instance_valid(UpgradeManager):
		var iron_lv = UpgradeManager.current_levels.get("iron_armor", 0)
		base_dmg *= (1.0 + 0.25 * iron_lv)
	ball.damage = base_dmg
	
	# 예측 사격: 적의 예상 위치를 향해 발사
	var dist = global_position.distance_to(target_enemy.global_position)
	var time_to_hit = dist / 100.0
	
	var enemy_speed = 3.5
	if "move_speed" in target_enemy: enemy_speed = target_enemy.move_speed
	var enemy_dir = - target_enemy.global_transform.basis.z
	var enemy_velocity = enemy_dir * enemy_speed
	
	var predicted_pos = target_enemy.global_position + enemy_velocity * time_to_hit
	ball.direction = (predicted_pos - muzzle.global_position).normalized()
	ball.target_node = target_enemy
	ball.look_at(ball.global_position + ball.direction, Vector3.UP)
