extends CanvasLayer

const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const MenuInputHelper = preload("res://scripts/ui/menu_input_helper.gd")
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
var _content_scroll: ScrollContainer = null
var _content_margin: MarginContainer = null
var _language_row: VBoxContainer = null
var _language_label: Label = null
var _language_option: OptionButton = null
var _syncing_language_option: bool = false
var _performance_row: VBoxContainer = null
var _performance_label: Label = null
var _performance_option: OptionButton = null
var _syncing_performance_option: bool = false
var _sail_control_row: VBoxContainer = null
var _sail_control_label: Label = null
var _sail_control_option: OptionButton = null
var _syncing_sail_control_option: bool = false
var _control_scheme_row: VBoxContainer = null
var _control_scheme_label: Label = null
var _control_scheme_option: OptionButton = null
var _syncing_control_scheme_option: bool = false
var _gamepad_confirm_row: VBoxContainer = null
var _gamepad_confirm_label: Label = null
var _gamepad_confirm_option: OptionButton = null
var _syncing_gamepad_confirm_option: bool = false
var _nav_repeater := MenuInputHelper.NavRepeater.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_wrap_content_in_scroll_container()
	_create_language_controls()
	_create_performance_controls()
	_create_sail_control_controls()
	_create_control_scheme_controls()
	_create_gamepad_confirm_controls()
	_apply_theme()
	_apply_layout_density()
	UiButtonAudio.wire_buttons(self)
	_bind_slider(master_slider, "master_volume")
	_bind_slider(music_slider, "music_volume")
	_bind_slider(sfx_slider, "sfx_volume")
	_bind_slider(ui_slider, "ui_volume")
	master_slider.value = float(SaveManager.get_setting("master_volume", 0.85))
	music_slider.value = float(SaveManager.get_setting("music_volume", 0.75))
	sfx_slider.value = float(SaveManager.get_setting("sfx_volume", 0.85))
	ui_slider.value = float(SaveManager.get_setting("ui_volume", 0.85))
	screen_fx_check.button_pressed = SaveManager.get_setting("screen_edge_fx_enabled", true) == true
	screen_fx_check.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	screen_fx_check.toggled.connect(_on_screen_fx_toggled)
	screen_fx_slider.step = 0.05
	screen_fx_slider.value = float(SaveManager.get_setting("screen_edge_fx_strength", 0.75))
	screen_fx_slider.value_changed.connect(_on_screen_fx_strength_changed)
	fullscreen_check.button_pressed = SaveManager.get_setting("fullscreen", false) == true
	fullscreen_check.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(_on_back_pressed)
	_populate_language_options()
	_populate_performance_options()
	_populate_sail_control_options()
	_populate_control_scheme_options()
	_populate_gamepad_confirm_options()
	_apply_localized_text()
	_sync_screen_fx_controls()
	_setup_focus_navigation()
	if not LocaleManager.locale_changed.is_connected(_on_locale_changed):
		LocaleManager.locale_changed.connect(_on_locale_changed)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_layout_density)


func _wrap_content_in_scroll_container() -> void:
	if not is_instance_valid(shell) or not is_instance_valid(content_box):
		return
	if content_box.get_parent() is MarginContainer and content_box.get_parent().get_parent() is ScrollContainer:
		_content_margin = content_box.get_parent() as MarginContainer
		_content_scroll = _content_margin.get_parent() as ScrollContainer
		return
	if content_box.get_parent() is ScrollContainer:
		_content_scroll = content_box.get_parent() as ScrollContainer
		return
	if content_box.get_parent() != shell:
		return
	var content_index := content_box.get_index()
	shell.remove_child(content_box)
	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "ContentScroll"
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.follow_focus = true
	shell.add_child(_content_scroll)
	shell.move_child(_content_scroll, content_index)
	_content_margin = MarginContainer.new()
	_content_margin.name = "ContentMargin"
	_content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.add_child(_content_margin)
	_content_margin.add_child(content_box)
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _create_language_controls() -> void:
	if is_instance_valid(_language_option) or not is_instance_valid(content_box):
		return
	_language_row = VBoxContainer.new()
	_language_row.name = "LanguageRow"
	_language_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.name = "LanguageHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	_language_row.add_child(header)

	_language_label = Label.new()
	_language_label.name = "LanguageLabel"
	_language_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_language_label)

	_language_option = OptionButton.new()
	_language_option.name = "LanguageOption"
	_language_option.custom_minimum_size = Vector2(172, 34)
	_language_option.focus_mode = Control.FOCUS_ALL
	_language_option.size_flags_horizontal = Control.SIZE_SHRINK_END
	_language_option.item_selected.connect(_on_language_selected)
	header.add_child(_language_option)

	content_box.add_child(_language_row)
	var ui_row := ui_slider.get_parent()
	if is_instance_valid(ui_row) and ui_row.get_parent() == content_box:
		content_box.move_child(_language_row, ui_row.get_index() + 1)


