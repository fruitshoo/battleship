extends RefCounted
class_name ChaserShipSupportHelper

static func become_derelict(ship) -> void:
	ship.is_derelict = true
	ship.set_meta("derelict_nonblocking", false)

	if not is_instance_valid(ship.cached_lm):
		ship.cached_lm = ship.get_tree().root.find_child("LevelManager", true, false)
		if not ship.cached_lm:
			var lm_nodes = ship.SceneGroupCache.get_nodes(ship.get_tree(), "level_manager")
			if lm_nodes.size() > 0:
				ship.cached_lm = lm_nodes[0]

	if not ship._merit_granted:
		if is_instance_valid(ship.cached_lm) and ship.cached_lm.has_method("add_merit"):
			ship.cached_lm.add_merit(20)
			ship._merit_granted = true
	if is_instance_valid(ship.cached_lm) and ship.cached_lm.has_method("add_ship_derelict"):
		ship.cached_lm.add_ship_derelict(1)

	ship._set_wake_state(false)

	if ship.DEBUG_CHASER_LOGS:
		print("[Status] 선원 전멸! 적함이 폐선(Derelict) 상태가 되었습니다.")

	ship.leaking_rate += 1.5
	if ship.boarders_count > 0:
		ship.boarders_count = 0

	ship.base_collision_radius *= 0.55
	ship._sync_profile_from_runtime()
	ship._set_wake_state(false)

	var tilt_tween = ship.create_tween()
	tilt_tween.tween_property(ship, "rotation_degrees:z", 15.0, 1.5).set_ease(Tween.EASE_OUT)
	tilt_tween.set_parallel(true)
	tilt_tween.tween_property(ship, "position:y", ship.base_y - 1.0, 2.0)

	ship.get_tree().create_timer(1.25).timeout.connect(func():
		if is_instance_valid(ship) and ship.is_derelict and not ship.is_sinking:
			ship.set_meta("derelict_nonblocking", true)
	)

	ship.get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(ship) and not ship.is_sinking:
			sink_derelict(ship)
	)


static func sink_derelict(ship) -> void:
	if ship.is_sinking:
		return
	ship.is_sinking = true
	print("[Ship] 폐선 침몰 시작!")

	ship._set_fire_emitting(true)

	var sink_tween = ship.create_tween()
	sink_tween.tween_property(ship, "global_position:y", ship.base_y - 15.0, 5.0).set_ease(Tween.EASE_IN)
	sink_tween.parallel().tween_property(ship, "rotation_degrees:x", randf_range(-20.0, 20.0), 5.0)
	sink_tween.parallel().tween_property(ship, "rotation_degrees:z", randf_range(20.0, 40.0) * (1 if randf() > 0.5 else -1), 5.0)

	await sink_tween.finished
	ship.queue_free()


static func check_offscreen_despawn(ship) -> void:
	var players = ship.SceneGroupCache.get_nodes(ship.get_tree(), "player")
	if players.is_empty():
		return
	var p = players[0]

	var dist = ship.global_position.distance_to(p.global_position)
	if dist > 150.0:
		print("[Ship] 폐선이 완전히 표류하여 사라집니다.")
		ship.queue_free()


static func drop_floating_loot(ship) -> void:
	if not ship.loot_scene:
		return
	if randf() > float(ship.floating_loot_drop_chance):
		return

	var loot = ship.loot_scene.instantiate()
	var offset_x = randf_range(-1.2, 1.2)
	var offset_z = randf_range(-1.2, 1.2)
	var spawn_pos = Vector3(ship.global_position.x + offset_x, 0.5, ship.global_position.z + offset_z)

	ship.get_tree().root.add_child.call_deferred(loot)
	loot.set_deferred("global_position", spawn_pos)

	if ship.survivor_scene and randf() < 0.3:
		var survivor = ship.survivor_scene.instantiate()
		var s_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
		var survivor_pos = ship.global_position + s_offset
		ship.get_tree().root.add_child.call_deferred(survivor)
		survivor.set_deferred("global_position", survivor_pos)
		print("[Rescue] 구출 가능한 생존자가 발생했습니다!")


static func evacuate_player_soldiers_as_survivors(ship) -> void:
	if not ship.survivor_scene:
		return
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return

	var converted_count = 0
	for child in soldiers_node.get_children():
		if child.get("team") == "player" and child.get("current_state") != 4:
			var spawn_pos = child.global_position
			spawn_pos.y = 0.5

			var survivor = ship.survivor_scene.instantiate()
			ship.get_tree().root.add_child.call_deferred(survivor)
			survivor.set_deferred("global_position", spawn_pos)

			child.queue_free()
			converted_count += 1

	if converted_count > 0:
		print("[Critical] 아군 병사 %d명이 바다로 뛰어들었습니다!" % converted_count)


static func evacuate_soldiers_to_home(ship) -> void:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return

	var returned_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") == 4:
			continue

		var h_ship = child.get("home_ship")
		if is_instance_valid(h_ship) and h_ship != ship and not h_ship.get("is_sinking") and not h_ship.get("is_dying"):
			var target_soldiers = h_ship.get_node_or_null("Soldiers")
			if not target_soldiers:
				continue

			var start_pos = child.global_position
			child.call_deferred("reparent", target_soldiers)

			var jump_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.5, 1.5))
			var end_pos = h_ship.global_transform * jump_offset

			var tween = ship.create_tween()
			tween.set_parallel(true)
			tween.tween_property(child, "global_position:x", end_pos.x, 0.5).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(child, "global_position:z", end_pos.z, 0.5).set_trans(Tween.TRANS_LINEAR)

			var mid_y = max(start_pos.y, end_pos.y) + 2.0
			var y_tween = ship.create_tween()
			y_tween.tween_property(child, "global_position:y", mid_y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			y_tween.tween_property(child, "global_position:y", end_pos.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

			child.set("owned_ship", h_ship)
			if child.get("is_stationary"):
				child.set("is_stationary", false)
			returned_count += 1
			print("[Evacuation] 병사가 원래 배(%s)로 복귀합니다!" % h_ship.name)

	if returned_count > 0:
		print("[Evacuation] 총 %d명의 병사가 원래 배로 복귀했습니다." % returned_count)


static func update_enemy_reinforcement(ship, delta: float) -> void:
	var alive_count = ship.get_alive_crew_count()
	if alive_count < ship.max_crew:
		ship.enemy_respawn_timer += delta
		if ship.enemy_respawn_timer >= ship.enemy_respawn_interval:
			ship.enemy_respawn_timer = 0.0
			ship._spawn_one_soldier("enemy")
			print("[Reinforcement] 적 함선에 병사가 보충되었습니다. (현재: %d)" % (alive_count + 1))
