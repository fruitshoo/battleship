extends RefCounted

const ACTION_NAME_META := "soldier_action_name"
const ACTION_BUSY_META := "soldier_action_busy"
const ACTION_AI_LOCK_META := "soldier_action_ai_locked"
const ACTION_ANIMATION_META := "action_animation_name"
const CARRY_ANCHOR_NAME := "CarryAnchor"
const CARRY_ANCHOR_META := "soldier_carry_anchor_node"
const CARRY_PAYLOAD_ID_META := "soldier_carry_payload_id"
const CARRY_PAYLOAD_KIND_META := "soldier_carry_payload_kind"
const CARRY_PAYLOAD_OWNER_META := "soldier_carry_payload_owner_id"
const PAYLOAD_DEF_KIND := "kind"
const PAYLOAD_DEF_FORWARD_OFFSET := "forward_offset"
const PAYLOAD_DEF_SIDE_OFFSET := "side_offset"
const PAYLOAD_DEF_HEIGHT_OFFSET := "height_offset"
const DEFAULT_CARRY_FORWARD_OFFSET := 0.08
const DEFAULT_CARRY_SIDE_OFFSET := 0.08
const DEFAULT_CARRY_HEIGHT_OFFSET := 0.46
const CARRY_PAYLOAD_KIND_GENERIC := "generic"
const CARRY_PAYLOAD_KIND_CORPSE := "corpse"
const CARRY_PAYLOAD_KIND_CANNONBALL := "cannonball"
const CARRY_PAYLOAD_KIND_TOOL := "tool"
const CARRY_PAYLOAD_KIND_SUPPLY_CRATE := "supply_crate"
const CARRY_PAYLOAD_DEFINITIONS := {
	CARRY_PAYLOAD_KIND_GENERIC: {
		PAYLOAD_DEF_FORWARD_OFFSET: DEFAULT_CARRY_FORWARD_OFFSET,
		PAYLOAD_DEF_SIDE_OFFSET: DEFAULT_CARRY_SIDE_OFFSET,
		PAYLOAD_DEF_HEIGHT_OFFSET: DEFAULT_CARRY_HEIGHT_OFFSET,
	},
	CARRY_PAYLOAD_KIND_CORPSE: {
		PAYLOAD_DEF_FORWARD_OFFSET: 0.08,
		PAYLOAD_DEF_SIDE_OFFSET: 0.08,
		PAYLOAD_DEF_HEIGHT_OFFSET: 0.46,
	},
	CARRY_PAYLOAD_KIND_CANNONBALL: {
		PAYLOAD_DEF_FORWARD_OFFSET: 0.18,
		PAYLOAD_DEF_SIDE_OFFSET: 0.05,
		PAYLOAD_DEF_HEIGHT_OFFSET: 0.36,
	},
	CARRY_PAYLOAD_KIND_TOOL: {
		PAYLOAD_DEF_FORWARD_OFFSET: 0.12,
		PAYLOAD_DEF_SIDE_OFFSET: 0.09,
		PAYLOAD_DEF_HEIGHT_OFFSET: 0.42,
	},
	CARRY_PAYLOAD_KIND_SUPPLY_CRATE: {
		PAYLOAD_DEF_FORWARD_OFFSET: 0.2,
		PAYLOAD_DEF_SIDE_OFFSET: 0.0,
		PAYLOAD_DEF_HEIGHT_OFFSET: 0.34,
	},
}