func _create_sail_control_controls() -> void:
	if is_instance_valid(_sail_control_option) or not is_instance_valid(content_box):
		return
	_sail_control_row = VBoxContainer.new()
	_sail_control_row.name = "SailControlRow"
	_sail_control_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.name = "SailControlHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	_sail_control_row.add_child(header)

	_sail_control_label = Label.new()
	_sail_control_label.name = "SailControlLabel"
	_sail_control_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_sail_control_label)

	_sail_control_option = OptionButton.new()
	_sail_control_option.name = "SailControlOption"
	_sail_control_option.custom_minimum_size = Vector2(172, 34)
	_sail_control_option.focus_mode = Control.FOCUS_ALL
	_sail_control_option.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sail_control_option.item_selected.connect(_on_sail_control_selected)
	header.add_child(_sail_control_option)

	content_box.add_child(_sail_control_row)
	if is_instance_valid(_performance_row) and _performance_row.get_parent() == content_box:
		content_box.move_child(_sail_control_row, _performance_row.get_index() + 1)


func _create_performance_controls() -> void:
	if is_instance_valid(_performance_option) or not is_instance_valid(content_box):
		return
	_performance_row = VBoxContainer.new()
	_performance_row.name = "PerformanceRow"
	_performance_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.name = "PerformanceHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	_performance_row.add_child(header)

	_performance_label = Label.new()
	_performance_label.name = "PerformanceLabel"
	_performance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_performance_label)

	_performance_option = OptionButton.new()
	_performance_option.name = "PerformanceOption"
	_performance_option.custom_minimum_size = Vector2(172, 34)
	_performance_option.focus_mode = Control.FOCUS_ALL
	_performance_option.size_flags_horizontal = Control.SIZE_SHRINK_END
	_performance_option.item_selected.connect(_on_performance_selected)
	header.add_child(_performance_option)

	content_box.add_child(_performance_row)
	if is_instance_valid(_language_row) and _language_row.get_parent() == content_box:
		content_box.move_child(_performance_row, _language_row.get_index() + 1)


func _create_control_scheme_controls() -> void:
	if is_instance_valid(_control_scheme_option) or not is_instance_valid(content_box):
		return
	_control_scheme_row = VBoxContainer.new()
	_control_scheme_row.name = "ControlSchemeRow"
	_control_scheme_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.name = "ControlSchemeHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	_control_scheme_row.add_child(header)

	_control_scheme_label = Label.new()
	_control_scheme_label.name = "ControlSchemeLabel"
	_control_scheme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_control_scheme_label)

	_control_scheme_option = OptionButton.new()
	_control_scheme_option.name = "ControlSchemeOption"
	_control_scheme_option.custom_minimum_size = Vector2(172, 34)
	_control_scheme_option.focus_mode = Control.FOCUS_ALL
	_control_scheme_option.size_flags_horizontal = Control.SIZE_SHRINK_END
	_control_scheme_option.item_selected.connect(_on_control_scheme_selected)
	header.add_child(_control_scheme_option)

	content_box.add_child(_control_scheme_row)
	if is_instance_valid(_sail_control_row) and _sail_control_row.get_parent() == content_box:
		content_box.move_child(_control_scheme_row, _sail_control_row.get_index() + 1)


