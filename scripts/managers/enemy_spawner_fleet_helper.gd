class_name EnemySpawnerFleetHelper
extends RefCounted


const SPAWN_RECIPES := "spawn_recipes"
const ENCOUNTER_PROFILES := "encounter_profiles"
const ENCOUNTER_PROFILE := "encounter_profile"
const SCENARIO_TRIGGERS := "scenario_triggers"
const RECIPE := "recipe"
const SHIPS := "ships"
const FORMATION_TYPE := "formation_type"
const FLEET_PROGRESSION := "fleet_progression"
const FLEET_WEIGHTS := "fleet_weights"
const START_TIME := "start_time"
const END_TIME := "end_time"
const ID := "id"
const CONDITION := "condition"
const ACTIONS := "actions"
const TYPE := "type"
const ELAPSED_TIME := "elapsed_time"
const PROFILE := "profile"
const ENABLED := "enabled"
const ONE_SHOT := "one_shot"
const NAME := "name"
const SHIP_TYPE := "ship_type"
const ROLE := "role"
const LABEL := "label"
const FLEET_CLASS := "fleet_class"
const AUTHORING := "authoring"
const COMBAT_PROFILE := "combat_profile"
const MOVEMENT_INTENT := "movement_intent"
const MOVEMENT_MODE := "movement_mode"
const MOVEMENT_SPEED_MIN := "movement_speed_min"
const MOVEMENT_SPEED_MAX := "movement_speed_max"
const MOVEMENT_SPRINT := "movement_sprint"
const MOVEMENT_FAMILY := "movement_family"

const META_AUTHORING_COMBAT_PROFILE := "enemy_authoring_combat_profile"
const META_AUTHORING_MOVEMENT_INTENT := "enemy_authoring_movement_intent"
const META_AUTHORING_MOVEMENT_MODE := "enemy_authoring_movement_mode"
const META_AUTHORING_MOVEMENT_SPEED_MIN := "enemy_authoring_movement_speed_min"
const META_AUTHORING_MOVEMENT_SPEED_MAX := "enemy_authoring_movement_speed_max"
const META_AUTHORING_MOVEMENT_SPRINT := "enemy_authoring_movement_sprint"
const META_AUTHORING_MOVEMENT_FAMILY := "enemy_authoring_movement_family"
const META_AUTHORING_RUNTIME_APPLIED := "enemy_authoring_runtime_applied"


static func apply_enemy_spawn_rules_root(spawner, root: Dictionary) -> void:
	var spawn_recipes := parse_spawn_recipes(root.get(SPAWN_RECIPES, {}))
	var encounter_profiles := parse_encounter_profiles(root.get(ENCOUNTER_PROFILES, {}))
	if "spawn_recipes" in spawner:
		spawner.spawn_recipes = spawn_recipes
	if "encounter_profiles" in spawner:
		spawner.encounter_profiles = encounter_profiles
	if "scenario_triggers" in spawner:
		spawner.scenario_triggers = parse_scenario_triggers(root.get(SCENARIO_TRIGGERS, []))
	var general_variant: Variant = root.get("general", {})
	if typeof(general_variant) == TYPE_DICTIONARY:
		var general: Dictionary = general_variant as Dictionary
		spawner.spawn_interval = float(general.get("spawn_interval", spawner.spawn_interval))
		spawner.min_spawn_distance = float(general.get("min_spawn_distance", spawner.min_spawn_distance))
		spawner.max_spawn_distance = float(general.get("max_spawn_distance", spawner.max_spawn_distance))
		spawner.max_enemies = int(general.get("max_enemies", spawner.max_enemies))
		spawner.max_distance_limit = float(general.get("max_distance_limit", spawner.max_distance_limit))
		spawner.reposition_check_interval = float(general.get("reposition_check_interval", spawner.reposition_check_interval))

	var formation_variant: Variant = root.get("formation", {})
	if typeof(formation_variant) == TYPE_DICTIONARY:
		var formation: Dictionary = formation_variant as Dictionary
		spawner.blockade_spacing = float(formation.get("blockade_spacing", spawner.blockade_spacing))
		var profile_name := get_formation_encounter_profile(formation)
		if not profile_name.is_empty() and "active_encounter_profile" in spawner:
			spawner.active_encounter_profile = profile_name
		var fleet_templates_variant: Variant = formation.get("fleet_templates", {})
		if typeof(fleet_templates_variant) == TYPE_DICTIONARY:
			var parsed_templates: Dictionary = parse_fleet_templates(fleet_templates_variant as Dictionary, spawn_recipes)
			if not parsed_templates.is_empty():
				spawner.fleet_templates = parsed_templates
		var parsed_progression: Array[Dictionary] = resolve_fleet_progression(formation, encounter_profiles)
		if not parsed_progression.is_empty():
			spawner.fleet_progression = parsed_progression

	var mix_variant: Variant = root.get("enemy_mix", {})
	if typeof(mix_variant) == TYPE_DICTIONARY:
		var enemy_mix: Dictionary = mix_variant as Dictionary
		spawner.cannon_chance_start_time = float(enemy_mix.get("cannon_chance_start_time", spawner.cannon_chance_start_time))
		spawner.cannon_chance_ramp_duration = float(enemy_mix.get("cannon_chance_ramp_duration", spawner.cannon_chance_ramp_duration))
		spawner.cannon_chance_max = float(enemy_mix.get("cannon_chance_max", spawner.cannon_chance_max))

	var elite_variant: Variant = root.get("elite", {})
	if typeof(elite_variant) == TYPE_DICTIONARY:
		var elite_rules: Dictionary = elite_variant as Dictionary
		spawner.elite_spawn_interval = float(elite_rules.get("spawn_interval", spawner.elite_spawn_interval))
		spawner.max_elite_spawns = int(elite_rules.get("max_elite_spawns", spawner.max_elite_spawns))

	var escorts_variant: Variant = root.get("mid_boss_escort", [])
	if typeof(escorts_variant) == TYPE_ARRAY:
		var parsed_escorts: Array[Dictionary] = []
		for entry_variant in escorts_variant:
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_variant as Dictionary
			parsed_escorts.append({
				"ship_type": str(entry.get("ship_type", "kobayabune_melee")),
				"role": str(entry.get("role", "")),
				"lateral": float(entry.get("lateral", 0.0)),
				"back": float(entry.get("back", 0.0))
			})
		if not parsed_escorts.is_empty():
			spawner.mid_boss_escort_layout = parsed_escorts


