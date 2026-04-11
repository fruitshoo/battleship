@tool
extends Node3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const DEBUG_COMBAT_LOGS := false
const DEBUG_CANNON_FIRE_LOGS := false

## 함포 (Cannon)
## 범위 내 적을 탐지하고 자동으로 발사 (Area3D 대신 직접 탐지)

@export var cannonball_scene: PackedScene = preload("res://scenes/projectiles/cannonball.tscn")
@export var muzzle_smoke_scene: PackedScene = preload("res://scenes/effects/impact_puff.tscn")
@export var fire_cooldown: float = 2.0
@export var detection_range: float = 22.0
@export var detection_arc: float = 25.0 # 탐지 각도 (±25도)
@export_range(0.05, 0.8) var target_scan_interval: float = 0.12
@export_range(1.0, 6.0) var target_tracking_scan_multiplier: float = 3.0
@export var team: String = "player" # "player" or "enemy"

@onready var muzzle: Marker3D = $Muzzle

var cooldown_timer: float = 0.0

var is_preparing: bool = false
var prepare_timer: float = 0.0
@export var prepare_time: float = 0.15 # 0.8에서 타격감을 위해 0.15초로 단축
var current_target: Node3D = null
var _target_scan_left: float = 0.0

# 함대 업그레이드 보너스 (나포함 전용)
var fleet_damage_mult: float = 1.0
var fleet_cooldown_mult: float = 1.0
var _owner_ship: Node = null

# 함수(수명 주기별) 성능을 위한 업그레이드 수치 캐싱
var _cached_range_mult: float = 1.0
var _cached_cd_mult: float = 1.0
var _cached_dmg_mult: float = 1.0
var _cached_crit_chance: float = 0.0
var _cached_crit_multiplier: float = 1.5
var _cached_ammo_type: String = "roundshot"

func _ready() -> void:
	# 초기 업그레이드 적용
	_update_cached_stats()
	_owner_ship = _resolve_owner_ship()
	_target_scan_left = randf_range(0.0, target_scan_interval)
	# 업그레이드 발생 시그널 연결
	var upgrade_manager = _get_upgrade_manager()
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_signal("upgrade_applied"):
		upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id == "cannon":
		_update_cached_stats()

func _update_cached_stats() -> void:
	_cached_range_mult = 1.0
	_cached_cd_mult = 1.0
	_cached_dmg_mult = 1.0
	_cached_crit_chance = 0.0
	_cached_crit_multiplier = 1.5
	if team != "player":
		return
	var upgrade_manager = _get_upgrade_manager()
	if is_instance_valid(upgrade_manager) and "current_levels" in upgrade_manager and "UPGRADES" in upgrade_manager:
		var cannon_lv = upgrade_manager.current_levels.get("cannon", 0)
		var s = upgrade_manager.UPGRADES.get("cannon", {}).get("stats", {})
		
		# 5레벨 체계: 매 레벨마다 보너스가 중첩됨
		_cached_range_mult = 1.0 + (s.get("range_pct_per_lv", 10) / 100.0) * (cannon_lv - 1)
		_cached_cd_mult = maxf(0.5, 1.0 - (s.get("cd_pct_per_lv", 8) / 100.0) * (cannon_lv - 1))
		_cached_dmg_mult = 1.0 + (s.get("dmg_pct_per_lv", 20) / 100.0) * (cannon_lv - 1)
		_cached_crit_chance = maxf(0.0, (s.get("crit_pct_per_lv", 2.5) / 100.0) * (cannon_lv - 1))
		_cached_crit_multiplier = float(s.get("crit_multiplier", 1.5))


func _get_upgrade_manager() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	return root.get_node_or_null("UpgradeManager")

func set_fleet_bonus(dmg_mult: float, cd_mult: float) -> void:
	fleet_damage_mult = dmg_mult
	fleet_cooldown_mult = cd_mult
	if DEBUG_COMBAT_LOGS:
		print("[Cannon] 함대 보너스 설정: 데미지x%.1f, 쿨다운x%.1f" % [dmg_mult, cd_mult])


