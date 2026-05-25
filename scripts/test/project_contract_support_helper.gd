extends RefCounted
class_name ProjectContractSupportHelper

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")

const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SupportFleetFormationHelper = preload("res://scripts/entities/ships/support_fleet_formation_helper.gd")
const SupportFleetCannonRules = preload("res://scripts/entities/ships/support_fleet_cannon_helper.gd")


static func _reconcile_support_fleet(player_ship: Node3D, failures: Array[String], reason: String, options: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(UpgradeManager) or not UpgradeManager.has_method("reconcile_support_fleet"):
		failures.append("support fleet smoke missing support fleet reconcile helper")
		return {}
	return UpgradeManager.call("reconcile_support_fleet", player_ship, reason, options)


static func _request_support_spawn(player_ship: Node3D, failures: Array[String], reason: String) -> Dictionary:
	return _reconcile_support_fleet(player_ship, failures, reason, {
		"allow_autospawn": true,
		"spawn_now": true,
	})


static func run_support_fleet_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("support fleet smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("support fleet smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("support fleet smoke missing PlayerShip")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	if not player_ship.has_method("_spawn_or_repair_support_ship") or not player_ship.has_method("_get_support_fleet_ships"):
		failures.append("support fleet smoke missing player ship support helpers")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	if "support_fleet_limit" in player_ship:
		player_ship.set("support_fleet_limit", 1)

	_run_support_wing_join_geometry_contract(failures, smoke_root, player_ship)

	var support_registry_before: int = EntityRegistry.count_support_ships()
	var capture_slots_before: int = PlayerFleetRoleHelper.count_capture_slot_ships(EntityRegistry.get_legacy_captured_ships())
	_request_support_spawn(player_ship, failures, "support_contract_initial_spawn")
	await _wait_frames(owner, wait_frames_after_spawn + 2)

	var support_ships: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships.size() != 1:
		failures.append("support fleet smoke expected 1 support ship, got %d" % support_ships.size())
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var support_ship := support_ships[0] as Node3D
	if not is_instance_valid(support_ship):
		failures.append("support fleet smoke support ship was invalid")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var support_team: String = str(support_ship.get("team"))
	if support_team != "player":
		failures.append("support fleet smoke team mismatch: %s" % support_team)
	if not player_ship.has_method("get_player_fleet_role") or str(player_ship.call("get_player_fleet_role")) != PlayerFleetRoleHelper.ROLE_PLAYER_FLAGSHIP:
		failures.append("support fleet smoke player ship should be tagged as player_flagship")
	if not support_ship.has_method("get_player_fleet_role") or str(support_ship.call("get_player_fleet_role")) != PlayerFleetRoleHelper.ROLE_SUPPORT_FLEET:
		failures.append("support fleet smoke support ship should be tagged as support_fleet")
	if PlayerFleetRoleHelper.is_legacy_captured_ship(support_ship):
		failures.append("support fleet smoke support ship should not consume legacy capture role slots")
	if not support_ship.is_in_group("support_ship"):
		failures.append("support fleet smoke missing support_ship group")
	if support_ship.get_meta("support_fleet_ship", false) != true:
		failures.append("support fleet smoke missing support_fleet_ship meta")
	if int(support_ship.get_meta("support_fleet_owner_id", 0)) != player_ship.get_instance_id():
		failures.append("support fleet smoke support ship owner mismatch")
	if EntityRegistry.count_support_ships() <= support_registry_before:
		failures.append("support fleet smoke did not increase support ship registry count")
	if not EntityRegistry.get_support_ships().has(support_ship):
		failures.append("support fleet smoke support ship missing from support registry bucket")
	if EntityRegistry.get_legacy_captured_ships().has(support_ship):
		failures.append("support fleet smoke support ship should not enter legacy captured registry bucket")
	if PlayerFleetRoleHelper.count_capture_slot_ships(EntityRegistry.get_legacy_captured_ships()) != capture_slots_before:
		failures.append("support fleet smoke support ship should not consume capture slots")

	_run_support_shared_cannon_cap_smoke(failures, support_ship)
	_run_support_shared_hull_upgrade_smoke(failures, support_ship)

	var target_ship: Node3D = null
	if support_ship.has_method("get_target_ship"):
		target_ship = support_ship.get_target_ship()
	else:
		var target_variant: Variant = support_ship.get("target")
		if is_instance_valid(target_variant):
			target_ship = target_variant
	if target_ship != player_ship:
		failures.append("support fleet smoke support ship target mismatch")

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if is_instance_valid(spawner) and spawner.has_method("debug_spawn_ship"):
		support_ship.set("target", player_ship)
		support_ship.set_meta("support_joining", false)
		var player_forward: Vector3 = -player_ship.global_transform.basis.z
		player_forward.y = 0.0
		if player_forward.length_squared() <= 0.001:
			player_forward = Vector3.FORWARD
		else:
			player_forward = player_forward.normalized()
		support_ship.global_position = player_ship.global_position - player_forward * 14.0
		support_ship.global_position.y = 0.0
		var threat_a: Node3D = spawner.call("debug_spawn_ship", "kobayabune_melee", 16.0, -7.0) as Node3D
		var threat_b: Node3D = spawner.call("debug_spawn_ship", "sekibune_melee", 18.0, 7.0) as Node3D
		for threat in [threat_a, threat_b]:
			if is_instance_valid(threat):
				if "current_speed" in threat:
					threat.set("current_speed", 0.0)
				if "_last_ai_speed" in threat:
					threat.set("_last_ai_speed", 0.0)
		await _wait_frames(owner, wait_frames_after_spawn + 4)
		if support_ship.get_meta("support_debug_mode", "") != "assist":
			failures.append("support fleet smoke support ship did not enter assist engagement mode")
		await _run_support_rescue_emergency_smoke(owner, failures, player_ship, support_ship, spawner, wait_frames_after_spawn)
		await _run_support_boss_breach_smoke(owner, failures, player_ship, support_ship, spawner, wait_frames_after_spawn)
		await _run_support_boss_breach_smoke(owner, failures, player_ship, support_ship, spawner, wait_frames_after_spawn, true)
		await _run_legacy_capture_guard_smoke(owner, failures, player_ship, spawner, wait_frames_after_spawn)

	var support_before_idle_pos: Vector3 = support_ship.global_position
	support_ship.set("target", null)
	await _wait_frames(owner, wait_frames_after_spawn + 2)
	var support_idle_distance: float = support_ship.global_position.distance_to(support_before_idle_pos)
	if support_idle_distance <= 0.1:
		failures.append("support fleet smoke support ship did not keep moving after target loss")
	if support_ship.get_meta("support_debug_lead_name", "") != "anchor":
		failures.append("support fleet smoke support ship did not enter anchor idle mode after target loss")

	var repair_before: float = 0.0
	if support_ship.get("hull_hp") != null and support_ship.get("max_hull_hp") != null:
		var max_hull_hp: float = float(support_ship.get("max_hull_hp"))
		repair_before = max_hull_hp * 0.2
		support_ship.set("hull_hp", repair_before)

	_request_support_spawn(player_ship, failures, "support_contract_repair")
	await _wait_frames(owner, 1)

	var support_ships_after: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships_after.size() != 1:
		failures.append("support fleet smoke limit gate failed, got %d support ships" % support_ships_after.size())
	if support_ship.get("hull_hp") != null and float(support_ship.get("hull_hp")) <= repair_before:
		failures.append("support fleet smoke repair path did not heal support ship")

	await _run_support_panokseon_upgrade_smoke(owner, failures, player_ship, wait_frames_after_spawn)
	await _run_support_signal_level_two_limit_smoke(owner, failures, player_ship, wait_frames_after_spawn)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_support_wing_join_geometry_contract(failures: Array[String], smoke_root: Node, player_ship: Node3D) -> void:
	var previous_formation := SupportFleetStateHelper.get_flagship_formation(player_ship)
	SupportFleetStateHelper.set_flagship_formation(player_ship, SupportFleetStateHelper.FORMATION_WING)

	var extra_support := Node3D.new()
	extra_support.name = "WingExtraSupportGeometryContract"
	extra_support.set_meta("support_squadron_slot_role", "screen_extra_7")
	smoke_root.add_child(extra_support)
	extra_support.global_position = player_ship.global_position + Vector3(44.0, 0.0, 44.0)
	SupportFleetStateHelper.assign_support_ship_to_flagship(extra_support, player_ship)

	var screen_lead := Node3D.new()
	screen_lead.name = "WingScreenLeadGeometryContract"
	screen_lead.set_meta("support_squadron_slot_role", "screen_lead")
	smoke_root.add_child(screen_lead)
	SupportFleetStateHelper.assign_support_ship_to_flagship(screen_lead, player_ship)
	var screen_flank := Node3D.new()
	screen_flank.name = "WingScreenFlankGeometryContract"
	screen_flank.set_meta("support_squadron_slot_role", "screen_flank")
	smoke_root.add_child(screen_flank)
	SupportFleetStateHelper.assign_support_ship_to_flagship(screen_flank, player_ship)
	var screen_lead_offset := SupportFleetFormationHelper.get_support_fleet_offset(screen_lead, 0, 10.0, 2)
	var screen_flank_offset := SupportFleetFormationHelper.get_support_fleet_offset(screen_flank, 1, 10.0, 2)
	if screen_lead_offset.x * screen_flank_offset.x >= 0.0:
		failures.append("support fleet smoke wing screen pair should split to opposite sides")
	if screen_lead_offset.z >= -0.1 or screen_flank_offset.z >= -0.1:
		failures.append("support fleet smoke wing screen pair should stage ahead of the flagship")
	if absf(screen_lead_offset.x) <= absf(screen_lead_offset.z) or absf(screen_flank_offset.x) <= absf(screen_flank_offset.z):
		failures.append("support fleet smoke wing screen pair should read as forward side screens, not rear chevrons")
	var artillery_lead := Node3D.new()
	artillery_lead.name = "EscortArtilleryLeadGeometryContract"
	artillery_lead.set_meta("support_squadron_slot_role", "artillery_lead")
	smoke_root.add_child(artillery_lead)
	SupportFleetStateHelper.assign_support_ship_to_flagship(artillery_lead, player_ship)
	var artillery_lead_offset := SupportFleetFormationHelper.get_support_fleet_offset(artillery_lead, 1, 10.0, 5)
	if absf(artillery_lead_offset.x) > 0.1:
		failures.append("support fleet smoke escort artillery lead should hold the rear center lane")
	if artillery_lead_offset.z <= screen_lead_offset.z:
		failures.append("support fleet smoke escort artillery lead should trail behind side screen ships")
	var armored_guard := Node3D.new()
	armored_guard.name = "EscortArmoredGuardGeometryContract"
	armored_guard.set_meta("support_squadron_slot_role", "armored_guard")
	smoke_root.add_child(armored_guard)
	SupportFleetStateHelper.assign_support_ship_to_flagship(armored_guard, player_ship)
	var armored_guard_offset := SupportFleetFormationHelper.get_support_fleet_offset(armored_guard, 2, 10.0, 5)
	if absf(armored_guard_offset.x) > 0.1:
		failures.append("support fleet smoke geobukseon guard should hold the rear center lane like panokseon")
	if armored_guard_offset.z <= artillery_lead_offset.z:
		failures.append("support fleet smoke geobukseon guard should trail behind the panokseon lane instead of fighting screen ships")
	var artillery_front_left := Node3D.new()
	artillery_front_left.name = "EscortArtilleryFrontLeftGeometryContract"
	artillery_front_left.set_meta("support_squadron_slot_role", "artillery_screen_front_left")
	smoke_root.add_child(artillery_front_left)
	SupportFleetStateHelper.assign_support_ship_to_flagship(artillery_front_left, player_ship)
	var artillery_front_right := Node3D.new()
	artillery_front_right.name = "EscortArtilleryFrontRightGeometryContract"
	artillery_front_right.set_meta("support_squadron_slot_role", "artillery_screen_front_right")
	smoke_root.add_child(artillery_front_right)
	SupportFleetStateHelper.assign_support_ship_to_flagship(artillery_front_right, player_ship)
	var artillery_rear_left := Node3D.new()
	artillery_rear_left.name = "EscortArtilleryRearLeftGeometryContract"
	artillery_rear_left.set_meta("support_squadron_slot_role", "artillery_screen_rear_left")
	smoke_root.add_child(artillery_rear_left)
	SupportFleetStateHelper.assign_support_ship_to_flagship(artillery_rear_left, player_ship)
	var artillery_rear_right := Node3D.new()
	artillery_rear_right.name = "EscortArtilleryRearRightGeometryContract"
	artillery_rear_right.set_meta("support_squadron_slot_role", "artillery_screen_rear_right")
	smoke_root.add_child(artillery_rear_right)
	SupportFleetStateHelper.assign_support_ship_to_flagship(artillery_rear_right, player_ship)
	var artillery_front_left_offset := SupportFleetFormationHelper.get_support_fleet_offset(artillery_front_left, 2, 10.0, 6)
	var artillery_front_right_offset := SupportFleetFormationHelper.get_support_fleet_offset(artillery_front_right, 3, 10.0, 6)
	var artillery_rear_left_offset := SupportFleetFormationHelper.get_support_fleet_offset(artillery_rear_left, 4, 10.0, 6)
	var artillery_rear_right_offset := SupportFleetFormationHelper.get_support_fleet_offset(artillery_rear_right, 5, 10.0, 6)
	if artillery_front_left_offset.x * artillery_front_right_offset.x >= 0.0:
		failures.append("support fleet smoke panokseon front screens should split to opposite sides")
	if artillery_rear_left_offset.x * artillery_rear_right_offset.x >= 0.0:
		failures.append("support fleet smoke panokseon rear screens should split to opposite sides")
	if artillery_front_left_offset.z >= 0.0 or artillery_front_right_offset.z >= 0.0:
		failures.append("support fleet smoke panokseon front screens should stage forward of the support panokseon")
	if artillery_rear_left_offset.z <= 0.0 or artillery_rear_right_offset.z <= 0.0:
		failures.append("support fleet smoke panokseon rear screens should trail behind the support panokseon")

	var extra_offset := SupportFleetFormationHelper.get_support_fleet_offset(extra_support, 5, 10.0, 7)
	if absf(extra_offset.x) < 0.1:
		failures.append("support fleet smoke wing extra support role collapsed to center instead of generic wing lane")
	var late_extra_offset := SupportFleetFormationHelper.get_support_fleet_offset(extra_support, 19, 10.0, 20)
	if absf(late_extra_offset.x) <= absf(extra_offset.x):
		failures.append("support fleet smoke generated wing lanes did not expand for later support slots")
	if late_extra_offset.z <= extra_offset.z:
		failures.append("support fleet smoke generated wing lanes did not trail deeper for later support slots")
	var generated_pair_left := SupportFleetFormationHelper.get_support_fleet_offset(extra_support, 8, 10.0, 20)
	var generated_pair_right := SupportFleetFormationHelper.get_support_fleet_offset(extra_support, 9, 10.0, 20)
	if generated_pair_left.x * generated_pair_right.x >= 0.0:
		failures.append("support fleet smoke generated wing pair did not alternate sides")

	var player_forward: Vector3 = -player_ship.global_transform.basis.z
	player_forward.y = 0.0
	player_forward = player_forward.normalized() if player_forward.length_squared() > 0.001 else Vector3.FORWARD
	var player_right := player_forward.cross(Vector3.UP)
	player_right = player_right.normalized() if player_right.length_squared() > 0.001 else Vector3.RIGHT

	var join_goal := SupportFleetFormationHelper.get_support_join_chain_goal(extra_support, [extra_support], 5, 14.0)
	var join_position: Vector3 = join_goal.get("position", extra_support.global_position)
	var join_offset := join_position - player_ship.global_position
	join_offset.y = 0.0
	if absf(join_offset.dot(player_right)) > 0.5:
		failures.append("support fleet smoke wing join goal should stage on column centerline before spreading")
	if join_offset.dot(player_forward) > -10.0:
		failures.append("support fleet smoke wing join goal should stage behind flagship before spreading")

	SupportFleetStateHelper.set_flagship_formation(player_ship, previous_formation)
	screen_lead.queue_free()
	screen_flank.queue_free()
	artillery_lead.queue_free()
	armored_guard.queue_free()
	extra_support.queue_free()


static func _run_support_rescue_emergency_smoke(owner: Node, failures: Array[String], player_ship: Node3D, support_ship: Node3D, spawner: Node, wait_frames_after_spawn: int) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(player_ship) or not is_instance_valid(support_ship) or not is_instance_valid(spawner):
		return
	var rescue_threat := spawner.call("debug_spawn_ship", "kobayabune_melee", 10.0, 0.0) as Node3D
	await _wait_frames(owner, wait_frames_after_spawn)
	if not is_instance_valid(rescue_threat):
		failures.append("support fleet smoke rescue threat spawn failed")
		return
	var player_forward: Vector3 = -player_ship.global_transform.basis.z
	player_forward.y = 0.0
	player_forward = player_forward.normalized() if player_forward.length_squared() > 0.001 else Vector3.FORWARD
	player_ship.set("deck_is_contested", true)
	player_ship.set("deck_is_overrun", true)
	player_ship.set("deck_hostile_boarder_count", 3)
	rescue_threat.global_position = player_ship.global_position + player_forward * 9.0
	if "boarding_target" in rescue_threat:
		rescue_threat.set("boarding_target", player_ship)
	if "current_speed" in rescue_threat:
		rescue_threat.set("current_speed", 0.0)
	if "_last_ai_speed" in rescue_threat:
		rescue_threat.set("_last_ai_speed", 0.0)
	if support_ship.has_method("_cancel_boarding"):
		support_ship.call("_cancel_boarding")
	var rescue_contact_distance: float = float(support_ship.call("get_collision_distance_to", player_ship)) if support_ship.has_method("get_collision_distance_to") else 8.0
	support_ship.set("target", player_ship)
	support_ship.set_meta("support_joining", false)
	support_ship.global_position = player_ship.global_position - player_forward * maxf(10.4, rescue_contact_distance + 1.9)
	support_ship.global_position.y = 0.0
	var rescue_start_position: Vector3 = support_ship.global_position
	var rescue_start_distance: float = support_ship.global_position.distance_to(player_ship.global_position)
	await _wait_frames(owner, wait_frames_after_spawn + 8)
	var rescue_mode := str(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_MODE, "")).strip_edges()
	if rescue_mode != ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP:
		failures.append("support fleet smoke support ship did not enter rescue mode during flagship deck emergency")
	var rescue_target_id := int(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, 0))
	if rescue_target_id != player_ship.get_instance_id():
		failures.append("support fleet smoke support ship rescue target mismatch")
	var rescue_reason := str(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_REASON, "")).strip_edges()
	if not rescue_reason.begins_with("flagship_deck_emergency"):
		failures.append("support fleet smoke support ship rescue reason mismatch: %s" % rescue_reason)
	var rescue_boarding: bool = support_ship.get("is_boarding") == true and support_ship.get("boarding_target") == player_ship
	if not rescue_boarding and str(support_ship.get_meta("support_debug_mode", "")) != "boarding":
		failures.append("support fleet smoke support ship did not commit to rescue boarding")
	var rescue_end_distance: float = support_ship.global_position.distance_to(player_ship.global_position)
	var rescue_travel_distance: float = support_ship.global_position.distance_to(rescue_start_position)
	if not rescue_boarding:
		if rescue_travel_distance < 0.35:
			failures.append("support fleet smoke support ship did not move into rescue approach")
		elif rescue_end_distance >= rescue_start_distance - 0.2:
			failures.append("support fleet smoke support ship did not close rescue distance")
	player_ship.set("deck_is_contested", false)
	player_ship.set("deck_is_overrun", false)
	player_ship.set("deck_hostile_boarder_count", 0)
	if support_ship.has_method("_cancel_boarding"):
		support_ship.call("_cancel_boarding")
	EntityRegistry.unregister_ship(rescue_threat)
	rescue_threat.queue_free()
	await _wait_frames(owner, 1)


