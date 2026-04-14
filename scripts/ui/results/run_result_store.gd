class_name RunResultStore
extends RefCounted

static var latest_result: Dictionary = {}


static func set_latest_result(result: Dictionary) -> void:
	latest_result = result.duplicate(true)


static func get_latest_result() -> Dictionary:
	return latest_result.duplicate(true)


static func clear() -> void:
	latest_result.clear()
