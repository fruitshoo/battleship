extends Node3D

const PLAYER_SHIP_SCENE := preload("res://scenes/ships/player_ship.tscn")
const ENEMY_BASE_SCENE := preload("res://scenes/ships/enemy_ship.tscn")
const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")
const ENEMY_GUNNER_SCENE := preload("res://scenes/ships/enemy_gunner_ship.tscn")
const ENEMY_FIREPOT_SCENE := preload("res://scenes/ships/enemy_firepot_ship.tscn")
const BOSS_SCENE := preload("res://scenes/ships/boss_ship.tscn")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const PlayerShipCrewHelper = preload("res://scripts/entities/ships/player_ship_crew_helper.gd")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var scenario_time_limit_seconds: float = 18.0
@export var intermission_seconds: float = 0.5
@export var auto_print_summary: bool = true
@export var auto_quit_delay_seconds: float = 0.05
@export var player_support_limit: int = 0

var _overlay_panel: PanelContainer = null
var _overlay_label: Label = null
var _overlay_refresh_left: float = 0.0
var _scenario_defs: Array[Dictionary] = []
var _scenario_results: Array[Dictionary] = []
var _current_scenario_index: int = -1
var _current_scenario_started_usec: int = 0
var _current_scenario_elapsed: float = 0.0
var _current_player_ship: Node3D = null
var _current_enemy_ship: Node3D = null
var _scenario_running: bool = false
var _sequence_finished: bool = false


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(delta: float) -> void:
	if not _scenario_running:
		return
	_current_scenario_elapsed = (Time.get_ticks_usec() - _current_scenario_started_usec) / 1000000.0
	_overlay_refresh_left = maxf(0.0, _overlay_refresh_left - delta)
	if _overlay_refresh_left <= 0.0:
		_overlay_refresh_left = 0.2
		_update_overlay()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_ensure_overlay()
	_scenario_defs = _build_scenarios()
	await _run_scenarios()


func _build_scenarios() -> Array[Dictionary]:
	return [
		{
			"name": "Gunner Duel",
			"enemy_scene": ENEMY_GUNNER_SCENE,
			"distance": 15.0,
			"enemy_lateral_offset": 0.0,
		},
		{
			"name": "Melee Rush",
			"enemy_scene": ENEMY_MELEE_SCENE,
			"distance": 8.0,
			"enemy_lateral_offset": 3.0,
		},
		{
			"name": "Firepot Pressure",
			"enemy_scene": ENEMY_FIREPOT_SCENE,
			"distance": 10.0,
			"enemy_lateral_offset": -3.5,
		},
		{
			"name": "Mixed Pressure",
			"enemy_scene": ENEMY_BASE_SCENE,
			"distance": 12.5,
			"enemy_lateral_offset": 0.0,
		},
		{
			"name": "Atakebune Boarding",
			"enemy_scene": BOSS_SCENE,
			"distance": 9.5,
			"enemy_lateral_offset": 6.0,
			"enemy_rotation_offset_deg": 90.0,
			"time_limit": 24.0,
			"disable_player_weapons": true,
			"disable_enemy_weapons": true,
			"force_player_auto_raid": true,
			"player_auto_raid_max_boarders": 4,
			"player_auto_raid_min_defenders": 1,
			"player_auto_raid_eval_interval": 0.12,
		},
		{
			"name": "Head-on Cleanup",
			"enemy_scene": ENEMY_MELEE_SCENE,
			"distance": 8.0,
			"enemy_lateral_offset": 0.0,
			"time_limit": 16.0,
			"disable_player_weapons": true,
			"disable_enemy_weapons": true,
			"player_alive_crew_limit": 1,
		},
		{
			"name": "Cleanup Drift",
			"enemy_scene": ENEMY_MELEE_SCENE,
			"distance": 8.5,
			"enemy_lateral_offset": 2.8,
			"time_limit": 16.0,
			"disable_player_weapons": true,
			"disable_enemy_weapons": true,
			"player_alive_crew_limit": 0,
		},
	]


