extends Node3D

const PLAYER_SHIP_SCENE := preload("res://scenes/ships/player_ship.tscn")
const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var scenario_time_limit_seconds: float = 8.0
@export var intermission_seconds: float = 0.4
@export var auto_print_summary: bool = true
@export var auto_quit_delay_seconds: float = 0.05
@export var scenario_ship_gap: float = 6.6
@export var line_spacing: float = 1.45
@export var stage_line_x: float = 0.7

var _overlay_panel: PanelContainer = null
var _overlay_label: Label = null
var _overlay_refresh_left: float = 0.0
var _scenario_defs: Array[Dictionary] = []
var _scenario_results: Array[Dictionary] = []
var _current_scenario_index: int = -1
var _current_scenario_elapsed: float = 0.0
var _current_scenario_started_usec: int = 0
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
			"name": "General Mirror",
			"player_roles": ["general", "general", "general"],
			"enemy_roles": ["general", "general", "general"],
			"line_gap": 2.0,
		},
		{
			"name": "Spearman Mirror",
			"player_roles": ["spearman", "spearman"],
			"enemy_roles": ["spearman", "spearman"],
			"line_gap": 2.2,
		},
		{
			"name": "General vs Spear",
			"player_roles": ["general", "general"],
			"enemy_roles": ["spearman", "spearman"],
			"line_gap": 2.3,
		},
		{
			"name": "Spearman Hold",
			"player_roles": ["spearman", "spearman"],
			"enemy_roles": ["general", "general"],
			"line_gap": 2.2,
		},
		{
			"name": "Bow Pressure",
			"player_roles": ["general", "general"],
			"enemy_roles": ["general", "general"],
			"line_gap": 7.5,
			"player_force_ranged_only": true,
		},
		{
			"name": "Repeater Mirror",
			"player_roles": ["repeating_crossbow", "repeating_crossbow"],
			"enemy_roles": ["repeating_crossbow", "repeating_crossbow"],
			"line_gap": 7.2,
			"player_force_ranged_only": true,
			"enemy_force_ranged_only": true,
		},
		{
			"name": "Repeater Volley",
			"player_roles": ["repeating_crossbow", "repeating_crossbow"],
			"enemy_roles": ["general", "general", "general"],
			"line_gap": 7.0,
			"player_force_ranged_only": true,
		},
		{
			"name": "Mixed Boarding",
			"player_roles": ["general", "spearman", "repeating_crossbow"],
			"enemy_roles": ["general", "general", "general"],
			"line_gap": 3.0,
		},
	]


