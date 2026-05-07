extends RefCounted
class_name SupportFleetCannonHelper

const PlayerShipSupportSquadronHelper = preload("res://scripts/entities/ships/player_ship_support_squadron_helper.gd")

const FLEET_SIGNAL_UPGRADE_ID := "fleet_signal"
const PANOKSEON_UPGRADE_ID := "panokseon_upgrade"
const SUPPORT_BASE_CANNON_COUNT := "support_base_cannon_count"
const SUPPORT_MAX_CANNON_COUNT := "support_max_cannon_count"
const PANOKSEON_SUPPORT_BASE_CANNON_COUNT := "panokseon_support_base_cannon_count"
const PANOKSEON_SUPPORT_MAX_CANNON_COUNT := "panokseon_support_max_cannon_count"


static func get_player_cannon_count_for_level(level: int, stats: Dictionary) -> int:
	var count := int(stats.get("player_base_cannon_count", 3))
	for entry in stats.get("player_extra_cannon_levels", [2, 3, 4, 5]):
		if level >= int(entry):
			count += 1
	return count


static func is_panokseon_support_active(current_levels: Dictionary) -> bool:
	return int(current_levels.get(PANOKSEON_UPGRADE_ID, 0)) > 0


static func get_support_cannon_count_for_current_levels(level: int, stats: Dictionary, current_levels: Dictionary) -> int:
	return get_support_cannon_count_for_level(level, stats, is_panokseon_support_active(current_levels))


static func get_support_cannon_count_for_level(level: int, stats: Dictionary, panokseon_support: bool = false) -> int:
	var support_base_key := PANOKSEON_SUPPORT_BASE_CANNON_COUNT if panokseon_support else SUPPORT_BASE_CANNON_COUNT
	var support_max_key := PANOKSEON_SUPPORT_MAX_CANNON_COUNT if panokseon_support else SUPPORT_MAX_CANNON_COUNT
	var count := int(stats.get(support_base_key, stats.get(SUPPORT_BASE_CANNON_COUNT, 1)))
	for entry in stats.get("player_extra_cannon_levels", [2, 3, 4, 5]):
		if level >= int(entry):
			count += 1
	return mini(count, int(stats.get(support_max_key, stats.get(SUPPORT_MAX_CANNON_COUNT, 3))))


static func get_active_support_cannon_names_for_ship_type(ship_type_name: String, level: int, current_levels: Dictionary = {}) -> Dictionary:
	var stats := ShipBlueprintHelper.load_stats(ship_type_name)
	var loadout := ShipWeaponLoadoutHelper.get_weapon_loadout(stats, ShipWeaponLoadoutHelper.get_default_support_cannon_loadout())
	var active_cannon_names: Dictionary = {}
	for spec in loadout:
		if ShipWeaponLoadoutHelper.get_kind(spec) != ShipWeaponLoadoutHelper.KIND_CANNON:
			continue
		if ShipWeaponLoadoutHelper.get_required_level(spec) > level:
			continue
		if not ShipWeaponLoadoutHelper.is_unlocked_for_levels(spec, current_levels):
			continue
		active_cannon_names[ShipWeaponLoadoutHelper.get_node_name(spec)] = true
	return active_cannon_names


static func get_support_fleet_limit_for_current_levels(current_levels: Dictionary, upgrades: Dictionary = {}, support_limit_override: int = -1) -> int:
	if support_limit_override >= 0:
		return maxi(0, support_limit_override)
	if int(current_levels.get(FLEET_SIGNAL_UPGRADE_ID, 0)) <= 0:
		return 0
	var limit := 1
	limit += _get_support_upgrade_limit_bonus(current_levels, upgrades)
	limit += PlayerShipSupportSquadronHelper.get_support_limit_bonus_for_levels(current_levels, upgrades)
	return maxi(0, limit)


static func get_active_support_slot_profiles_for_current_levels(current_levels: Dictionary, upgrades: Dictionary = {}, support_limit_override: int = -1) -> Array:
	var support_limit := get_support_fleet_limit_for_current_levels(current_levels, upgrades, support_limit_override)
	if support_limit <= 0:
		return []
	var active_profiles: Array = []
	for support_slot in range(support_limit):
		active_profiles.append(
			PlayerShipSupportSquadronHelper.resolve_support_fleet_profile_for_levels(current_levels, upgrades, support_slot)
		)
	return active_profiles


