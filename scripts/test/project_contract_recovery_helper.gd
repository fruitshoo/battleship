extends RefCounted
class_name ProjectContractRecoveryHelper

const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")


static func run_recovery_effect_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("recovery effect smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("recovery effect smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	var level_manager: Node = LevelManagerRegistry.get_level_manager(owner.get_tree())
	if not is_instance_valid(player_ship):
		failures.append("recovery effect smoke missing PlayerShip")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	if not is_instance_valid(level_manager):
		failures.append("recovery effect smoke missing LevelManager")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	await _run_floating_loot_smoke(owner, failures, smoke_root, player_ship, level_manager)
	await _run_survivor_smoke(owner, failures, smoke_root, player_ship)
	await _run_treasure_chest_smoke(owner, failures, smoke_root, player_ship)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_floating_loot_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D, level_manager: Node) -> void:
	var loot_scene := load("res://scenes/effects/floating_loot.tscn") as PackedScene
	if loot_scene == null:
		failures.append("recovery loot smoke scene load failed")
		return
	var loot := loot_scene.instantiate()
	if loot == null:
		failures.append("recovery loot smoke instantiate failed")
		return
	smoke_root.add_child(loot)
	if loot is Node3D:
		(loot as Node3D).global_position = player_ship.global_position + Vector3(1.5, 0.0, 0.0)
	await _wait_frames(owner, 1)

	var score_before: int = int(level_manager.get("current_score"))
	var hull_before: float = float(player_ship.get("hull_hp")) if player_ship.get("hull_hp") != null else 0.0
	if player_ship.get("max_hull_hp") != null:
		player_ship.set("hull_hp", maxf(1.0, float(player_ship.get("max_hull_hp")) * 0.4))
		hull_before = float(player_ship.get("hull_hp"))
	if player_ship.get("rowing_stamina") != null:
		player_ship.set("rowing_stamina", 0.0)
	loot.set("target_player", player_ship)
	loot.call("_collect_by_proximity")
	await _wait_frames(owner, 2)

	if loot.get("is_collected") != true:
		failures.append("recovery loot smoke did not mark loot collected")
	if int(level_manager.get("current_score")) <= score_before:
		failures.append("recovery loot smoke did not grant score")
	if player_ship.get("hull_hp") != null and float(player_ship.get("hull_hp")) <= hull_before:
		failures.append("recovery loot smoke did not repair player hull")


static func _run_survivor_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D) -> void:
	var survivor_scene := load("res://scenes/effects/survivor.tscn") as PackedScene
	if survivor_scene == null:
		failures.append("recovery survivor smoke scene load failed")
		return
	var survivor := survivor_scene.instantiate()
	if survivor == null:
		failures.append("recovery survivor smoke instantiate failed")
		return
	smoke_root.add_child(survivor)
	if survivor is Node3D:
		(survivor as Node3D).global_position = player_ship.global_position + Vector3(-1.5, 0.0, 0.0)
	await _wait_frames(owner, 1)

	if player_ship.get("max_crew_count") != null and player_ship.has_method("get_debug_crew_snapshot"):
		var crew_snapshot: Dictionary = player_ship.call("get_debug_crew_snapshot")
		var alive_before_fill: int = int(crew_snapshot.get("alive_count", 0))
		player_ship.set("max_crew_count", max(alive_before_fill + 1, int(player_ship.get("max_crew_count"))))

	var alive_before: int = 0
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_before = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))
	survivor.call("_try_collect", player_ship)
	await _wait_frames(owner, 2)
	var alive_after: int = alive_before
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_after = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))

	if survivor.get("is_collected") != true:
		failures.append("recovery survivor smoke did not mark survivor collected")
	if alive_after <= alive_before:
		failures.append("recovery survivor smoke did not add crew")


static func _run_treasure_chest_smoke(owner: Node, failures: Array[String], smoke_root: Node, player_ship: Node3D) -> void:
	var chest_scene := load("res://scenes/effects/treasure_chest.tscn") as PackedScene
	if chest_scene == null:
		failures.append("recovery treasure smoke scene load failed")
		return
	var chest := chest_scene.instantiate()
	if chest == null:
		failures.append("recovery treasure smoke instantiate failed")
		return
	smoke_root.add_child(chest)
	var expanded_pickup_distance: float = 8.0
	if chest.has_method("_get_effective_collection_range"):
		expanded_pickup_distance = maxf(5.0, float(chest.call("_get_effective_collection_range", player_ship)) - 0.5)
	if chest is Node3D:
		(chest as Node3D).global_position = player_ship.global_position + Vector3(expanded_pickup_distance, 0.0, 0.0)
	await _wait_frames(owner, 3)

	if chest.get("_is_collected") != true:
		failures.append("recovery treasure smoke did not mark chest collected from expanded range")
	if not chest.is_queued_for_deletion():
		failures.append("recovery treasure smoke did not queue chest for deletion")


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