static func build_default_spawn_slot_info(spawner) -> Dictionary:
	var elapsed_sec: float = spawner._get_elapsed_spawn_time()
	var cannon_chance: float = clamp((elapsed_sec - spawner.cannon_chance_start_time) / maxf(spawner.cannon_chance_ramp_duration, 0.01), 0.0, spawner.cannon_chance_max)
	if randf() > cannon_chance:
		return {"ship_type": "kobayabune_melee", "role": "vanguard", "label": "fallback_light"}
	return {"ship_type": "sekibune_cannon", "role": "gunline", "label": "fallback_heavy"}


static func apply_spawn_slot_info(enemy: Node, slot_info: Dictionary) -> void:
	if not is_instance_valid(enemy):
		return
	if "ship_type" in enemy:
		enemy.ship_type = str(slot_info.get(SHIP_TYPE, "kobayabune_melee"))
	if "formation_role_name" in enemy:
		enemy.formation_role_name = str(slot_info.get(ROLE, ""))
	enemy.set_meta("enemy_formation_role", str(slot_info.get(ROLE, "")))
	enemy.set_meta("enemy_formation_label", str(slot_info.get(LABEL, "")))
	enemy.set_meta("enemy_fleet_class", str(slot_info.get(FLEET_CLASS, "")))
	enemy.set_meta("enemy_formation_type", str(slot_info.get(FORMATION_TYPE, "")))
	enemy.set_meta("enemy_spawn_recipe", str(slot_info.get(RECIPE, "")))
	_apply_authoring_metadata(enemy, normalize_authoring_meta(slot_info.get(AUTHORING, {})))


static func apply_authoring_runtime_overrides(enemy: Node, slot_info: Dictionary) -> void:
	if not is_instance_valid(enemy):
		return
	var authoring := normalize_authoring_meta(slot_info.get(AUTHORING, {}))
	if authoring.is_empty():
		return
	_apply_authoring_metadata(enemy, authoring)
	enemy.set_meta(META_AUTHORING_RUNTIME_APPLIED, true)
	_apply_authoring_combat_profile(enemy, authoring)


static func apply_authoring_to_template(template: Array[Dictionary], authoring_meta: Variant) -> Array[Dictionary]:
	var normalized_authoring := normalize_authoring_meta(authoring_meta)
	if normalized_authoring.is_empty():
		return template
	var applied: Array[Dictionary] = []
	for slot in template:
		var next_slot := slot.duplicate(true)
		var merged_authoring := _merge_authoring_meta(next_slot.get(AUTHORING, {}), normalized_authoring)
		if merged_authoring.is_empty():
			next_slot.erase(AUTHORING)
		else:
			next_slot[AUTHORING] = merged_authoring
		applied.append(next_slot)
	return applied


static func normalize_authoring_meta(meta_variant: Variant) -> Dictionary:
	if typeof(meta_variant) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = meta_variant as Dictionary
	var meta: Dictionary = {}
	var combat_profile := str(source.get(COMBAT_PROFILE, "")).strip_edges()
	if not combat_profile.is_empty():
		meta[COMBAT_PROFILE] = combat_profile
	var movement_intent := str(source.get(MOVEMENT_INTENT, "")).strip_edges()
	if not movement_intent.is_empty():
		meta[MOVEMENT_INTENT] = movement_intent
	var movement_family := str(source.get(MOVEMENT_FAMILY, source.get("family", ""))).strip_edges()
	if not movement_family.is_empty():
		meta[MOVEMENT_FAMILY] = movement_family
	var movement_mode := str(source.get(MOVEMENT_MODE, "")).strip_edges()
	if not movement_mode.is_empty():
		meta[MOVEMENT_MODE] = movement_mode
	var speed_min_variant: Variant = source.get(MOVEMENT_SPEED_MIN, source.get("speed_min", null))
	var speed_max_variant: Variant = source.get(MOVEMENT_SPEED_MAX, source.get("speed_max", null))
	if speed_min_variant != null:
		meta[MOVEMENT_SPEED_MIN] = maxf(0.0, float(speed_min_variant))
	if speed_max_variant != null:
		meta[MOVEMENT_SPEED_MAX] = maxf(0.0, float(speed_max_variant))
	if meta.has(MOVEMENT_SPEED_MIN) and meta.has(MOVEMENT_SPEED_MAX) and float(meta[MOVEMENT_SPEED_MIN]) > float(meta[MOVEMENT_SPEED_MAX]):
		var speed_min := float(meta[MOVEMENT_SPEED_MIN])
		meta[MOVEMENT_SPEED_MIN] = float(meta[MOVEMENT_SPEED_MAX])
		meta[MOVEMENT_SPEED_MAX] = speed_min
	if source.has(MOVEMENT_SPRINT):
		meta[MOVEMENT_SPRINT] = source.get(MOVEMENT_SPRINT) == true
	elif source.has("sprint"):
		meta[MOVEMENT_SPRINT] = source.get("sprint") == true
	for label_key in ["combat_profile_label", "movement_intent_label"]:
		var label_value := str(source.get(label_key, "")).strip_edges()
		if not label_value.is_empty():
			meta[label_key] = label_value
	return meta


