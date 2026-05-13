extends RefCounted

const HudItemBar = preload("res://scripts/ui/hud/hud_item_bar.gd")
const HudUpgradeTrack = preload("res://scripts/ui/hud/hud_upgrade_track.gd")
const HudGaugeBar = preload("res://scripts/ui/hud/hud_gauge_bar.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const SAIL_MODE_ICON = preload("res://assets/ui/hud/sail_mode_icon.svg")
const SITE_BONUS_TOTALS_META := "sea_site_bonus_totals"

# Entry point
static func setup_new_layout(hud) -> void:
	if hud == null:
		return
	hud._setup_upgrade_tooltip()
	setup_top_left_layout(hud)
	setup_top_center_layout(hud)
	setup_top_right_layout(hud)
	setup_stat_panel(hud)
	setup_bottom_right_layout(hud)
	setup_bottom_left_layout(hud)
	setup_boss_hp_bar(hud)
	setup_boarding_ui(hud)


static func apply_layout_density(hud) -> void:
	if hud == null or hud.get_viewport() == null:
		return
	var viewport_size: Vector2 = hud.get_viewport().get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 1280.0) / 640.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 720.0) / 360.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	var edge_margin := roundf(lerpf(16.0, 24.0, density))
	var top_margin := roundf(lerpf(30.0, 38.0, density))
	var lower_margin := roundf(lerpf(18.0, 24.0, density))
	var panel_gap := roundi(lerpf(8.0, 10.0, density))
	var player_status_width := roundf(lerpf(124.0, 136.0, density))
	var player_status_hp_height := roundf(lerpf(8.0, 10.0, density))
	var player_status_stamina_height := 3.0
	var boss_width := roundf(lerpf(420.0, 560.0, density))
	var boss_height := roundf(lerpf(16.0, 20.0, density))
	var boss_gap := roundf(lerpf(5.0, 7.0, density))
	var boss_label_height := roundf(lerpf(20.0, 24.0, density))
	var boss_bottom_margin := roundf(lerpf(96.0, 152.0, density))
	var boarding_width := roundf(lerpf(168.0, 200.0, density))
	var speed_row_width := roundf(lerpf(160.0, 180.0, density))
	var speed_bar_width := roundf(lerpf(128.0, 148.0, density))
	var stat_has_site_bonus: bool = _stat_panel_has_site_bonus(hud)
	var stat_site_bonus_width := roundf(clampf(viewport_size.x * 0.22, 240.0, 300.0)) if stat_has_site_bonus else 0.0
	var available_stat_width: float = viewport_size.x - edge_margin * (3.0 if stat_has_site_bonus else 2.0) - stat_site_bonus_width
	var stat_panel_max_width: float = 760.0 if stat_has_site_bonus else 820.0
	var stat_panel_width := roundf(minf(clampf(viewport_size.x * (0.54 if stat_has_site_bonus else 0.48), 560.0, stat_panel_max_width), maxf(320.0, available_stat_width)))
	var stat_panel_height := roundf(clampf(viewport_size.y * 0.72, 420.0, 560.0))
	var stat_site_bonus_height := roundf(lerpf(300.0, 382.0, density))
	var stat_top := roundf(lerpf(42.0, 48.0, density))
	var stat_rail_stacked := stat_has_site_bonus and viewport_size.x < edge_margin * 3.0 + 320.0 + stat_site_bonus_width
	if stat_rail_stacked:
		var stacked_width := roundf(maxf(280.0, viewport_size.x - edge_margin * 2.0))
		stat_panel_width = stacked_width
		stat_site_bonus_width = stacked_width
		stat_panel_height = roundf(clampf(viewport_size.y * 0.56, 300.0, 430.0))
		var stacked_bonus_space := viewport_size.y - stat_top - stat_panel_height - panel_gap - lower_margin
		stat_site_bonus_height = roundf(clampf(stacked_bonus_space, 118.0, 240.0))

	if is_instance_valid(hud.top_left_container):
		hud.top_left_container.offset_left = edge_margin
		hud.top_left_container.offset_top = top_margin
	if is_instance_valid(hud.weapon_track):
		hud.weapon_track.custom_minimum_size.x = roundf(lerpf(220.0, 252.0, density))
	if is_instance_valid(hud.support_track):
		hud.support_track.custom_minimum_size.x = roundf(lerpf(220.0, 252.0, density))
	if is_instance_valid(hud.combat_stats_row):
		hud.combat_stats_row.add_theme_constant_override("separation", panel_gap)
	if is_instance_valid(hud.score_label):
		NavalUiTheme.style_gold(hud.score_label, roundi(lerpf(16.0, 18.0, density)))
	if is_instance_valid(hud.difficulty_label):
		NavalUiTheme.style_muted(hud.difficulty_label, roundi(lerpf(11.0, 12.0, density)))
	if is_instance_valid(hud.combat_sunk_value_label):
		NavalUiTheme.style_overlay_value(hud.combat_sunk_value_label, roundi(lerpf(11.0, 12.0, density)))
	if is_instance_valid(hud.combat_soldier_value_label):
		NavalUiTheme.style_overlay_value(hud.combat_soldier_value_label, roundi(lerpf(11.0, 12.0, density)))

	var timer_only := hud.get_node_or_null("TimerOnly") as Control
	if is_instance_valid(timer_only):
		var timer_half_width := roundf(lerpf(74.0, 90.0, density))
		timer_only.offset_left = -timer_half_width
		timer_only.offset_right = timer_half_width
		timer_only.offset_top = roundf(lerpf(34.0, 42.0, density))
		timer_only.offset_bottom = timer_only.offset_top + roundf(lerpf(28.0, 32.0, density))
	if is_instance_valid(hud.timer_label):
		NavalUiTheme.style_timer_value(hud.timer_label, roundi(lerpf(22.0, 26.0, density)))
	if is_instance_valid(hud.capture_opportunity_label):
		var capture_half_width := roundf(lerpf(150.0, 180.0, density))
		hud.capture_opportunity_label.offset_left = -capture_half_width
		hud.capture_opportunity_label.offset_right = capture_half_width
		hud.capture_opportunity_label.offset_top = roundf(lerpf(66.0, 76.0, density))
		hud.capture_opportunity_label.offset_bottom = hud.capture_opportunity_label.offset_top + 22.0
		NavalUiTheme.style_caption(hud.capture_opportunity_label, roundi(lerpf(10.0, 11.0, density)), NavalUiTheme.TEXT_GOLD)
	if is_instance_valid(hud.debug_distance_label):
		var debug_half_width := roundf(lerpf(150.0, 180.0, density))
		hud.debug_distance_label.offset_left = -debug_half_width
		hud.debug_distance_label.offset_right = debug_half_width
		hud.debug_distance_label.offset_top = roundf(lerpf(70.0, 80.0, density))
		hud.debug_distance_label.offset_bottom = hud.debug_distance_label.offset_top + 22.0
		NavalUiTheme.style_caption(hud.debug_distance_label, roundi(lerpf(9.0, 10.0, density)), NavalUiTheme.TEXT_MUTED)

	if is_instance_valid(hud.top_right_container):
		hud.top_right_container.offset_right = -edge_margin
		hud.top_right_container.offset_top = roundf(lerpf(220.0, 248.0, density))
	if is_instance_valid(hud.speed_bar):
		var speed_row := hud.speed_bar.get_parent() as HBoxContainer
		if is_instance_valid(speed_row):
			speed_row.custom_minimum_size = Vector2(speed_row_width, roundf(lerpf(16.0, 18.0, density)))
			speed_row.add_theme_constant_override("separation", panel_gap)
		hud.speed_bar.custom_minimum_size = Vector2(speed_bar_width, roundf(lerpf(16.0, 18.0, density)))
	if is_instance_valid(hud.speed_mode_icon):
		hud.speed_mode_icon.custom_minimum_size = Vector2(roundf(lerpf(20.0, 24.0, density)), roundf(lerpf(20.0, 24.0, density)))
	if is_instance_valid(hud.speed_bar_label):
		NavalUiTheme.style_overlay_value(hud.speed_bar_label, roundi(lerpf(10.0, 11.0, density)))

	if is_instance_valid(hud.stat_panel):
		hud.stat_panel.offset_left = edge_margin
		hud.stat_panel.offset_right = edge_margin + stat_panel_width
		hud.stat_panel.offset_top = stat_top
		hud.stat_panel.offset_bottom = hud.stat_panel.offset_top + stat_panel_height
		var stat_box := hud.stat_panel.get_child(0) as VBoxContainer
		if is_instance_valid(stat_box):
			stat_box.custom_minimum_size = Vector2(stat_panel_width - 24.0, stat_panel_height - 40.0)
	if is_instance_valid(hud.stat_site_bonus_panel):
		hud.stat_site_bonus_panel.visible = hud.show_stat_panel and stat_has_site_bonus
		if stat_rail_stacked:
			hud.stat_site_bonus_panel.anchor_left = 0.0
			hud.stat_site_bonus_panel.anchor_right = 0.0
			hud.stat_site_bonus_panel.offset_left = edge_margin
			hud.stat_site_bonus_panel.offset_right = edge_margin + stat_site_bonus_width
			hud.stat_site_bonus_panel.offset_top = stat_top + stat_panel_height + panel_gap
			hud.stat_site_bonus_panel.offset_bottom = hud.stat_site_bonus_panel.offset_top + stat_site_bonus_height
			hud.stat_site_bonus_panel.grow_horizontal = Control.GROW_DIRECTION_END
		else:
			hud.stat_site_bonus_panel.anchor_left = 1.0
			hud.stat_site_bonus_panel.anchor_right = 1.0
			hud.stat_site_bonus_panel.offset_left = -edge_margin - stat_site_bonus_width
			hud.stat_site_bonus_panel.offset_right = -edge_margin
			hud.stat_site_bonus_panel.offset_top = stat_top
			hud.stat_site_bonus_panel.offset_bottom = hud.stat_site_bonus_panel.offset_top + stat_site_bonus_height
			hud.stat_site_bonus_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		var site_bonus_box := hud.stat_site_bonus_panel.get_child(0) as VBoxContainer
		if is_instance_valid(site_bonus_box):
			site_bonus_box.custom_minimum_size = Vector2(stat_site_bonus_width - 4.0, stat_site_bonus_height)

	if is_instance_valid(hud.bottom_right_container):
		hud.bottom_right_container.offset_right = -edge_margin
		hud.bottom_right_container.offset_bottom = -lower_margin
	if is_instance_valid(hud.bottom_left_container):
		hud.bottom_left_container.offset_left = edge_margin
		hud.bottom_left_container.offset_bottom = -lower_margin
		hud.bottom_left_container.add_theme_constant_override("separation", roundi(lerpf(6.0, 8.0, density)))
	if is_instance_valid(hud.support_row):
		hud.support_row.add_theme_constant_override("separation", roundi(lerpf(4.0, 6.0, density)))
	if is_instance_valid(hud.support_slot_container):
		hud.support_slot_container.add_theme_constant_override("separation", roundi(lerpf(4.0, 6.0, density)))
	if is_instance_valid(hud.player_status_root):
		var player_status_height: float = player_status_hp_height + player_status_stamina_height + float(hud.PLAYER_STATUS_BAR_GAP)
		hud.player_status_root.custom_minimum_size = Vector2(player_status_width, player_status_height)
		hud.player_status_root.size = hud.player_status_root.custom_minimum_size
	if is_instance_valid(hud.hp_bar):
		hud.hp_bar.custom_minimum_size = Vector2(player_status_width, player_status_hp_height)
		hud.hp_bar.size = hud.hp_bar.custom_minimum_size
	if is_instance_valid(hud.hp_text_label):
		hud.hp_text_label.visible = false
	if is_instance_valid(hud.stamina_bar):
		hud.stamina_bar.position = Vector2(0.0, player_status_hp_height + hud.PLAYER_STATUS_BAR_GAP)
		hud.stamina_bar.custom_minimum_size = Vector2(player_status_width, player_status_stamina_height)
		hud.stamina_bar.size = hud.stamina_bar.custom_minimum_size

	if is_instance_valid(hud.boss_hp_container):
		var boss_stack_count := 0
		var boss_entries_variant = hud.get("boss_hp_entries")
		if boss_entries_variant is Dictionary:
			boss_stack_count = (boss_entries_variant as Dictionary).size()
		_apply_boss_hp_stack_layout(hud, boss_width, boss_height, boss_bottom_margin, boss_gap, boss_label_height, boss_stack_count)
	if is_instance_valid(hud.boarding_ui):
		hud.boarding_ui.offset_top = roundf(lerpf(88.0, 100.0, density))
	if is_instance_valid(hud.boarding_label):
		NavalUiTheme.style_overlay_value(hud.boarding_label, roundi(lerpf(14.0, 16.0, density)))
		hud.boarding_label.add_theme_constant_override("outline_size", 4)
	if is_instance_valid(hud.boarding_bar):
		hud.boarding_bar.custom_minimum_size = Vector2(boarding_width, roundf(lerpf(10.0, 12.0, density)))

