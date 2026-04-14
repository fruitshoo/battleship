extends RefCounted

const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const HudItemBar = preload("res://scripts/ui/hud/hud_item_bar.gd")
const HudUpgradeTrack = preload("res://scripts/ui/hud/hud_upgrade_track.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const SAIL_MODE_ICON = preload("res://assets/ui/hud/sail_mode_icon.svg")

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
	hud.top_left_container.offset_top = 32
	hud.score_label = hud._ensure_hud_label(hud.score_label, "ScoreLabel", "Gold: 0")
	hud.difficulty_label = hud._ensure_hud_label(hud.difficulty_label, "DifficultyLabel", "[Diff] 1")
	hud._attach_level_label_to_xp_bar()

	hud.weapon_track = HudUpgradeTrack.new()
	hud.weapon_track.setup_track("[함선 업그레이드]", NavalUiTheme.TEXT_BLUE, NavalUiTheme.PANEL_BG_DARK, NavalUiTheme.BORDER_GOLD_DIM)
	hud.top_left_container.add_child(hud.weapon_track)
	hud.weapon_container = hud.weapon_track.slot_container
	hud.weapon_slots = hud.weapon_track.slots
	for slot in hud.weapon_slots:
		hud._bind_upgrade_slot_hover(slot)

	hud.support_track = HudUpgradeTrack.new()
	hud.support_track.setup_track("[병사 업그레이드]", NavalUiTheme.TEXT_ACCENT, NavalUiTheme.PANEL_BG_DARK, NavalUiTheme.BORDER_GOLD_DIM)
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
		NavalUiTheme.style_gold(hud.score_label, 18)

	hud.combat_stats_label = Label.new()
	hud.combat_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	NavalUiTheme.style_muted(hud.combat_stats_label, 12)
	hud.combat_stats_label.text = "[전과]"
	hud.top_left_container.add_child(hud.combat_stats_label)

	hud.combat_stats_row = HBoxContainer.new()
	hud.combat_stats_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud.combat_stats_row.add_theme_constant_override("separation", 8)
	hud.top_left_container.add_child(hud.combat_stats_row)

	var sunk_chip: PanelContainer = _create_combat_stat_chip(hud, "directions_boat", NavalUiTheme.TEXT_BLUE, "combat_sunk_value_label", "0")
	var derelict_chip: PanelContainer = _create_combat_stat_chip(hud, "sailing", NavalUiTheme.TEXT_GOLD, "combat_derelict_value_label", "0")
	var soldier_chip: PanelContainer = _create_combat_stat_chip(hud, "groups", NavalUiTheme.TEXT_ACCENT, "combat_soldier_value_label", "0")
	sunk_chip.set_meta("tooltip_text", "격침: 적 함선을 침몰시킨 횟수")
	sunk_chip.set_meta("tooltip_color", NavalUiTheme.TEXT_BLUE)
	derelict_chip.set_meta("tooltip_text", "나포(폐선화): 적 병사를 모두 제거해 폐선 상태로 만든 횟수")
	derelict_chip.set_meta("tooltip_color", NavalUiTheme.TEXT_GOLD)
	soldier_chip.set_meta("tooltip_text", "병사 처치: 전투 사살과 수장을 포함한 적 병사 총 처치 수")
	soldier_chip.set_meta("tooltip_color", NavalUiTheme.TEXT_ACCENT)
	hud._bind_upgrade_slot_hover(sunk_chip)
	hud._bind_upgrade_slot_hover(derelict_chip)
	hud._bind_upgrade_slot_hover(soldier_chip)
	hud.combat_stats_row.add_child(sunk_chip)
	hud.combat_stats_row.add_child(derelict_chip)
	hud.combat_stats_row.add_child(soldier_chip)

	if hud.difficulty_label:
		move_label_to_container(hud.difficulty_label, hud.top_left_container)
		hud.difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		NavalUiTheme.style_muted(hud.difficulty_label, 12)

static func _create_combat_stat_chip(hud, icon_name: String, icon_color: Color, value_property_name: String, initial_text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	var chip_style := NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_DIM, 9, 1, 8.0, 5.0, 8.0, 5.0)
	chip.add_theme_stylebox_override("panel", chip_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)

	var icon_label := Label.new()
	icon_label.custom_minimum_size = Vector2(16, 16)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.add_theme_color_override("font_color", icon_color)
	if MATERIAL_SYMBOLS_FONT:
		icon_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
	icon_label.text = icon_name
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
	top_center_container.offset_top = 40
	top_center_container.offset_right = 90
	top_center_container.offset_bottom = 72
	top_center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH

	move_label_to_container(hud.timer_label, top_center_container)
	hud.timer_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.timer_label.add_theme_font_size_override("font_size", 28)
	hud.timer_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN)
	hud.timer_label.add_theme_color_override("font_shadow_color", NavalUiTheme.OUTLINE_DARK)
	hud.timer_label.add_theme_constant_override("shadow_outline_size", 3)

	hud.capture_opportunity_label = Label.new()
	hud.capture_opportunity_label.name = "CaptureOpportunityLabel"
	hud.capture_opportunity_label.text = ""
	hud.capture_opportunity_label.visible = false
	hud.capture_opportunity_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.capture_opportunity_label.offset_left = -180
	hud.capture_opportunity_label.offset_top = 74
	hud.capture_opportunity_label.offset_right = 180
	hud.capture_opportunity_label.offset_bottom = 96
	hud.capture_opportunity_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.capture_opportunity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_gold(hud.capture_opportunity_label, 11)
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
	hud.debug_distance_label.offset_top = 78
	hud.debug_distance_label.offset_right = 180
	hud.debug_distance_label.offset_bottom = 100
	hud.debug_distance_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.debug_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_muted(hud.debug_distance_label, 10)
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

	hud.speed_bar = ProgressBar.new()
	hud.speed_bar.custom_minimum_size = Vector2(148, 18)
	hud.speed_bar.min_value = 0.0
	hud.speed_bar.max_value = 100.0
	hud.speed_bar.value = 0.0
	hud.speed_bar.show_percentage = false
	speed_row.add_child(hud.speed_bar)

	NavalUiTheme.apply_progress_bar(hud.speed_bar, Color(0.06, 0.08, 0.11, 0.92), Color(0.64, 0.78, 0.88, 0.94), 4)

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
	hud.stat_panel = PanelContainer.new()
	hud.add_child(hud.stat_panel)
	hud.stat_panel.visible = hud.show_stat_panel
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
	stat_box.add_theme_constant_override("separation", 8)
	hud.stat_panel.add_child(stat_box)

	var title = Label.new()
	title.text = "전투 수치 [C]"
	NavalUiTheme.style_heading(title, 15)
	stat_box.add_child(title)

	hud.stat_scroll = ScrollContainer.new()
	hud.stat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.stat_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.stat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stat_box.add_child(hud.stat_scroll)

	hud.stat_content = VBoxContainer.new()
	hud.stat_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.stat_content.add_theme_constant_override("separation", 10)
	hud.stat_scroll.add_child(hud.stat_content)

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
		hud.support_row.add_theme_constant_override("separation", 10)
	if hud.support_row.get_parent() != hud.bottom_left_container:
		move_label_to_container(hud.support_row, hud.bottom_left_container)

	if hud.support_slot_container == null:
		hud.support_slot_container = VBoxContainer.new()
		hud.support_slot_container.name = "SupportSlots"
		hud.support_slot_container.add_theme_constant_override("separation", 6)
	if hud.support_slot_container.get_parent() != hud.support_row:
		move_label_to_container(hud.support_slot_container, hud.support_row)

	hud.hp_bar = ProgressBar.new()
	hud.hp_bar.custom_minimum_size = Vector2(240, 24)
	hud.hp_bar.show_percentage = false
	hud.bottom_left_container.add_child(hud.hp_bar)

	NavalUiTheme.apply_progress_bar(hud.hp_bar, Color(0.06, 0.08, 0.11, 0.92), Color(0.22, 0.74, 0.34, 0.92), 4)

	hud.hp_text_label = Label.new()
	hud.hp_text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.hp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.hp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(hud.hp_text_label, 14)
	hud.hp_bar.add_child(hud.hp_text_label)

	hud.stamina_bar = ProgressBar.new()
	hud.stamina_bar.custom_minimum_size = Vector2(240, 8)
	hud.stamina_bar.show_percentage = false
	hud.bottom_left_container.add_child(hud.stamina_bar)

	NavalUiTheme.apply_progress_bar(hud.stamina_bar, Color(0.06, 0.08, 0.11, 0.86), Color(0.88, 0.70, 0.24, 0.92), 2)

