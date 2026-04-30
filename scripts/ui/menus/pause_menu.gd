extends CanvasLayer

const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")

const PANEL_ENTRY_SCALE := Vector2(0.965, 0.965)
const BUTTON_ENTRY_SCALE := Vector2(0.975, 0.975)
const BUTTON_FOCUS_SCALE := Vector2(1.018, 1.018)
const PANEL_ENTRY_DURATION := 0.24
const BUTTON_ENTRY_DURATION := 0.18
const BUTTON_ENTRY_DELAY := 0.055

@onready var background: ColorRect = $Background
@onready var panel_container: PanelContainer = $Center/Panel
@onready var panel_margin: MarginContainer = $Center/Panel/Margin
@onready var root_vbox: VBoxContainer = $Center/Panel/Margin/VBox
@onready var eyebrow_wrap: PanelContainer = $Center/Panel/Margin/VBox/EyebrowWrap
@onready var eyebrow_label: Label = $Center/Panel/Margin/VBox/EyebrowWrap/Eyebrow
@onready var title_label: Label = $Center/Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Center/Panel/Margin/VBox/Subtitle
@onready var divider: ColorRect = $Center/Panel/Margin/VBox/Divider
@onready var buttons_box: VBoxContainer = $Center/Panel/Margin/VBox/Buttons
@onready var resume_btn: Button = $Center/Panel/Margin/VBox/Buttons/ResumeBtn
@onready var options_btn: Button = $Center/Panel/Margin/VBox/Buttons/OptionsBtn
@onready var main_menu_btn: Button = $Center/Panel/Margin/VBox/Buttons/MainMenuBtn
@onready var quit_btn: Button = $Center/Panel/Margin/VBox/Buttons/QuitBtn
@onready var footer_hint_label: Label = $Center/Panel/Margin/VBox/FooterHint

var _modal_open: bool = false
var _menu_buttons: Array[Button] = []
var _focused_button_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	_apply_background_fx()
	_apply_ui_theme()
	UiButtonAudio.wire_buttons(self)

	resume_btn.pressed.connect(_on_resume_pressed)
	options_btn.pressed.connect(_on_options_pressed)
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	if OS.get_name() == "Web":
		quit_btn.visible = false

	_menu_buttons = [resume_btn, options_btn, main_menu_btn]
	if quit_btn.visible:
		_menu_buttons.append(quit_btn)
	_apply_layout_density()
	if not LocaleManager.locale_changed.is_connected(_on_locale_changed):
		LocaleManager.locale_changed.connect(_on_locale_changed)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_layout_density)
	_wire_button_interactions()
	call_deferred("_begin_intro")

func _apply_ui_theme() -> void:
	ModalMenuSkin.apply_pause_shell(
		panel_container,
		eyebrow_wrap,
		eyebrow_label,
		title_label,
		subtitle_label,
		divider,
		footer_hint_label
	)
	if is_instance_valid(eyebrow_label):
		eyebrow_label.text = LocaleManager.t("pause.eyebrow", "항해 정지")
	if is_instance_valid(title_label):
		title_label.text = LocaleManager.t("pause.title", "일시정지")
	if is_instance_valid(subtitle_label):
		subtitle_label.text = LocaleManager.t("pause.subtitle", "전투와 항해가 잠시 멈췄습니다")
	if is_instance_valid(footer_hint_label):
		footer_hint_label.text = LocaleManager.t("pause.footer", "ESC 복귀 · 방향키 또는 마우스로 선택")
	ModalMenuSkin.decorate_pause_button(resume_btn, LocaleManager.t("pause.resume", "계속하기"), LocaleManager.t("pause.resume.desc", "현재 전투와 항해로 돌아갑니다"), "ESC", true)
	ModalMenuSkin.decorate_pause_button(options_btn, LocaleManager.t("pause.options", "설정"), LocaleManager.t("pause.options.desc", "소리와 입력, 표시 옵션을 조정합니다"), "", false)
	ModalMenuSkin.decorate_pause_button(main_menu_btn, LocaleManager.t("pause.main_menu", "메인 메뉴"), LocaleManager.t("pause.main_menu.desc", "항구 화면으로 나가고 현재 항해를 정리합니다"), "", false)
	ModalMenuSkin.decorate_pause_button(quit_btn, LocaleManager.t("pause.quit", "게임 종료"), LocaleManager.t("pause.quit.desc", "현재 세션을 마치고 프로그램을 종료합니다"), "", false)

	for button in [resume_btn, options_btn, main_menu_btn, quit_btn]:
		ModalMenuSkin.apply_pause_button_theme(button, button == resume_btn)


