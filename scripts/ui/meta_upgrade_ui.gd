extends CanvasLayer

const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const PLAYER_BASE_MOVE_SPEED := 6.0
const PLAYER_BASE_HULL_HP := 200.0
const SOLDIER_BASE_HEALTH := 70.0
const SOLDIER_BASE_ATTACK := 12.0
const SOLDIER_SWORD_MULT := 1.25
const SOLDIER_BOW_MULT := 1.0

signal closed

@export var title_text: String = "[업그레이드] 영구 강화"
@export var close_button_text: String = "닫기"

@onready var title_label: Label = $Backdrop/Panel/Shell/Header/Title
@onready var gold_label: Label = $Backdrop/Panel/Shell/Header/GoldPill/GoldLabel
@onready var upgrade_grid: GridContainer = $Backdrop/Panel/Shell/ScrollContainer/Grid
@onready var selected_icon_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/IconFrame/IconLabel
@onready var selected_name_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Name
@onready var selected_level_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Level
@onready var selected_desc_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Desc
@onready var selected_effect_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Effect
@onready var cost_label: Label = $Backdrop/Panel/Shell/Footer/CostLabel
@onready var buy_button: Button = $Backdrop/Panel/Shell/Footer/BuyButton
@onready var close_button: Button = $Backdrop/Panel/Shell/Footer/CloseButton

var _selected_upgrade_id: String = ""
var _card_buttons: Dictionary = {}

func _ready() -> void:
	title_label.text = title_text
	close_button.text = close_button_text
	close_button.pressed.connect(_on_close_pressed)
	buy_button.pressed.connect(_on_buy_pressed)
	update_ui()

func update_ui() -> void:
	gold_label.text = "보유 골드 %d G" % SaveManager.gold
	for child in upgrade_grid.get_children():
		child.queue_free()
	_card_buttons.clear()

	var upgrade_ids := _get_upgrade_ids()
	for id in upgrade_ids:
		var card = _create_upgrade_card(id)
		upgrade_grid.add_child(card)
		_card_buttons[id] = card

	if _selected_upgrade_id.is_empty() or not MetaManager.UPGRADES.has(_selected_upgrade_id):
		if not upgrade_ids.is_empty():
			_selected_upgrade_id = upgrade_ids[0]
	_update_detail_panel()
	_refresh_card_styles()

func _get_upgrade_ids() -> Array[String]:
	var upgrade_ids: Array[String] = []
	if MetaManager.has_method("get_upgrade_ids"):
		upgrade_ids = MetaManager.get_upgrade_ids()
	else:
		for key in MetaManager.UPGRADES.keys():
			upgrade_ids.append(str(key))
	return upgrade_ids

func _create_upgrade_card(id: String) -> Button:
	var data: Dictionary = MetaManager.UPGRADES[id]
	var level := SaveManager.get_upgrade_level(id)
	var max_level := int(data.get("max_level", 1))

	var card := Button.new()
	card.text = ""
	card.clip_contents = true
	card.custom_minimum_size = Vector2(136, 128)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", _make_card_style(id, false))
	card.add_theme_stylebox_override("hover", _make_card_style(id, true))
	card.add_theme_stylebox_override("pressed", _make_card_style(id, true))
	card.add_theme_stylebox_override("disabled", _make_card_style(id, false, true))
	card.pressed.connect(_on_card_pressed.bind(id))

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 10
	layout.offset_top = 8
	layout.offset_right = -10
	layout.offset_bottom = -8
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 4)
	card.add_child(layout)

	var title := Label.new()
	title.text = str(data.get("name", id))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	layout.add_child(title)

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(44, 44)
	icon_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_frame.add_theme_stylebox_override("panel", _make_icon_frame_style(id))
	layout.add_child(icon_frame)

	var icon := Label.new()
	icon.text = _get_upgrade_icon(id)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
	icon.add_theme_font_size_override("font_size", 26)
	icon.add_theme_color_override("font_color", _get_upgrade_color(id))
	icon_frame.add_child(icon)

	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 3)
	layout.add_child(pips)
	for i in range(max_level):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 6)
		pip.color = Color(0.56, 0.18, 0.35, 0.95) if i < level else Color(0.20, 0.16, 0.18, 0.95)
		pips.add_child(pip)

	var cost := Label.new()
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 11)
	if level >= max_level:
		cost.text = "MAX"
		cost.add_theme_color_override("font_color", Color(0.72, 0.90, 0.52))
	else:
		cost.text = "%d G" % MetaManager.get_upgrade_cost(id)
		cost.add_theme_color_override("font_color", Color(0.98, 0.83, 0.38))
	layout.add_child(cost)

	return card

