extends Node3D

const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")
const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

enum BattleMode {
	STRESS,
	VISUAL_COMPARE,
}

@export var auto_open_debug_panel: bool = true
@export var open_stat_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var enable_distance_debug: bool = false
@export var battle_mode: BattleMode = BattleMode.STRESS
@export var midgame_time_seconds: float = 240.0
@export var midgame_difficulty: int = 6
@export var level_duration: float = 30.0
@export var initial_wave_delay: float = 0.75
@export var wave_interval: float = 7.0
@export var wave_limit: int = 6
@export var wave_plan: PackedStringArray = PackedStringArray(["mixed", "heavy", "mixed", "heavy", "mixed", "heavy"])
@export var open_deck_for_combat: bool = true
@export var compare_warmup_seconds: float = 0.5
@export var compare_phase_seconds: float = 0.35
@export var auto_print_compare_results: bool = true
@export var auto_quit_delay_seconds: float = 0.05
@export var runtime_probe_enabled: bool = false
@export var runtime_probe_duration_seconds: float = 300.0
@export var runtime_probe_cycle_seconds: float = 60.0
@export var runtime_probe_sample_interval_seconds: float = 5.0
@export var support_probe_enabled: bool = false
@export var support_probe_setup_delay_seconds: float = 0.35
@export var support_probe_duration_seconds: float = 600.0
@export var support_probe_warmup_seconds: float = 5.0
@export var support_probe_sample_interval_seconds: float = 20.0
@export var support_probe_support_limit: int = 5
@export var support_probe_formation: int = SupportFleetStateHelper.FORMATION_WING
@export var support_probe_player_speed: float = 3.2
@export var support_probe_cannon_level: int = 5
@export var support_probe_fleet_signal_level: int = 1
@export var support_probe_fleet_crew_level: int = 0
@export var support_probe_panokseon_upgrade_level: int = 1
@export var support_probe_lock_survival: bool = true
var print_orphan_nodes: bool = false

var _overlay_panel: PanelContainer = null
var _overlay_label: Label = null
var _overlay_refresh_left: float = 0.0
var _elapsed_time: float = 0.0
var _wave_elapsed: float = 0.0
var _wave_index: int = -1
var _last_spawned_fleet: String = ""
var _compare_phase_samples: Array = [[], []]
var _compare_phase_elapsed: float = 0.0
var _compare_phase_index: int = 0
var _compare_warmup_elapsed: float = 0.0
var _compare_collecting: bool = false
var _compare_phase_finished: bool = false
var _compare_final_reported: bool = false
var _midgame_initialized: bool = false
var _runtime_probe_final_reported: bool = false
var _runtime_probe_sample_timer: float = 0.0
var _runtime_probe_cycle_elapsed: float = 0.0
var _runtime_probe_cleanup_pending: bool = false
var _runtime_probe_cleanup_wait_frames: int = 0
var _runtime_probe_cycle_index: int = 0
var _runtime_monitor_start: Dictionary = {}
var _runtime_monitor_cycle_start: Dictionary = {}
var _runtime_monitor_last: Dictionary = {}
var _runtime_monitor_peak_static_bytes: float = 0.0
var _runtime_monitor_peak_objects: float = 0.0
var _runtime_monitor_sample_count: int = 0
var _support_probe_setup_done: bool = false
var _support_probe_setup_elapsed: float = 0.0
var _support_probe_started: bool = false
var _support_probe_final_reported: bool = false
var _support_probe_warmup_elapsed: float = 0.0
var _support_probe_elapsed: float = 0.0
var _support_probe_sample_elapsed: float = 0.0
var _support_probe_frame_samples: Array = []
var _support_probe_window_samples: Array = []
var _support_probe_sample_index: int = 0
var _support_probe_monitor_start: Dictionary = {}
var _support_probe_monitor_last: Dictionary = {}
var _support_probe_monitor_peak_static_bytes: float = 0.0
var _support_probe_monitor_peak_objects: float = 0.0
var _support_probe_profile_buckets: bool = false
var _support_probe_profile_print_elapsed: float = 0.0


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(delta: float) -> void:
	_elapsed_time += delta
	_wave_elapsed += delta
	if runtime_probe_enabled and battle_mode == BattleMode.STRESS:
		_runtime_probe_cycle_elapsed += delta
		_sample_runtime_monitors(delta)
		_handle_runtime_probe_cleanup()
	if support_probe_enabled and battle_mode == BattleMode.STRESS:
		_update_support_probe_setup(delta)
		if _support_probe_setup_done:
			_track_support_probe(delta)
	_track_compare_sample(delta)
	_overlay_refresh_left = maxf(0.0, _overlay_refresh_left - delta)
	if _overlay_refresh_left <= 0.0:
		_overlay_refresh_left = 0.25
		_update_overlay()
	if _midgame_initialized and battle_mode == BattleMode.STRESS:
		_maybe_reset_runtime_probe_cycle()
		_maybe_finish_runtime_probe()
		if not _runtime_probe_cleanup_pending and not _runtime_probe_final_reported:
			_maybe_spawn_next_wave()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_apply_env_overrides()
	_ensure_stat_panel()
	_configure_midgame_state()
	_clear_existing_preview_spawns()
	_spawn_battle_load()
	_configure_compare_state()
	_ensure_overlay()
	_update_overlay()
	if runtime_probe_enabled:
		_capture_runtime_monitor_sample()
		_runtime_monitor_cycle_start = _runtime_monitor_last.duplicate()
		print("[MidgameRuntime] start duration=%.1f cycle=%.1f wave_limit=%d wave_interval=%.1f" % [
			runtime_probe_duration_seconds,
			runtime_probe_cycle_seconds,
			wave_limit,
			wave_interval,
		])


