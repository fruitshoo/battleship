extends Node3D

## 팔우노 (Ballista Launcher)
## 적 병사를 조준하여 강력한 관통 화살을 발사합니다.

@export var bolt_scene: PackedScene = preload("res://scenes/projectiles/ballista_bolt.tscn")
@export var fire_cooldown: float = 10.0
@export var detection_range: float = 35.0 # 대포보다 긴 사거리
@export var team: String = "player"

@onready var muzzle: Marker3D = $Muzzle

var cooldown_timer: float = 0.0
var current_target: Node3D = null
var _search_tick: int = 0

# 업그레이드 수치 캐싱
var _cached_dmg_mult: float = 1.0
var _cached_cd_mult: float = 1.0
var _cached_pierce: int = 3

func _ready() -> void:
	_update_cached_stats()
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
	var ship = get_parent()
	if is_instance_valid(ship) and (ship.get("is_dying") or ship.get("is_sinking")):
		return

	if cooldown_timer > 0:
		cooldown_timer -= delta
		return
	
	_search_tick += 1
	if _search_tick >= 15 or not is_instance_valid(current_target):
		_search_tick = 0
		_update_target()
	
	if is_instance_valid(current_target):
		# 사거리 체크
		if global_position.distance_squared_to(current_target.global_position) > detection_range * detection_range:
			current_target = null
		else:
			fire(current_target)

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var min_dist_sq = detection_range * detection_range
	
	var enemy_team = "enemy" if team == "player" else "player"
	var soldiers = get_tree().get_nodes_in_group("soldiers")
	
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
	cooldown_timer = fire_cooldown * _cached_cd_mult
	
	var bolt = bolt_scene.instantiate()
	bolt.position = muzzle.global_position
	bolt.team = team
	bolt.damage = 45.0 * _cached_dmg_mult
	bolt.max_pierce = _cached_pierce
	
	get_tree().root.add_child.call_deferred(bolt)
	
	# 조준 방향 (목표 병사 위치)
	var dir = (target.global_position - muzzle.global_position).normalized()
	bolt.direction = dir
	bolt.look_at(bolt.position + dir, Vector3.UP)
	
	# 사운드
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cannon_fire", global_position, 1.5) # 더 날카롭고 높은 피치 제안
