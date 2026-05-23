extends CanvasLayer

const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const MenuInputHelper = preload("res://scripts/ui/menu_input_helper.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")
const PLAYER_BASE_MOVE_SPEED := 6.0
const PLAYER_BASE_HULL_HP := 200.0
const SOLDIER_BASE_HEALTH := 100.0
const CATEGORY_ORDER := ["ship", "crew", "utility"]
const CATEGORY_LABELS := {
	"ship": "선체",
	"crew": "병사",
	"utility": "성장",
}
const CATEGORY_HINTS := {
	"ship": "기함 생존과 항해",
	"crew": "승선 병력 강화",
	"utility": "성장과 선택지",
}
const FALLBACK_CATEGORY_BY_ID := {
	"hull_hp": "ship",
	"hull_defense": "ship",
	"sail_speed": "ship",
	"crew_capacity": "crew",
	"crew_health": "crew",
	"crew_attack": "crew",
	"crew_defense": "crew",
	"xp_gain": "utility",
	"pickup_range": "utility",
	"reroll_stock": "utility",
}

signal closed

@export var title_text: String = "업그레이드"
@export var close_button_text: String = "닫기"

@onready var backdrop: ColorRect = $Backdrop
@onready var panel: PanelContainer = $Backdrop/Panel
@onready var shell: VBoxContainer = $Backdrop/Panel/Shell
@onready var header: VBoxContainer = $Backdrop/Panel/Shell/Header
@onready var header_row: HBoxContainer = $Backdrop/Panel/Shell/Header/HeaderRow
@onready var title_label: Label = $Backdrop/Panel/Shell/Header/HeaderRow/Title
@onready var gold_pill: PanelContainer = $Backdrop/Panel/Shell/Header/HeaderRow/GoldPill
@onready var gold_label: Label = $Backdrop/Panel/Shell/Header/HeaderRow/GoldPill/GoldLabel
@onready var content: HBoxContainer = $Backdrop/Panel/Shell/Content
@onready var category_list: VBoxContainer = $Backdrop/Panel/Shell/Content/CategoryList
@onready var scroll_container: ScrollContainer = $Backdrop/Panel/Shell/Content/UpgradeScroll
@onready var upgrade_list: VBoxContainer = $Backdrop/Panel/Shell/Content/UpgradeScroll/UpgradeList
@onready var detail_panel: PanelContainer = $Backdrop/Panel/Shell/Content/DetailPanel
@onready var detail_layout: VBoxContainer = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout
@onready var detail_top: HBoxContainer = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/DetailTop
@onready var icon_frame: PanelContainer = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/DetailTop/IconFrame
@onready var selected_icon_texture: TextureRect = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/DetailTop/IconFrame/IconTexture
@onready var selected_icon_label: Label = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/DetailTop/IconFrame/IconLabel
@onready var detail_info: VBoxContainer = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/DetailTop/Info
@onready var selected_name_label: Label = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/DetailTop/Info/Name
@onready var selected_level_label: Label = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/DetailTop/Info/Level
@onready var selected_desc_label: Label = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/Desc
@onready var selected_effect_label: Label = $Backdrop/Panel/Shell/Content/DetailPanel/DetailLayout/Effect
@onready var footer: HBoxContainer = $Backdrop/Panel/Shell/Footer
@onready var cost_label: Label = $Backdrop/Panel/Shell/Footer/CostLabel
@onready var buy_button: Button = $Backdrop/Panel/Shell/Footer/BuyButton
@onready var close_button: Button = $Backdrop/Panel/Shell/Footer/CloseButton

var _selected_upgrade_id: String = ""
var _active_category: String = "ship"
var _category_buttons: Dictionary = {}
var _upgrade_buttons: Dictionary = {}
var _ordered_upgrade_ids: Array[String] = []
var _footer_focus_index: int = -1
var _category_focus_active: bool = false
var _title_font_size: int = 34
var _row_title_font_size: int = 13
var _row_body_font_size: int = 11
var _detail_name_font_size: int = 20
var _detail_body_font_size: int = 13
var _gold_font_size: int = 16
var _footer_font_size: int = 15
var _row_height: int = 62
var _category_width: int = 132
var _detail_width: int = 276
var _art_texture_cache: Dictionary = {}
var _nav_repeater := MenuInputHelper.NavRepeater.new()

