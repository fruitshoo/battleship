extends RefCounted

const SOLDIER_SCENE = preload("res://scenes/entities/soldiers/soldier.tscn")

static func handle_input(ship, delta: float) -> void:
	var sail_turn_speed: float = float(ship.sail_turn_speed)
	if Input.is_action_pressed("sail_left"):
		ship.adjust_sail_angle(-sail_turn_speed * delta)
	if Input.is_action_pressed("sail_right"):
		ship.adjust_sail_angle(sail_turn_speed * delta)

	var steer_input = 0.0
	if Input.is_action_pressed("ship_left"):
		steer_input = -1.0
	elif Input.is_action_pressed("ship_right"):
		steer_input = 1.0
	ship.steer(steer_input, delta)

	if Input.is_action_pressed("row_forward"):
		ship.set_rowing(true)
	elif Input.is_action_pressed("row_backward"):
		ship.set_rowing(true)
	else:
		if ship.is_rowing:
			ship.set_rowing(false)

static func toggle_fleet_formation(ship) -> void:
	ship.CHASER_SHIP_SCRIPT.support_hold_formation = not bool(ship.CHASER_SHIP_SCRIPT.support_hold_formation)
	if ship.CHASER_SHIP_SCRIPT.support_hold_formation:
		ship.CHASER_SHIP_SCRIPT.fleet_formation = ship.CHASER_SHIP_SCRIPT.Formation.COLUMN
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("지원함: 진형 유지", 2.0)
	else:
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("지원함: 자유 교전", 2.0)

static func update_rowing_audio(ship, delta: float) -> void:
	if ship.is_rowing:
		if ship._oars_timer <= 0:
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
				var pitch := randf_range(0.95, 1.05)
				if ship.rowing_locked:
					pitch = randf_range(0.85, 0.92)
				ship._cached_audio_manager.play_sfx("oars_rowing", ship.global_position, pitch, 5.0)
			ship._oars_timer = 1.8 if ship.rowing_locked else 1.3
		else:
			ship._oars_timer -= delta

		if ship.rowing_stamina > 0.1 and not ship.rowing_locked and not ship._gilgunak_playing:
			ship._gilgunak_playing = true
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_gilgunak"):
				ship._cached_audio_manager.play_gilgunak(true)
	else:
		ship._oars_timer = 0.0
		if ship._gilgunak_playing:
			ship._gilgunak_playing = false
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_gilgunak"):
				ship._cached_audio_manager.play_gilgunak(false)

static func capture_derelict_ship(ship) -> void:
	print("[Capture] 폐선 나포 성공! 보상을 획득합니다.")
	if is_instance_valid(ship._cached_level_manager):
		var score_reward: int = max(0, int(ship._cached_level_manager.get("boarding_capture_score_reward")))
		var xp_reward: int = max(0, int(ship._cached_level_manager.get("boarding_capture_xp_reward")))
		var merit_reward: int = max(0, int(ship._cached_level_manager.get("boarding_capture_merit_reward")))
		if score_reward > 0 and ship._cached_level_manager.has_method("add_score"):
			ship._cached_level_manager.add_score(score_reward)
		if xp_reward > 0 and ship._cached_level_manager.has_method("add_xp"):
			ship._cached_level_manager.add_xp(xp_reward)
		if merit_reward > 0 and ship._cached_level_manager.has_method("add_merit"):
			ship._cached_level_manager.add_merit(merit_reward)
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("나포 성공! XP +%d / 지휘 +%d" % [xp_reward, merit_reward], 2.4)

	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.has_method("heal_full") and SoldierStateHelper.is_alive_soldier(child):
				child.heal_full()

	var alive_count = 0
	if soldiers_node:
		for child in soldiers_node.get_children():
			if SoldierStateHelper.is_alive_soldier(child):
				alive_count += 1

		if alive_count < ship.max_crew_count and is_instance_valid(ship._cached_level_manager) and ship._cached_level_manager.has_node("LevelLogic"):
			var s = SOLDIER_SCENE.instantiate()
			soldiers_node.add_child(s)
			s.set_team("player")
			var offset = Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-2.5, 2.5))
			s.position = offset
			if is_instance_valid(ship._cached_um) and ship._cached_um.has_method("_apply_current_stats_to_soldier"):
				ship._cached_um._apply_current_stats_to_soldier(s)
			print("[Crew] 포로 구출! 아군 병사 1명 합류.")

	ship._cancel_boarding()

static func replenish_crew(ship, soldier_scene: PackedScene) -> void:
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not soldiers_node or not soldier_scene:
		return
	for child in soldiers_node.get_children():
		var is_alive = SoldierStateHelper.is_alive_soldier(child)
		var is_player = child.has_method("is_player_team_soldier") and child.is_player_team_soldier()
		if not is_alive:
			child.queue_free()
		elif not is_player:
			continue
	ship._sync_player_crew_roster()
	print("[Crew] 병사 보충 완료! (현재: %d/%d)" % [ship.max_crew_count, ship.max_crew_count])
