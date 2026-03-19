extends RefCounted

const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const HudRelicBar = preload("res://scripts/ui/hud_relic_bar.gd")
const HudUpgradeTrack = preload("res://scripts/ui/hud_upgrade_track.gd")
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
	hud.weapon_track.setup_track("[함선 업그레이드]", Color(0.85, 0.95, 1.0), Color(0, 0, 0, 0.4), Color(0.3, 0.3, 0.3, 0.8))
	hud.top_left_container.add_child(hud.weapon_track)
	hud.weapon_container = hud.weapon_track.slot_container
	hud.weapon_slots = hud.weapon_track.slots
	for slot in hud.weapon_slots:
		hud._bind_upgrade_slot_hover(slot)

	hud.support_track = HudUpgradeTrack.new()
	hud.support_track.setup_track("[병사 업그레이드]", Color(1.0, 0.92, 0.72), Color(0, 0, 0, 0.35), Color(0.25, 0.25, 0.25, 0.8))
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
		hud.score_label.add_theme_font_size_override("font_size", 18)
		hud.score_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))

	hud.combat_stats_label = Label.new()
	hud.combat_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud.combat_stats_label.add_theme_font_size_override("font_size", 12)
	hud.combat_stats_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	hud.combat_stats_label.text = "[전과] 격침 0 | 나포 0 | 병사 0"
	hud.top_left_container.add_child(hud.combat_stats_label)

	if hud.difficulty_label:
		move_label_to_container(hud.difficulty_label, hud.top_left_container)
		hud.difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hud.difficulty_label.add_theme_font_size_override("font_size", 12)
		hud.difficulty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