const ACTION_CORPSE_CLEANUP_APPROACH := "corpse_cleanup_approach"
const ACTION_CORPSE_CLEANUP_CARRY := "corpse_cleanup_carry"
const ACTION_CORPSE_CLEANUP_THROW := "corpse_cleanup_throw"
const ACTION_CANNON_RELOAD := "cannon_reload"
const ACTION_INCAPACITATED_ASSIST := "incapacitated_assist"
const ACTION_DEF_NAME := "name"
const ACTION_DEF_FAMILY := "family"
const ACTION_DEF_LOCKS_AI := "locks_ai"
const ACTION_DEF_ANIMATION := "animation"
const ACTION_FAMILY_CORPSE_CLEANUP := "corpse_cleanup"
const ACTION_FAMILY_WEAPON_SUPPORT := "weapon_support"
const ACTION_FAMILY_MEDICAL_SUPPORT := "medical_support"
const CORPSE_CLEANUP_ACTIONS := {
	ACTION_CORPSE_CLEANUP_APPROACH: true,
	ACTION_CORPSE_CLEANUP_CARRY: true,
	ACTION_CORPSE_CLEANUP_THROW: true,
}
const ACTION_DEFINITIONS := {
	ACTION_CORPSE_CLEANUP_APPROACH: {
		ACTION_DEF_NAME: ACTION_CORPSE_CLEANUP_APPROACH,
		ACTION_DEF_FAMILY: ACTION_FAMILY_CORPSE_CLEANUP,
		ACTION_DEF_LOCKS_AI: true,
		ACTION_DEF_ANIMATION: ACTION_CORPSE_CLEANUP_APPROACH,
	},
	ACTION_CORPSE_CLEANUP_CARRY: {
		ACTION_DEF_NAME: ACTION_CORPSE_CLEANUP_CARRY,
		ACTION_DEF_FAMILY: ACTION_FAMILY_CORPSE_CLEANUP,
		ACTION_DEF_LOCKS_AI: true,
		ACTION_DEF_ANIMATION: ACTION_CORPSE_CLEANUP_CARRY,
	},
	ACTION_CORPSE_CLEANUP_THROW: {
		ACTION_DEF_NAME: ACTION_CORPSE_CLEANUP_THROW,
		ACTION_DEF_FAMILY: ACTION_FAMILY_CORPSE_CLEANUP,
		ACTION_DEF_LOCKS_AI: true,
		ACTION_DEF_ANIMATION: ACTION_CORPSE_CLEANUP_THROW,
	},
	ACTION_CANNON_RELOAD: {
		ACTION_DEF_NAME: ACTION_CANNON_RELOAD,
		ACTION_DEF_FAMILY: ACTION_FAMILY_WEAPON_SUPPORT,
		ACTION_DEF_LOCKS_AI: false,
		ACTION_DEF_ANIMATION: ACTION_CANNON_RELOAD,
	},
	ACTION_INCAPACITATED_ASSIST: {
		ACTION_DEF_NAME: ACTION_INCAPACITATED_ASSIST,
		ACTION_DEF_FAMILY: ACTION_FAMILY_MEDICAL_SUPPORT,
		ACTION_DEF_LOCKS_AI: false,
		ACTION_DEF_ANIMATION: ACTION_CORPSE_CLEANUP_CARRY,
	},
}


static func begin_action(soldier, action_name: String, locks_ai: bool = false, animation_name: String = "") -> bool:
	if not is_instance_valid(soldier):
		return false
	var normalized_action := normalize_action_name(action_name)
	if normalized_action.is_empty():
		return false
	var normalized_animation := normalize_action_name(animation_name)
	if normalized_animation.is_empty():
		normalized_animation = get_default_animation_name(normalized_action)
	soldier.set_meta(ACTION_NAME_META, normalized_action)
	soldier.set_meta(ACTION_BUSY_META, true)
	soldier.set_meta(ACTION_AI_LOCK_META, locks_ai)
	soldier.set_meta(ACTION_ANIMATION_META, normalized_animation)
	return true


static func begin_known_action(soldier, action_name: String, animation_name: String = "") -> bool:
	var normalized_action := normalize_action_name(action_name)
	var definition := get_action_definition(normalized_action)
	return begin_action(
		soldier,
		normalized_action,
		bool(definition.get(ACTION_DEF_LOCKS_AI, false)),
		animation_name
	)


static func finish_action(soldier, action_name: String = "") -> bool:
	if not is_instance_valid(soldier):
		return false
	var normalized_action := normalize_action_name(action_name)
	if not normalized_action.is_empty() and get_action_name(soldier) != normalized_action:
		return false
	_clear_meta(soldier, ACTION_NAME_META)
	_clear_meta(soldier, ACTION_BUSY_META)
	_clear_meta(soldier, ACTION_AI_LOCK_META)
	_clear_meta(soldier, ACTION_ANIMATION_META)
	return true


