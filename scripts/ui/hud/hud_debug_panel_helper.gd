extends RefCounted
class_name HudDebugPanelHelper

const CollisionVisualizer = preload("res://scripts/helpers/collision_visualizer.gd")
const DistanceDebugVisualizer = preload("res://scripts/helpers/distance_debug_visualizer.gd")
const AUTHORING_PALETTE_DATA_PATH := "res://data/authoring_palette.json"
const SHIP_STATS_DATA_PATH := "res://data/ship_stats.json"
const ENEMY_SPAWN_RULES_DATA_PATH := "res://data/enemy_spawn_rules.json"
const AUTHORING_QUEUE_USER_PATH := "user://authoring_palette_queue.json"
const AUTHORING_SCENARIO_TRIGGER_USER_PATH := "user://authoring_palette_scenario_trigger.json"
const AUTHORING_SCENARIO_PRESETS_USER_PATH := "user://authoring_palette_scenario_presets.json"
const AUTHORING_DATA_PATCH_USER_PATH := "user://authoring_palette_data_patch.json"
const PALETTE_PRESET_FALLBACK_ID := "palette_queue"
const SHOW_AUTHORING_PALETTE_TAB_SETTING := "battleship/debug/show_authoring_palette_tab"
const SHOW_AUTHORING_PALETTE_TAB_ENV := "BATTLESHIP_SHOW_AUTHORING_PALETTE"
const DEBUG_PANEL_SIZE := Vector2(920.0, 560.0)
const DEBUG_PANEL_MIN_SIZE := Vector2(760.0, 460.0)


static func setup_debug_panel(hud) -> void:
	if not OS.is_debug_build():
		return
	if is_instance_valid(hud.sail_debug_panel):
		return

	hud.debug_backdrop = ColorRect.new()
	hud.debug_backdrop.name = "DebugToolsBackdrop"
	hud.add_child(hud.debug_backdrop)
	hud.debug_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.debug_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.debug_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.debug_backdrop.color = Color.WHITE
	hud.debug_backdrop.material = UiOverlayFx.make_modal_blur_material(
		Color(0.02, 0.03, 0.05, 0.46),
		0.64,
		14.0,
		0.38,
		Vector2(0.5, 0.48)
	)
	hud.debug_backdrop.visible = false
	hud.debug_backdrop.z_index = 130
	hud.debug_backdrop.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event := event as InputEventMouseButton
		if mouse_event == null or not mouse_event.pressed:
			return
		hud._set_debug_modal_active(false)
		hud._update_sail_debug_toggle_button_text()
	)

	hud.sail_debug_panel = PanelContainer.new()
	hud.sail_debug_panel.name = "SailDebugPanel"
	hud.sail_debug_panel.z_index = 140
	hud.sail_debug_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.sail_debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.sail_debug_panel.custom_minimum_size = DEBUG_PANEL_SIZE
	hud.sail_debug_panel.size = DEBUG_PANEL_SIZE
	var panel_style := NavalUiTheme.make_hud_panel_style()
	hud.sail_debug_panel.add_theme_stylebox_override("panel", panel_style)

	var modal_box := VBoxContainer.new()
	modal_box.custom_minimum_size = DEBUG_PANEL_MIN_SIZE
	modal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_box.add_theme_constant_override("separation", 8)
	hud.sail_debug_panel.add_child(modal_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	modal_box.add_child(header)

	var title := Label.new()
	title.text = "Debug Tools"
	NavalUiTheme.style_heading(title, 13)
	header.add_child(title)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	var hint := Label.new()
	hint.text = "₩ / Esc"
	NavalUiTheme.style_muted(hint, 10)
	header.add_child(hint)

	var close_button := Button.new()
	close_button.text = "닫기"
	close_button.custom_minimum_size = Vector2(64, 28)
	close_button.focus_mode = Control.FOCUS_ALL
	NavalUiTheme.apply_hud_button(close_button, 11)
	close_button.pressed.connect(func() -> void:
		hud._set_debug_modal_active(false)
		hud._update_sail_debug_toggle_button_text()
	)
	header.add_child(close_button)

	var debug_tabs := TabContainer.new()
	debug_tabs.name = "DebugToolsTabs"
	debug_tabs.focus_mode = Control.FOCUS_ALL
	debug_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debug_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_box.add_child(debug_tabs)

	_add_environment_section(hud, debug_tabs)
	_add_debug_draw_section(hud, debug_tabs)
	_add_spawn_section(hud, debug_tabs)
	if is_authoring_palette_tab_visible():
		_add_authoring_palette_section(hud, debug_tabs)
	_add_misc_section(hud, debug_tabs)
	_add_ship_section(hud, debug_tabs)
	_add_sail_section(hud, debug_tabs)

	hud.add_child(hud.sail_debug_panel)
	hud.sail_debug_panel.anchor_left = 0.5
	hud.sail_debug_panel.anchor_right = 0.5
	hud.sail_debug_panel.anchor_top = 0.5
	hud.sail_debug_panel.anchor_bottom = 0.5
	hud.sail_debug_panel.offset_left = -DEBUG_PANEL_SIZE.x * 0.5
	hud.sail_debug_panel.offset_right = DEBUG_PANEL_SIZE.x * 0.5
	hud.sail_debug_panel.offset_top = -DEBUG_PANEL_SIZE.y * 0.5
	hud.sail_debug_panel.offset_bottom = DEBUG_PANEL_SIZE.y * 0.5
	hud.sail_debug_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.sail_debug_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud.sail_debug_panel.visible = false
	hud._sync_sail_debug_panel_from_player()
	hud._sync_debug_tools_panel_state()
	hud._update_sail_debug_toggle_button_text()


static func is_authoring_palette_tab_visible() -> bool:
	if ProjectSettings.has_setting(SHOW_AUTHORING_PALETTE_TAB_SETTING):
		return bool(ProjectSettings.get_setting(SHOW_AUTHORING_PALETTE_TAB_SETTING))
	var env_value := OS.get_environment(SHOW_AUTHORING_PALETTE_TAB_ENV).strip_edges().to_lower()
	return ["1", "true", "yes", "on"].has(env_value)


static func handle_debug_panel_keyboard_input(hud, event: InputEvent) -> bool:
	if not is_instance_valid(hud.sail_debug_panel) or not hud.sail_debug_panel.visible:
		return false
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.is_echo():
		return false
	var keycode := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	match keycode:
		KEY_PAGEUP:
			_cycle_debug_tab(hud, -1)
			return true
		KEY_PAGEDOWN:
			_cycle_debug_tab(hud, 1)
			return true
		KEY_HOME:
			if key_event.ctrl_pressed or key_event.meta_pressed:
				_set_debug_tab(hud, 0)
				return true
		KEY_END:
			if key_event.ctrl_pressed or key_event.meta_pressed:
				_set_debug_tab(hud, -1)
				return true
		KEY_TAB:
			if not _is_debug_focus_inside_panel(hud):
				grab_initial_debug_focus(hud)
				return true
	return false


static func grab_initial_debug_focus(hud) -> void:
	if not is_instance_valid(hud.sail_debug_panel):
		return
	var debug_tabs := hud.sail_debug_panel.find_child("DebugToolsTabs", true, false) as TabContainer
	var focus_target: Control = null
	if is_instance_valid(debug_tabs):
		var current_tab := debug_tabs.get_current_tab_control()
		if is_instance_valid(current_tab):
			focus_target = _find_first_focusable_control(current_tab)
	if not is_instance_valid(focus_target):
		focus_target = _find_first_focusable_control(hud.sail_debug_panel)
	if is_instance_valid(focus_target):
		focus_target.grab_focus()


static func clear_debug_focus(hud) -> void:
	var viewport: Viewport = hud.get_viewport()
	if viewport == null or not is_instance_valid(hud.sail_debug_panel):
		return
	var focused: Control = viewport.gui_get_focus_owner()
	if is_instance_valid(focused) and _is_node_descendant_of(focused, hud.sail_debug_panel):
		focused.release_focus()


static func _cycle_debug_tab(hud, delta: int) -> void:
	var debug_tabs := hud.sail_debug_panel.find_child("DebugToolsTabs", true, false) as TabContainer
	if not is_instance_valid(debug_tabs) or debug_tabs.get_tab_count() <= 0:
		return
	var next_tab := posmod(debug_tabs.current_tab + delta, debug_tabs.get_tab_count())
	debug_tabs.current_tab = next_tab
	grab_initial_debug_focus(hud)


static func _set_debug_tab(hud, tab_index: int) -> void:
	var debug_tabs := hud.sail_debug_panel.find_child("DebugToolsTabs", true, false) as TabContainer
	if not is_instance_valid(debug_tabs) or debug_tabs.get_tab_count() <= 0:
		return
	if tab_index < 0:
		debug_tabs.current_tab = debug_tabs.get_tab_count() - 1
	else:
		debug_tabs.current_tab = clampi(tab_index, 0, debug_tabs.get_tab_count() - 1)
	grab_initial_debug_focus(hud)


static func _is_debug_focus_inside_panel(hud) -> bool:
	var viewport: Viewport = hud.get_viewport()
	if viewport == null or not is_instance_valid(hud.sail_debug_panel):
		return false
	var focused: Control = viewport.gui_get_focus_owner()
	return is_instance_valid(focused) and _is_node_descendant_of(focused, hud.sail_debug_panel)


static func _find_first_focusable_control(root: Node) -> Control:
	var control := root as Control
	if is_instance_valid(control) and control.visible and control.focus_mode != Control.FOCUS_NONE:
		if not _is_control_disabled(control):
			return control
	for child in root.get_children():
		var focusable := _find_first_focusable_control(child)
		if is_instance_valid(focusable):
			return focusable
	return null


static func _is_control_disabled(control: Control) -> bool:
	if control is BaseButton:
		return (control as BaseButton).disabled
	if control is OptionButton:
		return (control as OptionButton).disabled
	return false


static func _is_node_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


static func get_level_manager_for_debug(hud) -> Node:
	if not is_instance_valid(hud._cached_level_manager):
		hud._cached_level_manager = LevelManagerRegistry.get_level_manager(hud.get_tree())
	return hud._cached_level_manager


static func get_environment_preset_manager_for_debug(hud) -> Node:
	if is_instance_valid(hud._cached_environment_preset_manager):
		return hud._cached_environment_preset_manager
	hud._cached_environment_preset_manager = hud.get_tree().root.find_child("EnvironmentPresetManager", true, false)
	return hud._cached_environment_preset_manager


static func invoke_level_debug_method(hud, method_name: String, args: Array = []) -> void:
	var level_manager: Node = get_level_manager_for_debug(hud)
	if not is_instance_valid(level_manager):
		hud.show_gust_warning_message("LevelManager 없음", 0.8)
		return
	if not level_manager.has_method(method_name):
		hud.show_gust_warning_message("디버그 메서드 없음: %s" % method_name, 0.8)
		return
	level_manager.callv(method_name, args)


static func apply_environment_preset(hud, preset_index: int) -> void:
	var preset_manager: Node = get_environment_preset_manager_for_debug(hud)
	if not is_instance_valid(preset_manager) or not preset_manager.has_method("apply_preset"):
		hud.show_gust_warning_message("환경 프리셋 매니저 없음", 0.8)
		return
	preset_manager.call("apply_preset", preset_index)
	sync_debug_tools_panel_state(hud)


static func sync_debug_tools_panel_state(hud) -> void:
	if not is_instance_valid(hud.sail_debug_panel):
		return
	if is_instance_valid(hud.debug_environment_value):
		var preset_manager: Node = get_environment_preset_manager_for_debug(hud)
		var environment_text: String = "-"
		if is_instance_valid(preset_manager):
			var preset_index: int = int(preset_manager.get("current_preset"))
			environment_text = "낮" if preset_index == 0 else "밤"
		hud.debug_environment_value.text = "프리셋: %s" % environment_text
	if is_instance_valid(hud.debug_collision_value):
		var bounds_text := "OFF"
		if CollisionVisualizer.runtime_enabled:
			bounds_text = "ON (%s)" % CollisionVisualizer.get_mode_name(CollisionVisualizer.runtime_mode)
		hud.debug_collision_value.text = "선박 영역: %s" % bounds_text
	if is_instance_valid(hud.debug_distance_value):
		hud.debug_distance_value.text = "거리 표시: %s" % ("ON" if DistanceDebugVisualizer.runtime_enabled else "OFF")
	if is_instance_valid(hud.debug_draw_channels_value):
		var draw_status := "사용 가능" if DebugDrawBridge.can_draw() else "비활성"
		hud.debug_draw_channels_value.text = "DebugDraw3D: %s\n%s" % [
			draw_status,
			DebugDrawBridge.get_channel_status_text()
		]
	hud._sync_ship_debug_panel_from_player()


static func _add_environment_section(hud, panel_box: Control) -> void:
	var section: Dictionary = create_debug_section("환경", false)
	panel_box.add_child(section["root"])

	var status := Label.new()
	status.text = "프리셋: -"
	NavalUiTheme.style_body(status, 11)
	section["body"].add_child(status)
	hud.debug_environment_value = status

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	section["body"].add_child(row)
	row.add_child(create_debug_action_button("낮", func() -> void:
		hud._apply_environment_preset(0)
	))
	row.add_child(create_debug_action_button("밤", func() -> void:
		hud._apply_environment_preset(1)
	))


static func _add_debug_draw_section(hud, panel_box: Control) -> void:
	var section: Dictionary = create_debug_section("시각화", false)
	panel_box.add_child(section["root"])
	var columns := create_debug_columns(section["body"], 2)
	var status_group := create_debug_group(columns[0], "상태")
	var channel_group := create_debug_group(columns[1], "드로우 채널")

	var status := Label.new()
	status.text = "DebugDraw3D: -"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_body(status, 11)
	status_group.add_child(status)
	hud.debug_draw_channels_value = status

	var collision_status := Label.new()
	collision_status.text = "선박 영역: OFF"
	NavalUiTheme.style_body(collision_status, 11)
	status_group.add_child(collision_status)
	hud.debug_collision_value = collision_status

	var distance_status := Label.new()
	distance_status.text = "거리 표시: OFF"
	NavalUiTheme.style_body(distance_status, 11)
	status_group.add_child(distance_status)
	hud.debug_distance_value = distance_status

	var collision_row := HBoxContainer.new()
	collision_row.add_theme_constant_override("separation", 4)
	status_group.add_child(collision_row)
	collision_row.add_child(create_debug_action_button("선박 영역", func() -> void:
		hud._invoke_level_debug_method("_toggle_collision_visualizers")
		hud._sync_debug_tools_panel_state()
	))
	collision_row.add_child(create_debug_action_button("영역 모드", func() -> void:
		hud._invoke_level_debug_method("_cycle_collision_visualizer_mode")
		hud._sync_debug_tools_panel_state()
	))
	collision_row.add_child(create_debug_action_button("거리", func() -> void:
		hud._toggle_distance_debug()
		hud._sync_debug_tools_panel_state()
	))

	var row_a := HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 4)
	channel_group.add_child(row_a)
	row_a.add_child(create_debug_action_button("충돌", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_COLLISION)
	))
	row_a.add_child(create_debug_action_button("탄착", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_PROJECTILE)
	))
	row_a.add_child(create_debug_action_button("AI 의도", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_AI_INTENT)
	))

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	channel_group.add_child(row_b)
	row_b.add_child(create_debug_action_button("스폰", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_SPAWN)
	))
	row_b.add_child(create_debug_action_button("선원", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_CREW_WORK)
	))
	row_b.add_child(create_debug_action_button("지원", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_SUPPORT)
	))

	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 4)
	channel_group.add_child(row_c)
	row_c.add_child(create_debug_action_button("바람", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_WIND)
	))
	row_c.add_child(create_debug_action_button("사이트", func() -> void:
		_toggle_debug_draw_channel(hud, DebugDrawBridge.CHANNEL_SITE)
	))

	var row_d := HBoxContainer.new()
	row_d.add_theme_constant_override("separation", 4)
	channel_group.add_child(row_d)
	row_d.add_child(create_debug_action_button("드로우 끄기", func() -> void:
		for channel in DebugDrawBridge.CHANNEL_ORDER:
			DebugDrawBridge.set_channel_enabled(str(channel), false)
		hud._invoke_level_debug_method("_set_collision_visualizers_enabled", [false])
		DistanceDebugVisualizer.set_runtime_enabled(false)
		hud._sync_debug_tools_panel_state()
	))


