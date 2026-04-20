extends RefCounted
class_name SeaSiteRewardHelper


const REWARD_UPGRADE_CHOICES := "upgrade_choices"
const REWARD_REPAIR_HULL := "repair_hull"
const REWARD_TRAIN_CREW := "train_crew"
const REWARD_EXPAND_CREW_LIMIT := "expand_crew_limit"
const REWARD_RESTORE_CREW := "restore_crew"


static func apply_reward(
	site: Node,
	player_ship: Node3D,
	reward_type: String,
	choice_count: int,
	hull_repair_ratio: float,
	hull_repair_minimum: float,
	crew_xp_amount: float,
	crew_limit_bonus: int,
	crew_restore_count: int
) -> bool:
	if reward_type == REWARD_REPAIR_HULL:
		return _repair_hull(site, player_ship, hull_repair_ratio, hull_repair_minimum)
	if reward_type == REWARD_TRAIN_CREW:
		return _train_crew(site, player_ship, crew_xp_amount)
	if reward_type == REWARD_EXPAND_CREW_LIMIT:
		return _expand_crew_limit(site, player_ship, crew_limit_bonus)
	if reward_type == REWARD_RESTORE_CREW:
		return _restore_crew(site, player_ship, crew_restore_count)
	return _open_upgrade_choices(site, choice_count)


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
		_notify(site, player_ship, "선체 수리 +%d" % int(round(after - before)))
	else:
		_notify(site, player_ship, "선체 상태 양호")
	return true


static func _train_crew(site: Node, player_ship: Node3D, xp_amount: float) -> bool:
	if not is_instance_valid(player_ship):
		return false
	var trained_count := 0
	var level_ups := 0
	for soldier in EntityRegistry.get_soldiers_by_ship(player_ship):
		if not is_instance_valid(soldier):
			continue
		if not _is_player_soldier(soldier):
			continue
		if _is_dead_soldier(soldier):
			continue
		if not soldier.has_method("add_soldier_xp"):
			continue
		var before_level := _get_soldier_level(soldier)
		soldier.call("add_soldier_xp", xp_amount, "sea_site")
		var after_level := _get_soldier_level(soldier)
		trained_count += 1
		if after_level > before_level:
			level_ups += after_level - before_level

	if trained_count <= 0:
		_notify(site, player_ship, "훈련할 병사 없음")
	elif level_ups > 0:
		_notify(site, player_ship, "병사 훈련: Lv +%d" % level_ups)
	else:
		_notify(site, player_ship, "병사 훈련 +%d XP" % int(round(xp_amount)))
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
	_notify(site, player_ship, "병사 정원 +%d" % add_count)
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
		_notify(site, player_ship, "병사 구조 +%d" % restored)
	else:
		_notify(site, player_ship, "병사 정원 가득")
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


static func _get_soldier_level(soldier: Node) -> int:
	if not is_instance_valid(soldier):
		return 0
	if soldier.has_method("get_soldier_level_value"):
		return int(soldier.call("get_soldier_level_value"))
	return int(soldier.get_meta("soldier_level", 1))


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
