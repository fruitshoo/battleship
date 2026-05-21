extends Node

const ShipAIIntentHelper = preload("res://scripts/entities/ships/ship_ai_intent_helper.gd")

var _failures: Array[String] = []


class MockShip:
	extends Node3D

	var limbo_ai_pilot_enabled := true


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	var ship := MockShip.new()
	ship.name = "IntentContractShip"
	add_child(ship)
	var target := Node3D.new()
	target.name = "IntentContractTarget"
	add_child(target)
	var other_target := Node3D.new()
	other_target.name = "IntentContractOtherTarget"
	add_child(other_target)
	await get_tree().process_frame

	_verify_disabled_limbo_is_safe(ship, target)
	ship.limbo_ai_pilot_enabled = true
	_verify_base_snapshot(ship)
	_verify_navigation_intent(ship, target, other_target)
	_verify_weapon_intent(ship)
	_verify_special_intent(ship, target, other_target)
	_verify_boarding_intent(ship, target, other_target)
	_verify_support_intents(ship, target)

	ship.queue_free()
	target.queue_free()
	other_target.queue_free()
	await get_tree().process_frame

	if _failures.is_empty():
		print("[ShipAIIntentHelperContract] ok")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[ShipAIIntentHelperContract] %s" % failure)
	get_tree().quit(1)


func _verify_disabled_limbo_is_safe(ship: MockShip, target: Node3D) -> void:
	ship.limbo_ai_pilot_enabled = false
	ship.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, ShipAILimboKeys.WEAPON_HOLD_FIRE)
	ship.set_meta(ShipAILimboKeys.META_WEAPON_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_BOARDING_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, Engine.get_physics_frames())
	if not ShipAIIntentHelper.from_limbo_meta(ship, target).is_empty():
		_failures.append("disabled LimboAI should return an empty intent snapshot")
	if ShipAIIntentHelper.should_hold_weapon_fire(ship):
		_failures.append("disabled LimboAI should not hold launcher fire")
	if not ShipAIIntentHelper.allows_boarding_attempt(ship, target):
		_failures.append("disabled LimboAI should allow legacy boarding fallback")
	if not ShipAIIntentHelper.allows_special_fire_pot(ship, target):
		_failures.append("disabled LimboAI should allow legacy special fallback")
	ship.limbo_ai_pilot_enabled = true


func _verify_base_snapshot(ship: MockShip) -> void:
	ship.set_meta(ShipAILimboKeys.META_TARGET_ID, 42)
	ship.set_meta(ShipAILimboKeys.META_TARGET_DISTANCE, 18.5)
	ship.set_meta(ShipAILimboKeys.META_INTENT, ShipAILimboKeys.INTENT_ENGAGE)
	ship.set_meta(ShipAILimboKeys.META_STANCE, ShipAILimboKeys.STANCE_ORBIT_PRESSURE)
	ship.set_meta(ShipAILimboKeys.META_PRESSURE_PHASE, ShipAILimboKeys.PHASE_DAMAGED)
	ship.set_meta(ShipAILimboKeys.META_PRESSURE, 2.0)
	var intent := ShipAIIntentHelper.from_limbo_meta(ship)
	_expect_eq(intent.get(ShipAIIntentHelper.KEY_DRIVER, ""), "limbo", "base snapshot driver")
	_expect_eq(int(intent.get(ShipAIIntentHelper.KEY_TARGET_ID, 0)), 42, "base snapshot target id")
	_expect_near(float(intent.get(ShipAIIntentHelper.KEY_TARGET_DISTANCE, 0.0)), 18.5, 0.001, "base snapshot target distance")
	_expect_eq(str(intent.get(ShipAIIntentHelper.KEY_RANGE_INTENT, "")), ShipAILimboKeys.INTENT_ENGAGE, "base snapshot range intent")
	_expect_eq(str(intent.get(ShipAIIntentHelper.KEY_STANCE, "")), ShipAILimboKeys.STANCE_ORBIT_PRESSURE, "base snapshot stance")
	_expect_eq(str(intent.get(ShipAIIntentHelper.KEY_PRESSURE_PHASE, "")), ShipAILimboKeys.PHASE_DAMAGED, "base snapshot pressure phase")
	_expect_near(float(intent.get(ShipAIIntentHelper.KEY_PRESSURE, 0.0)), 1.0, 0.001, "base snapshot pressure clamp")


