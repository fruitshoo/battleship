@tool
extends Node3D
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const DEBUG_COMBAT_LOGS := false
const DEBUG_CANNON_FIRE_LOGS := false
const CANNON_RELOAD_TEMPO_MULT := 1.10
const SITE_BONUS_TOTALS_META := "sea_site_bonus_totals"

## 함포 (Cannon)
## 범위 내 적을 탐지하고 자동으로 발사 (Area3D 대신 직접 탐지)

@export var cannonball_scene: PackedScene = preload("res://scenes/projectiles/cannonball.tscn")
@export var muzzle_smoke_scene: PackedScene = preload("res://scenes/effects/cannon_muzzle_smoke.tscn")
@export_range(0.0, 80.0, 0.5) var projectile_damage: float = 1.0
@export_range(1.0, 140.0, 0.5) var projectile_speed: float = 60.0
@export_range(0.0, 0.5, 0.01) var muzzle_smoke_follow_muzzle_time: float = 0.22
@export var fire_cooldown: float = 2.8
@export var crew_operated_reload_enabled: bool = true
@export_range(0.0, 3.0, 0.05) var max_reload_crew_power: float = 3.0
@export_range(0.05, 1.0, 0.05) var uncrewed_reload_speed_mult: float = 0.35
@export_range(1.0, 2.5, 0.05) var two_crew_reload_speed_mult: float = 1.35
@export_range(1.0, 3.0, 0.05) var three_crew_reload_speed_mult: float = 1.65
@export_range(0.2, 2.0, 0.05) var reload_crew_station_back_offset: float = 1.05
@export_range(0.2, 1.5, 0.05) var reload_crew_station_side_offset: float = 0.55
@export_range(0.0, 1.0, 0.05) var reload_crew_station_forward_step: float = 0.25
@export var reload_crew_animation_key: String = "cannon_reload_standby"
@export var detection_range: float = 22.0
@export var detection_arc: float = 25.0 # 탐지 각도 (±25도)
@export_range(0.0, 0.35, 0.01) var reload_extra_jitter_pct: float = 0.12
@export_range(0.05, 0.8) var target_scan_interval: float = 0.12
@export_range(1.0, 6.0) var target_tracking_scan_multiplier: float = 3.0
@export_range(0.0, 8.0, 0.1) var base_inaccuracy_deg: float = 1.0
@export_range(0.0, 8.0, 0.1) var moving_target_inaccuracy_deg: float = 2.2
@export_range(0.1, 1.0, 0.05) var prediction_lead_factor: float = 0.72
@export_range(1.0, 4.0, 0.05) var boarding_reload_cooldown_mult: float = 1.55
@export_range(1.0, 4.0, 0.05) var boarded_reload_cooldown_mult: float = 1.85
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
var _reload_crew_power: float = 0.0

# 함수(수명 주기별) 성능을 위한 업그레이드 수치 캐싱
var _cached_range_mult: float = 1.0
var _cached_cd_mult: float = 1.0
var _cached_dmg_mult: float = 1.0
var _cached_crit_chance: float = 0.0
var _cached_crit_multiplier: float = 1.5
var _cached_projectile_speed: float = 50.0

func _ready() -> void:
	# 초기 업그레이드 적용
	_owner_ship = _resolve_owner_ship()
	_update_cached_stats()
	_target_scan_left = randf_range(0.0, target_scan_interval)
	# 업그레이드 발생 시그널 연결
	var upgrade_manager = _get_upgrade_manager()
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_signal("upgrade_applied"):
		upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id in ["cannon_damage", "cannon_reload"]:
		_update_cached_stats()

