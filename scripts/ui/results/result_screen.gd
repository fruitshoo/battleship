extends Control


const GAME_SCENE_PATH := "res://scenes/main.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")

@export var background_texture: Texture2D

@onready var background_image: TextureRect = $BackgroundImage
@onready var background_tint: ColorRect = $BackgroundTint
@onready var content: VBoxContainer = $Content
@onready var title_block: VBoxContainer = $Content/TitleBlock
@onready var title_label: Label = $Content/TitleBlock/Title
@onready var subtitle_label: Label = $Content/TitleBlock/Subtitle
@onready var body: HBoxContainer = $Content/Body
@onready var summary_panel: PanelContainer = $Content/Body/SummaryPanel
@onready var summary_margin: MarginContainer = $Content/Body/SummaryPanel/Margin
@onready var summary_list: VBoxContainer = $Content/Body/SummaryPanel/Margin/SummaryList
@onready var weapon_panel: PanelContainer = $Content/Body/WeaponPanel
@onready var weapon_margin: MarginContainer = $Content/Body/WeaponPanel/Margin
@onready var weapon_list: VBoxContainer = $Content/Body/WeaponPanel/Margin/WeaponList
@onready var button_block: HBoxContainer = $ButtonBlock
@onready var restart_button: Button = $ButtonBlock/RestartButton
@onready var main_menu_button: Button = $ButtonBlock/MainMenuButton

