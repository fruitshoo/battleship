extends Node

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const PlayerShipCrewHelper = preload("res://scripts/entities/ships/player_ship_crew_helper.gd")


class MockRaidShip:
	extends Node3D

	var team: String = "player"
	var auto_raid_enabled: bool = true
	var auto_raid_target: Node3D = null
	var auto_raid_eval_timer: float = 10.0
	var auto_raid_eval_interval: float = 10.0
	var auto_raid_min_defenders: int = 1
	var auto_raid_max_boarders: int = 2
	var auto_raid_threat_range: float = 14.0
	var auto_raid_min_hull_ratio: float = 0.35
	var is_boarding: bool = true
	var boarding_target: Node3D = null
	var is_sinking: bool = false
	var is_dying: bool = false
	var _initial_rope_deployed: bool = true
	var _full_rope_deployed: bool = true
	var cancel_calls: int = 0

	func get_hull_ratio() -> float:
		return 1.0

	func get_boarding_attacker_ship() -> Node3D:
		return null

	func get_boarding_target_ship() -> Node3D:
		return boarding_target

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.0, 3.0)

	func get_collision_distance_to(_other: Node3D) -> float:
		return 4.0

	func _is_side_boarding_approach(_target_ship: Node3D) -> bool:
		return true

	func has_boarding_rope_link_to(other_ship: Node3D) -> bool:
		return is_boarding and boarding_target == other_ship and _initial_rope_deployed

	func _cancel_boarding() -> void:
		cancel_calls += 1
		is_boarding = false
		boarding_target = null
		remove_meta("boarding_purpose")
		remove_meta("boarding_transfer_suppressed")


class MockEnemyShip:
	extends Node3D

	var team: String = "enemy"

	func _init() -> void:
		add_to_group("enemy")

	func get_team_tag() -> String:
		return team

	func is_sinking_or_dying() -> bool:
		return false

	func is_derelict_ship() -> bool:
		return false

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.0, 3.0)


class MockSoldier:
	extends Node3D

	var team: String = "player"
	var owned_ship: Node3D = null
	var home_ship: Node3D = null
	var recall_calls: int = 0
	var recall_link_ready: bool = false

	func is_player_team_soldier() -> bool:
		return team == "player"

	func is_enemy_team_soldier() -> bool:
		return team == "enemy"

	func is_dead_soldier() -> bool:
		return false

	func is_jumping_value() -> bool:
		return false

	func get_home_ship_node() -> Node3D:
		return home_ship

	func get_owned_ship_node() -> Node3D:
		return owned_ship

	func _try_evacuate_to_home() -> void:
		recall_calls += 1
		recall_link_ready = is_instance_valid(home_ship) and home_ship.has_boarding_rope_link_to(owned_ship)
		if recall_link_ready:
			var old_ship: Node3D = owned_ship
			owned_ship = home_ship
			EntityRegistry.move_soldier_ship(self, old_ship, home_ship)


func _ready() -> void:
	var failures: Array[String] = []
	_verify_auto_raid_recall_uses_existing_rope_before_cancel(failures)
	if failures.is_empty():
		print("[AutoRaidRecallContract] ok")
		return
	for failure in failures:
		push_error("[AutoRaidRecallContract] %s" % failure)
	get_tree().quit(1)


func _verify_auto_raid_recall_uses_existing_rope_before_cancel(failures: Array[String]) -> void:
	var player := MockRaidShip.new()
	add_child(player)
	player.global_position = Vector3.ZERO

	var target := MockEnemyShip.new()
	add_child(target)
	target.global_position = Vector3(4.0, 0.0, 0.0)

	player.auto_raid_target = target
	player.boarding_target = target
	player.set_meta("boarding_purpose", "auto_raid")
	player.set_meta("boarding_transfer_suppressed", true)

	var defender := MockSoldier.new()
	add_child(defender)
	defender.home_ship = player
	defender.owned_ship = player
	EntityRegistry.register_soldier(defender)

	var boarder := MockSoldier.new()
	add_child(boarder)
	boarder.home_ship = player
	boarder.owned_ship = target
	EntityRegistry.register_soldier(boarder)

	PlayerShipCrewHelper.update_auto_boarding_raid(player, 0.1)

	if boarder.recall_calls != 1:
		failures.append("auto raid did not ask the away boarder to return")
	if boarder.recall_link_ready != true:
		failures.append("auto raid canceled the rope before recalling the away boarder")
	if boarder.owned_ship != player:
		failures.append("away boarder did not return over the active rope link")
	if player.cancel_calls != 1:
		failures.append("auto raid did not clean up the boarding link after recall finished")

	EntityRegistry.unregister_soldier(defender)
	EntityRegistry.unregister_soldier(boarder)
