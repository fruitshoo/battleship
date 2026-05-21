extends RefCounted
class_name ProjectContractRuntimeHelper

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")


const FIRE_EFFECT_SCENE_PATH := "res://scenes/effects/fire_effect.tscn"
const AUTHORING_PALETTE_DATA_PATH := "res://data/authoring_palette.json"
const AUTHORING_INTENT_FAMILY_ENEMY_RUNTIME := "enemy_runtime"
const AUTHORING_INTENT_FAMILY_SUPPORT_RUNTIME := "support_runtime"
const AIShipNavigationHelper = preload("res://scripts/entities/ships/ai_ship_navigation_helper.gd")
const AIShipSupportHelper = preload("res://scripts/entities/ships/ai_ship_support_helper.gd")
const PlayerShipScript = preload("res://scripts/entities/ships/player_ship.gd")
const RAMMING_BOOST_ANGLE_SHIP_TYPES := [
	"kobayabune_melee",
	"sekibune_melee",
	"sekibune_cannon",
	"atakebune_mid",
	"atakebune_final",
]
const RAMMING_BOOST_ASSIST_ANGLE_DEGREES := [
	-90.0,
	-75.0,
	-60.0,
	-55.0,
	-45.0,
	-30.0,
	-15.0,
	0.0,
	15.0,
	30.0,
	45.0,
	55.0,
	60.0,
	75.0,
	90.0,
]


class MockTargetingShip:
	extends Node3D

	var team: String = "enemy"
	var is_sinking: bool = false
	var is_dying: bool = false
	var is_dead: bool = false
	var is_player_controlled: bool = false

	func get_team_tag() -> String:
		return team

	func is_player_controlled_ship() -> bool:
		return is_player_controlled

	func is_combat_disabled() -> bool:
		return is_sinking or is_dying or is_dead


class MockAuthoringSupportShip:
	extends Node3D

	var team: String = "player"
	var target: Node3D = null
	var collision_distance: float = 8.0

	func _init() -> void:
		set_meta("support_fleet_ship", true)

	func get_team_tag() -> String:
		return team

	func get_collision_distance_to(_other: Node3D) -> float:
		return collision_distance


class MockAuthoringSupportTarget:
	extends Node3D

	var team: String = "enemy"
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var deck_hostile_boarder_count: int = 0
	var is_sinking: bool = false
	var is_dying: bool = false
	var is_dead: bool = false

	func get_team_tag() -> String:
		return team


class MockRammingAssistShip:
	extends Node3D

	var team: String = "enemy"
	var current_speed: float = 0.0
	var min_ramming_speed: float = 6.0
	var boost_active: bool = false
	var is_sinking: bool = false
	var is_dying: bool = false
	var is_dead: bool = false
	var received_ramming_count: int = 0
	var last_attacker: Node3D = null
	var last_impact_speed: float = 0.0
	var boost_hit_registered: bool = false
	var ramming_damage_multiplier: float = 1.0
	var ramming_knockback_multiplier: float = 1.0

	func get_team_tag() -> String:
		return team

	func is_sinking_or_dying() -> bool:
		return is_sinking or is_dying

	func is_ramming_boost_active() -> bool:
		return boost_active

	func apply_ramming_damage(attacker: Node3D, impact_speed: float) -> void:
		received_ramming_count += 1
		last_attacker = attacker
		last_impact_speed = impact_speed
		if is_instance_valid(attacker) and attacker.has_method("notify_ramming_boost_hit"):
			attacker.call("notify_ramming_boost_hit")

	func notify_ramming_boost_hit() -> void:
		boost_hit_registered = true

	func get_ramming_damage_multiplier_value() -> float:
		return ramming_damage_multiplier * (2.0 if boost_active else 1.0)


class MockRammingDamageVictim:
	extends Node3D

	var team: String = "enemy"
	var hull_hp: float = 8.0
	var hull_defense: float = 0.0
	var min_ramming_speed: float = 6.0
	var is_sinking: bool = false
	var is_dying: bool = false
	var _recent_ram_targets: Dictionary = {}
	var _cached_audio_manager: Node = null
	var water_splash_scene: PackedScene = null
	var wood_splinter_scene: PackedScene = null
	var DEBUG_COMBAT_LOGS: bool = false
	var received_damage: float = 0.0
	var ramming_aoe_count: int = 0
	var impulse_count: int = 0

	func get_team_tag() -> String:
		return team

	func apply_ramming_aoe(_amount: float, _impact_pos: Vector3) -> void:
		ramming_aoe_count += 1

	func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO, _damage_source: String = "") -> void:
		received_damage = amount
		hull_hp -= maxf(amount - hull_defense, 1.0)
		if hull_hp <= 0.0:
			is_dying = true

	func apply_collision_impulse(_impulse_velocity: Vector3) -> void:
		impulse_count += 1


static func run_runtime_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, smoke_spawn_boss: bool, smoke_spawn_final_boss: bool, smoke_spawn_ship_types: Array[String], smoke_spawn_launcher_scenes: Array[String], smoke_spawn_projectile_scenes: Array[String]) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("smoke scene load failed: %s" % smoke_scene_path)
		return
	_run_ship_targeting_contract(owner, failures)
	_run_ramming_boost_assist_contract(owner, failures)
	_run_ramming_boost_refund_contract(failures)
	_run_ramming_boost_lethal_feedback_contract(owner, failures)
	await _run_authoring_spawn_runtime_contract(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn)
	await _run_ramming_boost_spawned_angle_contract(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn)

	if not smoke_spawn_boss and not smoke_spawn_final_boss and smoke_spawn_ship_types.is_empty() and smoke_spawn_launcher_scenes.is_empty() and smoke_spawn_projectile_scenes.is_empty():
		failures.append("no smoke mode enabled")
		return

	if smoke_spawn_boss:
		await _run_single_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, "debug_spawn_mid_boss", "mid boss")
	if smoke_spawn_final_boss:
		await _run_single_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, "debug_spawn_final_boss", "final boss")
	for ship_type_name in smoke_spawn_ship_types:
		await _run_ship_variant_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, str(ship_type_name))
	await _run_derelict_contact_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn)
	for launcher_scene_path in smoke_spawn_launcher_scenes:
		await _run_launcher_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, str(launcher_scene_path))
	for projectile_scene_path in smoke_spawn_projectile_scenes:
		await _run_projectile_smoke_pass(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn, str(projectile_scene_path))
	if smoke_spawn_projectile_scenes.has("res://scenes/projectiles/fire_pot.tscn"):
		await _run_fire_pot_residual_smoke_contract(owner, failures, packed, smoke_scene_path, wait_frames_after_attach, wait_frames_after_spawn)
	if smoke_spawn_projectile_scenes.has("res://scenes/projectiles/janggun_missile.tscn"):
		await _run_janggun_missile_expiry_contract(owner, failures)
	_run_projectile_aim_height_contract(failures)


static func _run_ship_targeting_contract(owner: Node, failures: Array[String]) -> void:
	var root := Node3D.new()
	owner.add_child(root)

	var enemy := MockTargetingShip.new()
	root.add_child(enemy)
	enemy.team = "enemy"
	enemy.global_position = Vector3.ZERO

	var player_ship := MockTargetingShip.new()
	root.add_child(player_ship)
	player_ship.team = "player"
	player_ship.is_player_controlled = true
	player_ship.global_position = Vector3(10.0, 0.0, 0.0)

	var support_ship := MockTargetingShip.new()
	root.add_child(support_ship)
	support_ship.team = "player"
	support_ship.global_position = Vector3(9.2, 0.0, 0.0)

	EntityRegistry.register_ship(enemy)
	EntityRegistry.register_ship(player_ship)
	EntityRegistry.register_ship(support_ship)

	var enemy_target := ShipTargetingHelper.select_player_target_for(enemy)
	if enemy_target != player_ship:
		failures.append("ship targeting contract did not apply player-controlled target weight")

	var support_target := ShipTargetingHelper.select_player_target_for(support_ship)
	if support_target != player_ship:
		failures.append("ship targeting contract support ship did not follow player-controlled flagship")

	player_ship.is_sinking = true
	var retargeted_enemy_target := ShipTargetingHelper.select_player_target_for(enemy)
	if retargeted_enemy_target != support_ship:
		failures.append("ship targeting contract did not ignore disabled player-controlled ship")

	EntityRegistry.unregister_ship(enemy)
	EntityRegistry.unregister_ship(player_ship)
	EntityRegistry.unregister_ship(support_ship)
	root.queue_free()


static func _run_ramming_boost_assist_contract(owner: Node, failures: Array[String]) -> void:
	var root := Node3D.new()
	owner.add_child(root)

	var player := MockRammingAssistShip.new()
	root.add_child(player)
	player.team = "player"
	player.boost_active = true
	player.current_speed = 4.25
	player.min_ramming_speed = 6.0
	player.global_position = Vector3.ZERO
	PlayerFleetRoleHelper.mark_player_flagship(player)

	var enemy := MockRammingAssistShip.new()
	root.add_child(enemy)
	enemy.team = "enemy"
	enemy.global_position = Vector3(0.0, 0.0, -6.7)

	var assisted_hit := BaseShipCollisionHelper._try_assisted_ramming_boost_contact(player, enemy, 6.7, 6.0)
	if not assisted_hit:
		failures.append("ramming boost assist contract did not trigger just outside collision distance")
	if enemy.received_ramming_count != 1:
		failures.append("ramming boost assist contract did not apply ramming damage")
	if enemy.last_attacker != player:
		failures.append("ramming boost assist contract did not pass the player as attacker")
	if enemy.last_impact_speed < player.min_ramming_speed:
		failures.append("ramming boost assist contract impact speed below minimum")
	if not player.boost_hit_registered:
		failures.append("ramming boost assist contract did not register the boost hit")

	enemy.received_ramming_count = 0
	player.boost_hit_registered = false
	enemy.global_position = Vector3(6.7, 0.0, 0.0)
	var side_hit := BaseShipCollisionHelper._try_assisted_ramming_boost_contact(player, enemy, 6.7, 6.0)
	if side_hit or enemy.received_ramming_count != 0:
		failures.append("ramming boost assist contract allowed a side scrape to spend a boost hit")

	enemy.global_position = Vector3(0.0, 0.0, -6.7)
	player.current_speed = 3.5
	var slow_hit := BaseShipCollisionHelper._try_assisted_ramming_boost_contact(player, enemy, 6.7, 6.0)
	if slow_hit or enemy.received_ramming_count != 0:
		failures.append("ramming boost assist contract allowed a low-speed contact")

	root.queue_free()


