extends CanvasLayer

const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

@onready var panel_container: PanelContainer = $Center/Panel
@onready var title_label: Label = $Center/Panel/Margin/VBox/Title
@onready var resume_btn: Button = $Center/Panel/Margin/VBox/ResumeBtn
@onready var options_btn: Button = $Center/Panel/Margin/VBox/OptionsBtn
@onready var main_menu_btn: Button = $Center/Panel/Margin/VBox/MainMenuBtn
@onready var quit_btn: Button = $Center/Panel/Margin/VBox/QuitBtn

var _modal_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	
	_apply_ui_theme()
	
	resume_btn.pressed.connect(_on_resume_pressed)
	options_btn.pressed.connect(_on_options_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	
	if OS.get_name() == "Web":
		quit_btn.visible = false

func _apply_ui_theme() -> void:
	if is_instance_valid(panel_container):
		panel_container.add_theme_stylebox_override("panel", NavalUiTheme.make_menu_frame_style())
	NavalUiTheme.style_heading(title_label, 42)
	for button in [resume_btn, options_btn, main_menu_btn, quit_btn]:
		NavalUiTheme.apply_menu_button(button, 22)

func _unhandled_input(event: InputEvent) -> void:
	if _modal_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_resume_pressed()
		if get_viewport(): get_viewport().set_input_as_handled()

func _on_resume_pressed() -> void:
	if _modal_open: return
	get_tree().paused = false
	queue_free()

func _on_options_pressed() -> void:
	if _modal_open: return
	_modal_open = true
	var ui = OPTIONS_PANEL_SCENE.instantiate()
	add_child(ui)
	ui.closed.connect(func():
		_modal_open = false
	)

func _on_main_menu_pressed() -> void:
	if _modal_open: return
	get_tree().paused = false
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	get_tree().change_scene_to_file(MAIN_MENU_PATH)

func _on_quit_pressed() -> void:
	if _modal_open: return
	get_tree().quit()
