extends Control

const META_UPGRADE_UI_SCENE := preload("res://scenes/ui/meta_upgrade_ui.tscn")
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const CREDITS_PANEL_SCENE := preload("res://scenes/ui/credits_panel.tscn")
const GAME_SCENE_PATH := "res://scenes/main.tscn"
const MenuInputHelper = preload("res://scripts/ui/menu_input_helper.gd")
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")
const INTRO_LOGO_DURATION: float = 0.78
const INTRO_BUTTON_DURATION: float = 0.46
const INTRO_BUTTON_DELAY: float = 0.36
const INTRO_BUTTON_STAGGER: float = 0.11
const WINDOWS_RUNTIME_DLLS := [
	"liblimboai.windows.template_release.x86_64.dll",
	"libdd3d.windows.template_release.x86_64.dll",
]
const GAME_SCENE_PROBE_PATHS := [
	"res://resources/environment/world_environment.tres",
	"res://resources/environment/camera_attributes.tres",
	"res://resources/ui/theme.tres",
	"res://scripts/camera/camera_controller.gd",
	"res://scripts/managers/enemy_spawner.gd",
	"res://scripts/managers/level_manager.gd",
	"res://scripts/managers/environment_preset_manager.gd",
	"res://scripts/world/decor/sea_decor_spawner.gd",
	"res://scripts/world/sea_sites/sea_site_spawner.gd",
	"res://scenes/ui/game_hud.tscn",
	"res://scenes/ui/ship_control_panel.tscn",
	"res://scenes/effects/ocean_plane.tscn",
	"res://scenes/effects/cloud_field.tscn",
	"res://scenes/ships/player_ship.tscn",
	"res://scenes/entities/soldiers/soldier.tscn",
	"res://scenes/ships/hulls/panok_hull.tscn",
	"res://scenes/ships/enemy_ship.tscn",
	"res://scenes/ships/enemy_melee_ship.tscn",
	"res://scenes/ships/enemy_gunner_ship.tscn",
	"res://scenes/ships/enemy_firepot_ship.tscn",
	"res://scenes/ships/boss_ship.tscn",
	"res://resources/ai/limbo/soldier_ai_pilot.tres",
	"res://resources/ai/limbo/enemy_gunner_ai_pilot.tres",
	"res://resources/ai/limbo/enemy_boarder_ai_pilot.tres",
	"res://resources/ai/limbo/enemy_firepot_ai_pilot.tres",
	"res://resources/ai/limbo/boss_ship_ai_pilot.tres",
]
const DEPENDENCY_PROBE_LIMIT := 96
const DEPENDENCY_PROBE_RECURSION_LIMIT := 3
@export var background_texture: Texture2D
@export var use_3d_background: bool = true
@export_range(0.0, 1.0, 0.01) var background_dim: float = 0.18
@export var fallback_version_text: String = "v0.4.0-alpha"

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
@onready var credits_button: Button = $ButtonBlock/CreditsButton
@onready var quit_button: Button = $ButtonBlock/QuitButton
@onready var version_label: Label = $VersionLabel
@onready var status_label: Label = $StatusLabel

