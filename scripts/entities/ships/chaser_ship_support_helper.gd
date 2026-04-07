extends RefCounted
class_name ChaserShipSupportHelper

const DERELICT_NONBLOCKING_DELAY: float = 1.25
const DERELICT_MIN_VISIBLE_LIFETIME: float = 4.0
const DERELICT_OFFSCREEN_DESPAWN_DISTANCE: float = 42.0
const DERELICT_HARD_DESPAWN_DISTANCE: float = 150.0
const ENEMY_FIRE_POT_BASE_COOLDOWN: float = 7.5
const ENEMY_FIRE_POT_MIN_RANGE: float = 7.0
const ENEMY_FIRE_POT_MAX_RANGE: float = 18.0
const ENEMY_FIRE_POT_DAMAGE: float = 11.0
const ENEMY_FIRE_POT_RADIUS: float = 2.6

static func update_enemy_fire_pot_logic(ship, delta: float) -> void:
	if ship.is_dying or ship.is_sinking or ship.is_derelict:
		return
	if ship.fire_pot_cooldown_timer > 0.0:
		ship.fire_pot_cooldown_timer = maxf(0.0, ship.fire_pot_cooldown_timer - delta)
	if ship.fire_pot_cooldown_timer > 0.0:
		return
	if not is_instance_valid(ship.fire_pot_scene):
		return
	var target: Node3D = ship.get("target")
	if not is_instance_valid(target):
		return
	if target.get("team") != "player":
		return
	if target.get("is_dying") or target.get("is_sinking"):
		return
	if ship.is_boarding:
		return
	var dist: float = ship.global_position.distance_to(target.global_position)
	if dist < ENEMY_FIRE_POT_MIN_RANGE or dist > ENEMY_FIRE_POT_MAX_RANGE:
		return
	var tosser = _find_fire_pot_tosser(ship)
	if not is_instance_valid(tosser):
		return

	var start_pos: Vector3 = tosser.global_position + Vector3(0.0, 1.0, 0.0)
	var target_pos: Vector3 = _get_fire_pot_target_pos(target)
	var pot = ship.ScenePool.acquire(ship.get_tree(), ship.fire_pot_scene)
	pot.damage = ENEMY_FIRE_POT_DAMAGE
	pot.explosion_radius = ENEMY_FIRE_POT_RADIUS
	pot.team = ship.team
	ship.get_tree().root.add_child.call_deferred(pot)
	pot.set_deferred("global_position", start_pos)
	pot.call_deferred("setup_flight", start_pos, target_pos, 0.95, 3.8)
	tosser.look_at(Vector3(target_pos.x, tosser.global_position.y, target_pos.z), Vector3.UP)
	ship.fire_pot_cooldown_timer = ENEMY_FIRE_POT_BASE_COOLDOWN + randf_range(-0.8, 1.0)


static func _find_fire_pot_tosser(ship):
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return null
	for child in soldiers_node.get_children():
		if child.get("current_state") == 4:
			continue
		if child.get("team") != ship.team:
			continue
		if str(child.get("crew_role", "")) == "fire_pot":
			return child
	return null


static func _get_fire_pot_target_pos(target_ship: Node3D) -> Vector3:
	var target_pos: Vector3 = target_ship.global_position + Vector3(0.0, 1.8, 0.0)
	var masts: Array = target_ship.get("masts")
	if masts != null and not masts.is_empty():
		for mast in masts:
			if is_instance_valid(mast):
				target_pos = mast.global_position + Vector3(randf_range(-0.4, 0.4), 1.6, randf_range(-0.4, 0.4))
				break
	target_pos.x += randf_range(-0.6, 0.6)
	target_pos.z += randf_range(-0.6, 0.6)
	return target_pos

static func become_derelict(ship) -> void:
	ship.is_derelict = true
	ship.set_meta("derelict_nonblocking", false)
	ship.set_meta("derelict_started_at", Time.get_ticks_msec() / 1000.0)

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

	ship.get_tree().create_timer(DERELICT_NONBLOCKING_DELAY).timeout.connect(func():
		if is_instance_valid(ship) and ship.is_derelict and not ship.is_sinking:
			ship.set_meta("derelict_nonblocking", true)
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
	if not ship.is_derelict or ship.is_sinking:
		return
	var players = ship.SceneGroupCache.get_nodes(ship.get_tree(), "player")
	if players.is_empty():
		return
	var p = players[0]

	var started_at: float = float(ship.get_meta("derelict_started_at", 0.0))
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - started_at < DERELICT_MIN_VISIBLE_LIFETIME:
		return

	var dist = ship.global_position.distance_to(p.global_position)
	if dist > DERELICT_HARD_DESPAWN_DISTANCE:
		print("[Ship] 폐선이 완전히 표류하여 사라집니다.")
		ship.queue_free()
		return

	var cam: Camera3D = ship.get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		return
	var viewport_rect: Rect2 = ship.get_viewport().get_visible_rect()
	if _is_world_position_offscreen(cam, viewport_rect, ship.global_position) and dist > DERELICT_OFFSCREEN_DESPAWN_DISTANCE:
		print("[Ship] 화면 밖 폐선이 정리됩니다.")
		ship.queue_free()


static func _is_world_position_offscreen(cam: Camera3D, viewport_rect: Rect2, world_pos: Vector3) -> bool:
	if cam.is_position_behind(world_pos):
		return true
	var screen_pos: Vector2 = cam.unproject_position(world_pos)
	return not viewport_rect.has_point(screen_pos)


static func drop_floating_loot(ship) -> void:
	if not ship.loot_scene:
		return
	if randf() > float(ship.floating_loot_drop_chance):
		return

	var loot = ship.ScenePool.acquire(ship.get_tree(), ship.loot_scene)
	var offset_x = randf_range(-1.2, 1.2)
	var offset_z = randf_range(-1.2, 1.2)
	var spawn_pos = Vector3(ship.global_position.x + offset_x, 0.5, ship.global_position.z + offset_z)

	ship.get_tree().root.add_child.call_deferred(loot)
	loot.set_deferred("global_position", spawn_pos)

	if ship.survivor_scene and randf() < 0.3:
		var survivor = ship.ScenePool.acquire(ship.get_tree(), ship.survivor_scene)
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

			var survivor = ship.ScenePool.acquire(ship.get_tree(), ship.survivor_scene)
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
