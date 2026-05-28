extends Node
# @scene_contract_encapsulated


const SoldierScene = preload("res://scenes/entities/soldiers/soldier.tscn")
const SoldierLimboAIPilot = preload("res://scripts/ai/limbo/soldier_limbo_ai_pilot.gd")
const SoldierAILimboKeys = preload("res://scripts/ai/limbo/soldier_ai_limbo_keys.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")

const CONTRACT_META_STALE_FRAMES := 8

var _failed := false


class MockShip:
	extends Node3D

	var team := "player"
	var deck_half_extents := Vector2(2.4, 4.4)
	var deck_height := 0.4
	var base_collision_radius := 4.8
	var width_multiplier := 1.0
	var length_multiplier := 1.0
	var shiphandling_crew_ratio := 0.0
	var gunnery_crew_ratio := 0.0
	var current_speed := 0.0
	var rudder_angle := 0.0
	var is_rowing := false
	var is_boarding := false
	var deck_is_contested := false
	var deck_is_overrun := false
	var deck_hostile_boarder_count := 0
	var is_sinking := false
	var is_dying := false
	var boarding_target: Node3D = null
	var _initial_rope_deployed := false
	var _soldiers_container: Node3D = null

	func get_team_tag() -> String:
		return team

	func get_soldiers_container() -> Node:
		return _soldiers_container

	func get_deck_half_extents() -> Vector2:
		return deck_half_extents

	func get_current_speed_value() -> float:
		return current_speed

	func is_sinking_or_dying() -> bool:
		return is_sinking or is_dying

	func get_hull_ratio() -> float:
		return 1.0

	func get_boarding_target_ship() -> Node3D:
		return boarding_target if is_instance_valid(boarding_target) else null

	func has_boarding_rope_link_to(other_ship: Node3D) -> bool:
		return _initial_rope_deployed and get_boarding_target_ship() == other_ship


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	_assert_limboai_classes_registered()
	await _verify_default_tree_selection_contract()
	await _verify_boarding_tree_selection_contract()
	await _verify_attack_mode_contract()
	await _verify_move_mode_contract()
	await _verify_boarding_profile_prefers_active_boarding_target_contract()
	await _verify_ranged_profile_has_no_rail_muster_contract()
	await _verify_player_melee_profile_holds_home_deck_contract()
	await _verify_wander_mode_contract()

	if _failed:
		get_tree().quit(1)
		return
	print("[LimboAISoldierAIPilotContract] ok")
	get_tree().quit(0)


func _verify_default_tree_selection_contract() -> void:
	var boarder := SoldierScene.instantiate() as Node3D
	var ranged := SoldierScene.instantiate() as Node3D
	if boarder == null or ranged == null:
		_fail("failed to instantiate soldier scene for default tree selection")
		return
	add_child(boarder)
	add_child(ranged)
	await get_tree().process_frame

	boarder.set("crew_role", "general")
	boarder.set("is_ranged_only", false)
	var boarder_tree_path := str(boarder.call("get_limbo_ai_default_tree_path")).strip_edges()
	if boarder_tree_path != SoldierLimboAIPilot.BOARDER_TREE_PATH:
		_fail("boarder soldier default tree mismatch: %s" % boarder_tree_path)

	ranged.set("crew_role", "repeating_crossbow")
	ranged.set("is_ranged_only", false)
	var ranged_tree_path := str(ranged.call("get_limbo_ai_default_tree_path")).strip_edges()
	if ranged_tree_path != SoldierLimboAIPilot.RANGED_TREE_PATH:
		_fail("ranged soldier default tree mismatch: %s" % ranged_tree_path)

	boarder.queue_free()
	ranged.queue_free()
	await get_tree().process_frame