var _modal_open: bool = false
var _starting: bool = false
var _menu_buttons: Array[Button] = []
var _focused_button_index: int = 0
var _intro_started: bool = false
var _dependency_probe_logged: Dictionary = {}
var _nav_repeater := MenuInputHelper.NavRepeater.new()
var _button_focus := MenuInputHelper.ButtonFocusNavigator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_startup_log()
	_append_startup_log("main menu ready; %s" % _describe_runtime_state())
	_apply_background_settings()
	_apply_ui_theme()
	_apply_localized_text()
	_play_menu_music()
	UiButtonAudio.wire_buttons(self)
	start_button.pressed.connect(_on_start_pressed)
	meta_button.pressed.connect(_on_meta_pressed)
	options_button.pressed.connect(_on_options_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	meta_button.visible = false
	quit_button.visible = OS.get_name() != "Web"
	_menu_buttons = [start_button, options_button, credits_button]
	if quit_button.visible:
		_menu_buttons.append(quit_button)
	_button_focus.configure(_menu_buttons, _on_menu_button_focus_changed, _can_mouse_focus_menu_button)
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


func _input(event: InputEvent) -> void:
	if _modal_open:
		return

	var nav := _nav_repeater.consume_event(event)
	if nav.y != 0:
		_move_menu_focus(nav.y)
		if get_viewport():
			get_viewport().set_input_as_handled()
		return
	if MenuInputHelper.is_navigation_axis_event(event):
		if get_viewport():
			get_viewport().set_input_as_handled()
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
	_button_focus.focus_first()
	_focused_button_index = _button_focus.get_focused_index()


func _move_menu_focus(direction: int) -> void:
	_button_focus.move_focus(direction)
	_focused_button_index = _button_focus.get_focused_index()


func _activate_focused_menu_button() -> void:
	_button_focus.activate_focused()


func _on_menu_button_focus_changed(_button: Button, _focused: bool) -> void:
	_focused_button_index = _button_focus.get_focused_index()


func _can_mouse_focus_menu_button() -> bool:
	return not _modal_open and not _starting


func _is_menu_prev_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_menu_prev_event(event)


func _is_menu_next_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_menu_next_event(event)


func _is_confirm_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_confirm_event(event)


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
	if is_instance_valid(status_label):
		NavalUiTheme.style_caption(status_label, 13, NavalUiTheme.TEXT_MUTED)
		status_label.visible = false
	for button in [start_button, meta_button, options_button, credits_button, quit_button]:
		_apply_compact_menu_button(button)


func _apply_localized_text() -> void:
	if is_instance_valid(eyebrow_label):
		eyebrow_label.text = LocaleManager.t("main_menu.eyebrow", "조선 수군 로그라이트 해전")
	if is_instance_valid(start_button):
		start_button.text = LocaleManager.t("main_menu.loading", "로딩 중...") if _starting else LocaleManager.t("main_menu.start", "시작")
	if is_instance_valid(meta_button):
		meta_button.text = LocaleManager.t("main_menu.meta", "업그레이드")
	if is_instance_valid(options_button):
		options_button.text = LocaleManager.t("main_menu.options", "옵션")
	if is_instance_valid(credits_button):
		credits_button.text = LocaleManager.t("main_menu.credits", "크레딧")
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
	if is_instance_valid(status_label):
		var status_width := roundi(lerpf(360.0, 520.0, density))
		status_label.offset_left = -status_width * 0.5
		status_label.offset_right = status_width * 0.5
		status_label.anchor_top = lerpf(0.81, 0.785, density)
		status_label.anchor_bottom = status_label.anchor_top
		status_label.offset_top = 0.0
		status_label.offset_bottom = roundi(lerpf(44.0, 52.0, density))
		NavalUiTheme.style_caption(status_label, roundi(lerpf(11.0, 13.0, density)), status_label.get_theme_color("font_color"))


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
	credits_button.disabled = disabled
	quit_button.disabled = disabled
	if not disabled:
		_focus_first_menu_button()

func _on_start_pressed() -> void:
	if _modal_open or _starting:
		return
	_starting = true
	_set_status_message(LocaleManager.t("main_menu.loading", "로딩 중..."), false)
	_set_buttons_disabled(true)
	if is_instance_valid(start_button):
		start_button.text = LocaleManager.t("main_menu.loading", "로딩 중...")
	await get_tree().process_frame

	var preflight_error := _get_start_preflight_error()
	if not preflight_error.is_empty():
		push_error("MainMenu: start preflight failed: %s" % preflight_error)
		_fail_start(preflight_error)
		return
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	_append_startup_log("start requested; changing scene with %s" % GAME_SCENE_PATH)
	print("[MainMenu] start requested; changing scene to %s on %s" % [GAME_SCENE_PATH, OS.get_name()])
	var error := _change_to_game_scene()
	if error != OK:
		var message := LocaleManager.t(
			"main_menu.start_failed_change_scene",
			"게임을 시작하지 못했습니다. 로그를 확인해 주세요. ({error})",
			{"error": error_string(error)}
		)
		push_error("MainMenu: failed to change to %s: %s" % [GAME_SCENE_PATH, error_string(error)])
		_append_startup_log("change_scene_to_file failed: %s" % error_string(error))
		_fail_start(message)
		return
	_append_startup_log("change_scene_to_file accepted")


func _fail_start(message: String) -> void:
	_starting = false
	_set_buttons_disabled(false)
	if is_instance_valid(start_button):
		start_button.text = LocaleManager.t("main_menu.start", "시작")
		start_button.grab_focus()
	_set_status_message(message, true)


func _set_status_message(message: String, is_error: bool) -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = message
	status_label.visible = not message.strip_edges().is_empty()
	var color := Color(0.95, 0.42, 0.34, 0.98) if is_error else NavalUiTheme.TEXT_MUTED
	status_label.add_theme_color_override("font_color", color)


func _get_start_preflight_error() -> String:
	if OS.get_name() == "Windows":
		var missing_dlls := _get_missing_windows_runtime_dlls()
		if not missing_dlls.is_empty():
			return LocaleManager.t(
				"main_menu.start_failed_windows_dlls",
				"Windows 배포 파일이 일부 없습니다. ZIP 압축을 풀고 EXE와 DLL을 같은 폴더에서 실행해 주세요. ({files})",
				{"files": ", ".join(missing_dlls)}
			)
	return ""


func _get_missing_windows_runtime_dlls() -> Array[String]:
	var missing: Array[String] = []
	var exe_dir := OS.get_executable_path().get_base_dir()
	if exe_dir.is_empty():
		return missing
	for dll_name in WINDOWS_RUNTIME_DLLS:
		var dll_path := exe_dir.path_join(dll_name)
		if not FileAccess.file_exists(dll_path):
			missing.append(dll_name)
	return missing


func _change_to_game_scene() -> Error:
	var packed_scene := _load_game_packed_scene(GAME_SCENE_PATH)
	if packed_scene != null:
		var packed_error := get_tree().change_scene_to_packed(packed_scene)
		if packed_error == OK:
			_append_startup_log("change_scene_to_packed accepted: %s" % GAME_SCENE_PATH)
			return OK
		_append_startup_log("change_scene_to_packed failed for %s: %s" % [GAME_SCENE_PATH, error_string(packed_error)])

	var error := get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if error == OK:
		_append_startup_log("change_scene_to_file accepted: %s" % GAME_SCENE_PATH)
		return OK

	_append_startup_log("change_scene_to_file failed for %s: %s" % [GAME_SCENE_PATH, error_string(error)])
	if error != ERR_CANT_OPEN:
		return error

	var exported_scene_path := _find_exported_resource_path(GAME_SCENE_PATH)
	if exported_scene_path.is_empty():
		_append_startup_log("exported fallback path not found for %s" % GAME_SCENE_PATH)
		return error

	_append_startup_log("trying exported fallback scene path: %s" % exported_scene_path)
	packed_scene = _load_game_packed_scene(exported_scene_path)
	if packed_scene != null:
		var packed_fallback_error := get_tree().change_scene_to_packed(packed_scene)
		if packed_fallback_error == OK:
			_append_startup_log("change_scene_to_packed accepted fallback: %s" % exported_scene_path)
			return OK
		_append_startup_log("change_scene_to_packed fallback failed: %s" % error_string(packed_fallback_error))

	var fallback_error := get_tree().change_scene_to_file(exported_scene_path)
	if fallback_error != OK:
		_append_startup_log("exported fallback failed: %s" % error_string(fallback_error))
	return fallback_error


func _load_game_packed_scene(scene_path: String) -> PackedScene:
	var exists := ResourceLoader.exists(scene_path, "PackedScene")
	_append_startup_log("ResourceLoader.exists(%s, PackedScene)=%s" % [scene_path, exists])
	var resource := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	if resource == null:
		_append_startup_log("ResourceLoader.load returned null: %s" % scene_path)
		_log_scene_dependency_probe(scene_path, 0)
		return null
	if not (resource is PackedScene):
		_append_startup_log("ResourceLoader.load returned %s, not PackedScene: %s" % [resource.get_class(), scene_path])
		return null
	_append_startup_log("ResourceLoader.load returned PackedScene: %s" % scene_path)
	return resource as PackedScene


func _log_scene_dependency_probe(scene_path: String, depth: int = 0) -> void:
	if _dependency_probe_logged.has(scene_path):
		return
	_dependency_probe_logged[scene_path] = true
	_append_startup_log("dependency probe begin: %s" % scene_path)
	var dependency_paths: Array[String] = []
	for dependency in ResourceLoader.get_dependencies(scene_path):
		var dependency_path := _extract_resource_path(str(dependency))
		if not dependency_path.is_empty() and not dependency_paths.has(dependency_path):
			dependency_paths.append(dependency_path)
	for path in GAME_SCENE_PROBE_PATHS:
		if not dependency_paths.has(path):
			dependency_paths.append(path)
	_append_startup_log("dependency probe count=%d" % dependency_paths.size())
	var probe_limit := mini(dependency_paths.size(), DEPENDENCY_PROBE_LIMIT)
	for i in range(probe_limit):
		_log_resource_probe(dependency_paths[i], depth + 1)
	if dependency_paths.size() > probe_limit:
		_append_startup_log("dependency probe truncated: %d more" % (dependency_paths.size() - probe_limit))
	_append_startup_log("dependency probe end: %s" % scene_path)


func _extract_resource_path(raw_dependency: String) -> String:
	if raw_dependency.begins_with("res://"):
		return raw_dependency
	for part in raw_dependency.split("::", false):
		var text := str(part).strip_edges()
		if text.begins_with("res://"):
			return text
	return ""


func _log_resource_probe(path: String, depth: int) -> void:
	var exists := ResourceLoader.exists(path)
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if resource == null:
		_append_startup_log("probe load null exists=%s path=%s" % [exists, path])
		if depth < DEPENDENCY_PROBE_RECURSION_LIMIT and (path.ends_with(".tscn") or path.ends_with(".scn") or path.ends_with(".tres") or path.ends_with(".res")):
			_log_scene_dependency_probe(path, depth + 1)
		return
	var resource_class := resource.get_class()
	if resource is PackedScene:
		var instance := (resource as PackedScene).instantiate()
		var instance_class := "null"
		if instance != null:
			instance_class = instance.get_class()
			instance.queue_free()
		_append_startup_log("probe load ok exists=%s class=%s instance=%s path=%s" % [exists, resource_class, instance_class, path])
		return
	_append_startup_log("probe load ok exists=%s class=%s path=%s" % [exists, resource_class, path])


func _find_exported_resource_path(source_path: String) -> String:
	var exported_root := DirAccess.open("res://.godot/exported")
	if exported_root == null:
		_append_startup_log("cannot open res://.godot/exported")
		return ""

	exported_root.list_dir_begin()
	var entry := exported_root.get_next()
	while not entry.is_empty():
		if exported_root.current_is_dir() and not entry.begins_with("."):
			var file_cache_path := "res://.godot/exported/%s/file_cache" % entry
			var mapped_path := _find_exported_resource_path_in_cache(file_cache_path, source_path)
			if not mapped_path.is_empty():
				exported_root.list_dir_end()
				return mapped_path
			mapped_path = _find_exported_scene_path_by_suffix("res://.godot/exported/%s" % entry, source_path)
			if not mapped_path.is_empty():
				exported_root.list_dir_end()
				return mapped_path
		entry = exported_root.get_next()
	exported_root.list_dir_end()
	return ""


func _find_exported_resource_path_in_cache(file_cache_path: String, source_path: String) -> String:
	var file := FileAccess.open(file_cache_path, FileAccess.READ)
	if file == null:
		_append_startup_log("cannot open export file_cache: %s" % file_cache_path)
		return ""

	while not file.eof_reached():
		var line := file.get_line()
		if not line.begins_with("%s::" % source_path):
			continue
		var parts := line.split("::", false)
		if parts.size() >= 4:
			return str(parts[3]).strip_edges()
	return ""


func _find_exported_scene_path_by_suffix(exported_dir_path: String, source_path: String) -> String:
	var exported_dir := DirAccess.open(exported_dir_path)
	if exported_dir == null:
		_append_startup_log("cannot open exported scene dir: %s" % exported_dir_path)
		return ""

	var expected_suffix := "-%s.scn" % source_path.get_file().get_basename()
	exported_dir.list_dir_begin()
	var entry := exported_dir.get_next()
	while not entry.is_empty():
		if not exported_dir.current_is_dir() and entry.ends_with(expected_suffix):
			exported_dir.list_dir_end()
			return exported_dir_path.path_join(entry)
		entry = exported_dir.get_next()
	exported_dir.list_dir_end()
	return ""


func _reset_startup_log() -> void:
	var file := FileAccess.open("user://startup.log", FileAccess.WRITE)
	if file == null:
		return
	file.store_line("[MainMenu] startup log")
	file.store_line("user_data_dir=%s" % OS.get_user_data_dir())


func _append_startup_log(message: String) -> void:
	var file := FileAccess.open("user://startup.log", FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("[%s] %s" % [Time.get_datetime_string_from_system(), message])


func _describe_runtime_state() -> String:
	var dll_state: Array[String] = []
	var pck_state := ""
	if OS.get_name() == "Windows":
		var exe_dir := OS.get_executable_path().get_base_dir()
		for dll_name in WINDOWS_RUNTIME_DLLS:
			dll_state.append("%s=%s" % [dll_name, FileAccess.file_exists(exe_dir.path_join(dll_name))])
		var pck_path := exe_dir.path_join("%s.pck" % OS.get_executable_path().get_file().get_basename())
		pck_state = " pck=%s:%s" % [pck_path, FileAccess.file_exists(pck_path)]
	return "os=%s exe=%s user=%s bt_player=%s behavior_tree=%s dlls=[%s]%s" % [
		OS.get_name(),
		OS.get_executable_path(),
		OS.get_user_data_dir(),
		ClassDB.class_exists("BTPlayer"),
		ClassDB.class_exists("BehaviorTree"),
		", ".join(dll_state),
		pck_state,
	]

func _on_meta_pressed() -> void:
	if _modal_open:
		return
	_modal_open = true
	_set_buttons_disabled(true)
	var ui = META_UPGRADE_UI_SCENE.instantiate()
	ui.title_text = LocaleManager.t("meta.title", "업그레이드")
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

func _on_credits_pressed() -> void:
	if _modal_open:
		return
	_modal_open = true
	_set_buttons_disabled(true)
	var ui = CREDITS_PANEL_SCENE.instantiate()
	add_child(ui)
	ui.closed.connect(func():
		_modal_open = false
		_set_buttons_disabled(false)
	)

func _on_quit_pressed() -> void:
	if _modal_open:
		return
	get_tree().quit()