static func _run_ramming_boost_refund_contract(failures: Array[String]) -> void:
	var player := PlayerShipScript.new()
	player.sail_furled = true
	player.sail_deployed_ratio = 0.0
	player.current_speed = 0.0
	player.max_speed = 9.0
	player.min_ramming_speed = 6.0
	player.ramming_boost_duration = 0.2
	player.ramming_boost_recharge_duration = 18.0
	player.ramming_boost_charge = 1.0

	if not player.try_activate_ramming_boost():
		failures.append("ramming boost refund contract could not activate boost with folded sail")
	else:
		player._update_ramming_boost(0.25)
		if player.ramming_boost_active:
			failures.append("ramming boost refund contract did not end the boost")
		if player.ramming_boost_charge < 0.34:
			failures.append("ramming boost refund contract did not refund a missed boost")

	player.ramming_boost_charge = 1.0
	if player.try_activate_ramming_boost():
		player.notify_ramming_boost_hit()
		player._update_ramming_boost(0.25)
		if player.ramming_boost_charge >= 0.34:
			failures.append("ramming boost refund contract refunded a confirmed hit")
	else:
		failures.append("ramming boost refund contract could not reactivate boost after reset")

	player.free()


static func _run_ramming_boost_lethal_feedback_contract(owner: Node, failures: Array[String]) -> void:
	var root := Node3D.new()
	owner.add_child(root)

	var attacker := MockRammingAssistShip.new()
	root.add_child(attacker)
	attacker.team = "player"
	attacker.boost_active = true
	attacker.current_speed = 9.0
	attacker.min_ramming_speed = 6.0
	attacker.global_position = Vector3(0.0, 0.0, 0.0)
	PlayerFleetRoleHelper.mark_player_flagship(attacker)

	var victim := MockRammingDamageVictim.new()
	root.add_child(victim)
	victim.team = "enemy"
	victim.hull_hp = 6.0
	victim.global_position = Vector3(0.0, 0.0, -5.5)

	var speed_before := attacker.current_speed
	BaseShipCollisionHelper.apply_ramming_damage(victim, attacker, 8.5)

	if victim.received_damage <= 0.0 or not victim.is_dying:
		failures.append("ramming boost lethal feedback contract did not apply lethal damage")
	if victim.ramming_aoe_count != 1:
		failures.append("ramming boost lethal feedback contract did not apply impact aoe before sinking")
	if not attacker.boost_hit_registered:
		failures.append("ramming boost lethal feedback contract did not register boost hit")
	if attacker.current_speed >= speed_before * 0.72:
		failures.append("ramming boost lethal feedback contract did not brake attacker speed")
	if attacker.get("collision_impulse_velocity") == null and attacker.current_speed >= speed_before * 0.55:
		failures.append("ramming boost lethal feedback contract did not leave enough impact resistance")

	root.queue_free()


