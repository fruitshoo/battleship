extends Node


const PILOT_TREE_PATH := "res://resources/ai/limbo/ship_ai_pilot_skeleton.tres"
const CONTRACT_META_STALE_FRAMES := 8

var _failed := false


class MockShip:
	extends Node3D

	var team := "enemy"
	var is_sinking := false
	var is_dying := false
	var is_dead := false
	var target: Node3D = null
	var preferred_range := 24.0
	var range_tolerance := 4.0
	var retreat_distance := 8.0
	var gunner_role := true
	var allow_boarding := false
	var move_speed := 10.0
	var max_hull_hp := 100.0
	var hull_hp := 100.0
	var limbo_ai_pilot_enabled := true
	var use_fire_pot_attack := false
	var max_boarding_distance := 9.0
	var boarding_break_distance := 12.0
	var collision_distance := 8.0

	func is_combat_disabled() -> bool:
		return false

	func is_sinking_or_dying() -> bool:
		return is_sinking or is_dying

	func get_team_tag() -> String:
		return team

	func get_preferred_engagement_range() -> float:
		return preferred_range

	func get_engagement_range_tolerance() -> float:
		return range_tolerance

	func get_retreat_engagement_distance() -> float:
		return retreat_distance

	func is_gunner_role() -> bool:
		return gunner_role

	func can_board_targets() -> bool:
		return allow_boarding

	func can_use_fire_pot_attack() -> bool:
		return use_fire_pot_attack

	func get_collision_distance_to(_other: Node3D) -> float:
		return collision_distance

	func get_hull_ratio() -> float:
		return hull_hp / maxf(max_hull_hp, 0.001)


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	_assert_limboai_classes_registered()

	var enemy_ship := MockShip.new()
	enemy_ship.name = "LimboPilotEnemyShip"
	enemy_ship.team = "enemy"
	enemy_ship.position = Vector3.ZERO
	add_child(enemy_ship)

	var player_ship := MockShip.new()
	player_ship.name = "LimboPilotPlayerShip"
	player_ship.team = "player"
	player_ship.position = Vector3(24.0, 0.0, 0.0)
	add_child(player_ship)
	EntityRegistry.register_ship(enemy_ship)
	EntityRegistry.register_ship(player_ship)

	await _verify_pilot_state(
		enemy_ship,
		player_ship,
		24.0,
		100.0,
		ShipAILimboKeys.INTENT_ENGAGE,
		ShipAILimboKeys.PHASE_STABLE,
		0.0,
		ShipAILimboKeys.STANCE_BOMBARD,
		ShipAILimboKeys.WEAPON_BROADSIDE_READY
	)
	await _verify_pilot_state(
		enemy_ship,
		player_ship,
		40.0,
		100.0,
		ShipAILimboKeys.INTENT_CLOSE_DISTANCE,
		ShipAILimboKeys.PHASE_STABLE,
		0.0,
		ShipAILimboKeys.STANCE_CLOSE_DISTANCE,
		ShipAILimboKeys.WEAPON_RANGED_PRESSURE
	)
	await _verify_pilot_state(
		enemy_ship,
		player_ship,
		8.0,
		100.0,
		ShipAILimboKeys.INTENT_HOLD,
		ShipAILimboKeys.PHASE_STABLE,
		0.0,
		ShipAILimboKeys.STANCE_WITHDRAW,
		ShipAILimboKeys.WEAPON_HOLD_FIRE
	)
	await _verify_pilot_state(
		enemy_ship,
		player_ship,
		24.0,
		50.0,
		ShipAILimboKeys.INTENT_ENGAGE,
		ShipAILimboKeys.PHASE_DAMAGED,
		0.45,
		ShipAILimboKeys.STANCE_ORBIT_PRESSURE,
		ShipAILimboKeys.WEAPON_RANGED_PRESSURE
	)
	await _verify_pilot_state(
		enemy_ship,
		player_ship,
		24.0,
		20.0,
		ShipAILimboKeys.INTENT_ENGAGE,
		ShipAILimboKeys.PHASE_DESPERATE,
		1.0,
		ShipAILimboKeys.STANCE_DESPERATE_PUSH,
		ShipAILimboKeys.WEAPON_DESPERATE_VOLLEY
	)

	var target_id := int(enemy_ship.get_meta(ShipAILimboKeys.META_TARGET_ID, 0))
	if target_id != player_ship.get_instance_id():
		_fail("pilot target id mismatch: %d expected %d" % [target_id, player_ship.get_instance_id()])
	if enemy_ship.target != player_ship:
		_fail("pilot bridge did not apply target")
	_verify_weapon_guard(enemy_ship)
	await _verify_fire_pot_special_state(enemy_ship, player_ship, 11.0, ShipAILimboKeys.SPECIAL_FIRE_POT_READY)
	await _verify_fire_pot_special_state(enemy_ship, player_ship, 4.5, ShipAILimboKeys.SPECIAL_HOLD)
	await _verify_fire_pot_special_state(enemy_ship, player_ship, 22.0, ShipAILimboKeys.SPECIAL_CLOSE_DISTANCE)
	await _verify_boarding_intent_state(enemy_ship, player_ship, 14.5, ShipAILimboKeys.BOARDING_APPROACH)
	await _verify_boarding_intent_state(enemy_ship, player_ship, 9.5, ShipAILimboKeys.BOARDING_READY)

	EntityRegistry.unregister_ship(enemy_ship)
	EntityRegistry.unregister_ship(player_ship)
	enemy_ship.queue_free()
	player_ship.queue_free()

	if _failed:
		get_tree().quit(1)
		return
	print("[LimboAIShipAIPilotContract] ok target=%s range_intents=engage/close_distance/hold pressure=stable/damaged/desperate stance=bombard/orbit_pressure/withdraw/desperate_push" % player_ship.name)
	get_tree().quit(0)


