extends RefCounted
class_name SoldierShipWorkPriorityHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")
const SoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")

const TASK_NONE := "none"
const TASK_DECK_DEFENSE := "deck_defense"
const TASK_CORPSE_CLEANUP := "corpse_cleanup"
const TASK_CANNON_RELOAD := "cannon_reload"
const TASK_RIGGING_REPAIR := "rigging_repair"
const TASK_GUNNERY_STATION := "gunnery_station"
const TASK_SHIPHANDLING_ROWING := "shiphandling_rowing"
const TASK_SHIPHANDLING_RUDDER := "shiphandling_rudder"
const TASK_SHIPHANDLING_CRUISE := "shiphandling_cruise"

const PRIORITY_NONE := 0
const PRIORITY_DECK_DEFENSE := 100
const PRIORITY_CORPSE_CLEANUP := 80
const PRIORITY_CANNON_RELOAD := 70
const PRIORITY_RIGGING_REPAIR := 62
const PRIORITY_GUNNERY_STATION := 56
const PRIORITY_SHIPHANDLING_ROWING := 46
const PRIORITY_SHIPHANDLING_RUDDER := 42
const PRIORITY_SHIPHANDLING_CRUISE := 34

const KEY_TASK := "task"
const KEY_PRIORITY := "priority"
const KEY_TARGET := "target"
const KEY_REASON := "reason"
const KEY_SLOT := "slot"
const KEY_PHASE := "phase"
const KEY_RUNTIME := "runtime"
const KEY_PREEMPTS_ROUTINE := "preempts_routine"

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
	{KEY_TASK: TASK_RIGGING_REPAIR, KEY_PRIORITY: PRIORITY_RIGGING_REPAIR, KEY_PHASE: PHASE_REPAIR, KEY_RUNTIME: "ship_duty", KEY_REASON: "damaged rigging", KEY_PREEMPTS_ROUTINE: true},
	{KEY_TASK: TASK_GUNNERY_STATION, KEY_PRIORITY: PRIORITY_GUNNERY_STATION, KEY_PHASE: PHASE_BATTLE_STATION, KEY_RUNTIME: "ship_duty", KEY_REASON: "gunnery posture", KEY_PREEMPTS_ROUTINE: false},
	{KEY_TASK: TASK_SHIPHANDLING_ROWING, KEY_PRIORITY: PRIORITY_SHIPHANDLING_ROWING, KEY_PHASE: PHASE_SHIPHANDLING, KEY_RUNTIME: "ship_duty", KEY_REASON: "rowing", KEY_PREEMPTS_ROUTINE: false},
	{KEY_TASK: TASK_SHIPHANDLING_RUDDER, KEY_PRIORITY: PRIORITY_SHIPHANDLING_RUDDER, KEY_PHASE: PHASE_SHIPHANDLING, KEY_RUNTIME: "ship_duty", KEY_REASON: "rudder", KEY_PREEMPTS_ROUTINE: false},
	{KEY_TASK: TASK_SHIPHANDLING_CRUISE, KEY_PRIORITY: PRIORITY_SHIPHANDLING_CRUISE, KEY_PHASE: PHASE_SHIPHANDLING, KEY_RUNTIME: "ship_duty", KEY_REASON: "under way", KEY_PREEMPTS_ROUTINE: false},
]

const DUTY_TARGET_REACHED_DISTANCE_SQ := 1.2
const DEFAULT_SLOT_RESERVATION_SECONDS := 1.1
const WORK_SLOT_RESERVATIONS_META := "ship_work_slot_reservations"
const RESERVATION_SOLDIER_ID := "soldier_id"
const RESERVATION_TASK := "task"
const RESERVATION_EXPIRES_AT_MSEC := "expires_at_msec"


static func find_ship_work_target(soldier) -> Vector3:
	var directive := get_ship_work_directive(soldier)
	var ship := _get_owned_ship(soldier)
	var target: Variant = directive.get(KEY_TARGET, Vector3.INF)
	if not (target is Vector3):
		return Vector3.INF
	var target_vec: Vector3 = target
	var task_name := str(directive.get(KEY_TASK, TASK_NONE))
	var slot_key := str(directive.get(KEY_SLOT, ""))
	if not reserve_work_slot(ship, soldier, task_name, DEFAULT_SLOT_RESERVATION_SECONDS, slot_key):
		return Vector3.INF
	target_vec.y = soldier.global_position.y
	return target_vec


static func get_ship_work_directive(soldier) -> Dictionary:
	var ship := _get_owned_ship(soldier)
	if not _can_consider_deck_work(soldier, ship):
		return _none_directive()

	var half_ext: Vector2 = SoldierShipHelper.get_ship_deck_half_extents(soldier, ship)
	var candidates: Array[Dictionary] = []
	_append_candidate(candidates, _build_rigging_repair_directive(soldier, ship, half_ext))
	_append_candidate(candidates, _build_gunnery_station_directive(soldier, ship, half_ext))
	_append_candidate(candidates, _build_shiphandling_directive(soldier, ship, half_ext))

	var best := _choose_highest_priority(candidates, ship, soldier)
	if int(best.get(KEY_PRIORITY, PRIORITY_NONE)) <= PRIORITY_NONE:
		return _none_directive()
	if _is_already_at_directive_target(soldier, ship, best):
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
	if normalized_task == TASK_CANNON_RELOAD or normalized_task == TASK_GUNNERY_STATION:
		if _is_ranged_only(soldier):
			return 1.0
		if role == "general" or role == "fire_pot" or role == "repeating_crossbow" or role == "singigeon":
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
	return task_name.strip_edges().to_lower().replace(" ", "_")