func _ready() -> void:
	_apply_static_text()
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
	if not LocaleManager.locale_changed.is_connected(_on_locale_changed):
		LocaleManager.locale_changed.connect(_on_locale_changed)
	update_ui()


func _apply_static_text() -> void:
	if is_instance_valid(title_label):
		title_label.text = LocaleManager.t("meta.default_title", "업그레이드") if title_text == "업그레이드" else title_text
	if is_instance_valid(close_button):
		close_button.text = LocaleManager.t("meta.default_close", "닫기") if close_button_text == "닫기" else close_button_text


func _on_locale_changed(_locale: String) -> void:
	_apply_static_text()
	update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if MenuInputHelper.is_cancel_event(event):
		_on_close_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return

	var nav := _nav_repeater.consume_event(event)
	if nav != Vector2i.ZERO:
		_handle_nav(nav)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return
	if MenuInputHelper.is_navigation_axis_event(event):
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return

	if _is_prev_event(event):
		_handle_nav(Vector2i(-1, 0))
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_next_event(event):
		_handle_nav(Vector2i(1, 0))
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_up_event(event):
		_handle_nav(Vector2i(0, -1))
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_down_event(event):
		_handle_nav(Vector2i(0, 1))
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		if _footer_focus_index == 0:
			if is_instance_valid(buy_button) and buy_button.visible and not buy_button.disabled:
				buy_button.emit_signal("pressed")
		elif _footer_focus_index == 1:
			if is_instance_valid(close_button) and close_button.visible and not close_button.disabled:
				close_button.emit_signal("pressed")
		elif _category_focus_active:
			_exit_category_focus_to_list()
		else:
			UiButtonAudio.play_click()
			_on_buy_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func _handle_nav(nav: Vector2i) -> void:
	if nav.x < 0:
		if _footer_focus_index >= 0:
			_move_footer_focus(-1)
		elif not _category_focus_active:
			_enter_category_focus()
	elif nav.x > 0:
		if _footer_focus_index >= 0:
			_move_footer_focus(1)
		elif _category_focus_active:
			_exit_category_focus_to_list()
	elif nav.y < 0:
		if _footer_focus_index >= 0:
			_exit_footer_focus_to_list()
		elif _category_focus_active:
			_move_category_focus(-1)
		else:
			_move_selection_vertical(-1)
	elif nav.y > 0:
		if _category_focus_active:
			_move_category_focus(1)
		elif _footer_focus_index < 0:
			_move_selection_vertical(1)


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
	ModalMenuSkin.apply_modal_shell(panel, title_label, gold_label, true)
	ModalMenuSkin.apply_modal_section_panel(gold_pill, true)
	ModalMenuSkin.apply_modal_section_panel(detail_panel, true)
	if is_instance_valid(icon_frame):
		icon_frame.clip_contents = true
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
	_refresh_dynamic_styles()


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 980.0) / 520.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 620.0) / 260.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)

	_category_width = roundi(lerpf(112.0, 132.0, density))
	_detail_width = roundi(lerpf(260.0, 304.0, density))
	_row_height = roundi(lerpf(64.0, 76.0, density))
	_title_font_size = roundi(lerpf(28.0, 34.0, density))
	_row_title_font_size = roundi(lerpf(12.0, 14.0, density))
	_row_body_font_size = roundi(lerpf(10.0, 11.0, density))
	_detail_name_font_size = roundi(lerpf(18.0, 21.0, density))
	_detail_body_font_size = roundi(lerpf(12.0, 13.0, density))
	_gold_font_size = roundi(lerpf(13.0, 15.0, density))
	_footer_font_size = roundi(lerpf(13.0, 15.0, density))

	if is_instance_valid(panel):
		panel.custom_minimum_size.x = roundi(clampf(viewport_size.x - 120.0, 700.0, 1040.0))
		panel.custom_minimum_size.y = roundi(clampf(viewport_size.y - 120.0, 500.0, 680.0))
	if is_instance_valid(shell):
		shell.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(header):
		header.add_theme_constant_override("separation", 0)
	if is_instance_valid(header_row):
		header_row.add_theme_constant_override("separation", roundi(lerpf(12.0, 16.0, density)))
	if is_instance_valid(content):
		content.add_theme_constant_override("separation", roundi(lerpf(10.0, 14.0, density)))
	if is_instance_valid(category_list):
		category_list.custom_minimum_size.x = _category_width
		category_list.add_theme_constant_override("separation", roundi(lerpf(6.0, 8.0, density)))
	if is_instance_valid(upgrade_list):
		upgrade_list.add_theme_constant_override("separation", roundi(lerpf(6.0, 8.0, density)))
	if is_instance_valid(detail_panel):
		detail_panel.custom_minimum_size.x = _detail_width
	if is_instance_valid(detail_layout):
		detail_layout.add_theme_constant_override("separation", roundi(lerpf(10.0, 13.0, density)))
	if is_instance_valid(detail_top):
		detail_top.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(detail_info):
		detail_info.add_theme_constant_override("separation", 3)
	if is_instance_valid(icon_frame):
		var icon_size := roundf(lerpf(76.0, 90.0, density))
		icon_frame.custom_minimum_size = Vector2(icon_size, icon_size)
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
	gold_label.text = LocaleManager.t("meta.gold", "보유 포인트 {gold} P", {"gold": SaveManager.gold})
	_ensure_valid_category()
	_clear_children(category_list)
	_clear_children(upgrade_list)
	_category_buttons.clear()
	_upgrade_buttons.clear()

	for category in CATEGORY_ORDER:
		var ids := _get_upgrade_ids_for_category(category)
		if ids.is_empty():
			continue
		var category_button := _create_category_button(category)
		category_list.add_child(category_button)
		_category_buttons[category] = category_button

	_ordered_upgrade_ids = _get_upgrade_ids_for_category(_active_category)
	if _selected_upgrade_id.is_empty() or not _ordered_upgrade_ids.has(_selected_upgrade_id):
		_selected_upgrade_id = _ordered_upgrade_ids[0] if not _ordered_upgrade_ids.is_empty() else ""

	for id in _ordered_upgrade_ids:
		var row := _create_upgrade_row(id)
		upgrade_list.add_child(row)
		_upgrade_buttons[id] = row

	_update_detail_panel()
	_refresh_dynamic_styles()
	UiButtonAudio.wire_buttons(category_list)
	UiButtonAudio.wire_buttons(upgrade_list)
	if _footer_focus_index >= 0:
		call_deferred("_focus_footer_button", _footer_focus_index)
	elif not _category_focus_active:
		call_deferred("_scroll_selected_row_into_view")


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _ensure_valid_category() -> void:
	if not _get_upgrade_ids_for_category(_active_category).is_empty():
		return
	for category in CATEGORY_ORDER:
		if not _get_upgrade_ids_for_category(category).is_empty():
			_active_category = category
			return


