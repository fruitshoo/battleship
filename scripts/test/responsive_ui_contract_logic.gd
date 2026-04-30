extends RefCounted

const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const OPTIONS_PANEL_SCENE := preload("res://scenes/ui/options_panel.tscn")
const UPGRADE_UI_SCENE := preload("res://scenes/ui/upgrade_ui.tscn")
const META_UPGRADE_UI_SCENE := preload("res://scenes/ui/meta_upgrade_ui.tscn")
const SHIP_CONTROL_PANEL_SCENE := preload("res://scenes/ui/ship_control_panel.tscn")
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")

const VIEWPORT_SIZES := [
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1080),
]


static func run_contract(owner: Node, failures: Array[String]) -> void:
	var window := owner.get_window()
	var original_size := window.size if window != null else Vector2i.ZERO
	for target_size in VIEWPORT_SIZES:
		await _resize_window(owner, target_size)
		var effective_size := _get_effective_viewport_size(owner)
		await _run_main_menu_check(owner, failures, effective_size)
		await _run_pause_menu_check(owner, failures, effective_size)
		await _run_options_panel_check(owner, failures, effective_size)
		await _run_upgrade_ui_check(owner, failures, effective_size)
		await _run_meta_upgrade_check(owner, failures, effective_size)
		await _run_ship_control_check(owner, failures, effective_size)
	if window != null and original_size != Vector2i.ZERO:
		await _resize_window(owner, original_size)


static func _run_main_menu_check(owner: Node, failures: Array[String], viewport_size: Vector2) -> void:
	var menu := MAIN_MENU_SCENE.instantiate()
	owner.add_child(menu)
	await _wait_frames(owner, 2)
	_expect_control_within_viewport(menu.get_node_or_null("TitleBlock") as Control, viewport_size, failures, "main menu title block")
	_expect_control_within_viewport(menu.get_node_or_null("ButtonBlock") as Control, viewport_size, failures, "main menu button block")
	_expect_button_audio_wired(menu, failures, "main menu")
	menu.queue_free()
	await _wait_frames(owner, 1)


static func _run_pause_menu_check(owner: Node, failures: Array[String], viewport_size: Vector2) -> void:
	var pause_menu := PAUSE_MENU_SCENE.instantiate()
	owner.add_child(pause_menu)
	await _wait_frames(owner, 2)
	_expect_control_within_viewport(pause_menu.get_node_or_null("Center/Panel") as Control, viewport_size, failures, "pause panel")
	_expect_button_audio_wired(pause_menu, failures, "pause menu")
	pause_menu.queue_free()
	await _wait_frames(owner, 1)


static func _run_options_panel_check(owner: Node, failures: Array[String], viewport_size: Vector2) -> void:
	var options_panel := OPTIONS_PANEL_SCENE.instantiate()
	owner.add_child(options_panel)
	await _wait_frames(owner, 2)
	_expect_control_within_viewport(options_panel.get_node_or_null("Panel") as Control, viewport_size, failures, "options panel")
	_expect_button_audio_wired(options_panel, failures, "options panel")
	options_panel.queue_free()
	await _wait_frames(owner, 1)


static func _run_upgrade_ui_check(owner: Node, failures: Array[String], viewport_size: Vector2) -> void:
	var upgrade_ui = UPGRADE_UI_SCENE.instantiate()
	owner.add_child(upgrade_ui)
	await _wait_frames(owner, 2)
	upgrade_ui.show_upgrades(["cannon", "cannon_damage", "janggun"], 1)
	await _wait_frames(owner, 2)
	_expect_control_within_viewport(upgrade_ui.get_node_or_null("VBox") as Control, viewport_size, failures, "upgrade root")
	var cards_container := upgrade_ui.get_node_or_null("VBox/CardsContainer") as HBoxContainer
	if is_instance_valid(cards_container):
		for child in cards_container.get_children():
			_expect_control_within_viewport(child as Control, viewport_size, failures, "upgrade card")
	_expect_button_audio_wired(upgrade_ui, failures, "upgrade UI")
	var selected_upgrade := {"id": ""}
	upgrade_ui.upgrade_chosen.connect(func(upgrade_id: String) -> void:
		selected_upgrade["id"] = upgrade_id
	)
	upgrade_ui.call("_on_choice_pressed", "cannon_damage")
	await _wait_seconds(owner, 0.25)
	if str(selected_upgrade.get("id", "")) != "cannon_damage":
		failures.append("upgrade UI choice animation did not emit selected upgrade")
	upgrade_ui.queue_free()
	await _wait_frames(owner, 1)

	var reward_ui = UPGRADE_UI_SCENE.instantiate()
	owner.add_child(reward_ui)
	await _wait_frames(owner, 2)
	reward_ui.show_reward_results({
		"requested_count": 3,
		"applied_count": 3,
		"upgrades": [
			{"upgrade_id": "cannon", "from_level": 1, "to_level": 2},
			{"upgrade_id": "cannon_damage", "from_level": 1, "to_level": 2},
			{"upgrade_id": "janggun", "from_level": 1, "to_level": 2},
		],
	}, 8.0)
	await _wait_frames(owner, 2)
	_expect_control_within_viewport(reward_ui.get_node_or_null("VBox") as Control, viewport_size, failures, "treasure reward root")
	if reward_ui.get_node_or_null("TreasureShimmer") != null:
		failures.append("treasure reward UI should not create background shimmer layer")
	var reward_cards := reward_ui.get_node_or_null("VBox/CardsContainer") as HBoxContainer
	if is_instance_valid(reward_cards):
		for child in reward_cards.get_children():
			var reward_card := child as PanelContainer
			if not is_instance_valid(reward_card):
				continue
			var reward_style := reward_card.get_theme_stylebox("panel") as StyleBoxFlat
			if reward_card.has_meta("reward_highlight") or reward_style == null or reward_style.border_width_top > 2 or reward_style.shadow_size > 12:
				failures.append("treasure reward card should keep the plain non-halo reward style")
	_expect_button_audio_wired(reward_ui, failures, "treasure reward UI")
	reward_ui.queue_free()
	await _wait_frames(owner, 1)


