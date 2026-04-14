extends RefCounted

const RAID_SWITCH_BUFFER: float = 2.0
const RAID_LARGE_TARGET_EDGE_BUFFER: float = 1.45
const RAID_LARGE_TARGET_ALONG_BUFFER: float = 1.0
const RAID_MAX_ACTIVE_THREATS: int = 1
const AUTO_RAID_BOARDING_PURPOSE := "auto_raid"
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")

static func get_desired_player_captain_count(ship) -> int:
	return clampi(int(ship.captain_count), 0, maxi(0, int(ship.max_crew_count)))

static func is_captain(ship, soldier: Node) -> bool:
	if soldier == null:
		return false
	if "is_captain" in soldier:
		return soldier.is_captain == true
	return soldier.get_meta("is_captain", false) == true

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
		return str(soldier.crew_role)
	return str(soldier.get_meta("crew_role", ship.CREW_ROLE_GENERAL))

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

static func get_player_roster_count(ship) -> int:
	var count := 0
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(child):
			continue
		if child.has_method("is_player_team_soldier") and not child.is_player_team_soldier():
			continue
		elif not child.has_method("is_player_team_soldier") and str(child.get("team")) != "player":
			continue
		var is_incapacitated: bool = child.has_method("is_incapacitated_soldier") and child.is_incapacitated_soldier()
		if is_incapacitated:
			count += 1
		elif child.has_method("is_dead_soldier") and not child.is_dead_soldier():
			count += 1
	return count

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
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		if child.has_method("is_dead_soldier") and child.is_dead_soldier():
			continue
		if child.has_method("is_player_team_soldier") and not child.is_player_team_soldier():
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

static func add_survivor(ship, allow_over_capacity: bool = false) -> bool:
	return _add_player_crew(ship, allow_over_capacity, "survivor")

static func add_respawn_crew(ship) -> bool:
	return _add_player_crew(ship, false, "respawn")

static func _add_player_crew(ship, allow_over_capacity: bool, source: String) -> bool:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return false
	var roster_count: int = get_player_roster_count(ship)
	if not allow_over_capacity and roster_count >= int(ship.max_crew_count):
		return false
	var alive_count = roster_count
	var soldiers = EntityRegistry.get_soldiers_by_ship(ship)
	for child in soldiers:
		if child.has_method("is_player_team_soldier") and child.is_player_team_soldier():
			continue
		elif not child.has_method("is_player_team_soldier") and str(child.get("team")) == "player":
			continue
		if child.has_method("is_incapacitated_soldier") and child.is_incapacitated_soldier():
			continue
		elif child.has_method("is_dead_soldier") and not child.is_dead_soldier():
			continue
		else:
			child.queue_free()

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
	for child in soldiers:
		if child.has_method("is_dead_soldier") and child.is_dead_soldier():
			continue
		if child.has_method("is_player_team_soldier") and not child.is_player_team_soldier():
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
		var captain_message: String = "생존자 구조: 장군 복귀" if source == "survivor" else "병사 보충: 장군 복귀"
		print("[%s] 장군 1명이 복귀했습니다. (현재: %d/%d)" % [_get_crew_add_log_tag(source), alive_count + 1, ship.max_crew_count])
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message(captain_message, 2.0)
		var captain_audio_manager = ship.get_node_or_null("/root/AudioManager")
		if is_instance_valid(captain_audio_manager) and captain_audio_manager.has_method("play_sfx"):
			captain_audio_manager.play_sfx("soldier_hit", ship.global_position, 1.45)
		return true

	var role_to_add = ship.CREW_ROLE_GENERAL
	var found_slot := false
	for candidate in [ship.CREW_ROLE_SPEARMAN, ship.CREW_ROLE_REPEATING_CROSSBOW, ship.CREW_ROLE_SINGIGEON, ship.CREW_ROLE_FIRE_POT, ship.CREW_ROLE_GENERAL]:
		if int(current_by_role.get(candidate, 0)) < int(desired.get(candidate, 0)):
			role_to_add = candidate
			found_slot = true
			break
	if not found_slot and not allow_over_capacity:
		return false
	spawn_player_soldier(ship, soldiers_node, role_to_add)

	var crew_message: String = "생존자 구조 완료!" if source == "survivor" else "병사 보충 완료!"
	print("[%s] 아군 병사 1명 합류. (현재: %d/%d)" % [_get_crew_add_log_tag(source), alive_count + 1, ship.max_crew_count])
	if ship._cached_hud and ship._cached_hud.has_method("show_message"):
		ship._cached_hud.show_message(crew_message, 2.0)
	var audio_manager = ship.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("soldier_hit", ship.global_position, 1.5)
	return true

