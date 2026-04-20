extends Node

const BaseShipCrewHelper = preload("res://scripts/entities/ships/base_ship_crew_helper.gd")
const SoldierShipDutyHelper = preload("res://scripts/entities/soldiers/soldier_ship_duty_helper.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const CANNON_SCENE := preload("res://scenes/entities/launchers/cannon.tscn")


class MockShip:
	extends Node3D

	var team: String = "player"
	var gunnery_crew_alloc: int = 0
	var gunnery_crew_ratio: float = 0.5
	var shiphandling_crew_ratio: float = 0.2
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var is_boarding: bool = false
	var deck_hostile_boarder_count: int = 0
	var current_speed: float = 0.0
	var is_rowing: bool = false
	var rudder_angle: float = 0.0
	var base_collision_radius: float = 4.5
	var width_multiplier: float = 1.0
	var length_multiplier: float = 1.0
	var is_dying: bool = false
	var is_sinking: bool = false

	func get_team_tag() -> String:
		return team

	func is_combat_disabled() -> bool:
		return false


class MockLegacyShip:
	extends Node3D

	var team: String = "player"

	func get_gunnery_reload_multiplier() -> float:
		return 0.5


class MockSoldier:
	extends Node3D

	var team: String = "player"
	var owned_ship: Node = null
	var current_target: Node = null
	var current_state: int = 0
	var is_captain: bool = false
	var crew_role: String = "general"

	func get_team_tag() -> String:
		return team

	func get_owned_ship_node() -> Node3D:
		return owned_ship as Node3D


var _failed: bool = false


func _ready() -> void:
	await _run_contract()


func _run_contract() -> void:
	await _run_reload_curve_contract()
	if _failed:
		return
	await _run_active_cannon_assignment_contract()
	if _failed:
		return
	await _run_soldier_cannon_slot_contract()
	if _failed:
		return
	await _run_cannon_slot_reservation_contract()
	if _failed:
		return
	await _run_legacy_multiplier_contract()
	if _failed:
		return

	print("[CannonCrewReloadContract] ok")
	get_tree().quit(0)


func _run_reload_curve_contract() -> void:
	var cannon := CANNON_SCENE.instantiate()
	cannon.set("team", "enemy")
	cannon.set("fire_cooldown", 10.0)
	add_child(cannon)
	await get_tree().process_frame

	cannon.call("set_reload_crew_power", 0.0)
	var uncrewed_cooldown: float = float(cannon.call("_get_current_cooldown"))
	cannon.call("set_reload_crew_power", 1.0)
	var one_crew_cooldown: float = float(cannon.call("_get_current_cooldown"))
	cannon.call("set_reload_crew_power", 2.0)
	var two_crew_cooldown: float = float(cannon.call("_get_current_cooldown"))
	cannon.call("set_reload_crew_power", 3.0)
	var three_crew_cooldown: float = float(cannon.call("_get_current_cooldown"))

	_assert_gt("uncrewed_slower_than_one_crew", uncrewed_cooldown, one_crew_cooldown)
	_assert_close("one_crew_keeps_project_tempo_reload", one_crew_cooldown, 11.0)
	_assert_gt("two_crew_faster_than_one_crew", one_crew_cooldown, two_crew_cooldown)
	_assert_gt("three_crew_faster_than_two_crew", two_crew_cooldown, three_crew_cooldown)
	cannon.queue_free()


func _run_active_cannon_assignment_contract() -> void:
	var ship := MockShip.new()
	ship.name = "CrewShip"
	ship.gunnery_crew_alloc = 3
	add_child(ship)
	EntityRegistry.register_ship(ship)

	var forward_cannon := CANNON_SCENE.instantiate()
	forward_cannon.name = "ForwardCannon"
	var aft_cannon := CANNON_SCENE.instantiate()
	aft_cannon.name = "AftCannon"
	aft_cannon.rotation.y = PI
	ship.add_child(forward_cannon)
	ship.add_child(aft_cannon)

	var enemy := MockShip.new()
	enemy.name = "EnemyShip"
	enemy.team = "enemy"
	add_child(enemy)
	EntityRegistry.register_ship(enemy)
	enemy.global_position = Vector3(0.0, 0.0, -10.0)
	await get_tree().process_frame

	BaseShipCrewHelper.assign_cannon_reload_crew_power(ship)

	_assert_close("forward_cannon_receives_active_broadside_crew", float(forward_cannon.call("get_reload_crew_power")), 3.0)
	_assert_close("aft_cannon_receives_no_inactive_crew", float(aft_cannon.call("get_reload_crew_power")), 0.0)

	EntityRegistry.unregister_ship(ship)
	EntityRegistry.unregister_ship(enemy)
	ship.queue_free()
	enemy.queue_free()


func _run_soldier_cannon_slot_contract() -> void:
	var ship := MockShip.new()
	ship.name = "SlotShip"
	ship.gunnery_crew_alloc = 1
	ship.gunnery_crew_ratio = 0.5
	add_child(ship)
	EntityRegistry.register_ship(ship)

	var soldiers := Node3D.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)

	var soldier := MockSoldier.new()
	soldier.name = "GunneryWorker"
	soldier.owned_ship = ship
	soldiers.add_child(soldier)
	EntityRegistry.register_soldier(soldier)
	soldier.global_position = Vector3(4.0, 0.0, 3.0)

	var cannon := CANNON_SCENE.instantiate()
	cannon.name = "DutyCannon"
	cannon.set("team", "enemy")
	cannon.call("set_reload_crew_power", 1.0)
	ship.add_child(cannon)
	await get_tree().process_frame

	var expected_slot: Vector3 = cannon.call("get_reload_crew_station_global_position", 0)
	expected_slot.y = soldier.global_position.y
	var duty_target: Vector3 = SoldierShipDutyHelper.find_ship_duty_target(soldier)

	_assert_vec3_close("soldier_moves_to_cannon_reload_slot", duty_target, expected_slot)
	_assert_eq("soldier_cannon_duty_meta", str(soldier.get_meta("ship_duty_task", "")), "cannon_reload")
	_assert_eq("soldier_cannon_animation_placeholder", str(soldier.get_meta("ship_duty_animation_key", "")), "cannon_reload_standby")
	_assert_eq("soldier_cannon_not_arrived_yet", bool(soldier.get_meta("ship_duty_at_slot", true)), false)

	EntityRegistry.unregister_soldier(soldier)
	EntityRegistry.unregister_ship(ship)
	ship.queue_free()


