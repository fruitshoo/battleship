extends Node
# @scene_contract_encapsulated

const ShipScript = preload("res://scripts/test/chaser_isolation_boarding_collision.gd")


class MockMast:
	extends Node

	var sail_damage: float = 0.0
	var hull_wear_damage: float = 0.0

	func add_sail_damage(amount: float) -> void:
		sail_damage = clampf(sail_damage + maxf(amount, 0.0), 0.0, 1.0)

	func repair_sail_damage(amount: float) -> void:
		sail_damage = clampf(sail_damage - maxf(amount, 0.0), 0.0, 1.0)

	func get_sail_damage() -> float:
		return sail_damage

	func set_sail_angle(_angle: float) -> void:
		pass

	func set_hull_wear_damage(value: float) -> void:
		hull_wear_damage = clampf(value, 0.0, 1.0)

	func get_hull_wear_damage() -> float:
		return hull_wear_damage


class MockHud:
	extends Node

	var messages: Array[String] = []

	func show_message(message: String, _duration: float = 1.5) -> void:
		messages.append(message)


func _ready() -> void:
	var failures: Array[String] = []
	_verify_rigging_field_repair_is_disabled(failures)
	_verify_rudder_damage_is_disabled(failures)
	_verify_hull_health_drives_sail_wear_visual_floor(failures)
	if failures.is_empty():
		print("[ShipDamageContract] ok")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[ShipDamageContract] %s" % failure)
	get_tree().quit(1)


func _verify_rigging_field_repair_is_disabled(failures: Array[String]) -> void:
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
	if float(ship.get("_rigging_repair_cooldown")) > 0.0:
		failures.append("disabled rudder damage scheduled rigging field repair")
	if not is_equal_approx(float(ship.get("rudder_health")), 100.0):
		failures.append("disabled rudder damage should keep full rudder health")

	ship.set("_rigging_repair_cooldown", 0.0)
	mast.sail_damage = 0.0
	ship.call("_apply_sail_damage_from_hit", 30.0, "cannon")
	if mast.get_sail_damage() > 0.0:
		failures.append("disabled sail damage mutated the mock mast")
	if float(ship.get("_rigging_repair_cooldown")) > 0.0:
		failures.append("disabled sail damage scheduled rigging field repair")

	ship.set("rudder_health", 10.0)
	mast.sail_damage = 0.9
	ship.call("_mark_rigging_damage_for_repair")
	ship.call("_update_rigging_recovery", 30.0)
	if not is_equal_approx(float(ship.get("rudder_health")), 10.0):
		failures.append("disabled rigging repair changed rudder health")
	if not is_equal_approx(mast.get_sail_damage(), 0.9):
		failures.append("disabled rigging repair changed sail damage")
	if hud.messages.has("응급 수리 중") or hud.messages.has("응급 수리 완료"):
		failures.append("disabled rigging repair showed emergency repair feedback")

	ship.set("rudder_health", 10.0)
	mast.sail_damage = 0.9
	ship.set("is_burning", true)
	ship.call("_update_rigging_recovery", 5.0)
	if not is_equal_approx(float(ship.get("rudder_health")), 10.0) or not is_equal_approx(mast.get_sail_damage(), 0.9):
		failures.append("rigging field repair ran while the ship was burning")

	ship.free()


func _verify_hull_health_drives_sail_wear_visual_floor(failures: Array[String]) -> void:
	var ship: Node = ShipScript.new()
	add_child(ship)
	ship.set("max_hull_hp", 200.0)
	ship.set("hull_hp", 80.0)
	ship.set("hull_sail_wear_enabled", true)
	ship.set("hull_sail_wear_max_damage", 0.5)
	ship.set("hull_sail_wear_curve", 1.0)
	var mast := MockMast.new()
	ship.add_child(mast)
	var test_masts: Array[Node] = []
	test_masts.append(mast)
	ship.set("masts", test_masts)

	ship.call("_update_sail_visual")
	if absf(mast.get_hull_wear_damage() - 0.3) > 0.001:
		failures.append("hull health did not drive sail visual wear: %.3f" % mast.get_hull_wear_damage())
	if mast.get_sail_damage() > 0.001:
		failures.append("hull-driven sail wear should not mutate rigging damage: %.3f" % mast.get_sail_damage())

	ship.set("hull_hp", 200.0)
	ship.call("_update_sail_visual")
	if mast.get_hull_wear_damage() > 0.001:
		failures.append("full hull health did not clear sail visual wear floor: %.3f" % mast.get_hull_wear_damage())

	ship.free()


func _verify_rudder_damage_is_disabled(failures: Array[String]) -> void:
	var ship: Node = ShipScript.new()
	add_child(ship)
	ship.set("rudder_max_health", 100.0)
	ship.set("rudder_health", 100.0)

	var stern_hit: Vector3 = ship.global_position + Vector3.BACK * 12.0
	ship.call("_apply_rudder_damage_from_hit", 40.0, stern_hit, "cannon")
	if not is_equal_approx(float(ship.get("rudder_health")), 100.0):
		failures.append("standard cannon hits should not damage rudder control")

	ship.call("_apply_rudder_damage_from_hit", 40.0, stern_hit, "chain_shot")
	if not is_equal_approx(float(ship.get("rudder_health")), 100.0):
		failures.append("chain shot should not damage rudder control")

	var baseline_turn_mult: float = float(ship.call("get_rudder_turn_multiplier"))
	var baseline_response_mult: float = float(ship.call("get_rudder_response_multiplier"))
	ship.set("rudder_health", 0.0)
	var turn_mult: float = float(ship.call("get_rudder_turn_multiplier"))
	var response_mult: float = float(ship.call("get_rudder_response_multiplier"))
	if absf(turn_mult - baseline_turn_mult) > 0.001:
		failures.append("disabled rudder damage should not change turn authority: %.3f -> %.3f" % [baseline_turn_mult, turn_mult])
	if absf(response_mult - baseline_response_mult) > 0.001:
		failures.append("disabled rudder damage should not change response authority: %.3f -> %.3f" % [baseline_response_mult, response_mult])

	ship.free()
