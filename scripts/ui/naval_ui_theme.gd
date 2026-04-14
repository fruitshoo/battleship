extends RefCounted
class_name NavalUiTheme

const PANEL_BG := Color(0.07, 0.11, 0.16, 0.82)
const PANEL_BG_SOFT := Color(0.10, 0.16, 0.22, 0.68)
const PANEL_BG_DARK := Color(0.05, 0.08, 0.12, 0.9)
const PANEL_GOLD_BG := Color(0.14, 0.12, 0.08, 0.76)

const BORDER_GOLD := Color(0.82, 0.69, 0.42, 0.92)
const BORDER_GOLD_SOFT := Color(0.80, 0.68, 0.41, 0.52)
const BORDER_GOLD_DIM := Color(0.55, 0.47, 0.27, 0.86)

const TEXT_MAIN := Color(0.95, 0.94, 0.90, 1.0)
const TEXT_BODY := Color(0.82, 0.86, 0.91, 1.0)
const TEXT_MUTED := Color(0.62, 0.70, 0.79, 1.0)
const TEXT_GOLD := Color(0.96, 0.83, 0.43, 1.0)
const TEXT_ACCENT := Color(1.0, 0.91, 0.68, 1.0)
const TEXT_BLUE := Color(0.77, 0.88, 0.96, 1.0)

const OUTLINE_DARK := Color(0.06, 0.09, 0.12, 0.95)
const STATUS_GOOD := Color(0.24, 0.86, 0.34, 0.95)
const STATUS_WARN := Color(0.96, 0.78, 0.18, 0.95)
const STATUS_DANGER := Color(0.92, 0.24, 0.24, 0.95)
const STATUS_DEAD := Color(0.34, 0.31, 0.27, 0.50)
const STATUS_ACTIVE_BLUE := Color(0.64, 0.78, 0.88, 0.94)


static func make_panel_style(
	bg_color: Color = PANEL_BG,
	border_color: Color = BORDER_GOLD_SOFT,
	radius: int = 12,
	border_width: int = 1,
	margin_left: float = 12.0,
	margin_top: float = 10.0,
	margin_right: float = 12.0,
	margin_bottom: float = 10.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_left
	style.content_margin_top = margin_top
	style.content_margin_right = margin_right
	style.content_margin_bottom = margin_bottom
	return style


static func make_menu_frame_style() -> StyleBoxFlat:
	return make_panel_style(PANEL_BG_SOFT, BORDER_GOLD_SOFT, 22, 2, 32.0, 28.0, 32.0, 28.0)


static func make_gold_panel_style() -> StyleBoxFlat:
	return make_panel_style(PANEL_GOLD_BG, BORDER_GOLD, 14, 1, 18.0, 14.0, 18.0, 14.0)


static func make_hud_panel_style() -> StyleBoxFlat:
	return make_panel_style(PANEL_BG, BORDER_GOLD_SOFT, 10, 1, 10.0, 8.0, 10.0, 8.0)


static func make_hud_panel_compact_style() -> StyleBoxFlat:
	return make_panel_style(PANEL_BG_SOFT, BORDER_GOLD_SOFT, 8, 1, 8.0, 6.0, 8.0, 6.0)


static func make_button_style(state: String = "normal") -> StyleBoxFlat:
	var bg_color := PANEL_BG_SOFT
	var border_color := BORDER_GOLD_SOFT
	match state:
		"hover":
			bg_color = Color(0.16, 0.23, 0.31, 0.92)
			border_color = BORDER_GOLD
		"pressed":
			bg_color = Color(0.09, 0.13, 0.18, 0.96)
			border_color = Color(0.93, 0.84, 0.56, 0.96)
		"focus":
			bg_color = Color(0.16, 0.23, 0.31, 0.92)
			border_color = BORDER_GOLD
	return make_panel_style(bg_color, border_color, 14, 1, 20.0, 12.0, 20.0, 12.0)


static func make_slot_style(
	panel_bg: Color = PANEL_BG_DARK,
	border_color: Color = BORDER_GOLD_DIM,
	radius: int = 6
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = panel_bg
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


static func style_heading(label: Label, font_size: int = 15) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_ACCENT)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("shadow_outline_size", 2)


static func style_body(label: Label, font_size: int = 12) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_BODY)


static func style_muted(label: Label, font_size: int = 12) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_MUTED)


static func style_accent(label: Label, font_size: int = 13) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_ACCENT)


static func style_gold(label: Label, font_size: int = 18) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_GOLD)


static func style_overlay_value(label: Label, font_size: int = 11) -> void:
	if not is_instance_valid(label):
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", 3)


static func apply_menu_button(button: Button, font_size: int = 20) -> void:
	if not is_instance_valid(button):
		return
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT_MAIN)
	button.add_theme_color_override("font_focus_color", TEXT_MAIN)
	button.add_theme_color_override("font_hover_color", TEXT_ACCENT)
	button.add_theme_color_override("font_pressed_color", TEXT_ACCENT)
	button.add_theme_stylebox_override("normal", make_button_style("normal"))
	button.add_theme_stylebox_override("hover", make_button_style("hover"))
	button.add_theme_stylebox_override("pressed", make_button_style("pressed"))
	button.add_theme_stylebox_override("focus", make_button_style("focus"))


static func apply_hud_button(button: Button, font_size: int = 11) -> void:
	if not is_instance_valid(button):
		return
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT_MAIN)
	button.add_theme_color_override("font_hover_color", TEXT_ACCENT)
	button.add_theme_color_override("font_pressed_color", TEXT_ACCENT)
	button.add_theme_stylebox_override("normal", make_panel_style(PANEL_BG_SOFT, BORDER_GOLD_DIM, 8, 1, 12.0, 7.0, 12.0, 7.0))
	button.add_theme_stylebox_override("hover", make_panel_style(Color(0.14, 0.20, 0.27, 0.94), BORDER_GOLD, 8, 1, 12.0, 7.0, 12.0, 7.0))
	button.add_theme_stylebox_override("pressed", make_panel_style(Color(0.08, 0.12, 0.17, 0.96), BORDER_GOLD, 8, 1, 12.0, 7.0, 12.0, 7.0))
	button.add_theme_stylebox_override("focus", make_panel_style(Color(0.14, 0.20, 0.27, 0.94), BORDER_GOLD, 8, 1, 12.0, 7.0, 12.0, 7.0))


static func apply_progress_bar(bar: ProgressBar, bg_color: Color, fill_color: Color, radius: int = 4) -> void:
	if not is_instance_valid(bar):
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("fill", fill)


static func apply_slider(slider: Slider, bg_color: Color, fill_color: Color, radius: int = 4) -> void:
	if not is_instance_valid(slider):
		return
	var rail := StyleBoxFlat.new()
	rail.bg_color = bg_color
	rail.set_corner_radius_all(radius)
	rail.content_margin_top = 4.0
	rail.content_margin_bottom = 4.0
	slider.add_theme_stylebox_override("slider", rail)

	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = fill_color
	grabber_area.set_corner_radius_all(radius)
	grabber_area.content_margin_top = 4.0
	grabber_area.content_margin_bottom = 4.0
	slider.add_theme_stylebox_override("grabber_area", grabber_area)
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_area)
