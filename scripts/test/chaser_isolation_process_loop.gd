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


func can_use_fire_pot_attack() -> bool:
	return false


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
