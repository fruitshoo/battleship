extends Node

const ChaserShipBoardingHelper = preload("res://scripts/entities/ships/chaser_ship_boarding_helper.gd")
const ChaserShipMinionHelper = preload("res://scripts/entities/ships/chaser_ship_minion_helper.gd")
const BaseShipBoardingHelper = preload("res://scripts/entities/ships/base_ship_boarding_helper.gd")
const BaseShipStatusHelper = preload("res://scripts/entities/ships/base_ship_status_helper.gd")
const SoldierShipHelper = preload("res://scripts/entities/soldiers/soldier_ship_helper.gd")
const SoldierAiHelper = preload("res://scripts/entities/soldiers/soldier_ai_helper.gd")
const SoldierBoardingHelper = preload("res://scripts/entities/soldiers/soldier_boarding_helper.gd")
const SoldierSpeechHelper = preload("res://scripts/entities/soldiers/soldier_speech_helper.gd")
const SupportBoardingHelper = preload("res://scripts/entities/ships/support_boarding_helper.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const CannonScript = preload("res://scripts/entities/launchers/cannon.gd")
const SingigeonLauncherScript = preload("res://scripts/entities/launchers/singigeon_launcher.gd")
const BallistaLauncherScript = preload("res://scripts/entities/launchers/ballista_launcher.gd")
const JanggunLauncherScript = preload("res://scripts/entities/launchers/janggun_launcher.gd")


class MockTargetShip:
	extends Node3D

	var team: String = "enemy"
	var boarding_attacker: Node3D = null
	var is_derelict: bool = false
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var deck_friendly_crew_count: int = 0
	var deck_hostile_boarder_count: int = 0
	var is_sinking: bool = false
	var is_dying: bool = false
	var boarding_capture_duration: float = 10.0
	var boarding_capture_damage_tick: float = 10.0
	var boarding_capture_progress: float = 0.0
	var max_hull_hp: float = 100.0
	var _deck_overrun_announced: bool = false
	var _cached_hud: Node = null
	var damage_taken: float = 0.0

	func get_team_tag() -> String:
		return team

	func set_boarding_attacker_ship(attacker: Node3D) -> void:
		boarding_attacker = attacker

	func get_boarding_attacker_ship() -> Node3D:
		return boarding_attacker

	func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO, _damage_source: String = "") -> void:
		damage_taken += amount


class MockSupportShip:
	extends Node3D

	var team: String = "player"
	var is_boarding: bool = false
	var boarding_target: Node3D = null
	var boarding_timer: float = 9.0
	var boarding_prep_timer: float = 9.0
	var boarding_contact_timer: float = 9.0
	var boarding_hook_timer: float = 9.0
	var boarding_secondary_rope_timer: float = 9.0
	var boarding_break_distance: float = 12.0
	var max_boarding_distance: float = 9.0
	var _initial_rope_deployed: bool = true
	var _full_rope_deployed: bool = true
	var process_boarding_calls: int = 0
	var clear_rope_calls: int = 0
	var clear_latch_calls: int = 0
	var cancel_calls: int = 0
	var die_calls: int = 0
	var alive_crew_count: int = 3
	var side_boarding: bool = true
	var head_on_boarding: bool = false
	var cleanup_boarding: bool = false
	var collision_distance: float = 8.0
	var target: Node3D = null
	var support_hold_formation: bool = false

	func _init() -> void:
		set_meta("support_fleet_ship", true)

	func get_team_tag() -> String:
		return team

	func get_alive_crew_count() -> int:
		return alive_crew_count

	func get_collision_distance_to(_other: Node3D) -> float:
		return collision_distance

	func _is_side_boarding_approach(_target_ship: Node3D) -> bool:
		return side_boarding

	func _can_force_head_on_boarding(_target_ship: Node3D) -> bool:
		return head_on_boarding

	func _can_force_cleanup_boarding(_target_ship: Node3D) -> bool:
		return cleanup_boarding

	func _clear_ropes() -> void:
		clear_rope_calls += 1

	func _clear_boarding_latch() -> void:
		clear_latch_calls += 1

	func _process_boarding(_delta: float) -> void:
		process_boarding_calls += 1

	func _cancel_boarding() -> void:
		cancel_calls += 1
		is_boarding = false
		boarding_target = null

	func die() -> void:
		die_calls += 1


class MockWeaponOwner:
	extends Node3D

	var deck_is_overrun: bool = false

	func _init() -> void:
		add_to_group("ships")

	func are_weapons_disabled() -> bool:
		return deck_is_overrun

	func is_combat_disabled() -> bool:
		return false


