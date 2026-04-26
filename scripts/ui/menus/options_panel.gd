extends CanvasLayer

const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")

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
@onready var screen_fx_check: CheckBox = $Panel/Shell/Content/ScreenFxCheck
@onready var screen_fx_label: Label = $Panel/Shell/Content/ScreenFxRow/ScreenFxHeader/ScreenFxLabel
@onready var screen_fx_value_label: Label = $Panel/Shell/Content/ScreenFxRow/ScreenFxHeader/ScreenFxValue
@onready var screen_fx_slider: HSlider = $Panel/Shell/Content/ScreenFxRow/ScreenFxSlider
@onready var fullscreen_check: CheckBox = $Panel/Shell/Content/FullscreenCheck
@onready var shell: VBoxContainer = $Panel/Shell
@onready var content_box: VBoxContainer = $Panel/Shell/Content
@onready var footer: HBoxContainer = $Panel/Shell/Footer
@onready var back_button: Button = $Panel/Shell/Footer/BackButton

var _focusable_controls: Array[Control] = []
var _focused_control_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_apply_layout_density()
	_bind_slider(master_slider, "master_volume")
	_bind_slider(music_slider, "music_volume")
	_bind_slider(sfx_slider, "sfx_volume")
	_bind_slider(ui_slider, "ui_volume")
	master_slider.value = float(SaveManager.get_setting("master_volume", 0.85))
	music_slider.value = float(SaveManager.get_setting("music_volume", 0.75))
	sfx_slider.value = float(SaveManager.get_setting("sfx_volume", 0.85))
	ui_slider.value = float(SaveManager.get_setting("ui_volume", 0.85))
	screen_fx_check.text = "가장자리 집중 연출"
	screen_fx_check.button_pressed = SaveManager.get_setting("screen_edge_fx_enabled", true) == true
	screen_fx_check.toggled.connect(_on_screen_fx_toggled)
	screen_fx_slider.step = 0.05
	screen_fx_slider.value = float(SaveManager.get_setting("screen_edge_fx_strength", 0.75))
	screen_fx_slider.value_changed.connect(_on_screen_fx_strength_changed)
	fullscreen_check.button_pressed = SaveManager.get_setting("fullscreen", false) == true
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)
	_sync_screen_fx_controls()
	_setup_focus_navigation()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_layout_density)

