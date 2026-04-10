extends RefCounted


static func apply_overlay_theme(hud) -> void:
	if is_instance_valid(hud.gust_warning):
		hud.NavalUiTheme.style_accent(hud.gust_warning, 22)
		hud.gust_warning.add_theme_color_override("font_outline_color", hud.NavalUiTheme.OUTLINE_DARK)
		hud.gust_warning.add_theme_constant_override("outline_size", 4)
	if is_instance_valid(hud.game_over_label):
		hud.game_over_label.add_theme_color_override("font_color", Color(0.84, 0.34, 0.28, 1.0))
		hud.game_over_label.add_theme_color_override("font_outline_color", hud.NavalUiTheme.OUTLINE_DARK)
		hud.game_over_label.add_theme_constant_override("outline_size", 4)
	if is_instance_valid(hud.victory_label):
		hud.victory_label.add_theme_color_override("font_color", hud.NavalUiTheme.TEXT_GOLD)
		hud.victory_label.add_theme_color_override("font_outline_color", hud.NavalUiTheme.OUTLINE_DARK)
		hud.victory_label.add_theme_constant_override("outline_size", 4)


static func ensure_hud_label(hud, existing: Label, node_name: String, default_text: String) -> Label:
	if is_instance_valid(existing):
		return existing
	var label := Label.new()
	label.name = node_name
	label.text = default_text
	hud.add_child(label)
	return label


static func setup_top_xp_bar(hud) -> void:
	hud.level_label = ensure_hud_label(hud, hud.level_label, "LevelLabel", "[Lv] 1")
	hud.xp_bar = ProgressBar.new()
	hud.xp_bar.name = "TopXPBar"
	hud.add_child(hud.xp_bar)

	hud.xp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.xp_bar.custom_minimum_size.y = 18.0
	hud.xp_bar.show_percentage = false
	hud.xp_bar.z_index = 10

	hud.NavalUiTheme.apply_progress_bar(hud.xp_bar, Color(0.06, 0.08, 0.11, 0.82), Color(0.58, 0.77, 0.92, 0.94), 0)

	hud.merit_bar = ProgressBar.new()
	hud.merit_bar.name = "TopMeritBar"
	hud.add_child(hud.merit_bar)

	hud.merit_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.merit_bar.offset_top = 22.0
	hud.merit_bar.custom_minimum_size.y = 12.0
	hud.merit_bar.show_percentage = false
	hud.merit_bar.z_index = 10

	hud.NavalUiTheme.apply_progress_bar(hud.merit_bar, Color(0.09, 0.08, 0.06, 0.84), Color(0.92, 0.75, 0.28, 0.94), 0)

	hud.merit_label = Label.new()
	hud.merit_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.merit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.merit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.NavalUiTheme.style_overlay_value(hud.merit_label, 10)
	hud.merit_label.add_theme_constant_override("outline_size", 3)
	hud.merit_label.text = "지휘 포인트 (병영 강화 대기)"
	hud.merit_bar.add_child(hud.merit_label)


static func attach_level_label_to_xp_bar(hud) -> void:
	if not hud.level_label or not hud.xp_bar:
		return
	var current_parent: Node = hud.level_label.get_parent()
	if current_parent and current_parent != hud.xp_bar:
		current_parent.remove_child(hud.level_label)
	if hud.level_label.get_parent() != hud.xp_bar:
		hud.xp_bar.add_child(hud.level_label)
	hud.level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.level_label.add_theme_font_size_override("font_size", 14)
	hud.level_label.add_theme_color_override("font_outline_color", hud.NavalUiTheme.OUTLINE_DARK)
	hud.level_label.add_theme_constant_override("outline_size", 4)
