extends RefCounted
class_name SeaSiteRewardHelper


const REWARD_UPGRADE_CHOICES := "upgrade_choices"
const REWARD_REPAIR_HULL := "repair_hull"
const REWARD_TRAIN_CREW := "train_crew" # Legacy authoring value; maps to crew restoration.
const REWARD_EXPAND_CREW_LIMIT := "expand_crew_limit"
const REWARD_RESTORE_CREW := "restore_crew"
const REWARD_MINOR_STAT_BONUS := "minor_stat_bonus"
const MINOR_REWARD_DATA_PATH := "res://data/sea_site_rewards.json"
const META_SITE_BONUS_TOTALS := "sea_site_bonus_totals"
const META_SITE_BONUS_COUNTS := "sea_site_bonus_counts"


static func apply_reward(
	site: Node,
	player_ship: Node3D,
	reward_type: String,
	choice_count: int,
	hull_repair_ratio: float,
	hull_repair_minimum: float,
	crew_limit_bonus: int,
	crew_restore_count: int
) -> bool:
	if reward_type == REWARD_REPAIR_HULL:
		return _repair_hull(site, player_ship, hull_repair_ratio, hull_repair_minimum)
	if reward_type == REWARD_TRAIN_CREW:
		return _restore_crew(site, player_ship, crew_restore_count)
	if reward_type == REWARD_EXPAND_CREW_LIMIT:
		return _expand_crew_limit(site, player_ship, crew_limit_bonus)
	if reward_type == REWARD_RESTORE_CREW:
		return _restore_crew(site, player_ship, crew_restore_count)
	if reward_type == REWARD_MINOR_STAT_BONUS:
		return _apply_minor_stat_bonus(site, player_ship)
	return _open_upgrade_choices(site, choice_count)


static func get_site_bonus_total(ship: Node, bonus_id: String) -> float:
	if not is_instance_valid(ship):
		return 0.0
	var totals: Variant = ship.get_meta(META_SITE_BONUS_TOTALS, {})
	if totals is Dictionary:
		return maxf(0.0, float((totals as Dictionary).get(bonus_id, 0.0)))
	return 0.0


static func _apply_minor_stat_bonus(site: Node, player_ship: Node3D) -> bool:
	if not is_instance_valid(player_ship):
		return false
	var entry := _pick_minor_stat_bonus(player_ship)
	if entry.is_empty():
		_notify(site, player_ship, LocaleManager.t("hud.sea_site.exhausted", "이미 충분히 탐색함"))
		return true

	var bonus_id := str(entry.get("id", ""))
	var amount := maxf(0.0, float(entry.get("amount", 0.0)))
	var max_total := maxf(0.0, float(entry.get("max_total", amount)))
	var current_total := get_site_bonus_total(player_ship, bonus_id)
	var applied_amount := minf(amount, maxf(0.0, max_total - current_total))
	if bonus_id.is_empty() or applied_amount <= 0.0001:
		return false

	var totals := _get_site_bonus_totals(player_ship)
	var counts := _get_site_bonus_counts(player_ship)
	var next_total := current_total + applied_amount
	totals[bonus_id] = next_total
	counts[bonus_id] = int(counts.get(bonus_id, 0)) + 1
	player_ship.set_meta(META_SITE_BONUS_TOTALS, totals)
	player_ship.set_meta(META_SITE_BONUS_COUNTS, counts)

	if bonus_id == "max_hull_add":
		_apply_max_hull_bonus_delta(player_ship, applied_amount)
	_sync_site_bonus_consumers(site, player_ship)
	_sync_site_bonuses_to_player_fleet(site, player_ship)
	_notify(site, player_ship, _format_minor_bonus_message(entry, applied_amount, next_total))
	return true


