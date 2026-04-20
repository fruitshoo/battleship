extends RefCounted

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const SUPPORT_SHIP_SCENE = preload("res://scenes/ships/support_ship.tscn")
const ShipAllyRoleHelper = preload("res://scripts/entities/ships/ship_ally_role_helper.gd")
const PlayerShipSupportSquadronHelper = preload("res://scripts/entities/ships/player_ship_support_squadron_helper.gd")
const SUPPORT_FLEET_ORDER_META := "support_fleet_order"
const SUPPORT_FLEET_NEXT_ORDER_META := "support_fleet_next_order"
const SUPPORT_FLEET_PROFILE_META := "support_fleet_profile"
const SUPPORT_FLEET_ROLE_META := "support_fleet_role"
const SUPPORT_FLEET_SQUADRON_META := "support_squadron_id"
const SUPPORT_FLEET_SLOT_ROLE_META := "support_squadron_slot_role"

static func spawn_or_repair_ally(ship) -> void:
	if not ShipAllyRoleHelper.is_player_flagship(ship):
		return
	var support_ships: Array = get_support_fleet_ships(ship)

	if ship._cached_hud and ship._cached_hud.has_method("show_message"):
		ship._cached_hud.show_message("지원 함대가 합류했습니다!", 3.0)

	if not support_ships.is_empty():
		var repair_fraction: float = _get_support_repair_fraction(ship)
		for support_ship in support_ships:
			if support_ship.has_method("repair_ship"):
				support_ship.repair_ship(repair_fraction)
			var upgrade_manager = _get_upgrade_manager(ship)
			if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_upgrades_to_ship"):
				upgrade_manager.apply_fleet_upgrades_to_ship(support_ship)
		print("[Merit] 기존 지원 함대를 수리 및 강화했습니다.")
		if support_ships.size() >= ship.support_fleet_limit:
			return

	if not SUPPORT_SHIP_SCENE:
		return

	var support_slot: int = support_ships.size()
	var support_profile: Dictionary = resolve_support_fleet_profile(ship, support_slot)
	var ally = SUPPORT_SHIP_SCENE.instantiate()
	PlayerShipSupportSquadronHelper.apply_support_fleet_profile(ally, support_profile)

	if ally.has_method("set_team"):
		ally.set_team("player")
	else:
		ally.team = "player"
	var next_support_order: int = int(ship.get_meta(SUPPORT_FLEET_NEXT_ORDER_META, 0))
	ally.set_meta("support_joining", true)
	ShipAllyRoleHelper.mark_support_ship(ally)
	ally.set_meta("defer_initial_crew_setup", true)
	ally.set_meta(SUPPORT_FLEET_PROFILE_META, str(support_profile.get("id", "")))
	ally.set_meta(SUPPORT_FLEET_ROLE_META, str(support_profile.get("role", "")))
	ally.set_meta(SUPPORT_FLEET_SQUADRON_META, str(support_profile.get("squadron_id", "")))
	ally.set_meta(SUPPORT_FLEET_SLOT_ROLE_META, str(support_profile.get("slot_role", "")))
	ally.set_meta(SUPPORT_FLEET_ORDER_META, next_support_order)

	ship.get_parent().add_child(ally)

	var forward: Vector3 = -ship.global_transform.basis.z
	var spawn_pos: Vector3 = get_offscreen_ally_spawn_position(ship)
	ally.global_position = spawn_pos
	ally.look_at(ship.global_position + forward * 50.0, Vector3.UP)
	ship.set_meta(SUPPORT_FLEET_NEXT_ORDER_META, next_support_order + 1)

	if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
		ship._cached_audio_manager.play_sfx("support_foghorn", ally.global_position)

	if ally.has_method("set_team"):
		ally.set_team("player")
	if ally.has_method("add_to_group"):
		ally.add_to_group("captured_minion")
	EntityRegistry.register_captured_minion(ally)
	if "target" in ally:
		ally.target = ship
	if ally.has_method("_find_player"):
		ally._find_player()
	if "current_speed" in ally:
		ally.current_speed = maxf(float(ship.get("current_speed")), float(ally.get("move_speed")) * 0.6)
	if "_last_ai_speed" in ally:
		ally._last_ai_speed = ally.current_speed

	print("[Summon] 정규군 함선을 소환했습니다! profile=%s squadron=%s slot=%s" % [
		str(support_profile.get("id", "unknown")),
		str(support_profile.get("squadron_id", "unknown")),
		str(support_profile.get("slot_role", "unknown")),
	])

static func resolve_support_fleet_profile(ship, support_slot: int = 0) -> Dictionary:
	var current_levels: Dictionary = {}
	var upgrades: Dictionary = {}
	var upgrade_manager = _get_upgrade_manager(ship)
	if is_instance_valid(upgrade_manager):
		if "current_levels" in upgrade_manager and upgrade_manager.current_levels is Dictionary:
			current_levels = upgrade_manager.current_levels
		if "UPGRADES" in upgrade_manager and upgrade_manager.UPGRADES is Dictionary:
			upgrades = upgrade_manager.UPGRADES
	return PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels(current_levels, upgrades, support_slot)

static func _get_upgrade_manager(ship):
	if is_instance_valid(ship) and "_cached_um" in ship and is_instance_valid(ship._cached_um):
		return ship._cached_um
	if is_instance_valid(ship) and ship is Node:
		var tree := (ship as Node).get_tree()
		if tree != null and is_instance_valid(tree.root):
			return tree.root.get_node_or_null("UpgradeManager")
	return null

static func _get_support_repair_fraction(_ship) -> float:
	return 0.2

static func get_support_fleet_ships(ship) -> Array:
	var support_ships: Array = []
	for minion in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(minion):
			continue
		if not ShipAllyRoleHelper.is_support_ship(minion):
			continue
		if minion.has_method("is_combat_disabled") and minion.is_combat_disabled():
			continue
		support_ships.append(minion)
	support_ships.sort_custom(func(a, b):
		return int(a.get_meta(SUPPORT_FLEET_ORDER_META, a.get_instance_id())) < int(b.get_meta(SUPPORT_FLEET_ORDER_META, b.get_instance_id()))
	)
	return support_ships

static func get_offscreen_ally_spawn_position(ship) -> Vector3:
	var forward_dir: Vector3 = -ship.global_transform.basis.z
	forward_dir.y = 0.0
	if forward_dir.length_squared() <= 0.0001:
		forward_dir = Vector3.FORWARD
	else:
		forward_dir = forward_dir.normalized()
	var backward_dir: Vector3 = -forward_dir
	var right_dir: Vector3 = forward_dir.cross(Vector3.UP).normalized()
	var fallback_pos: Vector3 = ship.global_position + backward_dir * 62.0 + right_dir * randf_range(-18.0, 18.0)
	fallback_pos.y = 0.0

	var cam: Camera3D = ship.get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		return fallback_pos

	var viewport_rect: Rect2 = ship.get_viewport().get_visible_rect()
	var candidate: Vector3 = fallback_pos
	if not _is_world_position_offscreen(cam, viewport_rect, candidate):
		candidate = ship.global_position + backward_dir * 84.0 + right_dir * randf_range(-22.0, 22.0)
		candidate.y = 0.0

	if not _is_world_position_offscreen(cam, viewport_rect, candidate):
		candidate = ship.global_position + backward_dir * 104.0 + right_dir * randf_range(-28.0, 28.0)
		candidate.y = 0.0

	if _is_world_position_offscreen(cam, viewport_rect, candidate):
		return candidate

	return fallback_pos

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
