extends RefCounted
class_name BaseShipCollisionHelper

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")
const ShipEnemyContactLimitHelper = preload("res://scripts/entities/ships/ship_enemy_contact_limit_helper.gd")

const WoodSplinter = preload("res://scripts/effects/wood_splinter.gd")
const SHIP_COLLISION_WATER_SPLASH_SCENE: PackedScene = preload("res://scenes/effects/water_blast_big.tscn")
const COLLISION_REPULSION_CACHE_FRAME_META := "collision_repulsion_cache_frame"
const COLLISION_REPULSION_CACHE_FORCE_META := "collision_repulsion_cache_force"
const COLLISION_REPULSION_CACHE_SHIP_COUNT_META := "collision_repulsion_cache_ship_count"
const COLLISION_REPULSION_CACHE_MIN_SHIP_COUNT := 8
const COLLISION_REPULSION_CACHE_FRAME_WINDOW := 2
const DERELICT_FIRE_POT_APPROACH_PADDING: float = 5.5
const CONTACT_SFX_LIGHT_COOLDOWN_MSEC := 1300
const CONTACT_SFX_MEDIUM_COOLDOWN_MSEC := 850
const CONTACT_SFX_HEAVY_COOLDOWN_MSEC := 700
const CONTACT_SFX_CACHE_PRUNE_SIZE := 96
const CONTACT_VFX_COOLDOWN_MSEC := 850
const CONTACT_VFX_CACHE_PRUNE_SIZE := 96
const CONTACT_VFX_HEAD_ON_SPEED_RATIO := 0.78
const CONTACT_VFX_GENERAL_SPEED_RATIO := 0.86
const CONTACT_VFX_HOSTILE_SUPPORT_SPEED_RATIO := 0.58
const HULL_FRONT_VFX_ALIGNMENT_DOT := 0.62
const HULL_FRONT_VFX_PAD := 0.22
const HULL_FRONT_VFX_HEIGHT_RATIO := 0.26
const HULL_FRONT_VFX_MIN_HEIGHT := 0.42
const HULL_FRONT_VFX_MAX_HEIGHT := 0.78
const COLLISION_WATER_SPLASH_OUTBOARD_PAD := 0.95
const COLLISION_WATER_SPLASH_FRONT_PAD := 1.35
const PLAYER_CONTACT_VFX_HEIGHT_RATIO := 0.34
const PLAYER_CONTACT_VFX_MIN_HEIGHT := 0.58
const PLAYER_CONTACT_VFX_MAX_HEIGHT := 0.92
const FRONT_TO_SIDE_CONTACT_EDGE_BIAS := 0.38
const RAMMING_KNOCKBACK_MIN_FORWARD_DOT := 0.55
const RAMMING_KNOCKBACK_BASE_SPEED := 3.1
const RAMMING_KNOCKBACK_SPEED_SCALE := 0.78
const RAMMING_KNOCKBACK_MAX_SPEED := 11.0
const RAMMING_DAMAGE_SPEED_SCALE := 4.2
const RAMMING_DAMAGE_SIDE_HIT_MULT := 1.35
const RAMMING_DAMAGE_BOW_HIT_MULT := 0.55
const RAMMING_DAMAGE_ATTACKER_MIN_ALIGNMENT_MULT := 0.75
const RAMMING_DAMAGE_ATTACKER_MAX_ALIGNMENT_MULT := 1.22
const RAMMING_BOOST_ASSIST_PAD := 0.95
const RAMMING_BOOST_ASSIST_FORWARD_DOT := 0.52
const RAMMING_BOOST_ASSIST_MIN_SPEED_RATIO := 0.68
const RAMMING_BOOST_ASSIST_ENABLED := false
const RAMMING_IMPACT_RESISTANCE_ENABLED := false
const RAMMING_BOOST_IMPACT_BRAKE := 0.42
const RAMMING_LETHAL_IMPACT_BRAKE := 0.58
const RAMMING_BOOST_BACK_IMPULSE := 1.15
const RAMMING_BOOST_KNOCKBACK_MULT := 1.0
const RAMMING_LETHAL_VFX_SPEED_MULT := 1.28
const HEAD_ON_ESCAPE_RUDDER_DEADZONE := 5.0
const HEAD_ON_ESCAPE_REVERSE_SPEED := -0.15
const MOVEMENT_GUARD_BROAD_PHASE_SCALE := 1.18
const MOVEMENT_GUARD_BROAD_PHASE_PAD := 1.8
const MOVEMENT_GUARD_DEFAULT_SAFE_RATIO := 0.98
const MOVEMENT_GUARD_ENGAGEMENT_SAFE_RATIO := 0.92
const MOVEMENT_GUARD_SUPPORT_SAFE_RATIO := 0.84
const MOVEMENT_GUARD_MAX_CHECKS := 8
const COLLISION_LOW_SPEED_PRESSURE_MIN := 0.32
const COLLISION_LOW_SPEED_PRESSURE_FULL_RATIO := 0.82
const COLLISION_DEEP_OVERLAP_PRESSURE_MIN := 0.58
const COLLISION_HEAD_ON_BOUNCE_SPEED_SCALE := 0.32
const COLLISION_HEAD_ON_BOUNCE_MIN_SPEED := 1.2
const COLLISION_HEAD_ON_BOUNCE_MAX_SPEED := 4.8
const STRONG_COLLISION_REARM_DISTANCE_RATIO := 1.12