func _apply_theme() -> void:
	if is_instance_valid(backdrop):
		backdrop.color = Color.WHITE
		backdrop.material = UiOverlayFx.make_vignette_material(
			Color(0.02, 0.03, 0.05, 0.82),
			Vector2(0.5, 0.48),
			0.86,
			0.36,
			0.18,
			0.18,
			Vector3(0.018, 0.024, 0.028)
		)
	if is_instance_valid(panel):
		ModalMenuSkin.apply_modal_shell(panel, title_label, subtitle_label, true)
	for label in [master_label, music_label, sfx_label, ui_label]:
		NavalUiTheme.style_body(label, 13)
	if is_instance_valid(screen_fx_label):
		NavalUiTheme.style_body(screen_fx_label, 13)
	if is_instance_valid(screen_fx_value_label):
		NavalUiTheme.style_gold(screen_fx_value_label, 13)
	if is_instance_valid(screen_fx_check):
		NavalUiTheme.apply_menu_toggle(screen_fx_check, 13)
	if is_instance_valid(fullscreen_check):
		NavalUiTheme.apply_menu_toggle(fullscreen_check, 13)
	for slider in [master_slider, music_slider, sfx_slider, ui_slider, screen_fx_slider]:
		NavalUiTheme.apply_slider(slider, NavalUiTheme.PANEL_BG_DARK, NavalUiTheme.STATUS_ACTIVE_BLUE, 4)
	if is_instance_valid(back_button):
		ModalMenuSkin.apply_action_button_theme(back_button, true, true)


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 680.0) / 260.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 620.0) / 220.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	if is_instance_valid(panel):
		panel.custom_minimum_size.x = roundi(clampf(viewport_size.x - 148.0, 396.0, 540.0))
	if is_instance_valid(shell):
		shell.add_theme_constant_override("separation", roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(content_box):
		content_box.add_theme_constant_override("separation", roundi(lerpf(12.0, 14.0, density)))
	if is_instance_valid(title_label):
		NavalUiTheme.style_display_title(title_label, roundi(lerpf(32.0, 40.0, density)))
	if is_instance_valid(subtitle_label):
		NavalUiTheme.style_caption(subtitle_label, roundi(lerpf(12.0, 13.0, density)), NavalUiTheme.TEXT_BODY)
	for label in [master_label, music_label, sfx_label, ui_label]:
		if is_instance_valid(label):
			NavalUiTheme.style_body(label, roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(screen_fx_label):
		NavalUiTheme.style_body(screen_fx_label, roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(screen_fx_value_label):
		NavalUiTheme.style_gold(screen_fx_value_label, roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(screen_fx_slider):
		screen_fx_slider.custom_minimum_size.y = roundi(lerpf(18.0, 22.0, density))
	if is_instance_valid(screen_fx_check):
		screen_fx_check.add_theme_font_size_override("font_size", roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(fullscreen_check):
		fullscreen_check.add_theme_font_size_override("font_size", roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(footer):
		footer.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(back_button):
		back_button.custom_minimum_size = Vector2(roundi(clampf(viewport_size.x * 0.26, 156.0, 180.0)), roundi(lerpf(40.0, 44.0, density)))


func _setup_focus_navigation() -> void:
	_focusable_controls = [
		master_slider,
		music_slider,
		sfx_slider,
		ui_slider,
		screen_fx_check,
		screen_fx_slider,
		fullscreen_check,
		back_button,
	]
	for i in range(_focusable_controls.size()):
		var control := _focusable_controls[i]
		if not is_instance_valid(control):
			continue
		control.focus_mode = Control.FOCUS_ALL
		control.focus_entered.connect(func():
			_focused_control_index = i
		)
	call_deferred("_focus_first_control")


func _focus_first_control() -> void:
	for i in range(_focusable_controls.size()):
		var control := _focusable_controls[i]
		if is_instance_valid(control) and control.visible:
			_focused_control_index = i
			control.grab_focus()
			return


func _move_focus_vertical(direction: int) -> void:
	if _focusable_controls.is_empty():
		return
	var control_count := _focusable_controls.size()
	for step in range(1, control_count + 1):
		var next_index := posmod(_focused_control_index + direction * step, control_count)
		var control := _focusable_controls[next_index]
		if is_instance_valid(control) and control.visible:
			_focused_control_index = next_index
			control.grab_focus()
			return

func _bind_slider(slider: HSlider, setting_key: String) -> void:
	slider.value_changed.connect(func(value: float):
		SaveManager.set_setting(setting_key, value, false)
		SaveManager.apply_settings()
	)

func _on_fullscreen_toggled(pressed: bool) -> void:
	SaveManager.set_setting("fullscreen", pressed, false)
	SaveManager.apply_settings()

func _on_screen_fx_toggled(pressed: bool) -> void:
	SaveManager.set_setting("screen_edge_fx_enabled", pressed, false)
	SaveManager.apply_settings()
	_sync_screen_fx_controls()

func _on_screen_fx_strength_changed(value: float) -> void:
	SaveManager.set_setting("screen_edge_fx_strength", value, false)
	SaveManager.apply_settings()
	_sync_screen_fx_controls()

func _sync_screen_fx_controls() -> void:
	var enabled: bool = screen_fx_check.button_pressed if is_instance_valid(screen_fx_check) else true
	if is_instance_valid(screen_fx_slider):
		screen_fx_slider.editable = enabled
		screen_fx_slider.modulate = Color.WHITE if enabled else Color(1.0, 1.0, 1.0, 0.45)
	if is_instance_valid(screen_fx_value_label):
		var strength_percent := int(round(screen_fx_slider.value * 100.0)) if is_instance_valid(screen_fx_slider) else 0
		var descriptor := _describe_screen_fx_strength(screen_fx_slider.value if is_instance_valid(screen_fx_slider) else 0.0)
		screen_fx_value_label.text = "꺼짐" if not enabled else "%s · %d%%" % [descriptor, strength_percent]
		screen_fx_value_label.modulate = Color.WHITE if enabled else Color(1.0, 1.0, 1.0, 0.5)


func _describe_screen_fx_strength(value: float) -> String:
	if value < 0.28:
		return "약하게"
	if value < 0.62:
		return "표준"
	return "강하게"

func _on_back_pressed() -> void:
	SaveManager.save_game()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_prev_event(event):
		_move_focus_vertical(-1)
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_next_event(event):
		_move_focus_vertical(1)
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
		if focused is CheckBox:
			(focused as CheckBox).button_pressed = not (focused as CheckBox).button_pressed
			if get_viewport():
				get_viewport().set_input_as_handled()
		elif focused is Button:
			(focused as Button).emit_signal("pressed")
			if get_viewport():
				get_viewport().set_input_as_handled()


func _is_prev_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or _is_physical_key_pressed(event, KEY_W)


func _is_next_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_down") or _is_physical_key_pressed(event, KEY_S)


func _is_confirm_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or _is_keycode_pressed(event, KEY_SPACE) or _is_keycode_pressed(event, KEY_ENTER) or _is_keycode_pressed(event, KEY_KP_ENTER)


func _is_physical_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keycode


func _is_keycode_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