func _get_upgrade_ids() -> Array[String]:
	var upgrade_ids: Array[String] = []
	if MetaManager.has_method("get_upgrade_ids"):
		upgrade_ids = MetaManager.get_upgrade_ids()
	else:
		for key in MetaManager.UPGRADES.keys():
			upgrade_ids.append(str(key))
	return upgrade_ids


func _get_upgrade_ids_for_category(category: String) -> Array[String]:
	var result: Array[String] = []
	for id in _get_upgrade_ids():
		if _get_upgrade_category(id) == category:
			result.append(id)
	return result


func _get_upgrade_category(id: String) -> String:
	var data: Dictionary = MetaManager.UPGRADES.get(id, {})
	return str(data.get("category", FALLBACK_CATEGORY_BY_ID.get(id, "utility")))


func _get_category_label(category: String) -> String:
	return LocaleManager.t("meta.category.%s" % category, str(CATEGORY_LABELS.get(category, category)))


func _get_category_hint(category: String) -> String:
	return LocaleManager.t("meta.category.%s.hint" % category, str(CATEGORY_HINTS.get(category, "")))


func _get_upgrade_name(id: String, data: Dictionary) -> String:
	return LocaleManager.data_text(data, id, "meta_upgrade", "name", id)


func _get_upgrade_description(id: String, data: Dictionary) -> String:
	return LocaleManager.data_text(data, id, "meta_upgrade", "description", "")


