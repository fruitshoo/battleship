extends RefCounted
class_name ChaserShipAiHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const ChaserShipNavigationHelper = preload("res://scripts/entities/ships/chaser_ship_navigation_helper.gd")

static var _cached_ships_list: Array = []
static var _last_ships_cache_frame: int = -1

static func _is_true(value: Variant) -> bool:
	return value == true

static func _is_gunner(ship) -> bool:
	if ship.has_method("is_gunner_role"):
		return ship.call("is_gunner_role") == true
	return int(ship.combat_role) == int(ship.CombatRole.GUNNER)


static func _can_board(ship) -> bool:
	if ship.has_method("can_board_targets"):
		return ship.call("can_board_targets") == true
	return ship.allow_boarding == true


static func _target_ship(ship) -> Node3D:
	if not is_instance_valid(ship):
		return null
	if ship.has_method("get_target_ship"):
		return ship.get_target_ship()
	if "target" in ship:
		return ship.get("target")
	return null


static func _is_sinking_or_dying(node: Node) -> bool:
	if not is_instance_valid(node):
		return true
	if node.has_method("is_sinking_or_dying"):
		return node.is_sinking_or_dying()
	return _is_true(node.get("is_dying")) or _is_true(node.get("is_sinking"))


static func _is_player_controlled(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_player_controlled_ship"):
		return node.is_player_controlled_ship()
	return _is_true(node.get("is_player_controlled"))


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


static func get_ships_cached(_tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_ships_cache_frame:
		_cached_ships_list = EntityRegistry.get_ships()
		_last_ships_cache_frame = current_frame
	return _cached_ships_list


static func configure_logic_throttle(ship) -> void:
	var seed_value: int = abs(hash("%s:%s:%s" % [str(ship.get_instance_id()), ship.ship_type, ship.formation_role_name]))
	var phase: float = float(seed_value % 1000) / 1000.0
	var jitter_sign: float = -1.0 if (seed_value % 2) == 0 else 1.0
	var jitter_scale: float = float(seed_value % 500) / 500.0
	var jitter: float = ship.ai_logic_update_jitter * jitter_sign * jitter_scale
	ship._ai_logic_update_interval_runtime = clampf(ship.ai_logic_update_interval + jitter, 0.06, 0.5)
	ship._ai_separation_update_interval_runtime = get_separation_update_interval_runtime(ship, seed_value)
	ship.logic_timer = ship._ai_logic_update_interval_runtime * phase
	ship.separation_timer = ship._ai_separation_update_interval_runtime * phase


static func get_logic_update_interval_for_ship(ship) -> float:
	return ship._ai_logic_update_interval_runtime * get_load_multiplier(ship)


static func get_separation_update_interval_for_ship(ship) -> float:
	return ship._ai_separation_update_interval_runtime * get_load_multiplier(ship)


static func get_load_multiplier(ship) -> float:
	var ship_count: int = EntityRegistry.count_ships()
	var projectile_count: int = EntityRegistry.count_projectiles()
	var load_multiplier: float = 1.0
	if ship_count > 12:
		load_multiplier += minf(0.45, float(ship_count - 12) * 0.03)
	if projectile_count > 18:
		load_multiplier += minf(0.25, float(projectile_count - 18) * 0.01)
	if ship.team == "player":
		load_multiplier *= 0.9
	if _is_gunner(ship):
		load_multiplier *= 1.05
	return clampf(load_multiplier, 0.75, 1.6)


static func get_separation_update_interval_runtime(ship, seed_value: int) -> float:
	var base_interval: float = clampf(ship.ai_separation_update_interval, 0.05, 0.35)
	var role_adjust: float = 0.0
	if _is_gunner(ship):
		role_adjust = 0.02
	elif ship.has_method("is_charger_role") and ship.is_charger_role():
		role_adjust = -0.01
	var phase_jitter: float = float(seed_value % 7) * 0.005
	return clampf(base_interval + role_adjust + phase_jitter, 0.05, 0.35)


static func calculate_separation(ship) -> Vector3:
	if _is_true(ship.get_meta("derelict_nonblocking", false)):
		return Vector3.ZERO

	var force := Vector3.ZERO
	var neighbors := get_ships_cached(ship.get_tree())
	var count := 0
	var max_checks: int = min(neighbors.size(), 15)
	for i in range(max_checks):
		var other = neighbors[i]
		if other == ship or not is_instance_valid(other) or _is_true(other.get("is_dying")):
			continue
		if _is_true(other.get_meta("derelict_nonblocking", false)):
			continue
		if ship.is_boarding and other == ship.boarding_target:
			continue
		if other.has_method("get_boarding_attacker_ship") and other.get_boarding_attacker_ship() == ship:
			continue

		var offset: Vector3 = ship.global_position - other.global_position
		offset.y = 0.0
		var dist_sq: float = offset.length_squared()
		if dist_sq <= 0.01:
			continue

		var dist := sqrt(dist_sq)
		var coll_dist: float = ship.get_collision_distance_to(other)
		if ship.has_method("is_charger_role") and ship.is_charger_role() and is_instance_valid(_target_ship(ship)) and other == _target_ship(ship) and dist < coll_dist + 1.2:
			continue
		var separation_trigger_dist: float = coll_dist + (0.18 * ship.separation_pad_scale)

		if dist < separation_trigger_dist:
			var push_dir := offset.normalized()
			var ratio: float = (separation_trigger_dist - dist) / max(separation_trigger_dist, 0.001)
			var strength: float = pow(ratio, 2.0)
			force += push_dir * strength
			count += 1

	if count > 0:
		force = (force / count) * 1.8

	return force


static func process_physics(ship, delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if ship.has_method("is_combat_disabled") and ship.is_combat_disabled():
		return

	update_wave_sounds(ship, delta)

	ship.logic_timer -= delta
	var do_logic_update = false
	if ship.logic_timer <= 0:
		ship.logic_timer = _get_logic_update_interval(ship)
		do_logic_update = true
	ship.separation_timer -= delta
	if ship.separation_timer <= 0.0:
		ship.separation_timer = _get_separation_update_interval(ship)
		if ship.team == "player" and _is_true(ship.get_meta("support_fleet_ship", false)):
			ship.separation_force = Vector3.ZERO
		else:
			ship.separation_force = calculate_separation(ship)
	if ship.has_meta("post_impact_follow_timer"):
		var follow_timer: float = maxf(0.0, float(ship.get_meta("post_impact_follow_timer")) - delta)
		if follow_timer <= 0.0:
			ship.remove_meta("post_impact_follow_timer")
		else:
			ship.set_meta("post_impact_follow_timer", follow_timer)
	if ship.has_meta("boarding_impact_grace_timer"):
		var impact_grace_timer: float = maxf(0.0, float(ship.get_meta("boarding_impact_grace_timer")) - delta)
		if impact_grace_timer <= 0.0:
			ship.remove_meta("boarding_impact_grace_timer")
			if ship.has_meta("boarding_impact_target_id"):
				ship.remove_meta("boarding_impact_target_id")
		else:
			ship.set_meta("boarding_impact_grace_timer", impact_grace_timer)

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

	if ship.get_team_tag() == "player":
		if ship.is_boarding:
			ship._process_boarding(delta)
			return
		ship._process_minion_ai(delta)
		return

	if ship.is_boarding:
		ship._process_boarding(delta)
		return

	if not is_instance_valid(_target_ship(ship)):
		ship._set_wake_state(false)
		return
	var current_target: Node3D = _target_ship(ship)

	var nav := ChaserShipNavigationHelper.build_navigation(ship, current_target)
	var target_pos: Vector3 = nav["target_pos"]
	var desired_point: Vector3 = nav["desired_point"]
	var heading_point: Vector3 = nav["heading_point"]
	var dist_to_target: float = nav["dist_to_target"]
	var desired_speed_mult: float = nav["desired_speed_mult"]
	var permit_sprint: bool = nav["permit_sprint"]
	var dir_to_target: Vector3 = nav["dir_to_target"]

	if not _is_gunner(ship) and _can_board(ship) and dist_to_target <= ship.boarding_break_distance:
		var can_side_board: bool = ship.has_method("_is_side_boarding_approach") and ship.call("_is_side_boarding_approach", current_target)
		var can_force_head_on: bool = ship.has_method("_can_force_head_on_boarding") and ship.call("_can_force_head_on_boarding", current_target)
		var can_force_cleanup: bool = ship.has_method("_can_force_cleanup_boarding") and ship.call("_can_force_cleanup_boarding", current_target)
		var can_latched_board: bool = ship.has_method("_can_start_boarding_latched") and ship.call("_can_start_boarding_latched", current_target, dist_to_target, can_side_board, can_force_head_on, can_force_cleanup, delta)
		var direct_board_pad: float = 0.35
		if ship.has_method("get_team_tag") and ship.call("get_team_tag") == "enemy":
			direct_board_pad += 0.15
		var can_direct_board: bool = (can_side_board or can_force_head_on or can_force_cleanup) and dist_to_target <= ship.max_boarding_distance + direct_board_pad
		var impact_confirmed: bool = ship.has_method("_has_recent_boarding_impact") and ship.call("_has_recent_boarding_impact", current_target)
		if (can_latched_board or can_direct_board) and impact_confirmed:
			if ship.has_method("_board_ship"):
				ship.call("_board_ship", current_target)
				if ship.is_boarding:
					ship._process_boarding(delta)
					return
	elif ship.has_method("_decay_boarding_latch"):
		ship.call("_decay_boarding_latch", current_target, delta)

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
	if is_instance_valid(current_target):
		next_pos = ship._apply_ship_collision_guard(current_target, prev_pos, next_pos, 0.88, velocity.length())
	next_pos = ship._apply_neighbor_ship_guards(prev_pos, next_pos, current_target)
	ship.global_position = next_pos

	ship._update_rudder_visual()
	if ship.leaking_rate > 0:
		ship.take_damage(ship.leaking_rate * delta)
	ship._apply_bobbing_effect()
	if not ship.is_dying:
		ship.rotation.z += ship.tilt_offset
	ship._set_wake_state(ship.current_speed > 0.4, clampf(ship.current_speed / maxf(ship.max_speed, 0.01), 0.0, 1.0), 0.0, 0.0)


static func update_logic_throttled(ship) -> void:
	if not is_instance_valid(_target_ship(ship)) or _is_sinking_or_dying(_target_ship(ship)):
		ship.target = null
		find_player(ship)


static func _get_logic_update_interval(ship) -> float:
	if ship.has_method("get_ai_logic_update_interval"):
		return maxf(0.06, float(ship.call("get_ai_logic_update_interval")))
	return 0.2


static func _get_separation_update_interval(ship) -> float:
	if ship.has_method("get_ai_separation_update_interval"):
		return maxf(0.05, float(ship.call("get_ai_separation_update_interval")))
	return 0.12


static func find_player(ship) -> void:
	var players = EntityRegistry.get_ships_by_team("player")

	if ship.team == "player":
		for p in players:
			if _is_player_controlled(p):
				ship.target = p
				break
		return

	var closest_dist = INF
	var closest_player = null
	for p in players:
		if p == ship:
			continue
		if not _is_sinking_or_dying(p):
			var dist = ship.global_position.distance_squared_to(p.global_position)
			var weight = 1.0
			if _is_player_controlled(p):
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
