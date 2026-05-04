extends Control

const META_UPGRADE_UI_SCENE := preload("res://scenes/ui/meta_upgrade_ui.tscn")
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const GAME_SCENE_PATH := "res://scenes/main.tscn"
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")
const INTRO_LOGO_DURATION: float = 0.78
const INTRO_BUTTON_DURATION: float = 0.46
const INTRO_BUTTON_DELAY: float = 0.36
const INTRO_BUTTON_STAGGER: float = 0.11
@export var background_texture: Texture2D
@export var use_3d_background: bool = true
@export_range(0.0, 1.0, 0.01) var background_dim: float = 0.18
@export var fallback_version_text: String = "v0.1.0"

@onready var fleet_background: Node = get_node_or_null("MenuFleetBackground")
@onready var background_image: TextureRect = $BackgroundImage
@onready var background_overlay: ColorRect = $Background
@onready var title_block: VBoxContainer = $TitleBlock
@onready var eyebrow_label: Label = $TitleBlock/Eyebrow
@onready var title_logo: TextureRect = $TitleBlock/Title
@onready var button_block: VBoxContainer = $ButtonBlock
@onready var start_button: Button = $ButtonBlock/StartButton
@onready var meta_button: Button = $ButtonBlock/MetaButton
@onready var options_button: Button = $ButtonBlock/OptionsButton
@onready var quit_button: Button = $ButtonBlock/QuitButton
@onready var version_label: Label = $VersionLabel

var _modal_open: bool = false
var _menu_buttons: Array[Button] = []
var _focused_button_index: int = 0
var _intro_started: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_background_settings()
	_apply_ui_theme()
	_apply_localized_text()
	_play_menu_music()
	UiButtonAudio.wire_buttons(self)
	start_button.pressed.connect(_on_start_pressed)
	meta_button.pressed.connect(_on_meta_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.visible = OS.get_name() != "Web"
	_menu_buttons = [start_button, meta_button, options_button]
	if quit_button.visible:
		_menu_buttons.append(quit_button)
	_apply_layout_density()
	_refresh_version_label()
	SaveManager.apply_settings()
	if not LocaleManager.locale_changed.is_connected(_on_locale_changed):
		LocaleManager.locale_changed.connect(_on_locale_changed)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_layout_density)
	_focus_first_menu_button()
	call_deferred("_begin_intro")


func _exit_tree() -> void:
	_stop_menu_music()


func _play_menu_music() -> void:
	if is_instance_valid(AudioManager) and AudioManager.has_method("play_main_menu_music"):
		AudioManager.play_main_menu_music()


func _stop_menu_music() -> void:
	if is_instance_valid(AudioManager) and AudioManager.has_method("stop_main_menu_music"):
		AudioManager.stop_main_menu_music()


func _unhandled_input(event: InputEvent) -> void:
	if _modal_open:
		return
	if _is_menu_prev_event(event):
		_move_menu_focus(-1)
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_menu_next_event(event):
		_move_menu_focus(1)
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		_activate_focused_menu_button()
		if get_viewport():
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


func _apply_background_settings() -> void:
	var has_3d_background := use_3d_background and is_instance_valid(fleet_background)
	if is_instance_valid(fleet_background):
		fleet_background.visible = has_3d_background
	if is_instance_valid(background_image):
		background_image.texture = background_texture
		background_image.visible = not has_3d_background and background_texture != null
	if is_instance_valid(background_overlay):
		background_overlay.color = Color.WHITE
		background_overlay.material = UiOverlayFx.make_radial_darken_material(
				Color(0.02, 0.04, 0.07, clamp(background_dim, 0.0, 1.0)),
				0.42,
				0.84
			)


func _apply_ui_theme() -> void:
	NavalUiTheme.style_heading(eyebrow_label, 16)
	if is_instance_valid(eyebrow_label):
		eyebrow_label.visible = false
	if is_instance_valid(version_label):
		NavalUiTheme.style_caption(version_label, 13, NavalUiTheme.TEXT_MUTED)
	for button in [start_button, meta_button, options_button, quit_button]:
		_apply_compact_menu_button(button)


func _apply_localized_text() -> void:
	if is_instance_valid(eyebrow_label):
		eyebrow_label.text = LocaleManager.t("main_menu.eyebrow", "조선 수군 로그라이트 해전")
	if is_instance_valid(start_button):
		start_button.text = LocaleManager.t("main_menu.start", "시작")
	if is_instance_valid(meta_button):
		meta_button.text = LocaleManager.t("main_menu.meta", "업그레이드")
	if is_instance_valid(options_button):
		options_button.text = LocaleManager.t("main_menu.options", "옵션")
	if is_instance_valid(quit_button):
		quit_button.text = LocaleManager.t("main_menu.quit", "종료")


func _on_locale_changed(_locale: String) -> void:
	_apply_localized_text()