func _verify_attack_mode_contract() -> void:
	var scenario := await _spawn_scenario("Attack", Vector3.ZERO, Vector3(16.0, 0.0, 0.0))
	var shared_ship: MockShip = scenario.enemy_ship
	var enemy_soldier := await _spawn_soldier(shared_ship, "enemy", Vector3(-0.4, 0.4, 0.0), true)
	var player_soldier := await _spawn_soldier(shared_ship, "player", Vector3(0.4, 0.4, 0.0), true)
	enemy_soldier.current_state = enemy_soldier.State.IDLE
	enemy_soldier._update_limbo_ai_pilot(0.016)

	_assert_mode(enemy_soldier, SoldierAILimboKeys.MODE_ATTACK_TARGET, "attack mode")
	_assert_recent_target(enemy_soldier, player_soldier, "attack mode target")
	if enemy_soldier.current_target != player_soldier:
		_fail("attack mode bridge did not apply current_target")
	if enemy_soldier.current_state != enemy_soldier.State.ATTACK:
		_fail("attack mode bridge did not switch state to ATTACK")
	await _cleanup_scenario(scenario.root)


func _verify_boarding_tree_selection_contract() -> void:
	var scenario := await _spawn_scenario("BoardingTree", Vector3.ZERO, Vector3(0.0, 0.0, 12.0))
	scenario.player_ship.is_boarding = true
	scenario.player_ship.boarding_target = scenario.enemy_ship
	scenario.player_ship._initial_rope_deployed = true
	var boarder := await _spawn_soldier(scenario.player_ship, "player", Vector3(-1.2, 0.4, -3.8), true)
	boarder.call("apply_crew_role", "general")
	var tree_path := str(boarder.call("get_limbo_ai_default_tree_path")).strip_edges()
	if tree_path != SoldierLimboAIPilot.BOARDING_TREE_PATH:
		_fail("boarding soldier default tree mismatch: %s" % tree_path)
	await _cleanup_scenario(scenario.root)


func _verify_move_mode_contract() -> void:
	var scenario := await _spawn_scenario("Move", Vector3.ZERO, Vector3(16.0, 0.0, 0.0))
	var shared_ship: MockShip = scenario.enemy_ship
	var enemy_soldier := await _spawn_soldier(shared_ship, "enemy", Vector3(-2.0, 0.4, 0.0), true)
	var player_soldier := await _spawn_soldier(shared_ship, "player", Vector3(12.0, 0.4, 0.0), true)
	enemy_soldier.current_state = enemy_soldier.State.IDLE
	enemy_soldier._update_limbo_ai_pilot(0.016)

	_assert_mode(enemy_soldier, SoldierAILimboKeys.MODE_MOVE_TO_TARGET, "move mode")
	_assert_recent_target(enemy_soldier, player_soldier, "move mode target")
	if enemy_soldier.current_state != enemy_soldier.State.MOVE:
		_fail("move mode bridge did not switch state to MOVE")
	await _cleanup_scenario(scenario.root)


func _verify_boarding_profile_prefers_active_boarding_target_contract() -> void:
	var scenario := await _spawn_scenario("BoardingPreference", Vector3.ZERO, Vector3(0.0, 0.0, 16.0))
	var decoy_enemy_ship := _spawn_ship(scenario.root, "EnemyShipBoardingPreferenceDecoy", "enemy", Vector3(8.0, 0.0, 0.0))
	scenario.player_ship.gunnery_crew_ratio = 1.0
	scenario.player_ship.is_boarding = true
	scenario.player_ship.boarding_target = scenario.enemy_ship
	scenario.player_ship._initial_rope_deployed = true
	await get_tree().process_frame

	var boarder := await _spawn_soldier(scenario.player_ship, "player", Vector3(-2.3, 0.4, -4.2), true)
	boarder.call("apply_crew_role", "general")
	boarder.current_state = boarder.State.IDLE
	boarder.current_target = null
	boarder._update_limbo_ai_pilot(0.016)

	_assert_mode(boarder, SoldierAILimboKeys.MODE_WANDER, "boarding profile no duty mode")
	var reason := str(boarder.get_meta(SoldierAILimboKeys.META_REASON, "")).strip_edges()
	if reason != "wander":
		_fail("boarding profile should stay in simple wander mode without duty, got: %s" % reason)
	if boarder.has_meta(SoldierAILimboKeys.META_POINT):
		var actual_point: Variant = boarder.get_meta(SoldierAILimboKeys.META_POINT)
		if actual_point is Vector3:
			_fail("boarding profile should not publish a ship duty point")
	if is_instance_valid(decoy_enemy_ship) and scenario.player_ship.boarding_target != scenario.enemy_ship:
		_fail("boarding profile scenario lost active boarding target")
	await _cleanup_scenario(scenario.root)


