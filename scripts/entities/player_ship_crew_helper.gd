extends RefCounted

static func get_desired_player_crew_roles(ship) -> Dictionary:
	var desired := {
		ship.CREW_ROLE_GENERAL: ship.max_crew_count,
		ship.CREW_ROLE_SPEARMAN: 0,
		ship.CREW_ROLE_FIRE_POT: 0,
		ship.CREW_ROLE_REPEATING_CROSSBOW: 0,
		ship.CREW_ROLE_SINGIGEON: 0,
	}
	if is_instance_valid(ship._cached_um) and ship._cached_um.has_method("get_player_crew_roster"):
		var roster = ship._cached_um.get_player_crew_roster(ship.max_crew_count)
		for key in desired.keys():
			desired[key] = int(roster.get(key, desired[key]))
	return desired

static func get_soldier_role(ship, soldier: Node) -> String:
	if soldier == null:
		return ship.CREW_ROLE_GENERAL
	if "crew_role" in soldier:
		return String(soldier.crew_role)
	return String(soldier.get_meta("crew_role", ship.CREW_ROLE_GENERAL))

static func spawn_player_soldier(ship, soldiers_node: Node, role: String) -> Node:
	var soldier = ship.SOLDIER_SCENE.instantiate()
	soldiers_node.add_child(soldier)
	soldier.set_team("player")
	if soldier.has_method("apply_crew_role"):
		soldier.apply_crew_role(role)
	else:
		soldier.set_meta("crew_role", role)
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
		var role = get_soldier_role(ship, child)
		if not alive_by_role.has(role):
			role = ship.CREW_ROLE_GENERAL
		alive_by_role[role].append(child)
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
		print("[Crew] 정원 초과 합류! (현재 인원: %d/%d)" % [alive_count + 1, ship.max_crew_count])

	var desired = get_desired_player_crew_roles(ship)
	var current_by_role := {
		ship.CREW_ROLE_GENERAL: 0,
		ship.CREW_ROLE_SPEARMAN: 0,
		ship.CREW_ROLE_FIRE_POT: 0,
		ship.CREW_ROLE_REPEATING_CROSSBOW: 0,
		ship.CREW_ROLE_SINGIGEON: 0,
	}
	for child in soldiers_node.get_children():
		if child.get("current_state") == 4 or child.get("team") != "player":
			continue
		var role = get_soldier_role(ship, child)
		if not current_by_role.has(role):
			role = ship.CREW_ROLE_GENERAL
		current_by_role[role] += 1

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
