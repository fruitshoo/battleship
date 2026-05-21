extends Node
# @scene_contract_encapsulated

const AIShipNavigationHelper = preload("res://scripts/entities/ships/ai_ship_navigation_helper.gd")
const AIShipBoardingHelper = preload("res://scripts/entities/ships/ai_ship_boarding_helper.gd")



class MockShip:
	extends Node3D

	var team: String = "enemy"
	var allow_boarding: bool = true
	var current_speed: float = 0.0
	var move_speed: float = 10.0
	var acceleration: float = 10.0
	var deceleration: float = 10.0
	var max_boarding_distance: float = 9.0
	var boarding_break_distance: float = 12.0
	var boarding_target: Node3D = null
	var boarding_pull_velocity: Vector3 = Vector3.ZERO
	var preferred_combat_range: float = 18.0
	var combat_range_tolerance: float = 2.0
	var retreat_distance: float = 5.0
	var side_boarding_approach: bool = false
	var gunner_role: bool = false
	var limbo_ai_pilot_enabled: bool = false
	var min_ramming_speed: float = 6.0

	func get_team_tag() -> String:
		return team

	func can_board_targets() -> bool:
		return allow_boarding

	func is_gunner_role() -> bool:
		return gunner_role

	func get_current_speed_value() -> float:
		return current_speed

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.6, 4.0)

	func get_collision_distance_to(_other: Node3D) -> float:
		return 8.0

	func get_ships_cached(_tree: SceneTree) -> Array:
		return []

	func _calculate_boarding_pull_velocity(_delta: float) -> Vector3:
		return boarding_pull_velocity

	func _apply_bobbing_effect() -> void:
		pass

	func _process_boarding_common(_delta: float) -> void:
		pass

	func _is_side_boarding_approach(_target_ship: Node3D) -> bool:
		return side_boarding_approach


class MockTarget:
	extends Node3D

	var team: String = "player"
	var current_speed: float = 0.0
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var is_derelict: bool = false
	var blocks_boarding: bool = false

	func get_team_tag() -> String:
		return team

	func get_current_speed_value() -> float:
		return current_speed

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.8, 4.2)

	func can_be_boarded_by(_attacker_ship: Node = null) -> bool:
		return not blocks_boarding


class MockAuthoredCollisionShip:
	extends Node3D

	var base_collision_radius: float = 12.0
	var width_multiplier: float = 1.0
	var length_multiplier: float = 1.0


func _ready() -> void:
	var failures: Array[String] = []
	_verify_deck_area_limits_soft_collision_extents(failures)
	_verify_bow_sector_keeps_front_navigation(failures)
	_verify_true_side_still_uses_side_navigation(failures)
	_verify_head_on_boarding_holds_contact_anchor(failures)
	_verify_limbo_navigation_hint_offsets_gunner(failures)
	_verify_limbo_navigation_hint_speeds_gunner(failures)
	_verify_limbo_navigation_hint_does_not_break_close_boarding(failures)
	_verify_unboardable_target_uses_standoff_navigation(failures)
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

	var nav: Dictionary = AIShipNavigationHelper.build_navigation(ship, target)
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

	AIShipNavigationHelper.build_navigation(ship, target)
	var mode: String = str(ship.get_meta("boarding_approach_mode", ""))
	if mode != "side":
		failures.append("true side approach should remain side, got %s" % mode)


