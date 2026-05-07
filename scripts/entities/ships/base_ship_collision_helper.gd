extends RefCounted
class_name BaseShipCollisionHelper

const WoodSplinter = preload("res://scripts/effects/wood_splinter.gd")
const COLLISION_REPULSION_CACHE_FRAME_META := "collision_repulsion_cache_frame"
const COLLISION_REPULSION_CACHE_FORCE_META := "collision_repulsion_cache_force"
const COLLISION_REPULSION_CACHE_SHIP_COUNT_META := "collision_repulsion_cache_ship_count"
const COLLISION_REPULSION_CACHE_MIN_SHIP_COUNT := 8
const COLLISION_REPULSION_CACHE_FRAME_WINDOW := 2
const DERELICT_FIRE_POT_APPROACH_PADDING: float = 5.5

static func get_ship_mass_scale(ship: Node) -> float:
	if not is_instance_valid(ship):
		return 1.0
	var explicit_mass: Variant = ship.get("ship_mass_scale")
	if explicit_mass != null:
		return clampf(float(explicit_mass), 0.35, 4.0)
	if ship is Node3D:
		var half := ShipContactGeometry.get_soft_collision_half_extents(ship as Node3D)
		return clampf((half.x * half.y) / 18.0, 0.55, 2.8)
	return 1.0


static func get_collision_movement_share(ship: Node, other_ship: Node) -> float:
	var my_mass := get_ship_mass_scale(ship)
	var other_mass := get_ship_mass_scale(other_ship)
	var my_resistance := my_mass * my_mass
	var other_resistance := other_mass * other_mass
	return clampf(other_resistance / maxf(my_resistance + other_resistance, 0.001), 0.06, 0.94)


static func get_guard_correction_share(ship: Node, other_ship: Node, correction_length: float = 0.0) -> float:
	var share := clampf(get_collision_movement_share(ship, other_ship), 0.12, 0.86)
	if correction_length > 1.2:
		share = maxf(share, 0.42)
	return share


