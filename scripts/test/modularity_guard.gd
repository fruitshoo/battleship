extends Node

const REGISTRY_PATH := "res://scripts/test/module_boundaries.json"
const SCRIPTS_ROOT := "res://scripts"
const HELPER_SUFFIX := "_helper.gd"
const SCENE_CONTRACT_ALLOWED_OWNERS := {
	"res://scripts/entities/ships/base_ship.gd": true,
	"res://scripts/helpers/node_contract_helper.gd": true,
	"res://scripts/props/mast.gd": true,
}
const SCENE_CONTRACT_TEST_OPT_IN_MARKER := "# @scene_contract_encapsulated"
const MATRIX_EXECUTION_MODES := {
	"manual_preview": true,
	"standalone_wrapper": true,
	"suite_wrapper": true,
}
const SCENE_CONTRACT_FORBIDDEN_SIGNATURES := [
	"get_node_or_null(\"Soldiers\")",
	"get_node(\"Soldiers\")",
	"has_node(\"Soldiers\")",
	"$Soldiers",
	"name == \"Soldiers\"",
	"name = \"Soldiers\"",
	"get_node_or_null(\"ProximityArea\")",
	"get_node(\"ProximityArea\")",
	"has_node(\"ProximityArea\")",
	"name == \"ProximityArea\"",
	"name = \"ProximityArea\"",
	"get_node_or_null(\"HitArea\")",
	"get_node(\"HitArea\")",
	"has_node(\"HitArea\")",
	"name == \"HitArea\"",
	"name = \"HitArea\"",
	"get_node_or_null(\"Cannons\")",
	"get_node(\"Cannons\")",
	"has_node(\"Cannons\")",
	"find_child(\"Cannons\"",
	"name == \"Cannons\"",
	"name = \"Cannons\"",
	"get_node_or_null(\"SpearRail\")",
	"get_node(\"SpearRail\")",
	"has_node(\"SpearRail\")",
	"name == \"SpearRail\"",
	"name = \"SpearRail\"",
	"get_node_or_null(\"HullDefenseVisuals\")",
	"get_node(\"HullDefenseVisuals\")",
	"has_node(\"HullDefenseVisuals\")",
	"name == \"HullDefenseVisuals\"",
	"name = \"HullDefenseVisuals\"",
	"get_node_or_null(\"SingijeonLauncher\")",
	"get_node(\"SingijeonLauncher\")",
	"has_node(\"SingijeonLauncher\")",
	"name == \"SingijeonLauncher\"",
	"name = \"SingijeonLauncher\"",
	"get_node_or_null(\"JanggunLauncher\")",
	"get_node(\"JanggunLauncher\")",
	"has_node(\"JanggunLauncher\")",
	"name == \"JanggunLauncher\"",
	"name = \"JanggunLauncher\"",
	"get_node_or_null(\"HandPivot\")",
	"get_node(\"HandPivot\")",
	"has_node(\"HandPivot\")",
	"name == \"HandPivot\"",
	"name = \"HandPivot\"",
	"get_node_or_null(\"CollisionShape3D\")",
	"get_node(\"CollisionShape3D\")",
	"has_node(\"CollisionShape3D\")",
	"name == \"CollisionShape3D\"",
	"name = \"CollisionShape3D\"",
	"get_node_or_null(\"Yard\")",
	"get_node(\"Yard\")",
	"has_node(\"Yard\")",
	"name == \"Yard\"",
	"name = \"Yard\"",
	"get_node_or_null(\"Streamers\")",
	"get_node(\"Streamers\")",
	"has_node(\"Streamers\")",
	"find_child(\"Streamers\"",
	"name == \"Streamers\"",
	"name = \"Streamers\"",
	"get_node_or_null(\"SailVisual/Flag\")",
	"get_node(\"SailVisual/Flag\")",
	"has_node(\"SailVisual/Flag\")",
	"$SailVisual/Flag",
]