static func _toggle_debug_draw_channel(hud, channel: String) -> void:
	var enabled := DebugDrawBridge.toggle_channel(channel)
	hud.show_gust_warning_message("%s 드로우 %s" % [
		DebugDrawBridge.get_channel_label(channel),
		"ON" if enabled else "OFF"
	], 0.8)
	hud._sync_debug_tools_panel_state()


static func _add_spawn_section(hud, panel_box: Control) -> void:
	var section: Dictionary = create_debug_section("생성", false)
	panel_box.add_child(section["root"])
	var columns := create_debug_columns(section["body"], 2)
	var enemy_group := create_debug_group(columns[0], "적 함선")
	var fleet_group := create_debug_group(columns[1], "편대 / 지원")

	var row_a := HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 4)
	enemy_group.add_child(row_a)
	row_a.add_child(create_debug_action_button("세키 근접", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_test_ship", ["sekibune_melee", 40.0, -12.0])
	))
	row_a.add_child(create_debug_action_button("세키 포격", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_test_ship", ["sekibune_cannon", 40.0, 12.0])
	))

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	enemy_group.add_child(row_b)
	row_b.add_child(create_debug_action_button("중간보스", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_mid_boss")
	))
	row_b.add_child(create_debug_action_button("최종보스", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_final_boss")
	))

	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 4)
	fleet_group.add_child(row_c)
	row_c.add_child(create_debug_action_button("지원함 추가", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_support_ship")
	))
	row_c.add_child(create_debug_action_button("지원함 덤프", func() -> void:
		hud._invoke_level_debug_method("_debug_dump_support_fleet_state")
	))

	var row_d := HBoxContainer.new()
	row_d.add_theme_constant_override("separation", 4)
	fleet_group.add_child(row_d)
	row_d.add_child(create_debug_action_button("소형 편대", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_fleet", ["light"])
	))
	row_d.add_child(create_debug_action_button("혼성 편대", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_fleet", ["mixed"])
	))
	row_d.add_child(create_debug_action_button("대형 편대", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_fleet", ["heavy"])
	))


static func _add_authoring_palette_section(hud, panel_box: Control) -> void:
	var section: Dictionary = create_debug_section("조립 팔레트", false)
	panel_box.add_child(section["root"])

	var palette := load_authoring_palette()
	if palette.is_empty():
		var missing_label := Label.new()
		missing_label.text = "authoring_palette 없음"
		NavalUiTheme.style_muted(missing_label, 10)
		section["body"].add_child(missing_label)
		return

	var source_data: Dictionary = load_authoring_palette_source_data()
	var preview := Label.new()
	preview.text = "팔레트 항목에 마우스를 올리면 조립 내용이 표시됩니다."
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size = Vector2(0, 48)
	NavalUiTheme.style_muted(preview, 10)
	section["body"].add_child(preview)
	hud.debug_authoring_palette_preview_value = preview

	var schema_label := Label.new()
	schema_label.text = _describe_palette_block_schema(palette)
	schema_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	schema_label.custom_minimum_size = Vector2(0, 24)
	NavalUiTheme.style_muted(schema_label, 10)
	section["body"].add_child(schema_label)

	var selected := Label.new()
	selected.text = "선택: -"
	selected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected.custom_minimum_size = Vector2(0, 28)
	NavalUiTheme.style_accent(selected, 10)
	section["body"].add_child(selected)
	hud.debug_authoring_palette_selected_value = selected
	hud.debug_authoring_palette_selected_callback = Callable()
	hud.debug_authoring_palette_selected_action = {}

	var assembly_label := Label.new()
	assembly_label.text = "조립 카드: 전투=- / 이동=-"
	assembly_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assembly_label.custom_minimum_size = Vector2(0, 28)
	NavalUiTheme.style_muted(assembly_label, 10)
	section["body"].add_child(assembly_label)
	hud.debug_authoring_palette_assembly_value = assembly_label
	hud.debug_authoring_palette_assembly_meta = {}

	var queue_label := Label.new()
	queue_label.text = "큐: -"
	queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	queue_label.custom_minimum_size = Vector2(0, 36)
	NavalUiTheme.style_muted(queue_label, 10)
	section["body"].add_child(queue_label)
	hud.debug_authoring_palette_queue_value = queue_label
	hud.debug_authoring_palette_queue_entries.clear()
	hud.debug_authoring_palette_queue_selected_index = -1

	var preset_label := Label.new()
	preset_label.text = "프리셋: -"
	preset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_label.custom_minimum_size = Vector2(0, 28)
	NavalUiTheme.style_muted(preset_label, 10)
	section["body"].add_child(preset_label)
	hud.debug_authoring_palette_preset_value = preset_label

	var preset_preview := Label.new()
	preset_preview.text = "프리셋 내용: -"
	preset_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_preview.custom_minimum_size = Vector2(0, 42)
	NavalUiTheme.style_muted(preset_preview, 10)
	section["body"].add_child(preset_preview)
	hud.debug_authoring_palette_preset_preview_value = preset_preview

	var preset_select := OptionButton.new()
	preset_select.name = "AuthoringPalettePresetSelect"
	preset_select.custom_minimum_size = Vector2(0, 28)
	preset_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_select.focus_mode = Control.FOCUS_ALL
	preset_select.disabled = true
	section["body"].add_child(preset_select)
	hud.debug_authoring_palette_preset_select = preset_select
	preset_select.item_selected.connect(func(index: int) -> void:
		_select_scenario_preset(hud, index)
	)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(action_row)

	var execute_button := create_debug_action_button("선택 실행", func() -> void:
		var selected_callback: Callable = hud.debug_authoring_palette_selected_callback
		var selected_action: Dictionary = _apply_palette_assembly_to_action(hud.debug_authoring_palette_selected_action, hud.debug_authoring_palette_assembly_meta)
		var assembled_callback := _make_palette_action_callback(hud, selected_action)
		if assembled_callback.is_valid():
			assembled_callback.call()
		elif selected_callback.is_valid():
			selected_callback.call()
	)
	execute_button.disabled = true
	action_row.add_child(execute_button)
	hud.debug_authoring_palette_execute_button = execute_button

	var queue_add_button := create_debug_action_button("큐 추가", func() -> void:
		_add_selected_palette_action_to_queue(hud)
	)
	queue_add_button.disabled = true
	action_row.add_child(queue_add_button)
	hud.debug_authoring_palette_queue_add_button = queue_add_button

	action_row.add_child(create_debug_action_button("비우기", func() -> void:
		_clear_palette_selection(hud)
	))
	action_row.add_child(create_debug_action_button("카드 비우기", func() -> void:
		_clear_palette_assembly(hud)
	))

	var queue_row := HBoxContainer.new()
	queue_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(queue_row)

	var queue_execute_button := create_debug_action_button("큐 실행", func() -> void:
		_execute_palette_queue(hud)
	)
	queue_execute_button.disabled = true
	queue_row.add_child(queue_execute_button)
	hud.debug_authoring_palette_queue_execute_button = queue_execute_button

	var queue_duplicate_button := create_debug_action_button("큐 복제", func() -> void:
		_duplicate_selected_palette_queue_entry(hud)
	)
	queue_duplicate_button.disabled = true
	queue_row.add_child(queue_duplicate_button)
	hud.debug_authoring_palette_queue_duplicate_button = queue_duplicate_button

	var queue_delete_button := create_debug_action_button("큐 삭제", func() -> void:
		_delete_selected_palette_queue_entry(hud)
	)
	queue_delete_button.disabled = true
	queue_row.add_child(queue_delete_button)
	hud.debug_authoring_palette_queue_delete_button = queue_delete_button

	queue_row.add_child(create_debug_action_button("큐 비우기", func() -> void:
		_clear_palette_queue(hud)
	))

	var queue_select_row := HBoxContainer.new()
	queue_select_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(queue_select_row)
	var queue_prev_button := create_debug_action_button("큐 이전", func() -> void:
		_select_palette_queue_entry(hud, hud.debug_authoring_palette_queue_selected_index - 1)
	)
	queue_prev_button.disabled = true
	queue_select_row.add_child(queue_prev_button)
	hud.debug_authoring_palette_queue_prev_button = queue_prev_button
	var queue_next_button := create_debug_action_button("큐 다음", func() -> void:
		_select_palette_queue_entry(hud, hud.debug_authoring_palette_queue_selected_index + 1)
	)
	queue_next_button.disabled = true
	queue_select_row.add_child(queue_next_button)
	var queue_up_button := create_debug_action_button("큐 위로", func() -> void:
		_move_selected_palette_queue_entry(hud, -1)
	)
	queue_up_button.disabled = true
	queue_select_row.add_child(queue_up_button)
	hud.debug_authoring_palette_queue_move_up_button = queue_up_button
	var queue_down_button := create_debug_action_button("큐 아래", func() -> void:
		_move_selected_palette_queue_entry(hud, 1)
	)
	queue_down_button.disabled = true
	queue_select_row.add_child(queue_down_button)
	hud.debug_authoring_palette_queue_move_down_button = queue_down_button

	var queue_io_row := HBoxContainer.new()
	queue_io_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(queue_io_row)
	queue_io_row.add_child(create_debug_action_button("큐 저장", func() -> void:
		_save_palette_queue(hud)
	))
	queue_io_row.add_child(create_debug_action_button("큐 불러오기", func() -> void:
		_load_palette_queue(hud)
	))

	var scenario_io_row := HBoxContainer.new()
	scenario_io_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(scenario_io_row)
	scenario_io_row.add_child(create_debug_action_button("트리거 저장", func() -> void:
		_save_palette_queue_as_scenario_trigger(hud)
	))

	var preset_io_row := HBoxContainer.new()
	preset_io_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(preset_io_row)
	preset_io_row.add_child(create_debug_action_button("프리셋 저장", func() -> void:
		_save_palette_queue_as_scenario_preset(hud)
	))
	preset_io_row.add_child(create_debug_action_button("프리셋 불러오기", func() -> void:
		_load_active_scenario_preset_to_queue(hud)
	))

	var preset_action_row := HBoxContainer.new()
	preset_action_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(preset_action_row)
	preset_action_row.add_child(create_debug_action_button("프리셋 실행", func() -> void:
		_execute_selected_scenario_preset(hud)
	))
	preset_action_row.add_child(create_debug_action_button("데이터 승격", func() -> void:
		_promote_selected_scenario_preset_to_data_patch(hud)
	))
	preset_action_row.add_child(create_debug_action_button("패치 점검", func() -> void:
		_check_authoring_data_patch(hud)
	))
	preset_action_row.add_child(create_debug_action_button("패치 병합", func() -> void:
		_merge_authoring_data_patch(hud)
	))
	preset_action_row.add_child(create_debug_action_button("프리셋 삭제", func() -> void:
		_delete_selected_scenario_preset(hud)
	))
	_sync_palette_preset_ui(hud)

	_add_palette_ship_type_buttons(hud, section["body"], palette.get("ship_types", []), preview, selected, execute_button, source_data)
	_add_palette_recipe_buttons(hud, section["body"], palette.get("spawn_recipes", []), preview, selected, execute_button, source_data)
	_add_palette_combat_profile_buttons(hud, section["body"], palette.get("combat_profiles", []), preview, selected, execute_button, source_data)
	_add_palette_movement_intent_buttons(hud, section["body"], palette.get("movement_intents", []), preview, selected, execute_button)
	_add_palette_profile_buttons(hud, section["body"], palette.get("encounter_profiles", []), preview, selected, execute_button, source_data)
	_add_palette_trigger_buttons(hud, section["body"], palette.get("scenario_triggers", []), preview, selected, execute_button, source_data)


static func load_authoring_palette() -> Dictionary:
	return _load_json_dictionary(AUTHORING_PALETTE_DATA_PATH)


static func load_authoring_palette_source_data() -> Dictionary:
	return {
		"ship_stats": _load_json_dictionary(SHIP_STATS_DATA_PATH),
		"enemy_spawn_rules": _load_json_dictionary(ENEMY_SPAWN_RULES_DATA_PATH)
	}


static func _describe_palette_block_schema(palette: Dictionary) -> String:
	var version := int(palette.get("block_schema_version", 0))
	var blocks := _array_from(palette.get("assembly_blocks", []))
	var action_count := 0
	var meta_count := 0
	var reference_count := 0
	var slots: Array[String] = []
	for block_variant in blocks:
		var block := _dictionary_from(block_variant)
		if block.is_empty():
			continue
		match str(block.get("kind", "")).strip_edges():
			"action":
				action_count += 1
			"authoring_meta":
				meta_count += 1
			_:
				reference_count += 1
		var slot := str(block.get("slot", "")).strip_edges()
		if not slot.is_empty() and not slots.has(slot):
			slots.append(slot)
	var slot_text := ", ".join(slots) if not slots.is_empty() else "-"
	return "블록 스키마 v%d: 실행=%d / 카드=%d / 참조=%d | 슬롯=%s" % [
		version,
		action_count,
		meta_count,
		reference_count,
		slot_text
	]


static func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


static func _add_palette_ship_type_buttons(hud, body: VBoxContainer, entries_variant: Variant, preview_label: Label, selected_label: Label, execute_button: Button, source_data: Dictionary) -> void:
	var specs: Array[Dictionary] = []
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		if not _palette_entry_has_tag(entry, "enemy") or _palette_entry_has_tag(entry, "boss"):
			continue
		var ship_type := str(entry.get("id", "")).strip_edges()
		if ship_type.is_empty():
			continue
		var button_text := _palette_button_text(entry)
		var preview_text: String = _describe_palette_ship_type(entry, source_data)
		var action: Dictionary = {
			"type": "spawn_ship",
			"ship_type": ship_type,
			"distance": 40.0,
			"lateral_offset": 0.0
		}
		specs.append({
			"text": button_text,
			"selected": "함선: %s" % button_text,
			"preview": preview_text,
			"action": action,
			"callback": _make_palette_action_callback(hud, action)
		})
	_add_palette_group(hud, body, "함선", specs, 2, preview_label, selected_label, execute_button)


static func _add_palette_recipe_buttons(hud, body: VBoxContainer, entries_variant: Variant, preview_label: Label, selected_label: Label, execute_button: Button, source_data: Dictionary) -> void:
	var specs: Array[Dictionary] = []
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var recipe_name := str(entry.get("id", "")).strip_edges()
		if recipe_name.is_empty():
			continue
		var button_text := _palette_button_text(entry)
		var preview_text: String = _describe_palette_recipe(entry, source_data)
		var action: Dictionary = {
			"type": "spawn_recipe",
			"recipe": recipe_name
		}
		specs.append({
			"text": button_text,
			"selected": "편대: %s" % button_text,
			"preview": preview_text,
			"action": action,
			"callback": _make_palette_action_callback(hud, action)
		})
	_add_palette_group(hud, body, "편대 레시피", specs, 2, preview_label, selected_label, execute_button)


static func _add_palette_combat_profile_buttons(hud, body: VBoxContainer, entries_variant: Variant, preview_label: Label, selected_label: Label, execute_button: Button, source_data: Dictionary) -> void:
	var specs: Array[Dictionary] = []
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var profile_id := str(entry.get("id", "")).strip_edges()
		if profile_id.is_empty():
			continue
		var button_text := _palette_button_text(entry)
		specs.append({
			"text": button_text,
			"selected": "전투 모드: %s" % button_text,
			"preview": _describe_palette_combat_profile(entry, source_data),
			"authoring": _make_palette_reference_authoring_meta("combat_profile", entry)
		})
	_add_palette_reference_group(hud, body, "전투 모드", specs, 2, preview_label, selected_label, execute_button)


