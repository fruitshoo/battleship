extends RefCounted

const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const WATER_BURST_SCENE = preload("res://scenes/effects/water_burst.tscn")

static func die(ship) -> void:
	if ship.is_sinking or ship.is_dying:
		return
	ship.is_dying = true
	ship.is_sinking = true
	ship.is_player_controlled = false
	ship.current_speed = 0.0
	ship.fire_pot_cooldown_timer = 9999.0
	if is_instance_valid(ship.boarding_target) and ship.boarding_target.has_method("get_boarding_attacker_ship") and ship.boarding_target.get_boarding_attacker_ship() == ship:
		ship.boarding_target.set("boarding_attacker", null)
	ship.boarding_attacker = null
	disable_combat_modules_on_sink(ship)

	print("[Critical] 배가 침몰합니다!")

	var sink_tween = ship.create_tween()
	sink_tween.set_parallel(true)
	var sink_duration = 6.0
	sink_tween.tween_property(ship, "position:y", ship.position.y - 12.0, sink_duration).set_ease(Tween.EASE_IN)
	sink_tween.tween_property(ship, "rotation:z", deg_to_rad(25.0), sink_duration).set_ease(Tween.EASE_IN)
	sink_tween.tween_property(ship, "rotation:x", deg_to_rad(15.0), sink_duration).set_ease(Tween.EASE_IN)

	fade_out_meshes(ship, ship, sink_tween, sink_duration)

	var splash = ScenePool.acquire(ship.get_tree(), WATER_BURST_SCENE)
	if splash.has_method("configure_as_sink"):
		splash.configure_as_sink()
	splash.position = Vector3(ship.global_position.x, 0.2, ship.global_position.z)
	ship.get_tree().root.add_child(splash)
	if splash.has_method("pool_activate"):
		splash.pool_activate()

	var audio_manager = ship.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_large", ship.global_position, randf_range(0.8, 1.0), 3.0)

	sink_tween.set_parallel(false)
	sink_tween.tween_callback(func():
		var hud = find_hud(ship)
		if hud and hud.has_method("show_game_over"):
			hud.show_game_over()
		if ship._cached_level_manager and "current_score" in ship._cached_level_manager:
			print("[GameOver] 침몰! 최종 점수: %d" % ship._cached_level_manager.current_score)
	)

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
