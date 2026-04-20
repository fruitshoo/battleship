extends Node

const EnemyDrifterScene = preload("res://scenes/effects/enemy_drifter_xp.tscn")


class MockLevelManager:
	extends Node

	var drowned_soldier_kill_xp_reward: int = 3
	var drowned_soldier_kill_merit_reward: int = 0
	var current_xp: int = 0
	var soldiers_killed: int = 0
	var soldiers_drowned: int = 0
	var merit_points: int = 0
	var hud: Node = null

	func add_xp(amount: int) -> void:
		current_xp += amount

	func add_merit(amount: int) -> void:
		merit_points += amount

	func add_soldier_kill(count: int = 1, cause: String = "combat") -> void:
		soldiers_killed += count
		if cause == "drowned":
			soldiers_drowned += count


class MockShip:
	extends Node3D

	var team: String = "enemy"
	var cached_lm: Node = null
	var enemy_drifter_xp_scene: PackedScene = EnemyDrifterScene

	func _init() -> void:
		var soldiers := Node3D.new()
		soldiers.name = "Soldiers"
		add_child(soldiers)


class MockSoldier:
	extends Node3D

	var team: String = "enemy"
	var home_ship: Node = null
	var _dead: bool = false
	var _cached_level_manager: Node = null

	func get_team_tag() -> String:
		return team

	func is_dead_soldier() -> bool:
		return _dead


class MockPlayerShip:
	extends Node3D

	func _init() -> void:
		add_to_group("player")

	func get_directional_collision_radius(_world_dir: Vector3) -> float:
		return 1.2

	func is_sinking_or_dying() -> bool:
		return false


func _ready() -> void:
	var failures: Array[String] = []
	await get_tree().process_frame
	await _verify_sinking_enemy_soldier_xp_is_deferred_to_pickup(failures)
	_verify_accounted_soldier_does_not_grant_duplicate_drowned_xp(failures)
	_verify_enemy_drifter_uses_survivor_like_field_item_tuning(failures)
	LevelManagerRegistry.unregister_level_manager(LevelManagerRegistry.get_level_manager(get_tree()))
	if failures.is_empty():
		print("[EnemyDrifterXPContract] ok")
		get_tree().quit()
		return
	for failure in failures:
		push_error("[EnemyDrifterXPContract] %s" % failure)
	get_tree().quit(1)


func _verify_sinking_enemy_soldier_xp_is_deferred_to_pickup(failures: Array[String]) -> void:
	var lm := MockLevelManager.new()
	add_child(lm)
	LevelManagerRegistry.register_level_manager(lm)
	var ship := MockShip.new()
	ship.cached_lm = lm
	add_child(ship)
	ship.global_position = Vector3(10.0, 0.0, 0.0)
	var soldiers_node := ship.get_node("Soldiers")
	for _i in range(5):
		var soldier := MockSoldier.new()
		soldier.home_ship = ship
		soldier._cached_level_manager = lm
		soldiers_node.add_child(soldier)

	var spawned := ChaserShipSupportHelper.spawn_enemy_drifter_xp_pickups(ship)
	await get_tree().process_frame
	if spawned != 2:
		failures.append("expected 2 drifter pickups for 5 sinking soldiers, got %d" % spawned)
	if lm.current_xp != 0:
		failures.append("sinking soldiers granted XP immediately before pickup collection")
	if lm.soldiers_drowned != 5:
		failures.append("sinking soldiers did not update drowned combat stats immediately")

	var pickups := get_tree().get_nodes_in_group("enemy_drifter_xp")
	if pickups.size() != 2:
		failures.append("expected 2 enemy_drifter_xp nodes, found %d" % pickups.size())
		return
	var total_xp := 0
	for pickup_node in pickups:
		total_xp += int(pickup_node.get("xp_amount"))
	if total_xp != 15:
		failures.append("drifter pickups carried %d XP, expected 15" % total_xp)

	var player := MockPlayerShip.new()
	add_child(player)
	player.global_position = (pickups[0] as Node3D).global_position
	(pickups[0] as Node).call("_try_collect", player)
	if lm.current_xp <= 0:
		failures.append("collecting an enemy drifter pickup did not grant XP")
	if lm.current_xp >= total_xp:
		failures.append("collecting one grouped pickup granted all drifter XP at once")


func _verify_accounted_soldier_does_not_grant_duplicate_drowned_xp(failures: Array[String]) -> void:
	var lm := MockLevelManager.new()
	add_child(lm)
	var soldier := MockSoldier.new()
	soldier._cached_level_manager = lm
	soldier.set_meta("enemy_sinking_reward_accounted", true)
	SoldierLifecycleHelper._apply_enemy_kill_rewards(soldier)
	if lm.current_xp != 0:
		failures.append("accounted sinking soldier granted duplicate drowned XP")


func _verify_enemy_drifter_uses_survivor_like_field_item_tuning(failures: Array[String]) -> void:
	var pickup := EnemyDrifterScene.instantiate()
	if pickup == null:
		failures.append("enemy drifter tuning contract could not instantiate pickup")
		return
	add_child(pickup)
	await get_tree().process_frame
	if absf(float(pickup.get("waterline_offset")) - -0.05) > 0.001:
		failures.append("enemy drifter should use survivor-like waterline offset")
	if absf(float(pickup.get("visual_waterline_offset")) - 0.22) > 0.001:
		failures.append("enemy drifter should keep its visual near the survivor waterline")
	if absf(float(pickup.get("base_magnet_radius")) - 8.0) > 0.001:
		failures.append("enemy drifter should use survivor-like magnet radius")
	if absf(float(pickup.get("magnet_speed")) - 7.5) > 0.001:
		failures.append("enemy drifter should use survivor-like magnet speed")
	if absf(float(pickup.get("collection_contact_margin")) - 0.7) > 0.001:
		failures.append("enemy drifter should use survivor-like contact margin")
	var call_label := pickup.get_node_or_null("DrifterCallLabel") as Label3D
	if call_label == null:
		failures.append("enemy drifter should create a waterline speech label")
	elif call_label.outline_size > 8:
		failures.append("enemy drifter speech outline is too thick")
	var effect_source := FileAccess.get_file_as_string("res://scripts/effects/enemy_drifter_xp.gd")
	if not effect_source.contains("FieldItemHelper.sample_ocean_surface"):
		failures.append("enemy drifter should share ocean surface sampling through FieldItemHelper")
	var survivor_source := FileAccess.get_file_as_string("res://scripts/effects/survivor.gd")
	if not survivor_source.contains("FieldItemHelper.sample_ocean_surface"):
		failures.append("survivor should share ocean surface sampling through FieldItemHelper")
	pickup.queue_free()
