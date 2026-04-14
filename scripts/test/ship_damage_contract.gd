extends Node

const ShipScript = preload("res://scripts/test/chaser_isolation_boarding_collision.gd")


class MockMast:
	extends Node

	var sail_damage: float = 0.0

	func add_sail_damage(amount: float) -> void:
		sail_damage = clampf(sail_damage + maxf(amount, 0.0), 0.0, 1.0)

	func repair_sail_damage(amount: float) -> void:
		sail_damage = clampf(sail_damage - maxf(amount, 0.0), 0.0, 1.0)

	func get_sail_damage() -> float:
		return sail_damage


class MockHud:
	extends Node

	var messages: Array[String] = []

	func show_message(message: String, _duration: float = 1.5) -> void:
		messages.append(message)


func _ready() -> void:
	var failures: Array[String] = []
	_verify_rigging_field_repair_waits_then_recovers(failures)
	if failures.is_empty():
		print("[ShipDamageContract] ok")
		return
	for failure in failures:
		push_error("[ShipDamageContract] %s" % failure)
	get_tree().quit(1)


func _verify_rigging_field_repair_waits_then_recovers(failures: Array[String]) -> void:
	var ship: Node = ShipScript.new()
	add_child(ship)
	var hud := MockHud.new()
	add_child(hud)
	ship.set("_cached_hud", hud)
	ship.set_meta("show_rigging_repair_feedback", true)
	var mast := MockMast.new()
	ship.add_child(mast)
	var test_masts: Array[Node] = []
	test_masts.append(mast)
	ship.set("masts", test_masts)
	ship.set("rigging_repair_delay", 2.0)
	ship.set("rigging_repair_target_ratio", 0.65)
	ship.set("sail_field_repair_rate", 1.0)
	ship.set("rudder_field_repair_rate", 200.0)
	ship.set("rudder_max_health", 100.0)
	ship.set("rudder_health", 10.0)
	mast.sail_damage = 0.9

	ship.set("_rigging_repair_cooldown", 0.0)
	ship.call("apply_rudder_damage", 20.0)
	if float(ship.get("_rigging_repair_cooldown")) <= 0.0:
		failures.append("rudder damage did not schedule rigging field repair")

	ship.set("_rigging_repair_cooldown", 0.0)
	mast.sail_damage = 0.0
	ship.call("_apply_sail_damage_from_hit", 30.0, "cannon")
	if mast.get_sail_damage() <= 0.0:
		failures.append("sail damage fixture did not damage the mock mast")
	if float(ship.get("_rigging_repair_cooldown")) <= 0.0:
		failures.append("sail damage did not schedule rigging field repair")

	ship.set("rudder_health", 10.0)
	mast.sail_damage = 0.9
	ship.call("_mark_rigging_damage_for_repair")
	ship.call("_update_rigging_recovery", 1.0)
	if not is_equal_approx(float(ship.get("rudder_health")), 10.0):
		failures.append("rigging field repair started before its delay elapsed")
	if not is_equal_approx(mast.get_sail_damage(), 0.9):
		failures.append("sail field repair started before its delay elapsed")

	ship.call("_update_rigging_recovery", 1.1)
	ship.call("_update_rigging_recovery", 30.0)
	if float(ship.get("rudder_health")) < 64.9:
		failures.append("rudder field repair did not recover to emergency function")
	if float(ship.get("rudder_health")) > 65.1:
		failures.append("rudder field repair exceeded the emergency repair cap")
	if mast.get_sail_damage() > 0.351:
		failures.append("sail field repair did not recover to emergency function: %.3f" % mast.get_sail_damage())
	if mast.get_sail_damage() < 0.349:
		failures.append("sail field repair exceeded the emergency repair cap: %.3f" % mast.get_sail_damage())
	if not hud.messages.has("응급 수리 중"):
		failures.append("rigging field repair did not show active feedback")
	if not hud.messages.has("응급 수리 완료"):
		failures.append("rigging field repair did not show completion feedback")

	ship.set("rudder_health", 10.0)
	mast.sail_damage = 0.9
	ship.set("is_burning", true)
	ship.call("_update_rigging_recovery", 5.0)
	if not is_equal_approx(float(ship.get("rudder_health")), 10.0) or not is_equal_approx(mast.get_sail_damage(), 0.9):
		failures.append("rigging field repair ran while the ship was burning")

	ship.free()