static func _run_support_boss_breach_smoke(owner: Node, failures: Array[String], player_ship: Node3D, support_ship: Node3D, spawner: Node, wait_frames_after_spawn: int, use_manual_boarding_intent: bool = false) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(player_ship) or not is_instance_valid(support_ship) or not is_instance_valid(spawner):
		return
	SupportFleetStateHelper.set_flagship_hold_enabled(player_ship, false)
	if not spawner.has_method("debug_spawn_final_boss"):
		failures.append("support fleet smoke boss breach missing debug_spawn_final_boss")
		return
	var boss_ship := spawner.call("debug_spawn_final_boss") as Node3D
	await _wait_frames(owner, wait_frames_after_spawn + 3)
	if not is_instance_valid(boss_ship):
		failures.append("support fleet smoke boss breach spawn failed")
		return
	var player_forward: Vector3 = -player_ship.global_transform.basis.z
	player_forward.y = 0.0
	player_forward = player_forward.normalized() if player_forward.length_squared() > 0.001 else Vector3.FORWARD
	var support_contact_distance: float = float(support_ship.call("get_collision_distance_to", boss_ship)) if support_ship.has_method("get_collision_distance_to") else 8.0
	if use_manual_boarding_intent:
		player_ship.set("manual_boarding_target", boss_ship)
		player_ship.set("boarding_target", null)
	else:
		player_ship.set("boarding_target", boss_ship)
		player_ship.set("manual_boarding_target", null)
	support_ship.set("target", player_ship)
	support_ship.set_meta("support_joining", false)
	boss_ship.global_position = player_ship.global_position + player_forward * 15.0
	boss_ship.global_position.y = 0.0
	support_ship.global_position = player_ship.global_position - player_forward * maxf(11.0, support_contact_distance + 2.0)
	support_ship.global_position.y = 0.0
	if "current_speed" in boss_ship:
		boss_ship.set("current_speed", 0.0)
	if "_last_ai_speed" in boss_ship:
		boss_ship.set("_last_ai_speed", 0.0)
	var breach_start_position: Vector3 = support_ship.global_position
	var breach_start_distance: float = support_ship.global_position.distance_to(boss_ship.global_position)
	await _wait_frames(owner, wait_frames_after_spawn + 10)
	var breach_mode := str(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_MODE, "")).strip_edges()
	if breach_mode == ShipAILimboKeys.SUPPORT_MODE_BREACH_BOSS:
		failures.append("support fleet smoke support ship should no longer enter boss breach mode")
	if not breach_mode.is_empty() and breach_mode != ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT:
		failures.append("support fleet smoke boss pressure should stay in threat-screening doctrine: %s" % breach_mode)
	var breach_reason := str(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_REASON, "")).strip_edges()
	if not breach_reason.is_empty() and breach_reason != "nearby_threat":
		failures.append("support fleet smoke boss pressure reason mismatch: %s" % breach_reason)
	var breach_boarding: bool = support_ship.get("is_boarding") == true and support_ship.get("boarding_target") == boss_ship
	var breach_end_distance: float = support_ship.global_position.distance_to(boss_ship.global_position)
	var breach_travel_distance: float = support_ship.global_position.distance_to(breach_start_position)
	if breach_boarding:
		failures.append("support fleet smoke support ship should not board the boss under artillery doctrine")
	elif breach_travel_distance < 0.35:
		failures.append("support fleet smoke support ship did not react to nearby boss pressure")
	elif breach_end_distance >= breach_start_distance - 0.2:
		failures.append("support fleet smoke support ship did not close boss screening distance")
	player_ship.set("boarding_target", null)
	player_ship.set("manual_boarding_target", null)
	SupportFleetStateHelper.set_flagship_hold_enabled(player_ship, true)
	if support_ship.has_method("_cancel_boarding"):
		support_ship.call("_cancel_boarding")
	EntityRegistry.unregister_ship(boss_ship)
	boss_ship.queue_free()
	await _wait_frames(owner, 1)


