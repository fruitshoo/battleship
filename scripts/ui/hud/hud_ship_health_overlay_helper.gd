extends RefCounted


static func setup_ship_hp_overlay(hud) -> void:
	if is_instance_valid(hud.ship_hp_overlay):
		return
	hud.ship_hp_overlay = Control.new()
	hud.ship_hp_overlay.name = "ShipHealthOverlay"
	hud.ship_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.ship_hp_overlay.z_index = 20
	hud.add_child(hud.ship_hp_overlay)
	hud.ship_hp_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func update_ship_health_bars(hud, positions_only: bool = false) -> void:
	hud.HudUpdateHelper.update_ship_health_bars(hud, positions_only)


static func toggle_ship_health_bars(hud) -> void:
	hud.show_ship_health_bars = not hud.show_ship_health_bars
	update_ship_health_bars(hud)