static func _run_meta_upgrade_check(owner: Node, failures: Array[String], viewport_size: Vector2) -> void:
	var meta_upgrade_ui = META_UPGRADE_UI_SCENE.instantiate()
	owner.add_child(meta_upgrade_ui)
	await _wait_frames(owner, 2)
	_expect_control_within_viewport(meta_upgrade_ui.get_node_or_null("Backdrop/Panel") as Control, viewport_size, failures, "meta upgrade panel")
	_expect_button_audio_wired(meta_upgrade_ui, failures, "meta upgrade UI")
	meta_upgrade_ui.queue_free()
	await _wait_frames(owner, 1)


static func _run_ship_control_check(owner: Node, failures: Array[String], viewport_size: Vector2) -> void:
	var ship_control := SHIP_CONTROL_PANEL_SCENE.instantiate()
	owner.add_child(ship_control)
	await _wait_frames(owner, 2)
	_expect_control_within_viewport(ship_control.get_node_or_null("WindPanel") as Control, viewport_size, failures, "ship control panel", 6.0)
	_expect_compass_frame_in_safe_area(
		ship_control.get_node_or_null("WindPanel/WindIndicator/CompassWheel/CompassFrame") as Sprite2D,
		viewport_size,
		failures
	)
	ship_control.queue_free()
	await _wait_frames(owner, 1)


static func _resize_window(owner: Node, target_size: Vector2i) -> void:
	var window := owner.get_window()
	if window != null:
		window.size = target_size
	await _wait_frames(owner, 3)


static func _get_effective_viewport_size(owner: Node) -> Vector2:
	var viewport := owner.get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size
	var window := owner.get_window()
	if window != null:
		return window.size
	return Vector2.ZERO


static func _expect_control_within_viewport(control: Control, viewport_size: Vector2, failures: Array[String], label: String, padding: float = 2.0) -> void:
	if not is_instance_valid(control):
		failures.append("%s missing during responsive contract" % label)
		return
	var rect := control.get_global_rect()
	if rect.position.x < -padding \
		or rect.position.y < -padding \
		or rect.end.x > float(viewport_size.x) + padding \
		or rect.end.y > float(viewport_size.y) + padding:
		failures.append("%s exceeds viewport %s with rect %s" % [label, viewport_size, rect])


static func _expect_compass_frame_in_safe_area(compass_frame: Sprite2D, viewport_size: Vector2, failures: Array[String]) -> void:
	if not is_instance_valid(compass_frame):
		failures.append("ship control compass frame missing during responsive contract")
		return
	if not is_instance_valid(compass_frame.texture):
		failures.append("ship control compass frame missing texture during responsive contract")
		return
	var texture_size := compass_frame.texture.get_size()
	var global_scale := compass_frame.global_transform.get_scale().abs()
	var frame_size := Vector2(texture_size.x * global_scale.x, texture_size.y * global_scale.y)
	var rect := Rect2(compass_frame.global_position - frame_size * 0.5, frame_size)
	var top_safe_margin := 40.0
	var edge_padding := 4.0
	if rect.position.y < top_safe_margin \
		or rect.position.x < -edge_padding \
		or rect.end.x > viewport_size.x + edge_padding \
		or rect.end.y > viewport_size.y + edge_padding:
		failures.append("ship control compass frame unsafe viewport %s with rect %s" % [viewport_size, rect])


static func _expect_button_audio_wired(root: Node, failures: Array[String], label: String) -> void:
	var buttons: Array[BaseButton] = []
	_collect_buttons(root, buttons)
	if buttons.is_empty():
		return
	for button in buttons:
		if not is_instance_valid(button):
			continue
		if not button.has_meta(UiButtonAudio.WIRED_META):
			failures.append("%s button missing ui click sound: %s" % [label, button.name])


static func _collect_buttons(node: Node, buttons: Array[BaseButton]) -> void:
	if not is_instance_valid(node):
		return
	if node is BaseButton:
		buttons.append(node as BaseButton)
	for child in node.get_children():
		_collect_buttons(child, buttons)


static func _wait_frames(owner: Node, count: int) -> void:
	for _index in range(maxi(count, 1)):
		await owner.get_tree().process_frame


static func _wait_seconds(owner: Node, seconds: float) -> void:
	await owner.get_tree().create_timer(maxf(seconds, 0.01), true).timeout
