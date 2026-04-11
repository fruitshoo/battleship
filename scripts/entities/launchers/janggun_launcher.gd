extends Node3D
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
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
var _cached_target: Node3D = null
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
	if _owner_ship.has_method("is_combat_disabled") and _owner_ship.is_combat_disabled():
		return false
	return true

func _is_target_valid(target: Variant) -> bool:
	if not is_instance_valid(target) or not (target is Node3D):
		return false
	var target_node := target as Node3D
	if target_node.is_queued_for_deletion():
		return false
	if target_node.has_method("is_combat_disabled") and target_node.is_combat_disabled():
		return false
	return global_position.distance_squared_to(target_node.global_position) <= detection_range * detection_range


func _find_nearest_enemy() -> Node3D:
	var enemies = EntityRegistry.get_ships_by_team("enemy" if team == "player" else "player")
	var nearest: Node3D = null
	var min_dist_sq: float = detection_range * detection_range
	
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		
		# 빈 배(폐선)는 타겟에서 제외
		if enemy.has_method("is_combat_disabled") and enemy.is_combat_disabled(): continue
		
		var dist_sq = global_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			nearest = enemy
	
	return nearest


func fire(target: Variant) -> void:
	if not missile_scene:
		return
	if not _is_owner_combat_ready():
		return
	if not _is_target_valid(target):
		return
	var target_node := target as Node3D
	if target_node.has_method("get_hull_hp_value") and float(target_node.get_hull_hp_value()) <= 0.0:
		return
	
	var um = get_node_or_null("/root/UpgradeManager")
	var janggun_lv = 0
	if is_instance_valid(um) and "current_levels" in um:
		janggun_lv = um.current_levels.get("janggun", 0)
		
	# 5레벨 체계: 쿨다운 감소폭 상향 (레벨당 1.4초 감소, 5레벨에서 약 5초대 도달)
	cooldown_timer = maxf(5.0, fire_cooldown - janggun_lv * 1.4)
	
	var missile = ScenePool.acquire(get_tree(), missile_scene)
	missile.start_pos = global_position + Vector3(0, 1.0, 0)
	
	# 예측 사격 (Predictive Aiming)
	var dist = global_position.distance_to(target_node.global_position)
	# 레벨당 속도 증가폭 상향 (0.1 -> 0.15)
	var projectile_speed = 18.0 * (1.0 + janggun_lv * 0.15)
	var travel_time = dist / projectile_speed
	
	# 타겟의 속도와 방향 가져오기
	var target_speed = 0.0
	if "current_speed" in target_node:
		target_speed = target_node.current_speed
	elif "move_speed" in target_node: # chaser_ship 등
		target_speed = target_node.move_speed
		
	var target_dir = - target_node.global_transform.basis.z
	var target_velocity = target_dir * target_speed
	
	# 예상 도달 위치 계산
	var predicted_pos = target_node.global_position + (target_velocity * travel_time)
	
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
