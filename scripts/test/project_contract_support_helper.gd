extends RefCounted
class_name ProjectContractSupportHelper



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
	if not player_ship.has_method("_spawn_or_repair_ally") or not player_ship.has_method("_get_support_fleet_ships"):
		failures.append("support fleet smoke missing player ship support helpers")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	if "support_fleet_limit" in player_ship:
		player_ship.set("support_fleet_limit", 1)

	var captured_before: int = EntityRegistry.count_captured_minions()
	var capture_slots_before: int = ShipAllyRoleHelper.count_capture_slot_minions(EntityRegistry.get_captured_minions())
	player_ship.call("_spawn_or_repair_ally")
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
	if not player_ship.has_method("get_ally_ship_role") or str(player_ship.call("get_ally_ship_role")) != ShipAllyRoleHelper.ROLE_PLAYER_FLAGSHIP:
		failures.append("support fleet smoke player ship should be tagged as player_flagship")
	if not support_ship.has_method("get_ally_ship_role") or str(support_ship.call("get_ally_ship_role")) != ShipAllyRoleHelper.ROLE_SUPPORT_FLEET:
		failures.append("support fleet smoke support ship should be tagged as support_fleet")
	if ShipAllyRoleHelper.is_captured_minion(support_ship):
		failures.append("support fleet smoke support ship should not consume captured-minion role slots")
	if not support_ship.is_in_group("captured_minion"):
		failures.append("support fleet smoke missing captured_minion group")
	if support_ship.get_meta("support_fleet_ship", false) != true:
		failures.append("support fleet smoke missing support_fleet_ship meta")
	if EntityRegistry.count_captured_minions() <= captured_before:
		failures.append("support fleet smoke did not increase captured minion count")
	if not EntityRegistry.get_captured_minions().has(support_ship):
		failures.append("support fleet smoke support ship missing from registry bucket")
	if ShipAllyRoleHelper.count_capture_slot_minions(EntityRegistry.get_captured_minions()) != capture_slots_before:
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
		await _run_captured_minion_guard_smoke(owner, failures, player_ship, spawner, wait_frames_after_spawn)

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

	player_ship.call("_spawn_or_repair_ally")
	await _wait_frames(owner, 1)

	var support_ships_after: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships_after.size() != 1:
		failures.append("support fleet smoke limit gate failed, got %d support ships" % support_ships_after.size())
	if support_ship.get("hull_hp") != null and float(support_ship.get("hull_hp")) <= repair_before:
		failures.append("support fleet smoke repair path did not heal support ship")

	await _run_support_signal_level_two_limit_smoke(owner, failures, player_ship, wait_frames_after_spawn)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


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
	if breach_mode != ShipAILimboKeys.SUPPORT_MODE_BREACH_BOSS:
		failures.append("support fleet smoke support ship did not enter boss breach mode")
	var breach_target_id := int(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, 0))
	if breach_target_id != boss_ship.get_instance_id():
		failures.append("support fleet smoke support ship boss breach target mismatch")
	var breach_reason := str(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_REASON, "")).strip_edges()
	var expected_reason := "flagship_manual_boarding" if use_manual_boarding_intent else "flagship_boss_boarding"
	if breach_reason != expected_reason:
		failures.append("support fleet smoke support ship boss breach reason mismatch: %s" % breach_reason)
	var breach_boarding: bool = support_ship.get("is_boarding") == true and support_ship.get("boarding_target") == boss_ship
	var breach_end_distance: float = support_ship.global_position.distance_to(boss_ship.global_position)
	var breach_travel_distance: float = support_ship.global_position.distance_to(breach_start_position)
	if not breach_boarding:
		if breach_travel_distance < 0.35:
			failures.append("support fleet smoke support ship did not move into boss breach approach")
		elif breach_end_distance >= breach_start_distance - 0.2:
			failures.append("support fleet smoke support ship did not close boss breach distance")
	player_ship.set("boarding_target", null)
	player_ship.set("manual_boarding_target", null)
	if support_ship.has_method("_cancel_boarding"):
		support_ship.call("_cancel_boarding")
	EntityRegistry.unregister_ship(boss_ship)
	boss_ship.queue_free()
	await _wait_frames(owner, 1)


