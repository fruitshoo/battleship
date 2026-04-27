extends RefCounted
class_name NavalUiTheme

const FONT_DISPLAY = preload("res://assets/fonts/DeogonPrincessClassic.otf")
const FONT_DISPLAY_ALT = preload("res://assets/fonts/GyeonggiTitle-Bold.otf")
const FONT_BODY = preload("res://assets/fonts/GyeonggiBatang-Regular.otf")
const FONT_BODY_BOLD = preload("res://assets/fonts/GyeonggiBatang-Bold.otf")
const FONT_UI_REGULAR = preload("res://assets/fonts/MaruBuri-Regular.otf")
const FONT_UI_SEMIBOLD = preload("res://assets/fonts/MaruBuri-SemiBold.otf")
const FONT_UI_BOLD = preload("res://assets/fonts/MaruBuri-Bold.otf")

const FONT_REGULAR = FONT_UI_REGULAR
const FONT_MEDIUM = FONT_UI_REGULAR
const FONT_SEMIBOLD = FONT_UI_SEMIBOLD
const FONT_BOLD = FONT_UI_BOLD
const FONT_WORLD_SPEECH = FONT_UI_REGULAR
const FONT_WORLD_SPEECH_EMPHASIS = FONT_UI_SEMIBOLD
const FONT_WORLD_CALLOUT = FONT_UI_SEMIBOLD
const FONT_WORLD_HINT = FONT_UI_REGULAR
const FONT_WORLD_MARKER = FONT_UI_BOLD

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
	_apply_control_font(label, FONT_SEMIBOLD, font_size)
	label.add_theme_color_override("font_color", TEXT_ACCENT)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("shadow_outline_size", 2)


static func style_body(label: Label, font_size: int = 12) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_BODY, font_size)
	label.add_theme_color_override("font_color", TEXT_BODY)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("shadow_outline_size", 1)


static func style_muted(label: Label, font_size: int = 12) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_REGULAR, font_size)
	label.add_theme_color_override("font_color", TEXT_MUTED)


static func style_accent(label: Label, font_size: int = 13) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_SEMIBOLD, font_size)
	label.add_theme_color_override("font_color", TEXT_ACCENT)


static func style_gold(label: Label, font_size: int = 18) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_BOLD, font_size)
	label.add_theme_color_override("font_color", TEXT_GOLD)


static func style_overlay_value(label: Label, font_size: int = 11) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_BOLD, font_size)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", 3)


static func style_display_title(label: Label, font_size: int = 68) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_DISPLAY, font_size)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("shadow_outline_size", 2)
	label.add_theme_constant_override("outline_size", 1)


static func style_display_value(label: Label, font_size: int = 28) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_DISPLAY_ALT, font_size)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("shadow_outline_size", 3)


static func style_timer_value(label: Label, font_size: int = 28) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_UI_BOLD, font_size)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("shadow_outline_size", 2)


static func style_caption(label: Label, font_size: int = 13, color: Color = TEXT_BODY) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_MEDIUM, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("shadow_outline_size", 2)


static func style_status_banner(label: Label, font_size: int, color: Color, outline_size: int = 4) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_DISPLAY_ALT, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("shadow_outline_size", 2)
	label.add_theme_constant_override("outline_size", outline_size)


static func style_overlay_caption(label: Label, font_size: int = 10, color: Color = TEXT_MAIN, outline_size: int = 2) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_MEDIUM, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", outline_size)


static func style_tooltip_body(label: Label, font_size: int = 12) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_BODY, font_size)
	label.add_theme_constant_override("line_spacing", 2)
	label.add_theme_color_override("font_color", TEXT_BODY)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", 1)


static func style_loading_message(label: Label, font_size: int = 24) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_DISPLAY_ALT, font_size)
	label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82, 0.96))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)


