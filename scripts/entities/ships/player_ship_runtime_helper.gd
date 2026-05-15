extends RefCounted

const SOLDIER_SCENE = preload("res://scenes/entities/soldiers/soldier.tscn")
const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SUPPORT_JOINING_META := "support_joining"
const SUPPORT_ASSIST_TARGET_ID_META := "support_assist_target_id"
const SUPPORT_ASSIST_LOCK_TIMER_META := "support_assist_lock_timer"
const SUPPORT_ASSIST_EVAL_TIMER_META := "support_assist_eval_timer"
const SUPPORT_ASSIST_LANE_SIDE_META := "support_assist_lane_side"
const SUPPORT_JOIN_STAGE_META := "support_join_stage"
const CONTROL_SCHEME_SCREEN := "screen"
const SCREEN_STEER_FULL_ANGLE_DEG := 95.0
const SCREEN_STEER_SOFT_ZONE_DEG := 16.0
const SCREEN_STEER_SPEED_DAMPING := 0.035
const SCREEN_INPUT_DEADZONE := 0.08
const RAM_BOOST_TRIGGER_THRESHOLD := 0.45
const ROPE_RESIST_STICK_THRESHOLD := 0.62
const ROPE_RESIST_STICK_NEUTRAL := 0.28

static func handle_input(ship, delta: float) -> void:
	if Input.is_action_just_pressed("toggle_sail_furl") and ship.has_method("toggle_sail_furl"):
		ship.toggle_sail_furl()
	if _is_ramming_boost_just_pressed(ship) and ship.has_method("try_activate_ramming_boost"):
		ship.try_activate_ramming_boost()
	var rope_resist_direction := _get_rope_resist_input_direction(ship)
	if rope_resist_direction != 0 and ship.has_method("try_resist_incoming_boarding_rope"):
		ship.try_resist_incoming_boarding_rope(rope_resist_direction)

	var sail_turn_speed: float = float(ship.sail_turn_speed)
	if Input.is_action_pressed("sail_left"):
		ship.adjust_sail_angle(-sail_turn_speed * delta)
	if Input.is_action_pressed("sail_right"):
		ship.adjust_sail_angle(sail_turn_speed * delta)

	if _is_screen_relative_control_enabled():
		_handle_screen_relative_navigation(ship, delta)
	else:
		_handle_ship_relative_navigation(ship, delta)


static func _is_ramming_boost_just_pressed(ship) -> bool:
	var pressed := InputMap.has_action("ram_boost") and Input.is_action_pressed("ram_boost")
	pressed = pressed or Input.is_key_pressed(KEY_SHIFT)
	for device in Input.get_connected_joypads():
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) >= RAM_BOOST_TRIGGER_THRESHOLD:
			pressed = true
			break
	var was_pressed := bool(ship.get("ramming_boost_input_was_pressed")) if ship.get("ramming_boost_input_was_pressed") != null else false
	ship.set("ramming_boost_input_was_pressed", pressed)
	return pressed and not was_pressed


static func _get_rope_resist_input_direction(ship) -> int:
	var left_pressed := Input.is_action_just_pressed("ship_left")
	var right_pressed := Input.is_action_just_pressed("ship_right")
	if left_pressed != right_pressed:
		var digital_direction := -1 if left_pressed else 1
		_set_rope_resist_stick_latch(ship, digital_direction)
		return digital_direction

	var axis := Input.get_action_strength("ship_right") - Input.get_action_strength("ship_left")
	var latched_direction := _get_rope_resist_stick_latch(ship)
	if absf(axis) <= ROPE_RESIST_STICK_NEUTRAL:
		_set_rope_resist_stick_latch(ship, 0)
		return 0
	if axis <= -ROPE_RESIST_STICK_THRESHOLD and latched_direction != -1:
		_set_rope_resist_stick_latch(ship, -1)
		return -1
	if axis >= ROPE_RESIST_STICK_THRESHOLD and latched_direction != 1:
		_set_rope_resist_stick_latch(ship, 1)
		return 1
	return 0