func _run_scenarios() -> void:
	_scenario_results.clear()
	for scenario_index in range(_scenario_defs.size()):
		var scenario: Dictionary = _scenario_defs[scenario_index]
		_current_scenario_index = scenario_index
		await _setup_scenario(scenario)
		_current_scenario_started_usec = Time.get_ticks_usec()
		_current_scenario_elapsed = 0.0
		_scenario_running = true
		_update_overlay()
		if auto_print_summary:
			print("[ShipCombat] start scenario=%s enemy_scene=%s distance=%.1f" % [
				str(scenario.get("name", "Scenario")),
				_get_scene_name(scenario.get("enemy_scene", null)),
				float(scenario.get("distance", 0.0)),
			])

		while _scenario_running:
			await get_tree().process_frame
			_current_scenario_elapsed = (Time.get_ticks_usec() - _current_scenario_started_usec) / 1000000.0
			if _is_current_scenario_finished():
				var result := _build_current_result()
				_scenario_results.append(result)
				_scenario_running = false
				_update_overlay()
				if auto_print_summary:
					print("[ShipCombat] scenario=%s winner=%s elapsed=%.2f player_hull=%.1f enemy_hull=%.1f player_crew=%d enemy_crew=%d player_derelict=%s enemy_derelict=%s" % [
						str(result.get("name", "Scenario")),
						str(result.get("winner", "draw")),
						float(result.get("elapsed", 0.0)),
						float(result.get("player_hull", 0.0)),
						float(result.get("enemy_hull", 0.0)),
						int(result.get("player_crew", 0)),
						int(result.get("enemy_crew", 0)),
						"Y" if result.get("player_derelict", false) == true else "N",
						"Y" if result.get("enemy_derelict", false) == true else "N",
					])

		if scenario_index < _scenario_defs.size() - 1 and intermission_seconds > 0.0:
			await get_tree().create_timer(intermission_seconds).timeout

	_sequence_finished = true
	_report_summary()
	if _should_auto_quit_after_report():
		call_deferred("_quit_after_report")


func _setup_scenario(scenario: Dictionary) -> void:
	await _clear_existing_preview_nodes()
	_spawn_fresh_ships(scenario)
	await get_tree().process_frame
	_reset_player_ship_runtime()
	_configure_player_runtime(scenario)
	_configure_enemy_runtime(scenario)
	await get_tree().process_frame
	_update_overlay()


func _clear_existing_preview_nodes() -> void:
	for projectile in EntityRegistry.get_projectiles():
		if is_instance_valid(projectile):
			projectile.queue_free()
	for child in get_children():
		if child == get_node_or_null("PlayerShip"):
			continue
		if child is Node3D and (
			child.name == "PlayerShip"
			or child.has_meta("ship_combat_preview_spawn")
			or child.get_meta("support_fleet_ship", false) == true
			or child.is_in_group("captured_minion")
		):
			_archive_preview_node(child)
	await get_tree().process_frame


func _spawn_fresh_ships(scenario: Dictionary) -> void:
	_current_player_ship = get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(_current_player_ship):
		_current_player_ship = PLAYER_SHIP_SCENE.instantiate() as Node3D
		if is_instance_valid(_current_player_ship):
			_current_player_ship.name = "PlayerShip"
			_current_player_ship.set_meta("ship_combat_preview_spawn", true)
			add_child(_current_player_ship)

	if is_instance_valid(_current_player_ship):
		_current_player_ship.global_position = Vector3(-1.7, 0.0, 15.7)
		_current_player_ship.rotation = Vector3.ZERO

	var enemy_scene: PackedScene = scenario.get("enemy_scene", ENEMY_BASE_SCENE)
	_current_enemy_ship = enemy_scene.instantiate() as Node3D
	if is_instance_valid(_current_enemy_ship):
		_current_enemy_ship.name = "CombatPreviewEnemy"
		_current_enemy_ship.set_meta("ship_combat_preview_spawn", true)
		add_child(_current_enemy_ship)

		var distance: float = float(scenario.get("distance", 12.0))
		var lateral: float = float(scenario.get("enemy_lateral_offset", 0.0))
		var forward := -_current_player_ship.global_basis.z.normalized()
		var right := _current_player_ship.global_basis.x.normalized()
		_current_enemy_ship.global_position = _current_player_ship.global_position + forward * distance + right * lateral
		_current_enemy_ship.look_at(_current_player_ship.global_position, Vector3.UP)
		var rot_offset_deg: float = float(scenario.get("enemy_rotation_offset_deg", 0.0))
		if absf(rot_offset_deg) > 0.01:
			_current_enemy_ship.rotate_y(deg_to_rad(rot_offset_deg))
		PreviewHarnessHelper.assign_preview_target(_current_enemy_ship, _current_player_ship)