var _summary_font_size: int = 18
var _subtitle_font_size: int = 18
var _title_font_size: int = 50
var _button_font_size: int = 18
var _weapon_value_width: float = 120.0
var _last_result: Dictionary = {}
var _action_buttons: Array[Button] = []
var _focused_button_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	get_tree().paused = false
	_apply_background()
	_apply_theme()
	_apply_layout_density()
	_render_result(RunResultStore.get_latest_result())
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_action_buttons = [restart_button, main_menu_button]
	_wire_button_interactions()
	call_deferred("_focus_first_action_button")
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func _unhandled_input(event: InputEvent) -> void:
	if _is_prev_event(event):
		_move_action_focus(-1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_next_event(event):
		_move_action_focus(1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		_activate_focused_action()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_main_menu_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func _apply_background() -> void:
	if is_instance_valid(background_image):
		background_image.texture = background_texture
		background_image.visible = background_texture != null
	if is_instance_valid(background_tint):
		background_tint.color = Color.WHITE
		background_tint.material = UiOverlayFx.make_vignette_material(
			Color(0.02, 0.04, 0.07, 0.62),
			Vector2(0.5, 0.42),
			0.88,
			0.44,
			0.18,
			0.12,
			Vector3.ZERO
		)


func _wire_button_interactions() -> void:
	for button in _action_buttons:
		if not is_instance_valid(button):
			continue
		button.focus_entered.connect(func():
			var idx := _action_buttons.find(button)
			if idx != -1:
				_focused_button_index = idx
		)
		button.mouse_entered.connect(func():
			if button.visible and not button.disabled:
				button.grab_focus()
		)


func _focus_first_action_button() -> void:
	for i in range(_action_buttons.size()):
		var button := _action_buttons[i]
		if is_instance_valid(button) and button.visible and not button.disabled:
			_focused_button_index = i
			button.grab_focus()
			return


func _move_action_focus(direction: int) -> void:
	if _action_buttons.is_empty():
		return
	var button_count := _action_buttons.size()
	for step in range(1, button_count + 1):
		var next_index := posmod(_focused_button_index + direction * step, button_count)
		var button := _action_buttons[next_index]
		if is_instance_valid(button) and button.visible and not button.disabled:
			_focused_button_index = next_index
			button.grab_focus()
			return


func _activate_focused_action() -> void:
	if _focused_button_index < 0 or _focused_button_index >= _action_buttons.size():
		_focus_first_action_button()
		return
	var button := _action_buttons[_focused_button_index]
	if not is_instance_valid(button) or not button.visible or button.disabled:
		return
	button.emit_signal("pressed")


func _apply_theme() -> void:
	ModalMenuSkin.apply_modal_section_panel(summary_panel)
	ModalMenuSkin.apply_modal_section_panel(weapon_panel)
	NavalUiTheme.style_caption(subtitle_label, _subtitle_font_size, NavalUiTheme.TEXT_ACCENT)
	if is_instance_valid(title_label):
		NavalUiTheme.style_display_title(title_label, _title_font_size)
	for button in [restart_button, main_menu_button]:
		ModalMenuSkin.apply_action_button_theme(button, button == restart_button)


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 980.0) / 440.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 720.0) / 260.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	_summary_font_size = roundi(lerpf(15.0, 18.0, density))
	_subtitle_font_size = roundi(lerpf(15.0, 18.0, density))
	_title_font_size = roundi(lerpf(38.0, 50.0, density))
	_button_font_size = roundi(lerpf(16.0, 18.0, density))
	_weapon_value_width = roundf(lerpf(96.0, 120.0, density))
	if is_instance_valid(content):
		var half_width := roundi(clampf(viewport_size.x * 0.36, 320.0, 430.0))
		content.offset_left = -half_width
		content.offset_right = half_width
		content.anchor_top = 0.045
		content.anchor_bottom = 0.86
		content.add_theme_constant_override("separation", roundi(lerpf(12.0, 16.0, density)))
	if is_instance_valid(title_block):
		title_block.add_theme_constant_override("separation", roundi(lerpf(6.0, 8.0, density)))
	if is_instance_valid(body):
		body.add_theme_constant_override("separation", roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(summary_margin):
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			summary_margin.add_theme_constant_override(side, roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(weapon_margin):
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			weapon_margin.add_theme_constant_override(side, roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(summary_list):
		summary_list.add_theme_constant_override("separation", roundi(lerpf(9.0, 12.0, density)))
	if is_instance_valid(weapon_list):
		weapon_list.add_theme_constant_override("separation", roundi(lerpf(9.0, 12.0, density)))
	if is_instance_valid(button_block):
		var button_width := roundi(clampf(viewport_size.x * 0.17, 180.0, 220.0))
		button_block.offset_left = -button_width - 18.0
		button_block.offset_right = button_width + 18.0
		button_block.offset_top = roundi(lerpf(-62.0, -70.0, density))
		button_block.offset_bottom = -22.0
		button_block.add_theme_constant_override("separation", roundi(lerpf(10.0, 14.0, density)))
	for button in [restart_button, main_menu_button]:
		if not is_instance_valid(button):
			continue
		button.custom_minimum_size = Vector2(roundi(clampf(viewport_size.x * 0.17, 180.0, 220.0)), roundi(lerpf(42.0, 48.0, density)))
		button.add_theme_font_size_override("font_size", _button_font_size)
	_apply_theme()


func _on_viewport_size_changed() -> void:
	_apply_layout_density()
	if not _last_result.is_empty():
		_render_result(_last_result)


func _render_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	title_label.text = str(result.get("title", "항해 결과"))
	subtitle_label.text = str(result.get("outcome", "항해 종료"))

	_clear_children(summary_list)
	_clear_children(weapon_list)

	var survived_seconds: float = float(result.get("survived_seconds", 0.0))
	_add_summary_row("생존 시간", _format_time(survived_seconds))
	_add_summary_row("획득 골드", "%d G" % int(result.get("gold", 0)))
	_add_summary_row("도달 레벨", "Lv.%d" % int(result.get("level", 1)))
	_add_summary_row("격침", "%d척" % int(result.get("ships_sunk", 0)))
	_add_summary_row("나포", "%d척" % int(result.get("ships_derelicted", 0)))
	_add_summary_row("적 병사", "%d명" % int(result.get("soldiers_killed", 0)))
	_add_summary_row("아군 생존", "%d / %d" % [int(result.get("crew_alive", 0)), int(result.get("crew_capacity", 0))])
	_add_summary_row("총 무기 피해", "%.0f" % float(result.get("total_weapon_damage", 0.0)))

	var weapon_rows: Array = result.get("weapon_rows", [])
	if weapon_rows.is_empty():
		_add_weapon_empty_row()
	else:
		for row in weapon_rows:
			_add_weapon_row(row)


func _add_summary_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	summary_list.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_muted(label, _summary_font_size)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_gold(value, _summary_font_size)
	row.add_child(value)


func _add_weapon_row(row_data: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	weapon_list.add_child(row)

	var name_label := Label.new()
	name_label.text = str(row_data.get("name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(name_label, _summary_font_size)
	row.add_child(name_label)

	var damage_label := Label.new()
	damage_label.text = "%.0f" % float(row_data.get("damage", 0.0))
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	damage_label.custom_minimum_size = Vector2(_weapon_value_width, 0.0)
	NavalUiTheme.style_gold(damage_label, _summary_font_size)
	row.add_child(damage_label)


func _add_weapon_empty_row() -> void:
	var label := Label.new()
	label.text = "기록된 무기 피해 없음"
	NavalUiTheme.style_muted(label, _summary_font_size)
	weapon_list.add_child(label)


func _clear_children(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for child in node.get_children():
		child.queue_free()


func _format_time(seconds: float) -> String:
	var total_seconds: int = max(0, int(seconds))
	return "%02d:%02d" % [int(total_seconds / 60), total_seconds % 60]


func _on_restart_pressed() -> void:
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	RunResultStore.clear()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_main_menu_pressed() -> void:
	RunResultStore.clear()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _is_prev_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up") or _is_physical_key_pressed(event, KEY_A) or _is_physical_key_pressed(event, KEY_W)


func _is_next_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down") or _is_physical_key_pressed(event, KEY_D) or _is_physical_key_pressed(event, KEY_S)


func _is_confirm_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or _is_keycode_pressed(event, KEY_SPACE) or _is_keycode_pressed(event, KEY_ENTER) or _is_keycode_pressed(event, KEY_KP_ENTER)


func _is_physical_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keycode


func _is_keycode_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
