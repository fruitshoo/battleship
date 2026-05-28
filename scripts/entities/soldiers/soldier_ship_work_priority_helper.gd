extends RefCounted
class_name SoldierShipWorkPriorityHelper

const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")

const TASK_NONE := "none"
const TASK_CARGO_TRANSPORT := "cargo_transport"

const PRIORITY_NONE := 0
const PRIORITY_CARGO_TRANSPORT := 80

const KEY_TASK := "task"
const KEY_PRIORITY := "priority"
const KEY_PHASE := "phase"
const KEY_RUNTIME := "runtime"
const KEY_REASON := "reason"
const KEY_PREEMPTS_ROUTINE := "preempts_routine"

const PHASE_TRANSPORT := "transport"
const WORK_SLOT_RESERVATIONS_META := "ship_work_slot_reservations"
const RESERVATION_SOLDIER_ID := "soldier_id"
const RESERVATION_TASK := "task"
const RESERVATION_EXPIRES_AT_MSEC := "expires_at_msec"

const TASK_PRIORITY_TABLE := [
	{KEY_TASK: TASK_CARGO_TRANSPORT, KEY_PRIORITY: PRIORITY_CARGO_TRANSPORT, KEY_PHASE: PHASE_TRANSPORT, KEY_RUNTIME: "player_ship", KEY_REASON: "transport deck payload from allied deck", KEY_PREEMPTS_ROUTINE: true},
]


static func can_accept_immediate_work(soldier, task_name: String) -> bool:
	if normalize_task_name(task_name) != TASK_CARGO_TRANSPORT:
		return false
	if not is_instance_valid(soldier):
		return false
	if _get_node_team_tag(soldier) != "player":
		return false
	if SoldierStateHelper.is_dead_soldier(soldier):
		return false
	if soldier.get("current_target") != null:
		return false
	if soldier.get("is_captain") == true:
		return false
	if soldier.has_method("is_jumping_value") and soldier.call("is_jumping_value") == true:
		return false
	if SoldierActionHelper.has_action(soldier):
		return false
	var ship := _get_owned_ship(soldier)
	if not is_instance_valid(ship):
		return false
	if _get_node_team_tag(ship) != "player":
		return false
	if ship.get("deck_is_contested") == true or ship.get("deck_is_overrun") == true:
		return false
	var hostile_count: Variant = ship.get("deck_hostile_boarder_count")
	if hostile_count != null and int(hostile_count) > 0:
		return false
	return true


static func reserve_work_slot(work_anchor: Object, soldier, task_name: String, ttl_seconds: float = 1.1, slot_key: String = "") -> bool:
	if not is_instance_valid(work_anchor) or not is_instance_valid(soldier):
		return false
	var normalized_task := normalize_task_name(task_name)
	if normalized_task.is_empty() or normalized_task == TASK_NONE:
		return false
	var normalized_slot := _get_reservation_slot_key(normalized_task, slot_key)
	var reservations := _get_pruned_reservations(work_anchor)
	var existing: Variant = reservations.get(normalized_slot, {})
	var soldier_id := int(soldier.get_instance_id())
	if existing is Dictionary and _is_active_reservation(existing):
		var reserved_by := int(existing.get(RESERVATION_SOLDIER_ID, 0))
		if reserved_by != 0 and reserved_by != soldier_id:
			_set_reservations(work_anchor, reservations)
			return false
	reservations[normalized_slot] = {
		RESERVATION_SOLDIER_ID: soldier_id,
		RESERVATION_TASK: normalized_task,
		RESERVATION_EXPIRES_AT_MSEC: Time.get_ticks_msec() + int(maxf(ttl_seconds, 0.1) * 1000.0),
	}
	_set_reservations(work_anchor, reservations)
	return true


static func release_work_slot(work_anchor: Object, soldier = null, task_name: String = "", slot_key: String = "") -> void:
	if not is_instance_valid(work_anchor):
		return
	var reservations := _get_pruned_reservations(work_anchor)
	var soldier_id := int(soldier.get_instance_id()) if is_instance_valid(soldier) else 0
	var normalized_task := normalize_task_name(task_name)
	var normalized_slot := _get_reservation_slot_key(normalized_task, slot_key) if not normalized_task.is_empty() else ""

	for key in reservations.keys():
		var key_string := str(key)
		if not normalized_slot.is_empty() and key_string != normalized_slot:
			continue
		var entry: Variant = reservations[key]
		if not (entry is Dictionary):
			reservations.erase(key)
			continue
		if not normalized_task.is_empty() and str(entry.get(RESERVATION_TASK, "")) != normalized_task:
			continue
		if soldier_id != 0 and int(entry.get(RESERVATION_SOLDIER_ID, 0)) != soldier_id:
			continue
		reservations.erase(key)
	_set_reservations(work_anchor, reservations)