static func _add_palette_movement_intent_buttons(hud, body: VBoxContainer, entries_variant: Variant, preview_label: Label, selected_label: Label, execute_button: Button) -> void:
	var specs: Array[Dictionary] = []
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var intent_id := str(entry.get("id", "")).strip_edges()
		if intent_id.is_empty():
			continue
		var button_text := _palette_button_text(entry)
		specs.append({
			"text": button_text,
			"selected": "이동 의도: %s" % button_text,
			"preview": _describe_palette_movement_intent(entry),
			"authoring": _make_palette_reference_authoring_meta("movement_intent", entry)
		})
	_add_palette_reference_group(hud, body, "이동 의도", specs, 2, preview_label, selected_label, execute_button)


static func _add_palette_profile_buttons(hud, body: VBoxContainer, entries_variant: Variant, preview_label: Label, selected_label: Label, execute_button: Button, source_data: Dictionary) -> void:
	var specs: Array[Dictionary] = []
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var profile_name := str(entry.get("id", "")).strip_edges()
		if profile_name.is_empty():
			continue
		var button_text := _palette_button_text(entry)
		var preview_text: String = _describe_palette_profile(entry, source_data)
		var action: Dictionary = {
			"type": "set_encounter_profile",
			"profile": profile_name
		}
		specs.append({
			"text": button_text,
			"selected": "전개: %s" % button_text,
			"preview": preview_text,
			"action": action,
			"callback": _make_palette_action_callback(hud, action)
		})
	_add_palette_group(hud, body, "전개 프로필", specs, 1, preview_label, selected_label, execute_button)


static func _add_palette_trigger_buttons(hud, body: VBoxContainer, entries_variant: Variant, preview_label: Label, selected_label: Label, execute_button: Button, source_data: Dictionary) -> void:
	var specs: Array[Dictionary] = []
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var trigger_id := str(entry.get("id", "")).strip_edges()
		if trigger_id.is_empty():
			continue
		var button_text := _palette_button_text(entry)
		var preview_text: String = _describe_palette_trigger(entry, source_data)
		var action: Dictionary = {
			"type": "run_scenario_trigger",
			"trigger": trigger_id
		}
		specs.append({
			"text": button_text,
			"selected": "트리거: %s" % button_text,
			"preview": preview_text,
			"action": action,
			"callback": _make_palette_action_callback(hud, action)
		})
	_add_palette_group(hud, body, "트리거 실행", specs, 1, preview_label, selected_label, execute_button)


static func _add_palette_group(hud, body: VBoxContainer, title_text: String, button_specs: Array[Dictionary], columns: int, preview_label: Label, selected_label: Label, execute_button: Button) -> void:
	if button_specs.is_empty():
		return
	var title := Label.new()
	title.text = title_text
	NavalUiTheme.style_muted(title, 10)
	body.add_child(title)

	var safe_columns: int = maxi(1, columns)
	var row: HBoxContainer = null
	for index in range(button_specs.size()):
		if index % safe_columns == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			body.add_child(row)
		var spec: Dictionary = button_specs[index]
		var callback: Callable = spec.get("callback", Callable())
		if not callback.is_valid():
			continue
		var description := str(spec.get("preview", ""))
		var selected_text := str(spec.get("selected", spec.get("text", "-")))
		var action: Dictionary = _dictionary_from(spec.get("action", {})).duplicate(true)
		var button := _create_palette_select_button(
			hud,
			str(spec.get("text", "-")),
			selected_label,
			execute_button,
			selected_text,
			description,
			callback,
			action
		)
		_wire_palette_preview(button, preview_label, description)
		row.add_child(button)


static func _add_palette_reference_group(hud, body: VBoxContainer, title_text: String, button_specs: Array[Dictionary], columns: int, preview_label: Label, selected_label: Label, execute_button: Button) -> void:
	if button_specs.is_empty():
		return
	var title := Label.new()
	title.text = title_text
	NavalUiTheme.style_muted(title, 10)
	body.add_child(title)

	var safe_columns: int = maxi(1, columns)
	var row: HBoxContainer = null
	for index in range(button_specs.size()):
		if index % safe_columns == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			body.add_child(row)
		var spec: Dictionary = button_specs[index]
		var description := str(spec.get("preview", ""))
		var selected_text := str(spec.get("selected", spec.get("text", "-")))
		var authoring_meta: Dictionary = _normalize_palette_action_authoring_meta(spec.get("authoring", {}))
		var button := _create_palette_reference_button(
			hud,
			str(spec.get("text", "-")),
			selected_label,
			execute_button,
			selected_text,
			description,
			authoring_meta
		)
		_wire_palette_preview(button, preview_label, description)
		row.add_child(button)


static func _make_level_debug_callback(hud, method_name: String, args: Array = []) -> Callable:
	return func() -> void:
		hud._invoke_level_debug_method(method_name, args)


static func _make_palette_action_callback(hud, action: Dictionary) -> Callable:
	var normalized_action := _normalize_palette_queue_action(action)
	var action_type := str(normalized_action.get("type", ""))
	match action_type:
		"spawn_ship":
			return _make_level_debug_callback(hud, "_debug_spawn_test_ship", [
				str(normalized_action.get("ship_type", "")),
				float(normalized_action.get("distance", 40.0)),
				float(normalized_action.get("lateral_offset", 0.0)),
				_normalize_palette_action_authoring_meta(normalized_action.get("authoring", {}))
			])
		"spawn_recipe":
			return _make_level_debug_callback(hud, "_debug_spawn_recipe", [
				str(normalized_action.get("recipe", "")),
				_normalize_palette_action_authoring_meta(normalized_action.get("authoring", {}))
			])
		"set_encounter_profile":
			return _make_level_debug_callback(hud, "_debug_set_encounter_profile", [str(normalized_action.get("profile", ""))])
		"run_scenario_trigger":
			return _make_level_debug_callback(hud, "_debug_run_scenario_trigger", [str(normalized_action.get("trigger", ""))])
	return Callable()


static func _create_palette_select_button(hud, button_text: String, selected_label: Label, execute_button: Button, selected_text: String, description: String, callback: Callable, action: Dictionary) -> Button:
	return create_debug_action_button(button_text, func() -> void:
		_select_palette_action(hud, selected_label, execute_button, selected_text, description, callback, action)
	)


static func _create_palette_reference_button(hud, button_text: String, selected_label: Label, execute_button: Button, selected_text: String, description: String, authoring_meta: Dictionary) -> Button:
	return create_debug_action_button(button_text, func() -> void:
		_select_palette_reference(hud, selected_label, execute_button, selected_text, description, authoring_meta)
	)


static func _select_palette_action(hud, selected_label: Label, execute_button: Button, selected_text: String, description: String, callback: Callable, action: Dictionary) -> void:
	if not callback.is_valid():
		return
	hud.debug_authoring_palette_selected_callback = callback
	hud.debug_authoring_palette_selected_action = _normalize_palette_queue_action(action)
	if is_instance_valid(selected_label):
		selected_label.text = "선택: %s" % selected_text
	if is_instance_valid(hud.debug_authoring_palette_preview_value):
		hud.debug_authoring_palette_preview_value.text = description
	if is_instance_valid(execute_button):
		execute_button.disabled = false
	if is_instance_valid(hud.debug_authoring_palette_queue_add_button):
		hud.debug_authoring_palette_queue_add_button.disabled = false


static func _select_palette_reference(hud, selected_label: Label, execute_button: Button, selected_text: String, description: String, authoring_meta: Dictionary) -> void:
	hud.debug_authoring_palette_selected_callback = Callable()
	hud.debug_authoring_palette_selected_action = {}
	_merge_palette_assembly_reference(hud, authoring_meta)
	if is_instance_valid(selected_label):
		selected_label.text = "선택: %s" % selected_text
	if is_instance_valid(hud.debug_authoring_palette_preview_value):
		hud.debug_authoring_palette_preview_value.text = description
	if is_instance_valid(execute_button):
		execute_button.disabled = true
	if is_instance_valid(hud.debug_authoring_palette_queue_add_button):
		hud.debug_authoring_palette_queue_add_button.disabled = true


static func _merge_palette_assembly_reference(hud, authoring_meta: Dictionary) -> void:
	var current: Dictionary = _normalize_palette_action_authoring_meta(hud.debug_authoring_palette_assembly_meta)
	var next_meta: Dictionary = _normalize_palette_action_authoring_meta(authoring_meta)
	if next_meta.has("combat_profile"):
		current["combat_profile"] = str(next_meta.get("combat_profile", ""))
		current["combat_profile_label"] = str(next_meta.get("combat_profile_label", current.get("combat_profile", "")))
	if next_meta.has("movement_intent"):
		current["movement_intent"] = str(next_meta.get("movement_intent", ""))
		current["movement_intent_label"] = str(next_meta.get("movement_intent_label", current.get("movement_intent", "")))
		current["movement_family"] = str(next_meta.get("movement_family", ""))
		current["movement_mode"] = str(next_meta.get("movement_mode", ""))
		if next_meta.has("movement_speed_min"):
			current["movement_speed_min"] = float(next_meta.get("movement_speed_min", 0.0))
		if next_meta.has("movement_speed_max"):
			current["movement_speed_max"] = float(next_meta.get("movement_speed_max", 0.0))
		if next_meta.has("movement_sprint"):
			current["movement_sprint"] = next_meta.get("movement_sprint") == true
	hud.debug_authoring_palette_assembly_meta = current
	_sync_palette_assembly_ui(hud)


static func _clear_palette_assembly(hud) -> void:
	hud.debug_authoring_palette_assembly_meta = {}
	_sync_palette_assembly_ui(hud)
	_set_palette_preview_status(hud, "조립 카드 비움")


static func _sync_palette_assembly_ui(hud) -> void:
	if not is_instance_valid(hud.debug_authoring_palette_assembly_value):
		return
	var meta: Dictionary = _normalize_palette_action_authoring_meta(hud.debug_authoring_palette_assembly_meta)
	var combat_label := str(meta.get("combat_profile_label", "-")).strip_edges()
	if combat_label.is_empty():
		combat_label = "-"
	var movement_label := str(meta.get("movement_intent_label", "-")).strip_edges()
	if movement_label.is_empty():
		movement_label = "-"
	var movement_family := str(meta.get("movement_family", "")).strip_edges()
	if movement_label != "-" and not movement_family.is_empty():
		movement_label = "%s (%s)" % [movement_label, movement_family]
	hud.debug_authoring_palette_assembly_value.text = "조립 카드: 전투=%s / 이동=%s" % [combat_label, movement_label]


static func _clear_palette_selection(hud) -> void:
	hud.debug_authoring_palette_selected_callback = Callable()
	hud.debug_authoring_palette_selected_action = {}
	if is_instance_valid(hud.debug_authoring_palette_selected_value):
		hud.debug_authoring_palette_selected_value.text = "선택: -"
	if is_instance_valid(hud.debug_authoring_palette_preview_value):
		hud.debug_authoring_palette_preview_value.text = "팔레트 항목에 마우스를 올리면 조립 내용이 표시됩니다."
	if is_instance_valid(hud.debug_authoring_palette_execute_button):
		hud.debug_authoring_palette_execute_button.disabled = true
	if is_instance_valid(hud.debug_authoring_palette_queue_add_button):
		hud.debug_authoring_palette_queue_add_button.disabled = true


static func _add_selected_palette_action_to_queue(hud) -> void:
	var selected_callback: Callable = hud.debug_authoring_palette_selected_callback
	if not selected_callback.is_valid() or not is_instance_valid(hud.debug_authoring_palette_selected_value):
		return
	var selected_text := str(hud.debug_authoring_palette_selected_value.text)
	if selected_text.begins_with("선택: "):
		selected_text = selected_text.substr("선택: ".length())
	selected_text = selected_text.strip_edges()
	if selected_text.is_empty() or selected_text == "-":
		return
	var selected_action: Dictionary = _normalize_palette_queue_action(hud.debug_authoring_palette_selected_action)
	if selected_action.is_empty():
		return
	selected_action["label"] = selected_text
	selected_action = _apply_palette_assembly_to_action(selected_action, hud.debug_authoring_palette_assembly_meta)
	hud.debug_authoring_palette_queue_entries.append({
		"text": _format_palette_action_display_text(selected_action),
		"callback": selected_callback,
		"action": selected_action
	})
	hud.debug_authoring_palette_queue_selected_index = hud.debug_authoring_palette_queue_entries.size() - 1
	_sync_palette_queue_ui(hud)


static func _execute_palette_queue(hud) -> void:
	_execute_palette_entries(hud, hud.debug_authoring_palette_queue_entries)


static func _execute_palette_entries(hud, entries: Array[Dictionary]) -> int:
	var executed_count := 0
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var callback: Callable = entry.get("callback", Callable())
		if not callback.is_valid():
			callback = _make_palette_action_callback(hud, _dictionary_from(entry.get("action", {})))
		if callback.is_valid():
			callback.call()
			executed_count += 1
	return executed_count


static func _clear_palette_queue(hud) -> void:
	hud.debug_authoring_palette_queue_entries.clear()
	hud.debug_authoring_palette_queue_selected_index = -1
	_sync_palette_queue_ui(hud)


static func _select_palette_queue_entry(hud, index: int) -> void:
	if hud.debug_authoring_palette_queue_entries.is_empty():
		hud.debug_authoring_palette_queue_selected_index = -1
		_sync_palette_queue_ui(hud)
		return
	hud.debug_authoring_palette_queue_selected_index = clampi(index, 0, hud.debug_authoring_palette_queue_entries.size() - 1)
	_sync_palette_queue_ui(hud)
	var selected_entry: Dictionary = hud.debug_authoring_palette_queue_entries[hud.debug_authoring_palette_queue_selected_index]
	_set_palette_preview_status(hud, "큐 선택: %d. %s" % [
		hud.debug_authoring_palette_queue_selected_index + 1,
		str(selected_entry.get("text", "-"))
	])


static func _move_selected_palette_queue_entry(hud, direction: int) -> void:
	var entries: Array[Dictionary] = hud.debug_authoring_palette_queue_entries
	if entries.size() <= 1:
		return
	var current_index := clampi(hud.debug_authoring_palette_queue_selected_index, 0, entries.size() - 1)
	var target_index := clampi(current_index + direction, 0, entries.size() - 1)
	if current_index == target_index:
		return
	var moved_entry: Dictionary = entries[current_index]
	entries.remove_at(current_index)
	entries.insert(target_index, moved_entry)
	hud.debug_authoring_palette_queue_selected_index = target_index
	_sync_palette_queue_ui(hud)
	_set_palette_preview_status(hud, "큐 이동: %d. %s" % [
		target_index + 1,
		str(moved_entry.get("text", "-"))
	])


static func _duplicate_selected_palette_queue_entry(hud) -> void:
	var entries: Array[Dictionary] = hud.debug_authoring_palette_queue_entries
	if entries.is_empty():
		return
	var current_index := clampi(hud.debug_authoring_palette_queue_selected_index, 0, entries.size() - 1)
	var source_entry: Dictionary = entries[current_index]
	var source_action: Dictionary = _normalize_palette_queue_action(source_entry.get("action", {}))
	if source_action.is_empty():
		return
	var duplicate_entry := {
		"text": _format_palette_action_display_text(source_action),
		"callback": _make_palette_action_callback(hud, source_action),
		"action": source_action.duplicate(true)
	}
	var insert_index := current_index + 1
	entries.insert(insert_index, duplicate_entry)
	hud.debug_authoring_palette_queue_selected_index = insert_index
	_sync_palette_queue_ui(hud)
	_set_palette_preview_status(hud, "큐 복제: %d. %s" % [
		insert_index + 1,
		str(duplicate_entry.get("text", "-"))
	])


