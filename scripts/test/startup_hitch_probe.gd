extends Node3D

const ENEMY_GUNNER_SCENE := preload("res://scenes/ships/enemy_gunner_ship.tscn")

@export var auto_open_debug_panel: bool = false
@export var stop_regular_spawns: bool = true
@export var enemy_spawn_delay_seconds: float = 2.0
@export var probe_duration_seconds: float = 8.0
@export var hitch_report_threshold_ms: float = 28.0
@export var hitch_fail_threshold_ms: float = 48.0
@export var enemy_distance: float = 15.0
@export var enemy_lateral_offset: float = 0.0
@export var top_spike_count: int = 8
@export var count_event_limit: int = 24

var _elapsed: float = 0.0
var _samples: Array[float] = []
var _spikes: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _enemy_spawned: bool = false
var _projectile_seen: bool = false
var _audio_event_seen: bool = false
var _finished: bool = false
var _configured: bool = false
var _count_events_emitted: int = 0
var _seen_projectile_ids: Dictionary = {}
var _seen_projectile_types: Dictionary = {}
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_configure_probe")


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	var frame_ms: float = delta * 1000.0
	_samples.append(frame_ms)
	if frame_ms >= hitch_report_threshold_ms:
		var snapshot := _build_state_snapshot()
		snapshot["time"] = _elapsed
		snapshot["ms"] = frame_ms
		snapshot["event"] = _nearest_event_label(_elapsed)
		_spikes.append(snapshot)

	if _configured:
		_poll_state_events()

	if not _enemy_spawned and _elapsed >= enemy_spawn_delay_seconds:
		_spawn_probe_enemy()

	if _elapsed >= probe_duration_seconds:
		_finish_probe()


func _poll_state_events() -> void:
	var snapshot := _build_state_snapshot()
	if _last_snapshot.is_empty():
		_last_snapshot = snapshot
		return

	_mark_count_change("player_ships", int(_last_snapshot.get("player_ships", 0)), int(snapshot.get("player_ships", 0)))
	_mark_count_change("enemy_ships", int(_last_snapshot.get("enemy_ships", 0)), int(snapshot.get("enemy_ships", 0)))
	_mark_count_change("support_ships", int(_last_snapshot.get("support_ships", 0)), int(snapshot.get("support_ships", 0)))
	_mark_count_change("soldiers", int(_last_snapshot.get("soldiers", 0)), int(snapshot.get("soldiers", 0)))
	_mark_count_change("projectiles", int(_last_snapshot.get("projectiles", 0)), int(snapshot.get("projectiles", 0)))
	_mark_value_change("level", _last_snapshot.get("level", 0), snapshot.get("level", 0))
	_mark_value_change("difficulty", _last_snapshot.get("difficulty", 0), snapshot.get("difficulty", 0))
	_mark_value_change("score", _last_snapshot.get("score", 0), snapshot.get("score", 0))
	_mark_value_change("paused", _last_snapshot.get("paused", false), snapshot.get("paused", false))
	_mark_new_projectiles()
	_last_snapshot = snapshot


func _mark_count_change(label: String, previous: int, current: int) -> void:
	if previous == current or _count_events_emitted >= count_event_limit:
		return
	_count_events_emitted += 1
	_mark_event("%s_%d_to_%d" % [label, previous, current])


func _mark_value_change(label: String, previous: Variant, current: Variant) -> void:
	if previous == current or _count_events_emitted >= count_event_limit:
		return
	_count_events_emitted += 1
	_mark_event("%s_%s_to_%s" % [label, str(previous), str(current)])


func _mark_new_projectiles() -> void:
	for projectile in EntityRegistry.get_projectiles():
		if not is_instance_valid(projectile):
			continue
		var instance_id: int = projectile.get_instance_id()
		if _seen_projectile_ids.has(instance_id):
			continue
		_seen_projectile_ids[instance_id] = true
		var projectile_type := _describe_node(projectile)
		if not _projectile_seen:
			_projectile_seen = true
			_mark_event("first_projectile:%s" % projectile_type)
		if not _seen_projectile_types.has(projectile_type):
			_seen_projectile_types[projectile_type] = true
			_mark_event("first_projectile_type:%s" % projectile_type)


