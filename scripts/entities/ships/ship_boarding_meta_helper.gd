extends RefCounted
class_name ShipBoardingMetaHelper

const KEY_APPROACH_MODE := "boarding_approach_mode"
const KEY_CONTACT_MODE := "boarding_contact_mode"
const KEY_CONTACT_ANCHOR_LOCAL := "boarding_contact_anchor_local"
const KEY_HOLD_FORWARD := "boarding_hold_forward"
const KEY_LATCH_MODE := "boarding_latch_mode"
const KEY_LATCH_TARGET_ID := "boarding_latch_target_id"
const KEY_LATCH_TIMER := "boarding_latch_timer"
const KEY_MOTION_SETTLE_TIMER := "boarding_motion_settle_timer"
const KEY_PURPOSE := "boarding_purpose"
const KEY_SIDE_SIGN := "boarding_side_sign"
const KEY_SLOT_ID := "boarding_slot_id"
const KEY_TRANSFER_SUPPRESSED := "boarding_transfer_suppressed"
const KEY_POST_IMPACT_FOLLOW_TIMER := "post_impact_follow_timer"
const KEY_SUPPORT_DEBUG_MODE := "support_debug_mode"

const APPROACH_FRONT := "front"
const APPROACH_REAR := "rear"
const APPROACH_SIDE := "side"

const CONTACT_CLEANUP := "cleanup"
const CONTACT_HEAD_ON := "head_on"
const CONTACT_SIDE := "side"

const PURPOSE_AUTO_RAID := "auto_raid"
const PURPOSE_SUPPORT_ATTACK := "support_boarding"
const PURPOSE_SUPPORT_RESCUE := "support_rescue_boarding"

const SLOT_REAR_RECOVER_SIDE := "rear_recover_side"

const SUPPORT_DEBUG_ASSIST := "assist"
const SUPPORT_DEBUG_BOARDING := "boarding"
const SUPPORT_DEBUG_TRAIL := "trail"


static func get_contact_mode(ship: Node, fallback: String = "") -> String:
	return get_string(ship, KEY_CONTACT_MODE, fallback)


static func set_contact_mode(ship: Node, mode: String) -> void:
	set_meta_value(ship, KEY_CONTACT_MODE, mode)


static func get_approach_mode(ship: Node, fallback: String = "") -> String:
	return get_string(ship, KEY_APPROACH_MODE, fallback)


static func set_approach_mode(ship: Node, mode: String) -> void:
	set_meta_value(ship, KEY_APPROACH_MODE, mode)


static func get_boarding_purpose(ship: Node, fallback: String = "") -> String:
	return get_string(ship, KEY_PURPOSE, fallback)


static func set_boarding_purpose(ship: Node, purpose: String) -> void:
	set_meta_value(ship, KEY_PURPOSE, purpose)


static func is_boarding_purpose(ship: Node, purpose: String) -> bool:
	return get_boarding_purpose(ship) == purpose


static func get_support_boarding_purpose(is_rescue_boarding: bool) -> String:
	return PURPOSE_SUPPORT_RESCUE if is_rescue_boarding else PURPOSE_SUPPORT_ATTACK


static func get_side_sign(ship: Node, fallback: float = 0.0) -> float:
	if not is_instance_valid(ship):
		return fallback
	return float(ship.get_meta(KEY_SIDE_SIGN, fallback))


static func set_side_sign(ship: Node, side_sign: float) -> void:
	set_meta_value(ship, KEY_SIDE_SIGN, side_sign)


static func get_slot_id(ship: Node, fallback: String = "") -> String:
	return get_string(ship, KEY_SLOT_ID, fallback)


static func set_slot_id(ship: Node, slot_id: String) -> void:
	set_meta_value(ship, KEY_SLOT_ID, slot_id)