static func _get_rope_resist_stick_latch(ship) -> int:
	if is_instance_valid(ship) and ship.get("boarding_rope_resist_stick_latch_direction") != null:
		return int(ship.get("boarding_rope_resist_stick_latch_direction"))
	return 0


static func _set_rope_resist_stick_latch(ship, direction: int) -> void:
	if is_instance_valid(ship) and ship.get("boarding_rope_resist_stick_latch_direction") != null:
		ship.set("boarding_rope_resist_stick_latch_direction", direction)


static func _handle_ship_relative_navigation(ship, delta: float) -> void:
	var steer_input = 0.0
	if Input.is_action_pressed("ship_left"):
		steer_input = -1.0
	elif Input.is_action_pressed("ship_right"):
		steer_input = 1.0
	ship.steer(steer_input, delta)

	if Input.is_action_pressed("row_forward"):
		ship.set_rowing(true, 1)
	elif Input.is_action_pressed("row_backward"):
		ship.set_rowing(true, -1)
	else:
		if ship.is_rowing:
			ship.set_rowing(false)


static func _handle_screen_relative_navigation(ship, delta: float) -> void:
	var input_vec := Vector2(
		Input.get_action_strength("ship_right") - Input.get_action_strength("ship_left"),
		Input.get_action_strength("row_forward") - Input.get_action_strength("row_backward")
	)
	if input_vec.length() <= SCREEN_INPUT_DEADZONE:
		ship.steer(0.0, delta)
		if ship.is_rowing:
			ship.set_rowing(false)
		return
	input_vec = input_vec.normalized()
	var desired_dir := _get_screen_relative_world_direction(ship, input_vec)
	if desired_dir.length_squared() <= 0.001:
		_handle_ship_relative_navigation(ship, delta)
		return
	var ship_forward := Vector2(-sin(ship.rotation.y), -cos(ship.rotation.y)).normalized()
	var desired_2d := Vector2(desired_dir.x, desired_dir.z).normalized()
	var signed_angle := ship_forward.angle_to(desired_2d)
	var angle_deg := rad_to_deg(signed_angle)
	var steer_input := _calculate_screen_relative_steer(ship, angle_deg)
	ship.steer(steer_input, delta)
	ship.set_rowing(true, 1)


static func _get_screen_relative_world_direction(ship, input_vec: Vector2) -> Vector3:
	var camera: Camera3D = null
	var viewport: Viewport = ship.get_viewport() if is_instance_valid(ship) else null
	if viewport != null:
		camera = viewport.get_camera_3d()
	if not is_instance_valid(camera):
		return Vector3.ZERO
	var camera_forward := camera.global_transform.basis.y
	var camera_right := camera.global_transform.basis.x
	camera_forward.y = 0.0
	camera_right.y = 0.0
	if camera_forward.length_squared() <= 0.001:
		camera_forward = -camera.global_transform.basis.z
		camera_forward.y = 0.0
	if camera_forward.length_squared() <= 0.001 or camera_right.length_squared() <= 0.001:
		return Vector3.ZERO
	return (camera_right.normalized() * input_vec.x + camera_forward.normalized() * input_vec.y).normalized()


static func _is_screen_relative_control_enabled() -> bool:
	if not is_instance_valid(SaveManager):
		return false
	return str(SaveManager.get_setting("control_scheme", "ship")) == CONTROL_SCHEME_SCREEN


static func _calculate_screen_relative_steer(ship, angle_deg: float) -> float:
	var abs_angle := absf(angle_deg)
	if abs_angle <= 0.5:
		return 0.0
	var steer := clampf(angle_deg / SCREEN_STEER_FULL_ANGLE_DEG, -1.0, 1.0)
	var soft_ratio := smoothstep(0.0, SCREEN_STEER_SOFT_ZONE_DEG, abs_angle)
	var speed_ratio := clampf(absf(float(ship.current_speed)) / maxf(float(ship.max_speed), 0.1), 0.0, 1.4)
	var damping := clampf(1.0 - speed_ratio * SCREEN_STEER_SPEED_DAMPING, 0.78, 1.0)
	return steer * soft_ratio * damping