static func _run_ramming_boost_spawned_angle_contract(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("ramming boost angle contract instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player := smoke_root.get_node_or_null("PlayerShip") as Node3D
	var spawner := smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(player):
		failures.append("ramming boost angle contract missing PlayerShip")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	if not is_instance_valid(spawner) or not spawner.has_method("debug_spawn_ship"):
		failures.append("ramming boost angle contract missing EnemySpawner.debug_spawn_ship")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var player_forward: Vector3 = -player.global_transform.basis.z
	player_forward.y = 0.0
	player_forward = player_forward.normalized() if player_forward.length_squared() > 0.0001 else Vector3.FORWARD
	var player_right := player_forward.cross(Vector3.UP)
	player_right.y = 0.0
	player_right = player_right.normalized() if player_right.length_squared() > 0.0001 else Vector3.RIGHT
	var player_min_speed: float = maxf(float(player.get("min_ramming_speed")) if player.get("min_ramming_speed") != null else 6.0, 0.1)

	var mock_target := MockRammingAssistShip.new()
	smoke_root.add_child(mock_target)
	mock_target.team = "enemy"

	for ship_type_variant in RAMMING_BOOST_ANGLE_SHIP_TYPES:
		var ship_type := str(ship_type_variant)
		var hull_probe := spawner.call("debug_spawn_ship", ship_type, 28.0, 0.0) as Node3D
		if not is_instance_valid(hull_probe):
			failures.append("ramming boost angle contract could not spawn %s" % ship_type)
			continue
		await _wait_frames(owner, wait_frames_after_spawn)

		for angle_variant in RAMMING_BOOST_ASSIST_ANGLE_DEGREES:
			var angle_degrees := float(angle_variant)
			var angle_radians := deg_to_rad(angle_degrees)
			var approach_dir := (player_forward * cos(angle_radians) + player_right * sin(angle_radians))
			approach_dir.y = 0.0
			approach_dir = approach_dir.normalized() if approach_dir.length_squared() > 0.0001 else player_forward

			hull_probe.global_position = player.global_position + approach_dir * 12.0
			hull_probe.look_at(player.global_position, Vector3.UP)
			await _wait_frames(owner, 1)

			var collision_distance: float = float(player.call("get_collision_distance_to", hull_probe)) if player.has_method("get_collision_distance_to") else 6.0
			var test_distance := collision_distance + BaseShipCollisionHelper.RAMMING_BOOST_ASSIST_PAD * 0.75
			mock_target.global_position = player.global_position + approach_dir * test_distance
			mock_target.rotation = hull_probe.rotation
			mock_target.received_ramming_count = 0
			mock_target.last_attacker = null
			mock_target.last_impact_speed = 0.0
			mock_target.boost_hit_registered = false

			player.set("ramming_boost_active", true)
			player.set("ramming_boost_timer", 1.0)
			player.set("ramming_boost_hit_registered", false)
			player.set("current_speed", player_min_speed * 0.78)

			var did_hit := BaseShipCollisionHelper._try_assisted_ramming_boost_contact(player, mock_target, test_distance, collision_distance)
			var expected_hit := absf(angle_degrees) <= 55.0
			var registered_hit := bool(player.get("ramming_boost_hit_registered"))
			if expected_hit:
				if not did_hit or mock_target.received_ramming_count != 1 or not registered_hit:
					failures.append("ramming boost angle contract missed %s at %.0f degrees" % [ship_type, angle_degrees])
				elif mock_target.last_impact_speed < player_min_speed:
					failures.append("ramming boost angle contract low impact speed for %s at %.0f degrees" % [ship_type, angle_degrees])
			else:
				if did_hit or mock_target.received_ramming_count != 0 or registered_hit:
					failures.append("ramming boost angle contract over-accepted %s at %.0f degrees" % [ship_type, angle_degrees])

		hull_probe.queue_free()
		await _wait_frames(owner, 1)

	mock_target.queue_free()
	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_authoring_spawn_runtime_contract(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("authoring spawn runtime contract instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		failures.append("authoring spawn runtime contract missing EnemySpawner")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var palette := _load_authoring_palette(failures)
	if palette.is_empty():
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	var matrix_cases := _build_authoring_runtime_matrix_cases(failures, palette)
	if matrix_cases.is_empty():
		failures.append("authoring spawn runtime contract did not derive palette matrix cases")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	_validate_authoring_intent_family_coverage(failures, palette, matrix_cases)
	_validate_authoring_block_runtime_harness_coverage(spawner, failures, palette, matrix_cases)
	_run_authoring_support_intent_family_contract(failures, palette)
	await _run_authoring_direct_spawn_matrix(owner, spawner, failures, matrix_cases, wait_frames_after_spawn)
	await _run_authoring_scenario_spawn_ship_matrix(owner, smoke_root, spawner, failures, matrix_cases, wait_frames_after_spawn)
	var recipe_case := _find_authoring_runtime_case(matrix_cases, "boarding_side_follow", matrix_cases[0])
	var scenario_recipe_case := _find_authoring_runtime_case(matrix_cases, "gunner_standoff", matrix_cases[0])
	await _run_authoring_debug_recipe_matrix(owner, smoke_root, spawner, failures, recipe_case, wait_frames_after_spawn)
	await _run_authoring_scenario_recipe_matrix(owner, smoke_root, spawner, failures, scenario_recipe_case, wait_frames_after_spawn)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _build_authoring_runtime_matrix_cases(failures: Array[String], palette: Dictionary) -> Array[Dictionary]:
	var all_stats := ShipBlueprintHelper.load_all_stats()
	var combat_profiles := ShipBlueprintHelper.get_combat_profiles(all_stats)
	var combat_entries := _collect_palette_entries_by_id(palette.get("combat_profiles", []))
	var ship_entries := _collect_palette_entries_by_id(palette.get("ship_types", []))
	var movement_entries := _collect_palette_entries(palette.get("movement_intents", []))
	var cases: Array[Dictionary] = []
	for index in range(movement_entries.size()):
		var movement_entry: Dictionary = movement_entries[index]
		var movement_id := str(movement_entry.get("id", "")).strip_edges()
		var movement_mode := str(movement_entry.get("mode", movement_id)).strip_edges()
		if movement_id.is_empty() or movement_mode.is_empty():
			failures.append("authoring runtime matrix movement entry missing id or mode")
			continue
		if _authoring_movement_intent_family(movement_entry) != AUTHORING_INTENT_FAMILY_ENEMY_RUNTIME:
			continue
		var combat_profile := _pick_authoring_combat_profile_for_movement(movement_entry, combat_entries, combat_profiles)
		var ship_type := _pick_authoring_ship_type_for_movement(movement_entry, ship_entries)
		if combat_profile.is_empty():
			failures.append("authoring runtime matrix could not pick combat profile for %s" % movement_id)
			continue
		if ship_type.is_empty():
			failures.append("authoring runtime matrix could not pick ship type for %s" % movement_id)
			continue
		var profile_variant: Variant = combat_profiles.get(combat_profile, {})
		if typeof(profile_variant) != TYPE_DICTIONARY:
			failures.append("authoring runtime matrix missing combat profile stats: %s" % combat_profile)
			continue
		var profile: Dictionary = profile_variant as Dictionary
		var role_name := ShipCombatModeHelper.normalize_role_name(str(profile.get("combat_role", ShipCombatModeHelper.ROLE_CHARGER)))
		cases.append(_build_authoring_spawn_case(
			"palette matrix %s %s %s" % [ship_type, combat_profile, movement_id],
			ship_type,
			combat_profile,
			movement_id,
			movement_mode,
			role_name == ShipCombatModeHelper.ROLE_GUNNER,
			profile.get("allow_boarding", false) == true,
			float(profile.get("preferred_range", 14.0)),
			float(profile.get("range_tolerance", 2.5)),
			float(profile.get("retreat_distance", 8.0)),
			float(movement_entry.get("speed_min", 1.0)),
			float(movement_entry.get("speed_max", movement_entry.get("speed_min", 1.0))),
			movement_entry.get("sprint", false) == true,
			_authoring_movement_intent_family(movement_entry),
			24.0 + float(index % 3) * 2.0,
			-10.0 + float(index) * 4.0
		))
	return cases


static func _validate_authoring_block_runtime_harness_coverage(spawner: Node, failures: Array[String], palette: Dictionary, matrix_cases: Array[Dictionary]) -> void:
	var action_types: Dictionary = {}
	var meta_keys: Dictionary = {}
	for block in _collect_palette_entries(palette.get("assembly_blocks", [])):
		var kind := str(block.get("kind", "")).strip_edges()
		if kind == "action":
			var action_type := str(block.get("action_type", "")).strip_edges()
			if not action_type.is_empty():
				action_types[action_type] = true
		elif kind == "authoring_meta":
			var authoring_key := str(block.get("authoring_key", "")).strip_edges()
			if not authoring_key.is_empty():
				meta_keys[authoring_key] = true
	if action_types.has("spawn_ship") and matrix_cases.is_empty():
		failures.append("authoring block harness missing spawn_ship matrix coverage")
	if action_types.has("spawn_recipe") and matrix_cases.is_empty():
		failures.append("authoring block harness missing spawn_recipe matrix coverage")
	if action_types.has("set_encounter_profile"):
		_validate_authoring_set_encounter_profile_action_block(spawner, failures, palette)
	if action_types.has("run_scenario_trigger"):
		_validate_authoring_run_scenario_trigger_action_block(spawner, failures, palette)
	for action_type_variant in action_types.keys():
		var action_type := str(action_type_variant)
		if not ["spawn_ship", "spawn_recipe", "set_encounter_profile", "run_scenario_trigger"].has(action_type):
			failures.append("authoring block harness has no runtime action coverage for %s" % action_type)
	if meta_keys.has("movement_intent") and matrix_cases.is_empty():
		failures.append("authoring block harness missing movement_intent matrix coverage")
	if meta_keys.has("combat_profile") and matrix_cases.is_empty():
		failures.append("authoring block harness missing combat_profile matrix coverage")


static func _validate_authoring_set_encounter_profile_action_block(spawner: Node, failures: Array[String], palette: Dictionary) -> void:
	if not is_instance_valid(spawner) or not spawner.has_method("debug_set_encounter_profile"):
		failures.append("authoring block harness missing debug_set_encounter_profile")
		return
	var profile_id := _first_palette_entry_id(palette.get("encounter_profiles", []))
	if profile_id.is_empty():
		failures.append("authoring block harness missing encounter profile palette entry")
		return
	var applied: bool = bool(spawner.call("debug_set_encounter_profile", profile_id))
	if not applied:
		failures.append("authoring block harness set_encounter_profile failed: %s" % profile_id)
	if "active_encounter_profile" in spawner and str(spawner.get("active_encounter_profile")) != profile_id:
		failures.append("authoring block harness active encounter profile mismatch: %s" % str(spawner.get("active_encounter_profile")))


static func _validate_authoring_run_scenario_trigger_action_block(spawner: Node, failures: Array[String], palette: Dictionary) -> void:
	if not is_instance_valid(spawner) or not spawner.has_method("debug_run_scenario_trigger"):
		failures.append("authoring block harness missing debug_run_scenario_trigger")
		return
	var profile_id := _first_palette_entry_id(palette.get("encounter_profiles", []))
	if profile_id.is_empty():
		failures.append("authoring block harness missing encounter profile for trigger action")
		return
	var trigger_id := "authoring_runtime_action_block_trigger"
	spawner.scenario_triggers = EnemySpawnerFleetHelper.parse_scenario_triggers([
		{
			"id": trigger_id,
			"condition": {"elapsed_time": 0.0},
			"actions": [
				{"type": "set_encounter_profile", "profile": profile_id},
			],
		},
	])
	var applied: bool = bool(spawner.call("debug_run_scenario_trigger", trigger_id))
	if not applied:
		failures.append("authoring block harness run_scenario_trigger failed: %s" % trigger_id)
	if "active_encounter_profile" in spawner and str(spawner.get("active_encounter_profile")) != profile_id:
		failures.append("authoring block harness trigger profile mismatch: %s" % str(spawner.get("active_encounter_profile")))


static func _validate_authoring_intent_family_coverage(failures: Array[String], palette: Dictionary, matrix_cases: Array[Dictionary]) -> void:
	var movement_entries := _collect_palette_entries(palette.get("movement_intents", []))
	var matrix_intents: Dictionary = {}
	for case_data in matrix_cases:
		matrix_intents[str(case_data.get("movement_intent", ""))] = true
	var enemy_family_count := 0
	var support_family_count := 0
	for movement_entry in movement_entries:
		var movement_id := str(movement_entry.get("id", "")).strip_edges()
		var family := _authoring_movement_intent_family(movement_entry)
		if family == AUTHORING_INTENT_FAMILY_ENEMY_RUNTIME:
			enemy_family_count += 1
			if not matrix_intents.has(movement_id):
				failures.append("authoring runtime matrix missing enemy intent: %s" % movement_id)
		elif family == AUTHORING_INTENT_FAMILY_SUPPORT_RUNTIME:
			support_family_count += 1
			if matrix_intents.has(movement_id):
				failures.append("authoring runtime matrix should not enemy-spawn support intent: %s" % movement_id)
		else:
			failures.append("authoring runtime matrix unknown intent family for %s: %s" % [movement_id, family])
	if enemy_family_count <= 0:
		failures.append("authoring runtime matrix should include at least one enemy movement intent")
	if support_family_count <= 0:
		failures.append("authoring runtime matrix should include at least one support movement intent family")


static func _run_authoring_support_intent_family_contract(failures: Array[String], palette: Dictionary) -> void:
	var support_entries: Array[Dictionary] = []
	for movement_entry in _collect_palette_entries(palette.get("movement_intents", [])):
		if _authoring_movement_intent_family(movement_entry) == AUTHORING_INTENT_FAMILY_SUPPORT_RUNTIME:
			support_entries.append(movement_entry)
	if support_entries.is_empty():
		failures.append("authoring support intent family contract found no support intents")
		return
	for movement_entry in support_entries:
		var movement_id := str(movement_entry.get("id", "")).strip_edges()
		match movement_id:
			"support_assist":
				_validate_support_assist_authoring_intent(failures, movement_entry)
			_:
				failures.append("authoring support intent family has no runtime harness: %s" % movement_id)


static func _validate_support_assist_authoring_intent(failures: Array[String], movement_entry: Dictionary) -> void:
	var support := MockAuthoringSupportShip.new()
	support.name = "AuthoringSupportHarnessShip"
	support.global_position = Vector3(34.0, 0.0, 0.0)

	var player := MockAuthoringSupportTarget.new()
	player.name = "AuthoringSupportHarnessPlayer"
	player.team = "player"
	player.global_position = Vector3.ZERO
	player.deck_is_overrun = true
	player.deck_is_contested = true
	player.deck_hostile_boarder_count = 2
	support.target = player

	var attacker := MockAuthoringSupportTarget.new()
	attacker.name = "AuthoringSupportHarnessAttacker"
	attacker.team = "enemy"
	attacker.global_position = Vector3(4.0, 0.0, 0.0)

	var nav: Dictionary = AIShipSupportHelper._build_support_assist_navigation(support, attacker, 0)
	var expected_mode := str(movement_entry.get("mode", "support_assist")).strip_edges()
	if ShipMovementIntent.get_mode(nav) != expected_mode:
		failures.append("authoring support_assist navigation mode mismatch: %s" % ShipMovementIntent.get_mode(nav))
	var speed_min := float(movement_entry.get("speed_min", 0.0))
	var speed_max := float(movement_entry.get("speed_max", 999.0))
	var desired_speed := ShipMovementIntent.get_desired_speed_mult(nav)
	if desired_speed < speed_min - 0.001 or desired_speed > speed_max + 0.001:
		failures.append("authoring support_assist speed mismatch: %.3f not in %.3f..%.3f" % [desired_speed, speed_min, speed_max])
	if movement_entry.get("sprint", false) == true and not ShipMovementIntent.get_permit_sprint(nav):
		failures.append("authoring support_assist emergency navigation should permit sprint")
	if ShipMovementIntent.get_target_pos(nav) != attacker.global_position:
		failures.append("authoring support_assist target position mismatch")

	attacker.free()
	player.free()
	support.free()


static func _find_authoring_runtime_case(matrix_cases: Array[Dictionary], movement_intent: String, fallback: Dictionary) -> Dictionary:
	for case_data in matrix_cases:
		if str(case_data.get("movement_intent", "")) == movement_intent:
			return case_data
	return fallback


static func _load_authoring_palette(failures: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(AUTHORING_PALETTE_DATA_PATH):
		failures.append("authoring runtime matrix missing authoring palette: %s" % AUTHORING_PALETTE_DATA_PATH)
		return {}
	var file := FileAccess.open(AUTHORING_PALETTE_DATA_PATH, FileAccess.READ)
	if file == null:
		failures.append("authoring runtime matrix could not open authoring palette")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("authoring runtime matrix authoring palette should be a Dictionary")
		return {}
	return parsed as Dictionary


static func _collect_palette_entries(entries_variant: Variant) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if typeof(entries_variant) != TYPE_ARRAY:
		return entries
	var raw_entries: Array = entries_variant as Array
	for entry_variant in raw_entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var entry_id := str(entry.get("id", "")).strip_edges()
		if entry_id.is_empty():
			continue
		entries.append(entry)
	return entries


static func _collect_palette_entries_by_id(entries_variant: Variant) -> Dictionary:
	var by_id: Dictionary = {}
	for entry in _collect_palette_entries(entries_variant):
		by_id[str(entry.get("id", "")).strip_edges()] = entry
	return by_id


static func _first_palette_entry_id(entries_variant: Variant) -> String:
	for entry in _collect_palette_entries(entries_variant):
		var entry_id := str(entry.get("id", "")).strip_edges()
		if not entry_id.is_empty():
			return entry_id
	return ""


static func _pick_authoring_combat_profile_for_movement(movement_entry: Dictionary, combat_entries: Dictionary, combat_profiles: Dictionary) -> String:
	var movement_id := str(movement_entry.get("id", "")).strip_edges()
	var movement_tags := _palette_tags(movement_entry)
	var preferred_ids: Array[String] = []
	if _tags_have_any(movement_tags, ["ranged", "spacing", "safety"]):
		preferred_ids.append("stand_off_gunner")
	elif movement_id == "boarding_side_follow":
		preferred_ids.append("raider_charger")
	else:
		preferred_ids.append("boarding_charger")
	for fallback_id in ["boarding_charger", "raider_charger", "stand_off_gunner"]:
		if not preferred_ids.has(fallback_id):
			preferred_ids.append(fallback_id)
	for profile_id in preferred_ids:
		if combat_entries.has(profile_id) and combat_profiles.has(profile_id):
			return profile_id
	var desired_tag := "ranged" if _tags_have_any(movement_tags, ["ranged", "spacing", "safety"]) else "boarding"
	return _find_palette_entry_with_tag(combat_entries, combat_profiles, desired_tag)


static func _authoring_movement_intent_family(movement_entry: Dictionary) -> String:
	var family := str(movement_entry.get("family", "")).strip_edges()
	if not family.is_empty():
		return family
	var tags := _palette_tags(movement_entry)
	if _tags_have_any(tags, ["support", "assist"]):
		return AUTHORING_INTENT_FAMILY_SUPPORT_RUNTIME
	return AUTHORING_INTENT_FAMILY_ENEMY_RUNTIME


static func _find_palette_entry_with_tag(entries_by_id: Dictionary, required_catalog: Dictionary, required_tag: String) -> String:
	for entry_id_variant in entries_by_id.keys():
		var entry_id := str(entry_id_variant)
		if not required_catalog.has(entry_id):
			continue
		var entry_variant: Variant = entries_by_id[entry_id_variant]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var tags := _palette_tags(entry)
		if _tags_have_any(tags, ["boss", "final"]):
			continue
		if tags.has(required_tag):
			return entry_id
	return ""


static func _pick_authoring_ship_type_for_movement(movement_entry: Dictionary, ship_entries: Dictionary) -> String:
	var movement_tags := _palette_tags(movement_entry)
	var candidate_tag_sets: Array = []
	if _tags_have_any(movement_tags, ["ranged", "spacing", "safety"]):
		candidate_tag_sets.append(["enemy", "ranged"])
		candidate_tag_sets.append(["enemy", "medium"])
	elif _tags_have_any(movement_tags, ["contact", "recovery"]):
		candidate_tag_sets.append(["enemy", "medium", "boarding"])
		candidate_tag_sets.append(["enemy", "boarding"])
	else:
		candidate_tag_sets.append(["enemy", "light", "boarding"])
		candidate_tag_sets.append(["enemy", "boarding"])
		candidate_tag_sets.append(["enemy", "medium", "boarding"])
	candidate_tag_sets.append(["enemy"])
	for required_tags_variant in candidate_tag_sets:
		var required_tags: Array = required_tags_variant as Array
		var ship_type := _find_ship_entry_with_tags(ship_entries, required_tags)
		if not ship_type.is_empty():
			return ship_type
	return ""


static func _find_ship_entry_with_tags(ship_entries: Dictionary, required_tags: Array) -> String:
	for entry_id_variant in ship_entries.keys():
		var entry_id := str(entry_id_variant)
		var entry_variant: Variant = ship_entries[entry_id_variant]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var tags := _palette_tags(entry)
		if _tags_have_any(tags, ["boss", "final", "player"]):
			continue
		if _tags_have_all(tags, required_tags):
			return entry_id
	return ""


static func _palette_tags(entry: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	var tags_variant: Variant = entry.get("tags", [])
	if typeof(tags_variant) != TYPE_ARRAY:
		return tags
	var raw_tags: Array = tags_variant as Array
	for tag_variant in raw_tags:
		var tag := str(tag_variant).strip_edges()
		if not tag.is_empty() and not tags.has(tag):
			tags.append(tag)
	return tags


static func _tags_have_any(tags: Array[String], candidates: Array) -> bool:
	for candidate in candidates:
		if tags.has(str(candidate)):
			return true
	return false


static func _tags_have_all(tags: Array[String], required_tags: Array) -> bool:
	for required_tag in required_tags:
		if not tags.has(str(required_tag)):
			return false
	return true


static func _run_authoring_direct_spawn_matrix(owner: Node, spawner: Node, failures: Array[String], matrix_cases: Array[Dictionary], wait_frames_after_spawn: int) -> void:
	for case_data in matrix_cases:
		var direct_spawn: Node3D = spawner.call(
			"debug_spawn_ship",
			str(case_data["ship_type"]),
			float(case_data["distance"]),
			float(case_data["lateral_offset"]),
			_build_authoring_meta_from_case(case_data)
		) as Node3D
		await _wait_frames(owner, wait_frames_after_spawn)
		_validate_authoring_spawned_ship_case(failures, direct_spawn, str(case_data["label"]), case_data)


static func _run_authoring_scenario_spawn_ship_matrix(owner: Node, smoke_root: Node, spawner: Node, failures: Array[String], matrix_cases: Array[Dictionary], wait_frames_after_spawn: int) -> void:
	for index in range(matrix_cases.size()):
		var case_data: Dictionary = matrix_cases[index]
		var before_ids := _collect_spawned_ship_ids(smoke_root)
		var trigger_id := "authoring_runtime_spawn_ship_%d" % index
		spawner.scenario_triggers = EnemySpawnerFleetHelper.parse_scenario_triggers([
			{
				"id": trigger_id,
				"condition": {"elapsed_time": 0.0},
				"actions": [
					{
						"type": "spawn_ship",
						"ship_type": str(case_data["ship_type"]),
						"distance": float(case_data["distance"]),
						"lateral_offset": float(case_data["lateral_offset"]),
						"authoring": _build_authoring_meta_from_case(case_data),
					},
				],
			},
		])
		var applied: bool = bool(spawner.call("debug_run_scenario_trigger", trigger_id))
		if not applied:
			failures.append("%s scenario spawn_ship trigger did not apply" % str(case_data["label"]))
		await _wait_frames(owner, wait_frames_after_spawn)
		var spawned := _find_new_authoring_spawned_ship(smoke_root, before_ids, case_data)
		_validate_authoring_spawned_ship_case(failures, spawned, "%s scenario spawn_ship" % str(case_data["label"]), case_data)


static func _run_authoring_debug_recipe_matrix(owner: Node, smoke_root: Node, spawner: Node, failures: Array[String], case_data: Dictionary, wait_frames_after_spawn: int) -> void:
	var before_ids := _collect_spawned_ship_ids(smoke_root)
	spawner.call("debug_spawn_recipe", "light_raiders", _build_authoring_meta_from_case(case_data))
	await _wait_frames(owner, wait_frames_after_spawn)
	var spawns := _collect_new_spawned_ships(smoke_root, before_ids)
	if spawns.is_empty():
		failures.append("%s debug recipe did not spawn authored ships" % str(case_data["label"]))
	for index in range(spawns.size()):
		_validate_authoring_spawned_ship_case(failures, spawns[index], "%s debug recipe ship %d" % [str(case_data["label"]), index], case_data)


static func _run_authoring_scenario_recipe_matrix(owner: Node, smoke_root: Node, spawner: Node, failures: Array[String], case_data: Dictionary, wait_frames_after_spawn: int) -> void:
	var before_ids := _collect_spawned_ship_ids(smoke_root)
	var trigger_id := "authoring_runtime_recipe_matrix"
	spawner.scenario_triggers = EnemySpawnerFleetHelper.parse_scenario_triggers([
		{
			"id": trigger_id,
			"condition": {"elapsed_time": 0.0},
			"actions": [
				{
					"type": "spawn_recipe",
					"recipe": "light_raiders",
					"authoring": _build_authoring_meta_from_case(case_data),
				},
			],
		},
	])
	var applied: bool = bool(spawner.call("debug_run_scenario_trigger", trigger_id))
	if not applied:
		failures.append("%s scenario recipe trigger did not apply" % str(case_data["label"]))
	await _wait_frames(owner, wait_frames_after_spawn)
	var spawns := _collect_new_spawned_ships(smoke_root, before_ids)
	if spawns.is_empty():
		failures.append("%s scenario recipe did not spawn authored ships" % str(case_data["label"]))
	for index in range(spawns.size()):
		_validate_authoring_spawned_ship_case(failures, spawns[index], "%s scenario recipe ship %d" % [str(case_data["label"]), index], case_data)


static func _build_authoring_spawn_case(label: String, ship_type: String, combat_profile: String, movement_intent: String, movement_mode: String, expect_gunner: bool, expected_can_board: bool, expected_preferred_range: float, expected_range_tolerance: float, expected_retreat_distance: float, speed_min: float, speed_max: float, sprint: bool, movement_family: String, distance: float, lateral_offset: float) -> Dictionary:
	return {
		"label": label,
		"ship_type": ship_type,
		"combat_profile": combat_profile,
		"movement_intent": movement_intent,
		"movement_mode": movement_mode,
		"movement_family": movement_family,
		"expect_gunner": expect_gunner,
		"expected_can_board": expected_can_board,
		"expected_preferred_range": expected_preferred_range,
		"expected_range_tolerance": expected_range_tolerance,
		"expected_retreat_distance": expected_retreat_distance,
		"speed_min": speed_min,
		"speed_max": speed_max,
		"sprint": sprint,
		"distance": distance,
		"lateral_offset": lateral_offset,
	}


static func _build_authoring_meta_from_case(case_data: Dictionary) -> Dictionary:
	return _build_authoring_meta(
		str(case_data["combat_profile"]),
		str(case_data["movement_intent"]),
		str(case_data["movement_mode"]),
		str(case_data["movement_family"]),
		float(case_data["speed_min"]),
		float(case_data["speed_max"]),
		case_data["sprint"] == true
	)


static func _build_authoring_meta(combat_profile: String, movement_intent: String, movement_mode: String, movement_family: String, speed_min: float, speed_max: float, sprint: bool) -> Dictionary:
	return {
		"combat_profile": combat_profile,
		"movement_intent": movement_intent,
		"movement_family": movement_family,
		"movement_mode": movement_mode,
		"movement_speed_min": speed_min,
		"movement_speed_max": speed_max,
		"movement_sprint": sprint,
	}


static func _validate_authoring_spawned_ship_case(failures: Array[String], ship: Node3D, label: String, case_data: Dictionary) -> void:
	_validate_authoring_spawned_ship(
		failures,
		ship,
		label,
		str(case_data["combat_profile"]),
		str(case_data["movement_intent"]),
		str(case_data["movement_mode"]),
		str(case_data["movement_family"]),
		case_data["expect_gunner"] == true,
		float(case_data["speed_min"]),
		float(case_data["speed_max"]),
		case_data["sprint"] == true,
		case_data["expected_can_board"] == true,
		float(case_data["expected_preferred_range"]),
		float(case_data["expected_range_tolerance"]),
		float(case_data["expected_retreat_distance"])
	)


static func _find_authoring_spawned_ships(root: Node, combat_profile: String, movement_intent: String) -> Array[Node3D]:
	var ships: Array[Node3D] = []
	for child in root.get_children():
		var ship := child as Node3D
		if not is_instance_valid(ship):
			continue
		if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_COMBAT_PROFILE, "")) != combat_profile:
			continue
		if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_INTENT, "")) != movement_intent:
			continue
		ships.append(ship)
	return ships


static func _find_new_authoring_spawned_ship(root: Node, before_ids: Dictionary, case_data: Dictionary) -> Node3D:
	for ship in _collect_new_spawned_ships(root, before_ids):
		if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_COMBAT_PROFILE, "")) != str(case_data["combat_profile"]):
			continue
		if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_INTENT, "")) != str(case_data["movement_intent"]):
			continue
		return ship
	return null


