extends RefCounted
class_name ProjectContractSupportHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const ShipAllyRoleHelper = preload("res://scripts/entities/ships/ship_ally_role_helper.gd")


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
