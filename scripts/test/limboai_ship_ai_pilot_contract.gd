extends Node
# @scene_contract_encapsulated

const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")


const PILOT_TREE_PATH := "res://resources/ai/limbo/ship_ai_pilot_skeleton.tres"
const ENEMY_GUNNER_PILOT_TREE_PATH := "res://resources/ai/limbo/enemy_gunner_ai_pilot.tres"
const ENEMY_BOARDER_PILOT_TREE_PATH := "res://resources/ai/limbo/enemy_boarder_ai_pilot.tres"
const ENEMY_FIREPOT_PILOT_TREE_PATH := "res://resources/ai/limbo/enemy_firepot_ai_pilot.tres"
const BOSS_PILOT_TREE_PATH := "res://resources/ai/limbo/boss_ship_ai_pilot.tres"
const SUPPORT_PILOT_TREE_PATH := "res://resources/ai/limbo/support_ship_ai_pilot.tres"
const CAPTURED_MINION_PILOT_TREE_PATH := "res://resources/ai/limbo/captured_minion_ai_pilot.tres"
const CONTRACT_META_STALE_FRAMES := 8
const LIMBO_ACTIVE_SHIP_SCENE_PATHS := {
	"res://scenes/ships/enemy_base_ship.tscn": ENEMY_BOARDER_PILOT_TREE_PATH,
	"res://scenes/ships/enemy_ship.tscn": ENEMY_BOARDER_PILOT_TREE_PATH,
	"res://scenes/ships/enemy_melee_ship.tscn": ENEMY_BOARDER_PILOT_TREE_PATH,
	"res://scenes/ships/enemy_gunner_ship.tscn": ENEMY_GUNNER_PILOT_TREE_PATH,
	"res://scenes/ships/enemy_firepot_ship.tscn": ENEMY_FIREPOT_PILOT_TREE_PATH,
	"res://scenes/ships/boss_ship.tscn": BOSS_PILOT_TREE_PATH,
	"res://scenes/ships/support_ship.tscn": SUPPORT_PILOT_TREE_PATH,
	"res://scenes/ships/support_maengseon_ship.tscn": SUPPORT_PILOT_TREE_PATH,
	"res://scenes/ships/support_panokseon_ship.tscn": SUPPORT_PILOT_TREE_PATH,
}

var _failed := false


