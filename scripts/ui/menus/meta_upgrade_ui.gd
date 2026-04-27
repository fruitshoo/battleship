extends CanvasLayer

const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")
const PLAYER_BASE_MOVE_SPEED := 6.0
const PLAYER_BASE_HULL_HP := 200.0
const SOLDIER_BASE_HEALTH := 100.0
const META_CREW_DAMAGE_BONUS_PER_LEVEL := 0.04

signal closed

@export var title_text: String = "[업그레이드] 영구 강화"
@export var close_button_text: String = "닫기"

@onready var backdrop: ColorRect = $Backdrop
@onready var panel: PanelContainer = $Backdrop/Panel
@onready var shell: VBoxContainer = $Backdrop/Panel/Shell
@onready var header: VBoxContainer = $Backdrop/Panel/Shell/Header
@onready var title_label: Label = $Backdrop/Panel/Shell/Header/Title
@onready var gold_pill: PanelContainer = $Backdrop/Panel/Shell/Header/GoldPill
@onready var gold_label: Label = $Backdrop/Panel/Shell/Header/GoldPill/GoldLabel
@onready var scroll_container: ScrollContainer = $Backdrop/Panel/Shell/ScrollContainer
@onready var upgrade_grid: GridContainer = $Backdrop/Panel/Shell/ScrollContainer/Grid
@onready var detail_panel: PanelContainer = $Backdrop/Panel/Shell/DetailPanel
@onready var detail_layout: HBoxContainer = $Backdrop/Panel/Shell/DetailPanel/DetailLayout
@onready var icon_frame: PanelContainer = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/IconFrame
@onready var selected_icon_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/IconFrame/IconLabel
@onready var detail_info: VBoxContainer = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info
@onready var selected_name_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Name
@onready var selected_level_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Level
@onready var selected_desc_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Desc
@onready var selected_effect_label: Label = $Backdrop/Panel/Shell/DetailPanel/DetailLayout/Info/Effect
@onready var footer: HBoxContainer = $Backdrop/Panel/Shell/Footer
@onready var cost_label: Label = $Backdrop/Panel/Shell/Footer/CostLabel
@onready var buy_button: Button = $Backdrop/Panel/Shell/Footer/BuyButton
@onready var close_button: Button = $Backdrop/Panel/Shell/Footer/CloseButton

var _selected_upgrade_id: String = ""
var _card_buttons: Dictionary = {}
var _ordered_upgrade_ids: Array[String] = []
var _grid_columns: int = 4
var _footer_focus_index: int = -1
var _card_size := Vector2(136, 128)
var _title_font_size: int = 22
var _detail_name_font_size: int = 20
var _detail_body_font_size: int = 13
var _gold_font_size: int = 16
var _footer_font_size: int = 15

