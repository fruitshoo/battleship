extends CanvasLayer
const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const HudGameOverOverlay = preload("res://scripts/ui/hud_game_over_overlay.gd")
const HudUpgradeTooltip = preload("res://scripts/ui/hud_upgrade_tooltip.gd")
const HudLayoutBuilder = preload("res://scripts/ui/hud_layout_builder.gd")
const HudUpdateHelper = preload("res://scripts/ui/hud_update_helper.gd")
const HudUpgradeInfoHelper = preload("res://scripts/ui/hud_upgrade_info_helper.gd")
const HudStatPanelHelper = preload("res://scripts/ui/hud_stat_panel_helper.gd")
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

## 게임 HUD
## 현재 HUD는 런타임에 레이아웃을 조립하며, 이 스크립트는 상태 보관과 갱신 허브 역할을 맡는다.

# Core HUD labels
var level_label: Label = null
var score_label: Label = null
var timer_label: Label = null
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

# Boarding UI
var boarding_ui: VBoxContainer = null
var boarding_bar: ProgressBar = null
var boarding_label: Label = null

# Merit UI
var merit_bar: ProgressBar = null
var merit_label: Label = null

# Cached text/state
var _last_timer_str: String = ""
var _last_speed_str: String = ""
var _last_speed_ratio: float = -1.0
var _last_speed_mode: String = ""
var _speed_visual_value: float = 0.0
var _last_difficulty_text: String = ""
var _last_combat_stats_text: String = ""
var _relic_refresh_retry_left: float = 0.0

# Relic and stat UI
var relic_bar = null
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
	"cannon", "janggun", "ballista",
	"hull_defense", "sailing", "rowing", "supply_bonus", "fleet_signal",
	"fleet_cannon", "fleet_hull", "supply", "gold"
]
const CREW_UPGRADE_IDS := [
	"crew_numbers", "crew_attack", "crew_defense", "singigeon", "fire_pot", "repeating_crossbow",
	"fleet_crew"
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_top_xp_bar()
	_setup_new_layout()
	_setup_game_over_overlay()
	_setup_ship_hp_overlay()

	update_level(1)
	update_score(0)
	update_crew_status(4)
	if gust_warning:
		gust_warning.visible = false
	call_deferred("_refresh_owned_relic_icons")

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

	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0, 0, 0, 0.3)
	xp_bar.add_theme_stylebox_override("background", sb_bg)

	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.2, 0.7, 1.0, 0.9)
	sb_fg.set_border_width_all(0)
	xp_bar.add_theme_stylebox_override("fill", sb_fg)

	merit_bar = ProgressBar.new()
	merit_bar.name = "TopMeritBar"
	add_child(merit_bar)

	merit_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	merit_bar.offset_top = 22.0
	merit_bar.custom_minimum_size.y = 12.0
	merit_bar.show_percentage = false
	merit_bar.z_index = 10

	var mb_bg = StyleBoxFlat.new()
	mb_bg.bg_color = Color(0, 0, 0, 0.3)
	merit_bar.add_theme_stylebox_override("background", mb_bg)

	var mb_fg = StyleBoxFlat.new()
	mb_fg.bg_color = Color(1.0, 0.8, 0.2, 0.9)
	mb_fg.set_border_width_all(0)
	merit_bar.add_theme_stylebox_override("fill", mb_fg)

	merit_label = Label.new()
	merit_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	merit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	merit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	merit_label.add_theme_font_size_override("font_size", 10)
	merit_label.add_theme_color_override("font_outline_color", Color.BLACK)
	merit_label.add_theme_constant_override("outline_size", 3)
	merit_label.text = "지휘 포인트 (병영 강화 대기)"
	merit_bar.add_child(merit_label)

func _setup_new_layout() -> void:
	HudLayoutBuilder.setup_new_layout(self)

func _process(delta: float) -> void:
	_sync_game_time(delta)
	_player_lookup_cooldown = maxf(0.0, _player_lookup_cooldown - delta)
	if not is_instance_valid(player_ship):
		_try_resolve_player_ship()
	_update_upgrade_tooltip_state(delta)
	_update_upgrade_tooltip_position()
	_relic_refresh_retry_left = maxf(0.0, _relic_refresh_retry_left - delta)
	if _relic_refresh_retry_left <= 0.0 and relic_bar and is_instance_valid(UpgradeManager):
		var owned_relics = UpgradeManager.acquired_relics if "acquired_relics" in UpgradeManager else []
		if owned_relics is Array and relic_bar.current_relic_count < owned_relics.size():
			_relic_refresh_retry_left = 0.5
			_refresh_owned_relic_icons()
	if show_ship_health_bars:
		_update_ship_health_bars(true)
	_hud_refresh_left -= delta
	if _hud_refresh_left <= 0.0:
		_hud_refresh_left = hud_refresh_interval
		_update_timer()
		_update_speed_display()
		_update_crew_count()
		_update_hull_display()
		_update_stamina_display()
		_update_boarding_display()
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
	level_label.add_theme_color_override("font_outline_color", Color.BLACK)
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


func update_level(val: int) -> void:
	HudUpdateHelper.update_level(self, val)

func update_score(val: int) -> void:
	HudUpdateHelper.update_score(self, val)

func update_combat_stats(ship_sunk: int, soldiers_killed: int) -> void:
	HudUpdateHelper.update_combat_stats(self, ship_sunk, soldiers_killed)

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
				fill_style.bg_color = Color(0.2, 0.8, 0.3, 0.9)
			elif ratio > 0.3:
				fill_style.bg_color = Color(0.9, 0.7, 0.1, 0.9)
			else:
				fill_style.bg_color = Color(0.9, 0.2, 0.2, 0.9)

func update_stamina(current: float, maximum: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = maximum
		stamina_bar.value = current

		var fill_style = stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if current < 1.0:
				fill_style.bg_color = Color(0.6, 0.1, 0.1, 0.9)
			else:
				fill_style.bg_color = Color(1.0, 0.8, 0.2, 0.9)

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
				merit_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))

				var style = merit_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if style:
					style.bg_color = Color(1.0, 1.0, 0.5, 1.0)
			else:
				merit_label.text = "지휘 Lv.%d (%d / %d)" % [level, current, maximum]
				merit_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

				var style_normal = merit_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if style_normal:
					style_normal.bg_color = Color(1.0, 0.8, 0.2, 0.9)

func add_relic_icon(icon_data) -> void:
	if relic_bar == null:
		return
	var slot: PanelContainer = relic_bar.add_icon(icon_data)
	if is_instance_valid(slot):
		var relic_name: String = ""
		var relic_description: String = ""
		if icon_data is Dictionary:
			relic_name = str(icon_data.get("name", "렐릭"))
			relic_description = str(icon_data.get("description", ""))
		var tooltip_text: String = "[%s]\n%s" % [relic_name, relic_description]
		slot.set_meta("tooltip_text", tooltip_text.strip_edges())
		slot.set_meta("tooltip_color", Color(0.92, 0.78, 0.28, 1.0))
		if not bool(slot.get_meta("hover_bound", false)):
			_bind_upgrade_slot_hover(slot)
			slot.set_meta("hover_bound", true)

func clear_relic_icons() -> void:
	if relic_bar == null:
		return
	if relic_bar.has_method("clear_icons"):
		relic_bar.clear_icons()

func _refresh_owned_relic_icons() -> void:
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("refresh_hud_relic_icons"):
		UpgradeManager.refresh_hud_relic_icons()


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
