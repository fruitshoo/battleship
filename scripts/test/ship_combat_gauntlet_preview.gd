extends Node3D

const PLAYER_SHIP_SCENE := preload("res://scenes/ships/player_ship.tscn")
const ENEMY_RUNTIME_SCENE := preload("res://scenes/ships/enemy_ship.tscn")
const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")
const ENEMY_GUNNER_SCENE := preload("res://scenes/ships/enemy_gunner_ship.tscn")
const ENEMY_FIREPOT_SCENE := preload("res://scenes/ships/enemy_firepot_ship.tscn")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var encounter_time_limit_seconds: float = 18.0
@export var intermission_seconds: float = 0.9
@export var auto_print_summary: bool = true
@export var auto_quit_delay_seconds: float = 0.05
@export var player_support_limit: int = 0

var _overlay_panel: PanelContainer = null
var _overlay_label: Label = null
var _overlay_refresh_left: float = 0.0
var _encounters: Array[Dictionary] = []
var _encounter_results: Array[Dictionary] = []
var _current_index: int = -1
var _current_started_usec: int = 0
var _current_elapsed: float = 0.0
var _current_player_ship: Node3D = null
var _current_enemy_ship: Node3D = null
var _running: bool = false
var _sequence_finished: bool = false
var _baseline_hull: float = 0.0
var _baseline_crew: int = 0
var _upgrade_preset: String = ""
var _disable_recovery_pickups: bool = false
var _keep_support_fleet_between_encounters: bool = false


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(delta: float) -> void:
	if not _running:
		return
	_current_elapsed = (Time.get_ticks_usec() - _current_started_usec) / 1000000.0
	if _disable_recovery_pickups:
		_strip_recovery_pickups()
	_overlay_refresh_left = maxf(0.0, _overlay_refresh_left - delta)
	if _overlay_refresh_left <= 0.0:
		_overlay_refresh_left = 0.2
		_update_overlay()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_ensure_overlay()
	_upgrade_preset = OS.get_environment("BATTLESHIP_GAUNTLET_UPGRADE_PRESET").strip_edges().to_lower()
	_disable_recovery_pickups = _env_flag_enabled("BATTLESHIP_GAUNTLET_DISABLE_RECOVERY")
	_setup_player_ship()
	_encounters = _build_encounters()
	_baseline_hull = _get_ship_hull(_current_player_ship)
	_baseline_crew = _get_ship_crew(_current_player_ship)
	await _run_encounters()


func _build_encounters() -> Array[Dictionary]:
	return [
		{"name": "Opening Gunner", "enemy_scene": ENEMY_GUNNER_SCENE, "distance": 15.5, "enemy_lateral_offset": 0.0},
		{"name": "First Melee", "enemy_scene": ENEMY_MELEE_SCENE, "distance": 8.5, "enemy_lateral_offset": 2.8},
		{"name": "Firepot Chase", "enemy_scene": ENEMY_FIREPOT_SCENE, "distance": 10.5, "enemy_lateral_offset": -3.0},
		{"name": "Mixed Pressure", "enemy_scene": ENEMY_RUNTIME_SCENE, "distance": 12.5, "enemy_lateral_offset": 0.0},
		{"name": "Late Gunner", "enemy_scene": ENEMY_GUNNER_SCENE, "distance": 16.0, "enemy_lateral_offset": 1.6},
		{"name": "Final Melee", "enemy_scene": ENEMY_MELEE_SCENE, "distance": 8.0, "enemy_lateral_offset": -2.4},
	]


func _setup_player_ship() -> void:
	_current_player_ship = get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(_current_player_ship):
		_current_player_ship = PLAYER_SHIP_SCENE.instantiate() as Node3D
		if is_instance_valid(_current_player_ship):
			_current_player_ship.name = "PlayerShip"
			add_child(_current_player_ship)
	_reset_player_ship_for_gauntlet(true)
	_configure_player_runtime()
	_apply_upgrade_preset()