static func begin_corpse_cleanup_action(soldier, action_name: String) -> bool:
	var normalized_action := normalize_action_name(action_name)
	if not CORPSE_CLEANUP_ACTIONS.has(normalized_action):
		normalized_action = ACTION_CORPSE_CLEANUP_APPROACH
	return begin_known_action(soldier, normalized_action)


static func finish_corpse_cleanup_action(soldier) -> bool:
	if not is_corpse_cleanup_action(soldier):
		return false
	return finish_action(soldier)


static func has_action(soldier, action_name: String = "") -> bool:
	if not is_instance_valid(soldier) or not soldier.has_meta(ACTION_NAME_META):
		return false
	var normalized_action := normalize_action_name(action_name)
	return normalized_action.is_empty() or get_action_name(soldier) == normalized_action


static func is_action_ai_locked(soldier) -> bool:
	return is_instance_valid(soldier) and bool(soldier.get_meta(ACTION_AI_LOCK_META, false)) == true


static func get_action_name(soldier) -> String:
	if not is_instance_valid(soldier):
		return ""
	return str(soldier.get_meta(ACTION_NAME_META, ""))


static func get_action_animation_name(soldier) -> String:
	if not is_instance_valid(soldier):
		return ""
	return str(soldier.get_meta(ACTION_ANIMATION_META, ""))


static func is_corpse_cleanup_action(soldier) -> bool:
	return CORPSE_CLEANUP_ACTIONS.has(get_action_name(soldier))


static func get_action_definition(action_name: String) -> Dictionary:
	var normalized_action := normalize_action_name(action_name)
	var definition: Dictionary = ACTION_DEFINITIONS.get(normalized_action, {})
	if definition.is_empty():
		return {
			ACTION_DEF_NAME: normalized_action,
			ACTION_DEF_FAMILY: "",
			ACTION_DEF_LOCKS_AI: false,
			ACTION_DEF_ANIMATION: normalized_action,
		}
	return definition.duplicate(true)


static func get_action_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for action_name in ACTION_DEFINITIONS.keys():
		var definition: Dictionary = ACTION_DEFINITIONS[action_name]
		rows.append(definition.duplicate(true))
	return rows


static func get_action_family(action_name: String) -> String:
	return str(get_action_definition(action_name).get(ACTION_DEF_FAMILY, ""))


static func get_default_animation_name(action_name: String) -> String:
	var normalized_action := normalize_action_name(action_name)
	var definition := get_action_definition(normalized_action)
	var animation_name := normalize_action_name(str(definition.get(ACTION_DEF_ANIMATION, normalized_action)))
	return animation_name if not animation_name.is_empty() else normalized_action


static func is_known_action(action_name: String) -> bool:
	return ACTION_DEFINITIONS.has(normalize_action_name(action_name))


static func get_or_create_carry_anchor(soldier) -> Node3D:
	if not is_instance_valid(soldier) or not (soldier is Node3D):
		return null
	if soldier.has_meta(CARRY_ANCHOR_META):
		var cached_anchor := soldier.get_meta(CARRY_ANCHOR_META) as Node3D
		if is_instance_valid(cached_anchor):
			return cached_anchor
	var soldier_node := soldier as Node3D
	var anchor := soldier_node.get_node_or_null(CARRY_ANCHOR_NAME) as Node3D
	if anchor == null:
		anchor = Node3D.new()
		anchor.name = CARRY_ANCHOR_NAME
		soldier_node.add_child(anchor)
	soldier.set_meta(CARRY_ANCHOR_META, anchor)
	configure_carry_anchor(soldier, 1.0)
	return anchor


