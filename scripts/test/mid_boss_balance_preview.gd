extends Node3D


@export var auto_open_debug_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var run_duration_seconds: float = 60.0
@export var auto_print_summary: bool = true
@export var auto_quit_delay_seconds: float = 0.05
@export var support_fleet_limit: int = 1
@export var runtime_monitor_sample_interval_seconds: float = 5.0

var _player_ship: Node3D = null
var _mid_boss: Node3D = null
var _start_usec: int = 0
var _elapsed: float = 0.0
var _initial_player_hull: float = 0.0
var _initial_player_crew: int = 0
var _initial_boss_hull: float = 0.0
var _max_enemy_boarders_on_player: int = 0
var _max_player_boarders_on_boss: int = 0
var _max_support_count: int = 0
var _boss_boarding_seen: bool = false
var _player_boarding_seen: bool = false
var _support_assist_seen: bool = false
var _finished: bool = false
var _runtime_monitor_start: Dictionary = {}
var _runtime_monitor_last: Dictionary = {}
var _runtime_monitor_peak_static_bytes: float = 0.0
var _runtime_monitor_peak_objects: float = 0.0
var _runtime_monitor_sample_timer: float = 0.0
var _runtime_monitor_sample_count: int = 0


func _ready() -> void:
	call_deferred("_run_preview")


func _process(delta: float) -> void:
	if _finished:
		return
	if _start_usec <= 0:
		return
	_elapsed = (Time.get_ticks_usec() - _start_usec) / 1000000.0
	_sample_state()
	_sample_runtime_monitors(delta)


func _run_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_apply_env_overrides()
	await get_tree().process_frame
	_player_ship = get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(_player_ship):
		push_error("[MidBossBalance] missing PlayerShip")
		get_tree().quit(1)
		return

	_prepare_player()
	await get_tree().process_frame
	_spawn_mid_boss()
	await get_tree().process_frame
	_configure_boss_and_escorts()
	await get_tree().process_frame

	_initial_player_hull = _get_ship_hull(_player_ship)
	_initial_player_crew = _get_ship_crew(_player_ship)
	_initial_boss_hull = _get_ship_hull(_mid_boss)
	_start_usec = Time.get_ticks_usec()
	_capture_runtime_monitor_sample()

	if auto_print_summary:
		print("[MidBossBalance] start duration=%.1f player_hull=%.1f player_crew=%d boss_hull=%.1f support_limit=%d escorts=%d" % [
			run_duration_seconds,
			_initial_player_hull,
			_initial_player_crew,
			_initial_boss_hull,
			support_fleet_limit,
			_count_enemy_escorts(),
		])

	while _elapsed < run_duration_seconds and not _is_ship_out(_player_ship) and not _is_ship_out(_mid_boss):
		await get_tree().process_frame

	_finished = true
	_sample_state()
	_capture_runtime_monitor_sample()
	_print_summary()
	_print_runtime_monitor_summary()
	if _should_auto_quit():
		call_deferred("_quit_after_report")


func _apply_env_overrides() -> void:
	var duration_text := OS.get_environment("BATTLESHIP_MID_BOSS_PREVIEW_DURATION").strip_edges()
	if not duration_text.is_empty():
		run_duration_seconds = maxf(1.0, float(duration_text))
	var support_text := OS.get_environment("BATTLESHIP_MID_BOSS_SUPPORT_LIMIT").strip_edges()
	if not support_text.is_empty():
		support_fleet_limit = maxi(0, int(support_text))


func _prepare_player() -> void:
	_player_ship.global_position = Vector3(-1.7, 0.0, 15.7)
	_player_ship.rotation = Vector3.ZERO
	if "hull_hp" in _player_ship and "max_hull_hp" in _player_ship:
		_player_ship.set("hull_hp", float(_player_ship.get("max_hull_hp")))
	if "current_speed" in _player_ship:
		_player_ship.set("current_speed", 0.0)
	if "rudder_angle" in _player_ship:
		_player_ship.set("rudder_angle", 0.0)
	if "is_sinking" in _player_ship:
		_player_ship.set("is_sinking", false)
	if "is_dying" in _player_ship:
		_player_ship.set("is_dying", false)
	if "is_burning" in _player_ship:
		_player_ship.set("is_burning", false)
	if "is_derelict" in _player_ship:
		_player_ship.set("is_derelict", false)
	if "support_fleet_limit" in _player_ship:
		_player_ship.set("support_fleet_limit", support_fleet_limit)
	if "support_fleet_respawn_interval" in _player_ship:
		_player_ship.set("support_fleet_respawn_interval", 99999.0)
	if "support_fleet_respawn_timer" in _player_ship:
		_player_ship.set("support_fleet_respawn_timer", 0.0)
	if _player_ship.has_method("_sync_player_crew_roster"):
		_player_ship.call("_sync_player_crew_roster")
	for _index in range(support_fleet_limit):
		if _player_ship.has_method("_spawn_or_repair_ally"):
			_player_ship.call("_spawn_or_repair_ally")