func _archive_preview_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Node3D:
		var spatial := node as Node3D
		spatial.visible = false
		spatial.global_position = Vector3(0.0, -500.0, 0.0)
	node.set_meta("ship_combat_preview_archived", true)


func _reset_player_ship_runtime() -> void:
	if not is_instance_valid(_current_player_ship):
		return
	if "hull_hp" in _current_player_ship and "max_hull_hp" in _current_player_ship:
		_current_player_ship.set("hull_hp", float(_current_player_ship.get("max_hull_hp")))
	if "current_speed" in _current_player_ship:
		_current_player_ship.set("current_speed", 0.0)
	if "rudder_angle" in _current_player_ship:
		_current_player_ship.set("rudder_angle", 0.0)
	if "sail_angle" in _current_player_ship:
		_current_player_ship.set("sail_angle", 0.0)
	if "is_sinking" in _current_player_ship:
		_current_player_ship.set("is_sinking", false)
	if "is_dying" in _current_player_ship:
		_current_player_ship.set("is_dying", false)
	if "is_burning" in _current_player_ship:
		_current_player_ship.set("is_burning", false)
	if "is_derelict" in _current_player_ship:
		_current_player_ship.set("is_derelict", false)
	if "is_boarding" in _current_player_ship:
		_current_player_ship.set("is_boarding", false)
	if "boarding_target" in _current_player_ship:
		_current_player_ship.set("boarding_target", null)
	if "boarding_timer" in _current_player_ship:
		_current_player_ship.set("boarding_timer", 0.0)
	if "boarding_prep_timer" in _current_player_ship:
		_current_player_ship.set("boarding_prep_timer", 0.0)
	if "crew_respawn_timer" in _current_player_ship:
		_current_player_ship.set("crew_respawn_timer", 0.0)
	if _current_player_ship.has_method("clear_boarding_attacker_ship"):
		_current_player_ship.call("clear_boarding_attacker_ship")
	if _current_player_ship.has_method("set_preview_deck_state"):
		_current_player_ship.call("set_preview_deck_state", false, false)
	if _current_player_ship.has_method("_sync_player_crew_roster"):
		_current_player_ship.call("_sync_player_crew_roster")
	if _current_player_ship.has_method("check_derelict_status"):
		_current_player_ship.call("check_derelict_status")