func _create_gamepad_confirm_controls() -> void:
	if is_instance_valid(_gamepad_confirm_option) or not is_instance_valid(content_box):
		return
	_gamepad_confirm_row = VBoxContainer.new()
	_gamepad_confirm_row.name = "GamepadConfirmRow"
	_gamepad_confirm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.name = "GamepadConfirmHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	_gamepad_confirm_row.add_child(header)

	_gamepad_confirm_label = Label.new()
	_gamepad_confirm_label.name = "GamepadConfirmLabel"
	_gamepad_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_gamepad_confirm_label)

	_gamepad_confirm_option = OptionButton.new()
	_gamepad_confirm_option.name = "GamepadConfirmOption"
	_gamepad_confirm_option.custom_minimum_size = Vector2(172, 34)
	_gamepad_confirm_option.focus_mode = Control.FOCUS_ALL
	_gamepad_confirm_option.size_flags_horizontal = Control.SIZE_SHRINK_END
	_gamepad_confirm_option.item_selected.connect(_on_gamepad_confirm_selected)
	header.add_child(_gamepad_confirm_option)

	content_box.add_child(_gamepad_confirm_row)
	if is_instance_valid(_control_scheme_row) and _control_scheme_row.get_parent() == content_box:
		content_box.move_child(_gamepad_confirm_row, _control_scheme_row.get_index() + 1)


func _populate_language_options() -> void:
	if not is_instance_valid(_language_option):
		return
	_syncing_language_option = true
	_language_option.clear()
	var locales := LocaleManager.get_supported_locales()
	var selected_index := 0
	for i in range(locales.size()):
		var locale := str(locales[i])
		_language_option.add_item(LocaleManager.get_locale_label(locale), i)
		_language_option.set_item_metadata(i, locale)
		if locale == LocaleManager.get_current_locale():
			selected_index = i
	_language_option.select(selected_index)
	_syncing_language_option = false


func _populate_sail_control_options() -> void:
	if not is_instance_valid(_sail_control_option):
		return
	_syncing_sail_control_option = true
	_sail_control_option.clear()
	var modes: Array[String] = ["manual", "auto"]
	var selected_mode := str(SaveManager.get_setting("sail_control_mode", "manual"))
	var selected_index := 0
	for i in range(modes.size()):
		var mode: String = modes[i]
		var label_key := "options.sail_control.%s" % mode
		var fallback := "수동" if mode == "manual" else "자동"
		_sail_control_option.add_item(LocaleManager.t(label_key, fallback), i)
		_sail_control_option.set_item_metadata(i, mode)
		if mode == selected_mode:
			selected_index = i
	_sail_control_option.select(selected_index)
	_syncing_sail_control_option = false


func _populate_performance_options() -> void:
	if not is_instance_valid(_performance_option):
		return
	_syncing_performance_option = true
	_performance_option.clear()
	var modes: Array[String] = ["quality", "balanced", "performance"]
	var selected_mode := str(SaveManager.get_setting("performance_preset", "quality"))
	var selected_index := 0
	for i in range(modes.size()):
		var mode: String = modes[i]
		var label_key := "options.performance_preset.%s" % mode
		var fallback := "품질"
		if mode == "balanced":
			fallback = "균형"
		elif mode == "performance":
			fallback = "성능"
		_performance_option.add_item(LocaleManager.t(label_key, fallback), i)
		_performance_option.set_item_metadata(i, mode)
		if mode == selected_mode:
			selected_index = i
	_performance_option.select(selected_index)
	_syncing_performance_option = false


func _populate_control_scheme_options() -> void:
	if not is_instance_valid(_control_scheme_option):
		return
	_syncing_control_scheme_option = true
	_control_scheme_option.clear()
	var modes: Array[String] = ["ship", "screen"]
	var selected_mode := str(SaveManager.get_setting("control_scheme", "ship"))
	var selected_index := 0
	for i in range(modes.size()):
		var mode: String = modes[i]
		var label_key := "options.control_scheme.%s" % mode
		var fallback := "배 기준" if mode == "ship" else "화면 기준"
		_control_scheme_option.add_item(LocaleManager.t(label_key, fallback), i)
		_control_scheme_option.set_item_metadata(i, mode)
		if mode == selected_mode:
			selected_index = i
	_control_scheme_option.select(selected_index)
	_syncing_control_scheme_option = false


func _populate_gamepad_confirm_options() -> void:
	if not is_instance_valid(_gamepad_confirm_option):
		return
	_syncing_gamepad_confirm_option = true
	_gamepad_confirm_option.clear()
	var positions: Array[String] = ["bottom", "right"]
	var selected_position := str(SaveManager.get_setting("gamepad_confirm_button", "bottom"))
	var selected_index := 0
	for i in range(positions.size()):
		var position: String = positions[i]
		var label_key := "options.gamepad_confirm_button.%s" % position
		var fallback := "아래쪽" if position == "bottom" else "오른쪽"
		_gamepad_confirm_option.add_item(LocaleManager.t(label_key, fallback), i)
		_gamepad_confirm_option.set_item_metadata(i, position)
		if position == selected_position:
			selected_index = i
	_gamepad_confirm_option.select(selected_index)
	_syncing_gamepad_confirm_option = false