func _apply_compact_menu_button(button: Button) -> void:
	if not is_instance_valid(button):
		return
	ModalMenuSkin.apply_action_button_theme(button, button == start_button, true)


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 900.0) / 420.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 640.0) / 220.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	var title_half_width := roundi(lerpf(390.0, 520.0, density))
	var title_top := roundi(lerpf(28.0, 54.0, density))
	var title_bottom := roundi(lerpf(272.0, 420.0, density))
	var button_width := roundi(lerpf(260.0, 300.0, density))
	var button_height := roundi(lerpf(42.0, 48.0, density))
	var button_separation := roundi(lerpf(7.0, 9.0, density))

	if is_instance_valid(title_block):
		title_block.offset_left = -title_half_width
		title_block.offset_right = title_half_width
		title_block.offset_top = title_top
		title_block.offset_bottom = title_bottom
		title_block.add_theme_constant_override("separation", roundi(lerpf(6.0, 8.0, density)))
	if is_instance_valid(button_block):
		button_block.custom_minimum_size.x = button_width
		button_block.offset_left = -button_width * 0.5
		button_block.offset_right = button_width * 0.5
		button_block.anchor_top = lerpf(0.55, 0.535, density)
		button_block.anchor_bottom = button_block.anchor_top
		button_block.offset_bottom = roundi(lerpf(178.0, 204.0, density))
		button_block.add_theme_constant_override("separation", button_separation)
	if is_instance_valid(eyebrow_label):
		NavalUiTheme.style_heading(eyebrow_label, roundi(lerpf(13.0, 16.0, density)))
	if is_instance_valid(title_logo):
		title_logo.custom_minimum_size = Vector2(roundi(lerpf(540.0, 720.0, density)), roundi(lerpf(286.0, 382.0, density)))
	for button in _menu_buttons:
			if not is_instance_valid(button):
				continue
			button.custom_minimum_size.y = button_height
			button.add_theme_font_size_override("font_size", roundi(lerpf(15.0, 17.0, density)))
	if is_instance_valid(version_label):
		version_label.offset_left = roundi(lerpf(-92.0, -116.0, density))
		version_label.offset_top = roundi(lerpf(-30.0, -34.0, density))
		version_label.offset_right = -20.0
		version_label.offset_bottom = -12.0
		NavalUiTheme.style_caption(version_label, roundi(lerpf(11.0, 13.0, density)), NavalUiTheme.TEXT_MUTED)


func _begin_intro() -> void:
	if _intro_started:
		return
	_intro_started = true
	await get_tree().process_frame

	var title_target_y: float = title_block.position.y if is_instance_valid(title_block) else 0.0
	var button_target_y: float = button_block.position.y if is_instance_valid(button_block) else 0.0
	if is_instance_valid(title_block):
		title_block.modulate.a = 0.0
		title_block.position.y = title_target_y + 92.0
		title_block.scale = Vector2(0.92, 0.92)
		title_block.pivot_offset = title_block.size * 0.5
	if is_instance_valid(button_block):
		button_block.modulate.a = 0.0
		button_block.position.y = button_target_y + 56.0
		button_block.scale = Vector2(0.96, 0.96)
		button_block.pivot_offset = button_block.size * 0.5
	if is_instance_valid(version_label):
		version_label.modulate.a = 0.0

	for button in _menu_buttons:
		if not is_instance_valid(button):
			continue
		button.modulate.a = 0.0
		button.scale = Vector2(0.9, 0.9)
		button.pivot_offset = button.size * 0.5

	var intro := create_tween().set_parallel(true)
	if is_instance_valid(title_block):
		intro.tween_property(title_block, "modulate:a", 1.0, INTRO_LOGO_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		intro.tween_property(title_block, "position:y", title_target_y, INTRO_LOGO_DURATION).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		intro.tween_property(title_block, "scale", Vector2.ONE, INTRO_LOGO_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_instance_valid(button_block):
		intro.tween_property(button_block, "modulate:a", 1.0, INTRO_BUTTON_DURATION).set_delay(INTRO_BUTTON_DELAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		intro.tween_property(button_block, "position:y", button_target_y, INTRO_BUTTON_DURATION).set_delay(INTRO_BUTTON_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		intro.tween_property(button_block, "scale", Vector2.ONE, INTRO_BUTTON_DURATION).set_delay(INTRO_BUTTON_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_instance_valid(version_label):
		intro.tween_property(version_label, "modulate:a", 1.0, 0.34).set_delay(0.72).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	for i in range(_menu_buttons.size()):
		var button: Button = _menu_buttons[i]
		if not is_instance_valid(button):
			continue
		var delay := INTRO_BUTTON_DELAY + float(i) * INTRO_BUTTON_STAGGER
		intro.tween_property(button, "modulate:a", 1.0, INTRO_BUTTON_DURATION).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		intro.tween_property(button, "scale", Vector2.ONE, INTRO_BUTTON_DURATION).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	ui.title_text = LocaleManager.t("meta.title", "[항구] 영구 강화")
	ui.close_button_text = LocaleManager.t("meta.close_to_menu", "메뉴로 돌아가기")
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
