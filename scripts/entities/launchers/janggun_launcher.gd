extends Node3D
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
		_cached_target = null
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
	return LauncherCombatHelper.get_target_scan_interval(target_scan_interval, target_tracking_scan_multiplier, has_valid_target)

func _resolve_owner_ship() -> Node:
	return LauncherCombatHelper.resolve_owner_ship(self)

func _is_owner_combat_ready() -> bool:
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	return LauncherCombatHelper.is_owner_combat_ready(_owner_ship)

func _is_target_valid(target: Variant) -> bool:
	var target_node := LauncherCombatHelper.get_enemy_combat_target(target, team)
	if target_node == null:
		return false
	return LauncherCombatHelper.is_target_in_range(self, target_node, detection_range)


func _find_nearest_enemy() -> Node3D:
	var enemies = EntityRegistry.get_ships_by_team(LauncherCombatHelper.enemy_team_tag(team))
	var nearest: Node3D = null
	var min_dist_sq: float = detection_range * detection_range
	
	for enemy in enemies:
		var enemy_ship := LauncherCombatHelper.get_enemy_combat_target(enemy, team)
		if enemy_ship == null: continue
		
		var dist_sq = global_position.distance_squared_to(enemy_ship.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			nearest = enemy_ship
	
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
	
	var spawn_pos: Vector3 = global_position + Vector3(0, 1.0, 0)
	
	# 예측 사격 (Predictive Aiming)
	var target_aim_pos: Vector3 = NodeContractHelper.get_projectile_aim_point(target_node, 0.65)
	var dist = spawn_pos.distance_to(target_aim_pos)
	# 레벨당 속도 증가폭 상향 (0.1 -> 0.15)
	var projectile_speed = 16.5 * (1.0 + janggun_lv * 0.15)
	var travel_time = dist / projectile_speed
	
	# 타겟의 속도와 방향 가져오기
	var target_speed: float = NodeContractHelper.get_current_speed_value(target_node)
	var target_dir: Vector3 = target_node.get_move_direction_value() if target_node.has_method("get_move_direction_value") else - target_node.global_transform.basis.z
	target_dir.y = 0.0
	if target_dir.length_squared() > 0.001:
		target_dir = target_dir.normalized()
	else:
		target_dir = Vector3.FORWARD
	
	# 예상 도달 위치 계산
	var lead_offset: Vector3 = target_dir * target_speed * travel_time * 0.62
	var max_lead: float = clampf(dist * 0.24, 1.2, 5.5)
	if lead_offset.length() > max_lead:
		lead_offset = lead_offset.normalized() * max_lead
	var predicted_pos: Vector3 = target_aim_pos + lead_offset
	
	# 레벨당 데미지 증가폭 상향 (0.3 -> 0.5)
	var missile_damage: float = damage * (1.0 + janggun_lv * 0.5)
	
	var missile = ScenePool.acquire(get_tree(), missile_scene)
	get_tree().root.add_child(missile)
	if missile.has_method("launch"):
		missile.launch(spawn_pos, predicted_pos, team, missile_damage, projectile_speed, janggun_lv)
	else:
		missile.start_pos = spawn_pos
		missile.target_pos = predicted_pos
		missile.damage = missile_damage
		missile.speed = projectile_speed
		if "team" in missile:
			missile.team = team
		if "janggun_lv" in missile:
			missile.janggun_lv = janggun_lv
		missile.global_position = spawn_pos
	
	if DEBUG_COMBAT_LOGS:
		print("🪵 장군전 예측 사격 발사! (예상 시간: %.1fs)" % travel_time)
