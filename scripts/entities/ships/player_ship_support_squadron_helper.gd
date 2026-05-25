extends RefCounted
class_name PlayerShipSupportSquadronHelper

const MAENGSEON_HULL_SCENE = preload("res://scenes/ships/hulls/maengseon_hull.tscn")
const PANOK_HULL_SCENE = preload("res://scenes/ships/hulls/panok_hull.tscn")
const GEOBUKSEON_HULL_SCENE = preload("res://scenes/ships/hulls/geobukseon_hull.tscn")
const JOSEON_CANNON_SCENE = preload("res://scenes/entities/launchers/cannon_joseon.tscn")
const SUPPORT_MAENGSEON_SCENE_PATH := "res://scenes/ships/support_maengseon_ship.tscn"
const SUPPORT_PANOKSEON_SCENE_PATH := "res://scenes/ships/support_panokseon_ship.tscn"
const SUPPORT_GENERIC_SCENE_PATH := "res://scenes/ships/support_ship.tscn"

const PROFILE_MAENGSEON_SCREEN := "maengseon_screen"
const PROFILE_PANOKSEON_ESCORT := "panokseon_escort"
const PROFILE_GEOBUKSEON_GUARD := "geobukseon_guard"
const DEFAULT_PANOKSEON_UNLOCK_UPGRADE_ID := "panokseon_upgrade"
const DEFAULT_PANOKSEON_UNLOCK_LEVEL := 1
const DEFAULT_GEOBUKSEON_UNLOCK_UPGRADE_ID := "geobukseon_upgrade"
const DEFAULT_GEOBUKSEON_UNLOCK_LEVEL := 1