static func toggle_fleet_formation(ship) -> void:
	var hold_enabled := not SupportFleetStateHelper.is_flagship_hold_enabled(ship)
	SupportFleetStateHelper.set_flagship_hold_enabled(ship, hold_enabled)
	if hold_enabled:
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("지원함: 진형 유지 (%s)" % _get_fleet_formation_label(ship), 2.0)
	else:
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("지원함: 자유 교전", 2.0)

static func cycle_fleet_formation(ship) -> void:
	var current_formation := _get_normalized_fleet_formation(ship)
	var next_formation: int = SupportFleetStateHelper.FORMATION_WING \
		if current_formation == SupportFleetStateHelper.FORMATION_COLUMN \
		else SupportFleetStateHelper.FORMATION_COLUMN
	SupportFleetStateHelper.set_flagship_formation(ship, next_formation)
	if ship.has_method("_get_support_fleet_ships"):
		var support_ships: Array = ship.call("_get_support_fleet_ships")
		for support_ship in support_ships:
			if not is_instance_valid(support_ship):
				continue
			if support_ship.get("is_boarding") == true:
				continue
			support_ship.set_meta(SUPPORT_JOINING_META, true)
			support_ship.set_meta(SUPPORT_JOIN_STAGE_META, 0)
			for meta_name in [
				SUPPORT_ASSIST_TARGET_ID_META,
				SUPPORT_ASSIST_LOCK_TIMER_META,
				SUPPORT_ASSIST_EVAL_TIMER_META,
				SUPPORT_ASSIST_LANE_SIDE_META,
			]:
				if support_ship.has_meta(meta_name):
					support_ship.remove_meta(meta_name)
	if ship._cached_hud and ship._cached_hud.has_method("show_message"):
		var suffix := "" if SupportFleetStateHelper.is_flagship_hold_enabled(ship) else " (자유 교전 중)"
		ship._cached_hud.show_message("지원함 진형: %s%s" % [_get_fleet_formation_label(ship), suffix], 2.0)

static func _get_fleet_formation_label(ship) -> String:
	match _get_normalized_fleet_formation(ship):
		SupportFleetStateHelper.FORMATION_WING:
			return "호위진"
		_:
			return "장사진"

static func _get_normalized_fleet_formation(ship) -> int:
	return SupportFleetStateHelper.get_flagship_formation(ship)

static func update_rowing_audio(ship, delta: float) -> void:
	if ship.is_rowing:
		if ship._oars_timer <= 0:
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_sfx"):
				var pitch := randf_range(0.95, 1.05)
				ship._cached_audio_manager.play_sfx("oars_rowing", ship.global_position, pitch, 5.0)
			ship._oars_timer = 1.3
		else:
			ship._oars_timer -= delta

		if ship._gilgunak_playing:
			ship._gilgunak_playing = false
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_gilgunak"):
				ship._cached_audio_manager.play_gilgunak(false)
	else:
		ship._oars_timer = 0.0
		if ship._gilgunak_playing:
			ship._gilgunak_playing = false
			if is_instance_valid(ship._cached_audio_manager) and ship._cached_audio_manager.has_method("play_gilgunak"):
				ship._cached_audio_manager.play_gilgunak(false)


