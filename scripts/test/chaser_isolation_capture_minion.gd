@tool
extends "res://scripts/test/chaser_isolation_runtime_methods.gd"

var leaking_rate: float = 0.0
@export var minion_respawn_interval: float = 15.0
@export var max_minion_crew: int = 4
var minion_respawn_timer: float = 0.0


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
		var capture_merit_reward: int = max(0, int(cached_lm.get("boarding_capture_merit_reward")))
		if capture_score_reward > 0 and cached_lm.has_method("add_score"):
			cached_lm.add_score(capture_score_reward)
		if capture_xp_reward > 0 and cached_lm.has_method("add_xp"):
			cached_lm.add_xp(capture_xp_reward)
		if capture_merit_reward > 0 and cached_lm.has_method("add_merit"):
			cached_lm.add_merit(capture_merit_reward)

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


func _update_minion_respawn(delta: float) -> void:
	if deck_is_contested:
		return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node:
		return

	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4:
			alive_count += 1

	if alive_count < max_minion_crew:
		minion_respawn_timer += delta
		if minion_respawn_timer >= minion_respawn_interval:
			minion_respawn_timer = 0.0
			_respawn_minion_soldier()


func _respawn_minion_soldier() -> void:
	_spawn_one_soldier("player")
	print("[Crew] 나포함 병사 자생적 보충 완료.")


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