static var _last_contact_sfx_msec_by_pair: Dictionary = {}
static var _last_contact_vfx_msec_by_pair: Dictionary = {}
static var _disarmed_strong_collision_pairs: Dictionary = {}
static var _cached_collision_neighbors: Array = []
static var _cached_collision_neighbors_frame: int = -1

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

	var current_frame: int = Engine.get_physics_frames()
	var neighbors = _get_collision_neighbors_cached(current_frame)
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
	var my_half = ship.get_collision_half_extents()
	var my_team: String = NodeContractHelper.get_team_tag(ship)
	var enemy_enemy_contacts := 0

	for other in neighbors:
		if other == ship or not is_instance_valid(other) or (other.has_method("is_sinking_or_dying") and other.is_sinking_or_dying()):
			continue
		var other_team := NodeContractHelper.get_team_tag(other)
		var is_enemy_enemy_limited := ShipEnemyContactLimitHelper.should_limit(my_team, other_team, ship_count)
		if is_enemy_enemy_limited:
			if enemy_enemy_contacts >= ShipEnemyContactLimitHelper.get_max_collision_contacts():
				continue
			if not ShipEnemyContactLimitHelper.is_timeslice_active(ship, other, current_frame):
				continue

		var diff = other.global_position - ship.global_position
		diff.y = 0.0
		var dist_sq = diff.length_squared()
		var other_base_radius: float = NodeContractHelper.get_base_collision_radius_value(other)
		var other_width_mult: float = NodeContractHelper.get_collision_width_multiplier_value(other)
		var other_length_mult: float = NodeContractHelper.get_collision_length_multiplier_value(other)
		var other_half = Vector2(
			other_base_radius * other_width_mult,
			other_base_radius * other_length_mult
		)
		var derelict_approach_padding := 0.0
		if my_team == "player" and other_team == "enemy" and _is_derelict_ship(other):
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
		var is_hostile_support_contact = _is_hostile_support_contact(ship, other)
		if is_engagement_pair:
			coll_dist *= 0.90
		elif is_player_support_pair:
			coll_dist *= 0.92

		_refresh_strong_collision_rearm(ship, other, dist, coll_dist)
		if _try_salvage_derelict_contact(ship, other, dist, coll_dist):
			continue
		if other.get_meta("derelict_nonblocking", false) == true:
			continue

		_try_assisted_ramming_boost_contact(ship, other, dist, coll_dist)

		if dist < coll_dist:
			if is_enemy_enemy_limited:
				enemy_enemy_contacts += 1
			var strong_collision_armed := _is_strong_collision_armed(ship, other, dist, coll_dist)
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
			var backing_out := _is_backing_out_of_head_on(ship)
			var high_speed_head_on = head_on_pair and approach_speed >= ship.min_ramming_speed * 0.85
			if is_engagement_pair and head_on_pair:
				repulsion_strength *= 0.18
			elif is_player_support_pair:
				repulsion_strength *= 0.42
			elif high_speed_head_on:
				repulsion_strength *= 0.12
			if not strong_collision_armed:
				repulsion_strength *= 0.38
			var penetration_ratio = compression / maxf(coll_dist, 0.001)
			if penetration_ratio > 0.22:
				if is_player_support_pair:
					repulsion_strength = maxf(repulsion_strength, 18.0)
				elif high_speed_head_on:
					repulsion_strength = maxf(repulsion_strength, 26.0 if strong_collision_armed else 12.0)
				else:
					repulsion_strength = maxf(repulsion_strength, 72.0 if strong_collision_armed else 24.0)
			var min_ramming_speed := maxf(float(ship.min_ramming_speed), 0.1)
			var contact_pressure_ratio := clampf(approach_speed / min_ramming_speed, 0.0, 1.25)
			var contact_pressure_scale := lerpf(
				COLLISION_LOW_SPEED_PRESSURE_MIN,
				1.0,
				smoothstep(0.05, COLLISION_LOW_SPEED_PRESSURE_FULL_RATIO, contact_pressure_ratio)
			)
			if penetration_ratio > 0.16:
				var deep_overlap_scale := lerpf(
					COLLISION_LOW_SPEED_PRESSURE_MIN,
					COLLISION_DEEP_OVERLAP_PRESSURE_MIN,
					clampf((penetration_ratio - 0.16) / 0.18, 0.0, 1.0)
				)
				contact_pressure_scale = maxf(contact_pressure_scale, deep_overlap_scale)
			var repulsion_force = -dir * (compression * repulsion_strength * movement_share * contact_pressure_scale)
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
				var side_sign = _get_head_on_escape_side(ship, diff, my_right, other)
				if absf(side_sign) < 0.5:
					side_sign = 1.0 if ship.get_instance_id() < other.get_instance_id() else -1.0
				var lateral_strength := 16.0 if high_speed_head_on else 12.0
				if backing_out:
					lateral_strength *= 1.25
				if penetration_ratio > 0.12:
					lateral_strength += 10.0
				repulsion_force += my_right * side_sign * compression * lateral_strength * movement_share
			_draw_ship_collision_debug(ship, other, dir, my_radius, other_radius, dist, coll_dist, compression, repulsion_force, is_player_support_pair, high_speed_head_on)
			force += repulsion_force
			if strong_collision_armed and approach_speed < ship.min_ramming_speed:
				_play_ship_contact_sfx(ship, other, approach_speed, compression, coll_dist, pre_collision_speed, target_speed, is_player_support_pair, is_hostile_support_contact)
				_spawn_ship_contact_vfx(ship, other, approach_speed, compression, coll_dist, pre_collision_speed, target_speed, head_on_pair, is_player_support_pair, is_hostile_support_contact)
				_disarm_strong_collision_pair(ship, other)
			elif strong_collision_armed and not is_player_support_pair:
				try_spawn_strong_collision_effects(ship, other, approach_speed)

			if ship.current_speed > 0.5 and not is_player_support_pair:
				var forward_alignment = absf(my_fwd.dot(dir))
				var forward_into_contact = maxf(0.0, my_fwd.dot(dir))
				if is_hostile_support_contact and forward_into_contact > 0.25:
					var contact_intensity := _get_contact_vfx_intensity(approach_speed, compression, pre_collision_speed, target_speed, true)
					if contact_intensity >= float(ship.min_ramming_speed) * CONTACT_VFX_HOSTILE_SUPPORT_SPEED_RATIO:
						var contact_brake := clampf(0.24 + penetration_ratio * 1.8, 0.24, 0.62)
						ship.current_speed = lerp(ship.current_speed, 0.0, contact_brake)
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
						if strong_collision_armed:
							var bounce_impulse := clampf(
								approach_speed * COLLISION_HEAD_ON_BOUNCE_SPEED_SCALE * heavy_impact_scale,
								COLLISION_HEAD_ON_BOUNCE_MIN_SPEED,
								COLLISION_HEAD_ON_BOUNCE_MAX_SPEED
							)
							if ship.has_method("apply_collision_impulse"):
								ship.apply_collision_impulse(-my_fwd * bounce_impulse)
							ship.current_speed = lerp(ship.current_speed, ship.current_speed * 0.35, clampf(0.35 * heavy_impact_scale, 0.22, 0.55))
						else:
							ship.current_speed = lerp(ship.current_speed, ship.current_speed * 0.62, clampf(0.18 * heavy_impact_scale, 0.08, 0.28))
					elif is_engagement_pair:
						var stop_blend = 0.28 if head_on_pair else 0.18
						stop_blend *= heavy_impact_scale
						ship.current_speed = lerp(ship.current_speed, 0.0, stop_blend)
					else:
						ship.current_speed = lerp(ship.current_speed, 0.0, clampf(0.1 * heavy_impact_scale, 0.04, 0.18))

			if strong_collision_armed and approach_speed >= ship.min_ramming_speed and not is_player_support_pair:
				ship.apply_ramming_damage(other, approach_speed)
				_disarm_strong_collision_pair(ship, other)

	ship.set_meta(COLLISION_REPULSION_CACHE_FRAME_META, current_frame)
	ship.set_meta(COLLISION_REPULSION_CACHE_SHIP_COUNT_META, ship_count)
	ship.set_meta(COLLISION_REPULSION_CACHE_FORCE_META, force)
	return force