func _verify_pilot_state(
	enemy_ship: MockShip,
	player_ship: MockShip,
	distance: float,
	hull_hp: float,
	expected_intent: String,
	expected_phase: String,
	expected_pressure: float,
	expected_stance: String,
	expected_weapon_intent: String
) -> void:
	player_ship.position = Vector3(distance, 0.0, 0.0)
	enemy_ship.hull_hp = hull_hp
	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame

	var intent := str(enemy_ship.get_meta(ShipAILimboKeys.META_INTENT, ""))
	var target_distance := float(enemy_ship.get_meta(ShipAILimboKeys.META_TARGET_DISTANCE, -1.0))
	var phase := str(enemy_ship.get_meta(ShipAILimboKeys.META_PRESSURE_PHASE, ""))
	var pressure := float(enemy_ship.get_meta(ShipAILimboKeys.META_PRESSURE, -1.0))
	var stance := str(enemy_ship.get_meta(ShipAILimboKeys.META_STANCE, ""))
	if intent != expected_intent:
		_fail("pilot intent mismatch at %.1fm: %s expected %s" % [distance, intent, expected_intent])
	if absf(target_distance - distance) > 0.05:
		_fail("pilot target distance mismatch: %.2f expected %.2f" % [target_distance, distance])
	if phase != expected_phase:
		_fail("pilot pressure phase mismatch at %.1f hull: %s expected %s" % [hull_hp, phase, expected_phase])
	if absf(pressure - expected_pressure) > 0.01:
		_fail("pilot pressure mismatch at %.1f hull: %.2f expected %.2f" % [hull_hp, pressure, expected_pressure])
	if stance != expected_stance:
		_fail("pilot stance mismatch at %.1fm/%.1f hull: %s expected %s" % [distance, hull_hp, stance, expected_stance])
	_verify_navigation_hint(enemy_ship, player_ship, expected_stance)
	_verify_weapon_intent(enemy_ship, player_ship, expected_weapon_intent)


func _verify_weapon_intent(enemy_ship: MockShip, player_ship: MockShip, expected_weapon_intent: String) -> void:
	var weapon_intent := str(enemy_ship.get_meta(ShipAILimboKeys.META_WEAPON_INTENT, ""))
	if weapon_intent != expected_weapon_intent:
		_fail("pilot weapon intent mismatch: %s expected %s" % [weapon_intent, expected_weapon_intent])
	var weapon_target_id := int(enemy_ship.get_meta(ShipAILimboKeys.META_WEAPON_TARGET_ID, 0))
	if weapon_target_id != player_ship.get_instance_id():
		_fail("pilot weapon intent target mismatch: %d expected %d" % [weapon_target_id, player_ship.get_instance_id()])
	var weapon_frame := int(enemy_ship.get_meta(ShipAILimboKeys.META_WEAPON_FRAME, -1000000))
	if Engine.get_physics_frames() - weapon_frame > CONTRACT_META_STALE_FRAMES:
		_fail("pilot weapon intent frame is stale: %d" % weapon_frame)


