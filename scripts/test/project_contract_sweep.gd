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
	if not is_instance_valid(SaveManager):
		_failures.append("SaveManager autoload is not available for save smoke")
		return

	var save_path := "user://save_data.cfg"
	var backup_path := "user://save_data.backup.cfg"
	var save_backup := _capture_file_bytes(save_path)
	var backup_backup := _capture_file_bytes(backup_path)
	var snapshot := _capture_save_manager_state()
	var expected := {
		"gold": 1234,
		"meta_upgrades": {"hull_hp": 3, "sailing": 2},
		"items": ["choyogi", "ilseongjeongsiui"],
		"settings": {
			"master_volume": 0.12,
			"music_volume": 0.34,
			"sfx_volume": 0.56,
			"ui_volume": 0.78,
			"fullscreen": false,
		},
	}

	_apply_save_manager_state(expected)
	SaveManager.save_game()

	var loaded_main := ConfigFile.new()
	if loaded_main.load(save_path) != OK:
		_failures.append("save smoke could not reload main save file")
	else:
		_validate_save_config(loaded_main, expected, "main save smoke")

	var loaded_backup := ConfigFile.new()
	if loaded_backup.load(backup_path) != OK:
		_failures.append("save smoke could not reload backup save file")
	else:
		_validate_save_config(loaded_backup, expected, "backup save smoke")

	_apply_save_manager_state({
		"gold": 1,
		"meta_upgrades": {"wrong": 99},
		"items": ["wrong"],
		"settings": {},
	})
	SaveManager.load_game()
	_validate_save_manager_state(expected, "save smoke roundtrip")

	_restore_save_manager_state(snapshot)
	_restore_file_bytes(save_path, save_backup)
	_restore_file_bytes(backup_path, backup_backup)


func _run_hud_contract_smoke() -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		_failures.append("hud smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		_failures.append("hud smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(smoke_wait_frames_after_attach)

	var hud: Node = smoke_root.get_node_or_null("GameHUD")
	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(hud):
		_failures.append("preview base is missing GameHUD for hud smoke")
	if not is_instance_valid(player_ship):
		_failures.append("preview base is missing PlayerShip for hud smoke")
	if not is_instance_valid(spawner):
		_failures.append("preview base is missing EnemySpawner for hud smoke")
	if _failures.size() > 0:
		smoke_root.queue_free()
		await _wait_frames(1)
		return

	var target_ship: Node3D = null
	if spawner.has_method("debug_spawn_ship"):
		target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 12.0, 0.0) as Node3D
		await _wait_frames(smoke_wait_frames_after_spawn)
	if not is_instance_valid(target_ship):
		_failures.append("hud smoke target spawn failed")
		smoke_root.queue_free()
		await _wait_frames(1)
		return

	target_ship.global_position = player_ship.global_position + Vector3(0.0, 0.0, 9.0)
	if target_ship.has_method("set_team"):
		target_ship.call("set_team", "enemy")
	elif target_ship.get("team") != null:
		target_ship.set("team", "enemy")
	target_ship.set("is_derelict", false)
	if target_ship.get("is_sinking") != null:
		target_ship.set("is_sinking", false)
	if target_ship.get("is_dying") != null:
		target_ship.set("is_dying", false)

	_run_hud_state_baselines(hud, player_ship)
	_run_hud_boarding_state_check(hud, player_ship, target_ship)
	_run_hud_capture_state_check(hud, player_ship)
	_run_hud_debug_state_check(hud, player_ship)

	smoke_root.queue_free()
	await _wait_frames(1)


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


func _has_hull_child(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	for child in ship.get_children():
		if child is Node and str(child.name).contains("Hull"):
			return true
	return false


func _run_hud_state_baselines(hud: Node, player_ship: Node3D) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship):
		return
	player_ship.set("is_boarding", false)
	player_ship.set("boarding_prep_timer", 0.0)
	player_ship.set("boarding_prep_duration", 2.5)
	player_ship.set("current_speed", 3.5)
	player_ship.set("max_speed", 8.0)
	player_ship.set("hull_hp", 143.0)
	player_ship.set("max_hull_hp", 200.0)
	player_ship.set("rowing_stamina", 44.0)
	player_ship.set("max_rowing_stamina", 100.0)
	if hud.has_method("update_level"):
		hud.call("update_level", 7)
	if hud.has_method("update_score"):
		hud.call("update_score", 99)
	if hud.has_method("update_crew_status"):
		hud.call("update_crew_status", 3, 6)
	if hud.has_method("_update_timer"):
		hud.call("_update_timer")
	if hud.has_method("_update_speed_display"):
		hud.call("_update_speed_display")
	if hud.has_method("_update_hull_display"):
		hud.call("_update_hull_display")
	if hud.has_method("_update_stamina_display"):
		hud.call("_update_stamina_display")
	if hud.has_method("_update_boarding_display"):
		hud.call("_update_boarding_display")
	if hud.has_method("_update_ship_health_bars"):
		hud.call("_update_ship_health_bars", false)
	if hud.has_method("_sync_ship_debug_panel_from_player"):
		hud.call("_sync_ship_debug_panel_from_player")
	if hud.has_method("_update_stat_panel"):
		hud.show_stat_panel = true
		hud.call("_update_stat_panel")
	_validate_hud_baseline_state(hud)


