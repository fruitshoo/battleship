extends RefCounted
class_name SoldierShipWorkPriorityHelper

const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

const TASK_NONE := "none"
const TASK_DECK_DEFENSE := "deck_defense"
const TASK_CORPSE_CLEANUP := "corpse_cleanup"
const TASK_CANNON_RELOAD := "cannon_reload"
const TASK_RIGGING_REPAIR := "rigging_repair"
const TASK_GUNNERY_STATION := "gunnery_station"
const TASK_SHIPHANDLING_STATION := "shiphandling_station"
const TASK_SHIPHANDLING_ROWING := TASK_SHIPHANDLING_STATION
const TASK_SHIPHANDLING_RUDDER := TASK_SHIPHANDLING_STATION
const TASK_SHIPHANDLING_CRUISE := TASK_SHIPHANDLING_STATION

const PRIORITY_NONE := 0
const PRIORITY_DECK_DEFENSE := 100
const PRIORITY_CORPSE_CLEANUP := 80
const PRIORITY_CANNON_RELOAD := 70
const PRIORITY_RIGGING_REPAIR := 62
const PRIORITY_GUNNERY_STATION := PRIORITY_NONE
const PRIORITY_SHIPHANDLING_STATION := 42

const KEY_TASK := "task"
const KEY_PRIORITY := "priority"
const KEY_TARGET := "target"
const KEY_REASON := "reason"
const KEY_SLOT := "slot"
const KEY_PHASE := "phase"
const KEY_RUNTIME := "runtime"
const KEY_PREEMPTS_ROUTINE := "preempts_routine"
const KEY_LOCAL_TARGET := "local_target"

const PHASE_EMERGENCY := "emergency"
const PHASE_CLEANUP := "cleanup"
const PHASE_WEAPON_SUPPORT := "weapon_support"
const PHASE_REPAIR := "repair"
const PHASE_BATTLE_STATION := "battle_station"
const PHASE_SHIPHANDLING := "shiphandling"

const TASK_PRIORITY_TABLE := [
	{KEY_TASK: TASK_DECK_DEFENSE, KEY_PRIORITY: PRIORITY_DECK_DEFENSE, KEY_PHASE: PHASE_EMERGENCY, KEY_RUNTIME: "combat_ai", KEY_REASON: "hostiles on deck", KEY_PREEMPTS_ROUTINE: true},
	{KEY_TASK: TASK_CORPSE_CLEANUP, KEY_PRIORITY: PRIORITY_CORPSE_CLEANUP, KEY_PHASE: PHASE_CLEANUP, KEY_RUNTIME: "player_ship", KEY_REASON: "clear enemy corpse from allied deck", KEY_PREEMPTS_ROUTINE: true},
	{KEY_TASK: TASK_CANNON_RELOAD, KEY_PRIORITY: PRIORITY_CANNON_RELOAD, KEY_PHASE: PHASE_WEAPON_SUPPORT, KEY_RUNTIME: "cannon_reload", KEY_REASON: "weapon reload support", KEY_PREEMPTS_ROUTINE: true},
	{KEY_TASK: TASK_SHIPHANDLING_STATION, KEY_PRIORITY: PRIORITY_SHIPHANDLING_STATION, KEY_PHASE: PHASE_SHIPHANDLING, KEY_RUNTIME: "ship_duty", KEY_REASON: "shiphandling station", KEY_PREEMPTS_ROUTINE: false},
]

const DUTY_TARGET_REACHED_DISTANCE_SQ := 1.2
const DEFAULT_SLOT_RESERVATION_SECONDS := 1.1
const WORK_SLOT_RESERVATIONS_META := "ship_work_slot_reservations"
const ACTIVE_WORK_TASK_META := "ship_work_active_task"
const ACTIVE_WORK_SLOT_META := "ship_work_active_slot"
const ACTIVE_WORK_TARGET_LOCAL_META := "ship_work_active_target_local"
const RESERVATION_SOLDIER_ID := "soldier_id"
const RESERVATION_TASK := "task"
const RESERVATION_EXPIRES_AT_MSEC := "expires_at_msec"
const CANNON_DUTY_ARRIVE_RADIUS_SQ := 1.0
const CANNON_DUTY_OCCUPIED_RADIUS_SQ := 0.64
const DUTY_META_TASK := "ship_duty_task"
const DUTY_META_SLOT_KEY := "ship_duty_slot_key"
const DUTY_META_ANIMATION_KEY := "ship_duty_animation_key"
const DUTY_META_AT_SLOT := "ship_duty_at_slot"
const DIRECTIVE_CANNON := "cannon"
const DIRECTIVE_SLOT_INDEX := "slot_index"
const DIRECTIVE_ANIMATION_KEY := "animation_key"

