class_name LevelManagerProgressionHelper
extends RefCounted

static func add_score(lm: Node, points: int) -> void:
	if _env_flag_enabled("BATTLESHIP_DISABLE_RUNTIME_REWARDS"):
		return
	lm.current_score += points
	lm.enemies_killed += 1
	lm.score_changed.emit(lm.current_score)

	if is_instance_valid(SaveManager):
		var point_gain: int = max(0, points)
		if point_gain > 0:
			SaveManager.add_gold(point_gain)

	if lm.hud:
		lm.hud.update_score(lm.current_score)

static func add_ship_sunk(lm: Node, count: int = 1, ship: Variant = null) -> void:
	var safe_count: int = max(0, count)
	lm.ships_sunk += safe_count
	_record_defeated_ship(lm, ship, "sunk", safe_count)
	if lm.hud and lm.hud.has_method("update_combat_stats"):
		lm.hud.update_combat_stats(lm.ships_sunk, lm.ships_derelicted, lm.soldiers_killed, lm.soldiers_slain, lm.soldiers_drowned)

static func add_ship_derelict(lm: Node, count: int = 1, ship: Variant = null) -> void:
	var safe_count: int = max(0, count)
	lm.ships_derelicted += safe_count
	_record_defeated_ship(lm, ship, "derelicted", safe_count)
	if lm.hud and lm.hud.has_method("update_combat_stats"):
		lm.hud.update_combat_stats(lm.ships_sunk, lm.ships_derelicted, lm.soldiers_killed, lm.soldiers_slain, lm.soldiers_drowned)

static func add_soldier_kill(lm: Node, count: int = 1, cause: String = "combat") -> void:
	var total: int = max(0, count)
	lm.soldiers_killed += total
	if cause == "drowned":
		lm.soldiers_drowned += total
	else:
		lm.soldiers_slain += total
	if lm.hud and lm.hud.has_method("update_combat_stats"):
		lm.hud.update_combat_stats(lm.ships_sunk, lm.ships_derelicted, lm.soldiers_killed, lm.soldiers_slain, lm.soldiers_drowned)

static func add_bonus_xp_from_soldier_kill(lm: Node, kill_count: int = 1) -> void:
	var k: int = max(0, kill_count)
	if k <= 0:
		return
	add_xp(lm, lm.bonus_xp_per_soldier_kill * k)

static func add_player_weapon_damage(lm: Node, source_id: String, amount: float) -> void:
	if source_id.is_empty() or amount <= 0.0:
		return
	var normalized_source_id := _normalize_damage_source_id(source_id)
	var current = float(lm.weapon_damage_stats.get(normalized_source_id, 0.0))
	lm.weapon_damage_stats[normalized_source_id] = current + amount

static func get_total_weapon_damage(lm: Node) -> float:
	var total: float = 0.0
	for key in lm.weapon_damage_stats.keys():
		total += float(lm.weapon_damage_stats[key])
	return total

static func get_weapon_damage_rows(lm: Node, max_rows: int = 8) -> Array:
	var grouped_stats: Dictionary = {}
	for key in lm.weapon_damage_stats.keys():
		var normalized_key := _normalize_damage_source_id(str(key))
		grouped_stats[normalized_key] = float(grouped_stats.get(normalized_key, 0.0)) + float(lm.weapon_damage_stats[key])

	var rows: Array = []
	for key in grouped_stats.keys():
		var dmg = float(grouped_stats[key])
		if dmg <= 0.0:
			continue
		rows.append({
			"id": key,
			"name": lm.DAMAGE_SOURCE_NAME.get(key, key),
			"damage": dmg
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("damage", 0.0)) > float(b.get("damage", 0.0))
	)
	if rows.size() > max_rows:
		return rows.slice(0, max_rows)
	return rows

static func get_defeated_ship_rows(lm: Node, max_rows: int = 8) -> Array:
	if not ("defeated_ship_stats" in lm):
		return []
	var rows: Array = []
	for key in lm.defeated_ship_stats.keys():
		var row_variant: Variant = lm.defeated_ship_stats[key]
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant.duplicate(true)
		if int(row.get("defeated", 0)) <= 0 and int(row.get("sunk", 0)) <= 0 and int(row.get("derelicted", 0)) <= 0:
			continue
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var total_a := int(a.get("defeated", 0))
		var total_b := int(b.get("defeated", 0))
		if total_a == total_b:
			return int(a.get("sort_weight", 0)) > int(b.get("sort_weight", 0))
		return total_a > total_b
	)
	if rows.size() > max_rows:
		return rows.slice(0, max_rows)
	return rows

static func _record_defeated_ship(lm: Node, ship: Variant, outcome: String, count: int) -> void:
	if count <= 0 or not ("defeated_ship_stats" in lm):
		return
	var type_id := _normalize_defeated_ship_type(_get_ship_type_id(ship))
	if type_id.is_empty():
		return
	var row: Dictionary = lm.defeated_ship_stats.get(type_id, {
		"id": type_id,
		"name": _get_defeated_ship_name(type_id),
		"defeated": 0,
		"sunk": 0,
		"derelicted": 0,
		"sort_weight": _get_defeated_ship_sort_weight(type_id),
	})
	if outcome == "sunk":
		row["sunk"] = int(row.get("sunk", 0)) + count
	elif outcome == "derelicted":
		row["derelicted"] = int(row.get("derelicted", 0)) + count
	row["defeated"] = int(row.get("defeated", 0)) + _get_unique_defeated_count(ship, count)
	lm.defeated_ship_stats[type_id] = row

