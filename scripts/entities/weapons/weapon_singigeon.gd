extends "res://scripts/entities/weapons/weapon.gd"
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

@export var rocket_scene: PackedScene = preload("res://scenes/projectiles/singigeon_rocket.tscn")
@export var launch_cooldown: float = 5.0
@export var max_range: float = 24.0
@export var projectile_speed: float = 32.0

var blast_radius: float = 3.5
var personnel_damage_mult: float = 5.0
var _cached_spawn_parent: Node = null
var _upgrade_base_damage: float = 2.5

func _ready() -> void:
	attack_range = max_range
	attack_cooldown = launch_cooldown
	refresh_upgrade_stats()

func refresh_upgrade_stats() -> void:
	_apply_upgrade_stats()

func apply_owner_attack_damage(owner_attack_damage: float) -> void:
	var owner_bonus: float = maxf(0.0, owner_attack_damage - 12.0)
	damage = _upgrade_base_damage + owner_bonus

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not rocket_scene:
		return

	var rocket = ScenePool.acquire(attacker.get_tree(), rocket_scene) as Node3D
	if rocket == null:
		return

	var spawn_pos: Vector3 = attacker.global_position
	spawn_pos.y += 1.0

	var current_target_pos: Vector3 = target.global_position
	current_target_pos.y += 0.8
	var time_to_reach: float = clampf(spawn_pos.distance_to(current_target_pos) / maxf(projectile_speed, 1.0), 0.18, 0.9)
	var target_velocity: Variant = target.get("velocity")
	var local_velocity: Vector3 = Vector3.ZERO
	if typeof(target_velocity) == TYPE_VECTOR3:
		local_velocity = target_velocity
	var ship_velocity: Vector3 = Vector3.ZERO
	var target_ship_variant: Variant = target.get("owned_ship")
	if target_ship_variant is Node3D:
		var target_ship: Node3D = target_ship_variant
		if "current_speed" in target_ship:
			var ship_speed: float = float(target_ship.get("current_speed"))
			if ship_speed > 0.1:
				var ship_dir: Vector3 = -target_ship.global_transform.basis.z.normalized()
				if "move_dir" in target_ship and typeof(target_ship.get("move_dir")) == TYPE_VECTOR3:
					var move_dir: Vector3 = target_ship.get("move_dir")
					if move_dir.length_squared() > 0.0001:
						ship_dir = move_dir.normalized()
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
	if "blast_radius" in rocket:
		rocket.blast_radius = blast_radius
	if "personnel_damage_mult" in rocket:
		rocket.personnel_damage_mult = personnel_damage_mult
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
	if "team" in rocket and "team" in attacker:
		rocket.team = attacker.get("team")
	if "shooter" in rocket:
		var owner_ship: Node = attacker.get("owned_ship") as Node
		rocket.shooter = owner_ship if is_instance_valid(owner_ship) else attacker

	var spawn_parent := _resolve_spawn_parent(attacker.get_tree())
	spawn_parent.add_child(rocket)
	rocket.global_position = spawn_pos
	rocket.look_at(current_target_pos, Vector3.UP)

func _apply_upgrade_stats() -> void:
	var um = get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(um):
		return
	if not ("current_levels" in um):
		return
	var level: int = int(um.current_levels.get("singigeon", 1))
	if "singigeon" in um.UPGRADES:
		var stats: Dictionary = um.UPGRADES["singigeon"].get("stats", {})
		_upgrade_base_damage = float(stats.get("base_damage", 2.5))
		personnel_damage_mult = float(stats.get("personnel_damage_mult", 5.0))
		blast_radius = float(stats.get("base_blast_radius", 3.5)) + (float(level - 1) * float(stats.get("blast_radius_per_lv", 0.2)))
		attack_cooldown = maxf(2.2, float(stats.get("base_cooldown", 5.0)) - (float(level - 1) * float(stats.get("cooldown_reduce_per_lv", 0.35))))
		projectile_speed = float(stats.get("projectile_speed", 32.0))
	damage = _upgrade_base_damage

func _resolve_spawn_parent(tree: SceneTree) -> Node:
	if is_instance_valid(_cached_spawn_parent):
		return _cached_spawn_parent
	var lm = LevelManagerRegistry.get_level_manager(tree)
	if is_instance_valid(lm):
		_cached_spawn_parent = lm
		return _cached_spawn_parent
	_cached_spawn_parent = tree.root
	return _cached_spawn_parent