func _verify_navigation_intent(ship: MockShip, target: Node3D, other_target: Node3D) -> void:
	_clear_nav_meta(ship)
	var desired_point := Vector3(3.0, 0.0, -8.0)
	var heading_point := Vector3(7.0, 0.0, -2.0)
	ship.set_meta(ShipAILimboKeys.META_NAV_TARGET_ID, target.get_instance_id())
	ship.set_meta(ShipAILimboKeys.META_NAV_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT, desired_point)
	ship.set_meta(ShipAILimboKeys.META_NAV_HEADING_POINT, heading_point)
	ship.set_meta(ShipAILimboKeys.META_NAV_SPEED_MULT, 1.35)
	ship.set_meta(ShipAILimboKeys.META_NAV_PERMIT_SPRINT, false)
	ship.set_meta(ShipAILimboKeys.META_NAV_MODE, "limbo_close")
	var nav := ShipAIIntentHelper.get_limbo_navigation_intent(ship, target)
	_expect_eq(nav.get(ShipAIIntentHelper.KEY_MODE, ""), "limbo_close", "navigation mode")
	_expect_eq(nav.get(ShipAIIntentHelper.KEY_TARGET_ID, 0), target.get_instance_id(), "navigation target id")
	_expect_vec3(nav.get(ShipAIIntentHelper.KEY_DESIRED_POINT, Vector3.ZERO), desired_point, "navigation desired point")
	_expect_vec3(nav.get(ShipAIIntentHelper.KEY_HEADING_POINT, Vector3.ZERO), heading_point, "navigation heading point")
	_expect_near(float(nav.get(ShipAIIntentHelper.KEY_SPEED_MULT, 0.0)), 1.35, 0.001, "navigation speed mult")
	_expect_eq(nav.get(ShipAIIntentHelper.KEY_PERMIT_SPRINT, true), false, "navigation sprint flag")
	if not ShipAIIntentHelper.get_limbo_navigation_intent(ship, other_target).is_empty():
		_failures.append("navigation intent should reject target mismatch")
	ship.set_meta(ShipAILimboKeys.META_NAV_FRAME, Engine.get_physics_frames() - ShipAIIntentHelper.DEFAULT_STALE_FRAMES - 2)
	if not ShipAIIntentHelper.get_limbo_navigation_intent(ship, target).is_empty():
		_failures.append("navigation intent should reject stale metadata")


func _verify_weapon_intent(ship: MockShip) -> void:
	_clear_weapon_meta(ship)
	if ShipAIIntentHelper.should_hold_weapon_fire(ship):
		_failures.append("missing weapon intent should not hold fire")
	ship.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, ShipAILimboKeys.WEAPON_HOLD_FIRE)
	ship.set_meta(ShipAILimboKeys.META_WEAPON_FRAME, Engine.get_physics_frames())
	if not ShipAIIntentHelper.should_hold_weapon_fire(ship):
		_failures.append("fresh hold-fire weapon intent should hold fire")
	ship.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, ShipAILimboKeys.WEAPON_BROADSIDE_READY)
	if ShipAIIntentHelper.should_hold_weapon_fire(ship):
		_failures.append("fresh broadside weapon intent should not hold fire")
	ship.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, ShipAILimboKeys.WEAPON_HOLD_FIRE)
	ship.set_meta(ShipAILimboKeys.META_WEAPON_FRAME, Engine.get_physics_frames() - ShipAIIntentHelper.DEFAULT_STALE_FRAMES - 2)
	if ShipAIIntentHelper.should_hold_weapon_fire(ship):
		_failures.append("stale hold-fire weapon intent should not hold fire")


func _verify_special_intent(ship: MockShip, target: Node3D, other_target: Node3D) -> void:
	_clear_special_meta(ship)
	if not ShipAIIntentHelper.allows_special_fire_pot(ship, target):
		_failures.append("missing special intent should allow legacy special fallback")
	_set_special_meta(ship, target, ShipAILimboKeys.SPECIAL_FIRE_POT_READY)
	if not ShipAIIntentHelper.allows_special_fire_pot(ship, target):
		_failures.append("fire-pot ready special intent should allow special attack")
	if ShipAIIntentHelper.allows_special_fire_pot(ship, other_target):
		_failures.append("fresh special target mismatch should block special attack")
	_set_special_meta(ship, target, ShipAILimboKeys.SPECIAL_HOLD)
	if ShipAIIntentHelper.allows_special_fire_pot(ship, target):
		_failures.append("fresh special hold intent should block special attack")
	_set_special_meta(ship, target, "")
	if not ShipAIIntentHelper.allows_special_fire_pot(ship, target):
		_failures.append("fresh empty special intent should preserve legacy special fallback")
	ship.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, Engine.get_physics_frames() - ShipAIIntentHelper.DEFAULT_STALE_FRAMES - 2)
	if not ShipAIIntentHelper.allows_special_fire_pot(ship, target):
		_failures.append("stale special intent should allow legacy special fallback")


