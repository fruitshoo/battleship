extends RefCounted
class_name ProjectContractSaveHelper


static func run_save_contract_smoke(failures: Array[String]) -> void:
	if not is_instance_valid(SaveManager):
		failures.append("SaveManager autoload is not available for save smoke")
		return
	_validate_default_settings(failures)
	_validate_fullscreen_window_mode_updates(failures)

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
			"performance_preset": "performance",
			"fullscreen": false,
			"screen_edge_fx_enabled": true,
			"screen_edge_fx_strength": 0.42,
			"sail_control_mode": "auto",
			"control_scheme": "screen",
			"gamepad_confirm_button": "auto",
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


static func _validate_fullscreen_window_mode_updates(failures: Array[String]) -> void:
	var no_change: int = SaveManager.WINDOW_MODE_NO_CHANGE
	var windowed := DisplayServer.WINDOW_MODE_WINDOWED
	var maximized := DisplayServer.WINDOW_MODE_MAXIMIZED
	var fullscreen := DisplayServer.WINDOW_MODE_FULLSCREEN
	var exclusive := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

	if SaveManager._get_fullscreen_window_mode_update(windowed, false) != no_change:
		failures.append("fullscreen setting should not reapply windowed mode to a normal window")
	if SaveManager._get_fullscreen_window_mode_update(maximized, false) != no_change:
		failures.append("fullscreen setting should not shrink a maximized window")
	if SaveManager._get_fullscreen_window_mode_update(fullscreen, false) != windowed:
		failures.append("fullscreen setting should leave fullscreen when disabled")
	if SaveManager._get_fullscreen_window_mode_update(exclusive, false) != windowed:
		failures.append("fullscreen setting should leave exclusive fullscreen when disabled")
	if SaveManager._get_fullscreen_window_mode_update(windowed, true) != fullscreen:
		failures.append("fullscreen setting should enter fullscreen when enabled")
	if SaveManager._get_fullscreen_window_mode_update(fullscreen, true) != no_change:
		failures.append("fullscreen setting should not reapply fullscreen mode")


static func _validate_default_settings(failures: Array[String]) -> void:
	var defaults: Dictionary = SaveManager.DEFAULT_SETTINGS
	for key in ["master_volume", "music_volume", "sfx_volume", "ui_volume"]:
		if absf(float(defaults.get(key, -1.0)) - 0.5) > 0.001:
			failures.append("default settings should start %s at 50%% for distribution builds" % key)
	if str(defaults.get("control_scheme", "")) != "screen":
		failures.append("default settings should start with screen-relative controls")
	if str(defaults.get("gamepad_confirm_button", "")) != "auto":
		failures.append("default settings should auto-detect gamepad confirm layout")
	if defaults.get("gamepad_confirm_button_user_set", true) != false:
		failures.append("default settings should treat gamepad confirm as not manually overridden")
	if InputSettingsHelper.resolve_gamepad_confirm_position("auto", ["Nintendo Switch Pro Controller"]) != "right":
		failures.append("gamepad confirm auto should use right confirm for Nintendo-style pads")
	if InputSettingsHelper.resolve_gamepad_confirm_position("auto", ["Xbox Wireless Controller"]) != "bottom":
		failures.append("gamepad confirm auto should use bottom confirm for Xbox-style pads")
	if InputSettingsHelper.resolve_gamepad_confirm_position("right", ["Xbox Wireless Controller"]) != "right":
		failures.append("gamepad confirm manual right should override auto detection")
	if InputSettingsHelper.resolve_gamepad_confirm_position("bottom", ["Nintendo Switch Pro Controller"]) != "bottom":
		failures.append("gamepad confirm manual bottom should override auto detection")


static func _capture_save_manager_state() -> Dictionary:
	return {
		"gold": SaveManager.gold,
		"meta_upgrades": SaveManager.meta_upgrades.duplicate(true),
		"items": SaveManager.get_items(),
		"settings": _capture_settings_snapshot(),
	}


static func _capture_settings_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for key in ["master_volume", "music_volume", "sfx_volume", "ui_volume", "performance_preset", "fullscreen", "screen_edge_fx_enabled", "screen_edge_fx_strength", "sail_control_mode", "control_scheme", "gamepad_confirm_button", "gamepad_confirm_button_user_set"]:
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
