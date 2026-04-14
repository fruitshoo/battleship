extends RefCounted
class_name ProjectContractSceneWiringHelper


static func run_scene_wiring_contract_smoke(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var scene_checks := [
		{
			"path": "res://scenes/ships/player_ship.tscn",
			"label": "player ship",
			"team": "player",
			"player_controlled": true,
			"groups": ["player"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "WakeTrail", "ShipAudio", "CollisionVisualizer"],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": null,
		},
		{
			"path": "res://scenes/ships/enemy_ship.tscn",
			"label": "enemy ship",
			"team": "enemy",
			"player_controlled": false,
			"groups": ["enemy", "ships"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "WakeTrail", "CollisionVisualizer"],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": null,
		},
		{
			"path": "res://scenes/ships/boss_ship.tscn",
			"label": "boss ship",
			"team": "enemy",
			"player_controlled": false,
			"groups": ["boss", "ships"],
			"required_nodes": ["CollisionArea", "Soldiers", "CollisionVisualizer", "Cannons"],
			"require_hull": true,
			"require_boss_group": true,
			"allow_boarding": null,
		},
		{
			"path": "res://scenes/ships/enemy_firepot_ship.tscn",
			"label": "enemy firepot ship",
			"team": "enemy",
			"player_controlled": false,
			"groups": ["enemy", "ships"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "WakeTrail", "CollisionVisualizer"],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": true,
		},
	]

	for check in scene_checks:
		await _run_single_scene_wiring_pass(
			owner,
			failures,
			str(check["path"]),
			str(check["label"]),
			str(check["team"]),
			check["player_controlled"] == true,
			check["groups"],
			check["required_nodes"],
			check["require_hull"] == true,
			check["require_boss_group"] == true,
			check["allow_boarding"],
			wait_frames_after_attach
		)

	_run_main_player_effect_scene_wiring_pass(failures)
	await _run_result_scene_wiring_pass(owner, failures, wait_frames_after_attach)


static func _run_result_scene_wiring_pass(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/ui/result_screen.tscn") as PackedScene
	if packed == null:
		failures.append("result scene wiring load failed")
		return
	var result_root := packed.instantiate()
	if result_root == null:
		failures.append("result scene wiring instantiate failed")
		return
	owner.add_child(result_root)
	await _wait_frames(owner, wait_frames_after_attach)
	for node_path in ["Content/TitleBlock/Title", "Content/TitleBlock/Subtitle", "Content/Body/SummaryPanel/Margin/SummaryList", "Content/Body/WeaponPanel/Margin/WeaponList", "Content/ButtonBlock/RestartButton", "Content/ButtonBlock/MainMenuButton"]:
		if result_root.get_node_or_null(str(node_path)) == null:
			failures.append("result scene wiring missing node: %s" % node_path)
	result_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_main_player_effect_scene_wiring_pass(failures: Array[String]) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		failures.append("main scene wiring load failed")
		return
	var main_root := packed.instantiate()
	if main_root == null:
		failures.append("main scene wiring instantiate failed")
		return
	var player_ship := main_root.get_node_or_null("PlayerShip")
	if not is_instance_valid(player_ship):
		failures.append("main scene wiring missing PlayerShip")
		main_root.queue_free()
		return

	_validate_packed_scene_path(player_ship, "wood_splinter_scene", "res://scenes/effects/wood_splinter.tscn", failures)
	_validate_packed_scene_path(player_ship, "water_splash_scene", "res://scenes/effects/water_burst.tscn", failures)
	_validate_packed_scene_path(player_ship, "fire_effect_scene", "res://scenes/effects/fire_effect.tscn", failures)
	_validate_packed_scene_path(player_ship, "survivor_scene", "res://scenes/effects/survivor.tscn", failures)
	if player_ship.get("loot_scene") != null:
		failures.append("main scene PlayerShip loot_scene should stay null")
	main_root.queue_free()


static func _validate_packed_scene_path(node: Node, property_name: String, expected_path: String, failures: Array[String]) -> void:
	var value = node.get(property_name)
	if not (value is PackedScene):
		failures.append("main scene PlayerShip %s is not a PackedScene" % property_name)
		return
	var actual_path := (value as PackedScene).resource_path
	if actual_path != expected_path:
		failures.append("main scene PlayerShip %s mismatch: %s" % [property_name, actual_path])


static func _run_single_scene_wiring_pass(owner: Node, failures: Array[String], scene_path: String, label: String, expected_team: String, expected_player_controlled: bool, expected_groups: Array, required_nodes: Array, require_hull: bool, require_boss_group: bool, expected_allow_boarding, wait_frames_after_attach: int) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("scene wiring load failed: %s" % scene_path)
		return

	var scene_root := packed.instantiate()
	if scene_root == null:
		failures.append("scene wiring instantiate failed: %s" % scene_path)
		return

	var wrapper := Node3D.new()
	wrapper.name = "%s_WiringSmoke" % label.replace(" ", "_")
	owner.add_child(wrapper)
	wrapper.add_child(scene_root)
	await _wait_frames(owner, wait_frames_after_attach)

	if scene_root.has_method("get_team_tag"):
		var actual_team: String = str(scene_root.get_team_tag())
		if actual_team != expected_team:
			failures.append("%s wiring team mismatch: %s" % [label, actual_team])
	if scene_root.has_method("is_player_controlled_ship"):
		var actual_player_controlled: bool = scene_root.is_player_controlled_ship() == true
		if actual_player_controlled != expected_player_controlled:
			failures.append("%s wiring player-controlled mismatch" % label)
	for group_name in expected_groups:
		if not scene_root.is_in_group(str(group_name)):
			failures.append("%s missing group tag: %s" % [label, group_name])
	for node_name in required_nodes:
		if scene_root.get_node_or_null(str(node_name)) == null:
			failures.append("%s missing required node: %s" % [label, node_name])
	if require_hull and not _has_hull_child(scene_root):
		failures.append("%s missing runtime hull child" % label)
	if require_boss_group and not scene_root.is_in_group("boss"):
		failures.append("%s missing boss group tag after ready" % label)
	if expected_allow_boarding != null:
		var actual_allow_boarding: bool = scene_root.get("allow_boarding") == true
		if actual_allow_boarding != (expected_allow_boarding == true):
			failures.append("%s allow_boarding mismatch" % label)
		if scene_root.has_method("is_boarding_ship") and scene_root.is_boarding_ship() != true and expected_allow_boarding == true:
			failures.append("%s expected boarding-capable ship" % label)

	scene_root.queue_free()
	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _has_hull_child(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	for child in ship.get_children():
		if child is Node and str(child.name).contains("Hull"):
			return true
	return false


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
