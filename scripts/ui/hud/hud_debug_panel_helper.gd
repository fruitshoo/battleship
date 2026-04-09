extends RefCounted
class_name HudDebugPanelHelper

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const MastDamagePresets = preload("res://scripts/props/mast_damage_presets.gd")


static func setup_debug_panel(hud) -> void:
	if not OS.is_debug_build():
		return
	if is_instance_valid(hud.sail_debug_panel):
		return

	hud.sail_debug_toggle_button = Button.new()
	hud.sail_debug_toggle_button.name = "DebugToolsToggle"
	hud.sail_debug_toggle_button.text = "Debug"
	hud.sail_debug_toggle_button.custom_minimum_size = Vector2(72, 30)
	NavalUiTheme.apply_hud_button(hud.sail_debug_toggle_button, 11)
	hud.sail_debug_toggle_button.pressed.connect(func() -> void:
		if not is_instance_valid(hud.sail_debug_panel):
			return
		hud.sail_debug_panel.visible = not hud.sail_debug_panel.visible
		hud._update_sail_debug_toggle_button_text()
		if hud.sail_debug_panel.visible:
			hud._sync_sail_debug_panel_from_player()
			hud._sync_debug_tools_panel_state()
	)
	if is_instance_valid(hud.bottom_right_container):
		hud.bottom_right_container.add_child(hud.sail_debug_toggle_button)
	else:
		hud.add_child(hud.sail_debug_toggle_button)
		hud.sail_debug_toggle_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		hud.sail_debug_toggle_button.offset_right = -24
		hud.sail_debug_toggle_button.offset_bottom = -24

	hud.sail_debug_panel = PanelContainer.new()
	hud.sail_debug_panel.name = "SailDebugPanel"
	var panel_style := NavalUiTheme.make_hud_panel_style()
	hud.sail_debug_panel.add_theme_stylebox_override("panel", panel_style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(232, 280)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hud.sail_debug_panel.add_child(scroll)

	var panel_box := VBoxContainer.new()
	panel_box.custom_minimum_size = Vector2(212, 0)
	panel_box.add_theme_constant_override("separation", 6)
	scroll.add_child(panel_box)

	var title := Label.new()
	title.text = "Debug Tools"
	NavalUiTheme.style_heading(title, 13)
	panel_box.add_child(title)

	var hint := Label.new()
	hint.text = "기존 F키 기능을 버튼으로 모아둔 패널"
	NavalUiTheme.style_muted(hint, 10)
	panel_box.add_child(hint)

	_add_environment_section(hud, panel_box)
	_add_collision_section(hud, panel_box)
	_add_spawn_section(hud, panel_box)
	_add_misc_section(hud, panel_box)
	_add_ship_section(hud, panel_box)
	_add_sail_section(hud, panel_box)

	if is_instance_valid(hud.bottom_right_container):
		hud.bottom_right_container.add_child(hud.sail_debug_panel)
	else:
		hud.add_child(hud.sail_debug_panel)
		hud.sail_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		hud.sail_debug_panel.offset_right = -24
		hud.sail_debug_panel.offset_bottom = -120
	hud.sail_debug_panel.visible = false
	hud._sync_sail_debug_panel_from_player()
	hud._sync_debug_tools_panel_state()
	hud._update_sail_debug_toggle_button_text()


static func _add_environment_section(hud, panel_box: VBoxContainer) -> void:
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


static func _add_collision_section(hud, panel_box: VBoxContainer) -> void:
	var section: Dictionary = create_debug_section("충돌", false)
	panel_box.add_child(section["root"])

	var collision_status := Label.new()
	collision_status.text = "충돌 시각화: OFF"
	NavalUiTheme.style_body(collision_status, 11)
	section["body"].add_child(collision_status)
	hud.debug_collision_value = collision_status

	var distance_status := Label.new()
	distance_status.text = "거리 표시: OFF"
	NavalUiTheme.style_body(distance_status, 11)
	section["body"].add_child(distance_status)
	hud.debug_distance_value = distance_status

	var collision_row := HBoxContainer.new()
	collision_row.add_theme_constant_override("separation", 6)
	section["body"].add_child(collision_row)
	collision_row.add_child(create_debug_action_button("표시 토글", func() -> void:
		hud._invoke_level_debug_method("_toggle_collision_visualizers")
		hud._sync_debug_tools_panel_state()
	))
	collision_row.add_child(create_debug_action_button("모드 순환", func() -> void:
		hud._invoke_level_debug_method("_cycle_collision_visualizer_mode")
		hud._sync_debug_tools_panel_state()
	))

	var distance_row := HBoxContainer.new()
	distance_row.add_theme_constant_override("separation", 6)
	section["body"].add_child(distance_row)
	distance_row.add_child(create_debug_action_button("거리 토글", func() -> void:
		hud._toggle_distance_debug()
		hud._sync_debug_tools_panel_state()
	))


static func _add_spawn_section(hud, panel_box: VBoxContainer) -> void:
	var section: Dictionary = create_debug_section("스폰", false)
	panel_box.add_child(section["root"])

	var row_a := HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_a)
	row_a.add_child(create_debug_action_button("세키 근접", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_test_ship", ["sekibune_melee", 40.0, -12.0])
	))
	row_a.add_child(create_debug_action_button("세키 포격", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_test_ship", ["sekibune_cannon", 40.0, 12.0])
	))

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_b)
	row_b.add_child(create_debug_action_button("중간보스", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_mid_boss")
	))
	row_b.add_child(create_debug_action_button("최종보스", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_final_boss")
	))

	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_c)
	row_c.add_child(create_debug_action_button("지원함 추가", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_support_ship")
	))
	row_c.add_child(create_debug_action_button("지원함 덤프", func() -> void:
		hud._invoke_level_debug_method("_debug_dump_support_fleet_state")
	))

	var row_d := HBoxContainer.new()
	row_d.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_d)
	row_d.add_child(create_debug_action_button("소형 편대", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_fleet", ["light"])
	))
	row_d.add_child(create_debug_action_button("혼성 편대", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_fleet", ["mixed"])
	))
	row_d.add_child(create_debug_action_button("대형 편대", func() -> void:
		hud._invoke_level_debug_method("_debug_spawn_fleet", ["heavy"])
	))