func _verify_head_on_boarding_holds_contact_anchor(failures: Array[String]) -> void:
	var pair := _build_pair()
	var ship: MockShip = pair["ship"]
	var target: MockTarget = pair["target"]
	ship.boarding_target = target
	ship.global_position = Vector3(7.3, 0.0, 1.6)
	ship.rotation = Vector3(0.0, PI * 0.5, 0.0)
	ship.current_speed = 3.0
	ship.set_meta("boarding_contact_mode", "head_on")
	ship.set_meta("boarding_hold_forward", -ship.global_transform.basis.z)
	ship.set_meta("boarding_contact_anchor_local", target.to_local(Vector3(4.0, 0.0, 0.0)))

	var start_local: Vector3 = target.to_local(ship.global_position)
	for _index in range(12):
		AIShipBoardingHelper.process_boarding(ship, 0.1)
	var end_local: Vector3 = target.to_local(ship.global_position)

	if absf(end_local.z) > absf(start_local.z) + 0.1:
		failures.append("head-on boarding slid too far along target hull: %.2f" % end_local.z)
	if absf(end_local.z) > 1.5:
		failures.append("head-on boarding did not settle back toward contact anchor: %.2f" % end_local.z)


func _verify_deck_area_limits_soft_collision_extents(failures: Array[String]) -> void:
	var ship := _build_authored_collision_ship(Vector2(2.0, 4.0))
	var half_extents := ShipContactGeometry.get_soft_collision_half_extents(ship)
	var expected := Vector2(2.0, 4.0) + Vector2.ONE * ShipContactGeometry.AUTHORED_DECK_COLLISION_PAD
	if half_extents.distance_to(expected) > 0.01:
		failures.append("authored DeckArea should limit soft collision extents, got %s expected %s" % [half_extents, expected])
	ship.free()


func _verify_limbo_navigation_hint_offsets_gunner(failures: Array[String]) -> void:
	var pair := _build_pair()
	var ship: MockShip = pair["ship"]
	var target: MockTarget = pair["target"]
	ship.allow_boarding = false
	ship.gunner_role = true
	ship.limbo_ai_pilot_enabled = true
	ship.global_position = Vector3(18.0, 0.0, 0.0)
	target.global_position = Vector3.ZERO
	_set_limbo_nav_hint(ship, target, Vector3(18.0, 0.0, 4.8), target.global_position, 0.46, false, "limbo_orbit_pressure")

	var nav: Dictionary = AIShipNavigationHelper.build_navigation(ship, target)
	var desired_point: Vector3 = ShipMovementIntent.get_desired_point(nav)
	if desired_point.distance_to(ship.global_position) < 2.0:
		failures.append("Limbo navigation hint should offset gunner desired point")
	if ShipMovementIntent.get_desired_speed_mult(nav) < 0.34:
		failures.append("Limbo navigation hint speed should rise above idle standoff")
	if ShipMovementIntent.get_permit_sprint(nav):
		failures.append("Limbo navigation hint should not permit sprint")
	if ShipMovementIntent.get_mode(nav) != "limbo_orbit_pressure":
		failures.append("Limbo navigation hint mode mismatch: %s" % ShipMovementIntent.get_mode(nav))


func _verify_limbo_navigation_hint_speeds_gunner(failures: Array[String]) -> void:
	var pair := _build_pair()
	var ship: MockShip = pair["ship"]
	var target: MockTarget = pair["target"]
	ship.allow_boarding = false
	ship.gunner_role = true
	ship.limbo_ai_pilot_enabled = true
	ship.global_position = Vector3(34.0, 0.0, 0.0)
	target.global_position = Vector3.ZERO
	_set_limbo_nav_hint(ship, target, Vector3(18.0, 0.0, 0.0), target.global_position, 1.10, true, "limbo_close_distance")

	var nav: Dictionary = AIShipNavigationHelper.build_navigation(ship, target)
	var desired_speed := ShipMovementIntent.get_desired_speed_mult(nav)
	if desired_speed < 1.05:
		failures.append("Limbo navigation hint should speed gunner approach: %.3f" % desired_speed)
	var desired_distance := ShipMovementIntent.get_desired_point(nav).distance_to(target.global_position)
	if absf(desired_distance - ship.preferred_combat_range) > 0.25:
		failures.append("Limbo navigation hint desired range mismatch: %.2f" % desired_distance)