static func _run_legacy_capture_guard_smoke(owner: Node, failures: Array[String], player_ship: Node3D, spawner: Node, wait_frames_after_spawn: int) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(player_ship) or not is_instance_valid(spawner):
		return
	var captured_ship := spawner.call("debug_spawn_ship", "kobayabune_melee", 20.0, -12.0) as Node3D
	await _wait_frames(owner, wait_frames_after_spawn)
	if not is_instance_valid(captured_ship):
		failures.append("support fleet smoke legacy captured ship spawn failed")
		return
	if not captured_ship.has_method("capture_ship"):
		failures.append("support fleet smoke legacy captured ship missing capture_ship")
		EntityRegistry.unregister_ship(captured_ship)
		captured_ship.queue_free()
		await _wait_frames(owner, 1)
		return
	captured_ship.call("capture_ship")
	await _wait_frames(owner, wait_frames_after_spawn + 2)
	var guard_threat := spawner.call("debug_spawn_ship", "kobayabune_melee", 12.0, 0.0) as Node3D
	await _wait_frames(owner, wait_frames_after_spawn)
	if not is_instance_valid(guard_threat):
		failures.append("support fleet smoke guard threat spawn failed")
		EntityRegistry.unregister_legacy_captured_ship(captured_ship)
		EntityRegistry.unregister_ship(captured_ship)
		captured_ship.queue_free()
		await _wait_frames(owner, 1)
		return
	var player_forward: Vector3 = -player_ship.global_transform.basis.z
	player_forward.y = 0.0
	player_forward = player_forward.normalized() if player_forward.length_squared() > 0.001 else Vector3.FORWARD
	captured_ship.global_position = player_ship.global_position - player_forward * 12.0
	captured_ship.global_position.y = 0.0
	var captured_start_position: Vector3 = captured_ship.global_position
	var captured_start_forward_offset: float = (captured_start_position - player_ship.global_position).dot(player_forward)
	captured_ship.set("target", player_ship)
	guard_threat.global_position = player_ship.global_position + player_forward * 10.0
	var guard_start_distance: float = captured_ship.global_position.distance_to(guard_threat.global_position)
	if "boarding_target" in guard_threat:
		guard_threat.set("boarding_target", player_ship)
	if "current_speed" in guard_threat:
		guard_threat.set("current_speed", 0.0)
	if "_last_ai_speed" in guard_threat:
		guard_threat.set("_last_ai_speed", 0.0)
	await _wait_frames(owner, wait_frames_after_spawn + 6)
	if captured_ship.get("limbo_ai_pilot_enabled") != true:
		failures.append("support fleet smoke legacy captured ship did not enable LimboAI after capture")
	var legacy_capture_mode := str(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_MODE, "")).strip_edges()
	if legacy_capture_mode != ShipAILimboKeys.ALLY_MODE_GUARD_THREAT:
		failures.append("support fleet smoke legacy captured ship did not enter guard threat mode")
	var legacy_capture_target_id := int(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_TARGET_ID, 0))
	if legacy_capture_target_id != guard_threat.get_instance_id():
		failures.append("support fleet smoke legacy captured ship guard target mismatch")
	var legacy_capture_reason := str(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_REASON, "")).strip_edges()
	if legacy_capture_reason != "flagship_boarder":
		failures.append("support fleet smoke legacy captured ship guard reason mismatch: %s" % legacy_capture_reason)
	var captured_end_forward_offset: float = (captured_ship.global_position - player_ship.global_position).dot(player_forward)
	var captured_travel_distance: float = captured_ship.global_position.distance_to(captured_start_position)
	var guard_end_distance: float = captured_ship.global_position.distance_to(guard_threat.global_position)
	if captured_travel_distance < 0.35:
		failures.append("support fleet smoke legacy captured ship did not move to intercept threat")
	elif captured_end_forward_offset <= captured_start_forward_offset + 0.45 and guard_end_distance >= guard_start_distance - 0.2:
		failures.append("support fleet smoke legacy captured ship did not advance toward flagship boarder")
	EntityRegistry.unregister_ship(guard_threat)
	guard_threat.queue_free()
	EntityRegistry.unregister_legacy_captured_ship(captured_ship)
	EntityRegistry.unregister_ship(captured_ship)
	captured_ship.queue_free()
	await _wait_frames(owner, 1)


