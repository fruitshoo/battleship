extends Node

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const ProjectContractHudHelper = preload("res://scripts/test/project_contract_hud_helper.gd")
const ProjectContractSaveHelper = preload("res://scripts/test/project_contract_save_helper.gd")

@export var script_roots: Array[String] = ["res://scripts"]
@export var scene_roots: Array[String] = ["res://scenes"]
@export var smoke_scene_path: String = "res://scenes/test/preview_base.tscn"
@export var smoke_wait_frames_after_attach: int = 2
@export var smoke_wait_frames_after_spawn: int = 3
@export var smoke_spawn_boss: bool = true
@export var smoke_spawn_final_boss: bool = true
@export var smoke_spawn_ship_types: Array[String] = [
	"kobayabune_melee",
	"sekibune_cannon",
	"sekibune_melee",
]
@export var smoke_spawn_launcher_scenes: Array[String] = [
	"res://scenes/entities/launchers/cannon_joseon.tscn",
	"res://scenes/entities/launchers/ballista_launcher.tscn",
	"res://scenes/entities/launchers/janggun_launcher.tscn",
	"res://scenes/entities/launchers/singigeon_launcher.tscn",
]
@export var smoke_spawn_projectile_scenes: Array[String] = [
	"res://scenes/projectiles/cannonball.tscn",
	"res://scenes/projectiles/arrow.tscn",
	"res://scenes/projectiles/fire_pot.tscn",
	"res://scenes/projectiles/ballista_bolt.tscn",
	"res://scenes/projectiles/janggun_missile.tscn",
	"res://scenes/projectiles/singigeon_rocket.tscn",
]
@export var smoke_run_save_contract: bool = true
@export var smoke_run_hud_contract: bool = true
@export var smoke_run_support_fleet_contract: bool = true
@export var smoke_run_bootstrap_contract: bool = true
@export var smoke_run_recovery_effect_contract: bool = true
@export var smoke_run_scene_wiring_contract: bool = true

var _failures: Array[String] = []
var _loaded_scripts: int = 0
var _loaded_scenes: int = 0


func _ready() -> void:
	call_deferred("_run_contract_checks")


func _run_contract_checks() -> void:
	_scan_resource_roots(script_roots, ".gd")
	_scan_legacy_godot3_patterns(script_roots)
	_scan_resource_roots(scene_roots, ".tscn")
	await _run_runtime_smoke()
	if smoke_run_save_contract:
		_run_save_contract_smoke()
	if smoke_run_hud_contract:
		await _run_hud_contract_smoke()
	if smoke_run_support_fleet_contract:
		await _run_support_fleet_contract_smoke()
	if smoke_run_bootstrap_contract:
		await _run_bootstrap_contract_smoke()
	if smoke_run_recovery_effect_contract:
		await _run_recovery_effect_contract_smoke()
	if smoke_run_scene_wiring_contract:
		await _run_scene_wiring_contract_smoke()
	_report_and_quit()


func _scan_resource_roots(roots: Array[String], suffix: String) -> void:
	var paths: Array[String] = []
	for root in roots:
		_collect_paths(root, suffix, paths)
	paths.sort()

	for path in paths:
		var resource = load(path)
		if resource == null:
			_failures.append("load failed: %s" % path)
			continue
		if suffix == ".gd":
			if not (resource is Script):
				_failures.append("script load returned %s: %s" % [resource.get_class(), path])
				continue
			_loaded_scripts += 1
		else:
			if not (resource is PackedScene):
				_failures.append("scene load returned %s: %s" % [resource.get_class(), path])
				continue
			_loaded_scenes += 1