static func calculate_collision_repulsion(ship) -> Vector3:
	if ship.get_meta("derelict_nonblocking", false) == true:
		return Vector3.ZERO

	var neighbors = EntityRegistry.get_ships()
	var current_frame: int = Engine.get_physics_frames()
	var ship_count: int = neighbors.size()
	var skip_cache: bool = false
	if ship_count < COLLISION_REPULSION_CACHE_MIN_SHIP_COUNT:
		skip_cache = true
	elif ship.has_method("is_player_controlled_ship") and ship.call("is_player_controlled_ship") == true:
		skip_cache = true
	elif ship.get("is_boarding") == true:
		skip_cache = true
	elif ship.has_method("get_boarding_target_ship"):
		var boarding_target: Variant = ship.call("get_boarding_target_ship")
		if is_instance_valid(boarding_target):
			skip_cache = true
	if not skip_cache and ship.has_meta(COLLISION_REPULSION_CACHE_FRAME_META):
		var cached_frame: int = int(ship.get_meta(COLLISION_REPULSION_CACHE_FRAME_META, -1000))
		var cached_ship_count: int = int(ship.get_meta(COLLISION_REPULSION_CACHE_SHIP_COUNT_META, 0))
		if current_frame - cached_frame < COLLISION_REPULSION_CACHE_FRAME_WINDOW \
			and abs(cached_ship_count - ship_count) <= 1 \
			and ship.has_meta(COLLISION_REPULSION_CACHE_FORCE_META):
			var cached_force: Variant = ship.get_meta(COLLISION_REPULSION_CACHE_FORCE_META, Vector3.ZERO)
			return cached_force if cached_force is Vector3 else Vector3.ZERO

	var force = Vector3.ZERO

	for other in neighbors:
		if other == ship or not is_instance_valid(other) or (other.has_method("is_sinking_or_dying") and other.is_sinking_or_dying()):
			continue

		var diff = other.global_position - ship.global_position
		diff.y = 0.0
		var dist_sq = diff.length_squared()
		var my_half = ship.get_collision_half_extents()
		var other_base_radius: float = NodeContractHelper.get_base_collision_radius_value(other)
		var other_width_mult: float = NodeContractHelper.get_collision_width_multiplier_value(other)
		var other_length_mult: float = NodeContractHelper.get_collision_length_multiplier_value(other)
		var other_half = Vector2(
			other_base_radius * other_width_mult,
			other_base_radius * other_length_mult
		)
		var derelict_approach_padding := 0.0
		if NodeContractHelper.get_team_tag(ship) == "player" and NodeContractHelper.get_team_tag(other) == "enemy" and _is_derelict_ship(other):
			derelict_approach_padding = DERELICT_FIRE_POT_APPROACH_PADDING
		var broad_phase_dist = maxf(my_half.x, my_half.y) + maxf(other_half.x, other_half.y) + ship.broad_phase_padding + derelict_approach_padding

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
			other_radius = other_base_radius * other_width_mult + (other_base_radius * other_length_mult - other_base_radius * other_width_mult) * absf(other_fwd.dot(-dir))
		var coll_dist = my_radius + other_radius
		var is_engagement_pair = ship._is_engagement_pair(other)
		var is_player_support_pair = _is_player_support_pair(ship, other)
		if is_engagement_pair:
			coll_dist *= 0.90
		elif is_player_support_pair:
			coll_dist *= 0.92

		if _try_salvage_derelict_contact(ship, other, dist, coll_dist):
			continue
		if other.get_meta("derelict_nonblocking", false) == true:
			continue

		if dist < coll_dist:
			var compression = coll_dist - dist
			var movement_share := get_collision_movement_share(ship, other)
			var my_mass := get_ship_mass_scale(ship)
			var other_mass := get_ship_mass_scale(other)
			var heavy_impact_scale := clampf(1.0 + (other_mass - my_mass) * 0.18, 0.6, 1.45)
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
			elif is_player_support_pair:
				repulsion_strength *= 0.42
			elif high_speed_head_on:
				repulsion_strength *= 0.12
			var penetration_ratio = compression / maxf(coll_dist, 0.001)
			if penetration_ratio > 0.22:
				if is_player_support_pair:
					repulsion_strength = maxf(repulsion_strength, 18.0)
				elif high_speed_head_on:
					repulsion_strength = maxf(repulsion_strength, 26.0)
				else:
					repulsion_strength = maxf(repulsion_strength, 72.0)
			var repulsion_force = -dir * (compression * repulsion_strength * movement_share)
			if is_player_support_pair:
				var my_right = my_fwd.cross(Vector3.UP)
				my_right.y = 0.0
				if my_right.length_squared() <= 0.0001:
					my_right = Vector3(dir.z, 0.0, -dir.x)
				my_right = my_right.normalized()
				var side_sign = signf(diff.dot(my_right))
				if absf(side_sign) < 0.5:
					side_sign = 1.0 if ship.get_instance_id() < other.get_instance_id() else -1.0
				var lateral_escape = my_right * side_sign * compression * 12.0 * movement_share
				repulsion_force = (repulsion_force * 0.35) + lateral_escape
			elif is_engagement_pair and head_on_pair:
				var my_right = my_fwd.cross(Vector3.UP)
				my_right.y = 0.0
				if my_right.length_squared() <= 0.0001:
					my_right = Vector3(dir.z, 0.0, -dir.x)
				my_right = my_right.normalized()
				var side_sign = signf(diff.dot(my_right))
				if absf(side_sign) < 0.5:
					side_sign = 1.0 if ship.get_instance_id() < other.get_instance_id() else -1.0
				var lateral_strength := 14.0 if high_speed_head_on else 10.0
				if penetration_ratio > 0.12:
					lateral_strength += 8.0
				repulsion_force += my_right * side_sign * compression * lateral_strength * movement_share
			if (is_engagement_pair and head_on_pair) or high_speed_head_on:
				var backward_component = minf(0.0, repulsion_force.dot(my_fwd))
				if backward_component < 0.0:
					repulsion_force -= my_fwd * backward_component
			_draw_ship_collision_debug(ship, other, dir, my_radius, other_radius, dist, coll_dist, compression, repulsion_force, is_player_support_pair, high_speed_head_on)
			force += repulsion_force

			if ship.current_speed > 0.5 and not is_player_support_pair:
				var forward_alignment = absf(my_fwd.dot(dir))
				var forward_into_contact = maxf(0.0, my_fwd.dot(dir))
				if other_mass > my_mass and forward_into_contact > 0.35:
					var mass_brake := clampf((other_mass / maxf(my_mass, 0.001) - 1.0) * 0.18 * forward_into_contact, 0.0, 0.5)
					ship.current_speed *= 1.0 - mass_brake
				if forward_alignment < 0.76 and penetration_ratio > 0.05:
					var slide_brake := lerpf(0.04, 0.16, clampf((penetration_ratio - 0.05) / 0.25, 0.0, 1.0))
					slide_brake *= heavy_impact_scale
					if is_engagement_pair:
						slide_brake *= 0.7
					elif high_speed_head_on:
						slide_brake *= 0.5
					ship.current_speed *= maxf(0.78, 1.0 - slide_brake)
				if my_fwd.dot(dir) > 0.8:
					if high_speed_head_on:
						ship.current_speed = lerp(ship.current_speed, 0.0, clampf(0.72 * heavy_impact_scale, 0.32, 0.9))
					elif is_engagement_pair:
						var stop_blend = 0.48 if head_on_pair else 0.24
						stop_blend *= heavy_impact_scale
						ship.current_speed = lerp(ship.current_speed, 0.0, stop_blend)
					else:
						ship.current_speed = lerp(ship.current_speed, 0.0, clampf(0.1 * heavy_impact_scale, 0.04, 0.18))

			if approach_speed >= ship.min_ramming_speed and not is_player_support_pair:
				ship.apply_ramming_damage(other, approach_speed)

	ship.set_meta(COLLISION_REPULSION_CACHE_FRAME_META, current_frame)
	ship.set_meta(COLLISION_REPULSION_CACHE_SHIP_COUNT_META, ship_count)
	ship.set_meta(COLLISION_REPULSION_CACHE_FORCE_META, force)
	return force