func _apply_env_overrides() -> void:
	var mode_text := OS.get_environment("BATTLESHIP_MIDGAME_BATTLE_MODE").strip_edges().to_lower()
	if mode_text == "stress" or mode_text == "runtime" or mode_text == "runtime_probe":
		battle_mode = BattleMode.STRESS
	elif mode_text == "visual_compare" or mode_text == "compare":
		battle_mode = BattleMode.VISUAL_COMPARE

	var debug_panel_text := OS.get_environment("BATTLESHIP_MIDGAME_AUTO_OPEN_DEBUG_PANEL").strip_edges()
	if not debug_panel_text.is_empty():
		auto_open_debug_panel = _env_text_enabled(debug_panel_text)
	var stat_panel_text := OS.get_environment("BATTLESHIP_MIDGAME_OPEN_STAT_PANEL").strip_edges()
	if not stat_panel_text.is_empty():
		open_stat_panel = _env_text_enabled(stat_panel_text)

	runtime_probe_enabled = runtime_probe_enabled or _env_flag_enabled("BATTLESHIP_MIDGAME_RUNTIME_PROBE")
	support_probe_enabled = support_probe_enabled or _env_flag_enabled("BATTLESHIP_MIDGAME_SUPPORT_PROBE")
	var duration_text := OS.get_environment("BATTLESHIP_MIDGAME_RUNTIME_DURATION").strip_edges()
	if not duration_text.is_empty():
		runtime_probe_duration_seconds = maxf(1.0, float(duration_text))
	var cycle_text := OS.get_environment("BATTLESHIP_MIDGAME_RUNTIME_CYCLE_SECONDS").strip_edges()
	if not cycle_text.is_empty():
		runtime_probe_cycle_seconds = maxf(1.0, float(cycle_text))
	var sample_text := OS.get_environment("BATTLESHIP_MIDGAME_RUNTIME_SAMPLE_INTERVAL").strip_edges()
	if not sample_text.is_empty():
		runtime_probe_sample_interval_seconds = maxf(0.25, float(sample_text))
	var wave_limit_text := OS.get_environment("BATTLESHIP_MIDGAME_WAVE_LIMIT").strip_edges()
	if not wave_limit_text.is_empty():
		wave_limit = maxi(1, int(wave_limit_text))
	var wave_interval_text := OS.get_environment("BATTLESHIP_MIDGAME_WAVE_INTERVAL").strip_edges()
	if not wave_interval_text.is_empty():
		wave_interval = maxf(0.1, float(wave_interval_text))
	var initial_wave_delay_text := OS.get_environment("BATTLESHIP_MIDGAME_INITIAL_WAVE_DELAY").strip_edges()
	if not initial_wave_delay_text.is_empty():
		initial_wave_delay = maxf(0.0, float(initial_wave_delay_text))
	var support_probe_duration_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_DURATION").strip_edges()
	if not support_probe_duration_text.is_empty():
		support_probe_duration_seconds = maxf(1.0, float(support_probe_duration_text))
	var support_probe_setup_delay_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_SETUP_DELAY").strip_edges()
	if not support_probe_setup_delay_text.is_empty():
		support_probe_setup_delay_seconds = maxf(0.0, float(support_probe_setup_delay_text))
	var support_probe_warmup_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_WARMUP").strip_edges()
	if not support_probe_warmup_text.is_empty():
		support_probe_warmup_seconds = maxf(0.0, float(support_probe_warmup_text))
	var support_probe_sample_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_SAMPLE_INTERVAL").strip_edges()
	if not support_probe_sample_text.is_empty():
		support_probe_sample_interval_seconds = maxf(0.25, float(support_probe_sample_text))
	var support_probe_limit_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_SUPPORT_LIMIT").strip_edges()
	if not support_probe_limit_text.is_empty():
		support_probe_support_limit = maxi(0, int(support_probe_limit_text))
	var support_probe_speed_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_PLAYER_SPEED").strip_edges()
	if not support_probe_speed_text.is_empty():
		support_probe_player_speed = maxf(0.0, float(support_probe_speed_text))
	var support_probe_formation_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_FORMATION").strip_edges().to_lower()
	if support_probe_formation_text == "column" or support_probe_formation_text == "0":
		support_probe_formation = SupportFleetStateHelper.FORMATION_COLUMN
	elif support_probe_formation_text == "wing" or support_probe_formation_text == "1":
		support_probe_formation = SupportFleetStateHelper.FORMATION_WING
	var support_probe_cannon_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_CANNON_LEVEL").strip_edges()
	if not support_probe_cannon_text.is_empty():
		support_probe_cannon_level = maxi(0, int(support_probe_cannon_text))
	var support_probe_survival_text := OS.get_environment("BATTLESHIP_MIDGAME_SUPPORT_PROBE_LOCK_SURVIVAL").strip_edges()
	if not support_probe_survival_text.is_empty():
		support_probe_lock_survival = _env_text_enabled(support_probe_survival_text)
	_support_probe_profile_buckets = _env_flag_enabled("BATTLESHIP_MIDGAME_PROFILE_BUCKETS")
	if _support_probe_profile_buckets:
		PhysicsFrameProfiler.set_enabled(true)
	print_orphan_nodes = _env_flag_enabled("BATTLESHIP_MIDGAME_PRINT_ORPHANS")


func _ensure_stat_panel() -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return
	var should_show_stat_panel: bool = open_stat_panel
	var should_show_ship_health_bars: bool = open_stat_panel
	if battle_mode == BattleMode.VISUAL_COMPARE:
		should_show_stat_panel = false
		should_show_ship_health_bars = false
	if "show_stat_panel" in hud:
		hud.set("show_stat_panel", should_show_stat_panel)
	if should_show_stat_panel and hud.has_method("_update_stat_panel"):
		hud.call("_update_stat_panel")
	if enable_distance_debug and hud.has_method("_toggle_distance_debug"):
		hud.call("_toggle_distance_debug")
	if "show_ship_health_bars" in hud:
		hud.set("show_ship_health_bars", should_show_ship_health_bars)
		if hud.has_method("_update_ship_health_bars"):
			hud.call("_update_ship_health_bars", false)


