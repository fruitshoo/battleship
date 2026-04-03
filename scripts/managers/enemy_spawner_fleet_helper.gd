class_name EnemySpawnerFleetHelper
extends RefCounted


static func apply_enemy_spawn_rules_root(spawner, root: Dictionary) -> void:
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
		var fleet_templates_variant: Variant = formation.get("fleet_templates", {})
		if typeof(fleet_templates_variant) == TYPE_DICTIONARY:
			var parsed_templates: Dictionary = parse_fleet_templates(fleet_templates_variant as Dictionary)
			if not parsed_templates.is_empty():
				spawner.fleet_templates = parsed_templates
		var progression_variant: Variant = formation.get("fleet_progression", [])
		if typeof(progression_variant) == TYPE_ARRAY:
			var parsed_progression: Array[Dictionary] = parse_fleet_progression(progression_variant as Array)
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
		enemy.ship_type = str(slot_info.get("ship_type", "kobayabune_melee"))
	if "formation_role_name" in enemy:
		enemy.formation_role_name = str(slot_info.get("role", ""))
	enemy.set_meta("enemy_formation_role", str(slot_info.get("role", "")))
	enemy.set_meta("enemy_formation_label", str(slot_info.get("label", "")))
	enemy.set_meta("enemy_fleet_class", str(slot_info.get("fleet_class", "")))
	enemy.set_meta("enemy_formation_type", str(slot_info.get("formation_type", "")))


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


static func get_spawn_slot_info(template: Array[Dictionary], index: int) -> Dictionary:
	if index < 0 or index >= template.size():
		return {}
	return template[index]


static func parse_fleet_templates(raw_templates: Dictionary) -> Dictionary:
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
			var template: Dictionary = template_variant as Dictionary
			var ships_variant: Variant = template.get("ships", [])
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
				parsed_slots.append({
					"ship_type": str(slot.get("ship_type", "kobayabune_melee")),
					"role": str(slot.get("role", "")),
					"label": str(template.get("name", "")),
					"fleet_class": fleet_class,
					"formation_type": str(template.get("formation_type", "line_abreast"))
				})
			if not parsed_slots.is_empty():
				parsed_class_templates.append(parsed_slots)
		if not parsed_class_templates.is_empty():
			parsed[fleet_class] = parsed_class_templates
	return parsed


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
		parsed.append({
			"start_time": float(row.get("start_time", 0.0)),
			"end_time": float(row.get("end_time", 9999.0)),
			"light_weight": float(row.get("light_weight", 0.0)),
			"mixed_weight": float(row.get("mixed_weight", 0.0)),
			"heavy_weight": float(row.get("heavy_weight", 0.0))
		})
	return parsed


static func pick_fleet_class_for_time(spawner) -> String:
	var elapsed_sec: float = spawner._get_elapsed_spawn_time()
	for row in spawner.fleet_progression:
		var start_time_value: float = float(row.get("start_time", 0.0))
		var end_time_value: float = float(row.get("end_time", 9999.0))
		if elapsed_sec < start_time_value or elapsed_sec >= end_time_value:
			continue
		return pick_weighted_fleet_class(row)
	return "mixed"


static func pick_weighted_fleet_class(weights: Dictionary) -> String:
	var light_weight: float = maxf(0.0, float(weights.get("light_weight", 0.0)))
	var mixed_weight: float = maxf(0.0, float(weights.get("mixed_weight", 0.0)))
	var heavy_weight: float = maxf(0.0, float(weights.get("heavy_weight", 0.0)))
	var total_weight: float = light_weight + mixed_weight + heavy_weight
	if total_weight <= 0.0:
		return "mixed"
	var roll: float = randf() * total_weight
	if roll < light_weight:
		return "light"
	roll -= light_weight
	if roll < mixed_weight:
		return "mixed"
	return "heavy"
