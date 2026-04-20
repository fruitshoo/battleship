extends Node3D

const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")

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


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(delta: float) -> void:
	_elapsed_time += delta
	_wave_elapsed += delta
	if runtime_probe_enabled and battle_mode == BattleMode.STRESS:
		_runtime_probe_cycle_elapsed += delta
		_sample_runtime_monitors(delta)
		_handle_runtime_probe_cleanup()
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

	runtime_probe_enabled = runtime_probe_enabled or _env_flag_enabled("BATTLESHIP_MIDGAME_RUNTIME_PROBE")
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
	return value == "1" or value == "true" or value == "yes" or value == "on"
