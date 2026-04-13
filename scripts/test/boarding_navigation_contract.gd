extends Node

const ChaserShipNavigationHelper = preload("res://scripts/entities/ships/chaser_ship_navigation_helper.gd")


class MockShip:
	extends Node3D

	var team: String = "enemy"
	var allow_boarding: bool = true
	var current_speed: float = 0.0
	var move_speed: float = 10.0
	var max_boarding_distance: float = 9.0
	var boarding_break_distance: float = 12.0
	var preferred_combat_range: float = 18.0
	var combat_range_tolerance: float = 2.0
	var retreat_distance: float = 5.0
	var side_boarding_approach: bool = false

	func get_team_tag() -> String:
		return team

	func can_board_targets() -> bool:
		return allow_boarding

	func is_gunner_role() -> bool:
		return false

	func get_current_speed_value() -> float:
		return current_speed

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.6, 4.0)

	func get_collision_distance_to(_other: Node3D) -> float:
		return 8.0

	func get_ships_cached(_tree: SceneTree) -> Array:
		return []

	func _is_side_boarding_approach(_target_ship: Node3D) -> bool:
		return side_boarding_approach


class MockTarget:
	extends Node3D

	var team: String = "player"
	var current_speed: float = 0.0
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var is_derelict: bool = false

	func get_team_tag() -> String:
		return team

	func get_current_speed_value() -> float:
		return current_speed

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.8, 4.2)


func _ready() -> void:
	var failures: Array[String] = []
	_verify_bow_sector_keeps_front_navigation(failures)
	_verify_true_side_still_uses_side_navigation(failures)
	if failures.is_empty():
		print("[BoardingNavigationContract] ok")
		return
	for failure in failures:
		push_error("[BoardingNavigationContract] %s" % failure)
	get_tree().quit(1)


func _verify_bow_sector_keeps_front_navigation(failures: Array[String]) -> void:
	var pair := _build_pair()
	var ship: MockShip = pair["ship"]
	var target: MockTarget = pair["target"]
	var forward := -target.global_basis.z.normalized()
	var right := target.global_basis.x.normalized()
	ship.global_position = target.global_position + forward * 4.5 + right * 3.8
	ship.rotation.y = target.rotation.y + PI * 0.5
	ship.set_meta("boarding_side_sign", 1.0)
	ship.set_meta("post_impact_follow_timer", 2.1)

	var nav: Dictionary = ChaserShipNavigationHelper.build_navigation(ship, target)
	var mode: String = str(ship.get_meta("boarding_approach_mode", ""))
	if mode != "front":
		failures.append("bow-sector approach should stay front, got %s" % mode)
	if ship.has_meta("boarding_side_sign"):
		failures.append("bow-sector front navigation should clear stale side sign")
	var heading_vector: Vector3 = nav["heading_point"] - ship.global_position
	heading_vector.y = 0.0
	if heading_vector.length_squared() > 0.001:
		var parallel_to_target: float = absf(heading_vector.normalized().dot(forward))
		if parallel_to_target > 0.78:
			failures.append("bow-sector heading stayed too parallel to target forward: %.3f" % parallel_to_target)


func _verify_true_side_still_uses_side_navigation(failures: Array[String]) -> void:
	var pair := _build_pair()
	var ship: MockShip = pair["ship"]
	var target: MockTarget = pair["target"]
	var forward := -target.global_basis.z.normalized()
	var right := target.global_basis.x.normalized()
	ship.global_position = target.global_position + forward * 1.2 + right * 8.4
	ship.rotation.y = target.rotation.y + PI

	ChaserShipNavigationHelper.build_navigation(ship, target)
	var mode: String = str(ship.get_meta("boarding_approach_mode", ""))
	if mode != "side":
		failures.append("true side approach should remain side, got %s" % mode)


func _build_pair() -> Dictionary:
	var target := MockTarget.new()
	add_child(target)
	target.global_position = Vector3.ZERO
	target.rotation = Vector3.ZERO

	var ship := MockShip.new()
	add_child(ship)
	ship.global_position = Vector3.ZERO
	ship.rotation = Vector3.ZERO

	return {
		"ship": ship,
		"target": target,
	}