static func _run_support_panokseon_upgrade_smoke(owner: Node, failures: Array[String], player_ship: Node3D, wait_frames_after_spawn: int) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("support fleet smoke missing UpgradeManager for panokseon upgrade")
		return

	var original_signal_level: int = int(UpgradeManager.current_levels.get("fleet_signal", 0))
	var original_panokseon_level: int = int(UpgradeManager.current_levels.get("panokseon_upgrade", 0))
	var original_crew_level: int = int(UpgradeManager.current_levels.get("fleet_crew", 0))
	var original_cannon_level: int = int(UpgradeManager.current_levels.get("cannon", 0))
	UpgradeManager.current_levels["fleet_signal"] = 0
	UpgradeManager.current_levels["panokseon_upgrade"] = 1
	UpgradeManager.current_levels["fleet_crew"] = 0
	UpgradeManager.current_levels["cannon"] = 5
	_reconcile_support_fleet(player_ship, failures, "support_contract_panokseon_upgrade")
	await _wait_frames(owner, wait_frames_after_spawn + 2)

	var upgraded_supports: Array = player_ship.call("_get_support_fleet_ships")
	if upgraded_supports.size() != 1:
		failures.append("support fleet smoke panokseon upgrade should work without fleet_signal and keep one support ship")
	else:
		var panokseon_support := upgraded_supports[0] as Node3D
		if not is_instance_valid(panokseon_support):
			failures.append("support fleet smoke panokseon upgrade added panokseon invalid")
		else:
			if int(panokseon_support.get_meta("support_fleet_slot_index", -1)) != 0:
				failures.append("support fleet smoke panokseon upgrade should add panokseon in slot 0 without fleet_signal")
			elif str(panokseon_support.get("ship_type")) != "panokseon_ally":
				failures.append("support fleet smoke panokseon upgrade should add a panokseon support ship without fleet_signal")
			elif panokseon_support.scene_file_path != "res://scenes/ships/support_panokseon_ship.tscn":
				failures.append("support fleet smoke panokseon upgrade should spawn the dedicated panokseon support scene")
			elif str(panokseon_support.get_meta("support_fleet_profile", "")) != "panokseon_escort":
				failures.append("support fleet smoke panokseon upgrade profile mismatch")
			UpgradeManager.apply_fleet_upgrades_to_ship(panokseon_support)
			if _count_visible_fleet_cannons(panokseon_support) != 5:
				failures.append("support fleet smoke panokseon upgrade should expose 5 shared cannons on the added panokseon at cannon Lv.5")

	UpgradeManager.current_levels["fleet_signal"] = original_signal_level
	UpgradeManager.current_levels["panokseon_upgrade"] = original_panokseon_level
	UpgradeManager.current_levels["fleet_crew"] = original_crew_level
	UpgradeManager.current_levels["cannon"] = original_cannon_level
	_reconcile_support_fleet(player_ship, failures, "support_contract_panokseon_restore")


