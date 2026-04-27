extends RefCounted
class_name ProjectContractTypographyHelper

const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")


static func run_typography_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int) -> void:
	await _run_main_menu_typography_check(owner, failures)
	await _run_preview_typography_check(owner, failures, smoke_scene_path, wait_frames_after_attach)


static func _run_main_menu_typography_check(owner: Node, failures: Array[String]) -> void:
	var menu_root := MAIN_MENU_SCENE.instantiate()
	if menu_root == null:
		failures.append("typography smoke main menu instantiate failed")
		return
	owner.add_child(menu_root)
	await _wait_typography_frames(owner, 1)

	var title_label := menu_root.get_node_or_null("TitleBlock/Title") as Label
	var version_label := menu_root.get_node_or_null("VersionLabel") as Label
	var menu_density := _compute_main_menu_density(menu_root)
	_expect_control_font(title_label, NavalUiTheme.FONT_DISPLAY, roundi(lerpf(52.0, 68.0, menu_density)), failures, "main menu title")
	_expect_control_color(title_label, "font_color", NavalUiTheme.TEXT_MAIN, failures, "main menu title")
	_expect_control_constant(title_label, "outline_size", 1, failures, "main menu title")
	_expect_control_constant(title_label, "shadow_outline_size", 2, failures, "main menu title")
	_expect_control_font(version_label, NavalUiTheme.FONT_MEDIUM, roundi(lerpf(11.0, 13.0, menu_density)), failures, "main menu version")
	_expect_control_color(version_label, "font_color", NavalUiTheme.TEXT_MUTED, failures, "main menu version")

	menu_root.queue_free()
	await _wait_typography_frames(owner, 1)