func _apply_localized_text() -> void:
	if is_instance_valid(title_label):
		title_label.text = LocaleManager.t("options.title", "설정")
	if is_instance_valid(subtitle_label):
		subtitle_label.text = LocaleManager.t("options.subtitle", "음향과 화면 모드를 조정합니다.")
	if is_instance_valid(master_label):
		master_label.text = LocaleManager.t("options.master_volume", "전체 음량")
	if is_instance_valid(music_label):
		music_label.text = LocaleManager.t("options.music_volume", "음악")
	if is_instance_valid(sfx_label):
		sfx_label.text = LocaleManager.t("options.sfx_volume", "효과음")
	if is_instance_valid(ui_label):
		ui_label.text = LocaleManager.t("options.ui_volume", "UI")
	if is_instance_valid(_language_label):
		_language_label.text = LocaleManager.t("options.language", "언어")
	if is_instance_valid(_performance_label):
		_performance_label.text = LocaleManager.t("options.performance_preset", "성능 설정")
	if is_instance_valid(_sail_control_label):
		_sail_control_label.text = LocaleManager.t("options.sail_control", "돛 조절")
	if is_instance_valid(_control_scheme_label):
		_control_scheme_label.text = LocaleManager.t("options.control_scheme", "조작 방식")
	if is_instance_valid(_gamepad_confirm_label):
		_gamepad_confirm_label.text = LocaleManager.t("options.gamepad_confirm_button", "패드 확인 버튼")
	if is_instance_valid(screen_fx_check):
		screen_fx_check.text = LocaleManager.t("options.screen_fx_enabled", "가장자리 집중 연출")
	if is_instance_valid(screen_fx_label):
		screen_fx_label.text = LocaleManager.t("options.screen_fx_strength", "가장자리 연출 강도")
	if is_instance_valid(fullscreen_check):
		fullscreen_check.text = LocaleManager.t("options.fullscreen", "전체화면")
	if is_instance_valid(back_button):
		back_button.text = LocaleManager.t("options.close", "옵션 닫기")
	_sync_screen_fx_controls()


