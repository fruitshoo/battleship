@tool
extends "res://scripts/test/chaser_isolation_process_ai.gd"

var has_rammed: bool = false


func can_board_targets() -> bool:
	return allow_boarding


func capture_ship() -> void:
	if team == "player":
		return

	if EntityRegistry.count_captured_minions() >= 1:
		print("[Limitation] 함대 정원 초과! 적함을 파괴합니다.")
		die()
		return

	set_team("player")
	is_dying = false
	is_derelict = false
	is_burning = false
	fire_build_up = 0.0
	leaking_rate = 0.0
	hull_hp = max(hull_hp, max_hull_hp * 0.3)

	_cancel_boarding()
	if is_instance_valid(boarding_attacker):
		boarding_attacker._cancel_boarding()
		boarding_attacker = null

	tilt_offset = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	base_y = 0.0
	global_position.y = 0.0

	var tweens = get_tree().get_processed_tweens()
	for tween in tweens:
		pass

	var players = EntityRegistry.get_ships_by_team("player")
	if players.size() > 0 and players[0].get("is_player_controlled"):
		move_speed = players[0].get("max_speed")
	else:
		move_speed = 10.0

	if not is_in_group("captured_minion"):
		add_to_group("captured_minion")
		EntityRegistry.register_captured_minion(self)

	_update_children_team_for_capture()
	_refresh_deck_light()
	_apply_minion_visuals()

	if is_instance_valid(cached_lm):
		var capture_score_reward: int = max(0, int(cached_lm.get("boarding_capture_score_reward")))
		var capture_xp_reward: int = max(0, int(cached_lm.get("boarding_capture_xp_reward")))
		var capture_bonus_xp_reward: int = max(0, int(cached_lm.get("boarding_capture_bonus_xp_reward")))
		if capture_score_reward > 0 and cached_lm.has_method("add_score"):
			cached_lm.add_score(capture_score_reward)
		if capture_xp_reward > 0 and cached_lm.has_method("add_xp"):
			cached_lm.add_xp(capture_xp_reward)
		if capture_bonus_xp_reward > 0 and cached_lm.has_method("add_bonus_xp"):
			cached_lm.add_bonus_xp(capture_bonus_xp_reward)

	if is_instance_valid(cached_lm) and cached_lm.has_method("show_message"):
		cached_lm.show_message("적군 함선을 나포했습니다!", 3.0)

	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_stats_to_minion"):
		upgrade_manager.apply_fleet_stats_to_minion(self)

	target = null
	_find_player()

	_equip_minion_cannons()
	upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager):
		upgrade_manager.apply_fleet_upgrades_to_ship(self)

	print("[Capture] 나포 성공! 함대에 합류합니다. (target: %s)" % str(target))


func _equip_minion_cannons() -> void:
	if not cannon_scene:
		return

	_remove_all_cannons()

	var spawn_points = [
		{"pos": Vector3(0, 0.8, -3.5), "rot": 0},
		{"pos": Vector3(-1.0, 0.8, -0.5), "rot": 90},
		{"pos": Vector3(1.0, 0.8, -0.5), "rot": -90}
	]

	var i = 0
	for p in spawn_points:
		var cannon = cannon_scene.instantiate()
		cannon.name = "FleetCannon_" + str(i)
		add_child(cannon)
		cannon.position = p["pos"]
		cannon.rotation_degrees.y = p["rot"]
		if cannon.has_method("set_team"):
			cannon.set_team("player")
		if i > 0:
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)
		i += 1


func _update_children_team_for_capture() -> void:
	_update_children_team()
	for s in $Soldiers.get_children():
		if s.has_method("set_team"):
			s.set_team("player")
			s.owned_ship = self


func _remove_all_cannons() -> void:
	_recursive_remove_cannons(self)


