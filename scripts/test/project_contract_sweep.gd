extends Node

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")

@export var script_roots: Array[String] = ["res://scripts"]
@export var scene_roots: Array[String] = ["res://scenes"]
@export var smoke_scene_path: String = "res://scenes/test/preview_base.tscn"
@export var smoke_wait_frames_after_attach: int = 2
@export var smoke_wait_frames_after_spawn: int = 3
@export var smoke_spawn_boss: bool = true
@export var smoke_spawn_final_boss: bool = true

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

	if not smoke_spawn_boss and not smoke_spawn_final_boss:
		_failures.append("no boss smoke mode enabled")
		return

	if smoke_spawn_boss:
		await _run_single_smoke_pass(packed, "debug_spawn_mid_boss", "mid boss")
	if smoke_spawn_final_boss:
		await _run_single_smoke_pass(packed, "debug_spawn_final_boss", "final boss")


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