static func _get_crew_add_log_tag(source: String) -> String:
	return "Rescue" if source == "survivor" else "Crew"

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
	var boarding_attacker: Node3D = ship.get_boarding_attacker_ship() if ship.has_method("get_boarding_attacker_ship") else null
	if not is_instance_valid(boarding_attacker) or (boarding_attacker.has_method("is_combat_disabled") and boarding_attacker.is_combat_disabled()):
		return

	var target = boarding_attacker
	var dist = ship.global_position.distance_to(target.global_position)
	if dist > 15.0:
		return

	var tosser = null
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		if child.has_method("is_dead_soldier") and child.is_dead_soldier():
			continue
		if child.has_method("is_player_team_soldier") and not child.is_player_team_soldier():
			continue
		if get_soldier_role(ship, child) == ship.CREW_ROLE_FIRE_POT:
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

	var pot = ship.ScenePool.acquire(ship.get_tree(), ship.fire_pot_scene)
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
	if ship.auto_raid_enabled != true:
		_recall_raid_boarders(ship)
		_cancel_auto_raid_boarding_link(ship)
		ship.auto_raid_target = null
		return
	var is_auto_raid_boarding: bool = ship.is_boarding and str(ship.get_meta("boarding_purpose", "")) == AUTO_RAID_BOARDING_PURPOSE
	if ship.is_sinking or ship.is_dying or (ship.is_boarding and not is_auto_raid_boarding):
		_recall_raid_boarders(ship)
		_cancel_auto_raid_boarding_link(ship)
		ship.auto_raid_target = null
		return

	ship.auto_raid_eval_timer = maxf(0.0, float(ship.auto_raid_eval_timer) - delta)

	var current_target: Node3D = ship.auto_raid_target
	if is_instance_valid(current_target) and not _can_continue_raid(ship, current_target):
		if _recall_raid_boarders_with_link(ship, current_target):
			ship.auto_raid_target = current_target
			return
		current_target = null

	if ship.auto_raid_eval_timer <= 0.0:
		ship.auto_raid_eval_timer = float(ship.auto_raid_eval_interval)
		var next_target: Node3D = _find_raid_target(ship)
		if current_target != next_target and _count_boarders_from_home(ship) > 0:
			if _recall_raid_boarders_with_link(ship, current_target):
				ship.auto_raid_target = current_target
				return
			_recall_raid_boarders(ship, current_target)
			current_target = null
		else:
			current_target = next_target

	ship.auto_raid_target = current_target

	if is_instance_valid(current_target):
		_ensure_auto_raid_boarding_link(ship, current_target)
		_dispatch_raid_boarders(ship, current_target)
	else:
		_cancel_auto_raid_boarding_link(ship)
		_recall_raid_boarders(ship)


static func _find_raid_target(ship) -> Node3D:
	if not _can_initiate_raid(ship):
		return null

	var own_crew: int = ship.get_alive_crew_count()
	var candidates: Array = []
	var nearby_enemy_count: int = 0
	var boss_candidate_present: bool = false
	var enemies = EntityRegistry.get_ships_by_team("enemy")
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
		var raid_pressure: int = _get_raid_pressure_value(enemy)
		if raid_pressure <= 0:
			continue
		var score: float = float(raid_pressure) * 10.0
		score += float(own_crew - enemy_crew) * 2.0
		score -= dist * 0.15
		if _is_boss_raid_target(enemy):
			score += 14.0
			boss_candidate_present = true
		candidates.append({
			"ship": enemy,
			"score": score,
		})

	if nearby_enemy_count > RAID_MAX_ACTIVE_THREATS and not boss_candidate_present:
		return null
	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return candidates[0]["ship"] as Node3D