static var _cannon_reload_slots_cache_frame: int = -1
static var _cannon_reload_slots_cache: Dictionary = {}
static var _gunnery_workers_cache_frame: int = -1
static var _gunnery_workers_cache: Dictionary = {}


static func find_ship_work_target(soldier) -> Vector3:
	var directive_profile_start := PhysicsFrameProfiler.begin()
	var directive := get_ship_work_directive(soldier)
	PhysicsFrameProfiler.end("soldier_work_directive", directive_profile_start)
	var ship := _get_owned_ship(soldier)
	var target: Variant = directive.get(KEY_TARGET, Vector3.INF)
	if not (target is Vector3):
		clear_active_ship_work_target(soldier)
		return Vector3.INF
	var target_vec: Vector3 = target
	var task_name := str(directive.get(KEY_TASK, TASK_NONE))
	var slot_key := str(directive.get(KEY_SLOT, ""))
	if not reserve_work_slot(ship, soldier, task_name, DEFAULT_SLOT_RESERVATION_SECONDS, slot_key):
		clear_active_ship_work_target(soldier)
		return Vector3.INF
	_store_active_ship_work_target(soldier, directive)
	target_vec.y = soldier.global_position.y
	_sync_cannon_reload_duty_state_from_directive(soldier, directive, target_vec)
	return target_vec


static func get_active_ship_work_target(soldier) -> Vector3:
	var profile_start := PhysicsFrameProfiler.begin()
	if not is_instance_valid(soldier) or not soldier.has_meta(ACTIVE_WORK_TARGET_LOCAL_META):
		PhysicsFrameProfiler.end("soldier_active_work_target", profile_start)
		return Vector3.INF
	var ship := _get_owned_ship(soldier)
	if not _can_consider_deck_work(soldier, ship, true):
		clear_active_ship_work_target(soldier)
		PhysicsFrameProfiler.end("soldier_active_work_target", profile_start)
		return Vector3.INF
	var task_name := str(soldier.get_meta(ACTIVE_WORK_TASK_META, TASK_NONE))
	if not _is_active_work_task_still_valid(soldier, ship, task_name):
		clear_active_ship_work_target(soldier)
		PhysicsFrameProfiler.end("soldier_active_work_target", profile_start)
		return Vector3.INF
	var local_target_value: Variant = soldier.get_meta(ACTIVE_WORK_TARGET_LOCAL_META, Vector3.INF)
	if not (local_target_value is Vector3):
		clear_active_ship_work_target(soldier)
		PhysicsFrameProfiler.end("soldier_active_work_target", profile_start)
		return Vector3.INF
	var local_target: Vector3 = local_target_value
	var global_target: Vector3 = ship.to_global(local_target)
	global_target.y = soldier.global_position.y
	if task_name == TASK_CANNON_RELOAD:
		var slot_key := str(soldier.get_meta(ACTIVE_WORK_SLOT_META, ""))
		if not reserve_work_slot(ship, soldier, task_name, DEFAULT_SLOT_RESERVATION_SECONDS, slot_key):
			clear_active_ship_work_target(soldier)
			PhysicsFrameProfiler.end("soldier_active_work_target", profile_start)
			return Vector3.INF
		_sync_cannon_reload_duty_state_from_active(soldier, ship, local_target, global_target)
		PhysicsFrameProfiler.end("soldier_active_work_target", profile_start)
		return global_target
	PhysicsFrameProfiler.end("soldier_active_work_target", profile_start)
	return global_target


static func clear_active_ship_work_target(soldier) -> void:
	if not is_instance_valid(soldier):
		return
	var ship := _get_owned_ship(soldier)
	var task_name := str(soldier.get_meta(ACTIVE_WORK_TASK_META, ""))
	var slot_key := str(soldier.get_meta(ACTIVE_WORK_SLOT_META, ""))
	if is_instance_valid(ship) and not task_name.is_empty():
		release_work_slot(ship, soldier, task_name, slot_key)
	for meta_name in [ACTIVE_WORK_TASK_META, ACTIVE_WORK_SLOT_META, ACTIVE_WORK_TARGET_LOCAL_META]:
		if soldier.has_meta(meta_name):
			soldier.remove_meta(meta_name)
	_clear_cannon_reload_duty_state(soldier)


