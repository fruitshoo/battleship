extends RefCounted

const SUPPORT_SHIP_SCENE = preload("res://scenes/ships/support_ship.tscn")
const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SUPPORT_FLEET_ORDER_META := "support_fleet_order"
const SUPPORT_FLEET_NEXT_ORDER_META := "support_fleet_next_order"
const SUPPORT_FLEET_SLOT_INDEX_META := "support_fleet_slot_index"
const SUPPORT_FLEET_PROFILE_META := "support_fleet_profile"
const SUPPORT_FLEET_ROLE_META := "support_fleet_role"
const SUPPORT_FLEET_SQUADRON_META := "support_squadron_id"
const SUPPORT_FLEET_SLOT_ROLE_META := "support_squadron_slot_role"
const SITE_BONUS_TOTALS_META := "sea_site_bonus_totals"
const SITE_BONUS_COUNTS_META := "sea_site_bonus_counts"

static func spawn_or_repair_ally(ship) -> void:
	if not ShipAllyRoleHelper.is_player_flagship(ship):
		return
	SupportFleetStateHelper.initialize_flagship_state(ship)
	var support_ships: Array = get_support_fleet_ships(ship)

	if ship._cached_hud and ship._cached_hud.has_method("show_message"):
		ship._cached_hud.show_message("지원 함대가 합류했습니다!", 3.0)

	if not support_ships.is_empty():
		refresh_support_fleet_composition(ship)
		support_ships = get_support_fleet_ships(ship)
		var repair_fraction: float = _get_support_repair_fraction(ship)
		var upgrade_manager = _get_upgrade_manager(ship)
		for support_ship in support_ships:
			if support_ship.has_method("repair_ship"):
				support_ship.repair_ship(repair_fraction)
			_copy_site_bonuses_from_flagship(ship, support_ship)
			if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_upgrades_to_ship"):
				upgrade_manager.apply_fleet_upgrades_to_ship(support_ship)
		print("[Merit] 기존 지원 함대를 수리 및 강화했습니다.")
		if support_ships.size() >= ship.support_fleet_limit:
			return

	var occupied_slots: Dictionary = {}
	for support_ship in support_ships:
		if not is_instance_valid(support_ship):
			continue
		var support_order: int = int(support_ship.get_meta(SUPPORT_FLEET_ORDER_META, support_ship.get_instance_id()))
		var slot_index: int = int(support_ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, support_order))
		if slot_index >= 0:
			occupied_slots[slot_index] = true
	var support_slot: int = -1
	var max_slot_count: int = maxi(int(ship.support_fleet_limit), support_ships.size() + 1)
	for slot_index in range(max_slot_count):
		if occupied_slots.has(slot_index):
			continue
		support_slot = slot_index
		break
	if support_slot < 0:
		return
	var support_profile: Dictionary = resolve_support_fleet_profile(ship, support_slot)
	var support_scene := PlayerShipSupportSquadronHelper.get_profile_ship_scene(support_profile)
	if not support_scene:
		support_scene = SUPPORT_SHIP_SCENE
	if not support_scene:
		return
	var ally = support_scene.instantiate()
	PlayerShipSupportSquadronHelper.apply_support_fleet_profile(ally, support_profile)
	var next_support_order: int = int(ship.get_meta(SUPPORT_FLEET_NEXT_ORDER_META, 0))
	_configure_support_ship_instance(ally, ship, support_profile, support_slot, next_support_order, true)
	_copy_site_bonuses_from_flagship(ship, ally)

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
	var new_support_upgrade_manager = _get_upgrade_manager(ship)
	if is_instance_valid(new_support_upgrade_manager) and new_support_upgrade_manager.has_method("apply_fleet_upgrades_to_ship"):
		new_support_upgrade_manager.apply_fleet_upgrades_to_ship(ally)

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