static func get_auto_raid_debug_snapshot(ship, target_ship: Node3D = null) -> Dictionary:
	var snapshot := {
		"enabled": false,
		"can_initiate": false,
		"valid_target": false,
		"close_for_raid": false,
		"continue_ok": false,
		"own_crew": 0,
		"home_defenders": 0,
		"reserve": 0,
		"spare": 0,
		"enemy_ranged": 0,
		"desired_boarders": 0,
		"current_boarders": 0,
		"available_boarders": 0,
	}
	if not is_instance_valid(ship):
		return snapshot
	snapshot["enabled"] = ship.auto_raid_enabled == true
	snapshot["own_crew"] = ship.get_alive_crew_count() if ship.has_method("get_alive_crew_count") else 0
	snapshot["home_defenders"] = _count_home_defenders(ship)
	snapshot["reserve"] = int(ship.auto_raid_min_defenders)
	snapshot["spare"] = max(0, int(snapshot["home_defenders"]) - int(snapshot["reserve"]))
	snapshot["can_initiate"] = _can_initiate_raid(ship)

	var target: Node3D = target_ship
	if not is_instance_valid(target) and "auto_raid_target" in ship:
		target = ship.auto_raid_target
	if not is_instance_valid(target):
		return snapshot

	snapshot["valid_target"] = _is_valid_raid_target_ship(ship, target)
	snapshot["close_for_raid"] = _is_ship_close_for_raid(ship, target)
	snapshot["continue_ok"] = _can_continue_raid(ship, target)
	snapshot["enemy_ranged"] = _count_ranged_enemies_on_ship(target)
	snapshot["raid_pressure"] = _get_raid_pressure_value(target)
	snapshot["desired_boarders"] = _get_desired_boarder_count(ship, target)
	snapshot["current_boarders"] = _get_home_boarders_on_ship(ship, target).size()
	snapshot["available_boarders"] = _get_available_raid_boarders(ship).size()
	return snapshot


static func _can_initiate_raid(ship) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.get_hull_ratio() < float(ship.auto_raid_min_hull_ratio):
		return false
	if _count_enemy_boarders_on_ship(ship) > 0:
		return false
	if ship.has_method("get_boarding_attacker_ship") and is_instance_valid(ship.get_boarding_attacker_ship()):
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
	if _get_raid_pressure_value(target_ship) <= 0:
		return false
	return true


static func _dispatch_raid_boarders(ship, target_ship: Node3D) -> void:
	var desired_boarders: int = _get_desired_boarder_count(ship, target_ship)
	if desired_boarders <= 0:
		_recall_raid_boarders(ship)
		return
	if not _has_auto_raid_boarding_rope_ready(ship, target_ship):
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


