extends RefCounted

const RAID_SWITCH_BUFFER: float = 2.0
const RAID_MAX_ACTIVE_THREATS: int = 1

static func get_desired_player_captain_count(ship) -> int:
	return clampi(int(ship.captain_count), 0, maxi(0, int(ship.max_crew_count)))

static func is_captain(ship, soldier: Node) -> bool:
	if soldier == null:
		return false
	if "is_captain" in soldier:
		return bool(soldier.is_captain)
	return bool(soldier.get_meta("is_captain", false))

static func set_captain_state(ship, soldier: Node, enabled: bool) -> void:
	if soldier == null:
		return
	if soldier.has_method("set_captain_status"):
		soldier.set_captain_status(
			enabled,
			float(ship.captain_health_multiplier),
			float(ship.captain_attack_multiplier),
			float(ship.captain_defense_bonus)
		)
	else:
		soldier.set_meta("is_captain", enabled)

static func get_desired_player_crew_roles(ship) -> Dictionary:
	var captain_slots: int = get_desired_player_captain_count(ship)
	var regular_crew_capacity: int = maxi(0, int(ship.max_crew_count) - captain_slots)
	var desired := {
		ship.CREW_ROLE_GENERAL: regular_crew_capacity,
		ship.CREW_ROLE_SPEARMAN: 0,
		ship.CREW_ROLE_FIRE_POT: 0,
		ship.CREW_ROLE_REPEATING_CROSSBOW: 0,
		ship.CREW_ROLE_SINGIGEON: 0,
	}
	if is_instance_valid(ship._cached_um) and ship._cached_um.has_method("get_player_crew_roster"):
		var roster = ship._cached_um.get_player_crew_roster(regular_crew_capacity)
		for key in desired.keys():
			desired[key] = int(roster.get(key, desired[key]))
	return desired

static func get_soldier_role(ship, soldier: Node) -> String:
	if soldier == null:
		return ship.CREW_ROLE_GENERAL
	if "crew_role" in soldier:
		return String(soldier.crew_role)
	return String(soldier.get_meta("crew_role", ship.CREW_ROLE_GENERAL))

static func spawn_player_soldier(ship, soldiers_node: Node, role: String, captain: bool = false) -> Node:
	var soldier = ship.SOLDIER_SCENE.instantiate()
	soldiers_node.add_child(soldier)
	soldier.set_team("player")
	if soldier.has_method("apply_crew_role"):
		soldier.apply_crew_role(role)
	else:
		soldier.set_meta("crew_role", role)
	set_captain_state(ship, soldier, captain)
	var offset = Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-2.5, 2.5))
	soldier.position = offset
	if is_instance_valid(ship._cached_um) and ship._cached_um.has_method("_apply_current_stats_to_soldier"):
		ship._cached_um._apply_current_stats_to_soldier(soldier)
	return soldier