static func _get_collision_neighbors_cached(current_frame: int) -> Array:
	if current_frame != _cached_collision_neighbors_frame:
		_cached_collision_neighbors = EntityRegistry.get_ships()
		_cached_collision_neighbors_frame = current_frame
	return _cached_collision_neighbors


static func apply_movement_collision_guards(ship, prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null, impact_speed_hint: float = 0.0) -> Vector3:
	if not is_instance_valid(ship) or ship.get_meta("derelict_nonblocking", false) == true:
		return proposed_pos
	var corrected_pos := proposed_pos
	var ship_team: String = NodeContractHelper.get_team_tag(ship, "")
	var ship_guard_radius := _get_movement_guard_broad_radius(ship)
	var checked_count := 0
	var enemy_enemy_checked_count := 0
	var current_frame := Engine.get_physics_frames()
	var neighbors := _get_collision_neighbors_cached(current_frame)
	var ship_count := neighbors.size()
	for other_variant in neighbors:
		var other := other_variant as Node3D
		if other == ship or not is_instance_valid(other) or other == excluded_ship:
			continue
		if NodeContractHelper.is_sinking_or_dying(other) or other.get_meta("derelict_nonblocking", false) == true:
			continue
		var other_team: String = NodeContractHelper.get_team_tag(other, "")
		var is_enemy_enemy_limited := ShipEnemyContactLimitHelper.should_limit(ship_team, other_team, ship_count)
		if is_enemy_enemy_limited:
			if enemy_enemy_checked_count >= ShipEnemyContactLimitHelper.get_max_guard_checks():
				continue
			if not ShipEnemyContactLimitHelper.is_timeslice_active(ship, other, current_frame):
				continue
		var offset := corrected_pos - other.global_position
		offset.y = 0.0
		var broad_probe := (ship_guard_radius + _get_movement_guard_broad_radius(other)) * MOVEMENT_GUARD_BROAD_PHASE_SCALE + MOVEMENT_GUARD_BROAD_PHASE_PAD
		if offset.length_squared() > broad_probe * broad_probe:
			continue
		var safe_ratio := _get_movement_guard_safe_ratio(ship, other)
		var safe_probe: float = float(ship.get_collision_distance_to(other)) * maxf(safe_ratio, 1.08)
		if offset.length_squared() > safe_probe * safe_probe:
			continue
		var emit_collision_event := not ship_team.is_empty() and not other_team.is_empty() and ship_team != other_team
		corrected_pos = apply_single_movement_collision_guard(ship, other, prev_pos, corrected_pos, safe_ratio, impact_speed_hint, emit_collision_event)
		checked_count += 1
		if is_enemy_enemy_limited:
			enemy_enemy_checked_count += 1
		if checked_count >= MOVEMENT_GUARD_MAX_CHECKS:
			break
	return corrected_pos


