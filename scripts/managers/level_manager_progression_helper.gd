class_name LevelManagerProgressionHelper
extends RefCounted

static func add_score(lm: Node, points: int) -> void:
	if _env_flag_enabled("BATTLESHIP_DISABLE_RUNTIME_REWARDS"):
		return
	lm.current_score += points
	lm.enemies_killed += 1
	lm.score_changed.emit(lm.current_score)

	if is_instance_valid(SaveManager):
		var gold_gain: int = max(1, int(round(points * 0.3)))
		SaveManager.add_gold(gold_gain)

	if lm.hud:
		lm.hud.update_score(lm.current_score)

static func add_ship_sunk(lm: Node, count: int = 1) -> void:
	lm.ships_sunk += max(0, count)
	if lm.hud and lm.hud.has_method("update_combat_stats"):
		lm.hud.update_combat_stats(lm.ships_sunk, lm.ships_derelicted, lm.soldiers_killed, lm.soldiers_slain, lm.soldiers_drowned)

static func add_ship_derelict(lm: Node, count: int = 1) -> void:
	lm.ships_derelicted += max(0, count)
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

static func add_command_xp_from_soldier_kill(lm: Node, kill_count: int = 1) -> void:
	var k: int = max(0, kill_count)
	if k <= 0:
		return
	add_merit(lm, lm.merit_per_soldier_kill * k)

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

	if lm.hud and lm.hud.has_method("update_xp"):
		lm.hud.update_xp(lm.current_xp, lm.xp_to_next_level)

	if lm.current_xp >= lm.xp_to_next_level:
		lm.current_xp -= lm.xp_to_next_level
		set_level(lm, lm.current_level + 1)

static func add_merit(lm: Node, amount: int) -> void:
	if _env_flag_enabled("BATTLESHIP_DISABLE_RUNTIME_REWARDS"):
		return
	if lm.merit_points >= lm.max_merit_points:
		return

	lm.merit_points = min(lm.merit_points + amount, lm.max_merit_points)
	lm.merit_changed.emit(lm.merit_points, lm.max_merit_points, lm.merit_level)

	if lm.hud and lm.hud.has_method("update_merit"):
		lm.hud.update_merit(lm.merit_points, lm.max_merit_points, lm.merit_level)

	if lm.merit_points >= lm.max_merit_points:
		lm.merit_full.emit()
		print("[Command] 지휘 포인트가 가득 찼습니다! 병사 업그레이드를 시작합니다.")
		lm.consume_merit()

static func calculate_next_level_xp(lm: Node) -> void:
	lm.xp_to_next_level = max(1, int(lm.level_xp_base * pow(lm.current_level, lm.level_xp_exponent)))

static func get_merit_requirement(lm: Node, level: int) -> int:
	return max(1, lm.merit_base_points + (level - 1) * lm.merit_growth_per_level)

static func set_level(lm: Node, new_level: int) -> void:
	lm.current_level = new_level
	calculate_next_level_xp(lm)

	lm.level_up.emit(lm.current_level)
	if lm.hud:
		lm.hud.update_level(lm.current_level)

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
			data["max_enemies"],
			data.get("boarders", 2)
		)

static func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
