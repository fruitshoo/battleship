extends "res://scripts/entities/weapons/weapon.gd"

const BASE_DAMAGE: float = 10.0
const ARROW_SPEED: float = 34.0
const MIN_ARROW_FLIGHT_TIME: float = 0.12
const SOLDIER_AIM_VERTICAL_OFFSET: float = 1.05
const SHIP_AIM_VERTICAL_OFFSET: float = 0.55
const SINGIGEON_AIM_VERTICAL_OFFSET: float = 1.05
const SINGIGEON_SHIP_AIM_VERTICAL_OFFSET: float = 0.65
const SINGIGEON_PROC_NEXT_MSEC_META := "bow_singigeon_next_proc_msec"
const SINGIGEON_PROC_MISS_COUNT_META := "bow_singigeon_miss_count"

@export var arrow_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@export var singigeon_rocket_scene: PackedScene = preload("res://scenes/projectiles/singigeon_rocket.tscn")
@export var shoot_cooldown: float = 2.0
@export var max_range: float = 20.0
var _cached_spawn_parent: Node = null

func _ready() -> void:
	damage = BASE_DAMAGE
	attack_range = max_range
	attack_cooldown = shoot_cooldown


func apply_owner_damage_bonus_pct(damage_bonus_pct: float) -> void:
	damage = BASE_DAMAGE * (1.0 + maxf(0.0, damage_bonus_pct))


func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not arrow_scene: return
	if SoldierStateHelper.is_dead_soldier(target):
		return
	var team_name: String = attacker.get_team_tag() if attacker.has_method("get_team_tag") else "player"
	if _try_launch_singigeon_proc(target, attacker, team_name):
		return
	
	var arrow = ScenePool.acquire(attacker.get_tree(), arrow_scene) as Node3D
	# 발사 위치는 활(또는 병사 가슴 위치) 부근으로 약간 보정
	var spawn_pos = attacker.global_position
	spawn_pos.y += 0.8
	
	# 기본 타겟 위치
	var current_target_pos: Vector3 = _get_arrow_aim_point(target)
	
	# === 예측 샷 (Predictive Aiming) ===
	var arrow_speed = ARROW_SPEED
	var distance = spawn_pos.distance_to(current_target_pos)
	var time_to_reach = distance / arrow_speed
	
	if time_to_reach < MIN_ARROW_FLIGHT_TIME:
		time_to_reach = MIN_ARROW_FLIGHT_TIME
		
	# 타겟의 이동 속도(velocity)를 기반으로 미래 위치 예측
	var local_vel: Vector3 = target.get_velocity_value() if target.has_method("get_velocity_value") else (target.get("velocity") if "velocity" in target else Vector3.ZERO)
	
	# 타겟이 배 위에 타고 있는 경우 배의 이동 속도 합산
	var ship = _resolve_parent_ship(target)
		
	var ship_vel = Vector3.ZERO
	if ship and ship.has_method("get_current_speed_value"):
		var s_speed = ship.get_current_speed_value()
		if s_speed > 0.1:
			var s_dir = - ship.global_transform.basis.z.normalized()
			
			# AI/support ships may expose a smoothed move direction for leading.
			if ship.has_method("get_move_direction_value"):
				s_dir = ship.get_move_direction_value()
				
			ship_vel = s_dir * s_speed
			
	var total_vel = local_vel + ship_vel * 0.28
	var lead_offset: Vector3 = total_vel * time_to_reach * 0.42
	var max_lead: float = clampf(distance * 0.14, 0.2, 1.4)
	if lead_offset.length() > max_lead:
		lead_offset = lead_offset.normalized() * max_lead
	current_target_pos += lead_offset

	
	current_target_pos.x += randf_range(-0.05, 0.05)
	current_target_pos.z += randf_range(-0.05, 0.05)
	
	var dmg_mult = attacker.get_meta("damage_multiplier") if attacker.has_meta("damage_multiplier") else 1.0
	var crit_chance = attacker.get_crit_chance_value() if attacker.has_method("get_crit_chance_value") else 0.1
	var crit_multiplier = attacker.get_crit_multiplier_value() if attacker.has_method("get_crit_multiplier_value") else 2.0
	var is_crit = randf() < crit_chance
	var dist = spawn_pos.distance_to(current_target_pos)
	var final_arc_height: float = clamp(dist * 0.12, 0.28, 1.8)
	
	# 레벨 매니저 또는 부모 트리에 추가 (이 시점에 _ready 실행됨)
	var spawn_parent = _resolve_spawn_parent(attacker.get_tree())
	spawn_parent.add_child(arrow)
	if arrow.has_method("launch"):
		arrow.launch(
			spawn_pos,
			current_target_pos,
			target,
			team_name,
			damage * dmg_mult * (crit_multiplier if is_crit else 1.0),
			"bow",
			arrow_speed,
			final_arc_height,
			is_crit
		)
		
	# 위치 및 방향 최종 보정
	arrow.global_position = spawn_pos
	arrow.look_at(current_target_pos, Vector3.UP)
	
	# 활 쏘는 소리
	var audio_manager = attacker.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager):
		audio_manager.play_sfx("bow_shoot", attacker.global_position, randf_range(0.84, 1.0))

