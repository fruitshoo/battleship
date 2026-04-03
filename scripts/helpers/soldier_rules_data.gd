extends RefCounted
class_name SoldierRulesData

const DATA_PATH := "res://data/soldier_rules.json"

static var _cached_root: Dictionary = {}
static var _loaded: bool = false


static func get_root() -> Dictionary:
	if _loaded:
		return _cached_root

	_loaded = true
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("SoldierRulesData: failed to open %s" % DATA_PATH)
		return _cached_root

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_cached_root = parsed
	else:
		push_warning("SoldierRulesData: invalid JSON root in %s" % DATA_PATH)

	return _cached_root


static func get_section(section_name: String) -> Dictionary:
	var root: Dictionary = get_root()
	var value: Variant = root.get(section_name, {})
	return value if value is Dictionary else {}