func _update_cached_stats() -> void:
	_cached_range_mult = 1.0
	_cached_cd_mult = 1.0
	_cached_dmg_mult = 1.0
	_cached_crit_chance = 0.0
	_cached_crit_multiplier = 1.5
	_cached_projectile_speed = _get_projectile_speed()
	if team != "player":
		return
	var upgrade_manager = _get_upgrade_manager()
	if is_instance_valid(upgrade_manager) and "current_levels" in upgrade_manager and "UPGRADES" in upgrade_manager:
		var damage_lv: int = int(upgrade_manager.current_levels.get("cannon_damage", 0))
		var reload_lv: int = int(upgrade_manager.current_levels.get("cannon_reload", 0))
		var damage_stats: Dictionary = upgrade_manager.UPGRADES.get("cannon_damage", {}).get("stats", {})
		var reload_stats: Dictionary = upgrade_manager.UPGRADES.get("cannon_reload", {}).get("stats", {})

		_cached_dmg_mult = 1.0 + (float(damage_stats.get("dmg_pct_per_lv", 8)) / 100.0) * float(damage_lv)
		_cached_cd_mult = maxf(
			float(reload_stats.get("min_cd_mult", 0.75)),
			1.0 - (float(reload_stats.get("cd_pct_per_lv", 4)) / 100.0) * float(reload_lv)
		)
	var site_damage_bonus := _get_owner_site_bonus_total("cannon_damage_pct")
	var site_reload_bonus := clampf(_get_owner_site_bonus_total("cannon_reload_pct"), 0.0, 0.45)
	_cached_dmg_mult += site_damage_bonus
	_cached_cd_mult *= maxf(0.55, 1.0 - site_reload_bonus)


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


func _get_owner_site_bonus_total(bonus_id: String) -> float:
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	if not is_instance_valid(_owner_ship):
		return 0.0
	var totals: Variant = _owner_ship.get_meta(SITE_BONUS_TOTALS_META, {})
	if totals is Dictionary:
		return maxf(0.0, float((totals as Dictionary).get(bonus_id, 0.0)))
	return 0.0

func set_fleet_bonus(dmg_mult: float, cd_mult: float) -> void:
	fleet_damage_mult = dmg_mult
	fleet_cooldown_mult = cd_mult
	if DEBUG_COMBAT_LOGS:
		print("[Cannon] 함대 보너스 설정: 데미지x%.1f, 쿨다운x%.1f" % [dmg_mult, cd_mult])


func _process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_process(delta)
	PhysicsFrameProfiler.end("launcher_cannon_process", profile_start)


func _profiled_process(delta: float) -> void:
	# 0. 소유 배 상태 체크: 배가 침몰/파괴/폐선이거나 갑판을 빼앗기면 발사 불가
	if not _is_owner_weapon_ready():
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
	return LauncherCombatHelper.resolve_owner_ship(self)

func _is_owner_weapon_ready() -> bool:
	if not is_instance_valid(_owner_ship):
		_owner_ship = _resolve_owner_ship()
	return LauncherCombatHelper.is_owner_combat_ready(_owner_ship)

func _get_current_range() -> float:
	return detection_range * _cached_range_mult

func get_debug_cannon_snapshot() -> Dictionary:
	var projectile_stats: Dictionary = _get_projectile_stats_snapshot()
	var base_damage: float = _get_projectile_base_damage()
	if base_damage <= 1.0 and team == "player":
		base_damage = 22.0
	var site_damage_bonus := _get_owner_site_bonus_total("cannon_damage_pct")
	var site_reload_bonus := clampf(_get_owner_site_bonus_total("cannon_reload_pct"), 0.0, 0.45)
	var reload_crew_cooldown_mult := _get_reload_crew_cooldown_mult()
	var boarding_reload_cooldown_mult := _get_boarding_reload_cooldown_mult()
	var cannon_damage: float = base_damage * _cached_dmg_mult * fleet_damage_mult
	var current_cooldown: float = _get_current_cooldown()
	var expected_shot_damage: float = cannon_damage * (1.0 + _cached_crit_chance * (_cached_crit_multiplier - 1.0))
	return {
		"team": team,
		"count": 1,
		"range": _get_current_range(),
		"base_cooldown": fire_cooldown,
		"cooldown": current_cooldown,
		"base_damage": base_damage,
		"damage": cannon_damage,
		"damage_mult": _cached_dmg_mult,
		"fleet_damage_mult": fleet_damage_mult,
		"fleet_cooldown_mult": fleet_cooldown_mult,
		"cached_cooldown_mult": _cached_cd_mult,
		"reload_crew_cooldown_mult": reload_crew_cooldown_mult,
		"reload_crew_power": _reload_crew_power,
		"reload_crew_speed_mult": get_reload_crew_speed_multiplier(),
		"boarding_reload_cooldown_mult": boarding_reload_cooldown_mult,
		"tempo_mult": CANNON_RELOAD_TEMPO_MULT,
		"site_damage_bonus": site_damage_bonus,
		"site_reload_bonus": site_reload_bonus,
		"crit_chance": _cached_crit_chance,
		"crit_multiplier": _cached_crit_multiplier,
		"expected_dps": expected_shot_damage / current_cooldown if current_cooldown > 0.0 else 0.0,
		"detection_monitoring": is_processing() and is_physics_processing(),
		"detection_overlap_count": 1 if is_instance_valid(current_target) else 0,
		"projectile_stats": projectile_stats,
	}