func _try_launch_singigeon_proc(target: Node3D, attacker: Node3D, team_name: String) -> bool:
	if team_name != "player":
		return false
	if not is_instance_valid(singigeon_rocket_scene):
		return false
	var um = attacker.get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(um) or not ("current_levels" in um):
		return false
	var singigeon_level: int = int(um.current_levels.get("singigeon", 0))
	if singigeon_level <= 0:
		return false
	var upgrades: Dictionary = um.get("UPGRADES") if um.get("UPGRADES") is Dictionary else {}
	var proc_stats := UpgradeManagerDataHelper.get_singigeon_proc_stats(upgrades, um.current_levels, singigeon_level)
	var owner_ship: Node = attacker.get_owned_ship_node() if attacker.has_method("get_owned_ship_node") else null
	var cooldown_owner: Node = owner_ship if is_instance_valid(owner_ship) else attacker
	var now_msec := Time.get_ticks_msec()
	var next_proc_msec := int(cooldown_owner.get_meta(SINGIGEON_PROC_NEXT_MSEC_META, 0))
	if now_msec < next_proc_msec:
		return false
	var miss_count := int(cooldown_owner.get_meta(SINGIGEON_PROC_MISS_COUNT_META, 0))
	var chance := float(proc_stats.get("chance", 0.0))
	chance += minf(float(proc_stats.get("pity_max_bonus", 0.0)), float(miss_count) * float(proc_stats.get("pity_add", 0.0)))
	if randf() > chance:
		cooldown_owner.set_meta(SINGIGEON_PROC_MISS_COUNT_META, miss_count + 1)
		return false
	if not _launch_singigeon_proc_rocket(target, attacker, team_name, upgrades, singigeon_level):
		return false
	cooldown_owner.set_meta(SINGIGEON_PROC_MISS_COUNT_META, 0)
	var cooldown_msec := int(round(maxf(0.0, float(proc_stats.get("cooldown", 1.0))) * 1000.0))
	cooldown_owner.set_meta(SINGIGEON_PROC_NEXT_MSEC_META, now_msec + cooldown_msec)
	return true