static func _delete_selected_palette_queue_entry(hud) -> void:
	var entries: Array[Dictionary] = hud.debug_authoring_palette_queue_entries
	if entries.is_empty():
		return
	var current_index := clampi(hud.debug_authoring_palette_queue_selected_index, 0, entries.size() - 1)
	var deleted_entry: Dictionary = entries[current_index]
	entries.remove_at(current_index)
	hud.debug_authoring_palette_queue_selected_index = min(current_index, entries.size() - 1) if not entries.is_empty() else -1
	_sync_palette_queue_ui(hud)
	_set_palette_preview_status(hud, "큐 삭제: %s" % str(deleted_entry.get("text", "-")))


static func _save_palette_queue(hud) -> void:
	var actions := _build_palette_queue_actions(hud.debug_authoring_palette_queue_entries)
	var root := {
		"format": "battleship_authoring_palette_queue",
		"version": 1,
		"actions": actions
	}
	var file := FileAccess.open(AUTHORING_QUEUE_USER_PATH, FileAccess.WRITE)
	if file == null:
		_set_palette_preview_status(hud, "큐 저장 실패: %s" % AUTHORING_QUEUE_USER_PATH)
		return
	file.store_string(JSON.stringify(root, "\t"))
	_set_palette_preview_status(hud, "큐 저장: %d개 -> %s" % [actions.size(), AUTHORING_QUEUE_USER_PATH])


static func _save_palette_queue_as_scenario_trigger(hud) -> void:
	var trigger := _build_scenario_trigger_from_palette_queue(hud.debug_authoring_palette_queue_entries)
	var actions: Array = _array_from(trigger.get("actions", []))
	var root := {
		"format": "battleship_authoring_scenario_trigger",
		"version": 1,
		"scenario_triggers": [trigger]
	}
	var file := FileAccess.open(AUTHORING_SCENARIO_TRIGGER_USER_PATH, FileAccess.WRITE)
	if file == null:
		_set_palette_preview_status(hud, "트리거 저장 실패: %s" % AUTHORING_SCENARIO_TRIGGER_USER_PATH)
		return
	file.store_string(JSON.stringify(root, "\t"))
	_set_palette_preview_status(hud, "트리거 저장: %d개 -> %s" % [actions.size(), AUTHORING_SCENARIO_TRIGGER_USER_PATH])


static func _save_palette_queue_as_scenario_preset(hud) -> void:
	var queue_actions := _build_palette_queue_actions(hud.debug_authoring_palette_queue_entries)
	if queue_actions.is_empty():
		_set_palette_preview_status(hud, "프리셋 저장 실패: 큐 없음")
		return
	var trigger := _build_scenario_trigger_from_queue_actions(queue_actions)
	var preset_id := str(trigger.get("id", PALETTE_PRESET_FALLBACK_ID)).strip_edges()
	var preset_label := str(trigger.get("label", preset_id)).strip_edges()
	var preset := {
		"id": preset_id,
		"label": preset_label,
		"queue_actions": queue_actions,
		"trigger": trigger
	}
	var root := _load_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	var presets := _array_from(root.get("presets", []))
	var updated := false
	for index in range(presets.size()):
		var preset_variant: Variant = presets[index]
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var existing: Dictionary = preset_variant as Dictionary
		if str(existing.get("id", "")).strip_edges() != preset_id:
			continue
		presets[index] = preset
		updated = true
		break
	if not updated:
		presets.append(preset)
	var output := {
		"format": "battleship_authoring_scenario_presets",
		"version": 1,
		"active_preset": preset_id,
		"presets": presets
	}
	var file := FileAccess.open(AUTHORING_SCENARIO_PRESETS_USER_PATH, FileAccess.WRITE)
	if file == null:
		_set_palette_preview_status(hud, "프리셋 저장 실패: %s" % AUTHORING_SCENARIO_PRESETS_USER_PATH)
		return
	file.store_string(JSON.stringify(output, "\t"))
	_sync_palette_preset_ui(hud)
	_set_palette_preview_status(hud, "프리셋 저장: %s (%d개) -> %s" % [preset_label, queue_actions.size(), AUTHORING_SCENARIO_PRESETS_USER_PATH])


static func _load_active_scenario_preset_to_queue(hud) -> void:
	var root: Dictionary = _load_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		_set_palette_preview_status(hud, "프리셋 불러오기 실패: %s" % AUTHORING_SCENARIO_PRESETS_USER_PATH)
		return
	var preset := _get_selected_or_active_scenario_preset(hud, root)
	if preset.is_empty():
		_set_palette_preview_status(hud, "프리셋 불러오기 실패: 항목 없음")
		return
	var queue_actions := _get_queue_actions_from_scenario_preset(preset)
	var imported_entries := _build_palette_queue_entries_from_actions(hud, queue_actions)
	if imported_entries.is_empty():
		_set_palette_preview_status(hud, "프리셋 불러오기 실패: 실행 가능한 액션 없음")
		return
	hud.debug_authoring_palette_queue_entries = imported_entries
	hud.debug_authoring_palette_queue_selected_index = 0 if not imported_entries.is_empty() else -1
	_sync_palette_queue_ui(hud)
	_sync_palette_preset_ui(hud)
	var preset_label := str(preset.get("label", preset.get("id", "-"))).strip_edges()
	_set_palette_preview_status(hud, "프리셋 불러오기: %s (%d개) <- %s" % [preset_label, imported_entries.size(), AUTHORING_SCENARIO_PRESETS_USER_PATH])


static func _execute_selected_scenario_preset(hud) -> void:
	var root: Dictionary = _load_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		_set_palette_preview_status(hud, "프리셋 실행 실패: %s" % AUTHORING_SCENARIO_PRESETS_USER_PATH)
		return
	var preset := _get_selected_or_active_scenario_preset(hud, root)
	if preset.is_empty():
		_set_palette_preview_status(hud, "프리셋 실행 실패: 항목 없음")
		return
	var queue_actions := _get_queue_actions_from_scenario_preset(preset)
	var entries := _build_palette_queue_entries_from_actions(hud, queue_actions)
	if entries.is_empty():
		_set_palette_preview_status(hud, "프리셋 실행 실패: 실행 가능한 액션 없음")
		return
	var executed_count := _execute_palette_entries(hud, entries)
	_sync_palette_preset_ui(hud)
	var preset_label := str(preset.get("label", preset.get("id", "-"))).strip_edges()
	_set_palette_preview_status(hud, "프리셋 실행: %s (%d개)" % [preset_label, executed_count])


static func _promote_selected_scenario_preset_to_data_patch(hud) -> void:
	var root: Dictionary = _load_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		_set_palette_preview_status(hud, "데이터 승격 실패: %s" % AUTHORING_SCENARIO_PRESETS_USER_PATH)
		return
	var preset := _get_selected_or_active_scenario_preset(hud, root)
	if preset.is_empty():
		_set_palette_preview_status(hud, "데이터 승격 실패: 항목 없음")
		return
	var queue_actions := _get_queue_actions_from_scenario_preset(preset)
	if queue_actions.is_empty():
		_set_palette_preview_status(hud, "데이터 승격 실패: 실행 가능한 액션 없음")
		return
	var trigger: Dictionary = _dictionary_from(preset.get("trigger", {})).duplicate(true)
	if trigger.is_empty():
		trigger = _build_scenario_trigger_from_queue_actions(queue_actions)
	if trigger.is_empty():
		_set_palette_preview_status(hud, "데이터 승격 실패: 트리거 없음")
		return
	var trigger_actions := _array_from(trigger.get("actions", []))
	if trigger_actions.is_empty():
		trigger_actions = _build_scenario_actions_from_queue_actions(queue_actions)
		trigger["actions"] = trigger_actions
	if trigger_actions.is_empty():
		_set_palette_preview_status(hud, "데이터 승격 실패: 트리거 액션 없음")
		return
	var preset_id := str(preset.get("id", trigger.get("id", PALETTE_PRESET_FALLBACK_ID))).strip_edges()
	if preset_id.is_empty():
		preset_id = PALETTE_PRESET_FALLBACK_ID
	var preset_label := str(preset.get("label", trigger.get("label", preset_id))).strip_edges()
	if preset_label.is_empty():
		preset_label = preset_id
	if str(trigger.get("id", "")).strip_edges().is_empty():
		trigger["id"] = preset_id
	if str(trigger.get("label", "")).strip_edges().is_empty():
		trigger["label"] = preset_label
	var output := {
		"format": "battleship_authoring_data_patch",
		"version": 1,
		"target_path": ENEMY_SPAWN_RULES_DATA_PATH,
		"merge_key": "scenario_triggers",
		"source_preset": {
			"id": preset_id,
			"label": preset_label,
			"queue_actions": queue_actions
		},
		"enemy_spawn_rules_patch": {
			"scenario_triggers": [trigger]
		},
		"scenario_triggers": [trigger]
	}
	var file := FileAccess.open(AUTHORING_DATA_PATCH_USER_PATH, FileAccess.WRITE)
	if file == null:
		_set_palette_preview_status(hud, "데이터 승격 실패: %s" % AUTHORING_DATA_PATCH_USER_PATH)
		return
	file.store_string(JSON.stringify(output, "\t"))
	_sync_palette_preset_ui(hud)
	_set_palette_preview_status(hud, "데이터 승격: %s (%d개) -> %s" % [preset_label, trigger_actions.size(), AUTHORING_DATA_PATCH_USER_PATH])


static func _check_authoring_data_patch(hud) -> void:
	var root: Dictionary = _load_json_dictionary(AUTHORING_DATA_PATCH_USER_PATH)
	if root.is_empty():
		_set_palette_preview_status(hud, "패치 점검 실패: %s" % AUTHORING_DATA_PATCH_USER_PATH)
		return
	_set_palette_preview_status(hud, _format_authoring_data_patch_check_result(_validate_authoring_data_patch(root)))


static func _merge_authoring_data_patch(hud) -> void:
	var patch_root: Dictionary = _load_json_dictionary(AUTHORING_DATA_PATCH_USER_PATH)
	if patch_root.is_empty():
		_set_palette_preview_status(hud, "패치 병합 실패: %s" % AUTHORING_DATA_PATCH_USER_PATH)
		return
	var check_result := _validate_authoring_data_patch(patch_root)
	var errors := _array_from(check_result.get("errors", []))
	var conflicts := _array_from(check_result.get("conflicts", []))
	if not errors.is_empty() or not conflicts.is_empty():
		_set_palette_preview_status(hud, _format_authoring_data_patch_merge_blocked(check_result))
		return
	var patch_triggers := _get_authoring_data_patch_triggers(patch_root)
	if patch_triggers.is_empty():
		_set_palette_preview_status(hud, "패치 병합 실패: scenario_triggers 없음")
		return
	var original_spawn_rules := _load_json_dictionary(ENEMY_SPAWN_RULES_DATA_PATH).duplicate(true)
	if original_spawn_rules.is_empty():
		_set_palette_preview_status(hud, "패치 병합 실패: %s" % ENEMY_SPAWN_RULES_DATA_PATH)
		return
	var merged_spawn_rules := original_spawn_rules.duplicate(true)
	var existing_triggers := _array_from(merged_spawn_rules.get("scenario_triggers", []))
	for trigger_variant in patch_triggers:
		if typeof(trigger_variant) == TYPE_DICTIONARY:
			existing_triggers.append((trigger_variant as Dictionary).duplicate(true))
	merged_spawn_rules["scenario_triggers"] = existing_triggers

	var palette := _load_json_dictionary(AUTHORING_PALETTE_DATA_PATH).duplicate(true)
	if palette.is_empty():
		_set_palette_preview_status(hud, "패치 병합 실패: %s" % AUTHORING_PALETTE_DATA_PATH)
		return
	var palette_added := _merge_authoring_palette_trigger_entries(palette, patch_triggers)

	if not _write_json_dictionary(ENEMY_SPAWN_RULES_DATA_PATH, merged_spawn_rules):
		_set_palette_preview_status(hud, "패치 병합 실패: %s" % ENEMY_SPAWN_RULES_DATA_PATH)
		return
	if not _write_json_dictionary(AUTHORING_PALETTE_DATA_PATH, palette):
		_write_json_dictionary(ENEMY_SPAWN_RULES_DATA_PATH, original_spawn_rules)
		_set_palette_preview_status(hud, "패치 병합 실패: 팔레트 저장 실패(데이터 복원)")
		return
	_set_palette_preview_status(hud, "패치 병합: 트리거 %d개 / 팔레트 %d개 -> %s" % [
		patch_triggers.size(),
		palette_added,
		ENEMY_SPAWN_RULES_DATA_PATH
	])


