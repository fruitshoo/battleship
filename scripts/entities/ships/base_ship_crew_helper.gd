extends RefCounted
class_name BaseShipCrewHelper

const CANNON_RELOAD_CREW_MAX_PER_CANNON := 3.0
const HOSTILE_BOARDING_INTERVAL_MULT := 2.2
const CREW_WORK_SYSTEMS_ENABLED := false

static func update_crew_allocation_state(ship, delta: float) -> void:
	ship._crew_allocation_eval_left -= delta
	if ship._crew_allocation_eval_left > 0.0:
		return
	ship._crew_allocation_eval_left = ship.crew_allocation_eval_interval

	if not CREW_WORK_SYSTEMS_ENABLED:
		_reset_crew_allocation_state(ship)
		assign_cannon_reload_crew_power(ship)
		return

	var available_crew: int = estimate_available_crew_count(ship)
	if available_crew <= 0:
		_reset_crew_allocation_state(ship)
		assign_cannon_reload_crew_power(ship)
		return

	var combat_ratio_target: float = 0.2
	var shiphandling_ratio_target: float = 0.5
	var gunnery_ratio_target: float = 0.3

	if ship.deck_is_contested or ship.deck_is_overrun or ship.is_boarding or ship.deck_hostile_boarder_count > 0:
		combat_ratio_target = 0.7
		shiphandling_ratio_target = 0.2
		gunnery_ratio_target = 0.1
	elif is_in_gunnery_posture(ship):
		combat_ratio_target = 0.2
		shiphandling_ratio_target = 0.3
		gunnery_ratio_target = 0.5

	ship.combat_crew_alloc = clampi(int(round(available_crew * combat_ratio_target)), 0, available_crew)
	ship.shiphandling_crew_alloc = clampi(int(round(available_crew * shiphandling_ratio_target)), 0, max(0, available_crew - ship.combat_crew_alloc))
	ship.gunnery_crew_alloc = max(0, available_crew - ship.combat_crew_alloc - ship.shiphandling_crew_alloc)

	ship.combat_crew_ratio = float(ship.combat_crew_alloc) / float(available_crew)
	ship.shiphandling_crew_ratio = float(ship.shiphandling_crew_alloc) / float(available_crew)
	ship.gunnery_crew_ratio = float(ship.gunnery_crew_alloc) / float(available_crew)
	assign_cannon_reload_crew_power(ship)


static func _reset_crew_allocation_state(ship) -> void:
	ship.combat_crew_alloc = 0
	ship.shiphandling_crew_alloc = 0
	ship.gunnery_crew_alloc = 0
	ship.combat_crew_ratio = 0.0
	ship.shiphandling_crew_ratio = 0.0
	ship.gunnery_crew_ratio = 0.0


static func get_shiphandling_multiplier(ship) -> float:
	if not CREW_WORK_SYSTEMS_ENABLED:
		return 1.0
	var t: float = clampf((ship.shiphandling_crew_ratio - 0.2) / 0.3, 0.0, 1.0)
	return lerpf(0.65, 1.0, t)


static func get_gunnery_reload_multiplier(ship) -> float:
	if not CREW_WORK_SYSTEMS_ENABLED:
		return 1.0
	var t: float = clampf((ship.gunnery_crew_ratio - 0.1) / 0.4, 0.0, 1.0)
	return lerpf(1.35, 0.72, t)

static func assign_cannon_reload_crew_power(ship) -> void:
	var cannons: Array[Node] = get_ship_reload_crew_cannons(ship)
	if cannons.is_empty():
		return
	for cannon in cannons:
		cannon.call("set_reload_crew_power", 0.0)

	var crew_power: float = 0.0
	if ship.get("gunnery_crew_alloc") != null:
		crew_power = float(max(0, int(ship.get("gunnery_crew_alloc"))))
	if crew_power <= 0.0:
		return

	var active_cannons: Array[Node] = get_active_reload_crew_cannons(ship, cannons)
	if active_cannons.is_empty():
		return
	distribute_cannon_reload_crew_power(active_cannons, crew_power)