static func _collect_new_spawned_ships(root: Node, before_ids: Dictionary) -> Array[Node3D]:
	var spawns: Array[Node3D] = []
	if not is_instance_valid(root):
		return spawns
	for child in root.get_children():
		var ship := child as Node3D
		if not is_instance_valid(ship):
			continue
		if not ship.is_in_group("enemy"):
			continue
		if before_ids.has(ship.get_instance_id()):
			continue
		spawns.append(ship)
	return spawns


static func _collect_spawned_ship_ids(root: Node) -> Dictionary:
	var ids: Dictionary = {}
	if not is_instance_valid(root):
		return ids
	for child in root.get_children():
		var ship := child as Node3D
		if is_instance_valid(ship) and ship.is_in_group("enemy"):
			ids[ship.get_instance_id()] = true
	return ids


static func _validate_authoring_spawned_ship(failures: Array[String], ship: Node3D, label: String, expected_combat_profile: String, expected_movement_intent: String, expected_movement_mode: String, expected_movement_family: String, expect_gunner: bool, expected_speed_min: float, expected_speed_max: float, expected_sprint: bool, expected_can_board: bool = false, expected_preferred_range: float = -1.0, expected_range_tolerance: float = -1.0, expected_retreat_distance: float = -1.0) -> void:
	if not is_instance_valid(ship):
		failures.append("%s returned null" % label)
		return
	if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_COMBAT_PROFILE, "")) != expected_combat_profile:
		failures.append("%s combat_profile meta mismatch" % label)
	if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_INTENT, "")) != expected_movement_intent:
		failures.append("%s movement_intent meta mismatch" % label)
	if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_FAMILY, "")) != expected_movement_family:
		failures.append("%s movement_family meta mismatch" % label)
	if str(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_MODE, "")) != expected_movement_mode:
		failures.append("%s movement_mode meta mismatch" % label)
	if absf(float(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_SPEED_MIN, 0.0)) - expected_speed_min) > 0.001:
		failures.append("%s movement speed min meta mismatch" % label)
	if absf(float(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_SPEED_MAX, 0.0)) - expected_speed_max) > 0.001:
		failures.append("%s movement speed max meta mismatch" % label)
	if bool(ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_MOVEMENT_SPRINT, false)) != expected_sprint:
		failures.append("%s movement sprint meta mismatch" % label)
	if ship.get_meta(EnemySpawnerFleetHelper.META_AUTHORING_RUNTIME_APPLIED, false) != true:
		failures.append("%s runtime authoring override marker missing" % label)
	if ShipCombatModeHelper.is_gunner(ship) != expect_gunner:
		failures.append("%s combat role override mismatch" % label)
	if ShipCombatModeHelper.can_board(ship) != expected_can_board:
		failures.append("%s boarding flag override mismatch" % label)
	if expected_preferred_range >= 0.0 and absf(ShipCombatModeHelper.preferred_range(ship) - expected_preferred_range) > 0.05:
		failures.append("%s preferred range override mismatch" % label)
	if expected_range_tolerance >= 0.0 and absf(ShipCombatModeHelper.range_tolerance(ship) - expected_range_tolerance) > 0.05:
		failures.append("%s range tolerance override mismatch" % label)
	if expected_retreat_distance >= 0.0 and absf(ShipCombatModeHelper.retreat_distance(ship) - expected_retreat_distance) > 0.05:
		failures.append("%s retreat distance override mismatch" % label)
	if is_instance_valid(ship.get("target")):
		var nav: Dictionary = AIShipNavigationHelper.build_navigation(ship, ship.get("target"))
		if ShipMovementIntent.get_mode(nav) != expected_movement_mode:
			failures.append("%s navigation movement mode mismatch: %s" % [label, ShipMovementIntent.get_mode(nav)])
		var desired_speed := ShipMovementIntent.get_desired_speed_mult(nav)
		if desired_speed < expected_speed_min - 0.001 or desired_speed > expected_speed_max + 0.001:
			failures.append("%s navigation speed range mismatch: %.3f not in %.3f..%.3f" % [label, desired_speed, expected_speed_min, expected_speed_max])
		if not expected_sprint and ShipMovementIntent.get_permit_sprint(nav):
			failures.append("%s navigation sprint should be blocked by movement intent" % label)