func _ready() -> void:
	call_deferred("_run_guard")


func _run_guard() -> void:
	var violations: Array[String] = []
	var debt: Array[String] = []
	var watchlist: Array[String] = []
	var notices: Array[String] = []
	var registry := _load_registry(violations)
	if registry.is_empty():
		_finish(violations, debt, watchlist, notices)
		return

	var script_paths: Array[String] = []
	_collect_gd_paths(SCRIPTS_ROOT, script_paths)
	var helper_paths := _collect_helper_paths()
	var registered_helpers := _get_registered_helper_paths(registry)

	_check_runtime_scenario_matrix(registry, violations)
	_check_helper_registry_coverage(helper_paths, registered_helpers, registry, violations)
	_check_watched_responsibilities(registry, registered_helpers, violations)
	_check_exception_debt(registry, violations)
	_check_helper_shape(helper_paths, registry, violations, debt)
	_check_helper_public_surface(helper_paths, registry, violations, notices)
	_check_duplicate_static_functions(helper_paths, registry, violations, debt)
	_check_helper_dependency_boundaries(helper_paths, registered_helpers, registry, violations, watchlist, notices)
	_check_coordinate_pooling_hazards(script_paths, registry, violations, watchlist, notices)
	_check_scene_contract_encapsulation(script_paths, violations)

	print("[ModularityGuard] registered_helpers=%d actual_helpers=%d debt=%d watchlist=%d notices=%d violations=%d" % [
		registered_helpers.size(),
		helper_paths.size(),
		debt.size(),
		watchlist.size(),
		notices.size(),
		violations.size()
	])
	_finish(violations, debt, watchlist, notices, int(registry.get("max_known_warning_lines", 12)))