static func _merge_authoring_meta(base_meta: Variant, override_meta: Variant) -> Dictionary:
	var merged := normalize_authoring_meta(base_meta)
	var overrides := normalize_authoring_meta(override_meta)
	for key in overrides.keys():
		merged[key] = overrides[key]
	return merged


static func _apply_authoring_metadata(enemy: Node, authoring: Dictionary) -> void:
	if authoring.is_empty():
		return
	enemy.set_meta(AUTHORING, authoring.duplicate(true))
	var combat_profile := str(authoring.get(COMBAT_PROFILE, "")).strip_edges()
	if not combat_profile.is_empty():
		enemy.set_meta(META_AUTHORING_COMBAT_PROFILE, combat_profile)
	var movement_intent := str(authoring.get(MOVEMENT_INTENT, "")).strip_edges()
	if not movement_intent.is_empty():
		enemy.set_meta(META_AUTHORING_MOVEMENT_INTENT, movement_intent)
	var movement_family := str(authoring.get(MOVEMENT_FAMILY, "")).strip_edges()
	if not movement_family.is_empty():
		enemy.set_meta(META_AUTHORING_MOVEMENT_FAMILY, movement_family)
	var movement_mode := str(authoring.get(MOVEMENT_MODE, "")).strip_edges()
	if not movement_mode.is_empty():
		enemy.set_meta(META_AUTHORING_MOVEMENT_MODE, movement_mode)
	if authoring.has(MOVEMENT_SPEED_MIN):
		enemy.set_meta(META_AUTHORING_MOVEMENT_SPEED_MIN, float(authoring[MOVEMENT_SPEED_MIN]))
	if authoring.has(MOVEMENT_SPEED_MAX):
		enemy.set_meta(META_AUTHORING_MOVEMENT_SPEED_MAX, float(authoring[MOVEMENT_SPEED_MAX]))
	if authoring.has(MOVEMENT_SPRINT):
		enemy.set_meta(META_AUTHORING_MOVEMENT_SPRINT, authoring[MOVEMENT_SPRINT] == true)


static func _apply_authoring_combat_profile(enemy: Node, authoring: Dictionary) -> void:
	var combat_profile := str(authoring.get(COMBAT_PROFILE, "")).strip_edges()
	if combat_profile.is_empty():
		return
	var all_stats := ShipBlueprintHelper.load_all_stats()
	var profiles := ShipBlueprintHelper.get_combat_profiles(all_stats)
	var profile_variant: Variant = profiles.get(combat_profile, {})
	if typeof(profile_variant) != TYPE_DICTIONARY:
		return
	var profile: Dictionary = profile_variant as Dictionary
	if profile.has("combat_role") and "combat_role" in enemy:
		var role_name := ShipCombatModeHelper.normalize_role_name(str(profile["combat_role"]))
		enemy.set("combat_role", ShipCombatModeHelper.GUNNER_ROLE_INDEX if role_name == ShipCombatModeHelper.ROLE_GUNNER else ShipCombatModeHelper.CHARGER_ROLE_INDEX)
	if profile.has("allow_boarding") and "allow_boarding" in enemy:
		enemy.set("allow_boarding", profile["allow_boarding"] == true)
	if profile.has("preferred_range") and "preferred_combat_range" in enemy:
		enemy.set("preferred_combat_range", float(profile["preferred_range"]))
	if profile.has("range_tolerance") and "combat_range_tolerance" in enemy:
		enemy.set("combat_range_tolerance", float(profile["range_tolerance"]))
	if profile.has("retreat_distance") and "retreat_distance" in enemy:
		enemy.set("retreat_distance", float(profile["retreat_distance"]))


static func infer_role_for_ship_type(ship_type_name: String) -> String:
	var type_lower: String = ship_type_name.strip_edges().to_lower()
	if type_lower.contains("cannon") or type_lower.contains("atakebune"):
		return "gunline"
	if type_lower == "sekibune_melee":
		return "firepot"
	return "vanguard"


static func pick_enemy_scene(spawner, slot_info: Dictionary) -> PackedScene:
	var ship_type_name: String = str(slot_info.get("ship_type", "")).strip_edges().to_lower()
	var role_name: String = str(slot_info.get("role", "")).strip_edges().to_lower()
	if role_name.is_empty():
		role_name = infer_role_for_ship_type(ship_type_name)

	if role_name == "gunline" or role_name == "pressure_gunner" or ship_type_name.contains("cannon") or ship_type_name.contains("atakebune"):
		return spawner.enemy_gunner_scene if is_instance_valid(spawner.enemy_gunner_scene) else spawner.enemy_scene
	if role_name == "firepot" or ship_type_name == "sekibune_melee":
		return spawner.enemy_firepot_scene if is_instance_valid(spawner.enemy_firepot_scene) else spawner.enemy_scene
	return spawner.enemy_melee_scene if is_instance_valid(spawner.enemy_melee_scene) else spawner.enemy_scene