static func refresh_support_fleet_composition(ship) -> void:
	if not ShipAllyRoleHelper.is_player_flagship(ship):
		return
	SupportFleetStateHelper.initialize_flagship_state(ship)
	var support_ships: Array = get_support_fleet_ships(ship)
	if support_ships.is_empty():
		return
	var slot_assignments: Dictionary = _build_runtime_slot_assignments(ship, support_ships)
	var upgrade_manager = _get_upgrade_manager(ship)
	for support_order_index in range(support_ships.size()):
		var support_ship = support_ships[support_order_index]
		if not is_instance_valid(support_ship):
			continue
		var previous_slot: int = int(support_ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, support_order_index))
		var previous_profile_id := str(support_ship.get_meta(SUPPORT_FLEET_PROFILE_META, "")).strip_edges()
		var previous_squadron_id := str(support_ship.get_meta(SUPPORT_FLEET_SQUADRON_META, "")).strip_edges()
		var previous_slot_role := str(support_ship.get_meta(SUPPORT_FLEET_SLOT_ROLE_META, "")).strip_edges()
		var support_slot: int = int(slot_assignments.get(support_ship.get_instance_id(), support_ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, support_order_index)))
		if support_slot < 0:
			support_slot = support_order_index
		var support_profile: Dictionary = resolve_support_fleet_profile(ship, support_slot)
		var next_profile_id := PlayerShipSupportSquadronHelper.get_profile_id(support_profile)
		var next_squadron_id := str(support_profile.get("squadron_id", "")).strip_edges()
		var next_slot_role := str(support_profile.get("slot_role", "")).strip_edges()
		SupportFleetStateHelper.assign_support_ship_to_flagship(support_ship, ship)
		if not PlayerShipSupportSquadronHelper.profile_matches_runtime_ship(support_profile, support_ship):
			PlayerShipSupportSquadronHelper.apply_support_fleet_profile(support_ship, support_profile)
			if support_ship.has_method("refresh_support_fleet_profile_runtime"):
				support_ship.call("refresh_support_fleet_profile_runtime", support_profile)
		var support_order: int = int(support_ship.get_meta(SUPPORT_FLEET_ORDER_META, support_order_index))
		_apply_support_profile_meta(support_ship, support_profile, support_slot, support_order)
		var reassigned_slot: bool = (
			previous_slot != support_slot
			or previous_profile_id != next_profile_id
			or previous_squadron_id != next_squadron_id
			or previous_slot_role != next_slot_role
		)
		if (
			reassigned_slot
			and SupportFleetStateHelper.get_effective_formation(support_ship) == SupportFleetStateHelper.FORMATION_WING
			and support_ship.get("is_boarding") != true
		):
			support_ship.set_meta("support_joining", true)
		if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_upgrades_to_ship"):
			_copy_site_bonuses_from_flagship(ship, support_ship)
			upgrade_manager.apply_fleet_upgrades_to_ship(support_ship)

static func _get_upgrade_manager(ship):
	if is_instance_valid(ship) and "_cached_um" in ship and is_instance_valid(ship._cached_um):
		return ship._cached_um
	if is_instance_valid(ship) and ship is Node:
		var tree := (ship as Node).get_tree()
		if tree != null and is_instance_valid(tree.root):
			return tree.root.get_node_or_null("UpgradeManager")
	return null


static func _copy_site_bonuses_from_flagship(flagship, support_ship) -> void:
	if not is_instance_valid(flagship) or not is_instance_valid(support_ship):
		return
	for meta_key in [SITE_BONUS_TOTALS_META, SITE_BONUS_COUNTS_META]:
		if not flagship.has_meta(meta_key):
			continue
		var value: Variant = flagship.get_meta(meta_key)
		if value is Dictionary:
			support_ship.set_meta(meta_key, (value as Dictionary).duplicate(true))
		else:
			support_ship.set_meta(meta_key, value)

static func _get_support_repair_fraction(_ship) -> float:
	return 0.2

static func _configure_support_ship_instance(ally, flagship, support_profile: Dictionary, support_slot: int, support_order: int, joining_support: bool) -> void:
	if not is_instance_valid(ally):
		return
	if ally.has_method("set_team"):
		ally.set_team("player")
	else:
		ally.team = "player"
	ally.set_meta("support_joining", joining_support)
	if joining_support:
		ally.set_meta("defer_initial_crew_setup", true)
	elif ally.has_meta("defer_initial_crew_setup"):
		ally.remove_meta("defer_initial_crew_setup")
	ShipAllyRoleHelper.mark_support_ship(ally)
	SupportFleetStateHelper.assign_support_ship_to_flagship(ally, flagship)
	_apply_support_profile_meta(ally, support_profile, support_slot, support_order)