func _on_locale_changed(_locale: String) -> void:
	_apply_ui_theme()


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var height_fit: float = clampf((viewport_size.y - 760.0) / 220.0, 0.0, 1.0)
	var width_fit: float = clampf((viewport_size.x - 620.0) / 240.0, 0.0, 1.0)
	var density: float = min(height_fit, width_fit)

	if is_instance_valid(panel_container):
		panel_container.custom_minimum_size.x = roundi(clampf(viewport_size.x - 168.0, 396.0, 432.0))
	if is_instance_valid(panel_margin):
		panel_margin.add_theme_constant_override("margin_left", roundi(lerpf(20.0, 24.0, density)))
		panel_margin.add_theme_constant_override("margin_top", roundi(lerpf(20.0, 24.0, density)))
		panel_margin.add_theme_constant_override("margin_right", roundi(lerpf(20.0, 24.0, density)))
		panel_margin.add_theme_constant_override("margin_bottom", roundi(lerpf(18.0, 22.0, density)))
	if is_instance_valid(root_vbox):
		root_vbox.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(buttons_box):
		buttons_box.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", roundi(lerpf(44.0, 52.0, density)))
	if is_instance_valid(subtitle_label):
		subtitle_label.add_theme_font_size_override("font_size", roundi(lerpf(13.0, 14.0, density)))
	if is_instance_valid(footer_hint_label):
		footer_hint_label.add_theme_font_size_override("font_size", roundi(lerpf(9.0, 10.0, density)))
	for button in _menu_buttons:
		if not is_instance_valid(button):
			continue
		button.custom_minimum_size.y = roundi(lerpf(60.0, 68.0, density))
		var button_title := button.get_meta("title_label", null) as Label
		var button_subtitle := button.get_meta("subtitle_label", null) as Label
		var button_hint := button.get_meta("hint_label", null) as Label
		if is_instance_valid(button_title):
			button_title.add_theme_font_size_override("font_size", roundi(lerpf(18.0, 19.0, density)))
		if is_instance_valid(button_subtitle):
			button_subtitle.add_theme_font_size_override("font_size", roundi(lerpf(9.0, 10.0, density)))
		if is_instance_valid(button_hint):
			button_hint.add_theme_font_size_override("font_size", roundi(lerpf(9.0, 10.0, density)))

func _wire_button_interactions() -> void:
	for button in _menu_buttons:
		button.focus_entered.connect(func():
			var idx := _menu_buttons.find(button)
			if idx != -1:
				_focused_button_index = idx
			_animate_button_focus(button, true)
		)
		button.focus_exited.connect(func(): _animate_button_focus(button, false))
		button.mouse_entered.connect(func():
			if not _modal_open and button.visible and not button.disabled:
				button.grab_focus()
		)


func _focus_first_pause_button() -> void:
	for i in range(_menu_buttons.size()):
		var button: Button = _menu_buttons[i]
		if is_instance_valid(button) and button.visible and not button.disabled:
			_focused_button_index = i
			button.grab_focus()
			return


func _move_pause_focus(direction: int) -> void:
	if _menu_buttons.is_empty():
		return
	var button_count := _menu_buttons.size()
	for step in range(1, button_count + 1):
		var next_index := posmod(_focused_button_index + direction * step, button_count)
		var button: Button = _menu_buttons[next_index]
		if is_instance_valid(button) and button.visible and not button.disabled:
			_focused_button_index = next_index
			button.grab_focus()
			return