static func _add_misc_section(hud, panel_box: VBoxContainer) -> void:
	var section: Dictionary = create_debug_section("게임", false)
	panel_box.add_child(section["root"])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	section["body"].add_child(row)
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

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_b)
	row_b.add_child(create_debug_action_button("대포 디버그", func() -> void:
		hud._invoke_level_debug_method("_debug_cannons")
	))
	row_b.add_child(create_debug_action_button("체력바 토글", func() -> void:
		hud.toggle_ship_health_bars()
	))

	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_c)
	row_c.add_child(create_debug_action_button("통계 패널", func() -> void:
		hud.toggle_stat_panel()
	))


static func _add_ship_section(hud, panel_box: VBoxContainer) -> void:
	var section: Dictionary = create_debug_section("함선", false)
	panel_box.add_child(section["root"])

	var ship_status := Label.new()
	ship_status.text = "함선 상태: -"
	NavalUiTheme.style_body(ship_status, 11)
	section["body"].add_child(ship_status)
	hud.debug_ship_status_value = ship_status

	var ship_config := Label.new()
	ship_config.text = "설정: -"
	NavalUiTheme.style_muted(ship_config, 10)
	section["body"].add_child(ship_config)
	hud.debug_ship_config_value = ship_config

	var enemy_fleet_status := Label.new()
	enemy_fleet_status.text = "근처 편대: -"
	NavalUiTheme.style_muted(enemy_fleet_status, 10)
	section["body"].add_child(enemy_fleet_status)
	hud.debug_enemy_fleet_value = enemy_fleet_status

	var hull_row: Dictionary = create_slider_row("Hull")
	section["body"].add_child(hull_row["root"])
	hud.debug_ship_hull_slider = hull_row["slider"]
	hud.debug_ship_hull_value = hull_row["value"]
	hud.debug_ship_hull_slider.value = 1.0
	hud.debug_ship_hull_value.text = "1.00"
	hud.debug_ship_hull_slider.value_changed.connect(hud._on_debug_ship_hull_changed)

	var stamina_row: Dictionary = create_slider_row("Stamina")
	section["body"].add_child(stamina_row["root"])
	hud.debug_ship_stamina_slider = stamina_row["slider"]
	hud.debug_ship_stamina_value = stamina_row["value"]
	hud.debug_ship_stamina_slider.value = 1.0
	hud.debug_ship_stamina_value.text = "1.00"
	hud.debug_ship_stamina_slider.value_changed.connect(hud._on_debug_ship_stamina_changed)

	var row_a := HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_a)
	row_a.add_child(create_debug_action_button("선원 보충", hud._refill_player_crew_for_debug))
	row_a.add_child(create_debug_action_button("지원함 호출", hud._spawn_support_ship_for_debug))

	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_b)
	row_b.add_child(create_debug_action_button("정지", hud._stop_player_ship_for_debug))
	row_b.add_child(create_debug_action_button("화재 토글", hud._toggle_player_ship_fire_for_debug))

	var row_c := HBoxContainer.new()
	row_c.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_c)
	row_c.add_child(create_debug_action_button("노젓기 토글", hud._toggle_player_rowing_for_debug))
	row_c.add_child(create_debug_action_button("돛 정렬", hud._auto_adjust_player_sail_for_debug))

	var row_d := HBoxContainer.new()
	row_d.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_d)
	row_d.add_child(create_debug_action_button("정원 +1", func() -> void:
		hud._adjust_player_crew_capacity_for_debug(1)
	))
	row_d.add_child(create_debug_action_button("정원 -1", func() -> void:
		hud._adjust_player_crew_capacity_for_debug(-1)
	))

	var row_e := HBoxContainer.new()
	row_e.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_e)
	row_e.add_child(create_debug_action_button("장군 +1", func() -> void:
		hud._adjust_player_captain_count_for_debug(1)
	))
	row_e.add_child(create_debug_action_button("장군 -1", func() -> void:
		hud._adjust_player_captain_count_for_debug(-1)
	))

	var row_f := HBoxContainer.new()
	row_f.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_f)
	row_f.add_child(create_debug_action_button("지원한도 +1", func() -> void:
		hud._adjust_player_support_limit_for_debug(1)
	))
	row_f.add_child(create_debug_action_button("지원한도 -1", func() -> void:
		hud._adjust_player_support_limit_for_debug(-1)
	))

	var row_g := HBoxContainer.new()
	row_g.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_g)
	row_g.add_child(create_debug_action_button("속도 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("max_speed", 0.5, 2.0, 30.0, "속도")
	))
	row_g.add_child(create_debug_action_button("속도 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("max_speed", -0.5, 2.0, 30.0, "속도")
	))

	var row_h := HBoxContainer.new()
	row_h.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_h)
	row_h.add_child(create_debug_action_button("선회 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("turn_rate", 5.0, 10.0, 140.0, "선회")
	))
	row_h.add_child(create_debug_action_button("선회 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("turn_rate", -5.0, 10.0, 140.0, "선회")
	))

	var row_i := HBoxContainer.new()
	row_i.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_i)
	row_i.add_child(create_debug_action_button("방어 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("hull_defense", 1.0, 0.0, 20.0, "방어")
	))
	row_i.add_child(create_debug_action_button("방어 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("hull_defense", -1.0, 0.0, 20.0, "방어")
	))

	var row_j := HBoxContainer.new()
	row_j.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_j)
	row_j.add_child(create_debug_action_button("보충 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("crew_respawn_interval", 1.0, 2.0, 30.0, "보충")
	))
	row_j.add_child(create_debug_action_button("보충 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("crew_respawn_interval", -1.0, 2.0, 30.0, "보충")
	))

	var row_k := HBoxContainer.new()
	row_k.add_theme_constant_override("separation", 4)
	section["body"].add_child(row_k)
	row_k.add_child(create_debug_action_button("장악 +", func() -> void:
		hud._adjust_player_ship_float_for_debug("boarding_capture_duration", 0.5, 1.0, 12.0, "장악")
	))
	row_k.add_child(create_debug_action_button("장악 -", func() -> void:
		hud._adjust_player_ship_float_for_debug("boarding_capture_duration", -0.5, 1.0, 12.0, "장악")
	))


