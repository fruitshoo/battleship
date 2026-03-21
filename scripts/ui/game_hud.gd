extends CanvasLayer
const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const HudGameOverOverlay = preload("res://scripts/ui/hud_game_over_overlay.gd")
const HudUpgradeTooltip = preload("res://scripts/ui/hud_upgrade_tooltip.gd")
const HudLayoutBuilder = preload("res://scripts/ui/hud_layout_builder.gd")
const HudUpdateHelper = preload("res://scripts/ui/hud_update_helper.gd")
const HudUpgradeInfoHelper = preload("res://scripts/ui/hud_upgrade_info_helper.gd")
const HudStatPanelHelper = preload("res://scripts/ui/hud_stat_panel_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const CollisionVisualizer = preload("res://scripts/helpers/collision_visualizer.gd")
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

## 게임 HUD
## 현재 HUD는 런타임에 레이아웃을 조립하며, 이 스크립트는 상태 보관과 갱신 허브 역할을 맡는다.

# Core HUD labels
var level_label: Label = null
var score_label: Label = null
var timer_label: Label = null
var capture_opportunity_label: Label = null
var difficulty_label: Label = null
var crew_label: Label = null
var xp_bar: ProgressBar = null
@onready var gust_warning: Label = $GustWarning
@onready var game_over_label: Label = $GameOverLabel
@onready var victory_label: Label = $VictoryLabel

# Runtime state
var game_time: float = 0.0
var _gust_warning_timer: float = 0.0
var player_ship: Node3D = null
var _player_lookup_cooldown: float = 0.0
var _cached_level_manager: Node = null
var _cached_environment_preset_manager: Node = null

# Layout references
var hp_bar: ProgressBar = null
var hp_text_label: Label = null
var boss_hp_bar_new: ProgressBar = null
var boss_hp_text_label: Label = null
var stamina_bar: ProgressBar = null
var top_left_container: VBoxContainer = null
var top_right_container: VBoxContainer = null
var bottom_left_container: VBoxContainer = null
var bottom_right_container: VBoxContainer = null
var speed_display: Label = null
var speed_mode_icon: TextureRect = null
var speed_bar: ProgressBar = null
var speed_bar_label: Label = null
var weapon_track = null
var support_track = null
var force_panel: PanelContainer = null
var crew_status_bar: ProgressBar = null
var support_status_label: Label = null
var support_slot_container: HBoxContainer = null
var support_fleet_hud_slots: Array[PanelContainer] = []
var sail_debug_panel: PanelContainer = null
var sail_debug_toggle_button: Button = null
var sail_debug_damage_slider: HSlider = null
var sail_debug_burn_slider: HSlider = null
var sail_debug_hole_slider: HSlider = null
var sail_debug_damage_value: Label = null
var sail_debug_burn_value: Label = null
var sail_debug_hole_value: Label = null
var debug_environment_value: Label = null
var debug_collision_value: Label = null
var _sail_debug_ui_syncing: bool = false

# Boarding UI
var boarding_ui: VBoxContainer = null
var boarding_bar: ProgressBar = null
var boarding_label: Label = null

# Merit UI
var merit_bar: ProgressBar = null
var merit_label: Label = null

# Cached text/state
var _last_timer_str: String = ""
var _last_capture_opportunity_text: String = ""
var _last_speed_str: String = ""
var _last_speed_ratio: float = -1.0
var _last_speed_mode: String = ""
var _speed_visual_value: float = 0.0
var _last_difficulty_text: String = ""
var _last_combat_stats_text: String = ""
var _item_refresh_retry_left: float = 0.0
var _sail_debug_sync_left: float = 0.0

# Item and stat UI
var item_bar = null
var ship_hp_overlay: Control = null
var ship_hp_bars: Dictionary = {}
@export var show_ship_health_bars: bool = true
@export var show_stat_panel: bool = false
var stat_panel: PanelContainer = null
var stat_scroll: ScrollContainer = null
var stat_content: VBoxContainer = null
var _last_stat_signature: String = ""
@export_range(0.05, 1.0) var stat_refresh_interval: float = 0.2
var _stat_refresh_left: float = 0.0

# Upgrade slot UI
var weapon_container: Container = null
var weapon_slots: Array[PanelContainer] = []
var active_weapons: Dictionary = {} # 함선 업그레이드 ID -> 슬롯 인덱스
var support_container: Container = null
var support_slots: Array[PanelContainer] = []
var active_supports: Dictionary = {} # 병사 업그레이드 ID -> 슬롯 인덱스
var combat_stats_label: Label = null
var combat_stats_row: HBoxContainer = null
var combat_sunk_value_label: Label = null
var combat_derelict_value_label: Label = null
var combat_soldier_value_label: Label = null
var crew_composition_label: Label = null
var upgrade_tooltip_panel = null
var _tooltip_slot_ref: PanelContainer = null
var _tooltip_hover_slot: PanelContainer = null
var _tooltip_hover_elapsed: float = 0.0
var game_over_overlay: Control = null
var _game_over_transitioning: bool = false
@export_range(0.03, 0.5) var hud_refresh_interval: float = 0.05
var _hud_refresh_left: float = 0.0

const UPGRADE_TOOLTIP_SHOW_DELAY: float = 0.14
const UPGRADE_TOOLTIP_MIN_WIDTH: float = 320.0
const SHIP_HP_BAR_WIDTH: float = 82.0
const SHIP_HP_BAR_HEIGHT: float = 10.0
const SHIP_HP_BAR_OFFSET_Y: float = 34.0

const SHIP_UPGRADE_IDS := [
	"cannon", "janggun",
	"hull_defense", "sailing", "rowing", "supply_bonus", "fleet_signal",
	"fleet_cannon", "fleet_hull", "supply", "gold"
]
const CREW_UPGRADE_IDS := [
	"crew_numbers", "crew_attack", "crew_defense", "singigeon", "fire_pot", "repeating_crossbow",
	"fleet_crew"
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_overlay_theme()
	_setup_top_xp_bar()
	_setup_new_layout()
	_setup_game_over_overlay()
	_setup_ship_hp_overlay()

	update_level(1)
	update_score(0)
	update_crew_status(4)
	_setup_sail_debug_panel()
	if gust_warning:
		gust_warning.visible = false
	call_deferred("_refresh_owned_item_icons")


func _apply_overlay_theme() -> void:
	if is_instance_valid(gust_warning):
		NavalUiTheme.style_accent(gust_warning, 22)
		gust_warning.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
		gust_warning.add_theme_constant_override("outline_size", 4)
	if is_instance_valid(game_over_label):
		game_over_label.add_theme_color_override("font_color", Color(0.84, 0.34, 0.28, 1.0))
		game_over_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
		game_over_label.add_theme_constant_override("outline_size", 4)
	if is_instance_valid(victory_label):
		victory_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_GOLD)
		victory_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
		victory_label.add_theme_constant_override("outline_size", 4)

func _ensure_hud_label(existing: Label, node_name: String, default_text: String) -> Label:
	if is_instance_valid(existing):
		return existing
	var label := Label.new()
	label.name = node_name
	label.text = default_text
	add_child(label)
	return label


func _setup_top_xp_bar() -> void:
	level_label = _ensure_hud_label(level_label, "LevelLabel", "[Lv] 1")
	xp_bar = ProgressBar.new()
	xp_bar.name = "TopXPBar"
	add_child(xp_bar)

	xp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	xp_bar.custom_minimum_size.y = 18.0
	xp_bar.show_percentage = false
	xp_bar.z_index = 10

	NavalUiTheme.apply_progress_bar(xp_bar, Color(0.06, 0.08, 0.11, 0.82), Color(0.58, 0.77, 0.92, 0.94), 0)

	merit_bar = ProgressBar.new()
	merit_bar.name = "TopMeritBar"
	add_child(merit_bar)

	merit_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	merit_bar.offset_top = 22.0
	merit_bar.custom_minimum_size.y = 12.0
	merit_bar.show_percentage = false
	merit_bar.z_index = 10

	NavalUiTheme.apply_progress_bar(merit_bar, Color(0.09, 0.08, 0.06, 0.84), Color(0.92, 0.75, 0.28, 0.94), 0)

	merit_label = Label.new()
	merit_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	merit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	merit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(merit_label, 10)
	merit_label.add_theme_constant_override("outline_size", 3)
	merit_label.text = "지휘 포인트 (병영 강화 대기)"
	merit_bar.add_child(merit_label)

func _setup_new_layout() -> void:
	HudLayoutBuilder.setup_new_layout(self)

func _setup_sail_debug_panel() -> void:
	if not OS.is_debug_build():
		return
	if is_instance_valid(sail_debug_panel):
		return
	sail_debug_toggle_button = Button.new()
	sail_debug_toggle_button.name = "DebugToolsToggle"
	sail_debug_toggle_button.text = "Debug"
	sail_debug_toggle_button.custom_minimum_size = Vector2(72, 30)
	NavalUiTheme.apply_hud_button(sail_debug_toggle_button, 11)
	sail_debug_toggle_button.pressed.connect(func() -> void:
		if not is_instance_valid(sail_debug_panel):
			return
		sail_debug_panel.visible = not sail_debug_panel.visible
		_update_sail_debug_toggle_button_text()
		if sail_debug_panel.visible:
			_sync_sail_debug_panel_from_player()
			_sync_debug_tools_panel_state()
	)
	if is_instance_valid(bottom_right_container):
		bottom_right_container.add_child(sail_debug_toggle_button)
	else:
		add_child(sail_debug_toggle_button)
		sail_debug_toggle_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		sail_debug_toggle_button.offset_right = -24
		sail_debug_toggle_button.offset_bottom = -24

	sail_debug_panel = PanelContainer.new()
	sail_debug_panel.name = "SailDebugPanel"
	var panel_style := NavalUiTheme.make_hud_panel_style()
	sail_debug_panel.add_theme_stylebox_override("panel", panel_style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(232, 280)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sail_debug_panel.add_child(scroll)

	var panel_box := VBoxContainer.new()
	panel_box.custom_minimum_size = Vector2(212, 0)
	panel_box.add_theme_constant_override("separation", 6)
	scroll.add_child(panel_box)

	var title := Label.new()
	title.text = "Debug Tools"
	NavalUiTheme.style_heading(title, 13)
	panel_box.add_child(title)

	var hint := Label.new()
	hint.text = "기존 F키 기능을 버튼으로 모아둔 패널"
	NavalUiTheme.style_muted(hint, 10)
	panel_box.add_child(hint)

	var environment_section: Dictionary = _create_debug_section("환경", false)
	panel_box.add_child(environment_section["root"])
	var environment_status := Label.new()
	environment_status.text = "프리셋: -"
	NavalUiTheme.style_body(environment_status, 11)
	environment_section["body"].add_child(environment_status)
	debug_environment_value = environment_status

	var environment_row := HBoxContainer.new()
	environment_row.add_theme_constant_override("separation", 6)
	environment_section["body"].add_child(environment_row)
	environment_row.add_child(_create_debug_action_button("낮", func() -> void:
		_apply_environment_preset(0)
	))
	environment_row.add_child(_create_debug_action_button("밤", func() -> void:
		_apply_environment_preset(1)
	))

	var collision_section: Dictionary = _create_debug_section("충돌", false)
	panel_box.add_child(collision_section["root"])
	var collision_status := Label.new()
	collision_status.text = "충돌 시각화: OFF"
	NavalUiTheme.style_body(collision_status, 11)
	collision_section["body"].add_child(collision_status)
	debug_collision_value = collision_status

	var collision_row := HBoxContainer.new()
	collision_row.add_theme_constant_override("separation", 6)
	collision_section["body"].add_child(collision_row)
	collision_row.add_child(_create_debug_action_button("표시 토글", func() -> void:
		_invoke_level_debug_method("_toggle_collision_visualizers")
		_sync_debug_tools_panel_state()
	))
	collision_row.add_child(_create_debug_action_button("모드 순환", func() -> void:
		_invoke_level_debug_method("_cycle_collision_visualizer_mode")
		_sync_debug_tools_panel_state()
	))

	var spawn_section: Dictionary = _create_debug_section("스폰", false)
	panel_box.add_child(spawn_section["root"])
	var spawn_row_a := HBoxContainer.new()
	spawn_row_a.add_theme_constant_override("separation", 4)
	spawn_section["body"].add_child(spawn_row_a)
	spawn_row_a.add_child(_create_debug_action_button("세키 근접", func() -> void:
		_invoke_level_debug_method("_debug_spawn_test_ship", ["sekibune_melee", 40.0, -12.0])
	))
	spawn_row_a.add_child(_create_debug_action_button("세키 포격", func() -> void:
		_invoke_level_debug_method("_debug_spawn_test_ship", ["sekibune_cannon", 40.0, 12.0])
	))

	var spawn_row_b := HBoxContainer.new()
	spawn_row_b.add_theme_constant_override("separation", 4)
	spawn_section["body"].add_child(spawn_row_b)
	spawn_row_b.add_child(_create_debug_action_button("중간보스", func() -> void:
		_invoke_level_debug_method("_debug_spawn_mid_boss")
	))
	spawn_row_b.add_child(_create_debug_action_button("최종보스", func() -> void:
		_invoke_level_debug_method("_debug_spawn_final_boss")
	))

	var spawn_row_c := HBoxContainer.new()
	spawn_row_c.add_theme_constant_override("separation", 4)
	spawn_section["body"].add_child(spawn_row_c)
	spawn_row_c.add_child(_create_debug_action_button("지원함 추가", func() -> void:
		_invoke_level_debug_method("_debug_spawn_support_ship")
	))
	spawn_row_c.add_child(_create_debug_action_button("지원함 덤프", func() -> void:
		_invoke_level_debug_method("_debug_dump_support_fleet_state")
	))

	var misc_section: Dictionary = _create_debug_section("게임", false)
	panel_box.add_child(misc_section["root"])
	var misc_row := HBoxContainer.new()
	misc_row.add_theme_constant_override("separation", 4)
	misc_section["body"].add_child(misc_row)
	misc_row.add_child(_create_debug_action_button("강제 레벨업", func() -> void:
		_invoke_level_debug_method("add_xp", [9999])
	))
	misc_row.add_child(_create_debug_action_button("메타샵", func() -> void:
		_invoke_level_debug_method("show_meta_shop")
	))

	var misc_row_b := HBoxContainer.new()
	misc_row_b.add_theme_constant_override("separation", 4)
	misc_section["body"].add_child(misc_row_b)
	misc_row_b.add_child(_create_debug_action_button("대포 디버그", func() -> void:
		_invoke_level_debug_method("_debug_cannons")
	))
	misc_row_b.add_child(_create_debug_action_button("체력바 토글", func() -> void:
		toggle_ship_health_bars()
	))

	var misc_row_c := HBoxContainer.new()
	misc_row_c.add_theme_constant_override("separation", 4)
	misc_section["body"].add_child(misc_row_c)
	misc_row_c.add_child(_create_debug_action_button("통계 패널", func() -> void:
		toggle_stat_panel()
	))

	var sail_section: Dictionary = _create_debug_section("돛", true)
	panel_box.add_child(sail_section["root"])

	var damage_row: Dictionary = _create_sail_debug_slider_row("Damage")
	sail_section["body"].add_child(damage_row["root"])
	sail_debug_damage_slider = damage_row["slider"]
	sail_debug_damage_value = damage_row["value"]
	sail_debug_damage_slider.value_changed.connect(_on_sail_debug_damage_changed)

	var burn_row: Dictionary = _create_sail_debug_slider_row("Burn")
	sail_section["body"].add_child(burn_row["root"])
	sail_debug_burn_slider = burn_row["slider"]
	sail_debug_burn_value = burn_row["value"]
	sail_debug_burn_slider.value_changed.connect(_on_sail_debug_burn_changed)

	var hole_row: Dictionary = _create_sail_debug_slider_row("Hole")
	sail_section["body"].add_child(hole_row["root"])
	sail_debug_hole_slider = hole_row["slider"]
	sail_debug_hole_value = hole_row["value"]
	sail_debug_hole_slider.max_value = 2.0
	sail_debug_hole_slider.step = 0.01
	sail_debug_hole_slider.value = 1.0
	sail_debug_hole_slider.value_changed.connect(_on_sail_debug_hole_changed)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 4)
	sail_section["body"].add_child(preset_row)
	for preset in [
		{"label": "Clean", "damage": 0.0, "burn": 0.0},
		{"label": "Scorch", "damage": 0.22, "burn": 0.18, "hole": 0.5},
		{"label": "Fray", "damage": 0.55, "burn": 0.32, "hole": 1.0},
		{"label": "Burn", "damage": 0.88, "burn": 0.70, "hole": 1.4},
	]:
		var preset_button := Button.new()
		preset_button.text = str(preset["label"])
		preset_button.custom_minimum_size = Vector2(0, 26)
		preset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		NavalUiTheme.apply_hud_button(preset_button, 11)
		preset_button.pressed.connect(func() -> void:
			_apply_sail_debug_values(float(preset["damage"]), float(preset["burn"]), float(preset.get("hole", 1.0)))
		)
		preset_row.add_child(preset_button)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	sail_section["body"].add_child(action_row)

	var sync_button := Button.new()
	sync_button.text = "Sync"
	sync_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.apply_hud_button(sync_button, 11)
	sync_button.pressed.connect(_sync_sail_debug_panel_from_player)
	action_row.add_child(sync_button)

	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.apply_hud_button(reset_button, 11)
	reset_button.pressed.connect(func() -> void:
		_apply_sail_debug_values(0.0, 0.0, 1.0)
	)
	action_row.add_child(reset_button)

	if is_instance_valid(bottom_right_container):
		bottom_right_container.add_child(sail_debug_panel)
	else:
		add_child(sail_debug_panel)
		sail_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		sail_debug_panel.offset_right = -24
		sail_debug_panel.offset_bottom = -120
	sail_debug_panel.visible = false
	_sync_sail_debug_panel_from_player()
	_sync_debug_tools_panel_state()
	_update_sail_debug_toggle_button_text()


func _create_debug_section(title_text: String, expanded: bool) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)

	var toggle := Button.new()
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.flat = true
	toggle.text = ""
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.add_theme_color_override("font_color", NavalUiTheme.TEXT_ACCENT)
	root.add_child(toggle)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.visible = expanded
	root.add_child(body)

	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		_update_debug_section_button_text(toggle, title_text, body.visible)
	)
	_update_debug_section_button_text(toggle, title_text, expanded)

	return {
		"root": root,
		"toggle": toggle,
		"body": body,
	}