func _build_state_snapshot() -> Dictionary:
	return {
			"time": _elapsed,
			"ships": EntityRegistry.count_ships(),
			"soldiers": EntityRegistry.count_soldiers(),
			"projectiles": EntityRegistry.count_projectiles(),
			"player_ships": EntityRegistry.count_ships_by_team("player"),
			"enemy_ships": EntityRegistry.count_ships_by_team("enemy"),
			"support_ships": _get_support_ship_count(),
			"level": _get_level_value("current_level"),
			"difficulty": _get_level_value("game_difficulty"),
			"score": _get_level_value("current_score"),
			"paused": get_tree().paused,
		}


func _configure_probe() -> void:
	PreviewHarnessHelper.setup_common(self, auto_open_debug_panel, stop_regular_spawns)
	_connect_manager_events()
	_last_snapshot = _build_state_snapshot()
	_configured = true
	_mark_event("probe_ready")
	if is_instance_valid(AudioManager):
		if AudioManager.get("is_prewarm_finished") == true:
			_mark_audio_prewarm_finished()
		elif AudioManager.has_signal("prewarm_finished"):
			AudioManager.prewarm_finished.connect(_mark_audio_prewarm_finished, CONNECT_ONE_SHOT)


func _connect_manager_events() -> void:
	var level_manager := LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(level_manager):
		if level_manager.has_signal("level_up"):
			level_manager.level_up.connect(func(new_level: int) -> void:
				_mark_event("level_up:%d" % new_level)
			)
		if level_manager.has_signal("score_changed"):
			level_manager.score_changed.connect(func(new_score: int) -> void:
				_mark_event("score_changed:%d" % new_score)
			)
		if level_manager.has_signal("merit_full"):
			level_manager.merit_full.connect(func() -> void:
				_mark_event("merit_full")
			)
		if level_manager.has_signal("merit_changed"):
			level_manager.merit_changed.connect(func(current: int, maximum: int, level: int) -> void:
				_mark_event("merit_changed:%d/%d:L%d" % [current, maximum, level])
			)
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_signal("upgrade_applied"):
		UpgradeManager.upgrade_applied.connect(func(upgrade_id: String, new_level: int) -> void:
			_mark_event("upgrade_applied:%s:%d" % [upgrade_id, new_level])
		)


func _mark_audio_prewarm_finished() -> void:
	if _audio_event_seen:
		return
	_audio_event_seen = true
	_mark_event("audio_prewarm_finished")


func _spawn_probe_enemy() -> void:
	_enemy_spawned = true
	var player := get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player):
		_mark_event("enemy_spawn_failed_no_player")
		return
	var enemy := ENEMY_GUNNER_SCENE.instantiate() as Node3D
	if not is_instance_valid(enemy):
		_mark_event("enemy_spawn_failed_instantiate")
		return
	enemy.name = "StartupHitchEnemy"
	enemy.set_meta("startup_hitch_probe_spawn", true)
	add_child(enemy)
	var forward := -player.global_basis.z.normalized()
	var right := player.global_basis.x.normalized()
	enemy.global_position = player.global_position + forward * enemy_distance + right * enemy_lateral_offset
	enemy.look_at(player.global_position, Vector3.UP)
	PreviewHarnessHelper.assign_preview_target(enemy, player)
	_mark_event("enemy_spawned")


func _mark_event(event_name: String) -> void:
	var snapshot := _build_state_snapshot()
	snapshot["name"] = event_name
	_events.append(snapshot)
	print("[StartupHitch] event time=%.3f name=%s ships=%d player=%d enemy=%d support=%d soldiers=%d projectiles=%d level=%d difficulty=%d score=%d paused=%s" % [
		_elapsed,
		event_name,
		int(snapshot.get("ships", 0)),
		int(snapshot.get("player_ships", 0)),
		int(snapshot.get("enemy_ships", 0)),
		int(snapshot.get("support_ships", 0)),
		int(snapshot.get("soldiers", 0)),
		int(snapshot.get("projectiles", 0)),
		int(snapshot.get("level", 0)),
		int(snapshot.get("difficulty", 0)),
		int(snapshot.get("score", 0)),
		str(snapshot.get("paused", false)),
	])