func set_reload_crew_power(value: float) -> void:
	_reload_crew_power = clampf(value, 0.0, max_reload_crew_power)


func get_reload_crew_power() -> float:
	return _reload_crew_power


func get_max_reload_crew_power() -> float:
	return max_reload_crew_power


func get_reload_crew_station_count() -> int:
	return clampi(int(ceil(_reload_crew_power)), 0, int(max_reload_crew_power))


func get_reload_crew_station_global_position(slot_index: int) -> Vector3:
	return to_global(_get_reload_crew_station_local_position(slot_index))


func get_reload_crew_station_animation_key(_slot_index: int) -> String:
	return reload_crew_animation_key


func notify_reload_crew_station_worker(_soldier: Node, _slot_index: int, _arrived: bool) -> void:
	pass


func get_reload_crew_speed_multiplier() -> float:
	if not crew_operated_reload_enabled:
		return 1.0
	var crew_power: float = clampf(_reload_crew_power, 0.0, max_reload_crew_power)
	if crew_power <= 1.0:
		return lerpf(uncrewed_reload_speed_mult, 1.0, crew_power)
	if crew_power <= 2.0:
		return lerpf(1.0, two_crew_reload_speed_mult, crew_power - 1.0)
	var extra_span: float = maxf(0.01, max_reload_crew_power - 2.0)
	var extra_t: float = clampf((crew_power - 2.0) / extra_span, 0.0, 1.0)
	return lerpf(two_crew_reload_speed_mult, three_crew_reload_speed_mult, extra_t)


func can_cover_reload_allocation_target(target: Node) -> bool:
	if not (target is Node3D):
		return false
	var target_node := target as Node3D
	var range_value: float = _get_current_range()
	if range_value > 0.0:
		var planar_delta: Vector3 = target_node.global_position - global_position
		planar_delta.y = 0.0
		if planar_delta.length_squared() > range_value * range_value:
			return false
	return _is_within_arc(target_node)


func _get_reload_crew_station_local_position(slot_index: int) -> Vector3:
	match slot_index:
		0:
			return Vector3(0.0, 0.0, reload_crew_station_back_offset)
		1:
			return Vector3(-reload_crew_station_side_offset, 0.0, reload_crew_station_back_offset - reload_crew_station_forward_step)
		2:
			return Vector3(reload_crew_station_side_offset, 0.0, reload_crew_station_back_offset - reload_crew_station_forward_step)
		_:
			var side_sign: float = -1.0 if slot_index % 2 == 0 else 1.0
			var row: float = float(slot_index / 2)
			return Vector3(
				side_sign * reload_crew_station_side_offset,
				0.0,
				reload_crew_station_back_offset + row * reload_crew_station_forward_step
			)


func _get_reload_crew_cooldown_mult() -> float:
	if is_instance_valid(_owner_ship) and _owner_ship.has_method("get_gunnery_reload_multiplier"):
		return float(_owner_ship.call("get_gunnery_reload_multiplier"))
	if not crew_operated_reload_enabled:
		return 1.0
	return 1.0 / maxf(0.05, get_reload_crew_speed_multiplier())



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
	stats["damage"] = _get_projectile_base_damage()
	stats["crit_chance"] = float(projectile.get("crit_chance")) if projectile.get("crit_chance") != null else 0.0
	stats["crit_multiplier"] = float(projectile.get("crit_multiplier")) if projectile.get("crit_multiplier") != null else 1.0
	if projectile is Node:
		(projectile as Node).free()
	return stats