class MockShip:
	extends Node3D

	var team := "enemy"
	var is_sinking := false
	var is_dying := false
	var is_dead := false
	var is_derelict := false
	var ship_type := ""
	var target: Node3D = null
	var boarding_target: Node3D = null
	var boarding_attacker: Node3D = null
	var auto_raid_target: Node3D = null
	var manual_boarding_target: Node3D = null
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
	var deck_is_contested := false
	var deck_is_overrun := false
	var deck_hostile_boarder_count := 0
	var blocks_boarding := false
	var support_hold_formation := false

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

	func can_be_boarded_by(_attacker_ship: Node = null) -> bool:
		return not blocks_boarding

	func can_use_fire_pot_attack() -> bool:
		return use_fire_pot_attack

	func get_collision_distance_to(_other: Node3D) -> float:
		return collision_distance

	func get_boarding_target_ship() -> Node3D:
		return boarding_target

	func set_boarding_attacker_ship(attacker: Node3D) -> void:
		boarding_attacker = attacker

	func get_boarding_attacker_ship() -> Node3D:
		return boarding_attacker

	func get_hull_ratio() -> float:
		return hull_hp / maxf(max_hull_hp, 0.001)


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	_assert_limboai_classes_registered()
	await _verify_limbo_scene_defaults()
	await _verify_capture_enables_limbo_defaults()

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
	await _verify_boss_pilot_state(enemy_ship, player_ship, 24.0, 100.0)

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
	await _verify_unboardable_target_suppresses_boarding_intent(enemy_ship, player_ship)

	var support_ship := MockShip.new()
	support_ship.name = "LimboPilotSupportShip"
	support_ship.team = "player"
	support_ship.position = Vector3(-16.0, 0.0, 0.0)
	add_child(support_ship)
	ShipAllyRoleHelper.mark_player_flagship(player_ship)
	ShipAllyRoleHelper.mark_support_ship(support_ship)
	EntityRegistry.register_ship(support_ship)

	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP,
		"formation",
		player_ship,
		Vector3(-16.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(120.0, 0.0, 0.0),
		false,
		false,
		0,
		false
	)
	enemy_ship.add_to_group("boss")
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT,
		"nearby_threat",
		enemy_ship,
		Vector3(-10.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(20.0, 0.0, 0.0),
		false,
		false,
		0,
		false,
		enemy_ship
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT,
		"nearby_threat",
		enemy_ship,
		Vector3(-10.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(20.0, 0.0, 0.0),
		false,
		false,
		0,
		false,
		null,
		enemy_ship
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP,
		"formation_hold",
		player_ship,
		Vector3(-10.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(20.0, 0.0, 0.0),
		false,
		false,
		0,
		true,
		enemy_ship,
		null,
		true
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP,
		"formation_hold",
		player_ship,
		Vector3(-10.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(20.0, 0.0, 0.0),
		false,
		false,
		0,
		true,
		null,
		enemy_ship,
		true
	)
	enemy_ship.remove_from_group("boss")
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP,
		"flagship_deck_emergency",
		player_ship,
		Vector3(118.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(120.0, 0.0, 0.0),
		false,
		true,
		3,
		false
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT,
		"nearby_threat",
		enemy_ship,
		Vector3(-10.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(18.0, 0.0, 0.0),
		false,
		false,
		0,
		false
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_REGROUP,
		"outside_recall",
		player_ship,
		Vector3(150.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(120.0, 0.0, 0.0),
		false,
		false,
		0,
		false
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP,
		"formation_hold",
		player_ship,
		Vector3(-16.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(18.0, 0.0, 0.0),
		false,
		false,
		0,
		true
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP,
		"formation_hold",
		player_ship,
		Vector3(-16.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(18.0, 0.0, 0.0),
		false,
		false,
		0,
		true,
		null,
		null,
		true
	)
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT,
		"flagship_boarding_attacker",
		enemy_ship,
		Vector3(-16.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(18.0, 0.0, 0.0),
		false,
		false,
		0,
		true,
		null,
		null,
		true,
		enemy_ship
	)
	support_ship.ship_type = "panokseon_ally"
	support_ship.set_meta("support_squadron_slot_role", "artillery_lead")
	await _verify_support_pilot_mode(
		support_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT,
		"flagship_boarding_attacker",
		enemy_ship,
		Vector3(-16.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(18.0, 0.0, 0.0),
		false,
		false,
		0,
		false,
		null,
		null,
		false,
		enemy_ship
	)
	support_ship.ship_type = ""
	if support_ship.has_meta("support_squadron_slot_role"):
		support_ship.remove_meta("support_squadron_slot_role")

	var captured_ship := MockShip.new()
	captured_ship.name = "LimboPilotCapturedMinion"
	captured_ship.team = "player"
	captured_ship.position = Vector3(-12.0, 0.0, 0.0)
	add_child(captured_ship)
	ShipAllyRoleHelper.mark_captured_minion(captured_ship)
	EntityRegistry.register_ship(captured_ship)

	await _verify_captured_minion_pilot_mode(
		captured_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.ALLY_MODE_FOLLOW_FLAGSHIP,
		"formation",
		player_ship,
		Vector3(-12.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(120.0, 0.0, 0.0),
		false
	)
	await _verify_captured_minion_pilot_mode(
		captured_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.ALLY_MODE_GUARD_THREAT,
		"nearby_threat",
		enemy_ship,
		Vector3(-16.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(18.0, 0.0, 0.0),
		false
	)
	await _verify_captured_minion_pilot_mode(
		captured_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.ALLY_MODE_GUARD_THREAT,
		"flagship_boarder",
		enemy_ship,
		Vector3(-18.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(32.0, 0.0, 0.0),
		true
	)
	await _verify_captured_minion_pilot_mode(
		captured_ship,
		player_ship,
		enemy_ship,
		ShipAILimboKeys.ALLY_MODE_REGROUP,
		"outside_recall",
		player_ship,
		Vector3(48.0, 0.0, 0.0),
		Vector3.ZERO,
		Vector3(120.0, 0.0, 0.0),
		false
	)

	EntityRegistry.unregister_ship(captured_ship)
	EntityRegistry.unregister_ship(support_ship)
	EntityRegistry.unregister_ship(enemy_ship)
	EntityRegistry.unregister_ship(player_ship)
	captured_ship.queue_free()
	support_ship.queue_free()
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

	ShipLimboAIPilot.tick(enemy_ship, 0.016, ENEMY_FIREPOT_PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(enemy_ship, 0.016, ENEMY_FIREPOT_PILOT_TREE_PATH)
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


func _verify_unboardable_target_suppresses_boarding_intent(enemy_ship: MockShip, player_ship: MockShip) -> void:
	enemy_ship.team = "enemy"
	enemy_ship.gunner_role = false
	enemy_ship.allow_boarding = true
	enemy_ship.use_fire_pot_attack = false
	enemy_ship.limbo_ai_pilot_enabled = true
	player_ship.blocks_boarding = true
	player_ship.position = Vector3(9.5, 0.0, 0.0)

	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(enemy_ship, 0.016, PILOT_TREE_PATH)
	await get_tree().process_frame

	if enemy_ship.has_meta(ShipAILimboKeys.META_BOARDING_INTENT):
		_fail("pilot should not publish boarding intent against unboardable target")
	if not enemy_ship.has_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT):
		_fail("pilot should publish navigation hint against unboardable target")
	if not enemy_ship.has_meta(ShipAILimboKeys.META_WEAPON_INTENT):
		_fail("pilot should fall back to weapon pressure against unboardable target")

	player_ship.blocks_boarding = false
	enemy_ship.gunner_role = true
	enemy_ship.allow_boarding = false


func _verify_boss_pilot_state(
	enemy_ship: MockShip,
	player_ship: MockShip,
	distance: float,
	hull_hp: float
) -> void:
	player_ship.position = Vector3(distance, 0.0, 0.0)
	enemy_ship.hull_hp = hull_hp
	enemy_ship.gunner_role = true
	enemy_ship.allow_boarding = false
	enemy_ship.use_fire_pot_attack = false
	ShipLimboAIPilot.tick(enemy_ship, 0.016, BOSS_PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(enemy_ship, 0.016, BOSS_PILOT_TREE_PATH)
	await get_tree().process_frame
	_verify_navigation_hint(enemy_ship, player_ship, ShipAILimboKeys.STANCE_BOMBARD)
	_verify_weapon_intent(enemy_ship, player_ship, ShipAILimboKeys.WEAPON_BROADSIDE_READY)
	if enemy_ship.has_meta(ShipAILimboKeys.META_BOARDING_INTENT):
		_fail("boss pilot should not publish boarding intent")


func _verify_support_pilot_mode(
	support_ship: MockShip,
	player_ship: MockShip,
	enemy_ship: MockShip,
	expected_mode: String,
	expected_reason: String,
	expected_support_target: Node3D,
	support_position: Vector3,
	player_position: Vector3,
	enemy_position: Vector3,
	player_deck_contested: bool,
	player_deck_overrun: bool,
	hostile_boarder_count: int,
	support_hold_formation: bool,
	player_auto_raid_target: Node3D = null,
	player_manual_boarding_target: Node3D = null,
	use_flagship_owner_state: bool = false,
	player_boarding_attacker: Node3D = null
) -> void:
	support_ship.position = support_position
	player_ship.position = player_position
	enemy_ship.position = enemy_position
	enemy_ship.boarding_target = player_ship if player_deck_contested else null
	player_ship.auto_raid_target = player_auto_raid_target
	player_ship.manual_boarding_target = player_manual_boarding_target
	player_ship.set_boarding_attacker_ship(player_boarding_attacker)
	player_ship.deck_is_contested = player_deck_contested
	player_ship.deck_is_overrun = player_deck_overrun
	player_ship.deck_hostile_boarder_count = hostile_boarder_count
	if player_ship.has_meta(SupportFleetStateHelper.SUPPORT_FLEET_FORMATION_META):
		player_ship.remove_meta(SupportFleetStateHelper.SUPPORT_FLEET_FORMATION_META)
	if player_ship.has_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META):
		player_ship.remove_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META)
	if support_ship.has_meta(SupportFleetStateHelper.SUPPORT_FLEET_OWNER_ID_META):
		support_ship.remove_meta(SupportFleetStateHelper.SUPPORT_FLEET_OWNER_ID_META)
	if support_hold_formation and not use_flagship_owner_state:
		support_ship.set_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META, true)
	elif support_ship.has_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META):
		support_ship.remove_meta(SupportFleetStateHelper.SUPPORT_HOLD_FORMATION_META)
	if use_flagship_owner_state:
		SupportFleetStateHelper.set_flagship_hold_enabled(player_ship, support_hold_formation)
		SupportFleetStateHelper.assign_support_ship_to_flagship(support_ship, player_ship)
	support_ship.limbo_ai_pilot_enabled = true
	support_ship.target = player_ship if use_flagship_owner_state else null

	ShipLimboAIPilot.tick(support_ship, 0.016, SUPPORT_PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(support_ship, 0.016, SUPPORT_PILOT_TREE_PATH)
	await get_tree().process_frame

	var flagship_target_id := int(support_ship.get_meta(ShipAILimboKeys.META_TARGET_ID, 0))
	if flagship_target_id != player_ship.get_instance_id():
		_fail("support pilot flagship target mismatch: %d expected %d" % [flagship_target_id, player_ship.get_instance_id()])
	if support_ship.target != player_ship:
		_fail("support pilot should keep the flagship as the ship target")
	var mode := str(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_MODE, ""))
	if mode != expected_mode:
		_fail("support pilot mode mismatch: %s expected %s" % [mode, expected_mode])
	var support_target_id := int(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, 0))
	if support_target_id != expected_support_target.get_instance_id():
		_fail("support pilot support target mismatch: %d expected %d" % [support_target_id, expected_support_target.get_instance_id()])
	var support_frame := int(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_FRAME, -1000000))
	if Engine.get_physics_frames() - support_frame > CONTRACT_META_STALE_FRAMES:
		_fail("support pilot frame is stale: %d" % support_frame)
	var reason := str(support_ship.get_meta(ShipAILimboKeys.META_SUPPORT_REASON, "")).strip_edges()
	if reason.is_empty():
		_fail("support pilot reason is missing")
	elif reason != expected_reason:
		_fail("support pilot reason mismatch: %s expected %s" % [reason, expected_reason])
	if support_ship.has_meta(ShipAILimboKeys.META_WEAPON_INTENT):
		_fail("support pilot should not publish launcher weapon intent")


func _verify_captured_minion_pilot_mode(
	captured_ship: MockShip,
	player_ship: MockShip,
	enemy_ship: MockShip,
	expected_mode: String,
	expected_reason: String,
	expected_ally_target: Node3D,
	captured_position: Vector3,
	player_position: Vector3,
	enemy_position: Vector3,
	enemy_boarding_flagship: bool
) -> void:
	captured_ship.position = captured_position
	player_ship.position = player_position
	enemy_ship.position = enemy_position
	enemy_ship.boarding_target = player_ship if enemy_boarding_flagship else null
	captured_ship.limbo_ai_pilot_enabled = true
	captured_ship.target = null

	ShipLimboAIPilot.tick(captured_ship, 0.016, CAPTURED_MINION_PILOT_TREE_PATH)
	await get_tree().process_frame
	ShipLimboAIPilot.tick(captured_ship, 0.016, CAPTURED_MINION_PILOT_TREE_PATH)
	await get_tree().process_frame

	var flagship_target_id := int(captured_ship.get_meta(ShipAILimboKeys.META_TARGET_ID, 0))
	if flagship_target_id != player_ship.get_instance_id():
		_fail("captured pilot flagship target mismatch: %d expected %d" % [flagship_target_id, player_ship.get_instance_id()])
	if captured_ship.target != player_ship:
		_fail("captured pilot should keep the flagship as the ship target")
	var mode := str(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_MODE, ""))
	if mode != expected_mode:
		_fail("captured pilot mode mismatch: %s expected %s" % [mode, expected_mode])
	var ally_target_id := int(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_TARGET_ID, 0))
	if ally_target_id != expected_ally_target.get_instance_id():
		_fail("captured pilot ally target mismatch: %d expected %d" % [ally_target_id, expected_ally_target.get_instance_id()])
	var ally_frame := int(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_FRAME, -1000000))
	if Engine.get_physics_frames() - ally_frame > CONTRACT_META_STALE_FRAMES:
		_fail("captured pilot frame is stale: %d" % ally_frame)
	var reason := str(captured_ship.get_meta(ShipAILimboKeys.META_ALLY_REASON, "")).strip_edges()
	if reason.is_empty():
		_fail("captured pilot reason is missing")
	elif reason != expected_reason:
		_fail("captured pilot reason mismatch: %s expected %s" % [reason, expected_reason])


func _assert_limboai_classes_registered() -> void:
	for class_id in ["BTPlayer", "BehaviorTree", "BTAction", "BTCondition", "BTSequence"]:
		if not ClassDB.class_exists(class_id):
			_fail("missing LimboAI class: %s" % class_id)


func _verify_capture_enables_limbo_defaults() -> void:
	var packed := load("res://scenes/ships/enemy_ship.tscn") as PackedScene
	if packed == null:
		_fail("capture LimboAI scene load failed")
		return
	var captured_ship := packed.instantiate()
	if captured_ship == null:
		_fail("capture LimboAI scene instantiate failed")
		return
	add_child(captured_ship)
	await get_tree().process_frame
	captured_ship.call("capture_ship")
	await get_tree().process_frame
	if captured_ship.get("limbo_ai_pilot_enabled") != true:
		_fail("captured ship should enable LimboAI after capture")
	var tree_path := str(captured_ship.get("limbo_ai_pilot_tree_path")).strip_edges()
	if tree_path != CAPTURED_MINION_PILOT_TREE_PATH:
		_fail("captured ship LimboAI tree mismatch: %s expected %s" % [tree_path, CAPTURED_MINION_PILOT_TREE_PATH])
	EntityRegistry.unregister_captured_minion(captured_ship)
	EntityRegistry.unregister_ship(captured_ship)
	captured_ship.queue_free()
	await get_tree().process_frame


func _verify_limbo_scene_defaults() -> void:
	for scene_path in LIMBO_ACTIVE_SHIP_SCENE_PATHS.keys():
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_fail("LimboAI ship scene load failed: %s" % scene_path)
			continue
		var ship := packed.instantiate()
		if ship == null:
			_fail("LimboAI ship scene instantiate failed: %s" % scene_path)
			continue
		add_child(ship)
		await get_tree().process_frame
		if ship.get("limbo_ai_pilot_enabled") != true:
			_fail("LimboAI ship default disabled: %s" % scene_path)
		var tree_path := str(ship.get("limbo_ai_pilot_tree_path")).strip_edges()
		if tree_path.is_empty():
			_fail("LimboAI ship tree path missing: %s" % scene_path)
		var expected_tree_path := str(LIMBO_ACTIVE_SHIP_SCENE_PATHS[scene_path]).strip_edges()
		if tree_path != expected_tree_path:
			_fail("LimboAI ship tree path mismatch: %s -> %s expected %s" % [scene_path, tree_path, expected_tree_path])
		EntityRegistry.unregister_ship(ship)
		ship.queue_free()
		await get_tree().process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("[LimboAIShipAIPilotContract] %s" % message)