static func sync_player_crew_roster(ship) -> void:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return
	var desired = get_desired_player_crew_roles(ship)
	var desired_captains: int = get_desired_player_captain_count(ship)
	var alive_captains: Array = []
	var alive_by_role := {
		ship.CREW_ROLE_GENERAL: [],
		ship.CREW_ROLE_SPEARMAN: [],
		ship.CREW_ROLE_FIRE_POT: [],
		ship.CREW_ROLE_REPEATING_CROSSBOW: [],
		ship.CREW_ROLE_SINGIGEON: [],
	}
	for child in soldiers_node.get_children():
		if child.get("current_state") == 4 or child.get("team") != "player":
			continue
		if is_captain(ship, child):
			alive_captains.append(child)
			continue
		var role = get_soldier_role(ship, child)
		if not alive_by_role.has(role):
			role = ship.CREW_ROLE_GENERAL
		alive_by_role[role].append(child)
	while alive_captains.size() > desired_captains:
		var extra_captain = alive_captains.pop_back()
		set_captain_state(ship, extra_captain, false)
		if extra_captain.has_method("apply_crew_role"):
			extra_captain.apply_crew_role(ship.CREW_ROLE_GENERAL)
		else:
			extra_captain.set_meta("crew_role", ship.CREW_ROLE_GENERAL)
		alive_by_role[ship.CREW_ROLE_GENERAL].append(extra_captain)
	for _i in range(max(0, desired_captains - alive_captains.size())):
		var captain = spawn_player_soldier(ship, soldiers_node, ship.CREW_ROLE_GENERAL, true)
		alive_captains.append(captain)
	for role in [ship.CREW_ROLE_SPEARMAN, ship.CREW_ROLE_REPEATING_CROSSBOW, ship.CREW_ROLE_SINGIGEON, ship.CREW_ROLE_FIRE_POT]:
		var shortage = int(desired.get(role, 0)) - alive_by_role[role].size()
		while shortage > 0 and alive_by_role[ship.CREW_ROLE_GENERAL].size() > 0:
			var general = alive_by_role[ship.CREW_ROLE_GENERAL].pop_back()
			if general.has_method("apply_crew_role"):
				general.apply_crew_role(role)
			else:
				general.set_meta("crew_role", role)
			alive_by_role[role].append(general)
			shortage -= 1
	for role in [ship.CREW_ROLE_SPEARMAN, ship.CREW_ROLE_REPEATING_CROSSBOW, ship.CREW_ROLE_SINGIGEON, ship.CREW_ROLE_FIRE_POT, ship.CREW_ROLE_GENERAL]:
		var missing = int(desired.get(role, 0)) - alive_by_role[role].size()
		for _i in range(max(0, missing)):
			spawn_player_soldier(ship, soldiers_node, role)

static func add_survivor(ship) -> bool:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return false

	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4:
			alive_count += 1
		else:
			child.queue_free()

	if alive_count >= ship.max_crew_count:
		var reward: int = max(1, int(ship.survivor_merit_reward))
		if is_instance_valid(ship._cached_level_manager) and ship._cached_level_manager.has_method("add_merit"):
			ship._cached_level_manager.add_merit(reward)
		print("[Rescue] 생존자 구조 성공! 정원이 가득 차 지휘 포인트 %d를 획득했습니다. (현재: %d/%d)" % [reward, alive_count, ship.max_crew_count])
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("생존자 구조: 지휘 +%d" % reward, 2.0)
		var overflow_audio_manager = ship.get_node_or_null("/root/AudioManager")
		if is_instance_valid(overflow_audio_manager) and overflow_audio_manager.has_method("play_sfx"):
			overflow_audio_manager.play_sfx("soldier_hit", ship.global_position, 1.3)
		return true

	var desired = get_desired_player_crew_roles(ship)
	var desired_captains: int = get_desired_player_captain_count(ship)
	var current_by_role := {
		ship.CREW_ROLE_GENERAL: 0,
		ship.CREW_ROLE_SPEARMAN: 0,
		ship.CREW_ROLE_FIRE_POT: 0,
		ship.CREW_ROLE_REPEATING_CROSSBOW: 0,
		ship.CREW_ROLE_SINGIGEON: 0,
	}
	var current_captains: int = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") == 4 or child.get("team") != "player":
			continue
		if is_captain(ship, child):
			current_captains += 1
			continue
		var role = get_soldier_role(ship, child)
		if not current_by_role.has(role):
			role = ship.CREW_ROLE_GENERAL
		current_by_role[role] += 1

	if current_captains < desired_captains:
		spawn_player_soldier(ship, soldiers_node, ship.CREW_ROLE_GENERAL, true)
		print("[Rescue] 생존자 구조 성공! 장군 1명이 복귀했습니다. (현재: %d/%d)" % [alive_count + 1, ship.max_crew_count])
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("생존자 구조: 장군 복귀", 2.0)
		var captain_audio_manager = ship.get_node_or_null("/root/AudioManager")
		if is_instance_valid(captain_audio_manager) and captain_audio_manager.has_method("play_sfx"):
			captain_audio_manager.play_sfx("soldier_hit", ship.global_position, 1.45)
		return true

	var role_to_add = ship.CREW_ROLE_GENERAL
	for candidate in [ship.CREW_ROLE_SPEARMAN, ship.CREW_ROLE_REPEATING_CROSSBOW, ship.CREW_ROLE_SINGIGEON, ship.CREW_ROLE_FIRE_POT, ship.CREW_ROLE_GENERAL]:
		if int(current_by_role.get(candidate, 0)) < int(desired.get(candidate, 0)):
			role_to_add = candidate
			break
	spawn_player_soldier(ship, soldiers_node, role_to_add)

	print("[Rescue] 생존자 구조 성공! 아군 병사 1명 합류. (현재: %d/%d)" % [alive_count + 1, ship.max_crew_count])
	if ship._cached_hud and ship._cached_hud.has_method("show_message"):
		ship._cached_hud.show_message("생존자 구조 완료!", 2.0)
	var audio_manager = ship.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("soldier_hit", ship.global_position, 1.5)
	return true