func _verify_limbo_navigation_hint_does_not_break_close_boarding(failures: Array[String]) -> void:
	var pair := _build_pair()
	var ship: MockShip = pair["ship"]
	var target: MockTarget = pair["target"]
	ship.limbo_ai_pilot_enabled = true
	ship.global_position = Vector3(8.0, 0.0, 0.0)
	target.global_position = Vector3.ZERO
	_set_limbo_nav_hint(ship, target, Vector3(32.0, 0.0, 0.0), Vector3(32.0, 0.0, 0.0), 0.95, false, "limbo_withdraw")

	var nav: Dictionary = AIShipNavigationHelper.build_navigation(ship, target)
	var desired_distance := ShipMovementIntent.get_desired_point(nav).distance_to(target.global_position)
	if desired_distance > ship.global_position.distance_to(target.global_position) + 1.0:
		failures.append("Limbo navigation hint should not override close boarding navigation: %.2f" % desired_distance)


func _verify_unboardable_target_uses_standoff_navigation(failures: Array[String]) -> void:
	var pair := _build_pair()
	var ship: MockShip = pair["ship"]
	var target: MockTarget = pair["target"]
	target.blocks_boarding = true
	ship.global_position = Vector3(8.0, 0.0, 0.0)
	target.global_position = Vector3.ZERO
	ship.set_meta("boarding_approach_mode", "side")
	ship.set_meta("boarding_side_sign", 1.0)

	var nav: Dictionary = AIShipNavigationHelper.build_navigation(ship, target)
	if ship.has_meta("boarding_approach_mode") or ship.has_meta("boarding_side_sign"):
		failures.append("unboardable target should clear stale boarding navigation meta")
	if ShipMovementIntent.get_mode(nav) != "unboardable_standoff":
		failures.append("unboardable target should use standoff navigation, got %s" % ShipMovementIntent.get_mode(nav))
	if ShipMovementIntent.get_desired_speed_mult(nav) > 0.35:
		failures.append("unboardable target standoff should avoid full boarding charge")


func _set_limbo_nav_hint(
	ship: MockShip,
	target: MockTarget,
	desired_point: Vector3,
	heading_point: Vector3,
	speed_mult: float,
	permit_sprint: bool,
	mode: String
) -> void:
	ship.set_meta(ShipAILimboKeys.META_NAV_TARGET_ID, target.get_instance_id())
	ship.set_meta(ShipAILimboKeys.META_NAV_FRAME, Engine.get_physics_frames())
	ship.set_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT, desired_point)
	ship.set_meta(ShipAILimboKeys.META_NAV_HEADING_POINT, heading_point)
	ship.set_meta(ShipAILimboKeys.META_NAV_SPEED_MULT, speed_mult)
	ship.set_meta(ShipAILimboKeys.META_NAV_PERMIT_SPRINT, permit_sprint)
	ship.set_meta(ShipAILimboKeys.META_NAV_MODE, mode)


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


func _build_authored_collision_ship(deck_half_extents: Vector2) -> MockAuthoredCollisionShip:
	var ship := MockAuthoredCollisionShip.new()
	var authoring := Node3D.new()
	authoring.name = ShipAuthoringHelper.AUTHORING_ROOT
	ship.add_child(authoring)

	var deck_area := Node3D.new()
	deck_area.name = ShipAuthoringHelper.DECK_AREA
	deck_area.set_meta("use_authored_deck_area", true)
	authoring.add_child(deck_area)

	var points := Node3D.new()
	points.name = ShipAuthoringHelper.DECK_AREA_POINTS
	deck_area.add_child(points)

	var corners := [
		Vector3(-deck_half_extents.x, 0.0, -deck_half_extents.y),
		Vector3(deck_half_extents.x, 0.0, -deck_half_extents.y),
		Vector3(deck_half_extents.x, 0.0, deck_half_extents.y),
		Vector3(-deck_half_extents.x, 0.0, deck_half_extents.y),
	]
	for index in range(corners.size()):
		var marker := Marker3D.new()
		marker.name = "Point_%02d" % index
		marker.position = corners[index]
		points.add_child(marker)
	return ship
