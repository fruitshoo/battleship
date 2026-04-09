extends Node

const ProjectContractBootstrapHelper = preload("res://scripts/test/project_contract_bootstrap_helper.gd")
const ProjectContractHudHelper = preload("res://scripts/test/project_contract_hud_helper.gd")
const ProjectContractRecoveryHelper = preload("res://scripts/test/project_contract_recovery_helper.gd")
const ProjectContractRuntimeHelper = preload("res://scripts/test/project_contract_runtime_helper.gd")
const ProjectContractSaveHelper = preload("res://scripts/test/project_contract_save_helper.gd")
const ProjectContractSceneWiringHelper = preload("res://scripts/test/project_contract_scene_wiring_helper.gd")
const ProjectContractSupportHelper = preload("res://scripts/test/project_contract_support_helper.gd")

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
		{"pattern": "bool(", "label": "bool() constructor"},
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
	await ProjectContractRuntimeHelper.run_runtime_smoke(
		self,
		_failures,
		smoke_scene_path,
		smoke_wait_frames_after_attach,
		smoke_wait_frames_after_spawn,
		smoke_spawn_boss,
		smoke_spawn_final_boss,
		smoke_spawn_ship_types,
		smoke_spawn_launcher_scenes,
		smoke_spawn_projectile_scenes
	)


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
	await ProjectContractSceneWiringHelper.run_scene_wiring_contract_smoke(
		self,
		_failures,
		smoke_wait_frames_after_attach
	)


func _run_support_fleet_contract_smoke() -> void:
	await ProjectContractSupportHelper.run_support_fleet_contract_smoke(
		self,
		_failures,
		smoke_scene_path,
		smoke_wait_frames_after_attach,
		smoke_wait_frames_after_spawn
	)


func _run_bootstrap_contract_smoke() -> void:
	await ProjectContractBootstrapHelper.run_bootstrap_contract_smoke(
		self,
		_failures,
		smoke_scene_path,
		smoke_wait_frames_after_attach
	)


func _run_recovery_effect_contract_smoke() -> void:
	await ProjectContractRecoveryHelper.run_recovery_effect_contract_smoke(
		self,
		_failures,
		smoke_scene_path,
		smoke_wait_frames_after_attach
	)


func _report_and_quit() -> void:
	if _failures.is_empty():
		print("[ContractSweep] passed scripts=%d scenes=%d" % [_loaded_scripts, _loaded_scenes])
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("[ContractSweep] %s" % failure)
	print("[ContractSweep] failed scripts=%d scenes=%d issues=%d" % [_loaded_scripts, _loaded_scenes, _failures.size()])
	get_tree().quit(1)

