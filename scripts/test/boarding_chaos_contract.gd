extends Node

const SoldierLifecycleHelper = preload("res://scripts/entities/soldiers/soldier_lifecycle_helper.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")


class MockShip:
	extends Node3D

	var team: String = "player"
	var fire_ticks: int = 0
	var fire_damage_total: float = 0.0
	var is_boarding: bool = false
	var boarding_target: Node3D = null

	func take_fire_damage(amount: float, _duration: float) -> void:
		fire_ticks += 1
		fire_damage_total += amount

	func get_team_tag() -> String:
		return team


class MockSoldier:
	extends Node3D

	enum State {
		IDLE,
		DEAD,
	}

	var current_state: int = State.IDLE
	var team: String = "enemy"
	var owned_ship: Node3D = null
	var home_ship: Node3D = null
	var current_target: Node3D = null
	var is_boarder_on_player_ship: bool = false
	var chaos_duration_timer: float = 0.1
	var chaos_tick_timer: float = 0.01
	var chaos_damage_per_tick: float = 5.0
	var evacuation_attempts: int = 0

	func get_team_tag() -> String:
		return team

	func _try_evacuate_to_home() -> void:
		evacuation_attempts += 1

	func move_to_target(target: Node3D) -> void:
		current_target = target


func _ready() -> void:
	var failures: Array[String] = []
	_verify_enemy_boarder_does_not_retreat_on_timer(failures)
	_verify_enemy_boarder_pauses_chaos_while_fighting_defender(failures)
	_verify_enemy_boarder_pauses_chaos_while_support_rescue_boarding(failures)
	if failures.is_empty():
		print("[BoardingChaosContract] ok")
		return
	for failure in failures:
		push_error("[BoardingChaosContract] %s" % failure)
	get_tree().quit(1)


func _verify_enemy_boarder_does_not_retreat_on_timer(failures: Array[String]) -> void:
	var player_ship := MockShip.new()
	player_ship.team = "player"
	add_child(player_ship)

	var enemy_home := MockShip.new()
	enemy_home.team = "enemy"
	add_child(enemy_home)
	enemy_home.global_position = Vector3(40.0, 0.0, 0.0)

	var boarder := MockSoldier.new()
	add_child(boarder)
	boarder.owned_ship = player_ship
	boarder.home_ship = enemy_home
	boarder.global_position = Vector3.ZERO

	SoldierLifecycleHelper.update_boarding_chaos(boarder, 0.25)

	if boarder.evacuation_attempts != 0:
		failures.append("enemy boarder attempted timed evacuation after chaos timer expired")
	if boarder.owned_ship != player_ship:
		failures.append("enemy boarder left the player ship after timed chaos update")
	if boarder.is_boarder_on_player_ship != true:
		failures.append("enemy boarder was not marked as active on player ship")
	if player_ship.fire_ticks <= 0:
		failures.append("enemy boarder did not keep applying boarding chaos damage")


func _verify_enemy_boarder_pauses_chaos_while_fighting_defender(failures: Array[String]) -> void:
	var player_ship := MockShip.new()
	player_ship.team = "player"
	add_child(player_ship)

	var boarder := MockSoldier.new()
	add_child(boarder)
	boarder.team = "enemy"
	boarder.owned_ship = player_ship
	boarder.global_position = Vector3.ZERO
	boarder.chaos_tick_timer = 0.01

	var defender := MockSoldier.new()
	add_child(defender)
	defender.team = "player"
	defender.owned_ship = player_ship
	defender.global_position = Vector3(0.5, 0.0, 0.0)
	boarder.current_target = defender

	SoldierLifecycleHelper.update_boarding_chaos(boarder, 0.25)

	if player_ship.fire_ticks != 0:
		failures.append("enemy boarder kept raising boarding chaos while fighting a defender")
	if boarder.chaos_tick_timer < 0.35:
		failures.append("enemy boarder chaos timer was not held while fighting a defender")

	defender.queue_free()
	boarder.queue_free()
	player_ship.queue_free()


func _verify_enemy_boarder_pauses_chaos_while_support_rescue_boarding(failures: Array[String]) -> void:
	var player_ship := MockShip.new()
	player_ship.team = "player"
	add_child(player_ship)

	var support_ship := MockShip.new()
	support_ship.team = "player"
	support_ship.is_boarding = true
	support_ship.boarding_target = player_ship
	support_ship.set_meta("support_fleet_ship", true)
	support_ship.set_meta("boarding_purpose", "support_rescue_boarding")
	add_child(support_ship)
	EntityRegistry.register_ship(support_ship)

	var boarder := MockSoldier.new()
	add_child(boarder)
	boarder.team = "enemy"
	boarder.owned_ship = player_ship
	boarder.global_position = Vector3.ZERO
	boarder.chaos_tick_timer = 0.01

	SoldierLifecycleHelper.update_boarding_chaos(boarder, 0.25)

	if player_ship.fire_ticks != 0:
		failures.append("enemy boarder kept raising boarding chaos while support rescue boarding was active")
	if boarder.chaos_tick_timer < 0.35:
		failures.append("enemy boarder chaos timer was not held during support rescue boarding")

	EntityRegistry.unregister_ship(support_ship)
	boarder.queue_free()
	support_ship.queue_free()
	player_ship.queue_free()