static func update_fire_pot_logic(ship, delta: float) -> void:
	if ship.is_sinking or ship.is_dying or ship.hull_hp <= 0.0:
		return

	if ship.fire_pot_cooldown_timer > 0:
		ship.fire_pot_cooldown_timer -= delta

	if ship.fire_pot_cooldown_timer > 0:
		return
	if not is_instance_valid(ship._cached_um) or not "fire_pot" in ship._cached_um.UPGRADES:
		return

	var fp_lv = ship._cached_um.current_levels.get("fire_pot", 0)
	if fp_lv <= 0:
		return
	if not is_instance_valid(ship.boarding_attacker) or ship.boarding_attacker.get("is_dying") or ship.boarding_attacker.get("is_sinking"):
		return

	var target = ship.boarding_attacker
	var dist = ship.global_position.distance_to(target.global_position)
	if dist > 15.0:
		return

	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return

	var tosser = null
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4 and child.get("team") == "player" and get_soldier_role(ship, child) == ship.CREW_ROLE_FIRE_POT:
			tosser = child
			break

	if not tosser or not ship.fire_pot_scene:
		return

	var stats = ship._cached_um.UPGRADES["fire_pot"]["stats"]
	var cdr = stats.get("cooldown_reduce_per_lv", 1.0) * (fp_lv - 1)
	var cd = stats.get("base_cooldown", 6.0) - cdr
	if fp_lv == 4:
		cd = 3.5
	if fp_lv >= 5:
		cd = 3.0
	ship.fire_pot_cooldown_timer = cd

	var pot = ship.fire_pot_scene.instantiate()
	var target_pos = target.global_position
	target_pos.x += randf_range(-1.2, 1.2)
	target_pos.z += randf_range(-1.2, 1.2)
	target_pos.y += 0.5

	var start_pos = tosser.global_position
	start_pos.y += 1.0

	pot.damage = stats.get("base_damage", 15.0) + (fp_lv - 1) * stats.get("damage_per_lv", 5.0)
	pot.explosion_radius = stats.get("base_radius", 3.0) + (fp_lv - 1) * stats.get("radius_per_lv", 0.5)
	pot.team = ship.team

	ship.get_tree().root.add_child.call_deferred(pot)
	pot.set_deferred("global_position", start_pos)
	pot.call_deferred("setup_flight", start_pos, target_pos, 0.8, 3.5)

	tosser.look_at(Vector3(target_pos.x, tosser.global_position.y, target_pos.z), Vector3.UP)
	print("[FirePot] 병사가 적선으로 화통을 던졌습니다!")


static func update_auto_boarding_raid(ship, delta: float) -> void:
	if not bool(ship.auto_raid_enabled):
		_recall_raid_boarders(ship)
		ship.auto_raid_target = null
		return
	if ship.is_sinking or ship.is_dying or ship.is_boarding:
		_recall_raid_boarders(ship)
		ship.auto_raid_target = null
		return

	ship.auto_raid_eval_timer = maxf(0.0, float(ship.auto_raid_eval_timer) - delta)

	var current_target: Node3D = ship.auto_raid_target
	if is_instance_valid(current_target) and not _can_continue_raid(ship, current_target):
		current_target = null

	if ship.auto_raid_eval_timer <= 0.0:
		ship.auto_raid_eval_timer = float(ship.auto_raid_eval_interval)
		var next_target: Node3D = _find_raid_target(ship)
		if current_target != next_target and _count_boarders_from_home(ship) > 0:
			_recall_raid_boarders(ship)
			current_target = null
		else:
			current_target = next_target

	ship.auto_raid_target = current_target

	if is_instance_valid(current_target):
		_dispatch_raid_boarders(ship, current_target)
	else:
		_recall_raid_boarders(ship)


