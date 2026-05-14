extends RefCounted
class_name ProjectContractUpgradeHelper

const SupportFleetCannonRules = preload("res://scripts/entities/ships/support_fleet_cannon_helper.gd")
const UpgradeDataHelper = preload("res://scripts/managers/upgrade_manager_data_helper.gd")

static func run_upgrade_contract_smoke(failures: Array[String]) -> void:
	_validate_cannon_upgrade_split(failures)
	_validate_crew_reserve_retired(failures)
	_validate_crew_weapon_upgrades_do_not_increase_capacity(failures)
	_validate_support_hull_upgrade_retired(failures)
	_validate_sailing_upgrade_improves_handling(failures)
	_validate_panokseon_upgrade_gate(failures)
	_validate_player_geobukseon_upgrade(failures)
	_validate_hull_upgrade_split(failures)


static func _validate_cannon_upgrade_split(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return

	var upgrades: Dictionary = UpgradeManager.UPGRADES
	if not upgrades.has("cannon"):
		failures.append("upgrade smoke missing cannon/포문 upgrade")
		return
	var missing_split_upgrade := false
	if upgrades.has("fleet_cannon"):
		failures.append("upgrade smoke fleet_cannon should be retired")
	if not upgrades.has("cannon_damage"):
		failures.append("upgrade smoke missing cannon_damage/철환 upgrade")
		missing_split_upgrade = true
	if not upgrades.has("cannon_reload"):
		failures.append("upgrade smoke missing cannon_reload/화약 upgrade")
		missing_split_upgrade = true
	if not upgrades.has("front_cannon"):
		failures.append("upgrade smoke missing front_cannon/전면 포문 upgrade")
		missing_split_upgrade = true
	if missing_split_upgrade:
		return

	var cannon_data: Dictionary = upgrades.get("cannon", {})
	var cannon_stats: Dictionary = cannon_data.get("stats", {})
	if str(cannon_data.get("name", "")) != "포문":
		failures.append("upgrade smoke cannon upgrade should be named 포문")
	if int(cannon_data.get("max_level", 0)) != 3:
		failures.append("upgrade smoke 포문 max_level should be 3")
	if cannon_stats.has("dmg_pct_per_lv") or cannon_stats.has("cd_pct_per_lv") or cannon_stats.has("range_pct_per_lv"):
		failures.append("upgrade smoke 포문 should not carry damage/range/reload stats")
	if SupportFleetCannonRules.get_player_cannon_count_for_level(3, cannon_stats) != 6:
		failures.append("upgrade smoke 포문 Lv3 should reach 6 player side cannons")
	if SupportFleetCannonRules.get_support_cannon_count_for_level(3, cannon_stats) != 3:
		failures.append("upgrade smoke 포문 Lv3 support cannon cap should stay 3")
	if SupportFleetCannonRules.get_support_cannon_count_for_level(3, cannon_stats, true) != 6:
		failures.append("upgrade smoke 포문 Lv3 panokseon support side cannon cap should reach 6")
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("panokseon_ally", 1).size() != 2:
		failures.append("upgrade smoke panokseon support should start with two side cannons before 전면 포문")
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("maengseon_ally", 3).size() != 1:
		failures.append("upgrade smoke maengseon support should stay front-cannon only at 포문 Lv3")
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("panokseon_ally", 3).size() != 6:
		failures.append("upgrade smoke panokseon support should keep six side cannons before 전면 포문")
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("geobukseon_ally", 3).size() != 6:
		failures.append("upgrade smoke geobukseon support should expose two forward cannons plus four side cannons at 포문 Lv3")
	var panokseon_front_levels := {
		"front_cannon": 1,
	}
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("panokseon_ally", 1, panokseon_front_levels).size() != 3:
		failures.append("upgrade smoke panokseon support should unlock front cannon without needing 포문 Lv2")
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("panokseon_ally", 3, panokseon_front_levels).size() != 7:
		failures.append("upgrade smoke panokseon support should reach seven cannons with 전면 포문")
	var panokseon_levels := {
		"fleet_signal": 1,
		"panokseon_upgrade": 1,
	}
	if SupportFleetCannonRules.get_support_slot_summary_for_current_levels(panokseon_levels, upgrades) != "맹선 1척 | 판옥선 1척":
		failures.append("upgrade smoke support slot summary should reflect maengseon plus added panokseon roster")
	if SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(3, cannon_stats, panokseon_levels, upgrades) != "맹선 1문 | 판옥선 6문":
		failures.append("upgrade smoke support cannon summary should reflect side cannon slots at 포문 Lv3")
	var geobukseon_levels := {
		"fleet_signal": 1,
		"geobukseon_upgrade": 1,
	}
	if upgrades.get("geobukseon_upgrade", {}).get("disabled", false) != true:
		failures.append("upgrade smoke geobukseon support upgrade should stay disabled while player geobukseon is being tested")
	if SupportFleetCannonRules.get_support_slot_summary_for_current_levels(geobukseon_levels, upgrades) != "맹선 1척":
		failures.append("upgrade smoke disabled geobukseon support should fall back to maengseon screen roster")
	if SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(3, cannon_stats, geobukseon_levels, upgrades) != "맹선 1문":
		failures.append("upgrade smoke disabled geobukseon support should not add geobukseon cannons")
	panokseon_levels["front_cannon"] = 1
	if SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(3, cannon_stats, panokseon_levels, upgrades) != "맹선 1문 | 판옥선 7문":
		failures.append("upgrade smoke support cannon summary should include 전면 포문 when unlocked")
	if int(cannon_stats.get("support_max_cannon_count", 0)) != 3:
		failures.append("upgrade smoke support cannon cap should be 3")
	if int(cannon_stats.get("panokseon_support_base_cannon_count", 0)) != 2:
		failures.append("upgrade smoke panokseon support base cannon count should be 2")
	if int(cannon_stats.get("panokseon_support_max_cannon_count", 0)) != 6:
		failures.append("upgrade smoke panokseon support side cannon cap should be 6")

	var damage_stats: Dictionary = upgrades.get("cannon_damage", {}).get("stats", {})
	if str(upgrades.get("cannon_damage", {}).get("name", "")) != "철환":
		failures.append("upgrade smoke cannon_damage upgrade should be named 철환")
	if int(damage_stats.get("dmg_pct_per_lv", 0)) != 8:
		failures.append("upgrade smoke 철환 damage percent should be 8")

	var reload_stats: Dictionary = upgrades.get("cannon_reload", {}).get("stats", {})
	if str(upgrades.get("cannon_reload", {}).get("name", "")) != "화약":
		failures.append("upgrade smoke cannon_reload upgrade should be named 화약")
	if int(reload_stats.get("cd_pct_per_lv", 0)) != 4:
		failures.append("upgrade smoke 화약 cooldown percent should be 4")
	if float(reload_stats.get("min_cd_mult", 0.0)) < 0.75:
		failures.append("upgrade smoke 화약 min cooldown multiplier should not be below 0.75")

	var barricade_stats: Dictionary = upgrades.get("boarding_resist", {}).get("stats", {})
	if barricade_stats.has("capture_duration_mult_per_lv"):
		failures.append("upgrade smoke 창벽 should not be a capture-duration-only upgrade")
	if not barricade_stats.has("boarding_defense_damage_per_tick_per_lv"):
		failures.append("upgrade smoke 창벽 missing boarding defense damage stat")

	if not ("cannon_damage" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke 철환 missing from ship upgrade pool")
	if not ("cannon_reload" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke 화약 missing from ship upgrade pool")
	if not ("front_cannon" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke 전면 포문 missing from ship upgrade pool")
	if not UpgradeManager.has_method("_apply_front_cannon"):
		failures.append("upgrade smoke 전면 포문 missing immediate apply handler")
	if "fleet_cannon" in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS:
		failures.append("upgrade smoke fleet_cannon should not be in support ship pool")
	if upgrades.has("hull_repair") and upgrades["hull_repair"].get("disabled", false) != true:
		failures.append("upgrade smoke hull_repair data should stay disabled")
	var supply_stats: Dictionary = upgrades.get("supply_bonus", {}).get("stats", {})
	if upgrades.has("supply_bonus") and upgrades["supply_bonus"].get("disabled", false) != true:
		failures.append("upgrade smoke supply_bonus data should stay disabled")
	if str(upgrades.get("supply_bonus", {}).get("description", "")).contains("회복"):
		failures.append("upgrade smoke 보급 description should not mention healing")
	if supply_stats.has("base_heal") or supply_stats.has("heal_levels") or supply_stats.has("heal_add"):
		failures.append("upgrade smoke 보급 should not carry hull healing stats")
	if supply_stats.has("base_stamina_recovery") or supply_stats.has("stamina_recovery_levels") or supply_stats.has("stamina_recovery_add"):
		failures.append("upgrade smoke 보급 should not carry stamina recovery stats")
	var computed_supply_stats := UpgradeDataHelper.get_supply_bonus_stats(upgrades, {"supply_bonus": 5})
	if computed_supply_stats.size() != 1 or not computed_supply_stats.has("radius_bonus"):
		failures.append("upgrade smoke 보급 stats should expose only radius_bonus")
	var supply_radius_levels: Array = supply_stats.get("radius_levels", [])
	if supply_radius_levels.size() != 5:
		failures.append("upgrade smoke 보급 should increase pickup range at every level")


static func _validate_crew_reserve_retired(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return
	var upgrades: Dictionary = UpgradeManager.UPGRADES
	if "crew_reserve" in UpgradeManager.CREW_UPGRADE_IDS:
		failures.append("upgrade smoke crew_reserve should be retired from command choices")
	if "crew_reserve" in UpgradeManager.PRIORITY_CREW_UPGRADE_IDS:
		failures.append("upgrade smoke crew_reserve should not be a priority command choice")
	if upgrades.has("crew_reserve") and upgrades["crew_reserve"].get("disabled", false) != true:
		failures.append("upgrade smoke crew_reserve data should stay disabled")
	var reserve_stats: Dictionary = upgrades.get("crew_reserve", {}).get("stats", {})
	if reserve_stats.has("survivor_hull_heal_per_lv"):
		failures.append("upgrade smoke crew_reserve should not add survivor rescue hull healing")
	var survivor_source := FileAccess.get_file_as_string("res://scripts/effects/survivor.gd")
	if survivor_source.contains("survivor_hull_heal_bonus") or survivor_source.contains("_can_apply_hull_rescue_heal"):
		failures.append("upgrade smoke survivor rescue should not apply hull healing")


static func _validate_crew_weapon_upgrades_do_not_increase_capacity(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return
	var upgrades: Dictionary = UpgradeManager.UPGRADES
	var levels := {
		"crew_numbers": 5,
		"fire_pot": 5,
		"singigeon": 5,
	}
	var roster: Dictionary = UpgradeDataHelper.get_player_crew_roster(upgrades, levels, 5)
	var specialist_roles := [
		UpgradeDataHelper.CREW_ROLE_FIRE_POT,
	]
	var total_roster := int(roster.get(UpgradeDataHelper.CREW_ROLE_GENERAL, 0))
	for role in specialist_roles:
		total_roster += int(roster.get(role, 0))
		if int(roster.get(role, 0)) <= 0:
			failures.append("upgrade smoke fixed crew roster should keep at least one %s operator when all crew weapons are active" % role)
	total_roster += int(roster.get(UpgradeDataHelper.CREW_ROLE_SPEARMAN, 0))
	if int(roster.get(UpgradeDataHelper.CREW_ROLE_SPEARMAN, 0)) != 0:
		failures.append("upgrade smoke crew_numbers should improve spear damage instead of assigning spearman operators")
	total_roster += int(roster.get(UpgradeDataHelper.CREW_ROLE_SINGIGEON, 0))
	if int(roster.get(UpgradeDataHelper.CREW_ROLE_SINGIGEON, 0)) != 0:
		failures.append("upgrade smoke singigeon should proc from bow attacks instead of assigning operators")
	total_roster += int(roster.get(UpgradeDataHelper.CREW_ROLE_REPEATING_CROSSBOW, 0))
	if int(roster.get(UpgradeDataHelper.CREW_ROLE_REPEATING_CROSSBOW, 0)) != 0:
		failures.append("upgrade smoke repeating_crossbow should be retired from command choices")
	if total_roster != 5:
		failures.append("upgrade smoke crew weapon roster should not exceed fixed crew capacity")
	if "crew_attack" in UpgradeManager.CREW_UPGRADE_IDS:
		failures.append("upgrade smoke crew_attack should be retired from command choices")
	if upgrades.has("crew_attack") and upgrades["crew_attack"].get("disabled", false) != true:
		failures.append("upgrade smoke crew_attack data should stay disabled")
	if "repeating_crossbow" in UpgradeManager.CREW_UPGRADE_IDS:
		failures.append("upgrade smoke repeating_crossbow should be retired from command choices")
	if upgrades.has("repeating_crossbow") and upgrades["repeating_crossbow"].get("disabled", false) != true:
		failures.append("upgrade smoke repeating_crossbow data should stay disabled")
	if upgrades.has("fire_pot") and upgrades["fire_pot"].get("disabled", false) != true:
		failures.append("upgrade smoke fire_pot data should stay disabled")

	var source := FileAccess.get_file_as_string("res://scripts/managers/upgrade_manager.gd")
	if source.contains("for upgrade_id in [\"crew_numbers\", \"singigeon\", \"fire_pot\", \"repeating_crossbow\"]"):
		failures.append("upgrade smoke crew weapon upgrades should not add max_crew_count capacity")


static func _validate_support_hull_upgrade_retired(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return
	var upgrades: Dictionary = UpgradeManager.UPGRADES
	if "fleet_hull" in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS:
		failures.append("upgrade smoke fleet_hull should be retired from support ship choices")
	if "fleet_hull" in UpgradeManager.ACTIVE_SUPPORT_UPGRADE_IDS:
		failures.append("upgrade smoke fleet_hull should not drive active support upgrades")
	if upgrades.has("fleet_hull") and upgrades["fleet_hull"].get("disabled", false) != true:
		failures.append("upgrade smoke fleet_hull data should stay disabled")


static func _validate_sailing_upgrade_improves_handling(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return
	var upgrades: Dictionary = UpgradeManager.UPGRADES
	var sailing_data: Dictionary = upgrades.get("sailing", {})
	var sailing_stats: Dictionary = sailing_data.get("stats", {})
	if not str(sailing_data.get("description", "")).contains("전환"):
		failures.append("upgrade smoke sailing description should mention sail handling transition")
	var handling_levels: Array = sailing_stats.get("handling_levels", [])
	if handling_levels.size() != int(sailing_data.get("max_level", 0)):
		failures.append("upgrade smoke sailing should improve handling at every level")
	if float(sailing_stats.get("handling_mult", 1.0)) <= 1.0:
		failures.append("upgrade smoke sailing handling multiplier should improve furl speed")
	var source := FileAccess.get_file_as_string("res://scripts/managers/upgrade_manager.gd")
	if not source.contains("sail_furl_rate") or not source.contains("fold_duration"):
		failures.append("upgrade smoke sailing should apply to sail furl and mast fold timing")


static func _validate_panokseon_upgrade_gate(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return
	var upgrades: Dictionary = UpgradeManager.UPGRADES
	if not upgrades.has("panokseon_upgrade"):
		failures.append("upgrade smoke missing panokseon_upgrade")
		return
	if not ("panokseon_upgrade" in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke panokseon_upgrade missing from support ship pool")
	if not ("panokseon_upgrade" in UpgradeManager.ACTIVE_SUPPORT_UPGRADE_IDS):
		failures.append("upgrade smoke panokseon_upgrade should drive active support upgrades")
	if not UpgradeManager.has_method("reconcile_support_fleet"):
		failures.append("upgrade smoke missing reconcile_support_fleet entrypoint")
	var panokseon_stats: Dictionary = upgrades.get("panokseon_upgrade", {}).get("stats", {})
	if str(panokseon_stats.get("panokseon_upgrade_id", "")) != "panokseon_upgrade":
		failures.append("upgrade smoke panokseon_upgrade should self-declare unlock id")
	if int(panokseon_stats.get("panokseon_level", 0)) != 1:
		failures.append("upgrade smoke panokseon_upgrade should unlock at level 1")
	if int(panokseon_stats.get("panokseon_squadron_limit_add", 0)) != 1:
		failures.append("upgrade smoke panokseon_upgrade should add exactly one panokseon support slot")


static func _validate_player_geobukseon_upgrade(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return
	var upgrades: Dictionary = UpgradeManager.UPGRADES
	if not upgrades.has("geobukseon"):
		failures.append("upgrade smoke missing player geobukseon upgrade")
		return
	if not ("geobukseon" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke player geobukseon should be in main ship pool")
	var stats: Dictionary = upgrades.get("geobukseon", {}).get("stats", {})
	if str(stats.get("ship_type", "")) != "geobukseon_player":
		failures.append("upgrade smoke player geobukseon should target geobukseon_player ship type")
	if stats.get("blocks_boarding", false) != true:
		failures.append("upgrade smoke player geobukseon should block boarding")
	var player_stats := ShipBlueprintHelper.load_stats("geobukseon_player")
	if player_stats.get("blocks_boarding", false) != true:
		failures.append("upgrade smoke geobukseon_player should block boarding")
	if float(player_stats.get("move_speed", 0.0)) < 6.0:
		failures.append("upgrade smoke geobukseon_player should not reduce player move speed")
	var loadout := ShipWeaponLoadoutHelper.get_weapon_loadout(player_stats, [])
	var cannon_count := 0
	var front_cannon_count := 0
	for spec in loadout:
		if ShipWeaponLoadoutHelper.get_kind(spec) != ShipWeaponLoadoutHelper.KIND_CANNON:
			continue
		cannon_count += 1
		var slot_name := ShipWeaponLoadoutHelper.get_slot_name(spec)
		if slot_name == "CannonFront":
			failures.append("upgrade smoke geobukseon_player should not expose central front cannon")
		if slot_name.begins_with("CannonFront"):
			front_cannon_count += 1
	if front_cannon_count != 2:
		failures.append("upgrade smoke geobukseon_player should expose exactly two split forward cannons, got %d" % front_cannon_count)
	if cannon_count != 6:
		failures.append("upgrade smoke geobukseon_player should expose exactly six cannons, got %d" % cannon_count)


static func _validate_hull_upgrade_split(failures: Array[String]) -> void:
	if not is_instance_valid(UpgradeManager):
		failures.append("upgrade smoke missing UpgradeManager")
		return
	var upgrades: Dictionary = UpgradeManager.UPGRADES
	if not upgrades.has("hull"):
		failures.append("upgrade smoke missing hull/선체 upgrade")
		return
	if not ("hull" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke hull should be in main ship pool")
	if str(upgrades.get("hull_defense", {}).get("name", "")) != "방어":
		failures.append("upgrade smoke hull_defense should be renamed to 방어")
	if str(upgrades.get("hull", {}).get("name", "")) != "선체":
		failures.append("upgrade smoke hull upgrade should be named 선체")
	var hull_stats: Dictionary = upgrades.get("hull", {}).get("stats", {})
	if float(hull_stats.get("hp_add_per_lv", 0.0)) <= 0.0:
		failures.append("upgrade smoke hull should add max hull hp")
	if float(hull_stats.get("ramming_damage_pct_per_lv", 0.0)) <= 0.0:
		failures.append("upgrade smoke hull should improve ramming damage")
