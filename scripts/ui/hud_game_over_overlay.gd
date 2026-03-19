extends PanelContainer

signal return_requested

var subtitle_label: Label = null
var return_button: Button = null
var _countdown: float = -1.0
var _emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 400
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -180.0
	offset_top = 54.0
	offset_right = 180.0
	offset_bottom = 150.0

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.86, 0.32, 0.24, 0.9)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_bottom = 16.0
	add_theme_stylebox_override("panel", panel_style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_font_size_override("font_size", 14)
	subtitle_label.add_theme_color_override("font_color", Color(0.83, 0.86, 0.89))
	subtitle_label.text = "함선이 침몰했습니다. 항구로 복귀합니다."
	vbox.add_child(subtitle_label)

	return_button = Button.new()
	return_button.process_mode = Node.PROCESS_MODE_ALWAYS
	return_button.custom_minimum_size = Vector2(220.0, 42.0)
	return_button.text = "메인 메뉴로"
	return_button.pressed.connect(_request_return)
	vbox.add_child(return_button)

func _process(delta: float) -> void:
	if _countdown < 0.0 or _emitted:
		return
	_countdown = maxf(0.0, _countdown - delta)
	_update_button_text()
	if _countdown <= 0.0:
		_request_return()

func show_overlay(subtitle: String, countdown: float) -> void:
	_emitted = false
	_countdown = countdown
	if subtitle_label:
		subtitle_label.text = subtitle
	_update_button_text()
	visible = true
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.25)

func hide_overlay() -> void:
	_countdown = -1.0
	visible = false
	modulate.a = 1.0
	_emitted = false

func _update_button_text() -> void:
	if not is_instance_valid(return_button):
		return
	if _countdown < 0.0:
		return_button.text = "메인 메뉴로"
		return
	return_button.text = "메인 메뉴로 (%.0f)" % ceil(_countdown)

func _request_return() -> void:
	if _emitted:
		return
	_emitted = true
	_countdown = -1.0
	emit_signal("return_requested")