func _run_scenarios() -> void:
	_scenario_results.clear()
	for scenario_index in range(_scenario_defs.size()):
		var scenario: Dictionary = _scenario_defs[scenario_index]
		_current_scenario_index = scenario_index
		await _setup_scenario(scenario)
		_current_scenario_elapsed = 0.0
		_current_scenario_started_usec = Time.get_ticks_usec()
		_scenario_running = true
		_update_overlay()
		if auto_print_summary:
			var player_roles := _string_array_from_variant(scenario.get("player_roles", []))
			var enemy_roles := _string_array_from_variant(scenario.get("enemy_roles", []))
			print("[SoldierBalance] start scenario=%s player=%s enemy=%s" % [
				str(scenario.get("name", "Scenario")),
				",".join(player_roles),
				",".join(enemy_roles),
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
					print("[SoldierBalance] scenario=%s winner=%s elapsed=%.2f player_alive=%d enemy_alive=%d" % [
						result.get("name", "unknown"),
						result.get("winner", "draw"),
						float(result.get("elapsed", 0.0)),
						int(result.get("player_alive", 0)),
						int(result.get("enemy_alive", 0)),
					])

		if scenario_index < _scenario_defs.size() - 1 and intermission_seconds > 0.0:
			await get_tree().create_timer(intermission_seconds).timeout

	_sequence_finished = true
	_report_summary()
	if _should_auto_quit_after_report():
		call_deferred("_quit_after_report")


func _setup_scenario(scenario: Dictionary) -> void:
	await _clear_existing_preview_ships()
	_spawn_fresh_ships()
	await get_tree().process_frame

	_freeze_ship_runtime(_current_player_ship)
	_freeze_ship_runtime(_current_enemy_ship)
	_configure_player_runtime()
	_configure_enemy_runtime()

	await _configure_ship_roster(
		_current_player_ship,
		scenario.get("player_roles", []),
		true,
		scenario.get("player_force_ranged_only", false) == true
	)
	await _configure_ship_roster(
		_current_enemy_ship,
		scenario.get("enemy_roles", []),
		false,
		scenario.get("enemy_force_ranged_only", false) == true
	)
	await get_tree().process_frame

	_stage_soldier_lines(float(scenario.get("line_gap", 2.0)))
	_seed_initial_targets()
	_update_overlay()


func _clear_existing_preview_ships() -> void:
	for child in get_children():
		if child is Node3D and (
			child.name == "PlayerShip"
			or child.has_meta("soldier_balance_preview_spawn")
			or child.get_meta("support_fleet_ship", false) == true
			or child.is_in_group("captured_minion")
		):
			child.queue_free()
	await get_tree().process_frame


func _spawn_fresh_ships() -> void:
	_current_player_ship = PLAYER_SHIP_SCENE.instantiate() as Node3D
	if is_instance_valid(_current_player_ship):
		if "support_fleet_limit" in _current_player_ship:
			_current_player_ship.set("support_fleet_limit", 0)
		if "support_fleet_respawn_interval" in _current_player_ship:
			_current_player_ship.set("support_fleet_respawn_interval", 99999.0)
		if "captain_count" in _current_player_ship:
			_current_player_ship.set("captain_count", 0)
		_current_player_ship.name = "PlayerShip"
		add_child(_current_player_ship)
		_current_player_ship.global_position = Vector3(-1.7, 0.0, 15.7)
		_current_player_ship.rotation = Vector3.ZERO
		_current_player_ship.set_meta("soldier_balance_preview_spawn", true)

	_current_enemy_ship = ENEMY_MELEE_SCENE.instantiate() as Node3D
	if is_instance_valid(_current_enemy_ship):
		add_child(_current_enemy_ship)
		_current_enemy_ship.name = "BalanceEnemyShip"
		_current_enemy_ship.set_meta("soldier_balance_preview_spawn", true)
		_current_enemy_ship.global_position = Vector3(-1.7 + scenario_ship_gap, 0.0, 15.7)
		_current_enemy_ship.rotation = Vector3.ZERO
		PreviewHarnessHelper.assign_preview_target(_current_enemy_ship, _current_player_ship)


func _freeze_ship_runtime(ship: Node) -> void:
	if not is_instance_valid(ship):
		return
	ship.set_process(false)
	ship.set_physics_process(false)
	if "current_speed" in ship:
		ship.set("current_speed", 0.0)
	if "target_speed" in ship:
		ship.set("target_speed", 0.0)
	if "is_rowing" in ship:
		ship.set("is_rowing", false)


func _configure_player_runtime() -> void:
	if not is_instance_valid(_current_player_ship):
		return
	if "support_fleet_limit" in _current_player_ship:
		_current_player_ship.set("support_fleet_limit", 0)
	if "support_fleet_respawn_interval" in _current_player_ship:
		_current_player_ship.set("support_fleet_respawn_interval", 99999.0)
	if "support_fleet_respawn_timer" in _current_player_ship:
		_current_player_ship.set("support_fleet_respawn_timer", 0.0)
	if "captain_count" in _current_player_ship:
		_current_player_ship.set("captain_count", 0)


func _configure_enemy_runtime() -> void:
	if not is_instance_valid(_current_enemy_ship):
		return
	if "allow_boarding" in _current_enemy_ship:
		_current_enemy_ship.set("allow_boarding", false)


func _configure_ship_roster(ship: Node3D, roster_variant: Variant, is_player: bool, force_ranged_only: bool) -> void:
	if not is_instance_valid(ship):
		return
	var roster: Array[String] = []
	for entry in roster_variant:
		roster.append(str(entry).strip_edges().to_lower())

	var soldiers_node: Node = ship.get_node_or_null("Soldiers")
	if not is_instance_valid(soldiers_node):
		return

	while soldiers_node.get_child_count() < roster.size():
		if is_player and ship.has_method("_spawn_player_soldier"):
			ship.call("_spawn_player_soldier", soldiers_node, "general")
		elif not is_player and ship.has_method("_spawn_one_soldier"):
			ship.call("_spawn_one_soldier", "enemy", "general")
		else:
			break

	await get_tree().process_frame

	var soldiers: Array[Node] = []
	for child in soldiers_node.get_children():
		if child is Node3D:
			soldiers.append(child)

	while soldiers.size() > roster.size():
		var extra: Node = soldiers.pop_back()
		extra.queue_free()

	await get_tree().process_frame

	soldiers.clear()
	for child in soldiers_node.get_children():
		if child is Node3D:
			soldiers.append(child)

	for soldier_index in range(mini(soldiers.size(), roster.size())):
		_configure_soldier_for_role(
			soldiers[soldier_index],
			roster[soldier_index],
			is_player,
			force_ranged_only
		)


func _configure_soldier_for_role(soldier: Node, role_name: String, is_player: bool, force_ranged_only: bool) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.has_method("set_captain_status"):
		soldier.call("set_captain_status", false, 1.0, 1.0, 0.0)
	if "is_melee_only" in soldier:
		soldier.set("is_melee_only", false)
	if "is_ranged_only" in soldier:
		soldier.set("is_ranged_only", false)
	if soldier.has_method("apply_crew_role"):
		soldier.call("apply_crew_role", role_name)
	else:
		soldier.set("crew_role", role_name)
		soldier.set_meta("crew_role", role_name)

	if role_name == "repeating_crossbow" and "is_ranged_only" in soldier:
		soldier.set("is_ranged_only", force_ranged_only)
	if role_name == "general" and force_ranged_only and "is_ranged_only" in soldier:
		soldier.set("is_ranged_only", true)

	if soldier.has_method("set_team"):
		soldier.call("set_team", "player" if is_player else "enemy")
	if "current_health" in soldier and "max_health" in soldier:
		soldier.set("current_health", float(soldier.get("max_health")))
	if "attack_timer" in soldier:
		soldier.set("attack_timer", 0.0)
	if "decision_timer" in soldier:
		soldier.set("decision_timer", 0.0)
	if "combat_timer" in soldier:
		soldier.set("combat_timer", 0.0)
	if "rest_recovery_delay_timer" in soldier:
		soldier.set("rest_recovery_delay_timer", 999.0)


func _stage_soldier_lines(line_gap: float) -> void:
	var player_soldiers := _get_alive_ship_soldiers(_current_player_ship)
	var enemy_soldiers := _get_alive_ship_soldiers(_current_enemy_ship)
	if player_soldiers.is_empty() or enemy_soldiers.is_empty():
		return

	var enemy_forward := -_current_enemy_ship.global_basis.z.normalized()
	var enemy_right := _current_enemy_ship.global_basis.x.normalized()
	var stage_center := _current_enemy_ship.global_position + enemy_right * stage_line_x + Vector3.UP * 0.65

	var player_anchor := stage_center - enemy_forward * (line_gap * 0.5)
	var enemy_anchor := stage_center + enemy_forward * (line_gap * 0.5)

	for soldier_index in range(player_soldiers.size()):
		var player_soldier: Node3D = player_soldiers[soldier_index]
		if player_soldier.has_method("get_owned_ship_node"):
			player_soldier.set("owned_ship", _current_enemy_ship)
		if "velocity" in player_soldier:
			player_soldier.set("velocity", Vector3.ZERO)
		var spread := _get_line_spread_offset(soldier_index, player_soldiers.size())
		player_soldier.global_position = player_anchor + enemy_right * spread
		player_soldier.look_at(enemy_anchor + enemy_right * spread, Vector3.UP)

	for soldier_index in range(enemy_soldiers.size()):
		var enemy_soldier: Node3D = enemy_soldiers[soldier_index]
		enemy_soldier.set("owned_ship", _current_enemy_ship)
		if "velocity" in enemy_soldier:
			enemy_soldier.set("velocity", Vector3.ZERO)
		var spread := _get_line_spread_offset(soldier_index, enemy_soldiers.size())
		enemy_soldier.global_position = enemy_anchor + enemy_right * spread
		enemy_soldier.look_at(player_anchor + enemy_right * spread, Vector3.UP)


func _seed_initial_targets() -> void:
	var player_soldiers := _get_alive_ship_soldiers(_current_player_ship)
	var enemy_soldiers := _get_alive_ship_soldiers(_current_enemy_ship)
	for player_soldier in player_soldiers:
		var target := _find_nearest_opponent(player_soldier, enemy_soldiers)
		_assign_initial_target(player_soldier, target)
	for enemy_soldier in enemy_soldiers:
		var target := _find_nearest_opponent(enemy_soldier, player_soldiers)
		_assign_initial_target(enemy_soldier, target)


func _find_nearest_opponent(source: Node3D, candidates: Array[Node3D]) -> Node3D:
	if not is_instance_valid(source):
		return null
	var nearest: Node3D = null
	var nearest_distance_sq: float = INF
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var distance_sq := source.global_position.distance_squared_to(candidate.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	return nearest


func _assign_initial_target(soldier: Node, target: Node3D) -> void:
	if not is_instance_valid(soldier) or not is_instance_valid(target):
		return
	soldier.set("current_target", target)
	var attack_range: float = 1.2
	var current_weapon: Variant = soldier.get("current_weapon")
	if current_weapon != null and "attack_range" in current_weapon:
		attack_range = float(current_weapon.attack_range)
	var distance_xz := Vector2(
		soldier.global_position.x - target.global_position.x,
		soldier.global_position.z - target.global_position.z
	).length()
	if soldier.has_method("_change_state"):
		soldier.call("_change_state", 3 if distance_xz <= attack_range else 2)


func _get_line_spread_offset(index: int, count: int) -> float:
	if count <= 1:
		return 0.0
	var centered_index := float(index) - (float(count - 1) * 0.5)
	return centered_index * line_spacing


func _get_alive_ship_soldiers(ship: Node3D) -> Array[Node3D]:
	var alive: Array[Node3D] = []
	if not is_instance_valid(ship):
		return alive
	var soldiers_node: Node = ship.get_node_or_null("Soldiers")
	if not is_instance_valid(soldiers_node):
		return alive
	for child in soldiers_node.get_children():
		if not (child is Node3D):
			continue
		if child.has_method("is_dead_soldier") and child.call("is_dead_soldier") == true:
			continue
		alive.append(child)
	return alive


func _is_current_scenario_finished() -> bool:
	if not is_instance_valid(_current_player_ship) or not is_instance_valid(_current_enemy_ship):
		return true
	if _get_ship_alive_crew(_current_player_ship) <= 0:
		return true
	if _get_ship_alive_crew(_current_enemy_ship) <= 0:
		return true
	return _current_scenario_elapsed >= scenario_time_limit_seconds


func _build_current_result() -> Dictionary:
	var scenario: Dictionary = {}
	if _current_scenario_index >= 0 and _current_scenario_index < _scenario_defs.size():
		scenario = _scenario_defs[_current_scenario_index]
	var player_alive := _get_ship_alive_crew(_current_player_ship)
	var enemy_alive := _get_ship_alive_crew(_current_enemy_ship)
	var player_hp := _get_ship_alive_health(_current_player_ship)
	var enemy_hp := _get_ship_alive_health(_current_enemy_ship)
	var player_hp_pct := _get_ship_alive_health_ratio(_current_player_ship)
	var enemy_hp_pct := _get_ship_alive_health_ratio(_current_enemy_ship)
	var winner := "draw"
	if player_alive > 0 and enemy_alive <= 0:
		winner = "player"
	elif enemy_alive > 0 and player_alive <= 0:
		winner = "enemy"
	elif player_alive > enemy_alive:
		winner = "player_timeout"
	elif enemy_alive > player_alive:
		winner = "enemy_timeout"
	elif player_hp > enemy_hp + 1.0:
		winner = "player_hp_timeout"
	elif enemy_hp > player_hp + 1.0:
		winner = "enemy_hp_timeout"
	return {
		"name": str(scenario.get("name", "Scenario")),
		"elapsed": _current_scenario_elapsed,
		"player_alive": player_alive,
		"enemy_alive": enemy_alive,
		"player_hp": snappedf(player_hp, 0.1),
		"enemy_hp": snappedf(enemy_hp, 0.1),
		"player_hp_pct": snappedf(player_hp_pct * 100.0, 0.1),
		"enemy_hp_pct": snappedf(enemy_hp_pct * 100.0, 0.1),
		"winner": winner,
	}


func _get_ship_alive_crew(ship: Node) -> int:
	if not is_instance_valid(ship):
		return 0
	if ship.has_method("get_alive_crew_count"):
		return int(ship.call("get_alive_crew_count"))
	return 0


func _get_ship_alive_health(ship: Node3D) -> float:
	var total_health: float = 0.0
	for soldier in _get_alive_ship_soldiers(ship):
		if "current_health" in soldier:
			total_health += float(soldier.get("current_health"))
	return total_health


func _get_ship_alive_health_ratio(ship: Node3D) -> float:
	var total_health: float = 0.0
	var total_max_health: float = 0.0
	for soldier in _get_alive_ship_soldiers(ship):
		if "current_health" in soldier:
			total_health += float(soldier.get("current_health"))
		if "max_health" in soldier:
			total_max_health += float(soldier.get("max_health"))
	if total_max_health <= 0.0:
		return 0.0
	return total_health / total_max_health


func _string_array_from_variant(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	for entry in value:
		result.append(str(entry))
	return result


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay_panel):
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return

	_overlay_panel = PanelContainer.new()
	_overlay_panel.name = "SoldierBalanceOverlay"
	_overlay_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay_panel.offset_left = 20.0
	_overlay_panel.offset_top = 20.0
	_overlay_panel.offset_right = 470.0
	_overlay_panel.offset_bottom = 160.0
	_overlay_panel.z_index = 100
	_overlay_panel.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 10, 1, 10.0, 8.0, 10.0, 8.0)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_overlay_panel.add_child(box)

	var title := Label.new()
	title.text = "Soldier Balance Preview"
	NavalUiTheme.style_heading(title, 14)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "scenario / elapsed / surviving crew / winner"
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
	var player_alive := _get_ship_alive_crew(_current_player_ship)
	var enemy_alive := _get_ship_alive_crew(_current_enemy_ship)
	var player_hp := _get_ship_alive_health(_current_player_ship)
	var enemy_hp := _get_ship_alive_health(_current_enemy_ship)
	var winner := "-"
	if _sequence_finished and not _scenario_results.is_empty():
		winner = str(_scenario_results[_scenario_results.size() - 1].get("winner", "-"))
	elif _scenario_running:
		winner = _get_live_winner_hint(player_alive, enemy_alive)
	_overlay_label.text = "scenario:%s (%d/%d)\nelapsed:%.1fs / %.1fs\nplayer:%d hp:%.1f | enemy:%d hp:%.1f\nwinner:%s" % [
		scenario_name,
		maxi(_current_scenario_index + 1, 0),
		maxi(_scenario_defs.size(), 0),
		_current_scenario_elapsed,
		scenario_time_limit_seconds,
		player_alive,
		player_hp,
		enemy_alive,
		enemy_hp,
		winner,
	]


func _get_live_winner_hint(player_alive: int, enemy_alive: int) -> String:
	if player_alive <= 0 and enemy_alive <= 0:
		return "draw"
	if player_alive <= 0:
		return "enemy"
	if enemy_alive <= 0:
		return "player"
	if player_alive == enemy_alive:
		return "even"
	return "player+" if player_alive > enemy_alive else "enemy+"


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
			print("[SoldierBalance] result name=%s winner=%s elapsed=%.2f player_alive=%d enemy_alive=%d player_hp=%.1f enemy_hp=%.1f player_hp_pct=%.1f enemy_hp_pct=%.1f" % [
				str(result.get("name", "Scenario")),
				str(result.get("winner", "draw")),
				float(result.get("elapsed", 0.0)),
				int(result.get("player_alive", 0)),
				int(result.get("enemy_alive", 0)),
				float(result.get("player_hp", 0.0)),
				float(result.get("enemy_hp", 0.0)),
				float(result.get("player_hp_pct", 0.0)),
				float(result.get("enemy_hp_pct", 0.0)),
			])
		print("[SoldierBalance] summary scenarios=%d player_wins=%d enemy_wins=%d draws=%d" % [
			_scenario_results.size(),
			player_wins,
			enemy_wins,
			draws,
		])


func _should_auto_quit_after_report() -> bool:
	return _env_flag_enabled("BATTLESHIP_SOLDIER_BALANCE_AUTO_QUIT")


func _quit_after_report() -> void:
	if auto_quit_delay_seconds > 0.0:
		await get_tree().create_timer(auto_quit_delay_seconds).timeout
	get_tree().quit(0)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
