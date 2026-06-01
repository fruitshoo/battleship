extends RefCounted

const WATER_BLAST_SCENE = preload("res://scenes/effects/water_blast.tscn")
const CAPTAIN_DEATH_PREVIEW_META := "captain_death_preview_started"
const CAPTAIN_DEATH_HITSTOP_SCALE := 0.06
const CAPTAIN_DEATH_HITSTOP_DURATION := 0.1
const CAPTAIN_DEATH_SLOW_SCALE := 0.22
const CAPTAIN_DEATH_SLOW_DURATION := 1.85
const CAPTAIN_DEATH_GAME_OVER_DELAY := 1.95

static func die(ship) -> void:
	if ship.is_sinking or ship.is_dying:
		return
	BaseShipStatusHelper.clear_fire_effect(ship)
	ship.is_dying = true
	ship.is_sinking = true
	ship.is_player_controlled = false
	ship.current_speed = 0.0
	ship.fire_pot_cooldown_timer = 9999.0
	if is_instance_valid(ship.boarding_target) and ship.boarding_target.has_method("get_boarding_attacker_ship") and ship.boarding_target.get_boarding_attacker_ship() == ship:
		ship.boarding_target.clear_boarding_attacker_ship()
	ship.clear_boarding_attacker_ship()
	disable_combat_modules_on_sink(ship)

	print("[Critical] 배가 침몰합니다!")

	var sink_tween = ship.create_tween()
	sink_tween.set_parallel(true)
	var sink_duration = 6.0
	sink_tween.tween_property(ship, "position:y", ship.position.y - 12.0, sink_duration).set_ease(Tween.EASE_IN)
	sink_tween.tween_property(ship, "rotation:z", deg_to_rad(25.0), sink_duration).set_ease(Tween.EASE_IN)
	sink_tween.tween_property(ship, "rotation:x", deg_to_rad(15.0), sink_duration).set_ease(Tween.EASE_IN)

	fade_out_meshes(ship, ship, sink_tween, sink_duration)

	var splash = ScenePool.acquire(ship.get_tree(), WATER_BLAST_SCENE)
	if splash.has_method("configure_as_sink"):
		splash.configure_as_sink()
	splash.position = Vector3(ship.global_position.x, 0.2, ship.global_position.z)
	ship.get_tree().root.add_child(splash)
	if splash.has_method("pool_activate"):
		splash.pool_activate()

	var audio_manager = ship.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_large", ship.global_position, randf_range(0.8, 1.0), 3.0)
	if ship.has_method("play_sink_bubbles"):
		ship.play_sink_bubbles(0.35, -1.5)

	sink_tween.set_parallel(false)
	var ship_id: int = ship.get_instance_id()
	sink_tween.tween_callback(func():
		var player_ship := NodeContractHelper.get_instance_node(ship_id)
		if not is_instance_valid(player_ship):
			return
		var hud = find_hud(player_ship)
		if hud and hud.has_method("show_game_over"):
			hud.show_game_over()
		if player_ship._cached_level_manager and "current_score" in player_ship._cached_level_manager:
			print("[GameOver] 침몰! 최종 점수: %d" % player_ship._cached_level_manager.current_score)
	)

static func trigger_boarding_overrun_game_over(ship) -> void:
	if ship.is_sinking or ship.is_dying:
		return
	BaseShipStatusHelper.clear_fire_effect(ship)
	ship.is_dying = true
	ship.is_sinking = true
	ship.is_player_controlled = false
	ship.current_speed = 0.0
	ship.fire_pot_cooldown_timer = 9999.0
	if is_instance_valid(ship.boarding_target) and ship.boarding_target.has_method("get_boarding_attacker_ship") and ship.boarding_target.get_boarding_attacker_ship() == ship:
		ship.boarding_target.clear_boarding_attacker_ship()
	ship.clear_boarding_attacker_ship()
	disable_combat_modules_on_sink(ship)

	var hud = find_hud(ship)
	if hud and hud.has_method("show_game_over"):
		hud.show_game_over()
	if ship._cached_level_manager and "current_score" in ship._cached_level_manager:
		print("[GameOver] 갑판 장악! 최종 점수: %d" % ship._cached_level_manager.current_score)

static func preview_captain_death_moment(ship, death_position: Vector3) -> void:
	if not is_instance_valid(ship):
		return
	if ship.get_meta(CAPTAIN_DEATH_PREVIEW_META, false) == true:
		return
	ship.set_meta(CAPTAIN_DEATH_PREVIEW_META, true)
	_play_captain_death_focus(ship, death_position)
	_start_captain_death_hitstop_then_slowdown(ship)