static func configure_carry_anchor(
	soldier,
	side_sign: float = 1.0,
	forward_offset: float = DEFAULT_CARRY_FORWARD_OFFSET,
	side_offset: float = DEFAULT_CARRY_SIDE_OFFSET,
	height_offset: float = DEFAULT_CARRY_HEIGHT_OFFSET
) -> Node3D:
	var anchor := get_or_create_carry_anchor(soldier)
	if not is_instance_valid(anchor):
		return null
	var normalized_side := -1.0 if side_sign < 0.0 else 1.0
	anchor.position = Vector3(
		normalized_side * maxf(side_offset, 0.0),
		maxf(height_offset, 0.0),
		-maxf(forward_offset, 0.0)
	)
	anchor.rotation = Vector3.ZERO
	anchor.scale = Vector3.ONE
	return anchor


static func get_carry_anchor_global_position(soldier) -> Vector3:
	var anchor := get_or_create_carry_anchor(soldier)
	if is_instance_valid(anchor):
		return anchor.global_position
	if is_instance_valid(soldier) and soldier is Node3D:
		return (soldier as Node3D).global_position
	return Vector3.INF


static func get_carry_payload_definition(payload_kind: String = CARRY_PAYLOAD_KIND_GENERIC) -> Dictionary:
	var normalized_kind := normalize_payload_kind(payload_kind)
	var definition: Dictionary = CARRY_PAYLOAD_DEFINITIONS.get(normalized_kind, {})
	if definition.is_empty():
		normalized_kind = CARRY_PAYLOAD_KIND_GENERIC
		definition = CARRY_PAYLOAD_DEFINITIONS.get(CARRY_PAYLOAD_KIND_GENERIC, {})
	var resolved := definition.duplicate(true)
	resolved[PAYLOAD_DEF_KIND] = normalized_kind
	return resolved


static func get_carry_payload_offsets(payload_kind: String = CARRY_PAYLOAD_KIND_GENERIC, offset_overrides: Dictionary = {}) -> Dictionary:
	var definition := get_carry_payload_definition(payload_kind)
	var forward_offset := float(offset_overrides.get(PAYLOAD_DEF_FORWARD_OFFSET, definition.get(PAYLOAD_DEF_FORWARD_OFFSET, DEFAULT_CARRY_FORWARD_OFFSET)))
	var side_offset := float(offset_overrides.get(PAYLOAD_DEF_SIDE_OFFSET, definition.get(PAYLOAD_DEF_SIDE_OFFSET, DEFAULT_CARRY_SIDE_OFFSET)))
	var height_offset := float(offset_overrides.get(PAYLOAD_DEF_HEIGHT_OFFSET, definition.get(PAYLOAD_DEF_HEIGHT_OFFSET, DEFAULT_CARRY_HEIGHT_OFFSET)))
	return {
		PAYLOAD_DEF_FORWARD_OFFSET: maxf(forward_offset, 0.0),
		PAYLOAD_DEF_SIDE_OFFSET: maxf(side_offset, 0.0),
		PAYLOAD_DEF_HEIGHT_OFFSET: maxf(height_offset, 0.0),
	}


static func begin_typed_carry_payload(
	soldier,
	payload: Node3D,
	payload_kind: String = CARRY_PAYLOAD_KIND_GENERIC,
	side_sign: float = 1.0,
	offset_overrides: Dictionary = {}
) -> bool:
	var offsets := get_carry_payload_offsets(payload_kind, offset_overrides)
	return begin_carry_payload(
		soldier,
		payload,
		normalize_payload_kind(payload_kind),
		side_sign,
		float(offsets.get(PAYLOAD_DEF_FORWARD_OFFSET, DEFAULT_CARRY_FORWARD_OFFSET)),
		float(offsets.get(PAYLOAD_DEF_SIDE_OFFSET, DEFAULT_CARRY_SIDE_OFFSET)),
		float(offsets.get(PAYLOAD_DEF_HEIGHT_OFFSET, DEFAULT_CARRY_HEIGHT_OFFSET))
	)