func _configure_midgame_state() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if is_instance_valid(player) and open_deck_for_combat:
		PreviewHarnessHelper.apply_preview_deck_state(player, true, false)
	if runtime_probe_enabled and is_instance_valid(player):
		_prepare_runtime_probe_player(player)

	var level_manager: Node = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(level_manager):
		if "boss_spawn_time" in level_manager:
			level_manager.set("boss_spawn_time", 99999.0)
		if "survival_victory_time" in level_manager:
			level_manager.set("survival_victory_time", 99999.0)
		if "level_duration" in level_manager:
			level_manager.set("level_duration", level_duration)
		if "current_time" in level_manager:
			level_manager.set("current_time", midgame_time_seconds)
		if "game_difficulty" in level_manager:
			level_manager.set("game_difficulty", midgame_difficulty)
		if level_manager.has_method("_update_difficulty"):
			level_manager.call("_update_difficulty")

	var spawner: Node = get_node_or_null("EnemySpawner")
	if is_instance_valid(spawner) and "regular_spawn_stopped" in spawner:
		spawner.set("regular_spawn_stopped", true)

	_midgame_initialized = true
	_wave_elapsed = 0.0
	_wave_index = -1
	_last_spawned_fleet = ""


func _prepare_runtime_probe_player(player: Node3D) -> void:
	if "max_hull_hp" in player:
		player.set("max_hull_hp", maxf(float(player.get("max_hull_hp")), 99999.0))
	if "hull_hp" in player:
		player.set("hull_hp", maxf(float(player.get("hull_hp")), 99999.0))
	if "is_sinking" in player:
		player.set("is_sinking", false)
	if "is_dying" in player:
		player.set("is_dying", false)
	if "is_derelict" in player:
		player.set("is_derelict", false)


func _prepare_support_probe_player(player: Node3D) -> void:
	_prepare_runtime_probe_player(player)
	_stabilize_support_probe_ship(player, true)
	_apply_support_probe_upgrade_levels()
	if "support_fleet_limit" in player:
		player.set("support_fleet_limit", support_probe_support_limit)
	if "support_fleet_respawn_interval" in player:
		player.set("support_fleet_respawn_interval", 99999.0)
	if "support_fleet_respawn_timer" in player:
		player.set("support_fleet_respawn_timer", 0.0)
	if "current_speed" in player:
		player.set("current_speed", support_probe_player_speed)
	if "is_rowing" in player:
		player.set("is_rowing", support_probe_player_speed > 0.0)
	SupportFleetStateHelper.set_flagship_formation(player, support_probe_formation)
	SupportFleetStateHelper.set_flagship_hold_enabled(player, true)
	_spawn_support_probe_fleet(player)


func _apply_support_probe_upgrade_levels() -> void:
	var upgrade_manager := get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(upgrade_manager):
		return
	_raise_upgrade_level(upgrade_manager, "fleet_signal", support_probe_fleet_signal_level)
	_raise_upgrade_level(upgrade_manager, "panokseon_upgrade", support_probe_panokseon_upgrade_level)
	_raise_upgrade_level(upgrade_manager, "fleet_crew", support_probe_fleet_crew_level)
	_raise_upgrade_level(upgrade_manager, "cannon", support_probe_cannon_level)


func _raise_upgrade_level(upgrade_manager: Node, upgrade_id: String, target_level: int) -> void:
	if target_level <= 0:
		return
	if not ("current_levels" in upgrade_manager) or not upgrade_manager.has_method("apply_upgrade"):
		return
	if "UPGRADES" in upgrade_manager:
		var upgrades: Dictionary = upgrade_manager.get("UPGRADES")
		var upgrade_data: Dictionary = upgrades.get(upgrade_id, {})
		if upgrade_data.is_empty() or upgrade_data.get("disabled", false) == true:
			return
	var current_levels: Dictionary = upgrade_manager.get("current_levels")
	while int(current_levels.get(upgrade_id, 0)) < target_level:
		var previous_level := int(current_levels.get(upgrade_id, 0))
		upgrade_manager.call("apply_upgrade", upgrade_id)
		current_levels = upgrade_manager.get("current_levels")
		if int(current_levels.get(upgrade_id, 0)) <= previous_level:
			return


func _spawn_support_probe_fleet(player: Node3D) -> void:
	if support_probe_support_limit <= 0:
		return
	if not player.has_method("_spawn_or_repair_support_ship"):
		return
	var guard := 0
	while _get_support_probe_support_ships().size() < support_probe_support_limit and guard < support_probe_support_limit + 2:
		player.call("_spawn_or_repair_support_ship")
		guard += 1
	_configure_support_probe_supports(player)


func _configure_support_probe_supports(player: Node3D) -> void:
	for support_ship in _get_support_probe_support_ships():
		if not is_instance_valid(support_ship):
			continue
		if "target" in support_ship:
			support_ship.set("target", player)
		if "current_speed" in support_ship:
			support_ship.set("current_speed", support_probe_player_speed)
		support_ship.set_meta("support_joining", false)
		_stabilize_support_probe_ship(support_ship, false)


func _clear_existing_preview_spawns() -> void:
	PreviewHarnessHelper.clear_preview_enemies(self, "midgame_fleet_battle_spawn")


func _spawn_battle_load() -> void:
	if battle_mode == BattleMode.STRESS:
		_spawn_initial_wave()
		return
	_spawn_wave_schedule()


func _spawn_initial_wave() -> void:
	_maybe_spawn_next_wave(true)


func _spawn_wave_schedule() -> void:
	if wave_limit <= 0:
		return
	var wave_count: int = min(wave_limit, max(1, wave_plan.size()))
	for wave_index in range(wave_count):
		var fleet_class := _get_wave_fleet_class(wave_index)
		_spawn_fleet_wave(fleet_class)
		_last_spawned_fleet = fleet_class