func _on_locale_changed(_locale: String) -> void:
	_populate_language_options()
	_populate_performance_options()
	_populate_sail_control_options()
	_populate_control_scheme_options()
	_populate_gamepad_confirm_options()
	_apply_localized_text()


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
	for label in [master_label, music_label, sfx_label, ui_label, _language_label, _performance_label, _sail_control_label, _control_scheme_label, _gamepad_confirm_label]:
		if not is_instance_valid(label):
			continue
		NavalUiTheme.style_body(label, 13)
	if is_instance_valid(screen_fx_label):
		NavalUiTheme.style_body(screen_fx_label, 13)
	if is_instance_valid(screen_fx_value_label):
		NavalUiTheme.style_gold(screen_fx_value_label, 13)
	if is_instance_valid(screen_fx_check):
		NavalUiTheme.apply_menu_toggle(screen_fx_check, 13)
	if is_instance_valid(fullscreen_check):
		NavalUiTheme.apply_menu_toggle(fullscreen_check, 13)
	if is_instance_valid(_language_option):
		ModalMenuSkin.apply_action_button_theme(_language_option, false, true)
	if is_instance_valid(_performance_option):
		ModalMenuSkin.apply_action_button_theme(_performance_option, false, true)
	if is_instance_valid(_sail_control_option):
		ModalMenuSkin.apply_action_button_theme(_sail_control_option, false, true)
	if is_instance_valid(_control_scheme_option):
		ModalMenuSkin.apply_action_button_theme(_control_scheme_option, false, true)
	if is_instance_valid(_gamepad_confirm_option):
		ModalMenuSkin.apply_action_button_theme(_gamepad_confirm_option, false, true)
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
		var panel_width := roundf(clampf(viewport_size.x - 148.0, 396.0, 560.0))
		var panel_height := roundf(clampf(viewport_size.y - 72.0, 480.0, 612.0))
		panel.offset_left = -panel_width * 0.5
		panel.offset_right = panel_width * 0.5
		panel.offset_top = -panel_height * 0.5
		panel.offset_bottom = panel_height * 0.5
	if is_instance_valid(shell):
		shell.add_theme_constant_override("separation", roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(content_box):
		content_box.add_theme_constant_override("separation", roundi(lerpf(12.0, 14.0, density)))
		content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_instance_valid(_content_scroll):
		_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content_scroll.custom_minimum_size.y = 0.0
	if is_instance_valid(_content_margin):
		_content_margin.add_theme_constant_override("margin_right", roundi(lerpf(10.0, 16.0, density)))
		_content_margin.add_theme_constant_override("margin_bottom", 2)
	if is_instance_valid(title_label):
		NavalUiTheme.style_display_title(title_label, roundi(lerpf(32.0, 40.0, density)))
	if is_instance_valid(subtitle_label):
		NavalUiTheme.style_caption(subtitle_label, roundi(lerpf(12.0, 13.0, density)), NavalUiTheme.TEXT_BODY)
	for label in [master_label, music_label, sfx_label, ui_label, _language_label, _performance_label, _sail_control_label, _control_scheme_label, _gamepad_confirm_label]:
		if is_instance_valid(label):
			NavalUiTheme.style_body(label, roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(screen_fx_label):
		NavalUiTheme.style_body(screen_fx_label, roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(screen_fx_value_label):
		NavalUiTheme.style_gold(screen_fx_value_label, roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(screen_fx_slider):
		screen_fx_slider.custom_minimum_size.y = roundi(lerpf(18.0, 22.0, density))
	if is_instance_valid(_language_option):
		_language_option.custom_minimum_size = Vector2(roundf(lerpf(154.0, 172.0, density)), roundf(lerpf(32.0, 34.0, density)))
		_language_option.add_theme_font_size_override("font_size", roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(_performance_option):
		_performance_option.custom_minimum_size = Vector2(roundf(lerpf(154.0, 172.0, density)), roundf(lerpf(32.0, 34.0, density)))
		_performance_option.add_theme_font_size_override("font_size", roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(_sail_control_option):
		_sail_control_option.custom_minimum_size = Vector2(roundf(lerpf(154.0, 172.0, density)), roundf(lerpf(32.0, 34.0, density)))
		_sail_control_option.add_theme_font_size_override("font_size", roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(_control_scheme_option):
		_control_scheme_option.custom_minimum_size = Vector2(roundf(lerpf(154.0, 172.0, density)), roundf(lerpf(32.0, 34.0, density)))
		_control_scheme_option.add_theme_font_size_override("font_size", roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(_gamepad_confirm_option):
		_gamepad_confirm_option.custom_minimum_size = Vector2(roundf(lerpf(154.0, 172.0, density)), roundf(lerpf(32.0, 34.0, density)))
		_gamepad_confirm_option.add_theme_font_size_override("font_size", roundi(lerpf(12.0, 13.0, density)))
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
		_language_option,
		_performance_option,
		_sail_control_option,
		_control_scheme_option,
		_gamepad_confirm_option,
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
			_scroll_control_into_view(control)
		)
	call_deferred("_focus_first_control")


func _focus_first_control() -> void:
	for i in range(_focusable_controls.size()):
		var control := _focusable_controls[i]
		if is_instance_valid(control) and control.visible:
			_focused_control_index = i
			control.grab_focus()
			_scroll_control_into_view(control)
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
			_scroll_control_into_view(control)
			return


func _scroll_control_into_view(control: Control) -> void:
	if not is_instance_valid(_content_scroll) or not is_instance_valid(control):
		return
	if not _content_scroll.is_ancestor_of(control):
		return
	if _content_scroll.has_method("ensure_control_visible"):
		_content_scroll.call_deferred("ensure_control_visible", control)

func _bind_slider(slider: HSlider, setting_key: String) -> void:
	slider.value_changed.connect(func(value: float):
		SaveManager.set_setting(setting_key, value, false)
		SaveManager.apply_settings()
	)

func _on_fullscreen_toggled(pressed: bool) -> void:
	SaveManager.set_setting("fullscreen", pressed, false)
	SaveManager.apply_settings()


func _on_language_selected(index: int) -> void:
	if _syncing_language_option or not is_instance_valid(_language_option):
		return
	var locale := str(_language_option.get_item_metadata(index))
	LocaleManager.set_locale(locale)


func _on_sail_control_selected(index: int) -> void:
	if _syncing_sail_control_option or not is_instance_valid(_sail_control_option):
		return
	var mode := str(_sail_control_option.get_item_metadata(index))
	SaveManager.set_setting("sail_control_mode", mode, false)


func _on_performance_selected(index: int) -> void:
	if _syncing_performance_option or not is_instance_valid(_performance_option):
		return
	var mode := str(_performance_option.get_item_metadata(index))
	SaveManager.set_setting("performance_preset", mode, false)
	SaveManager.apply_settings()


func _on_control_scheme_selected(index: int) -> void:
	if _syncing_control_scheme_option or not is_instance_valid(_control_scheme_option):
		return
	var mode := str(_control_scheme_option.get_item_metadata(index))
	SaveManager.set_setting("control_scheme", mode, false)


func _on_gamepad_confirm_selected(index: int) -> void:
	if _syncing_gamepad_confirm_option or not is_instance_valid(_gamepad_confirm_option):
		return
	var position := str(_gamepad_confirm_option.get_item_metadata(index))
	SaveManager.set_setting("gamepad_confirm_button", position, false)
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
		screen_fx_value_label.text = LocaleManager.t("options.off", "꺼짐") if not enabled else "%s · %d%%" % [descriptor, strength_percent]
		screen_fx_value_label.modulate = Color.WHITE if enabled else Color(1.0, 1.0, 1.0, 0.5)


func _describe_screen_fx_strength(value: float) -> String:
	if value < 0.28:
		return LocaleManager.t("options.fx.weak", "약하게")
	if value < 0.62:
		return LocaleManager.t("options.fx.standard", "표준")
	return LocaleManager.t("options.fx.strong", "강하게")

func _on_back_pressed() -> void:
	SaveManager.save_game()
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if _handle_navigation_event(event):
		if get_viewport():
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if MenuInputHelper.is_cancel_event(event):
		_on_back_pressed()
		if get_viewport():
			get_viewport().set_input_as_handled()
		return

	if _handle_navigation_event(event):
		if get_viewport():
			get_viewport().set_input_as_handled()
		return

	if _is_confirm_event(event):
		var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
		if focused is CheckBox:
			if _is_native_confirm_event(event):
				if get_viewport():
					get_viewport().set_input_as_handled()
				return
			UiButtonAudio.play_click()
			(focused as CheckBox).button_pressed = not (focused as CheckBox).button_pressed
			if get_viewport():
				get_viewport().set_input_as_handled()
		elif focused is OptionButton:
			UiButtonAudio.play_click()
			(focused as OptionButton).show_popup()
			if get_viewport():
				get_viewport().set_input_as_handled()
		elif focused is Button:
			(focused as Button).emit_signal("pressed")
			if get_viewport():
				get_viewport().set_input_as_handled()


func _handle_navigation_event(event: InputEvent) -> bool:
	if _is_option_popup_open():
		return false
	var nav := _nav_repeater.consume_event(event)
	if nav.x != 0:
		_adjust_focused_horizontal(nav.x)
		return true
	if nav.y != 0:
		_move_focus_vertical(nav.y)
		return true
	if MenuInputHelper.is_navigation_axis_event(event):
		return true

	if _is_prev_event(event):
		_move_focus_vertical(-1)
		return true
	if _is_next_event(event):
		_move_focus_vertical(1)
		return true
	return false


func _adjust_focused_horizontal(direction: int) -> void:
	var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focused is HSlider:
		var slider := focused as HSlider
		var step_size := slider.step if slider.step > 0.0 else 0.01
		slider.value = clampf(slider.value + step_size * float(direction), slider.min_value, slider.max_value)
		_scroll_control_into_view(slider)
	elif focused is OptionButton:
		_select_adjacent_option(focused as OptionButton, direction)


func _select_adjacent_option(option: OptionButton, direction: int) -> void:
	if not is_instance_valid(option) or option.item_count <= 0:
		return
	var next_index := posmod(option.selected + direction, option.item_count)
	option.select(next_index)
	option.item_selected.emit(next_index)
	_scroll_control_into_view(option)


func _is_option_popup_open() -> bool:
	for option in [_language_option, _performance_option, _sail_control_option, _control_scheme_option, _gamepad_confirm_option]:
		if not is_instance_valid(option):
			continue
		var popup := (option as OptionButton).get_popup()
		if is_instance_valid(popup) and popup.visible:
			return true
	return false


func _is_prev_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_up_event(event)


func _is_next_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_down_event(event)


func _is_confirm_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_confirm_event(event)


func _is_native_confirm_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return false
		return key_event.keycode == KEY_SPACE or key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER
	return false
