extends Node

const SoldierLifecycleHelper = preload("res://scripts/entities/soldiers/soldier_lifecycle_helper.gd")
const SoldierScript = preload("res://scripts/entities/soldiers/soldier.gd")


class MockShip:
	extends Node3D

	var team: String = "player"
	var is_sinking: bool = false
	var is_dying: bool = false
	var derelict_checks: int = 0

	func get_team_tag() -> String:
		return team

	func is_sinking_or_dying() -> bool:
		return is_sinking or is_dying

	func check_derelict_status() -> void:
		derelict_checks += 1


class MockSoldier:
	extends Node3D

	enum State {
		IDLE,
		DEAD,
	}

	const RANGED_DAMAGE_SOURCES := {}

	var current_state: int = State.IDLE
	var team: String = "player"
	var current_health: float = 10.0
	var max_health: float = 40.0
	var defense: float = 0.0
	var velocity: Vector3 = Vector3.ZERO
	var current_target: Node3D = null
	var attack_timer: float = 0.0
	var is_boarder_on_player_ship: bool = false
	var owned_ship: Node3D = null
	var home_ship: Node3D = null
	var _cached_level_manager: Node = null
	var death_pose_count: int = 0
	var recovery_pose_count: int = 0
	var soldier_level: int = 1
	var soldier_xp: float = 0.0
	var xp_awards: int = 0

	func _flash_hit() -> void:
		pass

	func _play_death_pose() -> void:
		death_pose_count += 1

	func _play_recovery_pose() -> void:
		recovery_pose_count += 1

	func add_soldier_xp(amount: float, _reason: String = "") -> void:
		soldier_xp += amount
		xp_awards += 1


func _ready() -> void:
	var failures: Array[String] = []
	_verify_player_combat_damage_incapacitates(failures)
	_verify_defense_reduction_mitigates_player_damage(failures)
	_verify_heal_full_recovers_incapacitated_player(failures)
	_verify_recovery_uses_ship_medical_upgrade_stats(failures)
	_verify_player_soldier_level_progression(failures)
	_verify_enemy_combat_damage_still_dies(failures)
	_verify_player_drowning_still_dies(failures)
	if failures.is_empty():
		print("[SoldierIncapacitationContract] ok")
		return
	for failure in failures:
		push_error("[SoldierIncapacitationContract] %s" % failure)
	get_tree().quit(1)


func _make_ship(team: String) -> MockShip:
	var ship := MockShip.new()
	ship.team = team
	add_child(ship)
	return ship


func _make_soldier(team: String, ship: MockShip) -> MockSoldier:
	var soldier := MockSoldier.new()
	soldier.team = team
	soldier.owned_ship = ship
	soldier.home_ship = ship
	soldier.current_health = 8.0
	add_child(soldier)
	soldier.add_to_group("soldiers")
	return soldier


