extends Node3D



class MockSoldier:
	extends Node3D

	var _is_jumping: bool = false
	var owned_ship: Node3D = null
	var home_ship: Node3D = null
	var team: String = "player"


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	var source_ship := _make_ship("SourceShip", Vector3.ZERO)
	var target_ship := _make_ship("TargetShip", Vector3(8.0, 0.0, 0.0))
	var source_soldiers := source_ship.get_node("Soldiers") as Node3D
	var target_soldiers := target_ship.get_node("Soldiers") as Node3D

	var soldier := MockSoldier.new()
	soldier.name = "BoardingSoldier"
	source_soldiers.add_child(soldier)
	soldier.position = Vector3(0.0, 0.5, 0.0)
	soldier.owned_ship = source_ship
	soldier.home_ship = source_ship

	var start_global := soldier.global_position
	SoldierBoardingHelper.jump_to_ship(soldier, target_ship, true)

	_assert_true("soldier_marked_jumping", soldier._is_jumping)
	_assert_true("soldier_reparented_to_target_during_flight", soldier.get_parent() == target_soldiers)
	_assert_true("owned_ship_changes_during_flight", soldier.owned_ship == target_ship)
	_assert_close_vec("start_global_preserved", soldier.global_position, start_global, 0.001)

	var target_motion := create_tween()
	target_motion.tween_property(target_ship, "global_position", Vector3(12.0, 0.0, 0.0), 1.0)
	await target_motion.finished
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame

	_assert_true("soldier_landed_under_target_soldiers", soldier.get_parent() == target_soldiers)
	_assert_true("owned_ship_stays_target_after_landing", soldier.owned_ship == target_ship)
	_assert_true("soldier_not_jumping_after_landing", not soldier._is_jumping)
	_assert_close("landing_y_on_target_deck", soldier.position.y, 0.4, 0.001)
	_assert_true("landing_global_follows_moved_target", soldier.global_position.x > start_global.x + 4.0)

	print("[SoldierWorldMotionContract] ok")
	get_tree().quit(0)


func _make_ship(ship_name: String, world_position: Vector3) -> Node3D:
	var ship := Node3D.new()
	ship.name = ship_name
	add_child(ship)
	ship.global_position = world_position

	var soldiers := Node3D.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)
	return ship


func _assert_true(label: String, value: bool) -> void:
	if value:
		return
	push_error("[SoldierWorldMotionContract] %s expected true" % label)
	get_tree().quit(1)


func _assert_close_vec(label: String, actual: Vector3, expected: Vector3, epsilon: float) -> void:
	if actual.distance_to(expected) <= epsilon:
		return
	push_error("[SoldierWorldMotionContract] %s expected %s got %s" % [label, expected, actual])
	get_tree().quit(1)


func _assert_close(label: String, actual: float, expected: float, epsilon: float) -> void:
	if absf(actual - expected) <= epsilon:
		return
	push_error("[SoldierWorldMotionContract] %s expected %.3f got %.3f" % [label, expected, actual])
	get_tree().quit(1)