func _spawn_mid_boss() -> void:
	var spawner := get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner) or not spawner.has_method("debug_spawn_mid_boss"):
		push_error("[MidBossBalance] missing EnemySpawner.debug_spawn_mid_boss")
		get_tree().quit(1)
		return
	_mid_boss = spawner.call("debug_spawn_mid_boss") as Node3D
	if not is_instance_valid(_mid_boss):
		push_error("[MidBossBalance] mid boss spawn failed")
		get_tree().quit(1)
		return
	_mid_boss.set_meta("mid_boss_balance_primary", true)


func _configure_boss_and_escorts() -> void:
	for ship in EntityRegistry.get_ships_by_team("enemy"):
		if not is_instance_valid(ship):
			continue
		PreviewHarnessHelper.assign_preview_target(ship, _player_ship)
	for support_ship in _get_support_ships():
		if "target" in support_ship:
			support_ship.set("target", _player_ship)
		support_ship.set_meta("support_joining", false)


func _sample_state() -> void:
	_max_enemy_boarders_on_player = maxi(_max_enemy_boarders_on_player, _count_boarders_on_ship(_player_ship, "enemy"))
	_max_player_boarders_on_boss = maxi(_max_player_boarders_on_boss, _count_boarders_on_ship(_mid_boss, "player"))
	_max_support_count = maxi(_max_support_count, _get_support_ships().size())
	if _is_boarding(_mid_boss):
		_boss_boarding_seen = true
	if _is_boarding(_player_ship):
		_player_boarding_seen = true
	for support_ship in _get_support_ships():
		if str(support_ship.get_meta("support_debug_mode", "")) == "assist" or _is_boarding(support_ship):
			_support_assist_seen = true


func _sample_runtime_monitors(delta: float) -> void:
	if runtime_monitor_sample_interval_seconds <= 0.0:
		return
	_runtime_monitor_sample_timer -= delta
	if _runtime_monitor_sample_timer > 0.0:
		return
	_runtime_monitor_sample_timer = runtime_monitor_sample_interval_seconds
	_capture_runtime_monitor_sample()


