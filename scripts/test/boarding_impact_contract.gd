extends Node

const AttackerScript = preload("res://scripts/test/chaser_isolation_boarding_collision.gd")
const ChaserShipScript = preload("res://scripts/entities/ships/chaser_ship.gd")
const PlayerShipMovementHelper = preload("res://scripts/entities/ships/player_ship_movement_helper.gd")


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


class MockGuardedAttacker:
	extends Node3D

	var target: Node3D = null
	var min_ramming_speed: float = 6.0

	func can_board_targets() -> bool:
		return true

	func get_target_ship() -> Node3D:
		return target

	func get_collision_distance_to(_other: Node3D) -> float:
		return 8.0

	func _mark_boarding_impact(target_ship: Node3D, grace_duration: float = 1.25) -> void:
		set_meta("boarding_impact_target_id", target_ship.get_instance_id())
		set_meta("boarding_impact_grace_timer", grace_duration)

	func _has_recent_boarding_impact(target_ship: Node3D) -> bool:
		if float(get_meta("boarding_impact_grace_timer", 0.0)) <= 0.0:
			return false
		return int(get_meta("boarding_impact_target_id", 0)) == target_ship.get_instance_id()


class MockSeparationShip:
	extends Node3D

	var target: Node3D = null
	var boarding_target: Node3D = null
	var ship_mass_scale: float = 1.0
	var collision_distance: float = 8.0
	var neighbors: Array = []
	var allow_boarding: bool = true
	var gunner_role: bool = false
	var min_ramming_speed: float = 6.0
	var team: String = "player"

	func _get_ships_cached(_tree: SceneTree) -> Array:
		return neighbors

	func get_team_tag() -> String:
		return team

	func can_board_targets() -> bool:
		return allow_boarding

	func is_gunner_role() -> bool:
		return gunner_role

	func is_boarding_ship() -> bool:
		return is_instance_valid(boarding_target)

	func get_boarding_target_ship() -> Node3D:
		return boarding_target if is_instance_valid(boarding_target) else null

	func get_collision_distance_to(_other: Node3D) -> float:
		return collision_distance


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
	_verify_head_to_head_impact_allows_boarding(failures)
	_verify_bow_to_side_boarding_stores_side_anchor(failures)
	_verify_guarded_collision_records_contact_anchor(failures)
	_verify_cancel_boarding_clears_contact_anchor(failures)
	_verify_player_crew_takes_reduced_ramming_aoe(failures)
	_verify_enemy_boarding_latch_bonus_is_scoped(failures)
	_verify_enemy_boarding_pull_bonus_is_scoped(failures)
	_verify_boarding_pull_requires_active_rope_visual(failures)
	_verify_boarding_rope_does_not_push_when_slack(failures)
	_verify_boarding_pull_is_attacker_biased(failures)
	_verify_boarding_pull_uses_collision_scaled_rest_length(failures)
	_verify_hostile_support_contact_uses_collision_feedback(failures)
	_verify_boarding_pull_velocity_accumulates_and_clears(failures)
	_verify_boarding_pull_velocity_is_integrated_once(failures)
	_verify_hook_timer_uses_collision_scaled_contact_distance(failures)
	_verify_hooked_boarding_progresses_through_minor_distance_jitter(failures)
	_verify_lost_contact_without_rope_does_not_drive_boarding_motion(failures)
	_verify_boarding_approach_suppresses_pre_latch_separation(failures)


func _verify_boarding_approach_suppresses_pre_latch_separation(failures: Array[String]) -> void:
	var attacker := MockSeparationShip.new()
	var target := MockTarget.new()
	add_child(attacker)
	add_child(target)
	attacker.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -7.7)
	attacker.target = target
	attacker.neighbors = [attacker, target]
	var boarding_force := PlayerShipMovementHelper.calculate_separation(attacker)
	if boarding_force.length() > 0.001:
		failures.append("boarding approach should not be pushed off before latch: %.3f" % boarding_force.length())

	var gunner := MockSeparationShip.new()
	var gunner_target := MockTarget.new()
	add_child(gunner)
	add_child(gunner_target)
	gunner.global_position = Vector3.ZERO
	gunner_target.global_position = Vector3(0.0, 0.0, -7.7)
	gunner.target = gunner_target
	gunner.neighbors = [gunner, gunner_target]
	gunner.gunner_role = true
	var gunner_force := PlayerShipMovementHelper.calculate_separation(gunner)
	if gunner_force.length() <= 0.001:
		failures.append("non-boarding gunner should still receive close-range separation")

	attacker.queue_free()
	target.queue_free()
	gunner.queue_free()
	gunner_target.queue_free()


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


