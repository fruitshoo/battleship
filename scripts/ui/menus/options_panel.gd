extends CanvasLayer

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

signal closed

@onready var backdrop: ColorRect = $Backdrop
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Shell/Title
@onready var subtitle_label: Label = $Panel/Shell/Subtitle
@onready var master_label: Label = $Panel/Shell/Content/MasterRow/MasterLabel
@onready var master_slider: HSlider = $Panel/Shell/Content/MasterRow/MasterSlider
@onready var music_label: Label = $Panel/Shell/Content/MusicRow/MusicLabel
@onready var music_slider: HSlider = $Panel/Shell/Content/MusicRow/MusicSlider
@onready var sfx_label: Label = $Panel/Shell/Content/SfxRow/SfxLabel
@onready var sfx_slider: HSlider = $Panel/Shell/Content/SfxRow/SfxSlider
@onready var ui_label: Label = $Panel/Shell/Content/UiRow/UiLabel
@onready var ui_slider: HSlider = $Panel/Shell/Content/UiRow/UiSlider
@onready var fullscreen_check: CheckBox = $Panel/Shell/Content/FullscreenCheck
@onready var back_button: Button = $Panel/Shell/Footer/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_bind_slider(master_slider, "master_volume")
	_bind_slider(music_slider, "music_volume")
	_bind_slider(sfx_slider, "sfx_volume")
	_bind_slider(ui_slider, "ui_volume")
	master_slider.value = float(SaveManager.get_setting("master_volume", 0.85))
	music_slider.value = float(SaveManager.get_setting("music_volume", 0.75))
	sfx_slider.value = float(SaveManager.get_setting("sfx_volume", 0.85))
	ui_slider.value = float(SaveManager.get_setting("ui_volume", 0.85))
	fullscreen_check.button_pressed = SaveManager.get_setting("fullscreen", false) == true
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)

func _apply_theme() -> void:
	if is_instance_valid(backdrop):
		backdrop.color = Color(0.03, 0.06, 0.10, 0.74)
	if is_instance_valid(panel):
		panel.add_theme_stylebox_override("panel", NavalUiTheme.make_menu_frame_style())
	NavalUiTheme.style_heading(title_label, 30)
	NavalUiTheme.style_muted(subtitle_label, 14)
	for label in [master_label, music_label, sfx_label, ui_label]:
		NavalUiTheme.style_body(label, 13)
	if is_instance_valid(fullscreen_check):
		fullscreen_check.add_theme_color_override("font_color", NavalUiTheme.TEXT_BODY)
		fullscreen_check.add_theme_color_override("font_hover_color", NavalUiTheme.TEXT_ACCENT)
		fullscreen_check.add_theme_color_override("font_pressed_color", NavalUiTheme.TEXT_ACCENT)
	for slider in [master_slider, music_slider, sfx_slider, ui_slider]:
		NavalUiTheme.apply_progress_bar(slider, NavalUiTheme.PANEL_BG_DARK, NavalUiTheme.STATUS_ACTIVE_BLUE, 4)
	if is_instance_valid(back_button):
		NavalUiTheme.apply_menu_button(back_button, 16)

func _bind_slider(slider: HSlider, setting_key: String) -> void:
	slider.value_changed.connect(func(value: float):
		SaveManager.set_setting(setting_key, value, false)
		SaveManager.apply_settings()
	)

func _on_fullscreen_toggled(pressed: bool) -> void:
	SaveManager.set_setting("fullscreen", pressed, false)
	SaveManager.apply_settings()

func _on_back_pressed() -> void:
	SaveManager.save_game()
	closed.emit()
	queue_free()
