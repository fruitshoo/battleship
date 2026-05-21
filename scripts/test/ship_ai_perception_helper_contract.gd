extends Node

const ShipAIPerceptionHelper = preload("res://scripts/ai/limbo/ship_ai_perception_helper.gd")

var _failures: Array[String] = []


class MockShip:
	extends Node3D

	var hull_ratio_override := 0.75
	var team := "enemy"
	var combat_role := 1
	var allow_boarding := true
	var fire_pot_enabled := true
	var preferred_combat_range := 18.0
	var combat_range_tolerance := 3.5
	var retreat_distance := 7.5
	var current_speed := 2.0
	var move_speed := 10.0

	func get_hull_ratio() -> float:
		return hull_ratio_override

	func get_team_tag() -> String:
		return team

	func is_gunner_role() -> bool:
		return combat_role == 1

	func can_board_targets() -> bool:
		return allow_boarding

	func can_use_fire_pot_attack() -> bool:
		return fire_pot_enabled

	func get_preferred_engagement_range() -> float:
		return preferred_combat_range

	func get_engagement_range_tolerance() -> float:
		return combat_range_tolerance

	func get_retreat_engagement_distance() -> float:
		return retreat_distance

	func get_current_speed_value() -> float:
		return current_speed


class PropertyShip:
	extends Node3D

	var max_hull_hp := 200.0
	var hull_hp := 60.0
	var team := "player"
	var combat_role := 0
	var allow_boarding := false
	var orbit_distance := 32.0
	var preferred_combat_range := 16.0
	var combat_range_tolerance := 2.25
	var retreat_distance := 6.0
	var current_speed := 1.5
	var move_speed := 8.0


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	var ship := MockShip.new()
	ship.name = "PerceptionContractShip"
	add_child(ship)
	var property_ship := PropertyShip.new()
	property_ship.name = "PerceptionContractPropertyShip"
	add_child(property_ship)
	var target := PropertyShip.new()
	target.name = "PerceptionContractTarget"
	add_child(target)

	ship.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -40.0)
	target.rotation.y = 0.0
	await get_tree().process_frame

	_verify_method_backed_reads(ship)
	_verify_property_backed_reads(property_ship)
	_verify_distance_and_lead(ship, target)
	_verify_snapshot(ship, target)
	_verify_invalid_inputs_are_safe()

	ship.queue_free()
	property_ship.queue_free()
	target.queue_free()
	await get_tree().process_frame

	if _failures.is_empty():
		print("[ShipAIPerceptionHelperContract] ok")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[ShipAIPerceptionHelperContract] %s" % failure)
	get_tree().quit(1)


func _verify_method_backed_reads(ship: MockShip) -> void:
	_expect_near(ShipAIPerceptionHelper.get_hull_ratio(ship), 0.75, 0.001, "method hull ratio")
	_expect_eq(ShipAIPerceptionHelper.get_ship_team_tag(ship), "enemy", "method team tag")
	_expect_eq(ShipAIPerceptionHelper.is_enemy_ship(ship), true, "method enemy team")
	_expect_eq(ShipAIPerceptionHelper.is_ship_gunner(ship), true, "method gunner role")
	_expect_eq(ShipAIPerceptionHelper.can_ship_board(ship), true, "method boarding capability")
	_expect_eq(ShipAIPerceptionHelper.can_ship_use_fire_pot_attack(ship), true, "method fire-pot capability")
	_expect_near(ShipAIPerceptionHelper.get_preferred_range(ship, 10.0), 18.0, 0.001, "method preferred range")
	_expect_near(ShipAIPerceptionHelper.get_orbit_preferred_range(ship, 10.0), 18.0, 0.001, "method orbit preferred range")
	_expect_near(ShipAIPerceptionHelper.get_range_tolerance(ship, 1.0), 3.5, 0.001, "method range tolerance")
	_expect_near(ShipAIPerceptionHelper.get_retreat_range(ship, 1.0), 7.5, 0.001, "method retreat range")
	_expect_near(ShipAIPerceptionHelper.get_current_speed(ship), 2.0, 0.001, "method current speed")


func _verify_property_backed_reads(ship: PropertyShip) -> void:
	_expect_near(ShipAIPerceptionHelper.get_hull_ratio(ship), 0.3, 0.001, "property hull ratio")
	_expect_eq(ShipAIPerceptionHelper.get_ship_team_tag(ship), "player", "property team tag")
	_expect_eq(ShipAIPerceptionHelper.is_enemy_ship(ship), false, "property enemy team")
	_expect_eq(ShipAIPerceptionHelper.is_ship_gunner(ship), false, "property gunner role")
	_expect_eq(ShipAIPerceptionHelper.can_ship_board(ship), false, "property boarding capability")
	_expect_eq(ShipAIPerceptionHelper.can_ship_use_fire_pot_attack(ship), false, "property fire-pot capability")
	_expect_near(ShipAIPerceptionHelper.get_preferred_range(ship, 10.0), 16.0, 0.001, "property preferred range")
	_expect_near(ShipAIPerceptionHelper.get_orbit_preferred_range(ship, 10.0), 32.0, 0.001, "property orbit preferred range")
	_expect_near(ShipAIPerceptionHelper.get_range_tolerance(ship, 1.0), 2.25, 0.001, "property range tolerance")
	_expect_near(ShipAIPerceptionHelper.get_retreat_range(ship, 1.0), 6.0, 0.001, "property retreat range")
	_expect_near(ShipAIPerceptionHelper.get_current_speed(ship), 1.5, 0.001, "property current speed")