func _run_encounters() -> void:
	_encounter_results.clear()
	for encounter_index in range(_encounters.size()):
		_current_index = encounter_index
		var encounter: Dictionary = _encounters[encounter_index]
		await _prepare_encounter(encounter)
		if _is_player_out():
			break

		_current_started_usec = Time.get_ticks_usec()
		_current_elapsed = 0.0
		_running = true
		_update_overlay()
		if auto_print_summary:
			print("[ShipGauntlet] start encounter=%s enemy_scene=%s distance=%.1f" % [
				str(encounter.get("name", "Encounter")),
				_get_scene_name(encounter.get("enemy_scene", null)),
				float(encounter.get("distance", 0.0)),
			])

		while _running:
			await get_tree().process_frame
			_current_elapsed = (Time.get_ticks_usec() - _current_started_usec) / 1000000.0
			if _is_encounter_finished():
				var result := _build_current_result()
				_encounter_results.append(result)
				_running = false
				_update_overlay()
				if auto_print_summary:
					print("[ShipGauntlet] encounter=%s winner=%s elapsed=%.2f player_hull=%.1f enemy_hull=%.1f player_crew=%d enemy_crew=%d hull_loss=%.1f crew_loss=%d" % [
						str(result.get("name", "Encounter")),
						str(result.get("winner", "draw")),
						float(result.get("elapsed", 0.0)),
						float(result.get("player_hull", 0.0)),
						float(result.get("enemy_hull", 0.0)),
						int(result.get("player_crew", 0)),
						int(result.get("enemy_crew", 0)),
						float(result.get("encounter_hull_loss", 0.0)),
						int(result.get("encounter_crew_loss", 0)),
					])

		if _is_player_out():
			break

		if encounter_index < _encounters.size() - 1 and intermission_seconds > 0.0:
			await get_tree().create_timer(intermission_seconds).timeout

	_sequence_finished = true
	_report_summary()
	if _should_auto_quit_after_report():
		call_deferred("_quit_after_report")


func _prepare_encounter(encounter: Dictionary) -> void:
	await _clear_runtime_noise()
	_reset_player_ship_for_gauntlet(false)
	_spawn_enemy_ship(encounter)
	await get_tree().process_frame
	_configure_enemy_runtime()
	_update_overlay()


func _clear_runtime_noise() -> void:
	for projectile in EntityRegistry.get_projectiles():
		if is_instance_valid(projectile):
			projectile.queue_free()
	if _disable_recovery_pickups:
		_strip_recovery_pickups()
	for child in get_children():
		if child == _current_player_ship:
			continue
		if _keep_support_fleet_between_encounters and child.get_meta("support_fleet_ship", false) == true:
			if "target" in child:
				child.target = _current_player_ship
			continue
		if child is Node3D and (
			child.has_meta("ship_gauntlet_spawn")
			or child.get_meta("support_fleet_ship", false) == true
			or child.is_in_group("captured_minion")
		):
			_archive_preview_node(child)
	await get_tree().process_frame


func _spawn_enemy_ship(encounter: Dictionary) -> void:
	var enemy_scene: PackedScene = encounter.get("enemy_scene", ENEMY_RUNTIME_SCENE)
	_current_enemy_ship = enemy_scene.instantiate() as Node3D
	if not is_instance_valid(_current_enemy_ship):
		return
	_current_enemy_ship.name = "GauntletEnemy_%d" % max(_current_index, 0)
	_current_enemy_ship.set_meta("ship_gauntlet_spawn", true)
	PreviewHarnessHelper.unlock_preview_enemy_fire_pot(_current_enemy_ship)
	add_child(_current_enemy_ship)

	var distance: float = float(encounter.get("distance", 12.0))
	var lateral: float = float(encounter.get("enemy_lateral_offset", 0.0))
	var forward := -_current_player_ship.global_basis.z.normalized()
	var right := _current_player_ship.global_basis.x.normalized()
	_current_enemy_ship.global_position = _current_player_ship.global_position + forward * distance + right * lateral
	_current_enemy_ship.look_at(_current_player_ship.global_position, Vector3.UP)
	PreviewHarnessHelper.assign_preview_target(_current_enemy_ship, _current_player_ship)


