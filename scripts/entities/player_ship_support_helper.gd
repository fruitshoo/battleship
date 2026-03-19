extends RefCounted

const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const SUPPORT_FLEET_ORDER_META := "support_fleet_order"
const SUPPORT_FLEET_NEXT_ORDER_META := "support_fleet_next_order"

static func spawn_or_repair_ally(ship) -> void:
	var support_ships: Array = get_support_fleet_ships(ship)

	if ship._cached_hud and ship._cached_hud.has_method("show_message"):
		ship._cached_hud.show_message("지원 함대가 합류했습니다!", 3.0)

	if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
		ship._cached_audio_manager.play_sfx("trumpet_war", ship.global_position)

	if not support_ships.is_empty():
		for support_ship in support_ships:
			if support_ship.has_method("repair_ship"):
				support_ship.repair_ship(0.5)
			if is_instance_valid(UpgradeManager):
				UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)
		print("[Merit] 기존 지원 함대를 수리 및 강화했습니다.")
		if support_ships.size() >= ship.support_fleet_limit:
			return

	if not ship.ENEMY_SHIP_SCENE:
		return

	var ally = ship.ENEMY_SHIP_SCENE.instantiate()

	if "ship_type" in ally:
		ally.ship_type = "maengseon_ally"
	if "hull_scene" in ally:
		ally.hull_scene = ship.MAENGSEON_HULL_SCENE
		if "cannon_scene" in ally:
			ally.cannon_scene = ship.JOSEON_CANNON_SCENE

	if ally.has_method("set_team"):
		ally.set_team("player")
	else:
		ally.team = "player"
	var next_support_order: int = int(ship.get_meta(SUPPORT_FLEET_NEXT_ORDER_META, 0))
	ally.set_meta("support_joining", true)
	ally.set_meta("support_fleet_ship", true)
	ally.set_meta(SUPPORT_FLEET_ORDER_META, next_support_order)

	ship.get_parent().add_child(ally)

	var forward: Vector3 = -ship.global_transform.basis.z
	var spawn_pos: Vector3 = get_offscreen_ally_spawn_position(ship)
	ally.global_position = spawn_pos
	ally.look_at(ship.global_position + forward * 50.0, Vector3.UP)
	ship.set_meta(SUPPORT_FLEET_NEXT_ORDER_META, next_support_order + 1)

	if ally.has_method("set_team"):
		ally.set_team("player")
	if ally.has_method("add_to_group"):
		ally.add_to_group("captured_minion")
	if "target" in ally:
		ally.target = ship
	if ally.has_method("_find_player"):
		ally._find_player()
	if "current_speed" in ally:
		ally.current_speed = maxf(float(ship.get("current_speed")), float(ally.get("move_speed")) * 0.6)
	if "_last_ai_speed" in ally:
		ally._last_ai_speed = ally.current_speed

	print("[Summon] 정규군 함선을 소환했습니다!")

static func get_support_fleet_ships(ship) -> Array:
	var support_ships: Array = []
	var minions: Array = SceneGroupCache.get_nodes(ship.get_tree(), "captured_minion")
	for minion in minions:
		if not is_instance_valid(minion):
			continue
		if bool(minion.get_meta("support_fleet_ship", false)) == false:
			continue
		if minion.get("is_dying") == true or minion.get("is_sinking") == true or minion.get("is_derelict") == true:
			continue
		support_ships.append(minion)
	support_ships.sort_custom(func(a, b):
		return int(a.get_meta(SUPPORT_FLEET_ORDER_META, a.get_instance_id())) < int(b.get_meta(SUPPORT_FLEET_ORDER_META, b.get_instance_id()))
	)
	return support_ships

