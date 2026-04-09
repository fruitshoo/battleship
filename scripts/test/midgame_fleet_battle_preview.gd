extends Node3D

const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

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
@export var compare_phase_seconds: float = 12.0

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
var _midgame_initialized: bool = false


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(delta: float) -> void:
	_elapsed_time += delta
	_wave_elapsed += delta
	_track_compare_sample(delta)
	_overlay_refresh_left = maxf(0.0, _overlay_refresh_left - delta)
	if _overlay_refresh_left <= 0.0:
		_overlay_refresh_left = 0.25
		_update_overlay()
	if _midgame_initialized and battle_mode == BattleMode.STRESS:
		_maybe_spawn_next_wave()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_ensure_stat_panel()
	_configure_midgame_state()
	_clear_existing_preview_spawns()
	_spawn_battle_load()
	_configure_compare_state()
	_ensure_overlay()
	_update_overlay()


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

	var level_manager: Node = get_node_or_null("LevelManager")
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
	spawner.call("debug_spawn_fleet", fleet_class)
	_last_spawned_fleet = fleet_class


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
	var level_manager: Node = get_node_or_null("LevelManager")
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
	return "scenario:midgame_visual_compare phase:%s\nlean fps:%d avg:%.2fms | full fps:%d avg:%.2fms | delta:%.2fms\nships:%d soldiers:%d projectiles:%d\nlevel:%d time:%.1fs target:%.1fs wave:%d/%d next:%.1fs" % [
		phase_name,
		int(float(baseline.get("fps", 0.0))),
		float(baseline.get("avg_ms", 0.0)),
		int(float(overlay.get("fps", 0.0))),
		float(overlay.get("avg_ms", 0.0)),
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
	_compare_phase_samples = [[], []]
	_set_compare_phase_enabled(false)


func _count_ships() -> int:
	return get_tree().get_nodes_in_group("ships").size()


func _count_soldiers() -> int:
	return get_tree().get_nodes_in_group("soldiers").size()


func _count_projectiles() -> int:
	return _count_projectiles_recursive(get_tree().root)


func _count_projectiles_recursive(node: Node) -> int:
	if not is_instance_valid(node):
		return 0
	var count := 1 if str(node.scene_file_path).begins_with("res://scenes/projectiles/") else 0
	for child in node.get_children():
		if child is Node:
			count += _count_projectiles_recursive(child)
	return count


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
	var phase_samples: Array = _compare_phase_samples[_compare_phase_index]
	phase_samples.append(delta)
	_compare_phase_samples[_compare_phase_index] = phase_samples
	_compare_phase_elapsed += delta
	if _compare_phase_index == 0 and _compare_phase_elapsed >= compare_phase_seconds:
		_compare_phase_index = 1
		_compare_phase_elapsed = 0.0
		_set_compare_phase_enabled(true)


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
	for ship in get_tree().get_nodes_in_group("ships"):
		if not is_instance_valid(ship):
			continue
		PreviewHarnessHelper.set_preview_deck_light_enabled(ship, enabled)
