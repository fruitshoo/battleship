extends Node3D
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const DEBUG_COMBAT_LOGS := false

## 장군전 발사기 (Janggun Launcher)
## 통나무 미사일을 발사. 고데미지, 긴 쿨다운.

@export var missile_scene: PackedScene = preload("res://scenes/projectiles/janggun_missile.tscn")
@export var fire_cooldown: float = 12.0
@export var detection_range: float = 28.0
@export var damage: float = 10.0
@export_range(0.05, 0.5) var target_scan_interval: float = 0.2
@export var team: String = "player"

var cooldown_timer: float = 0.0
var _owner_ship: Node = null
var _target_scan_left: float = 0.0
var _cached_target: Variant = null
@export_range(1.0, 6.0) var target_tracking_scan_multiplier: float = 3.0

func _ready() -> void:
	_owner_ship = _resolve_owner_ship()
	_target_scan_left = randf_range(0.0, target_scan_interval)

func _process(delta: float) -> void:
	if not _is_owner_combat_ready():
		return
	
	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	_target_scan_left -= delta
	if _target_scan_left <= 0.0 or not _is_target_valid(_cached_target):
		_cached_target = _find_nearest_enemy()
		_target_scan_left = _get_target_scan_interval(_is_target_valid(_cached_target))
	
	if _is_target_valid(_cached_target):
		fire(_cached_target as Node3D)

func _get_target_scan_interval(has_valid_target: bool) -> float:
	var base_interval: float = target_scan_interval
	if has_valid_target:
		base_interval *= target_tracking_scan_multiplier
	return base_interval + randf_range(0.0, 0.05)

func _resolve_owner_ship() -> Node:
	var node: Node = get_parent()
	while is_instance_valid(node):
		if node.is_in_group("ships"):
			return node
		if "is_sinking" in node and "is_dying" in node:
			return node
		node = node.get_parent()
	return null

func _is_owner_combat_ready() -> bool:
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	if not is_instance_valid(_owner_ship):
		return true
	if _owner_ship.get("is_dying") or _owner_ship.get("is_sinking") or _owner_ship.get("is_derelict"):
		return false
	var owner_hp = _owner_ship.get("hull_hp")
	if owner_hp != null and float(owner_hp) <= 0.0:
		return false
	return true

func _is_target_valid(target: Variant) -> bool:
	if not is_instance_valid(target):
		return false
	if not (target is Node3D):
		return false
	var target_node := target as Node3D
	if target_node.get("is_derelict") == true or target_node.get("is_sinking") == true or target_node.get("is_dying") == true:
		return false
	var target_hp = target_node.get("hull_hp")
	if target_hp != null and float(target_hp) <= 0.0:
		return false
	return global_position.distance_squared_to(target_node.global_position) <= detection_range * detection_range


func _find_nearest_enemy() -> Node3D:
	var enemy_group = "enemy" if team == "player" else "player"
	var enemies = SceneGroupCache.get_nodes(get_tree(), enemy_group)
	var nearest: Node3D = null
	var min_dist_sq: float = detection_range * detection_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		
		# 빈 배(폐선)는 타겟에서 제외
		if enemy.get("is_derelict") == true: continue
		if enemy.get("is_sinking") == true or enemy.get("is_dying") == true: continue
		var enemy_hp = enemy.get("hull_hp")
		if enemy_hp != null and float(enemy_hp) <= 0.0: continue
		
		var dist_sq = global_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			nearest = enemy
	
	return nearest


func fire(target: Node3D) -> void:
	if not missile_scene:
		return
	if not _is_owner_combat_ready():
		return
	if not is_instance_valid(target) or target.get("is_sinking") == true or target.get("is_dying") == true:
		return
	var target_hp = target.get("hull_hp")
	if target_hp != null and float(target_hp) <= 0.0:
		return
	
	var um = get_node_or_null("/root/UpgradeManager")
	var janggun_lv = 0
	if is_instance_valid(um) and "current_levels" in um:
		janggun_lv = um.current_levels.get("janggun", 0)
		
	# 5레벨 체계: 쿨다운 감소폭 상향 (레벨당 1.4초 감소, 5레벨에서 약 5초대 도달)
	cooldown_timer = maxf(5.0, fire_cooldown - janggun_lv * 1.4)
	
	var missile = missile_scene.instantiate()
	missile.start_pos = global_position + Vector3(0, 1.0, 0)
	
	# 예측 사격 (Predictive Aiming)
	var dist = global_position.distance_to(target.global_position)
	# 레벨당 속도 증가폭 상향 (0.1 -> 0.15)
	var projectile_speed = 18.0 * (1.0 + janggun_lv * 0.15)
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
	# 레벨당 데미지 증가폭 상향 (0.3 -> 0.5)
	missile.damage = damage * (1.0 + janggun_lv * 0.5)
	missile.speed = projectile_speed
	if "team" in missile:
		missile.team = team
	if "janggun_lv" in missile:
		missile.janggun_lv = janggun_lv
	
	get_tree().root.add_child(missile)
	missile.global_position = missile.start_pos
	
	if DEBUG_COMBAT_LOGS:
		print("🪵 장군전 예측 사격 발사! (예상 시간: %.1fs)" % travel_time)