static func _get_unique_defeated_count(ship: Variant, count: int) -> int:
	if count <= 0:
		return 0
	if typeof(ship) != TYPE_OBJECT or not is_instance_valid(ship):
		return count
	if ship.get_meta("defeated_ship_breakdown_counted", false) == true:
		return 0
	ship.set_meta("defeated_ship_breakdown_counted", true)
	return count

static func _get_ship_type_id(ship: Variant) -> String:
	if ship == null:
		return ""
	if typeof(ship) == TYPE_STRING:
		return str(ship)
	if typeof(ship) != TYPE_OBJECT or not is_instance_valid(ship):
		return ""
	if ship.has_method("get_ship_type_value"):
		var method_value := str(ship.call("get_ship_type_value")).strip_edges()
		if not method_value.is_empty():
			return method_value
	var property_value: Variant = ship.get("ship_type")
	if property_value != null:
		return str(property_value)
	return str(ship.name)

static func _normalize_defeated_ship_type(type_id: String) -> String:
	var normalized := type_id.strip_edges().to_lower()
	if normalized.is_empty():
		return ""
	if normalized.contains("atake") and normalized.contains("final"):
		return "atakebune_final"
	if normalized.contains("atake"):
		return "atakebune"
	if normalized.contains("sekibune") and (normalized.contains("cannon") or normalized.contains("gunner")):
		return "sekibune_cannon"
	if normalized.contains("sekibune") or normalized.contains("seki"):
		return "sekibune"
	if normalized.contains("kobayabune") or normalized.contains("kobaya"):
		return "kobayabune"
	return normalized

static func _get_defeated_ship_name(type_id: String) -> String:
	match type_id:
		"kobayabune":
			return "고바야부네"
		"sekibune":
			return "세키부네"
		"sekibune_cannon":
			return "대철포 세키부네"
		"atakebune":
			return "아타케부네"
		"atakebune_final":
			return "대장선 아타케부네"
		_:
			return type_id.capitalize()

static func _get_defeated_ship_sort_weight(type_id: String) -> int:
	match type_id:
		"atakebune_final":
			return 50
		"atakebune":
			return 45
		"sekibune_cannon":
			return 35
		"sekibune":
			return 30
		"kobayabune":
			return 20
		_:
			return 0

static func _normalize_damage_source_id(source_id: String) -> String:
	var normalized := source_id.strip_edges()
	if normalized.is_empty():
		return normalized
	if normalized.begins_with("cannon"):
		return "cannon"
	return normalized.split(":", false, 1)[0]

static func add_xp(lm: Node, amount: int) -> void:
	if _env_flag_enabled("BATTLESHIP_DISABLE_RUNTIME_REWARDS"):
		return
	lm.current_xp += int(amount * lm.xp_multiplier)

	if lm.current_xp >= lm.xp_to_next_level:
		lm.current_xp -= lm.xp_to_next_level
		set_level(lm, lm.current_level + 1)

	if lm.hud and lm.hud.has_method("update_xp"):
		lm.hud.update_xp(lm.current_xp, lm.xp_to_next_level)

static func add_bonus_xp(lm: Node, amount: int) -> void:
	if _env_flag_enabled("BATTLESHIP_DISABLE_RUNTIME_REWARDS"):
		return
	var xp_amount: int = max(0, amount)
	if xp_amount <= 0:
		return
	add_xp(lm, xp_amount)

static func calculate_next_level_xp(lm: Node) -> void:
	lm.xp_to_next_level = max(1, int(lm.level_xp_base * pow(lm.current_level, lm.level_xp_exponent)))

static func set_level(lm: Node, new_level: int) -> void:
	lm.current_level = new_level
	calculate_next_level_xp(lm)

	lm.level_up.emit(lm.current_level)
	if lm.hud:
		lm.hud.update_level(lm.current_level)
		if lm.hud.has_method("update_xp"):
			lm.hud.update_xp(lm.current_xp, lm.xp_to_next_level)

	print("[LevelUp] Level Up! Lv.%d (Next XP: %d)" % [lm.current_level, lm.xp_to_next_level])

	add_score(lm, 5)

	var reroll_bonus: int = 0
	if is_instance_valid(MetaManager) and MetaManager.has_method("get_reroll_bonus"):
		reroll_bonus = int(MetaManager.get_reroll_bonus())
	lm.ship_rerolls_available = 1 + reroll_bonus

	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("level_up")

	lm._show_upgrade_ui(3)

static func update_difficulty(lm: Node) -> void:
	if not lm.enemy_spawner:
		return

	var data: Dictionary = lm.level_data.get(lm.game_difficulty, lm.level_data[lm.max_level])
	if lm.enemy_spawner.has_method("set_difficulty"):
		lm.enemy_spawner.set_difficulty(
			data["spawn_interval"],
			data["max_enemies"]
		)

static func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