static func get_ship_work_directive(soldier) -> Dictionary:
	var ship := _get_owned_ship(soldier)
	if not _can_consider_deck_work(soldier, ship):
		return _none_directive()

	var profile_start := PhysicsFrameProfiler.begin()
	var half_ext: Vector2 = SoldierShipHelper.get_ship_deck_half_extents(soldier, ship)
	var candidates: Array[Dictionary] = []
	_append_candidate(candidates, _build_gunnery_station_directive(soldier, ship, half_ext))
	_append_candidate(candidates, _build_shiphandling_directive(soldier, ship, half_ext))

	var best := _choose_highest_priority(candidates, ship, soldier)
	PhysicsFrameProfiler.end("soldier_work_candidates", profile_start)
	if int(best.get(KEY_PRIORITY, PRIORITY_NONE)) <= PRIORITY_NONE:
		return _none_directive()
	if _is_already_at_directive_target(soldier, ship, best) and str(best.get(KEY_TASK, TASK_NONE)) != TASK_CANNON_RELOAD:
		return _none_directive()
	return best


static func can_accept_immediate_work(soldier, task_name: String) -> bool:
	var ship := _get_owned_ship(soldier)
	if not _can_consider_deck_work(soldier, ship, true):
		return false
	if _has_conflicting_named_action(soldier, task_name):
		return false
	return int(get_task_priority(task_name)) > PRIORITY_NONE


static func score_worker_for_task(soldier, task_name: String, work_position: Vector3, max_distance_sq: float, work_anchor: Object = null, slot_key: String = "") -> float:
	if not can_accept_immediate_work(soldier, task_name):
		return -INF
	if is_instance_valid(work_anchor) and is_work_slot_reserved_for_other(work_anchor, soldier, task_name, slot_key):
		return -INF
	var distance_sq: float = soldier.global_position.distance_squared_to(work_position)
	if distance_sq > max_distance_sq:
		return -INF
	var distance_ratio: float = clampf(distance_sq / maxf(max_distance_sq, 0.001), 0.0, 1.0)
	var priority_score: float = float(get_task_priority(task_name)) * 1000.0
	var role_score: float = get_role_affinity_for_task(soldier, task_name) * 100.0
	var distance_score: float = (1.0 - distance_ratio) * 10.0
	return priority_score + role_score + distance_score


static func reserve_work_slot(work_anchor: Object, soldier, task_name: String, ttl_seconds: float = DEFAULT_SLOT_RESERVATION_SECONDS, slot_key: String = "") -> bool:
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
	var definition := get_task_definition(task_name)
	return int(definition.get(KEY_PRIORITY, PRIORITY_NONE))


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


static func get_role_affinity_for_task(soldier, task_name: String) -> float:
	var role := _get_soldier_role(soldier)
	var normalized_task := normalize_task_name(task_name)
	if normalized_task == TASK_DECK_DEFENSE:
		if role == "spearman":
			return 1.0
		if role == "general" or role == "fire_pot":
			return 0.9
		return 0.7
	if normalized_task == TASK_CORPSE_CLEANUP:
		if role == "general" or role == "spearman":
			return 0.85
		return 0.6
	if normalized_task == TASK_CANNON_RELOAD:
		if _is_ranged_only(soldier):
			return 1.0
		if role == "general" or role == "fire_pot" or role == "repeating_crossbow" or role == "singigeon" or role == "daecheolpo":
			return 0.9
		if role == "spearman":
			return 0.55
		return 0.7
	if normalized_task == TASK_RIGGING_REPAIR:
		if role == "general" or role == "spearman":
			return 0.9
		return 0.65
	if normalized_task.begins_with("shiphandling"):
		if role == "general" or role == "spearman":
			return 0.85
		return 0.6
	return 0.5


static func normalize_task_name(task_name: String) -> String:
	var normalized := task_name.strip_edges().to_lower().replace(" ", "_")
	match normalized:
		"shiphandling_rowing", "shiphandling_rudder", "shiphandling_cruise":
			return TASK_SHIPHANDLING_STATION
	return normalized


static func _build_rigging_repair_directive(_soldier, _ship: Node3D, _half_ext: Vector2) -> Dictionary:
	return _none_directive()