static func get_support_slot_summary_for_current_levels(current_levels: Dictionary, upgrades: Dictionary = {}, support_limit_override: int = -1) -> String:
	var profiles := get_active_support_slot_profiles_for_current_levels(current_levels, upgrades, support_limit_override)
	if profiles.is_empty():
		return "잠김"
	var entries: Array = []
	var entry_indices: Dictionary = {}
	for profile in profiles:
		var ship_type_name := PlayerShipSupportSquadronHelper.get_profile_ship_type(profile)
		var ship_label := _get_support_ship_summary_label(ship_type_name)
		if entry_indices.has(ship_label):
			var entry_index := int(entry_indices[ship_label])
			var entry: Dictionary = entries[entry_index]
			entry["slot_count"] = int(entry.get("slot_count", 0)) + 1
			entries[entry_index] = entry
			continue
		entry_indices[ship_label] = entries.size()
		entries.append({
			"ship_type": ship_type_name,
			"ship_label": ship_label,
			"slot_count": 1,
		})
	var parts: Array[String] = []
	for entry in entries:
		parts.append("%s %d척" % [str(entry.get("ship_label", "지원함")), int(entry.get("slot_count", 0))])
	return " | ".join(parts)


static func get_support_slot_cannon_entries_for_current_levels(
	level: int,
	_stats: Dictionary,
	current_levels: Dictionary,
	upgrades: Dictionary = {},
	support_limit_override: int = -1
) -> Array:
	var profiles := get_active_support_slot_profiles_for_current_levels(current_levels, upgrades, support_limit_override)
	if profiles.is_empty():
		return []
	var entries: Array = []
	var entry_indices: Dictionary = {}
	for profile in profiles:
		var ship_type_name := PlayerShipSupportSquadronHelper.get_profile_ship_type(profile)
		var ship_label := _get_support_ship_summary_label(ship_type_name)
		var cannon_count := get_active_support_cannon_names_for_ship_type(ship_type_name, level, current_levels).size()
		var group_key := "%s|%d" % [ship_label, cannon_count]
		if entry_indices.has(group_key):
			var entry_index := int(entry_indices[group_key])
			var entry: Dictionary = entries[entry_index]
			entry["slot_count"] = int(entry.get("slot_count", 0)) + 1
			entries[entry_index] = entry
			continue
		entry_indices[group_key] = entries.size()
		entries.append({
			"ship_type": ship_type_name,
			"ship_label": ship_label,
			"cannon_count": cannon_count,
			"slot_count": 1,
		})
	return entries


static func get_support_cannon_summary_for_current_levels(
	level: int,
	stats: Dictionary,
	current_levels: Dictionary,
	upgrades: Dictionary = {},
	support_limit_override: int = -1
) -> String:
	var entries := get_support_slot_cannon_entries_for_current_levels(
		level,
		stats,
		current_levels,
		upgrades,
		support_limit_override
	)
	if entries.is_empty():
		return "잠김"
	var parts: Array[String] = []
	for entry in entries:
		var part := "%s %d문" % [
			str(entry.get("ship_label", "지원함")),
			int(entry.get("cannon_count", 0)),
		]
		var slot_count := int(entry.get("slot_count", 0))
		if slot_count > 1:
			part += " x%d" % slot_count
		parts.append(part)
	return " | ".join(parts)


static func _get_support_upgrade_limit_bonus(current_levels: Dictionary, upgrades: Dictionary) -> int:
	var upgrade_bonus := 0
	var signal_level := int(current_levels.get(FLEET_SIGNAL_UPGRADE_ID, 0))
	var signal_stats: Dictionary = upgrades.get(FLEET_SIGNAL_UPGRADE_ID, {}).get("stats", {})
	if signal_level >= int(signal_stats.get("limit_add_level", 999)):
		upgrade_bonus += int(signal_stats.get("limit_add", 0))
	return upgrade_bonus


static func _is_panokseon_ship_type(ship_type_name: String) -> bool:
	return ship_type_name.contains("panokseon")


static func _get_support_ship_summary_label(ship_type_name: String) -> String:
	if ship_type_name.contains("geobukseon") or ship_type_name.contains("turtle"):
		return "거북선"
	if _is_panokseon_ship_type(ship_type_name):
		return "판옥선"
	if ship_type_name.contains("maengseon"):
		return "맹선"
	var stats := ShipBlueprintHelper.load_stats(ship_type_name)
	return str(stats.get("display_name", ship_type_name))