func _maybe_spawn_next_wave(force: bool = false) -> void:
	if not _midgame_initialized:
		return
	if battle_mode != BattleMode.STRESS:
		return
	if _wave_index >= wave_limit - 1:
		return
	var delay := initial_wave_delay if _wave_index < 0 else wave_interval
	if not force and _wave_elapsed < delay:
		return
	_wave_elapsed = 0.0
	_wave_index += 1
	var fleet_class := _get_wave_fleet_class(_wave_index)
	_spawn_fleet_wave(fleet_class)


func _get_wave_fleet_class(wave_index: int) -> String:
	if wave_plan.is_empty():
		return "mixed" if wave_index % 2 == 0 else "heavy"
	var plan_index: int = min(wave_index, wave_plan.size() - 1)
	return str(wave_plan[plan_index]).strip_edges().to_lower()


func _spawn_fleet_wave(fleet_class: String) -> void:
	var spawner: Node = get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner) or not spawner.has_method("debug_spawn_fleet"):
		return
	var known_enemy_ids: Dictionary = {}
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		if is_instance_valid(enemy):
			known_enemy_ids[enemy.get_instance_id()] = true
	spawner.call("debug_spawn_fleet", fleet_class)
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		if is_instance_valid(enemy) and not known_enemy_ids.has(enemy.get_instance_id()):
			enemy.set_meta("midgame_fleet_battle_spawn", true)
	_last_spawned_fleet = fleet_class


func _sample_runtime_monitors(delta: float) -> void:
	if runtime_probe_sample_interval_seconds <= 0.0:
		return
	_runtime_probe_sample_timer -= delta
	if _runtime_probe_sample_timer > 0.0:
		return
	_runtime_probe_sample_timer = runtime_probe_sample_interval_seconds
	_capture_runtime_monitor_sample()