static func _build_rigging_repair_directive(soldier, ship: Node3D, half_ext: Vector2) -> Dictionary:
	if not _has_repairable_rigging_damage(ship):
		return _none_directive()
	var bias_sign: float = _get_soldier_bias_sign(soldier)
	var local_target: Vector3 = Vector3(bias_sign * half_ext.x * 0.24, 0.0, half_ext.y * 0.72)
	var target_ratio: float = clampf(float(ship.get("rigging_repair_target_ratio")), 0.0, 1.0)
	var rudder_max_health: float = float(ship.get("rudder_max_health")) if ship.get("rudder_max_health") != null else 0.0
	var rudder_health: float = float(ship.get("rudder_health")) if ship.get("rudder_health") != null else rudder_max_health
	if rudder_max_health > 0.0 and rudder_health < rudder_max_health * target_ratio - 0.001:
		local_target = Vector3(bias_sign * half_ext.x * 0.32, 0.0, half_ext.y * 0.84)
	else:
		var mast_target := _get_most_damaged_mast_local(ship, half_ext)
		if mast_target != Vector3.INF:
			local_target = mast_target
	return _build_directive(TASK_RIGGING_REPAIR, local_target, ship, "damaged rigging")


static func _build_gunnery_station_directive(soldier, ship: Node3D, half_ext: Vector2) -> Dictionary:
	var gunnery_ratio: float = float(ship.get("gunnery_crew_ratio")) if ship.get("gunnery_crew_ratio") != null else 0.0
	if gunnery_ratio < 0.45:
		return _none_directive()
	if not _can_work_gunnery(soldier):
		return _none_directive()
	var side_sign: float = _get_enemy_side_sign(soldier, _get_soldier_bias_sign(soldier))
	var lane_index: int = int(soldier.get_instance_id()) % 5
	var lane_offset: float = clampf((float(lane_index) - 2.0) * 0.45, -half_ext.y * 0.42, half_ext.y * 0.42)
	var local_target := Vector3(side_sign * half_ext.x * 0.76, 0.0, lane_offset)
	return _build_directive(TASK_GUNNERY_STATION, local_target, ship, "gunnery posture")


static func _build_shiphandling_directive(soldier, ship: Node3D, half_ext: Vector2) -> Dictionary:
	var handling_ratio: float = float(ship.get("shiphandling_crew_ratio")) if ship.get("shiphandling_crew_ratio") != null else 0.0
	if handling_ratio < 0.45:
		return _none_directive()
	var bias_sign: float = _get_soldier_bias_sign(soldier)
	var duty_lane: int = int(soldier.get_instance_id()) % 5
	var duty_offset: float = clampf((float(duty_lane) - 2.0) * 0.55, -half_ext.y * 0.58, half_ext.y * 0.58)
	var rowing_active: bool = ship.get("is_rowing") == true if ship.get("is_rowing") != null else false
	if rowing_active:
		return _build_directive(TASK_SHIPHANDLING_ROWING, Vector3(bias_sign * half_ext.x * 0.72, 0.0, duty_offset), ship, "rowing")
	var rudder_angle: float = float(ship.get("rudder_angle")) if ship.get("rudder_angle") != null else 0.0
	if absf(rudder_angle) >= 7.5:
		return _build_directive(TASK_SHIPHANDLING_RUDDER, Vector3(bias_sign * half_ext.x * 0.32, 0.0, half_ext.y * 0.82), ship, "rudder")
	var current_speed: float = ship.get_current_speed_value() if ship.has_method("get_current_speed_value") else 0.0
	if current_speed > 1.2:
		return _build_directive(TASK_SHIPHANDLING_CRUISE, Vector3(bias_sign * half_ext.x * 0.22, 0.0, half_ext.y * 0.35), ship, "under way")
	return _none_directive()


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


static func _has_repairable_rigging_damage(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.get("rigging_field_repair_enabled") != true:
		return false
	if ship.get("is_burning") == true or ship.get("is_sinking") == true or ship.get("is_dying") == true or ship.get("is_derelict") == true:
		return false
	var target_ratio: float = clampf(float(ship.get("rigging_repair_target_ratio")), 0.0, 1.0)
	var rudder_max_health: float = float(ship.get("rudder_max_health")) if ship.get("rudder_max_health") != null else 0.0
	var rudder_health: float = float(ship.get("rudder_health")) if ship.get("rudder_health") != null else rudder_max_health
	if rudder_max_health > 0.0 and rudder_health < rudder_max_health * target_ratio - 0.001:
		return true
	var max_field_damage: float = 1.0 - target_ratio
	var masts_value: Variant = ship.get("masts")
	if not (masts_value is Array):
		return false
	for mast in masts_value:
		if not is_instance_valid(mast) or not mast.has_method("get_sail_damage"):
			continue
		if float(mast.call("get_sail_damage")) > max_field_damage + 0.001:
			return true
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
	return _is_ranged_only(soldier) or role == "general" or role == "fire_pot" or role == "repeating_crossbow" or role == "singigeon"


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
	var ship_local_pos: Vector3 = ship.to_local(soldier.global_position)
	var target_local: Vector3 = ship.to_local(target_vec)
	var local_diff := Vector2(ship_local_pos.x - target_local.x, ship_local_pos.z - target_local.z)
	return local_diff.length_squared() <= DUTY_TARGET_REACHED_DISTANCE_SQ


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
		return soldier.call("get_owned_ship_node") as Node3D
	var owned_ship_value: Variant = soldier.get("owned_ship")
	return owned_ship_value as Node3D if owned_ship_value is Node3D else null


static func _get_node_team_tag(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_method("get_team_tag"):
		return str(node.call("get_team_tag"))
	if node.get("team") != null:
		return str(node.get("team"))
	return ""