func _run_hud_boarding_state_check(hud: Node, player_ship: Node3D, target_ship: Node3D) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship) or not is_instance_valid(target_ship):
		return
	player_ship.set("is_boarding", true)
	player_ship.set("boarding_target", target_ship)
	player_ship.set("boarding_prep_timer", 0.5)
	player_ship.set("boarding_prep_duration", 2.0)
	if hud.has_method("_update_boarding_display"):
		hud.call("_update_boarding_display")
	if not is_instance_valid(hud.boarding_ui) or not hud.boarding_ui.visible:
		_failures.append("hud smoke boarding ui was not visible")
	if not is_instance_valid(hud.boarding_label) or hud.boarding_label.text != "도선 준비 중 (밧줄 고정)...":
		_failures.append("hud smoke boarding label mismatch")
	player_ship.set("boarding_prep_timer", 2.1)
	if hud.has_method("_update_boarding_display"):
		hud.call("_update_boarding_display")
	if is_instance_valid(hud.boarding_label) and hud.boarding_label.text != "도선 진행 중!":
		_failures.append("hud smoke boarding progress label mismatch")


func _run_hud_capture_state_check(hud: Node, player_ship: Node3D) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship):
		return
	player_ship.set("is_boarding", false)
	player_ship.set("boarding_target", null)
	var target_ship: Node3D = null
	if hud.get_tree():
		var all_enemies := EntityRegistry.get_ships_by_team("enemy")
		if not all_enemies.is_empty():
			target_ship = all_enemies[0] as Node3D
	if is_instance_valid(target_ship):
		target_ship.set("is_derelict", true)
	if hud.has_method("_update_capture_opportunity_display"):
		hud.call("_update_capture_opportunity_display")
	if not is_instance_valid(hud.capture_opportunity_label) or not hud.capture_opportunity_label.visible:
		_failures.append("hud smoke capture label was not visible")
	if is_instance_valid(hud.capture_opportunity_label) and hud.capture_opportunity_label.text != "폐선 확보 가능":
		_failures.append("hud smoke capture label mismatch")
	if hud.has_method("_update_distance_debug_display"):
		hud.call("_toggle_distance_debug")
		hud.call("_update_distance_debug_display")
	if not is_instance_valid(hud.debug_distance_label) or not hud.debug_distance_label.visible:
		_failures.append("hud smoke distance label was not visible")
	elif not hud.debug_distance_label.text.contains("거리"):
		_failures.append("hud smoke distance label mismatch")


func _run_hud_debug_state_check(hud: Node, player_ship: Node3D) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player_ship):
		return
	player_ship.set("is_sinking", true)
	if hud.has_method("_sync_ship_debug_panel_from_player"):
		hud.call("_sync_ship_debug_panel_from_player")
	if is_instance_valid(hud.debug_ship_status_value) and not hud.debug_ship_status_value.text.contains("선체"):
		_failures.append("hud smoke ship debug status text mismatch")
	if is_instance_valid(hud.debug_ship_config_value) and not hud.debug_ship_config_value.text.contains("설정"):
		_failures.append("hud smoke ship debug config text mismatch")
	player_ship.set("is_sinking", false)
	player_ship.set("is_dying", false)
	if hud.has_method("_update_ship_health_bars"):
		hud.call("_update_ship_health_bars", false)
	if is_instance_valid(hud.hp_text_label) and hud.hp_text_label.text != "HP 143 / 200":
		_failures.append("hud smoke HP label mismatch")
	if is_instance_valid(hud.speed_bar_label) and hud.speed_bar_label.text != "3.5":
		_failures.append("hud smoke speed label mismatch")


