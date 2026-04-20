extends PanelContainer


const MIN_WIDTH: float = 320.0
const OFFSET := Vector2(18.0, 16.0)

var _label: Label = null
var _fade_tween: Tween = null

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 300
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	modulate = Color(1.0, 1.0, 1.0, 1.0)

	var tip_style = StyleBoxFlat.new()
	tip_style.bg_color = NavalUiTheme.PANEL_BG
	tip_style.border_color = NavalUiTheme.BORDER_GOLD_SOFT
	tip_style.border_width_top = 1
	tip_style.border_width_bottom = 1
	tip_style.border_width_left = 1
	tip_style.border_width_right = 1
	tip_style.set_corner_radius_all(8)
	tip_style.shadow_color = Color(0, 0, 0, 0.45)
	tip_style.shadow_size = 6
	tip_style.content_margin_left = 12
	tip_style.content_margin_right = 12
	tip_style.content_margin_top = 10
	tip_style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", tip_style)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_constant_override("line_spacing", 2)
	_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_BODY)
	_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
	_label.add_theme_constant_override("outline_size", 2)
	_label.custom_minimum_size = Vector2(MIN_WIDTH - 24.0, 0.0)
	add_child(_label)

func show_tooltip(text: String, accent_color: Color, mouse_pos: Vector2, viewport_size: Vector2) -> void:
	if not is_instance_valid(_label):
		return
	_label.text = text
	_apply_theme(accent_color)
	visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	update_position(mouse_pos, viewport_size)

func hide_tooltip(instant: bool = false) -> void:
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null
	if instant or not visible:
		visible = false
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fade_tween.finished.connect(_finish_hide, CONNECT_ONE_SHOT)

func update_position(mouse_pos: Vector2, viewport_size: Vector2) -> void:
	if not visible:
		return
	var panel_size = size
	if panel_size.x <= 1.0:
		panel_size = custom_minimum_size
	var pos = mouse_pos + OFFSET
	pos.x = clampf(pos.x, 12.0, maxf(12.0, viewport_size.x - panel_size.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, viewport_size.y - panel_size.y - 12.0))
	position = pos

func is_showing() -> bool:
	return visible

func _apply_theme(accent_color: Color) -> void:
	var tip_style = get_theme_stylebox("panel")
	if not (tip_style is StyleBoxFlat):
		return
	var style_copy = (tip_style as StyleBoxFlat).duplicate()
	var accent = accent_color.lerp(Color.WHITE, 0.15)
	accent.a = 0.95
	style_copy.border_color = accent.lerp(NavalUiTheme.BORDER_GOLD, 0.3)
	add_theme_stylebox_override("panel", style_copy)

func _finish_hide() -> void:
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 1.0)