func _reset_player_ship_for_gauntlet(reset_hull_and_crew: bool) -> void:
	if not is_instance_valid(_current_player_ship):
		return
	_current_player_ship.global_position = Vector3(-1.7, 0.0, 15.7)
	_current_player_ship.rotation = Vector3.ZERO
	if reset_hull_and_crew:
		if "hull_hp" in _current_player_ship and "max_hull_hp" in _current_player_ship:
			_current_player_ship.set("hull_hp", float(_current_player_ship.get("max_hull_hp")))
		if _current_player_ship.has_method("_sync_player_crew_roster"):
			_current_player_ship.call("_sync_player_crew_roster")
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
	if _current_player_ship.has_method("clear_boarding_attacker_ship"):
		_current_player_ship.call("clear_boarding_attacker_ship")
	if _current_player_ship.has_method("set_preview_deck_state"):
		_current_player_ship.call("set_preview_deck_state", false, false)
	if _current_player_ship.has_method("check_derelict_status"):
		_current_player_ship.call("check_derelict_status")


func _configure_player_runtime() -> void:
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
	if "crew_respawn_interval" in _current_player_ship and _upgrade_preset.is_empty():
		_current_player_ship.set("crew_respawn_interval", 99999.0)
	if "crew_respawn_timer" in _current_player_ship:
		_current_player_ship.set("crew_respawn_timer", 0.0)
	if "is_rowing" in _current_player_ship:
		_current_player_ship.set("is_rowing", false)
	if _current_player_ship.has_method("set_preview_deck_state"):
		_current_player_ship.call("set_preview_deck_state", false, false)


func _apply_upgrade_preset() -> void:
	if _upgrade_preset.is_empty():
		return
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(upgrade_manager):
		return
	var preset_levels: Dictionary = {}
	match _upgrade_preset:
		"crew_sustain":
			preset_levels = {
				"crew_reserve": 2,
				"boarding_resist": 2,
			}
		"cannon_pressure":
			preset_levels = {
				"cannon": 3,
				"cannon_damage": 2,
				"cannon_reload": 2,
				"janggun": 2,
			}
		"crew_sustain_cannon":
			preset_levels = {
				"crew_reserve": 2,
				"boarding_resist": 2,
				"cannon": 2,
				"cannon_damage": 1,
				"cannon_reload": 1,
				"janggun": 1,
			}
		"fleet_screen":
			preset_levels = {
				"fleet_signal": 1,
				"hull_defense": 2,
				"cannon": 2,
				"fleet_crew": 2,
			}
		"crew_sustain_fleet":
			preset_levels = {
				"crew_reserve": 2,
				"boarding_resist": 2,
				"fleet_signal": 1,
				"hull_defense": 2,
				"cannon": 2,
				"fleet_crew": 2,
			}
		"crew_sustain_heavy":
			preset_levels = {
				"crew_reserve": 5,
				"boarding_resist": 5,
			}
		_:
			return
	for upgrade_id in preset_levels.keys():
		var target_level: int = int(preset_levels.get(upgrade_id, 0))
		while int(upgrade_manager.current_levels.get(upgrade_id, 0)) < target_level:
			upgrade_manager.apply_upgrade(upgrade_id)
	_keep_support_fleet_between_encounters = (
		int(preset_levels.get("fleet_signal", 0)) > 0
		or int(preset_levels.get("cannon", 0)) > 1
		or int(preset_levels.get("fleet_crew", 0)) > 0
	)
	if _keep_support_fleet_between_encounters:
		_prepare_support_fleet_screen()
	if auto_print_summary:
		print("[ShipGauntlet] upgrade_preset=%s" % _upgrade_preset)


