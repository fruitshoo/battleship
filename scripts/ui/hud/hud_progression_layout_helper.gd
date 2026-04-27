extends RefCounted

const HudGaugeBar = preload("res://scripts/ui/hud/hud_gauge_bar.gd")

static func apply_overlay_theme(hud) -> void:
	if is_instance_valid(hud.gust_warning):
		hud.gust_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		hud.gust_warning.offset_left = -260.0
		hud.gust_warning.offset_top = 104.0
		hud.gust_warning.offset_right = 260.0
		hud.gust_warning.offset_bottom = 134.0
		hud.gust_warning.grow_horizontal = Control.GROW_DIRECTION_BOTH
		NavalUiTheme.style_status_banner(hud.gust_warning, 22, Color(1.0, 0.7, 0.2, 1.0), 4)
	if is_instance_valid(hud.game_over_label):
		NavalUiTheme.style_status_banner(hud.game_over_label, 36, Color(0.84, 0.34, 0.28, 1.0), 4)
	if is_instance_valid(hud.victory_label):
		NavalUiTheme.style_status_banner(hud.victory_label, 48, NavalUiTheme.TEXT_GOLD, 4)


static func apply_overlay_density(hud) -> void:
	if hud == null or hud.get_viewport() == null:
		return
	var viewport_size: Vector2 = hud.get_viewport().get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 1280.0) / 640.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 720.0) / 360.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	var top_bar_height := roundf(lerpf(20.0, 24.0, density))
	var merit_bar_height := roundf(lerpf(14.0, 16.0, density))
	if is_instance_valid(hud.xp_bar):
		hud.xp_bar.custom_minimum_size.y = top_bar_height
	if is_instance_valid(hud.merit_bar):
		hud.merit_bar.offset_top = top_bar_height + 1.0
		hud.merit_bar.custom_minimum_size.y = merit_bar_height
	if is_instance_valid(hud.level_label):
		NavalUiTheme.style_overlay_caption(hud.level_label, roundi(lerpf(12.0, 13.0, density)), NavalUiTheme.TEXT_MAIN, 4)
	if is_instance_valid(hud.merit_label):
		NavalUiTheme.style_overlay_value(hud.merit_label, roundi(lerpf(10.0, 11.0, density)))
		hud.merit_label.add_theme_constant_override("outline_size", 3)
	if is_instance_valid(hud.gust_warning):
		hud.gust_warning.offset_left = -roundf(lerpf(220.0, 260.0, density))
		hud.gust_warning.offset_right = roundf(lerpf(220.0, 260.0, density))
		hud.gust_warning.offset_top = roundf(lerpf(90.0, 104.0, density))
		hud.gust_warning.offset_bottom = hud.gust_warning.offset_top + roundf(lerpf(26.0, 30.0, density))
		NavalUiTheme.style_status_banner(hud.gust_warning, roundi(lerpf(18.0, 22.0, density)), Color(1.0, 0.7, 0.2, 1.0), 4)
	if is_instance_valid(hud.game_over_label):
		NavalUiTheme.style_status_banner(hud.game_over_label, roundi(lerpf(30.0, 36.0, density)), Color(0.84, 0.34, 0.28, 1.0), 4)
	if is_instance_valid(hud.victory_label):
		NavalUiTheme.style_status_banner(hud.victory_label, roundi(lerpf(38.0, 48.0, density)), NavalUiTheme.TEXT_GOLD, 4)


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
	hud.xp_bar = HudGaugeBar.new()
	hud.xp_bar.name = "TopXPBar"
	hud.add_child(hud.xp_bar)

	hud.xp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.xp_bar.custom_minimum_size.y = 24.0
	hud.xp_bar.show_percentage = false
	hud.xp_bar.z_index = 10

	NavalUiTheme.apply_progress_bar(hud.xp_bar, Color(0.06, 0.08, 0.11, 0.82), Color(0.58, 0.77, 0.92, 0.94), 0)
	hud.xp_bar.configure_gauge(Color(0.06, 0.08, 0.11, 0.82), Color(0.58, 0.77, 0.92, 0.94), 0, {
		"damage_trail": false,
		"border_color": Color(0.42, 0.56, 0.68, 0.72),
		"shine_strength": 0.18,
	})

	hud.merit_bar = HudGaugeBar.new()
	hud.merit_bar.name = "TopMeritBar"
	hud.add_child(hud.merit_bar)

	hud.merit_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.merit_bar.offset_top = 25.0
	hud.merit_bar.custom_minimum_size.y = 16.0
	hud.merit_bar.show_percentage = false
	hud.merit_bar.z_index = 10

	NavalUiTheme.apply_progress_bar(hud.merit_bar, Color(0.09, 0.08, 0.06, 0.84), Color(0.92, 0.75, 0.28, 0.94), 0)
	hud.merit_bar.configure_gauge(Color(0.09, 0.08, 0.06, 0.84), Color(0.92, 0.75, 0.28, 0.94), 0, {
		"damage_trail": false,
		"border_color": NavalUiTheme.BORDER_GOLD_SOFT,
		"shine_strength": 0.22,
	})

	hud.merit_label = Label.new()
	hud.merit_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.merit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.merit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(hud.merit_label, 10)
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
	NavalUiTheme.style_overlay_caption(hud.level_label, 14, NavalUiTheme.TEXT_MAIN, 4)