static func apply_single_movement_collision_guard(ship, other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = MOVEMENT_GUARD_DEFAULT_SAFE_RATIO, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	if not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return proposed_pos
	if NodeContractHelper.is_sinking_or_dying(other_ship) or other_ship.get_meta("derelict_nonblocking", false) == true:
		return proposed_pos
	var target_pos := other_ship.global_position
	var safe_dist: float = ship.get_collision_distance_to(other_ship) * safe_ratio
	if safe_dist <= 0.01:
		return proposed_pos

	var from_2d := Vector2(prev_pos.x - target_pos.x, prev_pos.z - target_pos.z)
	var to_2d := Vector2(proposed_pos.x - target_pos.x, proposed_pos.z - target_pos.z)
	var move_2d := to_2d - from_2d
	var a := move_2d.dot(move_2d)
	if a > 0.00001:
		var b := 2.0 * from_2d.dot(move_2d)
		var c := from_2d.dot(from_2d) - safe_dist * safe_dist
		if c > 0.0:
			var disc := b * b - 4.0 * a * c
			if disc >= 0.0:
				var t := (-b - sqrt(disc)) / (2.0 * a)
				if t >= 0.0 and t <= 1.0:
					var hit_t := maxf(0.0, t - 0.02)
					var hit_pos := prev_pos.lerp(proposed_pos, hit_t)
					var correction := _get_movement_guard_correction(ship, other_ship, hit_pos, safe_dist)
					hit_pos += correction * get_guard_correction_share(ship, other_ship, correction.length())
					_emit_movement_guarded_collision(ship, other_ship, impact_speed_hint, emit_collision_event)
					return hit_pos

	var diff := proposed_pos - target_pos
	diff.y = 0.0
	var dist := diff.length()
	if dist < safe_dist:
		var correction := _get_movement_guard_correction(ship, other_ship, proposed_pos, safe_dist)
		proposed_pos += correction * get_guard_correction_share(ship, other_ship, correction.length())
		_emit_movement_guarded_collision(ship, other_ship, impact_speed_hint, emit_collision_event)
	return proposed_pos


static func _get_movement_guard_correction(ship, other_ship: Node3D, pos: Vector3, safe_dist: float) -> Vector3:
	var diff := pos - other_ship.global_position
	diff.y = 0.0
	var normal := diff.normalized() if diff.length_squared() > 0.0001 else _get_collision_guard_forward_flat(ship)
	var target_pos := pos
	target_pos.x = other_ship.global_position.x + normal.x * safe_dist
	target_pos.z = other_ship.global_position.z + normal.z * safe_dist
	return target_pos - pos


static func _emit_movement_guarded_collision(ship, other_ship: Node3D, impact_speed_hint: float, emit_collision_event: bool) -> void:
	if not emit_collision_event or not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return
	var coll_dist: float = ship.get_collision_distance_to(other_ship)
	var diff_to_other: Vector3 = ship.global_position - other_ship.global_position
	diff_to_other.y = 0.0
	var dist := diff_to_other.length()
	_refresh_strong_collision_rearm(ship, other_ship, dist, coll_dist)
	if not _is_strong_collision_armed(ship, other_ship, dist, coll_dist):
		return
	var min_ramming_speed := 4.0
	if ship.get("min_ramming_speed") != null:
		min_ramming_speed = float(ship.get("min_ramming_speed")) * 0.72
	var impact_speed := maxf(impact_speed_hint, min_ramming_speed)
	try_spawn_strong_collision_effects(ship, other_ship, impact_speed)
	if not is_instance_valid(ship._cached_audio_manager):
		ship._cached_audio_manager = ship.get_node_or_null("/root/AudioManager")
	var audio_manager = ship._cached_audio_manager
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx") and _can_play_contact_sfx(ship, other_ship, CONTACT_SFX_MEDIUM_COOLDOWN_MSEC):
		var impact_pos: Vector3 = (ship.global_position + other_ship.global_position) * 0.5
		impact_pos.y = maxf(ship.global_position.y, other_ship.global_position.y) + 0.35
		audio_manager.play_sfx("ship_collision", impact_pos, randf_range(0.86, 0.98), -2.0)
	if ship.has_method("apply_ramming_damage"):
		ship.call("apply_ramming_damage", other_ship, impact_speed)
	if other_ship.has_method("apply_ramming_damage"):
		other_ship.call("apply_ramming_damage", ship, impact_speed)
	if ship.has_method("apply_collision_impulse"):
		var bounce_dir: Vector3 = ship.global_position - other_ship.global_position
		bounce_dir.y = 0.0
		if bounce_dir.length_squared() > 0.0001:
			var bounce_impulse := clampf(
				impact_speed * COLLISION_HEAD_ON_BOUNCE_SPEED_SCALE,
				COLLISION_HEAD_ON_BOUNCE_MIN_SPEED,
				COLLISION_HEAD_ON_BOUNCE_MAX_SPEED
			)
			ship.call("apply_collision_impulse", bounce_dir.normalized() * bounce_impulse)
	_disarm_strong_collision_pair(ship, other_ship)
	if ship.get("current_speed") != null:
		var mass_ratio := get_ship_mass_scale(other_ship) / maxf(get_ship_mass_scale(ship), 0.1)
		var max_speed_after_contact := 0.0
		if ship.get("max_speed") != null:
			max_speed_after_contact = maxf(0.0, float(ship.get("max_speed")) * clampf(0.36 + (1.0 / maxf(mass_ratio, 0.25)) * 0.18, 0.38, 0.72))
		ship.set("current_speed", minf(float(ship.get("current_speed")), max_speed_after_contact))


static func _get_movement_guard_safe_ratio(ship, other_ship: Node3D) -> float:
	if _is_player_support_pair(ship, other_ship):
		return MOVEMENT_GUARD_SUPPORT_SAFE_RATIO
	if is_instance_valid(ship) and ship.has_method("_is_engagement_pair") and ship.call("_is_engagement_pair", other_ship):
		return MOVEMENT_GUARD_ENGAGEMENT_SAFE_RATIO
	return MOVEMENT_GUARD_DEFAULT_SAFE_RATIO


static func _get_movement_guard_broad_radius(ship: Node) -> float:
	if ship is Node3D:
		var half := ShipContactGeometry.get_soft_collision_half_extents(ship as Node3D)
		return maxf(0.5, maxf(half.x, half.y))
	var base_radius := NodeContractHelper.get_base_collision_radius_value(ship)
	var width_mult := NodeContractHelper.get_collision_width_multiplier_value(ship)
	var length_mult := NodeContractHelper.get_collision_length_multiplier_value(ship)
	return maxf(0.5, base_radius * maxf(width_mult, length_mult))


static func _get_collision_guard_forward_flat(ship: Node) -> Vector3:
	if ship is Node3D:
		var fwd := -(ship as Node3D).global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.0001:
			return fwd.normalized()
	return Vector3.FORWARD

static func _is_backing_out_of_head_on(ship) -> bool:
	if not is_instance_valid(ship):
		return false
	var speed_value: Variant = ship.get("current_speed")
	if speed_value != null and float(speed_value) <= HEAD_ON_ESCAPE_REVERSE_SPEED:
		return true
	var rowing_value: Variant = ship.get("is_rowing")
	var rowing_direction_value: Variant = ship.get("rowing_direction")
	return rowing_value == true and rowing_direction_value != null and int(rowing_direction_value) < 0


static func _get_head_on_escape_side(ship, diff: Vector3, my_right: Vector3, other: Node) -> float:
	var rudder_value: Variant = ship.get("rudder_angle")
	if rudder_value != null and absf(float(rudder_value)) >= HEAD_ON_ESCAPE_RUDDER_DEADZONE:
		return signf(float(rudder_value))
	var side_sign := signf(diff.dot(my_right))
	if absf(side_sign) >= 0.5:
		return side_sign
	return 1.0 if ship.get_instance_id() < other.get_instance_id() else -1.0


static func _spawn_ship_contact_vfx(
	ship,
	other: Node3D,
	approach_speed: float,
	compression: float,
	coll_dist: float,
	pre_collision_speed: float,
	target_speed: float,
	head_on_pair: bool,
	is_player_support_pair: bool,
	is_hostile_support_contact: bool = false
) -> void:
	if is_player_support_pair:
		return
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return
	var contact_intensity := _get_contact_vfx_intensity(approach_speed, compression, pre_collision_speed, target_speed, is_hostile_support_contact)
	var strong_threshold := _get_contact_vfx_threshold(ship, head_on_pair, is_hostile_support_contact)
	if contact_intensity < strong_threshold:
		return
	var threshold_ratio := CONTACT_VFX_HOSTILE_SUPPORT_SPEED_RATIO if is_hostile_support_contact else CONTACT_VFX_HEAD_ON_SPEED_RATIO
	try_spawn_strong_collision_effects(ship, other, maxf(contact_intensity, strong_threshold), threshold_ratio)


static func _get_contact_vfx_intensity(approach_speed: float, compression: float, pre_collision_speed: float, target_speed: float, is_hostile_support_contact: bool = false) -> float:
	var moving_scale := 1.0 if is_hostile_support_contact else 0.55
	var compression_scale := 2.35 if is_hostile_support_contact else 2.1
	var moving_intensity := maxf(absf(pre_collision_speed), absf(target_speed)) * moving_scale
	return maxf(maxf(approach_speed, moving_intensity), compression * compression_scale)


static func _get_contact_vfx_threshold(ship, head_on_pair: bool, is_hostile_support_contact: bool = false) -> float:
	var speed_ratio := CONTACT_VFX_HEAD_ON_SPEED_RATIO if head_on_pair else CONTACT_VFX_GENERAL_SPEED_RATIO
	if is_hostile_support_contact:
		speed_ratio = CONTACT_VFX_HOSTILE_SUPPORT_SPEED_RATIO
	return float(ship.min_ramming_speed) * speed_ratio


static func try_spawn_strong_collision_effects(ship, other: Node3D, impact_speed: float, min_speed_ratio: float = CONTACT_VFX_HEAD_ON_SPEED_RATIO) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return
	if not ship.is_inside_tree():
		return
	if impact_speed < float(ship.min_ramming_speed) * min_speed_ratio:
		return
	if not _can_play_contact_vfx(ship, other):
		return
	spawn_ship_collision_effects(ship, _get_ship_contact_point(ship, other), maxf(impact_speed, float(ship.min_ramming_speed)))


static func _get_ship_contact_point(ship, other: Node3D) -> Vector3:
	var diff: Vector3 = other.global_position - ship.global_position
	diff.y = 0.0
	if diff.length_squared() <= 0.0001:
		var ship_fwd: Vector3 = -ship.global_transform.basis.z
		ship_fwd.y = 0.0
		diff = ship_fwd if ship_fwd.length_squared() > 0.0001 else Vector3.FORWARD
	var dir := diff.normalized()
	var ship_radius := _get_visual_contact_radius(ship, dir, float(ship.call("get_directional_collision_radius", dir)) if ship.has_method("get_directional_collision_radius") else ShipContactGeometry.get_directional_collision_radius(ship, dir))
	var other_radius := _get_visual_contact_radius(other, -dir, float(other.call("get_directional_collision_radius", -dir)) if other.has_method("get_directional_collision_radius") else ShipContactGeometry.get_directional_collision_radius(other, -dir))
	var ship_edge: Vector3 = ship.global_position + dir * ship_radius
	var other_edge: Vector3 = other.global_position - dir * other_radius
	var impact_pos: Vector3 = (ship_edge + other_edge) * 0.5
	var ship_front_contact := _is_authored_hull_front_contact(ship, dir)
	var other_front_contact := _is_authored_hull_front_contact(other, -dir)
	if ship_front_contact != other_front_contact:
		var edge_bias := 1.0 - FRONT_TO_SIDE_CONTACT_EDGE_BIAS if ship_front_contact else FRONT_TO_SIDE_CONTACT_EDGE_BIAS
		impact_pos = ship_edge.lerp(other_edge, edge_bias)
	if impact_pos.distance_squared_to((ship.global_position + other.global_position) * 0.5) < 0.04:
		impact_pos = ship.global_position.lerp(other.global_position, ship_radius / maxf(ship_radius + other_radius, 0.001))
	impact_pos.y = maxf(ship.global_position.y, other.global_position.y) + _get_visual_contact_height(ship, other, dir)
	return impact_pos


static func _get_visual_contact_radius(ship: Node3D, world_dir: Vector3, fallback_radius: float) -> float:
	if not _is_authored_hull_front_contact(ship, world_dir):
		return fallback_radius
	var deck_half := _get_visual_hull_half_extents(ship)
	if deck_half.y <= 0.01:
		return fallback_radius
	return minf(fallback_radius, deck_half.y + HULL_FRONT_VFX_PAD)


static func _get_visual_contact_height(ship: Node3D, other: Node3D, dir: Vector3) -> float:
	var height := 0.12
	if _is_authored_hull_front_contact(ship, dir):
		height = maxf(height, _get_authored_hull_front_contact_height(ship))
	if _is_authored_hull_front_contact(other, -dir):
		height = maxf(height, _get_authored_hull_front_contact_height(other))
	if _is_player_team_ship(ship):
		height = maxf(height, _get_player_contact_height(ship))
	if _is_player_team_ship(other):
		height = maxf(height, _get_player_contact_height(other))
	return height


static func _get_player_contact_height(ship: Node3D) -> float:
	var deck_height_value: Variant = ship.get("deck_height")
	if deck_height_value == null:
		return PLAYER_CONTACT_VFX_MIN_HEIGHT
	return clampf(float(deck_height_value) * PLAYER_CONTACT_VFX_HEIGHT_RATIO, PLAYER_CONTACT_VFX_MIN_HEIGHT, PLAYER_CONTACT_VFX_MAX_HEIGHT)


static func _get_authored_hull_front_contact_height(ship: Node3D) -> float:
	var deck_height_value: Variant = ship.get("deck_height")
	if deck_height_value == null:
		return HULL_FRONT_VFX_MIN_HEIGHT
	return clampf(float(deck_height_value) * HULL_FRONT_VFX_HEIGHT_RATIO, HULL_FRONT_VFX_MIN_HEIGHT, HULL_FRONT_VFX_MAX_HEIGHT)


static func _is_authored_hull_front_contact(ship: Node3D, world_dir: Vector3) -> bool:
	if not is_instance_valid(ship):
		return false
	if not _has_visual_hull_front_bounds(ship):
		return false
	var dir := world_dir
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		return false
	dir = dir.normalized()
	var fwd: Vector3 = -ship.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() <= 0.0001:
		return false
	return fwd.normalized().dot(dir) >= HULL_FRONT_VFX_ALIGNMENT_DOT


static func _has_visual_hull_front_bounds(ship: Node3D) -> bool:
	if not is_instance_valid(ship) or not ship.has_method("get_deck_half_extents"):
		return false
	var deck_half: Variant = ship.call("get_deck_half_extents")
	return deck_half is Vector2 and (deck_half as Vector2).y > 0.01


static func _is_player_team_ship(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	return NodeContractHelper.get_team_tag(ship, "") == "player"


static func _get_visual_hull_half_extents(ship: Node3D) -> Vector2:
	if is_instance_valid(ship) and ship.has_method("get_deck_half_extents"):
		var deck_half: Variant = ship.call("get_deck_half_extents")
		if deck_half is Vector2:
			return deck_half as Vector2
	return ShipContactGeometry.get_soft_collision_half_extents(ship)


static func _can_play_contact_vfx(ship: Node, other: Node) -> bool:
	var pair_key := _get_contact_sfx_pair_key(ship, other)
	var now_msec := Time.get_ticks_msec()
	var last_msec := int(_last_contact_vfx_msec_by_pair.get(pair_key, -1000000))
	if now_msec - last_msec < CONTACT_VFX_COOLDOWN_MSEC:
		return false
	_last_contact_vfx_msec_by_pair[pair_key] = now_msec
	if _last_contact_vfx_msec_by_pair.size() > CONTACT_VFX_CACHE_PRUNE_SIZE:
		_prune_contact_vfx_cache(now_msec)
	return true


static func _prune_contact_vfx_cache(now_msec: int) -> void:
	for key in _last_contact_vfx_msec_by_pair.keys():
		if now_msec - int(_last_contact_vfx_msec_by_pair.get(key, 0)) > 5000:
			_last_contact_vfx_msec_by_pair.erase(key)


static func _play_ship_contact_sfx(
	ship,
	other: Node3D,
	approach_speed: float,
	compression: float,
	coll_dist: float,
	pre_collision_speed: float,
	target_speed: float,
	is_player_support_pair: bool,
	is_hostile_support_contact: bool = false
) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return
	if not is_instance_valid(ship._cached_audio_manager):
		ship._cached_audio_manager = ship.get_node_or_null("/root/AudioManager")
	if not is_instance_valid(ship._cached_audio_manager) or not ship._cached_audio_manager.has_method("play_sfx"):
		return
	var penetration_ratio := compression / maxf(coll_dist, 0.001)
	var moving_scale := 0.95 if is_hostile_support_contact else (0.32 if is_player_support_pair else 0.45)
	var compression_scale := 2.35 if is_hostile_support_contact else 2.0
	var moving_intensity := maxf(absf(pre_collision_speed), absf(target_speed)) * moving_scale
	var contact_intensity := maxf(maxf(approach_speed, moving_intensity), compression * compression_scale)
	if contact_intensity < 0.28 and penetration_ratio < 0.018:
		return

	var sfx_key := "mast_creak"
	var pitch_min := 0.82
	var pitch_max := 1.05
	var volume_db := -5.5
	var cooldown_msec := CONTACT_SFX_LIGHT_COOLDOWN_MSEC
	if contact_intensity >= 3.0 or penetration_ratio >= 0.11:
		sfx_key = "ship_collision"
		pitch_min = 0.78
		pitch_max = 0.94
		volume_db = -0.5
		cooldown_msec = CONTACT_SFX_HEAVY_COOLDOWN_MSEC
	elif contact_intensity >= 1.35 or penetration_ratio >= 0.055:
		sfx_key = "ship_collision"
		pitch_min = 0.9
		pitch_max = 1.04
		volume_db = -4.0
		cooldown_msec = CONTACT_SFX_MEDIUM_COOLDOWN_MSEC

	if not _can_play_contact_sfx(ship, other, cooldown_msec):
		return
	var impact_pos: Vector3 = (ship.global_position + other.global_position) * 0.5
	impact_pos.y = maxf(ship.global_position.y, other.global_position.y) + 0.35
	ship._cached_audio_manager.play_sfx(sfx_key, impact_pos, randf_range(pitch_min, pitch_max), volume_db)


static func _can_play_contact_sfx(ship: Node, other: Node, cooldown_msec: int) -> bool:
	var pair_key := _get_contact_sfx_pair_key(ship, other)
	var now_msec := Time.get_ticks_msec()
	var last_msec := int(_last_contact_sfx_msec_by_pair.get(pair_key, -1000000))
	if now_msec - last_msec < cooldown_msec:
		return false
	_last_contact_sfx_msec_by_pair[pair_key] = now_msec
	if _last_contact_sfx_msec_by_pair.size() > CONTACT_SFX_CACHE_PRUNE_SIZE:
		_prune_contact_sfx_cache(now_msec)
	return true


static func _refresh_strong_collision_rearm(ship: Node, other: Node, dist: float, coll_dist: float) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return
	var rearm_dist := maxf(coll_dist * STRONG_COLLISION_REARM_DISTANCE_RATIO, coll_dist)
	if dist >= rearm_dist:
		_disarmed_strong_collision_pairs.erase(_get_contact_sfx_pair_key(ship, other))


static func _is_strong_collision_armed(ship: Node, other: Node, dist: float, coll_dist: float) -> bool:
	_refresh_strong_collision_rearm(ship, other, dist, coll_dist)
	return not _disarmed_strong_collision_pairs.has(_get_contact_sfx_pair_key(ship, other))


static func _disarm_strong_collision_pair(ship: Node, other: Node) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return
	_disarmed_strong_collision_pairs[_get_contact_sfx_pair_key(ship, other)] = Time.get_ticks_msec()
	if _disarmed_strong_collision_pairs.size() > CONTACT_SFX_CACHE_PRUNE_SIZE:
		_prune_strong_collision_pair_cache()


static func _prune_strong_collision_pair_cache() -> void:
	var now_msec := Time.get_ticks_msec()
	for key in _disarmed_strong_collision_pairs.keys():
		if now_msec - int(_disarmed_strong_collision_pairs.get(key, 0)) > 8000:
			_disarmed_strong_collision_pairs.erase(key)


static func _get_contact_sfx_pair_key(ship: Node, other: Node) -> String:
	var a := ship.get_instance_id()
	var b := other.get_instance_id()
	if a > b:
		var tmp := a
		a = b
		b = tmp
	return "%d:%d" % [a, b]


static func _prune_contact_sfx_cache(now_msec: int) -> void:
	for key in _last_contact_sfx_msec_by_pair.keys():
		if now_msec - int(_last_contact_sfx_msec_by_pair.get(key, 0)) > 5000:
			_last_contact_sfx_msec_by_pair.erase(key)


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
	if _has_active_deck_melee(ship):
		other.set_meta("derelict_contact_waiting_for_deck_melee", true)
		return false
	if _has_unresolved_affiliated_boarders(other):
		other.set_meta("derelict_contact_waiting_for_boarder_cleanup", true)
		return false

	if other.has_meta("derelict_contact_waiting_for_deck_melee"):
		other.remove_meta("derelict_contact_waiting_for_deck_melee")
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


static func _try_assisted_ramming_boost_contact(ship, other: Node3D, dist: float, coll_dist: float) -> bool:
	if not RAMMING_BOOST_ASSIST_ENABLED:
		return false
	if not is_instance_valid(ship) or not is_instance_valid(other):
		return false
	if not NodeContractHelper.is_player_controlled_ship(ship):
		return false
	if NodeContractHelper.get_team_tag(ship) == NodeContractHelper.get_team_tag(other):
		return false
	if NodeContractHelper.is_sinking_or_dying(other):
		return false
	if not ship.has_method("is_ramming_boost_active") or ship.call("is_ramming_boost_active") != true:
		return false
	if dist > coll_dist + RAMMING_BOOST_ASSIST_PAD:
		return false
	var to_other: Vector3 = other.global_position - ship.global_position
	to_other.y = 0.0
	if to_other.length_squared() <= 0.0001:
		return false
	var dir := to_other.normalized()
	var ship_fwd: Vector3 = -ship.global_transform.basis.z
	ship_fwd.y = 0.0
	if ship_fwd.length_squared() <= 0.0001:
		return false
	ship_fwd = ship_fwd.normalized()
	var forward_dot := ship_fwd.dot(dir)
	if forward_dot < RAMMING_BOOST_ASSIST_FORWARD_DOT:
		return false
	var speed_value: Variant = ship.get("current_speed")
	var current_speed: float = absf(float(speed_value)) if speed_value != null else 0.0
	var min_speed_value: Variant = ship.get("min_ramming_speed")
	var min_speed: float = maxf(float(min_speed_value) if min_speed_value != null else 6.0, 0.1)
	if current_speed < min_speed * RAMMING_BOOST_ASSIST_MIN_SPEED_RATIO:
		return false
	var impact_speed: float = maxf(current_speed * lerpf(0.82, 1.0, clampf(forward_dot, 0.0, 1.0)), min_speed)
	if other.has_method("apply_ramming_damage"):
		other.call("apply_ramming_damage", ship, impact_speed)
		return true
	return false


static func _is_derelict_ship(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_derelict_ship"):
		return node.is_derelict_ship()
	if "is_derelict" in node:
		return node.get("is_derelict") == true
	return false


static func _has_active_deck_melee(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.get("deck_is_contested") == true or ship.get("deck_is_overrun") == true:
		return true
	var hostile_count_variant: Variant = ship.get("deck_hostile_boarder_count")
	if hostile_count_variant != null and int(hostile_count_variant) > 0:
		return true

	var ship_team: String = NodeContractHelper.get_team_tag(ship, "")
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier) or SoldierStateHelper.is_dead_soldier(soldier):
			continue
		var soldier_team: String = NodeContractHelper.get_team_tag(soldier, "")
		if not ship_team.is_empty() and soldier_team != ship_team:
			return true
		var target: Variant = soldier.get("current_target")
		if not is_instance_valid(target):
			continue
		if target.get("owned_ship") != ship:
			continue
		var target_team: String = NodeContractHelper.get_team_tag(target, "")
		if not ship_team.is_empty() and not target_team.is_empty() and target_team != ship_team:
			return true
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
	var ship_is_support: bool = PlayerFleetRoleHelper.is_support_ship(ship)
	var other_is_support: bool = PlayerFleetRoleHelper.is_support_ship(other_ship)
	var ship_is_player: bool = PlayerFleetRoleHelper.is_player_flagship(ship)
	var other_is_player: bool = PlayerFleetRoleHelper.is_player_flagship(other_ship)
	return (ship_is_support and other_is_player) or (other_is_support and ship_is_player)


static func _is_hostile_support_contact(ship, other_ship: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return false
	var ship_team := NodeContractHelper.get_team_tag(ship, "")
	var other_team := NodeContractHelper.get_team_tag(other_ship, "")
	if ship_team.is_empty() or other_team.is_empty() or ship_team == other_team:
		return false
	return PlayerFleetRoleHelper.is_support_ship(ship) or PlayerFleetRoleHelper.is_support_ship(other_ship)


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

	var angle_mult = remap(dot, 0.0, 1.0, RAMMING_DAMAGE_SIDE_HIT_MULT, RAMMING_DAMAGE_BOW_HIT_MULT)
	var attacker_alignment_mult := 1.0
	if is_instance_valid(other):
		var attacker_fwd := -other.global_transform.basis.z
		attacker_fwd.y = 0.0
		if attacker_fwd.length_squared() > 0.0001:
			attacker_fwd = attacker_fwd.normalized()
			var attacker_alignment := maxf(0.0, attacker_fwd.dot(-dir_to_other))
			attacker_alignment_mult = lerpf(
				RAMMING_DAMAGE_ATTACKER_MIN_ALIGNMENT_MULT,
				RAMMING_DAMAGE_ATTACKER_MAX_ALIGNMENT_MULT,
				smoothstep(0.25, 0.95, attacker_alignment)
			)
	var attacker_ram_mult := 1.0
	if is_instance_valid(other) and other.has_method("get_ramming_damage_multiplier_value"):
		attacker_ram_mult = maxf(0.1, float(other.call("get_ramming_damage_multiplier_value")))
	elif is_instance_valid(other) and other.get("ramming_damage_multiplier") != null:
		attacker_ram_mult = maxf(0.1, float(other.get("ramming_damage_multiplier")))
	var final_ram_damage = impact_speed * RAMMING_DAMAGE_SPEED_SCALE * angle_mult * attacker_alignment_mult * attacker_ram_mult

	var impact_pos = (ship.global_position + other.global_position) * 0.5
	impact_pos.y = 0.5
	var is_boosted_hit := _is_ramming_boost_attacker(other)
	var will_sink_from_hit := _will_ramming_hit_sink(ship, final_ram_damage)

	if not is_instance_valid(ship._cached_audio_manager):
		ship._cached_audio_manager = ship.get_node_or_null("/root/AudioManager")
	if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
		ship._cached_audio_manager.play_sfx("ship_collision", impact_pos, randf_range(0.74, 0.9), 0.0)

	var cam = ship.get_tree().root.get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(clamp(impact_speed * 0.05, 0.2, 0.6), 0.3)

	if will_sink_from_hit:
		spawn_ship_collision_effects(ship, _get_ship_contact_point(ship, other), impact_speed * (RAMMING_LETHAL_VFX_SPEED_MULT if will_sink_from_hit else 1.0))
	else:
		try_spawn_strong_collision_effects(ship, other, impact_speed)
	ship.apply_ramming_aoe(clamp(impact_speed * 1.5, 5.0, 20.0), impact_pos)
	_apply_ramming_impact_resistance(ship, other, impact_speed, dir_to_other, is_boosted_hit, will_sink_from_hit)
	_apply_ramming_knockback(ship, other, impact_speed, dir_to_other)

	if ship.DEBUG_COMBAT_LOGS:
		print("[Ramming] 충각 발생! (속도: %.1f) - 내 각도계수: %.2f, 공격 정렬: %.2f -> 입은 피해: %.1f" % [impact_speed, angle_mult, attacker_alignment_mult, final_ram_damage])
	ship.take_damage(final_ram_damage, (ship.global_position + other.global_position) * 0.5, "ramming")
	if is_instance_valid(other) and other.has_method("notify_ramming_boost_hit"):
		other.call("notify_ramming_boost_hit")


static func _is_ramming_boost_attacker(attacker: Node) -> bool:
	if not is_instance_valid(attacker) or not attacker.has_method("is_ramming_boost_active"):
		return false
	return attacker.call("is_ramming_boost_active") == true


static func _will_ramming_hit_sink(victim: Node, raw_ramming_damage: float) -> bool:
	if not is_instance_valid(victim):
		return false
	var hp_value: Variant = victim.get("hull_hp")
	if hp_value == null:
		return false
	var defense_value: Variant = victim.get("hull_defense")
	var defense := float(defense_value) if defense_value != null else 0.0
	var expected_damage := maxf(raw_ramming_damage - defense, 1.0)
	return float(hp_value) - expected_damage <= 0.0


static func _apply_ramming_impact_resistance(victim: Node, attacker: Node3D, impact_speed: float, dir_to_attacker: Vector3, is_boosted_hit: bool, will_sink_from_hit: bool) -> void:
	if not RAMMING_IMPACT_RESISTANCE_ENABLED:
		return
	if not is_instance_valid(victim) or not is_instance_valid(attacker):
		return
	if NodeContractHelper.get_team_tag(victim) == NodeContractHelper.get_team_tag(attacker):
		return
	if not is_boosted_hit and not will_sink_from_hit:
		return

	var speed_value: Variant = attacker.get("current_speed")
	if speed_value != null:
		var current_speed := float(speed_value)
		var victim_mass := get_ship_mass_scale(victim)
		var attacker_mass := get_ship_mass_scale(attacker)
		var mass_brake := clampf((victim_mass / maxf(attacker_mass, 0.1) - 1.0) * 0.10, 0.0, 0.16)
		var brake := clampf((RAMMING_LETHAL_IMPACT_BRAKE if will_sink_from_hit else RAMMING_BOOST_IMPACT_BRAKE) + mass_brake, 0.22, 0.72)
		attacker.set("current_speed", lerpf(current_speed, 0.0, brake))

	dir_to_attacker.y = 0.0
	if dir_to_attacker.length_squared() <= 0.0001:
		return
	if attacker.has_method("apply_collision_impulse"):
		var back_impulse := dir_to_attacker.normalized() * clampf(impact_speed * 0.16, 0.35, RAMMING_BOOST_BACK_IMPULSE)
		attacker.call("apply_collision_impulse", back_impulse)


static func _apply_ramming_knockback(victim, attacker: Node3D, impact_speed: float, dir_to_attacker: Vector3) -> void:
	if not is_instance_valid(victim) or not is_instance_valid(attacker):
		return
	if not victim.has_method("apply_collision_impulse"):
		return
	if NodeContractHelper.get_team_tag(victim) == NodeContractHelper.get_team_tag(attacker):
		return
	var knockback_mult_variant: Variant = attacker.get("ramming_knockback_multiplier")
	if knockback_mult_variant == null:
		return
	var knockback_mult := clampf(float(knockback_mult_variant), 0.0, 3.0)
	if knockback_mult <= 0.0:
		return
	if _is_ramming_boost_attacker(attacker):
		knockback_mult *= RAMMING_BOOST_KNOCKBACK_MULT
	dir_to_attacker.y = 0.0
	if dir_to_attacker.length_squared() <= 0.0001:
		return
	dir_to_attacker = dir_to_attacker.normalized()
	var attacker_fwd := -attacker.global_transform.basis.z
	attacker_fwd.y = 0.0
	if attacker_fwd.length_squared() <= 0.0001:
		return
	attacker_fwd = attacker_fwd.normalized()
	if attacker_fwd.dot(-dir_to_attacker) < RAMMING_KNOCKBACK_MIN_FORWARD_DOT:
		return
	var attacker_mass := get_ship_mass_scale(attacker)
	var victim_mass := get_ship_mass_scale(victim)
	var mass_scale := clampf(sqrt(attacker_mass / maxf(victim_mass, 0.1)), 0.65, 1.55)
	var threshold_variant: Variant = victim.get("min_ramming_speed")
	var threshold := maxf(float(threshold_variant) if threshold_variant != null else 6.0, 0.1)
	var extra_speed := maxf(0.0, impact_speed - threshold)
	var push_speed := clampf(
		(RAMMING_KNOCKBACK_BASE_SPEED + extra_speed * RAMMING_KNOCKBACK_SPEED_SCALE) * knockback_mult * mass_scale,
		0.0,
		RAMMING_KNOCKBACK_MAX_SPEED
	)
	if push_speed <= 0.05:
		return
	victim.apply_collision_impulse(-dir_to_attacker * push_speed)


static func spawn_ship_collision_effects(ship, impact_pos: Vector3, impact_speed: float) -> void:
	if not ship.is_inside_tree():
		return
	if _should_skip_collision_vfx_for_lightweight_ship(ship):
		return

	_spawn_ship_collision_water_splash(ship, impact_pos, impact_speed)

	# 우드 스플린터 (파편) - 충격 시 수면 효과 대신 나무 파편이 튀도록 함
	if ship.wood_splinter_scene:
		var pseudo_damage := impact_speed * 5.0
		WoodSplinter.spawn_burst(
			ship.get_tree(),
			ship.wood_splinter_scene,
			impact_pos + Vector3(0, 0.4, 0),
			pseudo_damage,
			impact_pos - ship.global_position,
			"ship_collision_splinter",
			5,
			80.0
		)


static func _should_skip_collision_vfx_for_lightweight_ship(ship) -> bool:
	if ship == null:
		return true
	return ship.get("wood_splinter_scene") == null


static func _spawn_ship_collision_water_splash(ship, impact_pos: Vector3, _impact_speed: float) -> void:
	var water_scene: PackedScene = SHIP_COLLISION_WATER_SPLASH_SCENE
	if water_scene == null:
		return
	var splash = ScenePool.acquire(ship.get_tree(), water_scene)
	if not is_instance_valid(splash):
		return
	var splash_pos := _get_ship_collision_water_splash_position(ship, impact_pos)
	ship.get_tree().root.add_child(splash)
	if splash is Node3D:
		(splash as Node3D).global_position = splash_pos
	if splash.has_method("pool_activate"):
		splash.pool_activate()
	if not is_instance_valid(ship._cached_audio_manager):
		ship._cached_audio_manager = ship.get_node_or_null("/root/AudioManager")
	if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
		ship._cached_audio_manager.play_sfx("ship_collision_water_splash", splash_pos, randf_range(0.96, 1.04), -0.5)


static func _get_ship_collision_water_splash_position(ship: Node3D, impact_pos: Vector3) -> Vector3:
	if not is_instance_valid(ship):
		return impact_pos
	var dir := impact_pos - ship.global_position
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		dir = -ship.global_transform.basis.z
		dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	var hull_radius := float(ship.call("get_directional_collision_radius", dir)) if ship.has_method("get_directional_collision_radius") else ShipContactGeometry.get_directional_collision_radius(ship, dir)
	var visual_radius := _get_visual_contact_radius(ship, dir, hull_radius)
	var outboard_pad := COLLISION_WATER_SPLASH_FRONT_PAD if _is_authored_hull_front_contact(ship, dir) else COLLISION_WATER_SPLASH_OUTBOARD_PAD
	var splash_pos := ship.global_position + dir * (visual_radius + outboard_pad)
	splash_pos.y = impact_pos.y
	return splash_pos
