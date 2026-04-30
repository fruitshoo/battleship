extends Node

signal locale_changed(locale: String)

const DEFAULT_LOCALE := "ko"
const SUPPORTED_LOCALES: Array[String] = ["ko", "en"]
const LOCALE_FILES := {
	"ko": "res://data/localization/ko.json",
	"en": "res://data/localization/en.json",
}

var current_locale: String = DEFAULT_LOCALE

var _tables: Dictionary = {}

func _ready() -> void:
	_load_tables()
	var saved_locale := str(SaveManager.get_setting("locale", DEFAULT_LOCALE)).strip_edges()
	set_locale(saved_locale, false)


func set_locale(locale: String, persist: bool = true) -> void:
	var normalized := _normalize_locale(locale)
	if normalized == current_locale:
		return
	current_locale = normalized
	TranslationServer.set_locale(current_locale)
	if persist:
		SaveManager.set_setting("locale", current_locale)
	locale_changed.emit(current_locale)


func get_current_locale() -> String:
	return current_locale


func get_supported_locales() -> Array[String]:
	return SUPPORTED_LOCALES.duplicate()


func get_locale_label(locale: String) -> String:
	var normalized := _normalize_locale(locale)
	return t("locale.%s" % normalized, normalized)


func t(key: String, fallback: String = "", values: Dictionary = {}) -> String:
	var normalized_key := key.strip_edges()
	if normalized_key.is_empty():
		return _format_text(fallback, values)
	var text := _lookup(current_locale, normalized_key)
	if text.is_empty() and current_locale != DEFAULT_LOCALE:
		text = _lookup(DEFAULT_LOCALE, normalized_key)
	if text.is_empty():
		text = fallback
	return _format_text(text, values)


func data_text(data: Dictionary, id: String, prefix: String, field: String, fallback: String = "") -> String:
	var field_fallback := fallback
	if field_fallback.is_empty():
		field_fallback = str(data.get(field, id if field == "name" else ""))
	var explicit_key := str(data.get("%s_key" % field, "")).strip_edges()
	var key := explicit_key if not explicit_key.is_empty() else "%s.%s.%s" % [prefix, id, field]
	return t(key, field_fallback)


func _load_tables() -> void:
	_tables.clear()
	for locale in SUPPORTED_LOCALES:
		_tables[locale] = _load_table(locale)


func _load_table(locale: String) -> Dictionary:
	var path := str(LOCALE_FILES.get(locale, ""))
	if path.is_empty():
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LocaleManager: translation file not found: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("LocaleManager: invalid translation table: %s" % path)
	return {}


func _lookup(locale: String, key: String) -> String:
	var table: Dictionary = _tables.get(locale, {})
	if not table.has(key):
		return ""
	return str(table[key])


func _format_text(text: String, values: Dictionary) -> String:
	var formatted := text
	for key in values.keys():
		formatted = formatted.replace("{%s}" % str(key), str(values[key]))
	return formatted


func _normalize_locale(locale: String) -> String:
	var normalized := locale.strip_edges().to_lower()
	if normalized.contains("_"):
		normalized = normalized.split("_")[0]
	if normalized.contains("-"):
		normalized = normalized.split("-")[0]
	if SUPPORTED_LOCALES.has(normalized):
		return normalized
	return DEFAULT_LOCALE