func _verify_ranged_profile_has_no_rail_muster_contract() -> void:
	var scenario := await _spawn_scenario("RangedNoMuster", Vector3.ZERO, Vector3(0.0, 0.0, 12.0))
	var ranged_profile_soldier := await _spawn_soldier(scenario.player_ship, "player", Vector3(-2.3, 0.4, -4.2), false)
	ranged_profile_soldier.call("apply_crew_role", "general")
	ranged_profile_soldier.set("limbo_ai_pilot_tree_path", SoldierLimboAIPilot.RANGED_TREE_PATH)
	ranged_profile_soldier.current_state = ranged_profile_soldier.State.IDLE
	ranged_profile_soldier.current_target = null
	ranged_profile_soldier._update_limbo_ai_pilot(0.016)

	_assert_mode(ranged_profile_soldier, SoldierAILimboKeys.MODE_WANDER, "ranged profile no rail muster mode")
	if ranged_profile_soldier.has_meta(SoldierAILimboKeys.META_POINT):
		var point_value: Variant = ranged_profile_soldier.get_meta(SoldierAILimboKeys.META_POINT)
		if point_value is Vector3:
			_fail("ranged profile should not publish a rail muster point")
	await _cleanup_scenario(scenario.root)


func _verify_player_melee_profile_holds_home_deck_contract() -> void:
	var scenario := await _spawn_scenario("PlayerDefensiveMuster", Vector3.ZERO, Vector3(0.0, 0.0, 12.0))
	var player_soldier := await _spawn_soldier(scenario.player_ship, "player", Vector3(-2.3, 0.4, -4.2), true)
	player_soldier.current_state = player_soldier.State.IDLE
	player_soldier.current_target = null
	player_soldier._update_limbo_ai_pilot(0.016)

	_assert_mode(player_soldier, SoldierAILimboKeys.MODE_WANDER, "player defensive melee hold mode")
	if player_soldier.has_meta(SoldierAILimboKeys.META_POINT):
		var point_value: Variant = player_soldier.get_meta(SoldierAILimboKeys.META_POINT)
		if point_value is Vector3:
			_fail("player melee defenders should not publish cross-ship muster points from the home deck")
	await _cleanup_scenario(scenario.root)


func _verify_wander_mode_contract() -> void:
	var scenario := await _spawn_scenario("Wander", Vector3.ZERO, Vector3(120.0, 0.0, 0.0))
	var player_soldier := await _spawn_soldier(scenario.player_ship, "player", Vector3(0.0, 0.4, 0.0), true)
	player_soldier.current_state = player_soldier.State.IDLE
	player_soldier.current_target = null
	player_soldier._update_limbo_ai_pilot(0.016)

	_assert_mode(player_soldier, SoldierAILimboKeys.MODE_WANDER, "wander mode")
	if player_soldier.has_meta(SoldierAILimboKeys.META_POINT):
		var point_value: Variant = player_soldier.get_meta(SoldierAILimboKeys.META_POINT)
		if point_value is Vector3:
			_fail("wander mode should not publish a duty point")
	await _cleanup_scenario(scenario.root)