static func _build_gunnery_station_directive(soldier, ship: Node3D, half_ext: Vector2) -> Dictionary:
	var gunnery_ratio: float = float(ship.get("gunnery_crew_ratio")) if ship.get("gunnery_crew_ratio") != null else 0.0
	if gunnery_ratio < 0.45:
		return _none_directive()
	if not _can_work_gunnery(soldier):
		return _none_directive()
	return _build_cannon_reload_slot_directive(soldier, ship)


static func _build_shiphandling_directive(soldier, ship: Node3D, half_ext: Vector2) -> Dictionary:
	var handling_ratio: float = float(ship.get("shiphandling_crew_ratio")) if ship.get("shiphandling_crew_ratio") != null else 0.0
	if not _shiphandling_station_is_needed(ship, handling_ratio):
		return _none_directive()
	var bias_sign: float = _get_soldier_bias_sign(soldier)
	var duty_lane: int = int(soldier.get_instance_id()) % 5
	var duty_offset: float = clampf((float(duty_lane) - 2.0) * 0.52, -half_ext.y * 0.52, half_ext.y * 0.52)
	var local_target := Vector3(bias_sign * half_ext.x * 0.38, 0.0, duty_offset)
	return _build_directive(TASK_SHIPHANDLING_STATION, local_target, ship, "shiphandling station")

static func _build_cannon_reload_slot_directive(soldier, ship: Node3D) -> Dictionary:
	var slots: Array[Dictionary] = _collect_cannon_reload_slots(ship)
	if slots.is_empty():
		return _none_directive()
	var workers: Array[Node] = _collect_gunnery_duty_workers(ship, _get_node_team_tag(soldier))
	if not workers.has(soldier):
		return _none_directive()
	var assignments: Dictionary = _assign_cannon_reload_slots(workers, slots)
	var slot: Dictionary = assignments.get(soldier.get_instance_id(), {})
	if slot.is_empty():
		return _none_directive()
	var target_global: Vector3 = slot.get("global_position", Vector3.INF)
	if target_global == Vector3.INF:
		return _none_directive()
	var local_target: Vector3 = ship.to_local(target_global)
	local_target.y = 0.0
	var directive := _build_directive(TASK_CANNON_RELOAD, local_target, ship, "cannon reload station")
	directive[KEY_SLOT] = str(slot.get("slot_key", ""))
	directive[DIRECTIVE_CANNON] = slot.get("cannon", null)
	directive[DIRECTIVE_SLOT_INDEX] = int(slot.get("slot_index", 0))
	directive[DIRECTIVE_ANIMATION_KEY] = _get_cannon_reload_slot_animation(slot)
	return directive


static func _collect_cannon_reload_slots(ship: Node) -> Array[Dictionary]:
	if not is_instance_valid(ship):
		return []
	var frame := Engine.get_physics_frames()
	if _cannon_reload_slots_cache_frame != frame:
		_cannon_reload_slots_cache_frame = frame
		_cannon_reload_slots_cache.clear()
	var cache_key := int(ship.get_instance_id())
	if _cannon_reload_slots_cache.has(cache_key):
		return _cannon_reload_slots_cache[cache_key]
	var profile_start := PhysicsFrameProfiler.begin()
	var slots: Array[Dictionary] = []
	var stack: Array[Node] = [ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node != ship and _is_cannon_reload_slot_source(node):
			var slot_count: int = int(node.call("get_reload_crew_station_count"))
			for slot_index in range(slot_count):
				var slot_key := "%s:%03d" % [str(node.get_path()), slot_index]
				slots.append({
					"cannon_path": str(node.get_path()),
					"cannon": node,
					"slot_index": slot_index,
					"slot_key": slot_key,
					"global_position": node.call("get_reload_crew_station_global_position", slot_index),
				})
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key := "%s:%03d" % [str(a.get("cannon_path", "")), int(a.get("slot_index", 0))]
		var b_key := "%s:%03d" % [str(b.get("cannon_path", "")), int(b.get("slot_index", 0))]
		return a_key < b_key
	)
	PhysicsFrameProfiler.end("soldier_cannon_slots_scan", profile_start)
	_cannon_reload_slots_cache[cache_key] = slots
	return slots


