extends RefCounted
class_name ProjectContractSaveHelper


static func run_save_contract_smoke(failures: Array[String]) -> void:
	if not is_instance_valid(SaveManager):
		failures.append("SaveManager autoload is not available for save smoke")
		return

	var save_path := "user://save_data.cfg"
	var backup_path := "user://save_data.backup.cfg"
	var save_backup := _capture_file_bytes(save_path)
	var backup_backup := _capture_file_bytes(backup_path)
	var snapshot := _capture_save_manager_state()
	var expected := {
		"gold": 1234,
		"meta_upgrades": {"hull_hp": 3, "sailing": 2},
		"items": ["choyogi", "ilseongjeongsiui"],
		"settings": {
			"master_volume": 0.12,
			"music_volume": 0.34,
			"sfx_volume": 0.56,
			"ui_volume": 0.78,
			"fullscreen": false,
		},
	}

	_apply_save_manager_state(expected)
	SaveManager.save_game()

	var loaded_main := ConfigFile.new()
	if loaded_main.load(save_path) != OK:
		failures.append("save smoke could not reload main save file")
	else:
		_validate_save_config(loaded_main, expected, "main save smoke", failures)

	var loaded_backup := ConfigFile.new()
	if loaded_backup.load(backup_path) != OK:
		failures.append("save smoke could not reload backup save file")
	else:
		_validate_save_config(loaded_backup, expected, "backup save smoke", failures)

	_apply_save_manager_state({
		"gold": 1,
		"meta_upgrades": {"wrong": 99},
		"items": ["wrong"],
		"settings": {},
	})
	SaveManager.load_game()
	_validate_save_manager_state(expected, "save smoke roundtrip", failures)

	_restore_save_manager_state(snapshot)
	_restore_file_bytes(save_path, save_backup, failures)
	_restore_file_bytes(backup_path, backup_backup, failures)


static func _capture_save_manager_state() -> Dictionary:
	return {
		"gold": SaveManager.gold,
		"meta_upgrades": SaveManager.meta_upgrades.duplicate(true),
		"items": SaveManager.get_items(),
		"settings": _capture_settings_snapshot(),
	}


static func _capture_settings_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for key in ["master_volume", "music_volume", "sfx_volume", "ui_volume", "fullscreen"]:
		snapshot[key] = SaveManager.get_setting(key)
	return snapshot


static func _apply_save_manager_state(state: Dictionary) -> void:
	SaveManager.gold = int(state.get("gold", 0))
	SaveManager.meta_upgrades = {}
	var meta_upgrades_value = state.get("meta_upgrades", {})
	if meta_upgrades_value is Dictionary:
		SaveManager.meta_upgrades = meta_upgrades_value.duplicate(true)
	SaveManager.items = []
	var items_value = state.get("items", [])
	if items_value is Array:
		for item_id in items_value:
			SaveManager.items.append(str(item_id))
	var settings_value = state.get("settings", {})
	SaveManager.settings = {}
	if settings_value is Dictionary:
		SaveManager.settings = settings_value.duplicate(true)


static func _restore_save_manager_state(snapshot: Dictionary) -> void:
	_apply_save_manager_state(snapshot)


static func _validate_save_manager_state(expected: Dictionary, label: String, failures: Array[String]) -> void:
	if SaveManager.gold != int(expected.get("gold", 0)):
		failures.append("%s gold mismatch" % label)
	if SaveManager.meta_upgrades != expected.get("meta_upgrades", {}):
		failures.append("%s meta upgrade mismatch" % label)
	if SaveManager.get_items() != expected.get("items", []):
		failures.append("%s items mismatch" % label)
	var expected_settings: Dictionary = expected.get("settings", {})
	for key in expected_settings.keys():
		if SaveManager.get_setting(str(key)) != expected_settings[key]:
			failures.append("%s setting mismatch for %s" % [label, key])


static func _validate_save_config(config: ConfigFile, expected: Dictionary, label: String, failures: Array[String]) -> void:
	var expected_gold: int = int(expected.get("gold", 0))
	var expected_meta_upgrades: Dictionary = expected.get("meta_upgrades", {})
	var expected_items: Array = expected.get("items", [])
	var expected_settings: Dictionary = expected.get("settings", {})

	if int(config.get_value("player", "gold", -1)) != expected_gold:
		failures.append("%s gold mismatch" % label)

	var loaded_meta_upgrades = config.get_value("player", "meta_upgrades", {})
	if loaded_meta_upgrades != expected_meta_upgrades:
		failures.append("%s meta upgrade mismatch" % label)

	var loaded_items = config.get_value("player", "items", [])
	if loaded_items != expected_items:
		failures.append("%s items mismatch" % label)

	var loaded_settings = config.get_value("player", "settings", {})
	if not (loaded_settings is Dictionary):
		failures.append("%s settings payload mismatch" % label)
	else:
		for key in expected_settings.keys():
			if loaded_settings.get(key) != expected_settings[key]:
				failures.append("%s setting mismatch for %s" % [label, key])


static func _capture_file_bytes(path: String) -> Dictionary:
	var payload := {"exists": false, "bytes": PackedByteArray()}
	if not FileAccess.file_exists(path):
		return payload
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return payload
	payload["exists"] = true
	payload["bytes"] = file.get_buffer(file.get_length())
	file.close()
	return payload


static func _restore_file_bytes(path: String, payload: Dictionary, failures: Array[String]) -> void:
	if payload.is_empty():
		return
	var existed: bool = payload.get("exists", false) == true
	var bytes: PackedByteArray = payload.get("bytes", PackedByteArray())
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			failures.append("failed to restore file: %s" % path)
			return
		file.store_buffer(bytes)
		file.close()
	elif FileAccess.file_exists(path):
		var remove_err := DirAccess.remove_absolute(path)
		if remove_err != OK:
			failures.append("failed to remove temp save file: %s" % path)
