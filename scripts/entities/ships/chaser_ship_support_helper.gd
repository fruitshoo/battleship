extends RefCounted
class_name ChaserShipSupportHelper

const DEFAULT_ENEMY_DRIFTER_XP_SCENE = preload("res://scenes/effects/enemy_drifter_xp.tscn")
const DERELICT_NONBLOCKING_DELAY: float = 1.25
const DERELICT_MIN_VISIBLE_LIFETIME: float = 4.0
const DERELICT_OFFSCREEN_DESPAWN_DISTANCE: float = 42.0
const DERELICT_HARD_DESPAWN_DISTANCE: float = 150.0
const DERELICT_SETTLE_Y_OFFSET: float = -0.28
const DERELICT_MIN_ROLL_DEGREES: float = 2.5
const DERELICT_MAX_ROLL_DEGREES: float = 6.5
const DERELICT_MAX_PITCH_DEGREES: float = 2.0
const DERELICT_SAIL_COLOR := Color(0.52, 0.50, 0.45, 1.0)
const DERELICT_SAIL_DAMAGE_MIN: float = 0.16
const DERELICT_SAIL_DAMAGE_MAX: float = 0.30
const ENEMY_FIRE_POT_BASE_COOLDOWN: float = 7.5
const ENEMY_FIRE_POT_MIN_RANGE: float = 7.0
const ENEMY_FIRE_POT_MAX_RANGE: float = 18.0
const ENEMY_FIRE_POT_DAMAGE: float = 11.0
const ENEMY_FIRE_POT_RADIUS: float = 2.6
const LIMBO_AI_SPECIAL_ATTACK_INTENT_STALE_FRAMES := 4
const ENEMY_DRIFTER_XP_ACCOUNTED_META := "enemy_drifter_xp_accounted"
const ENEMY_SINKING_REWARD_ACCOUNTED_META := "enemy_sinking_reward_accounted"
const ENEMY_DRIFTER_SOLDIERS_PER_PICKUP := 3
const ENEMY_DRIFTER_MAX_PICKUPS := 4

static func update_enemy_fire_pot_logic(ship, delta: float) -> void:
	if ship.is_dying or ship.is_sinking or ship.is_derelict:
		return
	if ship.fire_pot_cooldown_timer > 0.0:
		ship.fire_pot_cooldown_timer = maxf(0.0, ship.fire_pot_cooldown_timer - delta)
	if ship.fire_pot_cooldown_timer > 0.0:
		return
	if not is_instance_valid(ship.fire_pot_scene):
		return
	var raw_target = ship.get_target_ship() if ship.has_method("get_target_ship") else ship.get("target")
	if not is_instance_valid(raw_target):
		if "target" in ship:
			ship.target = null
		return
	var target: Node3D = raw_target as Node3D
	if not is_instance_valid(target):
		if "target" in ship:
			ship.target = null
		return
	if not _is_player_ship(target):
		return
	if target.has_method("is_sinking_or_dying") and target.is_sinking_or_dying():
		return
	if ship.is_boarding:
		return
	if ship.get("limbo_ai_pilot_enabled") == true:
		var special_frame := int(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, -1000000))
		if Engine.get_physics_frames() - special_frame <= LIMBO_AI_SPECIAL_ATTACK_INTENT_STALE_FRAMES:
			var special_target_id := int(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_TARGET_ID, 0))
			var special_intent := str(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT, "")).strip_edges()
			if special_target_id != target.get_instance_id():
				return
			if not special_intent.is_empty() and special_intent != ShipAILimboKeys.SPECIAL_FIRE_POT_READY:
				return
	var dist: float = ship.global_position.distance_to(target.global_position)
	if dist < ENEMY_FIRE_POT_MIN_RANGE or dist > ENEMY_FIRE_POT_MAX_RANGE:
		return
	var tosser = _find_fire_pot_tosser(ship)
	if not is_instance_valid(tosser):
		return

	var start_pos: Vector3 = tosser.global_position + Vector3(0.0, 1.0, 0.0)
	var target_pos: Vector3 = _get_fire_pot_target_pos(target)
	var pot = ScenePool.acquire(ship.get_tree(), ship.fire_pot_scene)
	pot.damage = ENEMY_FIRE_POT_DAMAGE
	pot.explosion_radius = ENEMY_FIRE_POT_RADIUS
	pot.team = ship.team
	ship.get_tree().root.add_child.call_deferred(pot)
	pot.set_deferred("global_position", start_pos)
	pot.call_deferred("setup_flight", start_pos, target_pos, 0.95, 3.8)
	tosser.look_at(Vector3(target_pos.x, tosser.global_position.y, target_pos.z), Vector3.UP)
	ship.fire_pot_cooldown_timer = ENEMY_FIRE_POT_BASE_COOLDOWN + randf_range(-0.8, 1.0)


