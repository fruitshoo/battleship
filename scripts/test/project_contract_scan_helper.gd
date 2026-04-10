extends RefCounted
class_name ProjectContractScanHelper


static func scan_resource_roots(roots: Array[String], suffix: String, failures: Array[String]) -> int:
	var paths: Array[String] = []
	for root in roots:
		_collect_paths(root, suffix, paths, failures)
	paths.sort()

	var loaded_count := 0
	for path in paths:
		var resource = load(path)
		if resource == null:
			failures.append("load failed: %s" % path)
			continue
		if suffix == ".gd":
			if not (resource is Script):
				failures.append("script load returned %s: %s" % [resource.get_class(), path])
				continue
		else:
			if not (resource is PackedScene):
				failures.append("scene load returned %s: %s" % [resource.get_class(), path])
				continue
		loaded_count += 1

	return loaded_count


static func scan_legacy_godot3_patterns(roots: Array[String], failures: Array[String]) -> void:
	var legacy_patterns := [
		{"pattern": "yield(", "label": "yield()"},
		{"pattern": "funcref(", "label": "funcref()"},
		{"pattern": ".instance(", "label": "PackedScene.instance()"},
		{"pattern": "String(", "label": "String() constructor"},
		{"pattern": "bool(", "label": "bool() constructor"},
	]

	var paths: Array[String] = []
	for root in roots:
		_collect_paths(root, ".gd", paths, failures)
	paths.sort()

	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			continue
		for legacy in legacy_patterns:
			var pattern: String = legacy["pattern"]
			var label: String = legacy["label"]
			var line_no := 1
			for line in source.split("\n", false):
				if line.find(pattern) != -1:
					failures.append("%s found in %s:%d" % [label, path, line_no])
				line_no += 1


static func _collect_paths(root_path: String, suffix: String, out: Array[String], failures: Array[String]) -> void:
	var dir := DirAccess.open(root_path)
	if dir == null:
		failures.append("unable to open: %s" % root_path)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(".") or entry.ends_with(".uid"):
			entry = dir.get_next()
			continue
		var full_path := "%s/%s" % [root_path, entry]
		if dir.current_is_dir():
			_collect_paths(full_path, suffix, out, failures)
		elif entry.ends_with(suffix):
			out.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
