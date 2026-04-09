@tool
extends "res://scripts/test/chaser_isolation_runtime_methods.gd"

var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0
@export var minion_respawn_interval: float = 15.0
@export var max_minion_crew: int = 4
var minion_respawn_timer: float = 0.0
var _oar_time: float = 0.0
var fire_pot_cooldown_timer: float = 0.0
var is_sprinting: bool = false
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


func can_use_fire_pot_attack() -> bool:
	return false


static func get_ships_cached(_tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_ships_cache_frame:
		_cached_ships_list = EntityRegistry.get_ships()
		_last_ships_cache_frame = current_frame
	return _cached_ships_list


func _process(delta: float) -> void:
	if is_dying:
		return

	_update_fire_effect()
	_auto_adjust_sail(delta)
	_update_sail_visual()
	_update_oar_visual(delta)
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	_update_boarding_state(delta)
	_update_enemy_fire_pot_logic(delta)

	if is_derelict:
		leaking_rate += 0.2 * delta
		target = null

	if team == "player":
		_update_minion_respawn(delta)

	_update_leaking_damage(delta)


func _update_leaking_damage(delta: float) -> void:
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
		return
	_leak_tick_timer += delta
	while _leak_tick_timer >= 1.0:
		_leak_tick_timer -= 1.0
		take_damage(leaking_rate, global_position, "leak")


func _update_enemy_fire_pot_logic(delta: float) -> void:
	if not can_use_fire_pot_attack():
		return
	ChaserShipSupportHelper.update_enemy_fire_pot_logic(self, delta)


func _physics_process(delta: float) -> void:
	ChaserShipAiHelper.process_physics(self, delta)


func _update_logic_throttled() -> void:
	ChaserShipAiHelper.update_logic_throttled(self)


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
	if bool(get_meta("derelict_nonblocking", false)):
		return Vector3.ZERO

	var force = Vector3.ZERO
	var neighbors = get_ships_cached(get_tree())
	var count = 0

	var _max_checks = min(neighbors.size(), 15)
	for i in range(_max_checks):
		var other = neighbors[i]
		if other == self or not is_instance_valid(other) or other.get("is_dying"):
			continue
		if bool(other.get_meta("derelict_nonblocking", false)):
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


func _auto_adjust_sail(delta: float) -> void:
	if not is_instance_valid(_cached_wind_manager) or not _cached_wind_manager.has_method("get_wind_direction"):
		return
	var wind_dir = _cached_wind_manager.get_wind_direction()
	var wind_angle = rad_to_deg(atan2(wind_dir.x, -wind_dir.y))
	var ship_angle_ccw = rad_to_deg(rotation.y)
	var rel_wind_angle = wrapf(wind_angle + ship_angle_ccw, -180.0, 180.0)
	var target_sail_angle = clamp(rel_wind_angle / 2.0, -90.0, 90.0)
	sail_angle = move_toward(sail_angle, target_sail_angle, 60.0 * delta)


func _update_oar_visual(delta: float) -> void:
	var has_oars = oar_pivot_left or oar_pivot_right
	if not has_oars:
		return

	var is_moving = not is_derelict and move_speed > 0.5 and is_instance_valid(target)

	if is_moving:
		var oar_speed = 3.6 if is_sprinting else 1.8
		_oar_time += delta * oar_speed

		var sweep_angle = sin(_oar_time) * 0.2
		var twist_angle = sin(_oar_time * 2.0) * 0.1

		if oar_pivot_left:
			oar_pivot_left.rotation.x = sweep_angle
			oar_pivot_left.rotation.z = twist_angle
		if oar_pivot_right:
			oar_pivot_right.rotation.x = sweep_angle
			oar_pivot_right.rotation.z = -twist_angle
	else:
		if oar_pivot_left:
			oar_pivot_left.rotation.x = lerp_angle(oar_pivot_left.rotation.x, 0.0, delta * 2.0)
			oar_pivot_left.rotation.z = lerp_angle(oar_pivot_left.rotation.z, 0.0, delta * 2.0)
		if oar_pivot_right:
			oar_pivot_right.rotation.x = lerp_angle(oar_pivot_right.rotation.x, 0.0, delta * 2.0)
			oar_pivot_right.rotation.z = lerp_angle(oar_pivot_right.rotation.z, 0.0, delta * 2.0)


func _update_minion_respawn(delta: float) -> void:
	if deck_is_contested:
		return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node:
		return

	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4:
			alive_count += 1

	if alive_count < max_minion_crew:
		minion_respawn_timer += delta
		if minion_respawn_timer >= minion_respawn_interval:
			minion_respawn_timer = 0.0
			_respawn_minion_soldier()


func _respawn_minion_soldier() -> void:
	_spawn_one_soldier("player")
	print("[Crew] 나포함 병사 자생적 보충 완료.")