func _prepare_support_fleet_screen() -> void:
	if not is_instance_valid(_current_player_ship):
		return
	if "support_fleet_limit" in _current_player_ship:
		_current_player_ship.set("support_fleet_limit", maxi(1, int(_current_player_ship.get("support_fleet_limit"))))
	if _current_player_ship.has_method("_spawn_or_repair_ally"):
		_current_player_ship.call("_spawn_or_repair_ally")


func _strip_recovery_pickups() -> void:
	var root: Node = get_tree().root
	_strip_recovery_nodes_under(root)
	_strip_recovery_nodes_under(self)


func _strip_recovery_nodes_under(parent: Node) -> void:
	if not is_instance_valid(parent):
		return
	for child in parent.get_children():
		if not is_instance_valid(child):
			continue
		if _is_recovery_pickup_node(child):
			_archive_preview_node(child)


func _is_recovery_pickup_node(node: Node) -> bool:
	var node_name: String = str(node.name)
	if node_name == "Survivor" or node_name == "FloatingLoot" or node_name == "TreasureChest":
		return true
	return node.is_in_group("treasure_chest")


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"


func _configure_enemy_runtime() -> void:
	if not is_instance_valid(_current_enemy_ship):
		return
	if _current_enemy_ship.has_method("set_preview_deck_state"):
		_current_enemy_ship.call("set_preview_deck_state", false, false)


func _is_encounter_finished() -> bool:
	if _is_player_out():
		return true
	if _is_enemy_out():
		return true
	return _current_elapsed >= encounter_time_limit_seconds


func _is_player_out() -> bool:
	return _is_ship_out(_current_player_ship)


func _is_enemy_out() -> bool:
	return _is_ship_out(_current_enemy_ship)


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
	var encounter: Dictionary = {}
	if _current_index >= 0 and _current_index < _encounters.size():
		encounter = _encounters[_current_index]

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

	var previous_hull: float = _baseline_hull
	var previous_crew: int = _baseline_crew
	if not _encounter_results.is_empty():
		var last_result: Dictionary = _encounter_results[_encounter_results.size() - 1]
		previous_hull = float(last_result.get("player_hull", previous_hull))
		previous_crew = int(last_result.get("player_crew", previous_crew))

	var winner := "draw"
	if _is_enemy_out() and not _is_player_out():
		winner = "player"
	elif _is_player_out() and not _is_enemy_out():
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
		"name": str(encounter.get("name", "Encounter")),
		"elapsed": _current_elapsed,
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
		"winner": winner,
		"encounter_hull_loss": snappedf(maxf(0.0, previous_hull - player_hull), 0.1),
		"encounter_crew_loss": maxi(0, previous_crew - player_crew),
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