func _verify_head_to_head_impact_allows_boarding(failures: Array[String]) -> void:
	var pair := _build_head_to_head_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	if attacker.call("_is_side_boarding_approach", target) == true:
		failures.append("head-to-head fixture unexpectedly satisfied side boarding approach")
		return
	if attacker.call("_can_force_head_on_boarding", target) != true:
		failures.append("head-to-head fixture did not satisfy forced boarding")
		return
	attacker.call("_mark_boarding_impact", target)
	attacker.call("_board_ship", target)
	if attacker.get("is_boarding") != true:
		failures.append("head-to-head contact did not start boarding after impact")
	if str(attacker.get_meta("boarding_contact_mode", "")) != "head_on":
		failures.append("head-to-head contact did not use head_on boarding contact mode")


func _verify_bow_to_side_boarding_stores_side_anchor(failures: Array[String]) -> void:
	var pair := _build_bow_to_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	ChaserShipBoardingHelper.store_boarding_contact_anchor(attacker, target)
	if not attacker.has_meta("boarding_contact_anchor_local"):
		failures.append("bow-to-side contact did not store a contact anchor")
		return
	var anchor_local: Vector3 = attacker.get_meta("boarding_contact_anchor_local", Vector3.ZERO)
	var deck_half: Vector2 = target.get_deck_half_extents()
	if absf(anchor_local.x) < deck_half.x * 0.65:
		failures.append("bow-to-side contact anchor should stay near the contacted side: %.2f" % anchor_local.x)
	if absf(anchor_local.z) > deck_half.y * 0.35:
		failures.append("bow-to-side contact anchor drifted too far toward bow/stern: %.2f" % anchor_local.z)


func _verify_guarded_collision_records_contact_anchor(failures: Array[String]) -> void:
	var target := MockTarget.new()
	add_child(target)
	target.global_position = Vector3.ZERO
	target.rotation = Vector3.ZERO

	var attacker := MockGuardedAttacker.new()
	add_child(attacker)
	attacker.target = target
	attacker.global_position = Vector3(5.0, 0.0, 0.0)
	attacker.rotation = Vector3(0.0, PI * 0.5, 0.0)

	ChaserShipBoardingHelper.emit_guarded_collision(attacker, target, 0.0)
	if not attacker._has_recent_boarding_impact(target):
		failures.append("guarded collision did not mark a recent boarding impact")
	if not attacker.has_meta("boarding_contact_anchor_local"):
		failures.append("guarded collision did not store a boarding contact anchor")
		return
	var anchor_local: Vector3 = attacker.get_meta("boarding_contact_anchor_local", Vector3.ZERO)
	var deck_half: Vector2 = target.get_deck_half_extents()
	if absf(anchor_local.x) < deck_half.x * 0.65:
		failures.append("guarded collision anchor should stay on the contacted side: %.2f" % anchor_local.x)
	if absf(anchor_local.z) > deck_half.y * 0.35:
		failures.append("guarded collision anchor drifted toward bow/stern: %.2f" % anchor_local.z)


func _verify_cancel_boarding_clears_contact_anchor(failures: Array[String]) -> void:
	var pair := _build_bow_to_side_contact_pair()
	var attacker: Node = pair["attacker"]
	var target: Node3D = pair["target"]
	attacker.set("is_boarding", true)
	attacker.set("boarding_target", target)
	attacker.set_meta("boarding_contact_mode", "head_on")
	attacker.set_meta("boarding_contact_anchor_local", Vector3(2.0, 0.4, 0.0))
	attacker.call("_cancel_boarding")
	if attacker.has_meta("boarding_contact_anchor_local"):
		failures.append("cancel boarding should clear the stored contact anchor")
	if attacker.has_meta("boarding_contact_mode"):
		failures.append("cancel boarding should clear the contact mode")


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
	if defender_pull_with_rope.length() >= attacker_pull_with_rope.length() * 0.45:
		failures.append("boarding defender pull should stay much weaker than attacker pull")

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


