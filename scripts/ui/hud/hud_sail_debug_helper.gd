extends RefCounted
class_name HudSailDebugHelper



static func update_sail_debug_toggle_button_text(hud) -> void:
	if not is_instance_valid(hud.sail_debug_toggle_button):
		return
	hud.sail_debug_toggle_button.text = "Debug 닫기" if is_instance_valid(hud.sail_debug_panel) and hud.sail_debug_panel.visible else "Debug 열기"


static func get_player_masts_for_debug(hud) -> Array[Node]:
	if not HudLookupHelper.ensure_player_ship(hud):
		return []
	var mast_nodes: Array[Node] = []
	var raw_masts = hud.player_ship.get("masts")
	if raw_masts is Array:
		for mast in raw_masts:
			if is_instance_valid(mast):
				mast_nodes.append(mast)
	return mast_nodes


static func apply_sail_debug_values(hud, damage: float, burn: float, hole_strength: float = 1.0) -> void:
	var masts: Array[Node] = get_player_masts_for_debug(hud)
	if masts.is_empty():
		hud.show_gust_warning_message("돛 디버그 대상 없음", 0.9)
		return
	if is_instance_valid(hud.player_ship):
		hud.player_ship.set_meta("debug_sail_burn_override_active", true)
		hud.player_ship.set_meta("debug_sail_burn_override_value", burn)
	var target_damage := clampf(damage, 0.0, 1.0)
	var target_burn := clampf(burn, 0.0, 1.0)
	var target_hole := clampf(hole_strength, 0.0, 2.0)
	for mast in masts:
		mast.set("sail_damage", target_damage)
		if mast.has_method("set_burn_amount"):
			mast.set_burn_amount(target_burn)
		else:
			mast.set("burn_amount", target_burn)
		if mast.has_method("set_hole_alpha_strength"):
			mast.set_hole_alpha_strength(target_hole)
		else:
			mast.set("hole_alpha_strength", target_hole)
	sync_sail_debug_panel_from_player(hud)
	hud.show_gust_warning_message("돛 손상 %.2f | burn %.2f | hole %.2f" % [target_damage, target_burn, target_hole], 0.7)


static func sync_sail_debug_panel_from_player(hud) -> void:
	if not is_instance_valid(hud.sail_debug_panel):
		return
	var masts: Array[Node] = get_player_masts_for_debug(hud)
	if masts.is_empty():
		return
	var first_mast: Node = masts[0]
	var current_damage: float = 0.0
	var current_burn: float = 0.0
	var current_hole: float = 1.0
	if first_mast.has_method("get_sail_damage"):
		current_damage = float(first_mast.get_sail_damage())
	if first_mast.has_method("get_burn_amount"):
		current_burn = float(first_mast.get_burn_amount())
	if first_mast.has_method("get_hole_alpha_strength"):
		current_hole = float(first_mast.get_hole_alpha_strength())
	hud._sail_debug_ui_syncing = true
	if is_instance_valid(hud.sail_debug_damage_slider):
		hud.sail_debug_damage_slider.value = current_damage
	if is_instance_valid(hud.sail_debug_burn_slider):
		hud.sail_debug_burn_slider.value = current_burn
	if is_instance_valid(hud.sail_debug_hole_slider):
		hud.sail_debug_hole_slider.value = current_hole
	if is_instance_valid(hud.sail_debug_damage_value):
		hud.sail_debug_damage_value.text = "%.2f" % current_damage
	if is_instance_valid(hud.sail_debug_burn_value):
		hud.sail_debug_burn_value.text = "%.2f" % current_burn
	if is_instance_valid(hud.sail_debug_hole_value):
		hud.sail_debug_hole_value.text = "%.2f" % current_hole
	hud._sail_debug_ui_syncing = false


static func on_sail_debug_damage_changed(hud, value: float) -> void:
	if hud._sail_debug_ui_syncing:
		return
	var burn_value: float = hud.sail_debug_burn_slider.value if is_instance_valid(hud.sail_debug_burn_slider) else 0.0
	var hole_value: float = hud.sail_debug_hole_slider.value if is_instance_valid(hud.sail_debug_hole_slider) else 1.0
	apply_sail_debug_values(hud, value, burn_value, hole_value)


static func on_sail_debug_burn_changed(hud, value: float) -> void:
	if hud._sail_debug_ui_syncing:
		return
	var damage_value: float = hud.sail_debug_damage_slider.value if is_instance_valid(hud.sail_debug_damage_slider) else 0.0
	var hole_value: float = hud.sail_debug_hole_slider.value if is_instance_valid(hud.sail_debug_hole_slider) else 1.0
	apply_sail_debug_values(hud, damage_value, value, hole_value)


static func on_sail_debug_hole_changed(hud, value: float) -> void:
	if hud._sail_debug_ui_syncing:
		return
	var damage_value: float = hud.sail_debug_damage_slider.value if is_instance_valid(hud.sail_debug_damage_slider) else 0.0
	var burn_value: float = hud.sail_debug_burn_slider.value if is_instance_valid(hud.sail_debug_burn_slider) else 0.0
	apply_sail_debug_values(hud, damage_value, burn_value, value)
