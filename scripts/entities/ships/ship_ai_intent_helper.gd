extends RefCounted
class_name ShipAIIntentHelper

const DEFAULT_STALE_FRAMES := 4
const KEY_DRIVER := "driver"
const KEY_TARGET_ID := "target_id"
const KEY_TARGET_DISTANCE := "target_distance"
const KEY_RANGE_INTENT := "range_intent"
const KEY_STANCE := "stance"
const KEY_PRESSURE_PHASE := "pressure_phase"
const KEY_PRESSURE := "pressure"
const KEY_NAV := "nav"
const KEY_WEAPON := "weapon"
const KEY_SPECIAL := "special"
const KEY_BOARDING := "boarding"
const KEY_SUPPORT := "support"
const KEY_LEGACY_CAPTURE := "legacy_capture"
const KEY_MODE := "mode"
const KEY_FRAME := "frame"
const KEY_REASON := "reason"
const KEY_DESIRED_POINT := "desired_point"
const KEY_HEADING_POINT := "heading_point"
const KEY_SPEED_MULT := "speed_mult"
const KEY_PERMIT_SPRINT := "permit_sprint"
const KEY_INTENT := "intent"


static func from_limbo_meta(ship: Node, target: Node = null, stale_frames: int = DEFAULT_STALE_FRAMES) -> Dictionary:
	if not _is_limbo_enabled(ship):
		return {}
	var intent := {
		KEY_DRIVER: "limbo",
		KEY_TARGET_ID: int(ship.get_meta(ShipAILimboKeys.META_TARGET_ID, 0)),
		KEY_TARGET_DISTANCE: float(ship.get_meta(ShipAILimboKeys.META_TARGET_DISTANCE, -1.0)),
		KEY_RANGE_INTENT: str(ship.get_meta(ShipAILimboKeys.META_INTENT, "")).strip_edges(),
		KEY_STANCE: str(ship.get_meta(ShipAILimboKeys.META_STANCE, "")).strip_edges(),
		KEY_PRESSURE_PHASE: str(ship.get_meta(ShipAILimboKeys.META_PRESSURE_PHASE, "")).strip_edges(),
		KEY_PRESSURE: clampf(float(ship.get_meta(ShipAILimboKeys.META_PRESSURE, 0.0)), 0.0, 1.0),
	}
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	var nav := get_limbo_navigation_intent(ship, target, stale_frames)
	if not nav.is_empty():
		intent[KEY_NAV] = nav
	var weapon := get_limbo_weapon_intent(ship, target_id, stale_frames)
	if not weapon.is_empty():
		intent[KEY_WEAPON] = weapon
	var special := get_limbo_special_intent(ship, target_id, stale_frames)
	if not special.is_empty():
		intent[KEY_SPECIAL] = special
	var boarding := get_limbo_boarding_intent(ship, target_id, stale_frames)
	if not boarding.is_empty():
		intent[KEY_BOARDING] = boarding
	var support := get_limbo_support_intent(ship, stale_frames)
	if not support.is_empty():
		intent[KEY_SUPPORT] = support
	var legacy_capture := get_limbo_legacy_capture_intent(ship, stale_frames)
	if not legacy_capture.is_empty():
		intent[KEY_LEGACY_CAPTURE] = legacy_capture
	return intent


static func get_limbo_navigation_intent(ship: Node, target: Node, stale_frames: int = DEFAULT_STALE_FRAMES) -> Dictionary:
	if not _is_limbo_enabled(ship) or not is_instance_valid(target):
		return {}
	var frame := int(ship.get_meta(ShipAILimboKeys.META_NAV_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return {}
	if int(ship.get_meta(ShipAILimboKeys.META_NAV_TARGET_ID, 0)) != target.get_instance_id():
		return {}
	var intent := {
		KEY_MODE: str(ship.get_meta(ShipAILimboKeys.META_NAV_MODE, "")).strip_edges(),
		KEY_FRAME: frame,
		KEY_TARGET_ID: target.get_instance_id(),
	}
	var desired_point: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT, null)
	if desired_point is Vector3:
		intent[KEY_DESIRED_POINT] = desired_point
	var heading_point: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_HEADING_POINT, null)
	if heading_point is Vector3:
		intent[KEY_HEADING_POINT] = heading_point
	var speed_mult: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_SPEED_MULT, null)
	if speed_mult != null:
		intent[KEY_SPEED_MULT] = float(speed_mult)
	var permit_sprint: Variant = ship.get_meta(ShipAILimboKeys.META_NAV_PERMIT_SPRINT, null)
	if permit_sprint != null:
		intent[KEY_PERMIT_SPRINT] = permit_sprint == true
	return intent