func _archive_preview_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Node3D:
		var spatial := node as Node3D
		spatial.visible = false
		spatial.global_position = Vector3(0.0, -500.0, 0.0)
	node.set_meta("ship_gauntlet_archived", true)


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay_panel):
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return

	_overlay_panel = PanelContainer.new()
	_overlay_panel.name = "ShipCombatGauntletOverlay"
	_overlay_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay_panel.offset_left = 20.0
	_overlay_panel.offset_top = 20.0
	_overlay_panel.offset_right = 520.0
	_overlay_panel.offset_bottom = 190.0
	_overlay_panel.z_index = 100
	_overlay_panel.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 10, 1, 10.0, 8.0, 10.0, 8.0)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_overlay_panel.add_child(box)

	var title := Label.new()
	title.text = "Ship Combat Gauntlet"
	NavalUiTheme.style_heading(title, 14)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "persistent player hull / crew attrition across encounters"
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
	var encounter_name := "Waiting"
	if _current_index >= 0 and _current_index < _encounters.size():
		encounter_name = str(_encounters[_current_index].get("name", encounter_name))
	var player_hull := _get_ship_hull(_current_player_ship)
	var enemy_hull := _get_ship_hull(_current_enemy_ship)
	var player_crew := _get_ship_crew(_current_player_ship)
	var enemy_crew := _get_ship_crew(_current_enemy_ship)
	var total_hull_loss := snappedf(maxf(0.0, _baseline_hull - player_hull), 0.1)
	var total_crew_loss := maxi(0, _baseline_crew - player_crew)
	var winner := "-"
	if _sequence_finished and not _encounter_results.is_empty():
		winner = str(_encounter_results[_encounter_results.size() - 1].get("winner", "-"))
	elif _running:
		winner = _get_live_winner_hint(player_hull, enemy_hull, player_crew, enemy_crew)
	_overlay_label.text = "encounter:%s (%d/%d)\nelapsed:%.1fs / %.1fs\nplayer hull:%.1f crew:%d total_loss:%.1f / %d\nenemy hull:%.1f crew:%d\nenemy derelict:%s boarding:%s\nwinner:%s" % [
		encounter_name,
		maxi(_current_index + 1, 0),
		maxi(_encounters.size(), 0),
		_current_elapsed,
		encounter_time_limit_seconds,
		player_hull,
		player_crew,
		total_hull_loss,
		total_crew_loss,
		enemy_hull,
		enemy_crew,
		"Y" if _is_derelict(_current_enemy_ship) else "N",
		"Y" if _is_boarding(_current_enemy_ship) else "N",
		winner,
	]


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
	for result in _encounter_results:
		var winner := str(result.get("winner", "draw"))
		if winner.begins_with("player"):
			player_wins += 1
		elif winner.begins_with("enemy"):
			enemy_wins += 1
		else:
			draws += 1

	var final_hull: float = _get_ship_hull(_current_player_ship)
	var final_crew: int = _get_ship_crew(_current_player_ship)
	var total_hull_loss := snappedf(maxf(0.0, _baseline_hull - final_hull), 0.1)
	var total_crew_loss := maxi(0, _baseline_crew - final_crew)

	if auto_print_summary:
		for result in _encounter_results:
			print("[ShipGauntlet] result name=%s winner=%s elapsed=%.2f player_hull=%.1f enemy_hull=%.1f player_crew=%d enemy_crew=%d encounter_hull_loss=%.1f encounter_crew_loss=%d" % [
				str(result.get("name", "Encounter")),
				str(result.get("winner", "draw")),
				float(result.get("elapsed", 0.0)),
				float(result.get("player_hull", 0.0)),
				float(result.get("enemy_hull", 0.0)),
				int(result.get("player_crew", 0)),
				int(result.get("enemy_crew", 0)),
				float(result.get("encounter_hull_loss", 0.0)),
				int(result.get("encounter_crew_loss", 0)),
			])
		print("[ShipGauntlet] summary encounters=%d player_wins=%d enemy_wins=%d draws=%d final_hull=%.1f final_crew=%d total_hull_loss=%.1f total_crew_loss=%d" % [
			_encounter_results.size(),
			player_wins,
			enemy_wins,
			draws,
			final_hull,
			final_crew,
			total_hull_loss,
			total_crew_loss,
		])


func _get_scene_name(scene: PackedScene) -> String:
	if scene == null:
		return "none"
	var path := scene.resource_path
	if path.is_empty():
		return "packed_scene"
	return path.get_file()


func _should_auto_quit_after_report() -> bool:
	return _env_flag_enabled("BATTLESHIP_SHIP_GAUNTLET_AUTO_QUIT")


func _quit_after_report() -> void:
	if auto_quit_delay_seconds > 0.0:
		await get_tree().create_timer(auto_quit_delay_seconds).timeout
	get_tree().quit(0)