func _collect_paths(root_path: String, suffix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		_failures.append("unable to open: %s" % root_path)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(".") or entry.ends_with(".uid"):
			entry = dir.get_next()
			continue
		var full_path := "%s/%s" % [root_path, entry]
		if dir.current_is_dir():
			_collect_paths(full_path, suffix, out)
		elif entry.ends_with(suffix):
			out.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_legacy_godot3_patterns(roots: Array[String]) -> void:
	var legacy_patterns := [
		{"pattern": "yield(", "label": "yield()"},
		{"pattern": "funcref(", "label": "funcref()"},
		{"pattern": ".instance(", "label": "PackedScene.instance()"},
		{"pattern": "String(", "label": "String() constructor"},
	]

	var paths: Array[String] = []
	for root in roots:
		_collect_paths(root, ".gd", paths)
	paths.sort()

	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			continue
		for legacy in legacy_patterns:
			var pattern: String = legacy["pattern"]
			var label: String = legacy["label"]
			var line_no := 1
			for line in source.split("\n", false):
				if line.find(pattern) != -1:
					_failures.append("%s found in %s:%d" % [label, path, line_no])
				line_no += 1


func _run_runtime_smoke() -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		_failures.append("smoke scene load failed: %s" % smoke_scene_path)
		return

	if not smoke_spawn_boss and not smoke_spawn_final_boss and smoke_spawn_ship_types.is_empty() and smoke_spawn_launcher_scenes.is_empty() and smoke_spawn_projectile_scenes.is_empty():
		_failures.append("no smoke mode enabled")
		return

	if smoke_spawn_boss:
		await _run_single_smoke_pass(packed, "debug_spawn_mid_boss", "mid boss")
	if smoke_spawn_final_boss:
		await _run_single_smoke_pass(packed, "debug_spawn_final_boss", "final boss")
	for ship_type_name in smoke_spawn_ship_types:
		await _run_ship_variant_smoke_pass(packed, str(ship_type_name))
	for launcher_scene_path in smoke_spawn_launcher_scenes:
		await _run_launcher_smoke_pass(packed, str(launcher_scene_path))
	for projectile_scene_path in smoke_spawn_projectile_scenes:
		await _run_projectile_smoke_pass(packed, str(projectile_scene_path))


func _run_save_contract_smoke() -> void:
	ProjectContractSaveHelper.run_save_contract_smoke(_failures)


func _run_hud_contract_smoke() -> void:
	await ProjectContractHudHelper.run_hud_contract_smoke(
		self,
		_failures,
		smoke_scene_path,
		smoke_wait_frames_after_attach,
		smoke_wait_frames_after_spawn
	)


func _run_scene_wiring_contract_smoke() -> void:
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
			str(check["path"]),
			str(check["label"]),
			str(check["team"]),
			bool(check["player_controlled"]),
			check["groups"],
			check["required_nodes"],
			bool(check["require_hull"]),
			bool(check["require_boss_group"]),
			check["allow_boarding"]
		)


func _run_single_scene_wiring_pass(scene_path: String, label: String, expected_team: String, expected_player_controlled: bool, expected_groups: Array, required_nodes: Array, require_hull: bool, require_boss_group: bool, expected_allow_boarding) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("scene wiring load failed: %s" % scene_path)
		return

	var scene_root := packed.instantiate()
	if scene_root == null:
		_failures.append("scene wiring instantiate failed: %s" % scene_path)
		return

	var wrapper := Node3D.new()
	wrapper.name = "%s_WiringSmoke" % label.replace(" ", "_")
	add_child(wrapper)
	wrapper.add_child(scene_root)
	await _wait_frames(smoke_wait_frames_after_attach)

	if scene_root.has_method("get_team_tag"):
		var actual_team: String = str(scene_root.get_team_tag())
		if actual_team != expected_team:
			_failures.append("%s wiring team mismatch: %s" % [label, actual_team])
	if scene_root.has_method("is_player_controlled_ship"):
		var actual_player_controlled: bool = bool(scene_root.is_player_controlled_ship())
		if actual_player_controlled != expected_player_controlled:
			_failures.append("%s wiring player-controlled mismatch" % label)
	for group_name in expected_groups:
		if not scene_root.is_in_group(str(group_name)):
			_failures.append("%s missing group tag: %s" % [label, group_name])
	for node_name in required_nodes:
		if scene_root.get_node_or_null(str(node_name)) == null:
			_failures.append("%s missing required node: %s" % [label, node_name])
	if require_hull and not _has_hull_child(scene_root):
		_failures.append("%s missing runtime hull child" % label)
	if require_boss_group and not scene_root.is_in_group("boss"):
		_failures.append("%s missing boss group tag after ready" % label)
	if expected_allow_boarding != null:
		var actual_allow_boarding: bool = scene_root.get("allow_boarding") == true
		if actual_allow_boarding != bool(expected_allow_boarding):
			_failures.append("%s allow_boarding mismatch" % label)
		if scene_root.has_method("is_boarding_ship") and scene_root.is_boarding_ship() != true and bool(expected_allow_boarding):
			_failures.append("%s expected boarding-capable ship" % label)

	scene_root.queue_free()
	wrapper.queue_free()
	await _wait_frames(1)


