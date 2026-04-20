extends RefCounted
class_name PlayerShipSupportSquadronHelper

const MAENGSEON_HULL_SCENE = preload("res://scenes/ships/hulls/maengseon_hull.tscn")
const PANOKSEON_HULL_SCENE = preload("res://scenes/ships/hulls/panokseon_hull.tscn")
const JOSEON_CANNON_SCENE = preload("res://scenes/entities/launchers/cannon_joseon.tscn")

const PROFILE_MAENGSEON_SCREEN := "maengseon_screen"
const PROFILE_PANOKSEON_ESCORT := "panokseon_escort"
const DEFAULT_PANOKSEON_UNLOCK_UPGRADE_ID := "fleet_signal"
const DEFAULT_PANOKSEON_UNLOCK_LEVEL := 2

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
		"slot_role": "artillery_screen_left",
	},
	{
		"squadron_id": "panokseon_artillery",
		"profile_id": PROFILE_MAENGSEON_SCREEN,
		"slot_role": "artillery_screen_right",
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

	plan.append(flagship_slots[0])
	if panokseon_unlocked:
		plan.append(panokseon_slots[0])
	for i in range(1, flagship_slots.size()):
		plan.append(flagship_slots[i])
	if panokseon_unlocked:
		for i in range(1, panokseon_slots.size()):
			plan.append(panokseon_slots[i])
	return plan


static func is_panokseon_squadron_unlocked(current_levels: Dictionary, upgrades: Dictionary = {}) -> bool:
	var unlock_id := get_panokseon_unlock_upgrade_id(upgrades)
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


static func apply_support_fleet_profile(ally, profile: Dictionary) -> void:
	if not is_instance_valid(ally):
		return
	if "ship_type" in ally:
		ally.ship_type = str(profile.get("ship_type", "maengseon_ally"))
	if "hull_scene" in ally:
		var hull_scene = profile.get("hull_scene", MAENGSEON_HULL_SCENE)
		if hull_scene is PackedScene:
			ally.hull_scene = hull_scene
	if "cannon_scene" in ally:
		var cannon_scene = profile.get("cannon_scene", JOSEON_CANNON_SCENE)
		if cannon_scene is PackedScene:
			ally.cannon_scene = cannon_scene


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
	var signal_stats: Dictionary = upgrades.get("fleet_signal", {}).get("stats", {})
	if signal_stats.has("panokseon_level") or signal_stats.has("panokseon_upgrade_id"):
		return signal_stats
	var hull_stats: Dictionary = upgrades.get("fleet_hull", {}).get("stats", {})
	if hull_stats.has("panokseon_level"):
		var legacy_stats := hull_stats.duplicate(true)
		legacy_stats["panokseon_upgrade_id"] = "fleet_hull"
		return legacy_stats
	return signal_stats