static func _run_preview_typography_check(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("typography smoke scene load failed: %s" % smoke_scene_path)
		return
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("typography smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_typography_frames(owner, wait_frames_after_attach)

	var hud: Node = smoke_root.get_node_or_null("GameHUD")
	if not is_instance_valid(hud):
		failures.append("typography smoke missing GameHUD")
	else:
		var hud_density := _compute_hud_density(smoke_root)
		_expect_control_font(hud.timer_label as Control, NavalUiTheme.FONT_UI_BOLD, roundi(lerpf(22.0, 26.0, hud_density)), failures, "hud timer")
		_expect_control_color(hud.timer_label as Control, "font_color", NavalUiTheme.TEXT_MAIN, failures, "hud timer")
		_expect_control_constant(hud.timer_label as Control, "outline_size", 4, failures, "hud timer")
		_expect_control_constant(hud.timer_label as Control, "shadow_outline_size", 2, failures, "hud timer")

	var preview_anchor := Node3D.new()
	preview_anchor.name = "TypographyPreviewAnchor"
	smoke_root.add_child(preview_anchor)
	var callout_label := PreviewHarnessHelper.add_billboard_label(
		preview_anchor,
		"Typography",
		Vector3(0.0, 4.0, 0.0),
		NavalUiTheme.TEXT_ACCENT,
		36
	)
	_expect_label3d_font(callout_label, NavalUiTheme.FONT_WORLD_CALLOUT, 36, 6, failures, "preview callout")
	_expect_label3d_billboard(callout_label, true, failures, "preview callout")

	var player_ship := smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("typography smoke missing PlayerShip")
	else:
		var player_soldiers: Array = EntityRegistry.get_soldiers_by_ship(player_ship)
		var soldier: Node = null
		if not player_soldiers.is_empty():
			soldier = player_soldiers[0] as Node
		if not is_instance_valid(soldier):
			failures.append("typography smoke missing player soldier")
		else:
			SoldierSpeechHelper.reset(soldier)
			SoldierSpeechHelper.update(soldier, 99.0)
			var speech_label := soldier.get_node_or_null(SoldierSpeechHelper.SPEECH_LABEL_NAME) as Label3D
			if not is_instance_valid(speech_label):
				failures.append("typography smoke speech label did not instantiate")
			else:
				var is_captain := bool(soldier.get("is_captain"))
				_expect_label3d_font(
					speech_label,
					NavalUiTheme.FONT_WORLD_SPEECH_EMPHASIS if is_captain else NavalUiTheme.FONT_WORLD_SPEECH,
					88 if is_captain else 78,
					8 if is_captain else 7,
					failures,
					"soldier speech"
				)
				_expect_label3d_billboard(speech_label, true, failures, "soldier speech")

	smoke_root.queue_free()
	await _wait_typography_frames(owner, 1)


static func _expect_control_font(control: Control, expected_font: Font, expected_size: int, failures: Array[String], label: String) -> void:
	if not is_instance_valid(control):
		failures.append("typography smoke missing control: %s" % label)
		return
	var font := control.get_theme_font("font")
	if not _font_matches(font, expected_font):
		failures.append("%s font mismatch: expected %s got %s" % [label, _font_path(expected_font), _font_path(font)])
	var actual_size := control.get_theme_font_size("font_size")
	if actual_size != expected_size:
		failures.append("%s font size mismatch: expected %d got %d" % [label, expected_size, actual_size])


static func _expect_control_color(control: Control, color_name: String, expected: Color, failures: Array[String], label: String) -> void:
	if not is_instance_valid(control):
		return
	var actual := control.get_theme_color(color_name)
	if not _colors_match(actual, expected):
		failures.append("%s %s mismatch: expected %s got %s" % [label, color_name, expected, actual])


static func _expect_control_constant(control: Control, constant_name: String, expected: int, failures: Array[String], label: String) -> void:
	if not is_instance_valid(control):
		return
	var actual := control.get_theme_constant(constant_name)
	if actual != expected:
		failures.append("%s %s mismatch: expected %d got %d" % [label, constant_name, expected, actual])


static func _expect_label3d_font(label_node: Label3D, expected_font: Font, expected_size: int, expected_outline: int, failures: Array[String], label: String) -> void:
	if not is_instance_valid(label_node):
		failures.append("typography smoke missing Label3D: %s" % label)
		return
	var font := label_node.get("font") as Font
	if not _font_matches(font, expected_font):
		failures.append("%s font mismatch: expected %s got %s" % [label, _font_path(expected_font), _font_path(font)])
	if label_node.font_size != expected_size:
		failures.append("%s font size mismatch: expected %d got %d" % [label, expected_size, label_node.font_size])
	if label_node.outline_size != expected_outline:
		failures.append("%s outline size mismatch: expected %d got %d" % [label, expected_outline, label_node.outline_size])


static func _expect_label3d_billboard(label_node: Label3D, require_no_depth_test: bool, failures: Array[String], label: String) -> void:
	if not is_instance_valid(label_node):
		return
	if label_node.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
		failures.append("%s billboard setting mismatch" % label)
	if require_no_depth_test and not label_node.no_depth_test:
		failures.append("%s should render without depth test" % label)


static func _wait_typography_frames(owner: Node, frame_count: int) -> void:
	for _index in range(maxi(frame_count, 1)):
		await owner.get_tree().process_frame


static func _compute_main_menu_density(root: Node) -> float:
	var viewport_size: Vector2 = root.get_viewport().get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 900.0) / 420.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 640.0) / 220.0, 0.0, 1.0)
	return min(width_fit, height_fit)


static func _compute_hud_density(root: Node) -> float:
	var viewport_size: Vector2 = root.get_viewport().get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 1280.0) / 640.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 720.0) / 360.0, 0.0, 1.0)
	return min(width_fit, height_fit)


static func _font_matches(actual: Font, expected: Font) -> bool:
	if actual == expected:
		return true
	return _font_path(actual) == _font_path(expected) and not _font_path(expected).is_empty()


static func _font_path(font: Font) -> String:
	return "" if font == null else font.resource_path


static func _colors_match(actual: Color, expected: Color, tolerance: float = 0.001) -> bool:
	return absf(actual.r - expected.r) <= tolerance \
		and absf(actual.g - expected.g) <= tolerance \
		and absf(actual.b - expected.b) <= tolerance \
		and absf(actual.a - expected.a) <= tolerance
