extends RefCounted
class_name PhysicsFrameProfiler

static var enabled: bool = false
static var _current_frame: int = -1
static var _current_samples: Dictionary = {}
static var _current_counts: Dictionary = {}
static var _last_frame: int = -1
static var _last_samples: Dictionary = {}
static var _last_counts: Dictionary = {}


static func set_enabled(value: bool) -> void:
	enabled = value and OS.is_debug_build()
	if enabled:
		_ensure_frame()


static func begin() -> int:
	if not enabled:
		return 0
	_ensure_frame()
	return Time.get_ticks_usec()


static func end(label: String, start_usec: int) -> void:
	if not enabled or start_usec <= 0:
		return
	_ensure_frame()
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	_current_samples[label] = int(_current_samples.get(label, 0)) + elapsed_usec
	_current_counts[label] = int(_current_counts.get(label, 0)) + 1


static func build_summary_lines(max_entries: int = 6) -> Array[String]:
	if not enabled:
		return []
	var samples := _current_samples
	var counts := _current_counts
	if samples.is_empty() and not _last_samples.is_empty():
		samples = _last_samples
		counts = _last_counts
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


static func _sort_entry_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("usec", 0)) > int(b.get("usec", 0))


static func _ensure_frame() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _current_frame:
		return
	if _current_frame >= 0 and not _current_samples.is_empty():
		_last_frame = _current_frame
		_last_samples = _current_samples.duplicate()
		_last_counts = _current_counts.duplicate()
	_current_frame = frame
	_current_samples = {}
	_current_counts = {}