# The profile ship_type values still use older *_ally ids because upgrade,
# harness, and scene data reference them directly. Treat them as support profile
# ids until a migration updates saved/test fixture data together.
const SUPPORT_PROFILES := {
	PROFILE_MAENGSEON_SCREEN: {
		"id": PROFILE_MAENGSEON_SCREEN,
		"ship_type": "maengseon_ally",
		"role": "screen_rescue",
		"crew_count": 4,
		"ship_scene_path": SUPPORT_MAENGSEON_SCENE_PATH,
		"hull_scene": MAENGSEON_HULL_SCENE,
		"cannon_scene": JOSEON_CANNON_SCENE,
	},
	PROFILE_PANOKSEON_ESCORT: {
		"id": PROFILE_PANOKSEON_ESCORT,
		"ship_type": "panokseon_ally",
		"role": "artillery_escort",
		"crew_count": 6,
		"ship_scene_path": SUPPORT_PANOKSEON_SCENE_PATH,
		"hull_scene": PANOK_HULL_SCENE,
		"cannon_scene": JOSEON_CANNON_SCENE,
	},
	PROFILE_GEOBUKSEON_GUARD: {
		"id": PROFILE_GEOBUKSEON_GUARD,
		"ship_type": "geobukseon_ally",
		"role": "armored_guard",
		"crew_count": 6,
		"ship_scene_path": SUPPORT_GENERIC_SCENE_PATH,
		"hull_scene": GEOBUKSEON_HULL_SCENE,
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

const GEOBUKSEON_GUARD_SLOTS := [
	{
		"squadron_id": "geobukseon_guard",
		"profile_id": PROFILE_GEOBUKSEON_GUARD,
		"slot_role": "armored_guard",
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
	var geobukseon_slots := GEOBUKSEON_GUARD_SLOTS.duplicate(true)
	var flagship_screen_unlocked := int(current_levels.get("fleet_signal", 0)) > 0
	var panokseon_unlocked := is_panokseon_squadron_unlocked(current_levels, upgrades)
	var geobukseon_unlocked := is_geobukseon_squadron_unlocked(current_levels, upgrades)

	if flagship_screen_unlocked and not flagship_slots.is_empty():
		plan.append(flagship_slots[0])
	if panokseon_unlocked:
		plan.append(panokseon_slots[0])
	if geobukseon_unlocked:
		plan.append(geobukseon_slots[0])
	if panokseon_unlocked:
		for i in range(1, panokseon_slots.size()):
			plan.append(panokseon_slots[i])
		if flagship_screen_unlocked:
			for i in range(1, flagship_slots.size()):
				plan.append(flagship_slots[i])
		return plan
	if flagship_screen_unlocked:
		for i in range(1, flagship_slots.size()):
			plan.append(flagship_slots[i])
	return plan


static func is_panokseon_squadron_unlocked(current_levels: Dictionary, upgrades: Dictionary = {}) -> bool:
	var unlock_id := get_panokseon_unlock_upgrade_id(upgrades)
	return int(current_levels.get(unlock_id, 0)) >= get_panokseon_unlock_level(upgrades)


static func is_geobukseon_squadron_unlocked(current_levels: Dictionary, upgrades: Dictionary = {}) -> bool:
	var unlock_id := get_geobukseon_unlock_upgrade_id(upgrades)
	if upgrades.has(unlock_id):
		var unlock_data: Dictionary = upgrades.get(unlock_id, {})
		if unlock_data.get("disabled", false) == true:
			return false
	if unlock_id == DEFAULT_GEOBUKSEON_UNLOCK_UPGRADE_ID and int(current_levels.get("fleet_signal", 0)) <= 0:
		return false
	return int(current_levels.get(unlock_id, 0)) >= get_geobukseon_unlock_level(upgrades)


static func get_panokseon_unlock_upgrade_id(upgrades: Dictionary = {}) -> String:
	var stats := _get_support_squadron_stats(upgrades)
	return str(stats.get("panokseon_upgrade_id", DEFAULT_PANOKSEON_UNLOCK_UPGRADE_ID))


static func get_panokseon_unlock_level(upgrades: Dictionary = {}) -> int:
	var stats := _get_support_squadron_stats(upgrades)
	return int(stats.get("panokseon_level", DEFAULT_PANOKSEON_UNLOCK_LEVEL))


static func get_geobukseon_unlock_upgrade_id(upgrades: Dictionary = {}) -> String:
	var stats := _get_geobukseon_squadron_stats(upgrades)
	return str(stats.get("geobukseon_upgrade_id", DEFAULT_GEOBUKSEON_UNLOCK_UPGRADE_ID))


static func get_geobukseon_unlock_level(upgrades: Dictionary = {}) -> int:
	var stats := _get_geobukseon_squadron_stats(upgrades)
	return int(stats.get("geobukseon_level", DEFAULT_GEOBUKSEON_UNLOCK_LEVEL))


static func get_support_limit_bonus_for_levels(current_levels: Dictionary, upgrades: Dictionary = {}) -> int:
	var limit_bonus := 0
	if is_panokseon_squadron_unlocked(current_levels, upgrades):
		var panokseon_stats := _get_support_squadron_stats(upgrades)
		limit_bonus += int(panokseon_stats.get("panokseon_squadron_limit_add", 0))
	if is_geobukseon_squadron_unlocked(current_levels, upgrades):
		var geobukseon_stats := _get_geobukseon_squadron_stats(upgrades)
		limit_bonus += int(geobukseon_stats.get("geobukseon_squadron_limit_add", 0))
	return limit_bonus


static func get_profile_id(profile: Dictionary) -> String:
	return str(profile.get("id", PROFILE_MAENGSEON_SCREEN))


static func get_profile_ship_type(profile: Dictionary) -> String:
	return str(profile.get("ship_type", "maengseon_ally"))


static func get_profile_hull_scene(profile: Dictionary) -> PackedScene:
	var hull_scene = profile.get("hull_scene", MAENGSEON_HULL_SCENE)
	return hull_scene as PackedScene if hull_scene is PackedScene else MAENGSEON_HULL_SCENE


static func get_profile_ship_scene(profile: Dictionary) -> PackedScene:
	var ship_scene = profile.get("ship_scene", null)
	if ship_scene is PackedScene:
		return ship_scene
	var scene_path := str(profile.get("ship_scene_path", SUPPORT_MAENGSEON_SCENE_PATH)).strip_edges()
	var loaded_scene := load(scene_path)
	return loaded_scene as PackedScene if loaded_scene is PackedScene else load(SUPPORT_MAENGSEON_SCENE_PATH) as PackedScene


static func get_profile_cannon_scene(profile: Dictionary) -> PackedScene:
	var cannon_scene = profile.get("cannon_scene", JOSEON_CANNON_SCENE)
	return cannon_scene as PackedScene if cannon_scene is PackedScene else JOSEON_CANNON_SCENE


static func get_profile_crew_count(profile: Dictionary) -> int:
	return maxi(1, int(profile.get("crew_count", 4)))


static func profile_matches_runtime_ship(profile: Dictionary, support_ship) -> bool:
	if not is_instance_valid(support_ship):
		return false
	var desired_profile_id := get_profile_id(profile)
	var desired_ship_type := get_profile_ship_type(profile)
	var current_profile_id := str(support_ship.get_meta("support_fleet_profile", ""))
	var current_ship_type := str(support_ship.get("ship_type"))
	if current_profile_id != desired_profile_id:
		return false
	if current_ship_type != desired_ship_type:
		return false
	return true


static func apply_support_fleet_profile(support_ship, profile: Dictionary) -> void:
	if not is_instance_valid(support_ship):
		return
	if "ship_type" in support_ship:
		support_ship.ship_type = get_profile_ship_type(profile)
	if "hull_scene" in support_ship:
		support_ship.hull_scene = get_profile_hull_scene(profile)
	if "cannon_scene" in support_ship:
		support_ship.cannon_scene = get_profile_cannon_scene(profile)
	var crew_count := get_profile_crew_count(profile)
	if "initial_crew_count" in support_ship:
		support_ship.initial_crew_count = crew_count
	if "max_crew" in support_ship:
		support_ship.max_crew = maxi(int(support_ship.max_crew), crew_count)
	if support_ship.has_method("set_player_fleet_crew_target_count"):
		support_ship.call("set_player_fleet_crew_target_count", crew_count)
	elif "max_minion_crew" in support_ship:
		support_ship.max_minion_crew = crew_count


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


static func _get_geobukseon_squadron_stats(upgrades: Dictionary) -> Dictionary:
	var geobukseon_stats: Dictionary = upgrades.get(DEFAULT_GEOBUKSEON_UNLOCK_UPGRADE_ID, {}).get("stats", {})
	if geobukseon_stats.has("geobukseon_level") or geobukseon_stats.has("geobukseon_upgrade_id"):
		return geobukseon_stats
	return {}