func _run_support_fleet_contract_smoke() -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		_failures.append("support fleet smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("support fleet smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		_failures.append("support fleet smoke missing PlayerShip")
		smoke_root.queue_free()
		await _wait_frames(1)
		return
	if not player_ship.has_method("_spawn_or_repair_ally") or not player_ship.has_method("_get_support_fleet_ships"):
		_failures.append("support fleet smoke missing player ship support helpers")
		smoke_root.queue_free()
		await _wait_frames(1)
		return

	if "support_fleet_limit" in player_ship:
		player_ship.set("support_fleet_limit", 1)

	var captured_before: int = EntityRegistry.count_captured_minions()
	player_ship.call("_spawn_or_repair_ally")
	await _wait_frames(smoke_wait_frames_after_spawn + 2)

	var support_ships: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships.size() != 1:
		_failures.append("support fleet smoke expected 1 support ship, got %d" % support_ships.size())
		smoke_root.queue_free()
		await _wait_frames(1)
		return

	var support_ship := support_ships[0] as Node3D
	if not is_instance_valid(support_ship):
		_failures.append("support fleet smoke support ship was invalid")
		smoke_root.queue_free()
		await _wait_frames(1)
		return

	var support_team: String = str(support_ship.get("team"))
	if support_team != "player":
		_failures.append("support fleet smoke team mismatch: %s" % support_team)
	if not support_ship.is_in_group("captured_minion"):
		_failures.append("support fleet smoke missing captured_minion group")
	if bool(support_ship.get_meta("support_fleet_ship", false)) == false:
		_failures.append("support fleet smoke missing support_fleet_ship meta")
	if EntityRegistry.count_captured_minions() <= captured_before:
		_failures.append("support fleet smoke did not increase captured minion count")
	if not EntityRegistry.get_captured_minions().has(support_ship):
		_failures.append("support fleet smoke support ship missing from registry bucket")

	var target_ship: Node3D = null
	if support_ship.has_method("get_target_ship"):
		target_ship = support_ship.get_target_ship()
	else:
		var target_variant: Variant = support_ship.get("target")
		if is_instance_valid(target_variant):
			target_ship = target_variant
	if target_ship != player_ship:
		_failures.append("support fleet smoke support ship target mismatch")

	var repair_before: float = 0.0
	if support_ship.get("hull_hp") != null and support_ship.get("max_hull_hp") != null:
		var max_hull_hp: float = float(support_ship.get("max_hull_hp"))
		repair_before = max_hull_hp * 0.2
		support_ship.set("hull_hp", repair_before)

	player_ship.call("_spawn_or_repair_ally")
	await _wait_frames(1)

	var support_ships_after: Array = player_ship.call("_get_support_fleet_ships")
	if support_ships_after.size() != 1:
		_failures.append("support fleet smoke limit gate failed, got %d support ships" % support_ships_after.size())
	if support_ship.get("hull_hp") != null and float(support_ship.get("hull_hp")) <= repair_before:
		_failures.append("support fleet smoke repair path did not heal support ship")

	smoke_root.queue_free()
	await _wait_frames(1)


func _run_bootstrap_contract_smoke() -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		_failures.append("bootstrap smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("bootstrap smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach + 1)

	if not is_instance_valid(AudioManager):
		_failures.append("bootstrap smoke missing AudioManager autoload")
	else:
		if not bool(AudioManager.get("is_prewarm_finished")) and AudioManager.has_signal("prewarm_finished"):
			await AudioManager.prewarm_finished
			await _wait_frames(1)
		if not bool(AudioManager.get("is_prewarm_finished")):
			_failures.append("bootstrap smoke audio prewarm did not finish")
		if bool(AudioManager.get("_startup_sfx_muted")):
			_failures.append("bootstrap smoke startup audio mute flag remained enabled")
		var sfx_index_before: int = int(AudioManager.get("current_sfx_index"))
		var ui_index_before: int = int(AudioManager.get("current_2d_index"))
		if AudioManager.has_method("set_startup_sfx_muted"):
			AudioManager.set_startup_sfx_muted(true)
		AudioManager.play_sfx("ui_click")
		AudioManager.play_sfx("cannon_fire", Vector3.ZERO)
		await _wait_frames(1)
		if int(AudioManager.get("current_sfx_index")) != sfx_index_before:
			_failures.append("bootstrap smoke muted 3D SFX still advanced audio pool")
		if int(AudioManager.get("current_2d_index")) != ui_index_before:
			_failures.append("bootstrap smoke muted 2D SFX still advanced audio pool")
		if AudioManager.has_method("set_startup_sfx_muted"):
			AudioManager.set_startup_sfx_muted(false)

	var prewarm_wrapper := Node3D.new()
	prewarm_wrapper.name = "BootstrapPrewarmSmoke"
	prewarm_wrapper.set_meta("prewarm_mode", true)
	smoke_root.add_child(prewarm_wrapper)

	var effect_paths := [
		"res://scenes/effects/impact_puff.tscn",
		"res://scenes/effects/water_burst.tscn",
		"res://scenes/effects/fire_effect.tscn",
	]
	for effect_path in effect_paths:
		var effect_scene := load(effect_path) as PackedScene
		if effect_scene == null:
			_failures.append("bootstrap smoke effect load failed: %s" % effect_path)
			continue
		var effect_instance := effect_scene.instantiate()
		if effect_instance == null:
			_failures.append("bootstrap smoke effect instantiate failed: %s" % effect_path)
			continue
		prewarm_wrapper.add_child(effect_instance)
		await _wait_frames(1)
		_validate_prewarm_effect_state(effect_instance, effect_path)

	smoke_root.queue_free()
	await _wait_frames(1)


func _run_recovery_effect_contract_smoke() -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		_failures.append("recovery effect smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("recovery effect smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	var level_manager: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if not is_instance_valid(player_ship):
		_failures.append("recovery effect smoke missing PlayerShip")
		smoke_root.queue_free()
		await _wait_frames(1)
		return
	if not is_instance_valid(level_manager):
		_failures.append("recovery effect smoke missing LevelManager")
		smoke_root.queue_free()
		await _wait_frames(1)
		return

	await _run_floating_loot_smoke(smoke_root, player_ship, level_manager)
	await _run_survivor_smoke(smoke_root, player_ship)
	await _run_treasure_chest_smoke(smoke_root, player_ship)

	smoke_root.queue_free()
	await _wait_frames(1)


func _run_floating_loot_smoke(smoke_root: Node, player_ship: Node3D, level_manager: Node) -> void:
	var loot_scene := load("res://scenes/effects/floating_loot.tscn") as PackedScene
	if loot_scene == null:
		_failures.append("recovery loot smoke scene load failed")
		return
	var loot := loot_scene.instantiate()
	if loot == null:
		_failures.append("recovery loot smoke instantiate failed")
		return
	smoke_root.add_child(loot)
	if loot is Node3D:
		(loot as Node3D).global_position = player_ship.global_position + Vector3(1.5, 0.0, 0.0)
	await _wait_frames(1)

	var score_before: int = int(level_manager.get("current_score"))
	var hull_before: float = float(player_ship.get("hull_hp")) if player_ship.get("hull_hp") != null else 0.0
	if player_ship.get("max_hull_hp") != null:
		player_ship.set("hull_hp", maxf(1.0, float(player_ship.get("max_hull_hp")) * 0.4))
		hull_before = float(player_ship.get("hull_hp"))
	if player_ship.get("rowing_stamina") != null:
		player_ship.set("rowing_stamina", 0.0)
	loot.set("target_player", player_ship)
	loot.call("_collect_by_proximity")
	await _wait_frames(2)

	if loot.get("is_collected") != true:
		_failures.append("recovery loot smoke did not mark loot collected")
	if int(level_manager.get("current_score")) <= score_before:
		_failures.append("recovery loot smoke did not grant score")
	if player_ship.get("hull_hp") != null and float(player_ship.get("hull_hp")) <= hull_before:
		_failures.append("recovery loot smoke did not repair player hull")


func _run_survivor_smoke(smoke_root: Node, player_ship: Node3D) -> void:
	var survivor_scene := load("res://scenes/effects/survivor.tscn") as PackedScene
	if survivor_scene == null:
		_failures.append("recovery survivor smoke scene load failed")
		return
	var survivor := survivor_scene.instantiate()
	if survivor == null:
		_failures.append("recovery survivor smoke instantiate failed")
		return
	smoke_root.add_child(survivor)
	if survivor is Node3D:
		(survivor as Node3D).global_position = player_ship.global_position + Vector3(-1.5, 0.0, 0.0)
	await _wait_frames(1)

	if player_ship.get("max_crew_count") != null and player_ship.has_method("get_debug_crew_snapshot"):
		var crew_snapshot: Dictionary = player_ship.call("get_debug_crew_snapshot")
		var alive_before_fill: int = int(crew_snapshot.get("alive_count", 0))
		player_ship.set("max_crew_count", max(alive_before_fill + 1, int(player_ship.get("max_crew_count"))))

	var alive_before: int = 0
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_before = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))
	survivor.call("_try_collect", player_ship)
	await _wait_frames(2)
	var alive_after: int = alive_before
	if player_ship.has_method("get_debug_crew_snapshot"):
		alive_after = int(player_ship.call("get_debug_crew_snapshot").get("alive_count", 0))

	if survivor.get("is_collected") != true:
		_failures.append("recovery survivor smoke did not mark survivor collected")
	if alive_after <= alive_before:
		_failures.append("recovery survivor smoke did not add crew")


