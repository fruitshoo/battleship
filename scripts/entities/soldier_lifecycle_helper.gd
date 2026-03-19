extends RefCounted
class_name SoldierLifecycleHelper


static func take_damage(soldier, amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if soldier.current_state == soldier.State.DEAD:
		return

	var defense_bonus: float = 0.0
	if soldier.has_meta("defense_flat_bonus"):
		defense_bonus = maxf(0.0, float(soldier.get_meta("defense_flat_bonus")))
	var mitigated_damage: float = maxf(amount - (soldier.defense + defense_bonus), 1.0)
	var quality_reduction: float = 0.0
	if soldier.has_meta("defense_reduction"):
		quality_reduction = clampf(float(soldier.get_meta("defense_reduction")), 0.0, 0.9)
	var cover_reduction: float = get_ship_ranged_cover_reduction(soldier, damage_source)
	var total_reduction: float = clampf(quality_reduction + cover_reduction, 0.0, 0.9)
	var final_damage: float = maxf(mitigated_damage * (1.0 - total_reduction), 1.0)
	soldier.current_health -= final_damage

	if not damage_source.is_empty() and soldier.team == "enemy":
		if soldier._cached_level_manager and soldier._cached_level_manager.has_method("add_player_weapon_damage"):
			soldier._cached_level_manager.add_player_weapon_damage(damage_source, final_damage)

	if soldier.has_method("_flash_hit"):
		soldier._flash_hit()

	if hit_position != Vector3.ZERO and soldier.current_state != soldier.State.DEAD:
		var knock_dir: Vector3 = soldier.global_position - hit_position
		knock_dir.y = 0.0
		if knock_dir.length_squared() > 0.001:
			knock_dir = knock_dir.normalized()
			soldier.velocity += knock_dir * minf(final_damage * 0.2, 3.5)

	if soldier.current_health <= 0.0:
		die(soldier)


static func get_ship_ranged_cover_reduction(soldier, damage_source: String) -> float:
	if not soldier.RANGED_DAMAGE_SOURCES.has(damage_source):
		return 0.0
	if not is_instance_valid(soldier.owned_ship):
		return 0.0
	if soldier.team == "enemy" and soldier.owned_ship.get("team") == "player":
		return 0.0
	if soldier.current_state == soldier.State.DEAD:
		return 0.0
	return 0.2


static func update_boarding_chaos(soldier, delta: float) -> void:
	if soldier.current_state == soldier.State.DEAD:
		return
	if not is_instance_valid(soldier.owned_ship):
		return
	if soldier.team != "enemy":
		return
	if soldier.owned_ship.get("team") != "player":
		return

	soldier.is_boarder_on_player_ship = true
	soldier.chaos_duration_timer -= delta
	soldier.chaos_tick_timer -= delta

	if soldier.chaos_tick_timer <= 0.0:
		soldier.chaos_tick_timer = 1.0
		if soldier.owned_ship.has_method("take_fire_damage"):
			soldier.owned_ship.take_fire_damage(soldier.chaos_damage_per_tick, 2.0)
		elif soldier.owned_ship.has_method("take_damage"):
			soldier.owned_ship.take_damage(soldier.chaos_damage_per_tick, soldier.global_position, "boarding_fire")

	if soldier.chaos_duration_timer <= 0.0:
		soldier.is_boarder_on_player_ship = false
		soldier.chaos_duration_timer = 8.0
		soldier.chaos_tick_timer = 0.0
		if soldier.has_method("_try_evacuate_to_home"):
			soldier._try_evacuate_to_home()


static func heal_full(soldier) -> void:
	if soldier.current_state != soldier.State.DEAD:
		soldier.current_health = soldier.max_health


static func die(soldier) -> void:
	if soldier.current_state == soldier.State.DEAD:
		return

	soldier.current_state = soldier.State.DEAD
	soldier.current_target = null
	soldier.attack_timer = 0.0
	soldier.is_boarder_on_player_ship = false

	if is_instance_valid(soldier.home_ship) and soldier.home_ship.has_method("check_derelict_status"):
		soldier.home_ship.call_deferred("check_derelict_status")

	if soldier.team == "enemy":
		if soldier._cached_level_manager and soldier._cached_level_manager.has_method("add_xp"):
			soldier._cached_level_manager.add_xp(5)
		if soldier._cached_level_manager and soldier._cached_level_manager.has_method("add_soldier_kill"):
			soldier._cached_level_manager.add_soldier_kill(1)
		if soldier._cached_level_manager:
			if soldier._cached_level_manager.has_method("add_command_xp_from_soldier_kill"):
				soldier._cached_level_manager.add_command_xp_from_soldier_kill(1)
			elif soldier._cached_level_manager.has_method("add_merit"):
				soldier._cached_level_manager.add_merit(1)

	var death_position: Vector3 = soldier.global_position
	var tree: SceneTree = soldier.get_tree()
	var audio_manager = soldier.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("soldier_die", death_position)
		if is_instance_valid(tree):
			tree.create_timer(randf_range(0.3, 0.6)).timeout.connect(func():
				var main_loop := Engine.get_main_loop() as SceneTree
				if not is_instance_valid(main_loop):
					return
				var delay_am = main_loop.root.get_node_or_null("AudioManager")
				if is_instance_valid(delay_am) and delay_am.has_method("play_sfx"):
					delay_am.play_sfx("water_splash_small", death_position, randf_range(0.8, 1.2))
			)

	soldier.set_physics_process(false)
	if soldier.is_in_group("soldiers"):
		soldier.remove_from_group("soldiers")
	if soldier.is_in_group("enemy"):
		soldier.remove_from_group("enemy")

	if soldier.has_node("CollisionShape3D"):
		soldier.get_node("CollisionShape3D").set_deferred("disabled", true)

	soldier.visible = false
