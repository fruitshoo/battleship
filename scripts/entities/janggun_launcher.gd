extends Node3D

## 장군전 발사기 (Janggun Launcher)
## 통나무 미사일을 발사. 고데미지, 긴 쿨다운.

@export var missile_scene: PackedScene = preload("res://scenes/projectiles/janggun_missile.tscn")
@export var fire_cooldown: float = 12.0
@export var detection_range: float = 35.0
@export var damage: float = 10.0

var cooldown_timer: float = 0.0


func _process(delta: float) -> void:
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	var nearest = _find_nearest_enemy()
	if nearest:
		fire(nearest)


func _find_nearest_enemy() -> Node3D:
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var min_dist: float = detection_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
	
	return nearest


func fire(target: Node3D) -> void:
	if not missile_scene: return
	cooldown_timer = fire_cooldown
	
	var missile = missile_scene.instantiate()
	missile.start_pos = global_position + Vector3(0, 1.0, 0)
	
	# 예측 사격 (Predictive Aiming)
	var dist = global_position.distance_to(target.global_position)
	var projectile_speed = 18.0 # janggun_missile.gd의 기본 속도
	var travel_time = dist / projectile_speed
	
	# 타겟의 속도와 방향 가져오기
	var target_speed = 0.0
	if "current_speed" in target:
		target_speed = target.current_speed
	elif "move_speed" in target: # chaser_ship 등
		target_speed = target.move_speed
		
	var target_dir = - target.global_transform.basis.z
	var target_velocity = target_dir * target_speed
	
	# 예상 도달 위치 계산
	var predicted_pos = target.global_position + (target_velocity * travel_time)
	
	missile.target_pos = predicted_pos
	missile.damage = damage
	
	get_tree().root.add_child(missile)
	missile.global_position = missile.start_pos
	
	print("🪵 장군전 예측 사격 발사! (예상 시간: %.1fs)" % travel_time)
