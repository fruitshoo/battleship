extends Node3D
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const LauncherCombatHelper = preload("res://scripts/entities/launchers/launcher_combat_helper.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")

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
	if _target_scan_left <= 0.0 or not _is_target_valid(current_target):
		_update_target()
		_target_scan_left = _get_target_scan_interval(_is_target_valid(current_target))
	
	if _is_target_valid(current_target):
		fire(current_target)
	else:
		current_target = null

func _get_target_scan_interval(has_valid_target: bool) -> float:
	return LauncherCombatHelper.get_target_scan_interval(target_scan_interval, target_tracking_scan_multiplier, has_valid_target)

func _resolve_owner_ship() -> Node:
	return LauncherCombatHelper.resolve_owner_ship(self)

func _is_owner_combat_ready() -> bool:
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	return LauncherCombatHelper.is_owner_combat_ready(_owner_ship)

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var min_dist_sq = detection_range * detection_range
	
	var soldiers = EntityRegistry.get_soldiers_by_team(LauncherCombatHelper.enemy_team_tag(team))
	
	for s in soldiers:
		if not LauncherCombatHelper.is_enemy_soldier_target(s, team, self, detection_range):
			continue
		var soldier := s as Node3D
		var dist_sq = global_position.distance_squared_to(soldier.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			nearest_enemy = soldier
	
	current_target = nearest_enemy

func _is_target_valid(target: Variant) -> bool:
	return LauncherCombatHelper.is_enemy_soldier_target(target, team, self, detection_range)

func fire(target: Node3D) -> void:
	if not _is_owner_combat_ready() or not _is_target_valid(target):
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
	var aim_pos: Vector3 = NodeContractHelper.get_projectile_aim_point(target, 0.55)
	var dir = (aim_pos - spawn_pos).normalized()
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