static func _draw_ship_collision_debug(
	ship,
	other_ship: Node3D,
	dir: Vector3,
	my_radius: float,
	other_radius: float,
	dist: float,
	coll_dist: float,
	compression: float,
	repulsion_force: Vector3,
	is_player_support_pair: bool,
	high_speed_head_on: bool
) -> void:
	if not DebugDrawBridge.collision_debug_enabled or not DebugDrawBridge.can_draw():
		return
	if not (ship is Node3D) or not is_instance_valid(other_ship):
		return
	var ship_3d := ship as Node3D
	var my_contact := ship_3d.global_position + dir * my_radius
	var other_contact := other_ship.global_position - dir * other_radius
	var contact_pos := (my_contact + other_contact) * 0.5
	contact_pos.y = maxf(ship_3d.global_position.y, other_ship.global_position.y) + 0.25
	var color := Color(1.0, 0.2, 0.08, 0.98)
	if is_player_support_pair:
		color = Color(0.35, 0.95, 1.0, 0.95)
	elif high_speed_head_on:
		color = Color(1.0, 0.08, 0.02, 1.0)
	DebugDrawBridge.draw_line_raised(ship_3d.global_position, other_ship.global_position, 1.1, color, 0.08, 0.042)
	DebugDrawBridge.draw_marker(
		contact_pos,
		color,
		"contact %.2fm" % compression,
		0.12,
		0.26,
		0.95
	)
	if repulsion_force.length_squared() > 0.001:
		var force_len := clampf(repulsion_force.length() * 0.025, 0.55, 4.0)
		DebugDrawBridge.draw_arrow(
			contact_pos + Vector3.UP * 1.25,
			contact_pos + Vector3.UP * 1.25 + repulsion_force.normalized() * force_len,
			color,
			0.12,
			0.45,
			0.04
		)


static func _try_salvage_derelict_contact(ship, other: Node3D, dist: float, coll_dist: float) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return false
	if not NodeContractHelper.is_player_controlled_ship(ship):
		return false
	if NodeContractHelper.get_team_tag(ship) != "player":
		return false
	if NodeContractHelper.get_team_tag(other) != "enemy":
		return false
	if dist >= coll_dist + DERELICT_FIRE_POT_APPROACH_PADDING:
		return false
	if ship.has_method("is_sinking_or_dying") and ship.is_sinking_or_dying():
		return false
	if NodeContractHelper.is_sinking_or_dying(other):
		return false
	if not _is_derelict_ship(other):
		return false
	if other.get_meta("derelict_contact_disposal_started", false) == true or other.get_meta("derelict_contact_salvaged", false) == true:
		return false
	if _has_unresolved_affiliated_boarders(other):
		other.set_meta("derelict_contact_waiting_for_boarder_cleanup", true)
		return false

	if other.has_meta("derelict_contact_waiting_for_boarder_cleanup"):
		other.remove_meta("derelict_contact_waiting_for_boarder_cleanup")
	other.set_meta("derelict_contact_disposal_started", true)
	other.set_meta("derelict_contact_salvaged", true)
	other.set_meta("derelict_nonblocking", true)
	if "monitoring" in other:
		other.set_deferred("monitoring", false)
	if "monitorable" in other:
		other.set_deferred("monitorable", false)
	if other.has_method("_set_contact_areas_enabled"):
		other.call("_set_contact_areas_enabled", false)

	if other.has_method("_ignite_derelict_from_contact"):
		other.call_deferred("_ignite_derelict_from_contact", ship)
	elif other.has_method("_sink_derelict"):
		other.call_deferred("_sink_derelict")
	return true