static func pick_fleet_template(spawner, remaining_slots: int) -> Array[Dictionary]:
	var empty_result: Array[Dictionary] = []
	var fleet_class: String = pick_fleet_class_for_time(spawner)
	if fleet_class.is_empty():
		return empty_result
	return pick_fleet_template_by_class(spawner, fleet_class, remaining_slots)


static func pick_fleet_template_by_class(spawner, fleet_class: String, remaining_slots: int) -> Array[Dictionary]:
	var empty_result: Array[Dictionary] = []
	var class_variant: Variant = spawner.fleet_templates.get(fleet_class, [])
	if typeof(class_variant) != TYPE_ARRAY:
		return empty_result
	var templates: Array = class_variant as Array
	if templates.is_empty():
		return empty_result

	var valid_templates: Array = []
	for template_variant in templates:
		if typeof(template_variant) != TYPE_ARRAY:
			continue
		var template: Array = template_variant as Array
		if template.is_empty():
			continue
		if template.size() <= remaining_slots:
			valid_templates.append(template)
	if valid_templates.is_empty():
		for template_variant in templates:
			if typeof(template_variant) != TYPE_ARRAY:
				continue
			var template: Array = template_variant as Array
			if template.is_empty():
				continue
			valid_templates.append(template)
	if valid_templates.is_empty():
		return empty_result

	var picked_variant: Variant = valid_templates.pick_random()
	if typeof(picked_variant) != TYPE_ARRAY:
		return empty_result
	var picked: Array = picked_variant as Array
	var parsed: Array[Dictionary] = []
	var limit: int = min(picked.size(), remaining_slots)
	for i in range(limit):
		var entry_variant: Variant = picked[i]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		parsed.append(entry_variant as Dictionary)
	return parsed


static func pick_fleet_template_by_recipe(spawner, recipe_name: String, remaining_slots: int) -> Array[Dictionary]:
	var empty_result: Array[Dictionary] = []
	var normalized_recipe := recipe_name.strip_edges()
	if normalized_recipe.is_empty():
		return empty_result
	for fleet_class_variant in spawner.fleet_templates.keys():
		var class_variant: Variant = spawner.fleet_templates[fleet_class_variant]
		if typeof(class_variant) != TYPE_ARRAY:
			continue
		var templates: Array = class_variant as Array
		for template_variant in templates:
			if typeof(template_variant) != TYPE_ARRAY:
				continue
			var template: Array = template_variant as Array
			if template.is_empty() or template.size() > remaining_slots:
				continue
			var first_slot_variant: Variant = template[0]
			if typeof(first_slot_variant) != TYPE_DICTIONARY:
				continue
			var slot := first_slot_variant as Dictionary
			if str(slot.get(RECIPE, "")).strip_edges() != normalized_recipe:
				continue
			var parsed: Array[Dictionary] = []
			for entry_variant in template:
				if typeof(entry_variant) == TYPE_DICTIONARY:
					parsed.append(entry_variant as Dictionary)
			return parsed
	return empty_result


static func get_spawn_slot_info(template: Array[Dictionary], index: int) -> Dictionary:
	if index < 0 or index >= template.size():
		return {}
	return template[index]


static func parse_spawn_recipes(raw_recipes_variant: Variant) -> Dictionary:
	var parsed: Dictionary = {}
	if typeof(raw_recipes_variant) != TYPE_DICTIONARY:
		return parsed
	var raw_recipes: Dictionary = raw_recipes_variant as Dictionary
	for recipe_name_variant in raw_recipes.keys():
		var recipe_name := str(recipe_name_variant).strip_edges()
		if recipe_name.is_empty():
			continue
		var recipe_variant: Variant = raw_recipes[recipe_name_variant]
		if typeof(recipe_variant) != TYPE_DICTIONARY:
			continue
		var recipe := _normalize_spawn_recipe(recipe_variant as Dictionary, recipe_name)
		if not recipe.is_empty():
			parsed[recipe_name] = recipe
	return parsed


static func parse_scenario_triggers(raw_triggers_variant: Variant) -> Array[Dictionary]:
	var parsed: Array[Dictionary] = []
	if typeof(raw_triggers_variant) != TYPE_ARRAY:
		return parsed
	var raw_triggers: Array = raw_triggers_variant as Array
	for index in range(raw_triggers.size()):
		var trigger_variant: Variant = raw_triggers[index]
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			continue
		var trigger: Dictionary = trigger_variant as Dictionary
		var trigger_id := str(trigger.get(ID, trigger.get(NAME, "trigger_%d" % index))).strip_edges()
		if trigger_id.is_empty():
			trigger_id = "trigger_%d" % index
		var condition := _normalize_scenario_condition(trigger)
		var actions := _normalize_scenario_actions(trigger.get(ACTIONS, []))
		if condition.is_empty() or actions.is_empty():
			continue
		parsed.append({
			ID: trigger_id,
			ENABLED: bool(trigger.get(ENABLED, true)),
			ONE_SHOT: bool(trigger.get(ONE_SHOT, true)),
			CONDITION: condition,
			ACTIONS: actions
		})
	return parsed


