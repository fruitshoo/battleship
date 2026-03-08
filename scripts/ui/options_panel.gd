extends CanvasLayer

signal closed

@onready var master_slider: HSlider = $Panel/Shell/Content/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Panel/Shell/Content/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Panel/Shell/Content/SfxRow/SfxSlider
@onready var ui_slider: HSlider = $Panel/Shell/Content/UiRow/UiSlider
@onready var fullscreen_check: CheckBox = $Panel/Shell/Content/FullscreenCheck
@onready var back_button: Button = $Panel/Shell/Footer/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_slider(master_slider, "master_volume")
	_bind_slider(music_slider, "music_volume")
	_bind_slider(sfx_slider, "sfx_volume")
	_bind_slider(ui_slider, "ui_volume")
	master_slider.value = float(SaveManager.get_setting("master_volume", 0.85))
	music_slider.value = float(SaveManager.get_setting("music_volume", 0.75))
	sfx_slider.value = float(SaveManager.get_setting("sfx_volume", 0.85))
	ui_slider.value = float(SaveManager.get_setting("ui_volume", 0.85))
	fullscreen_check.button_pressed = bool(SaveManager.get_setting("fullscreen", false))
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)

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
