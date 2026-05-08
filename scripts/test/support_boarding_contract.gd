extends Node

const SoldierAiHelper = preload("res://scripts/entities/soldiers/soldier_ai_helper.gd")
const CannonScript = preload("res://scripts/entities/launchers/cannon.gd")
const SingigeonLauncherScript = preload("res://scripts/entities/launchers/singigeon_launcher.gd")
const BallistaLauncherScript = preload("res://scripts/entities/launchers/ballista_launcher.gd")
const JanggunLauncherScript = preload("res://scripts/entities/launchers/janggun_launcher.gd")
const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SupportFleetFormationHelper = preload("res://scripts/entities/ships/support_fleet_formation_helper.gd")
const SoldierShipSpatialCacheHelper = preload("res://scripts/entities/soldiers/soldier_ship_spatial_cache_helper.gd")
const ShipAILimboKeys = preload("res://scripts/ai/limbo/ship_ai_limbo_keys.gd")


class MockTargetShip:
	extends Node3D

	var team: String = "enemy"
	var ship_type: String = ""
	var boarding_attacker: Node3D = null
	var is_derelict: bool = false
	var is_burning: bool = false
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
	var manual_boarding_target: Node3D = null
	var _deck_overrun_announced: bool = false
	var _cached_hud: Node = null
	var damage_taken: float = 0.0

	func get_team_tag() -> String:
		return team

	func set_boarding_attacker_ship(attacker: Node3D) -> void:
		boarding_attacker = attacker

	func get_boarding_attacker_ship() -> Node3D:
		return boarding_attacker

	func is_derelict_ship() -> bool:
		return is_derelict

	func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO, _damage_source: String = "") -> void:
		damage_taken += amount


class MockSupportShip:
	extends Node3D

	var team: String = "player"
	var ship_type: String = ""
	var fleet_formation: int = 0
	var base_collision_radius: float = 4.5
	var width_multiplier: float = 1.0
	var length_multiplier: float = 1.0
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
	var limbo_ai_pilot_enabled: bool = false

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


func _set_support_hold_enabled(ship: Node3D, enabled: bool) -> void:
	if not is_instance_valid(ship):
		return
	if enabled:
		ship.set_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META, true)
	elif ship.has_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META):
		ship.remove_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META)


func _set_support_formation(ship: Node3D, formation_value: int) -> void:
	if not is_instance_valid(ship):
		return
	ship.set_meta(SupportFleetStateHelper.SUPPORT_FLEET_FORMATION_META, formation_value)


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
	var is_boarding: bool = false
	var boarding_timer: float = 0.0
	var boarding_prep_timer: float = 0.0
	var boarding_contact_timer: float = 0.0
	var boarding_hook_timer: float = 0.0
	var boarding_secondary_rope_timer: float = 0.0
	var _initial_rope_deployed: bool = false
	var _full_rope_deployed: bool = false
	var boarding_attacker: Node3D = null
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var deck_hostile_boarder_count: int = 0
	var is_derelict: bool = false
	var is_dying: bool = false
	var is_sinking: bool = false
	var clear_rope_calls: int = 0
	var clear_latch_calls: int = 0
	var become_derelict_calls: int = 0

	func _init() -> void:
		var soldiers := Node3D.new()
		soldiers.name = "Soldiers"
		add_child(soldiers)

	func get_team_tag() -> String:
		return team

	func get_deck_half_extents() -> Vector2:
		return deck_half_extents

	func get_boarding_attacker_ship() -> Node3D:
		return boarding_attacker

	func clear_boarding_attacker_ship() -> void:
		boarding_attacker = null

	func _clear_ropes() -> void:
		clear_rope_calls += 1

	func _clear_boarding_latch() -> void:
		clear_latch_calls += 1

	func _become_derelict() -> void:
		is_derelict = true
		become_derelict_calls += 1

	func is_derelict_ship() -> bool:
		return is_derelict

	func _set_contact_areas_enabled(_enabled: bool) -> void:
		pass

	func _ignite_derelict_from_contact(_source_ship: Node3D = null) -> void:
		set_meta("derelict_contact_ignition_started", true)

	func check_derelict_status() -> void:
		BaseShipStatusHelper.check_derelict_status(self)


class MockTransferSoldier:
	extends Node3D

	var team: String = "player"
	var owned_ship: Node3D = null
	var home_ship: Node3D = null
	var dead: bool = false
	var _is_jumping: bool = false
	var is_stationary: bool = false
	var boarding_status: String = "on_deck"

	func get_team_tag() -> String:
		return team

	func set_team(next_team: String) -> void:
		team = next_team

	func is_dead() -> bool:
		return dead

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
	var is_ranged_only: bool = false
	var is_melee_only: bool = false
	var is_captain: bool = false
	var is_stationary: bool = false
	var _is_jumping: bool = false
	var CROSS_SHIP_ENGAGE_SHIP_DISTANCE: float = 8.0
	var CROSS_SHIP_ENGAGE_MAX_DISTANCE: float = 14.0

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
	_verify_support_ship_rejects_enemy_boarding_link(failures)
	_verify_support_ship_rejects_enemy_boarding_even_in_contact(failures)
	_verify_support_ship_rescues_overrun_player_deck(failures)
	_verify_support_ship_rescues_contested_player_deck(failures)
	_verify_support_ship_recalls_from_far_for_overrun_player_deck(failures)
	_verify_support_enemy_boarding_cancels_without_rescue(failures)
	_verify_support_ship_interrupts_attack_boarding_for_rescue(failures)
	_verify_support_rescue_boarding_relaxes_bad_alignment(failures)
	_verify_support_rescue_waits_until_boarding_motion_range(failures)
	_verify_support_hold_formation_ignores_normal_threats(failures)
	_verify_support_hold_formation_allows_boarding_attacker(failures)
	_verify_panokseon_free_assist_holds_line_against_normal_threats(failures)
	_verify_panokseon_free_assist_allows_flagship_boarding_attacker(failures)
	_verify_panokseon_limbo_screen_threat_keeps_line_for_normal_threats(failures)
	_verify_support_limbo_modes_drive_assist_execution(failures)
	_verify_support_ship_tracks_flagship_manual_boss_breach(failures)
	_verify_panokseon_column_goal_tracks_flagship_directly(failures)
	_verify_support_chain_goal_formation_variants(failures)
	_verify_support_chain_goal_formation_turn_following(failures)
	_verify_support_chain_goal_prefers_owner_flagship_over_target(failures)
	_verify_support_artillery_screen_goal_tracks_flagship_wing_lane(failures)
	_verify_panokseon_rescue_goal_opens_center_lane(failures)
	_verify_support_assist_navigation_prefers_owner_flagship_lane(failures)
	_verify_support_free_assist_uses_stable_role_lanes(failures)
	_verify_support_free_assist_softly_distributes_targets(failures)
	_verify_support_boss_breach_navigation_stages_from_flagship_lane(failures)
	_verify_support_free_assist_recalls_near_player(failures)
	_verify_enemy_boarding_transfers_last_available_soldier(failures)
	_verify_enemy_derelict_waits_for_affiliated_boarders_to_die(failures)
	_verify_derelict_disposal_waits_while_player_deck_is_contested(failures)
	_verify_derelict_disposal_waits_for_affiliated_boarder_cleanup(failures)
	_verify_boarding_transfer_snaps_soldier_to_target_deck(failures)
	_verify_boarding_transfer_wave_sends_multiple_soldiers(failures)
	_verify_boarding_transfer_waits_for_launch_side_boarders(failures)
	await _verify_boarding_transfer_tracks_moving_target_deck(failures)
	_verify_soldier_deck_recovery_repairs_parent_and_bounds(failures)
	_verify_soldier_boarding_status_marks_returning(failures)
	_verify_player_support_boarding_cancels_when_target_is_missing(failures)
	_verify_overrun_deck_suppresses_ship_weapons(failures)
	_verify_player_deck_emergency_speeds_support_assist(failures)
	_verify_soldier_retargets_hostile_boarder_on_owned_ship(failures)
	_verify_soldier_targets_boarder_on_distressed_ally_ship(failures)
	_verify_enemy_boarder_speaks_only_on_player_deck(failures)
	_verify_player_crew_speaks_when_ship_is_burning(failures)
	_verify_support_rescue_boarding_holds_player_capture_progress(failures)
	_verify_support_rescue_boarders_return_after_deck_safe(failures)
	_verify_support_attack_boarders_return_after_enemy_deck_safe(failures)
	_verify_support_attack_boarders_hold_on_boss_until_sinking(failures)
	if failures.is_empty():
		print("[SupportBoardingContract] ok")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[SupportBoardingContract] %s" % failure)
	get_tree().quit(1)