static func trigger_captain_death_game_over(ship, death_position: Vector3) -> void:
	if ship.is_sinking or ship.is_dying:
		return
	BaseShipStatusHelper.clear_fire_effect(ship)
	ship.is_dying = true
	ship.is_sinking = true
	ship.is_player_controlled = false
	ship.current_speed = 0.0
	ship.fire_pot_cooldown_timer = 9999.0
	if is_instance_valid(ship.boarding_target) and ship.boarding_target.has_method("get_boarding_attacker_ship") and ship.boarding_target.get_boarding_attacker_ship() == ship:
		ship.boarding_target.clear_boarding_attacker_ship()
	ship.clear_boarding_attacker_ship()
	disable_combat_modules_on_sink(ship)
	preview_captain_death_moment(ship, death_position)

	var hud = find_hud(ship)
	var tree: SceneTree = ship.get_tree()
	if not is_instance_valid(tree) or DisplayServer.get_name() == "headless":
		if hud and hud.has_method("show_game_over"):
			hud.show_game_over()
	else:
		tree.create_timer(CAPTAIN_DEATH_GAME_OVER_DELAY, true, false, true).timeout.connect(func():
			if is_instance_valid(hud) and hud.has_method("show_game_over"):
				hud.show_game_over()
		)
	if ship._cached_level_manager and "current_score" in ship._cached_level_manager:
		print("[GameOver] 장군 사망! 최종 점수: %d" % ship._cached_level_manager.current_score)

static func _play_captain_death_focus(ship, death_position: Vector3) -> void:
	var viewport: Viewport = ship.get_viewport()
	if not is_instance_valid(viewport):
		return
	var camera := viewport.get_camera_3d()
	if is_instance_valid(camera) and camera.has_method("play_captain_death_focus"):
		camera.call("play_captain_death_focus", death_position)

static func _start_captain_death_hitstop_then_slowdown(ship) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var previous_time_scale: float = Engine.time_scale
	if previous_time_scale <= CAPTAIN_DEATH_HITSTOP_SCALE + 0.01:
		return
	Engine.time_scale = CAPTAIN_DEATH_HITSTOP_SCALE
	var tree: SceneTree = ship.get_tree()
	if not is_instance_valid(tree):
		Engine.time_scale = previous_time_scale
		return
	tree.create_timer(CAPTAIN_DEATH_HITSTOP_DURATION, true, false, true).timeout.connect(func() -> void:
		if Engine.time_scale <= CAPTAIN_DEATH_HITSTOP_SCALE + 0.01:
			Engine.time_scale = CAPTAIN_DEATH_SLOW_SCALE
		_schedule_captain_death_time_restore(tree, previous_time_scale)
	, CONNECT_ONE_SHOT)

static func _start_captain_death_slowdown(ship) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var previous_time_scale: float = Engine.time_scale
	if previous_time_scale <= CAPTAIN_DEATH_SLOW_SCALE + 0.01:
		return
	Engine.time_scale = CAPTAIN_DEATH_SLOW_SCALE
	var tree: SceneTree = ship.get_tree()
	if not is_instance_valid(tree):
		Engine.time_scale = previous_time_scale
		return
	_schedule_captain_death_time_restore(tree, previous_time_scale)

static func _schedule_captain_death_time_restore(tree: SceneTree, previous_time_scale: float) -> void:
	if not is_instance_valid(tree):
		return
	var restore_time_scale := func() -> void:
		if Engine.time_scale <= CAPTAIN_DEATH_SLOW_SCALE + 0.01:
			Engine.time_scale = previous_time_scale
	tree.create_timer(CAPTAIN_DEATH_SLOW_DURATION, true, false, true).timeout.connect(restore_time_scale, CONNECT_ONE_SHOT)

static func disable_combat_modules_on_sink(ship) -> void:
	for child in ship.get_children():
		disable_combat_subtree(ship, child)

static func disable_combat_subtree(ship, node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
	if node is AudioStreamPlayer3D:
		var audio_player := node as AudioStreamPlayer3D
		audio_player.stop()
	if node is Area3D:
		var area := node as Area3D
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
	if node is CollisionShape3D:
		var collision_shape := node as CollisionShape3D
		collision_shape.set_deferred("disabled", true)
	if "is_preparing" in node:
		node.is_preparing = false
	if "current_target" in node:
		node.current_target = null
	for child in node.get_children():
		disable_combat_subtree(ship, child)

static func fade_out_meshes(ship, node: Node, tween: Tween, duration: float) -> void:
	if node is MeshInstance3D:
		tween.parallel().tween_property(node, "transparency", 1.0, duration).set_ease(Tween.EASE_IN)
	for child in node.get_children():
		fade_out_meshes(ship, child, tween, duration)

static func find_hud(ship) -> Node:
	if ship._cached_hud:
		return ship._cached_hud
	if ship._cached_level_manager and ship._cached_level_manager.get("hud"):
		return ship._cached_level_manager.hud
	return null
