extends Node

const ProjectContractTypographyHelper = preload("res://scripts/test/project_contract_typography_helper.gd")
const ResponsiveUiContractLogic = preload("res://scripts/test/responsive_ui_contract_logic.gd")
const ScreenEdgeFxContractLogic = preload("res://scripts/test/screen_edge_fx_contract_logic.gd")


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
@export var smoke_run_upgrade_contract: bool = true
@export var smoke_run_typography_contract: bool = true
@export var smoke_run_responsive_ui_contract: bool = true
@export var smoke_run_screen_edge_fx_contract: bool = true

var _failures: Array[String] = []
var _loaded_scripts: int = 0
var _loaded_scenes: int = 0


func _ready() -> void:
	call_deferred("_run_contract_checks")


func _run_contract_checks() -> void:
	_loaded_scripts = ProjectContractScanHelper.scan_resource_roots(script_roots, ".gd", _failures)
	ProjectContractScanHelper.scan_legacy_godot3_patterns(script_roots, _failures)
	_loaded_scenes = ProjectContractScanHelper.scan_resource_roots(scene_roots, ".tscn", _failures)
	await _run_runtime_smoke()
	if smoke_run_save_contract:
		_run_save_contract_smoke()
	if smoke_run_upgrade_contract:
		_run_upgrade_contract_smoke()
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
	if smoke_run_typography_contract:
		await _run_typography_contract_smoke()
	if smoke_run_responsive_ui_contract:
		await _run_responsive_ui_contract_smoke()
	if smoke_run_screen_edge_fx_contract:
		await _run_screen_edge_fx_contract_smoke()
	_report_and_quit()


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


func _run_upgrade_contract_smoke() -> void:
	ProjectContractUpgradeHelper.run_upgrade_contract_smoke(_failures)


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


func _run_typography_contract_smoke() -> void:
	await ProjectContractTypographyHelper.run_typography_contract_smoke(
		self,
		_failures,
		smoke_scene_path,
		smoke_wait_frames_after_attach
	)


func _run_screen_edge_fx_contract_smoke() -> void:
	await ScreenEdgeFxContractLogic.run_contract(self, _failures)


func _run_responsive_ui_contract_smoke() -> void:
	await ResponsiveUiContractLogic.run_contract(self, _failures)


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