static func _run_captured_minion_guard_smoke(owner: Node, failures: Array[String], player_ship: Node3D, spawner: Node, wait_frames_after_spawn: int) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(player_ship) or not is_instance_valid(spawner):
		return
	var captured_ship := spawner.call("debug_spawn_ship", "kobayabune_melee", 20.0, -12.0) as Node3D
	await _wait_frames(owner, wait_frames_after_spawn)
	if not is_instance_valid(captured_ship):
		failures.append("support fleet smoke captured minion spawn failed")
		return
	if not captured_ship.has_method("capture_ship"):
		failures.append("support fleet smoke captured minion missing capture_ship")
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
		EntityRegistry.unregister_captured_minion(captured_ship)
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
		failures.append("support fleet smoke captured minion did not enable LimboAI after capture")
	var ally_mode := str(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_MODE, "")).strip_edges()
	if ally_mode != ShipAILimboKeys.ALLY_MODE_GUARD_THREAT:
		failures.append("support fleet smoke captured minion did not enter guard threat mode")
	var ally_target_id := int(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_TARGET_ID, 0))
	if ally_target_id != guard_threat.get_instance_id():
		failures.append("support fleet smoke captured minion guard target mismatch")
	var ally_reason := str(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_REASON, "")).strip_edges()
	if ally_reason != "flagship_boarder":
		failures.append("support fleet smoke captured minion guard reason mismatch: %s" % ally_reason)
	var captured_end_forward_offset: float = (captured_ship.global_position - player_ship.global_position).dot(player_forward)
	var captured_travel_distance: float = captured_ship.global_position.distance_to(captured_start_position)
	var guard_end_distance: float = captured_ship.global_position.distance_to(guard_threat.global_position)
	if captured_travel_distance < 0.35:
		failures.append("support fleet smoke captured minion did not move to intercept threat")
	elif captured_end_forward_offset <= captured_start_forward_offset + 0.45 and guard_end_distance >= guard_start_distance - 0.2:
		failures.append("support fleet smoke captured minion did not advance toward flagship boarder")
	EntityRegistry.unregister_ship(guard_threat)
	guard_threat.queue_free()
	EntityRegistry.unregister_captured_minion(captured_ship)
	EntityRegistry.unregister_ship(captured_ship)
	captured_ship.queue_free()
	await _wait_frames(owner, 1)


static func _run_support_signal_level_two_limit_smoke(owner: Node, failures: Array[String], player_ship: Node3D, wait_frames_after_spawn: int) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("support fleet smoke missing UpgradeManager for signal level 2")
		return
	if not UpgradeManager.has_method("_refresh_support_fleet_upgrade_state"):
		failures.append("support fleet smoke missing support fleet refresh helper")
		return

	var original_signal_level: int = int(UpgradeManager.current_levels.get("fleet_signal", 0))
	var original_crew_level: int = int(UpgradeManager.current_levels.get("fleet_crew", 0))
	UpgradeManager.current_levels["fleet_signal"] = 2
	UpgradeManager.current_levels["fleet_crew"] = 0
	UpgradeManager.call("_refresh_support_fleet_upgrade_state", player_ship)

	if int(player_ship.get("support_fleet_limit")) < 2:
		failures.append("support fleet smoke signal Lv2 did not increase support limit")

	player_ship.call("_spawn_or_repair_ally")
	await _wait_frames(owner, wait_frames_after_spawn + 2)
	var support_ships: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships.size() < 2:
		failures.append("support fleet smoke signal Lv2 did not spawn second support ship")

	UpgradeManager.current_levels["fleet_signal"] = original_signal_level
	UpgradeManager.current_levels["fleet_crew"] = original_crew_level
	UpgradeManager.call("_refresh_support_fleet_upgrade_state", player_ship)


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
		var expected_count: int = mini(level, 3)
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
	UpgradeManager.apply_fleet_upgrades_to_ship(support_ship)


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
