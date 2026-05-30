extends RefCounted
class_name PlayerShipCargoTransportHelper

const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")

const CARRY_FORWARD_OFFSET := 0.08
const CARRY_SIDE_OFFSET := 0.08
const CARRY_HEIGHT_OFFSET := 0.46
const PICKUP_START_POSITION_META := "cargo_transport_pickup_start_position"
const PICKUP_START_ROTATION_META := "cargo_transport_pickup_start_rotation"
const THROW_ARC_META := "cargo_transport_throw_arc"
const STOW_POSE_META := "cargo_transport_stow_pose"
const STAIR_TOP_META := "cargo_transport_stair_top"
const STAIR_BOTTOM_META := "cargo_transport_stair_bottom"
const ROOF_THROW_ARC_META := "roof_cargo_transport_arc"
const ROOF_DEATH_OVERBOARD_IN_PROGRESS_META := "roof_death_overboard_in_progress"


static func update_cargo_transport(ship, delta: float) -> void:
	if not ship.cargo_transport_enabled:
		return
	if not can_run_cargo_transport(ship):
		ship.cargo_transport_peace_timer = 0.0
		ship.cargo_transport_timer = 0.0
		return

	ship.cargo_transport_peace_timer += delta
	if ship.cargo_transport_peace_timer < ship.cargo_transport_delay:
		return

	ship.cargo_transport_timer -= delta
	if ship.cargo_transport_timer > 0.0:
		return
	ship.cargo_transport_timer = ship.cargo_transport_interval
	try_cleanup_corpse(ship)


static func can_run_cargo_transport(ship) -> bool:
	if ship.is_sinking or ship.is_dying or ship.is_derelict:
		return false
	if ship.deck_is_contested or ship.deck_is_overrun:
		return false
	if ship.is_boarding:
		return false
	if ship._has_nearby_enemy_pressure_for_respawn():
		return false
	return true


static func try_cleanup_corpse(ship) -> void:
	var corpse: Node3D = find_cleanup_corpse(ship)
	if not is_instance_valid(corpse):
		return
	var corpse_team: String = corpse.get_team_tag() if corpse.has_method("get_team_tag") else str(corpse.get("team"))
	if corpse_team != "player" and is_roof_corpse(corpse):
		ship._throw_roof_payload_overboard(corpse)
		return
	var cleaner: Node3D = find_cargo_transport_actor(ship, corpse)
	if not is_instance_valid(cleaner):
		return
	if not SoldierShipWorkPriorityHelper.reserve_work_slot(corpse, cleaner, SoldierShipWorkPriorityHelper.TASK_CARGO_TRANSPORT, ship.cargo_transport_throw_duration + 4.0):
		return

	corpse.set_meta("cargo_transport_in_progress", true)
	set_actor_action(cleaner, SoldierActionHelper.ACTION_CARGO_TRANSPORT_APPROACH)
	prepare_cleaner(ship, cleaner, corpse)
	if corpse_team == "player":
		ship._stow_friendly_corpse_below_deck(cleaner, corpse)
	else:
		ship._throw_payload_overboard(cleaner, corpse)


static func find_cleanup_corpse(ship) -> Node3D:
	var friendly_corpse := find_cleanup_corpse_by_team(ship, "player")
	if is_instance_valid(friendly_corpse):
		return friendly_corpse
	return find_cleanup_enemy_corpse(ship)


static func find_cleanup_enemy_corpse(ship) -> Node3D:
	return find_cleanup_corpse_by_team(ship, "enemy")


static func is_roof_corpse(corpse: Node3D) -> bool:
	return SoldierDeckZoneHelper.is_roof(corpse)


static func find_cleanup_corpse_by_team(ship, target_team: String) -> Node3D:
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier) or not (soldier is Node3D):
			continue
		if soldier.get_meta("cargo_transport_in_progress", false) == true:
			continue
		if soldier.get_meta(ROOF_DEATH_OVERBOARD_IN_PROGRESS_META, false) == true:
			continue
		if SoldierShipWorkPriorityHelper.is_work_slot_reserved_for_other(soldier, null, SoldierShipWorkPriorityHelper.TASK_CARGO_TRANSPORT):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != target_team:
			continue
		if not SoldierStateHelper.is_dead_soldier(soldier):
			continue
		if SoldierStateHelper.is_incapacitated_soldier(soldier):
			continue
		return soldier as Node3D
	return null