func _launch_singigeon_proc_rocket(target: Node3D, attacker: Node3D, team_name: String, upgrades: Dictionary, singigeon_level: int) -> bool:
	var rocket = ScenePool.acquire(attacker.get_tree(), singigeon_rocket_scene) as Node3D
	if rocket == null:
		return false

	var stats: Dictionary = upgrades.get("singigeon", {}).get("stats", {})
	var projectile_speed := float(stats.get("projectile_speed", 32.0))
	var spawn_pos := attacker.global_position + Vector3.UP
	var current_target_pos := _get_singigeon_aim_point(target)
	var time_to_reach := clampf(spawn_pos.distance_to(current_target_pos) / maxf(projectile_speed, 1.0), 0.18, 0.9)
	var local_velocity: Vector3 = target.get_velocity_value() if target.has_method("get_velocity_value") else (target.get("velocity") if "velocity" in target else Vector3.ZERO)
	var target_ship: Node3D = target.get_owned_ship_node() if target.has_method("get_owned_ship_node") else _resolve_parent_ship(target)
	var ship_velocity := Vector3.ZERO
	if is_instance_valid(target_ship) and target_ship.has_method("get_current_speed_value"):
		var ship_speed: float = target_ship.get_current_speed_value()
		if ship_speed > 0.1:
			var ship_dir: Vector3 = -target_ship.global_transform.basis.z.normalized()
			if target_ship.has_method("get_move_direction_value"):
				ship_dir = target_ship.get_move_direction_value()
			ship_velocity = ship_dir * ship_speed
	current_target_pos += (local_velocity + ship_velocity) * time_to_reach * 0.9
	current_target_pos.x += randf_range(-0.08, 0.08)
	current_target_pos.z += randf_range(-0.08, 0.08)

	if "start_pos" in rocket:
		rocket.start_pos = spawn_pos
	if "target_pos" in rocket:
		rocket.target_pos = current_target_pos
	if "target_node" in rocket:
		rocket.target_node = target
	if "speed" in rocket:
		rocket.speed = projectile_speed
	if "damage" in rocket:
		rocket.damage = float(stats.get("base_damage", 2.5))
	if "personnel_damage_mult" in rocket:
		rocket.personnel_damage_mult = float(stats.get("personnel_damage_mult", 6.0))
	if "crit_chance" in rocket:
		rocket.crit_chance = attacker.get_crit_chance_value() if attacker.has_method("get_crit_chance_value") else 0.1
	if "crit_multiplier" in rocket:
		rocket.crit_multiplier = attacker.get_crit_multiplier_value() if attacker.has_method("get_crit_multiplier_value") else 2.0
	if "prefer_personnel_targets" in rocket:
		rocket.prefer_personnel_targets = true
	if "lock_on_delay" in rocket:
		rocket.lock_on_delay = 0.02
	if "homing_duration" in rocket:
		rocket.homing_duration = 0.95
	if "max_homing_distance" in rocket:
		rocket.max_homing_distance = maxf(float(rocket.max_homing_distance), 26.0)
	if "proximity_hit_radius" in rocket:
		rocket.proximity_hit_radius = 2.0
	if "allow_retarget" in rocket:
		rocket.allow_retarget = true
	if "retarget_radius" in rocket:
		rocket.retarget_radius = maxf(float(rocket.retarget_radius), 20.0)
	if "turn_rate_deg" in rocket:
		rocket.turn_rate_deg = maxf(float(rocket.turn_rate_deg), 155.0)
	if "terminal_turn_rate_deg" in rocket:
		rocket.terminal_turn_rate_deg = maxf(float(rocket.terminal_turn_rate_deg), 320.0)
	if "burst_phase_duration" in rocket:
		rocket.burst_phase_duration = minf(float(rocket.burst_phase_duration), 0.08)
	if "team" in rocket:
		rocket.team = team_name
	if "shooter" in rocket:
		var owner_ship: Node = attacker.get_owned_ship_node() if attacker.has_method("get_owned_ship_node") else null
		rocket.shooter = owner_ship if is_instance_valid(owner_ship) else attacker

	var spawn_parent := _resolve_spawn_parent(attacker.get_tree())
	spawn_parent.add_child(rocket)
	rocket.global_position = spawn_pos
	if rocket.has_method("restart_flight"):
		rocket.restart_flight()
	if rocket.global_position.distance_squared_to(current_target_pos) > 0.0001:
		rocket.look_at(current_target_pos, Vector3.UP)
	return true

func _resolve_parent_ship(node: Node, max_depth: int = 6) -> Node3D:
	var current = node
	var depth = 0
	while is_instance_valid(current) and depth <= max_depth:
		if current is Node3D and "current_speed" in current:
			return current as Node3D
		current = current.get_parent()
		depth += 1
	return null

func _get_arrow_aim_point(target: Node) -> Vector3:
	var offset := SOLDIER_AIM_VERTICAL_OFFSET if target.is_in_group("soldiers") else SHIP_AIM_VERTICAL_OFFSET
	return NodeContractHelper.get_projectile_aim_point(target, offset)

func _get_singigeon_aim_point(target: Node) -> Vector3:
	var offset := SINGIGEON_AIM_VERTICAL_OFFSET if target.is_in_group("soldiers") else SINGIGEON_SHIP_AIM_VERTICAL_OFFSET
	return NodeContractHelper.get_projectile_aim_point(target, offset)

func _resolve_spawn_parent(tree: SceneTree) -> Node:
	if is_instance_valid(_cached_spawn_parent):
		return _cached_spawn_parent
	var lm = LevelManagerRegistry.get_level_manager(tree)
	if is_instance_valid(lm):
		_cached_spawn_parent = lm
		return _cached_spawn_parent
	_cached_spawn_parent = tree.root
	return _cached_spawn_parent