func _run_cannon_slot_reservation_contract() -> void:
	var ship := MockShip.new()
	ship.name = "ReservationShip"
	ship.gunnery_crew_alloc = 1
	ship.gunnery_crew_ratio = 0.5
	add_child(ship)
	EntityRegistry.register_ship(ship)

	var soldiers := Node3D.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)

	var occupant := MockSoldier.new()
	occupant.name = "SlotOccupant"
	occupant.owned_ship = ship
	soldiers.add_child(occupant)
	EntityRegistry.register_soldier(occupant)

	var extra_worker := MockSoldier.new()
	extra_worker.name = "ExtraWorker"
	extra_worker.owned_ship = ship
	soldiers.add_child(extra_worker)
	EntityRegistry.register_soldier(extra_worker)

	var cannon := CANNON_SCENE.instantiate()
	cannon.name = "ReservedCannon"
	cannon.set("team", "enemy")
	cannon.call("set_reload_crew_power", 1.0)
	ship.add_child(cannon)
	await get_tree().process_frame

	var slot_position: Vector3 = cannon.call("get_reload_crew_station_global_position", 0)
	occupant.global_position = slot_position
	extra_worker.global_position = Vector3(4.0, 0.0, 3.0)

	var occupant_target: Vector3 = SoldierShipDutyHelper.find_ship_duty_target(occupant)
	var extra_target: Vector3 = SoldierShipDutyHelper.find_ship_duty_target(extra_worker)

	_assert_vec3_close("occupied_slot_stays_reserved_for_occupant", occupant_target, slot_position)
	_assert_eq("occupant_arrived_meta", bool(occupant.get_meta("ship_duty_at_slot", false)), true)
	_assert_true("extra_worker_not_assigned_occupied_slot", extra_target.distance_to(slot_position) > 0.25)
	_assert_eq("extra_worker_cannon_duty_cleared", str(extra_worker.get_meta("ship_duty_task", "")), "")

	EntityRegistry.unregister_soldier(occupant)
	EntityRegistry.unregister_soldier(extra_worker)
	EntityRegistry.unregister_ship(ship)
	ship.queue_free()


func _run_legacy_multiplier_contract() -> void:
	var ship := MockLegacyShip.new()
	ship.name = "LegacyShip"
	ship.add_to_group("ships")
	add_child(ship)

	var cannon := CANNON_SCENE.instantiate()
	cannon.set("team", "enemy")
	cannon.set("fire_cooldown", 10.0)
	cannon.set("crew_operated_reload_enabled", false)
	ship.add_child(cannon)
	await get_tree().process_frame

	var cooldown: float = float(cannon.call("_get_current_cooldown"))
	_assert_close("disabled_crew_reload_keeps_legacy_ship_multiplier", cooldown, 5.5)

	ship.queue_free()


func _assert_close(label: String, actual: float, expected: float, tolerance: float = 0.01) -> void:
	if absf(actual - expected) <= tolerance:
		return
	_failed = true
	push_error("[CannonCrewReloadContract] %s expected %.3f got %.3f" % [label, expected, actual])
	get_tree().quit(1)


func _assert_eq(label: String, actual, expected) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("[CannonCrewReloadContract] %s expected %s got %s" % [label, str(expected), str(actual)])
	get_tree().quit(1)


func _assert_true(label: String, value: bool) -> void:
	if value:
		return
	_failed = true
	push_error("[CannonCrewReloadContract] %s expected true" % label)
	get_tree().quit(1)


func _assert_gt(label: String, left: float, right: float) -> void:
	if left > right:
		return
	_failed = true
	push_error("[CannonCrewReloadContract] %s expected %.3f > %.3f" % [label, left, right])
	get_tree().quit(1)


func _assert_vec3_close(label: String, actual: Vector3, expected: Vector3, tolerance: float = 0.01) -> void:
	if actual.distance_to(expected) <= tolerance:
		return
	_failed = true
	push_error("[CannonCrewReloadContract] %s expected %s got %s" % [label, str(expected), str(actual)])
	get_tree().quit(1)