static func is_work_slot_reserved_for_other(work_anchor: Object, soldier = null, task_name: String = "", slot_key: String = "") -> bool:
	if not is_instance_valid(work_anchor):
		return false
	var reservations := _get_pruned_reservations(work_anchor)
	_set_reservations(work_anchor, reservations)
	var soldier_id := int(soldier.get_instance_id()) if is_instance_valid(soldier) else 0
	var normalized_task := normalize_task_name(task_name)
	var normalized_slot := _get_reservation_slot_key(normalized_task, slot_key) if not normalized_task.is_empty() else ""

	for key in reservations.keys():
		var key_string := str(key)
		if not normalized_slot.is_empty() and key_string != normalized_slot:
			continue
		var entry: Variant = reservations[key]
		if not (entry is Dictionary) or not _is_active_reservation(entry):
			continue
		if not normalized_task.is_empty() and str(entry.get(RESERVATION_TASK, "")) != normalized_task:
			continue
		var reserved_by := int(entry.get(RESERVATION_SOLDIER_ID, 0))
		if soldier_id == 0 or reserved_by != soldier_id:
			return true
	return false


static func get_task_priority(task_name: String) -> int:
	return PRIORITY_CARGO_TRANSPORT if normalize_task_name(task_name) == TASK_CARGO_TRANSPORT else PRIORITY_NONE


static func get_task_definition(task_name: String) -> Dictionary:
	var normalized_task := normalize_task_name(task_name)
	for row in TASK_PRIORITY_TABLE:
		var definition: Dictionary = row
		if str(definition.get(KEY_TASK, "")) == normalized_task:
			return definition.duplicate(true)
	return {
		KEY_TASK: TASK_NONE,
		KEY_PRIORITY: PRIORITY_NONE,
		KEY_PHASE: "",
		KEY_RUNTIME: "",
		KEY_REASON: "",
		KEY_PREEMPTS_ROUTINE: false,
	}


static func get_task_priority_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in TASK_PRIORITY_TABLE:
		var definition: Dictionary = row
		rows.append(definition.duplicate(true))
	return rows


static func get_task_phase(task_name: String) -> String:
	return str(get_task_definition(task_name).get(KEY_PHASE, ""))


static func normalize_task_name(task_name: String) -> String:
	return task_name.strip_edges().to_lower().replace(" ", "_")


static func _get_reservation_slot_key(task_name: String, slot_key: String = "") -> String:
	var normalized_task := normalize_task_name(task_name)
	var normalized_slot := slot_key.strip_edges()
	if normalized_slot.is_empty():
		normalized_slot = "default"
	return "%s|%s" % [normalized_task, normalized_slot]


static func _get_pruned_reservations(work_anchor: Object) -> Dictionary:
	var reservations_value: Variant = work_anchor.get_meta(WORK_SLOT_RESERVATIONS_META, {})
	var source: Dictionary = reservations_value if reservations_value is Dictionary else {}
	var pruned: Dictionary = {}
	for key in source.keys():
		var entry: Variant = source[key]
		if entry is Dictionary and _is_active_reservation(entry):
			pruned[str(key)] = entry
	return pruned


static func _set_reservations(work_anchor: Object, reservations: Dictionary) -> void:
	if reservations.is_empty():
		if work_anchor.has_meta(WORK_SLOT_RESERVATIONS_META):
			work_anchor.remove_meta(WORK_SLOT_RESERVATIONS_META)
		return
	work_anchor.set_meta(WORK_SLOT_RESERVATIONS_META, reservations)


static func _is_active_reservation(entry: Dictionary) -> bool:
	return int(entry.get(RESERVATION_EXPIRES_AT_MSEC, 0)) > Time.get_ticks_msec()


static func _get_owned_ship(soldier) -> Node3D:
	if not is_instance_valid(soldier):
		return null
	if soldier.has_method("get_owned_ship_node"):
		var owned_node: Variant = soldier.call("get_owned_ship_node")
		return owned_node if is_instance_valid(owned_node) and owned_node is Node3D else null
	var owned_value: Variant = soldier.get("owned_ship")
	return owned_value if is_instance_valid(owned_value) and owned_value is Node3D else null


static func _get_node_team_tag(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_method("get_team_tag"):
		return str(node.call("get_team_tag")).strip_edges().to_lower()
	if node.get("team") != null:
		return str(node.get("team")).strip_edges().to_lower()
	return ""