static func _find_raid_target(ship) -> Node3D:
	if not _can_initiate_raid(ship):
		return null

	var own_crew: int = ship.get_alive_crew_count()
	var candidates: Array = []
	var nearby_enemy_count: int = 0
	var enemies = ship.get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not _is_valid_raid_target_ship(ship, enemy):
			continue
		var dist: float = ship.global_position.distance_to(enemy.global_position)
		if dist <= float(ship.auto_raid_threat_range):
			nearby_enemy_count += 1
		if not _is_ship_close_for_raid(ship, enemy):
			continue
		var enemy_crew: int = int(enemy.call("get_alive_crew_count")) if enemy.has_method("get_alive_crew_count") else 0
		if own_crew <= enemy_crew:
			continue
		var enemy_ranged: int = _count_ranged_enemies_on_ship(enemy)
		if enemy_ranged <= 0:
			continue
		var score: float = float(enemy_ranged) * 10.0
		score += float(own_crew - enemy_crew) * 2.0
		score -= dist * 0.15
		candidates.append({
			"ship": enemy,
			"score": score,
		})

	if nearby_enemy_count > RAID_MAX_ACTIVE_THREATS:
		return null
	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return candidates[0]["ship"] as Node3D


static func _can_initiate_raid(ship) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.get_hull_ratio() < float(ship.auto_raid_min_hull_ratio):
		return false
	if _count_enemy_boarders_on_ship(ship) > 0:
		return false
	if is_instance_valid(ship.boarding_attacker):
		return false
	var available_defenders: int = _count_home_defenders(ship)
	return available_defenders > int(ship.auto_raid_min_defenders)


static func _can_continue_raid(ship, target_ship: Node3D) -> bool:
	if not _can_initiate_raid(ship):
		return false
	if not _is_valid_raid_target_ship(ship, target_ship):
		return false
	if not _is_ship_close_for_raid(ship, target_ship):
		return false
	if _count_ranged_enemies_on_ship(target_ship) <= 0:
		return false
	return true


static func _dispatch_raid_boarders(ship, target_ship: Node3D) -> void:
	var desired_boarders: int = _get_desired_boarder_count(ship, target_ship)
	if desired_boarders <= 0:
		_recall_raid_boarders(ship)
		return

	var current_boarders: Array = _get_home_boarders_on_ship(ship, target_ship)
	if current_boarders.size() >= desired_boarders:
		return

	var available: Array = _get_available_raid_boarders(ship)
	if available.is_empty():
		return

	available.sort_custom(func(a: Node, b: Node) -> bool:
		return _get_boarder_priority(a) > _get_boarder_priority(b)
	)

	for soldier in available:
		if current_boarders.size() >= desired_boarders:
			break
		if not is_instance_valid(soldier):
			continue
		soldier._jump_to_ship(target_ship)
		current_boarders.append(soldier)


static func _recall_raid_boarders(ship) -> void:
	var all_soldiers = ship.get_tree().get_nodes_in_group("soldiers")
	for soldier in all_soldiers:
		if not is_instance_valid(soldier):
			continue
		if soldier.get("team") != "player":
			continue
		if soldier.get("current_state") == 4:
			continue
		if soldier.get("home_ship") != ship:
			continue
		if soldier.get("owned_ship") == ship:
			continue
		if bool(soldier.get("_is_jumping")):
			continue
		if soldier.has_method("_try_evacuate_to_home"):
			soldier._try_evacuate_to_home()


