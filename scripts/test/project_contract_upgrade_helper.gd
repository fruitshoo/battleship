extends RefCounted
class_name ProjectContractUpgradeHelper

const SupportFleetCannonRules = preload("res://scripts/entities/ships/support_fleet_cannon_helper.gd")
const UpgradeDataHelper = preload("res://scripts/managers/upgrade_manager_data_helper.gd")

static func run_upgrade_contract_smoke(failures: Array[String]) -> void:
	_validate_cannon_upgrade_split(failures)
	_validate_crew_reserve_retired(failures)
	_validate_crew_weapon_upgrades_do_not_increase_capacity(failures)
	_validate_support_hull_upgrade_retired(failures)
	_validate_panokseon_upgrade_gate(failures)


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
	if missing_split_upgrade:
		return

	var cannon_data: Dictionary = upgrades.get("cannon", {})
	var cannon_stats: Dictionary = cannon_data.get("stats", {})
	if str(cannon_data.get("name", "")) != "포문":
		failures.append("upgrade smoke cannon upgrade should be named 포문")
	if int(cannon_data.get("max_level", 0)) != 5:
		failures.append("upgrade smoke 포문 max_level should be 5")
	if cannon_stats.has("dmg_pct_per_lv") or cannon_stats.has("cd_pct_per_lv") or cannon_stats.has("range_pct_per_lv"):
		failures.append("upgrade smoke 포문 should not carry damage/range/reload stats")
	if SupportFleetCannonRules.get_player_cannon_count_for_level(5, cannon_stats) != 7:
		failures.append("upgrade smoke 포문 Lv5 should reach 7 player cannons")
	if SupportFleetCannonRules.get_support_cannon_count_for_level(5, cannon_stats) != 3:
		failures.append("upgrade smoke 포문 Lv5 support cannon cap should stay 3")
	if SupportFleetCannonRules.get_support_cannon_count_for_level(5, cannon_stats, true) != 5:
		failures.append("upgrade smoke 포문 Lv5 panokseon support cannon cap should reach 5")
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("maengseon_ally", 5).size() != 1:
		failures.append("upgrade smoke maengseon support should stay front-cannon only at 포문 Lv5")
	if SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type("panokseon_ally", 5).size() != 5:
		failures.append("upgrade smoke panokseon support should keep five authored cannons at 포문 Lv5")
	var panokseon_levels := {
		"fleet_signal": 1,
		"panokseon_upgrade": 1,
	}
	if SupportFleetCannonRules.get_support_slot_summary_for_current_levels(panokseon_levels, upgrades) != "맹선 1척 | 판옥선 1척":
		failures.append("upgrade smoke support slot summary should reflect maengseon plus added panokseon roster")
	if SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(5, cannon_stats, panokseon_levels, upgrades) != "맹선 1문 | 판옥선 5문":
		failures.append("upgrade smoke support cannon summary should reflect ship-authored cannon slots at 포문 Lv5")
	if int(cannon_stats.get("support_max_cannon_count", 0)) != 3:
		failures.append("upgrade smoke support cannon cap should be 3")
	if int(cannon_stats.get("panokseon_support_base_cannon_count", 0)) != 3:
		failures.append("upgrade smoke panokseon support base cannon count should be 3")
	if int(cannon_stats.get("panokseon_support_max_cannon_count", 0)) != 5:
		failures.append("upgrade smoke panokseon support cannon cap should be 5")

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
		failures.append("upgrade smoke 방책 should not be a capture-duration-only upgrade")
	if not barricade_stats.has("boarding_defense_damage_per_tick_per_lv"):
		failures.append("upgrade smoke 방책 missing boarding defense damage stat")

	if not ("cannon_damage" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke 철환 missing from ship upgrade pool")
	if not ("cannon_reload" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke 화약 missing from ship upgrade pool")
	if "fleet_cannon" in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS:
		failures.append("upgrade smoke fleet_cannon should not be in support ship pool")


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
		"repeating_crossbow": 5,
		"singigeon": 5,
	}
	var roster: Dictionary = UpgradeDataHelper.get_player_crew_roster(upgrades, levels, 5)
	var specialist_roles := [
		UpgradeDataHelper.CREW_ROLE_SPEARMAN,
		UpgradeDataHelper.CREW_ROLE_FIRE_POT,
		UpgradeDataHelper.CREW_ROLE_REPEATING_CROSSBOW,
		UpgradeDataHelper.CREW_ROLE_SINGIGEON,
	]
	var total_roster := int(roster.get(UpgradeDataHelper.CREW_ROLE_GENERAL, 0))
	for role in specialist_roles:
		total_roster += int(roster.get(role, 0))
		if int(roster.get(role, 0)) <= 0:
			failures.append("upgrade smoke fixed crew roster should keep at least one %s operator when all crew weapons are active" % role)
	if total_roster != 5:
		failures.append("upgrade smoke crew weapon roster should not exceed fixed crew capacity")

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