static func get_offscreen_ally_spawn_position(ship) -> Vector3:
	var fallback_forward: Vector3 = -ship.global_transform.basis.z
	fallback_forward.y = 0.0
	if fallback_forward.length_squared() <= 0.0001:
		fallback_forward = Vector3.FORWARD
	else:
		fallback_forward = fallback_forward.normalized()
	var fallback_right: Vector3 = fallback_forward.cross(Vector3.UP).normalized()
	var fallback_pos: Vector3 = ship.global_position + fallback_right * randf_range(-35.0, 35.0) - fallback_forward * 55.0
	fallback_pos.y = 0.0

	var cam: Camera3D = ship.get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		return fallback_pos

	var viewport_rect: Rect2 = ship.get_viewport().get_visible_rect()
	var wind_dir_2d: Vector2 = Vector2.ZERO
	if is_instance_valid(ship._cached_wind_manager) and ship._cached_wind_manager.has_method("get_wind_direction"):
		wind_dir_2d = ship._cached_wind_manager.get_wind_direction()
	else:
		var wind_manager: Node = ship.get_node_or_null("/root/WindManager")
		if is_instance_valid(wind_manager) and wind_manager.has_method("get_wind_direction"):
			wind_dir_2d = wind_manager.get_wind_direction()

	if wind_dir_2d.length_squared() > 0.0001:
		var wind_flow_dir: Vector3 = Vector3(wind_dir_2d.x, 0.0, wind_dir_2d.y).normalized()
		var lateral_dir: Vector3 = wind_flow_dir.cross(Vector3.UP).normalized()
		var base_dist: float = randf_range(58.0, 72.0)
		var lateral_offset: float = randf_range(-16.0, 16.0)
		var candidate: Vector3 = ship.global_position - wind_flow_dir * base_dist + lateral_dir * lateral_offset
		candidate.y = 0.0

		if not _is_world_position_offscreen(cam, viewport_rect, candidate):
			candidate -= wind_flow_dir * randf_range(18.0, 26.0)
			candidate.y = 0.0

		if _is_world_position_offscreen(cam, viewport_rect, candidate):
			return candidate

	var use_left_side: bool = randf() < 0.5
	var sample_x: float = -96.0 if use_left_side else viewport_rect.size.x + 96.0
	var sample_y: float = viewport_rect.size.y * randf_range(0.48, 0.66)
	var projected_pos: Vector3 = _sample_ocean_plane_from_screen(cam, Vector2(sample_x, sample_y))
	if projected_pos == Vector3.ZERO:
		return fallback_pos

	var to_spawn: Vector3 = projected_pos - ship.global_position
	to_spawn.y = 0.0
	if to_spawn.length_squared() <= 0.0001:
		return fallback_pos

	var dist: float = to_spawn.length()
	var dir: Vector3 = to_spawn / dist
	var clamped_dist: float = clampf(dist, 48.0, 72.0)
	projected_pos = ship.global_position + dir * clamped_dist
	projected_pos.y = 0.0
	return projected_pos

static func update_support_fleet_respawn(ship, delta: float) -> void:
	if ship.is_sinking or ship.is_dying:
		return
	if not is_instance_valid(ship._cached_um):
		ship.support_fleet_respawn_timer = 0.0
		return
	if int(ship._cached_um.current_levels.get("fleet_signal", 0)) <= 0:
		ship.support_fleet_respawn_timer = 0.0
		return

	var support_ships: Array = get_support_fleet_ships(ship)
	if support_ships.size() >= ship.support_fleet_limit:
		ship.support_fleet_respawn_timer = 0.0
		return

	ship.support_fleet_respawn_timer += delta
	if ship.support_fleet_respawn_timer >= ship.support_fleet_respawn_interval:
		ship.support_fleet_respawn_timer = 0.0
		spawn_or_repair_ally(ship)

static func _is_world_position_offscreen(cam: Camera3D, viewport_rect: Rect2, world_pos: Vector3) -> bool:
	if cam.is_position_behind(world_pos):
		return true
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	return not viewport_rect.has_point(screen_pos)

static func _sample_ocean_plane_from_screen(cam: Camera3D, screen_pos: Vector2) -> Vector3:
	var ray_origin: Vector3 = cam.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = cam.project_ray_normal(screen_pos)
	if absf(ray_dir.y) <= 0.0001:
		return Vector3.ZERO

	var t: float = -ray_origin.y / ray_dir.y
	if t <= 0.0:
		return Vector3.ZERO

	var world_pos: Vector3 = ray_origin + ray_dir * t
	world_pos.y = 0.0
	return world_pos