static func get_limbo_weapon_intent(ship: Node, target_id: int = 0, stale_frames: int = DEFAULT_STALE_FRAMES) -> Dictionary:
	if not _is_limbo_enabled(ship):
		return {}
	var frame := int(ship.get_meta(ShipAILimboKeys.META_WEAPON_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return {}
	var actual_target_id := int(ship.get_meta(ShipAILimboKeys.META_WEAPON_TARGET_ID, 0))
	if target_id != 0 and actual_target_id != 0 and actual_target_id != target_id:
		return {}
	return {
		KEY_INTENT: str(ship.get_meta(ShipAILimboKeys.META_WEAPON_INTENT, "")).strip_edges(),
		KEY_FRAME: frame,
		KEY_TARGET_ID: actual_target_id,
	}


static func get_limbo_special_intent(ship: Node, target_id: int = 0, stale_frames: int = DEFAULT_STALE_FRAMES) -> Dictionary:
	if not _is_limbo_enabled(ship):
		return {}
	var frame := int(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return {}
	var actual_target_id := int(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_TARGET_ID, 0))
	if target_id != 0 and actual_target_id != target_id:
		return {}
	return {
		KEY_INTENT: str(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT, "")).strip_edges(),
		KEY_FRAME: frame,
		KEY_TARGET_ID: actual_target_id,
		KEY_TARGET_DISTANCE: float(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_DISTANCE, -1.0)),
	}


static func get_limbo_boarding_intent(ship: Node, target_id: int = 0, stale_frames: int = DEFAULT_STALE_FRAMES) -> Dictionary:
	if not _is_limbo_enabled(ship):
		return {}
	var frame := int(ship.get_meta(ShipAILimboKeys.META_BOARDING_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return {}
	var actual_target_id := int(ship.get_meta(ShipAILimboKeys.META_BOARDING_TARGET_ID, 0))
	if target_id != 0 and actual_target_id != target_id:
		return {}
	return {
		KEY_INTENT: str(ship.get_meta(ShipAILimboKeys.META_BOARDING_INTENT, "")).strip_edges(),
		KEY_FRAME: frame,
		KEY_TARGET_ID: actual_target_id,
		KEY_TARGET_DISTANCE: float(ship.get_meta(ShipAILimboKeys.META_BOARDING_DISTANCE, -1.0)),
		"attempt_distance": float(ship.get_meta(ShipAILimboKeys.META_BOARDING_ATTEMPT_DISTANCE, -1.0)),
	}


static func get_limbo_support_intent(ship: Node, stale_frames: int = DEFAULT_STALE_FRAMES) -> Dictionary:
	if not _is_limbo_enabled(ship):
		return {}
	var frame := int(ship.get_meta(ShipAILimboKeys.META_SUPPORT_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return {}
	return {
		KEY_MODE: str(ship.get_meta(ShipAILimboKeys.META_SUPPORT_MODE, "")).strip_edges(),
		KEY_FRAME: frame,
		KEY_TARGET_ID: int(ship.get_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, 0)),
		KEY_REASON: str(ship.get_meta(ShipAILimboKeys.META_SUPPORT_REASON, "")).strip_edges(),
	}


static func get_limbo_legacy_capture_intent(ship: Node, stale_frames: int = DEFAULT_STALE_FRAMES) -> Dictionary:
	if not _is_limbo_enabled(ship):
		return {}
	var frame := int(ship.get_meta(ShipAILimboKeys.META_ALLY_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return {}
	return {
		KEY_MODE: str(ship.get_meta(ShipAILimboKeys.META_ALLY_MODE, "")).strip_edges(),
		KEY_FRAME: frame,
		KEY_TARGET_ID: int(ship.get_meta(ShipAILimboKeys.META_ALLY_TARGET_ID, 0)),
		KEY_REASON: str(ship.get_meta(ShipAILimboKeys.META_ALLY_REASON, "")).strip_edges(),
	}


static func allows_boarding_attempt(ship: Node, target: Node, stale_frames: int = DEFAULT_STALE_FRAMES) -> bool:
	if not _is_limbo_enabled(ship):
		return true
	var frame := int(ship.get_meta(ShipAILimboKeys.META_BOARDING_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return true
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	var boarding := get_limbo_boarding_intent(ship, target_id, stale_frames)
	return not boarding.is_empty() and str(boarding.get(KEY_INTENT, "")) == ShipAILimboKeys.BOARDING_READY


static func should_hold_weapon_fire(ship: Node, stale_frames: int = DEFAULT_STALE_FRAMES) -> bool:
	var weapon := get_limbo_weapon_intent(ship, 0, stale_frames)
	return str(weapon.get(KEY_INTENT, "")).strip_edges() == ShipAILimboKeys.WEAPON_HOLD_FIRE


static func allows_special_fire_pot(ship: Node, target: Node, stale_frames: int = DEFAULT_STALE_FRAMES) -> bool:
	if not _is_limbo_enabled(ship):
		return true
	var frame := int(ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, -1000000))
	if not _is_fresh(frame, stale_frames):
		return true
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	var special := get_limbo_special_intent(ship, target_id, stale_frames)
	if special.is_empty():
		return false
	var special_intent := str(special.get(KEY_INTENT, "")).strip_edges()
	return special_intent.is_empty() or special_intent == ShipAILimboKeys.SPECIAL_FIRE_POT_READY


static func _is_limbo_enabled(ship: Node) -> bool:
	return is_instance_valid(ship) and ship.get("limbo_ai_pilot_enabled") == true


static func _is_fresh(frame: int, stale_frames: int) -> bool:
	return Engine.get_physics_frames() - frame <= stale_frames
