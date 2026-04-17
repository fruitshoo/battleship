extends CanvasLayer
const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const HudGameOverOverlay = preload("res://scripts/ui/hud/hud_game_over_overlay.gd")
const HudLayoutBuilder = preload("res://scripts/ui/hud/hud_layout_builder.gd")
const HudLookupHelper = preload("res://scripts/ui/hud/hud_lookup_helper.gd")
const HudUpdateHelper = preload("res://scripts/ui/hud/hud_update_helper.gd")
const HudUpgradeInfoHelper = preload("res://scripts/ui/hud/hud_upgrade_info_helper.gd")
const HudUpgradeTooltipHelper = preload("res://scripts/ui/hud/hud_upgrade_tooltip_helper.gd")
const HudStatPanelHelper = preload("res://scripts/ui/hud/hud_stat_panel_helper.gd")
const HudDebugPanelHelper = preload("res://scripts/ui/hud/hud_debug_panel_helper.gd")
const HudDistanceDebugHelper = preload("res://scripts/ui/hud/hud_distance_debug_helper.gd")
const HudSailDebugHelper = preload("res://scripts/ui/hud/hud_sail_debug_helper.gd")
const HudShipDebugHelper = preload("res://scripts/ui/hud/hud_ship_debug_helper.gd")
const HudEndStateHelper = preload("res://scripts/ui/hud/hud_end_state_helper.gd")
const HudStatusDisplayHelper = preload("res://scripts/ui/hud/hud_status_display_helper.gd")
const HudItemDisplayHelper = preload("res://scripts/ui/hud/hud_item_display_helper.gd")
const HudProgressionLayoutHelper = preload("res://scripts/ui/hud/hud_progression_layout_helper.gd")
const HudRuntimeHelper = preload("res://scripts/ui/hud/hud_runtime_helper.gd")
const HudShipHealthOverlayHelper = preload("res://scripts/ui/hud/hud_ship_health_overlay_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
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
var debug_authoring_palette_preview_value: Label = null
var debug_authoring_palette_selected_value: Label = null
var debug_authoring_palette_assembly_value: Label = null
var debug_authoring_palette_execute_button: Button = null
var debug_authoring_palette_queue_value: Label = null
var debug_authoring_palette_preset_value: Label = null
var debug_authoring_palette_preset_preview_value: Label = null
var debug_authoring_palette_preset_select: OptionButton = null
var debug_authoring_palette_queue_add_button: Button = null
var debug_authoring_palette_queue_execute_button: Button = null
var debug_authoring_palette_queue_duplicate_button: Button = null
var debug_authoring_palette_queue_delete_button: Button = null
var debug_authoring_palette_queue_prev_button: Button = null
var debug_authoring_palette_queue_next_button: Button = null
var debug_authoring_palette_queue_move_up_button: Button = null
var debug_authoring_palette_queue_move_down_button: Button = null
var debug_authoring_palette_selected_callback: Callable = Callable()
var debug_authoring_palette_selected_action: Dictionary = {}
var debug_authoring_palette_assembly_meta: Dictionary = {}
var debug_authoring_palette_queue_entries: Array[Dictionary] = []
var debug_authoring_palette_queue_selected_index: int = -1
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
	"cannon", "cannon_damage", "cannon_reload", "janggun",
	"hull_defense", "sailing", "rowing", "supply_bonus", "fleet_signal",
	"supply", "gold"
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
	HudProgressionLayoutHelper.apply_overlay_theme(self)

func _ensure_hud_label(existing: Label, node_name: String, default_text: String) -> Label:
	return HudProgressionLayoutHelper.ensure_hud_label(self, existing, node_name, default_text)


func _setup_top_xp_bar() -> void:
	HudProgressionLayoutHelper.setup_top_xp_bar(self)

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
	HudRuntimeHelper.process_hud(self, delta)


func _sync_game_time(delta: float) -> void:
	HudRuntimeHelper.sync_game_time(self, delta)

func _attach_level_label_to_xp_bar() -> void:
	HudProgressionLayoutHelper.attach_level_label_to_xp_bar(self)

func _try_resolve_player_ship() -> void:
	HudLookupHelper.try_resolve_player_ship(self)


func _get_level_manager_for_debug() -> Node:
	return HudDebugPanelHelper.get_level_manager_for_debug(self)


func _get_environment_preset_manager_for_debug() -> Node:
	return HudDebugPanelHelper.get_environment_preset_manager_for_debug(self)


func _invoke_level_debug_method(method_name: String, args: Array = []) -> void:
	HudDebugPanelHelper.invoke_level_debug_method(self, method_name, args)


func _apply_environment_preset(preset_index: int) -> void:
	HudDebugPanelHelper.apply_environment_preset(self, preset_index)


func _sync_debug_tools_panel_state() -> void:
	HudDebugPanelHelper.sync_debug_tools_panel_state(self)


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
	HudStatusDisplayHelper.update_hull_hp(self, current, maximum)

func update_stamina(current: float, maximum: float) -> void:
	HudStatusDisplayHelper.update_stamina(self, current, maximum)

func update_xp(current: int, maximum: int) -> void:
	HudStatusDisplayHelper.update_xp(self, current, maximum)

func update_merit(current: int, maximum: int, level: int = 1) -> void:
	HudStatusDisplayHelper.update_merit(self, current, maximum, level)

func add_item_icon(icon_data) -> void:
	HudItemDisplayHelper.add_item_icon(self, icon_data)

func clear_item_icons() -> void:
	HudItemDisplayHelper.clear_item_icons(self)

func _refresh_owned_item_icons() -> void:
	HudItemDisplayHelper.refresh_owned_item_icons(self)


func _setup_ship_hp_overlay() -> void:
	HudShipHealthOverlayHelper.setup_ship_hp_overlay(self)

func _update_ship_health_bars(positions_only: bool = false) -> void:
	HudShipHealthOverlayHelper.update_ship_health_bars(self, positions_only)

func toggle_ship_health_bars() -> void:
	HudShipHealthOverlayHelper.toggle_ship_health_bars(self)

func _update_stat_panel() -> void:
	HudStatPanelHelper.update_stat_panel(self)


func toggle_stat_panel() -> void:
	HudStatPanelHelper.toggle_stat_panel(self)

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
	HudStatusDisplayHelper.update_ammo_mode_display(self)


func show_game_over() -> void:
	HudEndStateHelper.show_game_over(self)


func update_boss_hp(current: float, maximum: float) -> void:
	HudUpdateHelper.update_boss_hp(self, current, maximum)


func show_gust_warning_message(message: String, duration: float = 0.35) -> void:
	HudStatusDisplayHelper.show_gust_warning_message(self, message, duration)


func show_message(message: String, duration: float = 1.5) -> void:
	show_gust_warning_message(message, duration)


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
	HudEndStateHelper.show_victory(self)

func show_victory_with_damage(rows: Array, total_damage: float) -> void:
	HudEndStateHelper.show_victory_with_damage(self, rows, total_damage)

func _setup_game_over_overlay() -> void:
	HudEndStateHelper.setup_game_over_overlay(self)

func _return_to_main_menu() -> void:
	HudEndStateHelper.return_to_main_menu(self)
