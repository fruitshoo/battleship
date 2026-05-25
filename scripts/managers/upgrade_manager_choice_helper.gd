extends RefCounted
class_name UpgradeManagerChoiceHelper


static func is_upgrade_available(upgrades: Dictionary, current_levels: Dictionary, upgrade_id: String) -> bool:
	if upgrade_id not in upgrades:
		return false
	if upgrades[upgrade_id].get("disabled", false) == true:
		return false
	return int(current_levels.get(upgrade_id, 0)) < int(upgrades[upgrade_id].get("max_level", 0))


static func collect_choices_from_ids(upgrades: Dictionary, current_levels: Dictionary, ids: Array[String], count: int) -> Array:
	var available: Array = []
	for upgrade_id in ids:
		if not is_upgrade_available(upgrades, current_levels, upgrade_id):
			continue
		available.append(upgrade_id)
	available.shuffle()
	return available.slice(0, mini(count, available.size()))


static func build_priority_then_random_choices(
	upgrades: Dictionary,
	current_levels: Dictionary,
	priority_ids: Array[String],
	pool_ids: Array[String],
	count: int
) -> Array:
	var choices: Array = []
	var remaining_pool: Array[String] = pool_ids.duplicate()

	for upgrade_id in priority_ids:
		if choices.size() >= count:
			break
		if not is_upgrade_available(upgrades, current_levels, upgrade_id):
			continue
		if choices.has(upgrade_id):
			continue
		choices.append(upgrade_id)
		remaining_pool.erase(upgrade_id)

	var random_fill: Array = collect_choices_from_ids(upgrades, current_levels, remaining_pool, count - choices.size())
	for upgrade_id in random_fill:
		if choices.size() >= count:
			break
		if choices.has(upgrade_id):
			continue
		choices.append(upgrade_id)

	return choices


static func fill_with_fallbacks(choices: Array, count: int, fallbacks: Array[String] = ["supply", "gold"]) -> void:
	var guard = 0
	while choices.size() < count and guard < 8:
		var fallback_id: String = fallbacks[guard % fallbacks.size()]
		if not choices.has(fallback_id):
			choices.append(fallback_id)
		guard += 1


static func sort_choices_by_preferred_order(choices: Array, preferred_ids: Array[String]) -> void:
	choices.sort_custom(func(a: String, b: String) -> bool:
		var a_idx := preferred_ids.find(a)
		var b_idx := preferred_ids.find(b)
		if a_idx == -1:
			a_idx = preferred_ids.size() + 100
		if b_idx == -1:
			b_idx = preferred_ids.size() + 100
		return a_idx < b_idx
	)


static func build_ship_upgrade_choices(
	upgrades: Dictionary,
	current_levels: Dictionary,
	ship_upgrade_ids: Array[String],
	support_ship_upgrade_ids: Array[String],
	priority_ship_upgrade_ids: Array[String],
	fleet_progress_available: bool,
	count: int = 3
) -> Array:
	var ship_pool: Array[String] = ship_upgrade_ids.duplicate()
	if fleet_progress_available:
		ship_pool.append_array(support_ship_upgrade_ids)
	var choices: Array = build_priority_then_random_choices(upgrades, current_levels, priority_ship_upgrade_ids, ship_pool, count)
	fill_with_fallbacks(choices, count)
	var preferred_order: Array[String] = ship_pool.duplicate()
	preferred_order.append_array(["supply", "gold"])
	sort_choices_by_preferred_order(choices, preferred_order)
	return choices


static func build_command_upgrade_choices(
	upgrades: Dictionary,
	current_levels: Dictionary,
	crew_upgrade_ids: Array[String],
	support_crew_upgrade_ids: Array[String],
	priority_crew_upgrade_ids: Array[String],
	fleet_progress_available: bool,
	count: int = 3
) -> Array:
	var command_pool: Array[String] = crew_upgrade_ids.duplicate()
	if fleet_progress_available:
		command_pool.append_array(support_crew_upgrade_ids)
	var choices: Array = build_priority_then_random_choices(upgrades, current_levels, priority_crew_upgrade_ids, command_pool, count)
	sort_choices_by_preferred_order(choices, command_pool)
	return choices


static func build_random_choices(upgrades: Dictionary, current_levels: Dictionary, count: int = 3, category_filter: int = -1) -> Array:
	var available: Array = []
	for upgrade_id in upgrades:
		if upgrade_id in ["supply", "gold"]:
			continue

		var upgrade_data: Dictionary = upgrades[upgrade_id]
		if upgrade_data.get("disabled", false) == true:
			continue
		if category_filter != -1 and upgrade_data.get("category", -1) != category_filter:
			continue
		if category_filter == -1 and upgrade_data.get("category", -1) == 5:
			continue

		if int(current_levels.get(upgrade_id, 0)) < int(upgrade_data.get("max_level", 0)):
			available.append(upgrade_id)

	available.shuffle()
	var choices: Array = available.slice(0, mini(count, available.size()))
	if category_filter == 5:
		return choices

	fill_with_fallbacks(choices, count)
	return choices
