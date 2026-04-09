extends RefCounted
class_name ChaserShipAiHelper

const ChaserShipNavigationHelper = preload("res://scripts/entities/ships/chaser_ship_navigation_helper.gd")

static func _is_gunner(ship) -> bool:
	if ship.has_method("is_gunner_role"):
		return bool(ship.call("is_gunner_role"))
	return int(ship.combat_role) == int(ship.CombatRole.GUNNER)


static func _can_board(ship) -> bool:
	if ship.has_method("can_board_targets"):
		return bool(ship.call("can_board_targets"))
	return bool(ship.allow_boarding)


static func _calculate_sail_drive_multiplier(ship, floor_ratio: float = 0.45) -> float:
	if not is_instance_valid(ship._cached_wind_manager):
		return 1.0
	if not ship._cached_wind_manager.has_method("get_wind_direction") or not ship._cached_wind_manager.has_method("get_wind_strength"):
		return 1.0

	var wind_dir: Vector2 = ship._cached_wind_manager.get_wind_direction()
	var wind_strength: float = ship._cached_wind_manager.get_wind_strength()
	var ship_angle_rad: float = ship.rotation.y
	var sail_world_rad: float = ship_angle_rad - deg_to_rad(ship.sail_angle)
	var sail_normal: Vector2 = -Vector2(sin(sail_world_rad), cos(sail_world_rad))
	var ship_forward: Vector2 = Vector2(-sin(ship_angle_rad), -cos(ship_angle_rad))
	var wind_force: float = max(0.0, wind_dir.dot(sail_normal))
	var forward_component: float = max(0.0, sail_normal.dot(ship_forward))
	var thrust: float = wind_force * forward_component
	var sail_efficiency: float = clamp((thrust * wind_strength) / 0.6, 0.0, 1.0)
	return lerp(floor_ratio, 1.05, sail_efficiency)


