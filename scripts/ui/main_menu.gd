extends Control

const META_UPGRADE_UI_SCENE := preload("res://scenes/ui/meta_upgrade_ui.tscn")
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const GAME_SCENE_PATH := "res://scenes/main.tscn"
@export var background_texture: Texture2D
@export_range(0.0, 1.0, 0.01) var background_dim: float = 0.08

@onready var background_image: TextureRect = $BackgroundImage
@onready var background_overlay: ColorRect = $Background
@onready var frame_panel: PanelContainer = $Margin/Frame
@onready var gold_panel: PanelContainer = $Margin/Frame/Layout/LeftColumn/GoldPanel
@onready var eyebrow_label: Label = $Margin/Frame/Layout/LeftColumn/Eyebrow
@onready var title_label: Label = $Margin/Frame/Layout/LeftColumn/Title
@onready var body_label: Label = $Margin/Frame/Layout/LeftColumn/Body
@onready var gold_label: Label = $Margin/Frame/Layout/LeftColumn/GoldPanel/GoldLabel
@onready var hint_label: Label = $Margin/Frame/Layout/LeftColumn/Hint
@onready var menu_title_label: Label = $Margin/Frame/Layout/RightColumn/MenuTitle
@onready var footer_label: Label = $Margin/Frame/Layout/RightColumn/Footer
@onready var start_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/StartButton
@onready var meta_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/MetaButton
@onready var options_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/OptionsButton
@onready var quit_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/QuitButton

var _modal_open: bool = false
var _menu_buttons: Array[Button] = []
var _focused_button_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_background_settings()
	_apply_ui_theme()
	start_button.pressed.connect(_on_start_pressed)
	meta_button.pressed.connect(_on_meta_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.visible = OS.get_name() != "Web"
	_menu_buttons = [start_button, meta_button, options_button]
	if quit_button.visible:
		_menu_buttons.append(quit_button)
	_refresh_gold_label()
	SaveManager.apply_settings()
	_focus_first_menu_button()


func _unhandled_input(event: InputEvent) -> void:
	if _modal_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		match key_event.physical_keycode:
			KEY_W, KEY_A:
				_move_menu_focus(-1)
				get_viewport().set_input_as_handled()
			KEY_S, KEY_D:
				_move_menu_focus(1)
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				_activate_focused_menu_button()
				get_viewport().set_input_as_handled()


func _focus_first_menu_button() -> void:
	for i in range(_menu_buttons.size()):
		var button: Button = _menu_buttons[i]
		if is_instance_valid(button) and button.visible and not button.disabled:
			_focused_button_index = i
			button.grab_focus()
			return


func _move_menu_focus(direction: int) -> void:
	if _menu_buttons.is_empty():
		return
	var button_count: int = _menu_buttons.size()
	for step in range(1, button_count + 1):
		var next_index: int = posmod(_focused_button_index + direction * step, button_count)
		var button: Button = _menu_buttons[next_index]
		if is_instance_valid(button) and button.visible and not button.disabled:
			_focused_button_index = next_index
			button.grab_focus()
			return


func _activate_focused_menu_button() -> void:
	if _menu_buttons.is_empty():
		return
	if _focused_button_index < 0 or _focused_button_index >= _menu_buttons.size():
		_focus_first_menu_button()
		return
	var button: Button = _menu_buttons[_focused_button_index]
	if not is_instance_valid(button) or not button.visible or button.disabled:
		return
	button.emit_signal("pressed")

func _apply_background_settings() -> void:
	if is_instance_valid(background_image):
		background_image.texture = background_texture
		background_image.visible = background_texture != null
	if is_instance_valid(background_overlay):
		background_overlay.color = Color(0.03, 0.07, 0.12, clamp(background_dim, 0.0, 1.0))


func _apply_ui_theme() -> void:
	if is_instance_valid(frame_panel):
		frame_panel.add_theme_stylebox_override("panel", NavalUiTheme.make_menu_frame_style())
	if is_instance_valid(gold_panel):
		gold_panel.add_theme_stylebox_override("panel", NavalUiTheme.make_gold_panel_style())
	NavalUiTheme.style_heading(eyebrow_label, 15)
	NavalUiTheme.style_heading(menu_title_label, 24)
	NavalUiTheme.style_body(body_label, 18)
	NavalUiTheme.style_muted(hint_label, 14)
	NavalUiTheme.style_muted(footer_label, 13)
	NavalUiTheme.style_gold(gold_label, 22)
	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", 62)
		title_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN)
		title_label.add_theme_color_override("font_shadow_color", NavalUiTheme.OUTLINE_DARK)
		title_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
		title_label.add_theme_constant_override("shadow_offset_x", 3)
		title_label.add_theme_constant_override("shadow_offset_y", 4)
		title_label.add_theme_constant_override("outline_size", 2)
	for button in [start_button, meta_button, options_button, quit_button]:
		NavalUiTheme.apply_menu_button(button, 20)

func _refresh_gold_label() -> void:
	gold_label.text = "보유 골드 %d G" % SaveManager.gold

func _set_buttons_disabled(disabled: bool) -> void:
	start_button.disabled = disabled
	meta_button.disabled = disabled
	options_button.disabled = disabled
	quit_button.disabled = disabled
	if not disabled:
		_focus_first_menu_button()

func _on_start_pressed() -> void:
	if _modal_open:
		return
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_meta_pressed() -> void:
	if _modal_open:
		return
	_modal_open = true
	_set_buttons_disabled(true)
	var ui = META_UPGRADE_UI_SCENE.instantiate()
	ui.title_text = "[항구] 영구 강화"
	ui.close_button_text = "메뉴로 돌아가기"
	add_child(ui)
	ui.closed.connect(func():
		_modal_open = false
		_set_buttons_disabled(false)
		_refresh_gold_label()
	)

func _on_options_pressed() -> void:
	if _modal_open:
		return
	_modal_open = true
	_set_buttons_disabled(true)
	var ui = OPTIONS_PANEL_SCENE.instantiate()
	add_child(ui)
	ui.closed.connect(func():
		_modal_open = false
		_set_buttons_disabled(false)
	)

func _on_quit_pressed() -> void:
	if _modal_open:
		return
	get_tree().quit()