func _verify_boarding_rope_does_not_push_when_slack(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.set("base_collision_radius", 2.0)
	attacker.set("width_multiplier", 1.0)
	attacker.set("length_multiplier", 1.0)
	attacker.global_position = Vector3.ZERO

	var defender: Node = AttackerScript.new()
	add_child(defender)
	defender.set("team", "player")
	defender.set("current_speed", 0.0)
	defender.set("base_collision_radius", 2.0)
	defender.set("width_multiplier", 1.0)
	defender.set("length_multiplier", 1.0)
	defender.global_position = Vector3(3.0, 0.0, 0.0)

	attacker.set("boarding_target", defender)
	defender.set("boarding_attacker", attacker)
	attacker.call("_spawn_ropes", 1)
	attacker.set("_initial_rope_deployed", true)

	var pull: Vector3 = attacker.call("_calculate_boarding_pull")
	if pull.length() > 0.001:
		failures.append("slack boarding rope should not push ships apart: %s" % pull)

	attacker.free()
	defender.free()


func _verify_boarding_pull_is_attacker_biased(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.global_position = Vector3.ZERO

	var defender: Node = AttackerScript.new()
	add_child(defender)
	defender.set("team", "player")
	defender.set("current_speed", 0.0)
	defender.global_position = Vector3(12.0, 0.0, 0.0)

	attacker.set("boarding_target", defender)
	defender.set("boarding_attacker", attacker)
	attacker.call("_spawn_ropes", 1)
	attacker.set("_initial_rope_deployed", true)

	var attacker_velocity: Vector3 = Vector3.ZERO
	var defender_velocity: Vector3 = Vector3.ZERO
	for _index in range(8):
		attacker_velocity = attacker.call("_calculate_boarding_pull_velocity", 0.1)
		defender_velocity = defender.call("_calculate_boarding_pull_velocity", 0.1)

	if defender_velocity.length() >= attacker_velocity.length() * 0.45:
		failures.append("boarding rope should move the hook thrower far more than the target")
	if float(defender.call("_get_boarding_pull_role_accel_multiplier", attacker)) > 0.3:
		failures.append("boarding defender acceleration multiplier is too high")
	if float(defender.call("_get_boarding_pull_role_velocity_multiplier", attacker)) > 0.35:
		failures.append("boarding defender velocity multiplier is too high")

	attacker.free()
	defender.free()


func _verify_boarding_pull_uses_collision_scaled_rest_length(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.set("base_collision_radius", 2.0)
	attacker.set("width_multiplier", 1.0)
	attacker.set("length_multiplier", 1.0)
	attacker.global_position = Vector3.ZERO

	var defender: Node = AttackerScript.new()
	add_child(defender)
	defender.set("team", "player")
	defender.set("current_speed", 0.0)
	defender.set("base_collision_radius", 2.0)
	defender.set("width_multiplier", 1.0)
	defender.set("length_multiplier", 1.0)
	defender.global_position = Vector3(7.0, 0.0, 0.0)

	attacker.set("boarding_target", defender)
	defender.set("boarding_attacker", attacker)
	attacker.call("_spawn_ropes", 1)
	attacker.set("_initial_rope_deployed", true)

	var rest_length: float = float(attacker.call("_get_boarding_pull_rest_length", attacker.call("_get_boarding_pull_contact_distance", defender)))
	if rest_length >= 7.0:
		failures.append("boarding pull rest length should shrink with smaller collision hulls")

	var attacker_pull: Vector3 = attacker.call("_calculate_boarding_pull")
	if attacker_pull.length() <= 0.001:
		failures.append("boarding pull should engage near a smaller ship contact distance")

	attacker.free()
	defender.free()


func _verify_hostile_support_contact_uses_collision_feedback(failures: Array[String]) -> void:
	var enemy := MockSeparationShip.new()
	var support := MockSeparationShip.new()
	add_child(enemy)
	add_child(support)
	enemy.team = "enemy"
	support.team = "player"
	ShipAllyRoleHelper.mark_support_ship(support)

	if not BaseShipCollisionHelper._is_hostile_support_contact(enemy, support):
		failures.append("enemy-to-support contact should be classified as hostile support contact")
	var normal_threshold: float = BaseShipCollisionHelper._get_contact_vfx_threshold(enemy, false, false)
	var support_threshold: float = BaseShipCollisionHelper._get_contact_vfx_threshold(enemy, false, true)
	if support_threshold >= normal_threshold * 0.8:
		failures.append("hostile support contact should lower visible impact threshold")
	var normal_intensity: float = BaseShipCollisionHelper._get_contact_vfx_intensity(0.0, 0.2, 4.2, 0.0, false)
	var support_intensity: float = BaseShipCollisionHelper._get_contact_vfx_intensity(0.0, 0.2, 4.2, 0.0, true)
	if support_intensity <= normal_intensity:
		failures.append("hostile support contact should read side shoves as stronger impacts")

	enemy.free()
	support.free()


func _verify_boarding_pull_velocity_accumulates_and_clears(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.set("base_collision_radius", 2.0)
	attacker.set("width_multiplier", 1.0)
	attacker.set("length_multiplier", 1.0)
	attacker.global_position = Vector3.ZERO

	var defender: Node = AttackerScript.new()
	add_child(defender)
	defender.set("team", "player")
	defender.set("current_speed", 0.0)
	defender.set("base_collision_radius", 2.0)
	defender.set("width_multiplier", 1.0)
	defender.set("length_multiplier", 1.0)
	defender.global_position = Vector3(9.0, 0.0, 0.0)

	attacker.set("boarding_target", defender)
	defender.set("boarding_attacker", attacker)
	attacker.call("_spawn_ropes", 1)
	attacker.set("_initial_rope_deployed", true)

	var first_velocity: Vector3 = attacker.call("_calculate_boarding_pull_velocity", 0.1)
	var accumulated_velocity: Vector3 = first_velocity
	for _index in range(6):
		accumulated_velocity = attacker.call("_calculate_boarding_pull_velocity", 0.1)

	if accumulated_velocity.length() <= first_velocity.length() + 0.5:
		failures.append("boarding pull velocity should accumulate while a rope remains hooked")
	if accumulated_velocity.length() <= 1.0:
		failures.append("boarding pull velocity stayed too weak after repeated hooked frames")

	attacker.call("_spawn_ropes", 2)
	var refreshed_velocity: Vector3 = attacker.get("boarding_pull_velocity") as Vector3
	if refreshed_velocity.length() < accumulated_velocity.length() - 0.001:
		failures.append("boarding pull velocity should survive rope visual refresh")

	attacker.call("_clear_ropes")
	attacker.set("_initial_rope_deployed", false)
	if (attacker.get("boarding_pull_velocity") as Vector3).length() > 0.001:
		failures.append("boarding pull velocity should reset as soon as rope visuals are cleared")
	var released_velocity: Vector3 = accumulated_velocity
	for _index in range(10):
		released_velocity = attacker.call("_calculate_boarding_pull_velocity", 0.1)

	if released_velocity.length() > 0.05:
		failures.append("boarding pull velocity should clear quickly after the rope is released")

	attacker.free()
	defender.free()


func _verify_boarding_pull_velocity_is_integrated_once(failures: Array[String]) -> void:
	var player_source := FileAccess.get_file_as_string("res://scripts/entities/ships/player_ship_movement_helper.gd")
	if player_source.contains("_calculate_boarding_pull() * delta"):
		failures.append("player movement should use accumulated boarding pull velocity")
	if not player_source.contains("_calculate_boarding_pull_velocity(delta)"):
		failures.append("player movement lost accumulated boarding pull velocity")

	var ai_source := FileAccess.get_file_as_string("res://scripts/entities/ships/chaser_ship_ai_helper.gd")
	if ai_source.contains("_calculate_boarding_pull() * delta"):
		failures.append("chaser movement should use accumulated boarding pull velocity")
	if not ai_source.contains("_calculate_boarding_pull_velocity(delta)"):
		failures.append("chaser movement lost accumulated boarding pull velocity")

	var boarding_source := FileAccess.get_file_as_string("res://scripts/entities/ships/chaser_ship_boarding_helper.gd")
	if boarding_source.contains("pull_velocity * delta") or boarding_source.contains("pull_force * delta"):
		failures.append("boarding pull velocity should not be multiplied by delta twice")
	if not boarding_source.contains("_calculate_boarding_pull_velocity(delta)"):
		failures.append("boarding motion lost accumulated boarding pull velocity")

	var base_ship_source := FileAccess.get_file_as_string("res://scripts/entities/ships/base_ship.gd")
	if not base_ship_source.contains("_clear_ropes(false)"):
		failures.append("rope refresh should preserve boarding pull velocity")
	if not base_ship_source.contains("func _clear_ropes(reset_pull_velocity: bool = true)"):
		failures.append("rope clear should explicitly reset boarding pull velocity by default")


func _verify_hook_timer_uses_collision_scaled_contact_distance(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.set("max_boarding_distance", 9.0)
	attacker.set("boarding_break_distance", 12.0)
	attacker.set("boarding_contact_grace_duration", 0.0)
	attacker.set("boarding_hook_throw_delay", 0.1)
	attacker.set("base_collision_radius", 7.0)
	attacker.set("width_multiplier", 1.0)
	attacker.set("length_multiplier", 1.0)
	attacker.global_position = Vector3.ZERO

	var defender: Node = AttackerScript.new()
	add_child(defender)
	defender.set("team", "player")
	defender.set("current_speed", 0.0)
	defender.set("base_collision_radius", 7.0)
	defender.set("width_multiplier", 1.0)
	defender.set("length_multiplier", 1.0)
	defender.global_position = Vector3(1.0, 0.0, 0.0)
	var collision_contact_distance: float = float(attacker.call("get_collision_distance_to", defender))
	defender.global_position = Vector3(collision_contact_distance + 0.6, 0.0, 0.0)

	attacker.set("boarding_target", defender)
	defender.set("boarding_attacker", attacker)

	for _index in range(10):
		attacker.call("_process_boarding_common", 0.2)

	if attacker.get("_initial_rope_deployed") != true:
		failures.append("boarding hook should deploy at collision-scaled contact distance")

	attacker.free()
	defender.free()


func _verify_hooked_boarding_progresses_through_minor_distance_jitter(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.set("max_boarding_distance", 4.0)
	attacker.set("boarding_break_distance", 8.0)
	attacker.set("boarding_contact_grace_duration", 0.0)
	attacker.set("boarding_prep_duration", 1.0)
	attacker.set("boarding_prep_timer", 0.0)
	attacker.set("boarding_contact_timer", 2.0)
	attacker.set("boarding_hook_timer", 2.0)
	attacker.set("_initial_rope_deployed", true)
	attacker.set("_full_rope_deployed", true)
	attacker.set("base_collision_radius", 2.0)
	attacker.set("width_multiplier", 1.0)
	attacker.set("length_multiplier", 1.0)
	attacker.global_position = Vector3.ZERO
	attacker.set_meta("boarding_contact_mode", "head_on")

	var defender: Node = AttackerScript.new()
	add_child(defender)
	defender.set("team", "player")
	defender.set("current_speed", 0.0)
	defender.set("base_collision_radius", 2.0)
	defender.set("width_multiplier", 1.0)
	defender.set("length_multiplier", 1.0)
	defender.global_position = Vector3(5.3, 0.0, 0.0)
	attacker.set("boarding_target", defender)
	defender.set("boarding_attacker", attacker)

	BaseShipBoardingHelper.process_boarding_common(attacker, 0.2)
	if float(attacker.get("boarding_prep_timer")) <= 0.0:
		failures.append("hooked boarding should keep progressing through small distance jitter")
	if attacker.get("_initial_rope_deployed") != true:
		failures.append("hooked boarding should not clear ropes on minor distance jitter")

	attacker.free()
	defender.free()


func _verify_lost_contact_without_rope_does_not_drive_boarding_motion(failures: Array[String]) -> void:
	var attacker: Node = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("is_boarding", true)
	attacker.set("current_speed", 0.0)
	attacker.set("boarding_break_distance", 20.0)
	attacker.set("_initial_rope_deployed", false)
	attacker.set("_full_rope_deployed", false)
	attacker.global_position = Vector3.ZERO

	var defender := MockTarget.new()
	add_child(defender)
	defender.global_position = Vector3(12.0, 0.0, 0.0)
	attacker.set("boarding_target", defender)
	defender.set_boarding_attacker_ship(attacker)

	var before_pos: Vector3 = attacker.global_position
	attacker.call("_process_boarding", 0.5)
	var moved: float = attacker.global_position.distance_to(before_pos)
	if moved > 0.01:
		failures.append("boarding ship kept driving contact motion after rope visual was gone")
	if attacker.get("is_boarding") != true:
		failures.append("boarding lost-contact fixture canceled before the break distance")

	attacker.free()
	defender.free()


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


func _build_head_to_head_contact_pair() -> Dictionary:
	var attacker: Node3D = AttackerScript.new()
	add_child(attacker)
	attacker.set("team", "enemy")
	attacker.set("allow_boarding", true)
	attacker.set("current_speed", 1.6)
	attacker.set("max_boarding_distance", 9.0)
	attacker.global_position = Vector3(0.0, 0.0, 7.3)
	attacker.rotation = Vector3.ZERO
	_add_mock_crew(attacker, "enemy", 4)

	var target := MockTarget.new()
	add_child(target)
	target.alive_crew_count = 5
	target.global_position = Vector3.ZERO
	target.rotation = Vector3(0.0, PI, 0.0)
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