static func _run_single_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, spawn_method: String, label: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var level_manager: Node = LevelManagerRegistry.get_level_manager(owner.get_tree())
	if not is_instance_valid(level_manager):
		failures.append("level manager registry lookup failed during %s smoke" % label)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for %s smoke" % label)

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	var spawned_boss: Node3D = null
	if not is_instance_valid(spawner):
		failures.append("preview base is missing EnemySpawner for %s smoke" % label)
	else:
		if spawner.has_method(spawn_method):
			spawned_boss = spawner.call(spawn_method) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		_validate_spawned_boss(failures, spawned_boss, label)
		if is_instance_valid(spawned_boss):
			spawned_boss.set("current_speed", 0.0)
			spawned_boss.set("rudder_angle", 0.0)
			spawned_boss.rotation.y += PI * 0.5
			var boss_motion_start: Vector3 = spawned_boss.global_position
			await _wait_frames(owner, 12)
			if not is_instance_valid(spawned_boss):
				failures.append("%s rudder motion contract boss disappeared during steering check" % label)
			else:
				var boss_current_speed: float = float(spawned_boss.get("current_speed"))
				if boss_current_speed <= 0.08:
					failures.append("%s rudder motion contract never built forward speed: %.3f" % [label, boss_current_speed])
				var boss_rudder_angle: float = absf(float(spawned_boss.get("rudder_angle")))
				if boss_rudder_angle <= 0.2:
					failures.append("%s rudder motion contract never engaged rudder: %.3f" % [label, boss_rudder_angle])
				var boss_displacement: Vector3 = spawned_boss.global_position - boss_motion_start
				boss_displacement.y = 0.0
				if boss_displacement.length() <= 0.015:
					failures.append("%s rudder motion contract barely moved: %.3f" % [label, boss_displacement.length()])

	_validate_registry_smoke(failures, player_ship, label)
	if label == "final boss":
		await _validate_final_boss_victory_on_death(owner, failures, spawned_boss, level_manager, label)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_ship_variant_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, ship_type_name: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for %s smoke" % ship_type_name)

	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(spawner):
		failures.append("preview base is missing EnemySpawner for %s smoke" % ship_type_name)
	else:
		var spawned_ship: Node3D = null
		if spawner.has_method("debug_spawn_ship"):
			spawned_ship = spawner.call("debug_spawn_ship", ship_type_name) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		_validate_spawned_ship(failures, spawned_ship, ship_type_name)

	_validate_registry_smoke(failures, player_ship, ship_type_name)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_derelict_contact_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
	if not is_instance_valid(player_ship) or not is_instance_valid(spawner):
		failures.append("derelict contact smoke missing player ship or spawner")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var derelict_ship: Node3D = null
	if spawner.has_method("debug_spawn_ship"):
		derelict_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 5.0, 0.0) as Node3D
	await _wait_frames(owner, wait_frames_after_spawn)
	if not is_instance_valid(derelict_ship):
		failures.append("derelict contact smoke failed to spawn derelict target")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return
	if not derelict_ship.has_method("_become_derelict"):
		failures.append("derelict contact smoke target is missing _become_derelict()")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	derelict_ship.call("_become_derelict")
	await _wait_frames(owner, 1)
	derelict_ship.set_meta("derelict_nonblocking", true)
	derelict_ship.set("hull_hp", 50.0)
	var approach_dir := Vector3(0.0, 0.0, -1.0)
	var player_contact_radius: float = float(player_ship.call("get_directional_collision_radius", approach_dir)) if player_ship.has_method("get_directional_collision_radius") else 4.5
	var derelict_contact_radius: float = float(derelict_ship.call("get_directional_collision_radius", -approach_dir)) if derelict_ship.has_method("get_directional_collision_radius") else 2.5
	derelict_ship.global_position = player_ship.global_position + approach_dir * (player_contact_radius + derelict_contact_radius + 2.0)
	var player_max_hull: float = float(player_ship.get("max_hull_hp"))
	var player_hull_before: float = maxf(1.0, player_max_hull - 20.0)
	player_ship.set("hull_hp", player_hull_before)
	if player_ship.has_method("_calculate_collision_repulsion"):
		player_ship.call("_calculate_collision_repulsion")
	await _wait_frames(owner, wait_frames_after_spawn)

	if derelict_ship.get_meta("derelict_contact_salvaged", false) != true:
		failures.append("derelict contact smoke did not mark salvage on contact")
	if derelict_ship.get_meta("derelict_contact_disposal_started", false) != true:
		failures.append("derelict approach smoke did not mark disposal as started")
	if derelict_ship.get_meta("derelict_contact_ignition_started", false) != true:
		failures.append("derelict approach smoke did not start fire-pot disposal before direct contact")
	if derelict_ship.get_meta("derelict_nonblocking", false) != true:
		failures.append("derelict contact smoke did not unlock nonblocking on contact")
	if absf(float(player_ship.get("hull_hp")) - player_hull_before) > 0.01:
		failures.append("derelict contact smoke should not grant immediate hull repair")
	await _wait_frames(owner, 55)
	if is_instance_valid(derelict_ship):
		if derelict_ship.get("is_burning") != true:
			failures.append("derelict contact smoke did not ignite derelict ship")
		if derelict_ship.get("is_sinking") == true:
			failures.append("derelict contact smoke sank immediately instead of burning first")
	await _wait_frames(owner, 360)
	if is_instance_valid(derelict_ship):
		if not derelict_ship.get("is_sinking"):
			failures.append("derelict contact smoke did not start normal sinking after burning hull to zero")
		if derelict_ship.get_meta("floating_loot_dropped", false) != true:
			failures.append("derelict contact smoke should use floating loot reward after sinking")

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_launcher_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, launcher_scene_path: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for launcher smoke: %s" % launcher_scene_path)
	else:
		var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
		var target_ship: Node3D = null
		if is_instance_valid(spawner) and spawner.has_method("debug_spawn_ship"):
			target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 18.0, 0.0) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		if not is_instance_valid(target_ship):
			failures.append("launcher smoke target spawn failed: %s" % launcher_scene_path)
		else:
			var launcher_scene := load(launcher_scene_path) as PackedScene
			if launcher_scene == null:
				failures.append("launcher scene load failed: %s" % launcher_scene_path)
			else:
				var launcher := launcher_scene.instantiate()
				if launcher == null:
					failures.append("launcher scene instantiate failed: %s" % launcher_scene_path)
				else:
					if launcher.has_method("set_team"):
						launcher.set_team("player")
					elif launcher.get("team") != null:
						launcher.set("team", "player")
					player_ship.add_child(launcher)
					launcher.set_process(false)
					launcher.set_physics_process(false)
					await _wait_frames(owner, wait_frames_after_attach)
					var launcher_team_variant: Variant = launcher.get("team")
					var launcher_team: String = "player" if launcher_team_variant == null else str(launcher_team_variant)
					if launcher_team != "player":
						failures.append("launcher team contract failed: %s" % launcher_scene_path)

					var before_projectiles := EntityRegistry.count_projectiles()
					if launcher.has_method("fire"):
						if launcher_scene_path.contains("singigeon"):
							launcher.call("fire", target_ship, 0.0)
						else:
							launcher.call("fire", target_ship)
						await _wait_frames(owner, wait_frames_after_spawn)
						var after_projectiles := EntityRegistry.count_projectiles()
						if after_projectiles <= before_projectiles:
							failures.append("launcher did not spawn projectile: %s" % launcher_scene_path)
					else:
						failures.append("launcher is missing fire() method: %s" % launcher_scene_path)

					if launcher.has_method("_is_target_valid"):
						var stale_target: Node3D = target_ship
						stale_target.queue_free()
						await _wait_frames(owner, 2)
						var stale_valid: bool = bool(launcher.call("_is_target_valid", stale_target))
						if stale_valid:
							failures.append("launcher stale target validator accepted freed target: %s" % launcher_scene_path)

					if launcher_scene_path.contains("janggun") and launcher.has_method("_is_cannon_target_pair_valid"):
						var stale_cannon := Node3D.new()
						smoke_root.add_child(stale_cannon)
						stale_cannon.queue_free()
						await _wait_frames(owner, 2)
						var stale_pair_valid: bool = bool(launcher.call("_is_cannon_target_pair_valid", stale_cannon, target_ship))
						if stale_pair_valid:
							failures.append("janggun launcher accepted freed cached cannon")

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_projectile_smoke_pass(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int, projectile_scene_path: String) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("preview base is missing PlayerShip for projectile smoke: %s" % projectile_scene_path)
	else:
		var spawner: Node = smoke_root.get_node_or_null("EnemySpawner")
		var target_ship: Node3D = null
		if is_instance_valid(spawner) and spawner.has_method("debug_spawn_ship"):
			target_ship = spawner.call("debug_spawn_ship", "kobayabune_melee", 18.0, 0.0) as Node3D
			await _wait_frames(owner, wait_frames_after_spawn)
		if not is_instance_valid(target_ship):
			failures.append("projectile smoke target spawn failed: %s" % projectile_scene_path)
		else:
			var projectile_scene := load(projectile_scene_path) as PackedScene
			if projectile_scene == null:
				failures.append("projectile scene load failed: %s" % projectile_scene_path)
			else:
				var projectile := projectile_scene.instantiate()
				if projectile == null:
					failures.append("projectile scene instantiate failed: %s" % projectile_scene_path)
				else:
					var target_aim_pos: Vector3 = NodeContractHelper.get_projectile_aim_point(target_ship, 0.55)
					if projectile_scene_path.ends_with("fire_pot.tscn"):
						projectile.team = "player"
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_aim_pos
					elif projectile_scene_path.ends_with("ballista_bolt.tscn"):
						projectile.team = "player"
						projectile.direction = (target_aim_pos - player_ship.global_position).normalized()
						if projectile.direction.length_squared() <= 0.0001:
							projectile.direction = Vector3.FORWARD
						projectile.position = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
					elif projectile_scene_path.ends_with("janggun_missile.tscn"):
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_aim_pos
						projectile.team = "player"
						projectile.janggun_lv = 1
					elif projectile_scene_path.ends_with("singigeon_rocket.tscn"):
						projectile.start_pos = player_ship.global_position + Vector3(0.0, 1.0, 0.0)
						projectile.target_pos = target_aim_pos
						projectile.launch_direction = (target_aim_pos - player_ship.global_position).normalized()
						projectile.team = "player"
						projectile.shooter = player_ship

					var before_projectiles := EntityRegistry.count_projectiles()
					smoke_root.add_child(projectile)
					await _wait_frames(owner, wait_frames_after_attach)
					if not is_instance_valid(projectile):
						smoke_root.queue_free()
						await _wait_frames(owner, 1)
						return
					if projectile.has_method("set_team"):
						projectile.set_team("player")
					elif projectile.get("team") != null:
						projectile.set("team", "player")
					var projectile_team_variant: Variant = projectile.get("team")
					var projectile_team: String = "player" if projectile_team_variant == null else str(projectile_team_variant)
					if projectile_team != "player":
						failures.append("projectile team contract failed: %s" % projectile_scene_path)
					_configure_projectile_smoke(projectile, projectile_scene_path, player_ship, target_ship)
					if projectile_scene_path.ends_with("cannonball.tscn") and is_instance_valid(projectile):
						var max_travel_variant: Variant = projectile.get("_max_travel_distance")
						if max_travel_variant == null:
							failures.append("cannonball should expose a miss travel limit")
						else:
							var cannon_spawn_pos := player_ship.global_position + Vector3(0.0, 1.2, 0.0)
							var target_distance := cannon_spawn_pos.distance_to(target_aim_pos)
							var max_travel_distance := float(max_travel_variant)
							var lifetime_distance := float(projectile.get("speed")) * float(projectile.get("lifetime"))
							if max_travel_distance <= target_distance:
								failures.append("cannonball miss travel limit should extend past target distance")
							if max_travel_distance > target_distance + 14.0:
								failures.append("cannonball miss travel limit allows too much overshoot: %.2f" % (max_travel_distance - target_distance))
							if max_travel_distance >= lifetime_distance:
								failures.append("cannonball miss travel limit should be shorter than lifetime travel distance")
					await _wait_frames(owner, wait_frames_after_spawn)
					var after_projectiles := EntityRegistry.count_projectiles()
					if after_projectiles <= before_projectiles:
						failures.append("projectile did not register in entity registry: %s" % projectile_scene_path)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _configure_projectile_smoke(projectile: Node, projectile_scene_path: String, player_ship: Node3D, target_ship: Node3D) -> void:
	var target_aim_pos: Vector3 = NodeContractHelper.get_projectile_aim_point(target_ship, 0.55)
	if projectile_scene_path.ends_with("cannonball.tscn"):
		if projectile.has_method("launch"):
			projectile.call(
				"launch",
				player_ship.global_position + Vector3(0.0, 1.2, 0.0),
				"player",
				(target_aim_pos - (player_ship.global_position + Vector3(0.0, 1.2, 0.0))).normalized(),
				target_ship,
				12.0,
				1.0
			)
	elif projectile_scene_path.ends_with("arrow.tscn"):
		if projectile.has_method("launch"):
			projectile.call(
				"launch",
				player_ship.global_position + Vector3(0.0, 1.0, 0.0),
				target_aim_pos,
				target_ship,
				"player",
				9.0,
				"bow",
				24.0,
				2.0
			)
	elif projectile_scene_path.ends_with("fire_pot.tscn"):
		if projectile.has_method("setup_flight"):
			projectile.call("setup_flight", projectile.start_pos, projectile.target_pos, 0.8, 3.5)


