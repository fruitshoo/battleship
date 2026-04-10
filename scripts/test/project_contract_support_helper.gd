extends RefCounted
class_name ProjectContractSupportHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")


static func run_support_fleet_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("support fleet smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("support fleet smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("support fleet smoke missing PlayerShip")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	if not player_ship.has_method("_spawn_or_repair_ally") or not player_ship.has_method("_get_support_fleet_ships"):
		failures.append("support fleet smoke missing player ship support helpers")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	if "support_fleet_limit" in player_ship:
		player_ship.set("support_fleet_limit", 1)

	var captured_before: int = EntityRegistry.count_captured_minions()
	player_ship.call("_spawn_or_repair_ally")
	await _wait_frames(owner, wait_frames_after_spawn + 2)

	var support_ships: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships.size() != 1:
		failures.append("support fleet smoke expected 1 support ship, got %d" % support_ships.size())
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var support_ship := support_ships[0] as Node3D
	if not is_instance_valid(support_ship):
		failures.append("support fleet smoke support ship was invalid")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var support_team: String = str(support_ship.get("team"))
	if support_team != "player":
		failures.append("support fleet smoke team mismatch: %s" % support_team)
	if not support_ship.is_in_group("captured_minion"):
		failures.append("support fleet smoke missing captured_minion group")
	if support_ship.get_meta("support_fleet_ship", false) != true:
		failures.append("support fleet smoke missing support_fleet_ship meta")
	if EntityRegistry.count_captured_minions() <= captured_before:
		failures.append("support fleet smoke did not increase captured minion count")
	if not EntityRegistry.get_captured_minions().has(support_ship):
		failures.append("support fleet smoke support ship missing from registry bucket")

	var target_ship: Node3D = null
	if support_ship.has_method("get_target_ship"):
		target_ship = support_ship.get_target_ship()
	else:
		var target_variant: Variant = support_ship.get("target")
		if is_instance_valid(target_variant):
			target_ship = target_variant
	if target_ship != player_ship:
		failures.append("support fleet smoke support ship target mismatch")

	var support_before_idle_pos: Vector3 = support_ship.global_position
	support_ship.set("target", null)
	await _wait_frames(owner, wait_frames_after_spawn + 2)
	var support_idle_distance: float = support_ship.global_position.distance_to(support_before_idle_pos)
	if support_idle_distance <= 0.1:
		failures.append("support fleet smoke support ship did not keep moving after target loss")
	if support_ship.get_meta("support_debug_lead_name", "") != "anchor":
		failures.append("support fleet smoke support ship did not enter anchor idle mode after target loss")

	var repair_before: float = 0.0
	if support_ship.get("hull_hp") != null and support_ship.get("max_hull_hp") != null:
		var max_hull_hp: float = float(support_ship.get("max_hull_hp"))
		repair_before = max_hull_hp * 0.2
		support_ship.set("hull_hp", repair_before)

	player_ship.call("_spawn_or_repair_ally")
	await _wait_frames(owner, 1)

	var support_ships_after: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships_after.size() != 1:
		failures.append("support fleet smoke limit gate failed, got %d support ships" % support_ships_after.size())
	if support_ship.get("hull_hp") != null and float(support_ship.get("hull_hp")) <= repair_before:
		failures.append("support fleet smoke repair path did not heal support ship")

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