static func _is_derelict_ship(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_derelict_ship"):
		return node.is_derelict_ship()
	if "is_derelict" in node:
		return node.get("is_derelict") == true
	return false


static func _has_unresolved_affiliated_boarders(derelict_ship: Node) -> bool:
	if not is_instance_valid(derelict_ship):
		return false
	var ship_team: String = NodeContractHelper.get_team_tag(derelict_ship, "")
	for soldier in EntityRegistry.get_soldiers():
		if not is_instance_valid(soldier) or soldier.is_queued_for_deletion():
			continue
		var home_ship_variant: Variant = soldier.get("home_ship")
		if home_ship_variant != derelict_ship:
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if not ship_team.is_empty() and soldier_team != ship_team:
			continue
		var owned_ship_variant: Variant = soldier.get("owned_ship")
		if owned_ship_variant == derelict_ship:
			continue
		return true
	return false


static func _is_player_support_pair(ship, other_ship: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return false
	if (ship.has_method("is_player_team") and not ship.is_player_team()) or (other_ship.has_method("is_player_team") and not other_ship.is_player_team()):
		return false
	var ship_is_support: bool = ShipAllyRoleHelper.is_support_ship(ship)
	var other_is_support: bool = ShipAllyRoleHelper.is_support_ship(other_ship)
	var ship_is_player: bool = ShipAllyRoleHelper.is_player_flagship(ship)
	var other_is_player: bool = ShipAllyRoleHelper.is_player_flagship(other_ship)
	return (ship_is_support and other_is_player) or (other_is_support and ship_is_player)


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

	# 이펙트 중복 생성 방지: 두 배가 동시에 충돌을 감지하므로 instance_id가 낮은 쪽에서만 이펙트 생성
	if ship.get_instance_id() < other.get_instance_id():
		spawn_ship_collision_effects(ship, impact_pos, impact_speed)
	ship.apply_ramming_aoe(clamp(impact_speed * 1.5, 5.0, 20.0), impact_pos)

	if ship.DEBUG_COMBAT_LOGS:
		print("[Ramming] 충각 발생! (속도: %.1f) - 내 각도계수: %.2f -> 입은 피해: %.1f" % [impact_speed, angle_mult, final_ram_damage])
	ship.take_damage(final_ram_damage, (ship.global_position + other.global_position) * 0.5, "ramming")


static func spawn_ship_collision_effects(ship, impact_pos: Vector3, impact_speed: float) -> void:
	if not ship.is_inside_tree():
		return

	# 우드 스플린터 (파편) - 충격 시 수면 효과 대신 나무 파편이 튀도록 함
	if ship.wood_splinter_scene:
		var pseudo_damage := impact_speed * 2.8
		WoodSplinter.spawn_burst(
			ship.get_tree(),
			ship.wood_splinter_scene,
			impact_pos + Vector3(0, 0.4, 0),
			pseudo_damage,
			impact_pos - ship.global_position,
			"ship_collision_splinter",
			4,
			80.0
		)

	# 임팩트 퍼프 (연기/먼지)
	if ship.impact_puff_scene and VfxBudget.allow_spawn(ship.get_tree(), "ship_collision_smoke", impact_pos, 4, 85.0):
		var smoke = ScenePool.acquire(ship.get_tree(), ship.impact_puff_scene)
		ship.get_tree().root.add_child(smoke)
		smoke.position = impact_pos + Vector3(0.0, 0.6, 0.0)
		if smoke.has_method("set_intensity"):
			smoke.set_intensity(clampf(impact_speed / 6.5, 0.9, 1.6))
		if smoke.has_method("pool_activate"):
			smoke.pool_activate()
