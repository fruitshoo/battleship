extends RefCounted

const SOLDIER_SCENE = preload("res://scenes/soldier.tscn")

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

	if Input.is_key_pressed(KEY_F) and Engine.get_physics_frames() % 30 == 0:
		toggle_fleet_formation(ship)

static func toggle_fleet_formation(ship) -> void:
	if ship.CHASER_SHIP_SCRIPT.fleet_formation == ship.CHASER_SHIP_SCRIPT.Formation.COLUMN:
		ship.CHASER_SHIP_SCRIPT.fleet_formation = ship.CHASER_SHIP_SCRIPT.Formation.WING
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("함대 진형: 학익진 (Wing)", 2.0)
	else:
		ship.CHASER_SHIP_SCRIPT.fleet_formation = ship.CHASER_SHIP_SCRIPT.Formation.COLUMN
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("함대 진형: 장사진 (Column)", 2.0)

static func update_rowing_audio(ship, delta: float) -> void:
	if ship.is_rowing and not ship.rowing_locked and ship.rowing_stamina > 0:
		if ship._oars_timer <= 0:
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
				ship._cached_audio_manager.play_sfx("oars_rowing", ship.global_position, randf_range(0.95, 1.05), 5.0)
			ship._oars_timer = 1.3
		else:
			ship._oars_timer -= delta

		if ship.rowing_stamina > 0.1 and not ship._gilgunak_playing:
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
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.has_method("heal_full") and child.get("current_state") != 4:
				child.heal_full()

	var alive_count = 0
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.get("current_state") != 4:
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
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node or not soldier_scene:
		return
	for child in soldiers_node.get_children():
		var is_alive = child.get("current_state") != 4
		var is_player = child.get("team") == "player"
		if not is_alive:
			child.queue_free()
		elif not is_player:
			continue
	ship._sync_player_crew_roster()
	print("[Crew] 병사 보충 완료! (현재: %d/%d)" % [ship.max_crew_count, ship.max_crew_count])