func _process(delta: float) -> void:
	# 0. 소유 배 상태 체크: 배가 침몰/파괴/폐선이면 발사 불가
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	if is_instance_valid(_owner_ship):
		if _owner_ship.has_method("is_combat_disabled") and _owner_ship.is_combat_disabled():
			is_preparing = false
			current_target = null
			return

	if is_preparing:
		# 발사 대기 중에도 타겟이 유효한지 실시간 체크
		if not _is_target_valid(current_target):
			is_preparing = false
			current_target = null
			return
			
		prepare_timer -= delta
		if prepare_timer <= 0:
			_execute_fire()
		return
		
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			# 장전 완료 사운드 (금속 철컥/쿵 소리)
			var audio_manager = get_node_or_null("/root/AudioManager")
			if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
				audio_manager.play_sfx("cannon_reload", global_position, randf_range(0.9, 1.1))
		return
	
	_target_scan_left -= delta
	if _target_scan_left <= 0.0 or not is_instance_valid(current_target):
		_update_target()
		_target_scan_left = _get_target_scan_interval(_is_target_valid(current_target))
	
	if _is_target_valid(current_target):
		var target_node := current_target as Node3D
		fire(target_node)
	else:
		current_target = null

func _resolve_owner_ship() -> Node:
	var node: Node = get_parent()
	while is_instance_valid(node):
		if node.is_in_group("ships"):
			return node
		if "is_sinking" in node and "is_dying" in node:
			return node
		node = node.get_parent()
	return null

func _get_current_range() -> float:
	return detection_range * _cached_range_mult

func _get_current_ammo_type() -> String:
	if team != "player":
		return "roundshot"
	if is_instance_valid(_owner_ship) and _owner_ship.get("current_cannon_ammo") != null:
		_cached_ammo_type = str(_owner_ship.get("current_cannon_ammo"))
	return _cached_ammo_type


func get_debug_cannon_snapshot() -> Dictionary:
	var projectile_stats: Dictionary = _get_projectile_stats_snapshot()
	var base_damage: float = float(projectile_stats.get("damage", 0.0))
	if base_damage <= 1.0 and team == "player":
		base_damage = 25.0
	var cannon_damage: float = base_damage * _cached_dmg_mult * fleet_damage_mult
	var current_cooldown: float = _get_current_cooldown()
	var expected_shot_damage: float = cannon_damage * (1.0 + _cached_crit_chance * (_cached_crit_multiplier - 1.0))
	return {
		"team": team,
		"count": 1,
		"range": _get_current_range(),
		"cooldown": current_cooldown,
		"base_damage": base_damage,
		"damage": cannon_damage,
		"damage_mult": _cached_dmg_mult,
		"fleet_damage_mult": fleet_damage_mult,
		"crit_chance": _cached_crit_chance,
		"crit_multiplier": _cached_crit_multiplier,
		"expected_dps": expected_shot_damage / current_cooldown if current_cooldown > 0.0 else 0.0,
		"ammo_type": _get_current_ammo_type(),
		"projectile_stats": projectile_stats,
	}


func _get_projectile_stats_snapshot() -> Dictionary:
	var stats: Dictionary = {
		"damage": 0.0,
		"crit_chance": 0.0,
		"crit_multiplier": 1.0,
	}
	var projectile_scene = cannonball_scene
	if not (projectile_scene is PackedScene):
		return stats
	var projectile = (projectile_scene as PackedScene).instantiate()
	if projectile == null:
		return stats
	stats["damage"] = float(projectile.get("damage")) if projectile.get("damage") != null else 0.0
	stats["crit_chance"] = float(projectile.get("crit_chance")) if projectile.get("crit_chance") != null else 0.0
	stats["crit_multiplier"] = float(projectile.get("crit_multiplier")) if projectile.get("crit_multiplier") != null else 1.0
	if projectile is Node:
		(projectile as Node).free()
	return stats

func _enemy_team_tag() -> String:
	return "enemy" if team == "player" else "player"