func _make_card_style(id: String, selected: bool, disabled: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent := _get_upgrade_color(id)
	style.bg_color = Color(0.29, 0.31, 0.36, 0.96) if not selected else Color(0.24, 0.36, 0.64, 0.98)
	if disabled:
		style.bg_color = style.bg_color.darkened(0.25)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent.lightened(0.15) if selected else Color(0.78, 0.62, 0.30, 0.92)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 2
	return style

func _make_icon_frame_style(id: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = _get_upgrade_color(id).lightened(0.1)
	style.set_corner_radius_all(6)
	return style

func _on_card_pressed(id: String) -> void:
	_selected_upgrade_id = id
	_update_detail_panel()
	_refresh_card_styles()

func _refresh_card_styles() -> void:
	for key in _card_buttons.keys():
		var id := str(key)
		var card := _card_buttons[id] as Button
		if not is_instance_valid(card):
			continue
		var selected: bool = (id == _selected_upgrade_id)
		card.add_theme_stylebox_override("normal", _make_card_style(id, selected))
		card.add_theme_stylebox_override("hover", _make_card_style(id, true))
		card.add_theme_stylebox_override("pressed", _make_card_style(id, true))

func _update_detail_panel() -> void:
	if _selected_upgrade_id.is_empty():
		return
	var data: Dictionary = MetaManager.UPGRADES.get(_selected_upgrade_id, {})
	var level := SaveManager.get_upgrade_level(_selected_upgrade_id)
	var max_level := int(data.get("max_level", 1))
	var cost := MetaManager.get_upgrade_cost(_selected_upgrade_id)
	var is_max := level >= max_level

	selected_icon_label.text = _get_upgrade_icon(_selected_upgrade_id)
	selected_icon_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
	selected_icon_label.add_theme_font_size_override("font_size", 36)
	selected_icon_label.add_theme_color_override("font_color", _get_upgrade_color(_selected_upgrade_id))
	selected_name_label.text = str(data.get("name", _selected_upgrade_id))
	selected_level_label.text = "Lv.%d / %d" % [level, max_level]
	selected_desc_label.text = str(data.get("description", ""))
	selected_effect_label.text = _build_effect_text(_selected_upgrade_id, level)

	if is_max:
		cost_label.text = "최대 레벨 도달"
		cost_label.add_theme_color_override("font_color", Color(0.72, 0.90, 0.52))
		buy_button.text = "MAX"
		buy_button.disabled = true
	else:
		cost_label.text = "비용 %d G" % cost
		cost_label.add_theme_color_override("font_color", Color(0.98, 0.83, 0.38))
		buy_button.text = "구입"
		buy_button.disabled = SaveManager.gold < cost

func _build_effect_text(id: String, level: int) -> String:
	var next_level := level + 1
	match id:
		"hull_hp":
			return "선체 %.0f → %.0f" % [
				PLAYER_BASE_HULL_HP + level * 40.0,
				PLAYER_BASE_HULL_HP + next_level * 40.0,
			]
		"hull_defense":
			return "방어력 %.0f → %.0f" % [level * 2.0, next_level * 2.0]
		"sail_speed":
			return "최대 속도 %.1f → %.1f" % [
				PLAYER_BASE_MOVE_SPEED * (1.0 + level * 0.1),
				PLAYER_BASE_MOVE_SPEED * (1.0 + next_level * 0.1),
			]
		"xp_gain":
			return "획득 XP 100 → %.0f | 다음 100 → %.0f" % [
				100.0 * (1.0 + level * 0.1),
				100.0 * (1.0 + next_level * 0.1),
			]
		"pickup_range":
			return "현재 +%.1fm | 다음 +%.1fm" % [level * 1.5, next_level * 1.5]
		"reroll_stock":
			return "현재 +%d회 | 다음 +%d회" % [level, next_level]
		"crew_capacity":
			return "현재 +%d명 | 다음 +%d명" % [level, next_level]
		"crew_health":
			return "병사 체력 %.0f → %.0f" % [
				SOLDIER_BASE_HEALTH * (1.0 + level * 0.12),
				SOLDIER_BASE_HEALTH * (1.0 + next_level * 0.12),
			]
		"crew_attack":
			return "검 %.1f → %.1f | 활 %.1f → %.1f" % [
				(SOLDIER_BASE_ATTACK + level * 2.0) * SOLDIER_SWORD_MULT,
				(SOLDIER_BASE_ATTACK + next_level * 2.0) * SOLDIER_SWORD_MULT,
				(SOLDIER_BASE_ATTACK + level * 2.0) * SOLDIER_BOW_MULT,
				(SOLDIER_BASE_ATTACK + next_level * 2.0) * SOLDIER_BOW_MULT,
			]
		"crew_defense":
			return "병사 방어력 +%d → +%d" % [level, next_level]
	return ""

func _get_upgrade_icon(id: String) -> String:
	var icon_map := {
		"hull_hp": "health_and_safety",
		"hull_defense": "shield",
		"sail_speed": "speed",
		"xp_gain": "trending_up",
		"pickup_range": "radar",
		"reroll_stock": "refresh",
		"crew_capacity": "groups",
		"crew_health": "favorite",
		"crew_attack": "swords",
		"crew_defense": "shield_person",
	}
	return icon_map.get(id, "build")

func _get_upgrade_color(id: String) -> Color:
	var color_map := {
		"hull_hp": Color(0.96, 0.34, 0.28),
		"hull_defense": Color(0.83, 0.83, 0.88),
		"sail_speed": Color(0.55, 0.92, 1.0),
		"xp_gain": Color(0.78, 0.92, 0.35),
		"pickup_range": Color(0.40, 0.70, 1.0),
		"reroll_stock": Color(1.0, 0.80, 0.30),
		"crew_capacity": Color(0.55, 0.84, 1.0),
		"crew_health": Color(0.44, 0.92, 0.48),
		"crew_attack": Color(1.0, 0.56, 0.28),
		"crew_defense": Color(0.76, 0.88, 1.0),
	}
	return color_map.get(id, Color.WHITE)

func _on_buy_pressed() -> void:
	if _selected_upgrade_id.is_empty():
		return
	if MetaManager.buy_upgrade(_selected_upgrade_id):
		update_ui()

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
