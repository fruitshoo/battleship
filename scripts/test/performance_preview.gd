extends Node3D

const ENEMY_MELEE_SCENE := preload("res://scenes/ships/enemy_melee_ship.tscn")
const ENEMY_GUNNER_SCENE := preload("res://scenes/ships/enemy_gunner_ship.tscn")
const ENEMY_FIREPOT_SCENE := preload("res://scenes/ships/enemy_firepot_ship.tscn")
const CANNONBALL_SCENE := preload("res://scenes/projectiles/cannonball.tscn")
const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")
const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

enum Scenario {
	IDLE,
	SHIP_DENSITY,
	BOARDING_STRESS,
	PROJECTILE_STRESS,
	FULL_COMBAT,
	OVERLAY_COMPARE,
}

@export var scenario: Scenario = Scenario.FULL_COMBAT
@export var auto_open_debug_panel: bool = true
@export var open_stat_panel: bool = true
@export var stop_regular_spawns: bool = true
@export var overlay_refresh_interval: float = 0.25
@export var sample_window_frames: int = 120
@export var melee_ship_count: int = 6
@export var gunner_ship_count: int = 6
@export var firepot_ship_count: int = 2
@export var projectile_count: int = 48
@export var ship_ring_radius: float = 24.0
@export var boarding_ring_radius: float = 9.0
@export var projectile_ring_radius: float = 42.0
@export var projectile_lifetime_multiplier: float = 3.0
@export var compare_phase_seconds: float = 3.0

var _overlay_panel: PanelContainer = null
var _overlay_label: Label = null
var _overlay_refresh_left: float = 0.0
var _elapsed_time: float = 0.0
var _frame_samples: Array[float] = []
var _compare_phase_samples: Array = [[], []]
var _compare_phase_elapsed: float = 0.0
var _compare_phase_index: int = 0
var _projectile_spawns: Array[Node] = []


func _ready() -> void:
	call_deferred("_configure_preview")


func _process(delta: float) -> void:
	_elapsed_time += delta
	_track_frame_sample(delta)
	_track_compare_sample(delta)
	_overlay_refresh_left = maxf(0.0, _overlay_refresh_left - delta)
	if _overlay_refresh_left <= 0.0:
		_overlay_refresh_left = overlay_refresh_interval
		_update_overlay()


func _configure_preview() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_ensure_stat_panel()
	_clear_existing_preview_spawns()
	_apply_scenario()
	_configure_compare_state()
	_ensure_overlay()
	_update_overlay()


func _ensure_stat_panel() -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return
	if "show_stat_panel" in hud:
		hud.set("show_stat_panel", open_stat_panel)
	if open_stat_panel and hud.has_method("_update_stat_panel"):
		hud.call("_update_stat_panel")


func _clear_existing_preview_spawns() -> void:
	PreviewHarnessHelper.clear_preview_enemies(self, "performance_preview_spawn")
	for child in get_children():
		if child is Node and child.has_meta("performance_preview_projectile"):
			child.queue_free()
	_projectile_spawns.clear()


func _apply_scenario() -> void:
	var player: Node3D = get_node_or_null("PlayerShip")
	if not is_instance_valid(player):
		return

	_preview_reset_player_state(player)

	match scenario:
		Scenario.IDLE:
			pass
		Scenario.SHIP_DENSITY:
			_spawn_ship_density(player)
		Scenario.BOARDING_STRESS:
			PreviewHarnessHelper.apply_preview_deck_state(player, true, false)
			_spawn_boarding_stress(player)
		Scenario.PROJECTILE_STRESS:
			_spawn_projectile_stress(player)
		Scenario.FULL_COMBAT:
			PreviewHarnessHelper.apply_preview_deck_state(player, true, false)
			_spawn_ship_density(player)
			_spawn_projectile_stress(player)
		Scenario.OVERLAY_COMPARE:
			PreviewHarnessHelper.apply_preview_deck_state(player, true, false)
			_spawn_ship_density(player)
			_spawn_projectile_stress(player)


func _preview_reset_player_state(player: Node3D) -> void:
	PreviewHarnessHelper.apply_preview_deck_state(player, false, false)