func _update_target() -> void:
	var nearest_enemy: Node3D = null
	var current_range = _get_current_range()
	# 최대 탐지 거리의 제곱값 초기화 (이보다 먼 타겟은 무시)
	var max_range_sq: float = current_range * current_range
	# 현재까지 찾은 가장 '매력적인' 타겟의 가중치 적용 거리
	var best_score_sq: float = INF
	
	var enemies = EntityRegistry.get_ships_by_team(LauncherCombatHelper.enemy_team_tag(team))
	
	for enemy in enemies:
		var enemy_ship := LauncherCombatHelper.get_enemy_combat_target(enemy, team)
		if enemy_ship == null:
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
	var target_node := LauncherCombatHelper.get_enemy_combat_target(target, team)
	if target_node == null:
		return false
		
	var current_range = _get_current_range()
	if not LauncherCombatHelper.is_target_in_range(self, target_node, current_range): return false
	if not _is_within_arc(target_node): return false
	
	return true

func _is_within_arc(target: Node3D) -> bool:
	var aim_point: Vector3 = NodeContractHelper.get_projectile_aim_point(target, 0.55)
	var to_target = aim_point - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return true
	to_target = to_target.normalized()
	var forward = - global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var dot = forward.dot(to_target)
	var angle = rad_to_deg(acos(clamp(dot, -1.0, 1.0)))
	return angle < detection_arc


## 타겟 우선순위를 위해 배에 적군이 있는지 체크
func _is_ship_occupied_by_enemy(target_ship: Node3D) -> bool:
	return LauncherCombatHelper.has_alive_soldier_on_team(target_ship, LauncherCombatHelper.enemy_team_tag(team))


func _get_current_cooldown() -> float:
	# 캐시된 업그레이드 배율 * 함대 배율
	var cooldown_mult: float = _cached_cd_mult * fleet_cooldown_mult
	cooldown_mult *= _get_reload_crew_cooldown_mult()
	cooldown_mult *= _get_boarding_reload_cooldown_mult()
	return fire_cooldown * cooldown_mult * CANNON_RELOAD_TEMPO_MULT

func _get_boarding_reload_cooldown_mult() -> float:
	if not is_instance_valid(_owner_ship):
		return 1.0
	var mult: float = 1.0
	if _owner_ship.has_method("is_boarding_ship") and _owner_ship.is_boarding_ship():
		mult = maxf(mult, boarding_reload_cooldown_mult)
	if _owner_ship.has_method("get_boarding_attacker_ship") and is_instance_valid(_owner_ship.get_boarding_attacker_ship()):
		mult = maxf(mult, boarded_reload_cooldown_mult)
	return mult

func _get_next_reload_cooldown() -> float:
	var base_cooldown: float = _get_current_cooldown()
	if reload_extra_jitter_pct <= 0.0:
		return base_cooldown
	return base_cooldown * randf_range(1.0, 1.0 + reload_extra_jitter_pct)