# Shared helpers
static func move_label_to_container(node: Control, container: Control) -> void:
	if not is_instance_valid(node) or not is_instance_valid(container):
		return
	var current_parent = node.get_parent()
	if current_parent:
		current_parent.remove_child(node)
	container.add_child(node)

# Top row
static func setup_top_left_layout(hud) -> void:
	if hud == null:
		return
	if hud.top_left_container:
		return
	hud.top_left_container = VBoxContainer.new()
	hud.add_child(hud.top_left_container)
	hud.top_left_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.top_left_container.offset_left = 24
	hud.top_left_container.offset_top = 48
	hud.score_label = hud._ensure_hud_label(hud.score_label, "ScoreLabel", "Gold: 0")
	hud.difficulty_label = hud._ensure_hud_label(hud.difficulty_label, "DifficultyLabel", "[Diff] 1")
	hud._attach_level_label_to_xp_bar()

	hud.weapon_track = HudUpgradeTrack.new()
	hud.weapon_track.setup_track("", NavalUiTheme.TEXT_BLUE, NavalUiTheme.PANEL_BG_DARK, NavalUiTheme.BORDER_GOLD_DIM)
	hud.top_left_container.add_child(hud.weapon_track)
	hud.weapon_container = hud.weapon_track.slot_container
	hud.weapon_slots = hud.weapon_track.slots
	for slot in hud.weapon_slots:
		hud._bind_upgrade_slot_hover(slot)

	hud.support_track = HudUpgradeTrack.new()
	hud.support_track.setup_track("", NavalUiTheme.TEXT_ACCENT, NavalUiTheme.PANEL_BG_DARK, NavalUiTheme.BORDER_GOLD_DIM)
	hud.top_left_container.add_child(hud.support_track)
	hud.support_container = hud.support_track.slot_container
	hud.support_slots = hud.support_track.slots
	for slot in hud.support_slots:
		hud._bind_upgrade_slot_hover(slot)

	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	hud.top_left_container.add_child(spacer)

	if hud.score_label:
		move_label_to_container(hud.score_label, hud.top_left_container)
		hud.score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		NavalUiTheme.style_gold(hud.score_label, 17)

	hud.combat_stats_row = HBoxContainer.new()
	hud.combat_stats_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud.combat_stats_row.add_theme_constant_override("separation", 8)
	hud.top_left_container.add_child(hud.combat_stats_row)

	var sunk_chip: PanelContainer = _create_combat_stat_chip(hud, "directions_boat", NavalUiTheme.TEXT_BLUE, "combat_sunk_value_label", "0")
	var soldier_chip: PanelContainer = _create_combat_stat_chip(hud, "groups", NavalUiTheme.TEXT_ACCENT, "combat_soldier_value_label", "0")
	sunk_chip.set_meta("tooltip_text", "배 파괴: 침몰과 폐선화를 포함한 적 함선 무력화 수")
	sunk_chip.set_meta("tooltip_color", NavalUiTheme.TEXT_BLUE)
	soldier_chip.set_meta("tooltip_text", "병사 처치: 전투 사살과 수장을 포함한 적 병사 총 처치 수")
	soldier_chip.set_meta("tooltip_color", NavalUiTheme.TEXT_ACCENT)
	hud._bind_upgrade_slot_hover(sunk_chip)
	hud._bind_upgrade_slot_hover(soldier_chip)
	hud.combat_stats_row.add_child(sunk_chip)
	hud.combat_stats_row.add_child(soldier_chip)

	if hud.difficulty_label:
		hud.difficulty_label.visible = false