func _load_registry(violations: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(REGISTRY_PATH):
		violations.append("Missing module boundary registry: %s" % REGISTRY_PATH)
		return {}

	var text := FileAccess.get_file_as_string(REGISTRY_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		violations.append("Module boundary registry is not valid JSON object: %s" % REGISTRY_PATH)
		return {}
	return parsed


func _load_json_file(path: String, label: String, violations: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		violations.append("%s is missing: %s" % [label, path])
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		violations.append("%s is not a valid JSON object: %s" % [label, path])
		return {}
	return parsed


func _collect_helper_paths() -> Array[String]:
	var gd_paths: Array[String] = []
	_collect_gd_paths(SCRIPTS_ROOT, gd_paths)

	var helper_paths: Array[String] = []
	for path in gd_paths:
		if path.ends_with(HELPER_SUFFIX):
			helper_paths.append(path)
	helper_paths.sort()
	return helper_paths


func _collect_gd_paths(dir_path: String, out_paths: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			_collect_gd_paths(path, out_paths)
		elif file_name.ends_with(".gd"):
			out_paths.append(path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _get_registered_helper_paths(registry: Dictionary) -> Array[String]:
	var helpers: Dictionary = registry.get("helpers", {})
	var paths: Array[String] = []
	for path in helpers.keys():
		paths.append(str(path))
	paths.sort()
	return paths


func _check_helper_registry_coverage(helper_paths: Array[String], registered_helpers: Array[String], registry: Dictionary, violations: Array[String]) -> void:
	var helpers: Dictionary = registry.get("helpers", {})

	for path in helper_paths:
		if not helpers.has(path):
			violations.append("Unregistered helper: %s. Add a responsibility entry or extend an existing helper instead." % path)

	for path in registered_helpers:
		if not FileAccess.file_exists(path):
			violations.append("Registered helper path is missing: %s" % path)
			continue
		var entry: Dictionary = helpers.get(path, {})
		if str(entry.get("layer", "")).strip_edges().is_empty():
			violations.append("Registered helper has no layer: %s" % path)
		if str(entry.get("responsibility", "")).strip_edges().is_empty():
			violations.append("Registered helper has no responsibility: %s" % path)


func _check_runtime_scenario_matrix(registry: Dictionary, violations: Array[String]) -> void:
	var matrix_path := str(registry.get("scenario_matrix_path", "res://scenes/test/runtime_scenario_matrix.json"))
	var matrix := _load_json_file(matrix_path, "Runtime scenario matrix", violations)
	if matrix.is_empty():
		return

	var shared_refs_value = matrix.get("shared_references", [])
	if typeof(shared_refs_value) != TYPE_ARRAY:
		violations.append("Runtime scenario matrix shared_references must be an array")
	else:
		_check_matrix_references(shared_refs_value as Array, "shared_references", violations)

	var all_harness_ids: Dictionary = {}
	for array_name in ["runtime_harnesses", "architecture_harnesses", "static_authoring_scenes"]:
		var entries_value = matrix.get(array_name, [])
		if typeof(entries_value) != TYPE_ARRAY:
			violations.append("Runtime scenario matrix %s must be an array" % array_name)
			continue
		_check_matrix_harness_entries(entries_value as Array, array_name, all_harness_ids, violations)


func _check_matrix_references(entries: Array, label: String, violations: Array[String]) -> void:
	var ids: Dictionary = {}
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			violations.append("Runtime scenario matrix %s entry must be an object" % label)
			continue
		var entry: Dictionary = raw_entry
		var entry_id := str(entry.get("id", ""))
		_check_snake_id(entry_id, "Runtime scenario matrix %s id" % label, violations)
		if ids.has(entry_id):
			violations.append("Duplicate runtime scenario matrix %s id: %s" % [label, entry_id])
		ids[entry_id] = true
		_check_optional_matrix_path(entry, "scene", "%s %s" % [label, entry_id], violations)
		_check_optional_matrix_path(entry, "script", "%s %s" % [label, entry_id], violations)
		_check_optional_matrix_path(entry, "registry", "%s %s" % [label, entry_id], violations)
		_check_optional_matrix_path(entry, "document", "%s %s" % [label, entry_id], violations)


func _check_matrix_harness_entries(entries: Array, label: String, all_harness_ids: Dictionary, violations: Array[String]) -> void:
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			violations.append("Runtime scenario matrix %s entry must be an object" % label)
			continue
		var entry: Dictionary = raw_entry
		var harness_id := str(entry.get("id", ""))
		_check_snake_id(harness_id, "Runtime scenario matrix %s harness id" % label, violations)
		if all_harness_ids.has(harness_id):
			violations.append("Duplicate runtime scenario matrix harness id: %s" % harness_id)
		all_harness_ids[harness_id] = true
		_check_optional_matrix_path(entry, "scene", "%s %s" % [label, harness_id], violations)
		_check_optional_matrix_path(entry, "script", "%s %s" % [label, harness_id], violations)
		_check_optional_matrix_path(entry, "registry", "%s %s" % [label, harness_id], violations)
		_check_optional_matrix_path(entry, "document", "%s %s" % [label, harness_id], violations)
		_check_optional_matrix_path(entry, "wrapper", "%s %s" % [label, harness_id], violations)
		_check_matrix_execution_metadata(entry, label, harness_id, violations)

		var scenarios_value = entry.get("scenarios", [])
		if typeof(scenarios_value) != TYPE_ARRAY:
			violations.append("Runtime scenario matrix %s %s scenarios must be an array" % [label, harness_id])
			continue
		var scenario_ids: Dictionary = {}
		for raw_scenario in scenarios_value as Array:
			if typeof(raw_scenario) != TYPE_DICTIONARY:
				violations.append("Runtime scenario matrix %s %s scenario must be an object" % [label, harness_id])
				continue
			var scenario: Dictionary = raw_scenario
			var scenario_id := str(scenario.get("id", ""))
			_check_snake_id(scenario_id, "Runtime scenario matrix %s %s scenario id" % [label, harness_id], violations)
			if scenario_ids.has(scenario_id):
				violations.append("Duplicate scenario id in %s %s: %s" % [label, harness_id, scenario_id])
			scenario_ids[scenario_id] = true
			if str(scenario.get("coverage", "")).strip_edges().is_empty():
				violations.append("Runtime scenario matrix %s %s scenario has no coverage: %s" % [label, harness_id, scenario_id])


func _check_matrix_execution_metadata(entry: Dictionary, label: String, harness_id: String, violations: Array[String]) -> void:
	var execution := str(entry.get("execution", "")).strip_edges()
	if execution.is_empty():
		violations.append("Runtime scenario matrix %s %s has no execution metadata" % [label, harness_id])
		return
	if not MATRIX_EXECUTION_MODES.has(execution):
		violations.append("Runtime scenario matrix %s %s execution is invalid: %s" % [label, harness_id, execution])
		return
	if execution in ["standalone_wrapper", "suite_wrapper"] and not entry.has("wrapper"):
		violations.append("Runtime scenario matrix %s %s execution %s requires wrapper path" % [label, harness_id, execution])


func _check_optional_matrix_path(entry: Dictionary, field_name: String, label: String, violations: Array[String]) -> void:
	if not entry.has(field_name):
		return
	var path := str(entry.get(field_name, ""))
	if path.is_empty():
		violations.append("Runtime scenario matrix %s has empty %s" % [label, field_name])
	elif not path.begins_with("res://"):
		violations.append("Runtime scenario matrix %s %s must use res:// path: %s" % [label, field_name, path])
	elif not FileAccess.file_exists(path):
		violations.append("Runtime scenario matrix %s %s path is missing: %s" % [label, field_name, path])


func _check_snake_id(id_value: String, label: String, violations: Array[String]) -> void:
	if id_value.is_empty():
		violations.append("%s is empty" % label)
		return
	for index in range(id_value.length()):
		var code := id_value.unicode_at(index)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_underscore := code == 95
		if not (is_lower or is_digit or is_underscore):
			violations.append("%s must be snake_case: %s" % [label, id_value])
			return
	if id_value.begins_with("_") or id_value.ends_with("_") or id_value.contains("__"):
		violations.append("%s must be stable snake_case without edge/double underscores: %s" % [label, id_value])


func _check_watched_responsibilities(registry: Dictionary, registered_helpers: Array[String], violations: Array[String]) -> void:
	var watched: Array = registry.get("watched_responsibilities", [])
	for item in watched:
		if typeof(item) != TYPE_DICTIONARY:
			violations.append("watched_responsibilities entry must be an object")
			continue
		var owner := str(item.get("owner", ""))
		var invariant := str(item.get("invariant", "")).strip_edges()
		if owner.is_empty():
			violations.append("watched_responsibilities entry has no owner")
		elif not FileAccess.file_exists(owner):
			violations.append("Watched responsibility owner path is missing: %s" % owner)
		elif owner.ends_with(HELPER_SUFFIX) and not registered_helpers.has(owner):
			violations.append("Watched helper owner is not registered: %s" % owner)
		if invariant.is_empty():
			violations.append("watched_responsibilities entry has no invariant for owner: %s" % owner)


func _check_exception_debt(registry: Dictionary, violations: Array[String]) -> void:
	var expected_keys := _collect_exception_debt_keys(registry)
	var debt: Dictionary = registry.get("exception_debt", {})
	for key in expected_keys.keys():
		if not debt.has(key):
			violations.append("Exception lacks debt metadata: %s" % key)
			continue
		var entry_value = debt.get(key)
		if typeof(entry_value) != TYPE_DICTIONARY:
			violations.append("Exception debt metadata must be an object: %s" % key)
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("reason", "")).strip_edges().is_empty():
			violations.append("Exception debt metadata has no reason: %s" % key)
		if str(entry.get("priority", "")).strip_edges().is_empty():
			violations.append("Exception debt metadata has no priority: %s" % key)
		if str(entry.get("recommended_action", "")).strip_edges().is_empty():
			violations.append("Exception debt metadata has no recommended_action: %s" % key)

	for raw_key in debt.keys():
		var key := str(raw_key)
		if not expected_keys.has(key):
			violations.append("Stale exception debt metadata without matching exception: %s" % key)


func _collect_exception_debt_keys(registry: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	for field_name in ["large_helper_exceptions", "thin_helper_exceptions", "class_name_exceptions"]:
		var category: String = str(field_name).replace("_exceptions", "")
		var entries: Dictionary = registry.get(field_name, {})
		for path in entries.keys():
			keys["%s|%s" % [category, str(path)]] = true

	var duplicate_entries: Array = registry.get("allowed_duplicate_static_functions", [])
	for raw_entry in duplicate_entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var function_name := str(entry.get("name", ""))
		var paths: Array = entry.get("paths", [])
		paths.sort()
		keys["duplicate_static_function|%s" % _duplicate_key(function_name, paths)] = true
	return keys


func _check_helper_shape(helper_paths: Array[String], registry: Dictionary, violations: Array[String], debt: Array[String]) -> void:
	var max_helper_lines := int(registry.get("max_helper_lines", 360))
	var large_exceptions: Dictionary = registry.get("large_helper_exceptions", {})
	var thin_exceptions: Dictionary = registry.get("thin_helper_exceptions", {})
	var class_name_exceptions: Dictionary = registry.get("class_name_exceptions", {})

	for path in helper_paths:
		var source := FileAccess.get_file_as_string(path)
		var line_count := _count_lines(source)
		var static_functions := _extract_static_function_names(source)
		var has_class_name := _has_class_name(source)

		if line_count > max_helper_lines and not large_exceptions.has(path):
			violations.append("Large helper without explicit exception: %s has %d lines, limit %d" % [path, line_count, max_helper_lines])
		elif line_count > max_helper_lines:
			debt.append("Known large helper: %s has %d lines. %s" % [path, line_count, str(large_exceptions.get(path, ""))])

		if static_functions.size() <= 2 and not thin_exceptions.has(path):
			violations.append("Thin helper without explicit exception: %s has %d static funcs. Prefer extending an existing owner." % [path, static_functions.size()])
		elif static_functions.size() <= 2:
			debt.append("Known thin helper: %s has %d static funcs. %s" % [path, static_functions.size(), str(thin_exceptions.get(path, ""))])

		if not has_class_name and not class_name_exceptions.has(path):
			violations.append("Helper without class_name exception: %s. New helpers should expose an explicit class_name." % path)
		elif not has_class_name:
			debt.append("Known helper without class_name: %s. %s" % [path, str(class_name_exceptions.get(path, ""))])


func _check_helper_public_surface(helper_paths: Array[String], registry: Dictionary, violations: Array[String], notices: Array[String]) -> void:
	var baselines: Dictionary = registry.get("helper_static_function_baselines", {})
	for path in helper_paths:
		var source := FileAccess.get_file_as_string(path)
		var current_functions := _extract_static_function_names(source)
		if not baselines.has(path):
			violations.append("Helper has no public surface baseline: %s" % path)
			continue

		var baseline_value = baselines.get(path)
		if typeof(baseline_value) != TYPE_DICTIONARY:
			violations.append("Helper public surface baseline must be an object: %s" % path)
			continue
		var baseline: Dictionary = baseline_value
		var baseline_count := int(baseline.get("count", -1))
		var baseline_functions_value = baseline.get("functions", [])
		if typeof(baseline_functions_value) != TYPE_ARRAY:
			violations.append("Helper public surface baseline functions must be an array: %s" % path)
			continue
		var baseline_functions: Array = baseline_functions_value
		if baseline_count < 0:
			violations.append("Helper public surface baseline has invalid count: %s" % path)
		if current_functions.size() > baseline_count:
			violations.append("Helper public surface grew: %s baseline=%d current=%d. Extend an existing owner deliberately and update baseline with rationale." % [path, baseline_count, current_functions.size()])
		elif current_functions.size() < baseline_count:
			notices.append("Helper public surface shrank: %s baseline=%d current=%d. Update baseline after confirming cleanup." % [path, baseline_count, current_functions.size()])

		for function_name in current_functions:
			if not baseline_functions.has(function_name):
				violations.append("Helper added static function outside baseline: %s::%s" % [path, function_name])
		for raw_function_name in baseline_functions:
			var function_name := str(raw_function_name)
			if not current_functions.has(function_name):
				notices.append("Helper removed static function from baseline: %s::%s. Update baseline after confirming cleanup." % [path, function_name])

	for raw_path in baselines.keys():
		var path := str(raw_path)
		if not helper_paths.has(path):
			violations.append("Stale helper public surface baseline without helper: %s" % path)


func _check_duplicate_static_functions(helper_paths: Array[String], registry: Dictionary, violations: Array[String], debt: Array[String]) -> void:
	var functions_to_paths: Dictionary = {}
	for path in helper_paths:
		var source := FileAccess.get_file_as_string(path)
		for function_name in _extract_static_function_names(source):
			if not functions_to_paths.has(function_name):
				functions_to_paths[function_name] = []
			var paths: Array = functions_to_paths[function_name]
			if not paths.has(path):
				paths.append(path)

	var allowed_duplicates := _build_allowed_duplicate_map(registry)
	for function_name in functions_to_paths.keys():
		var paths: Array = functions_to_paths[function_name]
		if paths.size() <= 1:
			continue
		paths.sort()
		var key := _duplicate_key(str(function_name), paths)
		if allowed_duplicates.has(key):
			debt.append("Known duplicate static func: %s in %s. %s" % [
				function_name,
				_join_paths(paths),
				str(allowed_duplicates.get(key, ""))
			])
		else:
			violations.append("Duplicate static func without boundary exception: %s in %s" % [
				function_name,
				_join_paths(paths)
			])


func _check_helper_dependency_boundaries(helper_paths: Array[String], registered_helpers: Array[String], registry: Dictionary, violations: Array[String], watchlist: Array[String], notices: Array[String]) -> void:
	var baselines: Dictionary = registry.get("helper_dependency_baselines", {})
	var seen_edges: Dictionary = {}

	for path in helper_paths:
		var source := FileAccess.get_file_as_string(path)
		for preload_path in _extract_preload_paths(source):
			if not preload_path.ends_with(HELPER_SUFFIX):
				continue
			if not registered_helpers.has(preload_path):
				violations.append("Helper preloads unregistered helper: %s -> %s" % [path, preload_path])
				continue
			var key := _dependency_key(path, preload_path)
			seen_edges[key] = true
			if not baselines.has(key):
				violations.append("New helper dependency without boundary baseline: %s -> %s" % [path, preload_path])
			else:
				watchlist.append("Known helper dependency: %s -> %s" % [path, preload_path])

	for raw_key in baselines.keys():
		var key := str(raw_key)
		var entry_value = baselines.get(key)
		if typeof(entry_value) != TYPE_DICTIONARY:
			violations.append("Helper dependency baseline must be an object: %s" % key)
			continue
		var entry: Dictionary = entry_value
		var from_path := str(entry.get("from", ""))
		var to_path := str(entry.get("to", ""))
		if from_path.is_empty() or to_path.is_empty():
			violations.append("Helper dependency baseline missing from/to: %s" % key)
		if str(entry.get("reason", "")).strip_edges().is_empty():
			violations.append("Helper dependency baseline missing reason: %s" % key)
		if not seen_edges.has(key):
			notices.append("Stale helper dependency baseline not observed: %s" % key)


func _check_coordinate_pooling_hazards(script_paths: Array[String], registry: Dictionary, violations: Array[String], watchlist: Array[String], notices: Array[String]) -> void:
	var baselines: Dictionary = registry.get("hazard_baselines", {})
	var seen_hazards: Dictionary = {}
	var hazards := _scan_coordinate_pooling_hazards(script_paths)
	for hazard in hazards:
		var key := _hazard_key(hazard)
		seen_hazards[key] = true
		if not baselines.has(key):
			violations.append("New coordinate/pooling hazard without baseline: %s" % key)
		else:
			watchlist.append("Known coordinate/pooling hazard: %s" % key)

	for raw_key in baselines.keys():
		var key := str(raw_key)
		var entry_value = baselines.get(key)
		if typeof(entry_value) != TYPE_DICTIONARY:
			violations.append("Hazard baseline must be an object: %s" % key)
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("kind", "")).strip_edges().is_empty():
			violations.append("Hazard baseline missing kind: %s" % key)
		if str(entry.get("path", "")).strip_edges().is_empty():
			violations.append("Hazard baseline missing path: %s" % key)
		if str(entry.get("signature", "")).strip_edges().is_empty():
			violations.append("Hazard baseline missing signature: %s" % key)
		if str(entry.get("recommended_action", "")).strip_edges().is_empty():
			violations.append("Hazard baseline missing recommended_action: %s" % key)
		if not seen_hazards.has(key):
			notices.append("Stale coordinate/pooling hazard baseline not observed: %s" % key)


func _check_scene_contract_encapsulation(script_paths: Array[String], violations: Array[String]) -> void:
	for path in script_paths:
		var text := FileAccess.get_file_as_string(path)
		var is_opted_in_test_contract: bool = path.begins_with("res://scripts/test/") and _has_scene_contract_test_marker(text)
		if path.begins_with("res://scripts/test/") and not is_opted_in_test_contract:
			continue
		if not is_opted_in_test_contract and SCENE_CONTRACT_ALLOWED_OWNERS.has(path):
			continue
		for signature in SCENE_CONTRACT_FORBIDDEN_SIGNATURES:
			if text.contains(signature):
				violations.append("Scene contract access outside owner: %s uses %s. Use owner accessors or contract APIs instead." % [path, signature])


func _has_scene_contract_test_marker(text: String) -> bool:
	for line in text.split("\n"):
		if str(line).strip_edges() == SCENE_CONTRACT_TEST_OPT_IN_MARKER:
			return true
	return false


func _build_allowed_duplicate_map(registry: Dictionary) -> Dictionary:
	var allowed: Dictionary = {}
	var entries: Array = registry.get("allowed_duplicate_static_functions", [])
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var function_name := str(entry.get("name", ""))
		var paths: Array = entry.get("paths", [])
		paths.sort()
		allowed[_duplicate_key(function_name, paths)] = str(entry.get("reason", ""))
	return allowed


func _extract_preload_paths(source: String) -> Array[String]:
	var paths: Array[String] = []
	var marker := "preload(\""
	for line in source.split("\n"):
		var search_from := 0
		while search_from < line.length():
			var start := str(line).find(marker, search_from)
			if start < 0:
				break
			var path_start := start + marker.length()
			var path_end := str(line).find("\"", path_start)
			if path_end < 0:
				break
			var path := str(line).substr(path_start, path_end - path_start)
			if not path.is_empty():
				paths.append(path)
			search_from = path_end + 1
	return paths


func _scan_coordinate_pooling_hazards(script_paths: Array[String]) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	for path in script_paths:
		if path == "res://scripts/test/modularity_guard.gd":
			continue
		var source := FileAccess.get_file_as_string(path)
		var has_deferred_add := source.contains("add_child.call_deferred") or source.contains("call_deferred(\"add_child\"")
		var in_pool_reset := false
		var pool_indent := 0
		for raw_line in source.split("\n"):
			var line := str(raw_line)
			var stripped := line.strip_edges()
			var indent := _line_indent(line)
			if stripped.begins_with("func pool_reset"):
				in_pool_reset = true
				pool_indent = indent
			elif in_pool_reset and not stripped.is_empty() and indent <= pool_indent and not stripped.begins_with("#"):
				in_pool_reset = false

			if line.contains("tween_property") and (line.contains("\"position:x\"") or line.contains("\"position:z\"")):
				hazards.append(_make_hazard("local_position_axis_tween", path, stripped))
			if line.contains("reparent(") and path != "res://scripts/entities/soldiers/soldier_boarding_helper.gd":
				hazards.append(_make_hazard("direct_reparent_outside_soldier_boarding", path, stripped))
			if has_deferred_add and line.contains("set_deferred(\"global_position\""):
				hazards.append(_make_hazard("deferred_global_position_after_deferred_add", path, stripped))
			if in_pool_reset and line.contains("base_y") and line.contains("global_position.y"):
				hazards.append(_make_hazard("pool_reset_reads_global_y", path, stripped))
	return hazards


func _make_hazard(kind: String, path: String, signature: String) -> Dictionary:
	return {
		"kind": kind,
		"path": path,
		"signature": signature,
	}


func _line_indent(line: String) -> int:
	var count := 0
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if character == "\t":
			count += 4
		elif character == " ":
			count += 1
		else:
			break
	return count


func _extract_static_function_names(source: String) -> Array[String]:
	var names: Array[String] = []
	for line in source.split("\n"):
		var stripped := str(line).strip_edges()
		if not stripped.begins_with("static func "):
			continue
		var declaration := stripped.substr("static func ".length())
		var function_name := declaration.get_slice("(", 0).strip_edges()
		if not function_name.is_empty():
			names.append(function_name)
	return names


func _has_class_name(source: String) -> bool:
	for line in source.split("\n"):
		if str(line).strip_edges().begins_with("class_name "):
			return true
	return false


func _count_lines(source: String) -> int:
	if source.is_empty():
		return 0
	return source.split("\n").size()


func _duplicate_key(function_name: String, paths: Array) -> String:
	var sorted_paths := paths.duplicate()
	sorted_paths.sort()
	return "%s|%s" % [function_name, _join_paths(sorted_paths)]


func _dependency_key(from_path: String, to_path: String) -> String:
	return "%s|%s" % [from_path, to_path]


func _hazard_key(hazard: Dictionary) -> String:
	return "%s|%s|%s" % [
		str(hazard.get("kind", "")),
		str(hazard.get("path", "")),
		str(hazard.get("signature", "")),
	]


func _join_paths(paths: Array) -> String:
	var packed := PackedStringArray()
	for path in paths:
		packed.append(str(path))
	return ",".join(packed)


func _finish(violations: Array[String], debt: Array[String], watchlist: Array[String], notices: Array[String], max_known_warning_lines: int = 12) -> void:
	var line_limit: int = maxi(0, max_known_warning_lines)
	_print_nonfatal_bucket("debt", debt, line_limit, "registered architecture debt")
	_print_nonfatal_bucket("watchlist", watchlist, line_limit, "registered dependency and coordinate/pooling watchpoints")
	_print_nonfatal_bucket("notice", notices, line_limit, "cleanup notices")

	if violations.is_empty():
		print("[ModularityGuard] ok")
		get_tree().quit(0)
		return

	for violation in violations:
		push_error("[ModularityGuard] %s" % violation)
	get_tree().quit(1)


func _print_nonfatal_bucket(bucket_name: String, messages: Array[String], line_limit: int, description: String) -> void:
	if messages.is_empty():
		return
	var shown_count: int = mini(line_limit, messages.size())
	for index in range(shown_count):
		print("[ModularityGuard][%s] %s" % [bucket_name, messages[index]])
	if messages.size() > shown_count:
		print("[ModularityGuard][%s] %d more %s hidden; see %s." % [
			bucket_name,
			messages.size() - shown_count,
			description,
			REGISTRY_PATH
		])
