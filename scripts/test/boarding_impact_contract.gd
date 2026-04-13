extends Node

const AttackerScript = preload("res://scripts/test/chaser_isolation_boarding_collision.gd")


class MockTarget:
	extends Node3D

	var team: String = "player"
	var current_speed: float = 0.0
	var boarding_attacker: Node3D = null
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var deck_hostile_boarder_count: int = 0
	var alive_crew_count: int = 0

	func _init() -> void:
		add_to_group("player")

	func get_team_tag() -> String:
		return team

	func get_alive_crew_count() -> int:
		return alive_crew_count

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.6, 4.0)

	func set_boarding_attacker_ship(attacker: Node3D) -> void:
		boarding_attacker = attacker

	func get_boarding_attacker_ship() -> Node3D:
		return boarding_attacker


class MockSoldier:
	extends Node

	var team: String = "enemy"
	var damage_taken: float = 0.0
	var damage_source: String = ""

	func _init(initial_team: String = "enemy") -> void:
		team = initial_team

	func get_team_tag() -> String:
		return team

	func is_dead() -> bool:
		return false

	func is_dead_soldier() -> bool:
		return false

	func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO, source: String = "") -> void:
		damage_taken += amount
		damage_source = source


func _ready() -> void:
	var failures: Array[String] = []
	_run_boarding_requires_impact_contract(failures)
	if failures.is_empty():
		print("[BoardingImpactContract] ok")
		return
	for failure in failures:
		push_error("[BoardingImpactContract] %s" % failure)
	get_tree().quit(1)


func _run_boarding_requires_impact_contract(failures: Array[String]) -> void:
	_verify_proximity_does_not_board(failures)
	_verify_direct_board_requires_impact(failures)
	_verify_impact_allows_boarding(failures)
	_verify_body_impact_allows_boarding(failures)
	_verify_expired_impact_blocks_boarding(failures)
	_verify_bow_to_side_impact_allows_boarding(failures)
	_verify_player_crew_takes_reduced_ramming_aoe(failures)


func _verify_proximity_does_not_board(failures: Array[String]) -> void:
	var pair := _build_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	var area := Area3D.new()
	area.add_to_group("ship_proximity")
	target.add_child(area)
	attacker.call("_on_area_entered", area)
	if attacker.get("is_boarding") == true:
		failures.append("ship_proximity started boarding before a boarding impact was recorded")


func _verify_direct_board_requires_impact(failures: Array[String]) -> void:
	var pair := _build_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	if attacker.call("_is_side_boarding_approach", target) != true:
		failures.append("side contact fixture did not satisfy side boarding approach")
		return
	attacker.call("_board_ship", target)
	if attacker.get("is_boarding") == true:
		failures.append("_board_ship started boarding without a recent impact marker")


func _verify_impact_allows_boarding(failures: Array[String]) -> void:
	var pair := _build_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	attacker.call("_mark_boarding_impact", target)
	if attacker.call("_has_recent_boarding_impact", target) != true:
		failures.append("recent impact marker was not recognized")
		return
	attacker.call("_board_ship", target)
	if attacker.get("is_boarding") != true:
		failures.append("boarding did not start after a recent impact marker")
	if attacker.get("boarding_target") != target:
		failures.append("boarding target was not assigned after impact-gated boarding")
	if target.get_boarding_attacker_ship() != attacker:
		failures.append("target did not record the boarding attacker after impact-gated boarding")


func _verify_body_impact_allows_boarding(failures: Array[String]) -> void:
	var pair := _build_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	attacker.call("_on_body_entered", target)
	if attacker.get("is_boarding") != true:
		failures.append("body collision did not mark impact and start boarding")


func _verify_expired_impact_blocks_boarding(failures: Array[String]) -> void:
	var pair := _build_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	attacker.call("_mark_boarding_impact", target)
	attacker.set_meta("boarding_impact_grace_timer", 0.0)
	if attacker.call("_has_recent_boarding_impact", target) == true:
		failures.append("expired impact marker was still considered recent")
		return
	attacker.call("_board_ship", target)
	if attacker.get("is_boarding") == true:
		failures.append("_board_ship started boarding after the impact marker expired")


func _verify_bow_to_side_impact_allows_boarding(failures: Array[String]) -> void:
	var pair := _build_bow_to_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	if attacker.call("_is_side_boarding_approach", target) == true:
		failures.append("bow-to-side fixture unexpectedly satisfied side boarding approach")
		return
	if attacker.call("_can_force_head_on_boarding", target) != true:
		failures.append("bow-to-side fixture did not satisfy forced head-on boarding")
		return
	attacker.call("_mark_boarding_impact", target)
	attacker.call("_board_ship", target)
	if attacker.get("is_boarding") != true:
		failures.append("bow-to-side contact did not start boarding after impact")
	if str(attacker.get_meta("boarding_contact_mode", "")) != "head_on":
		failures.append("bow-to-side contact did not use head_on boarding contact mode")


func _verify_player_crew_takes_reduced_ramming_aoe(failures: Array[String]) -> void:
	var ship: Node3D = AttackerScript.new()
	add_child(ship)
	ship.set("team", "player")
	var soldiers := Node.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)
	var player_soldier := MockSoldier.new("player")
	var enemy_soldier := MockSoldier.new("enemy")
	soldiers.add_child(player_soldier)
	soldiers.add_child(enemy_soldier)

	ship.call("apply_ramming_aoe", 20.0, Vector3.ZERO)

	if not is_equal_approx(player_soldier.damage_taken, 7.0):
		failures.append("player ramming aoe was not reduced: %.2f" % player_soldier.damage_taken)
	if not is_equal_approx(enemy_soldier.damage_taken, 20.0):
		failures.append("enemy ramming aoe was unexpectedly reduced: %.2f" % enemy_soldier.damage_taken)
	if player_soldier.damage_source != "ramming_aoe" or enemy_soldier.damage_source != "ramming_aoe":
		failures.append("ramming aoe damage source was not tagged")


func _build_side_contact_pair() -> Dictionary:
	var attacker: Node3D = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("allow_boarding", true)
	attacker.set("current_speed", 2.5)
	attacker.set("max_boarding_distance", 9.0)
	attacker.global_position = Vector3.ZERO
	attacker.rotation = Vector3.ZERO
	_add_mock_crew(attacker, "enemy", 4)

	var target := MockTarget.new()
	add_child(target)
	target.global_position = Vector3(5.0, 0.0, 0.0)
	target.rotation = Vector3.ZERO
	attacker.set("target", target)

	return {
		"attacker": attacker,
		"target": target,
	}


func _build_bow_to_side_contact_pair() -> Dictionary:
	var attacker: Node3D = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("allow_boarding", true)
	attacker.set("current_speed", 1.0)
	attacker.set("max_boarding_distance", 9.0)
	attacker.global_position = Vector3(5.0, 0.0, 0.0)
	attacker.rotation = Vector3(0.0, PI * 0.5, 0.0)
	_add_mock_crew(attacker, "enemy", 4)

	var target := MockTarget.new()
	add_child(target)
	target.alive_crew_count = 5
	target.global_position = Vector3.ZERO
	target.rotation = Vector3.ZERO
	attacker.set("target", target)

	return {
		"attacker": attacker,
		"target": target,
	}


func _add_mock_crew(ship: Node, crew_team: String, count: int) -> void:
	var soldiers := Node.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)
	for _index in range(count):
		soldiers.add_child(MockSoldier.new(crew_team))