func _verify_boarding_intent(ship: MockShip, target: Node3D, other_target: Node3D) -> void:
	_clear_boarding_meta(ship)
	if not ShipAIIntentHelper.allows_boarding_attempt(ship, target):
		_failures.append("missing boarding intent should allow legacy boarding fallback")
	_set_boarding_meta(ship, target, ShipAILimboKeys.BOARDING_READY)
	if not ShipAIIntentHelper.allows_boarding_attempt(ship, target):
		_failures.append("fresh boarding-ready intent should allow boarding")
	if ShipAIIntentHelper.allows_boarding_attempt(ship, other_target):
		_failures.append("fresh boarding target mismatch should block boarding")
	_set_boarding_meta(ship, target, ShipAILimboKeys.BOARDING_APPROACH)
	if ShipAIIntentHelper.allows_boarding_attempt(ship, target):
		_failures.append("fresh boarding-approach intent should block boarding")
	ship.set_meta(ShipAILimboKeys.META_BOARDING_FRAME, Engine.get_physics_frames() - ShipAIIntentHelper.DEFAULT_STALE_FRAMES - 2)
	if not ShipAIIntentHelper.allows_boarding_attempt(ship, target):
		_failures.append("stale boarding intent should allow legacy boarding fallback")


func _verify_support_intents(ship: MockShip, target: Node3D) -> void:
	_clear_support_meta(ship)
	_clear_legacy_capture_meta(ship)
	if not ShipAIIntentHelper.get_limbo_support_intent(ship).is_empty():
		_failures.append("missing support intent should be empty")
	if not ShipAIIntentHelper.get_limbo_legacy_capture_intent(ship).is_empty():
		_failures.append("missing legacy capture intent should be empty")
	ship.set_meta(ShipAILimboKeys.META_SUPPORT_MODE, ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT)
	ship.set_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, target.get_instance_id())
	ship.set_meta(ShipAILimboKeys.META_SUPPORT_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_SUPPORT_REASON, "contract_support")
	var support := ShipAIIntentHelper.get_limbo_support_intent(ship)
	_expect_eq(support.get(ShipAIIntentHelper.KEY_MODE, ""), ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT, "support mode")
	_expect_eq(int(support.get(ShipAIIntentHelper.KEY_TARGET_ID, 0)), target.get_instance_id(), "support target id")
	_expect_eq(support.get(ShipAIIntentHelper.KEY_REASON, ""), "contract_support", "support reason")
	ship.set_meta(ShipAILimboKeys.META_SUPPORT_FRAME, Engine.get_physics_frames() - ShipAIIntentHelper.DEFAULT_STALE_FRAMES - 2)
	if not ShipAIIntentHelper.get_limbo_support_intent(ship).is_empty():
		_failures.append("stale support intent should be empty")
	ship.set_meta(ShipAILimboKeys.META_ALLY_MODE, ShipAILimboKeys.ALLY_MODE_GUARD_THREAT)
	ship.set_meta(ShipAILimboKeys.META_ALLY_TARGET_ID, target.get_instance_id())
	ship.set_meta(ShipAILimboKeys.META_ALLY_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_ALLY_REASON, "contract_legacy")
	var legacy_capture := ShipAIIntentHelper.get_limbo_legacy_capture_intent(ship)
	_expect_eq(legacy_capture.get(ShipAIIntentHelper.KEY_MODE, ""), ShipAILimboKeys.ALLY_MODE_GUARD_THREAT, "legacy capture mode")
	_expect_eq(int(legacy_capture.get(ShipAIIntentHelper.KEY_TARGET_ID, 0)), target.get_instance_id(), "legacy capture target id")
	_expect_eq(legacy_capture.get(ShipAIIntentHelper.KEY_REASON, ""), "contract_legacy", "legacy capture reason")
	ship.set_meta(ShipAILimboKeys.META_ALLY_FRAME, Engine.get_physics_frames() - ShipAIIntentHelper.DEFAULT_STALE_FRAMES - 2)
	if not ShipAIIntentHelper.get_limbo_legacy_capture_intent(ship).is_empty():
		_failures.append("stale legacy capture intent should be empty")


