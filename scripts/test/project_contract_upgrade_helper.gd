extends RefCounted
class_name ProjectContractUpgradeHelper


static func run_upgrade_contract_smoke(failures: Array[String]) -> void:
	_validate_cannon_upgrade_split(failures)


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
		failures.append("upgrade smoke missing cannon_damage/화약 upgrade")
		missing_split_upgrade = true
	if not upgrades.has("cannon_reload"):
		failures.append("upgrade smoke missing cannon_reload/장전 upgrade")
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
	if _get_player_cannon_count_for_level(5, cannon_stats) != 7:
		failures.append("upgrade smoke 포문 Lv5 should reach 7 player cannons")
	if _get_support_cannon_count_for_level(5, cannon_stats) != 3:
		failures.append("upgrade smoke 포문 Lv5 support cannon cap should stay 3")
	if int(cannon_stats.get("support_max_cannon_count", 0)) != 3:
		failures.append("upgrade smoke support cannon cap should be 3")

	var damage_stats: Dictionary = upgrades.get("cannon_damage", {}).get("stats", {})
	if int(damage_stats.get("dmg_pct_per_lv", 0)) != 8:
		failures.append("upgrade smoke 화약 damage percent should be 8")

	var reload_stats: Dictionary = upgrades.get("cannon_reload", {}).get("stats", {})
	if int(reload_stats.get("cd_pct_per_lv", 0)) != 4:
		failures.append("upgrade smoke 장전 cooldown percent should be 4")
	if float(reload_stats.get("min_cd_mult", 0.0)) < 0.75:
		failures.append("upgrade smoke 장전 min cooldown multiplier should not be below 0.75")

	if not ("cannon_damage" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke 화약 missing from ship upgrade pool")
	if not ("cannon_reload" in UpgradeManager.SHIP_UPGRADE_IDS):
		failures.append("upgrade smoke 장전 missing from ship upgrade pool")
	if "fleet_cannon" in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS:
		failures.append("upgrade smoke fleet_cannon should not be in support ship pool")


static func _get_player_cannon_count_for_level(level: int, stats: Dictionary) -> int:
	var count := int(stats.get("player_base_cannon_count", 3))
	for entry in stats.get("player_extra_cannon_levels", [2, 3, 4, 5]):
		if level >= int(entry):
			count += 1
	return count


static func _get_support_cannon_count_for_level(level: int, stats: Dictionary) -> int:
	var count := int(stats.get("support_base_cannon_count", 1))
	for entry in stats.get("player_extra_cannon_levels", [2, 3, 4, 5]):
		if level >= int(entry):
			count += 1
	return mini(count, int(stats.get("support_max_cannon_count", 3)))
