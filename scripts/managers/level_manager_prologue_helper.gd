class_name LevelManagerPrologueHelper
extends RefCounted

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

const ENV_SKIP_KEY := "BATTLESHIP_SKIP_PROLOGUE"
const FADE_OUT_SECONDS := 0.75

static func should_prepare(lm: Node) -> bool:
	if not bool(lm.prologue_enabled):
		return false
	if _is_prologue_env_flag_enabled(ENV_SKIP_KEY):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return true


static func prepare(lm: Node) -> void:
	lm._prologue_pending = true
	lm._prologue_active = false
	lm._prologue_stage_elapsed = 0.0


static func start_if_needed(lm: Node) -> void:
	if not bool(lm._prologue_pending) or bool(lm._prologue_active):
		return
	lm._prologue_active = true
	lm._prologue_stage_elapsed = 0.0
	lm._prologue_notice_layer = _create_notice_layer(lm)
	_set_notice_text(lm, _get_controls_text())


static func update_prologue(lm: Node, delta: float) -> void:
	if not bool(lm._prologue_active):
		return
	lm._prologue_stage_elapsed += delta
	if lm._prologue_stage_elapsed >= float(lm.prologue_intro_seconds):
		complete(lm, false)


static func handle_skip_input(lm: Node, event: InputEvent) -> bool:
	if not bool(lm._prologue_active):
		return false
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	if key_event.keycode != KEY_TAB and key_event.keycode != KEY_ESCAPE:
		return false
	complete(lm, true)
	return true


static func is_active_or_pending(lm: Node) -> bool:
	return bool(lm._prologue_active) or bool(lm._prologue_pending)


static func complete(lm: Node, skipped: bool) -> void:
	if not bool(lm._prologue_active) and not bool(lm._prologue_pending):
		return
	lm._prologue_active = false
	lm._prologue_pending = false
	if skipped:
		_remove_notice_layer(lm)
	else:
		_fade_out_notice_layer(lm)


static func toggle_controls_hint(lm: Node) -> void:
	lm._prologue_active = false
	lm._prologue_pending = false
	if is_instance_valid(lm._prologue_notice_layer):
		_remove_notice_layer(lm)
		return
	lm._prologue_notice_layer = _create_notice_layer(lm)
	_set_notice_text(lm, _get_controls_text())


static func _get_controls_text() -> String:
	return "WASD/방향키: 이동    Q/E: 돛 방향    R: 돛 접기/펼치기"


static func _create_notice_layer(lm: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "PrologueNoticeLayer"
	layer.layer = 85
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var label := Label.new()
	label.name = "NoticeLabel"
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_left = 300.0
	label.offset_top = -96.0
	label.offset_right = -300.0
	label.offset_bottom = -58.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(label, 15)
	label.add_theme_color_override("font_color", Color(0.93, 0.92, 0.86, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.92))
	label.add_theme_constant_override("outline_size", 3)
	layer.add_child(label)
	lm.add_child(layer)
	lm._prologue_notice_label = label
	return layer


static func _set_notice_text(lm: Node, text: String) -> void:
	if is_instance_valid(lm._prologue_notice_label):
		lm._prologue_notice_label.text = "%s    Tab/Esc: 건너뛰기" % text


static func _show_final_notice(lm: Node, text: String) -> void:
	if not is_instance_valid(lm._prologue_notice_layer):
		lm._prologue_notice_layer = _create_notice_layer(lm)
	_set_notice_text(lm, text)
	var layer: CanvasLayer = lm._prologue_notice_layer
	lm._prologue_notice_layer = null
	lm._prologue_notice_label = null
	lm.get_tree().create_timer(2.4).timeout.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
	)


static func _fade_out_notice_layer(lm: Node) -> void:
	if not is_instance_valid(lm._prologue_notice_layer):
		return
	var layer: CanvasLayer = lm._prologue_notice_layer
	lm._prologue_notice_layer = null
	lm._prologue_notice_label = null
	var tween := lm.create_tween()
	tween.tween_property(layer, "modulate:a", 0.0, FADE_OUT_SECONDS)
	tween.tween_callback(layer.queue_free)


static func _remove_notice_layer(lm: Node) -> void:
	if is_instance_valid(lm._prologue_notice_layer):
		lm._prologue_notice_layer.queue_free()
	lm._prologue_notice_layer = null
	lm._prologue_notice_label = null


static func _is_prologue_env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
