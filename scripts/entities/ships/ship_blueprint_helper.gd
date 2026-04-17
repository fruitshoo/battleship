extends RefCounted
class_name ShipBlueprintHelper

const STATS_PATH := "res://data/ship_stats.json"
const CREW_ORDER: Array[String] = ["general", "melee", "ranged", "fire_pot"]

const COMBAT_PROFILES := "combat_profiles"
const COMBAT_PROFILE := "combat_profile"
const SHIP_ARCHETYPES := "ship_archetypes"
const SHIP_ARCHETYPE := "ship_archetype"

const HULL_KOBAYABUNE := "res://scenes/ships/hulls/kobayabune_hull.tscn"
const HULL_SEKIBUNE := "res://scenes/ships/hulls/sekibune_hull.tscn"
const HULL_SEKIBUNE_MELEE := "res://scenes/ships/hulls/sekibune_melee_hull.tscn"
const HULL_PANOKSEON := "res://scenes/ships/hulls/panokseon_hull.tscn"
const HULL_ATAKEBUNE := "res://scenes/ships/hulls/atakebune_hull.tscn"
const HULL_MAENGSEON := "res://scenes/ships/hulls/maengseon_hull.tscn"


static func load_stats(type_name: String) -> Dictionary:
	var all_stats := load_all_stats()
	if all_stats.is_empty():
		return {}
	if not all_stats.has(type_name):
		print("[ShipBlueprint] Warning: Stats for type '%s' not found in JSON." % type_name)
		return {}
	var stats: Variant = all_stats[type_name]
	if typeof(stats) != TYPE_DICTIONARY:
		return {}
	var resolved_stats := resolve_ship_archetype(stats as Dictionary, get_ship_archetypes(all_stats))
	return resolve_combat_profile(resolved_stats, get_combat_profiles(all_stats))


static func load_all_stats() -> Dictionary:
	if not FileAccess.file_exists(STATS_PATH):
		print("[ShipBlueprint] Error: ship_stats.json not found!")
		return {}

	var file := FileAccess.open(STATS_PATH, FileAccess.READ)
	if file == null:
		print("[ShipBlueprint] Error: ship_stats.json could not be opened!")
		return {}

	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		print("[ShipBlueprint] Error: ship_stats.json is not a Dictionary.")
		return {}

	return data as Dictionary


static func get_ship_archetypes(all_stats: Dictionary = {}) -> Dictionary:
	var stats_source := all_stats
	if stats_source.is_empty():
		stats_source = load_all_stats()
	var archetypes_variant: Variant = stats_source.get(SHIP_ARCHETYPES, {})
	return archetypes_variant as Dictionary if typeof(archetypes_variant) == TYPE_DICTIONARY else {}


static func resolve_ship_archetype(stats: Dictionary, archetypes: Dictionary = {}) -> Dictionary:
	var archetype_name := get_ship_archetype_name(stats)
	if archetype_name.is_empty():
		return stats.duplicate(true)

	var archetype_source := archetypes
	if archetype_source.is_empty():
		archetype_source = get_ship_archetypes()
	var archetype_variant: Variant = archetype_source.get(archetype_name, {})
	if typeof(archetype_variant) != TYPE_DICTIONARY:
		return stats.duplicate(true)

	var resolved: Dictionary = (archetype_variant as Dictionary).duplicate(true)
	for key in stats.keys():
		resolved[key] = stats[key]
	return resolved


static func get_ship_archetype_name(stats: Dictionary, fallback: String = "") -> String:
	var value: Variant = stats.get(SHIP_ARCHETYPE, fallback)
	return str(value).strip_edges() if value != null else fallback


static func get_combat_profiles(all_stats: Dictionary = {}) -> Dictionary:
	var stats_source := all_stats
	if stats_source.is_empty():
		stats_source = load_all_stats()
	var profiles_variant: Variant = stats_source.get(COMBAT_PROFILES, {})
	return profiles_variant as Dictionary if typeof(profiles_variant) == TYPE_DICTIONARY else {}