static func get_ship_reload_crew_cannons(ship) -> Array[Node]:
	var cannons: Array[Node] = []
	var stack: Array[Node] = [ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node != ship and is_cannon_reload_crew_target(node):
			cannons.append(node)
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return cannons


static func get_active_reload_crew_cannons(ship, cannons: Array[Node]) -> Array[Node]:
	var active: Array[Node] = []
	var target := get_nearest_enemy_ship_for_allocation(ship)
	for cannon in cannons:
		if not is_reload_crew_cannon_available(cannon):
			continue
		if _cannon_has_active_reload_work(cannon) or (is_instance_valid(target) and cannon_can_cover_allocation_target(cannon, target)):
			active.append(cannon)
	return active


static func distribute_cannon_reload_crew_power(cannons: Array[Node], crew_power: float) -> void:
	var remaining: float = maxf(0.0, crew_power)
	if remaining <= 0.0:
		return
	var assigned: Dictionary = {}
	for cannon in cannons:
		if remaining <= 0.0:
			break
		var initial_max_power: float = CANNON_RELOAD_CREW_MAX_PER_CANNON
		if cannon.has_method("get_max_reload_crew_power"):
			initial_max_power = float(cannon.call("get_max_reload_crew_power"))
		var power: float = minf(minf(1.0, maxf(0.0, initial_max_power)), remaining)
		assigned[cannon] = power
		remaining -= power

	var cursor: int = 0
	while remaining > 0.001 and not cannons.is_empty():
		var cannon: Node = cannons[cursor % cannons.size()]
		var current_power: float = float(assigned.get(cannon, 0.0))
		var reload_max_power: float = CANNON_RELOAD_CREW_MAX_PER_CANNON
		if cannon.has_method("get_max_reload_crew_power"):
			reload_max_power = float(cannon.call("get_max_reload_crew_power"))
		var room: float = maxf(0.0, reload_max_power - current_power)
		if room > 0.001:
			var extra: float = minf(room, remaining)
			assigned[cannon] = current_power + extra
			remaining -= extra
		cursor += 1
		if cursor > cannons.size() * 4:
			break

	for cannon in cannons:
		cannon.call("set_reload_crew_power", float(assigned.get(cannon, 0.0)))


static func is_cannon_reload_crew_target(node: Node) -> bool:
	return node.has_method("set_reload_crew_power") and node.has_method("get_reload_crew_power")


static func is_reload_crew_cannon_available(cannon: Node) -> bool:
	if not is_instance_valid(cannon) or cannon.is_queued_for_deletion():
		return false
	if cannon.is_inside_tree():
		if cannon.has_method("is_visible_in_tree") and not cannon.is_visible_in_tree():
			return false
		if cannon.has_method("is_processing") and not cannon.is_processing():
			return false
	return true


static func _cannon_has_active_reload_work(cannon: Node) -> bool:
	if not is_instance_valid(cannon):
		return false
	if cannon.get("cooldown_timer") != null and float(cannon.get("cooldown_timer")) > 0.05:
		return true
	if cannon.get("is_preparing") == true:
		return true
	return false


static func cannon_can_cover_allocation_target(cannon: Node, target: Node) -> bool:
	if cannon.has_method("can_cover_reload_allocation_target"):
		return bool(cannon.call("can_cover_reload_allocation_target", target))
	if not (cannon is Node3D) or not (target is Node3D):
		return false
	var cannon_node := cannon as Node3D
	var target_node := target as Node3D
	if cannon.has_method("_get_current_range"):
		var range_value: float = float(cannon.call("_get_current_range"))
		if range_value > 0.0:
			var planar_delta: Vector3 = target_node.global_position - cannon_node.global_position
			planar_delta.y = 0.0
			if planar_delta.length_squared() > range_value * range_value:
				return false
	if cannon.has_method("_is_within_arc"):
		return bool(cannon.call("_is_within_arc", target_node))
	return true


static func get_combat_effectiveness_multiplier(ship) -> float:
	if not CREW_WORK_SYSTEMS_ENABLED:
		return 1.0
	var t: float = clampf((ship.combat_crew_ratio - 0.2) / 0.5, 0.0, 1.0)
	return lerpf(0.8, 1.25, t)


static func get_effective_boarding_interval(ship) -> float:
	if _is_hostile_boarding_player(ship):
		var interval: float = ship.boarding_interval
		interval *= HOSTILE_BOARDING_INTERVAL_MULT
		return maxf(0.45, interval)
	var interval: float = ship.boarding_interval / get_combat_effectiveness_multiplier(ship)
	return maxf(0.45, interval)


static func _is_hostile_boarding_player(ship) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(ship.get("boarding_target")):
		return false
	return _get_ship_team_tag(ship) == "enemy" and _get_ship_team_tag(ship.get("boarding_target")) == "player"


static func _get_ship_team_tag(ship) -> String:
	if is_instance_valid(ship) and ship.has_method("get_team_tag"):
		return str(ship.call("get_team_tag"))
	if is_instance_valid(ship) and ship.get("team") != null:
		return str(ship.get("team"))
	return "unknown"


static func get_effective_boarding_capture_duration(ship, attacker_ship: Node = null) -> float:
	var attacker_combat_mult: float = 1.0
	if is_instance_valid(attacker_ship) and attacker_ship.has_method("get_combat_effectiveness_multiplier"):
		attacker_combat_mult = float(attacker_ship.call("get_combat_effectiveness_multiplier"))
	var defender_combat_mult: float = maxf(0.01, get_combat_effectiveness_multiplier(ship))
	var duration_mult: float = defender_combat_mult / maxf(0.01, attacker_combat_mult)
	if ship.has_meta("boarding_capture_duration_multiplier"):
		duration_mult *= maxf(0.1, float(ship.get_meta("boarding_capture_duration_multiplier")))
	return clampf(ship.boarding_capture_duration * duration_mult, 1.2, 16.0)


static func estimate_available_crew_count(ship) -> int:
	var soldiers: Array = EntityRegistry.get_soldiers_by_ship(ship)
	if not soldiers.is_empty():
		var alive_count: int = 0
		var own_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else str(ship.get("team"))
		for child in soldiers:
			if not is_instance_valid(child):
				continue
			if child.has_method("get_team_tag") and child.get_team_tag() != own_team:
				continue
			if SoldierStateHelper.is_dead_soldier(child):
				continue
			alive_count += 1
		if alive_count > 0:
			return alive_count
	if ship.get("current_crew_count") != null:
		return max(0, int(ship.get("current_crew_count")))
	if ship.get("max_crew_count") != null:
		return max(0, int(ship.get("max_crew_count")))
	if ship.get("max_crew") != null:
		return max(0, int(ship.get("max_crew")))
	return 0


static func train_existing_crew_from_survivor(ship) -> bool:
	var trainee := _pick_survivor_training_target(ship)
	if not is_instance_valid(trainee):
		_show_survivor_training_message(ship, "생존자 구조: 정원 가득")
		return true

	var before_level := _get_soldier_level(trainee)
	var xp_amount := _get_soldier_next_level_xp(trainee)
	if xp_amount <= 0.0:
		xp_amount = 1.0
	if trainee.has_method("add_soldier_xp"):
		trainee.call("add_soldier_xp", xp_amount, "survivor_overflow")
	var after_level := _get_soldier_level(trainee)
	var message := "생존자 구조: 병사 훈련"
	if after_level > before_level:
		message = "생존자 구조: 병사 Lv.%d" % after_level
	_show_survivor_training_message(ship, message)
	var audio_manager = ship.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("level_up" if after_level > before_level else "soldier_hit", ship.global_position, 1.25)
	return true


static func _pick_survivor_training_target(ship) -> Node:
	var best: Node = null
	var best_level := INF
	var best_xp := INF
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier):
			continue
		if not _is_player_training_candidate(soldier):
			continue
		if not SoldierStateHelper.is_alive_soldier(soldier):
			continue
		if not soldier.has_method("add_soldier_xp"):
			continue
		var next_xp := _get_soldier_next_level_xp(soldier)
		if next_xp <= 0.0:
			continue
		var level := _get_soldier_level(soldier)
		var current_xp := _get_soldier_xp(soldier)
		if level < best_level or (level == best_level and current_xp < best_xp):
			best = soldier
			best_level = level
			best_xp = current_xp
	return best


