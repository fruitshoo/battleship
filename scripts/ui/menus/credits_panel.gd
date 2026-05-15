extends CanvasLayer

const MenuInputHelper = preload("res://scripts/ui/menu_input_helper.gd")
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")

const CREDITS_PATH := "res://CREDITS.md"
const FALLBACK_CREDITS := """# Credits

Credits file could not be loaded.
"""

signal closed

@onready var backdrop: ColorRect = $Backdrop
@onready var panel: PanelContainer = $Panel
@onready var shell: VBoxContainer = $Panel/Shell
@onready var title_label: Label = $Panel/Shell/Title
@onready var subtitle_label: Label = $Panel/Shell/Subtitle
@onready var credits_text: RichTextLabel = $Panel/Shell/CreditsText
@onready var footer: HBoxContainer = $Panel/Shell/Footer
@onready var back_button: Button = $Panel/Shell/Footer/BackButton

var _nav_repeater := MenuInputHelper.NavRepeater.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_apply_layout_density()
	_apply_localized_text()
	UiButtonAudio.wire_buttons(self)
	back_button.pressed.connect(_on_back_pressed)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_layout_density)
	if not LocaleManager.locale_changed.is_connected(_on_locale_changed):
		LocaleManager.locale_changed.connect(_on_locale_changed)
	call_deferred("_focus_back_button")


func _on_locale_changed(_locale: String) -> void:
	_apply_localized_text()


func _apply_localized_text() -> void:
	if is_instance_valid(title_label):
		title_label.text = LocaleManager.t("credits.title", "크레딧")
	if is_instance_valid(subtitle_label):
		subtitle_label.text = LocaleManager.t("credits.subtitle", "외부 자산과 라이선스 표기")
	if is_instance_valid(back_button):
		back_button.text = LocaleManager.t("credits.close", "메뉴로 돌아가기")
	if is_instance_valid(credits_text):
		credits_text.text = _markdown_to_bbcode(_load_credits_text())


func _apply_theme() -> void:
	if is_instance_valid(backdrop):
		backdrop.color = Color.WHITE
		backdrop.material = UiOverlayFx.make_vignette_material(
			Color(0.02, 0.03, 0.05, 0.84),
			Vector2(0.5, 0.48),
			0.86,
			0.36,
			0.18,
			0.18,
			Vector3(0.018, 0.024, 0.028)
		)
	if is_instance_valid(panel):
		ModalMenuSkin.apply_modal_shell(panel, title_label, subtitle_label, true)
	if is_instance_valid(credits_text):
		credits_text.bbcode_enabled = true
		credits_text.scroll_active = true
		credits_text.fit_content = false
		credits_text.add_theme_font_override("normal_font", NavalUiTheme.FONT_REGULAR)
		credits_text.add_theme_font_override("bold_font", NavalUiTheme.FONT_SEMIBOLD)
		credits_text.add_theme_font_size_override("normal_font_size", 13)
		credits_text.add_theme_color_override("default_color", NavalUiTheme.TEXT_BODY)
	if is_instance_valid(back_button):
		ModalMenuSkin.apply_action_button_theme(back_button, true, true)


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 760.0) / 320.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 580.0) / 260.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	if is_instance_valid(panel):
		var panel_width := roundf(clampf(viewport_size.x - 124.0, 430.0, 720.0))
		var panel_height := roundf(clampf(viewport_size.y - 72.0, 470.0, 650.0))
		panel.offset_left = -panel_width * 0.5
		panel.offset_right = panel_width * 0.5
		panel.offset_top = -panel_height * 0.5
		panel.offset_bottom = panel_height * 0.5
	if is_instance_valid(shell):
		shell.add_theme_constant_override("separation", roundi(lerpf(12.0, 16.0, density)))
	if is_instance_valid(title_label):
		NavalUiTheme.style_display_title(title_label, roundi(lerpf(32.0, 40.0, density)))
	if is_instance_valid(subtitle_label):
		NavalUiTheme.style_caption(subtitle_label, roundi(lerpf(12.0, 13.0, density)), NavalUiTheme.TEXT_BODY)
	if is_instance_valid(credits_text):
		credits_text.add_theme_font_size_override("normal_font_size", roundi(lerpf(12.0, 13.0, density)))
	if is_instance_valid(footer):
		footer.add_theme_constant_override("separation", roundi(lerpf(10.0, 12.0, density)))
	if is_instance_valid(back_button):
		back_button.custom_minimum_size = Vector2(roundi(clampf(viewport_size.x * 0.24, 160.0, 200.0)), roundi(lerpf(40.0, 44.0, density)))