static func _apply_support_profile_meta(ally, support_profile: Dictionary, support_slot: int, support_order: int) -> void:
	if not is_instance_valid(ally):
		return
	ally.set_meta(SUPPORT_FLEET_SLOT_INDEX_META, support_slot)
	ally.set_meta(SUPPORT_FLEET_PROFILE_META, PlayerShipSupportSquadronHelper.get_profile_id(support_profile))
	ally.set_meta(SUPPORT_FLEET_ROLE_META, str(support_profile.get("role", "")))
	ally.set_meta(SUPPORT_FLEET_SQUADRON_META, str(support_profile.get("squadron_id", "")))
	ally.set_meta(SUPPORT_FLEET_SLOT_ROLE_META, str(support_profile.get("slot_role", "")))
	ally.set_meta(SUPPORT_FLEET_ORDER_META, support_order)

static func _build_runtime_slot_assignments(ship, support_ships: Array) -> Dictionary:
	var assignments: Dictionary = {}
	var occupied_slots: Dictionary = {}
	var slot_count: int = maxi(int(ship.support_fleet_limit), support_ships.size())

	for support_ship in support_ships:
		if not is_instance_valid(support_ship):
			continue
		var current_profile_id := _get_runtime_support_profile_id(support_ship)
		var preferred_slot: int = int(support_ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, -1))
		var slot_index: int = _find_matching_unoccupied_slot(ship, current_profile_id, preferred_slot, occupied_slots, slot_count)
		if slot_index >= 0:
			assignments[support_ship.get_instance_id()] = slot_index
			occupied_slots[slot_index] = true

	for support_ship in support_ships:
		if not is_instance_valid(support_ship):
			continue
		if assignments.has(support_ship.get_instance_id()):
			continue
		var preferred_slot: int = int(support_ship.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, -1))
		var fallback_slot: int = _find_first_unoccupied_slot(preferred_slot, occupied_slots, slot_count)
		assignments[support_ship.get_instance_id()] = fallback_slot
		occupied_slots[fallback_slot] = true

	return assignments

static func _get_runtime_support_profile_id(ally) -> String:
	if not is_instance_valid(ally):
		return PlayerShipSupportSquadronHelper.PROFILE_MAENGSEON_SCREEN
	var profile_id := str(ally.get_meta(SUPPORT_FLEET_PROFILE_META, "")).strip_edges()
	if not profile_id.is_empty():
		return profile_id
	return PlayerShipSupportSquadronHelper.PROFILE_PANOKSEON_ESCORT if str(ally.get("ship_type")) == "panokseon_ally" else PlayerShipSupportSquadronHelper.PROFILE_MAENGSEON_SCREEN

static func _find_matching_unoccupied_slot(ship, profile_id: String, preferred_slot: int, occupied_slots: Dictionary, slot_count: int) -> int:
	if preferred_slot >= 0 and not occupied_slots.has(preferred_slot):
		var preferred_profile := resolve_support_fleet_profile(ship, preferred_slot)
		if PlayerShipSupportSquadronHelper.get_profile_id(preferred_profile) == profile_id:
			return preferred_slot
	for slot_index in range(slot_count):
		if occupied_slots.has(slot_index):
			continue
		var support_profile := resolve_support_fleet_profile(ship, slot_index)
		if PlayerShipSupportSquadronHelper.get_profile_id(support_profile) == profile_id:
			return slot_index
	return -1

static func _find_first_unoccupied_slot(preferred_slot: int, occupied_slots: Dictionary, slot_count: int) -> int:
	if preferred_slot >= 0 and not occupied_slots.has(preferred_slot):
		return preferred_slot
	for slot_index in range(slot_count):
		if not occupied_slots.has(slot_index):
			return slot_index
	return slot_count

static func get_support_fleet_ships(ship) -> Array:
	SupportFleetStateHelper.initialize_flagship_state(ship)
	var support_ships: Array = []
	for minion in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(minion):
			continue
		if not ShipAllyRoleHelper.is_support_ship(minion):
			continue
		if minion.has_method("is_combat_disabled") and minion.is_combat_disabled():
			continue
		if not SupportFleetStateHelper.is_support_owned_by_flagship(minion, ship):
			continue
		support_ships.append(minion)
	support_ships.sort_custom(func(a, b):
		var order_a: int = int(a.get_meta(SUPPORT_FLEET_ORDER_META, a.get_instance_id()))
		var order_b: int = int(b.get_meta(SUPPORT_FLEET_ORDER_META, b.get_instance_id()))
		var slot_a: int = int(a.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, order_a))
		var slot_b: int = int(b.get_meta(SUPPORT_FLEET_SLOT_INDEX_META, order_b))
		if slot_a != slot_b:
			return slot_a < slot_b
		return order_a < order_b
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
