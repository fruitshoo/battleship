extends Node3D
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")

## 팔우노 (Ballista Launcher)
## 적 병사를 조준하여 강력한 관통 화살을 발사합니다.

@export var bolt_scene: PackedScene = preload("res://scenes/projectiles/ballista_bolt.tscn")
@export var fire_cooldown: float = 10.0
@export var detection_range: float = 28.0 # 대포보다 긴 사거리
@export_range(0.05, 1.0) var target_scan_interval: float = 0.16
@export_range(1.0, 6.0) var target_tracking_scan_multiplier: float = 2.8
@export var team: String = "player"

@onready var muzzle: Marker3D = $Muzzle

var cooldown_timer: float = 0.0
var current_target: Node3D = null
var _target_scan_left: float = 0.0
var _owner_ship: Node = null

# 업그레이드 수치 캐싱
var _cached_dmg_mult: float = 1.0
var _cached_cd_mult: float = 1.0
var _cached_pierce: int = 3

func _ready() -> void:
	_update_cached_stats()
	_owner_ship = _resolve_owner_ship()
	_target_scan_left = randf_range(0.0, target_scan_interval)
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_signal("upgrade_applied"):
		upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id == "ballista":
		_update_cached_stats()

func _update_cached_stats() -> void:
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and "current_levels" in upgrade_manager:
		var lv = upgrade_manager.current_levels.get("ballista", 1)
		var s = upgrade_manager.UPGRADES.get("ballista", {}).get("stats", {})
		
		_cached_dmg_mult = 1.0 + (s.get("damage_per_lv", 15.0) / 45.0) * (lv - 1)
		_cached_cd_mult = maxf(0.5, 1.0 - (s.get("cooldown_reduce_per_lv", 1.0) / 10.0) * (lv - 1))
		_cached_pierce = int(s.get("base_pierce", 3) + (lv - 1) * s.get("pierce_per_lv", 1))

func _process(delta: float) -> void:
	if not _is_owner_combat_ready():
		current_target = null
		return

	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	_target_scan_left -= delta
	if _target_scan_left <= 0.0 or not is_instance_valid(current_target):
		_update_target()
		_target_scan_left = _get_target_scan_interval(is_instance_valid(current_target))
	
	if is_instance_valid(current_target):
		# 사거리 체크
		if global_position.distance_squared_to(current_target.global_position) > detection_range * detection_range:
			current_target = null
		else:
			fire(current_target)

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

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var min_dist_sq = detection_range * detection_range
	
	var enemy_team = "enemy" if team == "player" else "player"
	var soldiers = SceneGroupCache.get_nodes(get_tree(), "soldiers")
	
	for s in soldiers:
		if not is_instance_valid(s) or s.get("current_state") == 4: # 4 = DEAD
			continue
		if s.get("team") != enemy_team:
			continue
			
		var dist_sq = global_position.distance_squared_to(s.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			nearest_enemy = s
	
	current_target = nearest_enemy

func fire(target: Node3D) -> void:
	if not _is_owner_combat_ready() or not is_instance_valid(target):
		current_target = null
		return
	cooldown_timer = fire_cooldown * _cached_cd_mult
	
	var bolt = ScenePool.acquire(get_tree(), bolt_scene)
	var spawn_pos = muzzle.global_position if is_instance_valid(muzzle) else (global_position + Vector3(0, 0.5, 0))
	# 아직 트리에 없는 발사체는 global_position 대신 루트 기준 로컬 position을 먼저 설정한다.
	bolt.position = spawn_pos
	bolt.team = team
	bolt.damage = 45.0 * _cached_dmg_mult
	bolt.max_pierce = _cached_pierce
	
	get_tree().root.add_child.call_deferred(bolt)
	
	# 조준 방향 (목표 병사 위치)
	var dir = (target.global_position - spawn_pos).normalized()
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	bolt.direction = dir
	var up_vec = Vector3.UP
	if absf(dir.dot(up_vec)) > 0.99:
		up_vec = Vector3.RIGHT
	bolt.basis = Basis.looking_at(dir, up_vec)
	
	# 사운드
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cannon_fire", global_position, 1.5) # 더 날카롭고 높은 피치 제안