func _activate_focused_pause_button() -> void:
	if _focused_button_index < 0 or _focused_button_index >= _menu_buttons.size():
		_focus_first_pause_button()
		return
	var button := _menu_buttons[_focused_button_index]
	if not is_instance_valid(button) or not button.visible or button.disabled:
		return
	button.emit_signal("pressed")

func _begin_intro() -> void:
	if not is_instance_valid(panel_container):
		return
	panel_container.pivot_offset = panel_container.size * 0.5
	for button in _menu_buttons:
		button.pivot_offset = button.size * 0.5
		button.modulate = Color(1.0, 1.0, 1.0, 0.0)
		button.scale = BUTTON_ENTRY_SCALE
	background.modulate.a = 0.0
	panel_container.modulate.a = 0.0
	panel_container.scale = PANEL_ENTRY_SCALE
	footer_hint_label.modulate.a = 0.0

	var intro := create_tween().set_parallel(true)
	intro.tween_property(background, "modulate:a", 1.0, PANEL_ENTRY_DURATION)
	intro.tween_property(panel_container, "modulate:a", 1.0, PANEL_ENTRY_DURATION)
	intro.tween_property(panel_container, "scale", Vector2.ONE, PANEL_ENTRY_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for i in range(_menu_buttons.size()):
		var button := _menu_buttons[i]
		var button_tween := create_tween()
		button_tween.tween_interval(0.06 + BUTTON_ENTRY_DELAY * float(i))
		button_tween.set_parallel(true)
		button_tween.tween_property(button, "modulate:a", 1.0, BUTTON_ENTRY_DURATION)
		button_tween.tween_property(button, "scale", Vector2.ONE, BUTTON_ENTRY_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var footer_tween := create_tween()
	footer_tween.tween_interval(0.06 + BUTTON_ENTRY_DELAY * float(_menu_buttons.size()) + 0.04)
	footer_tween.tween_property(footer_hint_label, "modulate:a", 1.0, 0.18)

	call_deferred("_focus_first_pause_button")

func _animate_button_focus(button: Button, focused: bool) -> void:
	if not is_instance_valid(button):
		return
	ModalMenuSkin.set_pause_button_content_state(button, focused)
	var tween := create_tween()
	tween.tween_property(button, "scale", BUTTON_FOCUS_SCALE if focused else Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _apply_background_fx() -> void:
	if not is_instance_valid(background):
		return
	background.material = UiOverlayFx.make_vignette_material(
		Color(0.02, 0.03, 0.05, 0.84),
		Vector2(0.5, 0.48),
		0.86,
		0.36,
		0.18,
		0.18,
		Vector3(0.018, 0.024, 0.028)
	)

func _unhandled_input(event: InputEvent) -> void:
	if _modal_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_resume_pressed()
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_menu_prev_event(event):
		_move_pause_focus(-1)
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_menu_next_event(event):
		_move_pause_focus(1)
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		_activate_focused_pause_button()
		if get_viewport():
			get_viewport().set_input_as_handled()

func _on_resume_pressed() -> void:
	if _modal_open:
		return
	get_tree().paused = false
	queue_free()

func _on_options_pressed() -> void:
	if _modal_open:
		return
	_modal_open = true
	var ui = OPTIONS_PANEL_SCENE.instantiate()
	add_child(ui)
	ui.closed.connect(func():
		_modal_open = false
		call_deferred("_focus_first_pause_button")
	)

func _on_main_menu_pressed() -> void:
	if _modal_open:
		return
	get_tree().paused = false
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	get_tree().change_scene_to_file(MAIN_MENU_PATH)

func _on_quit_pressed() -> void:
	if _modal_open:
		return
	get_tree().quit()


func _is_menu_prev_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or _is_physical_key_pressed(event, KEY_W) or _is_physical_key_pressed(event, KEY_A)


func _is_menu_next_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_down") or _is_physical_key_pressed(event, KEY_S) or _is_physical_key_pressed(event, KEY_D)


func _is_confirm_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or _is_keycode_pressed(event, KEY_SPACE) or _is_keycode_pressed(event, KEY_ENTER) or _is_keycode_pressed(event, KEY_KP_ENTER)


func _is_physical_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keycode


func _is_keycode_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