class MockTransferShip:
	extends Node3D

	var team: String = "player"
	var boarding_target: Node3D = null
	var deck_height: float = 0.75
	var deck_half_extents: Vector2 = Vector2(2.0, 3.0)

	func _init() -> void:
		var soldiers := Node3D.new()
		soldiers.name = "Soldiers"
		add_child(soldiers)

	func get_team_tag() -> String:
		return team

	func get_deck_half_extents() -> Vector2:
		return deck_half_extents


class MockTransferSoldier:
	extends Node3D

	var team: String = "player"
	var owned_ship: Node3D = null
	var home_ship: Node3D = null
	var _is_jumping: bool = false
	var is_stationary: bool = false
	var boarding_status: String = "on_deck"

	func get_team_tag() -> String:
		return team

	func set_team(next_team: String) -> void:
		team = next_team

	func is_dead() -> bool:
		return false

	func set_boarding_status(next_status: String) -> void:
		boarding_status = next_status
		set_meta("boarding_status", boarding_status)

	func get_boarding_status_value() -> String:
		return boarding_status

	func _try_evacuate_to_home() -> void:
		SoldierBoardingHelper.try_evacuate_to_home(self)


class MockCombatSoldier:
	extends Node3D

	enum State {
		IDLE,
		MOVE,
		ATTACK,
		DEAD,
	}

	var team: String = "player"
	var owned_ship: Node3D = null
	var current_state: int = State.MOVE
	var current_target: Node3D = null
	var current_weapon: Node3D = null
	var detection_range: float = 35.0
	var is_captain: bool = false
	var is_stationary: bool = false
	var _is_jumping: bool = false

	func get_team_tag() -> String:
		return team

	func is_dead_soldier() -> bool:
		return false

	func get_current_state_value() -> int:
		return current_state

	func _change_state(next_state: int) -> void:
		current_state = next_state

	func find_nearest_hostile_on_owned_ship() -> Node3D:
		return SoldierShipHelper.find_nearest_hostile_on_owned_ship(self)


func _ready() -> void:
	var failures: Array[String] = []
	_verify_support_ship_can_start_boarding_link(failures)
	_verify_support_ship_waits_for_contact_before_boarding(failures)
	_verify_support_ship_rescues_overrun_player_deck(failures)
	_verify_support_ship_rescues_contested_player_deck(failures)
	_verify_support_rescue_boarding_relaxes_bad_alignment(failures)
	_verify_support_rescue_waits_until_boarding_motion_range(failures)
	_verify_support_hold_formation_ignores_normal_threats(failures)
	_verify_support_hold_formation_allows_boarding_attacker(failures)
	_verify_support_free_assist_recalls_near_player(failures)
	_verify_boarding_transfer_snaps_soldier_to_target_deck(failures)
	_verify_boarding_transfer_wave_sends_multiple_soldiers(failures)
	await _verify_boarding_transfer_tracks_moving_target_deck(failures)
	_verify_soldier_deck_recovery_repairs_parent_and_bounds(failures)
	_verify_soldier_boarding_status_marks_returning(failures)
	_verify_player_support_boarding_cancels_when_target_is_missing(failures)
	_verify_overrun_deck_suppresses_ship_weapons(failures)
	_verify_player_deck_emergency_speeds_support_assist(failures)
	_verify_soldier_retargets_hostile_boarder_on_owned_ship(failures)
	_verify_enemy_boarder_speaks_only_on_player_deck(failures)
	_verify_support_rescue_boarding_holds_player_capture_progress(failures)
	_verify_support_rescue_boarders_return_after_deck_safe(failures)
	_verify_support_attack_boarders_return_after_enemy_deck_safe(failures)
	if failures.is_empty():
		print("[SupportBoardingContract] ok")
		return
	for failure in failures:
		push_error("[SupportBoardingContract] %s" % failure)
	get_tree().quit(1)