func _ready() -> void:
	title_label.text = title_text
	close_button.text = close_button_text
	_apply_theme()
	_apply_layout_density()
	UiButtonAudio.wire_button(close_button)
	UiButtonAudio.wire_button(buy_button)
	close_button.pressed.connect(_on_close_pressed)
	buy_button.pressed.connect(_on_buy_pressed)
	buy_button.focus_entered.connect(func(): _footer_focus_index = 0)
	close_button.focus_entered.connect(func(): _footer_focus_index = 1)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return

	if _is_prev_event(event):
		if _footer_focus_index >= 0:
			_move_footer_focus(-1)
		else:
			_move_grid_horizontal(-1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_next_event(event):
		if _footer_focus_index >= 0:
			_move_footer_focus(1)
		else:
			_move_grid_horizontal(1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_up_event(event):
		if _footer_focus_index >= 0:
			_exit_footer_focus_to_grid()
		else:
			_move_grid_vertical(-1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_down_event(event):
		if _footer_focus_index >= 0:
			pass
		else:
			_move_grid_vertical(1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		if _footer_focus_index == 0:
			if is_instance_valid(buy_button) and buy_button.visible and not buy_button.disabled:
				buy_button.emit_signal("pressed")
		elif _footer_focus_index == 1:
			if is_instance_valid(close_button) and close_button.visible and not close_button.disabled:
				close_button.emit_signal("pressed")
		else:
			UiButtonAudio.play_click()
			_on_buy_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _apply_theme() -> void:
	if is_instance_valid(backdrop):
		backdrop.color = Color.WHITE
		backdrop.material = UiOverlayFx.make_vignette_material(
			Color(0.02, 0.03, 0.05, 0.84),
			Vector2(0.5, 0.48),
			0.86,
			0.36,
			0.18,
			0.18,
			Vector3(0.018, 0.024, 0.028)
		)
	ModalMenuSkin.apply_modal_shell(panel, title_label, gold_label, false)
	ModalMenuSkin.apply_modal_section_panel(gold_pill, true)
	ModalMenuSkin.apply_modal_section_panel(detail_panel, true)
	if is_instance_valid(icon_frame):
		icon_frame.add_theme_stylebox_override("panel", NavalUiTheme.make_emblem_frame_style(NavalUiTheme.TEXT_GOLD, true))
	NavalUiTheme.style_display_title(title_label, _title_font_size)
	NavalUiTheme.style_gold(gold_label, _gold_font_size)
	NavalUiTheme.style_heading(selected_name_label, _detail_name_font_size)
	NavalUiTheme.style_gold(selected_level_label, max(12, _detail_body_font_size))
	NavalUiTheme.style_body(selected_desc_label, _detail_body_font_size)
	NavalUiTheme.style_body(selected_effect_label, _detail_body_font_size)
	NavalUiTheme.style_gold(cost_label, _footer_font_size)
	ModalMenuSkin.apply_action_button_theme(buy_button, true, true)
	ModalMenuSkin.apply_action_button_theme(close_button, false, true)


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 1080.0) / 520.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 760.0) / 280.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	_grid_columns = 2 if viewport_size.x < 980.0 else (3 if viewport_size.x < 1320.0 else 4)
	_card_size = Vector2(roundf(lerpf(118.0, 136.0, density)), roundf(lerpf(114.0, 128.0, density)))
	_title_font_size = roundi(lerpf(34.0, 42.0, density))
	_detail_name_font_size = roundi(lerpf(18.0, 20.0, density))
	_detail_body_font_size = roundi(lerpf(12.0, 13.0, density))
	_gold_font_size = roundi(lerpf(14.0, 16.0, density))
	_footer_font_size = roundi(lerpf(13.0, 15.0, density))
	if is_instance_valid(panel):
		panel.custom_minimum_size.x = roundi(clampf(viewport_size.x - 120.0, 560.0, 680.0))
	if is_instance_valid(shell):
		shell.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(header):
		header.add_theme_constant_override("separation", roundi(lerpf(6.0, 8.0, density)))
	if is_instance_valid(upgrade_grid):
		upgrade_grid.columns = _grid_columns
		upgrade_grid.add_theme_constant_override("h_separation", roundi(lerpf(8.0, 10.0, density)))
		upgrade_grid.add_theme_constant_override("v_separation", roundi(lerpf(8.0, 10.0, density)))
	if is_instance_valid(detail_layout):
		detail_layout.add_theme_constant_override("separation", roundi(lerpf(10.0, 14.0, density)))
	if is_instance_valid(detail_info):
		detail_info.add_theme_constant_override("separation", roundi(lerpf(3.0, 4.0, density)))
	if is_instance_valid(icon_frame):
		icon_frame.custom_minimum_size = Vector2(roundf(lerpf(60.0, 68.0, density)), roundf(lerpf(60.0, 68.0, density)))
	if is_instance_valid(footer):
		footer.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(buy_button):
		buy_button.custom_minimum_size = Vector2(roundf(lerpf(108.0, 120.0, density)), roundf(lerpf(38.0, 42.0, density)))
	if is_instance_valid(close_button):
		close_button.custom_minimum_size = Vector2(roundf(lerpf(108.0, 120.0, density)), roundf(lerpf(38.0, 42.0, density)))
	_apply_theme()


func _on_viewport_size_changed() -> void:
	_apply_layout_density()
	update_ui()

func update_ui() -> void:
	gold_label.text = "보유 골드 %d G" % SaveManager.gold
	for child in upgrade_grid.get_children():
		child.queue_free()
	_card_buttons.clear()

	var upgrade_ids := _get_upgrade_ids()
	_ordered_upgrade_ids = upgrade_ids.duplicate()
	for id in upgrade_ids:
		var card = _create_upgrade_card(id)
		upgrade_grid.add_child(card)
		_card_buttons[id] = card

	if _selected_upgrade_id.is_empty() or not MetaManager.UPGRADES.has(_selected_upgrade_id):
		if not upgrade_ids.is_empty():
			_selected_upgrade_id = upgrade_ids[0]
	_update_detail_panel()
	_refresh_card_styles()
	UiButtonAudio.wire_buttons(upgrade_grid)
	if _footer_focus_index >= 0:
		call_deferred("_focus_footer_button", _footer_focus_index)

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
	card.custom_minimum_size = _card_size
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("normal", _make_card_style(id, false))
	card.add_theme_stylebox_override("hover", _make_card_style(id, true))
	card.add_theme_stylebox_override("pressed", _make_card_style(id, true))
	card.add_theme_stylebox_override("disabled", _make_card_style(id, false, true))
	UiButtonAudio.wire_button(card)
	card.pressed.connect(_on_card_pressed.bind(id))
	card.mouse_entered.connect(func():
		_select_upgrade(id)
	)

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
	NavalUiTheme.style_body(title, max(11, _detail_body_font_size - 1))
	layout.add_child(title)

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(roundf(_card_size.x * 0.32), roundf(_card_size.x * 0.32))
	icon_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_frame.add_theme_stylebox_override("panel", _make_icon_frame_style(id))
	layout.add_child(icon_frame)

	var icon := Label.new()
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	NavalUiTheme.apply_emblem(
		icon,
		id,
		roundi(lerpf(22.0, 26.0, clampf((float(_card_size.x) - 118.0) / 18.0, 0.0, 1.0))),
		_get_upgrade_color(id)
	)
	icon_frame.add_child(icon)

	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 3)
	layout.add_child(pips)
	for i in range(max_level):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(roundf(lerpf(12.0, 14.0, clampf((float(_card_size.x) - 118.0) / 18.0, 0.0, 1.0))), 6)
		pip.color = NavalUiTheme.TEXT_GOLD if i < level else Color(0.20, 0.16, 0.18, 0.95)
		pips.add_child(pip)

	var cost := Label.new()
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_gold(cost, max(10, _detail_body_font_size - 2))
	if level >= max_level:
		cost.text = "MAX"
		cost.add_theme_color_override("font_color", Color(0.72, 0.90, 0.52))
	else:
		cost.text = "%d G" % MetaManager.get_upgrade_cost(id)
		cost.add_theme_color_override("font_color", NavalUiTheme.TEXT_GOLD)
	layout.add_child(cost)

	return card

func _make_card_style(id: String, selected: bool, disabled: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent := _get_upgrade_color(id)
	style.bg_color = NavalUiTheme.PANEL_BG_SOFT if not selected else Color(0.20, 0.29, 0.41, 0.98)
	if disabled:
		style.bg_color = style.bg_color.darkened(0.25)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent.lerp(NavalUiTheme.BORDER_GOLD, 0.4).lightened(0.08) if selected else NavalUiTheme.BORDER_GOLD_DIM
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 2
	return style

func _make_icon_frame_style(id: String) -> StyleBoxFlat:
	return NavalUiTheme.make_emblem_frame_style(_get_upgrade_color(id), true)

func _on_card_pressed(id: String) -> void:
	_select_upgrade(id)

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

	NavalUiTheme.apply_emblem(
		selected_icon_label,
		_selected_upgrade_id,
		roundi(lerpf(30.0, 36.0, clampf((float(icon_frame.custom_minimum_size.x) - 60.0) / 8.0, 0.0, 1.0))),
		_get_upgrade_color(_selected_upgrade_id)
	)
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
		cost_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_GOLD)
		buy_button.text = "구입"
		buy_button.disabled = SaveManager.gold < cost


func _select_upgrade(id: String) -> void:
	if not MetaManager.UPGRADES.has(id):
		return
	_selected_upgrade_id = id
	_footer_focus_index = -1
	_update_detail_panel()
	_refresh_card_styles()
	_scroll_selected_card_into_view()


func _scroll_selected_card_into_view() -> void:
	var selected_card := _card_buttons.get(_selected_upgrade_id, null) as Control
	if is_instance_valid(selected_card) and is_instance_valid(scroll_container):
		scroll_container.ensure_control_visible(selected_card)


func _get_selected_index() -> int:
	return _ordered_upgrade_ids.find(_selected_upgrade_id)


func _move_grid_horizontal(direction: int) -> void:
	if _ordered_upgrade_ids.is_empty():
		return
	var selected_index := _get_selected_index()
	if selected_index == -1:
		_select_upgrade(_ordered_upgrade_ids[0])
		return
	var next_index := clampi(selected_index + direction, 0, _ordered_upgrade_ids.size() - 1)
	_select_upgrade(_ordered_upgrade_ids[next_index])


func _move_grid_vertical(direction: int) -> void:
	if _ordered_upgrade_ids.is_empty():
		return
	var selected_index := _get_selected_index()
	if selected_index == -1:
		_select_upgrade(_ordered_upgrade_ids[0])
		return
	var next_index := selected_index + direction * _grid_columns
	if next_index >= 0 and next_index < _ordered_upgrade_ids.size():
		_select_upgrade(_ordered_upgrade_ids[next_index])
		return
	if direction > 0:
		_enter_footer_focus()


func _enter_footer_focus() -> void:
	var preferred_index := 0 if not buy_button.disabled else 1
	_focus_footer_button(preferred_index)


func _focus_footer_button(index: int) -> void:
	_footer_focus_index = clampi(index, 0, 1)
	if _footer_focus_index == 0 and is_instance_valid(buy_button) and not buy_button.disabled:
		buy_button.grab_focus()
		return
	if is_instance_valid(close_button):
		_footer_focus_index = 1
		close_button.grab_focus()


func _move_footer_focus(direction: int) -> void:
	if direction < 0 and _footer_focus_index == 1 and is_instance_valid(buy_button) and not buy_button.disabled:
		_focus_footer_button(0)
	elif direction > 0 and _footer_focus_index == 0:
		_focus_footer_button(1)


func _exit_footer_focus_to_grid() -> void:
	_footer_focus_index = -1
	_scroll_selected_card_into_view()


func _is_prev_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_left") or _is_physical_key_pressed(event, KEY_A)


func _is_next_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_right") or _is_physical_key_pressed(event, KEY_D)


func _is_up_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or _is_physical_key_pressed(event, KEY_W)


func _is_down_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_down") or _is_physical_key_pressed(event, KEY_S)


func _is_confirm_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or _is_keycode_pressed(event, KEY_SPACE) or _is_keycode_pressed(event, KEY_ENTER) or _is_keycode_pressed(event, KEY_KP_ENTER)


func _is_physical_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keycode


func _is_keycode_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode

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
			return "무기 피해 +%.0f%% → +%.0f%%" % [
				level * META_CREW_DAMAGE_BONUS_PER_LEVEL * 100.0,
				next_level * META_CREW_DAMAGE_BONUS_PER_LEVEL * 100.0,
			]
		"crew_defense":
			return "병사 방어력 +%d → +%d" % [level, next_level]
	return ""

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