static func setup_top_center_layout(hud) -> void:
	if hud == null:
		return
	hud.timer_label = hud._ensure_hud_label(hud.timer_label, "TimerLabel", "0:00")
	var top_center_container = PanelContainer.new()
	hud.add_child(top_center_container)
	top_center_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top_center_container.offset_top = 40
	top_center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var time_sb = StyleBoxFlat.new()
	time_sb.bg_color = Color(0, 0, 0, 0.35)
	time_sb.set_corner_radius_all(12)
	time_sb.content_margin_left = 16
	time_sb.content_margin_right = 16
	time_sb.content_margin_top = 4
	time_sb.content_margin_bottom = 4
	top_center_container.add_theme_stylebox_override("panel", time_sb)

	move_label_to_container(hud.timer_label, top_center_container)
	hud.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.timer_label.add_theme_font_size_override("font_size", 22)
	hud.timer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	hud.timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hud.timer_label.add_theme_constant_override("shadow_outline_size", 2)

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
	var speed_panel_style = StyleBoxFlat.new()
	speed_panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	speed_panel_style.set_corner_radius_all(8)
	speed_panel_style.content_margin_left = 8
	speed_panel_style.content_margin_right = 8
	speed_panel_style.content_margin_top = 8
	speed_panel_style.content_margin_bottom = 8
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
	hud.speed_mode_icon.modulate = Color(0.86, 0.93, 1.0, 1.0)
	speed_row.add_child(hud.speed_mode_icon)

	hud.speed_bar = ProgressBar.new()
	hud.speed_bar.custom_minimum_size = Vector2(148, 18)
	hud.speed_bar.min_value = 0.0
	hud.speed_bar.max_value = 100.0
	hud.speed_bar.value = 0.0
	hud.speed_bar.show_percentage = false
	speed_row.add_child(hud.speed_bar)

	var speed_bg = StyleBoxFlat.new()
	speed_bg.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	speed_bg.set_corner_radius_all(4)
	var speed_fg = StyleBoxFlat.new()
	speed_fg.bg_color = Color(0.2, 0.7, 1.0, 0.92)
	speed_fg.set_corner_radius_all(4)
	hud.speed_bar.add_theme_stylebox_override("background", speed_bg)
	hud.speed_bar.add_theme_stylebox_override("fill", speed_fg)

	hud.speed_bar_label = Label.new()
	hud.speed_bar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.speed_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.speed_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.speed_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.speed_bar_label.add_theme_font_size_override("font_size", 11)
	hud.speed_bar_label.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0, 1.0))
	hud.speed_bar_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
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

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.05, 0.09, 0.88)
	panel_style.border_color = Color(0.72, 0.82, 0.92, 0.28)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	hud.stat_panel.add_theme_stylebox_override("panel", panel_style)

	var stat_box = VBoxContainer.new()
	stat_box.custom_minimum_size = Vector2(352, 300)
	stat_box.add_theme_constant_override("separation", 8)
	hud.stat_panel.add_child(stat_box)

	var title = Label.new()
	title.text = "전투 수치 [C]"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_outline_size", 2)
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
	if hud.relic_bar == null:
		hud.relic_bar = HudRelicBar.new()
		hud.bottom_right_container.add_child(hud.relic_bar)

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
	hud.crew_label = hud._ensure_hud_label(hud.crew_label, "CrewLabel", "")
	var force_box: VBoxContainer = null
	var crew_row: VBoxContainer = null
	var support_row: HBoxContainer = null
	if hud.force_panel == null:
		hud.force_panel = PanelContainer.new()
		hud.force_panel.name = "ForcePanel"
		var force_style = StyleBoxFlat.new()
		force_style.bg_color = Color(0.02, 0.03, 0.06, 0.72)
		force_style.border_color = Color(0.72, 0.82, 0.92, 0.22)
		force_style.set_border_width_all(1)
		force_style.set_corner_radius_all(8)
		force_style.content_margin_left = 10
		force_style.content_margin_right = 10
		force_style.content_margin_top = 8
		force_style.content_margin_bottom = 8
		hud.force_panel.add_theme_stylebox_override("panel", force_style)
		hud.bottom_left_container.add_child(hud.force_panel)

		force_box = VBoxContainer.new()
		force_box.name = "ForceBox"
		force_box.add_theme_constant_override("separation", 6)
		hud.force_panel.add_child(force_box)

		crew_row = VBoxContainer.new()
		crew_row.name = "CrewRow"
		crew_row.add_theme_constant_override("separation", 4)
		force_box.add_child(crew_row)

		support_row = HBoxContainer.new()
		support_row.name = "SupportRow"
		support_row.add_theme_constant_override("separation", 8)
		force_box.add_child(support_row)
	else:
		force_box = hud.force_panel.get_node_or_null("ForceBox") as VBoxContainer
		crew_row = hud.force_panel.get_node_or_null("ForceBox/CrewRow") as VBoxContainer
		support_row = hud.force_panel.get_node_or_null("ForceBox/SupportRow") as HBoxContainer

	if hud.crew_label and crew_row:
		move_label_to_container(hud.crew_label, crew_row)
		hud.crew_label.add_theme_font_size_override("font_size", 16)
		hud.crew_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	if hud.crew_composition_label == null:
		hud.crew_composition_label = Label.new()
		hud.crew_composition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hud.crew_composition_label.add_theme_font_size_override("font_size", 11)
		hud.crew_composition_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
		hud.crew_composition_label.text = "[편성] 일반 4 | 창병 0 | 화통 0 | 연노 0 | 신기전 0"
	if crew_row and hud.crew_composition_label.get_parent() != crew_row:
		move_label_to_container(hud.crew_composition_label, crew_row)

	if hud.crew_status_bar == null:
		hud.crew_status_bar = ProgressBar.new()
		hud.crew_status_bar.custom_minimum_size = Vector2(220, 8)
		hud.crew_status_bar.max_value = 1.0
		hud.crew_status_bar.show_percentage = false
		var crew_bg = StyleBoxFlat.new()
		crew_bg.bg_color = Color(0.08, 0.08, 0.1, 0.82)
		crew_bg.set_corner_radius_all(3)
		var crew_fg = StyleBoxFlat.new()
		crew_fg.bg_color = Color(0.92, 0.28, 0.28, 0.88)
		crew_fg.set_corner_radius_all(3)
		hud.crew_status_bar.add_theme_stylebox_override("background", crew_bg)
		hud.crew_status_bar.add_theme_stylebox_override("fill", crew_fg)
	if crew_row and hud.crew_status_bar.get_parent() != crew_row:
		move_label_to_container(hud.crew_status_bar, crew_row)

	if hud.support_status_label == null:
		hud.support_status_label = Label.new()
		hud.support_status_label.text = "지원함 0/0"
		hud.support_status_label.add_theme_font_size_override("font_size", 13)
		hud.support_status_label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.98))
	if support_row and hud.support_status_label.get_parent() != support_row:
		move_label_to_container(hud.support_status_label, support_row)

	if hud.support_slot_container == null:
		hud.support_slot_container = HBoxContainer.new()
		hud.support_slot_container.name = "SupportSlots"
		hud.support_slot_container.add_theme_constant_override("separation", 6)
	if support_row and hud.support_slot_container.get_parent() != support_row:
		move_label_to_container(hud.support_slot_container, support_row)

	hud.hp_bar = ProgressBar.new()
	hud.hp_bar.custom_minimum_size = Vector2(240, 24)
	hud.hp_bar.show_percentage = false
	hud.bottom_left_container.add_child(hud.hp_bar)

	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	sb_bg.set_corner_radius_all(4)
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.2, 0.8, 0.3, 0.9)
	sb_fg.set_corner_radius_all(4)
	hud.hp_bar.add_theme_stylebox_override("background", sb_bg)
	hud.hp_bar.add_theme_stylebox_override("fill", sb_fg)

	hud.hp_text_label = Label.new()
	hud.hp_text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.hp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.hp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.hp_text_label.add_theme_font_size_override("font_size", 14)
	hud.hp_bar.add_child(hud.hp_text_label)

	hud.stamina_bar = ProgressBar.new()
	hud.stamina_bar.custom_minimum_size = Vector2(240, 8)
	hud.stamina_bar.show_percentage = false
	hud.bottom_left_container.add_child(hud.stamina_bar)

	var stam_bg = StyleBoxFlat.new()
	stam_bg.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	stam_bg.set_corner_radius_all(2)
	var stam_fg = StyleBoxFlat.new()
	stam_fg.bg_color = Color(1.0, 0.8, 0.2, 0.9)
	stam_fg.set_corner_radius_all(2)
	hud.stamina_bar.add_theme_stylebox_override("background", stam_bg)
	hud.stamina_bar.add_theme_stylebox_override("fill", stam_fg)

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

	var boss_sb_bg = StyleBoxFlat.new()
	boss_sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	boss_sb_bg.set_corner_radius_all(4)
	var boss_sb_fg = StyleBoxFlat.new()
	boss_sb_fg.bg_color = Color(0.9, 0.2, 0.2, 0.9)
	boss_sb_fg.set_corner_radius_all(4)
	hud.boss_hp_bar_new.add_theme_stylebox_override("background", boss_sb_bg)
	hud.boss_hp_bar_new.add_theme_stylebox_override("fill", boss_sb_fg)

	hud.boss_hp_text_label = Label.new()
	hud.boss_hp_text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.boss_hp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.boss_hp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	hud.boarding_label.add_theme_font_size_override("font_size", 16)
	hud.boarding_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.boarding_label.add_theme_constant_override("outline_size", 4)
	hud.boarding_ui.add_child(hud.boarding_label)

	hud.boarding_bar = ProgressBar.new()
	hud.boarding_bar.custom_minimum_size = Vector2(200, 12)
	hud.boarding_bar.show_percentage = false
	var b_bg = StyleBoxFlat.new()
	b_bg.bg_color = Color(0, 0, 0, 0.4)
	b_bg.set_corner_radius_all(4)
	var b_fg = StyleBoxFlat.new()
	b_fg.bg_color = Color(1.0, 1.0, 1.0, 0.8)
	b_fg.set_corner_radius_all(4)
	hud.boarding_bar.add_theme_stylebox_override("background", b_bg)
	hud.boarding_bar.add_theme_stylebox_override("fill", b_fg)
	hud.boarding_ui.add_child(hud.boarding_bar)