func _get_upgrade_level(id: String) -> int:
	if MetaManager.has_method("get_upgrade_level"):
		return int(MetaManager.get_upgrade_level(id))
	return int(SaveManager.get_upgrade_level(id))


func _create_category_button(category: String) -> Button:
	var progress := _get_category_progress(category)
	var button := Button.new()
	button.text = "%s  %d/%d" % [
		_get_category_label(category),
		int(progress.get("level", 0)),
		int(progress.get("max", 0)),
	]
	button.tooltip_text = _get_category_hint(category)
	button.custom_minimum_size = Vector2(_category_width, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", NavalUiTheme.FONT_SEMIBOLD)
	button.add_theme_font_size_override("font_size", max(12, _row_title_font_size))
	button.add_theme_color_override("font_color", NavalUiTheme.TEXT_BODY)
	button.add_theme_color_override("font_hover_color", NavalUiTheme.TEXT_ACCENT)
	button.add_theme_color_override("font_pressed_color", NavalUiTheme.TEXT_ACCENT)
	button.add_theme_color_override("font_focus_color", NavalUiTheme.TEXT_ACCENT)
	button.pressed.connect(_select_category.bind(category))
	return button


func _get_category_progress(category: String) -> Dictionary:
	var current_level := 0
	var max_level := 0
	for id in _get_upgrade_ids_for_category(category):
		var data: Dictionary = MetaManager.UPGRADES.get(id, {})
		current_level += _get_upgrade_level(id)
		max_level += int(data.get("max_level", 0))
	return {
		"level": current_level,
		"max": max_level,
	}


func _create_upgrade_row(id: String) -> Button:
	var data: Dictionary = MetaManager.UPGRADES[id]
	var level := _get_upgrade_level(id)
	var max_level := int(data.get("max_level", 1))
	var is_max := level >= max_level
	var cost := MetaManager.get_upgrade_cost(id)
	var affordable := SaveManager.gold >= cost
	var accent := _get_upgrade_color(id)

	var row := Button.new()
	row.text = ""
	row.clip_contents = true
	row.custom_minimum_size = Vector2(0, _row_height)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.focus_mode = Control.FOCUS_NONE
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("normal", _make_upgrade_row_style(id, false, "normal", is_max, affordable))
	row.add_theme_stylebox_override("hover", _make_upgrade_row_style(id, true, "hover", is_max, affordable))
	row.add_theme_stylebox_override("pressed", _make_upgrade_row_style(id, true, "pressed", is_max, affordable))
	row.pressed.connect(_select_upgrade.bind(id))
	row.mouse_entered.connect(func(): _select_upgrade(id))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)

	var layout := HBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var icon_frame_row := PanelContainer.new()
	icon_frame_row.custom_minimum_size = Vector2(_row_height - 12, _row_height - 12)
	icon_frame_row.clip_contents = true
	icon_frame_row.add_theme_stylebox_override("panel", NavalUiTheme.make_emblem_frame_style(accent, true))
	layout.add_child(icon_frame_row)

	_add_art_or_emblem(
		icon_frame_row,
		id,
		roundi(lerpf(24.0, 30.0, clampf(float(_row_height - 64) / 12.0, 0.0, 1.0))),
		accent
	)

	var copy_box := VBoxContainer.new()
	copy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy_box.alignment = BoxContainer.ALIGNMENT_CENTER
	copy_box.add_theme_constant_override("separation", 2)
	layout.add_child(copy_box)

	var name_label := Label.new()
	name_label.text = _get_upgrade_name(id, data)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_override("font", NavalUiTheme.FONT_SEMIBOLD)
	name_label.add_theme_font_size_override("font_size", _row_title_font_size)
	name_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN.lerp(accent, 0.16))
	copy_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = _get_upgrade_description(id, data)
	desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc_label.add_theme_font_override("font", NavalUiTheme.FONT_MEDIUM)
	desc_label.add_theme_font_size_override("font_size", _row_body_font_size)
	desc_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MUTED)
	copy_box.add_child(desc_label)

	var level_box := VBoxContainer.new()
	level_box.custom_minimum_size = Vector2(roundf(lerpf(74.0, 86.0, clampf(float(_row_height - 64) / 12.0, 0.0, 1.0))), 0)
	level_box.alignment = BoxContainer.ALIGNMENT_CENTER
	level_box.add_theme_constant_override("separation", 4)
	layout.add_child(level_box)

	var level_label := Label.new()
	level_label.text = "Lv.%d/%d" % [level, max_level]
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	NavalUiTheme.style_gold(level_label, max(10, _row_body_font_size))
	level_box.add_child(level_label)

	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_END
	pips.add_theme_constant_override("separation", 3)
	level_box.add_child(pips)
	for i in range(max_level):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(10, 5)
		pip.color = NavalUiTheme.TEXT_GOLD if i < level else Color(0.20, 0.18, 0.15, 0.95)
		pips.add_child(pip)

	var price_label := Label.new()
	price_label.custom_minimum_size = Vector2(58, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_gold(price_label, max(11, _row_body_font_size))
	if is_max:
		price_label.text = "MAX"
		price_label.add_theme_color_override("font_color", Color(0.72, 0.90, 0.52))
	else:
		price_label.text = "%d P" % cost
		price_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_GOLD if affordable else NavalUiTheme.TEXT_MUTED)
	layout.add_child(price_label)

	return row