func _validate_hud_baseline_state(hud: Node) -> void:
	if is_instance_valid(hud.boarding_ui) and hud.boarding_ui.visible:
		_failures.append("hud smoke baseline boarding ui should be hidden")
	if is_instance_valid(hud.capture_opportunity_label) and hud.capture_opportunity_label.visible:
		_failures.append("hud smoke baseline capture label should be hidden")
	if is_instance_valid(hud.debug_distance_label) and hud.debug_distance_label.visible:
		_failures.append("hud smoke baseline distance label should be hidden")
	if is_instance_valid(hud.debug_ship_status_value) and not hud.debug_ship_status_value.text.contains("선체"):
		_failures.append("hud smoke ship debug status was not populated")
	if is_instance_valid(hud.debug_ship_config_value) and not hud.debug_ship_config_value.text.contains("설정"):
		_failures.append("hud smoke ship debug config was not populated")
	if is_instance_valid(hud.stat_content) and hud.stat_content.get_child_count() <= 0:
		_failures.append("hud smoke stat panel was not populated")


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


func _capture_save_manager_state() -> Dictionary:
	return {
		"gold": SaveManager.gold,
		"meta_upgrades": SaveManager.meta_upgrades.duplicate(true),
		"items": SaveManager.get_items(),
		"settings": _capture_settings_snapshot(),
	}


func _capture_settings_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for key in ["master_volume", "music_volume", "sfx_volume", "ui_volume", "fullscreen"]:
		snapshot[key] = SaveManager.get_setting(key)
	return snapshot


func _apply_save_manager_state(state: Dictionary) -> void:
	SaveManager.gold = int(state.get("gold", 0))
	SaveManager.meta_upgrades = {}
	var meta_upgrades_value = state.get("meta_upgrades", {})
	if meta_upgrades_value is Dictionary:
		SaveManager.meta_upgrades = meta_upgrades_value.duplicate(true)
	SaveManager.items = []
	var items_value = state.get("items", [])
	if items_value is Array:
		for item_id in items_value:
			SaveManager.items.append(str(item_id))
	var settings_value = state.get("settings", {})
	SaveManager.settings = {}
	if settings_value is Dictionary:
		SaveManager.settings = settings_value.duplicate(true)


func _restore_save_manager_state(snapshot: Dictionary) -> void:
	_apply_save_manager_state(snapshot)


func _validate_save_manager_state(expected: Dictionary, label: String) -> void:
	if SaveManager.gold != int(expected.get("gold", 0)):
		_failures.append("%s gold mismatch" % label)
	if SaveManager.meta_upgrades != expected.get("meta_upgrades", {}):
		_failures.append("%s meta upgrade mismatch" % label)
	if SaveManager.get_items() != expected.get("items", []):
		_failures.append("%s items mismatch" % label)
	var expected_settings: Dictionary = expected.get("settings", {})
	for key in expected_settings.keys():
		if SaveManager.get_setting(str(key)) != expected_settings[key]:
			_failures.append("%s setting mismatch for %s" % [label, key])


func _validate_save_config(config: ConfigFile, expected: Dictionary, label: String) -> void:
	var expected_gold: int = int(expected.get("gold", 0))
	var expected_meta_upgrades: Dictionary = expected.get("meta_upgrades", {})
	var expected_items: Array = expected.get("items", [])
	var expected_settings: Dictionary = expected.get("settings", {})

	if int(config.get_value("player", "gold", -1)) != expected_gold:
		_failures.append("%s gold mismatch" % label)

	var loaded_meta_upgrades = config.get_value("player", "meta_upgrades", {})
	if loaded_meta_upgrades != expected_meta_upgrades:
		_failures.append("%s meta upgrade mismatch" % label)

	var loaded_items = config.get_value("player", "items", [])
	if loaded_items != expected_items:
		_failures.append("%s items mismatch" % label)

	var loaded_settings = config.get_value("player", "settings", {})
	if not (loaded_settings is Dictionary):
		_failures.append("%s settings payload mismatch" % label)
	else:
		for key in expected_settings.keys():
			if loaded_settings.get(key) != expected_settings[key]:
				_failures.append("%s setting mismatch for %s" % [label, key])


func _capture_file_bytes(path: String) -> Dictionary:
	var payload := {"exists": false, "bytes": PackedByteArray()}
	if not FileAccess.file_exists(path):
		return payload
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return payload
	payload["exists"] = true
	payload["bytes"] = file.get_buffer(file.get_length())
	file.close()
	return payload


func _restore_file_bytes(path: String, payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var existed := bool(payload.get("exists", false))
	var bytes: PackedByteArray = payload.get("bytes", PackedByteArray())
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_failures.append("failed to restore file: %s" % path)
			return
		file.store_buffer(bytes)
		file.close()
	elif FileAccess.file_exists(path):
		var remove_err := DirAccess.remove_absolute(path)
		if remove_err != OK:
			_failures.append("failed to remove temp save file: %s" % path)


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
