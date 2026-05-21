@tool
extends "res://scripts/test/ai_ship_isolation_runtime_methods.gd"

const AIShipRuntimeHelper = preload("res://scripts/entities/ships/ai_ship_runtime_helper.gd")

var separation_timer: float = 0.0
var logic_timer: float = 0.0
@export_range(0.05, 0.5, 0.01) var ai_logic_update_interval: float = 0.2
@export_range(0.0, 0.15, 0.01) var ai_logic_update_jitter: float = 0.05
var _ai_logic_update_interval_runtime: float = 0.2
@export_range(0.05, 0.5, 0.01) var ai_separation_update_interval: float = 0.12
var _ai_separation_update_interval_runtime: float = 0.12
@export_range(0.25, 1.5) var separation_pad_scale: float = 1.0
static var _cached_ships_list: Array = []
static var _last_ships_cache_frame: int = -1


func is_gunner_role() -> bool:
	return int(combat_role) == int(CombatRole.GUNNER)


func is_charger_role() -> bool:
	return not is_gunner_role()


static func get_ships_cached(_tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_ships_cache_frame:
		_cached_ships_list = EntityRegistry.get_ships()
		_last_ships_cache_frame = current_frame
	return _cached_ships_list


func _physics_process(delta: float) -> void:
	AIShipRuntimeHelper.process_physics(self, delta)


func _update_logic_throttled() -> void:
	AIShipRuntimeHelper.update_logic_throttled(self)


func _configure_ai_logic_throttle() -> void:
	var seed_value: int = abs(hash("%s:%s:%s" % [str(get_instance_id()), ship_type, formation_role_name]))
	var phase: float = float(seed_value % 1000) / 1000.0
	var jitter_sign: float = -1.0 if (seed_value % 2) == 0 else 1.0
	var jitter_scale: float = float(seed_value % 500) / 500.0
	var jitter: float = ai_logic_update_jitter * jitter_sign * jitter_scale
	_ai_logic_update_interval_runtime = clampf(ai_logic_update_interval + jitter, 0.06, 0.5)
	_ai_separation_update_interval_runtime = _get_ai_separation_update_interval_runtime(seed_value)
	logic_timer = _ai_logic_update_interval_runtime * phase
	separation_timer = _ai_separation_update_interval_runtime * phase


func get_ai_logic_update_interval() -> float:
	return _ai_logic_update_interval_runtime * _get_ai_load_multiplier()


func get_ai_separation_update_interval() -> float:
	return _ai_separation_update_interval_runtime * _get_ai_load_multiplier()


func _get_ai_load_multiplier() -> float:
	var ship_count: int = EntityRegistry.count_ships()
	var projectile_count: int = EntityRegistry.count_projectiles()
	var load_multiplier: float = 1.0
	if ship_count > 12:
		load_multiplier += minf(0.45, float(ship_count - 12) * 0.03)
	if projectile_count > 18:
		load_multiplier += minf(0.25, float(projectile_count - 18) * 0.01)
	if team == "player":
		load_multiplier *= 0.9
	if is_gunner_role():
		load_multiplier *= 1.05
	return clampf(load_multiplier, 0.75, 1.6)


func _get_ai_separation_update_interval_runtime(seed_value: int) -> float:
	var base_interval: float = clampf(ai_separation_update_interval, 0.05, 0.35)
	var role_adjust: float = 0.0
	if is_gunner_role():
		role_adjust = 0.02
	elif is_charger_role():
		role_adjust = -0.01
	var phase_jitter: float = float(seed_value % 7) * 0.005
	return clampf(base_interval + role_adjust + phase_jitter, 0.05, 0.35)


func _calculate_separation() -> Vector3:
	if get_meta("derelict_nonblocking", false) == true:
		return Vector3.ZERO

	var force = Vector3.ZERO
	var neighbors = get_ships_cached(get_tree())
	var count = 0

	var _max_checks = min(neighbors.size(), 15)
	for i in range(_max_checks):
		var other = neighbors[i]
		if other == self or not is_instance_valid(other) or other.get("is_dying"):
			continue
		if other.get_meta("derelict_nonblocking", false) == true:
			continue
		if is_boarding and other == boarding_target:
			continue
		if other.has_method("get_boarding_attacker_ship") and other.get_boarding_attacker_ship() == self:
			continue

		var offset = global_position - other.global_position
		offset.y = 0.0
		var dist_sq = offset.length_squared()
		if dist_sq <= 0.01:
			continue

		var dist = sqrt(dist_sq)
		var coll_dist = get_collision_distance_to(other)
		if is_charger_role() and is_instance_valid(target) and other == target and dist < coll_dist + 1.2:
			continue
		var separation_trigger_dist = coll_dist + (0.18 * separation_pad_scale)

		if dist < separation_trigger_dist:
			var push_dir = offset.normalized()
			var ratio = (separation_trigger_dist - dist) / max(separation_trigger_dist, 0.001)
			var strength = pow(ratio, 2.0)
			force += push_dir * strength
			count += 1

	if count > 0:
		force = (force / count) * 1.8

	return force