static func process_physics(ship, delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if ship.is_dying:
		return

	update_wave_sounds(ship, delta)

	ship.logic_timer -= delta
	var do_logic_update = false
	if ship.logic_timer <= 0:
		ship.logic_timer = _get_logic_update_interval(ship)
		do_logic_update = true
	if ship.has_meta("post_impact_follow_timer"):
		var follow_timer: float = maxf(0.0, float(ship.get_meta("post_impact_follow_timer")) - delta)
		if follow_timer <= 0.0:
			ship.remove_meta("post_impact_follow_timer")
		else:
			ship.set_meta("post_impact_follow_timer", follow_timer)

	if ship.is_derelict:
		var wind_manager = ship.get_node_or_null("/root/WindManager")
		if is_instance_valid(wind_manager):
			var wind_dir_v2: Vector2 = wind_manager.wind_direction
			var wind_dir = Vector3(wind_dir_v2.x, 0, wind_dir_v2.y)
			var wind_force = wind_manager.wind_strength * 0.4
			ship.position += wind_dir * wind_force * delta

			var target_rot = atan2(-wind_dir.x, -wind_dir.z)
			ship.rotation.y = lerp_angle(ship.rotation.y, target_rot, delta * 0.5)
			ship._set_wake_state(false)

		if do_logic_update:
			ship._check_offscreen_despawn()
		return

	ship.update_crew_allocation_state(delta)

	if do_logic_update:
		update_logic_throttled(ship)

	if ship.team == "player":
		ship._process_minion_ai(delta)
		return

	if ship.is_boarding:
		ship._process_boarding(delta)
		return

	if not is_instance_valid(ship.target):
		ship._set_wake_state(false)
		return

	var nav := ChaserShipNavigationHelper.build_navigation(ship, ship.target)
	var target_pos: Vector3 = nav["target_pos"]
	var desired_point: Vector3 = nav["desired_point"]
	var heading_point: Vector3 = nav["heading_point"]
	var dist_to_target: float = nav["dist_to_target"]
	var desired_speed_mult: float = nav["desired_speed_mult"]
	var permit_sprint: bool = nav["permit_sprint"]
	var dir_to_target: Vector3 = nav["dir_to_target"]

	if not _is_gunner(ship) and _can_board(ship) and dist_to_target <= ship.max_boarding_distance + 0.35:
		if ship.has_method("_is_side_boarding_approach") and ship.call("_is_side_boarding_approach", ship.target):
			if ship.has_method("_board_ship"):
				ship.call("_board_ship", ship.target)
				if ship.is_boarding:
					ship._process_boarding(delta)
					return

	var move_vector = desired_point - ship.global_position
	move_vector.y = 0.0
	var move_dir = move_vector.normalized() if move_vector.length_squared() > 0.001 else Vector3.ZERO
	if ship.separation_force.length_squared() > 0.001:
		if move_dir == Vector3.ZERO:
			move_dir = ship.separation_force.normalized()
		else:
			move_dir = (move_dir + ship.separation_force * 1.5).normalized()

	var heading_vector = heading_point - ship.global_position
	heading_vector.y = 0.0
	if heading_vector.length_squared() <= 0.001:
		heading_vector = move_dir if move_dir.length_squared() > 0.001 else dir_to_target
	var target_rotation_y = atan2(-heading_vector.x, -heading_vector.z)
	var angle_diff = wrapf(target_rotation_y - ship.rotation.y, -PI, PI)
	var desired_rudder = clamp(-rad_to_deg(angle_diff) * ship.ai_rudder_gain, -40.0, 40.0)
	var close_turn_blend = 0.0
	if ship.ai_close_turn_soft_radius > 0.01:
		close_turn_blend = clamp(1.0 - (dist_to_target / ship.ai_close_turn_soft_radius), 0.0, 1.0)
	var close_turn_factor = lerp(1.0, ship.ai_close_turn_scale, close_turn_blend)
	desired_rudder *= close_turn_factor
	var rudder_speed_adjusted = ship.ai_rudder_response_speed * ship.get_rudder_response_multiplier()
	ship.rudder_angle = move_toward(ship.rudder_angle, desired_rudder, rudder_speed_adjusted * delta)

	var leak_speed_mult = clamp(1.0 - (ship.leaking_rate * 0.05), 0.3, 1.0)
	var desired_speed = ship.move_speed * leak_speed_mult * desired_speed_mult * ship.get_shiphandling_multiplier()

	if not _is_gunner(ship) and dist_to_target < 4.4:
		var slow_factor = clamp((dist_to_target - 1.4) / 3.0, 0.88, 1.0)
		desired_speed *= slow_factor
		ship.is_sprinting = false
	else:
		if ship.team == "enemy" and permit_sprint:
			if not ship.is_sprinting and dist_to_target > 10.0 and dist_to_target < 28.0 and ship.stamina > 30.0:
				ship.is_sprinting = true
			if ship.is_sprinting and (ship.stamina <= 0.0 or dist_to_target <= 8.0):
				ship.is_sprinting = false

			if ship.is_sprinting:
				ship.stamina = max(0.0, ship.stamina - 20.0 * delta)
				desired_speed *= ship.sprint_multiplier
			else:
				ship.stamina = min(ship.max_stamina, ship.stamina + 15.0 * delta)
		else:
			ship.is_sprinting = false
			ship.stamina = min(ship.max_stamina, ship.stamina + 18.0 * delta)

	if desired_speed > ship.current_speed:
		ship.current_speed = move_toward(ship.current_speed, desired_speed, ship.acceleration * delta)
	else:
		ship.current_speed = move_toward(ship.current_speed, desired_speed, ship.deceleration * delta)

	var wind_mult: float = _calculate_sail_drive_multiplier(ship) * ship.get_shiphandling_multiplier()
	if ship.current_speed > 0.1:
		var speed_ratio = clamp(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0)
		var turn_scale = ship.ai_turn_authority * close_turn_factor
		var actual_turn = (ship.rudder_angle / 45.0) * ship.turn_rate * ship.get_rudder_turn_multiplier() * speed_ratio * ship.turn_mult * turn_scale * delta
		var max_turn_this_frame = ship.ai_max_turn_rate * delta
		actual_turn = clamp(actual_turn, -max_turn_this_frame, max_turn_this_frame)
		ship.rotation.y -= deg_to_rad(actual_turn)

	var forward_vec = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y))
	var velocity = forward_vec * ship.current_speed * wind_mult
	velocity += ship.separation_force
	velocity += ship._calculate_boarding_pull() * delta
	var collision_repulsion = ship._calculate_collision_repulsion()
	if not _is_gunner(ship) and dist_to_target < ship.max_boarding_distance + 1.2:
		var to_target_flat = ship.target.global_position - ship.global_position
		to_target_flat.y = 0.0
		if to_target_flat.length_squared() > 0.001:
			var approach_dot = forward_vec.normalized().dot(to_target_flat.normalized())
			if approach_dot > 0.3:
				collision_repulsion *= 0.35
	velocity += collision_repulsion * delta

	var prev_pos = ship.global_position
	var next_pos = prev_pos + velocity * delta
	# Allow visible impact with the target, but stop the AI from tunneling so deep
	# that ships overlap past the midline before the collision reads as a hit.
	if is_instance_valid(ship.target):
		next_pos = ship._apply_ship_collision_guard(ship.target, prev_pos, next_pos, 0.88, velocity.length())
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, ship.target)
	ship.global_position = next_pos

	ship._update_rudder_visual()
	if ship.leaking_rate > 0:
		ship.take_damage(ship.leaking_rate * delta)
	ship._apply_bobbing_effect()
	if not ship.is_dying:
		ship.rotation.z += ship.tilt_offset
	ship._set_wake_state(ship.current_speed > 0.4, clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0), 0.0, 0.0)