static func _is_player_training_candidate(soldier: Node) -> bool:
	if soldier.has_method("is_player_team_soldier"):
		return soldier.call("is_player_team_soldier") == true
	if soldier.has_method("get_team_tag"):
		return str(soldier.call("get_team_tag")) == "player"
	return str(soldier.get("team")) == "player"


static func _get_soldier_level(soldier: Node) -> int:
	if not is_instance_valid(soldier):
		return 0
	if soldier.has_method("get_soldier_level_value"):
		return int(soldier.call("get_soldier_level_value"))
	return int(soldier.get_meta("soldier_level", 1))


static func _get_soldier_xp(soldier: Node) -> float:
	if not is_instance_valid(soldier):
		return 0.0
	if soldier.has_method("get_soldier_xp_value"):
		return float(soldier.call("get_soldier_xp_value"))
	return float(soldier.get_meta("soldier_xp", 0.0))


static func _get_soldier_next_level_xp(soldier: Node) -> float:
	if not is_instance_valid(soldier):
		return 0.0
	if soldier.has_method("get_soldier_next_level_xp_requirement"):
		return float(soldier.call("get_soldier_next_level_xp_requirement"))
	return 0.0


static func _show_survivor_training_message(ship, message: String) -> void:
	print("[Rescue] %s" % message)
	var hud = null
	if "_cached_hud" in ship:
		hud = ship._cached_hud
	if is_instance_valid(hud) and hud.has_method("show_message"):
		hud.show_message(message, 2.0)