static func _run_janggun_missile_expiry_contract(owner: Node, failures: Array[String]) -> void:
	var projectile_scene := load("res://scenes/projectiles/janggun_missile.tscn") as PackedScene
	if projectile_scene == null:
		failures.append("janggun missile expiry contract scene load failed")
		return
	var root := Node3D.new()
	owner.add_child(root)
	var missile := ScenePool.acquire(owner.get_tree(), projectile_scene)
	if missile == null:
		failures.append("janggun missile expiry contract instantiate failed")
		root.queue_free()
		await _wait_frames(owner, 1)
		return
	root.add_child(missile)
	if missile.has_method("launch"):
		missile.call("launch", Vector3(0.0, 2.0, 0.0), Vector3(6.0, 2.0, 0.0), "player", 1.0, 24.0, 0)
	else:
		failures.append("janggun missile expiry contract missing launch method")
		ScenePool.release(missile)
		root.queue_free()
		await _wait_frames(owner, 1)
		return
	await _wait_physics_frames(owner, 120)
	if EntityRegistry.get_projectiles().has(missile):
		failures.append("janggun missile should leave projectile registry after missed flight expiry")
	if is_instance_valid(missile) and missile.get_parent() == root:
		failures.append("janggun missile should release to pool or free after missed flight expiry")
	root.queue_free()
	await _wait_frames(owner, 1)


