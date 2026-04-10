extends CanvasLayer
const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const HudGameOverOverlay = preload("res://scripts/ui/hud/hud_game_over_overlay.gd")
const HudLayoutBuilder = preload("res://scripts/ui/hud/hud_layout_builder.gd")
const HudUpdateHelper = preload("res://scripts/ui/hud/hud_update_helper.gd")
const HudUpgradeInfoHelper = preload("res://scripts/ui/hud/hud_upgrade_info_helper.gd")
const HudUpgradeTooltipHelper = preload("res://scripts/ui/hud/hud_upgrade_tooltip_helper.gd")
const HudStatPanelHelper = preload("res://scripts/ui/hud/hud_stat_panel_helper.gd")
const HudDebugPanelHelper = preload("res://scripts/ui/hud/hud_debug_panel_helper.gd")
const HudDistanceDebugHelper = preload("res://scripts/ui/hud/hud_distance_debug_helper.gd")
const HudSailDebugHelper = preload("res://scripts/ui/hud/hud_sail_debug_helper.gd")
const HudShipDebugHelper = preload("res://scripts/ui/hud/hud_ship_debug_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const CollisionVisualizer = preload("res://scripts/helpers/collision_visualizer.gd")
const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const CANNON_CLOSE_RANGE_FALLOFF_DISTANCE: float = 8.0
const CANNON_CLOSE_RANGE_MIN_MULTIPLIER: float = 0.55

## 게임 HUD
## 현재 HUD는 런타임에 레이아웃을 조립하며, 이 스크립트는 상태 보관과 갱신 허브 역할을 맡는다.

# Core HUD labels
var level_label: Label = null
var score_label: Label = null
var timer_label: Label = null
var capture_opportunity_label: Label = null
var ammo_mode_label: Label = null
var debug_distance_label: Label = null
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
var support_row: HBoxContainer = null
var support_panel: PanelContainer = null
var crew_status_bar: ProgressBar = null
var support_status_label: Label = null
var support_slot_container: VBoxContainer = null
var support_fleet_hud_slots: Array[PanelContainer] = []
var sail_debug_panel: PanelContainer = null
var sail_debug_toggle_button: Button = null
var sail_debug_damage_slider: HSlider = null
var sail_debug_burn_slider: HSlider = null
var sail_debug_hole_slider: HSlider = null
var sail_debug_damage_value: Label = null
var sail_debug_burn_value: Label = null
var sail_debug_hole_value: Label = null
var debug_ship_status_value: Label = null
var debug_ship_config_value: Label = null
var debug_enemy_fleet_value: Label = null
var debug_ship_hull_slider: HSlider = null
var debug_ship_hull_value: Label = null
var debug_ship_stamina_slider: HSlider = null
var debug_ship_stamina_value: Label = null
var debug_environment_value: Label = null
var debug_collision_value: Label = null
var debug_distance_value: Label = null
var _sail_debug_ui_syncing: bool = false
var _ship_debug_ui_syncing: bool = false

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
var _last_ammo_mode_text: String = ""
var _last_speed_str: String = ""
var _last_speed_ratio: float = -1.0
var _last_speed_mode: String = ""
var _speed_visual_value: float = 0.0
var _last_difficulty_text: String = ""
var _last_combat_stats_text: String = ""
var _item_refresh_retry_left: float = 0.0
var _sail_debug_sync_left: float = 0.0
var _distance_debug_refresh_left: float = 0.0

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
	HudDebugPanelHelper.setup_debug_panel(self)


func _update_sail_debug_toggle_button_text() -> void:
	HudSailDebugHelper.update_sail_debug_toggle_button_text(self)


func _sync_ship_debug_panel_from_player() -> void:
	HudShipDebugHelper.sync_ship_debug_panel_from_player(self)


func _on_debug_ship_hull_changed(value: float) -> void:
	HudShipDebugHelper.on_debug_ship_hull_changed(self, value)


func _on_debug_ship_stamina_changed(value: float) -> void:
	HudShipDebugHelper.on_debug_ship_stamina_changed(self, value)


func _refill_player_crew_for_debug() -> void:
	HudShipDebugHelper.refill_player_crew_for_debug(self)


func _spawn_support_ship_for_debug() -> void:
	HudShipDebugHelper.spawn_support_ship_for_debug(self)


func _stop_player_ship_for_debug() -> void:
	HudShipDebugHelper.stop_player_ship_for_debug(self)


func _toggle_player_ship_fire_for_debug() -> void:
	HudShipDebugHelper.toggle_player_ship_fire_for_debug(self)


func _toggle_player_rowing_for_debug() -> void:
	HudShipDebugHelper.toggle_player_rowing_for_debug(self)


func _auto_adjust_player_sail_for_debug() -> void:
	HudShipDebugHelper.auto_adjust_player_sail_for_debug(self)


func _adjust_player_crew_capacity_for_debug(delta_amount: int) -> void:
	HudShipDebugHelper.adjust_player_crew_capacity_for_debug(self, delta_amount)


func _adjust_player_captain_count_for_debug(delta_amount: int) -> void:
	HudShipDebugHelper.adjust_player_captain_count_for_debug(self, delta_amount)


func _adjust_player_support_limit_for_debug(delta_amount: int) -> void:
	HudShipDebugHelper.adjust_player_support_limit_for_debug(self, delta_amount)


func _adjust_player_ship_float_for_debug(property_name: String, delta_value: float, min_value: float, max_value: float, label: String) -> void:
	HudShipDebugHelper.adjust_player_ship_float_for_debug(self, property_name, delta_value, min_value, max_value, label)

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
		_update_ammo_mode_display()
		_update_distance_debug_display()
		_update_ship_health_bars(false)
	if show_stat_panel:
		_stat_refresh_left -= delta
		if _stat_refresh_left <= 0.0:
			_stat_refresh_left = stat_refresh_interval
			_update_stat_panel()


func _sync_game_time(delta: float) -> void:
	if not is_instance_valid(_cached_level_manager):
		_cached_level_manager = LevelManagerRegistry.get_level_manager(get_tree())
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
	var players = EntityRegistry.get_ships_by_team("player")
	for p in players:
		if is_instance_valid(p) and p.get("is_player_controlled") == true:
			player_ship = p
			return
	if players.size() > 0 and is_instance_valid(players[0]):
		player_ship = players[0]


func _get_level_manager_for_debug() -> Node:
	if not is_instance_valid(_cached_level_manager):
		_cached_level_manager = LevelManagerRegistry.get_level_manager(get_tree())
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
	if is_instance_valid(debug_distance_value):
		debug_distance_value.text = "거리 표시: %s" % ("ON" if DistanceDebugVisualizer.runtime_enabled else "OFF")
	_sync_ship_debug_panel_from_player()


func _toggle_distance_debug() -> void:
	HudDistanceDebugHelper.toggle_distance_debug(self)


func _ensure_distance_debug_visualizer() -> void:
	HudDistanceDebugHelper.ensure_distance_debug_visualizer(self)


func _update_distance_debug_display() -> void:
	HudDistanceDebugHelper.update_distance_debug_display(self)


func _find_nearest_enemy_ship_for_distance_debug() -> Node3D:
	return HudDistanceDebugHelper.find_nearest_enemy_ship_for_distance_debug(self)


func _get_planar_distance(a: Vector3, b: Vector3) -> float:
	return HudDistanceDebugHelper.get_planar_distance(a, b)


func _get_ship_pair_melee_distance_debug(player: Node3D, other_ship: Node3D) -> float:
	return HudDistanceDebugHelper.get_ship_pair_melee_distance_debug(self, player, other_ship)


func _get_player_cannon_range_for_debug() -> float:
	return HudDistanceDebugHelper.get_player_cannon_range_for_debug(self)


func _get_cannon_efficiency_for_debug(planar_distance: float) -> float:
	return HudDistanceDebugHelper.get_cannon_efficiency_for_debug(self, planar_distance)


func _get_ship_deck_half_extents_for_debug(ship: Node3D) -> Vector2:
	return HudDistanceDebugHelper.get_ship_deck_half_extents_for_debug(ship)


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
		if slot.get_meta("hover_bound", false) != true:
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
	HudUpgradeTooltipHelper.setup_upgrade_tooltip(self)

func _bind_upgrade_slot_hover(slot: PanelContainer) -> void:
	HudUpgradeTooltipHelper.bind_upgrade_slot_hover(self, slot)

func _on_upgrade_slot_mouse_entered(slot: PanelContainer) -> void:
	HudUpgradeTooltipHelper.on_upgrade_slot_mouse_entered(self, slot)

func _on_upgrade_slot_mouse_exited(slot: PanelContainer) -> void:
	HudUpgradeTooltipHelper.on_upgrade_slot_mouse_exited(self, slot)

func _update_upgrade_tooltip_state(delta: float) -> void:
	HudUpgradeTooltipHelper.update_upgrade_tooltip_state(self, delta)

func _show_slot_tooltip(slot: PanelContainer) -> void:
	HudUpgradeTooltipHelper.show_slot_tooltip(self, slot)

func _slot_has_tooltip(slot: PanelContainer) -> bool:
	return HudUpgradeTooltipHelper.slot_has_tooltip(self, slot)

func _get_slot_tooltip_payload(slot: PanelContainer) -> Dictionary:
	return HudUpgradeTooltipHelper.get_slot_tooltip_payload(self, slot)

func _hide_upgrade_tooltip(instant: bool = false) -> void:
	HudUpgradeTooltipHelper.hide_upgrade_tooltip(self, instant)

func _update_upgrade_tooltip_position() -> void:
	HudUpgradeTooltipHelper.update_upgrade_tooltip_position(self)

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
	HudUpgradeTooltipHelper.update_upgrade_track_slot(self, upgrade_id, level, track)

func update_ship_upgrade_ui(upgrade_id: String, level: int) -> void:
	HudUpgradeTooltipHelper.update_ship_upgrade_ui(self, upgrade_id, level)

func update_crew_upgrade_ui(upgrade_id: String, level: int) -> void:
	HudUpgradeTooltipHelper.update_crew_upgrade_ui(self, upgrade_id, level)

func update_weapon_ui(weapon_id: String, level: int) -> void:
	HudUpgradeTooltipHelper.update_weapon_ui(self, weapon_id, level)

func update_support_ui(upgrade_id: String, level: int) -> void:
	HudUpgradeTooltipHelper.update_support_ui(self, upgrade_id, level)


func _update_hull_display() -> void:
	HudUpdateHelper.update_hull_display(self)

func _update_stamina_display() -> void:
	HudUpdateHelper.update_stamina_display(self)

func _update_boarding_display() -> void:
	HudUpdateHelper.update_boarding_display(self)

func _update_capture_opportunity_display() -> void:
	HudUpdateHelper.update_capture_opportunity_display(self)


func _update_ammo_mode_display() -> void:
	if not is_instance_valid(ammo_mode_label):
		return
	if not is_instance_valid(player_ship):
		_try_resolve_player_ship()
	if not is_instance_valid(player_ship):
		if ammo_mode_label.visible:
			ammo_mode_label.visible = false
		return
	var ammo_key: String = str(player_ship.get("current_cannon_ammo")) if player_ship.get("current_cannon_ammo") != null else "roundshot"
	var ammo_text: String = "탄종: 실선탄"
	match ammo_key:
		"chainshot":
			ammo_text = "탄종: 사슬탄"
		"grapeshot":
			ammo_text = "탄종: 포도탄"
	if _last_ammo_mode_text != ammo_text:
		_last_ammo_mode_text = ammo_text
		ammo_mode_label.text = ammo_text
	ammo_mode_label.visible = true


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
	return HudSailDebugHelper.get_player_masts_for_debug(self)


func _apply_sail_debug_values(damage: float, burn: float, hole_strength: float = 1.0) -> void:
	HudSailDebugHelper.apply_sail_debug_values(self, damage, burn, hole_strength)


func _sync_sail_debug_panel_from_player() -> void:
	HudSailDebugHelper.sync_sail_debug_panel_from_player(self)


func _on_sail_debug_damage_changed(value: float) -> void:
	HudSailDebugHelper.on_sail_debug_damage_changed(self, value)


func _on_sail_debug_burn_changed(value: float) -> void:
	HudSailDebugHelper.on_sail_debug_burn_changed(self, value)


func _on_sail_debug_hole_changed(value: float) -> void:
	HudSailDebugHelper.on_sail_debug_hole_changed(self, value)


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