func _spawn_scenario(label: String, player_pos: Vector3, enemy_pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "LimboAISoldierScenario%s" % label
	add_child(root)

	var player_ship := _spawn_ship(root, "PlayerShip%s" % label, "player", player_pos)
	var enemy_ship := _spawn_ship(root, "EnemyShip%s" % label, "enemy", enemy_pos)

	await get_tree().process_frame
	return {
		"root": root,
		"player_ship": player_ship,
		"enemy_ship": enemy_ship,
	}


func _spawn_ship(parent: Node, ship_name: String, team_name: String, position_value: Vector3) -> MockShip:
	var ship := MockShip.new()
	ship.name = ship_name
	ship.team = team_name
	ship.position = position_value
	var soldiers_node := Node3D.new()
	soldiers_node.name = NodeContractHelper.SHIP_NODE_SOLDIERS
	ship._soldiers_container = soldiers_node
	ship.add_child(soldiers_node)
	parent.add_child(ship)
	EntityRegistry.register_ship(ship)
	return ship


func _spawn_soldier(ship: MockShip, team_name: String, local_position: Vector3, melee_only: bool) -> Node3D:
	var soldier := SoldierScene.instantiate() as Node3D
	if soldier == null:
		_fail("failed to instantiate soldier scene")
		return null
	soldier.set("team", team_name)
	soldier.set("is_melee_only", melee_only)
	soldier.set("is_ranged_only", false)
	soldier.set("limbo_ai_pilot_enabled", true)
	var soldiers_node := ship.get_soldiers_container()
	soldiers_node.add_child(soldier)
	await get_tree().process_frame
	soldier.position = local_position
	soldier.set("wander_timer", 999.0)
	if melee_only and soldier.has_method("_set_active_weapon"):
		soldier.call("_set_active_weapon", "sword")
	return soldier


func _cleanup_scenario(root: Node) -> void:
	if not is_instance_valid(root):
		return
	for child in root.get_children():
		if child is Node:
			EntityRegistry.unregister_ship(child)
	root.queue_free()
	await get_tree().process_frame


func _assert_mode(soldier: Node, expected_mode: String, context: String) -> void:
	var actual_mode := str(soldier.get_meta(SoldierAILimboKeys.META_MODE, "")).strip_edges()
	if actual_mode != expected_mode:
		_fail("%s expected mode %s got %s" % [context, expected_mode, actual_mode])
	var frame: int = int(soldier.get_meta(SoldierAILimboKeys.META_FRAME, -100000))
	if Engine.get_physics_frames() - frame > CONTRACT_META_STALE_FRAMES:
		_fail("%s produced stale Limbo frame metadata" % context)


func _assert_recent_target(soldier: Node, expected_target: Node, context: String) -> void:
	var target_id: int = int(soldier.get_meta(SoldierAILimboKeys.META_TARGET_ID, 0))
	if target_id != expected_target.get_instance_id():
		_fail("%s expected target id %d got %d" % [context, expected_target.get_instance_id(), target_id])


func _assert_recent_point(soldier: Node, context: String) -> void:
	if not soldier.has_meta(SoldierAILimboKeys.META_POINT):
		_fail("%s did not publish a Vector3 point" % context)
		return
	var point_value: Variant = soldier.get_meta(SoldierAILimboKeys.META_POINT)
	if not (point_value is Vector3):
		_fail("%s did not publish a Vector3 point" % context)
		return
	var point: Vector3 = point_value
	if point == Vector3.INF:
		_fail("%s published Vector3.INF instead of a usable point" % context)


func _assert_limboai_classes_registered() -> void:
	for required_class in ["BTPlayer", "BehaviorTree", "BlackboardPlan"]:
		if not ClassDB.class_exists(required_class):
			_fail("missing LimboAI class: %s" % required_class)
	if not SoldierLimboAIPilot.is_available():
		_fail("SoldierLimboAIPilot reported LimboAI unavailable")


func _fail(message: String) -> void:
	_failed = true
	push_error("[LimboAISoldierAIPilotContract] %s" % message)