func _get_target_scan_interval(has_valid_target: bool) -> float:
	return LauncherCombatHelper.get_target_scan_interval(target_scan_interval, target_tracking_scan_multiplier, has_valid_target, 0.04)


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
	if not _is_owner_weapon_ready():
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
	cooldown_timer = _get_next_reload_cooldown()
	if is_instance_valid(_owner_ship) and _owner_ship.has_method("request_cannon_reload_pose"):
		_owner_ship.request_cannon_reload_pose(self, minf(1.2, maxf(0.55, cooldown_timer * 0.35)))
	
	# 예측 사격: 적의 예상 위치를 향해 발사
	var target_aim_pos: Vector3 = NodeContractHelper.get_projectile_aim_point(target_node, 0.55)
	var dist = muzzle.global_position.distance_to(target_aim_pos)
	
	var current_projectile_speed: float = _cached_projectile_speed
	var time_to_hit = dist / maxf(current_projectile_speed, 1.0)
	
	var enemy_speed: float = _get_ship_speed(target_node, 3.5)
	var enemy_dir = - target_node.global_transform.basis.z
	var enemy_velocity = enemy_dir * enemy_speed
	
	var predicted_pos = target_aim_pos + enemy_velocity * time_to_hit * prediction_lead_factor
	var fire_direction = (predicted_pos - muzzle.global_position).normalized()
	if fire_direction.is_zero_approx():
		fire_direction = - global_transform.basis.z
	fire_direction = _apply_cannon_inaccuracy(fire_direction, target_node, dist)
	if DebugDrawBridge.projectile_debug_enabled:
		DebugDrawBridge.draw_targeting_solution(
			muzzle.global_position,
			target_aim_pos,
			predicted_pos,
			fire_direction,
			_get_current_range(),
			"%s -> %s" % [name, target_node.name],
			1.1
		)

	var final_damage = 1.0
	var ball = ScenePool.acquire(get_tree(), cannonball_scene)
	get_tree().root.add_child(ball)
	var projectile_base_damage: float = _get_projectile_base_damage()
	if "damage" in ball:
		final_damage = projectile_base_damage * _cached_dmg_mult * fleet_damage_mult
	if "speed" in ball:
		ball.speed = _cached_projectile_speed
	if ball.has_method("set_meta"):
		ball.set_meta("shooter_label", name)
	if team == "player" and "crit_chance" in ball:
		ball.crit_chance = _cached_crit_chance
	if team == "player" and "crit_multiplier" in ball:
		ball.crit_multiplier = _cached_crit_multiplier
	var planned_travel_distance: float = muzzle.global_position.distance_to(predicted_pos)
	if "miss_overshoot_distance" in ball:
		planned_travel_distance += float(ball.miss_overshoot_distance)
	if ball.has_method("launch"):
		ball.launch(muzzle.global_position, team, fire_direction, target_node, final_damage, _cached_range_mult, planned_travel_distance)
	else:
		ball.position = muzzle.global_position
		ball.team = team
		ball.damage = final_damage
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
		if not is_instance_valid(smoke):
			return
		if smoke.has_method("configure_as_muzzle"):
			smoke.configure_as_muzzle()
		if smoke.has_method("set_intensity"):
			var muzzle_intensity: float = 1.0
			if projectile_base_damage > 0.0:
				muzzle_intensity = clampf(final_damage / projectile_base_damage, 0.85, 1.45)
			smoke.set_intensity(muzzle_intensity)
		# Basis.looking_at 안전 가드
		var smoke_dir = fire_direction if not fire_direction.is_zero_approx() else Vector3.FORWARD
		var smoke_position := muzzle.global_position
		var smoke_basis := _get_muzzle_smoke_basis(smoke_dir)
		var smoke_parent: Node = muzzle if muzzle_smoke_follow_muzzle_time > 0.0 and is_instance_valid(muzzle) else get_tree().root
		smoke_parent.add_child(smoke)
		if smoke is Node3D:
			(smoke as Node3D).global_transform = Transform3D(smoke_basis, smoke_position)
		if smoke_parent == muzzle:
			_schedule_muzzle_smoke_detach(smoke, muzzle_smoke_follow_muzzle_time)
		if smoke.has_method("pool_activate"):
			smoke.pool_activate()
		else:
			_activate_plain_muzzle_smoke(smoke)


func _get_muzzle_smoke_basis(smoke_dir: Vector3) -> Basis:
	var dir := smoke_dir.normalized()
	if dir.is_zero_approx():
		dir = Vector3.FORWARD
	return Basis.looking_at(dir, Vector3.UP)


func _schedule_muzzle_smoke_detach(smoke: Node, delay: float) -> void:
	var tree := get_tree()
	if not is_instance_valid(tree) or delay <= 0.0:
		return
	var smoke_id := smoke.get_instance_id()
	var muzzle_id := muzzle.get_instance_id() if is_instance_valid(muzzle) else 0
	tree.create_timer(delay).timeout.connect(func() -> void:
		_detach_muzzle_smoke_to_world(smoke_id, muzzle_id)
	)