func _set_special_meta(ship: MockShip, target: Node3D, special_intent: String) -> void:
	ship.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT, special_intent)
	ship.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_TARGET_ID, target.get_instance_id())
	ship.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_DISTANCE, 10.0)


func _set_boarding_meta(ship: MockShip, target: Node3D, boarding_intent: String) -> void:
	ship.set_meta(ShipAILimboKeys.META_BOARDING_INTENT, boarding_intent)
	ship.set_meta(ShipAILimboKeys.META_BOARDING_TARGET_ID, target.get_instance_id())
	ship.set_meta(ShipAILimboKeys.META_BOARDING_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_BOARDING_DISTANCE, 8.0)
	ship.set_meta(ShipAILimboKeys.META_BOARDING_ATTEMPT_DISTANCE, 9.0)


func _clear_nav_meta(ship: MockShip) -> void:
	for key in [
		ShipAILimboKeys.META_NAV_TARGET_ID,
		ShipAILimboKeys.META_NAV_FRAME,
		ShipAILimboKeys.META_NAV_DESIRED_POINT,
		ShipAILimboKeys.META_NAV_HEADING_POINT,
		ShipAILimboKeys.META_NAV_SPEED_MULT,
		ShipAILimboKeys.META_NAV_PERMIT_SPRINT,
		ShipAILimboKeys.META_NAV_MODE,
	]:
		if ship.has_meta(key):
			ship.remove_meta(key)


func _clear_weapon_meta(ship: MockShip) -> void:
	for key in [
		ShipAILimboKeys.META_WEAPON_INTENT,
		ShipAILimboKeys.META_WEAPON_TARGET_ID,
		ShipAILimboKeys.META_WEAPON_FRAME,
	]:
		if ship.has_meta(key):
			ship.remove_meta(key)


func _clear_special_meta(ship: MockShip) -> void:
	for key in [
		ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT,
		ShipAILimboKeys.META_SPECIAL_ATTACK_TARGET_ID,
		ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME,
		ShipAILimboKeys.META_SPECIAL_ATTACK_DISTANCE,
	]:
		if ship.has_meta(key):
			ship.remove_meta(key)


func _clear_boarding_meta(ship: MockShip) -> void:
	for key in [
		ShipAILimboKeys.META_BOARDING_INTENT,
		ShipAILimboKeys.META_BOARDING_TARGET_ID,
		ShipAILimboKeys.META_BOARDING_FRAME,
		ShipAILimboKeys.META_BOARDING_DISTANCE,
		ShipAILimboKeys.META_BOARDING_ATTEMPT_DISTANCE,
	]:
		if ship.has_meta(key):
			ship.remove_meta(key)


func _clear_support_meta(ship: MockShip) -> void:
	for key in [
		ShipAILimboKeys.META_SUPPORT_MODE,
		ShipAILimboKeys.META_SUPPORT_TARGET_ID,
		ShipAILimboKeys.META_SUPPORT_FRAME,
		ShipAILimboKeys.META_SUPPORT_REASON,
	]:
		if ship.has_meta(key):
			ship.remove_meta(key)


func _clear_legacy_capture_meta(ship: MockShip) -> void:
	for key in [
		ShipAILimboKeys.META_ALLY_MODE,
		ShipAILimboKeys.META_ALLY_TARGET_ID,
		ShipAILimboKeys.META_ALLY_FRAME,
		ShipAILimboKeys.META_ALLY_REASON,
	]:
		if ship.has_meta(key):
			ship.remove_meta(key)


func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures.append("%s mismatch: %s expected %s" % [label, str(actual), str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s mismatch: %.4f expected %.4f" % [label, actual, expected])


func _expect_vec3(actual: Variant, expected: Vector3, label: String) -> void:
	if not (actual is Vector3):
		_failures.append("%s is not Vector3: %s" % [label, str(actual)])
		return
	if actual.distance_to(expected) > 0.001:
		_failures.append("%s mismatch: %s expected %s" % [label, str(actual), str(expected)])