static func update_sail_wind_audio(ship, delta: float) -> void:
	if not is_instance_valid(ship._cached_audio_manager) or not ship._cached_audio_manager.has_method("play_sfx"):
		ship._last_audio_wind_intake = float(ship._current_wind_intake)
		ship._last_audio_speed = float(ship.current_speed)
		return

	ship._sail_catch_audio_timer = maxf(0.0, ship._sail_catch_audio_timer - delta)
	ship._sail_luff_audio_timer = maxf(0.0, ship._sail_luff_audio_timer - delta)
	ship._speed_shift_audio_timer = maxf(0.0, ship._speed_shift_audio_timer - delta)

	var deployed: float = clampf(float(ship.sail_deployed_ratio), 0.0, 1.0)
	var wind_intake: float = clampf(float(ship._current_wind_intake), 0.0, 1.0)
	var previous_intake: float = clampf(float(ship._last_audio_wind_intake), 0.0, 1.0)
	var current_speed: float = absf(float(ship.current_speed))
	var previous_speed: float = absf(float(ship._last_audio_speed))
	var max_speed_value: float = maxf(float(ship.max_speed), 0.1)
	var speed_ratio: float = clampf(current_speed / max_speed_value, 0.0, 1.0)
	var speed_delta_rate: float = (current_speed - previous_speed) / maxf(delta, 0.001)

	if deployed > 0.22 and wind_intake >= 0.56 and previous_intake < 0.38 and ship._sail_catch_audio_timer <= 0.0:
		var catch_pitch := randf_range(0.86, 0.98)
		var catch_volume := lerpf(-2.5, 2.0, wind_intake)
		ship._cached_audio_manager.play_sfx("sail_flap", ship.global_position, catch_pitch, catch_volume)
		if randf() < 0.42:
			ship._cached_audio_manager.play_sfx("mast_creak", ship.global_position, randf_range(0.78, 0.92), 0.0)
		ship._sail_catch_audio_timer = randf_range(1.4, 2.2)
		ship._sail_luff_audio_timer = maxf(ship._sail_luff_audio_timer, 0.85)

	var luffing := deployed > 0.48 and wind_intake < 0.24 and current_speed > 0.45
	if luffing and ship._sail_luff_audio_timer <= 0.0:
		var luff_pitch := randf_range(1.08, 1.23)
		ship._cached_audio_manager.play_sfx("sail_flap", ship.global_position, luff_pitch, -4.5)
		ship._sail_luff_audio_timer = randf_range(2.0, 3.4)

	if ship._speed_shift_audio_timer <= 0.0 and current_speed > 0.8:
		if speed_delta_rate > 0.75:
			ship._cached_audio_manager.play_sfx("wave_splash", ship.global_position, randf_range(1.04, 1.18), lerpf(-4.5, -1.0, speed_ratio))
			ship._speed_shift_audio_timer = randf_range(1.1, 1.7)
		elif speed_delta_rate < -0.9:
			ship._cached_audio_manager.play_sfx("wave_splash", ship.global_position, randf_range(0.78, 0.94), lerpf(-5.5, -2.0, speed_ratio))
			ship._speed_shift_audio_timer = randf_range(1.2, 1.9)

	ship._last_audio_wind_intake = wind_intake
	ship._last_audio_speed = current_speed

static func capture_derelict_ship(ship) -> void:
	print("[Capture] 폐선 나포 성공! 보상을 획득합니다.")
	if is_instance_valid(ship._cached_level_manager):
		var score_reward: int = max(0, int(ship._cached_level_manager.get("boarding_capture_score_reward")))
		var xp_reward: int = max(0, int(ship._cached_level_manager.get("boarding_capture_xp_reward")))
		var bonus_xp_reward: int = max(0, int(ship._cached_level_manager.get("boarding_capture_bonus_xp_reward")))
		if score_reward > 0 and ship._cached_level_manager.has_method("add_score"):
			ship._cached_level_manager.add_score(score_reward)
		if xp_reward > 0 and ship._cached_level_manager.has_method("add_xp"):
			ship._cached_level_manager.add_xp(xp_reward)
		if bonus_xp_reward > 0 and ship._cached_level_manager.has_method("add_bonus_xp"):
			ship._cached_level_manager.add_bonus_xp(bonus_xp_reward)
		if ship._cached_hud and ship._cached_hud.has_method("show_message"):
			ship._cached_hud.show_message("나포 성공! XP +%d" % [xp_reward + bonus_xp_reward], 2.4)

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
