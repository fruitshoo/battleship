extends RefCounted
class_name ModalMenuSkin


static func apply_modal_shell(
	panel_container: PanelContainer,
	title_label: Label,
	subtitle_label: Label,
	compact: bool = false
) -> void:
	if is_instance_valid(panel_container):
		panel_container.add_theme_stylebox_override("panel", _make_modal_panel_style(compact))
	if is_instance_valid(title_label):
		NavalUiTheme.style_display_title(title_label, 40 if compact else 48)
	if is_instance_valid(subtitle_label):
		NavalUiTheme.style_caption(subtitle_label, 13 if compact else 14, NavalUiTheme.TEXT_BODY)


static func apply_modal_section_panel(panel_container: PanelContainer, compact: bool = false) -> void:
	if not is_instance_valid(panel_container):
		return
	panel_container.add_theme_stylebox_override("panel", _make_modal_section_style(compact))


static func apply_action_button_theme(button: Button, emphasized: bool = false, compact: bool = false) -> void:
	if not is_instance_valid(button):
		return
	button.focus_mode = Control.FOCUS_ALL
	NavalUiTheme.apply_menu_button(button, 17 if compact else 18)
	button.add_theme_stylebox_override("normal", _make_action_button_style("normal", emphasized, compact))
	button.add_theme_stylebox_override("hover", _make_action_button_style("hover", emphasized, compact))
	button.add_theme_stylebox_override("pressed", _make_action_button_style("pressed", emphasized, compact))
	button.add_theme_stylebox_override("focus", _make_action_button_style("focus", emphasized, compact))


static func apply_pause_shell(
	panel_container: PanelContainer,
	eyebrow_wrap: PanelContainer,
	eyebrow_label: Label,
	title_label: Label,
	subtitle_label: Label,
	divider: ColorRect,
	footer_hint_label: Label
) -> void:
	if is_instance_valid(panel_container):
		panel_container.add_theme_stylebox_override("panel", _make_pause_panel_style())

	if is_instance_valid(eyebrow_wrap):
		eyebrow_wrap.visible = false
	if is_instance_valid(eyebrow_label):
		eyebrow_label.visible = false
	if is_instance_valid(title_label):
		NavalUiTheme.style_display_title(title_label, 52)
	if is_instance_valid(subtitle_label):
		NavalUiTheme.style_caption(subtitle_label, 14, NavalUiTheme.TEXT_BODY)
	if is_instance_valid(divider):
		divider.color = NavalUiTheme.BORDER_GOLD_SOFT
	if is_instance_valid(footer_hint_label):
		NavalUiTheme.style_overlay_caption(footer_hint_label, 10, NavalUiTheme.TEXT_MUTED, 1)


static func decorate_pause_button(button: Button, title: String, subtitle: String, hint: String, emphasized: bool) -> void:
	if not is_instance_valid(button):
		return
	if button.get_meta("decorated", false):
		button.set_meta("button_title", title)
		button.set_meta("button_subtitle", subtitle)
		button.set_meta("button_hint", hint)
		button.set_meta("button_emphasized", emphasized)
		var title_label := button.get_meta("title_label", null) as Label
		var subtitle_label := button.get_meta("subtitle_label", null) as Label
		var hint_label := button.get_meta("hint_label", null) as Label
		if is_instance_valid(title_label):
			title_label.text = title
		if is_instance_valid(subtitle_label):
			subtitle_label.text = subtitle
		if is_instance_valid(hint_label):
			hint_label.text = hint
			hint_label.visible = not hint.is_empty()
		return

	button.text = ""
	button.set_meta("decorated", true)
	button.set_meta("button_title", title)
	button.set_meta("button_subtitle", subtitle)
	button.set_meta("button_hint", hint)
	button.set_meta("button_emphasized", emphasized)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 9)
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var copy_box := VBoxContainer.new()
	copy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_box.alignment = BoxContainer.ALIGNMENT_CENTER
	copy_box.add_theme_constant_override("separation", 1)
	row.add_child(copy_box)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", NavalUiTheme.FONT_SEMIBOLD)
	title_label.add_theme_font_size_override("font_size", 19)
	copy_box.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_font_override("font", NavalUiTheme.FONT_MEDIUM)
	subtitle_label.add_theme_font_size_override("font_size", 10)
	copy_box.add_child(subtitle_label)

	var hint_label := Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_override("font", NavalUiTheme.FONT_SEMIBOLD)
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.text = hint
	hint_label.visible = not hint.is_empty()
	row.add_child(hint_label)

	button.set_meta("title_label", title_label)
	button.set_meta("subtitle_label", subtitle_label)
	button.set_meta("hint_label", hint_label)


static func apply_pause_button_theme(button: Button, emphasized: bool = false) -> void:
	if not is_instance_valid(button):
		return
	button.focus_mode = Control.FOCUS_ALL
	NavalUiTheme.apply_menu_button(button, 22)
	button.text = ""
	button.add_theme_font_override("font", NavalUiTheme.FONT_SEMIBOLD)
	button.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN if emphasized else NavalUiTheme.TEXT_BODY)
	button.add_theme_color_override("font_focus_color", NavalUiTheme.TEXT_MAIN)
	button.add_theme_color_override("font_hover_color", NavalUiTheme.TEXT_ACCENT)
	button.add_theme_color_override("font_pressed_color", NavalUiTheme.TEXT_ACCENT)
	button.add_theme_stylebox_override("normal", _make_pause_button_style("normal", emphasized))
	button.add_theme_stylebox_override("hover", _make_pause_button_style("hover", emphasized))
	button.add_theme_stylebox_override("pressed", _make_pause_button_style("pressed", emphasized))
	button.add_theme_stylebox_override("focus", _make_pause_button_style("focus", emphasized))
	set_pause_button_content_state(button, false)