func _capture_runtime_monitor_sample() -> void:
	var snapshot := {
		"static_bytes": float(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"objects": float(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": float(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": float(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"ships": float(_count_ships()),
		"soldiers": float(_count_soldiers()),
		"projectiles": float(_count_projectiles()),
	}
	if _runtime_monitor_sample_count <= 0:
		_runtime_monitor_start = snapshot.duplicate()
	_runtime_monitor_last = snapshot.duplicate()
	_runtime_monitor_peak_static_bytes = maxf(_runtime_monitor_peak_static_bytes, _runtime_monitor_value(snapshot, "static_bytes"))
	_runtime_monitor_peak_objects = maxf(_runtime_monitor_peak_objects, _runtime_monitor_value(snapshot, "objects"))
	_runtime_monitor_sample_count += 1


func _maybe_reset_runtime_probe_cycle() -> void:
	if not runtime_probe_enabled:
		return
	if _runtime_probe_cleanup_pending:
		return
	if runtime_probe_cycle_seconds <= 0.0:
		return
	if _runtime_probe_cycle_elapsed < runtime_probe_cycle_seconds:
		return
	_begin_runtime_probe_cycle_reset()


func _begin_runtime_probe_cycle_reset() -> void:
	_runtime_probe_cycle_index += 1
	_capture_runtime_monitor_sample()
	_print_runtime_probe_cycle("before_cleanup")
	_clear_runtime_probe_load()
	_runtime_probe_cleanup_pending = true
	_runtime_probe_cleanup_wait_frames = 3
	_runtime_probe_cycle_elapsed = 0.0
	_wave_index = -1
	_wave_elapsed = 0.0
	_last_spawned_fleet = ""


func _handle_runtime_probe_cleanup() -> void:
	if not _runtime_probe_cleanup_pending:
		return
	_runtime_probe_cleanup_wait_frames -= 1
	if _runtime_probe_cleanup_wait_frames > 0:
		return
	_runtime_probe_cleanup_pending = false
	_capture_runtime_monitor_sample()
	_runtime_monitor_cycle_start = _runtime_monitor_last.duplicate()
	_print_runtime_probe_cycle("after_cleanup")
	_wave_elapsed = initial_wave_delay


func _clear_runtime_probe_load() -> void:
	for projectile in EntityRegistry.get_projectiles():
		if is_instance_valid(projectile):
			projectile.queue_free()
	for soldier in EntityRegistry.get_soldiers_by_team("enemy"):
		if is_instance_valid(soldier):
			soldier.queue_free()
	for enemy in EntityRegistry.get_ships_by_team("enemy"):
		if is_instance_valid(enemy):
			enemy.queue_free()


func _maybe_finish_runtime_probe() -> void:
	if not runtime_probe_enabled:
		return
	if _runtime_probe_final_reported:
		return
	if _runtime_probe_cleanup_pending:
		return
	if _elapsed_time < runtime_probe_duration_seconds:
		return
	_runtime_probe_final_reported = true
	_capture_runtime_monitor_sample()
	_print_runtime_probe_summary()
	if _should_auto_quit_after_report():
		call_deferred("_quit_after_compare_report")


func _print_runtime_probe_cycle(phase: String) -> void:
	var static_mb: float = _runtime_monitor_value(_runtime_monitor_last, "static_bytes") / 1048576.0
	var cycle_static_start_mb: float = _runtime_monitor_value(_runtime_monitor_cycle_start, "static_bytes") / 1048576.0
	print("[MidgameRuntime] cycle=%d phase=%s elapsed=%.2f static_mb=%.2f cycle_static_mb_delta=%.2f objects=%d resources=%d nodes=%d orphan_nodes=%d ships=%d soldiers=%d projectiles=%d" % [
		_runtime_probe_cycle_index,
		phase,
		_elapsed_time,
		static_mb,
		static_mb - cycle_static_start_mb,
		int(_runtime_monitor_value(_runtime_monitor_last, "objects")),
		int(_runtime_monitor_value(_runtime_monitor_last, "resources")),
		int(_runtime_monitor_value(_runtime_monitor_last, "nodes")),
		int(_runtime_monitor_value(_runtime_monitor_last, "orphan_nodes")),
		int(_runtime_monitor_value(_runtime_monitor_last, "ships")),
		int(_runtime_monitor_value(_runtime_monitor_last, "soldiers")),
		int(_runtime_monitor_value(_runtime_monitor_last, "projectiles")),
	])
	if print_orphan_nodes and int(_runtime_monitor_value(_runtime_monitor_last, "orphan_nodes")) > 0:
		Node.print_orphan_nodes()


func _print_runtime_probe_summary() -> void:
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
	print("[MidgameRuntime] summary samples=%d cycles=%d elapsed=%.2f static_mb_start=%.2f static_mb_end=%.2f static_mb_delta=%.2f static_mb_peak=%.2f objects_start=%d objects_end=%d objects_delta=%d objects_peak=%d resources_start=%d resources_end=%d resources_delta=%d nodes_start=%d nodes_end=%d nodes_delta=%d orphan_nodes_end=%d ships=%d soldiers=%d projectiles=%d" % [
		_runtime_monitor_sample_count,
		_runtime_probe_cycle_index,
		_elapsed_time,
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
		int(_runtime_monitor_value(_runtime_monitor_last, "ships")),
		int(_runtime_monitor_value(_runtime_monitor_last, "soldiers")),
		int(_runtime_monitor_value(_runtime_monitor_last, "projectiles")),
	])


func _runtime_monitor_value(snapshot: Dictionary, key: String) -> float:
	return float(snapshot.get(key, 0.0))


func _update_support_probe_setup(delta: float) -> void:
	if _support_probe_setup_done:
		return
	if not _midgame_initialized:
		return
	_support_probe_setup_elapsed += delta
	if _support_probe_setup_elapsed < support_probe_setup_delay_seconds:
		return
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return
	_prepare_support_probe_player(player)
	_support_probe_setup_done = true


func _track_support_probe(delta: float) -> void:
	_maintain_support_probe_roster()
	if _support_probe_final_reported:
		return
	if not _support_probe_started:
		_support_probe_warmup_elapsed += delta
		if _support_probe_warmup_elapsed < support_probe_warmup_seconds:
			return
		_begin_support_probe()

	_support_probe_elapsed += delta
	_support_probe_sample_elapsed += delta
	_support_probe_frame_samples.append(delta)
	_support_probe_window_samples.append(delta)
	if _support_probe_profile_buckets and delta >= 0.05:
		_support_probe_profile_print_elapsed += delta
		if _support_probe_profile_print_elapsed >= 0.45:
			_support_probe_profile_print_elapsed = 0.0
			_print_support_probe_profile("slow_frame", delta)
	if _support_probe_sample_elapsed >= support_probe_sample_interval_seconds:
		_print_support_probe_sample()
	if _support_probe_elapsed >= support_probe_duration_seconds:
		_support_probe_final_reported = true
		_print_support_probe_summary()
		if _should_auto_quit_after_report():
			call_deferred("_quit_after_compare_report")


func _begin_support_probe() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if is_instance_valid(player):
		_prepare_support_probe_player(player)
	_support_probe_started = true
	_support_probe_elapsed = 0.0
	_support_probe_sample_elapsed = 0.0
	_support_probe_sample_index = 0
	_support_probe_frame_samples.clear()
	_support_probe_window_samples.clear()
	_support_probe_monitor_start.clear()
	_support_probe_monitor_last.clear()
	_support_probe_monitor_peak_static_bytes = 0.0
	_support_probe_monitor_peak_objects = 0.0
	_capture_support_probe_monitor_sample()
	var roster := _get_support_probe_roster_counts()
	print("[MidgameSupportPerf] start duration=%.1f warmup=%.1f sample_interval=%.1f formation=%s support_limit=%d support=%d panokseon_total=%d maengseon=%d wave_limit=%d wave_interval=%.1f" % [
		support_probe_duration_seconds,
		support_probe_warmup_seconds,
		support_probe_sample_interval_seconds,
		"wing" if support_probe_formation == SupportFleetStateHelper.FORMATION_WING else "column",
		support_probe_support_limit,
		int(roster.get("support", 0)),
		int(roster.get("panokseon_total", 0)),
		int(roster.get("maengseon", 0)),
		wave_limit,
		wave_interval,
	])


func _maintain_support_probe_player_motion() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return
	_stabilize_support_probe_ship(player, true)
	if "current_speed" in player:
		player.set("current_speed", support_probe_player_speed)
	if "is_rowing" in player:
		player.set("is_rowing", support_probe_player_speed > 0.0)


func _maintain_support_probe_roster() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return
	_maintain_support_probe_player_motion()
	var support_ships := _get_support_probe_support_ships()
	for support_ship in support_ships:
		if is_instance_valid(support_ship):
			_stabilize_support_probe_ship(support_ship, false)
	if support_ships.size() < support_probe_support_limit:
		_spawn_support_probe_fleet(player)
	else:
		_configure_support_probe_supports(player)


func _stabilize_support_probe_ship(ship: Node3D, is_flagship: bool) -> void:
	if not support_probe_lock_survival or not is_instance_valid(ship):
		return
	if "max_hull_hp" in ship:
		ship.set("max_hull_hp", maxf(float(ship.get("max_hull_hp")), 999999.0))
	if "hull_hp" in ship:
		var target_hull := 999999.0
		if "max_hull_hp" in ship:
			target_hull = maxf(float(ship.get("max_hull_hp")), target_hull)
		ship.set("hull_hp", target_hull)
	for bool_property in [
		"is_sinking",
		"is_dying",
		"is_derelict",
		"is_burning",
		"deck_is_overrun",
	]:
		if bool_property in ship:
			ship.set(bool_property, false)
	if "burn_timer" in ship:
		ship.set("burn_timer", 0.0)
	if "deck_hostile_boarder_count" in ship:
		ship.set("deck_hostile_boarder_count", 0)
	if is_flagship and "support_fleet_respawn_timer" in ship:
		ship.set("support_fleet_respawn_timer", 0.0)


func _capture_support_probe_monitor_sample() -> void:
	var snapshot := {
		"static_bytes": float(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"objects": float(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": float(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": float(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	if _support_probe_monitor_start.is_empty():
		_support_probe_monitor_start = snapshot.duplicate()
	_support_probe_monitor_last = snapshot.duplicate()
	_support_probe_monitor_peak_static_bytes = maxf(_support_probe_monitor_peak_static_bytes, _support_probe_monitor_value(snapshot, "static_bytes"))
	_support_probe_monitor_peak_objects = maxf(_support_probe_monitor_peak_objects, _support_probe_monitor_value(snapshot, "objects"))


func _print_support_probe_sample() -> void:
	_capture_support_probe_monitor_sample()
	_support_probe_sample_index += 1
	var stats := _summarize_delta_samples(_support_probe_window_samples)
	var roster := _get_support_probe_roster_counts()
	print("[MidgameSupportPerf] sample=%d elapsed=%.2f fps=%.1f avg=%.2fms p95=%.2fms p99=%.2fms max=%.2fms ships=%d enemies=%d support=%d panokseon_total=%d maengseon=%d soldiers=%d projectiles=%d static_mb=%.2f objects=%d nodes=%d" % [
		_support_probe_sample_index,
		_support_probe_elapsed,
		float(stats.get("fps", 0.0)),
		float(stats.get("avg_ms", 0.0)),
		float(stats.get("p95_ms", 0.0)),
		float(stats.get("p99_ms", 0.0)),
		float(stats.get("max_ms", 0.0)),
		_count_ships(),
		EntityRegistry.get_ships_by_team("enemy").size(),
		int(roster.get("support", 0)),
		int(roster.get("panokseon_total", 0)),
		int(roster.get("maengseon", 0)),
		_count_soldiers(),
		_count_projectiles(),
		_support_probe_monitor_value(_support_probe_monitor_last, "static_bytes") / 1048576.0,
		int(_support_probe_monitor_value(_support_probe_monitor_last, "objects")),
		int(_support_probe_monitor_value(_support_probe_monitor_last, "nodes")),
	])
	if _support_probe_profile_buckets:
		_print_support_probe_profile("sample_%d" % _support_probe_sample_index)
	_support_probe_window_samples.clear()
	_support_probe_sample_elapsed = 0.0


func _print_support_probe_profile(reason: String, frame_delta: float = -1.0) -> void:
	var header := "[MidgameSupportPerf] profile %s" % reason
	if frame_delta >= 0.0:
		header += " frame=%.2fms" % (frame_delta * 1000.0)
	print(header)
	for line in PhysicsFrameProfiler.build_summary_lines(14):
		print("[MidgameSupportPerf]   %s" % line)


func _print_support_probe_summary() -> void:
	if not _support_probe_window_samples.is_empty():
		_print_support_probe_sample()
	else:
		_capture_support_probe_monitor_sample()
	var stats := _summarize_delta_samples(_support_probe_frame_samples)
	var roster := _get_support_probe_roster_counts()
	var static_start_mb: float = _support_probe_monitor_value(_support_probe_monitor_start, "static_bytes") / 1048576.0
	var static_end_mb: float = _support_probe_monitor_value(_support_probe_monitor_last, "static_bytes") / 1048576.0
	print("[MidgameSupportPerf] summary duration=%.2f samples=%d fps=%.1f avg=%.2fms p95=%.2fms p99=%.2fms max=%.2fms ships=%d enemies=%d support=%d panokseon_total=%d maengseon=%d soldiers=%d projectiles=%d static_mb_start=%.2f static_mb_end=%.2f static_mb_delta=%.2f static_mb_peak=%.2f objects=%d objects_peak=%d resources=%d nodes=%d orphan_nodes=%d" % [
		_support_probe_elapsed,
		int(stats.get("sample_count", 0)),
		float(stats.get("fps", 0.0)),
		float(stats.get("avg_ms", 0.0)),
		float(stats.get("p95_ms", 0.0)),
		float(stats.get("p99_ms", 0.0)),
		float(stats.get("max_ms", 0.0)),
		_count_ships(),
		EntityRegistry.get_ships_by_team("enemy").size(),
		int(roster.get("support", 0)),
		int(roster.get("panokseon_total", 0)),
		int(roster.get("maengseon", 0)),
		_count_soldiers(),
		_count_projectiles(),
		static_start_mb,
		static_end_mb,
		static_end_mb - static_start_mb,
		_support_probe_monitor_peak_static_bytes / 1048576.0,
		int(_support_probe_monitor_value(_support_probe_monitor_last, "objects")),
		int(_support_probe_monitor_peak_objects),
		int(_support_probe_monitor_value(_support_probe_monitor_last, "resources")),
		int(_support_probe_monitor_value(_support_probe_monitor_last, "nodes")),
		int(_support_probe_monitor_value(_support_probe_monitor_last, "orphan_nodes")),
	])


func _summarize_delta_samples(samples: Array) -> Dictionary:
	var sample_count := samples.size()
	var total_delta := 0.0
	var max_delta := 0.0
	for sample in samples:
		var sample_delta: float = float(sample)
		total_delta += sample_delta
		max_delta = maxf(max_delta, sample_delta)
	var avg_delta := total_delta / float(sample_count) if sample_count > 0 else 0.0
	return {
		"fps": 1.0 / avg_delta if avg_delta > 0.0 else 0.0,
		"avg_ms": avg_delta * 1000.0,
		"p95_ms": _get_percentile_delta_ms(samples, 0.95),
		"p99_ms": _get_percentile_delta_ms(samples, 0.99),
		"max_ms": max_delta * 1000.0,
		"sample_count": sample_count,
	}


func _get_percentile_delta_ms(samples: Array, percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples: Array = samples.duplicate()
	sorted_samples.sort()
	var sample_index := clampi(int(ceil(float(sorted_samples.size()) * percentile)) - 1, 0, sorted_samples.size() - 1)
	return float(sorted_samples[sample_index]) * 1000.0


func _get_support_probe_roster_counts() -> Dictionary:
	var support_count := 0
	var maengseon_count := 0
	var panokseon_total := 0
	for ship in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(ship):
			continue
		var ship_type_name := str(ship.get("ship_type")).strip_edges().to_lower() if "ship_type" in ship else ""
		if ship_type_name.contains("panokseon"):
			panokseon_total += 1
		if ship.get_meta("support_fleet_ship", false) == true:
			support_count += 1
			if ship_type_name.contains("maengseon"):
				maengseon_count += 1
	return {
		"support": support_count,
		"panokseon_total": panokseon_total,
		"maengseon": maengseon_count,
	}


func _get_support_probe_support_ships() -> Array:
	var support_ships: Array = []
	for ship in EntityRegistry.get_ships_by_team("player"):
		if is_instance_valid(ship) and ship.get_meta("support_fleet_ship", false) == true:
			support_ships.append(ship)
	return support_ships


func _support_probe_monitor_value(snapshot: Dictionary, key: String) -> float:
	return float(snapshot.get(key, 0.0))


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay_panel):
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return

	_overlay_panel = PanelContainer.new()
	_overlay_panel.name = "MidgameFleetBattleOverlay"
	_overlay_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay_panel.offset_left = 20.0
	_overlay_panel.offset_top = 20.0
	_overlay_panel.offset_right = 500.0
	_overlay_panel.offset_bottom = 170.0
	_overlay_panel.z_index = 100
	_overlay_panel.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 10, 1, 10.0, 8.0, 10.0, 8.0)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_overlay_panel.add_child(box)

	var title := Label.new()
	title.text = "Midgame Fleet Battle"
	NavalUiTheme.style_heading(title, 14)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "wave / level / enemy count / visual load"
	NavalUiTheme.style_muted(hint, 10)
	box.add_child(hint)

	_overlay_label = Label.new()
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_body(_overlay_label, 12)
	box.add_child(_overlay_label)

	hud.add_child(_overlay_panel)
	_overlay_panel.visible = true


func _update_overlay() -> void:
	if not is_instance_valid(_overlay_label):
		return
	var level_manager: Node = LevelManagerRegistry.get_level_manager(get_tree())
	var current_time := float(level_manager.get("current_time")) if is_instance_valid(level_manager) and "current_time" in level_manager else midgame_time_seconds
	var current_difficulty := int(level_manager.get("game_difficulty")) if is_instance_valid(level_manager) and "game_difficulty" in level_manager else midgame_difficulty
	var next_wave_in := maxf(0.0, (initial_wave_delay if _wave_index < 0 else wave_interval) - _wave_elapsed)
	if battle_mode == BattleMode.VISUAL_COMPARE:
		_overlay_label.text = _build_visual_compare_text(current_difficulty, current_time, next_wave_in)
		return
	_overlay_label.text = "scenario:midgame_fleet_battle\nlevel:%d time:%.1fs target:%.1fs\nwave:%d/%d next:%.1fs last:%s\nships:%d soldiers:%d projectiles:%d elapsed:%.1fs" % [
		current_difficulty,
		current_time,
		midgame_time_seconds,
		maxi(_wave_index + 1, 0),
		wave_limit,
		next_wave_in,
		_last_spawned_fleet if not _last_spawned_fleet.is_empty() else "-",
		_count_ships(),
		_count_soldiers(),
		_count_projectiles(),
		_elapsed_time,
	]


func _build_visual_compare_text(current_difficulty: int, current_time: float, next_wave_in: float) -> String:
	var baseline: Dictionary = _summarize_compare_samples(0)
	var overlay: Dictionary = _summarize_compare_samples(1)
	var phase_name := "lean" if _compare_phase_index == 0 else "full"
	return "scenario:midgame_visual_compare phase:%s\nlean fps:%d avg:%.2fms p95:%.2fms | full fps:%d avg:%.2fms p95:%.2fms | delta:%.2fms\nships:%d soldiers:%d projectiles:%d\nlevel:%d time:%.1fs target:%.1fs wave:%d/%d next:%.1fs" % [
		phase_name,
		int(float(baseline.get("fps", 0.0))),
		float(baseline.get("avg_ms", 0.0)),
		_get_phase_p95_ms(0),
		int(float(overlay.get("fps", 0.0))),
		float(overlay.get("avg_ms", 0.0)),
		_get_phase_p95_ms(1),
		float(overlay.get("avg_ms", 0.0)) - float(baseline.get("avg_ms", 0.0)),
		_count_ships(),
		_count_soldiers(),
		_count_projectiles(),
		current_difficulty,
		current_time,
		midgame_time_seconds,
		maxi(_wave_index + 1, 0),
		wave_limit,
		next_wave_in,
	]


func _configure_compare_state() -> void:
	if battle_mode != BattleMode.VISUAL_COMPARE:
		return
	_compare_phase_index = 0
	_compare_phase_elapsed = 0.0
	_compare_warmup_elapsed = 0.0
	_compare_collecting = false
	_compare_phase_samples = [[], []]
	_set_compare_phase_enabled(false)


func _count_ships() -> int:
	return EntityRegistry.count_ships()


func _count_soldiers() -> int:
	return EntityRegistry.count_soldiers()


func _count_projectiles() -> int:
	return EntityRegistry.count_projectiles()


func _summarize_compare_samples(phase_index: int) -> Dictionary:
	var samples: Array = _compare_phase_samples[phase_index]
	var sample_count := samples.size()
	var total_delta := 0.0
	var max_delta := 0.0
	for sample in samples:
		var sample_delta: float = float(sample)
		total_delta += sample_delta
		max_delta = maxf(max_delta, sample_delta)
	var avg_delta := total_delta / float(sample_count) if sample_count > 0 else 0.0
	return {
		"fps": 1.0 / avg_delta if avg_delta > 0.0 else 0.0,
		"avg_ms": avg_delta * 1000.0,
		"max_ms": max_delta * 1000.0,
		"sample_count": sample_count,
	}


func _track_compare_sample(delta: float) -> void:
	if battle_mode != BattleMode.VISUAL_COMPARE:
		return
	if not _compare_collecting:
		_compare_warmup_elapsed += delta
		if _compare_warmup_elapsed < compare_warmup_seconds:
			return
		_compare_collecting = true
		_compare_phase_samples = [[], []]
		_compare_phase_elapsed = 0.0
	var phase_samples: Array = _compare_phase_samples[_compare_phase_index]
	phase_samples.append(delta)
	_compare_phase_samples[_compare_phase_index] = phase_samples
	_compare_phase_elapsed += delta
	if _compare_phase_index == 0 and _compare_phase_elapsed >= compare_phase_seconds:
		_compare_phase_index = 1
		_compare_phase_elapsed = 0.0
		_set_compare_phase_enabled(true)
		if auto_print_compare_results:
			_print_compare_phase_report("baseline", _summarize_compare_samples(0), _count_ships(), _count_soldiers(), _count_projectiles())
	elif _compare_phase_index == 1 and _compare_phase_elapsed >= compare_phase_seconds:
		_compare_phase_finished = true
		if auto_print_compare_results and not _compare_final_reported:
			_compare_final_reported = true
			_print_compare_final_report()


func _set_compare_phase_enabled(enabled: bool) -> void:
	if battle_mode != BattleMode.VISUAL_COMPARE:
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return
	if "show_stat_panel" in hud:
		hud.set("show_stat_panel", enabled)
	if "show_ship_health_bars" in hud:
		hud.set("show_ship_health_bars", enabled)
	if hud.has_method("_update_stat_panel"):
		hud.call("_update_stat_panel")
	if hud.has_method("_update_ship_health_bars"):
		hud.call("_update_ship_health_bars", false)
	if DistanceDebugVisualizer.runtime_enabled != enabled and hud.has_method("_toggle_distance_debug"):
		hud.call("_toggle_distance_debug")
	if enabled and hud.has_method("_ensure_distance_debug_visualizer"):
		hud.call("_ensure_distance_debug_visualizer")
	for ship in EntityRegistry.get_ships():
		if not is_instance_valid(ship):
			continue
		PreviewHarnessHelper.set_preview_deck_light_enabled(ship, enabled)


func _print_compare_phase_report(label: String, sample_stats: Dictionary, ships: int, soldiers: int, projectiles: int) -> void:
	var fps_value := float(sample_stats.get("fps", 0.0))
	var avg_ms := float(sample_stats.get("avg_ms", 0.0))
	var p95_ms := _get_phase_p95_ms(_compare_phase_index if label == "overlay" else 0)
	print("[MidgameBattle] %s fps=%.1f avg=%.2fms p95=%.2fms samples=%d ships=%d soldiers=%d projectiles=%d" % [
		label,
		fps_value,
		avg_ms,
		p95_ms,
		int(sample_stats.get("sample_count", 0)),
		ships,
		soldiers,
		projectiles,
	])


func _print_compare_final_report() -> void:
	var baseline: Dictionary = _summarize_compare_samples(0)
	var overlay: Dictionary = _summarize_compare_samples(1)
	var baseline_p95 := _get_phase_p95_ms(0)
	var overlay_p95 := _get_phase_p95_ms(1)
	print("[MidgameBattle] compare baseline fps=%.1f avg=%.2fms p95=%.2fms samples=%d" % [
		float(baseline.get("fps", 0.0)),
		float(baseline.get("avg_ms", 0.0)),
		baseline_p95,
		int(baseline.get("sample_count", 0)),
	])
	print("[MidgameBattle] compare overlay fps=%.1f avg=%.2fms p95=%.2fms samples=%d" % [
		float(overlay.get("fps", 0.0)),
		float(overlay.get("avg_ms", 0.0)),
		overlay_p95,
		int(overlay.get("sample_count", 0)),
	])
	print("[MidgameBattle] compare delta avg=%.2fms p95=%.2fms" % [
		float(overlay.get("avg_ms", 0.0)) - float(baseline.get("avg_ms", 0.0)),
		overlay_p95 - baseline_p95,
	])
	if _should_auto_quit_after_report():
		call_deferred("_quit_after_compare_report")


func _get_phase_p95_ms(phase_index: int) -> float:
	var samples: Array = _compare_phase_samples[phase_index]
	if samples.is_empty():
		return 0.0
	var sorted_samples: Array = samples.duplicate()
	sorted_samples.sort()
	var p95_index := clampi(int(ceil(float(sorted_samples.size()) * 0.95)) - 1, 0, sorted_samples.size() - 1)
	return float(sorted_samples[p95_index]) * 1000.0


func _should_auto_quit_after_report() -> bool:
	return _env_flag_enabled("BATTLESHIP_MIDGAME_AUTO_QUIT")


func _quit_after_compare_report() -> void:
	if auto_quit_delay_seconds > 0.0:
		await get_tree().create_timer(auto_quit_delay_seconds).timeout
	get_tree().quit(0)


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return _env_text_enabled(value)


func _env_text_enabled(value: String) -> bool:
	var normalized := value.strip_edges().to_lower()
	return normalized == "1" or normalized == "true" or normalized == "yes" or normalized == "on"