static func resolve_combat_profile(stats: Dictionary, profiles: Dictionary = {}) -> Dictionary:
	var profile_name := get_combat_profile_name(stats)
	if profile_name.is_empty():
		return stats.duplicate()

	var profile_source := profiles
	if profile_source.is_empty():
		profile_source = get_combat_profiles()
	var profile_variant: Variant = profile_source.get(profile_name, {})
	if typeof(profile_variant) != TYPE_DICTIONARY:
		return stats.duplicate()

	var resolved: Dictionary = (profile_variant as Dictionary).duplicate()
	for key in stats.keys():
		resolved[key] = stats[key]
	return resolved


static func get_combat_profile_name(stats: Dictionary, fallback: String = "") -> String:
	var value: Variant = stats.get(COMBAT_PROFILE, fallback)
	return str(value).strip_edges() if value != null else fallback


static func get_hull_scene_path(type_name: String, stats: Dictionary = {}) -> String:
	var authored_path: String = str(stats.get("hull_scene", "")).strip_edges()
	if not authored_path.is_empty():
		return authored_path

	var type_lower := type_name.to_lower()
	if type_lower.contains("kobayabune"):
		return HULL_KOBAYABUNE
	if type_lower == "sekibune_melee":
		return HULL_SEKIBUNE_MELEE
	if type_lower.contains("panokseon"):
		return HULL_PANOKSEON
	if type_lower.contains("atakebune"):
		return HULL_ATAKEBUNE
	if type_lower.contains("maengseon"):
		return HULL_MAENGSEON
	if type_lower.contains("sekibune"):
		return HULL_SEKIBUNE
	return ""


static func load_hull_scene(type_name: String, fallback: PackedScene = null, stats: Dictionary = {}) -> PackedScene:
	var resolved_stats := stats
	if resolved_stats.is_empty():
		resolved_stats = load_stats(type_name)
	var hull_path := get_hull_scene_path(type_name, resolved_stats)
	if hull_path.is_empty():
		return fallback
	var loaded: Resource = load(hull_path)
	return loaded as PackedScene if loaded is PackedScene else fallback


static func build_crew_composition(stats: Dictionary) -> Array[String]:
	var crew: Array[String] = []
	var composition_variant: Variant = stats.get("crew_composition", {})
	if typeof(composition_variant) != TYPE_DICTIONARY:
		return crew
	var composition: Dictionary = composition_variant as Dictionary
	for soldier_type_name in CREW_ORDER:
		var count: int = int(composition.get(soldier_type_name, 0))
		for _i in range(maxi(count, 0)):
			crew.append(soldier_type_name)
	return crew


static func apply_chaser_stats(ship, stats: Dictionary) -> void:
	if not is_instance_valid(ship):
		return
	if stats.has("hull_hp"):
		ship.max_hull_hp = float(stats["hull_hp"])
	if stats.has("move_speed"):
		ship.move_speed = float(stats["move_speed"])
	if stats.has("boarders"):
		ship.boarders_count = int(stats["boarders"])
	if stats.has("has_cannons"):
		ship.has_cannons = stats["has_cannons"] == true
	if stats.has("soldier_type"):
		ship.preferred_soldier_type = str(stats["soldier_type"])
	if stats.has("separation_pad_scale"):
		ship.separation_pad_scale = float(stats["separation_pad_scale"])


static func apply_boss_stats(ship, stats: Dictionary) -> void:
	if not is_instance_valid(ship):
		return
	if stats.has("hull_hp"):
		ship.max_hull_hp = float(stats["hull_hp"])
	if stats.has("move_speed"):
		ship.move_speed = float(stats["move_speed"])
	if stats.has("tier"):
		ship.tier = int(stats["tier"])
	if stats.has("orbit_distance"):
		ship.orbit_distance = float(stats["orbit_distance"])
