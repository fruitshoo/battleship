extends RefCounted

const HudUpgradeTooltip = preload("res://scripts/ui/hud/hud_upgrade_tooltip.gd")
const HudUpgradeInfoHelper = preload("res://scripts/ui/hud/hud_upgrade_info_helper.gd")


static func setup_upgrade_tooltip(hud) -> void:
	if is_instance_valid(hud.upgrade_tooltip_panel):
		return
	hud.upgrade_tooltip_panel = HudUpgradeTooltip.new()
	hud.add_child(hud.upgrade_tooltip_panel)


static func bind_upgrade_slot_hover(hud, slot: PanelContainer) -> void:
	slot.mouse_entered.connect(hud._on_upgrade_slot_mouse_entered.bind(slot))
	slot.mouse_exited.connect(hud._on_upgrade_slot_mouse_exited.bind(slot))


static func on_upgrade_slot_mouse_entered(hud, slot: PanelContainer) -> void:
	if hud.show_stat_panel:
		return
	if not is_instance_valid(hud.upgrade_tooltip_panel):
		return
	if not slot_has_tooltip(hud, slot):
		return
	hud._tooltip_hover_slot = slot
	hud._tooltip_hover_elapsed = 0.0
	if hud._tooltip_slot_ref != slot and hud.upgrade_tooltip_panel.is_showing():
		show_slot_tooltip(hud, slot)


static func on_upgrade_slot_mouse_exited(hud, slot: PanelContainer) -> void:
	if hud._tooltip_hover_slot == slot:
		hud._tooltip_hover_slot = null
		hud._tooltip_hover_elapsed = 0.0
	if hud._tooltip_slot_ref != slot:
		return
	hud._tooltip_slot_ref = null
	hide_upgrade_tooltip(hud)


static func update_upgrade_tooltip_state(hud, delta: float) -> void:
	if hud.show_stat_panel:
		if is_instance_valid(hud.upgrade_tooltip_panel) and hud.upgrade_tooltip_panel.is_showing():
			hide_upgrade_tooltip(hud, true)
		return
	if is_instance_valid(hud._tooltip_hover_slot):
		hud._tooltip_hover_elapsed += delta
		if (not is_instance_valid(hud.upgrade_tooltip_panel) or not hud.upgrade_tooltip_panel.is_showing()) and hud._tooltip_hover_elapsed >= hud.UPGRADE_TOOLTIP_SHOW_DELAY:
			show_slot_tooltip(hud, hud._tooltip_hover_slot)


static func show_slot_tooltip(hud, slot: PanelContainer) -> void:
	if hud.show_stat_panel:
		return
	if not is_instance_valid(hud.upgrade_tooltip_panel):
		return
	var tooltip_payload: Dictionary = get_slot_tooltip_payload(hud, slot)
	if tooltip_payload.is_empty():
		return
	hud._tooltip_slot_ref = slot
	hud.upgrade_tooltip_panel.show_tooltip(
		str(tooltip_payload.get("text", "")),
		tooltip_payload.get("color", Color(0.9, 0.85, 0.6, 1.0)),
		hud.get_viewport().get_mouse_position(),
		hud.get_viewport().get_visible_rect().size
	)


static func slot_has_tooltip(hud, slot: PanelContainer) -> bool:
	return not get_slot_tooltip_payload(hud, slot).is_empty()


static func get_slot_tooltip_payload(hud, slot: PanelContainer) -> Dictionary:
	var tooltip_text: String = str(slot.get_meta("tooltip_text", ""))
	if not tooltip_text.is_empty():
		return {
			"text": tooltip_text,
			"color": slot.get_meta("tooltip_color", Color(0.9, 0.85, 0.6, 1.0))
		}
	var upgrade_id: String = str(slot.get_meta("upgrade_id", ""))
	var level: int = int(slot.get_meta("upgrade_level", 0))
	if upgrade_id.is_empty() or level <= 0:
		return {}
	return {
		"text": HudUpgradeInfoHelper.build_upgrade_tooltip_text(hud, upgrade_id, level),
		"color": HudUpgradeInfoHelper.get_upgrade_color(upgrade_id)
	}


static func hide_upgrade_tooltip(hud, instant: bool = false) -> void:
	if not is_instance_valid(hud.upgrade_tooltip_panel):
		return
	hud.upgrade_tooltip_panel.hide_tooltip(instant)


static func update_upgrade_tooltip_position(hud) -> void:
	if not is_instance_valid(hud.upgrade_tooltip_panel) or not hud.upgrade_tooltip_panel.is_showing():
		return
	hud.upgrade_tooltip_panel.update_position(
		hud.get_viewport().get_mouse_position(),
		hud.get_viewport().get_visible_rect().size
	)


static func update_upgrade_track_slot(hud, upgrade_id: String, level: int, track: String) -> void:
	if level <= 0:
		return
	var actual_icon: String = HudUpgradeInfoHelper.get_upgrade_icon(upgrade_id)
	var actual_color: Color = HudUpgradeInfoHelper.get_upgrade_color(upgrade_id)
	var track_node = hud.weapon_track if track == "ship" else hud.support_track
	if not track_node:
		return

	var slot_idx := -1
	if track == "ship":
		if hud.active_weapons.has(upgrade_id):
			slot_idx = hud.active_weapons[upgrade_id]
		else:
			slot_idx = hud.active_weapons.size()
			hud.active_weapons[upgrade_id] = slot_idx
	else:
		if hud.active_supports.has(upgrade_id):
			slot_idx = hud.active_supports[upgrade_id]
		else:
			slot_idx = hud.active_supports.size()
			hud.active_supports[upgrade_id] = slot_idx

	var slot = track_node.update_slot(slot_idx, upgrade_id, level, actual_icon, actual_color)
	if is_instance_valid(slot) and not bool(slot.get_meta("hover_bound", false)):
		bind_upgrade_slot_hover(hud, slot)
		slot.set_meta("hover_bound", true)

	if track == "ship":
		hud.weapon_slots = track_node.slots
	else:
		hud.support_slots = track_node.slots


static func update_ship_upgrade_ui(hud, upgrade_id: String, level: int) -> void:
	update_upgrade_track_slot(hud, upgrade_id, level, "ship")


static func update_crew_upgrade_ui(hud, upgrade_id: String, level: int) -> void:
	update_upgrade_track_slot(hud, upgrade_id, level, "crew")


static func update_weapon_ui(hud, weapon_id: String, level: int) -> void:
	if HudUpgradeInfoHelper.is_crew_upgrade(hud, weapon_id):
		update_crew_upgrade_ui(hud, weapon_id, level)
		return
	update_ship_upgrade_ui(hud, weapon_id, level)


static func update_support_ui(hud, upgrade_id: String, level: int) -> void:
	if HudUpgradeInfoHelper.is_crew_upgrade(hud, upgrade_id):
		update_crew_upgrade_ui(hud, upgrade_id, level)
		return
	update_ship_upgrade_ui(hud, upgrade_id, level)