static func find_cargo_transport_actor(ship, corpse: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance_sq: float = INF
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier) or not (soldier is Node3D):
			continue
		if is_actor_busy(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != "player":
			continue
		if not SoldierShipWorkPriorityHelper.can_accept_immediate_work(soldier, SoldierShipWorkPriorityHelper.TASK_CARGO_TRANSPORT):
			continue
		if SoldierStateHelper.is_dead_soldier(soldier):
			continue
		var soldier_node := soldier as Node3D
		var distance_sq: float = soldier_node.global_position.distance_squared_to(corpse.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = soldier_node
	return best


static func prepare_cleaner(ship, cleaner: Node3D, corpse: Node3D) -> void:
	if "current_target" in cleaner:
		cleaner.set("current_target", null)
	if "attack_timer" in cleaner:
		cleaner.set("attack_timer", maxf(float(cleaner.get("attack_timer")), ship.cargo_transport_throw_duration + 2.0))
	if "velocity" in cleaner:
		cleaner.set("velocity", Vector3.ZERO)
	if cleaner.has_method("_change_state"):
		cleaner.call("_change_state", 0)
	var look_target := Vector3(corpse.global_position.x, cleaner.global_position.y, corpse.global_position.z)
	if not cleaner.global_position.is_equal_approx(look_target):
		cleaner.look_at(look_target, Vector3.UP)


static func is_actor_busy(soldier) -> bool:
	if not is_instance_valid(soldier):
		return true
	if soldier.has_method("has_named_action"):
		return bool(soldier.call("has_named_action"))
	return SoldierActionHelper.has_action(soldier)


static func set_actor_action(cleaner: Node3D, action_name: String) -> void:
	if not is_instance_valid(cleaner):
		return
	if cleaner.has_method("begin_cargo_transport_action"):
		cleaner.call("begin_cargo_transport_action", action_name)
	else:
		SoldierActionHelper.begin_cargo_transport_action(cleaner, action_name)


static func get_pickup_point(ship, cleaner: Node3D, corpse: Node3D) -> Vector3:
	var corpse_local: Vector3 = ship.to_local(corpse.global_position)
	var cleaner_local: Vector3 = ship.to_local(cleaner.global_position)
	var approach_dir: Vector3 = cleaner_local - corpse_local
	approach_dir.y = 0.0
	if approach_dir.length_squared() <= 0.001:
		approach_dir = Vector3(-1.0 if corpse_local.x >= 0.0 else 1.0, 0.0, 0.0)
	approach_dir = approach_dir.normalized()
	var local_point: Vector3 = corpse_local + approach_dir * 0.72
	local_point = clamp_deck_local(ship, local_point, 0.38)
	var global_point: Vector3 = ship.to_global(local_point)
	global_point.y = cleaner.global_position.y
	return global_point


static func get_stair_stand_point(ship, cleaner: Node3D) -> Vector3:
	var stair_path: Dictionary = ship.get_crew_stair_descent_points()
	var stair_local: Vector3 = stair_path.get("top_local", ship.to_local(ship.get_crew_stair_global_position()))
	stair_local = clamp_deck_local(ship, stair_local, 0.38)
	var global_point: Vector3 = ship.to_global(stair_local)
	global_point.y = cleaner.global_position.y
	return global_point


static func get_rail_stand_point(ship, cleaner: Node3D, corpse: Node3D, throw_target: Vector3) -> Vector3:
	var local_pos: Vector3 = ship.to_local(corpse.global_position)
	var local_throw: Vector3 = ship.to_local(throw_target)
	var side_sign: float = 1.0 if local_throw.x >= 0.0 else -1.0
	var deck_half_width: float = maxf(1.8, ship._hull_half_extents.x * ship.deck_bounds_ratio)
	var deck_half_length: float = maxf(2.5, ship._hull_half_extents.y * ship.deck_bounds_ratio)
	local_pos.x = side_sign * maxf(0.3, deck_half_width - 0.58)
	local_pos.z = clampf(local_pos.z, -deck_half_length + 0.32, deck_half_length - 0.32)
	var global_point: Vector3 = ship.to_global(local_pos)
	global_point.y = cleaner.global_position.y
	return global_point


static func get_actor_local_target(cleaner: Node3D, global_target: Vector3, preserve_target_y: bool = false) -> Vector3:
	var parent_3d := cleaner.get_parent() as Node3D
	if not is_instance_valid(parent_3d):
		return global_target
	var local_target: Vector3 = parent_3d.to_local(global_target)
	if not preserve_target_y:
		local_target.y = cleaner.position.y
	return local_target


static func get_carry_rotation(ship, corpse: Node3D, actor_position: Vector3, throw_target: Vector3) -> Vector3:
	var to_rail: Vector3 = throw_target - actor_position
	to_rail.y = 0.0
	if to_rail.length_squared() <= 0.001:
		return corpse.rotation + Vector3(deg_to_rad(8.0), 0.0, deg_to_rad(6.0))
	to_rail = to_rail.normalized()
	var yaw := atan2(to_rail.x, to_rail.z)
	var side_roll := deg_to_rad(18.0 if ship.to_local(actor_position).x >= 0.0 else -18.0)
	return Vector3(deg_to_rad(8.0), yaw, side_roll)


static func get_walk_seconds(from_position: Vector3, to_position: Vector3, cleaner: Node3D) -> float:
	var planar_delta: Vector3 = to_position - from_position
	planar_delta.y = 0.0
	var move_speed_value: float = float(cleaner.get("move_speed")) if cleaner.get("move_speed") != null else 3.0
	return clampf(planar_delta.length() / maxf(move_speed_value * 1.05, 0.1), 0.18, 1.45)


static func clamp_deck_local(ship, local_point: Vector3, inset: float) -> Vector3:
	var deck_half_width: float = maxf(1.8, ship._hull_half_extents.x * ship.deck_bounds_ratio)
	var deck_half_length: float = maxf(2.5, ship._hull_half_extents.y * ship.deck_bounds_ratio)
	local_point.x = clampf(local_point.x, -deck_half_width + inset, deck_half_width - inset)
	local_point.z = clampf(local_point.z, -deck_half_length + inset, deck_half_length - inset)
	return local_point


static func face_actor(cleaner: Node3D, look_position: Vector3) -> void:
	if not is_instance_valid(cleaner):
		return
	var look_target := Vector3(look_position.x, cleaner.global_position.y, look_position.z)
	if not cleaner.global_position.is_equal_approx(look_target):
		cleaner.look_at(look_target, Vector3.UP)


static func get_transport_payload_offsets() -> Dictionary:
	return {
		SoldierActionHelper.PAYLOAD_DEF_FORWARD_OFFSET: CARRY_FORWARD_OFFSET,
		SoldierActionHelper.PAYLOAD_DEF_SIDE_OFFSET: CARRY_SIDE_OFFSET,
		SoldierActionHelper.PAYLOAD_DEF_HEIGHT_OFFSET: CARRY_HEIGHT_OFFSET,
	}


static func get_throw_origin(cleaner: Node3D, corpse: Node3D, throw_target: Vector3) -> Vector3:
	return get_throw_origin_from_actor_position(cleaner.global_position, corpse, throw_target)


static func get_throw_origin_from_actor_position(actor_position: Vector3, corpse: Node3D, throw_target: Vector3) -> Vector3:
	var to_rail: Vector3 = throw_target - actor_position
	to_rail.y = 0.0
	if to_rail.length_squared() <= 0.001:
		to_rail = corpse.global_position - actor_position
		to_rail.y = 0.0
	if to_rail.length_squared() <= 0.001:
		to_rail = Vector3.RIGHT
	to_rail = to_rail.normalized()
	var origin := actor_position + to_rail * 0.62
	origin.y = maxf(corpse.global_position.y, actor_position.y + 0.48)
	return origin


static func get_throw_target(ship, corpse: Node3D) -> Vector3:
	var local_pos: Vector3 = ship.to_local(corpse.global_position)
	var side_sign: float = 1.0 if local_pos.x >= 0.0 else -1.0
	var deck_half_width: float = maxf(1.8, ship._hull_half_extents.x * ship.deck_bounds_ratio)
	var deck_half_length: float = maxf(2.5, ship._hull_half_extents.y * ship.deck_bounds_ratio)
	local_pos.x = side_sign * (deck_half_width + randf_range(3.0, 4.2))
	local_pos.z = clampf(local_pos.z, -deck_half_length, deck_half_length)
	var global_target: Vector3 = ship.to_global(local_pos)
	global_target.y = 0.05
	return global_target


static func get_roof_throw_target(ship, corpse: Node3D) -> Vector3:
	var local_pos: Vector3 = ship.to_local(corpse.global_position)
	var side_sign: float = 1.0 if local_pos.x >= 0.0 else -1.0
	if absf(local_pos.x) < 0.25:
		side_sign = 1.0 if randf() >= 0.5 else -1.0
	var roof_half_width: float = maxf(1.35, minf(ship._hull_half_extents.x * 0.55, ship._hull_half_extents.x))
	var roof_half_length: float = maxf(2.0, ship._hull_half_extents.y * 0.68)
	local_pos.x = side_sign * (roof_half_width + randf_range(2.4, 3.5))
	local_pos.z = clampf(local_pos.z + randf_range(-0.25, 0.25), -roof_half_length, roof_half_length)
	var global_target: Vector3 = ship.to_global(local_pos)
	global_target.y = 0.05
	return global_target


static func grant_xp(ship) -> void:
	if not is_instance_valid(ship._cached_level_manager) or not ship._cached_level_manager.has_method("add_bonus_xp"):
		return
	var xp_reward: int = max(0, int(ship._cached_level_manager.get("cargo_transport_xp_reward")))
	if xp_reward <= 0:
		return
	ship._cached_level_manager.add_bonus_xp(xp_reward)


static func play_overboard_disposal_splash(ship, splash_pos: Vector3) -> void:
	if ship.water_splash_scene:
		var splash = ScenePool.acquire(ship.get_tree(), ship.water_splash_scene)
		if is_instance_valid(splash):
			ship.get_tree().root.add_child(splash)
			if splash is Node3D:
				(splash as Node3D).global_position = Vector3(splash_pos.x, 0.05, splash_pos.z)
			if splash.has_method("configure_as_overboard_disposal"):
				splash.configure_as_overboard_disposal()
			elif splash.has_method("configure_as_splash"):
				splash.configure_as_splash()
			elif splash.has_method("configure_as_small"):
				splash.configure_as_small()
			if splash.has_method("pool_activate"):
				splash.call_deferred("pool_activate")
	if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
		ship._cached_audio_manager.play_sfx("water_splash_small", splash_pos, randf_range(0.85, 1.15), 2.0)