func _spawn_ship_density(player: Node3D) -> void:
	_spawn_ring_ships(ENEMY_MELEE_SCENE, melee_ship_count, player, ship_ring_radius, "performance_preview_spawn")
	_spawn_ring_ships(ENEMY_GUNNER_SCENE, gunner_ship_count, player, ship_ring_radius * 1.15, "performance_preview_spawn")
	_spawn_ring_ships(ENEMY_FIREPOT_SCENE, firepot_ship_count, player, ship_ring_radius * 0.85, "performance_preview_spawn")


func _spawn_boarding_stress(player: Node3D) -> void:
	_spawn_ring_ships(ENEMY_MELEE_SCENE, max(8, melee_ship_count * 2), player, boarding_ring_radius, "performance_preview_spawn")


func _spawn_projectile_stress(player: Node3D) -> void:
	var count: int = maxi(1, projectile_count)
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var radial := Vector3(cos(angle), 0.0, sin(angle)).normalized()
		var spawn_pos := player.global_position + radial * projectile_ring_radius + Vector3(0.0, 1.4, 0.0)
		_spawn_cannonball(spawn_pos, radial, "enemy")


func _spawn_ring_ships(scene: PackedScene, count: int, player: Node3D, radius: float, meta_name: String) -> void:
	if count <= 0:
		return
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var radial := Vector3(cos(angle), 0.0, sin(angle)).normalized()
		var world_pos := player.global_position + radial * radius
		_spawn_ship(scene, world_pos, player, meta_name)


func _spawn_ship(scene: PackedScene, world_pos: Vector3, player: Node3D, meta_name: String) -> void:
	var ship := scene.instantiate()
	if ship == null:
		return
	add_child(ship)
	ship.set_meta(meta_name, true)
	if ship is Node3D:
		ship.global_position = world_pos
		ship.look_at(player.global_position, Vector3.UP)
	PreviewHarnessHelper.assign_preview_target(ship, player)


func _spawn_cannonball(world_pos: Vector3, direction: Vector3, team: String) -> void:
	var cannonball := CANNONBALL_SCENE.instantiate()
	if cannonball == null:
		return
	add_child(cannonball)
	cannonball.set_meta("performance_preview_projectile", true)
	_projectile_spawns.append(cannonball)
	if cannonball.has_method("launch"):
		cannonball.call(
			"launch",
			world_pos,
			team,
			direction,
			null,
			1.0,
			projectile_lifetime_multiplier,
			"roundshot"
		)
	elif cannonball is Node3D:
		var projectile := cannonball as Node3D
		projectile.global_position = world_pos
		projectile.look_at(world_pos + direction, Vector3.UP)


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay_panel):
		return
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return

	_overlay_panel = PanelContainer.new()
	_overlay_panel.name = "PerformanceOverlay"
	_overlay_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_overlay_panel.offset_left = 20.0
	_overlay_panel.offset_top = 20.0
	_overlay_panel.offset_right = 450.0
	_overlay_panel.offset_bottom = 150.0
	_overlay_panel.z_index = 100
	_overlay_panel.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 10, 1, 10.0, 8.0, 10.0, 8.0)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_overlay_panel.add_child(box)

	var title := Label.new()
	title.text = "Performance Preview"
	NavalUiTheme.style_heading(title, 14)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "scenario / fps / frame time / ship counts"
	NavalUiTheme.style_muted(hint, 10)
	box.add_child(hint)

	_overlay_label = Label.new()
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_body(_overlay_label, 12)
	box.add_child(_overlay_label)

	hud.add_child(_overlay_panel)
	_overlay_panel.visible = true


func _configure_compare_state() -> void:
	if scenario != Scenario.OVERLAY_COMPARE:
		return
	_compare_phase_index = 0
	_compare_phase_elapsed = 0.0
	_compare_phase_samples = [[], []]
	_set_stat_panel_enabled(false)
	_set_distance_debug_enabled(false)


func _track_compare_sample(delta: float) -> void:
	if scenario != Scenario.OVERLAY_COMPARE:
		return
	var phase_samples: Array = _compare_phase_samples[_compare_phase_index]
	phase_samples.append(delta)
	_compare_phase_samples[_compare_phase_index] = phase_samples
	_compare_phase_elapsed += delta
	if _compare_phase_index == 0 and _compare_phase_elapsed >= compare_phase_seconds:
		_compare_phase_index = 1
		_compare_phase_elapsed = 0.0
		_set_stat_panel_enabled(true)
		_set_distance_debug_enabled(true)