static func _pick_minor_stat_bonus(player_ship: Node3D) -> Dictionary:
	var entries := _load_minor_stat_bonus_entries()
	var choices: Array = []
	var total_weight := 0.0
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var bonus_id := str(entry.get("id", ""))
		if bonus_id.is_empty():
			continue
		var amount := maxf(0.0, float(entry.get("amount", 0.0)))
		var max_total := maxf(0.0, float(entry.get("max_total", amount)))
		if amount <= 0.0 or get_site_bonus_total(player_ship, bonus_id) >= max_total - 0.0001:
			continue
		var weight := maxf(0.0, float(entry.get("weight", 1.0)))
		if weight <= 0.0:
			continue
		var weighted_entry := entry.duplicate(true)
		weighted_entry["_weight"] = weight
		choices.append(weighted_entry)
		total_weight += weight

	if choices.is_empty() or total_weight <= 0.0:
		return {}

	var roll := randf() * total_weight
	for raw_choice in choices:
		var choice: Dictionary = raw_choice
		roll -= float(choice.get("_weight", 1.0))
		if roll <= 0.0:
			choice.erase("_weight")
			return choice
	var fallback: Dictionary = choices.back()
	fallback.erase("_weight")
	return fallback


static func _load_minor_stat_bonus_entries() -> Array:
	if not FileAccess.file_exists(MINOR_REWARD_DATA_PATH):
		push_warning("[SeaSiteReward] minor reward data missing: %s" % MINOR_REWARD_DATA_PATH)
		return []
	var text := FileAccess.get_file_as_string(MINOR_REWARD_DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("[SeaSiteReward] minor reward data parse failed")
		return []
	var entries: Variant = (parsed as Dictionary).get("minor_stat_bonuses", [])
	if entries is Array:
		return entries as Array
	return []


static func _get_site_bonus_totals(player_ship: Node) -> Dictionary:
	var totals: Variant = player_ship.get_meta(META_SITE_BONUS_TOTALS, {})
	if totals is Dictionary:
		return (totals as Dictionary).duplicate(true)
	return {}


static func _get_site_bonus_counts(player_ship: Node) -> Dictionary:
	var counts: Variant = player_ship.get_meta(META_SITE_BONUS_COUNTS, {})
	if counts is Dictionary:
		return (counts as Dictionary).duplicate(true)
	return {}


static func _apply_max_hull_bonus_delta(player_ship: Node3D, amount: float) -> void:
	if not is_instance_valid(player_ship):
		return
	if player_ship.get("max_hull_hp") == null:
		return
	var before_max := float(player_ship.get("max_hull_hp"))
	player_ship.set("max_hull_hp", before_max + amount)
	if player_ship.get("hull_hp") != null:
		player_ship.set("hull_hp", minf(float(player_ship.get("max_hull_hp")), float(player_ship.get("hull_hp")) + amount))


static func _sync_site_bonus_consumers(site: Node, player_ship: Node3D) -> void:
	if not is_instance_valid(player_ship):
		return
	_refresh_ship_upgrade_derived_stats(site, player_ship)
	_refresh_ship_soldier_site_bonuses(site, player_ship)
	_refresh_ship_cannon_site_bonuses(player_ship)
	_sync_hull_hud(site, player_ship)


static func _sync_site_bonuses_to_player_fleet(site: Node, player_ship: Node3D) -> void:
	if not is_instance_valid(player_ship):
		return
	var totals := _get_site_bonus_totals(player_ship)
	var counts := _get_site_bonus_counts(player_ship)
	var upgrade_manager := _get_upgrade_manager(site)
	for ship in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(ship) or ship == player_ship:
			continue
		ship.set_meta(META_SITE_BONUS_TOTALS, totals.duplicate(true))
		ship.set_meta(META_SITE_BONUS_COUNTS, counts.duplicate(true))
		if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_upgrades_to_ship"):
			upgrade_manager.call("apply_fleet_upgrades_to_ship", ship)
		_refresh_ship_cannon_site_bonuses(ship as Node3D)


static func _refresh_ship_upgrade_derived_stats(site: Node, player_ship: Node3D) -> void:
	var upgrade_manager := _get_upgrade_manager(site)
	if not is_instance_valid(upgrade_manager):
		return
	var current_levels: Dictionary = {}
	var raw_levels: Variant = upgrade_manager.get("current_levels")
	if raw_levels is Dictionary:
		current_levels = raw_levels as Dictionary
	if upgrade_manager.has_method("_apply_hull_defense"):
		upgrade_manager.call("_apply_hull_defense", player_ship, int(current_levels.get("hull_defense", 0)))
	if upgrade_manager.has_method("_apply_hull_repair"):
		upgrade_manager.call("_apply_hull_repair", player_ship, int(current_levels.get("hull_repair", 0)))


static func _refresh_ship_soldier_site_bonuses(site: Node, player_ship: Node3D) -> void:
	var upgrade_manager := _get_upgrade_manager(site)
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if not is_instance_valid(soldier) or not _is_player_soldier(soldier):
			continue
		if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("_apply_current_stats_to_soldier"):
			upgrade_manager.call("_apply_current_stats_to_soldier", soldier)
		elif soldier.has_method("_update_weapon_stats"):
			soldier.call("_update_weapon_stats")


static func _refresh_ship_cannon_site_bonuses(ship: Node3D) -> void:
	if not is_instance_valid(ship):
		return
	for node in _collect_descendants(ship):
		if not is_instance_valid(node):
			continue
		if node.has_method("_update_cached_stats") and node.has_method("get_debug_cannon_snapshot"):
			node.call("_update_cached_stats")


static func _collect_descendants(root: Node) -> Array:
	var result: Array = []
	for child in root.get_children():
		result.append(child)
		result.append_array(_collect_descendants(child))
	return result


static func _get_upgrade_manager(site: Node) -> Node:
	if not is_instance_valid(site) or site.get_tree() == null or site.get_tree().root == null:
		return null
	return site.get_tree().root.get_node_or_null("UpgradeManager")


static func _format_minor_bonus_message(entry: Dictionary, amount: float, total: float) -> String:
	var bonus_id := str(entry.get("id", ""))
	var name := LocaleManager.data_text(entry, bonus_id, "sea_site_bonus", "name", "탐색 보너스")
	var format := str(entry.get("format", "flat"))
	return LocaleManager.t("hud.sea_site.minor_bonus", "{name} {amount} (누적 {total})", {
		"name": name,
		"amount": _format_bonus_value(format, amount),
		"total": _format_bonus_value(format, total),
	})


static func _format_bonus_value(format: String, value: float) -> String:
	match format:
		"percent":
			return "+%d%%" % int(round(value * 100.0))
		"per_second":
			return LocaleManager.t("hud.sea_site.format.per_second", "+{value}/초", {"value": "%.1f" % value})
		"hp":
			return "+%d" % int(round(value))
		_:
			if absf(value - round(value)) < 0.01:
				return "+%d" % int(round(value))
			return "+%.1f" % value


static func _open_upgrade_choices(site: Node, choice_count: int) -> bool:
	if not is_instance_valid(site):
		return false
	var lm := LevelManagerRegistry.get_level_manager(site.get_tree())
	if not is_instance_valid(lm) or not lm.has_method("_show_upgrade_ui"):
		return false
	var active_ui: Variant = lm.get("_upgrade_ui_instance")
	if is_instance_valid(active_ui):
		return false
	lm.call_deferred("_show_upgrade_ui", choice_count)
	return true


static func _repair_hull(site: Node, player_ship: Node3D, repair_ratio: float, repair_minimum: float) -> bool:
	if not is_instance_valid(player_ship):
		return false
	if player_ship.get("hull_hp") == null or player_ship.get("max_hull_hp") == null:
		return false

	var max_hull: float = maxf(1.0, float(player_ship.get("max_hull_hp")))
	var before: float = clampf(float(player_ship.get("hull_hp")), 0.0, max_hull)
	var repair_amount: float = maxf(repair_minimum, max_hull * maxf(repair_ratio, 0.0))
	var after: float = minf(max_hull, before + repair_amount)
	player_ship.set("hull_hp", after)
	_sync_hull_hud(site, player_ship)

	if after > before + 0.01:
		_notify(site, player_ship, LocaleManager.t("hud.sea_site.hull_repair", "선체 수리 +{amount}", {"amount": int(round(after - before))}))
	else:
		_notify(site, player_ship, LocaleManager.t("hud.sea_site.hull_good", "선체 상태 양호"))
	return true


static func _expand_crew_limit(site: Node, player_ship: Node3D, bonus: int) -> bool:
	if not is_instance_valid(player_ship):
		return false
	if player_ship.get("max_crew_count") == null:
		return false
	var add_count := maxi(1, bonus)
	var before := int(player_ship.get("max_crew_count"))
	var after := before + add_count
	player_ship.set("max_crew_count", after)
	var base_capacity := int(player_ship.get_meta("base_player_max_crew_count", before))
	player_ship.set_meta("base_player_max_crew_count", base_capacity + add_count)
	if player_ship.has_method("_sync_player_crew_roster"):
		player_ship.call("_sync_player_crew_roster")
	if player_ship.has_method("_update_crew_count"):
		player_ship.call("_update_crew_count")
	_notify(site, player_ship, LocaleManager.t("hud.sea_site.crew_capacity", "병사 정원 +{amount}", {"amount": add_count}))
	return true


static func _restore_crew(site: Node, player_ship: Node3D, restore_count: int) -> bool:
	if not is_instance_valid(player_ship):
		return false
	if not player_ship.has_method("add_survivor"):
		return false
	var restored := 0
	for _index in range(maxi(1, restore_count)):
		if player_ship.call("add_survivor", false) == true:
			restored += 1
		else:
			break
	if restored > 0:
		_notify(site, player_ship, LocaleManager.t("hud.sea_site.crew_rescue", "병사 구조 +{amount}", {"amount": restored}))
	else:
		_notify(site, player_ship, LocaleManager.t("hud.sea_site.crew_full", "병사 정원 가득"))
	return true


static func _is_player_soldier(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.has_method("is_player_team_soldier"):
		return soldier.call("is_player_team_soldier") == true
	return str(soldier.get("team")) == "player"


static func _is_dead_soldier(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return true
	if soldier.has_method("is_state_value_dead"):
		return soldier.call("is_state_value_dead", soldier.get("current_state")) == true
	return false


static func _sync_hull_hud(site: Node, player_ship: Node3D) -> void:
	var hud := _get_hud(site, player_ship)
	if is_instance_valid(hud) and hud.has_method("update_hull_hp"):
		hud.call("update_hull_hp", player_ship.get("hull_hp"), player_ship.get("max_hull_hp"))


static func _notify(site: Node, player_ship: Node3D, message: String) -> void:
	var hud := _get_hud(site, player_ship)
	if not is_instance_valid(hud):
		return
	if hud.has_method("show_message"):
		hud.call("show_message", message, 1.8)
	elif hud.has_method("show_gust_warning_message"):
		hud.call("show_gust_warning_message", message, 1.2)


static func _get_hud(site: Node, player_ship: Node3D) -> Node:
	var hud: Node = null
	if is_instance_valid(player_ship) and player_ship.has_method("_find_hud"):
		hud = player_ship.call("_find_hud") as Node
	if not is_instance_valid(hud) and is_instance_valid(player_ship):
		var cached_hud: Variant = player_ship.get("_cached_hud")
		if is_instance_valid(cached_hud):
			hud = cached_hud as Node
	if not is_instance_valid(hud) and is_instance_valid(site):
		var lm := LevelManagerRegistry.get_level_manager(site.get_tree())
		if is_instance_valid(lm):
			var level_hud: Variant = lm.get("hud")
			if is_instance_valid(level_hud):
				hud = level_hud as Node
	return hud