static func resolve_emblem_text(token: String) -> String:
	var normalized := token.strip_edges()
	if normalized.is_empty():
		return "•"
	var emblem_map := {
		"analytics": "전",
		"adjust": "탄",
		"air": "풍",
		"apps": "문",
		"arrow_selector_tool": "궁",
		"auto_awesome": "보",
		"ballista": "궁",
		"bolt": "전",
		"boss_heart": "심",
		"build": "강",
		"cannon": "포",
		"cannon_damage": "철",
		"cannon_reload": "약",
		"chevron_right": "•",
		"crew_attack": "공",
		"crew_capacity": "병",
		"crew_defense": "방",
		"crew_health": "체",
		"diamond": "보",
		"directions_boat": "배",
		"explore": "항",
		"favorite": "심",
		"fire_pot": "화",
		"flag": "기",
		"fleet_crew": "원",
		"fleet_signal": "선",
		"fort": "판",
		"gold": "금",
		"grade": "치",
		"group": "병",
		"groups": "병",
		"health_and_safety": "갑",
			"healing": "회",
			"hull_defense": "갑",
			"hull_repair": "수",
			"hull_hp": "선",
		"hourglass_empty": "시",
		"janggun": "장",
		"local_fire_department": "화",
		"medical_services": "보",
		"monitoring": "D",
		"network_node": "철",
		"offline_bolt": "추",
		"paid": "금",
		"panokseon_upgrade": "판",
		"pickup_range": "탐",
		"radar": "탐",
		"refresh": "재",
		"reroll_stock": "재",
		"repeating_crossbow": "연",
		"rocket_launch": "신",
		"rowing": "노",
		"sailing": "돛",
		"sail_speed": "돛",
		"schedule": "시",
		"screen_edge_fx": "연",
		"shield": "방",
		"shield_person": "방",
		"singigeon": "신",
		"speed": "속",
		"sports_baseball": "포",
		"star": "별",
		"supply": "보",
		"supply_bonus": "보",
		"swords": "검",
		"sync_alt": "선",
		"timer": "장",
		"trending_down": "소",
		"trending_up": "증",
		"turn_right": "타",
		"update": "개",
		"water": "수",
		"xp_gain": "경",
	}
	if emblem_map.has(normalized):
		return str(emblem_map[normalized])
	if normalized.contains("_"):
		var pieces := normalized.split("_", false)
		var compact := ""
		for piece in pieces:
			if piece.is_empty():
				continue
			compact += piece.substr(0, 1).to_upper()
			if compact.length() >= 2:
				break
		if not compact.is_empty():
			return compact
	return normalized.substr(0, min(normalized.length(), 2)).to_upper()


static func apply_emblem(label: Label, token: String, font_size: int, color: Color = TEXT_ACCENT) -> void:
	if not is_instance_valid(label):
		return
	_apply_control_font(label, FONT_BOLD, font_size)
	label.text = resolve_emblem_text(token)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_DARK)
	label.add_theme_color_override("font_shadow_color", OUTLINE_DARK)
	label.add_theme_constant_override("outline_size", maxi(1, int(round(font_size * 0.12))))
	label.add_theme_constant_override("shadow_outline_size", 2)


static func make_emblem_frame_style(accent: Color, compact: bool = false) -> StyleBoxFlat:
	return make_panel_style(
		Color(0.05, 0.08, 0.12, 0.96),
		accent.lerp(BORDER_GOLD, 0.28),
		10 if compact else 12,
		1,
		0.0,
		0.0,
		0.0,
		0.0
	)


static func make_emblem_plate_style(accent: Color, compact: bool = false) -> StyleBoxFlat:
	return make_panel_style(
		Color(accent.r, accent.g, accent.b, 0.07),
		accent.lerp(BORDER_GOLD_SOFT, 0.16),
		10 if compact else 12,
		1,
		0.0,
		0.0,
		0.0,
		0.0
	)


static func make_hud_chip_style() -> StyleBoxFlat:
	return make_panel_style(PANEL_BG_SOFT, BORDER_GOLD_DIM, 9, 1, 8.0, 5.0, 8.0, 5.0)


static func make_tooltip_panel_style() -> StyleBoxFlat:
	var style := make_panel_style(PANEL_BG, BORDER_GOLD_SOFT, 8, 1, 12.0, 10.0, 12.0, 10.0)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	return style


static func make_support_slot_style(
	accent: Color = Color(0.84, 0.68, 0.35, 0.90),
	bg_color: Color = Color(0.05, 0.07, 0.10, 0.90),
	radius: int = 18,
	border_width: int = 1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = accent
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


static func make_support_slot_damage_style(radius: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.92, 0.24, 0.24, 0.76)
	style.set_corner_radius_all(radius)
	return style


static func make_support_slot_dead_style(radius: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.72)
	style.set_corner_radius_all(radius)
	return style


static func make_ship_hp_bar_background_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.06, 0.72)
	style.set_border_width_all(1)
	style.border_color = accent
	style.set_corner_radius_all(3)
	return style


