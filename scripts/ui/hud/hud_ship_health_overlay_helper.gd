extends RefCounted

const HudGaugeBar = preload("res://scripts/ui/hud/hud_gauge_bar.gd")


static func setup_ship_hp_overlay(hud) -> void:
	if is_instance_valid(hud.ship_hp_overlay):
		_setup_player_status_overlay(hud)
		return
	hud.ship_hp_overlay = Control.new()
	hud.ship_hp_overlay.name = "ShipHealthOverlay"
	hud.ship_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.ship_hp_overlay.z_index = -30
	hud.add_child(hud.ship_hp_overlay)
	hud.ship_hp_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_player_status_overlay(hud)


static func _setup_player_status_overlay(hud) -> void:
	if is_instance_valid(hud.player_status_root):
		return
	var root := Control.new()
	root.name = "PlayerStatus"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = Vector2(hud.PLAYER_STATUS_BAR_WIDTH, hud.PLAYER_STATUS_STACK_HEIGHT)
	root.size = root.custom_minimum_size
	root.z_index = 10
	root.visible = false
	hud.ship_hp_overlay.add_child(root)
	hud.player_status_root = root

	hud.hp_bar = HudGaugeBar.new()
	hud.hp_bar.name = "Hull"
	hud.hp_bar.show_percentage = false
	hud.hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.hp_bar.custom_minimum_size = Vector2(hud.PLAYER_STATUS_BAR_WIDTH, hud.PLAYER_STATUS_HP_HEIGHT)
	hud.hp_bar.size = hud.hp_bar.custom_minimum_size
	root.add_child(hud.hp_bar)
	hud.hp_bar.configure_gauge(Color(0.02, 0.03, 0.04, 0.58), Color(0.22, 0.76, 0.34, 0.95), 3, {
		"border_color": Color(0.0, 0.0, 0.0, 0.0),
		"damage_trail": false,
		"low_pulse": false,
		"low_pulse_threshold": 0.28,
		"segments": 0,
		"shine_strength": 0.08,
		"trail_follow_speed": 3.8,
	})

	hud.hp_text_label = Label.new()
	hud.hp_text_label.name = "HullText"
	hud.hp_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.hp_text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.hp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.hp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_value(hud.hp_text_label, 11)
	hud.hp_text_label.visible = false
	hud.hp_bar.add_child(hud.hp_text_label)

	hud.speed_bar = HudGaugeBar.new()
	hud.speed_bar.name = "Speed"
	hud.speed_bar.show_percentage = false
	hud.speed_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.speed_bar.position = Vector2(0.0, hud.PLAYER_STATUS_HP_HEIGHT + hud.PLAYER_STATUS_BAR_GAP)
	hud.speed_bar.custom_minimum_size = Vector2(hud.PLAYER_STATUS_BAR_WIDTH, hud.PLAYER_STATUS_SPEED_HEIGHT)
	hud.speed_bar.size = hud.speed_bar.custom_minimum_size
	hud.speed_bar.min_value = 0.0
	hud.speed_bar.max_value = 100.0
	hud.speed_bar.value = 0.0
	root.add_child(hud.speed_bar)
	hud.speed_bar.configure_gauge(Color(0.03, 0.04, 0.06, 0.42), NavalUiTheme.STATUS_ACTIVE_BLUE, 1, {
		"damage_trail": false,
		"low_pulse": false,
		"border_color": Color(0.0, 0.0, 0.0, 0.0),
		"shine_strength": 0.02,
	})

	hud.speed_bar_label = Label.new()
	hud.speed_bar_label.name = "SpeedText"
	hud.speed_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.speed_bar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.speed_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.speed_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.speed_bar_label.text = "0.0"
	hud.speed_bar_label.visible = false
	NavalUiTheme.style_overlay_value(hud.speed_bar_label, 11)
	hud.speed_bar_label.add_theme_constant_override("outline_size", 4)
	hud.speed_bar.add_child(hud.speed_bar_label)


static func update_ship_health_bars(hud, positions_only: bool = false) -> void:
	hud.HudUpdateHelper.update_ship_health_bars(hud, positions_only)


static func toggle_ship_health_bars(hud) -> void:
	hud.show_ship_health_bars = not hud.show_ship_health_bars
	update_ship_health_bars(hud)