static func _collect_gunnery_duty_workers(ship: Node, team: String) -> Array[Node]:
	if not is_instance_valid(ship):
		return []
	var frame := Engine.get_physics_frames()
	if _gunnery_workers_cache_frame != frame:
		_gunnery_workers_cache_frame = frame
		_gunnery_workers_cache.clear()
	var cache_key := "%d:%s" % [int(ship.get_instance_id()), team]
	if _gunnery_workers_cache.has(cache_key):
		return _gunnery_workers_cache[cache_key]
	var profile_start := PhysicsFrameProfiler.begin()
	var workers: Array[Node] = []
	var candidates: Array = EntityRegistry.get_soldiers_by_ship(ship)
	if candidates.is_empty():
		var soldiers_node: Node = NodeContractHelper.get_soldiers_container(ship)
		if is_instance_valid(soldiers_node):
			candidates = soldiers_node.get_children()
	for child in candidates:
		if not is_instance_valid(child):
			continue
		if _get_node_team_tag(child) != team:
			continue
		if _get_owned_ship(child) != ship:
			continue
		if not _can_consider_deck_work(child, ship as Node3D, true):
			continue
		if not _can_work_gunnery(child):
			continue
		workers.append(child)
	workers.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_instance_id()) < int(b.get_instance_id())
	)
	PhysicsFrameProfiler.end("soldier_gunnery_workers_scan", profile_start)
	_gunnery_workers_cache[cache_key] = workers
	return workers


static func _assign_cannon_reload_slots(workers: Array[Node], slots: Array[Dictionary]) -> Dictionary:
	var assignments: Dictionary = {}
	var reserved_slots: Dictionary = {}
	for worker in workers:
		var occupied_index: int = _find_occupied_cannon_slot_index(worker, slots)
		if occupied_index < 0 or reserved_slots.has(occupied_index):
			continue
		assignments[worker.get_instance_id()] = slots[occupied_index]
		reserved_slots[occupied_index] = worker.get_instance_id()

	for worker in workers:
		if assignments.has(worker.get_instance_id()):
			continue
		for slot_index in range(slots.size()):
			if reserved_slots.has(slot_index):
				continue
			assignments[worker.get_instance_id()] = slots[slot_index]
			reserved_slots[slot_index] = worker.get_instance_id()
			break
	return assignments


static func _find_occupied_cannon_slot_index(worker: Node, slots: Array[Dictionary]) -> int:
	if not (worker is Node3D):
		return -1
	var worker_node := worker as Node3D
	var best_index: int = -1
	var best_dist_sq: float = INF
	for slot_index in range(slots.size()):
		var slot: Dictionary = slots[slot_index]
		var slot_position: Vector3 = slot.get("global_position", Vector3.INF)
		if slot_position == Vector3.INF:
			continue
		var planar_delta := Vector2(worker_node.global_position.x - slot_position.x, worker_node.global_position.z - slot_position.z)
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq <= CANNON_DUTY_OCCUPIED_RADIUS_SQ and dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_index = slot_index
	return best_index


static func _is_cannon_reload_slot_source(node: Node) -> bool:
	if not node.has_method("get_reload_crew_station_count"):
		return false
	if not node.has_method("get_reload_crew_station_global_position"):
		return false
	if node.has_method("get_reload_crew_power") and float(node.call("get_reload_crew_power")) <= 0.0:
		return false
	if node.is_inside_tree():
		if node.has_method("is_visible_in_tree") and not node.is_visible_in_tree():
			return false
		if node.has_method("is_processing") and not node.is_processing():
			return false
	return true


static func _get_cannon_reload_slot_by_key(ship: Node, slot_key: String) -> Dictionary:
	if slot_key.strip_edges().is_empty():
		return {}
	for slot in _collect_cannon_reload_slots(ship):
		if str(slot.get("slot_key", "")) == slot_key:
			return slot
	return {}


static func _get_cannon_reload_slot_animation(slot: Dictionary) -> String:
	var cannon = slot.get("cannon", null)
	var slot_index: int = int(slot.get("slot_index", 0))
	if is_instance_valid(cannon) and cannon.has_method("get_reload_crew_station_animation_key"):
		return str(cannon.call("get_reload_crew_station_animation_key", slot_index))
	return "cannon_reload_standby"


static func _sync_cannon_reload_duty_state_from_directive(soldier, directive: Dictionary, target_global: Vector3) -> void:
	if str(directive.get(KEY_TASK, TASK_NONE)) != TASK_CANNON_RELOAD:
		_clear_cannon_reload_duty_state(soldier)
		return
	var slot: Dictionary = {
		"cannon": directive.get(DIRECTIVE_CANNON, null),
		"slot_index": int(directive.get(DIRECTIVE_SLOT_INDEX, 0)),
		"slot_key": str(directive.get(KEY_SLOT, "")),
	}
	_mark_cannon_reload_slot_state(soldier, slot, target_global, str(directive.get(DIRECTIVE_ANIMATION_KEY, "cannon_reload_standby")))