static func _run_support_signal_level_two_limit_smoke(owner: Node, failures: Array[String], player_ship: Node3D, wait_frames_after_spawn: int) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("support fleet smoke missing UpgradeManager for signal level 2")
		return

	var original_signal_level: int = int(UpgradeManager.current_levels.get("fleet_signal", 0))
	var original_panokseon_level: int = int(UpgradeManager.current_levels.get("panokseon_upgrade", 0))
	var original_crew_level: int = int(UpgradeManager.current_levels.get("fleet_crew", 0))
	UpgradeManager.current_levels["fleet_signal"] = 2
	UpgradeManager.current_levels["panokseon_upgrade"] = 0
	UpgradeManager.current_levels["fleet_crew"] = 0
	_reconcile_support_fleet(player_ship, failures, "support_contract_signal_level_two")
	await _wait_frames(owner, 2)

	if int(player_ship.get("support_fleet_limit")) < 2:
		failures.append("support fleet smoke signal Lv2 did not increase support limit")

	_request_support_spawn(player_ship, failures, "support_contract_signal_level_two_spawn")
	await _wait_frames(owner, wait_frames_after_spawn + 2)
	var support_ships: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships.size() < 2:
		failures.append("support fleet smoke signal Lv2 did not spawn second support ship")
	else:
		var lead_support := support_ships[0] as Node3D
		var second_support := support_ships[1] as Node3D
		if not is_instance_valid(lead_support):
			failures.append("support fleet smoke signal Lv2 lead support ship invalid")
		elif int(lead_support.get_meta("support_fleet_slot_index", -1)) != 0:
			failures.append("support fleet smoke signal Lv2 lead support should keep slot 0")
		elif str(lead_support.get("ship_type")) != "maengseon_ally":
			failures.append("support fleet smoke signal Lv2 lead support should remain maengseon without panokseon upgrade")
		if not is_instance_valid(second_support):
			failures.append("support fleet smoke signal Lv2 second support ship invalid")
		elif int(second_support.get_meta("support_fleet_slot_index", -1)) != 1:
			failures.append("support fleet smoke signal Lv2 second support should keep slot 1")
		elif str(second_support.get("ship_type")) != "maengseon_ally":
			failures.append("support fleet smoke signal Lv2 second support ship should remain maengseon")
		elif str(second_support.get_meta("support_fleet_profile", "")) != "maengseon_screen":
			failures.append("support fleet smoke signal Lv2 second support ship profile mismatch")

		if is_instance_valid(lead_support):
			EntityRegistry.unregister_support_ship(lead_support)
			EntityRegistry.unregister_ship(lead_support)
			lead_support.queue_free()
			await _wait_frames(owner, 2)
			_reconcile_support_fleet(player_ship, failures, "support_contract_slot_stability_refresh")
			await _wait_frames(owner, 2)

			var remaining_supports: Array = player_ship.call("_get_support_fleet_ships")
			if remaining_supports.size() != 1:
				failures.append("support fleet smoke slot stability expected 1 surviving support ship, got %d" % remaining_supports.size())
			else:
				var remaining_support := remaining_supports[0] as Node3D
				if not is_instance_valid(remaining_support):
					failures.append("support fleet smoke slot stability surviving support invalid")
				elif int(remaining_support.get_meta("support_fleet_slot_index", -1)) != 1:
					failures.append("support fleet smoke slot stability should preserve the surviving support slot id")
				elif str(remaining_support.get("ship_type")) != "maengseon_ally":
					failures.append("support fleet smoke slot stability should keep the surviving screen ship as maengseon")

			_request_support_spawn(player_ship, failures, "support_contract_slot_stability_refill")
			await _wait_frames(owner, wait_frames_after_spawn + 2)
			var restored_supports: Array = player_ship.call("_get_support_fleet_ships")
			if restored_supports.size() < 2:
				failures.append("support fleet smoke slot stability did not refill the vacated lead slot")
			else:
				var restored_lead := restored_supports[0] as Node3D
				var restored_screen := restored_supports[1] as Node3D
				if not is_instance_valid(restored_lead):
					failures.append("support fleet smoke slot stability restored lead invalid")
				elif int(restored_lead.get_meta("support_fleet_slot_index", -1)) != 0:
					failures.append("support fleet smoke slot stability restored lead should reclaim slot 0")
				elif str(restored_lead.get("ship_type")) != "maengseon_ally":
					failures.append("support fleet smoke slot stability restored lead should respawn as maengseon")
				if not is_instance_valid(restored_screen):
					failures.append("support fleet smoke slot stability restored screen invalid")
				elif int(restored_screen.get_meta("support_fleet_slot_index", -1)) != 1:
					failures.append("support fleet smoke slot stability restored screen should remain in slot 1")
				elif str(restored_screen.get("ship_type")) != "maengseon_ally":
					failures.append("support fleet smoke slot stability restored screen should remain maengseon")

		UpgradeManager.current_levels["panokseon_upgrade"] = 1
		_reconcile_support_fleet(player_ship, failures, "support_contract_signal_plus_panokseon")
		await _wait_frames(owner, wait_frames_after_spawn + 2)
		var panokseon_supports: Array = player_ship.call("_get_support_fleet_ships")
		if panokseon_supports.size() < 3:
			failures.append("support fleet smoke panokseon upgrade after two maengseon supports should add a third ship")
		else:
			var slot_zero := panokseon_supports[0] as Node3D
			var slot_one := panokseon_supports[1] as Node3D
			var slot_two := panokseon_supports[2] as Node3D
			if not is_instance_valid(slot_zero) or int(slot_zero.get_meta("support_fleet_slot_index", -1)) != 0 or str(slot_zero.get("ship_type")) != "maengseon_ally":
				failures.append("support fleet smoke panokseon unlock should preserve maengseon at slot 0")
			if not is_instance_valid(slot_one) or int(slot_one.get_meta("support_fleet_slot_index", -1)) != 1 or str(slot_one.get("ship_type")) != "panokseon_ally":
				failures.append("support fleet smoke panokseon unlock should insert a new panokseon at slot 1")
			if not is_instance_valid(slot_two) or int(slot_two.get_meta("support_fleet_slot_index", -1)) != 2 or str(slot_two.get("ship_type")) != "maengseon_ally":
				failures.append("support fleet smoke panokseon unlock should preserve existing maengseon by shifting it to slot 2")
			if is_instance_valid(slot_one):
				await _run_support_panokseon_mast_fold_sync_contract(owner, failures, player_ship, slot_one)

	UpgradeManager.current_levels["fleet_signal"] = original_signal_level
	UpgradeManager.current_levels["panokseon_upgrade"] = original_panokseon_level
	UpgradeManager.current_levels["fleet_crew"] = original_crew_level
	_reconcile_support_fleet(player_ship, failures, "support_contract_signal_level_two_restore")