static func _ensure_auto_raid_boarding_link(ship, target_ship: Node3D) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(target_ship):
		return
	if ship.is_boarding and ship.get_boarding_target_ship() == target_ship and str(ship.get_meta("boarding_purpose", "")) == AUTO_RAID_BOARDING_PURPOSE:
		return
	if ship.is_boarding:
		if str(ship.get_meta("boarding_purpose", "")) != AUTO_RAID_BOARDING_PURPOSE:
			return
		_cancel_auto_raid_boarding_link(ship)

	ship.is_boarding = true
	ship.boarding_target = target_ship
	ship.set_meta("boarding_purpose", AUTO_RAID_BOARDING_PURPOSE)
	ship.set_meta("boarding_transfer_suppressed", true)
	if ship.has_method("_is_side_boarding_approach") and ship._is_side_boarding_approach(target_ship):
		ship.set_meta("boarding_contact_mode", "side")
	else:
		ship.set_meta("boarding_contact_mode", "cleanup")

	var hold_forward: Vector3 = -ship.global_transform.basis.z
	hold_forward.y = 0.0
	if hold_forward.length_squared() > 0.001:
		ship.set_meta("boarding_hold_forward", hold_forward.normalized())
	if target_ship.has_method("set_boarding_attacker_ship"):
		target_ship.set_boarding_attacker_ship(ship)
	if ship.has_method("_clear_ropes"):
		ship._clear_ropes()
	ship.boarding_timer = 0.0
	ship.boarding_prep_timer = 0.0
	ship.boarding_contact_timer = 0.0
	ship.boarding_hook_timer = 0.0
	ship.boarding_secondary_rope_timer = 0.0
	ship.set_meta("boarding_motion_settle_timer", 0.0)
	if "_initial_rope_deployed" in ship:
		ship.set("_initial_rope_deployed", false)
	if "_full_rope_deployed" in ship:
		ship.set("_full_rope_deployed", false)


static func _cancel_auto_raid_boarding_link(ship) -> void:
	if not is_instance_valid(ship):
		return
	if str(ship.get_meta("boarding_purpose", "")) != AUTO_RAID_BOARDING_PURPOSE:
		return
	if ship.has_method("_cancel_boarding"):
		ship._cancel_boarding()
		return
	ship.is_boarding = false
	ship.boarding_target = null
	ship.remove_meta("boarding_purpose")
	ship.remove_meta("boarding_transfer_suppressed")


static func _has_auto_raid_boarding_rope_ready(ship, target_ship: Node3D) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(target_ship):
		return false
	if str(ship.get_meta("boarding_purpose", "")) != AUTO_RAID_BOARDING_PURPOSE:
		return false
	if not ship.is_boarding or ship.get_boarding_target_ship() != target_ship:
		return false
	if ship.has_method("has_boarding_rope_link_to"):
		return ship.has_boarding_rope_link_to(target_ship) == true
	if "_initial_rope_deployed" in ship:
		return ship.get("_initial_rope_deployed") == true
	return false


