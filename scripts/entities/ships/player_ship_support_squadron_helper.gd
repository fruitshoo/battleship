extends RefCounted
class_name PlayerShipSupportSquadronHelper

const MAENGSEON_HULL_SCENE = preload("res://scenes/ships/hulls/maengseon_hull.tscn")
const PANOKSEON_HULL_SCENE = preload("res://scenes/ships/hulls/panokseon_hull.tscn")
const JOSEON_CANNON_SCENE = preload("res://scenes/entities/launchers/cannon_joseon.tscn")

const PROFILE_MAENGSEON_SCREEN := "maengseon_screen"
const PROFILE_PANOKSEON_ESCORT := "panokseon_escort"
const DEFAULT_PANOKSEON_UNLOCK_UPGRADE_ID := "panokseon_upgrade"
const DEFAULT_PANOKSEON_UNLOCK_LEVEL := 1

const SUPPORT_PROFILES := {
	PROFILE_MAENGSEON_SCREEN: {
		"id": PROFILE_MAENGSEON_SCREEN,
		"ship_type": "maengseon_ally",
		"role": "screen_rescue",
		"hull_scene": MAENGSEON_HULL_SCENE,
		"cannon_scene": JOSEON_CANNON_SCENE,
	},
	PROFILE_PANOKSEON_ESCORT: {
		"id": PROFILE_PANOKSEON_ESCORT,
		"ship_type": "panokseon_ally",
		"role": "artillery_escort",
		"hull_scene": PANOKSEON_HULL_SCENE,
		"cannon_scene": JOSEON_CANNON_SCENE,
	},
}

const FLAGSHIP_SCREEN_SLOTS := [
	{
		"squadron_id": "flagship_screen",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "screen_lead",
	},
	{
		"squadron_id": "flagship_screen",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "screen_flank",
	},
	{
		"squadron_id": "flagship_screen",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "rescue_rear",
	},
]

const PANOKSEON_ARTILLERY_SLOTS := [
	{
		"squadron_id": "panokseon_artillery",
		"profile_id": PROFILE_PANOKSEON_ESCORT,
		"slot_role": "artillery_lead",
	},
	{
		"squadron_id": "panokseon_artillery",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "artillery_screen_front_left",
	},
	{
		"squadron_id": "panokseon_artillery",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "artillery_screen_front_right",
	},
	{
		"squadron_id": "panokseon_artillery",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "artillery_screen_rear_left",
	},
	{
		"squadron_id": "panokseon_artillery",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "artillery_screen_rear_right",
	},
]


static func resolve_support_fleet_profile_for_levels(current_levels: Dictionary, upgrades: Dictionary = {}, support_slot: int = 0) -> Dictionary:
	var slot_plan := get_support_slot_plan_for_levels(current_levels, upgrades)
	var normalized_slot: int = max(0, support_slot)
	if normalized_slot < slot_plan.size():
		return _build_profile_for_slot(slot_plan[normalized_slot], normalized_slot)
	return _build_profile_for_slot(_build_fallback_slot(normalized_slot), normalized_slot)


static func get_support_slot_plan_for_levels(current_levels: Dictionary, upgrades: Dictionary = {}) -> Array:
	var plan: Array = []
	var flagship_slots := FLAGSHIP_SCREEN_SLOTS.duplicate(true)
	var panokseon_slots := PANOKSEON_ARTILLERY_SLOTS.duplicate(true)
	var panokseon_unlocked := is_panokseon_squadron_unlocked(current_levels, upgrades)

	if not flagship_slots.is_empty():
		plan.append(flagship_slots[0])
	if panokseon_unlocked:
		plan.append(panokseon_slots[0])
		for i in range(1, panokseon_slots.size()):
			plan.append(panokseon_slots[i])
		for i in range(1, flagship_slots.size()):
			plan.append(flagship_slots[i])
		return plan
	for i in range(1, flagship_slots.size()):
		plan.append(flagship_slots[i])
	return plan


static func is_panokseon_squadron_unlocked(current_levels: Dictionary, upgrades: Dictionary = {}) -> bool:
	var unlock_id := get_panokseon_unlock_upgrade_id(upgrades)
	if unlock_id == DEFAULT_PANOKSEON_UNLOCK_UPGRADE_ID and int(current_levels.get("fleet_signal", 0)) <= 0:
		return false
	return int(current_levels.get(unlock_id, 0)) >= get_panokseon_unlock_level(upgrades)