static func is_in_gunnery_posture(ship) -> bool:
	var cannons := get_ship_reload_crew_cannons(ship)
	if cannons.is_empty():
		return false
	return not get_active_reload_crew_cannons(ship, cannons).is_empty()


static func get_ship_cannon_range_for_allocation(ship) -> float:
	var max_range: float = 0.0
	var stack: Array[Node] = [ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.has_method("_get_current_range"):
			max_range = maxf(max_range, float(node.call("_get_current_range")))
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return max_range


static func get_nearest_enemy_ship_distance_for_allocation(ship) -> float:
	var nearest_ship := get_nearest_enemy_ship_for_allocation(ship)
	if not is_instance_valid(nearest_ship):
		return -1.0
	var planar_delta: Vector3 = nearest_ship.global_position - ship.global_position
	planar_delta.y = 0.0
	return planar_delta.length()


static func get_nearest_enemy_ship_for_allocation(ship) -> Node3D:
	var own_team: String = ship.get_team_tag() if ship.has_method("get_team_tag") else str(ship.get("team"))
	var nearest_distance_sq: float = INF
	var nearest_ship: Node3D = null
	var opposing_team: String = "enemy" if own_team == "player" else "player"
	var all_ships: Array = EntityRegistry.get_ships_by_team(opposing_team)
	for other in all_ships:
		if not is_instance_valid(other) or other == ship or not (other is Node3D):
			continue
		if other.has_method("is_combat_disabled") and other.is_combat_disabled():
			continue
		if other.get("is_dying") == true or other.get("is_sinking") == true:
			continue
		var planar_delta: Vector3 = other.global_position - ship.global_position
		planar_delta.y = 0.0
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
			nearest_ship = other as Node3D
	return nearest_ship


static func build_debug_crew_snapshot(ship) -> Dictionary:
	var result: Dictionary = {
		"alive_count": 0,
		"general_count": 0,
		"spearman_count": 0,
		"fire_pot_count": 0,
		"repeater_count": 0,
		"singigeon_count": 0,
		"sample_hp": 0.0,
		"sample_defense": 0.0,
		"sword_damage": 0.0,
		"bow_damage": 0.0,
		"crit_chance": 0.0,
		"crit_multiplier": 1.0,
	}
	if not is_instance_valid(ship):
		return result

	var soldiers: Array = EntityRegistry.get_soldiers_by_ship(ship)
	if soldiers.is_empty():
		return result

	var sample_soldier = null
	for child in soldiers:
		if not is_instance_valid(child):
			continue
		var team_tag: String = str(child.get("team"))
		if team_tag != "player":
			continue
		if _is_dead_soldier_node(child):
			continue
		result["alive_count"] = int(result.get("alive_count", 0)) + 1
		var role: String = "general"
		if child.get("crew_role") != null:
			role = str(child.get("crew_role"))
		match role:
			"spearman":
				result["spearman_count"] = int(result.get("spearman_count", 0)) + 1
			"fire_pot":
				result["fire_pot_count"] = int(result.get("fire_pot_count", 0)) + 1
			"repeating_crossbow":
				result["repeater_count"] = int(result.get("repeater_count", 0)) + 1
			"singigeon":
				result["singigeon_count"] = int(result.get("singigeon_count", 0)) + 1
			_:
				result["general_count"] = int(result.get("general_count", 0)) + 1
		if sample_soldier == null or role == "general":
			sample_soldier = child

	if sample_soldier == null:
		return result

	result["sample_hp"] = float(sample_soldier.get("max_health")) if sample_soldier.get("max_health") != null else 0.0
	var defense_bonus: float = 0.0
	if sample_soldier.has_meta("defense_flat_bonus"):
		defense_bonus = float(sample_soldier.get_meta("defense_flat_bonus"))
	result["sample_defense"] = float(sample_soldier.get("defense")) if sample_soldier.get("defense") != null else 0.0
	result["sample_defense"] += defense_bonus
	result["crit_chance"] = float(sample_soldier.get("crit_chance")) if sample_soldier.get("crit_chance") != null else 0.0
	result["crit_multiplier"] = float(sample_soldier.get("crit_multiplier")) if sample_soldier.get("crit_multiplier") != null else 1.0
	if sample_soldier.get("weapon_sword") != null:
		result["sword_damage"] = float(sample_soldier.get("weapon_sword").get("damage")) if sample_soldier.get("weapon_sword").get("damage") != null else 0.0
	if sample_soldier.get("weapon_bow") != null:
		result["bow_damage"] = float(sample_soldier.get("weapon_bow").get("damage")) if sample_soldier.get("weapon_bow").get("damage") != null else 0.0
	return result


static func _is_dead_soldier_node(soldier: Node) -> bool:
	return SoldierStateHelper.is_dead_soldier(soldier)