static func _sync_cannon_reload_duty_state_from_active(soldier, ship: Node, _local_target: Vector3, target_global: Vector3) -> void:
	var slot_key := str(soldier.get_meta(ACTIVE_WORK_SLOT_META, ""))
	var slot := _get_cannon_reload_slot_by_key(ship, slot_key)
	if slot.is_empty():
		_clear_cannon_reload_duty_state(soldier)
		return
	_mark_cannon_reload_slot_state(soldier, slot, target_global, _get_cannon_reload_slot_animation(slot))


static func _mark_cannon_reload_slot_state(soldier, slot: Dictionary, target_global: Vector3, animation_key: String) -> void:
	if not is_instance_valid(soldier):
		return
	var planar_delta := Vector2(soldier.global_position.x - target_global.x, soldier.global_position.z - target_global.z)
	var arrived: bool = planar_delta.length_squared() <= CANNON_DUTY_ARRIVE_RADIUS_SQ
	var cannon = slot.get("cannon", null)
	var slot_index: int = int(slot.get("slot_index", 0))
	if is_instance_valid(cannon) and cannon.has_method("notify_reload_crew_station_worker"):
		cannon.call("notify_reload_crew_station_worker", soldier, slot_index, arrived)
	var previous_task := str(soldier.get_meta(DUTY_META_TASK, ""))
	var previous_slot := str(soldier.get_meta(DUTY_META_SLOT_KEY, ""))
	var previous_animation := str(soldier.get_meta(DUTY_META_ANIMATION_KEY, ""))
	var previous_arrived := bool(soldier.get_meta(DUTY_META_AT_SLOT, false))
	var next_slot := str(slot.get("slot_key", ""))
	soldier.set_meta(DUTY_META_TASK, TASK_CANNON_RELOAD)
	soldier.set_meta(DUTY_META_SLOT_KEY, next_slot)
	soldier.set_meta(DUTY_META_ANIMATION_KEY, animation_key)
	soldier.set_meta(DUTY_META_AT_SLOT, arrived)
	if previous_task != TASK_CANNON_RELOAD or previous_slot != next_slot or previous_animation != animation_key or previous_arrived != arrived:
		_refresh_soldier_duty_visual(soldier)


static func _clear_cannon_reload_duty_state(soldier) -> void:
	if not is_instance_valid(soldier):
		return
	var had_duty_state: bool = false
	for key in [DUTY_META_TASK, DUTY_META_SLOT_KEY, DUTY_META_ANIMATION_KEY, DUTY_META_AT_SLOT]:
		if soldier.has_meta(key):
			had_duty_state = true
			soldier.remove_meta(key)
	if had_duty_state:
		_refresh_soldier_duty_visual(soldier)


static func _refresh_soldier_duty_visual(soldier) -> void:
	if is_instance_valid(soldier) and soldier.has_method("_update_role_visual"):
		soldier.call_deferred("_update_role_visual")


static func _can_consider_deck_work(soldier, ship: Node3D, allow_current_same_task: bool = false) -> bool:
	if not is_instance_valid(soldier) or not is_instance_valid(ship):
		return false
	var owned_team: String = _get_node_team_tag(ship)
	if owned_team != _get_node_team_tag(soldier):
		return false
	if SoldierStateHelper.is_dead_soldier(soldier):
		return false
	if soldier.get("current_target") != null:
		return false
	if soldier.get("is_captain") == true:
		return false
	if soldier.has_method("is_jumping_value") and soldier.call("is_jumping_value") == true:
		return false
	if _ship_has_deck_emergency(ship):
		return false
	if not allow_current_same_task and SoldierActionHelper.has_action(soldier):
		return false
	return true


static func _has_conflicting_named_action(soldier, task_name: String) -> bool:
	if not SoldierActionHelper.has_action(soldier):
		return false
	var current_action := SoldierActionHelper.get_action_name(soldier)
	var normalized_task := normalize_task_name(task_name)
	return current_action != normalized_task