func _configure_player_runtime(scenario: Dictionary) -> void:
	if not is_instance_valid(_current_player_ship):
		return
	if "support_fleet_limit" in _current_player_ship:
		_current_player_ship.set("support_fleet_limit", player_support_limit)
	if "support_fleet_respawn_interval" in _current_player_ship:
		_current_player_ship.set("support_fleet_respawn_interval", 99999.0)
	if "support_fleet_respawn_timer" in _current_player_ship:
		_current_player_ship.set("support_fleet_respawn_timer", 0.0)
	if "captain_count" in _current_player_ship:
		_current_player_ship.set("captain_count", 0)
	if "crew_respawn_interval" in _current_player_ship:
		_current_player_ship.set("crew_respawn_interval", 99999.0)
	if "crew_respawn_timer" in _current_player_ship:
		_current_player_ship.set("crew_respawn_timer", 0.0)
	if "auto_raid_enabled" in _current_player_ship:
		_current_player_ship.set("auto_raid_enabled", scenario.get("force_player_auto_raid", false) == true)
	if "auto_raid_max_boarders" in _current_player_ship:
		_current_player_ship.set("auto_raid_max_boarders", int(scenario.get("player_auto_raid_max_boarders", 2)))
	if "auto_raid_min_defenders" in _current_player_ship:
		_current_player_ship.set("auto_raid_min_defenders", int(scenario.get("player_auto_raid_min_defenders", 3)))
	if "auto_raid_eval_interval" in _current_player_ship:
		_current_player_ship.set("auto_raid_eval_interval", float(scenario.get("player_auto_raid_eval_interval", 0.35)))
	if "auto_raid_eval_timer" in _current_player_ship:
		_current_player_ship.set("auto_raid_eval_timer", 0.0)
	if "auto_raid_target" in _current_player_ship:
		_current_player_ship.set("auto_raid_target", null)
	if "is_rowing" in _current_player_ship:
		_current_player_ship.set("is_rowing", false)
	if scenario.get("disable_player_weapons", false) == true:
		_set_ship_launcher_detection_range(_current_player_ship, 0.0)
	if _current_player_ship.has_method("set_preview_deck_state"):
		_current_player_ship.call("set_preview_deck_state", false, false)
	_apply_player_crew_limit(int(scenario.get("player_alive_crew_limit", -1)))


func _apply_player_crew_limit(alive_limit: int) -> void:
	if alive_limit < 0 or not is_instance_valid(_current_player_ship):
		return
	var survivors: Array = []
	for soldier in EntityRegistry.get_soldiers_by_ship(_current_player_ship):
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("is_player_team_soldier") and not soldier.is_player_team_soldier():
			continue
		survivors.append(soldier)
	if survivors.size() <= alive_limit:
		return
	for index in range(alive_limit, survivors.size()):
		survivors[index].queue_free()


func _configure_enemy_runtime(scenario: Dictionary) -> void:
	if not is_instance_valid(_current_enemy_ship):
		return
	if scenario.get("disable_enemy_weapons", false) == true:
		_set_ship_launcher_detection_range(_current_enemy_ship, 0.0)
	if _current_enemy_ship.has_method("set_preview_deck_state"):
		_current_enemy_ship.call("set_preview_deck_state", false, false)


func _set_ship_launcher_detection_range(ship: Node, detection_range: float) -> void:
	if not is_instance_valid(ship):
		return
	for child in ship.get_children():
		if "detection_range" in child:
			child.set("detection_range", detection_range)
		_set_ship_launcher_detection_range(child, detection_range)


func _is_current_scenario_finished() -> bool:
	if not is_instance_valid(_current_player_ship) or not is_instance_valid(_current_enemy_ship):
		return true
	if _is_ship_out(_current_player_ship):
		return true
	if _is_ship_out(_current_enemy_ship):
		return true
	return _current_scenario_elapsed >= _get_current_scenario_time_limit()