static func get_hold_forward(ship: Node, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if not is_instance_valid(ship):
		return fallback
	var value: Variant = ship.get_meta(KEY_HOLD_FORWARD, fallback)
	return value if value is Vector3 else fallback


static func set_hold_forward(ship: Node, hold_forward: Vector3) -> void:
	set_meta_value(ship, KEY_HOLD_FORWARD, hold_forward)


static func get_contact_anchor_local(ship: Node, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if not is_instance_valid(ship):
		return fallback
	var value: Variant = ship.get_meta(KEY_CONTACT_ANCHOR_LOCAL, fallback)
	return value if value is Vector3 else fallback


static func set_contact_anchor_local(ship: Node, anchor_local: Vector3) -> void:
	set_meta_value(ship, KEY_CONTACT_ANCHOR_LOCAL, anchor_local)


static func has_contact_anchor(ship: Node) -> bool:
	return is_instance_valid(ship) and ship.has_meta(KEY_CONTACT_ANCHOR_LOCAL)


static func get_motion_settle_timer(ship: Node, fallback: float = 0.0) -> float:
	if not is_instance_valid(ship):
		return fallback
	return float(ship.get_meta(KEY_MOTION_SETTLE_TIMER, fallback))


static func set_motion_settle_timer(ship: Node, timer: float) -> void:
	set_meta_value(ship, KEY_MOTION_SETTLE_TIMER, timer)


static func get_latch_mode(ship: Node, fallback: String = "") -> String:
	return get_string(ship, KEY_LATCH_MODE, fallback)


static func set_latch(ship: Node, target_id: int, timer: float, mode: String) -> void:
	set_meta_value(ship, KEY_LATCH_TARGET_ID, target_id)
	set_meta_value(ship, KEY_LATCH_TIMER, timer)
	set_meta_value(ship, KEY_LATCH_MODE, mode)


static func get_latch_target_id(ship: Node, fallback: int = 0) -> int:
	if not is_instance_valid(ship):
		return fallback
	return int(ship.get_meta(KEY_LATCH_TARGET_ID, fallback))


static func get_latch_timer(ship: Node, fallback: float = 0.0) -> float:
	if not is_instance_valid(ship):
		return fallback
	return float(ship.get_meta(KEY_LATCH_TIMER, fallback))


static func set_latch_timer(ship: Node, timer: float) -> void:
	set_meta_value(ship, KEY_LATCH_TIMER, timer)


static func is_transfer_suppressed(ship: Node) -> bool:
	return is_instance_valid(ship) and ship.get_meta(KEY_TRANSFER_SUPPRESSED, false) == true


static func set_transfer_suppressed(ship: Node, suppressed: bool) -> void:
	set_meta_value(ship, KEY_TRANSFER_SUPPRESSED, suppressed)


static func get_post_impact_follow_timer(ship: Node, fallback: float = 0.0) -> float:
	if not is_instance_valid(ship):
		return fallback
	return float(ship.get_meta(KEY_POST_IMPACT_FOLLOW_TIMER, fallback))


static func set_post_impact_follow_timer(ship: Node, timer: float) -> void:
	set_meta_value(ship, KEY_POST_IMPACT_FOLLOW_TIMER, timer)


static func set_support_debug_mode(ship: Node, mode: String) -> void:
	set_meta_value(ship, KEY_SUPPORT_DEBUG_MODE, mode)


static func get_string(ship: Node, key: String, fallback: String = "") -> String:
	if not is_instance_valid(ship):
		return fallback
	return str(ship.get_meta(key, fallback))


static func set_meta_value(ship: Node, key: String, value: Variant) -> void:
	if is_instance_valid(ship):
		ship.set_meta(key, value)


static func remove_meta_key(ship: Node, key: String) -> void:
	if is_instance_valid(ship) and ship.has_meta(key):
		ship.remove_meta(key)


static func clear_navigation_meta(ship: Node) -> void:
	remove_meta_key(ship, KEY_SLOT_ID)
	remove_meta_key(ship, KEY_SIDE_SIGN)
	remove_meta_key(ship, KEY_APPROACH_MODE)


static func clear_boarding_link_meta(ship: Node) -> void:
	remove_meta_key(ship, KEY_CONTACT_MODE)
	remove_meta_key(ship, KEY_HOLD_FORWARD)
	remove_meta_key(ship, KEY_CONTACT_ANCHOR_LOCAL)
	remove_meta_key(ship, KEY_MOTION_SETTLE_TIMER)
	remove_meta_key(ship, KEY_PURPOSE)
	remove_meta_key(ship, KEY_TRANSFER_SUPPRESSED)


static func clear_latch_meta(ship: Node) -> void:
	remove_meta_key(ship, KEY_LATCH_TARGET_ID)
	remove_meta_key(ship, KEY_LATCH_TIMER)
	remove_meta_key(ship, KEY_LATCH_MODE)