static func _run_projectile_aim_height_contract(failures: Array[String]) -> void:
	var low_ship := BaseShip.new()
	low_ship.global_position = Vector3(0.0, 0.0, 0.0)
	low_ship.deck_height = 0.35
	var high_ship := BaseShip.new()
	high_ship.global_position = Vector3(8.0, 2.0, 0.0)
	high_ship.deck_height = 1.1

	var low_aim: Vector3 = NodeContractHelper.get_projectile_aim_point(low_ship, 0.55)
	var high_aim: Vector3 = NodeContractHelper.get_projectile_aim_point(high_ship, 0.55)
	if low_aim.y <= low_ship.global_position.y + 0.5:
		failures.append("projectile aim point should target above low ship waterline")
	if high_aim.y <= high_ship.global_position.y + high_ship.deck_height:
		failures.append("projectile aim point should include high ship deck height")
	if high_aim.y <= low_aim.y + 2.0:
		failures.append("projectile aim point should preserve vertical difference between ship classes")
	var detached_ship := BaseShip.new()
	detached_ship.position = Vector3(3.0, 1.0, -2.0)
	detached_ship.deck_height = 0.8
	var detached_aim: Vector3 = NodeContractHelper.get_projectile_aim_point(detached_ship, 0.55)
	if absf(detached_aim.y - (detached_ship.position.y + detached_ship.deck_height + 0.55)) > 0.01:
		failures.append("projectile aim helper should not read global_position from off-tree ships")

	var soldier := Node3D.new()
	soldier.add_to_group("soldiers")
	soldier.global_position = Vector3(2.0, high_ship.global_position.y + high_ship.deck_height, 1.0)
	var soldier_aim: Vector3 = NodeContractHelper.get_projectile_aim_point(soldier, 0.5)
	if absf(soldier_aim.y - (soldier.global_position.y + 0.5)) > 0.01:
		failures.append("projectile aim point should target soldier body height")

	var cannon_source := FileAccess.get_file_as_string("res://scripts/entities/launchers/cannon.gd")
	if not cannon_source.contains("get_projectile_aim_point(target_node"):
		failures.append("cannon launcher should use projectile aim point for raised ship targets")
	if not cannon_source.contains("to_target.y = 0.0"):
		failures.append("cannon launcher arc check should stay planar across ship height differences")
	var singigeon_source := FileAccess.get_file_as_string("res://scripts/entities/launchers/singigeon_launcher.gd")
	if singigeon_source.contains("lead_pos.y = maxf(target_pos.y, from_pos.y)"):
		failures.append("singigeon launcher should not clamp target aim height to shooter height")
	if not singigeon_source.contains("get_projectile_aim_point(target"):
		failures.append("singigeon launcher should use projectile aim point for raised ship targets")
	var janggun_source := FileAccess.get_file_as_string("res://scripts/entities/launchers/janggun_launcher.gd")
	if not janggun_source.contains("JANGGUN_SHIP_AIM_VERTICAL_OFFSET"):
		failures.append("janggun launcher should use its lower ship impact aim offset")
	if not janggun_source.contains("get_projectile_aim_point(target_node, JANGGUN_SHIP_AIM_VERTICAL_OFFSET)"):
		failures.append("janggun launcher should aim below the high HitArea ceiling")
	var rocket_source := FileAccess.get_file_as_string("res://scripts/projectiles/singigeon_rocket.gd")
	if rocket_source.contains("homing_target.global_position + Vector3(0.0, 0.4, 0.0)"):
		failures.append("singigeon rocket homing should keep using projectile aim point")
	if not rocket_source.contains("get_projectile_aim_point(homing_target"):
		failures.append("singigeon rocket homing should aim at raised ship targets")
	if not rocket_source.contains("if not ship_3d.is_inside_tree():"):
		failures.append("singigeon rocket should ignore ship targets that left the scene tree")
	if not rocket_source.contains("if not (node as Node3D).is_inside_tree():"):
		failures.append("singigeon rocket should ignore soldier targets that left the scene tree")
	var node_contract_source := FileAccess.get_file_as_string("res://scripts/helpers/node_contract_helper.gd")
	if not node_contract_source.contains("node_3d.global_position if node_3d.is_inside_tree() else node_3d.position"):
		failures.append("projectile aim helper should have an off-tree position fallback")
	var janggun_scene := load("res://scenes/projectiles/janggun_missile.tscn") as PackedScene
	if janggun_scene == null:
		failures.append("janggun missile scene should load for visible impact contract")
	else:
		var missile := janggun_scene.instantiate()
		var impact_ship := BaseShip.new()
		impact_ship.deck_height = 1.4
		impact_ship.base_collision_radius = 4.0
		impact_ship.width_multiplier = 0.55
		impact_ship.length_multiplier = 1.0
		missile.global_position = Vector3(8.0, 5.0, 8.0)
		var impact: Vector3 = missile.call("_resolve_visible_ship_impact_position", impact_ship)
		if impact.y > impact_ship.global_position.y + impact_ship.deck_height + 0.25:
			failures.append("janggun visible impact should clamp below high invisible HitArea ceiling")
		var local_impact: Vector3 = impact_ship.to_local(impact)
		var half := impact_ship.get_collision_half_extents()
		if absf(local_impact.x) > half.x + 0.01 or absf(local_impact.z) > half.y + 0.01:
			failures.append("janggun visible impact should clamp into the visible hull footprint")
		missile.free()
		impact_ship.free()

	low_ship.free()
	high_ship.free()
	detached_ship.free()
	soldier.free()


static func _run_fire_pot_residual_smoke_contract(owner: Node, failures: Array[String], packed: PackedScene, smoke_scene_path: String, wait_frames_after_attach: int, wait_frames_after_spawn: int) -> void:
	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("smoke scene instantiate failed for fire pot residual smoke contract: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach)

	var player_ship: Node3D = smoke_root.get_node_or_null("PlayerShip") as Node3D
	if not is_instance_valid(player_ship):
		failures.append("fire pot residual smoke contract missing player ship")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var target_ship := _create_fire_pot_contract_ship_hitbox(smoke_root, player_ship.global_position + Vector3(12.0, 0.0, 0.0))
	await _wait_frames(owner, wait_frames_after_spawn)
	await _wait_physics_frames(owner, 1)
	if not is_instance_valid(target_ship):
		failures.append("fire pot residual smoke contract target hitbox setup failed")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var fire_pot_scene := load("res://scenes/projectiles/fire_pot.tscn") as PackedScene
	if fire_pot_scene == null:
		failures.append("fire pot residual smoke contract failed to load fire pot scene")
		smoke_root.queue_free()
		await _wait_frames(owner, 1)
		return

	var hit_pos := target_ship.global_position + Vector3(0.0, 0.4, 0.0)
	var hit_projectile := fire_pot_scene.instantiate()
	if hit_projectile == null:
		failures.append("fire pot residual smoke contract failed to instantiate hit projectile")
	else:
		hit_projectile.set("team", "player")
		hit_projectile.set("explosion_radius", 8.0)
		smoke_root.add_child(hit_projectile)
		await _wait_frames(owner, wait_frames_after_attach)
		var hit_projectile_node := hit_projectile as Node3D
		hit_projectile_node.global_position = hit_pos
		await _wait_physics_frames(owner, 1)
		var affected_hit: bool = hit_projectile.call("_apply_area_damage") == true
		if not affected_hit:
			failures.append("fire pot residual smoke contract did not recognize a ship hitbox hit")
		ScenePool.release(hit_projectile)
		await _wait_frames(owner, 2)

	var miss_pos := player_ship.global_position + Vector3(80.0, 0.4, 80.0)
	var miss_before := _count_active_fire_effects_near(owner.get_tree().root, miss_pos, 8.0)
	var miss_projectile := fire_pot_scene.instantiate()
	if miss_projectile == null:
		failures.append("fire pot residual smoke contract failed to instantiate miss projectile")
	else:
		miss_projectile.set("team", "player")
		miss_projectile.set("explosion_radius", 3.0)
		smoke_root.add_child(miss_projectile)
		await _wait_frames(owner, wait_frames_after_attach)
		var miss_projectile_node := miss_projectile as Node3D
		miss_projectile_node.global_position = miss_pos
		await _wait_physics_frames(owner, 1)
		miss_projectile.call("explode")
		await _wait_frames(owner, 3)
		var miss_after := _count_active_fire_effects_near(owner.get_tree().root, miss_pos, 8.0)
		if miss_after > miss_before:
			failures.append("fire pot residual smoke contract spawned residual smoke on water miss")
		_release_active_fire_effects_near(owner.get_tree().root, miss_pos, 8.0)
		await _wait_frames(owner, 2)

	await _run_fire_effect_pool_reset_contract(owner, failures)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _create_fire_pot_contract_ship_hitbox(parent: Node, position: Vector3) -> Node3D:
	var ship_root := Node3D.new()
	ship_root.name = "FirePotContractShip"
	ship_root.add_to_group("enemy")
	ship_root.add_to_group("ships")
	parent.add_child(ship_root)
	ship_root.global_position = position

	var hitbox := Area3D.new()
	hitbox.name = "HitArea"
	hitbox.collision_layer = 4
	hitbox.collision_mask = 0
	hitbox.add_to_group("ship_hitbox")
	ship_root.add_child(hitbox)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 8.0)
	shape.shape = box
	hitbox.add_child(shape)
	return ship_root


static func _run_fire_effect_pool_reset_contract(owner: Node, failures: Array[String]) -> void:
	var fire_effect_scene := load(FIRE_EFFECT_SCENE_PATH) as PackedScene
	if fire_effect_scene == null:
		failures.append("fire effect pool reset contract failed to load fire effect scene")
		return

	var fire_effect := ScenePool.acquire(owner.get_tree(), fire_effect_scene)
	if not is_instance_valid(fire_effect):
		failures.append("fire effect pool reset contract failed to acquire fire effect")
		return

	owner.get_tree().root.add_child(fire_effect)
	if fire_effect.has_method("pool_activate"):
		fire_effect.call("pool_activate")
	await _wait_frames(owner, 1)
	if not _is_fire_effect_active(fire_effect):
		failures.append("fire effect pool reset contract did not activate particles")

	var fire_effect_id := fire_effect.get_instance_id()
	ScenePool.release(fire_effect)
	await _wait_frames(owner, 2)
	var pooled_effect := NodeContractHelper.get_instance_node(fire_effect_id)
	if is_instance_valid(pooled_effect) and _is_fire_effect_active(pooled_effect):
		failures.append("fire effect pool reset contract left smoke particles active after release")


static func _count_active_fire_effects_near(node: Node, center: Vector3, radius: float) -> int:
	if node == null:
		return 0
	return _count_active_fire_effects_near_node(node, center, radius * radius)