func _detach_muzzle_smoke_to_world(smoke_id: int, muzzle_id: int) -> void:
	var smoke := NodeContractHelper.get_instance_node(smoke_id)
	var muzzle_node := NodeContractHelper.get_instance_node(muzzle_id)
	var tree := get_tree()
	if not is_instance_valid(smoke) or not is_instance_valid(muzzle_node) or not is_instance_valid(tree):
		return
	if smoke.get_parent() != muzzle_node:
		return
	var saved_transform := Transform3D.IDENTITY
	if smoke is Node3D:
		saved_transform = (smoke as Node3D).global_transform
	muzzle_node.remove_child(smoke)
	tree.root.add_child(smoke)
	if smoke is Node3D:
		(smoke as Node3D).global_transform = saved_transform


func _activate_plain_muzzle_smoke(smoke: Node) -> void:
	var max_lifetime := _restart_plain_muzzle_particles(smoke)
	if max_lifetime <= 0.0:
		ScenePool.release(smoke)
		return
	var tree := get_tree()
	if not is_instance_valid(tree):
		ScenePool.release(smoke)
		return
	tree.create_timer(max_lifetime + 0.35).timeout.connect(func() -> void:
		ScenePool.release(smoke)
	)


func _restart_plain_muzzle_particles(node: Node) -> float:
	var max_lifetime := 0.0
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.visible = true
		particles.restart()
		particles.emitting = true
		max_lifetime = maxf(max_lifetime, particles.lifetime)
	for child in node.get_children():
		max_lifetime = maxf(max_lifetime, _restart_plain_muzzle_particles(child))
	return max_lifetime


func _get_projectile_speed() -> float:
	if projectile_speed > 0.0:
		return maxf(projectile_speed, 1.0)
	if not cannonball_scene:
		return 50.0
	var projectile = cannonball_scene.instantiate()
	if projectile == null:
		return 50.0
	var scene_projectile_speed: float = float(projectile.get("speed")) if projectile.get("speed") != null else 50.0
	if projectile is Node:
		(projectile as Node).free()
	return maxf(scene_projectile_speed, 1.0)


func _get_projectile_base_damage() -> float:
	if projectile_damage > 0.0:
		return projectile_damage
	if not cannonball_scene:
		return 1.0
	var projectile = cannonball_scene.instantiate()
	if projectile == null:
		return 1.0
	var projectile_base_damage: float = float(projectile.get("damage")) if projectile.get("damage") != null else 1.0
	if projectile is Node:
		(projectile as Node).free()
	return maxf(projectile_base_damage, 1.0)


func _get_ship_speed(ship: Node3D, fallback: float = 0.0) -> float:
	if not is_instance_valid(ship):
		return fallback
	if ship.has_method("get_current_speed_value"):
		return float(ship.call("get_current_speed_value"))
	if "current_speed" in ship:
		return float(ship.get("current_speed"))
	if "move_speed" in ship:
		return float(ship.get("move_speed"))
	return fallback


func _apply_cannon_inaccuracy(base_direction: Vector3, target_node: Node3D, distance_to_target: float) -> Vector3:
	var shooter_speed := 0.0
	if is_instance_valid(_owner_ship) and _owner_ship is Node3D:
		shooter_speed = _get_ship_speed(_owner_ship as Node3D, 0.0)
	var target_speed: float = _get_ship_speed(target_node, 0.0)
	var movement_spread: float = clampf((shooter_speed + target_speed) / 12.0, 0.0, 1.0) * moving_target_inaccuracy_deg
	var distance_spread: float = clampf((distance_to_target - 8.0) / 18.0, 0.0, 1.0) * 2.4
	var total_spread: float = base_inaccuracy_deg + movement_spread + distance_spread
	if team != "player":
		total_spread *= 1.12
	var yaw_error: float = deg_to_rad(randf_range(-total_spread, total_spread))
	var scattered_direction: Vector3 = base_direction.rotated(Vector3.UP, yaw_error).normalized()
	return scattered_direction if not scattered_direction.is_zero_approx() else base_direction