static func make_ship_hp_bar_fill_style(color: Color = STATUS_GOOD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style


static func apply_menu_button(button: Button, font_size: int = 20) -> void:
	if not is_instance_valid(button):
		return
	_apply_control_font(button, FONT_SEMIBOLD, font_size)
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
	_apply_control_font(button, FONT_SEMIBOLD, font_size)
	button.add_theme_color_override("font_color", TEXT_MAIN)
	button.add_theme_color_override("font_hover_color", TEXT_ACCENT)
	button.add_theme_color_override("font_pressed_color", TEXT_ACCENT)
	button.add_theme_stylebox_override("normal", make_panel_style(PANEL_BG_SOFT, BORDER_GOLD_DIM, 8, 1, 12.0, 7.0, 12.0, 7.0))
	button.add_theme_stylebox_override("hover", make_panel_style(Color(0.14, 0.20, 0.27, 0.94), BORDER_GOLD, 8, 1, 12.0, 7.0, 12.0, 7.0))
	button.add_theme_stylebox_override("pressed", make_panel_style(Color(0.08, 0.12, 0.17, 0.96), BORDER_GOLD, 8, 1, 12.0, 7.0, 12.0, 7.0))
	button.add_theme_stylebox_override("focus", make_panel_style(Color(0.14, 0.20, 0.27, 0.94), BORDER_GOLD, 8, 1, 12.0, 7.0, 12.0, 7.0))


static func apply_menu_toggle(button: BaseButton, font_size: int = 13) -> void:
	if not is_instance_valid(button):
		return
	_apply_control_font(button, FONT_MEDIUM, font_size)
	button.add_theme_color_override("font_color", TEXT_BODY)
	button.add_theme_color_override("font_hover_color", TEXT_ACCENT)
	button.add_theme_color_override("font_pressed_color", TEXT_ACCENT)


static func apply_progress_bar(bar: ProgressBar, bg_color: Color, fill_color: Color, radius: int = 4) -> void:
	if not is_instance_valid(bar):
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.border_color = BORDER_GOLD_DIM
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("fill", fill)
	if bar.has_method("configure_gauge"):
		bar.configure_gauge(bg_color, fill_color, radius)


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


static func style_world_speech(label: Label3D, is_captain: bool, color: Color) -> void:
	if not is_instance_valid(label):
		return
	_apply_label3d_font(label, FONT_WORLD_SPEECH_EMPHASIS if is_captain else FONT_WORLD_SPEECH)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 88 if is_captain else 78
	label.outline_size = 8 if is_captain else 7
	label.extra_cull_margin = 20.0
	label.no_depth_test = true
	label.render_priority = 20
	label.outline_render_priority = 21
	label.modulate = color


static func style_world_callout(label: Label3D, font_size: int, color: Color) -> void:
	if not is_instance_valid(label):
		return
	_apply_label3d_font(label, FONT_WORLD_CALLOUT)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.outline_size = 6
	label.extra_cull_margin = 24.0
	label.no_depth_test = true
	label.render_priority = 20
	label.outline_render_priority = 21
	label.modulate = color


static func style_world_hint(label: Label3D, font_size: int, color: Color) -> void:
	if not is_instance_valid(label):
		return
	_apply_label3d_font(label, FONT_WORLD_HINT)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.outline_size = 6
	label.extra_cull_margin = 12.0
	label.modulate = color


static func style_world_marker(label: Label3D, font_size: int, color: Color) -> void:
	if not is_instance_valid(label):
		return
	_apply_label3d_font(label, FONT_WORLD_MARKER)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.outline_size = 5
	label.extra_cull_margin = 10.0
	label.modulate = color


static func _apply_control_font(control: Control, font_resource: Font, font_size: int) -> void:
	if not is_instance_valid(control):
		return
	if font_resource != null:
		control.add_theme_font_override("font", font_resource)
	control.add_theme_font_size_override("font_size", font_size)


static func _apply_label3d_font(label: Label3D, font_resource: Font) -> void:
	if not is_instance_valid(label) or font_resource == null:
		return
	label.set("font", font_resource)