func _refresh_dynamic_styles() -> void:
	for key in _category_buttons.keys():
		var category := str(key)
		var button := _category_buttons[category] as Button
		if not is_instance_valid(button):
			continue
		var selected := category == _active_category
		var focused := _category_focus_active and selected
		button.add_theme_stylebox_override("normal", _make_category_style(category, selected, "normal", focused))
		button.add_theme_stylebox_override("hover", _make_category_style(category, true, "hover", true))
		button.add_theme_stylebox_override("pressed", _make_category_style(category, true, "pressed", true))
		button.add_theme_stylebox_override("focus", _make_category_style(category, true, "hover", true))
		button.add_theme_color_override("font_color", NavalUiTheme.TEXT_ACCENT if selected else NavalUiTheme.TEXT_BODY)

	for key in _upgrade_buttons.keys():
		var id := str(key)
		var row := _upgrade_buttons[id] as Button
		if not is_instance_valid(row):
			continue
		var data: Dictionary = MetaManager.UPGRADES.get(id, {})
		var level := _get_upgrade_level(id)
		var max_level := int(data.get("max_level", 1))
		var is_max := level >= max_level
		var affordable := SaveManager.gold >= MetaManager.get_upgrade_cost(id)
		var selected := id == _selected_upgrade_id and not _category_focus_active
		row.add_theme_stylebox_override("normal", _make_upgrade_row_style(id, selected, "normal", is_max, affordable))
		row.add_theme_stylebox_override("hover", _make_upgrade_row_style(id, true, "hover", is_max, affordable))
		row.add_theme_stylebox_override("pressed", _make_upgrade_row_style(id, true, "pressed", is_max, affordable))
		row.add_theme_stylebox_override("focus", _make_upgrade_row_style(id, true, "hover", is_max, affordable))


func _make_category_style(category: String, selected: bool, state: String, focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.13, 0.52)
	style.border_color = Color(0.34, 0.29, 0.18, 0.52)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if selected:
		style.bg_color = Color(0.12, 0.17, 0.23, 0.86)
		style.border_color = NavalUiTheme.BORDER_GOLD_SOFT
	if focused:
		style.bg_color = Color(0.15, 0.20, 0.27, 0.96)
		style.border_color = NavalUiTheme.BORDER_GOLD
		style.set_border_width_all(2)
	if state == "hover" or state == "pressed":
		style.bg_color = style.bg_color.lightened(0.06)
		style.border_color = NavalUiTheme.BORDER_GOLD
	return style