static func _count_enemy_boarders_on_ship(ship) -> int:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return 0
	var count: int = 0
	for soldier in soldiers_node.get_children():
		if soldier.get("current_state") == 4:
			continue
		if soldier.get("team") == "enemy":
			count += 1
	return count


static func _count_home_defenders(ship) -> int:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return 0
	var count: int = 0
	for soldier in soldiers_node.get_children():
		if soldier.get("current_state") == 4:
			continue
		if soldier.get("team") != "player":
			continue
		if bool(soldier.get("_is_jumping")):
			continue
		count += 1
	return count


static func _count_boarders_from_home(ship) -> int:
	var count: int = 0
	var all_soldiers = ship.get_tree().get_nodes_in_group("soldiers")
	for soldier in all_soldiers:
		if not is_instance_valid(soldier):
			continue
		if soldier.get("team") != "player":
			continue
		if soldier.get("current_state") == 4:
			continue
		if soldier.get("home_ship") != ship:
			continue
		if soldier.get("owned_ship") != ship:
			count += 1
	return count


static func _get_home_boarders_on_ship(ship, target_ship: Node3D) -> Array:
	var result: Array = []
	var all_soldiers = ship.get_tree().get_nodes_in_group("soldiers")
	for soldier in all_soldiers:
		if not is_instance_valid(soldier):
			continue
		if soldier.get("team") != "player":
			continue
		if soldier.get("current_state") == 4:
			continue
		if soldier.get("home_ship") != ship:
			continue
		if soldier.get("owned_ship") == target_ship:
			result.append(soldier)
	return result


static func _get_available_raid_boarders(ship) -> Array:
	var result: Array = []
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return result

	for soldier in soldiers_node.get_children():
		if not is_instance_valid(soldier):
			continue
		if soldier.get("team") != "player":
			continue
		if soldier.get("current_state") == 4:
			continue
		if bool(soldier.get("_is_jumping")):
			continue
		if bool(soldier.get("is_ranged_only")):
			continue
		if is_captain(ship, soldier):
			continue
		result.append(soldier)
	return result


static func _get_boarder_priority(soldier: Node) -> int:
	var role: String = String(soldier.get("crew_role"))
	if bool(soldier.get("is_melee_only")):
		return 3
	if role == "spearman":
		return 2
	return 1


static func _get_desired_boarder_count(ship, target_ship: Node3D) -> int:
	var home_defenders: int = _count_home_defenders(ship)
	var reserve: int = int(ship.auto_raid_min_defenders)
	var spare: int = max(0, home_defenders - reserve)
	if spare <= 0:
		return 0

	var enemy_ranged: int = _count_ranged_enemies_on_ship(target_ship)
	var desired: int = min(int(ship.auto_raid_max_boarders), spare, max(1, enemy_ranged))
	return desired


static func _count_ranged_enemies_on_ship(target_ship: Node3D) -> int:
	var soldiers_node = target_ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return 0
	var count: int = 0
	for soldier in soldiers_node.get_children():
		if soldier.get("current_state") == 4:
			continue
		if soldier.get("team") != "enemy":
			continue
		if bool(soldier.get("is_ranged_only")):
			count += 1
	return count


static func _is_valid_raid_target_ship(ship, target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if target_ship == ship:
		return false
	if not target_ship.is_in_group("enemy"):
		return false
	if target_ship.get("team") == "player":
		return false
	if target_ship.get("is_dying") or target_ship.get("is_sinking") or target_ship.get("is_derelict"):
		return false
	return true


static func _is_ship_close_for_raid(ship, target_ship: Node3D) -> bool:
	if not ship.has_method("_is_side_boarding_approach"):
		return false
	if not bool(ship.call("_is_side_boarding_approach", target_ship)):
		return false
	var my_ext: Vector2 = ship.get_deck_half_extents()
	var other_ext: Vector2 = target_ship.get_deck_half_extents() if target_ship.has_method("get_deck_half_extents") else Vector2(2.0, 3.0)
	var max_distance: float = my_ext.y + other_ext.y + RAID_SWITCH_BUFFER
	return ship.global_position.distance_to(target_ship.global_position) <= max_distance