static func _validate_authoring_data_patch(root: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var conflicts: Array[String] = []
	var warnings: Array[String] = []
	var trigger_count := 0
	var action_count := 0

	if str(root.get("format", "")).strip_edges() != "battleship_authoring_data_patch":
		errors.append("format 불일치")
	if str(root.get("target_path", "")).strip_edges() != ENEMY_SPAWN_RULES_DATA_PATH:
		errors.append("target_path 불일치")

	var patch := _dictionary_from(root.get("enemy_spawn_rules_patch", {}))
	var triggers := _array_from(patch.get("scenario_triggers", []))
	if triggers.is_empty():
		triggers = _array_from(root.get("scenario_triggers", []))
	if triggers.is_empty():
		errors.append("scenario_triggers 없음")

	var source_data := load_authoring_palette_source_data()
	var ship_stats := _dictionary_from(source_data.get("ship_stats", {}))
	var combat_profiles := _dictionary_from(ship_stats.get("combat_profiles", {}))
	var spawn_rules := _dictionary_from(source_data.get("enemy_spawn_rules", {}))
	var spawn_recipes := _dictionary_from(spawn_rules.get("spawn_recipes", {}))
	var encounter_profiles := _dictionary_from(spawn_rules.get("encounter_profiles", {}))
	var formation := _dictionary_from(spawn_rules.get("formation", {}))
	var fleet_templates := _dictionary_from(formation.get("fleet_templates", {}))
	var movement_intents := _collect_palette_movement_intent_ids(load_authoring_palette())
	var existing_trigger_ids := _collect_authoring_trigger_ids(_array_from(spawn_rules.get("scenario_triggers", [])))
	var patch_trigger_ids: Dictionary = {}

	for index in range(triggers.size()):
		var trigger_variant: Variant = triggers[index]
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			errors.append("scenario_triggers[%d] 형식 오류" % index)
			continue
		trigger_count += 1
		var trigger: Dictionary = trigger_variant as Dictionary
		var trigger_id := str(trigger.get("id", trigger.get("name", ""))).strip_edges()
		if trigger_id.is_empty():
			errors.append("scenario_triggers[%d] id 없음" % index)
			continue
		if patch_trigger_ids.has(trigger_id):
			errors.append("scenario_triggers[%d] 중복 id=%s" % [index, trigger_id])
		else:
			patch_trigger_ids[trigger_id] = true
		if existing_trigger_ids.has(trigger_id):
			conflicts.append("기존 트리거 id=%s" % trigger_id)

	for index in range(triggers.size()):
		var trigger_variant: Variant = triggers[index]
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			continue
		var trigger: Dictionary = trigger_variant as Dictionary
		var trigger_id := str(trigger.get("id", trigger.get("name", ""))).strip_edges()
		var label := "scenario_triggers[%d]" % index
		var condition := _dictionary_from(trigger.get("condition", {}))
		if condition.is_empty():
			errors.append("%s condition 없음" % label)
		elif float(condition.get("elapsed_time", -1.0)) < 0.0:
			errors.append("%s condition.elapsed_time < 0" % label)
		var actions := _array_from(trigger.get("actions", []))
		if actions.is_empty():
			errors.append("%s actions 없음" % label)
			continue
		action_count += actions.size()
		for action_index in range(actions.size()):
			_validate_authoring_data_patch_action(
				"%s.actions[%d]" % [label, action_index],
				actions[action_index],
				trigger_id,
				ship_stats,
				combat_profiles,
				movement_intents,
				spawn_recipes,
				encounter_profiles,
				fleet_templates,
				existing_trigger_ids,
				patch_trigger_ids,
				errors
			)

	if not errors.is_empty():
		warnings.append("오류를 고친 뒤 다시 승격하세요")
	elif not conflicts.is_empty():
		warnings.append("같은 id를 덮어쓸지 새 id로 바꿀지 결정하세요")
	return {
		"trigger_count": trigger_count,
		"action_count": action_count,
		"errors": errors,
		"conflicts": conflicts,
		"warnings": warnings
	}


static func _validate_authoring_data_patch_action(label: String, action_variant: Variant, current_trigger_id: String, ship_stats: Dictionary, combat_profiles: Dictionary, movement_intents: Dictionary, spawn_recipes: Dictionary, encounter_profiles: Dictionary, fleet_templates: Dictionary, existing_trigger_ids: Dictionary, patch_trigger_ids: Dictionary, errors: Array[String]) -> void:
	if typeof(action_variant) != TYPE_DICTIONARY:
		errors.append("%s 형식 오류" % label)
		return
	var action: Dictionary = action_variant as Dictionary
	var action_type := str(action.get("type", "")).strip_edges()
	if not ["set_encounter_profile", "spawn_fleet", "spawn_recipe", "spawn_ship", "run_scenario_trigger", "spawn_mid_boss", "trigger_boss_event", "stop_regular_spawns"].has(action_type):
		errors.append("%s 지원하지 않는 type=%s" % [label, action_type])
		return
	match action_type:
		"set_encounter_profile":
			var profile_name := str(action.get("profile", "")).strip_edges()
			if profile_name.is_empty() or not encounter_profiles.has(profile_name):
				errors.append("%s 알 수 없는 profile=%s" % [label, profile_name])
		"spawn_fleet":
			var fleet_class := str(action.get("fleet_class", "")).strip_edges()
			if fleet_class.is_empty() or not fleet_templates.has(fleet_class):
				errors.append("%s 알 수 없는 fleet_class=%s" % [label, fleet_class])
		"spawn_recipe":
			var recipe_name := str(action.get("recipe", "")).strip_edges()
			if recipe_name.is_empty() or not spawn_recipes.has(recipe_name):
				errors.append("%s 알 수 없는 recipe=%s" % [label, recipe_name])
		"spawn_ship":
			var ship_type := str(action.get("ship_type", "")).strip_edges()
			if ship_type.is_empty() or not ship_stats.has(ship_type):
				errors.append("%s 알 수 없는 ship_type=%s" % [label, ship_type])
		"run_scenario_trigger":
			var trigger_id := str(action.get("trigger", "")).strip_edges()
			if trigger_id.is_empty():
				errors.append("%s trigger 없음" % label)
			elif trigger_id == current_trigger_id:
				errors.append("%s 자기 자신 실행: %s" % [label, trigger_id])
			elif not existing_trigger_ids.has(trigger_id) and not patch_trigger_ids.has(trigger_id):
				errors.append("%s 알 수 없는 trigger=%s" % [label, trigger_id])
	_validate_authoring_action_meta(label, action, combat_profiles, movement_intents, errors)


static func _validate_authoring_action_meta(label: String, action: Dictionary, combat_profiles: Dictionary, movement_intents: Dictionary, errors: Array[String]) -> void:
	if not action.has("authoring"):
		return
	var authoring_variant: Variant = action.get("authoring", {})
	if typeof(authoring_variant) != TYPE_DICTIONARY:
		errors.append("%s authoring 형식 오류" % label)
		return
	var authoring: Dictionary = authoring_variant as Dictionary
	var combat_profile := str(authoring.get("combat_profile", "")).strip_edges()
	if not combat_profile.is_empty() and not combat_profiles.has(combat_profile):
		errors.append("%s 알 수 없는 authoring.combat_profile=%s" % [label, combat_profile])
	var movement_intent := str(authoring.get("movement_intent", "")).strip_edges()
	if not movement_intent.is_empty() and not movement_intents.has(movement_intent):
		errors.append("%s 알 수 없는 authoring.movement_intent=%s" % [label, movement_intent])
	elif not movement_intent.is_empty():
		var movement_entry := _dictionary_from(movement_intents.get(movement_intent, {}))
		var expected_family := str(movement_entry.get("family", "")).strip_edges()
		var movement_family := str(authoring.get("movement_family", authoring.get("family", ""))).strip_edges()
		if not movement_family.is_empty() and movement_family != expected_family:
			errors.append("%s authoring.movement_family 불일치 %s != %s" % [label, movement_family, expected_family])
	var has_movement_speed := authoring.has("movement_speed_min") or authoring.has("movement_speed_max")
	if has_movement_speed:
		if movement_intent.is_empty():
			errors.append("%s authoring 이동 속도에는 movement_intent가 필요합니다" % label)
		elif not authoring.has("movement_speed_min") or not authoring.has("movement_speed_max"):
			errors.append("%s authoring 이동 속도 min/max 누락" % label)
		else:
			var speed_min := float(authoring.get("movement_speed_min", 0.0))
			var speed_max := float(authoring.get("movement_speed_max", 0.0))
			if speed_min < 0.0 or speed_max <= 0.0 or speed_min > speed_max:
				errors.append("%s authoring 이동 속도 범위 오류 %.3f..%.3f" % [label, speed_min, speed_max])
	if authoring.has("movement_sprint") and typeof(authoring.get("movement_sprint")) != TYPE_BOOL:
		errors.append("%s authoring.movement_sprint 형식 오류" % label)


static func _collect_palette_movement_intent_ids(palette: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	var entries := _array_from(palette.get("movement_intents", []))
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var entry_id := str(entry.get("id", "")).strip_edges()
		if not entry_id.is_empty():
			ids[entry_id] = entry
	return ids


static func _collect_authoring_trigger_ids(triggers: Array) -> Dictionary:
	var ids: Dictionary = {}
	for trigger_variant in triggers:
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			continue
		var trigger: Dictionary = trigger_variant as Dictionary
		var trigger_id := str(trigger.get("id", trigger.get("name", ""))).strip_edges()
		if not trigger_id.is_empty():
			ids[trigger_id] = true
	return ids


static func _format_authoring_data_patch_check_result(result: Dictionary) -> String:
	var errors := _array_from(result.get("errors", []))
	var conflicts := _array_from(result.get("conflicts", []))
	var warnings := _array_from(result.get("warnings", []))
	var trigger_count := int(result.get("trigger_count", 0))
	var action_count := int(result.get("action_count", 0))
	if not errors.is_empty():
		return "패치 점검: 오류 %d개\n%s" % [errors.size(), _format_authoring_check_details(errors, warnings)]
	if not conflicts.is_empty():
		return "패치 점검: 충돌 %d개\n%s" % [conflicts.size(), _format_authoring_check_details(conflicts, warnings)]
	var text := "패치 점검: 병합 가능 %d개 / 액션 %d개" % [trigger_count, action_count]
	if not warnings.is_empty():
		text += "\n%s" % _format_authoring_check_details([], warnings)
	return text


static func _format_authoring_data_patch_merge_blocked(result: Dictionary) -> String:
	var errors := _array_from(result.get("errors", []))
	var conflicts := _array_from(result.get("conflicts", []))
	var warnings := _array_from(result.get("warnings", []))
	if not errors.is_empty():
		return "패치 병합 차단: 오류 %d개\n%s" % [errors.size(), _format_authoring_check_details(errors, warnings)]
	return "패치 병합 차단: 충돌 %d개\n%s" % [conflicts.size(), _format_authoring_check_details(conflicts, warnings)]


static func _format_authoring_check_details(primary: Array, secondary: Array) -> String:
	var parts: Array[String] = []
	for index in range(min(primary.size(), 4)):
		parts.append(str(primary[index]))
	if primary.size() > 4:
		parts.append("외 %d개" % (primary.size() - 4))
	for index in range(min(secondary.size(), 2)):
		parts.append(str(secondary[index]))
	return "\n".join(parts)


static func _get_authoring_data_patch_triggers(root: Dictionary) -> Array:
	var patch := _dictionary_from(root.get("enemy_spawn_rules_patch", {}))
	var triggers := _array_from(patch.get("scenario_triggers", []))
	if triggers.is_empty():
		triggers = _array_from(root.get("scenario_triggers", []))
	return triggers


static func _merge_authoring_palette_trigger_entries(palette: Dictionary, triggers: Array) -> int:
	var entries := _array_from(palette.get("scenario_triggers", []))
	var entry_ids: Dictionary = {}
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var entry_id := str(entry.get("id", "")).strip_edges()
		if not entry_id.is_empty():
			entry_ids[entry_id] = true
	var added_count := 0
	for trigger_variant in triggers:
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			continue
		var trigger: Dictionary = trigger_variant as Dictionary
		var trigger_id := str(trigger.get("id", trigger.get("name", ""))).strip_edges()
		if trigger_id.is_empty() or entry_ids.has(trigger_id):
			continue
		var trigger_label := str(trigger.get("label", "")).strip_edges()
		if trigger_label.is_empty():
			trigger_label = trigger_id
		entries.append({
			"id": trigger_id,
			"label": trigger_label,
			"tags": ["scenario", "promoted"]
		})
		entry_ids[trigger_id] = true
		added_count += 1
	palette["scenario_triggers"] = entries
	return added_count


static func _write_json_dictionary(path: String, root: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(root, "\t"))
	return true


static func _delete_selected_scenario_preset(hud) -> void:
	var root: Dictionary = _load_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		_set_palette_preview_status(hud, "프리셋 삭제 실패: %s" % AUTHORING_SCENARIO_PRESETS_USER_PATH)
		return
	var preset_id := _get_selected_preset_id(hud)
	if preset_id.is_empty():
		preset_id = str(root.get("active_preset", "")).strip_edges()
	if preset_id.is_empty():
		_set_palette_preview_status(hud, "프리셋 삭제 실패: 선택 없음")
		return
	var presets := _array_from(root.get("presets", []))
	var remaining_presets: Array = []
	var deleted_preset: Dictionary = {}
	for preset_variant in presets:
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var preset: Dictionary = preset_variant as Dictionary
		if str(preset.get("id", "")).strip_edges() == preset_id:
			deleted_preset = preset
			continue
		remaining_presets.append(preset)
	if deleted_preset.is_empty():
		_set_palette_preview_status(hud, "프리셋 삭제 실패: %s" % preset_id)
		return
	var active_id := str(root.get("active_preset", "")).strip_edges()
	if active_id == preset_id or not _scenario_preset_array_has_id(remaining_presets, active_id):
		active_id = _first_scenario_preset_id(remaining_presets)
	var output := {
		"format": "battleship_authoring_scenario_presets",
		"version": 1,
		"active_preset": active_id,
		"presets": remaining_presets
	}
	var file := FileAccess.open(AUTHORING_SCENARIO_PRESETS_USER_PATH, FileAccess.WRITE)
	if file == null:
		_set_palette_preview_status(hud, "프리셋 삭제 실패: %s" % AUTHORING_SCENARIO_PRESETS_USER_PATH)
		return
	file.store_string(JSON.stringify(output, "\t"))
	_sync_palette_preset_ui(hud)
	var preset_label := str(deleted_preset.get("label", deleted_preset.get("id", preset_id))).strip_edges()
	_set_palette_preview_status(hud, "프리셋 삭제: %s (%d개 남음)" % [preset_label, remaining_presets.size()])


static func _load_palette_queue(hud) -> void:
	var root: Dictionary = _load_json_dictionary(AUTHORING_QUEUE_USER_PATH)
	if root.is_empty():
		_set_palette_preview_status(hud, "큐 불러오기 실패: %s" % AUTHORING_QUEUE_USER_PATH)
		return
	var actions: Array = _array_from(root.get("actions", []))
	var imported_entries := _build_palette_queue_entries_from_actions(hud, actions)
	hud.debug_authoring_palette_queue_entries = imported_entries
	hud.debug_authoring_palette_queue_selected_index = 0 if not imported_entries.is_empty() else -1
	_sync_palette_queue_ui(hud)
	_set_palette_preview_status(hud, "큐 불러오기: %d개 <- %s" % [imported_entries.size(), AUTHORING_QUEUE_USER_PATH])


static func _set_palette_preview_status(hud, status_text: String) -> void:
	if is_instance_valid(hud.debug_authoring_palette_preview_value):
		hud.debug_authoring_palette_preview_value.text = status_text


static func _sync_palette_queue_ui(hud) -> void:
	_normalize_palette_queue_selection(hud)
	if is_instance_valid(hud.debug_authoring_palette_queue_value):
		hud.debug_authoring_palette_queue_value.text = _format_palette_queue_text(
			hud.debug_authoring_palette_queue_entries,
			hud.debug_authoring_palette_queue_selected_index
		)
	if is_instance_valid(hud.debug_authoring_palette_queue_execute_button):
		hud.debug_authoring_palette_queue_execute_button.disabled = hud.debug_authoring_palette_queue_entries.is_empty()
	var selected_index: int = hud.debug_authoring_palette_queue_selected_index
	var entry_count: int = hud.debug_authoring_palette_queue_entries.size()
	if is_instance_valid(hud.debug_authoring_palette_queue_duplicate_button):
		hud.debug_authoring_palette_queue_duplicate_button.disabled = entry_count <= 0
	if is_instance_valid(hud.debug_authoring_palette_queue_delete_button):
		hud.debug_authoring_palette_queue_delete_button.disabled = entry_count <= 0
	if is_instance_valid(hud.debug_authoring_palette_queue_prev_button):
		hud.debug_authoring_palette_queue_prev_button.disabled = entry_count <= 1 or selected_index <= 0
	if is_instance_valid(hud.debug_authoring_palette_queue_next_button):
		hud.debug_authoring_palette_queue_next_button.disabled = entry_count <= 1 or selected_index >= entry_count - 1
	if is_instance_valid(hud.debug_authoring_palette_queue_move_up_button):
		hud.debug_authoring_palette_queue_move_up_button.disabled = entry_count <= 1 or selected_index <= 0
	if is_instance_valid(hud.debug_authoring_palette_queue_move_down_button):
		hud.debug_authoring_palette_queue_move_down_button.disabled = entry_count <= 1 or selected_index >= entry_count - 1


static func _normalize_palette_queue_selection(hud) -> void:
	var entry_count: int = hud.debug_authoring_palette_queue_entries.size()
	if entry_count <= 0:
		hud.debug_authoring_palette_queue_selected_index = -1
		return
	hud.debug_authoring_palette_queue_selected_index = clampi(hud.debug_authoring_palette_queue_selected_index, 0, entry_count - 1)


static func _sync_palette_preset_ui(hud) -> void:
	if not is_instance_valid(hud.debug_authoring_palette_preset_value):
		return
	var root := _load_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		hud.debug_authoring_palette_preset_value.text = "프리셋: -"
		_set_palette_preset_preview(hud, "프리셋 내용: -")
		if is_instance_valid(hud.debug_authoring_palette_preset_select):
			hud.debug_authoring_palette_preset_select.clear()
			hud.debug_authoring_palette_preset_select.disabled = true
		return
	var presets := _array_from(root.get("presets", []))
	var active := _get_active_scenario_preset(root)
	var active_label := str(active.get("label", root.get("active_preset", "-"))).strip_edges()
	if active_label.is_empty():
		active_label = "-"
	hud.debug_authoring_palette_preset_value.text = "프리셋: %d개 / %s" % [presets.size(), active_label]
	_set_palette_preset_preview(hud, _format_scenario_preset_preview(active))
	_sync_palette_preset_select(hud, presets, str(active.get("id", root.get("active_preset", ""))).strip_edges())


static func _sync_palette_preset_select(hud, presets: Array, active_id: String) -> void:
	if not is_instance_valid(hud.debug_authoring_palette_preset_select):
		return
	var preset_select: OptionButton = hud.debug_authoring_palette_preset_select
	preset_select.clear()
	var active_index := -1
	for preset_variant in presets:
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var preset: Dictionary = preset_variant as Dictionary
		var preset_id := str(preset.get("id", "")).strip_edges()
		if preset_id.is_empty():
			continue
		var preset_label := str(preset.get("label", preset_id)).strip_edges()
		if preset_label.is_empty():
			preset_label = preset_id
		var index := preset_select.item_count
		preset_select.add_item(preset_label)
		preset_select.set_item_metadata(index, preset_id)
		if preset_id == active_id:
			active_index = index
	preset_select.disabled = preset_select.item_count <= 0
	if preset_select.item_count <= 0:
		return
	if active_index < 0:
		active_index = 0
	preset_select.select(active_index)


static func _set_palette_preset_preview(hud, preview_text: String) -> void:
	if is_instance_valid(hud.debug_authoring_palette_preset_preview_value):
		hud.debug_authoring_palette_preset_preview_value.text = preview_text


static func _format_scenario_preset_preview(preset: Dictionary) -> String:
	if preset.is_empty():
		return "프리셋 내용: -"
	var preset_label := str(preset.get("label", preset.get("id", "-"))).strip_edges()
	if preset_label.is_empty():
		preset_label = "-"
	var parts: Array[String] = ["프리셋 내용: %s" % preset_label]
	var queue_actions := _get_queue_actions_from_scenario_preset(preset)
	if queue_actions.is_empty():
		parts.append("액션: -")
		return "\n".join(parts)
	for index in range(queue_actions.size()):
		var action: Dictionary = _normalize_palette_queue_action(queue_actions[index])
		if action.is_empty():
			continue
		parts.append("%d. %s" % [index + 1, _format_palette_action_summary(action)])
	return "\n".join(parts)


static func _format_palette_action_summary(action: Dictionary) -> String:
	var label_text := str(action.get("label", "")).strip_edges()
	if label_text.is_empty():
		label_text = _palette_action_label(action)
	var authoring_suffix := _format_palette_authoring_suffix(action.get("authoring", {}))
	match str(action.get("type", "")):
		"spawn_ship":
			var lateral_offset := float(action.get("lateral_offset", 0.0))
			var lateral_text := "+%.0fm" % lateral_offset if lateral_offset >= 0.0 else "%.0fm" % lateral_offset
			return "%s%s -> %s @%.0fm %s" % [
				label_text,
				authoring_suffix,
				str(action.get("ship_type", "-")),
				float(action.get("distance", 40.0)),
				lateral_text
			]
		"spawn_recipe":
			return "%s%s -> %s" % [label_text, authoring_suffix, str(action.get("recipe", "-"))]
		"set_encounter_profile":
			return "%s -> %s" % [label_text, str(action.get("profile", "-"))]
		"run_scenario_trigger":
			return "%s -> %s" % [label_text, str(action.get("trigger", "-"))]
	return "%s%s" % [label_text, authoring_suffix]


static func _format_palette_action_display_text(action: Dictionary) -> String:
	var label_text := str(action.get("label", "")).strip_edges()
	if label_text.is_empty():
		label_text = _palette_action_label(action)
	return "%s%s" % [label_text, _format_palette_authoring_suffix(action.get("authoring", {}))]


static func _format_palette_queue_text(entries: Array[Dictionary], selected_index: int = -1) -> String:
	if entries.is_empty():
		return "큐: -"
	var parts: Array[String] = []
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var entry_text := "%d. %s" % [index + 1, str(entry.get("text", "-"))]
		if index == selected_index:
			entry_text = "[%s]" % entry_text
		parts.append(entry_text)
	return "큐: %s" % " -> ".join(parts)


static func _build_palette_queue_actions(entries: Array[Dictionary]) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var action: Dictionary = _normalize_palette_queue_action(entry.get("action", {}))
		if action.is_empty():
			continue
		var label_text := str(action.get("label", "")).strip_edges()
		if label_text.is_empty():
			label_text = str(entry.get("label", "")).strip_edges()
		if label_text.is_empty():
			label_text = str(entry.get("text", "")).strip_edges()
		if label_text.is_empty():
			label_text = _palette_action_label(action)
		action["label"] = label_text
		actions.append(action)
	return actions


static func _build_palette_queue_entries_from_actions(hud, actions: Array) -> Array[Dictionary]:
	var imported_entries: Array[Dictionary] = []
	for action_variant in actions:
		var action: Dictionary = _normalize_palette_queue_action(action_variant)
		if action.is_empty():
			continue
		var callback := _make_palette_action_callback(hud, action)
		if not callback.is_valid():
			continue
		var label_text := str(action.get("label", "")).strip_edges()
		if label_text.is_empty():
			label_text = _palette_action_label(action)
		imported_entries.append({
			"text": _format_palette_action_display_text(action),
			"callback": callback,
			"action": action
		})
	return imported_entries


static func _build_scenario_trigger_from_palette_queue(entries: Array[Dictionary]) -> Dictionary:
	return _build_scenario_trigger_from_queue_actions(_build_palette_queue_actions(entries))


static func _build_scenario_trigger_from_queue_actions(queue_actions: Array) -> Dictionary:
	var actions := _build_scenario_actions_from_queue_actions(queue_actions)
	var preset_id := _make_palette_queue_preset_id_from_actions(queue_actions)
	var preset_label := _make_palette_queue_preset_label_from_actions(queue_actions)
	return {
		"id": preset_id,
		"label": preset_label,
		"condition": {"elapsed_time": 0.0},
		"one_shot": true,
		"enabled": true,
		"actions": actions
	}


static func _build_scenario_actions_from_palette_queue(entries: Array[Dictionary]) -> Array[Dictionary]:
	return _build_scenario_actions_from_queue_actions(_build_palette_queue_actions(entries))


static func _build_scenario_actions_from_queue_actions(queue_actions: Array) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for action_variant in queue_actions:
		var action: Dictionary = _normalize_palette_queue_action(action_variant)
		if action.is_empty():
			continue
		var scenario_action := _palette_queue_action_to_scenario_action(action)
		if scenario_action.is_empty():
			continue
		var label_text := str(action.get("label", "")).strip_edges()
		if label_text.is_empty():
			label_text = _palette_action_label(action)
		scenario_action["label"] = label_text
		actions.append(scenario_action)
	return actions


static func _palette_queue_action_to_scenario_action(action: Dictionary) -> Dictionary:
	var scenario_action: Dictionary = {}
	match str(action.get("type", "")):
		"spawn_ship":
			scenario_action = {
				"type": "spawn_ship",
				"ship_type": str(action.get("ship_type", "")),
				"distance": float(action.get("distance", 40.0)),
				"lateral_offset": float(action.get("lateral_offset", 0.0))
			}
		"spawn_recipe":
			scenario_action = {
				"type": "spawn_recipe",
				"recipe": str(action.get("recipe", ""))
			}
		"set_encounter_profile":
			scenario_action = {
				"type": "set_encounter_profile",
				"profile": str(action.get("profile", ""))
			}
		"run_scenario_trigger":
			scenario_action = {
				"type": "run_scenario_trigger",
				"trigger": str(action.get("trigger", ""))
			}
	if scenario_action.is_empty():
		return {}
	var authoring: Dictionary = _normalize_palette_action_authoring_meta(action.get("authoring", {}))
	if not authoring.is_empty():
		scenario_action["authoring"] = authoring
	return scenario_action


static func _queue_actions_from_scenario_actions(scenario_actions: Array) -> Array[Dictionary]:
	var queue_actions: Array[Dictionary] = []
	for action_variant in scenario_actions:
		var action: Dictionary = _normalize_palette_queue_action(action_variant)
		if action.is_empty():
			continue
		queue_actions.append(action)
	return queue_actions


static func _get_queue_actions_from_scenario_preset(preset: Dictionary) -> Array:
	var queue_actions: Array = _array_from(preset.get("queue_actions", []))
	if not queue_actions.is_empty():
		return queue_actions
	var trigger: Dictionary = _dictionary_from(preset.get("trigger", {}))
	return _queue_actions_from_scenario_actions(_array_from(trigger.get("actions", [])))


static func _select_scenario_preset(hud, index: int) -> void:
	var preset_id := _get_preset_select_id(hud, index)
	if preset_id.is_empty():
		return
	var root := _load_json_dictionary(AUTHORING_SCENARIO_PRESETS_USER_PATH)
	if root.is_empty():
		return
	var preset := _find_scenario_preset(root, preset_id)
	if preset.is_empty():
		return
	root["active_preset"] = preset_id
	var file := FileAccess.open(AUTHORING_SCENARIO_PRESETS_USER_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(root, "\t"))
	_sync_palette_preset_ui(hud)
	var preset_label := str(preset.get("label", preset_id)).strip_edges()
	_set_palette_preview_status(hud, "프리셋 선택: %s" % preset_label)


static func _get_selected_or_active_scenario_preset(hud, root: Dictionary) -> Dictionary:
	var selected_id := _get_selected_preset_id(hud)
	if not selected_id.is_empty():
		var selected_preset := _find_scenario_preset(root, selected_id)
		if not selected_preset.is_empty():
			return selected_preset
	return _get_active_scenario_preset(root)


static func _get_selected_preset_id(hud) -> String:
	if not is_instance_valid(hud.debug_authoring_palette_preset_select):
		return ""
	var preset_select: OptionButton = hud.debug_authoring_palette_preset_select
	return _get_preset_select_id(hud, preset_select.selected)


static func _get_preset_select_id(hud, index: int) -> String:
	if not is_instance_valid(hud.debug_authoring_palette_preset_select):
		return ""
	var preset_select: OptionButton = hud.debug_authoring_palette_preset_select
	if index < 0 or index >= preset_select.item_count:
		return ""
	return str(preset_select.get_item_metadata(index)).strip_edges()


static func _find_scenario_preset(root: Dictionary, preset_id: String) -> Dictionary:
	var normalized_id := preset_id.strip_edges()
	if normalized_id.is_empty():
		return {}
	var presets := _array_from(root.get("presets", []))
	for preset_variant in presets:
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var preset: Dictionary = preset_variant as Dictionary
		if str(preset.get("id", "")).strip_edges() == normalized_id:
			return preset
	return {}


static func _scenario_preset_array_has_id(presets: Array, preset_id: String) -> bool:
	var normalized_id := preset_id.strip_edges()
	if normalized_id.is_empty():
		return false
	for preset_variant in presets:
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var preset: Dictionary = preset_variant as Dictionary
		if str(preset.get("id", "")).strip_edges() == normalized_id:
			return true
	return false


static func _first_scenario_preset_id(presets: Array) -> String:
	for preset_variant in presets:
		if typeof(preset_variant) != TYPE_DICTIONARY:
			continue
		var preset: Dictionary = preset_variant as Dictionary
		var preset_id := str(preset.get("id", "")).strip_edges()
		if not preset_id.is_empty():
			return preset_id
	return ""


static func _get_active_scenario_preset(root: Dictionary) -> Dictionary:
	var presets := _array_from(root.get("presets", []))
	if presets.is_empty():
		return {}
	var active_id := str(root.get("active_preset", "")).strip_edges()
	if not active_id.is_empty():
		for preset_variant in presets:
			if typeof(preset_variant) != TYPE_DICTIONARY:
				continue
			var preset: Dictionary = preset_variant as Dictionary
			if str(preset.get("id", "")).strip_edges() == active_id:
				return preset
	for preset_variant in presets:
		if typeof(preset_variant) == TYPE_DICTIONARY:
			return preset_variant as Dictionary
	return {}


static func _make_palette_queue_preset_id_from_actions(queue_actions: Array) -> String:
	var parts: Array[String] = []
	for action_variant in queue_actions:
		var action: Dictionary = _normalize_palette_queue_action(action_variant)
		if action.is_empty():
			continue
		var identity := _palette_action_identity(action)
		if not identity.is_empty():
			parts.append(identity)
	return _slugify_palette_identifier("_".join(parts), PALETTE_PRESET_FALLBACK_ID)


static func _make_palette_queue_preset_label_from_actions(queue_actions: Array) -> String:
	var parts: Array[String] = []
	for action_variant in queue_actions:
		var action: Dictionary = _normalize_palette_queue_action(action_variant)
		if action.is_empty():
			continue
		var label_text := _format_palette_action_display_text(action)
		if not label_text.is_empty() and label_text != "-":
			parts.append(label_text)
	return " + ".join(parts) if not parts.is_empty() else PALETTE_PRESET_FALLBACK_ID


static func _palette_action_identity(action: Dictionary) -> String:
	var parts: Array[String] = []
	match str(action.get("type", "")):
		"spawn_ship":
			parts.append(str(action.get("ship_type", "")).strip_edges())
		"spawn_recipe":
			parts.append(str(action.get("recipe", "")).strip_edges())
		"set_encounter_profile":
			parts.append(str(action.get("profile", "")).strip_edges())
		"run_scenario_trigger":
			parts.append(str(action.get("trigger", "")).strip_edges())
	var authoring: Dictionary = _normalize_palette_action_authoring_meta(action.get("authoring", {}))
	var combat_profile := str(authoring.get("combat_profile", "")).strip_edges()
	if not combat_profile.is_empty():
		parts.append(combat_profile)
	var movement_intent := str(authoring.get("movement_intent", "")).strip_edges()
	if not movement_intent.is_empty():
		parts.append(movement_intent)
	var clean_parts: Array[String] = []
	for part in parts:
		var part_text := str(part).strip_edges()
		if not part_text.is_empty():
			clean_parts.append(part_text)
	return "_".join(clean_parts)


static func _slugify_palette_identifier(value: String, fallback: String) -> String:
	var lower_value := value.strip_edges().to_lower()
	var safe_chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var slug := ""
	for index in range(lower_value.length()):
		var character := lower_value.substr(index, 1)
		if safe_chars.contains(character):
			slug += character
		elif character == "_" or character == "-" or character == " ":
			if not slug.ends_with("_"):
				slug += "_"
		elif not slug.ends_with("_"):
			slug += "_"
	while slug.begins_with("_"):
		slug = slug.substr(1)
	while slug.ends_with("_") and slug.length() > 0:
		slug = slug.substr(0, slug.length() - 1)
	return slug if not slug.is_empty() else fallback


static func _normalize_palette_queue_action(action_variant: Variant) -> Dictionary:
	var action: Dictionary = _dictionary_from(action_variant).duplicate(true)
	var action_type := str(action.get("type", "")).strip_edges()
	if action_type.is_empty():
		return {}
	match action_type:
		"spawn_ship":
			var ship_type := str(action.get("ship_type", "")).strip_edges()
			if ship_type.is_empty():
				return {}
			return _finalize_normalized_palette_action({
				"type": action_type,
				"ship_type": ship_type,
				"distance": float(action.get("distance", 40.0)),
				"lateral_offset": float(action.get("lateral_offset", 0.0)),
				"label": str(action.get("label", "")).strip_edges()
			}, action)
		"spawn_recipe":
			var recipe := str(action.get("recipe", "")).strip_edges()
			if recipe.is_empty():
				return {}
			return _finalize_normalized_palette_action({
				"type": action_type,
				"recipe": recipe,
				"label": str(action.get("label", "")).strip_edges()
			}, action)
		"set_encounter_profile":
			var profile := str(action.get("profile", "")).strip_edges()
			if profile.is_empty():
				return {}
			return _finalize_normalized_palette_action({
				"type": action_type,
				"profile": profile,
				"label": str(action.get("label", "")).strip_edges()
			}, action)
		"run_scenario_trigger":
			var trigger := str(action.get("trigger", "")).strip_edges()
			if trigger.is_empty():
				return {}
			return _finalize_normalized_palette_action({
				"type": action_type,
				"trigger": trigger,
				"label": str(action.get("label", "")).strip_edges()
			}, action)
	return {}


static func _finalize_normalized_palette_action(normalized_action: Dictionary, source_action: Dictionary) -> Dictionary:
	var label_text := str(normalized_action.get("label", "")).strip_edges()
	normalized_action["label"] = label_text
	var authoring: Dictionary = _normalize_palette_action_authoring_meta(source_action.get("authoring", {}))
	if not authoring.is_empty() and _palette_action_accepts_assembly_meta(normalized_action):
		normalized_action["authoring"] = authoring
	return normalized_action


static func _make_palette_reference_authoring_meta(reference_type: String, entry: Dictionary) -> Dictionary:
	var entry_id := str(entry.get("id", "")).strip_edges()
	if entry_id.is_empty():
		return {}
	var label_text := _palette_button_text(entry)
	match reference_type:
		"combat_profile":
			return {
				"combat_profile": entry_id,
				"combat_profile_label": label_text
			}
		"movement_intent":
			var meta := {
				"movement_intent": entry_id,
				"movement_intent_label": label_text,
				"movement_family": str(entry.get("family", "")).strip_edges(),
				"movement_mode": str(entry.get("mode", "")).strip_edges()
			}
			var speed_range := _get_palette_movement_speed_range(entry)
			if not speed_range.is_empty():
				meta["movement_speed_min"] = float(speed_range.get("min", 0.0))
				meta["movement_speed_max"] = float(speed_range.get("max", 0.0))
			if entry.has("sprint"):
				meta["movement_sprint"] = entry.get("sprint") == true
			return meta
	return {}


static func _apply_palette_assembly_to_action(action: Dictionary, assembly_meta: Variant) -> Dictionary:
	var normalized_action: Dictionary = _normalize_palette_queue_action(action)
	if normalized_action.is_empty() or not _palette_action_accepts_assembly_meta(normalized_action):
		return normalized_action
	var authoring: Dictionary = _normalize_palette_action_authoring_meta(assembly_meta)
	if not authoring.is_empty():
		normalized_action["authoring"] = authoring
	return normalized_action


static func _palette_action_accepts_assembly_meta(action: Dictionary) -> bool:
	return ["spawn_ship", "spawn_recipe"].has(str(action.get("type", "")))


static func _normalize_palette_action_authoring_meta(meta_variant: Variant) -> Dictionary:
	var source: Dictionary = _dictionary_from(meta_variant)
	if source.is_empty():
		return {}
	var meta: Dictionary = {}
	var combat_profile := str(source.get("combat_profile", "")).strip_edges()
	if not combat_profile.is_empty():
		meta["combat_profile"] = combat_profile
		var combat_label := str(source.get("combat_profile_label", source.get("combat_label", combat_profile))).strip_edges()
		meta["combat_profile_label"] = combat_label if not combat_label.is_empty() else combat_profile
	var movement_intent := str(source.get("movement_intent", "")).strip_edges()
	if not movement_intent.is_empty():
		meta["movement_intent"] = movement_intent
		var movement_label := str(source.get("movement_intent_label", source.get("movement_label", movement_intent))).strip_edges()
		meta["movement_intent_label"] = movement_label if not movement_label.is_empty() else movement_intent
		var movement_mode := str(source.get("movement_mode", "")).strip_edges()
		if not movement_mode.is_empty():
			meta["movement_mode"] = movement_mode
		var movement_family := str(source.get("movement_family", source.get("family", ""))).strip_edges()
		if not movement_family.is_empty():
			meta["movement_family"] = movement_family
		var speed_min_variant: Variant = source.get("movement_speed_min", source.get("speed_min", null))
		var speed_max_variant: Variant = source.get("movement_speed_max", source.get("speed_max", null))
		if speed_min_variant != null:
			meta["movement_speed_min"] = maxf(0.0, float(speed_min_variant))
		if speed_max_variant != null:
			meta["movement_speed_max"] = maxf(0.0, float(speed_max_variant))
		if source.has("movement_sprint"):
			meta["movement_sprint"] = source.get("movement_sprint") == true
		elif source.has("sprint"):
			meta["movement_sprint"] = source.get("sprint") == true
	return meta


static func _get_palette_movement_speed_range(entry: Dictionary) -> Dictionary:
	var has_min := entry.has("speed_min")
	var has_max := entry.has("speed_max")
	if has_min and has_max:
		var speed_min := maxf(0.0, float(entry.get("speed_min", 0.0)))
		var speed_max := maxf(0.0, float(entry.get("speed_max", 0.0)))
		if speed_min > speed_max:
			var swapped_entry_speed := speed_min
			speed_min = speed_max
			speed_max = swapped_entry_speed
		return {"min": speed_min, "max": speed_max}
	var speed_text := str(entry.get("speed", "")).strip_edges()
	var parts := speed_text.split("-", false)
	if parts.size() != 2:
		return {}
	var parsed_min := maxf(0.0, float(str(parts[0]).strip_edges()))
	var parsed_max := maxf(0.0, float(str(parts[1]).strip_edges()))
	if parsed_min > parsed_max:
		var swapped_text_speed := parsed_min
		parsed_min = parsed_max
		parsed_max = swapped_text_speed
	return {"min": parsed_min, "max": parsed_max}


static func _format_palette_authoring_suffix(meta_variant: Variant) -> String:
	var meta: Dictionary = _normalize_palette_action_authoring_meta(meta_variant)
	if meta.is_empty():
		return ""
	var parts: Array[String] = []
	var combat_label := str(meta.get("combat_profile_label", "")).strip_edges()
	if not combat_label.is_empty():
		parts.append("전투: %s" % combat_label)
	var movement_label := str(meta.get("movement_intent_label", "")).strip_edges()
	if not movement_label.is_empty():
		var movement_family := str(meta.get("movement_family", "")).strip_edges()
		if not movement_family.is_empty():
			movement_label = "%s (%s)" % [movement_label, movement_family]
		parts.append("이동: %s" % movement_label)
	return " [%s]" % " | ".join(parts) if not parts.is_empty() else ""


static func _palette_action_label(action: Dictionary) -> String:
	match str(action.get("type", "")):
		"spawn_ship":
			return "함선: %s" % str(action.get("ship_type", "-"))
		"spawn_recipe":
			return "편대: %s" % str(action.get("recipe", "-"))
		"set_encounter_profile":
			return "전개: %s" % str(action.get("profile", "-"))
		"run_scenario_trigger":
			return "트리거: %s" % str(action.get("trigger", "-"))
	return "-"


static func _wire_palette_preview(button: Button, preview_label: Label, description: String) -> void:
	if not is_instance_valid(preview_label) or description.strip_edges().is_empty():
		return
	button.mouse_entered.connect(func() -> void:
		preview_label.text = description
	)
	button.focus_entered.connect(func() -> void:
		preview_label.text = description
	)
	button.pressed.connect(func() -> void:
		preview_label.text = description
	)


static func _describe_palette_ship_type(entry: Dictionary, source_data: Dictionary) -> String:
	var ship_id := str(entry.get("id", "")).strip_edges()
	var label_text := _palette_button_text(entry)
	var ship_stats: Dictionary = _dictionary_from(source_data.get("ship_stats", {}))
	var ship_entry: Dictionary = _dictionary_from(ship_stats.get(ship_id, {}))
	var archetype_id := str(entry.get("ship_archetype", "")).strip_edges()
	if archetype_id.is_empty():
		archetype_id = str(ship_entry.get("ship_archetype", "")).strip_edges()
	var archetypes: Dictionary = _dictionary_from(ship_stats.get("ship_archetypes", {}))
	var archetype: Dictionary = _dictionary_from(archetypes.get(archetype_id, {}))
	var combat_profile := str(archetype.get("combat_profile", "-")).strip_edges()
	var hull_scene := str(archetype.get("hull_scene", "-")).strip_edges()
	var hull_name := hull_scene.get_file().get_basename() if not hull_scene.is_empty() else "-"
	var crew_text := _format_count_dictionary(archetype.get("crew_composition", {}))
	var loadout: Array = _array_from(archetype.get("weapon_loadout", []))
	var parts: Array[String] = [
		"함선: %s" % label_text,
		"id=%s" % ship_id,
		"archetype=%s" % (archetype_id if not archetype_id.is_empty() else "-"),
		"hull=%s" % hull_name,
		"combat=%s" % (combat_profile if not combat_profile.is_empty() else "-"),
		"crew=%s" % crew_text,
		"weapons=%d" % loadout.size()
	]
	return "\n".join(parts)


static func _describe_palette_recipe(entry: Dictionary, source_data: Dictionary) -> String:
	var recipe_id := str(entry.get("id", "")).strip_edges()
	var label_text := _palette_button_text(entry)
	var spawn_rules: Dictionary = _dictionary_from(source_data.get("enemy_spawn_rules", {}))
	var recipes: Dictionary = _dictionary_from(spawn_rules.get("spawn_recipes", {}))
	var recipe: Dictionary = _dictionary_from(recipes.get(recipe_id, {}))
	var formation_type := str(recipe.get("formation_type", "-")).strip_edges()
	var fleet_class := str(entry.get("fleet_class", "-")).strip_edges()
	var ships: Array = _array_from(recipe.get("ships", []))
	var ship_texts: Array[String] = []
	for ship_variant in ships:
		var ship_data: Dictionary = _dictionary_from(ship_variant)
		var ship_type := str(ship_data.get("ship_type", "-")).strip_edges()
		var role := str(ship_data.get("role", "-")).strip_edges()
		ship_texts.append("%s/%s" % [ship_type, role])
	var parts: Array[String] = [
		"편대 레시피: %s" % label_text,
		"id=%s | class=%s | formation=%s" % [recipe_id, fleet_class, formation_type],
		"ships=%s" % (", ".join(ship_texts) if not ship_texts.is_empty() else "-")
	]
	return "\n".join(parts)


static func _describe_palette_combat_profile(entry: Dictionary, source_data: Dictionary) -> String:
	var profile_id := str(entry.get("id", "")).strip_edges()
	var label_text := _palette_button_text(entry)
	var ship_stats: Dictionary = _dictionary_from(source_data.get("ship_stats", {}))
	var profiles: Dictionary = _dictionary_from(ship_stats.get("combat_profiles", {}))
	var profile: Dictionary = _dictionary_from(profiles.get(profile_id, {}))
	var archetypes: Dictionary = _dictionary_from(ship_stats.get("ship_archetypes", {}))
	var users: Array[String] = []
	for archetype_id_variant in archetypes.keys():
		var archetype_id := str(archetype_id_variant).strip_edges()
		var archetype: Dictionary = _dictionary_from(archetypes.get(archetype_id_variant, {}))
		if str(archetype.get("combat_profile", "")).strip_edges() == profile_id:
			users.append(archetype_id)
	var role_text := str(profile.get("combat_role", "-")).strip_edges()
	var boarding_text := "Y" if bool(profile.get("allow_boarding", false)) else "N"
	var preferred_range := float(profile.get("preferred_range", 0.0))
	var tolerance := float(profile.get("range_tolerance", 0.0))
	var retreat := float(profile.get("retreat_distance", 0.0))
	var parts: Array[String] = [
		"전투 모드: %s" % label_text,
		"id=%s | role=%s | boarding=%s" % [profile_id, role_text if not role_text.is_empty() else "-", boarding_text],
		"range=%.1f +/- %.1f | retreat=%.1f" % [preferred_range, tolerance, retreat],
		"used_by=%s" % (", ".join(users) if not users.is_empty() else "-")
	]
	if profile.has("orbit_distance"):
		parts.append("orbit=%.1f" % float(profile.get("orbit_distance", 0.0)))
	return "\n".join(parts)


static func _describe_palette_movement_intent(entry: Dictionary) -> String:
	var intent_id := str(entry.get("id", "")).strip_edges()
	var label_text := _palette_button_text(entry)
	var mode_text := str(entry.get("mode", "-")).strip_edges()
	var family_text := str(entry.get("family", "-")).strip_edges()
	var speed_text := str(entry.get("speed", "-")).strip_edges()
	var sprint_text := "Y" if bool(entry.get("sprint", false)) else "N"
	var description := str(entry.get("description", "")).strip_edges()
	var parts: Array[String] = [
		"이동 의도: %s" % label_text,
		"id=%s | mode=%s | family=%s" % [intent_id, mode_text if not mode_text.is_empty() else "-", family_text if not family_text.is_empty() else "-"],
		"speed=%s | sprint=%s" % [speed_text if not speed_text.is_empty() else "-", sprint_text]
	]
	if not description.is_empty():
		parts.append(description)
	return "\n".join(parts)


static func _describe_palette_profile(entry: Dictionary, source_data: Dictionary) -> String:
	var profile_id := str(entry.get("id", "")).strip_edges()
	var label_text := _palette_button_text(entry)
	var spawn_rules: Dictionary = _dictionary_from(source_data.get("enemy_spawn_rules", {}))
	var profiles: Dictionary = _dictionary_from(spawn_rules.get("encounter_profiles", {}))
	var profile: Dictionary = _dictionary_from(profiles.get(profile_id, {}))
	var progression: Array = _array_from(profile.get("fleet_progression", []))
	var row_texts: Array[String] = []
	for row_variant in progression:
		var row_data: Dictionary = _dictionary_from(row_variant)
		var start_time: float = float(row_data.get("start_time", 0.0))
		var end_time: float = float(row_data.get("end_time", 0.0))
		var weights_text := _format_count_dictionary(row_data.get("fleet_weights", {}))
		row_texts.append("%.0f-%.0fs: %s" % [start_time, end_time, weights_text])
	var parts: Array[String] = [
		"전개 프로필: %s" % label_text,
		"id=%s" % profile_id,
		"progression=%s" % (" | ".join(row_texts) if not row_texts.is_empty() else "-")
	]
	return "\n".join(parts)


static func _describe_palette_trigger(entry: Dictionary, source_data: Dictionary) -> String:
	var trigger_id := str(entry.get("id", "")).strip_edges()
	var label_text := _palette_button_text(entry)
	var trigger: Dictionary = _find_scenario_trigger(trigger_id, source_data)
	var condition: Dictionary = _dictionary_from(trigger.get("condition", {}))
	var elapsed_time: float = float(condition.get("elapsed_time", 0.0))
	var actions: Array = _array_from(trigger.get("actions", []))
	var action_texts: Array[String] = []
	for action_variant in actions:
		var action: Dictionary = _dictionary_from(action_variant)
		var action_type := str(action.get("type", "-")).strip_edges()
		match action_type:
			"set_encounter_profile":
				action_texts.append("%s -> %s" % [action_type, str(action.get("profile", "-"))])
			"spawn_fleet":
				action_texts.append("%s -> %s" % [action_type, str(action.get("fleet_class", "-"))])
			"trigger_boss_event":
				action_texts.append("%s -> %s" % [action_type, str(action.get("event", "-"))])
			_:
				action_texts.append(action_type)
	var parts: Array[String] = [
		"시나리오 트리거: %s" % label_text,
		"id=%s | elapsed=%.0fs" % [trigger_id, elapsed_time],
		"actions=%s" % (", ".join(action_texts) if not action_texts.is_empty() else "-")
	]
	return "\n".join(parts)


static func _find_scenario_trigger(trigger_id: String, source_data: Dictionary) -> Dictionary:
	var spawn_rules: Dictionary = _dictionary_from(source_data.get("enemy_spawn_rules", {}))
	var triggers: Array = _array_from(spawn_rules.get("scenario_triggers", []))
	for trigger_variant in triggers:
		var trigger: Dictionary = _dictionary_from(trigger_variant)
		if str(trigger.get("id", "")).strip_edges() == trigger_id:
			return trigger
	return {}


static func _format_count_dictionary(value: Variant) -> String:
	var data: Dictionary = _dictionary_from(value)
	if data.is_empty():
		return "-"
	var keys: Array = data.keys()
	keys.sort()
	var parts: Array[String] = []
	for key_variant in keys:
		var key_text := str(key_variant)
		var amount_variant: Variant = data.get(key_variant, 0)
		if typeof(amount_variant) == TYPE_FLOAT:
			parts.append("%s %.2f" % [key_text, float(amount_variant)])
		else:
			parts.append("%s %s" % [key_text, str(amount_variant)])
	return ", ".join(parts)


static func _dictionary_from(value: Variant) -> Dictionary:
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func _array_from(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []


static func _palette_button_text(entry: Dictionary) -> String:
	var label_text := str(entry.get("label", "")).strip_edges()
	return label_text if not label_text.is_empty() else str(entry.get("id", "-"))


static func _palette_entry_has_tag(entry: Dictionary, tag_name: String) -> bool:
	var tags_variant: Variant = entry.get("tags", [])
	if typeof(tags_variant) != TYPE_ARRAY:
		return false
	var normalized_tag := tag_name.strip_edges()
	var tags: Array = tags_variant as Array
	for tag_variant in tags:
		if str(tag_variant).strip_edges() == normalized_tag:
			return true
	return false


static func _add_misc_section(hud, panel_box: Control) -> void:
	var section: Dictionary = create_debug_section("진행", false)
	panel_box.add_child(section["root"])
	var columns := create_debug_columns(section["body"], 2)
	var progression_group := create_debug_group(columns[0], "성장 / 보상")
	var result_group := create_debug_group(columns[1], "결과 / 화면")
	var diagnostics_group := create_debug_group(columns[1], "전투 진단")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	progression_group.add_child(row)
	row.add_child(create_debug_action_button("강제 레벨업", func() -> void:
		var lm = hud._get_level_manager_for_debug()
		if lm and lm.get("current_level") != null:
			hud._invoke_level_debug_method("_set_level", [lm.current_level + 1])
	))
	row.add_child(create_debug_action_button("병사 렙업", func() -> void:
		hud._invoke_level_debug_method("_debug_force_fleet_level_up")
	))
	row.add_child(create_debug_action_button("메타샵", func() -> void:
		hud._invoke_level_debug_method("show_meta_shop")
	))

	var reward_row := HBoxContainer.new()
	reward_row.add_theme_constant_override("separation", 4)
	progression_group.add_child(reward_row)
	reward_row.add_child(create_debug_action_button("해역 보너스", func() -> void:
		if not is_instance_valid(hud.player_ship):
			hud.show_gust_warning_message("해역 보너스 대상 없음", 0.8)
			return
		var applied := SeaSiteRewardHelper.apply_reward(
			hud,
			hud.player_ship,
			SeaSiteRewardHelper.REWARD_MINOR_STAT_BONUS,
			0,
			0.0,
			0.0,
			0.0,
			0,
			0
		)
		if applied:
			if "_last_stat_signature" in hud:
				hud.set("_last_stat_signature", "")
			if hud.has_method("_update_stat_panel"):
				hud.call("_update_stat_panel")
			hud._sync_debug_tools_panel_state()
	))

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	result_group.add_child(row_b)
	row_b.add_child(create_debug_action_button("승리 결과", func() -> void:
		hud._invoke_level_debug_method("_debug_show_victory_result")
	))
	row_b.add_child(create_debug_action_button("패배 결과", func() -> void:
		hud._invoke_level_debug_method("_debug_show_defeat_result")
	))

	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 4)
	result_group.add_child(row_c)
	row_c.add_child(create_debug_action_button("체력바 토글", func() -> void:
		hud.toggle_ship_health_bars()
	))
	row_c.add_child(create_debug_action_button("통계 패널", func() -> void:
		hud.toggle_stat_panel()
	))

	var row_d := HBoxContainer.new()
	row_d.add_theme_constant_override("separation", 4)
	diagnostics_group.add_child(row_d)
	row_d.add_child(create_debug_action_button("대포 디버그", func() -> void:
		hud._invoke_level_debug_method("_debug_cannons")
	))


static func _add_ship_section(hud, panel_box: Control) -> void:
	var section: Dictionary = create_debug_section("함선", false)
	panel_box.add_child(section["root"])
	var columns := create_debug_columns(section["body"], 2)
	var status_group := create_debug_group(columns[0], "상태 모니터")
	var damage_group := create_debug_group(columns[0], "피해 시뮬레이션")
	var action_group := create_debug_group(columns[1], "즉시 조작")
	var crew_group := create_debug_group(columns[1], "승선 / 지원")
	var stat_group := create_debug_group(columns[1], "함선 스탯")

	var ship_status := Label.new()
	ship_status.text = "함선 상태: -"
	NavalUiTheme.style_body(ship_status, 11)
	status_group.add_child(ship_status)
	hud.debug_ship_status_value = ship_status

	var ship_config := Label.new()
	ship_config.text = "설정: -"
	NavalUiTheme.style_muted(ship_config, 10)
	status_group.add_child(ship_config)
	hud.debug_ship_config_value = ship_config

	var enemy_fleet_status := Label.new()
	enemy_fleet_status.text = "근처 편대: -"
	NavalUiTheme.style_muted(enemy_fleet_status, 10)
	status_group.add_child(enemy_fleet_status)
	hud.debug_enemy_fleet_value = enemy_fleet_status

	var ship_ai_status := Label.new()
	ship_ai_status.text = "플레이어 AI: -"
	ship_ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_muted(ship_ai_status, 10)
	status_group.add_child(ship_ai_status)
	hud.debug_ship_ai_value = ship_ai_status

	var enemy_ai_status := Label.new()
	enemy_ai_status.text = "적선 AI: -"
	enemy_ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_muted(enemy_ai_status, 10)
	status_group.add_child(enemy_ai_status)
	hud.debug_enemy_ai_value = enemy_ai_status

	var ally_ai_status := Label.new()
	ally_ai_status.text = "아군 AI: -"
	ally_ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_muted(ally_ai_status, 10)
	status_group.add_child(ally_ai_status)
	hud.debug_ally_ai_value = ally_ai_status

	var support_fleet_status := Label.new()
	support_fleet_status.text = "지원함 진형: -"
	support_fleet_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_muted(support_fleet_status, 10)
	status_group.add_child(support_fleet_status)
	hud.debug_support_fleet_value = support_fleet_status

	var player_soldier_ai_status := Label.new()
	player_soldier_ai_status.text = "아군 병사 AI: -"
	player_soldier_ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_muted(player_soldier_ai_status, 10)
	status_group.add_child(player_soldier_ai_status)
	hud.debug_player_soldier_ai_value = player_soldier_ai_status

	var enemy_soldier_ai_status := Label.new()
	enemy_soldier_ai_status.text = "적 병사 AI: -"
	enemy_soldier_ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_muted(enemy_soldier_ai_status, 10)
	status_group.add_child(enemy_soldier_ai_status)
	hud.debug_enemy_soldier_ai_value = enemy_soldier_ai_status

	var hull_row: Dictionary = create_slider_row("Hull")
	damage_group.add_child(hull_row["root"])
	hud.debug_ship_hull_slider = hull_row["slider"]
	hud.debug_ship_hull_value = hull_row["value"]
	hud.debug_ship_hull_slider.value = 1.0
	hud.debug_ship_hull_value.text = "1.00"
	hud.debug_ship_hull_slider.value_changed.connect(hud._on_debug_ship_hull_changed)

	var stamina_row: Dictionary = create_slider_row("Stamina")
	damage_group.add_child(stamina_row["root"])
	hud.debug_ship_stamina_slider = stamina_row["slider"]
	hud.debug_ship_stamina_value = stamina_row["value"]
	hud.debug_ship_stamina_slider.value = 1.0
	hud.debug_ship_stamina_value.text = "1.00"
	hud.debug_ship_stamina_slider.value_changed.connect(hud._on_debug_ship_stamina_changed)

	var row_a := HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 4)
	action_group.add_child(row_a)
	row_a.add_child(create_debug_action_button("선원 보충", hud._refill_player_crew_for_debug))
	row_a.add_child(create_debug_action_button("지원함 호출", hud._spawn_support_ship_for_debug))

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	action_group.add_child(row_b)
	row_b.add_child(create_debug_action_button("정지", hud._stop_player_ship_for_debug))
	row_b.add_child(create_debug_action_button("화재 토글", hud._toggle_player_ship_fire_for_debug))

	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 4)
	action_group.add_child(row_c)
	row_c.add_child(create_debug_action_button("노젓기 토글", hud._toggle_player_rowing_for_debug))
	row_c.add_child(create_debug_action_button("돛 정렬", hud._auto_adjust_player_sail_for_debug))
	row_c.add_child(create_debug_action_button("돛대 접기", hud._toggle_player_masts_folded_for_debug))

	var row_d := HBoxContainer.new()
	row_d.add_theme_constant_override("separation", 4)
	crew_group.add_child(row_d)
	row_d.add_child(create_debug_action_button("정원 +1", func() -> void:
		hud._adjust_player_crew_capacity_for_debug(1)
	))
	row_d.add_child(create_debug_action_button("정원 -1", func() -> void:
		hud._adjust_player_crew_capacity_for_debug(-1)
	))

	var row_e := HBoxContainer.new()
	row_e.add_theme_constant_override("separation", 4)
	crew_group.add_child(row_e)
	row_e.add_child(create_debug_action_button("장군 +1", func() -> void:
		hud._adjust_player_captain_count_for_debug(1)
	))
	row_e.add_child(create_debug_action_button("장군 -1", func() -> void:
		hud._adjust_player_captain_count_for_debug(-1)
	))

	var row_f := HBoxContainer.new()
	row_f.add_theme_constant_override("separation", 4)
	crew_group.add_child(row_f)
	row_f.add_child(create_debug_action_button("지원한도 +1", func() -> void:
		hud._adjust_player_support_limit_for_debug(1)
	))
	row_f.add_child(create_debug_action_button("지원한도 -1", func() -> void:
		hud._adjust_player_support_limit_for_debug(-1)
	))

	var row_g := HBoxContainer.new()
	row_g.add_theme_constant_override("separation", 4)
	stat_group.add_child(row_g)
	row_g.add_child(create_debug_action_button("속도 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("max_speed", 0.5, 2.0, 30.0, "속도")
	))
	row_g.add_child(create_debug_action_button("속도 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("max_speed", -0.5, 2.0, 30.0, "속도")
	))

	var row_h := HBoxContainer.new()
	row_h.add_theme_constant_override("separation", 4)
	stat_group.add_child(row_h)
	row_h.add_child(create_debug_action_button("선회 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("turn_rate", 5.0, 10.0, 140.0, "선회")
	))
	row_h.add_child(create_debug_action_button("선회 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("turn_rate", -5.0, 10.0, 140.0, "선회")
	))

	var row_i := HBoxContainer.new()
	row_i.add_theme_constant_override("separation", 4)
	stat_group.add_child(row_i)
	row_i.add_child(create_debug_action_button("방어 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("hull_defense", 1.0, 0.0, 20.0, "방어")
	))
	row_i.add_child(create_debug_action_button("방어 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("hull_defense", -1.0, 0.0, 20.0, "방어")
	))

	var row_j := HBoxContainer.new()
	row_j.add_theme_constant_override("separation", 4)
	stat_group.add_child(row_j)
	row_j.add_child(create_debug_action_button("보충 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("crew_respawn_interval", 1.0, 2.0, 30.0, "보충")
	))
	row_j.add_child(create_debug_action_button("보충 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("crew_respawn_interval", -1.0, 2.0, 30.0, "보충")
	))

	var row_k := HBoxContainer.new()
	row_k.add_theme_constant_override("separation", 4)
	stat_group.add_child(row_k)
	row_k.add_child(create_debug_action_button("장악 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("boarding_capture_duration", 0.5, 1.0, 12.0, "장악")
	))
	row_k.add_child(create_debug_action_button("장악 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("boarding_capture_duration", -0.5, 1.0, 12.0, "장악")
	))