func _make_upgrade_row_style(id: String, selected: bool, state: String, is_max: bool, affordable: bool) -> StyleBoxFlat:
	var accent := _get_upgrade_color(id)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.46)
	style.border_color = Color(0.35, 0.31, 0.22, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	if selected:
		style.bg_color = Color(0.10, 0.15, 0.21, 0.84)
		style.border_color = accent.lerp(NavalUiTheme.BORDER_GOLD, 0.46)
	if state == "hover" or state == "pressed":
		style.bg_color = style.bg_color.lightened(0.05)
		style.border_color = accent.lerp(NavalUiTheme.BORDER_GOLD, 0.62)
	if is_max:
		style.border_color = Color(0.54, 0.72, 0.42, 0.72) if selected else Color(0.35, 0.45, 0.31, 0.50)
	elif affordable and selected:
		style.shadow_color = Color(0.78, 0.62, 0.26, 0.08)
		style.shadow_size = 5
	return style


func _update_detail_panel() -> void:
	if _selected_upgrade_id.is_empty() or not MetaManager.UPGRADES.has(_selected_upgrade_id):
		selected_icon_label.text = ""
		selected_name_label.text = ""
		selected_level_label.text = ""
		selected_desc_label.text = ""
		selected_effect_label.text = ""
		cost_label.text = ""
		buy_button.disabled = true
		return

	var data: Dictionary = MetaManager.UPGRADES.get(_selected_upgrade_id, {})
	var level := _get_upgrade_level(_selected_upgrade_id)
	var max_level := int(data.get("max_level", 1))
	var cost := MetaManager.get_upgrade_cost(_selected_upgrade_id)
	var is_max := level >= max_level

	_update_detail_art(_selected_upgrade_id)
	selected_name_label.text = _get_upgrade_name(_selected_upgrade_id, data)
	selected_level_label.text = "Lv.%d / %d" % [level, max_level]
	selected_desc_label.text = _get_upgrade_description(_selected_upgrade_id, data)
	selected_effect_label.text = _build_effect_text(_selected_upgrade_id, level)

	if is_max:
		cost_label.text = LocaleManager.t("meta.max_level", "최대 레벨 도달")
		cost_label.add_theme_color_override("font_color", Color(0.72, 0.90, 0.52))
		buy_button.text = "MAX"
		buy_button.disabled = true
	else:
		cost_label.text = LocaleManager.t("meta.cost", "비용 {cost} P", {"cost": cost})
		cost_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_GOLD if SaveManager.gold >= cost else NavalUiTheme.TEXT_MUTED)
		buy_button.text = LocaleManager.t("meta.buy", "구입")
		buy_button.disabled = SaveManager.gold < cost


func _select_category(category: String, keep_category_focus: bool = false) -> void:
	if category == _active_category:
		_category_focus_active = keep_category_focus
		_refresh_dynamic_styles()
		return
	_active_category = category
	UiButtonAudio.play_nav()
	_footer_focus_index = -1
	_category_focus_active = keep_category_focus
	var ids := _get_upgrade_ids_for_category(_active_category)
	_selected_upgrade_id = ids[0] if not ids.is_empty() else ""
	update_ui()


func _select_upgrade(id: String) -> void:
	if not MetaManager.UPGRADES.has(id):
		return
	var selection_changed := id != _selected_upgrade_id
	_active_category = _get_upgrade_category(id)
	_selected_upgrade_id = id
	if selection_changed:
		UiButtonAudio.play_nav()
	_footer_focus_index = -1
	_category_focus_active = false
	_update_detail_panel()
	_refresh_dynamic_styles()
	_scroll_selected_row_into_view()


func _add_art_or_emblem(parent: Control, id: String, emblem_size: int, accent: Color) -> void:
	var texture := _get_upgrade_art_texture(id)
	if texture != null:
		var art := TextureRect.new()
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.texture = texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		parent.add_child(art)
		return

	var icon := Label.new()
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	NavalUiTheme.apply_emblem(icon, id, emblem_size, accent)
	parent.add_child(icon)