func _focus_back_button() -> void:
	if is_instance_valid(back_button):
		back_button.grab_focus()


func _load_credits_text() -> String:
	if not FileAccess.file_exists(CREDITS_PATH):
		return FALLBACK_CREDITS
	var file := FileAccess.open(CREDITS_PATH, FileAccess.READ)
	if file == null:
		return FALLBACK_CREDITS
	return _sanitize_local_paths(file.get_as_text())


func _sanitize_local_paths(text: String) -> String:
	var sanitized := text
	var marker := "/Users/"
	while sanitized.find(marker) >= 0:
		var start := sanitized.find(marker)
		var end := start
		while end < sanitized.length():
			var character := sanitized.substr(end, 1)
			if character == " " or character == "\n" or character == "\r" or character == "\t" or character == "`":
				break
			end += 1
		var absolute_path := sanitized.substr(start, end - start)
		var project_marker := "/Godot/battleship/"
		var project_index := absolute_path.find(project_marker)
		var replacement := absolute_path.substr(project_index + project_marker.length()) if project_index >= 0 else "[local path]"
		sanitized = sanitized.substr(0, start) + replacement + sanitized.substr(end)
	return sanitized


func _markdown_to_bbcode(markdown: String) -> String:
	var output: Array[String] = []
	for raw_line in markdown.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			output.append("")
		elif line.begins_with("### "):
			output.append("[color=%s][b]%s[/b][/color]" % [NavalUiTheme.TEXT_GOLD.to_html(false), _escape_bbcode(line.substr(4))])
		elif line.begins_with("## "):
			output.append("\n[font_size=17][color=%s][b]%s[/b][/color][/font_size]" % [NavalUiTheme.TEXT_ACCENT.to_html(false), _escape_bbcode(line.substr(3))])
		elif line.begins_with("# "):
			output.append("[font_size=24][color=%s][b]%s[/b][/color][/font_size]" % [NavalUiTheme.TEXT_MAIN.to_html(false), _escape_bbcode(line.substr(2))])
		elif line.begins_with("- "):
			output.append("  • %s" % _format_inline_markdown(line.substr(2)))
		else:
			output.append(_format_inline_markdown(line))
	return "\n".join(output)


func _format_inline_markdown(text: String) -> String:
	var escaped := _escape_bbcode(text)
	escaped = _replace_inline_code(escaped)
	if escaped.begins_with("Source: "):
		var url := escaped.substr("Source: ".length()).strip_edges()
		return "[color=%s]Source:[/color] [url=%s]%s[/url]" % [NavalUiTheme.TEXT_MUTED.to_html(false), url, url]
	if escaped.begins_with("License: "):
		return "[color=%s]License:[/color] %s" % [NavalUiTheme.TEXT_MUTED.to_html(false), escaped.substr("License: ".length()).strip_edges()]
	return escaped


func _replace_inline_code(text: String) -> String:
	var parts := text.split("`")
	if parts.size() < 3:
		return text
	var result := ""
	for i in range(parts.size()):
		if i % 2 == 1:
			result += "[color=%s]%s[/color]" % [NavalUiTheme.TEXT_GOLD.to_html(false), parts[i]]
		else:
			result += parts[i]
	return result


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _unhandled_input(event: InputEvent) -> void:
	if MenuInputHelper.is_cancel_event(event):
		_on_back_pressed()
		if get_viewport():
			get_viewport().set_input_as_handled()
		return

	var nav := _nav_repeater.consume_event(event)
	if nav.y != 0:
		_scroll_credits(nav.y)
		if get_viewport():
			get_viewport().set_input_as_handled()
		return
	if MenuInputHelper.is_navigation_axis_event(event):
		if get_viewport():
			get_viewport().set_input_as_handled()
		return

	if MenuInputHelper.is_confirm_event(event):
		if get_viewport() == null or get_viewport().gui_get_focus_owner() == back_button:
			_on_back_pressed()
			if get_viewport():
				get_viewport().set_input_as_handled()


func _scroll_credits(direction: int) -> void:
	if not is_instance_valid(credits_text) or not credits_text.has_method("get_v_scroll_bar"):
		return
	var scroll_bar := credits_text.call("get_v_scroll_bar") as VScrollBar
	if not is_instance_valid(scroll_bar):
		return
	scroll_bar.value = clampf(scroll_bar.value + float(direction) * 58.0, scroll_bar.min_value, scroll_bar.max_value)


func _on_back_pressed() -> void:
	closed.emit()
	queue_free()