static func update_logic_throttled(ship) -> void:
	if not is_instance_valid(ship.target) or ship.target.get("is_sinking"):
		ship.target = null
		find_player(ship)
	if ship.team == "player" and bool(ship.get_meta("support_fleet_ship", false)):
		ship.separation_force = Vector3.ZERO
		return
	ship.separation_force = ship._calculate_separation()


static func _get_logic_update_interval(ship) -> float:
	if ship.has_method("get_ai_logic_update_interval"):
		return maxf(0.06, float(ship.call("get_ai_logic_update_interval")))
	return 0.2


static func find_player(ship) -> void:
	var players = ship.SceneGroupCache.get_nodes(ship.get_tree(), "player")

	if ship.is_in_group("captured_minion") or ship.team == "player":
		for p in players:
			if p.get("is_player_controlled") == true:
				ship.target = p
				break
		return

	var closest_dist = INF
	var closest_player = null
	for p in players:
		if p == ship:
			continue
		if not p.get("is_sinking") and not p.get("is_dead"):
			var dist = ship.global_position.distance_squared_to(p.global_position)
			var weight = 1.0
			if p.get("is_player_controlled") == true:
				weight = 0.8
			var weighted_dist = dist * weight
			if weighted_dist < closest_dist:
				closest_dist = weighted_dist
				closest_player = p

	ship.target = closest_player


static func update_wave_sounds(ship, delta: float) -> void:
	if ship.is_dying or ship.is_derelict:
		return

	var speed = ship.move_speed
	if not is_instance_valid(ship.target):
		speed = 0.0

	if speed > 0.5:
		ship._wave_timer -= delta
		if ship._wave_timer <= 0:
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
				ship._cached_audio_manager.play_sfx("wave_splash", ship.global_position, randf_range(0.8, 1.2), 3.0)
			var speed_mod = clamp(speed / 5.0, 0.4, 1.5)
			ship._wave_timer = randf_range(2.0, 4.5) / speed_mod
