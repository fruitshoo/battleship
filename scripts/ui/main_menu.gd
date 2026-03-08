extends Control

const META_UPGRADE_UI_SCENE := preload("res://scenes/ui/meta_upgrade_ui.tscn")
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const GAME_SCENE_PATH := "res://scenes/main.tscn"

@onready var gold_label: Label = $Margin/Frame/Layout/LeftColumn/GoldPanel/GoldLabel
@onready var start_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/StartButton
@onready var meta_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/MetaButton
@onready var options_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/OptionsButton
@onready var quit_button: Button = $Margin/Frame/Layout/RightColumn/Buttons/QuitButton

var _modal_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	start_button.pressed.connect(_on_start_pressed)
	meta_button.pressed.connect(_on_meta_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.visible = OS.get_name() != "Web"
	_refresh_gold_label()
	SaveManager.apply_settings()

func _refresh_gold_label() -> void:
	gold_label.text = "보유 골드 %d G" % SaveManager.gold

func _set_buttons_disabled(disabled: bool) -> void:
	start_button.disabled = disabled
	meta_button.disabled = disabled
	options_button.disabled = disabled
	quit_button.disabled = disabled

func _on_start_pressed() -> void:
	if _modal_open:
		return
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