func _verify_player_combat_damage_incapacitates(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	var soldier := _make_soldier("player", ship)

	SoldierLifecycleHelper.take_damage(soldier, 20.0, Vector3.ZERO, "sword")

	if soldier.current_state != soldier.State.DEAD:
		failures.append("player soldier did not enter dead-state combat exclusion when incapacitated")
	if soldier.get_meta("incapacitated", false) != true:
		failures.append("player soldier combat defeat was not marked as incapacitated")
	if soldier.current_health != 0.0:
		failures.append("incapacitated player soldier health was not clamped to zero")
	if soldier.is_in_group("soldiers"):
		failures.append("incapacitated player soldier remained in soldiers group")
	if soldier.death_pose_count <= 0:
		failures.append("incapacitated player soldier did not play the downed pose")


func _verify_defense_reduction_mitigates_player_damage(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	var soldier := _make_soldier("player", ship)
	soldier.current_health = 100.0
	soldier.max_health = 100.0
	soldier.set_meta("defense_reduction", 0.2)

	SoldierLifecycleHelper.take_damage(soldier, 10.0, Vector3.ZERO, "sword")

	if not is_equal_approx(soldier.current_health, 92.0):
		failures.append("defense reduction did not mitigate player soldier damage: %.2f" % soldier.current_health)


func _verify_heal_full_recovers_incapacitated_player(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	var soldier := _make_soldier("player", ship)

	SoldierLifecycleHelper.take_damage(soldier, 20.0, Vector3.ZERO, "sword")
	SoldierLifecycleHelper.heal_full(soldier)

	if soldier.current_state != soldier.State.IDLE:
		failures.append("heal_full did not return incapacitated player soldier to idle")
	if soldier.get_meta("incapacitated", false) == true:
		failures.append("heal_full did not clear incapacitated marker")
	if not soldier.is_in_group("soldiers"):
		failures.append("recovered player soldier did not rejoin soldiers group")
	if soldier.current_health != soldier.max_health:
		failures.append("heal_full did not restore incapacitated player soldier to full health")
	if soldier.recovery_pose_count <= 0:
		failures.append("heal_full did not play the recovery pose")


func _verify_recovery_uses_ship_medical_upgrade_stats(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	ship.set_meta("incapacitated_recovery_health_ratio", 0.6)
	var soldier := _make_soldier("player", ship)

	SoldierLifecycleHelper.take_damage(soldier, 20.0, Vector3.ZERO, "sword")
	SoldierLifecycleHelper._try_recover_incapacitated(soldier)

	if soldier.current_state != soldier.State.IDLE:
		failures.append("medical recovery stat did not recover incapacitated soldier")
	var expected_health := soldier.max_health * 0.6
	if not is_equal_approx(soldier.current_health, expected_health):
		failures.append("medical recovery stat did not set upgraded recovery health: %.2f vs %.2f" % [soldier.current_health, expected_health])
	if soldier.xp_awards != 1 or not is_equal_approx(soldier.soldier_xp, 1.0):
		failures.append("recovered soldier did not receive survival level xp")


func _verify_player_soldier_level_progression(failures: Array[String]) -> void:
	var soldier = SoldierScript.new()
	soldier.team = "player"
	soldier.add_soldier_xp(1.0, "contract")
	if soldier.get_soldier_level_value() != 1 or not is_equal_approx(soldier.get_soldier_xp_value(), 1.0):
		failures.append("player soldier level changed before reaching level xp requirement")

	soldier.add_soldier_xp(1.0, "contract")
	if soldier.get_soldier_level_value() != 2:
		failures.append("player soldier did not reach level 2 at xp requirement")
	if not is_equal_approx(float(soldier.get_meta("soldier_level_attack_bonus", 0.0)), 0.75):
		failures.append("player soldier level 2 attack bonus was not applied")

	soldier.add_soldier_xp(100.0, "contract")
	if soldier.get_soldier_level_value() != 5:
		failures.append("player soldier level did not clamp at cap")
	if not is_equal_approx(soldier.get_soldier_xp_value(), 0.0):
		failures.append("player soldier xp did not clear at level cap")
	soldier.free()


func _verify_enemy_combat_damage_still_dies(failures: Array[String]) -> void:
	var ship := _make_ship("enemy")
	var soldier := _make_soldier("enemy", ship)

	SoldierLifecycleHelper.take_damage(soldier, 20.0, Vector3.ZERO, "sword")

	if soldier.current_state != soldier.State.DEAD:
		failures.append("enemy soldier did not die from lethal combat damage")
	if soldier.get_meta("incapacitated", false) == true:
		failures.append("enemy soldier was incorrectly marked incapacitated")
	if soldier.death_pose_count <= 0:
		failures.append("enemy soldier combat death did not play the death pose")


func _verify_player_drowning_still_dies(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	var soldier := _make_soldier("player", ship)
	soldier.set_meta("last_death_cause", "drowned")
	soldier.set_meta("last_damage_source", "drowned")

	SoldierLifecycleHelper.die(soldier)

	if soldier.current_state != soldier.State.DEAD:
		failures.append("drowned player soldier did not die")
	if soldier.get_meta("incapacitated", false) == true:
		failures.append("drowned player soldier was incorrectly marked incapacitated")