static func _add_sail_section(hud, panel_box: VBoxContainer) -> void:
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
	NavalUiTheme.apply_hud_button(sync_button, 11)
	sync_button.pressed.connect(hud._sync_sail_debug_panel_from_player)
	action_row.add_child(sync_button)

	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.apply_hud_button(reset_button, 11)
	reset_button.pressed.connect(func() -> void:
		hud._apply_sail_debug_values(
			float(MastDamagePresets.CLEAN["damage"]),
			float(MastDamagePresets.CLEAN["burn"]),
			float(MastDamagePresets.CLEAN["hole"])
		)
	)
	action_row.add_child(reset_button)


static func create_debug_section(title_text: String, expanded: bool) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)

	var toggle := Button.new()
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.flat = true
	toggle.text = ""
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.add_theme_color_override("font_color", NavalUiTheme.TEXT_ACCENT)
	root.add_child(toggle)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.visible = expanded
	root.add_child(body)

	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		_update_debug_section_button_text(toggle, title_text, body.visible)
	)
	_update_debug_section_button_text(toggle, title_text, expanded)

	return {"root": root, "toggle": toggle, "body": body}


static func _update_debug_section_button_text(button: Button, title_text: String, expanded: bool) -> void:
	button.text = "%s %s" % ["▾" if expanded else "▸", title_text]


static func create_debug_action_button(button_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(0, 28)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.0
	root.add_child(slider)

	return {"root": root, "slider": slider, "value": value}