func _capture_runtime_monitor_sample() -> void:
	var snapshot := {
		"static_bytes": float(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"objects": float(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": float(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": float(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	if _runtime_monitor_sample_count <= 0:
		_runtime_monitor_start = snapshot.duplicate()
	_runtime_monitor_last = snapshot.duplicate()
	_runtime_monitor_peak_static_bytes = maxf(_runtime_monitor_peak_static_bytes, _runtime_monitor_value(snapshot, "static_bytes"))
	_runtime_monitor_peak_objects = maxf(_runtime_monitor_peak_objects, _runtime_monitor_value(snapshot, "objects"))
	_runtime_monitor_sample_count += 1


func _print_summary() -> void:
	if not auto_print_summary:
		return
	var player_hull: float = _get_ship_hull(_player_ship)
	var boss_hull: float = _get_ship_hull(_mid_boss)
	var player_crew: int = _get_ship_crew(_player_ship)
	var player_dead_crew: int = _count_soldiers_on_ship(_player_ship, "player", false)
	var boss_crew: int = _get_ship_crew(_mid_boss)
	var support_crew: int = _get_total_support_crew()
	var escort_count: int = _count_enemy_escorts()
	var support_count: int = _get_support_ships().size()
	var outcome: String = _get_outcome()
	print("[MidBossBalance] summary support_limit=%d outcome=%s elapsed=%.2f player_hull=%.1f player_hull_loss=%.1f player_crew=%d player_dead_crew=%d support_crew=%d fleet_crew=%d player_crew_loss=%d boss_hull=%.1f boss_hull_loss=%.1f boss_crew=%d escorts_alive=%d support_alive=%d max_support=%d max_enemy_boarders_on_player=%d max_player_boarders_on_boss=%d boss_boarding=%s player_boarding=%s support_assist=%s" % [
		support_fleet_limit,
		outcome,
		_elapsed,
		player_hull,
		maxf(0.0, _initial_player_hull - player_hull),
		player_crew,
		player_dead_crew,
		support_crew,
		player_crew + support_crew,
		maxi(0, _initial_player_crew - player_crew),
		boss_hull,
		maxf(0.0, _initial_boss_hull - boss_hull),
		boss_crew,
		escort_count,
		support_count,
		_max_support_count,
		_max_enemy_boarders_on_player,
		_max_player_boarders_on_boss,
		"Y" if _boss_boarding_seen else "N",
		"Y" if _player_boarding_seen else "N",
		"Y" if _support_assist_seen else "N",
	])


func _print_runtime_monitor_summary() -> void:
	if not auto_print_summary:
		return
	if _runtime_monitor_sample_count <= 0:
		return
	var static_start_mb: float = _runtime_monitor_value(_runtime_monitor_start, "static_bytes") / 1048576.0
	var static_end_mb: float = _runtime_monitor_value(_runtime_monitor_last, "static_bytes") / 1048576.0
	var static_peak_mb: float = _runtime_monitor_peak_static_bytes / 1048576.0
	var objects_start: int = int(_runtime_monitor_value(_runtime_monitor_start, "objects"))
	var objects_end: int = int(_runtime_monitor_value(_runtime_monitor_last, "objects"))
	var resources_start: int = int(_runtime_monitor_value(_runtime_monitor_start, "resources"))
	var resources_end: int = int(_runtime_monitor_value(_runtime_monitor_last, "resources"))
	var nodes_start: int = int(_runtime_monitor_value(_runtime_monitor_start, "nodes"))
	var nodes_end: int = int(_runtime_monitor_value(_runtime_monitor_last, "nodes"))
	var orphan_nodes_end: int = int(_runtime_monitor_value(_runtime_monitor_last, "orphan_nodes"))
	print("[MidBossRuntime] summary samples=%d elapsed=%.2f static_mb_start=%.2f static_mb_end=%.2f static_mb_delta=%.2f static_mb_peak=%.2f objects_start=%d objects_end=%d objects_delta=%d objects_peak=%d resources_start=%d resources_end=%d resources_delta=%d nodes_start=%d nodes_end=%d nodes_delta=%d orphan_nodes_end=%d" % [
		_runtime_monitor_sample_count,
		_elapsed,
		static_start_mb,
		static_end_mb,
		static_end_mb - static_start_mb,
		static_peak_mb,
		objects_start,
		objects_end,
		objects_end - objects_start,
		int(_runtime_monitor_peak_objects),
		resources_start,
		resources_end,
		resources_end - resources_start,
		nodes_start,
		nodes_end,
		nodes_end - nodes_start,
		orphan_nodes_end,
	])


func _runtime_monitor_value(snapshot: Dictionary, key: String) -> float:
	return float(snapshot.get(key, 0.0))


func _get_outcome() -> String:
	if _is_ship_out(_player_ship) and _is_ship_out(_mid_boss):
		return "mutual_out"
	if _is_ship_out(_player_ship):
		return "player_out"
	if _is_ship_out(_mid_boss):
		return "boss_out"
	return "timeout"


func _get_support_ships() -> Array:
	var ships: Array = []
	for ship in EntityRegistry.get_ships_by_team("player"):
		if is_instance_valid(ship) and ship.get_meta("support_fleet_ship", false) == true:
			ships.append(ship)
	return ships


func _count_enemy_escorts() -> int:
	var count: int = 0
	for ship in EntityRegistry.get_ships_by_team("enemy"):
		if not is_instance_valid(ship) or ship == _mid_boss:
			continue
		if ship.is_in_group("boss"):
			continue
		if _is_ship_out(ship):
			continue
		count += 1
	return count


func _count_boarders_on_ship(ship: Node3D, boarder_team: String) -> int:
	return _count_soldiers_on_ship(ship, boarder_team, true)


func _count_soldiers_on_ship(ship: Node3D, team_filter: String, alive: bool) -> int:
	if not is_instance_valid(ship):
		return 0
	var count: int = 0
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier):
			continue
		var is_dead: bool = soldier.has_method("is_dead_soldier") and soldier.call("is_dead_soldier") == true
		if alive and is_dead:
			continue
		if not alive and not is_dead:
			continue
		var team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if team == team_filter:
			count += 1
	return count


func _get_total_support_crew() -> int:
	var crew: int = 0
	for support_ship in _get_support_ships():
		crew += _get_ship_crew(support_ship)
	return crew


func _get_ship_hull(ship: Node3D) -> float:
	if not is_instance_valid(ship):
		return 0.0
	if ship.has_method("get_hull_hp_value"):
		return float(ship.call("get_hull_hp_value"))
	return float(ship.get("hull_hp")) if "hull_hp" in ship else 0.0


func _get_ship_crew(ship: Node3D) -> int:
	if not is_instance_valid(ship):
		return 0
	if ship.has_method("get_alive_crew_count"):
		return int(ship.call("get_alive_crew_count"))
	return 0


func _is_boarding(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("is_boarding_ship"):
		return ship.call("is_boarding_ship") == true
	return ship.get("is_boarding") == true if "is_boarding" in ship else false


func _is_ship_out(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return true
	if ship.has_method("is_combat_disabled") and ship.call("is_combat_disabled") == true:
		return true
	if ship.has_method("is_derelict_ship") and ship.call("is_derelict_ship") == true:
		return true
	if ship.get("is_sinking") == true or ship.get("is_dying") == true or ship.get("is_dead") == true:
		return true
	return _get_ship_hull(ship) <= 0.0


func _should_auto_quit() -> bool:
	return _env_flag_enabled("BATTLESHIP_MID_BOSS_PREVIEW_AUTO_QUIT")


func _quit_after_report() -> void:
	if auto_quit_delay_seconds > 0.0:
		await get_tree().create_timer(auto_quit_delay_seconds).timeout
	get_tree().quit(0)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