func _verify_distance_and_lead(ship: MockShip, target: PropertyShip) -> void:
	_expect_near(ShipAIPerceptionHelper.get_target_distance(ship, target), 40.0, 0.001, "target distance")
	var led_pos := ShipAIPerceptionHelper.get_led_target_position(ship, target, 40.0)
	_expect_vec3(led_pos, Vector3(0.0, 0.0, -44.5), "led target position")
	var close_pos := ShipAIPerceptionHelper.get_led_target_position(ship, target, 24.0)
	_expect_vec3(close_pos, target.global_position, "close target should not lead")


func _verify_snapshot(ship: MockShip, target: PropertyShip) -> void:
	var snapshot := ShipAIPerceptionHelper.build_engagement_snapshot(ship, target, 11.0, 1.5, 5.0)
	_expect_near(float(snapshot.get(ShipAIPerceptionHelper.KEY_TARGET_DISTANCE, 0.0)), 40.0, 0.001, "snapshot distance")
	_expect_near(float(snapshot.get(ShipAIPerceptionHelper.KEY_PREFERRED_RANGE, 0.0)), 18.0, 0.001, "snapshot preferred range")
	_expect_near(float(snapshot.get(ShipAIPerceptionHelper.KEY_RANGE_TOLERANCE, 0.0)), 3.5, 0.001, "snapshot range tolerance")
	_expect_near(float(snapshot.get(ShipAIPerceptionHelper.KEY_RETREAT_RANGE, 0.0)), 7.5, 0.001, "snapshot retreat range")
	_expect_vec3(snapshot.get(ShipAIPerceptionHelper.KEY_LED_TARGET_POSITION, Vector3.ZERO), Vector3(0.0, 0.0, -44.5), "snapshot led target")


func _verify_invalid_inputs_are_safe() -> void:
	_expect_eq(ShipAIPerceptionHelper.build_engagement_snapshot(null, null, 1.0, 1.0).is_empty(), true, "invalid snapshot")
	_expect_near(ShipAIPerceptionHelper.get_target_distance(null, null), 0.0, 0.001, "invalid distance")
	_expect_near(ShipAIPerceptionHelper.get_hull_ratio(null), 1.0, 0.001, "invalid hull ratio")
	_expect_eq(ShipAIPerceptionHelper.get_ship_team_tag(null), "", "invalid team")
	_expect_eq(ShipAIPerceptionHelper.is_enemy_ship(null), true, "invalid enemy fallback")
	_expect_eq(ShipAIPerceptionHelper.is_ship_gunner(null), false, "invalid gunner")
	_expect_eq(ShipAIPerceptionHelper.can_ship_board(null), false, "invalid boarding")
	_expect_eq(ShipAIPerceptionHelper.can_ship_use_fire_pot_attack(null), false, "invalid fire pot")
	_expect_near(ShipAIPerceptionHelper.get_preferred_range(null, 9.0), 9.0, 0.001, "invalid preferred range")
	_expect_near(ShipAIPerceptionHelper.get_orbit_preferred_range(null, 9.0), 9.0, 0.001, "invalid orbit preferred range")
	_expect_near(ShipAIPerceptionHelper.get_range_tolerance(null, 2.0), 2.0, 0.001, "invalid range tolerance")
	_expect_near(ShipAIPerceptionHelper.get_retreat_range(null, 3.0), 3.0, 0.001, "invalid retreat range")
	_expect_near(ShipAIPerceptionHelper.get_current_speed(null), 0.0, 0.001, "invalid current speed")
	_expect_vec3(ShipAIPerceptionHelper.get_led_target_position(null, null), Vector3.ZERO, "invalid led target")


func _expect_eq(actual, expected, label: String) -> void:
	if actual != expected:
		_failures.append("%s mismatch: %s expected %s" % [label, str(actual), str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures.append("%s mismatch: %.4f expected %.4f" % [label, actual, expected])


func _expect_vec3(actual, expected: Vector3, label: String) -> void:
	if typeof(actual) != TYPE_VECTOR3:
		_failures.append("%s should be Vector3, got %s" % [label, type_string(typeof(actual))])
		return
	var actual_vec := actual as Vector3
	if actual_vec.distance_to(expected) > 0.001:
		_failures.append("%s mismatch: %s expected %s" % [label, str(actual_vec), str(expected)])
