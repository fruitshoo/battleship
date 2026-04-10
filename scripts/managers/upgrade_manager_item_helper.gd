extends RefCounted


static func load_items_from_resources(manager) -> bool:
	manager.ITEMS.clear()
	var dir := DirAccess.open(manager.ITEM_DATA_DIR)
	if dir == null:
		return false

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource_path := "%s/%s" % [manager.ITEM_DATA_DIR, file_name]
			var item_res: Resource = load(resource_path)
			if item_res != null and item_res.get_script() == manager.ItemDataResource:
				var item_id := str(item_res.get("item_id"))
				if item_id.is_empty():
					file_name = dir.get_next()
					continue
				var item_name := str(item_res.get("item_name"))
				var item_description := str(item_res.get("description"))
				var item_icon := str(item_res.get("icon"))
				var item_alert_msg := str(item_res.get("alert_msg"))
				var icon_texture_variant: Variant = item_res.get("icon_texture")
				var icon_texture_path := ""
				if icon_texture_variant is Texture2D:
					icon_texture_path = (icon_texture_variant as Texture2D).resource_path
				manager.ITEMS[item_id] = {
					"name": item_name,
					"description": item_description,
					"icon": item_icon,
					"icon_texture": icon_texture_path,
					"alert_msg": item_alert_msg,
					"resource_path": resource_path,
				}
		file_name = dir.get_next()
	dir.list_dir_end()

	return not manager.ITEMS.is_empty()


static func equip_owned_items(manager) -> void:
	manager._sync_items_from_save()
	var ship = manager._get_player_ship()
	if not ship:
		return
	for item_id in manager.acquired_items:
		if item_id not in manager.ITEMS:
			continue
		manager._apply_item_to_ship(item_id, ship)
	manager.refresh_hud_item_icons()


static func refresh_hud_item_icons(manager) -> void:
	manager._sync_items_from_save()
	var ship = manager._get_player_ship()
	if not ship:
		return
	for item_id in manager.acquired_items:
		if item_id in manager.ITEMS:
			manager._apply_item_to_ship(item_id, ship)
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if not hud:
		return
	if hud.has_method("clear_item_icons"):
		hud.clear_item_icons()
	for item_id in manager.acquired_items:
		if item_id not in manager.ITEMS:
			continue
		var item_data = manager.ITEMS[item_id]
		if hud.has_method("add_item_icon"):
			var item_icon: Dictionary = get_item_icon_payload(item_id, item_data)
			if not item_icon.is_empty():
				hud.add_item_icon(item_icon)


static func add_item(manager, item_id: String) -> void:
	if item_id not in manager.ITEMS:
		push_warning("UpgradeManager: 존재하지 않는 아이템 ID입니다 - %s" % item_id)
		return

	if manager.acquired_items.has(item_id):
		var existing_ship = manager._get_player_ship()
		if existing_ship:
			manager._apply_item_to_ship(item_id, existing_ship)
			manager.refresh_hud_item_icons()
		return

	manager.acquired_items.append(item_id)
	if is_instance_valid(SaveManager) and SaveManager.has_method("add_item"):
		SaveManager.add_item(item_id)

	var item_data = manager.ITEMS[item_id]
	var ship = manager._get_player_ship()
	if ship:
		manager._apply_item_to_ship(item_id, ship)
		manager.refresh_hud_item_icons()
		var hud = ship._find_hud() if ship.has_method("_find_hud") else null
		if hud and "alert_msg" in item_data and hud.has_method("show_message"):
			hud.show_message(item_data["alert_msg"], 3.0)

	print("[Item] %s 획득! - %s" % [item_data["name"], item_data["description"]])


static func get_item_icon_payload(item_id: String, item_data: Dictionary) -> Dictionary:
	var payload: Dictionary = {
		"item_id": item_id,
		"name": str(item_data.get("name", item_id)),
		"description": str(item_data.get("description", "")),
		"icon_data": null,
	}
	if "icon_texture" in item_data:
		var icon_texture_path := str(item_data["icon_texture"])
		if not icon_texture_path.is_empty():
			payload["icon_data"] = icon_texture_path
			return payload
	if "icon" in item_data:
		payload["icon_data"] = item_data["icon"]
	return payload