static func begin_carry_payload(
	soldier,
	payload: Node3D,
	payload_kind: String = CARRY_PAYLOAD_KIND_GENERIC,
	side_sign: float = 1.0,
	forward_offset: float = DEFAULT_CARRY_FORWARD_OFFSET,
	side_offset: float = DEFAULT_CARRY_SIDE_OFFSET,
	height_offset: float = DEFAULT_CARRY_HEIGHT_OFFSET
) -> bool:
	if not is_instance_valid(soldier) or not is_instance_valid(payload):
		return false
	var anchor := configure_carry_anchor(soldier, side_sign, forward_offset, side_offset, height_offset)
	if not is_instance_valid(anchor):
		return false
	var normalized_kind := normalize_payload_kind(payload_kind)
	soldier.set_meta(CARRY_PAYLOAD_ID_META, payload.get_instance_id())
	soldier.set_meta(CARRY_PAYLOAD_KIND_META, normalized_kind)
	payload.set_meta(CARRY_PAYLOAD_OWNER_META, soldier.get_instance_id())
	payload.set_meta(CARRY_PAYLOAD_KIND_META, normalized_kind)
	return true


static func finish_carry_payload(soldier, payload: Node3D = null) -> void:
	if not is_instance_valid(soldier):
		return
	var payload_node := payload
	if not is_instance_valid(payload_node):
		payload_node = get_carry_payload(soldier)
	if soldier.has_meta(CARRY_PAYLOAD_ID_META):
		soldier.remove_meta(CARRY_PAYLOAD_ID_META)
	if soldier.has_meta(CARRY_PAYLOAD_KIND_META):
		soldier.remove_meta(CARRY_PAYLOAD_KIND_META)
	if is_instance_valid(payload_node):
		if payload_node.has_meta(CARRY_PAYLOAD_OWNER_META):
			payload_node.remove_meta(CARRY_PAYLOAD_OWNER_META)
		if payload_node.has_meta(CARRY_PAYLOAD_KIND_META):
			payload_node.remove_meta(CARRY_PAYLOAD_KIND_META)


static func get_carry_payload(soldier) -> Node3D:
	if not is_instance_valid(soldier) or not soldier.has_meta(CARRY_PAYLOAD_ID_META):
		return null
	return NodeContractHelper.get_instance_node3d(int(soldier.get_meta(CARRY_PAYLOAD_ID_META, 0)))


static func get_carry_payload_kind(soldier) -> String:
	if not is_instance_valid(soldier):
		return ""
	return str(soldier.get_meta(CARRY_PAYLOAD_KIND_META, ""))


static func apply_carry_payload_pickup(soldier, payload: Node3D, progress: float, start_position: Vector3, start_rotation: Vector3, target_rotation: Vector3) -> bool:
	if not is_instance_valid(soldier) or not is_instance_valid(payload):
		return false
	var anchor_position := get_carry_anchor_global_position(soldier)
	if anchor_position == Vector3.INF:
		return false
	var eased_t: float = smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	payload.global_position = start_position.lerp(anchor_position, eased_t)
	payload.rotation = _lerp_rotation(start_rotation, target_rotation, eased_t)
	return true


static func apply_carry_payload_follow(soldier, payload: Node3D, progress: float, start_rotation: Vector3, target_rotation: Vector3) -> bool:
	if not is_instance_valid(soldier) or not is_instance_valid(payload):
		return false
	var anchor_position := get_carry_anchor_global_position(soldier)
	if anchor_position == Vector3.INF:
		return false
	var eased_t: float = smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	payload.global_position = anchor_position
	payload.rotation = _lerp_rotation(start_rotation, target_rotation, eased_t)
	return true


static func normalize_action_name(action_name: String) -> String:
	return action_name.strip_edges().to_lower().replace(" ", "_")


static func normalize_payload_kind(payload_kind: String) -> String:
	var normalized_kind := normalize_action_name(payload_kind)
	return CARRY_PAYLOAD_KIND_GENERIC if normalized_kind.is_empty() else normalized_kind


static func _lerp_rotation(start_rotation: Vector3, target_rotation: Vector3, weight: float) -> Vector3:
	return Vector3(
		lerp_angle(start_rotation.x, target_rotation.x, weight),
		lerp_angle(start_rotation.y, target_rotation.y, weight),
		lerp_angle(start_rotation.z, target_rotation.z, weight)
	)


static func _clear_meta(soldier, meta_name: String) -> void:
	if soldier.has_meta(meta_name):
		soldier.remove_meta(meta_name)
