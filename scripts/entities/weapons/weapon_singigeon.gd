extends "res://scripts/entities/weapons/weapon.gd"

@export var rocket_scene: PackedScene = preload("res://scenes/projectiles/singigeon_rocket.tscn")
@export var launch_cooldown: float = 5.0
@export var max_range: float = 24.0
@export var projectile_speed: float = 30.0

const SOLDIER_AIM_VERTICAL_OFFSET: float = 1.05
const SHIP_AIM_VERTICAL_OFFSET: float = 0.65

var personnel_damage_mult: float = 1.0
var _cached_spawn_parent: Node = null
var _upgrade_base_damage: float = 12.0
var _upgrade_damage_per_level: float = 2.0
var _owner_damage_bonus_pct: float = 0.0
var _upgrade_level: int = 1

func _ready() -> void:
	attack_range = max_range
	attack_cooldown = launch_cooldown
	refresh_upgrade_stats()

func refresh_upgrade_stats() -> void:
	_apply_upgrade_stats()

func apply_owner_damage_bonus_pct(damage_bonus_pct: float) -> void:
	_owner_damage_bonus_pct = maxf(0.0, damage_bonus_pct)
	_apply_effective_damage()

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not rocket_scene:
		return
	if target.is_in_group("soldiers") and SoldierStateHelper.is_dead_soldier(target):
		return

	var rocket = ScenePool.acquire(attacker.get_tree(), rocket_scene) as Node3D
	if rocket == null:
		return

	var spawn_pos: Vector3 = attacker.global_position
	spawn_pos.y += 1.0

	var current_target_pos: Vector3 = _get_singigeon_aim_point(target)
	var time_to_reach: float = clampf(spawn_pos.distance_to(current_target_pos) / maxf(projectile_speed, 1.0), 0.18, 0.9)
	var local_velocity: Vector3 = target.get_velocity_value() if target.has_method("get_velocity_value") else (target.get("velocity") if "velocity" in target else Vector3.ZERO)
	var ship_velocity: Vector3 = Vector3.ZERO
	var target_ship: Node3D = target.get_owned_ship_node() if target.has_method("get_owned_ship_node") else null
	if is_instance_valid(target_ship):
		if target_ship.has_method("get_current_speed_value"):
			var ship_speed: float = target_ship.get_current_speed_value()
			if ship_speed > 0.1:
				var ship_dir: Vector3 = -target_ship.global_transform.basis.z.normalized()
				if target_ship.has_method("get_move_direction_value"):
					ship_dir = target_ship.get_move_direction_value()
				ship_velocity = ship_dir * ship_speed
	current_target_pos += (local_velocity + ship_velocity) * time_to_reach * 0.9

	if "start_pos" in rocket:
		rocket.start_pos = spawn_pos
	if "target_pos" in rocket:
		rocket.target_pos = current_target_pos
	if "target_node" in rocket:
		rocket.target_node = target
	if "speed" in rocket:
		rocket.speed = projectile_speed
	if "damage" in rocket:
		rocket.damage = damage
	if "personnel_damage_mult" in rocket:
		rocket.personnel_damage_mult = personnel_damage_mult
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
	if "team" in rocket and attacker.has_method("get_team_tag"):
		rocket.team = attacker.get_team_tag()
	if "shooter" in rocket:
		var owner_ship: Node = attacker.get_owned_ship_node() if attacker.has_method("get_owned_ship_node") else null
		rocket.shooter = owner_ship if is_instance_valid(owner_ship) else attacker

	var spawn_parent := _resolve_spawn_parent(attacker.get_tree())
	spawn_parent.add_child(rocket)
	rocket.global_position = spawn_pos
	if rocket.has_method("restart_flight"):
		rocket.restart_flight()
	rocket.look_at(current_target_pos, Vector3.UP)
	_play_singigeon_launch_sfx(attacker, spawn_pos)

func _apply_upgrade_stats() -> void:
	var um = get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(um):
		return
	if not ("current_levels" in um):
		return
	_upgrade_level = maxi(1, int(um.current_levels.get("singigeon", 1)))
	if "singigeon" in um.UPGRADES:
		var stats: Dictionary = um.UPGRADES["singigeon"].get("stats", {})
		_upgrade_base_damage = float(stats.get("base_damage", 12.0))
		_upgrade_damage_per_level = float(stats.get("damage_per_lv", 2.0))
		personnel_damage_mult = float(stats.get("personnel_damage_mult", 1.0))
		attack_cooldown = maxf(2.2, float(stats.get("base_cooldown", 5.0)) - (float(_upgrade_level - 1) * float(stats.get("cooldown_reduce_per_lv", 0.35))))
		projectile_speed = float(stats.get("projectile_speed", 30.0))
	_apply_effective_damage()

func _apply_effective_damage() -> void:
	var level_damage := _upgrade_base_damage + float(maxi(0, _upgrade_level - 1)) * _upgrade_damage_per_level
	damage = level_damage * (1.0 + _owner_damage_bonus_pct)

func _get_singigeon_aim_point(target: Node) -> Vector3:
	var offset := SOLDIER_AIM_VERTICAL_OFFSET if target.is_in_group("soldiers") else SHIP_AIM_VERTICAL_OFFSET
	return NodeContractHelper.get_projectile_aim_point(target, offset)

func _play_singigeon_launch_sfx(attacker: Node, spawn_pos: Vector3) -> void:
	if not is_instance_valid(attacker):
		return
	var audio_manager = attacker.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("singigeon_launch", spawn_pos, randf_range(0.96, 1.06))

func _resolve_spawn_parent(tree: SceneTree) -> Node:
	if is_instance_valid(_cached_spawn_parent):
		return _cached_spawn_parent
	var lm = LevelManagerRegistry.get_level_manager(tree)
	if is_instance_valid(lm):
		_cached_spawn_parent = lm
		return _cached_spawn_parent
	_cached_spawn_parent = tree.root
	return _cached_spawn_parent