static func parse_encounter_profiles(raw_profiles_variant: Variant) -> Dictionary:
	var parsed: Dictionary = {}
	if typeof(raw_profiles_variant) != TYPE_DICTIONARY:
		return parsed
	var raw_profiles: Dictionary = raw_profiles_variant as Dictionary
	for profile_name_variant in raw_profiles.keys():
		var profile_name := str(profile_name_variant).strip_edges()
		if profile_name.is_empty():
			continue
		var profile_variant: Variant = raw_profiles[profile_name_variant]
		if typeof(profile_variant) != TYPE_DICTIONARY:
			continue
		var profile: Dictionary = profile_variant as Dictionary
		var progression_variant: Variant = profile.get(FLEET_PROGRESSION, [])
		if typeof(progression_variant) != TYPE_ARRAY:
			continue
		var progression := parse_fleet_progression(progression_variant as Array)
		if progression.is_empty():
			continue
		parsed[profile_name] = {
			NAME: str(profile.get(NAME, profile_name)),
			FLEET_PROGRESSION: progression
		}
	return parsed


static func get_formation_encounter_profile(formation: Dictionary) -> String:
	return str(formation.get(ENCOUNTER_PROFILE, "")).strip_edges()


static func resolve_fleet_progression(formation: Dictionary, encounter_profiles: Dictionary = {}) -> Array[Dictionary]:
	var profile_name := get_formation_encounter_profile(formation)
	if not profile_name.is_empty() and encounter_profiles.has(profile_name):
		var profile_variant: Variant = encounter_profiles[profile_name]
		if typeof(profile_variant) == TYPE_DICTIONARY:
			var profile: Dictionary = profile_variant as Dictionary
			var profile_progression_variant: Variant = profile.get(FLEET_PROGRESSION, [])
			if typeof(profile_progression_variant) == TYPE_ARRAY:
				var profile_progression := parse_fleet_progression(profile_progression_variant as Array)
				if not profile_progression.is_empty():
					return profile_progression

	var progression_variant: Variant = formation.get(FLEET_PROGRESSION, [])
	if typeof(progression_variant) == TYPE_ARRAY:
		return parse_fleet_progression(progression_variant as Array)
	return []


static func parse_fleet_templates(raw_templates: Dictionary, spawn_recipes: Dictionary = {}) -> Dictionary:
	var parsed: Dictionary = {}
	for class_key_variant in raw_templates.keys():
		var fleet_class: String = str(class_key_variant)
		var templates_variant: Variant = raw_templates[class_key_variant]
		if typeof(templates_variant) != TYPE_ARRAY:
			continue
		var templates_array: Array = templates_variant as Array
		var parsed_class_templates: Array = []
		for template_variant in templates_array:
			if typeof(template_variant) != TYPE_DICTIONARY:
				continue
			var template: Dictionary = _resolve_spawn_template(template_variant as Dictionary, spawn_recipes)
			var ships_variant: Variant = template.get(SHIPS, [])
			if typeof(ships_variant) != TYPE_ARRAY:
				continue
			var ships: Array = ships_variant as Array
			if ships.is_empty():
				continue
			var parsed_slots: Array[Dictionary] = []
			for slot_variant in ships:
				if typeof(slot_variant) != TYPE_DICTIONARY:
					continue
				var slot: Dictionary = slot_variant as Dictionary
				var template_name := str(template.get(NAME, template.get(RECIPE, "")))
				var parsed_slot := {
					SHIP_TYPE: str(slot.get(SHIP_TYPE, "kobayabune_melee")),
					ROLE: str(slot.get(ROLE, "")),
					LABEL: template_name,
					FLEET_CLASS: fleet_class,
					FORMATION_TYPE: str(template.get(FORMATION_TYPE, "line_abreast")),
					RECIPE: str(template.get(RECIPE, ""))
				}
				var authoring := _merge_authoring_meta(template.get(AUTHORING, {}), slot.get(AUTHORING, {}))
				if not authoring.is_empty():
					parsed_slot[AUTHORING] = authoring
				parsed_slots.append(parsed_slot)
			if not parsed_slots.is_empty():
				parsed_class_templates.append(parsed_slots)
		if not parsed_class_templates.is_empty():
			parsed[fleet_class] = parsed_class_templates
	return parsed


static func _resolve_spawn_template(template: Dictionary, spawn_recipes: Dictionary) -> Dictionary:
	var recipe_name := str(template.get(RECIPE, "")).strip_edges()
	if recipe_name.is_empty() or not spawn_recipes.has(recipe_name):
		return template.duplicate(true)

	var recipe_variant: Variant = spawn_recipes[recipe_name]
	var resolved: Dictionary = (recipe_variant as Dictionary).duplicate(true) if typeof(recipe_variant) == TYPE_DICTIONARY else {}
	for key in template.keys():
		resolved[key] = template[key]
	if not resolved.has(NAME):
		resolved[NAME] = recipe_name
	return resolved