func _track_frame_sample(delta: float) -> void:
	_frame_samples.append(delta)
	if _frame_samples.size() > sample_window_frames:
		_frame_samples.pop_front()


func _update_overlay() -> void:
	if not is_instance_valid(_overlay_label):
		return
	if scenario == Scenario.OVERLAY_COMPARE:
		_overlay_label.text = _build_compare_overlay_text()
		return
	var sample_count := _frame_samples.size()
	var avg_delta := 0.0
	var max_delta := 0.0
	for sample in _frame_samples:
		var sample_delta: float = float(sample)
		avg_delta += sample_delta
		max_delta = maxf(max_delta, sample_delta)
	if sample_count > 0:
		avg_delta /= float(sample_count)

	var avg_ms := avg_delta * 1000.0
	var max_ms := max_delta * 1000.0
	var fps_now := float(Engine.get_frames_per_second())

	_overlay_label.text = "scenario:%s\nfps:%d avg:%.1f frame:%.2fms max:%.2fms\nships:%d soldiers:%d projectiles:%d\nelapsed:%.1fs samples:%d" % [
		_get_scenario_name(),
		int(fps_now),
		(1000.0 / maxf(avg_ms, 0.001)),
		avg_ms,
		max_ms,
		_count_ships(),
		_count_soldiers(),
		_count_projectiles(),
		_elapsed_time,
		sample_count,
	]


func _build_compare_overlay_text() -> String:
	var baseline: Dictionary = _summarize_phase_samples(0)
	var overlay: Dictionary = _summarize_phase_samples(1)
	var phase_name := "baseline" if _compare_phase_index == 0 else "overlay"
	return "scenario:overlay_compare phase:%s\nbase fps:%d avg:%.2fms | overlay fps:%d avg:%.2fms | delta:%.2fms\nstat:%s distance:%s ships:%d soldiers:%d projectiles:%d" % [
		phase_name,
		int(float(baseline.get("fps", 0.0))),
		float(baseline.get("avg_ms", 0.0)),
		int(float(overlay.get("fps", 0.0))),
		float(overlay.get("avg_ms", 0.0)),
		float(overlay.get("avg_ms", 0.0)) - float(baseline.get("avg_ms", 0.0)),
		"ON" if bool(baseline.get("stat_enabled", false)) or bool(overlay.get("stat_enabled", false)) else "OFF",
		"ON" if bool(baseline.get("distance_enabled", false)) or bool(overlay.get("distance_enabled", false)) else "OFF",
		_count_ships(),
		_count_soldiers(),
		_count_projectiles(),
	]


func _summarize_phase_samples(phase_index: int) -> Dictionary:
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
		"stat_enabled": phase_index == 1,
		"distance_enabled": phase_index == 1,
	}


func _set_stat_panel_enabled(enabled: bool) -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return
	if "show_stat_panel" in hud:
		hud.set("show_stat_panel", enabled)
	if hud.has_method("_update_stat_panel"):
		hud.call("_update_stat_panel")


func _set_distance_debug_enabled(enabled: bool) -> void:
	var hud: Node = get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		return
	if DistanceDebugVisualizer.runtime_enabled != enabled and hud.has_method("_toggle_distance_debug"):
		hud.call("_toggle_distance_debug")
	if enabled and hud.has_method("_ensure_distance_debug_visualizer"):
		hud.call("_ensure_distance_debug_visualizer")


func _get_scenario_name() -> String:
	match scenario:
		Scenario.SHIP_DENSITY:
			return "ship_density"
		Scenario.BOARDING_STRESS:
			return "boarding_stress"
		Scenario.PROJECTILE_STRESS:
			return "projectile_stress"
		Scenario.FULL_COMBAT:
			return "full_combat"
		Scenario.OVERLAY_COMPARE:
			return "overlay_compare"
		_:
			return "idle"


func _count_ships() -> int:
	return get_tree().get_nodes_in_group("ships").size()


func _count_soldiers() -> int:
	return get_tree().get_nodes_in_group("soldiers").size()


func _count_projectiles() -> int:
	var count := 0
	for projectile in _projectile_spawns:
		if is_instance_valid(projectile):
			count += 1
	return count