static func _create_combat_stat_chip(hud, icon_name: String, icon_color: Color, value_property_name: String, initial_text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", NavalUiTheme.make_hud_chip_style())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)

	var icon_label := Label.new()
	icon_label.custom_minimum_size = Vector2(16, 16)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.apply_emblem(icon_label, icon_name, 13, icon_color)
	row.add_child(icon_label)

	var value_label := Label.new()
	value_label.text = initial_text
	NavalUiTheme.style_overlay_value(value_label, 12)
	value_label.add_theme_constant_override("outline_size", 3)
	row.add_child(value_label)

	hud.set(value_property_name, value_label)
	return chip

static func setup_top_center_layout(hud) -> void:
	if hud == null:
		return
	hud.timer_label = hud._ensure_hud_label(hud.timer_label, "TimerLabel", "0:00")
	var top_center_container := Control.new()
	top_center_container.name = "TimerOnly"
	hud.add_child(top_center_container)
	top_center_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top_center_container.offset_left = -90
	top_center_container.offset_top = 58
	top_center_container.offset_right = 90
	top_center_container.offset_bottom = 92
	top_center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH

	move_label_to_container(hud.timer_label, top_center_container)
	hud.timer_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_timer_value(hud.timer_label, 26)

	hud.capture_opportunity_label = Label.new()
	hud.capture_opportunity_label.name = "CaptureOpportunityLabel"
	hud.capture_opportunity_label.text = ""
	hud.capture_opportunity_label.visible = false
	hud.capture_opportunity_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.capture_opportunity_label.offset_left = -180
	hud.capture_opportunity_label.offset_top = 96
	hud.capture_opportunity_label.offset_right = 180
	hud.capture_opportunity_label.offset_bottom = 118
	hud.capture_opportunity_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.capture_opportunity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_caption(hud.capture_opportunity_label, 11, NavalUiTheme.TEXT_GOLD)
	hud.capture_opportunity_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
	hud.capture_opportunity_label.add_theme_constant_override("outline_size", 3)
	hud.add_child(hud.capture_opportunity_label)

	hud.ammo_mode_label = Label.new()
	hud.ammo_mode_label.name = "AmmoModeLabel"
	hud.ammo_mode_label.text = ""
	hud.ammo_mode_label.visible = false
	hud.add_child(hud.ammo_mode_label)

	hud.debug_distance_label = Label.new()
	hud.debug_distance_label.name = "DebugDistanceLabel"
	hud.debug_distance_label.text = ""
	hud.debug_distance_label.visible = false
	hud.debug_distance_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.debug_distance_label.offset_left = -180
	hud.debug_distance_label.offset_top = 100
	hud.debug_distance_label.offset_right = 180
	hud.debug_distance_label.offset_bottom = 122
	hud.debug_distance_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.debug_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_caption(hud.debug_distance_label, 10, NavalUiTheme.TEXT_MUTED)
	hud.debug_distance_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
	hud.debug_distance_label.add_theme_constant_override("outline_size", 3)
	hud.add_child(hud.debug_distance_label)

# Right side
static func setup_top_right_layout(hud) -> void:
	if hud == null:
		return
	if hud.top_right_container:
		return
	hud.top_right_container = VBoxContainer.new()
	hud.add_child(hud.top_right_container)
	hud.top_right_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hud.top_right_container.offset_right = -24
	hud.top_right_container.offset_top = 248
	hud.top_right_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var speed_panel = PanelContainer.new()
	var speed_panel_style := NavalUiTheme.make_hud_panel_compact_style()
	speed_panel.add_theme_stylebox_override("panel", speed_panel_style)
	hud.top_right_container.add_child(speed_panel)

	var speed_row = HBoxContainer.new()
	speed_row.custom_minimum_size = Vector2(180, 18)
	speed_row.alignment = BoxContainer.ALIGNMENT_END
	speed_row.add_theme_constant_override("separation", 8)
	speed_panel.add_child(speed_row)

	hud.speed_mode_icon = TextureRect.new()
	hud.speed_mode_icon.custom_minimum_size = Vector2(24, 24)
	hud.speed_mode_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud.speed_mode_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hud.speed_mode_icon.texture = SAIL_MODE_ICON
	hud.speed_mode_icon.modulate = NavalUiTheme.TEXT_ACCENT
	speed_row.add_child(hud.speed_mode_icon)

	hud.speed_bar = HudGaugeBar.new()
	hud.speed_bar.custom_minimum_size = Vector2(148, 18)
	hud.speed_bar.min_value = 0.0
	hud.speed_bar.max_value = 100.0
	hud.speed_bar.value = 0.0
	hud.speed_bar.show_percentage = false
	speed_row.add_child(hud.speed_bar)

	NavalUiTheme.apply_progress_bar(hud.speed_bar, Color(0.06, 0.08, 0.11, 0.92), Color(0.64, 0.78, 0.88, 0.94), 4)
	hud.speed_bar.configure_gauge(Color(0.06, 0.08, 0.11, 0.92), Color(0.64, 0.78, 0.88, 0.94), 4, {
		"damage_trail": false,
		"border_color": NavalUiTheme.BORDER_GOLD_SOFT,
		"shine_strength": 0.18,
	})

	hud.speed_bar_label = Label.new()
	hud.speed_bar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.speed_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.speed_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.speed_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(hud.speed_bar_label, 11)
	hud.speed_bar_label.add_theme_constant_override("outline_size", 4)
	hud.speed_bar_label.text = "0.0"
	hud.speed_bar.add_child(hud.speed_bar_label)

# Detail/stat UI
static func setup_stat_panel(hud) -> void:
	if hud == null:
		return
	if hud.stat_panel:
		return
	hud.stat_backdrop = ColorRect.new()
	hud.stat_backdrop.name = "StatBackdrop"
	hud.add_child(hud.stat_backdrop)
	hud.stat_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.stat_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.stat_backdrop.color = Color.WHITE
	hud.stat_backdrop.material = UiOverlayFx.make_modal_blur_material(
		Color(0.02, 0.03, 0.05, 0.42),
		0.62,
		14.0,
		0.38,
		Vector2(0.32, 0.48)
	)
	hud.stat_backdrop.visible = false
	hud.stat_backdrop.z_index = 80

	hud.stat_panel = PanelContainer.new()
	hud.add_child(hud.stat_panel)
	hud.stat_panel.visible = hud.show_stat_panel
	hud.stat_panel.z_index = 90
	hud.stat_panel.anchor_left = 0.0
	hud.stat_panel.anchor_right = 0.0
	hud.stat_panel.anchor_top = 0.0
	hud.stat_panel.anchor_bottom = 0.0
	hud.stat_panel.offset_left = 24
	hud.stat_panel.offset_right = 400
	hud.stat_panel.offset_top = 48
	hud.stat_panel.offset_bottom = 544
	hud.stat_panel.grow_horizontal = Control.GROW_DIRECTION_END
	hud.stat_panel.grow_vertical = Control.GROW_DIRECTION_END

	var panel_style := NavalUiTheme.make_hud_panel_style()
	hud.stat_panel.add_theme_stylebox_override("panel", panel_style)

	var stat_box = VBoxContainer.new()
	stat_box.custom_minimum_size = Vector2(352, 300)
	stat_box.add_theme_constant_override("separation", 6)
	hud.stat_panel.add_child(stat_box)

	var title = Label.new()
	title.text = "전투 수치 [Tab]"
	NavalUiTheme.style_heading(title, 15)
	stat_box.add_child(title)

	hud.stat_scroll = ScrollContainer.new()
	hud.stat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.stat_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.stat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stat_box.add_child(hud.stat_scroll)

	var stat_scroll_gutter := MarginContainer.new()
	stat_scroll_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_scroll_gutter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stat_scroll_gutter.add_theme_constant_override("margin_right", 18)
	hud.stat_scroll.add_child(stat_scroll_gutter)

	hud.stat_content = VBoxContainer.new()
	hud.stat_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.stat_content.add_theme_constant_override("separation", 6)
	stat_scroll_gutter.add_child(hud.stat_content)

	hud.stat_site_bonus_panel = MarginContainer.new()
	hud.add_child(hud.stat_site_bonus_panel)
	hud.stat_site_bonus_panel.visible = hud.show_stat_panel
	hud.stat_site_bonus_panel.z_index = 90
	hud.stat_site_bonus_panel.anchor_left = 1.0
	hud.stat_site_bonus_panel.anchor_right = 1.0
	hud.stat_site_bonus_panel.anchor_top = 0.0
	hud.stat_site_bonus_panel.anchor_bottom = 0.0
	hud.stat_site_bonus_panel.offset_left = -364
	hud.stat_site_bonus_panel.offset_right = -24
	hud.stat_site_bonus_panel.offset_top = 48
	hud.stat_site_bonus_panel.offset_bottom = 430
	hud.stat_site_bonus_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.stat_site_bonus_panel.grow_vertical = Control.GROW_DIRECTION_END
	hud.stat_site_bonus_panel.add_theme_constant_override("margin_left", 4)
	hud.stat_site_bonus_panel.add_theme_constant_override("margin_top", 2)
	hud.stat_site_bonus_panel.add_theme_constant_override("margin_right", 0)
	hud.stat_site_bonus_panel.add_theme_constant_override("margin_bottom", 0)

	var site_bonus_box = VBoxContainer.new()
	site_bonus_box.custom_minimum_size = Vector2(336, 382)
	site_bonus_box.add_theme_constant_override("separation", 10)
	hud.stat_site_bonus_panel.add_child(site_bonus_box)

	var site_bonus_title = Label.new()
	site_bonus_title.text = "해역 보너스"
	NavalUiTheme.style_heading(site_bonus_title, 15)
	site_bonus_box.add_child(site_bonus_title)

	hud.stat_site_bonus_scroll = ScrollContainer.new()
	hud.stat_site_bonus_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.stat_site_bonus_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.stat_site_bonus_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	site_bonus_box.add_child(hud.stat_site_bonus_scroll)

	var site_bonus_scroll_gutter := MarginContainer.new()
	site_bonus_scroll_gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	site_bonus_scroll_gutter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	site_bonus_scroll_gutter.add_theme_constant_override("margin_right", 14)
	hud.stat_site_bonus_scroll.add_child(site_bonus_scroll_gutter)

	hud.stat_site_bonus_content = VBoxContainer.new()
	hud.stat_site_bonus_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.stat_site_bonus_content.add_theme_constant_override("separation", 10)
	site_bonus_scroll_gutter.add_child(hud.stat_site_bonus_content)

# Bottom corners
static func setup_bottom_right_layout(hud) -> void:
	if hud == null:
		return
	if hud.bottom_right_container:
		return
	hud.bottom_right_container = VBoxContainer.new()
	hud.add_child(hud.bottom_right_container)
	hud.bottom_right_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hud.bottom_right_container.offset_right = -24
	hud.bottom_right_container.offset_bottom = -24
	hud.bottom_right_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.bottom_right_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if hud.item_bar == null:
		hud.item_bar = HudItemBar.new()
		hud.bottom_right_container.add_child(hud.item_bar)

static func _stat_panel_has_site_bonus(hud) -> bool:
	if hud == null or not is_instance_valid(hud.player_ship):
		return false
	var totals_variant: Variant = hud.player_ship.get_meta(SITE_BONUS_TOTALS_META, {})
	if typeof(totals_variant) != TYPE_DICTIONARY:
		return false
	for value in (totals_variant as Dictionary).values():
		if absf(float(value)) > 0.0001:
			return true
	return false

static func setup_bottom_left_layout(hud) -> void:
	if hud == null:
		return
	if hud.bottom_left_container:
		return
	hud.bottom_left_container = VBoxContainer.new()
	hud.add_child(hud.bottom_left_container)
	hud.bottom_left_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hud.bottom_left_container.offset_left = 24
	hud.bottom_left_container.offset_bottom = -24
	hud.bottom_left_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if hud.support_row == null:
		hud.support_row = HBoxContainer.new()
		hud.support_row.name = "SupportRow"
		hud.support_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		hud.support_row.add_theme_constant_override("separation", 4)
	if hud.support_row.get_parent() != hud.bottom_left_container:
		move_label_to_container(hud.support_row, hud.bottom_left_container)

	if hud.support_slot_container == null:
		hud.support_slot_container = HBoxContainer.new()
		hud.support_slot_container.name = "SupportSlots"
		hud.support_slot_container.alignment = BoxContainer.ALIGNMENT_BEGIN
		hud.support_slot_container.add_theme_constant_override("separation", 4)
	if hud.support_slot_container.get_parent() != hud.support_row:
		move_label_to_container(hud.support_slot_container, hud.support_row)

# Combat overlays
static func setup_boss_hp_bar(hud) -> void:
	if hud == null:
		return
	if hud.boss_hp_container:
		return
	hud.boss_hp_container = VBoxContainer.new()
	hud.boss_hp_container.name = "BossHPStack"
	hud.boss_hp_container.visible = false
	hud.boss_hp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.boss_hp_container.alignment = BoxContainer.ALIGNMENT_END
	hud.boss_hp_container.z_index = 30
	hud.add_child(hud.boss_hp_container)
	_apply_boss_hp_stack_layout(hud, 560.0, 20.0, 152.0, 7.0, 24.0, 0)

static func _apply_boss_hp_stack_layout(hud, boss_width: float, boss_height: float, bottom_margin: float, gap: float, label_height: float, stack_count: int) -> void:
	if hud == null or not is_instance_valid(hud.boss_hp_container):
		return
	var visible_count: int = maxi(stack_count, 1)
	var show_labels: bool = stack_count > 0
	var label_gap: float = 2.0 if show_labels else 0.0
	var row_height: float = boss_height + (label_height + label_gap if show_labels else 0.0)
	var stack_height: float = row_height * float(visible_count) + gap * float(maxi(visible_count - 1, 0))
	hud.boss_hp_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud.boss_hp_container.offset_left = -boss_width * 0.5
	hud.boss_hp_container.offset_right = boss_width * 0.5
	hud.boss_hp_container.offset_bottom = -bottom_margin
	hud.boss_hp_container.offset_top = -bottom_margin - stack_height
	hud.boss_hp_container.custom_minimum_size = Vector2(boss_width, stack_height)
	hud.boss_hp_container.add_theme_constant_override("separation", int(gap))

	var entries_variant = hud.get("boss_hp_entries")
	if not (entries_variant is Dictionary):
		return
	for entry in (entries_variant as Dictionary).values():
		if not (entry is Dictionary):
			continue
		var root := (entry as Dictionary).get("root", null) as VBoxContainer
		if is_instance_valid(root):
			root.custom_minimum_size = Vector2(boss_width, row_height)
			root.add_theme_constant_override("separation", int(label_gap))
		var bar := (entry as Dictionary).get("bar", null) as ProgressBar
		if is_instance_valid(bar):
			bar.custom_minimum_size = Vector2(boss_width, boss_height)
		var label := (entry as Dictionary).get("label", null) as Label
		if is_instance_valid(label):
			label.custom_minimum_size = Vector2(boss_width, label_height)
			NavalUiTheme.style_caption(label, 13, NavalUiTheme.TEXT_MUTED)

static func setup_boarding_ui(hud) -> void:
	if hud == null:
		return
	if hud.boarding_ui:
		return
	hud.boarding_ui = VBoxContainer.new()
	hud.add_child(hud.boarding_ui)
	hud.boarding_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud.boarding_ui.offset_top = 100
	hud.boarding_ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.boarding_ui.visible = false

	hud.boarding_label = Label.new()
	hud.boarding_label.text = "도선 준비 중..."
	hud.boarding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(hud.boarding_label, 16)
	hud.boarding_label.add_theme_constant_override("outline_size", 4)
	hud.boarding_ui.add_child(hud.boarding_label)

	hud.boarding_bar = HudGaugeBar.new()
	hud.boarding_bar.custom_minimum_size = Vector2(200, 12)
	hud.boarding_bar.show_percentage = false
	NavalUiTheme.apply_progress_bar(hud.boarding_bar, Color(0.06, 0.08, 0.11, 0.86), Color(0.90, 0.86, 0.74, 0.92), 4)
	hud.boarding_bar.configure_gauge(Color(0.06, 0.08, 0.11, 0.86), Color(0.90, 0.86, 0.74, 0.92), 4, {
		"damage_trail": false,
		"border_color": NavalUiTheme.BORDER_GOLD_SOFT,
		"shine_strength": 0.2,
	})
	hud.boarding_ui.add_child(hud.boarding_bar)
