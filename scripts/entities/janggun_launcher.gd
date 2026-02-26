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
	missile.target_pos = target.global_position
	missile.damage = damage
	
	get_tree().root.add_child(missile)
	missile.global_position = missile.start_pos
	
	print("🪵 장군전 발사!")
