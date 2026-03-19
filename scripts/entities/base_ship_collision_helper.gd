extends RefCounted
class_name BaseShipCollisionHelper

static func calculate_collision_repulsion(ship) -> Vector3:
	if bool(ship.get_meta("derelict_nonblocking", false)):
		return Vector3.ZERO

	var force = Vector3.ZERO
	var neighbors = ship.SceneGroupCache.get_nodes(ship.get_tree(), "ships")

	for other in neighbors:
		if other == ship or not is_instance_valid(other) or other.get("is_dying") or other.get("is_sinking"):
			continue
		if bool(other.get_meta("derelict_nonblocking", false)):
			continue

		var diff = other.global_position - ship.global_position
		diff.y = 0.0
		var dist_sq = diff.length_squared()
		var my_half = ship.get_collision_half_extents()
		var other_half = Vector2(
			other.base_collision_radius * other.width_multiplier,
			other.base_collision_radius * other.length_multiplier
		)
		var broad_phase_dist = maxf(my_half.x, my_half.y) + maxf(other_half.x, other_half.y) + ship.broad_phase_padding

		if dist_sq > broad_phase_dist * broad_phase_dist:
			continue

		var dist = sqrt(dist_sq)
		var dir = diff / max(dist, 0.001)
		var my_fwd = -ship.global_transform.basis.z
		my_fwd.y = 0.0
		if my_fwd.length_squared() > 0.0001:
			my_fwd = my_fwd.normalized()
		else:
			my_fwd = dir
		var other_fwd = -other.global_transform.basis.z
		other_fwd.y = 0.0
		if other_fwd.length_squared() > 0.0001:
			other_fwd = other_fwd.normalized()
		else:
			other_fwd = -dir

		var my_radius = ship.get_directional_collision_radius(dir)
		var other_radius = 0.0
		if other.has_method("get_directional_collision_radius"):
			other_radius = float(other.call("get_directional_collision_radius", -dir))
		else:
			other_radius = other.base_collision_radius * other.width_multiplier + (other.base_collision_radius * other.length_multiplier - other.base_collision_radius * other.width_multiplier) * absf(other_fwd.dot(-dir))
		var coll_dist = my_radius + other_radius
		var is_engagement_pair = ship._is_engagement_pair(other)
		if is_engagement_pair:
			coll_dist *= 0.90

		if dist < coll_dist:
			var compression = coll_dist - dist
			var target_speed = 0.0
			if "current_speed" in other:
				target_speed = other.current_speed
			var pre_collision_speed = ship.current_speed
			var pre_my_vel = my_fwd * pre_collision_speed
			var pre_other_vel = other_fwd * target_speed
			var approach_speed = (pre_my_vel - pre_other_vel).dot(dir)

			var repulsion_strength = 24.0 if is_engagement_pair else 40.0
			var head_on_pair = my_fwd.dot(dir) > 0.72 and other_fwd.dot(-dir) > 0.72
			var high_speed_head_on = head_on_pair and approach_speed >= ship.min_ramming_speed * 0.85
			if is_engagement_pair and head_on_pair:
				repulsion_strength *= 0.18
			elif high_speed_head_on:
				repulsion_strength *= 0.12
			var penetration_ratio = compression / maxf(coll_dist, 0.001)
			if penetration_ratio > 0.22:
				if high_speed_head_on:
					repulsion_strength = maxf(repulsion_strength, 26.0)
				else:
					repulsion_strength = maxf(repulsion_strength, 72.0)
			var repulsion_force = -dir * (compression * repulsion_strength)
			if (is_engagement_pair and head_on_pair) or high_speed_head_on:
				var backward_component = minf(0.0, repulsion_force.dot(my_fwd))
				if backward_component < 0.0:
					repulsion_force -= my_fwd * backward_component
			force += repulsion_force

			if ship.current_speed > 0.5:
				var forward_alignment = absf(my_fwd.dot(dir))
				if forward_alignment < 0.76 and penetration_ratio > 0.05:
					var slide_brake := lerpf(0.04, 0.16, clampf((penetration_ratio - 0.05) / 0.25, 0.0, 1.0))
					if is_engagement_pair:
						slide_brake *= 0.7
					elif high_speed_head_on:
						slide_brake *= 0.5
					ship.current_speed *= maxf(0.78, 1.0 - slide_brake)
				if my_fwd.dot(dir) > 0.8:
					if high_speed_head_on:
						ship.current_speed = lerp(ship.current_speed, 0.0, 0.72)
					elif is_engagement_pair:
						var stop_blend = 0.48 if head_on_pair else 0.24
						ship.current_speed = lerp(ship.current_speed, 0.0, stop_blend)
					else:
						ship.current_speed = lerp(ship.current_speed, 0.0, 0.1)

			if approach_speed >= ship.min_ramming_speed:
				ship.apply_ramming_damage(other, approach_speed)

	return force