static func _recall_raid_boarders_with_link(ship, target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if _get_home_boarders_on_ship(ship, target_ship).is_empty():
		return false
	_ensure_auto_raid_boarding_link(ship, target_ship)
	_recall_raid_boarders(ship, target_ship)
	return not _get_home_boarders_on_ship(ship, target_ship).is_empty()


static func _recall_raid_boarders(ship, target_ship: Node3D = null) -> void:
	var all_soldiers = EntityRegistry.get_soldiers_by_team("player")
	for soldier in all_soldiers:
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_player_team_soldier") and not soldier.is_player_team_soldier():
			continue
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("get_home_ship_node") and soldier.get_home_ship_node() != ship:
			continue
		if soldier.has_method("get_owned_ship_node") and soldier.get_owned_ship_node() == ship:
			continue
		if is_instance_valid(target_ship) and soldier.has_method("get_owned_ship_node") and soldier.get_owned_ship_node() != target_ship:
			continue
		if soldier.has_method("is_jumping_value") and soldier.is_jumping_value():
			continue
		if soldier.has_method("_try_evacuate_to_home"):
			soldier._try_evacuate_to_home()


static func _count_enemy_boarders_on_ship(ship) -> int:
	var count: int = 0
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("is_enemy_team_soldier") and soldier.is_enemy_team_soldier():
			count += 1
	return count


static func _count_home_defenders(ship) -> int:
	var count: int = 0
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("is_player_team_soldier") and not soldier.is_player_team_soldier():
			continue
		if soldier.has_method("is_jumping_value") and soldier.is_jumping_value():
			continue
		count += 1
	return count


static func _count_boarders_from_home(ship) -> int:
	var count: int = 0
	var all_soldiers = EntityRegistry.get_soldiers_by_team("player")
	for soldier in all_soldiers:
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_player_team_soldier") and not soldier.is_player_team_soldier():
			continue
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("get_home_ship_node") and soldier.get_home_ship_node() != ship:
			continue
		if soldier.has_method("get_owned_ship_node") and soldier.get_owned_ship_node() != ship:
			count += 1
	return count


static func _get_home_boarders_on_ship(ship, target_ship: Node3D) -> Array:
	var result: Array = []
	var all_soldiers = EntityRegistry.get_soldiers_by_team("player")
	for soldier in all_soldiers:
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_player_team_soldier") and not soldier.is_player_team_soldier():
			continue
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("get_home_ship_node") and soldier.get_home_ship_node() != ship:
			continue
		if soldier.has_method("get_owned_ship_node") and soldier.get_owned_ship_node() == target_ship:
			result.append(soldier)
	return result


static func _get_available_raid_boarders(ship) -> Array:
	var result: Array = []
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_player_team_soldier") and not soldier.is_player_team_soldier():
			continue
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("is_jumping_value") and soldier.is_jumping_value():
			continue
		if soldier.has_method("is_ranged_only_value") and soldier.is_ranged_only_value():
			continue
		if is_captain(ship, soldier):
			continue
		result.append(soldier)
	return result


static func _get_boarder_priority(soldier: Node) -> int:
	var role: String = str(soldier.get_crew_role_value()) if soldier.has_method("get_crew_role_value") else str(soldier.get("crew_role"))
	if soldier.has_method("is_melee_only_value") and soldier.is_melee_only_value():
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

	var raid_pressure: int = _get_raid_pressure_value(target_ship)
	var desired_cap: int = int(ship.auto_raid_max_boarders)
	if _is_boss_raid_target(target_ship):
		desired_cap += 1
	var desired: int = min(desired_cap, spare, max(1, raid_pressure))
	if _is_boss_raid_target(target_ship) and spare >= 2:
		desired = max(desired, min(desired_cap, 2))
	return desired


static func _count_ranged_enemies_on_ship(target_ship: Node3D) -> int:
	var count: int = 0
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("is_enemy_team_soldier") and not soldier.is_enemy_team_soldier():
			continue
		if soldier.has_method("is_ranged_only_value") and soldier.is_ranged_only_value():
			count += 1
	return count


static func _get_raid_pressure_value(target_ship: Node3D) -> int:
	if not is_instance_valid(target_ship):
		return 0
	var enemy_ranged: int = _count_ranged_enemies_on_ship(target_ship)
	if enemy_ranged > 0:
		return enemy_ranged
	if _is_boss_raid_target(target_ship):
		var enemy_crew: int = int(target_ship.call("get_alive_crew_count")) if target_ship.has_method("get_alive_crew_count") else 0
		if enemy_crew > 0:
			return maxi(1, ceili(float(enemy_crew) / 3.0))
	return 0


static func _is_valid_raid_target_ship(ship, target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if target_ship == ship:
		return false
	if target_ship.has_method("get_team_tag"):
		if target_ship.get_team_tag() != "enemy":
			return false
	elif not target_ship.is_in_group("enemy"):
		return false
	if target_ship.has_method("is_player_team") and target_ship.is_player_team():
		return false
	if target_ship.has_method("is_sinking_or_dying") and target_ship.is_sinking_or_dying():
		return false
	if target_ship.has_method("is_derelict_ship") and target_ship.is_derelict_ship():
		return false
	return true


static func _is_ship_close_for_raid(ship, target_ship: Node3D) -> bool:
	var my_ext: Vector2 = ship.get_deck_half_extents()
	var other_ext: Vector2 = target_ship.get_deck_half_extents() if target_ship.has_method("get_deck_half_extents") else Vector2(2.0, 3.0)
	var center_distance: float = ship.global_position.distance_to(target_ship.global_position)
	var max_distance: float = my_ext.y + other_ext.y + RAID_SWITCH_BUFFER
	var large_target: bool = _is_large_raid_target(target_ship, other_ext)
	if large_target:
		var broad_phase_distance: float = max_distance + maxf(my_ext.x, other_ext.x) * 0.75
		if ship.has_method("get_collision_distance_to"):
			broad_phase_distance = maxf(broad_phase_distance, float(ship.call("get_collision_distance_to", target_ship)) + RAID_SWITCH_BUFFER)
		if center_distance > broad_phase_distance:
			return false
		return _has_raid_deck_edge_contact(ship, target_ship, my_ext, other_ext)
	var hull_contact_distance: float = max_distance
	if ship.has_method("get_collision_distance_to"):
		hull_contact_distance = maxf(hull_contact_distance, float(ship.call("get_collision_distance_to", target_ship)) + RAID_SWITCH_BUFFER)
	if center_distance > hull_contact_distance:
		return false
	if ship.has_method("_is_side_boarding_approach") and ship.call("_is_side_boarding_approach", target_ship) == true:
		return true

	# 대형 선체는 중심점/접점 기준 오차가 더 커서 자동 월선 판정을 조금 완화한다.
	var combined_length: float = my_ext.y + other_ext.y
	if combined_length < 8.5:
		return false
	if not ship.has_method("_get_boarding_alignment_state"):
		return false
	var state: Variant = ship.call("_get_boarding_alignment_state", target_ship)
	if typeof(state) != TYPE_DICTIONARY:
		return false
	var boarding_state: Dictionary = state as Dictionary
	if boarding_state.is_empty():
		return false
	var my_contact_abs: float = absf(float(boarding_state.get("my_contact_dot", 1.0)))
	var target_contact_abs: float = absf(float(boarding_state.get("target_contact_dot", 1.0)))
	var parallel_dot: float = float(boarding_state.get("parallel_dot", -1.0))
	return my_contact_abs <= 0.82 and target_contact_abs <= 0.82 and parallel_dot >= -0.15


static func _has_raid_deck_edge_contact(ship, target_ship: Node3D, my_ext: Vector2, other_ext: Vector2) -> bool:
	if not ship.has_method("_get_boarding_alignment_state"):
		return false
	var state: Variant = ship.call("_get_boarding_alignment_state", target_ship)
	if typeof(state) != TYPE_DICTIONARY:
		return false
	var boarding_state: Dictionary = state as Dictionary
	if boarding_state.is_empty():
		return false

	var my_contact_abs: float = absf(float(boarding_state.get("my_contact_dot", 1.0)))
	var target_contact_abs: float = absf(float(boarding_state.get("target_contact_dot", 1.0)))
	var parallel_dot: float = float(boarding_state.get("parallel_dot", -1.0))
	if my_contact_abs > 0.86 or target_contact_abs > 0.86 or parallel_dot < -0.2:
		return false

	var target_local_on_ship: Vector3 = ship.to_local(target_ship.global_position)
	var ship_local_on_target: Vector3 = target_ship.to_local(ship.global_position)
	var total_width: float = my_ext.x + other_ext.x
	var total_length: float = my_ext.y + other_ext.y
	var lateral_gap: float = maxf(
		absf(target_local_on_ship.x) - total_width,
		absf(ship_local_on_target.x) - total_width
	)
	if lateral_gap > RAID_LARGE_TARGET_EDGE_BUFFER:
		return false
	var along_gap: float = maxf(
		absf(target_local_on_ship.z) - total_length,
		absf(ship_local_on_target.z) - total_length
	)
	return along_gap <= RAID_LARGE_TARGET_ALONG_BUFFER


static func _is_large_raid_target(target_ship: Node3D, target_ext: Vector2) -> bool:
	if target_ext.y >= 5.0 or target_ext.x >= 3.8:
		return true
	if target_ship.is_in_group("boss"):
		return true
	if "ship_type" in target_ship:
		var ship_type_name: String = str(target_ship.get("ship_type")).to_lower()
		if ship_type_name.contains("atakebune"):
			return true
	return false


static func _is_boss_raid_target(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if target_ship.is_in_group("boss"):
		return true
	if "ship_type" in target_ship:
		var ship_type_name: String = str(target_ship.get("ship_type")).to_lower()
		return ship_type_name.contains("atakebune")
	return false