func _verify_support_ship_rejects_enemy_boarding_link(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO

	var target := MockTargetShip.new()
	add_child(target)
	target.global_position = Vector3(8.0, 0.0, 0.0)

	var started: bool = ChaserShipMinionHelper._try_start_support_boarding(support, target, 0.1)

	if started == true or support.is_boarding == true:
		failures.append("support ship should not start enemy boarding links")
	if support.boarding_target != null:
		failures.append("support ship should not assign an enemy boarding target")
	if support.has_meta("boarding_purpose"):
		failures.append("support ship should not set attack boarding purpose metadata")
	if target.get_boarding_attacker_ship() != null:
		failures.append("support ship should not register itself as an enemy boarding attacker")
	if support.clear_rope_calls != 0 or support.clear_latch_calls != 0:
		failures.append("support ship should not reset boarding ropes or latches for blocked enemy boarding")
	if support.process_boarding_calls != 0:
		failures.append("support ship should not hand off to common boarding process for blocked enemy boarding")

	target.queue_free()
	support.queue_free()


func _verify_support_ship_rejects_enemy_boarding_even_in_contact(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	support.collision_distance = 8.0

	var target := MockTargetShip.new()
	add_child(target)
	target.global_position = Vector3(11.2, 0.0, 0.0)

	var started_far: bool = ChaserShipMinionHelper._try_start_support_boarding(support, target, 0.1)
	if started_far == true or support.is_boarding == true:
		failures.append("support ship should not start enemy boarding outside contact range")

	target.global_position = Vector3(8.4, 0.0, 0.0)
	support.side_boarding = false
	support.head_on_boarding = true
	support.cleanup_boarding = true
	var started_cleanup: bool = ChaserShipMinionHelper._try_start_support_boarding(support, target, 0.1)
	if started_cleanup == true or support.is_boarding == true:
		failures.append("support ship should keep rejecting enemy boarding even after contact becomes valid")
	if support.has_meta("boarding_contact_mode"):
		failures.append("support ship should not stamp enemy boarding contact mode metadata")

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


func _verify_support_ship_recalls_from_far_for_overrun_player_deck(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(118.0, 0.0, 0.0)
	support.collision_distance = 8.0

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	player.deck_is_overrun = true
	player.deck_friendly_crew_count = 0
	player.deck_hostile_boarder_count = 3
	support.target = player

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != player:
		failures.append("support ship did not emergency-recall from far distance to overrun player deck")

	player.queue_free()
	support.queue_free()


func _verify_support_ship_interrupts_attack_boarding_for_rescue(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(6.0, 0.0, 0.0)
	support.is_boarding = true
	ShipBoardingMetaHelper.set_boarding_purpose(support, SupportBoardingHelper.SUPPORT_BOARDING_PURPOSE)

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	player.deck_is_overrun = true
	player.deck_friendly_crew_count = 0
	player.deck_hostile_boarder_count = 2
	support.target = player

	var enemy_target := MockTargetShip.new()
	add_child(enemy_target)
	enemy_target.team = "enemy"
	enemy_target.global_position = Vector3(6.0, 0.0, 1.5)
	support.boarding_target = enemy_target

	var interrupted: bool = ChaserShipMinionHelper.try_interrupt_boarding_for_flagship_rescue(support)
	if interrupted != true:
		failures.append("support ship did not interrupt attack boarding for flagship rescue")
	if support.cancel_calls != 1 or support.is_boarding == true:
		failures.append("support rescue interrupt did not cancel current attack boarding")
	if int(support.get_meta("support_assist_target_id", 0)) != player.get_instance_id():
		failures.append("support rescue interrupt did not lock onto the overrun flagship")

	enemy_target.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_enemy_boarding_cancels_without_rescue(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(6.0, 0.0, 0.0)
	support.is_boarding = true
	ShipBoardingMetaHelper.set_boarding_purpose(support, SupportBoardingHelper.SUPPORT_BOARDING_PURPOSE)

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy_target := MockTargetShip.new()
	add_child(enemy_target)
	enemy_target.team = "enemy"
	enemy_target.global_position = Vector3(6.0, 0.0, 1.5)
	support.boarding_target = enemy_target

	var canceled: bool = ChaserShipMinionHelper.try_interrupt_boarding_for_flagship_rescue(support)
	if canceled != true:
		failures.append("support ship did not cancel legacy enemy boarding when no rescue was active")
	if support.cancel_calls != 1 or support.is_boarding == true:
		failures.append("support enemy boarding cancel did not clear the active boarding link")
	if int(support.get_meta("support_assist_target_id", 0)) != 0:
		failures.append("support enemy boarding cancel should not lock onto the flagship without a rescue emergency")

	enemy_target.queue_free()
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
	_set_support_hold_enabled(support, true)

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
	_set_support_hold_enabled(support, true)

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


func _verify_panokseon_free_assist_holds_line_against_normal_threats(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	_set_support_hold_enabled(support, false)
	support.ship_type = "panokseon_ally"
	support.set_meta("support_squadron_slot_role", "artillery_lead")

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy := MockTargetShip.new()
	add_child(enemy)
	enemy.team = "enemy"
	enemy.global_position = Vector3(10.0, 0.0, 0.0)
	EntityRegistry.register_ship(enemy)

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != null:
		failures.append("panokseon free assist should keep formation instead of chasing normal threats")
	if support.has_meta("support_assist_target_id"):
		failures.append("panokseon free assist should not keep a normal-threat target lock")

	EntityRegistry.unregister_ship(enemy)
	enemy.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_panokseon_free_assist_allows_flagship_boarding_attacker(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	_set_support_hold_enabled(support, false)
	support.ship_type = "panokseon_ally"
	support.set_meta("support_squadron_slot_role", "artillery_lead")

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy_attacker := MockTargetShip.new()
	add_child(enemy_attacker)
	enemy_attacker.team = "enemy"
	enemy_attacker.global_position = Vector3(11.0, 0.0, 0.0)
	player.set_boarding_attacker_ship(enemy_attacker)

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != enemy_attacker:
		failures.append("panokseon free assist should still screen the flagship boarding attacker")

	enemy_attacker.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_panokseon_limbo_screen_threat_keeps_line_for_normal_threats(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	_set_support_hold_enabled(support, false)
	support.ship_type = "panokseon_ally"
	support.limbo_ai_pilot_enabled = true
	support.set_meta("support_squadron_slot_role", "artillery_lead")

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy := MockTargetShip.new()
	add_child(enemy)
	enemy.team = "enemy"
	enemy.global_position = Vector3(11.0, 0.0, 0.0)

	support.set_meta(ShipAILimboKeys.META_SUPPORT_FRAME, Engine.get_physics_frames())
	support.set_meta(ShipAILimboKeys.META_SUPPORT_MODE, ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT)
	support.set_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, enemy.get_instance_id())
	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != null:
		failures.append("panokseon free assist limbo screen threat should keep following the flagship for normal threats")
	if support.has_meta("support_assist_target_id"):
		failures.append("panokseon free assist limbo screen threat should not keep a normal-threat target lock")

	enemy.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_limbo_modes_drive_assist_execution(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3.ZERO
	_set_support_hold_enabled(support, false)
	support.ship_type = "panokseon_ally"
	support.limbo_ai_pilot_enabled = true
	support.set_meta("support_squadron_slot_role", "artillery_lead")

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var enemy_attacker := MockTargetShip.new()
	add_child(enemy_attacker)
	enemy_attacker.team = "enemy"
	enemy_attacker.global_position = Vector3(11.0, 0.0, 0.0)
	player.set_boarding_attacker_ship(enemy_attacker)

	support.set_meta(ShipAILimboKeys.META_SUPPORT_FRAME, Engine.get_physics_frames())
	support.set_meta(ShipAILimboKeys.META_SUPPORT_MODE, ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP)
	support.set_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, player.get_instance_id())
	var selected_follow: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected_follow != null:
		failures.append("support assist executor should respect follow mode instead of overriding with boarding attacker")

	support.set_meta(ShipAILimboKeys.META_SUPPORT_FRAME, Engine.get_physics_frames())
	support.set_meta(ShipAILimboKeys.META_SUPPORT_MODE, ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT)
	support.set_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, enemy_attacker.get_instance_id())
	var selected_screen: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected_screen != enemy_attacker:
		failures.append("support assist executor did not honor limbo screen threat mode target")

	enemy_attacker.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_ship_tracks_flagship_manual_boss_breach(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(-9.0, 0.0, 0.0)
	support.collision_distance = 8.0

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var boss := MockTargetShip.new()
	add_child(boss)
	boss.team = "enemy"
	boss.global_position = Vector3(18.0, 0.0, 0.0)
	boss.add_to_group("boss")
	player.manual_boarding_target = boss

	var selected: Node3D = ChaserShipMinionHelper._get_support_assist_target(support, player, 0.1)
	if selected != null:
		failures.append("support ship should ignore flagship manual boss pressure when no real rescue threat exists")
	if ChaserShipMinionHelper._is_support_boss_breach_target(support, boss):
		failures.append("support ship should not classify flagship manual boss pressure as boss breach anymore")
	var started_breach_boarding: bool = ChaserShipMinionHelper._try_start_support_boarding(support, boss, 0.1)
	if started_breach_boarding == true or support.is_boarding == true:
		failures.append("support ship should not hook onto boss decks under artillery doctrine")

	boss.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_panokseon_column_goal_tracks_flagship_directly(failures: Array[String]) -> void:
	var maengseon := MockSupportShip.new()
	add_child(maengseon)
	maengseon.global_position = Vector3(92.0, 0.0, 0.0)
	maengseon.set_meta("support_squadron_slot_role", "screen_lead")
	maengseon.set_meta("support_trail_points", [Vector3(92.0, 0.0, -14.0), Vector3(92.0, 0.0, 0.0)])

	var panokseon := MockSupportShip.new()
	add_child(panokseon)
	panokseon.ship_type = "panokseon_ally"
	panokseon.global_position = Vector3(90.0, 0.0, 4.0)
	panokseon.set_meta("support_squadron_slot_role", "artillery_lead")
	_set_support_formation(panokseon, 0)

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	player.set_meta("support_trail_points", [Vector3(0.0, 0.0, -14.0), Vector3.ZERO])
	maengseon.target = player
	panokseon.target = player

	var lead_ship := SupportFleetFormationHelper.get_support_lead_ship(panokseon, [maengseon, panokseon], 1)
	if lead_ship != player:
		failures.append("panokseon column formation should follow the flagship directly instead of the previous maengseon")
	var goal := SupportFleetFormationHelper.get_support_chain_goal(panokseon, [maengseon, panokseon], 1, 10.0)
	var goal_pos: Vector3 = goal.get("position", Vector3.ZERO)
	if goal_pos.distance_to(player.global_position) >= goal_pos.distance_to(maengseon.global_position):
		failures.append("panokseon column goal should stay near the flagship line instead of chaining behind maengseon")

	player.queue_free()
	panokseon.queue_free()
	maengseon.queue_free()


func _verify_support_chain_goal_formation_variants(failures: Array[String]) -> void:
	var support_a := MockSupportShip.new()
	add_child(support_a)
	var support_b := MockSupportShip.new()
	add_child(support_b)

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support_a.target = player
	support_b.target = player

	_set_support_formation(support_a, 0)
	var column_goal := SupportFleetFormationHelper.get_support_chain_goal(support_a, [support_a, support_b], 0, 10.0)
	_set_support_formation(support_a, 1)
	var wing_goal := SupportFleetFormationHelper.get_support_chain_goal(support_a, [support_a, support_b], 0, 10.0)
	_set_support_formation(support_a, 2)
	var legacy_wedge_goal := SupportFleetFormationHelper.get_support_chain_goal(support_a, [support_a, support_b], 0, 10.0)

	var column_pos: Vector3 = column_goal.get("position", Vector3.ZERO)
	var wing_pos: Vector3 = wing_goal.get("position", Vector3.ZERO)
	var legacy_wedge_pos: Vector3 = legacy_wedge_goal.get("position", Vector3.ZERO)
	if absf(column_pos.x) > 0.25:
		failures.append("support column goal should stay centered behind the flagship")
	if absf(wing_pos.x) <= 0.25:
		failures.append("support wing goal should spread laterally from the flagship")
	if wing_pos.distance_to(legacy_wedge_pos) > 0.35:
		failures.append("legacy wedge support goal should now alias the wing formation goal")

	support_a.set_meta("support_squadron_slot_role", "screen_lead")
	_set_support_formation(support_a, 0)
	var role_column_offset: Vector3 = ChaserShipMinionHelper._get_minion_offset(support_a, 0, true)
	_set_support_formation(support_a, 1)
	var role_wing_offset: Vector3 = ChaserShipMinionHelper._get_minion_offset(support_a, 0, true)
	if role_column_offset.z < 12.5:
		failures.append("support column offset should keep a clearer trailing gap behind the flagship")
	if role_column_offset.z <= role_wing_offset.z + 2.5:
		failures.append("support column offset should trail more deeply than the wing offset")

	player.queue_free()
	support_b.queue_free()
	support_a.queue_free()


func _verify_support_chain_goal_formation_turn_following(failures: Array[String]) -> void:
	var support_a := MockSupportShip.new()
	add_child(support_a)
	var support_b := MockSupportShip.new()
	add_child(support_b)
	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	player.set_meta("support_trail_points", [
		Vector3(-18.0, 0.0, 0.0),
		Vector3(-9.0, 0.0, 0.0),
		Vector3.ZERO,
	])
	support_a.target = player
	support_b.target = player
	_set_support_formation(support_a, 1)

	var wing_goal := SupportFleetFormationHelper.get_support_chain_goal(support_a, [support_a, support_b], 0, 10.0)
	var wing_pos: Vector3 = wing_goal.get("position", Vector3.ZERO)
	var wing_fwd: Vector3 = wing_goal.get("forward", Vector3.ZERO)
	if wing_pos.x >= -1.5:
		failures.append("support wing turn-follow goal should stay behind the flagship trail when the flagship yaws")
	if absf(wing_pos.z) <= 0.25:
		failures.append("support wing turn-follow goal should keep lateral spread while following the flagship trail")
	if wing_fwd.dot(Vector3.RIGHT) <= 0.7:
		failures.append("support wing turn-follow goal should inherit trail forward during flagship turns")

	player.queue_free()
	support_b.queue_free()
	support_a.queue_free()


func _verify_support_chain_goal_prefers_owner_flagship_over_target(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	var owner_flagship := MockTargetShip.new()
	add_child(owner_flagship)
	owner_flagship.team = "player"
	owner_flagship.global_position = Vector3.ZERO
	owner_flagship.set_meta("support_trail_points", [Vector3(0.0, 0.0, -14.0), Vector3.ZERO])
	var decoy_target := MockTargetShip.new()
	add_child(decoy_target)
	decoy_target.team = "player"
	decoy_target.global_position = Vector3(92.0, 0.0, 0.0)
	decoy_target.set_meta("support_trail_points", [Vector3(92.0, 0.0, -14.0), Vector3(92.0, 0.0, 0.0)])

	support.target = decoy_target
	SupportFleetStateHelper.assign_support_ship_to_flagship(support, owner_flagship)
	_set_support_formation(support, 1)

	var goal := SupportFleetFormationHelper.get_support_chain_goal(support, [support], 0, 10.0)
	var goal_pos: Vector3 = goal.get("position", Vector3.ZERO)
	if goal_pos.distance_to(owner_flagship.global_position) >= goal_pos.distance_to(decoy_target.global_position):
		failures.append("support chain goal should follow the owner flagship instead of a drifted runtime target")
	if goal_pos.x >= 40.0:
		failures.append("support chain goal drifted toward the decoy target instead of staying near the owner flagship")

	decoy_target.queue_free()
	owner_flagship.queue_free()
	support.queue_free()


func _verify_support_artillery_screen_goal_tracks_flagship_wing_lane(failures: Array[String]) -> void:
	var panokseon := MockSupportShip.new()
	add_child(panokseon)
	panokseon.global_position = Vector3(18.0, 0.0, -12.0)
	_set_support_formation(panokseon, 1)
	panokseon.base_collision_radius = 5.2
	panokseon.width_multiplier = 1.08
	panokseon.length_multiplier = 1.28
	panokseon.set_meta("support_squadron_id", "panokseon_artillery")
	panokseon.set_meta("support_squadron_slot_role", "artillery_lead")

	var rescue := MockSupportShip.new()
	add_child(rescue)
	rescue.global_position = Vector3.ZERO
	rescue.set_meta("support_squadron_id", "flagship_screen")
	rescue.set_meta("support_squadron_slot_role", "rescue_rear")

	var artillery_screen := MockSupportShip.new()
	add_child(artillery_screen)
	_set_support_formation(artillery_screen, 1)
	artillery_screen.base_collision_radius = 4.1
	artillery_screen.width_multiplier = 0.92
	artillery_screen.length_multiplier = 1.08
	artillery_screen.set_meta("support_squadron_id", "panokseon_artillery")
	artillery_screen.set_meta("support_squadron_slot_role", "artillery_screen_front_right")

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	panokseon.target = player
	rescue.target = player
	artillery_screen.target = player

	var goal := SupportFleetFormationHelper.get_support_chain_goal(
		artillery_screen,
		[panokseon, rescue, artillery_screen],
		2,
		10.0
	)
	var goal_pos: Vector3 = goal.get("position", Vector3.ZERO)
	if goal_pos.x <= panokseon.global_position.x + 2.0:
		failures.append("artillery screen wing goal should occupy the panokseon right wing instead of collapsing toward center")
	if absf(goal_pos.z - panokseon.global_position.z) > 8.0:
		failures.append("artillery screen wing goal should stay beside the support panokseon instead of becoming a rear flagship guard")
	if goal_pos.distance_to(panokseon.global_position) >= goal_pos.distance_to(player.global_position):
		failures.append("artillery screen wing goal should anchor closer to the support panokseon than to the flagship")

	player.queue_free()
	artillery_screen.queue_free()
	rescue.queue_free()
	panokseon.queue_free()


func _verify_panokseon_rescue_goal_opens_center_lane(failures: Array[String]) -> void:
	var panokseon := MockSupportShip.new()
	add_child(panokseon)
	panokseon.global_position = Vector3(14.0, 0.0, -10.0)
	_set_support_formation(panokseon, 1)
	panokseon.base_collision_radius = 5.2
	panokseon.width_multiplier = 1.08
	panokseon.length_multiplier = 1.28
	panokseon.set_meta("support_squadron_slot_role", "artillery_lead")

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	panokseon.target = player

	var normal_goal := SupportFleetFormationHelper.get_support_chain_goal(panokseon, [panokseon], 0, 10.0)
	var normal_pos: Vector3 = normal_goal.get("position", Vector3.ZERO)
	player.deck_is_contested = true
	player.deck_hostile_boarder_count = 3
	var rescue_goal := SupportFleetFormationHelper.get_support_chain_goal(panokseon, [panokseon], 0, 10.0)
	var rescue_pos: Vector3 = rescue_goal.get("position", Vector3.ZERO)
	var normal_lane_offset := absf(normal_pos.x - player.global_position.x)
	var rescue_lane_offset := absf(rescue_pos.x - player.global_position.x)
	if normal_lane_offset > 8.0:
		failures.append("panokseon normal wing goal should stay on a nearby rear quarter instead of drifting too far wide")
	if rescue_lane_offset <= normal_lane_offset + 1.0:
		failures.append("panokseon rescue goal should widen its lateral offset to vacate more center lane for rescue ships")

	player.queue_free()
	panokseon.queue_free()


func _verify_support_assist_navigation_prefers_owner_flagship_lane(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(0.0, 0.0, -18.0)
	var owner_flagship := MockTargetShip.new()
	add_child(owner_flagship)
	owner_flagship.team = "player"
	owner_flagship.global_position = Vector3.ZERO
	var decoy_target := MockTargetShip.new()
	add_child(decoy_target)
	decoy_target.team = "player"
	decoy_target.global_position = Vector3(88.0, 0.0, 0.0)
	var assist_target := MockTargetShip.new()
	add_child(assist_target)
	assist_target.team = "enemy"
	assist_target.global_position = Vector3(9.0, 0.0, 2.0)

	support.target = decoy_target
	SupportFleetStateHelper.assign_support_ship_to_flagship(support, owner_flagship)

	var nav := ChaserShipMinionHelper._build_support_assist_navigation(support, assist_target, 0)
	var desired_point: Vector3 = ShipMovementIntent.get_desired_point(nav, Vector3.ZERO)
	if desired_point.distance_to(owner_flagship.global_position) >= desired_point.distance_to(decoy_target.global_position):
		failures.append("support assist navigation should lane around the owner flagship instead of the drifted runtime target")

	assist_target.queue_free()
	decoy_target.queue_free()
	owner_flagship.queue_free()
	support.queue_free()


func _verify_support_free_assist_uses_stable_role_lanes(failures: Array[String]) -> void:
	var owner_flagship := MockTargetShip.new()
	add_child(owner_flagship)
	owner_flagship.team = "player"
	owner_flagship.global_position = Vector3.ZERO

	var assist_target := MockTargetShip.new()
	add_child(assist_target)
	assist_target.team = "enemy"
	assist_target.global_position = Vector3(18.0, 0.0, 0.0)

	var screen_left := MockSupportShip.new()
	add_child(screen_left)
	screen_left.global_position = Vector3(0.0, 0.0, -18.0)
	screen_left.set_meta("support_squadron_slot_role", "screen_lead")
	screen_left.set_meta("support_fleet_slot_index", 0)
	SupportFleetStateHelper.assign_support_ship_to_flagship(screen_left, owner_flagship)

	var screen_right := MockSupportShip.new()
	add_child(screen_right)
	screen_right.global_position = Vector3(0.0, 0.0, -17.0)
	screen_right.set_meta("support_squadron_slot_role", "screen_flank")
	screen_right.set_meta("support_fleet_slot_index", 2)
	SupportFleetStateHelper.assign_support_ship_to_flagship(screen_right, owner_flagship)

	var nav_left := ChaserShipMinionHelper._build_support_assist_navigation(screen_left, assist_target, 0)
	var nav_right := ChaserShipMinionHelper._build_support_assist_navigation(screen_right, assist_target, 1)
	var player_forward: Vector3 = -owner_flagship.global_transform.basis.z
	player_forward.y = 0.0
	player_forward = player_forward.normalized() if player_forward.length_squared() > 0.001 else Vector3.FORWARD
	var player_right: Vector3 = player_forward.cross(Vector3.UP)
	player_right = player_right.normalized() if player_right.length_squared() > 0.001 else Vector3.RIGHT
	var left_lane: float = (ShipMovementIntent.get_desired_point(nav_left, Vector3.ZERO) - owner_flagship.global_position).dot(player_right)
	var right_lane: float = (ShipMovementIntent.get_desired_point(nav_right, Vector3.ZERO) - owner_flagship.global_position).dot(player_right)
	if left_lane * right_lane >= 0.0:
		failures.append("support free assist should keep screen ships on opposite role lanes after formation-hold toggle")
	if float(screen_left.get_meta("support_assist_lane_side", 0.0)) >= 0.0 or float(screen_right.get_meta("support_assist_lane_side", 0.0)) <= 0.0:
		failures.append("support free assist lane side meta should be role-stable instead of current-position based")
	if ChaserShipMinionHelper._get_support_assist_separation_radius(screen_left, screen_right) <= ChaserShipMinionHelper.SUPPORT_ASSIST_SEPARATION_RADIUS:
		failures.append("support free assist separation radius should include hull clearance padding")

	screen_right.queue_free()
	screen_left.queue_free()
	assist_target.queue_free()
	owner_flagship.queue_free()


func _verify_support_free_assist_softly_distributes_targets(failures: Array[String]) -> void:
	var player := MockTargetShip.new()
	add_child(player)
	player.name = "soft_distribution_player"
	player.team = "player"
	player.global_position = Vector3.ZERO
	SupportFleetStateHelper.set_flagship_hold_enabled(player, false)

	var support_a := MockSupportShip.new()
	add_child(support_a)
	support_a.name = "soft_distribution_support_a"
	support_a.global_position = Vector3(0.0, 0.0, -2.0)
	support_a.target = player
	_set_support_hold_enabled(support_a, false)
	SupportFleetStateHelper.assign_support_ship_to_flagship(support_a, player)
	_set_support_hold_enabled(support_a, false)
	EntityRegistry.register_ship(support_a)

	var support_b := MockSupportShip.new()
	add_child(support_b)
	support_b.name = "soft_distribution_support_b"
	support_b.global_position = Vector3(0.0, 0.0, 2.0)
	support_b.target = player
	_set_support_hold_enabled(support_b, false)
	SupportFleetStateHelper.assign_support_ship_to_flagship(support_b, player)
	_set_support_hold_enabled(support_b, false)
	EntityRegistry.register_ship(support_b)

	var near_enemy := MockTargetShip.new()
	add_child(near_enemy)
	near_enemy.name = "soft_distribution_near_enemy"
	near_enemy.team = "enemy"
	near_enemy.global_position = Vector3(10.0, 0.0, 0.0)
	EntityRegistry.register_ship(near_enemy)

	var alternate_enemy := MockTargetShip.new()
	add_child(alternate_enemy)
	alternate_enemy.name = "soft_distribution_alternate_enemy"
	alternate_enemy.team = "enemy"
	alternate_enemy.global_position = Vector3(16.0, 0.0, 0.0)
	EntityRegistry.register_ship(alternate_enemy)

	var selected_a: Node3D = ChaserShipMinionHelper._get_support_assist_target(support_a, player, 0.1)
	var selected_b: Node3D = ChaserShipMinionHelper._get_support_assist_target(support_b, player, 0.1)
	if selected_a != near_enemy:
		failures.append("first support free assist should still prefer the nearest valid threat; selected=%s" % [selected_a.name if is_instance_valid(selected_a) else "null"])
	if selected_b != alternate_enemy:
		failures.append("second support free assist should prefer an alternate threat once the nearest target is already assigned; selected=%s" % [selected_b.name if is_instance_valid(selected_b) else "null"])
	var near_penalty: float = ChaserShipMinionHelper._get_support_assist_assignment_penalty(
		support_b,
		player,
		near_enemy,
		ChaserShipMinionHelper.SUPPORT_ASSIST_LEASH_DISTANCE,
		false,
		false,
		false,
		false,
		true
	)
	if near_penalty <= 0.0:
		failures.append("support free assist target sharing should add a soft penalty to already assigned normal threats")

	EntityRegistry.unregister_ship(alternate_enemy)
	EntityRegistry.unregister_ship(near_enemy)
	EntityRegistry.unregister_ship(support_b)
	EntityRegistry.unregister_ship(support_a)
	alternate_enemy.queue_free()
	near_enemy.queue_free()
	support_b.queue_free()
	support_a.queue_free()
	player.queue_free()


func _verify_support_boss_breach_navigation_stages_from_flagship_lane(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(0.0, 0.0, -18.0)

	var player := MockTargetShip.new()
	add_child(player)
	player.team = "player"
	player.global_position = Vector3.ZERO
	support.target = player

	var boss := MockTargetShip.new()
	add_child(boss)
	boss.team = "enemy"
	boss.global_position = Vector3(24.0, 0.0, 0.0)
	boss.add_to_group("boss")
	player.manual_boarding_target = boss

	var nav := ChaserShipMinionHelper._build_support_assist_navigation(support, boss, 0)
	var desired_point: Vector3 = ShipMovementIntent.get_desired_point(nav, Vector3.ZERO)
	if desired_point.distance_to(boss.global_position) <= 6.0:
		failures.append("support boss pressure navigation should keep a visible stand-off from the boss hull")
	if absf(desired_point.z - player.global_position.z) <= 2.0:
		failures.append("support boss pressure navigation should keep a visible lateral artillery lane")

	boss.queue_free()
	player.queue_free()
	support.queue_free()


func _verify_support_free_assist_recalls_near_player(failures: Array[String]) -> void:
	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(36.5, 0.0, 0.0)
	_set_support_hold_enabled(support, false)

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


func _verify_enemy_boarding_transfers_last_available_soldier(failures: Array[String]) -> void:
	var source := MockTransferShip.new()
	add_child(source)
	source.team = "enemy"
	source.is_boarding = true
	source.global_position = Vector3.ZERO

	var target := MockTransferShip.new()
	add_child(target)
	target.team = "player"
	target.global_position = Vector3(8.0, 0.0, 0.0)
	source.boarding_target = target

	var soldier := MockTransferSoldier.new()
	soldier.team = "enemy"
	soldier.owned_ship = source
	soldier.home_ship = source
	soldier.position = Vector3(0.0, 0.4, 0.0)
	source.get_node("Soldiers").add_child(soldier)
	EntityRegistry.register_soldier(soldier)

	var transferred := BaseShipBoardingHelper.transfer_one_soldier(source)

	if transferred != true:
		failures.append("enemy boarding should transfer the last available allied soldier instead of forcing one to stay behind")
	if soldier.get_parent() != target.get_node("Soldiers"):
		failures.append("enemy boarding did not move the final available soldier onto the target deck")
	if soldier.owned_ship != target:
		failures.append("enemy boarding did not hand the final available soldier to the target ship")
	if source.get_node("Soldiers").get_child_count() != 0:
		failures.append("enemy boarding should allow the source deck to become temporarily empty after a full boarding wave")

	EntityRegistry.unregister_soldier(soldier)
	target.queue_free()
	source.queue_free()


func _verify_enemy_derelict_waits_for_affiliated_boarders_to_die(failures: Array[String]) -> void:
	var source := MockTransferShip.new()
	add_child(source)
	source.team = "enemy"
	source.is_boarding = true
	source.global_position = Vector3.ZERO

	var target := MockTransferShip.new()
	add_child(target)
	target.team = "player"
	target.global_position = Vector3(8.0, 0.0, 0.0)
	source.boarding_target = target

	var soldier := MockTransferSoldier.new()
	soldier.team = "enemy"
	soldier.owned_ship = source
	soldier.home_ship = source
	soldier.position = Vector3(0.0, 0.4, 0.0)
	source.get_node("Soldiers").add_child(soldier)
	EntityRegistry.register_soldier(soldier)

	BaseShipBoardingHelper.transfer_one_soldier(source)
	var no_more_boarders := BaseShipBoardingHelper.transfer_one_soldier(source)

	if no_more_boarders != false:
		failures.append("enemy boarding should stop once no source-deck soldiers remain")
	if source.is_boarding != false or source.clear_rope_calls <= 0:
		failures.append("enemy boarding should cancel the boarding link when the source deck has no more soldiers to send")
	if source.is_derelict or source.become_derelict_calls != 0:
		failures.append("enemy ship should not become derelict merely because its deck is empty while affiliated boarders are still alive")

	source.check_derelict_status()
	if source.is_derelict:
		failures.append("enemy ship derelict check should keep the ship active while affiliated boarders are alive on the target deck")

	soldier.dead = true
	source.check_derelict_status()
	if not source.is_derelict or source.become_derelict_calls != 1:
		failures.append("enemy ship should become derelict once all affiliated boarders from that hull are dead")

	EntityRegistry.unregister_soldier(soldier)
	target.queue_free()
	source.queue_free()


func _verify_derelict_disposal_waits_while_player_deck_is_contested(failures: Array[String]) -> void:
	var player := MockTransferShip.new()
	add_child(player)
	player.team = "player"
	ShipAllyRoleHelper.mark_player_flagship(player)
	player.global_position = Vector3.ZERO
	player.deck_is_contested = true
	player.deck_hostile_boarder_count = 1

	var derelict := MockTransferShip.new()
	add_child(derelict)
	derelict.team = "enemy"
	derelict.is_derelict = true
	derelict.global_position = Vector3(1.0, 0.0, 0.0)

	var blocked := BaseShipCollisionHelper._try_salvage_derelict_contact(player, derelict, 1.0, 1.0)
	if blocked:
		failures.append("derelict disposal should wait while the player deck is in melee")
	if derelict.get_meta("derelict_contact_disposal_started", false) == true:
		failures.append("derelict disposal should not start while player crew is fighting boarders")
	if derelict.get_meta("derelict_contact_waiting_for_deck_melee", false) != true:
		failures.append("derelict disposal should mark that it is waiting for player deck melee to end")

	player.deck_is_contested = false
	player.deck_hostile_boarder_count = 0
	var started := BaseShipCollisionHelper._try_salvage_derelict_contact(player, derelict, 1.0, 1.0)
	if not started:
		failures.append("derelict disposal should start once player deck melee ends")
	if derelict.get_meta("derelict_contact_waiting_for_deck_melee", false) == true:
		failures.append("derelict disposal should clear deck melee waiting meta after melee ends")

	ShipAllyRoleHelper.clear_ally_role(player)
	player.queue_free()
	derelict.queue_free()


func _verify_derelict_disposal_waits_for_affiliated_boarder_cleanup(failures: Array[String]) -> void:
	var player := MockTransferShip.new()
	add_child(player)
	player.team = "player"
	ShipAllyRoleHelper.mark_player_flagship(player)
	player.global_position = Vector3.ZERO

	var derelict := MockTransferShip.new()
	add_child(derelict)
	derelict.team = "enemy"
	derelict.is_derelict = true
	derelict.global_position = Vector3(1.0, 0.0, 0.0)

	var corpse := MockTransferSoldier.new()
	corpse.team = "enemy"
	corpse.owned_ship = player
	corpse.home_ship = derelict
	corpse.dead = true
	player.get_node("Soldiers").add_child(corpse)
	EntityRegistry.register_soldier(corpse)

	var blocked := BaseShipCollisionHelper._try_salvage_derelict_contact(player, derelict, 1.0, 1.0)
	if blocked:
		failures.append("derelict disposal should wait while affiliated boarder corpses remain on the player deck")
	if derelict.get_meta("derelict_contact_disposal_started", false) == true:
		failures.append("derelict disposal should not mark disposal started before affiliated boarder cleanup")
	if derelict.get_meta("derelict_contact_waiting_for_boarder_cleanup", false) != true:
		failures.append("derelict disposal should mark that it is waiting for affiliated boarder cleanup")

	EntityRegistry.unregister_soldier(corpse)
	corpse.queue_free()

	var started := BaseShipCollisionHelper._try_salvage_derelict_contact(player, derelict, 1.0, 1.0)
	if not started:
		failures.append("derelict disposal should start once affiliated boarders from that hull are cleaned up")
	if derelict.get_meta("derelict_contact_disposal_started", false) != true:
		failures.append("derelict disposal should mark disposal started after affiliated boarder cleanup")
	if derelict.get_meta("derelict_contact_waiting_for_boarder_cleanup", false) == true:
		failures.append("derelict disposal should clear waiting meta after affiliated boarder cleanup")

	ShipAllyRoleHelper.clear_ally_role(player)
	player.queue_free()
	derelict.queue_free()


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


func _verify_boarding_transfer_waits_for_launch_side_boarders(failures: Array[String]) -> void:
	var source := MockTransferShip.new()
	add_child(source)
	source.team = "enemy"
	source.is_boarding = true
	source.global_position = Vector3.ZERO

	var target := MockTransferShip.new()
	add_child(target)
	target.team = "player"
	target.global_position = Vector3(6.0, 0.0, 0.0)
	source.boarding_target = target

	var far_boarder := MockTransferSoldier.new()
	far_boarder.team = "enemy"
	far_boarder.owned_ship = source
	far_boarder.position = Vector3(-2.0, 0.4, 0.0)
	source.get_node("Soldiers").add_child(far_boarder)

	var far_transferred := BaseShipBoardingHelper.transfer_one_soldier(source)
	if far_transferred:
		failures.append("boarding transfer should not launch a soldier from the far side of the source deck")
	if source.is_boarding != true or source.clear_rope_calls != 0:
		failures.append("boarding transfer should wait for launch-side boarders instead of cancelling the link")
	if far_boarder.get_parent() != source.get_node("Soldiers"):
		failures.append("far-side boarder should remain on the source ship while waiting for launch position")

	var near_boarder := MockTransferSoldier.new()
	near_boarder.team = "enemy"
	near_boarder.owned_ship = source
	near_boarder.position = Vector3(1.9, 0.4, 0.0)
	source.get_node("Soldiers").add_child(near_boarder)

	var near_transferred := BaseShipBoardingHelper.transfer_one_soldier(source)
	if not near_transferred:
		failures.append("boarding transfer should launch a soldier already near the contact-side edge")
	if near_boarder.get_parent() != target.get_node("Soldiers"):
		failures.append("boarding transfer did not choose the contact-side boarder")
	if far_boarder.get_parent() != source.get_node("Soldiers"):
		failures.append("boarding transfer moved the far-side boarder before the contact-side boarder")

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


func _verify_soldier_targets_boarder_on_distressed_ally_ship(failures: Array[String]) -> void:
	var player_ship := MockTargetShip.new()
	add_child(player_ship)
	player_ship.team = "player"
	player_ship.global_position = Vector3.ZERO

	var ally_ship := MockTargetShip.new()
	add_child(ally_ship)
	ally_ship.team = "player"
	ally_ship.global_position = Vector3(9.0, 0.0, 0.0)
	ally_ship.deck_is_contested = true
	ally_ship.deck_hostile_boarder_count = 1

	var enemy_ship := MockTargetShip.new()
	add_child(enemy_ship)
	enemy_ship.team = "enemy"
	enemy_ship.global_position = Vector3(18.0, 0.0, 0.0)

	var defender := MockCombatSoldier.new()
	add_child(defender)
	defender.team = "player"
	defender.owned_ship = player_ship
	defender.is_ranged_only = true
	defender.global_position = Vector3.ZERO

	var boarder := MockCombatSoldier.new()
	add_child(boarder)
	boarder.team = "enemy"
	boarder.owned_ship = ally_ship
	boarder.global_position = Vector3(9.0, 0.0, 0.0)

	var remote_enemy := MockCombatSoldier.new()
	add_child(remote_enemy)
	remote_enemy.team = "enemy"
	remote_enemy.owned_ship = enemy_ship
	remote_enemy.global_position = Vector3(18.0, 0.0, 0.0)

	EntityRegistry.register_ship(player_ship)
	EntityRegistry.register_ship(ally_ship)
	EntityRegistry.register_ship(enemy_ship)
	EntityRegistry.register_soldier(defender)
	EntityRegistry.register_soldier(boarder)
	EntityRegistry.register_soldier(remote_enemy)

	var scan_data := SoldierShipSpatialCacheHelper.get_ship_enemy_scan_data(defender)
	var distress_ships: Array = scan_data.get("nearby_ally_distress_ships", [])
	if not distress_ships.has(ally_ship):
		failures.append("soldier targeting scan did not include distressed ally ship")

	var nearest := SoldierShipHelper.find_nearest_enemy(defender)
	if nearest != boarder:
		failures.append("soldier targeting did not select enemy boarder on distressed ally ship")

	EntityRegistry.unregister_soldier(remote_enemy)
	EntityRegistry.unregister_soldier(boarder)
	EntityRegistry.unregister_soldier(defender)
	EntityRegistry.unregister_ship(enemy_ship)
	EntityRegistry.unregister_ship(ally_ship)
	EntityRegistry.unregister_ship(player_ship)
	remote_enemy.queue_free()
	boarder.queue_free()
	defender.queue_free()
	enemy_ship.queue_free()
	ally_ship.queue_free()
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


func _verify_player_crew_speaks_when_ship_is_burning(failures: Array[String]) -> void:
	var player_ship := MockTargetShip.new()
	add_child(player_ship)
	player_ship.team = "player"
	player_ship.is_burning = true

	var sailor := MockCombatSoldier.new()
	add_child(sailor)
	sailor.team = "player"
	sailor.owned_ship = player_ship

	SoldierSpeechHelper.reset(sailor)
	sailor.set_meta("speech_timer", 0.0)
	SoldierSpeechHelper.update(sailor, 1.0)

	var label := sailor.get_node_or_null("SpeechLabel") as Label3D
	if label == null:
		failures.append("player crew did not create a speech label while ship is burning")
	elif label.visible != true or label.text.is_empty():
		failures.append("player crew fire speech did not use fire-context lines")

	sailor.queue_free()
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


func _verify_support_attack_boarders_hold_on_boss_until_sinking(failures: Array[String]) -> void:
	var boss := MockTargetShip.new()
	add_child(boss)
	boss.team = "enemy"
	boss.ship_type = "atakebune_mid"
	boss.global_position = Vector3.ZERO
	boss.boarding_capture_progress = 2.0
	boss.add_to_group("boss")

	var support := MockSupportShip.new()
	add_child(support)
	support.global_position = Vector3(8.0, 0.0, 0.0)
	support.is_boarding = true
	support.boarding_target = boss
	support._initial_rope_deployed = true
	support.set_meta("boarding_purpose", SupportBoardingHelper.SUPPORT_BOARDING_PURPOSE)
	EntityRegistry.register_ship(support)

	var support_boarder := MockTransferSoldier.new()
	add_child(support_boarder)
	support_boarder.team = "player"
	support_boarder.global_position = boss.global_position
	support_boarder.owned_ship = boss
	support_boarder.home_ship = support
	EntityRegistry.register_soldier(support_boarder)

	BaseShipStatusHelper.update_boarding_state(boss, 0.25)

	if support_boarder.owned_ship != support:
		failures.append("support attack boarder on boss did not return after the boss deck was secured")
	if support_boarder.get_boarding_status_value() != "returning":
		failures.append("support attack boarder on boss was not marked returning while jumping home")
	if support.is_boarding == true:
		failures.append("support boss attack boarding link stayed active after the boss deck was secured")
	if support.has_meta("boarding_purpose"):
		failures.append("support boss attack boarding purpose meta was not cleared after return")
	if support.has_meta("boarding_transfer_suppressed"):
		failures.append("support boss attack transfer suppression meta was not cleared after return")
	if boss.boarding_capture_progress > 0.0:
		failures.append("support boss attack return should reset boss capture progress")

	EntityRegistry.unregister_ship(support)
	EntityRegistry.unregister_soldier(support_boarder)
	support_boarder.queue_free()
	support.queue_free()
	boss.queue_free()