func _recursive_remove_cannons(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("fire") or "cannonball_scene" in child:
			child.queue_free()
		else:
			_recursive_remove_cannons(child)


func _apply_minion_visuals() -> void:
	for mast in masts:
		if mast.has_method("set_sail_color"):
			mast.set_sail_color(Color(0.9, 0.9, 1.0, 1.0))
		if mast.has_method("set_team_color"):
			mast.set_team_color("player")

	if is_instance_valid(_fire_instance):
		_set_fire_emitting(false)


func _process_minion_ai(delta: float) -> void:
	ChaserShipMinionHelper.process_minion_ai(self, delta)


func _update_wave_sounds(delta: float) -> void:
	ChaserShipAiHelper.update_wave_sounds(self, delta)


func apply_fleet_weapon_upgrade(level: int) -> void:
	var cannons = []
	for child in get_children():
		if child.name.begins_with("FleetCannon_"):
			cannons.append(child)

	var active_count = 1
	if level >= 2:
		active_count = 2
	if level >= 3:
		active_count = 3

	for i in range(cannons.size()):
		var cannon = cannons[i]
		if i < active_count:
			cannon.visible = true
			cannon.set_process(true)
			cannon.set_physics_process(true)
		else:
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)

	print("[Fleet] 함대 무장 업그레이드 적용: Lv.%d (대포 %d문 활성화)" % [level, active_count])


func repair_ship(percent: float) -> void:
	var amt = max_hull_hp * percent
	hull_hp = minf(hull_hp + amt, max_hull_hp)
	print("[Fleet] 함선 수리됨: +%d HP" % amt)


func _process_boarding(delta: float) -> void:
	ChaserShipBoardingHelper.process_boarding(self, delta)


func _apply_neighbor_ship_guards(prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null) -> Vector3:
	return ChaserShipBoardingHelper.apply_neighbor_ship_guards(self, prev_pos, proposed_pos, excluded_ship)


func _apply_ship_collision_guard(other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = 0.94, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	return ChaserShipBoardingHelper.apply_ship_collision_guard(self, other_ship, prev_pos, proposed_pos, safe_ratio, impact_speed_hint, emit_collision_event)


func _emit_guarded_collision(other_ship: Node3D, impact_speed_hint: float) -> void:
	ChaserShipBoardingHelper.emit_guarded_collision(self, other_ship, impact_speed_hint)


func _soften_collision_speed() -> void:
	ChaserShipBoardingHelper.soften_collision_speed(self)


func _find_player() -> void:
	ChaserShipAiHelper.find_player(self)


func _on_body_entered(body: Node3D) -> void:
	if not can_board_targets():
		return
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		_board_ship(body)


func _on_area_entered(area: Area3D) -> void:
	if not can_board_targets():
		return
	if area.is_in_group("ship_hitbox"):
		return

	if area.is_in_group("player"):
		_board_ship(area)
	elif area.is_in_group("ship_proximity"):
		var role_parent = area.get_parent()
		if role_parent and role_parent.is_in_group("player"):
			_board_ship(role_parent)


func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01:
		tilt_offset = 0.0


func _board_ship(target_ship: Node3D) -> void:
	if not can_board_targets():
		return
	if is_dying or is_boarding:
		return

	if get_alive_crew_count() <= 0:
		return

	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not (ship_node and ship_node.is_in_group("player")):
			return

	if ship_node.get("team") == team:
		return

	if team == "player":
		return

	if is_derelict:
		return

	if not _is_side_boarding_approach(ship_node):
		return

	if not has_rammed:
		has_rammed = true
		if DEBUG_COMBAT_LOGS:
			print("[Impact] 충돌 발생! 도선 시작.")

	if ship_node != boarding_target:
		boarding_target = ship_node

	is_boarding = true
	boarding_target = ship_node

	if boarding_target.has_method("set_boarding_attacker_ship"):
		boarding_target.set_boarding_attacker_ship(self)

	_clear_ropes()
	boarding_timer = 0.0
	boarding_prep_timer = 0.0
	boarding_contact_timer = 0.0
	boarding_hook_timer = 0.0
	boarding_secondary_rope_timer = 0.0
	_initial_rope_deployed = false
	_full_rope_deployed = false

	if DEBUG_COMBAT_LOGS:
		print("[Boarding] 접점 확보! 접현 후 갈고리 투척을 준비합니다.")


func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)


func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