static func _count_active_fire_effects_near_node(node: Node, center: Vector3, radius_squared: float) -> int:
	var count := 0
	if node.name == "FireEffect" and node is Node3D:
		var node_3d := node as Node3D
		if node_3d.global_position.distance_squared_to(center) <= radius_squared and _is_fire_effect_active(node):
			count += 1
	for child in node.get_children():
		count += _count_active_fire_effects_near_node(child, center, radius_squared)
	return count


static func _release_active_fire_effects_near(node: Node, center: Vector3, radius: float) -> void:
	if node == null:
		return
	_release_active_fire_effects_near_node(node, center, radius * radius)


static func _release_active_fire_effects_near_node(node: Node, center: Vector3, radius_squared: float) -> void:
	if node.name == "FireEffect" and node is Node3D:
		var node_3d := node as Node3D
		if node_3d.global_position.distance_squared_to(center) <= radius_squared and _is_fire_effect_active(node):
			ScenePool.release(node)
			return
	for child in node.get_children():
		_release_active_fire_effects_near_node(child, center, radius_squared)


static func _is_fire_effect_active(node: Node) -> bool:
	if node is Node3D and (node as Node3D).visible:
		return true
	return _has_emitting_particles(node)


static func _has_emitting_particles(node: Node) -> bool:
	if node is GPUParticles3D and (node as GPUParticles3D).emitting:
		return true
	for child in node.get_children():
		if _has_emitting_particles(child):
			return true
	return false


static func _validate_registry_smoke(failures: Array[String], player_ship: Node3D, label: String) -> void:
	if not is_instance_valid(player_ship):
		return

	var player_lookup: Node = EntityRegistry.get_first_ship_by_team("player")
	if player_lookup != player_ship:
		failures.append("%s smoke player ship registry lookup mismatch" % label)

	if EntityRegistry.count_ships_by_team("player") <= 0:
		failures.append("%s smoke player ship team bucket is empty" % label)

	if EntityRegistry.count_soldiers_by_team("player") <= 0:
		failures.append("%s smoke player soldier bucket is empty" % label)

	var enemy_ships: Array = EntityRegistry.get_ships_by_team("enemy")
	if enemy_ships.is_empty():
		failures.append("%s smoke enemy ship team bucket is empty" % label)
		return

	var boss_count := 0
	for ship in enemy_ships:
		if is_instance_valid(ship) and ship.is_in_group("boss"):
			boss_count += 1
	if boss_count <= 0:
		failures.append("%s smoke boss ship did not enter the enemy team bucket" % label)


static func _validate_spawned_boss(failures: Array[String], spawned_boss: Node3D, label: String) -> void:
	if not is_instance_valid(spawned_boss):
		failures.append("%s spawn returned null" % label)
		return
	var boss_team := str(spawned_boss.get("team"))
	if boss_team != "enemy":
		failures.append("%s team contract failed: %s" % [label, boss_team])
	if not spawned_boss.is_in_group("boss"):
		failures.append("%s is missing boss group tag" % label)
	var registered_enemy := EntityRegistry.get_ships_by_team("enemy").has(spawned_boss)
	if not registered_enemy:
		failures.append("%s instance was not registered in enemy team bucket" % label)
	var expected_crew_count: int = 6 if int(spawned_boss.get("tier")) == 1 else 4
	var actual_crew_count: int = EntityRegistry.get_soldiers_by_ship(spawned_boss).size()
	if actual_crew_count != expected_crew_count:
		failures.append("%s crew count contract failed: %d != %d" % [label, actual_crew_count, expected_crew_count])
	var max_hull_hp: float = float(spawned_boss.get("max_hull_hp"))
	if int(spawned_boss.get("tier")) == 1 and max_hull_hp > 520.0:
		failures.append("%s mid boss hull contract failed: %.1f > 520.0" % [label, max_hull_hp])
	var preferred_range: float = float(spawned_boss.get("preferred_combat_range"))
	var range_tolerance: float = float(spawned_boss.get("combat_range_tolerance"))
	var retreat_distance: float = float(spawned_boss.get("retreat_distance"))
	if int(spawned_boss.get("tier")) == 1:
		if absf(preferred_range - 14.0) > 0.05:
			failures.append("%s mid boss preferred range contract failed: %.2f != 14.0" % [label, preferred_range])
		if absf(range_tolerance - 2.5) > 0.05:
			failures.append("%s mid boss range tolerance contract failed: %.2f != 2.5" % [label, range_tolerance])
		if absf(retreat_distance - 7.0) > 0.05:
			failures.append("%s mid boss retreat distance contract failed: %.2f != 7.0" % [label, retreat_distance])
	else:
		if absf(preferred_range - 16.0) > 0.05:
			failures.append("%s final boss preferred range contract failed: %.2f != 16.0" % [label, preferred_range])
		if absf(range_tolerance - 2.5) > 0.05:
			failures.append("%s final boss range tolerance contract failed: %.2f != 2.5" % [label, range_tolerance])
		if absf(retreat_distance - 9.0) > 0.05:
			failures.append("%s final boss retreat distance contract failed: %.2f != 9.0" % [label, retreat_distance])


static func _validate_final_boss_victory_on_death(owner: Node, failures: Array[String], spawned_boss: Node3D, level_manager: Node, label: String) -> void:
	if not is_instance_valid(spawned_boss):
		return
	if int(spawned_boss.get("tier")) < 2:
		failures.append("%s victory contract fixture was not tier 2" % label)
		return
	if not is_instance_valid(level_manager):
		failures.append("%s victory contract missing level manager" % label)
		return
	if level_manager.get("_victory_triggered") == true:
		failures.append("%s victory contract started with victory already triggered" % label)
		return
	var time_scale_before: float = Engine.time_scale
	if spawned_boss.has_method("die"):
		spawned_boss.call("die")
		await _wait_frames(owner, 1)
	if spawned_boss.get("_defeat_flourish_started") != true:
		failures.append("%s death did not start the defeat flourish" % label)
	_validate_final_boss_defeat_message(failures, level_manager, label)
	if DisplayServer.get_name() == "headless" and not is_equal_approx(Engine.time_scale, time_scale_before):
		failures.append("%s headless defeat flourish changed Engine.time_scale" % label)
	if level_manager.get("_victory_triggered") != true:
		failures.append("%s death did not trigger victory" % label)
	var result_data: Dictionary = RunResultStore.get_latest_result()
	if str(result_data.get("outcome", "")) != "최종 보스 격침":
		failures.append("%s death did not populate final boss result data" % label)


static func _validate_final_boss_defeat_message(failures: Array[String], level_manager: Node, label: String) -> void:
	var hud: Node = level_manager.get("hud") if is_instance_valid(level_manager) else null
	if not is_instance_valid(hud):
		failures.append("%s defeat flourish missing HUD" % label)
		return
	var warning_variant: Variant = hud.get("gust_warning")
	var warning_label := warning_variant as Label
	if not is_instance_valid(warning_label):
		failures.append("%s defeat flourish missing warning label" % label)
		return
	if warning_label.text != "최종 보스 격침!" or not warning_label.visible:
		failures.append("%s defeat flourish did not show the boss defeat message" % label)


static func _validate_spawned_ship(failures: Array[String], spawned_ship: Node3D, label: String) -> void:
	if not is_instance_valid(spawned_ship):
		failures.append("%s spawn returned null" % label)
		return
	var ship_team := str(spawned_ship.get("team"))
	if ship_team != "enemy":
		failures.append("%s team contract failed: %s" % [label, ship_team])
	if not spawned_ship.is_in_group("ships"):
		failures.append("%s is missing ships group tag" % label)
	var registered_enemy := EntityRegistry.get_ships_by_team("enemy").has(spawned_ship)
	if not registered_enemy:
		failures.append("%s instance was not registered in enemy team bucket" % label)
	_validate_spawned_ship_collision_fit(failures, spawned_ship, label)

	if label == "sekibune_cannon":
		var scan_stack: Array[Node] = [spawned_ship]
		var cannon_count := 0
		var daecheolpo_count := 0
		while not scan_stack.is_empty():
			var node := scan_stack.pop_back() as Node
			if not is_instance_valid(node):
				continue
			for child in node.get_children():
				if child.has_method("fire") or "cannonball_scene" in child:
					cannon_count += 1
					continue
				if child.get("crew_role") != null and str(child.get("crew_role")) == "daecheolpo":
					daecheolpo_count += 1
				scan_stack.append(child)
		if cannon_count > 0:
			failures.append("sekibune_cannon should not spawn ship-mounted cannons")
		if daecheolpo_count < 1:
			failures.append("sekibune_cannon should spawn daecheolpo crew")


static func _validate_spawned_ship_collision_fit(failures: Array[String], spawned_ship: Node3D, label: String) -> void:
	if not is_instance_valid(spawned_ship):
		return
	if not spawned_ship.has_method("get_collision_half_extents"):
		return
	var soft_extents_value: Variant = spawned_ship.call("get_collision_half_extents")
	if not (soft_extents_value is Vector2):
		return
	var soft_extents := soft_extents_value as Vector2
	if soft_extents.x <= 0.01 or soft_extents.y <= 0.01:
		failures.append("%s collision fit produced invalid soft extents: %s" % [label, soft_extents])
		return
	var hit_area := NodeContractHelper.get_hit_area(spawned_ship)
	if not is_instance_valid(hit_area):
		return
	var hit_shape_node := ShipContactGeometry.get_contact_area_collision_shape(hit_area)
	if not (hit_shape_node is CollisionShape3D):
		return
	var hit_shape := (hit_shape_node as CollisionShape3D).shape
	if not (hit_shape is BoxShape3D):
		return
	var hit_box := hit_shape as BoxShape3D
	var hit_half_extents := Vector2(hit_box.size.x * 0.5, hit_box.size.z * 0.5)
	if hit_half_extents.x <= 0.01 or hit_half_extents.y <= 0.01:
		return
	var width_ratio: float = soft_extents.x / hit_half_extents.x
	var length_ratio: float = soft_extents.y / hit_half_extents.y
	if width_ratio < 0.9:
		failures.append("%s collision fit width too small for hull/contact box: %.3f" % [label, width_ratio])
	if length_ratio < 0.9:
		failures.append("%s collision fit length too small for hull/contact box: %.3f" % [label, length_ratio])


static func _wait_frames(owner: Node, count: int) -> void:
	for _index in range(max(0, count)):
		await owner.get_tree().process_frame


static func _wait_physics_frames(owner: Node, count: int) -> void:
	for _index in range(max(0, count)):
		await owner.get_tree().physics_frame