static func set_pause_button_content_state(button: Button, focused: bool) -> void:
	if not is_instance_valid(button):
		return
	var emphasized := bool(button.get_meta("button_emphasized", false))
	var title_label := button.get_meta("title_label", null) as Label
	var subtitle_label := button.get_meta("subtitle_label", null) as Label
	var hint_label := button.get_meta("hint_label", null) as Label
	if is_instance_valid(title_label):
		title_label.add_theme_color_override(
			"font_color",
			NavalUiTheme.TEXT_ACCENT if focused else (NavalUiTheme.TEXT_MAIN if emphasized else NavalUiTheme.TEXT_BODY)
		)
	if is_instance_valid(subtitle_label):
		subtitle_label.add_theme_color_override(
			"font_color",
			NavalUiTheme.TEXT_BODY if focused else NavalUiTheme.TEXT_MUTED
		)
	if is_instance_valid(hint_label):
		hint_label.add_theme_color_override(
			"font_color",
			NavalUiTheme.TEXT_GOLD if focused else NavalUiTheme.TEXT_MUTED
		)


static func _make_pause_panel_style() -> StyleBoxFlat:
	var style := NavalUiTheme.make_panel_style(
		Color(0.05, 0.08, 0.12, 0.86),
		NavalUiTheme.BORDER_GOLD_SOFT,
		24,
		2,
		22.0,
		20.0,
		22.0,
		20.0
	)
	style.shadow_size = 18
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	return style


static func _make_modal_panel_style(compact: bool) -> StyleBoxFlat:
	var style := NavalUiTheme.make_panel_style(
		Color(0.05, 0.08, 0.12, 0.82),
		NavalUiTheme.BORDER_GOLD_SOFT,
		20 if compact else 22,
		2,
		24.0 if compact else 28.0,
		20.0 if compact else 24.0,
		24.0 if compact else 28.0,
		18.0 if compact else 24.0
	)
	style.shadow_size = 16 if compact else 18
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	return style


static func _make_modal_section_style(compact: bool) -> StyleBoxFlat:
	var style := NavalUiTheme.make_panel_style(
		Color(0.05, 0.08, 0.12, 0.64),
		NavalUiTheme.BORDER_GOLD_SOFT,
		10 if compact else 12,
		1,
		18.0 if compact else 20.0,
		14.0 if compact else 18.0,
		18.0 if compact else 20.0,
		14.0 if compact else 18.0
	)
	style.shadow_size = 8 if compact else 10
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.16)
	return style


static func _make_pause_button_style(state: String, emphasized: bool) -> StyleBoxFlat:
	var bg_color := Color(0.075, 0.11, 0.16, 0.90)
	var border_color := NavalUiTheme.BORDER_GOLD_DIM
	var shadow_color := Color(0.0, 0.0, 0.0, 0.18)
	var shadow_size := 6
	if emphasized:
		bg_color = Color(0.095, 0.13, 0.19, 0.92)
		border_color = NavalUiTheme.BORDER_GOLD_SOFT
	match state:
		"hover", "focus":
			bg_color = Color(0.12, 0.18, 0.25, 0.96)
			border_color = NavalUiTheme.BORDER_GOLD
			shadow_color = Color(0.82, 0.69, 0.42, 0.14)
			shadow_size = 12
		"pressed":
			bg_color = Color(0.07, 0.11, 0.16, 0.98)
			border_color = Color(0.96, 0.86, 0.58, 0.98)
			shadow_color = Color(0.82, 0.69, 0.42, 0.10)
			shadow_size = 8
	var style := NavalUiTheme.make_panel_style(bg_color, border_color, 18, 1, 18.0, 12.0, 18.0, 12.0)
	style.shadow_size = shadow_size
	style.shadow_color = shadow_color
	return style


static func _make_action_button_style(state: String, emphasized: bool, compact: bool) -> StyleBoxFlat:
	var bg_color := Color(0.075, 0.11, 0.16, 0.88)
	var border_color := NavalUiTheme.BORDER_GOLD_DIM
	if emphasized:
		bg_color = Color(0.10, 0.14, 0.20, 0.92)
		border_color = NavalUiTheme.BORDER_GOLD_SOFT
	match state:
		"hover", "focus":
			bg_color = Color(0.14, 0.20, 0.27, 0.94)
			border_color = NavalUiTheme.BORDER_GOLD
		"pressed":
			bg_color = Color(0.08, 0.12, 0.17, 0.96)
			border_color = Color(0.93, 0.84, 0.56, 0.96)
	var style := NavalUiTheme.make_panel_style(
		bg_color,
		border_color,
		14 if compact else 16,
		1,
		16.0 if compact else 20.0,
		10.0 if compact else 12.0,
		16.0 if compact else 20.0,
		10.0 if compact else 12.0
	)
	style.shadow_size = 8 if compact else 10
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	return style