func _verify_support_ship_can_start_boarding_link(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO

	var target := MockTargetShip.new()
	add_child(target)
	target.global_position = Vector3(8.0, 0.0, 0.0)

	var started: bool = ChaserShipMinionHelper._try_start_support_boarding(support, target, 0.1)

	if started != true or support.is_boarding != true:
		failures.append("support ship did not enter boarding state against assist target")
	if support.boarding_target != target:
		failures.append("support boarding target was not assigned")
	if str(support.get_meta("boarding_purpose", "")) != SupportBoardingHelper.SUPPORT_BOARDING_PURPOSE:
		failures.append("support boarding purpose meta was not set")
	if str(support.get_meta("boarding_contact_mode", "")) != "side":
		failures.append("support boarding did not preserve side contact mode")
	if target.get_boarding_attacker_ship() != support:
		failures.append("support boarding did not register attacker on target")
	if support.clear_rope_calls <= 0:
		failures.append("support boarding did not reset existing ropes")
	if support.clear_latch_calls <= 0:
		failures.append("support boarding did not clear stale latch")
	if support.process_boarding_calls <= 0:
		failures.append("support boarding did not hand off to common boarding process")
	if support.boarding_timer != 0.0 or support.boarding_prep_timer != 0.0:
		failures.append("support boarding timers were not reset")
	if support._initial_rope_deployed == true or support._full_rope_deployed == true:
		failures.append("support boarding rope deployment flags were not reset")


func _verify_support_ship_waits_for_contact_before_boarding(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	support.collision_distance = 8.0

	var target := MockTargetShip.new()
	add_child(target)
	target.global_position = Vector3(11.2, 0.0, 0.0)

	var started_far: bool = ChaserShipMinionHelper._try_start_support_boarding(support, target, 0.1)
	if started_far == true or support.is_boarding == true:
		failures.append("support ship started boarding before contact range")

	target.global_position = Vector3(8.4, 0.0, 0.0)
	support.side_boarding = false
	support.head_on_boarding = true
	support.cleanup_boarding = true
	var started_cleanup: bool = ChaserShipMinionHelper._try_start_support_boarding(support, target, 0.1)
	if started_cleanup != true or support.is_boarding != true:
		failures.append("support ship did not board after cleanup contact became valid")
	if str(support.get_meta("boarding_contact_mode", "")) != "cleanup":
		failures.append("support boarding did not prefer cleanup contact over head-on contact")

	target.queue_free()
	support.queue_free()


func _verify_support_ship_rescues_overrun_player_deck(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	support.collision_distance = 8.0

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3(8.4, 0.0, 0.0)
	player.deck_is_overrun = true
	player.deck_friendly_crew_count = 0
	player.deck_hostile_boarder_count = 2
	support.target = player

	var enemy_attacker := MockTargetShip.new()
	add_child(enemy_attacker)
	enemy_attacker.team = "enemy"
	enemy_attacker.global_position = Vector3(8.4, 0.0, 2.0)
	player.set_boarding_attacker_ship(enemy_attacker)

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != player:
		failures.append("support ship did not select overrun player deck as rescue target")

	var started: bool = ChaserShipMinionHelper._try_start_support_boarding(support, player, 0.1)
	if started != true or support.boarding_target != player:
		failures.append("support ship did not start rescue boarding onto overrun player deck")
	if str(support.get_meta("boarding_purpose", "")) != SupportBoardingHelper.SUPPORT_RESCUE_BOARDING_PURPOSE:
		failures.append("support rescue boarding purpose meta was not set")
	if player.get_boarding_attacker_ship() != enemy_attacker:
		failures.append("support rescue boarding overwrote the enemy boarding attacker")

	enemy_attacker.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_ship_rescues_contested_player_deck(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(7.0, 0.0, -1.0)
	support.collision_distance = 8.0

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	player.deck_is_contested = true
	player.deck_friendly_crew_count = 3
	player.deck_hostile_boarder_count = 1
	support.target = player

	var enemy_attacker := MockTargetShip.new()
	add_child(enemy_attacker)
	enemy_attacker.team = "enemy"
	enemy_attacker.global_position = Vector3(4.0, 0.0, 0.0)
	EntityRegistry.register_ship(enemy_attacker)

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != player:
		failures.append("support ship did not prioritize contested player deck rescue")

	var started: bool = ChaserShipMinionHelper._try_start_support_boarding(support, player, 0.1)
	if started != true or support.boarding_target != player:
		failures.append("support ship did not start rescue boarding onto contested player deck")
	if str(support.get_meta("boarding_purpose", "")) != SupportBoardingHelper.SUPPORT_RESCUE_BOARDING_PURPOSE:
		failures.append("support contested rescue boarding purpose meta was not set")

	EntityRegistry.unregister_ship(enemy_attacker)
	enemy_attacker.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_rescue_boarding_relaxes_bad_alignment(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	support.collision_distance = 8.0
	support.side_boarding = false
	support.cleanup_boarding = false

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3(8.8, 0.0, 0.0)
	player.deck_is_overrun = true
	player.deck_friendly_crew_count = 0
	player.deck_hostile_boarder_count = 2
	support.target = player

	var started: bool = ChaserShipMinionHelper._try_start_support_boarding(support, player, 0.1)
	if started != true or support.boarding_target != player:
		failures.append("support rescue boarding stayed in assist mode when close but not side-aligned")
	if str(support.get_meta("boarding_contact_mode", "")) != "cleanup":
		failures.append("support rescue boarding did not fall back to cleanup contact when alignment was poor")

	player.queue_free()
	support.queue_free()


func _verify_support_rescue_waits_until_boarding_motion_range(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	support.collision_distance = 8.0
	support.side_boarding = false
	support.cleanup_boarding = false

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3(9.8, 0.0, 0.0)
	player.deck_is_overrun = true
	player.deck_friendly_crew_count = 0
	player.deck_hostile_boarder_count = 2
	support.target = player

	var started_far: bool = ChaserShipMinionHelper._try_start_support_boarding(support, player, 0.1)
	if started_far == true or support.is_boarding == true:
		failures.append("support rescue boarding started before boarding motion range and can freeze outside contact")

	player.global_position = Vector3(8.8, 0.0, 0.0)
	var started_close: bool = ChaserShipMinionHelper._try_start_support_boarding(support, player, 0.1)
	if started_close != true or support.boarding_target != player:
		failures.append("support rescue boarding did not start once inside boarding motion range")

	player.queue_free()
	support.queue_free()


func _verify_support_hold_formation_ignores_normal_threats(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	support.support_hold_formation = true

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy := MockTargetShip.new()
	add_child(enemy)
	enemy.team = "enemy"
	enemy.global_position = Vector3(12.0, 0.0, 0.0)
	EntityRegistry.register_ship(enemy)

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != null:
		failures.append("support hold formation selected a normal threat")
	if support.has_meta("support_assist_target_id"):
		failures.append("support hold formation kept a normal-threat assist lock")

	EntityRegistry.unregister_ship(enemy)
	enemy.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_hold_formation_allows_boarding_attacker(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	support.support_hold_formation = true

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy_attacker := MockTargetShip.new()
	add_child(enemy_attacker)
	enemy_attacker.team = "enemy"
	enemy_attacker.global_position = Vector3(10.0, 0.0, 0.0)
	player.set_boarding_attacker_ship(enemy_attacker)

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != enemy_attacker:
		failures.append("support hold formation ignored the player boarding attacker")

	enemy_attacker.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_free_assist_recalls_near_player(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(33.5, 0.0, 0.0)
	support.support_hold_formation = false

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy := MockTargetShip.new()
	add_child(enemy)
	enemy.team = "enemy"
	enemy.global_position = Vector3(12.0, 0.0, 0.0)
	EntityRegistry.register_ship(enemy)

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != null:
		failures.append("support free assist stayed in combat after exceeding player soft recall distance")
	if support.has_meta("support_assist_target_id"):
		failures.append("support free assist kept target lock after player soft recall")
	if ChaserShipMinionHelper._get_support_assist_rowing_wind_floor(false) < 0.78:
		failures.append("support free assist rowing wind floor is too weak for player follow")
	if ChaserShipMinionHelper._get_support_assist_rowing_speed_multiplier(42.0, false) <= 1.20:
		failures.append("support free assist rowing speed bonus is too weak at follow distance")

	EntityRegistry.unregister_ship(enemy)
	enemy.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_boarding_transfer_snaps_soldier_to_target_deck(failures: Array[String]) -> void:
	var source := MockTransferShip.new()
	add_child(source)
	source.team = "player"

	var target := MockTransferShip.new()
	add_child(target)
	target.team = "enemy"
	target.deck_height = 0.8
	target.deck_half_extents = Vector2(2.0, 3.0)
	target.global_position = Vector3(20.0, 0.0, 0.0)
	source.boarding_target = target

	var soldier := MockTransferSoldier.new()
	source.get_node("Soldiers").add_child(soldier)
	soldier.owned_ship = source
	soldier.position = Vector3(0.0, 0.4, 0.0)

	BaseShipBoardingHelper.transfer_one_soldier(source)

	if soldier.get_parent() != target.get_node("Soldiers"):
		failures.append("boarding transfer did not reparent soldier under target Soldiers node")
	if soldier.owned_ship != target:
		failures.append("boarding transfer did not move soldier ownership to target ship")
	if soldier._is_jumping != true:
		failures.append("boarding transfer did not mark soldier as jumping during deck transfer")
	if soldier.get_boarding_status_value() != "boarding":
		failures.append("boarding transfer did not mark soldier boarding status during transfer")

	BaseShipBoardingHelper._finish_transfer_landing(soldier.get_instance_id(), target.get_instance_id(), Vector3(99.0, -4.0, 99.0))

	if soldier._is_jumping != false:
		failures.append("boarding transfer did not clear jumping state after landing")
	if soldier.get_boarding_status_value() != "on_deck":
		failures.append("boarding transfer did not restore soldier status after landing")
	if not is_equal_approx(soldier.position.y, target.deck_height):
		failures.append("boarding transfer landing did not snap soldier to target deck height")
	if absf(soldier.position.x) > target.deck_half_extents.x or absf(soldier.position.z) > target.deck_half_extents.y:
		failures.append("boarding transfer landing did not clamp soldier inside target deck bounds")

	target.queue_free()
	source.queue_free()


func _verify_boarding_transfer_wave_sends_multiple_soldiers(failures: Array[String]) -> void:
	var source := MockTransferShip.new()
	add_child(source)
	source.team = "player"
	source.global_position = Vector3.ZERO

	var target := MockTransferShip.new()
	add_child(target)
	target.team = "enemy"
	target.global_position = Vector3(6.0, 0.0, 0.0)
	source.boarding_target = target

	for i in range(4):
		var boarder := MockTransferSoldier.new()
		boarder.team = "player"
		boarder.owned_ship = source
		boarder.position = Vector3(float(i) * 0.15, 0.4, 0.0)
		source.get_node("Soldiers").add_child(boarder)

	for i in range(4):
		var defender := MockTransferSoldier.new()
		defender.team = "enemy"
		defender.owned_ship = target
		defender.position = Vector3(float(i) * 0.15, 0.4, 0.0)
		target.get_node("Soldiers").add_child(defender)

	var transferred_count := BaseShipBoardingHelper.transfer_boarding_wave(source)
	var source_player_count := 0
	var target_player_count := 0
	for child in source.get_node("Soldiers").get_children():
		if child.has_method("get_team_tag") and child.get_team_tag() == "player":
			source_player_count += 1
	for child in target.get_node("Soldiers").get_children():
		if child.has_method("get_team_tag") and child.get_team_tag() == "player":
			target_player_count += 1

	if transferred_count < 2:
		failures.append("boarding transfer wave did not send multiple soldiers")
	if target_player_count != transferred_count:
		failures.append("boarding transfer wave count did not match soldiers moved to target")
	if source_player_count != 4 - transferred_count:
		failures.append("boarding transfer wave did not remove moved soldiers from source deck")

	target.queue_free()
	source.queue_free()


func _verify_boarding_transfer_tracks_moving_target_deck(failures: Array[String]) -> void:
	var source := MockTransferShip.new()
	add_child(source)
	source.team = "player"
	source.global_position = Vector3.ZERO

	var target := MockTransferShip.new()
	add_child(target)
	target.team = "enemy"
	target.deck_height = 0.8
	target.deck_half_extents = Vector2(2.0, 3.0)
	target.global_position = Vector3(6.0, 0.0, 0.0)
	source.boarding_target = target

	var soldier := MockTransferSoldier.new()
	source.get_node("Soldiers").add_child(soldier)
	soldier.owned_ship = source
	soldier.position = Vector3(0.0, 0.4, 0.0)

	BaseShipBoardingHelper.transfer_one_soldier(source)

	for frame_index in range(72):
		target.global_position += Vector3(0.06, 0.0, 0.02)
		target.rotation.y += 0.012
		await get_tree().process_frame

	if soldier.get_parent() != target.get_node("Soldiers"):
		failures.append("moving target boarding transfer did not keep soldier under target Soldiers node")
	if soldier.owned_ship != target:
		failures.append("moving target boarding transfer did not keep soldier ownership on target ship")
	if soldier._is_jumping != false:
		failures.append("moving target boarding transfer left soldier stuck in jumping state")
	if soldier.get_boarding_status_value() != "on_deck":
		failures.append("moving target boarding transfer did not restore soldier status after landing")
	if not is_equal_approx(soldier.position.y, target.deck_height):
		failures.append("moving target boarding transfer did not land at target deck height")
	if absf(soldier.position.x) > target.deck_half_extents.x or absf(soldier.position.z) > target.deck_half_extents.y:
		failures.append("moving target boarding transfer landed outside moving target deck bounds")

	target.queue_free()
	source.queue_free()


func _verify_soldier_deck_recovery_repairs_parent_and_bounds(failures: Array[String]) -> void:
	var ship := MockTransferShip.new()
	add_child(ship)
	ship.deck_height = 0.85
	ship.deck_half_extents = Vector2(1.6, 2.4)
	ship.global_position = Vector3(11.0, 0.0, -7.0)
	ship.rotation.y = 0.7

	var stray_parent := Node3D.new()
	add_child(stray_parent)

	var soldier := MockTransferSoldier.new()
	stray_parent.add_child(soldier)
	soldier.owned_ship = ship
	soldier.global_position = ship.to_global(Vector3(12.0, -2.5, -14.0))

	SoldierShipHelper.keep_within_owned_ship_bounds(soldier)

	var soldier_local: Vector3 = ship.to_local(soldier.global_position)
	if soldier.get_parent() != ship.get_node("Soldiers"):
		failures.append("soldier deck recovery did not reparent stray soldier under ship Soldiers node")
	if not is_equal_approx(soldier_local.y, ship.deck_height):
		failures.append("soldier deck recovery did not snap stray soldier to deck height")
	if absf(soldier_local.x) > ship.deck_half_extents.x or absf(soldier_local.z) > ship.deck_half_extents.y:
		failures.append("soldier deck recovery did not clamp stray soldier inside deck bounds")

	stray_parent.queue_free()
	ship.queue_free()


func _verify_soldier_boarding_status_marks_returning(failures: Array[String]) -> void:
	var home := MockTransferShip.new()
	add_child(home)

	var target := MockTransferShip.new()
	add_child(target)

	var soldier := MockTransferSoldier.new()
	target.get_node("Soldiers").add_child(soldier)
	soldier.home_ship = home
	soldier.owned_ship = target
	soldier.position = Vector3.ZERO

	SoldierBoardingHelper.jump_to_ship(soldier, home, true)

	if soldier.get_boarding_status_value() != "returning":
		failures.append("soldier return jump did not mark boarding status as returning")
	if soldier._is_jumping != true:
		failures.append("soldier return jump did not mark soldier as jumping")

	home.queue_free()
	target.queue_free()


func _verify_player_support_boarding_cancels_when_target_is_missing(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.is_boarding = true
	support.boarding_target = null

	ChaserShipBoardingHelper.process_boarding(support, 0.1)

	if support.cancel_calls != 1:
		failures.append("player support ship did not cancel missing-target boarding")
	if support.die_calls != 0:
		failures.append("player support ship died when boarding target was missing")


func _verify_overrun_deck_suppresses_ship_weapons(failures: Array[String]) -> void:
	var owner := MockWeaponOwner.new()
	add_child(owner)
	owner.deck_is_overrun = true

	var weapon_cases: Array[Dictionary] = [
		{"label": "cannon", "node": CannonScript.new(), "method": "_is_owner_weapon_ready"},
		{"label": "singigeon", "node": SingigeonLauncherScript.new(), "method": "_is_owner_combat_ready"},
		{"label": "ballista", "node": BallistaLauncherScript.new(), "method": "_is_owner_combat_ready"},
		{"label": "janggun", "node": JanggunLauncherScript.new(), "method": "_is_owner_combat_ready"},
	]

	for weapon_case in weapon_cases:
		var weapon: Node = weapon_case["node"]
		weapon.set("_owner_ship", owner)
		if weapon.call(str(weapon_case["method"])) == true:
			failures.append("%s stayed combat-ready after owner deck was overrun" % str(weapon_case["label"]))
		weapon.free()
	owner.queue_free()


func _verify_player_deck_emergency_speeds_support_assist(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(34.0, 0.0, 0.0)

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var attacker := MockTargetShip.new()
	add_child(attacker)
	attacker.global_position = Vector3(4.0, 0.0, 0.0)

	var normal_nav: Dictionary = ChaserShipMinionHelper._build_support_assist_navigation(support, attacker, 0)
	player.deck_is_overrun = true
	player.deck_hostile_boarder_count = 2
	var emergency_nav: Dictionary = ChaserShipMinionHelper._build_support_assist_navigation(support, attacker, 0)

	if float(emergency_nav.get("desired_speed_mult", 0.0)) <= float(normal_nav.get("desired_speed_mult", 0.0)):
		failures.append("player deck emergency did not increase support assist desired speed")
	if emergency_nav.get("permit_sprint") != true:
		failures.append("player deck emergency did not mark support assist as sprint-capable")
	if ChaserShipMinionHelper._get_support_assist_rowing_wind_floor(false) < 0.65:
		failures.append("support assist rowing wind floor is too weak for free combat")
	if ChaserShipMinionHelper._get_support_assist_rowing_wind_floor(true) <= ChaserShipMinionHelper._get_support_assist_rowing_wind_floor(false):
		failures.append("support emergency assist did not increase rowing wind floor")
	if ChaserShipMinionHelper._get_support_assist_rowing_speed_multiplier(42.0, false) <= 1.05:
		failures.append("support assist rowing speed multiplier is too weak at distance")
	if ChaserShipMinionHelper._get_support_assist_rowing_speed_multiplier(42.0, true) <= ChaserShipMinionHelper._get_support_assist_rowing_speed_multiplier(42.0, false):
		failures.append("support emergency assist did not increase rowing speed multiplier")

	attacker.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_soldier_retargets_hostile_boarder_on_owned_ship(failures: Array[String]) -> void:
	var player_ship := MockTargetShip.new()
	add_child(player_ship)
	player_ship.team = "player"
	player_ship.global_position = Vector3.ZERO

	var enemy_ship := MockTargetShip.new()
	add_child(enemy_ship)
	enemy_ship.team = "enemy"
	enemy_ship.global_position = Vector3(7.0, 0.0, 0.0)

	var defender := MockCombatSoldier.new()
	add_child(defender)
	defender.team = "player"
	defender.owned_ship = player_ship
	defender.global_position = Vector3.ZERO

	var remote_enemy := MockCombatSoldier.new()
	add_child(remote_enemy)
	remote_enemy.team = "enemy"
	remote_enemy.owned_ship = enemy_ship
	remote_enemy.global_position = Vector3(7.0, 0.0, 0.0)

	var boarder := MockCombatSoldier.new()
	add_child(boarder)
	boarder.team = "enemy"
	boarder.owned_ship = player_ship
	boarder.global_position = Vector3(0.9, 0.0, 0.0)

	EntityRegistry.register_soldier(defender)
	EntityRegistry.register_soldier(remote_enemy)
	EntityRegistry.register_soldier(boarder)
	defender.current_target = remote_enemy

	var nearest := SoldierShipHelper.find_nearest_enemy(defender)
	if nearest != boarder:
		failures.append("soldier targeting did not prioritize hostile boarder on owned ship")

	SoldierAiHelper.state_move(defender)
	if defender.current_target != boarder:
		failures.append("soldier move state did not retarget from cross-ship enemy to local boarder")
	if defender.current_state != defender.State.MOVE:
		failures.append("soldier retarget did not keep defender in move state")

	EntityRegistry.unregister_soldier(boarder)
	EntityRegistry.unregister_soldier(remote_enemy)
	EntityRegistry.unregister_soldier(defender)
	boarder.queue_free()
	remote_enemy.queue_free()
	defender.queue_free()
	enemy_ship.queue_free()
	player_ship.queue_free()


func _verify_enemy_boarder_speaks_only_on_player_deck(failures: Array[String]) -> void:
	var player_ship := MockTargetShip.new()
	add_child(player_ship)
	player_ship.team = "player"

	var enemy_ship := MockTargetShip.new()
	add_child(enemy_ship)
	enemy_ship.team = "enemy"

	var boarder := MockCombatSoldier.new()
	add_child(boarder)
	boarder.team = "enemy"
	boarder.owned_ship = enemy_ship

	SoldierSpeechHelper.reset(boarder)
	boarder.set_meta("speech_timer", 0.0)
	SoldierSpeechHelper.update(boarder, 1.0)
	if boarder.get_node_or_null("SpeechLabel") != null:
		failures.append("enemy soldier spoke before boarding the player deck")

	boarder.owned_ship = player_ship
	boarder.set_meta("speech_timer", 0.0)
	SoldierSpeechHelper.update(boarder, 1.0)

	var label := boarder.get_node_or_null("SpeechLabel") as Label3D
	if label == null:
		failures.append("enemy boarder did not create a speech label on player deck")
	elif label.visible != true or label.text.is_empty():
		failures.append("enemy boarder did not speak after reaching player deck")
	elif label.modulate.r <= label.modulate.b:
		failures.append("enemy boarder speech did not use hostile label color")
	elif label.no_depth_test != true:
		failures.append("enemy boarder speech label should ignore depth clipping")
	elif label.render_priority < 20 or label.outline_render_priority < 21:
		failures.append("enemy boarder speech label render priority is too low")

	boarder.queue_free()
	enemy_ship.queue_free()
	player_ship.queue_free()


func _verify_support_rescue_boarding_holds_player_capture_progress(failures: Array[String]) -> void:
	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.boarding_capture_duration = 8.0
	player.boarding_capture_progress = 2.0

	var enemy_boarder := MockTransferSoldier.new()
	add_child(enemy_boarder)
	enemy_boarder.team = "enemy"
	enemy_boarder.owned_ship = player
	EntityRegistry.register_soldier(enemy_boarder)

	var support := MockSupportShip.new()
	add_child(support)
	support.target = player
	support.is_boarding = true
	support.boarding_target = player
	support.set_meta("boarding_purpose", SupportBoardingHelper.SUPPORT_RESCUE_BOARDING_PURPOSE)
	EntityRegistry.register_ship(support)

	BaseShipStatusHelper.update_boarding_state(player, 1.25)

	if player.deck_is_overrun != true:
		failures.append("support rescue capture-progress contract did not create overrun player deck")
	if not is_equal_approx(player.boarding_capture_progress, 2.0):
		failures.append("support rescue boarding did not hold player capture progress")
	if player.damage_taken > 0.0:
		failures.append("support rescue boarding allowed overrun capture damage tick")

	EntityRegistry.unregister_ship(support)
	EntityRegistry.unregister_soldier(enemy_boarder)
	support.queue_free()
	enemy_boarder.queue_free()
	player.queue_free()


func _verify_support_rescue_boarders_return_after_deck_safe(failures: Array[String]) -> void:
	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO

	var support := MockSupportShip.new()
	add_child(support)
	support.target = player
	support.global_position = Vector3(8.0, 0.0, 0.0)
	support.is_boarding = true
	support.boarding_target = player
	support._initial_rope_deployed = true
	support.set_meta("boarding_purpose", SupportBoardingHelper.SUPPORT_RESCUE_BOARDING_PURPOSE)
	EntityRegistry.register_ship(support)

	var support_boarder := MockTransferSoldier.new()
	add_child(support_boarder)
	support_boarder.team = "player"
	support_boarder.owned_ship = player
	support_boarder.home_ship = support
	EntityRegistry.register_soldier(support_boarder)

	BaseShipStatusHelper.update_boarding_state(player, 0.25)

	if support_boarder.owned_ship != support:
		failures.append("support rescue boarder did not return to support ship after deck was safe")
	if support_boarder.get_boarding_status_value() != "returning":
		failures.append("support rescue boarder was not marked returning while jumping home")
	if support.is_boarding == true:
		failures.append("support rescue boarding link stayed active after boarders returned")
	if support.has_meta("boarding_purpose"):
		failures.append("support rescue boarding purpose meta was not cleared after return")
	if support.has_meta("boarding_transfer_suppressed"):
		failures.append("support rescue transfer suppression meta was not cleared after return")

	EntityRegistry.unregister_ship(support)
	EntityRegistry.unregister_soldier(support_boarder)
	support_boarder.queue_free()
	support.queue_free()
	player.queue_free()


func _verify_support_attack_boarders_return_after_enemy_deck_safe(failures: Array[String]) -> void:
	var enemy := MockTargetShip.new()
	add_child(enemy)
	enemy.team = "enemy"
	enemy.global_position = Vector3.ZERO
	enemy.boarding_capture_progress = 2.0

	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(8.0, 0.0, 0.0)
	support.is_boarding = true
	support.boarding_target = enemy
	support._initial_rope_deployed = true
	support.set_meta("boarding_purpose", SupportBoardingHelper.SUPPORT_BOARDING_PURPOSE)
	EntityRegistry.register_ship(support)

	var support_boarder := MockTransferSoldier.new()
	add_child(support_boarder)
	support_boarder.team = "player"
	support_boarder.global_position = enemy.global_position
	support_boarder.owned_ship = enemy
	support_boarder.home_ship = support
	EntityRegistry.register_soldier(support_boarder)

	BaseShipStatusHelper.update_boarding_state(enemy, 0.25)

	if support_boarder.owned_ship != support:
		failures.append("support attack boarder did not return after enemy deck was safe")
	if support_boarder.get_boarding_status_value() != "returning":
		failures.append("support attack boarder was not marked returning while jumping home")
	if support.is_boarding == true:
		failures.append("support attack boarding link stayed active after boarders returned")
	if support.has_meta("boarding_purpose"):
		failures.append("support attack boarding purpose meta was not cleared after return")
	if support.has_meta("boarding_transfer_suppressed"):
		failures.append("support attack transfer suppression meta was not cleared after return")
	if enemy.boarding_capture_progress > 0.0:
		failures.append("support attack return should reset enemy capture progress")

	EntityRegistry.unregister_ship(support)
	EntityRegistry.unregister_soldier(support_boarder)
	support_boarder.queue_free()
	support.queue_free()
	enemy.queue_free()
