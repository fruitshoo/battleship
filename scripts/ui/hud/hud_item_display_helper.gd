extends RefCounted


static func add_item_icon(hud, icon_data) -> void:
	if hud.item_bar == null:
		return
	var slot: PanelContainer = hud.item_bar.add_icon(icon_data)
	if is_instance_valid(slot):
		var item_name := ""
		var item_description := ""
		if icon_data is Dictionary:
			item_name = str(icon_data.get("name", "아이템"))
			item_description = str(icon_data.get("description", ""))
		var tooltip_text := "[%s]\n%s" % [item_name, item_description]
		slot.set_meta("tooltip_text", tooltip_text.strip_edges())
		slot.set_meta("tooltip_color", NavalUiTheme.TEXT_GOLD)
		if slot.get_meta("hover_bound", false) != true:
			hud._bind_upgrade_slot_hover(slot)
			slot.set_meta("hover_bound", true)


static func clear_item_icons(hud) -> void:
	if hud.item_bar == null:
		return
	if hud.item_bar.has_method("clear_icons"):
		hud.item_bar.clear_icons()


static func refresh_owned_item_icons(hud) -> void:
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("refresh_hud_item_icons"):
		UpgradeManager.refresh_hud_item_icons()