func _run_treasure_chest_smoke(smoke_root: Node, player_ship: Node3D) -> void:
	var chest_scene := load("res://scenes/effects/treasure_chest.tscn") as PackedScene
	if chest_scene == null:
		_failures.append("recovery treasure smoke scene load failed")
		return
	var chest := chest_scene.instantiate()
	if chest == null:
		_failures.append("recovery treasure smoke instantiate failed")
		return
	smoke_root.add_child(chest)
	if chest is Node3D:
		(chest as Node3D).global_position = player_ship.global_position + Vector3(0.0, 0.0, 1.0)
	await _wait_frames(1)

	chest.call("_collect")
	await _wait_frames(1)
	if chest.get("_is_collected") != true:
		_failures.append("recovery treasure smoke did not mark chest collected")
	if not chest.is_queued_for_deletion():
		_failures.append("recovery treasure smoke did not queue chest for deletion")


func _validate_prewarm_effect_state(effect_root: Node, effect_path: String) -> void:
	if not is_instance_valid(effect_root):
		_failures.append("bootstrap smoke invalid effect instance: %s" % effect_path)
		return
	var stack: Array[Node] = [effect_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node is GPUParticles3D and (node as GPUParticles3D).emitting:
			_failures.append("bootstrap smoke prewarm particle emitted unexpectedly: %s" % effect_path)
		if node is AudioStreamPlayer3D and (node as AudioStreamPlayer3D).playing:
			_failures.append("bootstrap smoke prewarm audio played unexpectedly: %s" % effect_path)
		for child in node.get_children():
			if child is Node:
				stack.append(child)


func _has_hull_child(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	for child in ship.get_children():
		if child is Node and str(child.name).contains("Hull"):
			return true
	return false


func _run_single_smoke_pass(packed: PackedScene, spawn_method: String, label: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach)

	var level_manager: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if not is_instance_valid(level_manager):
		_failures.append("level manager registry lookup failed during %s smoke" % label)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		_failures.append("preview base is missing PlayerShip for %s smoke" % label)

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		_failures.append("preview base is missing EnemySpawner for %s smoke" % label)
	else:
		var spawned_boss: Node3D = null
		if spawner.has_method(spawn_method):
			spawned_boss = spawner.call(spawn_method) as Node3D
			await _wait_frames(smoke_wait_frames_after_spawn)
		_validate_spawned_boss(spawned_boss, label)

	_validate_registry_smoke(player_ship, label)

	smoke_root.queue_free()
	await _wait_frames(1)


func _run_ship_variant_smoke_pass(packed: PackedScene, ship_type_name: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		_failures.append("preview base is missing PlayerShip for %s smoke" % ship_type_name)

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		_failures.append("preview base is missing EnemySpawner for %s smoke" % ship_type_name)
	else:
		var spawned_ship: Node3D = null
		if spawner.has_method("debug_spawn_ship"):
			spawned_ship = spawner.call("debug_spawn_ship", ship_type_name) as Node3D
			await _wait_frames(smoke_wait_frames_after_spawn)
		_validate_spawned_ship(spawned_ship, ship_type_name)

	_validate_registry_smoke(player_ship, ship_type_name)

	smoke_root.queue_free()
	await _wait_frames(1)


func _run_launcher_smoke_pass(packed: PackedScene, launcher_scene_path: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		_failures.append("preview base is missing PlayerShip for launcher smoke: %s" % launcher_scene_path)
	else:
		var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
		var target_ship: Node3D = null
		if is_instance_valid(spawner) and spawner.has_method("debug_spawn_ship"):
			target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 18.0, 0.0) as Node3D
			await _wait_frames(smoke_wait_frames_after_spawn)
		if not is_instance_valid(target_ship):
			_failures.append("launcher smoke target spawn failed: %s" % launcher_scene_path)
		else:
			var launcher_scene := load(launcher_scene_path) as PackedScene
			if launcher_scene == null:
				_failures.append("launcher scene load failed: %s" % launcher_scene_path)
			else:
				var launcher := launcher_scene.instantiate()
				if launcher == null:
					_failures.append("launcher scene instantiate failed: %s" % launcher_scene_path)
				else:
					if launcher.has_method("set_team"):
						launcher.set_team("player")
					elif launcher.get("team") != null:
						launcher.set("team", "player")
					player_ship.add_child(launcher)
					launcher.set_process(false)
					launcher.set_physics_process(false)
					await _wait_frames(smoke_wait_frames_after_attach)
					var launcher_team_variant: Variant = launcher.get("team")
					var launcher_team: String = "player" if launcher_team_variant == null else str(launcher_team_variant)
					if launcher_team != "player":
						_failures.append("launcher team contract failed: %s" % launcher_scene_path)

					var before_projectiles := EntityRegistry.count_projectiles()
					if launcher.has_method("fire"):
						if launcher_scene_path.contains("singigeon"):
							launcher.call("fire", target_ship, 0.0)
						else:
							launcher.call("fire", target_ship)
						await _wait_frames(smoke_wait_frames_after_spawn)
						var after_projectiles := EntityRegistry.count_projectiles()
						if after_projectiles <= before_projectiles:
							_failures.append("launcher did not spawn projectile: %s" % launcher_scene_path)
					else:
						_failures.append("launcher is missing fire() method: %s" % launcher_scene_path)

	smoke_root.queue_free()
	await _wait_frames(1)


func _run_projectile_smoke_pass(packed: PackedScene, projectile_scene_path: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		_failures.append("preview base is missing PlayerShip for projectile smoke: %s" % projectile_scene_path)
	else:
		var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
		var target_ship: Node3D = null
		if is_instance_valid(spawner) and spawner.has_method("debug_spawn_ship"):
			target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 18.0, 0.0) as Node3D
			await _wait_frames(smoke_wait_frames_after_spawn)
		if not is_instance_valid(target_ship):
			_failures.append("projectile smoke target spawn failed: %s" % projectile_scene_path)
		else:
			var projectile_scene := load(projectile_scene_path) as PackedScene
			if projectile_scene == null:
				_failures.append("projectile scene load failed: %s" % projectile_scene_path)
			else:
				var projectile := projectile_scene.instantiate()
				if projectile == null:
					_failures.append("projectile scene instantiate failed: %s" % projectile_scene_path)
				else:
					if projectile_scene_path.ends_with("fire_pot.tscn"):
						projectile.team = "player"
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_ship.global_position
					elif projectile_scene_path.ends_with("ballista_bolt.tscn"):
						projectile.team = "player"
						projectile.direction = (target_ship.global_position - player_ship.global_position).normalized()
						if projectile.direction.length_squared() <= 0.0001:
							projectile.direction = Vector3.FORWARD
						projectile.position = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
					elif projectile_scene_path.ends_with("janggun_missile.tscn"):
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_ship.global_position
						projectile.team = "player"
						projectile.janggun_lv = 1
					elif projectile_scene_path.ends_with("singigeon_rocket.tscn"):
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_ship.global_position
						projectile.launch_direction = (target_ship.global_position - player_ship.global_position).normalized()
						projectile.team = "player"
						projectile.shooter = player_ship

					var before_projectiles := EntityRegistry.count_projectiles()
					smoke_root.add_child(projectile)
					await _wait_frames(smoke_wait_frames_after_attach)
					if projectile.has_method("set_team"):
						projectile.set_team("player")
					elif projectile.get("team") != null:
						projectile.set("team", "player")
					var projectile_team_variant: Variant = projectile.get("team")
					var projectile_team: String = "player" if projectile_team_variant == null else str(projectile_team_variant)
					if projectile_team != "player":
						_failures.append("projectile team contract failed: %s" % projectile_scene_path)
					_configure_projectile_smoke(projectile, projectile_scene_path, player_ship, target_ship)
					await _wait_frames(smoke_wait_frames_after_spawn)
					var after_projectiles := EntityRegistry.count_projectiles()
					if after_projectiles <= before_projectiles:
						_failures.append("projectile did not register in entity registry: %s" % projectile_scene_path)

	smoke_root.queue_free()
	await _wait_frames(1)


func _configure_projectile_smoke(projectile: Node, projectile_scene_path: String, player_ship: Node3D, target_ship: Node3D) -> void:
	if projectile_scene_path.ends_with("cannonball.tscn"):
		if projectile.has_method("launch"):
			projectile.call(
				"launch",
				player_ship.global_position + Vector3(0.0, 1.2, 0.0),
				"player",
				-target_ship.global_transform.basis.z,
				target_ship,
				12.0,
				1.0,
				"roundshot"
			)
	elif projectile_scene_path.ends_with("arrow.tscn"):
		if projectile.has_method("launch"):
			projectile.call(
				"launch",
				player_ship.global_position + Vector3(0.0, 1.0, 0.0),
				target_ship.global_position,
				target_ship,
				"player",
				9.0,
				"bow",
				24.0,
				2.0
			)
	elif projectile_scene_path.ends_with("fire_pot.tscn"):
		if projectile.has_method("setup_flight"):
			projectile.call("setup_flight", projectile.start_pos, projectile.target_pos, 0.8, 3.5)


func _validate_registry_smoke(player_ship: Node3D, label: String) -> void:
	if not is_instance_valid(player_ship):
		return

	var player_lookup: Node = EntityRegistry.get_first_ship_by_team("player")
	if player_lookup != player_ship:
		_failures.append("%s smoke player ship registry lookup mismatch" % label)

	if EntityRegistry.count_ships_by_team("player") <= 0:
		_failures.append("%s smoke player ship team bucket is empty" % label)

	if EntityRegistry.count_soldiers_by_team("player") <= 0:
		_failures.append("%s smoke player soldier bucket is empty" % label)

	var enemy_ships: Array = EntityRegistry.get_ships_by_team("enemy")
	if enemy_ships.is_empty():
		_failures.append("%s smoke enemy ship team bucket is empty" % label)
		return

	var boss_count := 0
	for ship in enemy_ships:
		if is_instance_valid(ship) and ship.is_in_group("boss"):
			boss_count += 1
	if boss_count <= 0:
		_failures.append("%s smoke boss ship did not enter the enemy team bucket" % label)


func _validate_spawned_boss(spawned_boss: Node3D, label: String) -> void:
	if not is_instance_valid(spawned_boss):
		_failures.append("%s spawn returned null" % label)
		return
	var boss_team := str(spawned_boss.get("team"))
	if boss_team != "enemy":
		_failures.append("%s team contract failed: %s" % [label, boss_team])
	if not spawned_boss.is_in_group("boss"):
		_failures.append("%s is missing boss group tag" % label)
	var registered_enemy := EntityRegistry.get_ships_by_team("enemy").has(spawned_boss)
	if not registered_enemy:
		_failures.append("%s instance was not registered in enemy team bucket" % label)


func _validate_spawned_ship(spawned_ship: Node3D, label: String) -> void:
	if not is_instance_valid(spawned_ship):
		_failures.append("%s spawn returned null" % label)
		return
	var ship_team := str(spawned_ship.get("team"))
	if ship_team != "enemy":
		_failures.append("%s team contract failed: %s" % [label, ship_team])
	if not spawned_ship.is_in_group("ships"):
		_failures.append("%s is missing ships group tag" % label)
	var registered_enemy := EntityRegistry.get_ships_by_team("enemy").has(spawned_ship)
	if not registered_enemy:
		_failures.append("%s instance was not registered in enemy team bucket" % label)


func _report_and_quit() -> void:
	if _failures.is_empty():
		print("[ContractSweep] passed scripts=%d scenes=%d" % [_loaded_scripts, _loaded_scenes])
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("[ContractSweep] %s" % failure)
	print("[ContractSweep] failed scripts=%d scenes=%d issues=%d" % [_loaded_scripts, _loaded_scenes, _failures.size()])
	get_tree().quit(1)


func _wait_frames(count: int) -> void:
	for _i in range(max(0, count)):
		await get_tree().process_frame