static func _normalize_spawn_recipe(recipe: Dictionary, recipe_name: String) -> Dictionary:
	var ships_variant: Variant = recipe.get(SHIPS, [])
	if typeof(ships_variant) != TYPE_ARRAY:
		return {}
	var ships: Array = ships_variant as Array
	if ships.is_empty():
		return {}

	var normalized_ships: Array[Dictionary] = []
	for slot_variant in ships:
		if typeof(slot_variant) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_variant as Dictionary
		var normalized_slot := {
			SHIP_TYPE: str(slot.get(SHIP_TYPE, "kobayabune_melee")),
			ROLE: str(slot.get(ROLE, ""))
		}
		var slot_authoring := normalize_authoring_meta(slot.get(AUTHORING, {}))
		if not slot_authoring.is_empty():
			normalized_slot[AUTHORING] = slot_authoring
		normalized_ships.append(normalized_slot)
	if normalized_ships.is_empty():
		return {}

	var normalized_recipe := {
		NAME: str(recipe.get(NAME, recipe_name)),
		FORMATION_TYPE: str(recipe.get(FORMATION_TYPE, "line_abreast")),
		SHIPS: normalized_ships
	}
	var recipe_authoring := normalize_authoring_meta(recipe.get(AUTHORING, {}))
	if not recipe_authoring.is_empty():
		normalized_recipe[AUTHORING] = recipe_authoring
	return normalized_recipe