func _verify_navigation_hint(enemy_ship: MockShip, player_ship: MockShip, expected_stance: String) -> void:
	var nav_target_id := int(enemy_ship.get_meta(ShipAILimboKeys.META_NAV_TARGET_ID, 0))
	if nav_target_id != player_ship.get_instance_id():
		_fail("pilot navigation hint target mismatch: %d expected %d" % [nav_target_id, player_ship.get_instance_id()])
	var nav_frame := int(enemy_ship.get_meta(ShipAILimboKeys.META_NAV_FRAME, -1000000))
	if Engine.get_physics_frames() - nav_frame > CONTRACT_META_STALE_FRAMES:
		_fail("pilot navigation hint frame is stale: %d" % nav_frame)
	var desired_value: Variant = enemy_ship.get_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT, null)
	var heading_value: Variant = enemy_ship.get_meta(ShipAILimboKeys.META_NAV_HEADING_POINT, null)
	if not (desired_value is Vector3):
		_fail("pilot navigation desired point missing for stance %s" % expected_stance)
		return
	if not (heading_value is Vector3):
		_fail("pilot navigation heading point missing for stance %s" % expected_stance)
	var speed := float(enemy_ship.get_meta(ShipAILimboKeys.META_NAV_SPEED_MULT, -1.0))
	if speed <= 0.0:
		_fail("pilot navigation speed missing for stance %s" % expected_stance)
	var mode := str(enemy_ship.get_meta(ShipAILimboKeys.META_NAV_MODE, ""))
	if not mode.begins_with("limbo_"):
		_fail("pilot navigation mode missing for stance %s: %s" % [expected_stance, mode])
	match expected_stance:
		ShipAILimboKeys.STANCE_CLOSE_DISTANCE:
			if speed < 0.98:
				_fail("pilot close-distance navigation speed too low: %.2f" % speed)
		ShipAILimboKeys.STANCE_ORBIT_PRESSURE:
			if speed < 0.34:
				_fail("pilot orbit-pressure navigation speed too low: %.2f" % speed)
		ShipAILimboKeys.STANCE_DESPERATE_PUSH:
			if speed < 1.05:
				_fail("pilot desperate-push navigation speed too low: %.2f" % speed)
		ShipAILimboKeys.STANCE_WITHDRAW:
			if bool(enemy_ship.get_meta(ShipAILimboKeys.META_NAV_PERMIT_SPRINT, true)) == true:
				_fail("pilot withdraw navigation should block sprint")


func _verify_weapon_guard(enemy_ship: MockShip) -> void:
	enemy_ship.team = "enemy"
	enemy_ship.limbo_ai_pilot_enabled = true
	enemy_ship.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, ShipAILimboKeys.WEAPON_HOLD_FIRE)
	enemy_ship.set_meta(ShipAILimboKeys.META_WEAPON_FRAME, Engine.get_physics_frames())
	if LauncherCombatHelper.is_owner_combat_ready(enemy_ship):
		_fail("launcher guard should block enemy hold-fire weapon intent")

	enemy_ship.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, ShipAILimboKeys.WEAPON_BROADSIDE_READY)
	if not LauncherCombatHelper.is_owner_combat_ready(enemy_ship):
		_fail("launcher guard should allow non-hold LimboAI weapon intent")

	enemy_ship.team = "player"
	enemy_ship.set_meta(ShipAILimboKeys.META_WEAPON_INTENT, ShipAILimboKeys.WEAPON_HOLD_FIRE)
	if not LauncherCombatHelper.is_owner_combat_ready(enemy_ship):
		_fail("launcher guard should not apply LimboAI weapon intent to player ships")

	enemy_ship.team = "enemy"
	enemy_ship.set_meta(ShipAILimboKeys.META_WEAPON_FRAME, Engine.get_physics_frames() - 12)
	if not LauncherCombatHelper.is_owner_combat_ready(enemy_ship):
		_fail("launcher guard should ignore stale LimboAI weapon intent")