func _is_enemy_ship(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var resolved = HitTargetResolver.resolve_team_tag(node)
	if not resolved.is_empty():
		return resolved == _enemy_team_tag()
	return node.is_in_group(_enemy_team_tag())

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var current_range = _get_current_range()
	# 최대 탐지 거리의 제곱값 초기화 (이보다 먼 타겟은 무시)
	var max_range_sq: float = current_range * current_range
	# 현재까지 찾은 가장 '매력적인' 타겟의 가중치 적용 거리
	var best_score_sq: float = INF
	
	var enemies = EntityRegistry.get_ships_by_team(_enemy_team_tag())
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		var enemy_ship := enemy as Node3D
		if not _is_enemy_ship(enemy_ship):
			continue
		if is_instance_valid(_owner_ship) and enemy_ship == _owner_ship:
			continue
		
		# 실제 물리적 거리 스퀘어 계산
		var real_dist_sq = global_position.distance_squared_to(enemy_ship.global_position)
		
		# 실제 거리가 최대 사거리를 벗어나면 무조건 패스
		if real_dist_sq > max_range_sq:
			continue
		
		if not _is_within_arc(enemy_ship):
			continue
			
		if _is_ship_occupied_by_friendly(enemy_ship):
			continue
			
		# [핵심 로직] 빈 배(is_derelict)는 아예 타겟에서 제외 (시스템 개편)
		if enemy_ship.get("is_derelict") == true:
			continue
			
		# [핵심 로직] 타겟 점수 계산 (실제 거리를 기반으로 패널티 부여)
		var score_sq = real_dist_sq
		
		# 타겟 배에 적군이 한 명도 없다면 (빈 배거나 곧 빈 배가 될 배),
		# 거리에 엄청난 페널티(예: 10배 거리)를 주어 우선순위를 대폭 낮춤
		if not _is_ship_occupied_by_enemy(enemy_ship):
			score_sq *= 100.0 # 스퀘어 값이므로 100배 = 거리 10배
				
		# 점수가 가장 낮은(가장 매력적인) 타겟 갱신
		if score_sq < best_score_sq:
			best_score_sq = score_sq
			nearest_enemy = enemy_ship
	
	current_target = nearest_enemy

func _is_target_valid(target: Variant) -> bool:
	if not is_instance_valid(target) or not (target is Node3D):
		return false
	var target_node := target as Node3D
	if target_node.is_queued_for_deletion():
		return false
	
	if target_node.has_method("is_combat_disabled") and target_node.is_combat_disabled():
		return false
		
	# 팀 체크 (그룹 꼬임보다 우선)
	if not _is_enemy_ship(target_node):
		return false
		
	var current_range = _get_current_range()
	if global_position.distance_squared_to(target_node.global_position) > current_range * current_range: return false
	if not _is_within_arc(target_node): return false
	
	# 도선 중이거나 폐선인 배인지 최종 체크
	if target_node.has_method("is_combat_disabled") and target_node.is_combat_disabled(): return false
	if target_node.has_method("get_boarding_attacker_ship"):
		var attacker: Variant = target_node.get_boarding_attacker_ship()
		if is_instance_valid(attacker) and attacker is Node and attacker.has_method("get_team_tag") and attacker.get_team_tag() == team:
			return false
		
	if _is_ship_occupied_by_friendly(target_node): return false
	return true

func _is_within_arc(target: Node3D) -> bool:
	var to_target = (target.global_position - global_position).normalized()
	var forward = - global_transform.basis.z
	var dot = forward.dot(to_target)
	var angle = rad_to_deg(acos(clamp(dot, -1.0, 1.0)))
	return angle < detection_arc


## 아군 오사 방지를 위해 배에 아군이 있는지 체크
func _is_ship_occupied_by_friendly(target_ship: Node3D) -> bool:
	var soldiers_node = target_ship.get_node_or_null("Soldiers")
	if not soldiers_node: return false
	
	for child in soldiers_node.get_children():
		# 살아있는 아군 병사가 한 명이라도 있으면 True
		if child.has_method("get_team_tag") and child.get_team_tag() == team and child.has_method("is_dead") and not child.is_dead():
			return true
	return false

## 타겟 우선순위를 위해 배에 적군이 있는지 체크
func _is_ship_occupied_by_enemy(target_ship: Node3D) -> bool:
	var soldiers_node = target_ship.get_node_or_null("Soldiers")
	if not soldiers_node: return false
	
	var enemy_team = "enemy" if team == "player" else "player"
	for child in soldiers_node.get_children():
		# 살아있는 적군 병사가 한 명이라도 있으면 True
		if child.has_method("get_team_tag") and child.get_team_tag() == enemy_team and child.has_method("is_dead") and not child.is_dead():
			return true
	return false


func _get_current_cooldown() -> float:
	# 캐시된 업그레이드 배율 * 함대 배율
	var cooldown_mult: float = _cached_cd_mult * fleet_cooldown_mult
	if is_instance_valid(_owner_ship) and _owner_ship.has_method("get_gunnery_reload_multiplier"):
		cooldown_mult *= float(_owner_ship.call("get_gunnery_reload_multiplier"))
	return fire_cooldown * cooldown_mult

func _get_target_scan_interval(has_valid_target: bool) -> float:
	var base_interval: float = target_scan_interval
	if has_valid_target:
		base_interval *= target_tracking_scan_multiplier
	return base_interval + randf_range(0.0, 0.04)


func fire(target_enemy: Node3D) -> void:
	if not cannonball_scene: return
	
	# 발사 준비(도화선) 시작
	is_preparing = true
	prepare_timer = prepare_time
	current_target = target_enemy
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cannon_fuse", global_position)


func _execute_fire() -> void:
	is_preparing = false
	if is_instance_valid(_owner_ship):
		if _owner_ship.has_method("is_combat_disabled") and _owner_ship.is_combat_disabled():
			current_target = null
			return
	
	# 최종 발사 직전 다시 한번 타겟 유효성 검증
	if not _is_target_valid(current_target):
		current_target = null
		return
	var target_node := current_target
		
	# 사운드 재생
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cannon_fire", global_position, randf_range(0.9, 1.1))
		
	# 화면 흔들림 (Screen Shake) - 플레이어 대포일 경우만 (오래봐도 안 피로하게 아주 약하게)
	if team == "player":
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake"):
			cam.shake(0.15, 0.1) # 진동 세기 0.15, 지속시간 0.1초 (기존 0.5/0.25에서 대폭 완화)
	
	# 쿨타임 시작
	cooldown_timer = _get_current_cooldown()
	
	# 예측 사격: 적의 예상 위치를 향해 발사
	var dist = global_position.distance_to(target_node.global_position)
	
	var time_to_hit = dist / 50.0 # 탄속 50.0으로 동기화 (기존 80.0 오류 수정)
	
	var enemy_speed = 3.5
	if "move_speed" in target_node: enemy_speed = target_node.move_speed
	var enemy_dir = - target_node.global_transform.basis.z
	var enemy_velocity = enemy_dir * enemy_speed
	
	var predicted_pos = target_node.global_position + enemy_velocity * time_to_hit
	var fire_direction = (predicted_pos - muzzle.global_position).normalized()
	if fire_direction.is_zero_approx():
		fire_direction = - global_transform.basis.z

	var final_damage = 1.0
	var ammo_type: String = _get_current_ammo_type()
	var ball = ScenePool.acquire(get_tree(), cannonball_scene)
	get_tree().root.add_child(ball)
	var projectile_base_damage: float = 0.0
	if "damage" in ball:
		projectile_base_damage = float(ball.damage)
		final_damage = projectile_base_damage * _cached_dmg_mult * fleet_damage_mult
	if ball.has_method("set_meta"):
		ball.set_meta("shooter_label", name)
	if team == "player" and "crit_chance" in ball:
		ball.crit_chance = _cached_crit_chance
	if team == "player" and "crit_multiplier" in ball:
		ball.crit_multiplier = _cached_crit_multiplier
	if ball.has_method("launch"):
		ball.launch(muzzle.global_position, team, fire_direction, target_node, final_damage, _cached_range_mult, ammo_type)
	else:
		ball.position = muzzle.global_position
		ball.team = team
		ball.damage = final_damage
		if "ammo_type" in ball:
			ball.ammo_type = ammo_type
		if team == "player":
			ball.crit_chance = _cached_crit_chance
			ball.crit_multiplier = _cached_crit_multiplier
		if ball.has_method("set_meta"):
			ball.set_meta("shooter_label", name)
		ball.direction = fire_direction
		ball.target_node = target_node
		if ball.has_method("set_lifetime_multiplier"):
			ball.set_lifetime_multiplier(_cached_range_mult)
		ball.basis = Basis.looking_at(fire_direction, Vector3.UP)

	if DEBUG_CANNON_FIRE_LOGS and OS.is_debug_build():
		print("[CannonFire][%s#%s][team=%s] base=%.1f dmg_mult=%.2f fleet=%.2f final=%.1f range_mult=%.2f cd=%.2f crit=%.1f%% x%.1f target=%s" % [
			name,
			str(get_instance_id()),
			team,
			projectile_base_damage,
			_cached_dmg_mult,
			fleet_damage_mult,
			final_damage,
			_cached_range_mult,
			_get_current_cooldown(),
			_cached_crit_chance * 100.0,
			_cached_crit_multiplier,
			target_node.name,
		])

	# 머즐 연기 생성
	if muzzle_smoke_scene:
		var smoke = ScenePool.acquire(get_tree(), muzzle_smoke_scene)
		if smoke.has_method("configure_as_muzzle"):
			smoke.configure_as_muzzle()
		if smoke.has_method("set_intensity"):
			var muzzle_intensity: float = 1.0
			if projectile_base_damage > 0.0:
				muzzle_intensity = clampf(final_damage / projectile_base_damage, 0.85, 1.45)
			smoke.set_intensity(muzzle_intensity)
		smoke.position = muzzle.global_position
		# Basis.looking_at 안전 가드
		var smoke_dir = fire_direction if not fire_direction.is_zero_approx() else Vector3.FORWARD
		smoke.basis = Basis.looking_at(smoke_dir, Vector3.UP)
		get_tree().root.add_child(smoke)
		if smoke.has_method("pool_activate"):
			smoke.pool_activate()