static func get_formation_offset(spawner, formation_type: String, index: int, spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	match formation_type:
		"column":
			return get_column_offset(spawner, index, spawn_count, forward_dir)
		"wedge":
			return get_wedge_offset(spawner, index, spawn_count, right_dir, forward_dir)
		"escort":
			return get_escort_offset(spawner, index, spawn_count, right_dir, forward_dir)
		"echelon":
			return get_echelon_offset(spawner, index, spawn_count, right_dir, forward_dir)
		_:
			return get_line_abreast_offset(spawner, index, spawn_count, right_dir)


static func get_line_abreast_offset(spawner, index: int, spawn_count: int, right_dir: Vector3) -> Vector3:
	var offset_multiplier: float = index - (spawn_count - 1) / 2.0
	return right_dir * (offset_multiplier * spawner.blockade_spacing)


static func get_column_offset(spawner, index: int, spawn_count: int, forward_dir: Vector3) -> Vector3:
	var offset_multiplier: float = index - (spawn_count - 1) / 2.0
	return forward_dir * (-offset_multiplier * spawner.blockade_spacing * 0.95)


static func get_wedge_offset(spawner, index: int, spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	if spawn_count <= 1:
		return Vector3.ZERO
	if spawn_count == 2:
		var side_sign: float = -1.0 if index == 0 else 1.0
		return right_dir * (side_sign * spawner.blockade_spacing * 0.45) + forward_dir * (spawner.blockade_spacing * 0.4)

	var offsets: Array[Vector3] = [Vector3.ZERO]
	offsets.append(right_dir * (-spawner.blockade_spacing * 0.7) + forward_dir * (spawner.blockade_spacing * 0.55))
	offsets.append(right_dir * (spawner.blockade_spacing * 0.7) + forward_dir * (spawner.blockade_spacing * 0.55))
	if spawn_count >= 4:
		offsets.append(right_dir * (-spawner.blockade_spacing * 1.35) + forward_dir * (spawner.blockade_spacing * 1.05))
	if spawn_count >= 5:
		offsets.append(right_dir * (spawner.blockade_spacing * 1.35) + forward_dir * (spawner.blockade_spacing * 1.05))
	if index < offsets.size():
		return offsets[index]
	return get_line_abreast_offset(spawner, index, spawn_count, right_dir)


static func get_escort_offset(spawner, index: int, spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	if spawn_count <= 1:
		return Vector3.ZERO
	if spawn_count == 2:
		return get_line_abreast_offset(spawner, index, spawn_count, right_dir)
	if index == 0:
		return Vector3.ZERO
	if index == 1:
		return right_dir * (-spawner.blockade_spacing * 0.85) + forward_dir * (spawner.blockade_spacing * 0.45)
	if index == 2:
		return right_dir * (spawner.blockade_spacing * 0.85) + forward_dir * (spawner.blockade_spacing * 0.45)
	return forward_dir * (spawner.blockade_spacing * 0.95)


static func get_echelon_offset(spawner, index: int, _spawn_count: int, right_dir: Vector3, forward_dir: Vector3) -> Vector3:
	var step: float = float(index)
	return right_dir * (step * spawner.blockade_spacing * 0.62) + forward_dir * (step * spawner.blockade_spacing * 0.62)


static func parse_fleet_progression(raw_progression: Array) -> Array[Dictionary]:
	var parsed: Array[Dictionary] = []
	for row_variant in raw_progression:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant as Dictionary
		var weights := parse_fleet_weights(row.get(FLEET_WEIGHTS, {}))
		if weights.is_empty():
			weights = parse_fleet_weights(row)
		var parsed_row: Dictionary = {
			START_TIME: float(row.get(START_TIME, 0.0)),
			END_TIME: float(row.get(END_TIME, 9999.0)),
			FLEET_WEIGHTS: weights
		}
		for fleet_class_variant in weights.keys():
			var fleet_class := str(fleet_class_variant)
			parsed_row["%s_weight" % fleet_class] = float(weights[fleet_class_variant])
		parsed.append(parsed_row)
	return parsed


static func parse_fleet_weights(raw_weights_variant: Variant) -> Dictionary:
	var parsed: Dictionary = {}
	if typeof(raw_weights_variant) != TYPE_DICTIONARY:
		return parsed
	var raw_weights: Dictionary = raw_weights_variant as Dictionary
	for key_variant in raw_weights.keys():
		var fleet_class := str(key_variant).strip_edges()
		if fleet_class.is_empty():
			continue
		if [START_TIME, END_TIME, FLEET_WEIGHTS, FLEET_PROGRESSION, NAME, ENCOUNTER_PROFILE].has(fleet_class):
			continue
		if fleet_class.ends_with("_weight"):
			fleet_class = fleet_class.substr(0, fleet_class.length() - "_weight".length())
		if fleet_class.is_empty():
			continue
		var weight_variant: Variant = raw_weights[key_variant]
		if typeof(weight_variant) != TYPE_FLOAT and typeof(weight_variant) != TYPE_INT:
			continue
		var weight: float = maxf(0.0, float(weight_variant))
		if weight <= 0.0:
			continue
		parsed[fleet_class] = weight
	return parsed


static func set_encounter_profile(spawner, profile_name: String) -> bool:
	var normalized_name := profile_name.strip_edges()
	if normalized_name.is_empty():
		return false
	if not ("encounter_profiles" in spawner):
		return false
	var profiles_variant: Variant = spawner.encounter_profiles
	if typeof(profiles_variant) != TYPE_DICTIONARY:
		return false
	var profiles: Dictionary = profiles_variant as Dictionary
	if not profiles.has(normalized_name):
		return false
	var profile_variant: Variant = profiles[normalized_name]
	if typeof(profile_variant) != TYPE_DICTIONARY:
		return false
	var profile: Dictionary = profile_variant as Dictionary
	var progression_variant: Variant = profile.get(FLEET_PROGRESSION, [])
	if typeof(progression_variant) != TYPE_ARRAY:
		return false
	var progression := parse_fleet_progression(progression_variant as Array)
	if progression.is_empty():
		return false
	spawner.fleet_progression = progression
	if "active_encounter_profile" in spawner:
		spawner.active_encounter_profile = normalized_name
	return true


static func process_scenario_triggers(spawner) -> void:
	if not ("scenario_triggers" in spawner):
		return
	var triggers_variant: Variant = spawner.scenario_triggers
	if typeof(triggers_variant) != TYPE_ARRAY:
		return
	var triggers: Array = triggers_variant as Array
	if triggers.is_empty():
		return
	var elapsed_sec: float = spawner._get_elapsed_spawn_time() if spawner.has_method("_get_elapsed_spawn_time") else 0.0
	for trigger_variant in triggers:
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			continue
		var trigger: Dictionary = trigger_variant as Dictionary
		if not bool(trigger.get(ENABLED, true)):
			continue
		var trigger_id := str(trigger.get(ID, "")).strip_edges()
		if _is_scenario_trigger_already_fired(spawner, trigger_id) and bool(trigger.get(ONE_SHOT, true)):
			continue
		if not _scenario_condition_met(trigger, elapsed_sec):
			continue
		_apply_scenario_trigger(spawner, trigger)
		_mark_scenario_trigger_fired(spawner, trigger_id)


static func run_scenario_trigger_by_id(spawner, trigger_id: String) -> bool:
	var normalized_id := trigger_id.strip_edges()
	if normalized_id.is_empty():
		return false
	if not ("scenario_triggers" in spawner):
		return false
	var triggers_variant: Variant = spawner.scenario_triggers
	if typeof(triggers_variant) != TYPE_ARRAY:
		return false
	var triggers: Array = triggers_variant as Array
	for trigger_variant in triggers:
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			continue
		var trigger := trigger_variant as Dictionary
		if str(trigger.get(ID, "")).strip_edges() != normalized_id:
			continue
		_apply_scenario_trigger(spawner, trigger)
		_mark_scenario_trigger_fired(spawner, normalized_id)
		return true
	return false


static func pick_fleet_class_for_time(spawner) -> String:
	var elapsed_sec: float = spawner._get_elapsed_spawn_time()
	for row in spawner.fleet_progression:
		var start_time_value: float = float(row.get(START_TIME, 0.0))
		var end_time_value: float = float(row.get(END_TIME, 9999.0))
		if elapsed_sec < start_time_value or elapsed_sec >= end_time_value:
			continue
		return pick_weighted_fleet_class(row)
	return "mixed"


static func pick_weighted_fleet_class(weights: Dictionary) -> String:
	var fleet_weights := parse_fleet_weights(weights.get(FLEET_WEIGHTS, {}))
	if fleet_weights.is_empty():
		fleet_weights = parse_fleet_weights(weights)

	var fleet_classes: Array[String] = []
	var total_weight: float = 0.0
	for fleet_class_variant in fleet_weights.keys():
		var fleet_class := str(fleet_class_variant)
		var weight: float = maxf(0.0, float(fleet_weights[fleet_class_variant]))
		if weight <= 0.0:
			continue
		fleet_classes.append(fleet_class)
		total_weight += weight
	if total_weight <= 0.0:
		return "mixed"
	var roll: float = randf() * total_weight
	for fleet_class in fleet_classes:
		var weight: float = maxf(0.0, float(fleet_weights[fleet_class]))
		if roll < weight:
			return fleet_class
		roll -= weight
	return "mixed"


static func _normalize_scenario_condition(trigger: Dictionary) -> Dictionary:
	var raw_condition_variant: Variant = trigger.get(CONDITION, {})
	var condition: Dictionary = raw_condition_variant as Dictionary if typeof(raw_condition_variant) == TYPE_DICTIONARY else {}
	var elapsed_time: float = -1.0
	if condition.has(ELAPSED_TIME):
		elapsed_time = float(condition.get(ELAPSED_TIME, -1.0))
	elif trigger.has(ELAPSED_TIME):
		elapsed_time = float(trigger.get(ELAPSED_TIME, -1.0))
	if elapsed_time < 0.0:
		return {}
	return {ELAPSED_TIME: elapsed_time}


static func _normalize_scenario_actions(raw_actions_variant: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if typeof(raw_actions_variant) != TYPE_ARRAY:
		return normalized
	var raw_actions: Array = raw_actions_variant as Array
	for action_variant in raw_actions:
		if typeof(action_variant) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = action_variant as Dictionary
		var action_type := str(action.get(TYPE, "")).strip_edges()
		if action_type.is_empty():
			continue
		var normalized_action := action.duplicate(true)
		normalized_action[TYPE] = action_type
		normalized.append(normalized_action)
	return normalized


static func _scenario_condition_met(trigger: Dictionary, elapsed_sec: float) -> bool:
	var condition_variant: Variant = trigger.get(CONDITION, {})
	if typeof(condition_variant) != TYPE_DICTIONARY:
		return false
	var condition: Dictionary = condition_variant as Dictionary
	var elapsed_time := float(condition.get(ELAPSED_TIME, -1.0))
	return elapsed_time >= 0.0 and elapsed_sec >= elapsed_time


static func _apply_scenario_trigger(spawner, trigger: Dictionary) -> void:
	var actions_variant: Variant = trigger.get(ACTIONS, [])
	if typeof(actions_variant) != TYPE_ARRAY:
		return
	var actions: Array = actions_variant as Array
	for action_variant in actions:
		if typeof(action_variant) != TYPE_DICTIONARY:
			continue
		_apply_scenario_action(spawner, action_variant as Dictionary)


static func _apply_scenario_action(spawner, action: Dictionary) -> void:
	var action_type := str(action.get(TYPE, "")).strip_edges()
	match action_type:
		"set_encounter_profile":
			set_encounter_profile(spawner, str(action.get(PROFILE, "")))
		"spawn_fleet":
			var fleet_class := str(action.get(FLEET_CLASS, "")).strip_edges()
			var fallback_slots: int = int(spawner.max_enemies) if "max_enemies" in spawner else 1
			var max_slots: int = maxi(1, int(action.get("max_slots", fallback_slots)))
			var template: Array[Dictionary] = pick_fleet_template_by_class(spawner, fleet_class, max_slots)
			if not template.is_empty() and spawner.has_method("_spawn_enemy_from_template"):
				spawner.call("_spawn_enemy_from_template", template, min(template.size(), max_slots))
		"spawn_recipe":
			var recipe_name := str(action.get(RECIPE, "")).strip_edges()
			var recipe_fallback_slots: int = int(spawner.max_enemies) if "max_enemies" in spawner else 1
			var recipe_max_slots: int = maxi(1, int(action.get("max_slots", recipe_fallback_slots)))
			var recipe_template: Array[Dictionary] = pick_fleet_template_by_recipe(spawner, recipe_name, recipe_max_slots)
			recipe_template = apply_authoring_to_template(recipe_template, action.get(AUTHORING, {}))
			if not recipe_template.is_empty() and spawner.has_method("_spawn_enemy_from_template"):
				spawner.call("_spawn_enemy_from_template", recipe_template, min(recipe_template.size(), recipe_max_slots))
		"spawn_ship":
			var ship_type_name := str(action.get(SHIP_TYPE, "")).strip_edges()
			if ship_type_name.is_empty():
				return
			if spawner.has_method("debug_spawn_ship"):
				spawner.call(
					"debug_spawn_ship",
					ship_type_name,
					float(action.get("distance", 40.0)),
					float(action.get("lateral_offset", 0.0)),
					normalize_authoring_meta(action.get(AUTHORING, {}))
				)
			elif spawner.has_method("_spawn_enemy_from_template"):
				var ship_template: Array[Dictionary] = [{
					SHIP_TYPE: ship_type_name,
					ROLE: infer_role_for_ship_type(ship_type_name),
					AUTHORING: normalize_authoring_meta(action.get(AUTHORING, {}))
				}]
				spawner.call("_spawn_enemy_from_template", ship_template, 1)
		"run_scenario_trigger":
			var trigger_id := str(action.get("trigger", "")).strip_edges()
			if not trigger_id.is_empty():
				run_scenario_trigger_by_id(spawner, trigger_id)
		"spawn_mid_boss":
			if spawner.has_method("_spawn_elite_ship"):
				spawner.call("_spawn_elite_ship")
		"trigger_boss_event":
			if spawner.has_method("trigger_boss_event"):
				spawner.call("trigger_boss_event")
		"stop_regular_spawns":
			if "regular_spawn_stopped" in spawner:
				spawner.regular_spawn_stopped = bool(action.get("value", true))


static func _is_scenario_trigger_already_fired(spawner, trigger_id: String) -> bool:
	if trigger_id.is_empty():
		return false
	if not ("triggered_scenario_ids" in spawner):
		return false
	var fired_variant: Variant = spawner.triggered_scenario_ids
	if typeof(fired_variant) != TYPE_DICTIONARY:
		return false
	return (fired_variant as Dictionary).has(trigger_id)


static func _mark_scenario_trigger_fired(spawner, trigger_id: String) -> void:
	if trigger_id.is_empty() or not ("triggered_scenario_ids" in spawner):
		return
	if typeof(spawner.triggered_scenario_ids) != TYPE_DICTIONARY:
		spawner.triggered_scenario_ids = {}
	spawner.triggered_scenario_ids[trigger_id] = true