# Combat overlays
static func setup_boss_hp_bar(hud) -> void:
	if hud == null:
		return
	if hud.boss_hp_bar_new:
		return
	hud.boss_hp_bar_new = ProgressBar.new()
	hud.add_child(hud.boss_hp_bar_new)
	hud.boss_hp_bar_new.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud.boss_hp_bar_new.offset_top = 80
	hud.boss_hp_bar_new.custom_minimum_size = Vector2(500, 28)
	hud.boss_hp_bar_new.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.boss_hp_bar_new.show_percentage = false
	hud.boss_hp_bar_new.visible = false

	NavalUiTheme.apply_progress_bar(hud.boss_hp_bar_new, Color(0.07, 0.08, 0.10, 0.92), Color(0.77, 0.22, 0.20, 0.95), 4)

	hud.boss_hp_text_label = Label.new()
	hud.boss_hp_text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.boss_hp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.boss_hp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(hud.boss_hp_text_label, 13)
	hud.boss_hp_bar_new.add_child(hud.boss_hp_text_label)

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

	hud.boarding_bar = ProgressBar.new()
	hud.boarding_bar.custom_minimum_size = Vector2(200, 12)
	hud.boarding_bar.show_percentage = false
	NavalUiTheme.apply_progress_bar(hud.boarding_bar, Color(0.06, 0.08, 0.11, 0.86), Color(0.90, 0.86, 0.74, 0.92), 4)
	hud.boarding_ui.add_child(hud.boarding_bar)