static func _add_sail_section(hud, panel_box: Control) -> void:
	var section: Dictionary = create_debug_section("돛", true)
	panel_box.add_child(section["root"])

	var damage_row: Dictionary = create_slider_row("Damage")
	section["body"].add_child(damage_row["root"])
	hud.sail_debug_damage_slider = damage_row["slider"]
	hud.sail_debug_damage_value = damage_row["value"]
	hud.sail_debug_damage_slider.value_changed.connect(hud._on_sail_debug_damage_changed)

	var burn_row: Dictionary = create_slider_row("Burn")
	section["body"].add_child(burn_row["root"])
	hud.sail_debug_burn_slider = burn_row["slider"]
	hud.sail_debug_burn_value = burn_row["value"]
	hud.sail_debug_burn_slider.value_changed.connect(hud._on_sail_debug_burn_changed)

	var hole_row: Dictionary = create_slider_row("Hole")
	section["body"].add_child(hole_row["root"])
	hud.sail_debug_hole_slider = hole_row["slider"]
	hud.sail_debug_hole_value = hole_row["value"]
	hud.sail_debug_hole_slider.max_value = 2.0
	hud.sail_debug_hole_slider.step = 0.01
	hud.sail_debug_hole_slider.value = 1.0
	hud.sail_debug_hole_slider.value_changed.connect(hud._on_sail_debug_hole_changed)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 4)
	section["body"].add_child(preset_row)
	for preset in MastDamagePresets.ALL:
		var preset_button := Button.new()
		preset_button.text = str(preset["name"])
		preset_button.custom_minimum_size = Vector2(0, 26)
		preset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset_button.focus_mode = Control.FOCUS_ALL
		NavalUiTheme.apply_hud_button(preset_button, 11)
		preset_button.pressed.connect(func() -> void:
			hud._apply_sail_debug_values(float(preset["damage"]), float(preset["burn"]), float(preset.get("hole", 1.0)))
		)
		preset_row.add_child(preset_button)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	section["body"].add_child(action_row)

	var sync_button := Button.new()
	sync_button.text = "Sync"
	sync_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync_button.focus_mode = Control.FOCUS_ALL
	NavalUiTheme.apply_hud_button(sync_button, 11)
	sync_button.pressed.connect(hud._sync_sail_debug_panel_from_player)
	action_row.add_child(sync_button)

	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.focus_mode = Control.FOCUS_ALL
	NavalUiTheme.apply_hud_button(reset_button, 11)
	reset_button.pressed.connect(func() -> void:
		hud._apply_sail_debug_values(
			float(MastDamagePresets.CLEAN["damage"]),
			float(MastDamagePresets.CLEAN["burn"]),
			float(MastDamagePresets.CLEAN["hole"])
		)
	)
	action_row.add_child(reset_button)