static func _run_support_shared_cannon_cap_smoke(failures: Array[String], support_ship: Node3D) -> void:
	if not is_instance_valid(support_ship):
		return
	if not is_instance_valid(UpgradeManager):
		failures.append("support fleet smoke missing UpgradeManager for shared cannon cap")
		return
	if not support_ship.has_method("apply_fleet_weapon_upgrade"):
		failures.append("support fleet smoke support ship missing apply_fleet_weapon_upgrade")
		return

	var original_cannon_level: int = int(UpgradeManager.current_levels.get("cannon", 0))
	for level in [1, 2, 3, 4, 5]:
		UpgradeManager.current_levels["cannon"] = level
		UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)
		var visible_count := _count_visible_fleet_cannons(support_ship)
		var expected_count := SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type(str(support_ship.get("ship_type")), level).size()
		if visible_count != expected_count:
			failures.append("support fleet smoke shared cannon cap mismatch Lv.%d: %d != %d" % [level, visible_count, expected_count])
	UpgradeManager.current_levels["cannon"] = original_cannon_level
	UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)


static func _run_support_shared_hull_upgrade_smoke(failures: Array[String], support_ship: Node3D) -> void:
	if not is_instance_valid(support_ship):
		return
	if not is_instance_valid(UpgradeManager):
		failures.append("support fleet smoke missing UpgradeManager for shared hull upgrade")
		return
	if "fleet_hull" in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS:
		failures.append("support fleet smoke fleet_hull should not be offered as support ship upgrade")
	if "fleet_hull" in UpgradeManager.ACTIVE_SUPPORT_UPGRADE_IDS:
		failures.append("support fleet smoke fleet_hull should not be an active support upgrade")

	var original_hull_level: int = int(UpgradeManager.current_levels.get("hull_defense", 0))
	var original_hull_structure_level: int = int(UpgradeManager.current_levels.get("hull", 0))
	UpgradeManager.current_levels["hull"] = 0
	UpgradeManager.current_levels["hull_defense"] = 0
	UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)
	var base_max_hp: float = float(support_ship.get("max_hull_hp")) if support_ship.get("max_hull_hp") != null else 0.0
	var base_defense: float = float(support_ship.get("hull_defense")) if support_ship.get("hull_defense") != null else 0.0

	if support_ship.get("hull_hp") != null and support_ship.get("max_hull_hp") != null:
		support_ship.set("hull_hp", maxf(1.0, base_max_hp - 100.0))

	UpgradeManager.current_levels["hull_defense"] = 4
	UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)
	var upgraded_max_hp: float = float(support_ship.get("max_hull_hp")) if support_ship.get("max_hull_hp") != null else 0.0
	var upgraded_defense: float = float(support_ship.get("hull_defense")) if support_ship.get("hull_defense") != null else 0.0
	if absf(upgraded_max_hp - base_max_hp) > 0.01:
		failures.append("support fleet smoke shared hull upgrade should not add separate support max HP")
	if upgraded_defense < base_defense + 3.9:
		failures.append("support fleet smoke shared hull upgrade did not apply hull_defense levels")
	if support_ship.get("hull_hp") != null and float(support_ship.get("hull_hp")) <= maxf(1.0, base_max_hp - 100.0):
		failures.append("support fleet smoke shared hull repair level did not heal support ship")

	UpgradeManager.current_levels["hull_defense"] = 5
	UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)
	if support_ship.get("hull_regen_rate") != null and float(support_ship.get("hull_regen_rate")) < 1.4:
		failures.append("support fleet smoke shared hull upgrade did not apply regen level")

	UpgradeManager.current_levels["hull_defense"] = original_hull_level
	UpgradeManager.current_levels["hull"] = original_hull_structure_level
	UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)


