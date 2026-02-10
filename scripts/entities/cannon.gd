extends Node3D

## 함포 (Cannon)
## 고정된 방향으로 적을 탐지하고 자동으로 발사함

@export var cannonball_scene: PackedScene = preload("res://scenes/effects/cannonball.tscn")
@export var fire_cooldown: float = 2.0
@export var detection_range: float = 25.0 # 사거리 추가 하향 (35.0 -> 25.0)
@export var detection_arc: float = 45.0 # 탐지 각도 (도)

@onready var detection_area: Area3D = $DetectionArea
@onready var muzzle: Marker3D = $Muzzle

var cooldown_timer: float = 0.0

func _process(delta: float) -> void:
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
		
	# 탐지 영역 내 적 확인
	var targets = detection_area.get_overlapping_areas() + detection_area.get_overlapping_bodies()
	var nearest_enemy: Node3D = null
	var min_dist = detection_range
	
	for target in targets:
		var enemy = target if target.is_in_group("enemy") else target.get_parent()
		if not (enemy and enemy.is_in_group("enemy")): continue
			
		# 예측 사격 로직 (Lead Targeting)
		var enemy_pos = enemy.global_position
		var dist = global_position.distance_to(enemy_pos)
		
		if dist < min_dist:
			# 적의 이동 방향과 속도 추정
			var enemy_speed = 3.5 # 기본값 (chaser_ship.gd의 move_speed)
			if "move_speed" in enemy: enemy_speed = enemy.move_speed
			
			var enemy_dir = - enemy.global_transform.basis.z # enemy.look_at(player) 이므로 -z가 전진방향
			var enemy_velocity = enemy_dir * enemy_speed
			
			# 도달 시간 계산 (포탄 속도 약 100)
			var time_to_hit = dist / 100.0
			var predicted_pos = enemy_pos + enemy_velocity * time_to_hit
			
			# 예측 지점이 사격 각도 내에 있는지 확인
			var to_predicted = (predicted_pos - global_position).normalized()
			var dot = - global_transform.basis.z.dot(to_predicted)
			var angle = rad_to_deg(acos(clamp(dot, -1, 1)))
			
			if angle < detection_arc:
				min_dist = dist
				nearest_enemy = enemy
					
	if nearest_enemy:
		fire(nearest_enemy)


func fire(target_enemy: Node3D) -> void:
	if not cannonball_scene: return
	
	cooldown_timer = fire_cooldown
	
	var ball = cannonball_scene.instantiate()
	# 대포알은 월드 루트에 추가하여 배의 움직임과 분리
	get_tree().root.add_child(ball)
	
	ball.global_position = muzzle.global_position
	# 대포가 바라보는 방향으로 발사
	ball.direction = - global_transform.basis.z
	ball.target_node = target_enemy # 유도 대상 전달
	ball.look_at(ball.global_position + ball.direction, Vector3.UP)
	
	# 발사 효과 (사운드/이펙트 추후 추가)
	# print("💥 Cannon Fired!")