func _verify_fire_pot_special_state(
	enemy_ship: MockShip,
	player_ship: MockShip,
	distance: float,
	expected_special_intent: String
) -> void:
	enemy_ship.team = "enemy"
	enemy_ship.gunner_role = false
	enemy_ship.allow_boarding = true
	enemy_ship.use_fire_pot_attack = true
	enemy_ship.limbo_ai_pilot_enabled = true
	player_ship.position = Vector3(distance, 0.0, 0.0)

	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame

	var special_intent := str(enemy_ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_INTENT, ""))
	if special_intent != expected_special_intent:
		_fail("pilot special attack intent mismatch at %.1fm: %s expected %s" % [distance, special_intent, expected_special_intent])
	var special_target_id := int(enemy_ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_TARGET_ID, 0))
	if special_target_id != player_ship.get_instance_id():
		_fail("pilot special attack target mismatch: %d expected %d" % [special_target_id, player_ship.get_instance_id()])
	var special_frame := int(enemy_ship.get_meta(ShipAILimboKeys.META_SPECIAL_ATTACK_FRAME, -1000000))
	if Engine.get_physics_frames() - special_frame > CONTRACT_META_STALE_FRAMES:
		_fail("pilot special attack frame is stale: %d" % special_frame)
	if enemy_ship.has_meta(ShipAILimboKeys.META_WEAPON_INTENT):
		_fail("boarding firepot pilot should not publish launcher weapon intent")

	enemy_ship.gunner_role = true
	enemy_ship.allow_boarding = false
	enemy_ship.use_fire_pot_attack = false


func _verify_boarding_intent_state(
	enemy_ship: MockShip,
	player_ship: MockShip,
	distance: float,
	expected_boarding_intent: String
) -> void:
	enemy_ship.team = "enemy"
	enemy_ship.gunner_role = false
	enemy_ship.allow_boarding = true
	enemy_ship.use_fire_pot_attack = false
	enemy_ship.limbo_ai_pilot_enabled = true
	player_ship.position = Vector3(distance, 0.0, 0.0)

	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame

	var boarding_intent := str(enemy_ship.get_meta(ShipAILimboKeys.META_BOARDING_INTENT, ""))
	if boarding_intent != expected_boarding_intent:
		_fail("pilot boarding intent mismatch at %.1fm: %s expected %s" % [distance, boarding_intent, expected_boarding_intent])
	var boarding_target_id := int(enemy_ship.get_meta(ShipAILimboKeys.META_BOARDING_TARGET_ID, 0))
	if boarding_target_id != player_ship.get_instance_id():
		_fail("pilot boarding target mismatch: %d expected %d" % [boarding_target_id, player_ship.get_instance_id()])
	var boarding_frame := int(enemy_ship.get_meta(ShipAILimboKeys.META_BOARDING_FRAME, -1000000))
	if Engine.get_physics_frames() - boarding_frame > CONTRACT_META_STALE_FRAMES:
		_fail("pilot boarding frame is stale: %d" % boarding_frame)
	var attempt_distance := float(enemy_ship.get_meta(ShipAILimboKeys.META_BOARDING_ATTEMPT_DISTANCE, 0.0))
	if absf(attempt_distance - enemy_ship.boarding_break_distance) > 0.05:
		_fail("pilot boarding attempt distance mismatch: %.2f expected %.2f" % [attempt_distance, enemy_ship.boarding_break_distance])
	if enemy_ship.has_meta(ShipAILimboKeys.META_WEAPON_INTENT):
		_fail("boarding pilot should not publish launcher weapon intent")

	enemy_ship.gunner_role = true
	enemy_ship.allow_boarding = false


func _assert_limboai_classes_registered() -> void:
	for class_id in ["BTPlayer", "BehaviorTree", "BTAction", "BTCondition", "BTSequence"]:
		if not ClassDB.class_exists(class_id):
			_fail("missing LimboAI class: %s" % class_id)


func _fail(message: String) -> void:
	_failed = true
	push_error("[LimboAIShipAIPilotContract] %s" % message)
