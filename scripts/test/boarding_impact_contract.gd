extends Node

const AttackerScript = preload("res://scripts/test/chaser_isolation_boarding_collision.gd")
const ChaserShipScript = preload("res://scripts/entities/ships/chaser_ship.gd")


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
	_verify_enemy_boarding_latch_bonus_is_scoped(failures)
	_verify_enemy_boarding_pull_bonus_is_scoped(failures)
	_verify_boarding_pull_requires_active_rope_visual(failures)
	_verify_rigging_field_repair_waits_then_recovers(failures)


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


func _verify_enemy_boarding_latch_bonus_is_scoped(failures: Array[String]) -> void:
	var enemy_ship: Node = ChaserShipScript.new()
	var player_ship: Node = ChaserShipScript.new()
	enemy_ship.set("team", "enemy")
	player_ship.set("team", "player")

	var enemy_distance_bonus: float = float(enemy_ship.call("_get_enemy_boarding_latch_distance_bonus"))
	var player_distance_bonus: float = float(player_ship.call("_get_enemy_boarding_latch_distance_bonus"))
	var enemy_duration_bonus: float = float(enemy_ship.call("_get_enemy_boarding_latch_duration_bonus"))
	var player_duration_bonus: float = float(player_ship.call("_get_enemy_boarding_latch_duration_bonus"))
	var enemy_speed_bonus: float = float(enemy_ship.call("_get_enemy_boarding_latch_speed_bonus"))
	var player_speed_bonus: float = float(player_ship.call("_get_enemy_boarding_latch_speed_bonus"))

	if not is_equal_approx(enemy_distance_bonus, 0.25) or not is_equal_approx(player_distance_bonus, 0.0):
		failures.append("enemy boarding latch distance bonus scope changed: enemy %.2f player %.2f" % [enemy_distance_bonus, player_distance_bonus])
	if not is_equal_approx(enemy_duration_bonus, 0.15) or not is_equal_approx(player_duration_bonus, 0.0):
		failures.append("enemy boarding latch duration bonus scope changed: enemy %.2f player %.2f" % [enemy_duration_bonus, player_duration_bonus])
	if not is_equal_approx(enemy_speed_bonus, 0.15) or not is_equal_approx(player_speed_bonus, 0.0):
		failures.append("enemy boarding latch speed bonus scope changed: enemy %.2f player %.2f" % [enemy_speed_bonus, player_speed_bonus])

	enemy_ship.free()
	player_ship.free()


func _verify_enemy_boarding_pull_bonus_is_scoped(failures: Array[String]) -> void:
	var defender: Node = AttackerScript.new()
	var enemy_attacker: Node3D = AttackerScript.new()
	var player_attacker: Node3D = AttackerScript.new()
	enemy_attacker.set("team", "enemy")
	player_attacker.set("team", "player")

	defender.set("boarding_attacker", enemy_attacker)
	var enemy_pull_mult: float = float(defender.call("_get_enemy_boarding_pull_multiplier", enemy_attacker))
	defender.set("boarding_attacker", player_attacker)
	var player_pull_mult: float = float(defender.call("_get_enemy_boarding_pull_multiplier", player_attacker))

	if not is_equal_approx(enemy_pull_mult, 1.08):
		failures.append("enemy boarding pull multiplier changed: %.2f" % enemy_pull_mult)
	if not is_equal_approx(player_pull_mult, 1.0):
		failures.append("player boarding pull multiplier should stay neutral: %.2f" % player_pull_mult)

	defender.free()
	enemy_attacker.free()
	player_attacker.free()


func _verify_boarding_pull_requires_active_rope_visual(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.global_position = Vector3.ZERO

	var defender: Node3D = AttackerScript.new()
	add_child(defender)
	defender.set("team", "player")
	defender.set("current_speed", 0.0)
	defender.global_position = Vector3(12.0, 0.0, 0.0)

	attacker.set("boarding_target", defender)
	defender.set("boarding_attacker", attacker)
	attacker.set("_initial_rope_deployed", false)

	var attacker_pull_without_rope: Vector3 = attacker.call("_calculate_boarding_pull")
	var defender_pull_without_rope: Vector3 = defender.call("_calculate_boarding_pull")
	if attacker_pull_without_rope.length() > 0.001:
		failures.append("boarding attacker kept pulling before a rope visual existed")
	if defender_pull_without_rope.length() > 0.001:
		failures.append("boarding defender kept being pulled before a rope visual existed")

	attacker.call("_spawn_ropes", 1)
	attacker.set("_initial_rope_deployed", true)

	var attacker_pull_with_rope: Vector3 = attacker.call("_calculate_boarding_pull")
	var defender_pull_with_rope: Vector3 = defender.call("_calculate_boarding_pull")
	if attacker_pull_with_rope.length() <= 0.001:
		failures.append("boarding attacker lost pull while a rope visual was active")
	if defender_pull_with_rope.length() <= 0.001:
		failures.append("boarding defender lost pull while a rope visual was active")

	attacker.call("_clear_ropes")
	attacker.set("_initial_rope_deployed", false)

	var attacker_pull_after_clear: Vector3 = attacker.call("_calculate_boarding_pull")
	var defender_pull_after_clear: Vector3 = defender.call("_calculate_boarding_pull")
	if attacker_pull_after_clear.length() > 0.001:
		failures.append("boarding attacker kept pulling after rope visuals were cleared")
	if defender_pull_after_clear.length() > 0.001:
		failures.append("boarding defender kept being pulled after rope visuals were cleared")

	attacker.free()
	defender.free()


func _verify_rigging_field_repair_waits_then_recovers(failures: Array[String]) -> void:
	var ship: Node = AttackerScript.new()
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