static func create_debug_columns(parent: Control, column_count: int) -> Array[VBoxContainer]:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var columns: Array[VBoxContainer] = []
	for _index in range(maxi(1, column_count)):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 12)
		row.add_child(column)
		columns.append(column)
	return columns


static func create_debug_group(parent: Control, title_text: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 6)
	parent.add_child(group)

	var title := Label.new()
	title.text = title_text
	NavalUiTheme.style_accent(title, 11)
	group.add_child(title)
	return group


static func create_debug_section(title_text: String, _expanded: bool) -> Dictionary:
	var root := ScrollContainer.new()
	root.name = title_text
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)

	return {"root": root, "toggle": null, "body": body}


static func _update_debug_section_button_text(button: Button, title_text: String, expanded: bool) -> void:
	button.text = "%s %s" % ["▾" if expanded else "▸", title_text]


static func create_debug_action_button(button_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(0, 28)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	NavalUiTheme.apply_hud_button(button, 11)
	button.pressed.connect(callback)
	return button


static func create_slider_row(title_text: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(title, 11)
	header.add_child(title)

	var value := Label.new()
	value.text = "0.00"
	value.custom_minimum_size.x = 38
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	NavalUiTheme.style_accent(value, 11)
	header.add_child(value)
	root.add_child(header)

	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_ALL
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.0
	root.add_child(slider)

	return {"root": root, "slider": slider, "value": value}