static func _find_fire_pot_tosser(ship):
	for child in EntityRegistry.get_soldiers_by_ship(ship):
		if SoldierStateHelper.is_dead_soldier(child):
			continue
		if child.has_method("get_team_tag") and child.get_team_tag() != ship.team:
			continue
		if child.has_method("get_crew_role_value") and child.get_crew_role_value() == "fire_pot":
			return child
	return null


static func _is_player_ship(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_player_team"):
		return node.is_player_team()
	if node.has_method("get_team_tag"):
		return node.get_team_tag() == "player"
	return false


static func _get_fire_pot_target_pos(target_ship: Node3D) -> Vector3:
	var target_pos: Vector3 = NodeContractHelper.get_projectile_aim_point(target_ship, 0.8)
	var masts_variant: Variant = target_ship.get("masts")
	if masts_variant is Array:
		var masts: Array = masts_variant as Array
		for mast in masts:
			if is_instance_valid(mast):
				target_pos = mast.global_position + Vector3(randf_range(-0.4, 0.4), 1.6, randf_range(-0.4, 0.4))
				break
	target_pos.x += randf_range(-0.6, 0.6)
	target_pos.z += randf_range(-0.6, 0.6)
	return target_pos


static func spawn_enemy_drifter_xp_pickups(ship) -> int:
	if not is_instance_valid(ship) or not ship.is_inside_tree():
		return 0
	if ship.get_meta(ENEMY_DRIFTER_XP_ACCOUNTED_META, false) == true:
		return 0
	ship.set_meta(ENEMY_DRIFTER_XP_ACCOUNTED_META, true)
	if str(ship.get("team")) != "enemy":
		return 0

	var soldiers_node: Node = NodeContractHelper.get_soldiers_container(ship)
	if not is_instance_valid(soldiers_node):
		return 0

	var sinking_soldiers: Array[Node3D] = []
	for child in soldiers_node.get_children():
		var soldier := child as Node3D
		if not is_instance_valid(soldier):
			continue
		if SoldierStateHelper.is_dead_soldier(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != "enemy":
			continue
		var home_ship_variant: Variant = soldier.get("home_ship")
		if is_instance_valid(home_ship_variant) and home_ship_variant != ship:
			continue
		sinking_soldiers.append(soldier)

	var soldier_count: int = sinking_soldiers.size()
	if soldier_count <= 0:
		return 0

	var lm: Node = ship.get("cached_lm") if ship.get("cached_lm") != null else LevelManagerRegistry.get_level_manager(ship.get_tree())
	var xp_per_soldier: int = 3
	var merit_per_soldier: int = 0
	if is_instance_valid(lm):
		xp_per_soldier = max(0, int(lm.get("drowned_soldier_kill_xp_reward")))
		merit_per_soldier = max(0, int(lm.get("drowned_soldier_kill_merit_reward")))
		if lm.has_method("add_soldier_kill"):
			lm.add_soldier_kill(soldier_count, "drowned")
		if merit_per_soldier > 0 and lm.has_method("add_merit"):
			lm.add_merit(merit_per_soldier * soldier_count)

	for soldier in sinking_soldiers:
		soldier.set_meta(ENEMY_SINKING_REWARD_ACCOUNTED_META, true)
		soldier.set_meta("last_death_cause", "drowned")
		soldier.set_meta("last_damage_source", "drowned")

	if xp_per_soldier <= 0:
		return 0

	var pickup_count: int = mini(ENEMY_DRIFTER_MAX_PICKUPS, ceili(float(soldier_count) / float(ENEMY_DRIFTER_SOLDIERS_PER_PICKUP)))
	var remaining_soldiers: int = soldier_count
	var spawned_count: int = 0
	for index in range(pickup_count):
		var remaining_pickups := pickup_count - index
		var soldiers_in_pickup: int = ceili(float(remaining_soldiers) / float(remaining_pickups))
		remaining_soldiers -= soldiers_in_pickup
		var xp_amount: int = xp_per_soldier * soldiers_in_pickup
		if xp_amount <= 0:
			continue
		var pickup := _instantiate_enemy_drifter_pickup(ship)
		if not is_instance_valid(pickup):
			continue
		if pickup.has_method("configure"):
			pickup.call("configure", xp_amount, soldiers_in_pickup)
		var angle: float = randf_range(0.0, TAU)
		var radius: float = randf_range(0.8, 2.4 + float(index) * 0.35)
		var spawn_pos: Vector3 = Vector3(
			ship.global_position.x + cos(angle) * radius,
			0.0,
			ship.global_position.z + sin(angle) * radius
		)
		ship.get_tree().root.add_child.call_deferred(pickup)
		pickup.set_deferred("global_position", spawn_pos)
		spawned_count += 1
	return spawned_count


static func _instantiate_enemy_drifter_pickup(ship) -> Node:
	var scene: PackedScene = null
	if "enemy_drifter_xp_scene" in ship:
		var scene_variant: Variant = ship.get("enemy_drifter_xp_scene")
		if scene_variant is PackedScene:
			scene = scene_variant as PackedScene
	if not is_instance_valid(scene):
		scene = DEFAULT_ENEMY_DRIFTER_XP_SCENE
	return ScenePool.acquire(ship.get_tree(), scene)

static func become_derelict(ship) -> void:
	ship.is_derelict = true
	ship.set_meta("derelict_nonblocking", false)
	ship.set_meta("derelict_started_at", Time.get_ticks_msec() / 1000.0)

	if not is_instance_valid(ship.cached_lm):
		ship.cached_lm = LevelManagerRegistry.get_level_manager(ship.get_tree())

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

	ship.base_collision_radius *= 0.55
	ship._sync_profile_from_runtime()
	ship._set_wake_state(false)

	_weather_derelict_sails(ship)
	_play_derelict_transition_visuals(ship)
	_set_derelict_settle_pose(ship)

	var ship_id: int = ship.get_instance_id()
	ship.get_tree().create_timer(DERELICT_NONBLOCKING_DELAY).timeout.connect(func():
		var derelict_ship = instance_from_id(ship_id)
		if is_instance_valid(derelict_ship) and derelict_ship.is_derelict and not derelict_ship.is_sinking:
			derelict_ship.set_meta("derelict_nonblocking", true)
	)


static func _weather_derelict_sails(ship) -> void:
	var masts_variant: Variant = ship.get("masts") if "masts" in ship else []
	if not (masts_variant is Array):
		return
	for mast in masts_variant:
		if not is_instance_valid(mast):
			continue
		if mast.has_method("add_sail_damage"):
			mast.add_sail_damage(randf_range(DERELICT_SAIL_DAMAGE_MIN, DERELICT_SAIL_DAMAGE_MAX))
		elif mast.has_method("set_sail_damage"):
			mast.set_sail_damage(randf_range(DERELICT_SAIL_DAMAGE_MIN, DERELICT_SAIL_DAMAGE_MAX))
		if mast.has_method("set_sail_color"):
			mast.set_sail_color(DERELICT_SAIL_COLOR)


static func _play_derelict_transition_visuals(ship) -> void:
	if not is_instance_valid(ship) or not ship.is_inside_tree():
		return

	_spawn_derelict_smoke(ship, Vector3(-0.7, 0.9, -1.6), 0.95)
	_spawn_derelict_smoke(ship, Vector3(0.8, 0.85, 0.3), 0.85)
	_spawn_derelict_smoke(ship, Vector3(0.1, 1.0, 1.7), 0.75)
	_spawn_derelict_water_burst(ship, Vector3(-1.1, 0.0, -2.1), 0.82)
	_spawn_derelict_water_burst(ship, Vector3(1.0, 0.0, 1.8), 0.72)


static func _spawn_derelict_smoke(ship, local_offset: Vector3, intensity: float) -> void:
	var scene: PackedScene = ship.get("impact_puff_scene") if "impact_puff_scene" in ship else null
	if not is_instance_valid(scene):
		return
	var smoke = ScenePool.acquire(ship.get_tree(), scene)
	if not is_instance_valid(smoke):
		return
	ship.get_tree().root.add_child(smoke)
	smoke.global_position = ship.to_global(local_offset)
	if smoke.has_method("set_intensity"):
		smoke.set_intensity(intensity)
	if smoke.has_method("pool_activate"):
		smoke.pool_activate()


static func _spawn_derelict_water_burst(ship, local_offset: Vector3, intensity: float) -> void:
	var scene: PackedScene = ship.get("water_splash_scene") if "water_splash_scene" in ship else null
	if not is_instance_valid(scene):
		return
	var splash = ScenePool.acquire(ship.get_tree(), scene)
	if not is_instance_valid(splash):
		return
	ship.get_tree().root.add_child(splash)
	var splash_pos: Vector3 = ship.to_global(local_offset)
	splash_pos.y = ship.base_y + 0.05
	splash.global_position = splash_pos
	if splash.has_method("configure_as_small"):
		splash.configure_as_small()
	if splash.has_method("set_intensity"):
		splash.set_intensity(intensity)
	if splash.has_method("pool_activate"):
		splash.pool_activate()


static func _set_derelict_settle_pose(ship) -> void:
	var roll_degrees: float = randf_range(-DERELICT_MAX_ROLL_DEGREES, DERELICT_MAX_ROLL_DEGREES)
	if absf(roll_degrees) < DERELICT_MIN_ROLL_DEGREES:
		roll_degrees = DERELICT_MIN_ROLL_DEGREES * (1.0 if randf() >= 0.5 else -1.0)
	var pitch_degrees: float = randf_range(-DERELICT_MAX_PITCH_DEGREES, DERELICT_MAX_PITCH_DEGREES)
	var settle_tween = ship.create_tween()
	settle_tween.set_parallel(true)
	settle_tween.tween_property(ship, "rotation_degrees:z", roll_degrees, 1.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle_tween.tween_property(ship, "rotation_degrees:x", pitch_degrees, 1.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle_tween.tween_property(ship, "position:y", ship.base_y + DERELICT_SETTLE_Y_OFFSET, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func sink_derelict(ship) -> void:
	if ship.is_sinking:
		return
	ship.is_sinking = true
	print("[Ship] 폐선 침몰 시작!")
	drop_floating_loot(ship)

	ship._set_fire_emitting(true)

	var sink_tween = ship.create_tween()
	sink_tween.tween_property(ship, "global_position:y", ship.base_y - 15.0, 5.0).set_ease(Tween.EASE_IN)
	sink_tween.parallel().tween_property(ship, "rotation_degrees:x", randf_range(-20.0, 20.0), 5.0)
	sink_tween.parallel().tween_property(ship, "rotation_degrees:z", randf_range(20.0, 40.0) * (1 if randf() > 0.5 else -1), 5.0)
	if ship.has_method("play_sink_bubbles"):
		ship.play_sink_bubbles(0.25, -1.5)

	await sink_tween.finished
	ship.queue_free()


static func check_offscreen_despawn(ship) -> void:
	if not ship.is_derelict or ship.is_sinking:
		return
	var player: Node = EntityRegistry.get_first_ship_by_team("player")
	if not is_instance_valid(player):
		return

	var started_at: float = float(ship.get_meta("derelict_started_at", 0.0))
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - started_at < DERELICT_MIN_VISIBLE_LIFETIME:
		return

	var dist = ship.global_position.distance_to(player.global_position)
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
	if ship.get_meta("floating_loot_dropped", false) == true:
		return
	ship.set_meta("floating_loot_dropped", true)
	if randf() > float(ship.floating_loot_drop_chance):
		return

	var loot = ScenePool.acquire(ship.get_tree(), ship.loot_scene)
	var offset_x = randf_range(-1.2, 1.2)
	var offset_z = randf_range(-1.2, 1.2)
	var spawn_pos = Vector3(ship.global_position.x + offset_x, 0.5, ship.global_position.z + offset_z)

	ship.get_tree().root.add_child.call_deferred(loot)
	loot.set_deferred("global_position", spawn_pos)

	if ship.survivor_scene and randf() < 0.3:
		var survivor = ScenePool.acquire(ship.get_tree(), ship.survivor_scene)
		var s_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
		var survivor_pos = ship.global_position + s_offset
		ship.get_tree().root.add_child.call_deferred(survivor)
		survivor.set_deferred("global_position", survivor_pos)
		print("[Rescue] 구출 가능한 생존자가 발생했습니다!")


static func evacuate_player_soldiers_as_survivors(ship) -> void:
	if not ship.survivor_scene:
		return
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not soldiers_node:
		return

	var converted_count = 0
	for child in soldiers_node.get_children():
		if child.has_method("is_player_team_soldier") and child.is_player_team_soldier() and SoldierStateHelper.is_alive_soldier(child):
			var spawn_pos = child.global_position
			spawn_pos.y = 0.5

			var survivor = ScenePool.acquire(ship.get_tree(), ship.survivor_scene)
			ship.get_tree().root.add_child.call_deferred(survivor)
			survivor.set_deferred("global_position", spawn_pos)

			child.queue_free()
			converted_count += 1

	if converted_count > 0:
		print("[Critical] 아군 병사 %d명이 바다로 뛰어들었습니다!" % converted_count)


static func evacuate_soldiers_to_home(ship) -> void:
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not soldiers_node:
		return

	var returned_count = 0
	for child in soldiers_node.get_children():
		if SoldierStateHelper.is_dead_soldier(child):
			continue

		var h_ship = child.get("home_ship")
		if is_instance_valid(h_ship) and h_ship != ship and not (h_ship.has_method("is_sinking_or_dying") and h_ship.is_sinking_or_dying()):
			var target_soldiers = NodeContractHelper.get_soldiers_container(h_ship)
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
			if child.has_method("is_stationary_value") and child.is_stationary_value():
				child.set("is_stationary", false)
			returned_count += 1
			print("[Evacuation] 병사가 원래 배(%s)로 복귀합니다!" % h_ship.name)

	if returned_count > 0:
		print("[Evacuation] 총 %d명의 병사가 원래 배로 복귀했습니다." % returned_count)