func _is_ship_out(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return true
	if ship.has_method("is_combat_disabled") and ship.call("is_combat_disabled") == true:
		return true
	if ship.has_method("is_derelict_ship") and ship.call("is_derelict_ship") == true:
		return true
	if _get_ship_hull(ship) <= 0.0:
		return true
	return false


func _build_current_result() -> Dictionary:
	var scenario: Dictionary = {}
	if _current_scenario_index >= 0 and _current_scenario_index < _scenario_defs.size():
		scenario = _scenario_defs[_current_scenario_index]

	var player_hull := _get_ship_hull(_current_player_ship)
	var enemy_hull := _get_ship_hull(_current_enemy_ship)
	var player_hull_ratio := _get_ship_hull_ratio(_current_player_ship)
	var enemy_hull_ratio := _get_ship_hull_ratio(_current_enemy_ship)
	var player_crew := _get_ship_crew(_current_player_ship)
	var enemy_crew := _get_ship_crew(_current_enemy_ship)
	var player_derelict := _is_derelict(_current_player_ship)
	var enemy_derelict := _is_derelict(_current_enemy_ship)
	var player_boarding := _is_boarding(_current_player_ship)
	var enemy_boarding := _is_boarding(_current_enemy_ship)
	var player_boarders_on_enemy := _count_boarders_from_home_to_target(_current_player_ship, _current_enemy_ship)
	var enemy_boarders_on_player := _count_boarders_from_home_to_target(_current_enemy_ship, _current_player_ship)
	var raid_debug: Dictionary = PlayerShipCrewHelper.get_auto_raid_debug_snapshot(_current_player_ship, _current_enemy_ship)

	var winner := "draw"
	if _is_ship_out(_current_enemy_ship) and not _is_ship_out(_current_player_ship):
		winner = "player"
	elif _is_ship_out(_current_player_ship) and not _is_ship_out(_current_enemy_ship):
		winner = "enemy"
	elif player_hull_ratio > enemy_hull_ratio + 0.05:
		winner = "player_hull_timeout"
	elif enemy_hull_ratio > player_hull_ratio + 0.05:
		winner = "enemy_hull_timeout"
	elif player_crew > enemy_crew:
		winner = "player_crew_timeout"
	elif enemy_crew > player_crew:
		winner = "enemy_crew_timeout"

	return {
		"name": str(scenario.get("name", "Scenario")),
		"elapsed": _current_scenario_elapsed,
		"player_hull": snappedf(player_hull, 0.1),
		"enemy_hull": snappedf(enemy_hull, 0.1),
		"player_hull_pct": snappedf(player_hull_ratio * 100.0, 0.1),
		"enemy_hull_pct": snappedf(enemy_hull_ratio * 100.0, 0.1),
		"player_crew": player_crew,
		"enemy_crew": enemy_crew,
		"player_derelict": player_derelict,
		"enemy_derelict": enemy_derelict,
		"player_boarding": player_boarding,
		"enemy_boarding": enemy_boarding,
		"player_boarders_on_enemy": player_boarders_on_enemy,
		"enemy_boarders_on_player": enemy_boarders_on_player,
		"raid_debug": raid_debug,
		"winner": winner,
	}


func _get_ship_hull(ship: Node3D) -> float:
	if not is_instance_valid(ship):
		return 0.0
	if ship.has_method("get_hull_hp_value"):
		return float(ship.call("get_hull_hp_value"))
	return float(ship.get("hull_hp")) if "hull_hp" in ship else 0.0


func _get_ship_hull_ratio(ship: Node3D) -> float:
	if not is_instance_valid(ship):
		return 0.0
	if ship.has_method("get_hull_ratio"):
		return float(ship.call("get_hull_ratio"))
	var hull: float = _get_ship_hull(ship)
	var max_hull: float = float(ship.get("max_hull_hp")) if "max_hull_hp" in ship else maxf(hull, 1.0)
	if max_hull <= 0.0:
		return 0.0
	return hull / max_hull


func _get_ship_crew(ship: Node3D) -> int:
	if not is_instance_valid(ship):
		return 0
	if ship.has_method("get_alive_crew_count"):
		return int(ship.call("get_alive_crew_count"))
	return 0


func _is_derelict(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("is_derelict_ship"):
		return ship.call("is_derelict_ship") == true
	return ship.get("is_derelict") == true if "is_derelict" in ship else false


func _is_boarding(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("is_boarding_ship"):
		return ship.call("is_boarding_ship") == true
	return ship.get("is_boarding") == true if "is_boarding" in ship else false


func _count_boarders_from_home_to_target(home_ship: Node3D, target_ship: Node3D) -> int:
	if not is_instance_valid(home_ship) or not is_instance_valid(target_ship):
		return 0
	var count: int = 0
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_dead_soldier") and soldier.is_dead_soldier():
			continue
		if soldier.has_method("get_home_ship_node") and soldier.get_home_ship_node() == home_ship:
			count += 1
	return count


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay_panel):
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return

	_overlay_panel = PanelContainer.new()
	_overlay_panel.name = "ShipCombatBalanceOverlay"
	_overlay_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay_panel.offset_left = 20.0
	_overlay_panel.offset_top = 20.0
	_overlay_panel.offset_right = 500.0
	_overlay_panel.offset_bottom = 180.0
	_overlay_panel.z_index = 100
	_overlay_panel.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 10, 1, 10.0, 8.0, 10.0, 8.0)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_overlay_panel.add_child(box)

	var title := Label.new()
	title.text = "Ship Combat Balance"
	NavalUiTheme.style_heading(title, 14)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "scenario / hull / crew / boarding / derelict"
	NavalUiTheme.style_muted(hint, 10)
	box.add_child(hint)

	_overlay_label = Label.new()
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_body(_overlay_label, 12)
	box.add_child(_overlay_label)

	hud.add_child(_overlay_panel)


func _update_overlay() -> void:
	if not is_instance_valid(_overlay_label):
		return
	var scenario_name := "Waiting"
	if _current_scenario_index >= 0 and _current_scenario_index < _scenario_defs.size():
		scenario_name = str(_scenario_defs[_current_scenario_index].get("name", scenario_name))
	var player_hull := _get_ship_hull(_current_player_ship)
	var enemy_hull := _get_ship_hull(_current_enemy_ship)
	var player_crew := _get_ship_crew(_current_player_ship)
	var enemy_crew := _get_ship_crew(_current_enemy_ship)
	var winner := "-"
	var raid_debug: Dictionary = PlayerShipCrewHelper.get_auto_raid_debug_snapshot(_current_player_ship, _current_enemy_ship)
	if _sequence_finished and not _scenario_results.is_empty():
		winner = str(_scenario_results[_scenario_results.size() - 1].get("winner", "-"))
	elif _scenario_running:
		winner = _get_live_winner_hint(player_hull, enemy_hull, player_crew, enemy_crew)
	var raid_line := ""
	if scenario_name == "Atakebune Boarding":
		raid_line = "\nraid valid:%s close:%s init:%s pressure:%d ranged:%d spare:%d desired:%d avail:%d" % [
			"Y" if raid_debug.get("valid_target", false) == true else "N",
			"Y" if raid_debug.get("close_for_raid", false) == true else "N",
			"Y" if raid_debug.get("can_initiate", false) == true else "N",
			int(raid_debug.get("raid_pressure", 0)),
			int(raid_debug.get("enemy_ranged", 0)),
			int(raid_debug.get("spare", 0)),
			int(raid_debug.get("desired_boarders", 0)),
			int(raid_debug.get("available_boarders", 0)),
		]
	_overlay_label.text = "scenario:%s (%d/%d)\nelapsed:%.1fs / %.1fs\nplayer hull:%.1f crew:%d board:%s enemy_boarders:%d derelict:%s\nenemy hull:%.1f crew:%d board:%s our_boarders:%d derelict:%s%s\nwinner:%s" % [
		scenario_name,
		maxi(_current_scenario_index + 1, 0),
		maxi(_scenario_defs.size(), 0),
		_current_scenario_elapsed,
		_get_current_scenario_time_limit(),
		player_hull,
		player_crew,
		"Y" if _is_boarding(_current_player_ship) else "N",
		_count_boarders_from_home_to_target(_current_enemy_ship, _current_player_ship),
		"Y" if _is_derelict(_current_player_ship) else "N",
		enemy_hull,
		enemy_crew,
		"Y" if _is_boarding(_current_enemy_ship) else "N",
		_count_boarders_from_home_to_target(_current_player_ship, _current_enemy_ship),
		"Y" if _is_derelict(_current_enemy_ship) else "N",
		raid_line,
		winner,
	]


func _get_current_scenario_time_limit() -> float:
	if _current_scenario_index >= 0 and _current_scenario_index < _scenario_defs.size():
		return float(_scenario_defs[_current_scenario_index].get("time_limit", scenario_time_limit_seconds))
	return scenario_time_limit_seconds


func _get_live_winner_hint(player_hull: float, enemy_hull: float, player_crew: int, enemy_crew: int) -> String:
	if player_hull <= 0.0 and enemy_hull <= 0.0:
		return "draw"
	if player_hull <= 0.0:
		return "enemy"
	if enemy_hull <= 0.0:
		return "player"
	if absf(player_hull - enemy_hull) > 12.0:
		return "player+" if player_hull > enemy_hull else "enemy+"
	if player_crew == enemy_crew:
		return "even"
	return "player crew+" if player_crew > enemy_crew else "enemy crew+"


func _report_summary() -> void:
	var player_wins: int = 0
	var enemy_wins: int = 0
	var draws: int = 0
	for result in _scenario_results:
		var winner := str(result.get("winner", "draw"))
		if winner.begins_with("player"):
			player_wins += 1
		elif winner.begins_with("enemy"):
			enemy_wins += 1
		else:
			draws += 1
	if auto_print_summary:
		for result in _scenario_results:
			var raid_debug: Dictionary = result.get("raid_debug", {})
			print("[ShipCombat] result name=%s winner=%s elapsed=%.2f player_hull=%.1f enemy_hull=%.1f player_hull_pct=%.1f enemy_hull_pct=%.1f player_crew=%d enemy_crew=%d player_derelict=%s enemy_derelict=%s player_boarding=%s enemy_boarding=%s player_boarders_on_enemy=%d enemy_boarders_on_player=%d raid_valid=%s raid_close=%s raid_init=%s raid_pressure=%d raid_ranged=%d raid_spare=%d raid_desired=%d raid_available=%d" % [
				str(result.get("name", "Scenario")),
				str(result.get("winner", "draw")),
				float(result.get("elapsed", 0.0)),
				float(result.get("player_hull", 0.0)),
				float(result.get("enemy_hull", 0.0)),
				float(result.get("player_hull_pct", 0.0)),
				float(result.get("enemy_hull_pct", 0.0)),
				int(result.get("player_crew", 0)),
				int(result.get("enemy_crew", 0)),
				"Y" if result.get("player_derelict", false) == true else "N",
				"Y" if result.get("enemy_derelict", false) == true else "N",
				"Y" if result.get("player_boarding", false) == true else "N",
				"Y" if result.get("enemy_boarding", false) == true else "N",
				int(result.get("player_boarders_on_enemy", 0)),
				int(result.get("enemy_boarders_on_player", 0)),
				"Y" if raid_debug.get("valid_target", false) == true else "N",
				"Y" if raid_debug.get("close_for_raid", false) == true else "N",
				"Y" if raid_debug.get("can_initiate", false) == true else "N",
				int(raid_debug.get("raid_pressure", 0)),
				int(raid_debug.get("enemy_ranged", 0)),
				int(raid_debug.get("spare", 0)),
				int(raid_debug.get("desired_boarders", 0)),
				int(raid_debug.get("available_boarders", 0)),
			])
		print("[ShipCombat] summary scenarios=%d player_wins=%d enemy_wins=%d draws=%d" % [
			_scenario_results.size(),
			player_wins,
			enemy_wins,
			draws,
		])


func _get_scene_name(scene: PackedScene) -> String:
	if scene == null:
		return "none"
	var path := scene.resource_path
	if path.is_empty():
		return "packed_scene"
	return path.get_file()


func _should_auto_quit_after_report() -> bool:
	return _env_flag_enabled("BATTLESHIP_SHIP_COMBAT_AUTO_QUIT")


func _quit_after_report() -> void:
	if auto_quit_delay_seconds > 0.0:
		await get_tree().create_timer(auto_quit_delay_seconds).timeout
	get_tree().quit(0)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