func _update_detail_art(id: String) -> void:
	var texture := _get_upgrade_art_texture(id)
	if is_instance_valid(selected_icon_texture):
		selected_icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		selected_icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		selected_icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		selected_icon_texture.texture = texture
		selected_icon_texture.visible = texture != null
	if is_instance_valid(selected_icon_label):
		selected_icon_label.visible = texture == null
		if texture == null:
			NavalUiTheme.apply_emblem(
				selected_icon_label,
				id,
				roundi(lerpf(36.0, 44.0, clampf((float(icon_frame.custom_minimum_size.x) - 76.0) / 14.0, 0.0, 1.0))),
				_get_upgrade_color(id)
			)


func _get_upgrade_art_texture(id: String) -> Texture2D:
	if _art_texture_cache.has(id):
		return _art_texture_cache[id] as Texture2D
	var data: Dictionary = MetaManager.UPGRADES.get(id, {})
	var art_path := str(data.get("card_art_path", "")).strip_edges()
	if art_path.is_empty() or not ResourceLoader.exists(art_path):
		_art_texture_cache[id] = null
		return null
	var texture := ResourceLoader.load(art_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	_art_texture_cache[id] = texture
	return texture


func _scroll_selected_row_into_view() -> void:
	var selected_row := _upgrade_buttons.get(_selected_upgrade_id, null) as Control
	if is_instance_valid(selected_row) and is_instance_valid(scroll_container):
		scroll_container.ensure_control_visible(selected_row)


func _get_selected_index() -> int:
	return _ordered_upgrade_ids.find(_selected_upgrade_id)


func _enter_category_focus() -> void:
	_footer_focus_index = -1
	_category_focus_active = true
	_refresh_dynamic_styles()


func _exit_category_focus_to_list() -> void:
	_category_focus_active = false
	_refresh_dynamic_styles()
	_scroll_selected_row_into_view()


func _move_category_focus(direction: int) -> void:
	if CATEGORY_ORDER.is_empty():
		return
	var index := CATEGORY_ORDER.find(_active_category)
	if index == -1:
		index = 0
	var attempts := CATEGORY_ORDER.size()
	while attempts > 0:
		index = wrapi(index + direction, 0, CATEGORY_ORDER.size())
		var category := str(CATEGORY_ORDER[index])
		if not _get_upgrade_ids_for_category(category).is_empty():
			_select_category(category, true)
			return
		attempts -= 1


func _move_selection_vertical(direction: int) -> void:
	if _ordered_upgrade_ids.is_empty():
		return
	var selected_index := _get_selected_index()
	if selected_index == -1:
		_select_upgrade(_ordered_upgrade_ids[0])
		return
	var next_index := selected_index + direction
	if next_index >= 0 and next_index < _ordered_upgrade_ids.size():
		_select_upgrade(_ordered_upgrade_ids[next_index])
		return
	if direction > 0:
		_enter_footer_focus()


func _enter_footer_focus() -> void:
	_category_focus_active = false
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


func _exit_footer_focus_to_list() -> void:
	_footer_focus_index = -1
	_category_focus_active = false
	_scroll_selected_row_into_view()


func _is_prev_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_left_event(event)


func _is_next_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_right_event(event)


func _is_up_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_up_event(event)


func _is_down_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_down_event(event)


func _is_confirm_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_confirm_event(event)


func _build_effect_text(id: String, level: int) -> String:
	var data: Dictionary = MetaManager.UPGRADES.get(id, {})
	var max_level := int(data.get("max_level", level))
	var next_level := mini(level + 1, max_level)
	var is_max := level >= max_level
	match id:
		"hull_hp":
			return _progress_line(
				LocaleManager.t("meta.effect.hull_hp", "선체"),
				"%.0f" % (PLAYER_BASE_HULL_HP + level * MetaManager.HULL_HP_BONUS_PER_LEVEL),
				"%.0f" % (PLAYER_BASE_HULL_HP + next_level * MetaManager.HULL_HP_BONUS_PER_LEVEL),
				is_max
			)
		"hull_defense":
			return _progress_line(
				LocaleManager.t("meta.effect.hull_defense", "방어력"),
				"%.1f" % (level * MetaManager.HULL_DEFENSE_BONUS_PER_LEVEL),
				"%.1f" % (next_level * MetaManager.HULL_DEFENSE_BONUS_PER_LEVEL),
				is_max
			)
		"sail_speed":
			return _progress_line(
				LocaleManager.t("meta.effect.sail_speed", "최대 속도"),
				"%.1f" % (PLAYER_BASE_MOVE_SPEED * (1.0 + level * MetaManager.SAIL_SPEED_BONUS_PER_LEVEL)),
				"%.1f" % (PLAYER_BASE_MOVE_SPEED * (1.0 + next_level * MetaManager.SAIL_SPEED_BONUS_PER_LEVEL)),
				is_max
			)
		"xp_gain":
			return _progress_line(
				LocaleManager.t("meta.effect.xp_gain", "획득 XP"),
				"%.0f%%" % (100.0 * (1.0 + level * MetaManager.XP_GAIN_BONUS_PER_LEVEL)),
				"%.0f%%" % (100.0 * (1.0 + next_level * MetaManager.XP_GAIN_BONUS_PER_LEVEL)),
				is_max
			)
		"pickup_range":
			return _progress_line(
				LocaleManager.t("meta.effect.pickup_range", "수집 반경"),
				"+%.1fm" % (level * MetaManager.COLLECTION_RADIUS_BONUS_PER_LEVEL),
				"+%.1fm" % (next_level * MetaManager.COLLECTION_RADIUS_BONUS_PER_LEVEL),
				is_max
			)
		"reroll_stock":
			return _progress_line(
				LocaleManager.t("meta.effect.reroll_stock", "재굴림"),
				"+%d회" % MetaManager.get_reroll_bonus_for_level(level),
				"+%d회" % MetaManager.get_reroll_bonus_for_level(next_level),
				is_max
			)
		"crew_capacity":
			return _progress_line(
				LocaleManager.t("meta.effect.crew_capacity", "병사 수"),
				"+%d명" % MetaManager.get_crew_capacity_bonus_for_level(level),
				"+%d명" % MetaManager.get_crew_capacity_bonus_for_level(next_level),
				is_max
			)
		"crew_health":
			return _progress_line(
				LocaleManager.t("meta.effect.crew_health", "병사 체력"),
				"%.0f" % (SOLDIER_BASE_HEALTH * (1.0 + level * MetaManager.CREW_HEALTH_BONUS_PER_LEVEL)),
				"%.0f" % (SOLDIER_BASE_HEALTH * (1.0 + next_level * MetaManager.CREW_HEALTH_BONUS_PER_LEVEL)),
				is_max
			)
		"crew_attack":
			return _progress_line(
				LocaleManager.t("meta.effect.crew_attack", "무기 피해"),
				"+%.1f%%" % (level * MetaManager.CREW_DAMAGE_BONUS_PER_LEVEL * 100.0),
				"+%.1f%%" % (next_level * MetaManager.CREW_DAMAGE_BONUS_PER_LEVEL * 100.0),
				is_max
			)
		"crew_defense":
			return _progress_line(
				LocaleManager.t("meta.effect.crew_defense", "병사 방어력"),
				"+%.1f" % (level * MetaManager.CREW_DEFENSE_BONUS_PER_LEVEL),
				"+%.1f" % (next_level * MetaManager.CREW_DEFENSE_BONUS_PER_LEVEL),
				is_max
			)
	return ""


func _progress_line(label: String, current_value: String, next_value: String, is_max: bool) -> String:
	if is_max:
		return LocaleManager.t("meta.effect.max", "{label} {current} (최대)", {"label": label, "current": current_value})
	return LocaleManager.t("meta.effect.progress", "{label} {current} -> {next}", {"label": label, "current": current_value, "next": next_value})


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