static func get_panokseon_unlock_upgrade_id(upgrades: Dictionary = {}) -> String:
	var stats := _get_support_squadron_stats(upgrades)
	return str(stats.get("panokseon_upgrade_id", DEFAULT_PANOKSEON_UNLOCK_UPGRADE_ID))


static func get_panokseon_unlock_level(upgrades: Dictionary = {}) -> int:
	var stats := _get_support_squadron_stats(upgrades)
	return int(stats.get("panokseon_level", DEFAULT_PANOKSEON_UNLOCK_LEVEL))


static func get_support_limit_bonus_for_levels(current_levels: Dictionary, upgrades: Dictionary = {}) -> int:
	if not is_panokseon_squadron_unlocked(current_levels, upgrades):
		return 0
	var stats := _get_support_squadron_stats(upgrades)
	return int(stats.get("panokseon_squadron_limit_add", 0))


static func get_profile_id(profile: Dictionary) -> String:
	return str(profile.get("id", PROFILE_MAENGSEON_SCREEN))


static func get_profile_ship_type(profile: Dictionary) -> String:
	return str(profile.get("ship_type", "maengseon_ally"))


static func get_profile_hull_scene(profile: Dictionary) -> PackedScene:
	var hull_scene = profile.get("hull_scene", MAENGSEON_HULL_SCENE)
	return hull_scene as PackedScene if hull_scene is PackedScene else MAENGSEON_HULL_SCENE


static func get_profile_cannon_scene(profile: Dictionary) -> PackedScene:
	var cannon_scene = profile.get("cannon_scene", JOSEON_CANNON_SCENE)
	return cannon_scene as PackedScene if cannon_scene is PackedScene else JOSEON_CANNON_SCENE


static func profile_matches_runtime_ship(profile: Dictionary, ally) -> bool:
	if not is_instance_valid(ally):
		return false
	var desired_profile_id := get_profile_id(profile)
	var desired_ship_type := get_profile_ship_type(profile)
	var current_profile_id := str(ally.get_meta("support_fleet_profile", ""))
	var current_ship_type := str(ally.get("ship_type"))
	if current_profile_id != desired_profile_id:
		return false
	if current_ship_type != desired_ship_type:
		return false
	return true


static func apply_support_fleet_profile(ally, profile: Dictionary) -> void:
	if not is_instance_valid(ally):
		return
	if "ship_type" in ally:
		ally.ship_type = get_profile_ship_type(profile)
	if "hull_scene" in ally:
		ally.hull_scene = get_profile_hull_scene(profile)
	if "cannon_scene" in ally:
		ally.cannon_scene = get_profile_cannon_scene(profile)


static func _build_profile_for_slot(slot: Dictionary, slot_index: int) -> Dictionary:
	var profile_id := str(slot.get("profile_id", PROFILE_MAENGSEON_SCREEN))
	var base_profile: Dictionary = SUPPORT_PROFILES.get(profile_id, SUPPORT_PROFILES[PROFILE_MAENGSEON_SCREEN]).duplicate(true)
	base_profile["squadron_id"] = str(slot.get("squadron_id", "flagship_screen"))
	base_profile["slot_role"] = str(slot.get("slot_role", "screen_extra"))
	base_profile["slot_index"] = slot_index
	return base_profile


static func _build_fallback_slot(slot_index: int) -> Dictionary:
	return {
		"squadron_id": "flagship_screen",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "screen_extra_%d" % slot_index,
	}


static func _get_support_squadron_stats(upgrades: Dictionary) -> Dictionary:
	var panokseon_stats: Dictionary = upgrades.get(DEFAULT_PANOKSEON_UNLOCK_UPGRADE_ID, {}).get("stats", {})
	if panokseon_stats.has("panokseon_level") or panokseon_stats.has("panokseon_upgrade_id"):
		return panokseon_stats
	var signal_stats: Dictionary = upgrades.get("fleet_signal", {}).get("stats", {})
	if signal_stats.has("panokseon_level") or signal_stats.has("panokseon_upgrade_id"):
		return signal_stats
	var hull_stats: Dictionary = upgrades.get("fleet_hull", {}).get("stats", {})
	if hull_stats.has("panokseon_level"):
		var legacy_stats := hull_stats.duplicate(true)
		legacy_stats["panokseon_upgrade_id"] = "fleet_hull"
		return legacy_stats
	return signal_stats