static func apply_ramming_damage(ship, other: Node3D, impact_speed: float) -> void:
	if ship.is_sinking or ship.is_dying:
		return
	if impact_speed < ship.min_ramming_speed:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	if ship._recent_ram_targets.has(other):
		if current_time - ship._recent_ram_targets[other] < 1.0:
			return
	ship._recent_ram_targets[other] = current_time

	var my_fwd = Vector3(-sin(ship.rotation.y), 0, -cos(ship.rotation.y)).normalized()
	var dir_to_other = (other.global_position - ship.global_position).normalized()
	var dot = abs(my_fwd.dot(dir_to_other))
	var other_dot = 1.0
	if other.has_method("get_rotation"):
		var other_fwd = Vector3(-sin(other.rotation.y), 0, -cos(other.rotation.y)).normalized()
		other_dot = abs(other_fwd.dot(-dir_to_other))

	var angle_mult = remap(dot, 0.0, 1.0, 1.25, 0.30)
	var final_ram_damage = impact_speed * 3.2 * angle_mult

	var impact_pos = (ship.global_position + other.global_position) * 0.5
	impact_pos.y = 0.5

	if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
		ship._cached_audio_manager.play_sfx("impact_wood", ship.global_position, randf_range(0.6, 0.8), 5.0)

	var cam = ship.get_tree().root.get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(clamp(impact_speed * 0.05, 0.2, 0.6), 0.3)

	spawn_ship_collision_effects(ship, impact_pos, impact_speed)
	ship.apply_ramming_aoe(clamp(impact_speed * 1.5, 5.0, 20.0), impact_pos)

	if ship.DEBUG_COMBAT_LOGS:
		print("[Ramming] 충각 발생! (속도: %.1f) - 내 각도계수: %.2f -> 입은 피해: %.1f" % [impact_speed, angle_mult, final_ram_damage])
	ship.take_damage(final_ram_damage, (ship.global_position + other.global_position) * 0.5, "ramming")


static func spawn_ship_collision_effects(ship, impact_pos: Vector3, impact_speed: float) -> void:
	if not ship.is_inside_tree():
		return

	var splash_pos := impact_pos
	splash_pos.y = 0.2
	if ship.water_splash_scene and ship.VfxBudget.allow_spawn(ship.get_tree(), "ship_collision_splash", splash_pos, 3, 90.0):
		var splash = ship.ScenePool.acquire(ship.get_tree(), ship.water_splash_scene)
		if splash.has_method("configure_as_splash"):
			splash.configure_as_splash()
		ship.get_tree().root.add_child(splash)
		splash.position = splash_pos
		if splash.has_method("pool_activate"):
			splash.pool_activate()

	if ship.wood_splinter_scene and ship.VfxBudget.allow_spawn(ship.get_tree(), "ship_collision_splinter", impact_pos, 4, 85.0):
		var splinter = ship.ScenePool.acquire(ship.get_tree(), ship.wood_splinter_scene)
		ship.get_tree().root.add_child(splinter)
		splinter.position = impact_pos + Vector3(0.0, 0.6, 0.0)
		splinter.rotation.y = randf() * TAU
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(maxf(impact_speed * 4.0, 12.0))
		if splinter.has_method("pool_activate"):
			splinter.pool_activate()