func _update_debug_section_button_text(button: Button, title_text: String, expanded: bool) -> void:
	button.text = "%s %s" % ["▾" if expanded else "▸", title_text]


func _create_debug_action_button(button_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(0, 28)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.apply_hud_button(button, 11)
	button.pressed.connect(callback)
	return button


func _update_sail_debug_toggle_button_text() -> void:
	if not is_instance_valid(sail_debug_toggle_button):
		return
	sail_debug_toggle_button.text = "Debug 닫기" if is_instance_valid(sail_debug_panel) and sail_debug_panel.visible else "Debug 열기"

func _create_sail_debug_slider_row(title_text: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(title, 11)
	header.add_child(title)

	var value := Label.new()
	value.text = "0.00"
	value.custom_minimum_size.x = 38
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	NavalUiTheme.style_accent(value, 11)
	header.add_child(value)
	root.add_child(header)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.0
	root.add_child(slider)

	return {
		"root": root,
		"slider": slider,
		"value": value,
	}

func _process(delta: float) -> void:
	_sync_game_time(delta)
	if _gust_warning_timer > 0.0:
		_gust_warning_timer = maxf(0.0, _gust_warning_timer - delta)
		if gust_warning:
			gust_warning.visible = true
	elif gust_warning and gust_warning.visible:
		gust_warning.visible = false
	_player_lookup_cooldown = maxf(0.0, _player_lookup_cooldown - delta)
	if not is_instance_valid(player_ship):
		_try_resolve_player_ship()
	_update_upgrade_tooltip_state(delta)
	_update_upgrade_tooltip_position()
	_item_refresh_retry_left = maxf(0.0, _item_refresh_retry_left - delta)
	if _item_refresh_retry_left <= 0.0 and item_bar and is_instance_valid(UpgradeManager):
		var owned_items = UpgradeManager.acquired_items if "acquired_items" in UpgradeManager else []
		if owned_items is Array and item_bar.current_item_count < owned_items.size():
			_item_refresh_retry_left = 0.5
			_refresh_owned_item_icons()
	if is_instance_valid(sail_debug_panel) and sail_debug_panel.visible:
		_sail_debug_sync_left = maxf(0.0, _sail_debug_sync_left - delta)
		if _sail_debug_sync_left <= 0.0:
			_sail_debug_sync_left = 0.2
			_sync_sail_debug_panel_from_player()
			_sync_debug_tools_panel_state()
	if show_ship_health_bars:
		_update_ship_health_bars(true)
	_hud_refresh_left -= delta
	if _hud_refresh_left <= 0.0:
		_hud_refresh_left = hud_refresh_interval
		_update_timer()
		_update_speed_display()
		_update_force_panel()
		_update_hull_display()
		_update_stamina_display()
		_update_boarding_display()
		_update_capture_opportunity_display()
		_update_ship_health_bars(false)
	if show_stat_panel:
		_stat_refresh_left -= delta
		if _stat_refresh_left <= 0.0:
			_stat_refresh_left = stat_refresh_interval
			_update_stat_panel()


func _sync_game_time(delta: float) -> void:
	if not is_instance_valid(_cached_level_manager):
		_cached_level_manager = SceneGroupCache.get_first(get_tree(), "level_manager")
	if is_instance_valid(_cached_level_manager) and _cached_level_manager.get("current_time") != null:
		game_time = float(_cached_level_manager.current_time)
	else:
		game_time += delta

func _attach_level_label_to_xp_bar() -> void:
	if not level_label or not xp_bar:
		return
	var current_parent = level_label.get_parent()
	if current_parent and current_parent != xp_bar:
		current_parent.remove_child(level_label)
	if level_label.get_parent() != xp_bar:
		xp_bar.add_child(level_label)
	level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
	level_label.add_theme_constant_override("outline_size", 4)

func _try_resolve_player_ship() -> void:
	if is_instance_valid(player_ship):
		return
	if _player_lookup_cooldown > 0.0:
		return
	_player_lookup_cooldown = 0.25
	var players = SceneGroupCache.get_nodes(get_tree(), "player")
	for p in players:
		if is_instance_valid(p) and p.get("is_player_controlled") == true:
			player_ship = p
			return
	if players.size() > 0 and is_instance_valid(players[0]):
		player_ship = players[0]


func _get_level_manager_for_debug() -> Node:
	if not is_instance_valid(_cached_level_manager):
		_cached_level_manager = SceneGroupCache.get_first(get_tree(), "level_manager")
	return _cached_level_manager


func _get_environment_preset_manager_for_debug() -> Node:
	if is_instance_valid(_cached_environment_preset_manager):
		return _cached_environment_preset_manager
	_cached_environment_preset_manager = get_tree().root.find_child("EnvironmentPresetManager", true, false)
	return _cached_environment_preset_manager


func _invoke_level_debug_method(method_name: String, args: Array = []) -> void:
	var level_manager: Node = _get_level_manager_for_debug()
	if not is_instance_valid(level_manager):
		show_gust_warning_message("LevelManager 없음", 0.8)
		return
	if not level_manager.has_method(method_name):
		show_gust_warning_message("디버그 메서드 없음: %s" % method_name, 0.8)
		return
	level_manager.callv(method_name, args)


func _apply_environment_preset(preset_index: int) -> void:
	var preset_manager: Node = _get_environment_preset_manager_for_debug()
	if not is_instance_valid(preset_manager) or not preset_manager.has_method("apply_preset"):
		show_gust_warning_message("환경 프리셋 매니저 없음", 0.8)
		return
	preset_manager.call("apply_preset", preset_index)
	_sync_debug_tools_panel_state()


func _sync_debug_tools_panel_state() -> void:
	if not is_instance_valid(sail_debug_panel):
		return
	if is_instance_valid(debug_environment_value):
		var preset_manager: Node = _get_environment_preset_manager_for_debug()
		var environment_text: String = "-"
		if is_instance_valid(preset_manager):
			var preset_index: int = int(preset_manager.get("current_preset"))
			environment_text = "낮" if preset_index == 0 else "밤"
		debug_environment_value.text = "프리셋: %s" % environment_text
	if is_instance_valid(debug_collision_value):
		var collision_text := "OFF"
		if CollisionVisualizer.runtime_enabled:
			var mode_name := "ALL"
			match CollisionVisualizer.runtime_mode:
				CollisionVisualizer.MODE_BASE:
					mode_name = "BASE"
				CollisionVisualizer.MODE_SEPARATION:
					mode_name = "SEPARATION"
				CollisionVisualizer.MODE_GUARD:
					mode_name = "GUARD"
			collision_text = "ON (%s)" % mode_name
		debug_collision_value.text = "충돌 시각화: %s" % collision_text


func update_level(val: int) -> void:
	HudUpdateHelper.update_level(self, val)

func update_score(val: int) -> void:
	HudUpdateHelper.update_score(self, val)

func update_combat_stats(ship_sunk: int, ships_derelicted: int, soldiers_killed: int, soldiers_slain: int, soldiers_drowned: int) -> void:
	HudUpdateHelper.update_combat_stats(self, ship_sunk, ships_derelicted, soldiers_killed, soldiers_slain, soldiers_drowned)

func update_difficulty_ui(val: int) -> void:
	HudUpdateHelper.update_difficulty_ui(self, val)

func update_crew_status(count: int, max_count: int = 4) -> void:
	HudUpdateHelper.update_crew_status(self, count, max_count)

func _update_timer() -> void:
	HudUpdateHelper.update_timer(self)

func _update_speed_display() -> void:
	HudUpdateHelper.update_speed_display(self)

func _update_crew_count() -> void:
	HudUpdateHelper.update_crew_count(self)

func _update_force_panel() -> void:
	HudUpdateHelper.update_force_panel(self)

func update_hull_hp(current: float, maximum: float) -> void:
	if hp_bar:
		hp_bar.max_value = maximum

		var tween = create_tween()
		tween.tween_property(hp_bar, "value", current, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		if hp_text_label:
			hp_text_label.text = "HP %.0f / %.0f" % [current, maximum]

		var ratio = current / maximum
		var fill_style = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if ratio > 0.6:
				fill_style.bg_color = NavalUiTheme.STATUS_GOOD
			elif ratio > 0.3:
				fill_style.bg_color = NavalUiTheme.STATUS_WARN
			else:
				fill_style.bg_color = NavalUiTheme.STATUS_DANGER

func update_stamina(current: float, maximum: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = maximum
		stamina_bar.value = current

		var fill_style = stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if current < 1.0:
				fill_style.bg_color = NavalUiTheme.STATUS_DANGER
			else:
				fill_style.bg_color = NavalUiTheme.STATUS_WARN

func update_xp(current: int, maximum: int) -> void:
	if xp_bar:
		xp_bar.max_value = maximum
		xp_bar.value = current

func update_merit(current: int, maximum: int, level: int = 1) -> void:
	if merit_bar:
		merit_bar.max_value = maximum

		var tween = create_tween()
		tween.tween_property(merit_bar, "value", current, 0.3).set_trans(Tween.TRANS_SINE)

		if merit_label:
			if current >= maximum:
				merit_label.text = "[ 병영 LEVEL UP! ]"
				merit_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_GOLD)

				var style = merit_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if style:
					style.bg_color = Color(1.0, 0.94, 0.58, 1.0)
			else:
				merit_label.text = "지휘 Lv.%d (%d / %d)" % [level, current, maximum]
				merit_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN)

				var style_normal = merit_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if style_normal:
					style_normal.bg_color = NavalUiTheme.STATUS_WARN

func add_item_icon(icon_data) -> void:
	if item_bar == null:
		return
	var slot: PanelContainer = item_bar.add_icon(icon_data)
	if is_instance_valid(slot):
		var item_name: String = ""
		var item_description: String = ""
		if icon_data is Dictionary:
			item_name = str(icon_data.get("name", "아이템"))
			item_description = str(icon_data.get("description", ""))
		var tooltip_text: String = "[%s]\n%s" % [item_name, item_description]
		slot.set_meta("tooltip_text", tooltip_text.strip_edges())
		slot.set_meta("tooltip_color", NavalUiTheme.TEXT_GOLD)
		if not bool(slot.get_meta("hover_bound", false)):
			_bind_upgrade_slot_hover(slot)
			slot.set_meta("hover_bound", true)

func clear_item_icons() -> void:
	if item_bar == null:
		return
	if item_bar.has_method("clear_icons"):
		item_bar.clear_icons()

func _refresh_owned_item_icons() -> void:
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("refresh_hud_item_icons"):
		UpgradeManager.refresh_hud_item_icons()


func _setup_ship_hp_overlay() -> void:
	if is_instance_valid(ship_hp_overlay):
		return
	ship_hp_overlay = Control.new()
	ship_hp_overlay.name = "ShipHealthOverlay"
	ship_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ship_hp_overlay.z_index = 20
	add_child(ship_hp_overlay)
	ship_hp_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _update_ship_health_bars(positions_only: bool = false) -> void:
	HudUpdateHelper.update_ship_health_bars(self, positions_only)

func toggle_ship_health_bars() -> void:
	show_ship_health_bars = not show_ship_health_bars
	_update_ship_health_bars()

func _update_stat_panel() -> void:
	HudStatPanelHelper.update_stat_panel(self)


func toggle_stat_panel() -> void:
	show_stat_panel = not show_stat_panel
	if show_stat_panel:
		_tooltip_hover_slot = null
		_tooltip_slot_ref = null
		_tooltip_hover_elapsed = 0.0
		_hide_upgrade_tooltip(true)
	_stat_refresh_left = 0.0
	_update_stat_panel()

func _setup_upgrade_tooltip() -> void:
	if is_instance_valid(upgrade_tooltip_panel):
		return
	upgrade_tooltip_panel = HudUpgradeTooltip.new()
	add_child(upgrade_tooltip_panel)

func _bind_upgrade_slot_hover(slot: PanelContainer) -> void:
	slot.mouse_entered.connect(_on_upgrade_slot_mouse_entered.bind(slot))
	slot.mouse_exited.connect(_on_upgrade_slot_mouse_exited.bind(slot))

func _on_upgrade_slot_mouse_entered(slot: PanelContainer) -> void:
	if show_stat_panel:
		return
	if not is_instance_valid(upgrade_tooltip_panel):
		return
	if not _slot_has_tooltip(slot):
		return
	_tooltip_hover_slot = slot
	_tooltip_hover_elapsed = 0.0
	if _tooltip_slot_ref != slot and upgrade_tooltip_panel.is_showing():
		_show_slot_tooltip(slot)

func _on_upgrade_slot_mouse_exited(slot: PanelContainer) -> void:
	if _tooltip_hover_slot == slot:
		_tooltip_hover_slot = null
		_tooltip_hover_elapsed = 0.0
	if _tooltip_slot_ref != slot:
		return
	_tooltip_slot_ref = null
	_hide_upgrade_tooltip()

func _update_upgrade_tooltip_state(delta: float) -> void:
	if show_stat_panel:
		if is_instance_valid(upgrade_tooltip_panel) and upgrade_tooltip_panel.is_showing():
			_hide_upgrade_tooltip(true)
		return
	if is_instance_valid(_tooltip_hover_slot):
		_tooltip_hover_elapsed += delta
		if (not is_instance_valid(upgrade_tooltip_panel) or not upgrade_tooltip_panel.is_showing()) and _tooltip_hover_elapsed >= UPGRADE_TOOLTIP_SHOW_DELAY:
			_show_slot_tooltip(_tooltip_hover_slot)

func _show_slot_tooltip(slot: PanelContainer) -> void:
	if show_stat_panel:
		return
	if not is_instance_valid(upgrade_tooltip_panel):
		return
	var tooltip_payload: Dictionary = _get_slot_tooltip_payload(slot)
	if tooltip_payload.is_empty():
		return
	_tooltip_slot_ref = slot
	upgrade_tooltip_panel.show_tooltip(
		str(tooltip_payload.get("text", "")),
		tooltip_payload.get("color", Color(0.9, 0.85, 0.6, 1.0)),
		get_viewport().get_mouse_position(),
		get_viewport().get_visible_rect().size
	)

func _slot_has_tooltip(slot: PanelContainer) -> bool:
	return not _get_slot_tooltip_payload(slot).is_empty()

func _get_slot_tooltip_payload(slot: PanelContainer) -> Dictionary:
	var tooltip_text: String = str(slot.get_meta("tooltip_text", ""))
	if not tooltip_text.is_empty():
		return {
			"text": tooltip_text,
			"color": slot.get_meta("tooltip_color", Color(0.9, 0.85, 0.6, 1.0))
		}
	var upgrade_id = str(slot.get_meta("upgrade_id", ""))
	var level = int(slot.get_meta("upgrade_level", 0))
	if upgrade_id.is_empty() or level <= 0:
		return {}
	return {
		"text": _build_upgrade_tooltip_text(upgrade_id, level),
		"color": _get_upgrade_color(upgrade_id)
	}

func _hide_upgrade_tooltip(instant: bool = false) -> void:
	if not is_instance_valid(upgrade_tooltip_panel):
		return
	upgrade_tooltip_panel.hide_tooltip(instant)

func _update_upgrade_tooltip_position() -> void:
	if not is_instance_valid(upgrade_tooltip_panel) or not upgrade_tooltip_panel.is_showing():
		return
	upgrade_tooltip_panel.update_position(
		get_viewport().get_mouse_position(),
		get_viewport().get_visible_rect().size
	)

func _is_ship_upgrade(upgrade_id: String) -> bool:
	return HudUpgradeInfoHelper.is_ship_upgrade(self, upgrade_id)

func _is_crew_upgrade(upgrade_id: String) -> bool:
	return HudUpgradeInfoHelper.is_crew_upgrade(self, upgrade_id)

func _build_upgrade_tooltip_text(upgrade_id: String, level: int) -> String:
	return HudUpgradeInfoHelper.build_upgrade_tooltip_text(self, upgrade_id, level)

func _build_upgrade_spec_text(upgrade_id: String, level: int, stats: Dictionary) -> String:
	return HudUpgradeInfoHelper.build_upgrade_spec_text(upgrade_id, level, stats)

func _get_upgrade_icon(upgrade_id: String) -> String:
	return HudUpgradeInfoHelper.get_upgrade_icon(upgrade_id)

func _get_upgrade_color(upgrade_id: String) -> Color:
	return HudUpgradeInfoHelper.get_upgrade_color(upgrade_id)

func _update_upgrade_track_slot(upgrade_id: String, level: int, track: String) -> void:
	if level <= 0:
		return
	var actual_icon = _get_upgrade_icon(upgrade_id)
	var actual_color = _get_upgrade_color(upgrade_id)
	var track_node = weapon_track if track == "ship" else support_track
	if not track_node:
		return
	var slots = track_node.slots

	var slot_idx = -1
	if track == "ship":
		if active_weapons.has(upgrade_id):
			slot_idx = active_weapons[upgrade_id]
		else:
			slot_idx = active_weapons.size()
			active_weapons[upgrade_id] = slot_idx
	else:
		if active_supports.has(upgrade_id):
			slot_idx = active_supports[upgrade_id]
		else:
			slot_idx = active_supports.size()
			active_supports[upgrade_id] = slot_idx

	var slot = track_node.update_slot(slot_idx, upgrade_id, level, actual_icon, actual_color)
	if is_instance_valid(slot) and not bool(slot.get_meta("hover_bound", false)):
		_bind_upgrade_slot_hover(slot)
		slot.set_meta("hover_bound", true)

	if track == "ship":
		weapon_slots = track_node.slots
	else:
		support_slots = track_node.slots

func update_ship_upgrade_ui(upgrade_id: String, level: int) -> void:
	_update_upgrade_track_slot(upgrade_id, level, "ship")

func update_crew_upgrade_ui(upgrade_id: String, level: int) -> void:
	_update_upgrade_track_slot(upgrade_id, level, "crew")

func update_weapon_ui(weapon_id: String, level: int) -> void:
	if _is_crew_upgrade(weapon_id):
		update_crew_upgrade_ui(weapon_id, level)
		return
	update_ship_upgrade_ui(weapon_id, level)

func update_support_ui(upgrade_id: String, level: int) -> void:
	if _is_crew_upgrade(upgrade_id):
		update_crew_upgrade_ui(upgrade_id, level)
		return
	update_ship_upgrade_ui(upgrade_id, level)


func _update_hull_display() -> void:
	HudUpdateHelper.update_hull_display(self)

func _update_stamina_display() -> void:
	HudUpdateHelper.update_stamina_display(self)

func _update_boarding_display() -> void:
	HudUpdateHelper.update_boarding_display(self)

func _update_capture_opportunity_display() -> void:
	HudUpdateHelper.update_capture_opportunity_display(self)


func show_game_over() -> void:
	if _game_over_transitioning:
		return
	if game_over_label:
		game_over_label.text = "!!! SHIP DESTROYED !!!"
		game_over_label.visible = true
		# 페이드인
		var tween = create_tween()
		game_over_label.modulate.a = 0.0
		tween.tween_property(game_over_label, "modulate:a", 1.0, 1.0)
	get_tree().paused = true
	if is_instance_valid(game_over_overlay):
		game_over_overlay.show_overlay("함선이 침몰했습니다. 항구로 복귀합니다.", 4.0)


func update_boss_hp(current: float, maximum: float) -> void:
	HudUpdateHelper.update_boss_hp(self, current, maximum)


func show_gust_warning_message(message: String, duration: float = 0.35) -> void:
	if not gust_warning:
		return
	gust_warning.text = message
	gust_warning.visible = true
	_gust_warning_timer = maxf(_gust_warning_timer, duration)


func _get_player_masts_for_debug() -> Array[Node]:
	if not is_instance_valid(player_ship):
		_try_resolve_player_ship()
	if not is_instance_valid(player_ship):
		return []
	var mast_nodes: Array[Node] = []
	var raw_masts = player_ship.get("masts")
	if raw_masts is Array:
		for mast in raw_masts:
			if is_instance_valid(mast):
				mast_nodes.append(mast)
	return mast_nodes


func _apply_sail_debug_values(damage: float, burn: float, hole_strength: float = 1.0) -> void:
	var masts: Array[Node] = _get_player_masts_for_debug()
	if masts.is_empty():
		show_gust_warning_message("돛 디버그 대상 없음", 0.9)
		return
	if is_instance_valid(player_ship):
		player_ship.set_meta("debug_sail_burn_override_active", true)
		player_ship.set_meta("debug_sail_burn_override_value", burn)
	var target_damage := clampf(damage, 0.0, 1.0)
	var target_burn := clampf(burn, 0.0, 1.0)
	var target_hole := clampf(hole_strength, 0.0, 2.0)
	for mast in masts:
		mast.set("sail_damage", target_damage)
		if mast.has_method("set_burn_amount"):
			mast.set_burn_amount(target_burn)
		else:
			mast.set("burn_amount", target_burn)
		if mast.has_method("set_hole_alpha_strength"):
			mast.set_hole_alpha_strength(target_hole)
		else:
			mast.set("hole_alpha_strength", target_hole)
	_sync_sail_debug_panel_from_player()
	show_gust_warning_message("돛 손상 %.2f | burn %.2f | hole %.2f" % [target_damage, target_burn, target_hole], 0.7)


func _sync_sail_debug_panel_from_player() -> void:
	if not is_instance_valid(sail_debug_panel):
		return
	var masts: Array[Node] = _get_player_masts_for_debug()
	if masts.is_empty():
		return
	var first_mast: Node = masts[0]
	var current_damage: float = 0.0
	var current_burn: float = 0.0
	var current_hole: float = 1.0
	if first_mast.has_method("get_sail_damage"):
		current_damage = float(first_mast.get_sail_damage())
	if first_mast.has_method("get_burn_amount"):
		current_burn = float(first_mast.get_burn_amount())
	if first_mast.has_method("get_hole_alpha_strength"):
		current_hole = float(first_mast.get_hole_alpha_strength())
	_sail_debug_ui_syncing = true
	if is_instance_valid(sail_debug_damage_slider):
		sail_debug_damage_slider.value = current_damage
	if is_instance_valid(sail_debug_burn_slider):
		sail_debug_burn_slider.value = current_burn
	if is_instance_valid(sail_debug_hole_slider):
		sail_debug_hole_slider.value = current_hole
	if is_instance_valid(sail_debug_damage_value):
		sail_debug_damage_value.text = "%.2f" % current_damage
	if is_instance_valid(sail_debug_burn_value):
		sail_debug_burn_value.text = "%.2f" % current_burn
	if is_instance_valid(sail_debug_hole_value):
		sail_debug_hole_value.text = "%.2f" % current_hole
	_sail_debug_ui_syncing = false


func _on_sail_debug_damage_changed(value: float) -> void:
	if _sail_debug_ui_syncing:
		return
	var burn_value: float = sail_debug_burn_slider.value if is_instance_valid(sail_debug_burn_slider) else 0.0
	var hole_value: float = sail_debug_hole_slider.value if is_instance_valid(sail_debug_hole_slider) else 1.0
	_apply_sail_debug_values(value, burn_value, hole_value)


func _on_sail_debug_burn_changed(value: float) -> void:
	if _sail_debug_ui_syncing:
		return
	var damage_value: float = sail_debug_damage_slider.value if is_instance_valid(sail_debug_damage_slider) else 0.0
	var hole_value: float = sail_debug_hole_slider.value if is_instance_valid(sail_debug_hole_slider) else 1.0
	_apply_sail_debug_values(damage_value, value, hole_value)


func _on_sail_debug_hole_changed(value: float) -> void:
	if _sail_debug_ui_syncing:
		return
	var damage_value: float = sail_debug_damage_slider.value if is_instance_valid(sail_debug_damage_slider) else 0.0
	var burn_value: float = sail_debug_burn_slider.value if is_instance_valid(sail_debug_burn_slider) else 0.0
	_apply_sail_debug_values(damage_value, burn_value, value)


func show_victory() -> void:
	if victory_label:
		victory_label.text = "[!] VICTORY [!]"
		victory_label.visible = true
		var tween = create_tween()
		victory_label.modulate.a = 0.0
		tween.tween_property(victory_label, "modulate:a", 1.0, 2.0)

func show_victory_with_damage(rows: Array, total_damage: float) -> void:
	if not victory_label:
		return
	var lines: Array[String] = []
	lines.append("[!] VICTORY [!]")
	lines.append("총 무기 피해: %.0f" % total_damage)
	if rows.is_empty():
		lines.append("무기 데미지 통계 없음")
	else:
		lines.append("----- 무기별 데미지 -----")
		for row in rows:
			var name = str(row.get("name", "?"))
			var dmg = float(row.get("damage", 0.0))
			lines.append("%s : %.0f" % [name, dmg])
	
	victory_label.text = "\n".join(lines)
	victory_label.visible = true
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	victory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_label.offset_left = -320.0
	victory_label.offset_top = -180.0
	victory_label.offset_right = 320.0
	victory_label.offset_bottom = 220.0
	victory_label.add_theme_font_size_override("font_size", 24)
	
	var tween = create_tween()
	victory_label.modulate.a = 0.0
	tween.tween_property(victory_label, "modulate:a", 1.0, 0.8)

func _setup_game_over_overlay() -> void:
	if is_instance_valid(game_over_overlay):
		return
	game_over_overlay = HudGameOverOverlay.new()
	game_over_overlay.return_requested.connect(_return_to_main_menu)
	add_child(game_over_overlay)

func _return_to_main_menu() -> void:
	if _game_over_transitioning:
		return
	_game_over_transitioning = true
	if is_instance_valid(game_over_overlay):
		game_over_overlay.hide_overlay()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
