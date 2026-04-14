extends Control

const META_UPGRADE_UI_SCENE := preload("res://scenes/ui/meta_upgrade_ui.tscn")
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const GAME_SCENE_PATH := "res://scenes/main.tscn"
@export var background_texture: Texture2D
@export_range(0.0, 1.0, 0.01) var background_dim: float = 0.18
@export var fallback_version_text: String = "v0.1.0"

@onready var background_image: TextureRect = $BackgroundImage
@onready var background_overlay: ColorRect = $Background
@onready var eyebrow_label: Label = $TitleBlock/Eyebrow
@onready var title_label: Label = $TitleBlock/Title
@onready var start_button: Button = $ButtonBlock/StartButton
@onready var meta_button: Button = $ButtonBlock/MetaButton
@onready var options_button: Button = $ButtonBlock/OptionsButton
@onready var quit_button: Button = $ButtonBlock/QuitButton
@onready var version_label: Label = $VersionLabel

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
	_refresh_version_label()
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
				if get_viewport(): get_viewport().set_input_as_handled()
			KEY_S, KEY_D:
				_move_menu_focus(1)
				if get_viewport(): get_viewport().set_input_as_handled()
			KEY_SPACE:
				_activate_focused_menu_button()
				if get_viewport(): get_viewport().set_input_as_handled()


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
	if is_instance_valid(background_overlay) and background_overlay.material is ShaderMaterial:
		var vignette_material := background_overlay.material as ShaderMaterial
		vignette_material.set_shader_parameter("vignette_color", Color(0.02, 0.04, 0.07, clamp(background_dim, 0.0, 1.0)))


func _apply_ui_theme() -> void:
	NavalUiTheme.style_heading(eyebrow_label, 16)
	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", 68)
		title_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN)
		title_label.add_theme_color_override("font_shadow_color", NavalUiTheme.OUTLINE_DARK)
		title_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
		title_label.add_theme_constant_override("shadow_offset_x", 3)
		title_label.add_theme_constant_override("shadow_offset_y", 4)
		title_label.add_theme_constant_override("outline_size", 2)
	for button in [start_button, meta_button, options_button, quit_button]:
		_apply_compact_menu_button(button)


func _apply_compact_menu_button(button: Button) -> void:
	if not is_instance_valid(button):
		return
	NavalUiTheme.apply_menu_button(button, 18)
	button.add_theme_stylebox_override("normal", NavalUiTheme.make_panel_style(NavalUiTheme.PANEL_BG_SOFT, NavalUiTheme.BORDER_GOLD_SOFT, 8, 1, 16.0, 8.0, 16.0, 8.0))
	button.add_theme_stylebox_override("hover", NavalUiTheme.make_panel_style(Color(0.16, 0.23, 0.31, 0.82), NavalUiTheme.BORDER_GOLD, 8, 1, 16.0, 8.0, 16.0, 8.0))
	button.add_theme_stylebox_override("pressed", NavalUiTheme.make_panel_style(Color(0.09, 0.13, 0.18, 0.90), Color(0.93, 0.84, 0.56, 0.92), 8, 1, 16.0, 8.0, 16.0, 8.0))
	button.add_theme_stylebox_override("focus", NavalUiTheme.make_panel_style(Color(0.16, 0.23, 0.31, 0.82), NavalUiTheme.BORDER_GOLD, 8, 1, 16.0, 8.0, 16.0, 8.0))

func _refresh_version_label() -> void:
	if not is_instance_valid(version_label):
		return
	var project_version := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if project_version.is_empty():
		version_label.text = fallback_version_text
	elif project_version.begins_with("v"):
		version_label.text = project_version
	else:
		version_label.text = "v%s" % project_version

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