static func _ship_has_deck_emergency(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return true
	if ship.get("deck_is_contested") == true or ship.get("deck_is_overrun") == true:
		return true
	return int(ship.get("deck_hostile_boarder_count")) > 0 if ship.get("deck_hostile_boarder_count") != null else false


static func _has_repairable_rigging_damage(_ship: Node3D) -> bool:
	return false


static func _get_most_damaged_mast_local(ship: Node3D, half_ext: Vector2) -> Vector3:
	var target_ratio: float = clampf(float(ship.get("rigging_repair_target_ratio")), 0.0, 1.0)
	var max_field_damage: float = 1.0 - target_ratio
	var best_mast: Node3D = null
	var best_damage: float = max_field_damage
	var masts_value: Variant = ship.get("masts")
	if not (masts_value is Array):
		return Vector3.INF
	for mast in masts_value:
		if not is_instance_valid(mast) or not (mast is Node3D) or not mast.has_method("get_sail_damage"):
			continue
		var damage: float = float(mast.call("get_sail_damage"))
		if damage <= best_damage:
			continue
		best_damage = damage
		best_mast = mast as Node3D
	if not is_instance_valid(best_mast):
		return Vector3.INF
	var local_pos: Vector3 = ship.to_local(best_mast.global_position)
	local_pos.x = clampf(local_pos.x, -half_ext.x * 0.55, half_ext.x * 0.55)
	local_pos.z = clampf(local_pos.z, -half_ext.y * 0.72, half_ext.y * 0.72)
	local_pos.y = 0.0
	return local_pos


static func _can_work_gunnery(soldier) -> bool:
	var role := _get_soldier_role(soldier)
	return _is_ranged_only(soldier) or role == "general" or role == "fire_pot" or role == "repeating_crossbow" or role == "singigeon" or role == "daecheolpo"


static func _get_soldier_role(soldier) -> String:
	if not is_instance_valid(soldier):
		return ""
	if soldier.has_method("get_crew_role_value"):
		return str(soldier.call("get_crew_role_value")).strip_edges().to_lower()
	if soldier.get("crew_role") != null:
		return str(soldier.get("crew_role")).strip_edges().to_lower()
	return ""


static func _is_ranged_only(soldier) -> bool:
	return is_instance_valid(soldier) and soldier.has_method("is_ranged_only_value") and soldier.call("is_ranged_only_value") == true


static func _get_enemy_side_sign(soldier, fallback_sign: float) -> float:
	var owned_ship: Node3D = _get_owned_ship(soldier)
	if not is_instance_valid(owned_ship):
		return fallback_sign
	var opposing_team: String = "enemy" if _get_node_team_tag(soldier) == "player" else "player"
	var opposing_ships: Array = EntityRegistry.get_ships_by_team(opposing_team)
	var best_ship: Node3D = null
	var best_distance_sq: float = INF
	for other_ship in opposing_ships:
		if not is_instance_valid(other_ship):
			continue
		if other_ship.has_method("is_sinking_or_dying") and other_ship.call("is_sinking_or_dying") == true:
			continue
		var planar_delta: Vector3 = other_ship.global_position - owned_ship.global_position
		planar_delta.y = 0.0
		var dist_sq: float = planar_delta.length_squared()
		if dist_sq < best_distance_sq:
			best_distance_sq = dist_sq
			best_ship = other_ship
	if not is_instance_valid(best_ship):
		return fallback_sign
	var enemy_local: Vector3 = owned_ship.to_local(best_ship.global_position)
	if absf(enemy_local.x) <= 0.2:
		return fallback_sign
	return 1.0 if enemy_local.x >= 0.0 else -1.0


static func _build_directive(task_name: String, local_target: Vector3, ship: Node3D, reason: String) -> Dictionary:
	var global_target: Vector3 = ship.to_global(local_target)
	return {
		KEY_TASK: task_name,
		KEY_PRIORITY: get_task_priority(task_name),
		KEY_TARGET: global_target,
		KEY_LOCAL_TARGET: local_target,
		KEY_REASON: reason,
		KEY_SLOT: _make_local_slot_key(task_name, local_target),
	}


static func _none_directive() -> Dictionary:
	return {
		KEY_TASK: TASK_NONE,
		KEY_PRIORITY: PRIORITY_NONE,
		KEY_TARGET: Vector3.INF,
		KEY_REASON: "",
		KEY_SLOT: "",
	}


static func _append_candidate(candidates: Array[Dictionary], candidate: Dictionary) -> void:
	if int(candidate.get(KEY_PRIORITY, PRIORITY_NONE)) > PRIORITY_NONE:
		candidates.append(candidate)


static func _choose_highest_priority(candidates: Array[Dictionary], ship: Node3D, soldier) -> Dictionary:
	var best := _none_directive()
	for candidate in candidates:
		if is_work_slot_reserved_for_other(ship, soldier, str(candidate.get(KEY_TASK, "")), str(candidate.get(KEY_SLOT, ""))):
			continue
		if int(candidate.get(KEY_PRIORITY, PRIORITY_NONE)) > int(best.get(KEY_PRIORITY, PRIORITY_NONE)):
			best = candidate
	return best


static func _is_already_at_directive_target(soldier, ship: Node3D, directive: Dictionary) -> bool:
	var target: Variant = directive.get(KEY_TARGET, Vector3.INF)
	if not (target is Vector3):
		return true
	var target_vec: Vector3 = target
	var target_local: Vector3 = ship.to_local(target_vec)
	return _is_local_target_reached(soldier, ship, target_local)


static func _is_local_target_reached(soldier, ship: Node3D, target_local: Vector3) -> bool:
	var ship_local_pos: Vector3 = ship.to_local(soldier.global_position)
	var local_diff := Vector2(ship_local_pos.x - target_local.x, ship_local_pos.z - target_local.z)
	return local_diff.length_squared() <= DUTY_TARGET_REACHED_DISTANCE_SQ


static func _store_active_ship_work_target(soldier, directive: Dictionary) -> void:
	if not is_instance_valid(soldier):
		return
	var local_target: Variant = directive.get(KEY_LOCAL_TARGET, Vector3.INF)
	if not (local_target is Vector3):
		clear_active_ship_work_target(soldier)
		return
	soldier.set_meta(ACTIVE_WORK_TASK_META, str(directive.get(KEY_TASK, TASK_NONE)))
	soldier.set_meta(ACTIVE_WORK_SLOT_META, str(directive.get(KEY_SLOT, "")))
	soldier.set_meta(ACTIVE_WORK_TARGET_LOCAL_META, local_target)


static func _is_active_work_task_still_valid(soldier, ship: Node3D, task_name: String) -> bool:
	if not is_instance_valid(ship):
		return false
	var normalized_task := normalize_task_name(task_name)
	match normalized_task:
		TASK_RIGGING_REPAIR:
			return _has_repairable_rigging_damage(ship)
		TASK_CANNON_RELOAD:
			var gunnery_ratio: float = float(ship.get("gunnery_crew_ratio")) if ship.get("gunnery_crew_ratio") != null else 0.0
			return gunnery_ratio >= 0.45 and _can_work_gunnery(soldier) and not _get_cannon_reload_slot_by_key(ship, str(soldier.get_meta(ACTIVE_WORK_SLOT_META, ""))).is_empty()
		TASK_GUNNERY_STATION:
			return false
		TASK_SHIPHANDLING_STATION:
			var handling_ratio: float = float(ship.get("shiphandling_crew_ratio")) if ship.get("shiphandling_crew_ratio") != null else 0.0
			return _shiphandling_station_is_needed(ship, handling_ratio)
	return false


static func _shiphandling_station_is_needed(ship: Node3D, handling_ratio: float) -> bool:
	if handling_ratio < 0.45:
		return false
	var rowing_active: bool = ship.get("is_rowing") == true if ship.get("is_rowing") != null else false
	if rowing_active:
		return true
	var rudder_angle: float = float(ship.get("rudder_angle")) if ship.get("rudder_angle") != null else 0.0
	return absf(rudder_angle) >= 12.0


static func _get_soldier_bias_sign(soldier) -> float:
	return -1.0 if int(soldier.get_instance_id()) % 2 == 0 else 1.0


static func _make_local_slot_key(task_name: String, local_target: Vector3) -> String:
	var quantized_x := int(round(local_target.x * 4.0))
	var quantized_z := int(round(local_target.z * 4.0))
	return "%s:%d:%d" % [normalize_task_name(task_name), quantized_x, quantized_z]


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
	var owned_ship_value: Variant = soldier.get("owned_ship")
	return owned_ship_value if is_instance_valid(owned_ship_value) and owned_ship_value is Node3D else null


static func _get_node_team_tag(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_method("get_team_tag"):
		return str(node.call("get_team_tag"))
	if node.get("team") != null:
		return str(node.get("team"))
	return ""