static func _run_support_panokseon_mast_fold_sync_contract(owner: Node, failures: Array[String], flagship: Node3D, support_ship: Node3D) -> void:
	if not is_instance_valid(flagship) or not is_instance_valid(support_ship):
		return
	if not support_ship.has_method("sync_sail_furl_with_flagship"):
		failures.append("support panokseon mast fold sync missing sail sync method")
		return
	if not support_ship.has_method("are_masts_folded") or not support_ship.has_method("get_mast_fold_ratio"):
		failures.append("support panokseon mast fold sync missing mast fold methods")
		return
	var fold_pivots: Array = support_ship.get("mast_fold_pivots") if support_ship.get("mast_fold_pivots") != null else []
	if fold_pivots.is_empty():
		failures.append("support panokseon should expose mast fold pivots")
		return

	flagship.call("set_sail_furled", true)
	support_ship.call("sync_sail_furl_with_flagship", 999.0)
	if support_ship.get("sail_furled") != true:
		failures.append("support panokseon should inherit furled sail state before mast fold")
	if float(support_ship.get("sail_deployed_ratio")) > 0.001:
		failures.append("support panokseon should lower sails before folding masts")
	if not bool(support_ship.call("are_masts_folded")):
		failures.append("support panokseon should fold masts after sails are lowered")

	await _wait_frames(owner, 4)
	if float(support_ship.call("get_mast_fold_ratio")) <= 0.001:
		failures.append("support panokseon mast fold pivots should animate after fold command")

	flagship.call("set_sail_furled", false)
	support_ship.call("sync_sail_furl_with_flagship", 0.1)
	if bool(support_ship.call("are_masts_folded")):
		failures.append("support panokseon should start unfolding masts before raising sails")
	if float(support_ship.get("sail_deployed_ratio")) > 0.001 and float(support_ship.call("get_mast_fold_ratio")) > 0.001:
		failures.append("support panokseon should keep sails down while masts are still folding")

	support_ship.call("sync_sail_furl_with_flagship", 0.0, true)


static func _count_visible_fleet_cannons(ship: Node) -> int:
	var count := 0
	for child in ship.get_children():
		if not is_instance_valid(child):
			continue
		if not str(child.name).begins_with("FleetCannon_"):
			continue
		if child is Node3D and (child as Node3D).visible:
			count += 1
	return count


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