func _finish_probe() -> void:
	_finished = true
	var summary := _build_summary()
	print("[StartupHitch] summary frames=%d avg_ms=%.2f p95_ms=%.2f max_ms=%.2f spikes=%d threshold_ms=%.1f first_projectile=%s" % [
		int(summary.get("frames", 0)),
		float(summary.get("avg_ms", 0.0)),
		float(summary.get("p95_ms", 0.0)),
		float(summary.get("max_ms", 0.0)),
		_spikes.size(),
		hitch_report_threshold_ms,
		"Y" if _projectile_seen else "N",
	])
	_print_top_spikes()
	var should_fail: bool = _env_flag_enabled("BATTLESHIP_HITCH_FAIL")
	if should_fail and float(summary.get("max_ms", 0.0)) >= hitch_fail_threshold_ms:
		push_error("[StartupHitch] max_ms %.2f exceeded fail threshold %.2f" % [float(summary.get("max_ms", 0.0)), hitch_fail_threshold_ms])
		get_tree().quit(1)
		return
	get_tree().quit(0)


func _build_summary() -> Dictionary:
	var count := _samples.size()
	if count <= 0:
		return {"frames": 0, "avg_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0}
	var total: float = 0.0
	var max_ms: float = 0.0
	for sample in _samples:
		total += sample
		max_ms = maxf(max_ms, sample)
	var sorted_samples: Array = _samples.duplicate()
	sorted_samples.sort()
	var p95_index: int = clampi(int(ceil(float(count) * 0.95)) - 1, 0, count - 1)
	return {
		"frames": count,
		"avg_ms": total / float(count),
		"p95_ms": float(sorted_samples[p95_index]),
		"max_ms": max_ms,
	}


func _print_top_spikes() -> void:
	if _spikes.is_empty():
		print("[StartupHitch] top_spikes none")
		return
	var sorted_spikes: Array = _spikes.duplicate()
	sorted_spikes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("ms", 0.0)) > float(b.get("ms", 0.0))
	)
	var limit: int = mini(top_spike_count, sorted_spikes.size())
	for index in range(limit):
		var spike: Dictionary = sorted_spikes[index]
		print("[StartupHitch] top%d time=%.3f ms=%.2f near=%s ships=%d player=%d enemy=%d support=%d soldiers=%d projectiles=%d level=%d difficulty=%d score=%d paused=%s" % [
			index + 1,
			float(spike.get("time", 0.0)),
			float(spike.get("ms", 0.0)),
			str(spike.get("event", "-")),
			int(spike.get("ships", 0)),
			int(spike.get("player_ships", 0)),
			int(spike.get("enemy_ships", 0)),
			int(spike.get("support_ships", 0)),
			int(spike.get("soldiers", 0)),
			int(spike.get("projectiles", 0)),
			int(spike.get("level", 0)),
			int(spike.get("difficulty", 0)),
			int(spike.get("score", 0)),
			str(spike.get("paused", false)),
		])


func _nearest_event_label(time_seconds: float) -> String:
	if _events.is_empty():
		return "-"
	var nearest_name: String = "-"
	var nearest_time: float = 0.0
	var nearest_delta: float = INF
	for event in _events:
		var delta: float = absf(time_seconds - float(event.get("time", 0.0)))
		if delta < nearest_delta:
			nearest_delta = delta
			nearest_name = str(event.get("name", "-"))
			nearest_time = float(event.get("time", 0.0))
	return "%s %+0.3fs" % [nearest_name, time_seconds - nearest_time]


func _get_support_ship_count() -> int:
	var player := get_node_or_null("PlayerShip")
	if is_instance_valid(player) and player.has_method("_get_support_fleet_ships"):
		return player.call("_get_support_fleet_ships").size()
	var count := 0
	for ship in EntityRegistry.get_ships_by_team("player"):
		if is_instance_valid(ship) and ship.get_meta("support_fleet_ship", false) == true:
			count += 1
	return count


func _get_level_value(property_name: String) -> int:
	var level_manager := LevelManagerRegistry.get_level_manager(get_tree())
	if not is_instance_valid(level_manager):
		return 0
	var value: Variant = level_manager.get(property_name)
	if value == null:
		return 0
	return int(value)


func _describe_node(node: Node) -> String:
	var script: Resource = node.get_script() as Resource
	if script != null and script.resource_path != "":
		return script.resource_path.get_file().get_basename()
	return node.scene_file_path.get_file().get_basename() if node.scene_file_path != "" else node.name


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
