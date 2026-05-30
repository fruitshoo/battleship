extends RefCounted
class_name PhysicsFrameProfiler

static var enabled: bool = false
static var _current_frame: int = -1
static var _current_samples: Dictionary = {}
static var _current_exclusive_samples: Dictionary = {}
static var _current_counts: Dictionary = {}
static var _last_frame: int = -1
static var _last_samples: Dictionary = {}
static var _last_exclusive_samples: Dictionary = {}
static var _last_counts: Dictionary = {}
static var _active_stack: Array[int] = []
static var _active_child_usec_by_start: Dictionary = {}


static func set_enabled(value: bool) -> void:
	enabled = value and OS.is_debug_build()
	if enabled:
		_ensure_frame()


static func begin() -> int:
	if not enabled:
		return 0
	_ensure_frame()
	var start_usec := Time.get_ticks_usec()
	_active_stack.append(start_usec)
	_active_child_usec_by_start[start_usec] = 0
	return start_usec


static func end(label: String, start_usec: int) -> void:
	if not enabled or start_usec <= 0:
		return
	_ensure_frame()
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var child_usec := int(_active_child_usec_by_start.get(start_usec, 0))
	var exclusive_usec := maxi(0, elapsed_usec - child_usec)
	_current_samples[label] = int(_current_samples.get(label, 0)) + elapsed_usec
	_current_exclusive_samples[label] = int(_current_exclusive_samples.get(label, 0)) + exclusive_usec
	_current_counts[label] = int(_current_counts.get(label, 0)) + 1
	_pop_active_sample(start_usec, elapsed_usec)


static func build_summary_lines(max_entries: int = 6) -> Array[String]:
	if not enabled:
		return []
	var data := _get_display_data()
	var samples: Dictionary = data.get("samples", {})
	var counts: Dictionary = data.get("counts", {})
	if samples.is_empty():
		return ["Physics buckets: waiting"]

	var entries: Array[Dictionary] = []
	var total_usec := 0
	for key in samples.keys():
		var elapsed := int(samples[key])
		total_usec += elapsed
		entries.append({
			"label": str(key),
			"usec": elapsed,
			"count": int(counts.get(key, 0)),
		})
	entries.sort_custom(_sort_entry_desc)

	var lines: Array[String] = ["Profile buckets %.1fms" % (float(total_usec) / 1000.0)]
	var shown := 0
	for entry in entries:
		if shown >= max_entries:
			break
		lines.append("%s %.1fms x%d" % [
			str(entry["label"]),
			float(entry["usec"]) / 1000.0,
			int(entry["count"]),
		])
		shown += 1
	return lines


static func build_exclusive_summary_lines(max_entries: int = 6) -> Array[String]:
	if not enabled:
		return []
	var data := _get_display_data()
	var samples: Dictionary = data.get("exclusive_samples", {})
	var counts: Dictionary = data.get("counts", {})
	if samples.is_empty():
		return []

	var entries: Array[Dictionary] = []
	var total_usec := 0
	for key in samples.keys():
		var elapsed := int(samples[key])
		total_usec += elapsed
		entries.append({
			"label": str(key),
			"usec": elapsed,
			"count": int(counts.get(key, 0)),
		})
	entries.sort_custom(_sort_entry_desc)

	var lines: Array[String] = ["Exclusive buckets %.1fms" % (float(total_usec) / 1000.0)]
	var shown := 0
	for entry in entries:
		if shown >= max_entries:
			break
		lines.append("%s %.1fms x%d" % [
			str(entry["label"]),
			float(entry["usec"]) / 1000.0,
			int(entry["count"]),
		])
		shown += 1
	return lines


static func build_filtered_summary_lines(prefixes: Array[String], title: String, max_entries: int = 6) -> Array[String]:
	if not enabled:
		return []
	var data := _get_display_data()
	var samples: Dictionary = data.get("samples", {})
	var counts: Dictionary = data.get("counts", {})
	if samples.is_empty():
		return []

	var entries: Array[Dictionary] = []
	var total_usec := 0
	for key in samples.keys():
		var label := str(key)
		if not _label_has_any_prefix(label, prefixes):
			continue
		var elapsed := int(samples[key])
		total_usec += elapsed
		entries.append({
			"label": label,
			"usec": elapsed,
			"count": int(counts.get(key, 0)),
		})
	if entries.is_empty():
		return []

	entries.sort_custom(_sort_entry_desc)
	var lines: Array[String] = ["%s %.1fms" % [title, float(total_usec) / 1000.0]]
	var shown := 0
	for entry in entries:
		if shown >= max_entries:
			break
		lines.append("%s %.1fms x%d" % [
			str(entry["label"]),
			float(entry["usec"]) / 1000.0,
			int(entry["count"]),
		])
		shown += 1
	return lines


static func get_summary_total_msec() -> float:
	if not enabled:
		return 0.0
	var data := _get_display_data()
	var samples: Dictionary = data.get("samples", {})
	if samples.is_empty():
		return 0.0
	var total_usec := 0
	for key in samples.keys():
		total_usec += int(samples[key])
	return float(total_usec) / 1000.0


static func get_exclusive_summary_total_msec() -> float:
	if not enabled:
		return 0.0
	var data := _get_display_data()
	var samples: Dictionary = data.get("exclusive_samples", {})
	if samples.is_empty():
		return 0.0
	var total_usec := 0
	for key in samples.keys():
		total_usec += int(samples[key])
	return float(total_usec) / 1000.0


static func _get_display_data() -> Dictionary:
	var samples := _current_samples
	var exclusive_samples := _current_exclusive_samples
	var counts := _current_counts
	if samples.is_empty() and not _last_samples.is_empty():
		samples = _last_samples
		exclusive_samples = _last_exclusive_samples
		counts = _last_counts
	return {
		"samples": samples,
		"exclusive_samples": exclusive_samples,
		"counts": counts,
	}


static func _label_has_any_prefix(label: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if label.begins_with(prefix):
			return true
	return false


static func _sort_entry_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("usec", 0)) > int(b.get("usec", 0))


static func _pop_active_sample(start_usec: int, elapsed_usec: int) -> void:
	var found_index := -1
	for i in range(_active_stack.size() - 1, -1, -1):
		if int(_active_stack[i]) == start_usec:
			found_index = i
			break
	if found_index >= 0:
		_active_stack.remove_at(found_index)
	_active_child_usec_by_start.erase(start_usec)
	if not _active_stack.is_empty():
		var parent_start := int(_active_stack[_active_stack.size() - 1])
		_active_child_usec_by_start[parent_start] = int(_active_child_usec_by_start.get(parent_start, 0)) + elapsed_usec


static func _ensure_frame() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _current_frame:
		return
	if _current_frame >= 0 and not _current_samples.is_empty():
		_last_frame = _current_frame
		_last_samples = _current_samples.duplicate()
		_last_exclusive_samples = _current_exclusive_samples.duplicate()
		_last_counts = _current_counts.duplicate()
	_current_frame = frame
	_current_samples = {}
	_current_exclusive_samples = {}
	_current_counts = {}
	_active_stack = []
	_active_child_usec_by_start = {}
