extends RefCounted
class_name ProjectContractSceneWiringHelper

const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")

const ENEMY_SPAWN_RULES_DATA_PATH := "res://data/enemy_spawn_rules.json"
const LEVEL_PROGRESSION_DATA_PATH := "res://data/level_progression.json"
const AUTHORING_PALETTE_DATA_PATH := "res://data/authoring_palette.json"
const AUTHORING_INTENT_FAMILY_ENEMY_RUNTIME := "enemy_runtime"
const AUTHORING_INTENT_FAMILY_SUPPORT_RUNTIME := "support_runtime"
const AUTHORING_INTENT_FAMILIES := [
	AUTHORING_INTENT_FAMILY_ENEMY_RUNTIME,
	AUTHORING_INTENT_FAMILY_SUPPORT_RUNTIME,
]
const AUTHORING_PALETTE_BLOCK_SCHEMA_VERSION := 1
const AUTHORING_PALETTE_CATALOGS := [
	"ship_archetypes",
	"ship_types",
	"weapon_profiles",
	"combat_profiles",
	"movement_intents",
	"spawn_recipes",
	"fleet_classes",
	"encounter_profiles",
	"scenario_triggers",
]
const AUTHORING_BLOCK_KINDS := ["action", "authoring_meta", "reference"]
const AUTHORING_BLOCK_SOURCE_PATHS := [
	"res://data/ship_stats.json",
	"res://data/enemy_spawn_rules.json",
	"res://data/authoring_palette.json",
]
const AUTHORING_BLOCK_ACTION_TYPES := [
	"spawn_ship",
	"spawn_recipe",
	"set_encounter_profile",
	"run_scenario_trigger",
]
const AUTHORING_BLOCK_AUTHORING_KEYS := ["combat_profile", "movement_intent"]


class MockAllyRoleShip:
	extends Node3D

	var team: String = "player"
	var is_player_controlled: bool = false

	func get_team_tag() -> String:
		return team


class MockShipWorkShip:
	extends Node3D

	var team: String = "player"
	var deck_height: float = 0.4
	var shiphandling_crew_ratio: float = 1.0
	var gunnery_crew_ratio: float = 0.0
	var is_rowing: bool = true
	var rudder_angle: float = 0.0
	var current_speed: float = 5.0
	var deck_is_contested: bool = false
	var deck_is_overrun: bool = false
	var deck_hostile_boarder_count: int = 0
	var rigging_field_repair_enabled: bool = false
	var is_burning: bool = false
	var is_sinking: bool = false
	var is_dying: bool = false
	var is_derelict: bool = false

	func get_team_tag() -> String:
		return team

	func get_deck_half_extents() -> Vector2:
		return Vector2(2.5, 5.0)

	func get_current_speed_value() -> float:
		return current_speed


class MockShipWorkSoldier:
	extends Node3D

	var team: String = "player"
	var owned_ship: Node3D = null
	var current_target: Node3D = null
	var is_captain: bool = false
	var crew_role: String = "general"

	func get_team_tag() -> String:
		return team

	func get_owned_ship_node() -> Node3D:
		return owned_ship

	func is_dead_soldier() -> bool:
		return false

	func is_jumping_value() -> bool:
		return false

	func is_ranged_only_value() -> bool:
		return false


static func run_scene_wiring_contract_smoke(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var scene_checks := [
		{
			"path": "res://scenes/ships/player_ship.tscn",
			"label": "player ship",
			"team": "player",
			"player_controlled": true,
			"groups": ["player"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "ShipAudio", "CollisionVisualizer"],
			"forbidden_nodes": [],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": null,
		},
		{
			"path": "res://scenes/ships/enemy_base_ship.tscn",
			"label": "enemy base ship",
			"team": "enemy",
			"player_controlled": false,
			"groups": ["enemy", "ships"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "CollisionVisualizer"],
			"forbidden_nodes": [],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": null,
		},
		{
			"path": "res://scenes/ships/enemy_ship.tscn",
			"label": "enemy runtime ship",
			"team": "enemy",
			"player_controlled": false,
			"groups": ["enemy", "ships"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "CollisionVisualizer"],
			"forbidden_nodes": [],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": null,
		},
		{
			"path": "res://scenes/ships/boss_ship.tscn",
			"label": "boss ship",
			"team": "enemy",
			"player_controlled": false,
			"groups": ["boss", "ships"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "CollisionVisualizer", "Cannons"],
			"forbidden_nodes": ["CollisionArea"],
			"require_hull": true,
			"require_boss_group": true,
			"allow_boarding": null,
		},
		{
			"path": "res://scenes/ships/enemy_firepot_ship.tscn",
			"label": "enemy firepot ship",
			"team": "enemy",
			"player_controlled": false,
			"groups": ["enemy", "ships"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "CollisionVisualizer"],
			"forbidden_nodes": [],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": true,
		},
		{
			"path": "res://scenes/ships/support_ship.tscn",
			"label": "support ship",
			"team": "player",
			"player_controlled": false,
			"groups": ["player", "ships", "captured_minion"],
			"required_nodes": ["ProximityArea", "HitArea", "Soldiers", "CollisionVisualizer"],
			"forbidden_nodes": [],
			"require_hull": true,
			"require_boss_group": false,
			"allow_boarding": true,
		},
	]

	for check in scene_checks:
		await _run_single_scene_wiring_pass(
			owner,
			failures,
			str(check["path"]),
			str(check["label"]),
			str(check["team"]),
			check["player_controlled"] == true,
			check["groups"],
			check["required_nodes"],
			check["forbidden_nodes"],
			check["require_hull"] == true,
			check["require_boss_group"] == true,
			check["allow_boarding"],
			wait_frames_after_attach
		)

	_run_main_player_effect_scene_wiring_pass(failures)
	await _run_player_ship_runtime_safety_contract(owner, failures, wait_frames_after_attach)
	_run_player_corpse_cleanup_sequence_contract(failures)
	_run_transparent_vfx_render_priority_contract(failures)
	await _run_player_cannon_slot_authoring_contract(owner, failures, wait_frames_after_attach)
	await _run_player_boarding_anchor_authoring_contract(owner, failures, wait_frames_after_attach)
	await _run_player_crew_slot_authoring_contract(owner, failures, wait_frames_after_attach)
	await _run_support_ship_spawn_template_contract(owner, failures, wait_frames_after_attach)
	_run_ship_ally_role_contract(failures)
	_run_hull_authoring_marker_contract(failures)
	_run_ship_blueprint_weapon_loadout_contract(failures)
	_run_level_progression_contract(failures)
	_run_enemy_spawn_rules_contract(failures)
	_run_scenario_action_authoring_negative_contract(failures)
	_run_authoring_palette_contract(failures)
	await _run_soldier_common_action_contract(owner, failures, wait_frames_after_attach)
	_run_soldier_ship_work_priority_contract(owner, failures)
	_run_soldier_smooth_turn_contract(owner, failures)
	await _run_boarding_rope_anchor_height_contract(owner, failures, wait_frames_after_attach)
	await _run_boarding_landing_contract(owner, failures, wait_frames_after_attach)
	_run_weapon_damage_grouping_contract(failures)
	await _run_result_scene_wiring_pass(owner, failures, wait_frames_after_attach)


static func _run_player_ship_runtime_safety_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/ships/player_ship.tscn") as PackedScene
	if packed == null:
		failures.append("player ship runtime safety contract load failed")
		return
	var wrapper := Node3D.new()
	wrapper.name = "PlayerShipRuntimeSafetyContract"
	owner.add_child(wrapper)
	var start_marker := Marker3D.new()
	start_marker.name = "PlayerStart"
	start_marker.global_position = Vector3(11.0, 1.25, -7.0)
	wrapper.add_child(start_marker)
	var player_ship := packed.instantiate() as Node3D
	if player_ship == null:
		failures.append("player ship runtime safety contract instantiate failed")
		wrapper.queue_free()
		return

	player_ship.set("max_hull_hp", 0.33)
	player_ship.set("fire_effect_scene", load("res://scenes/effects/wood_splinter.tscn"))
	player_ship.set("loot_scene", load("res://scenes/effects/water_burst.tscn"))
	player_ship.set("survivor_scene", load("res://scenes/effects/fire_effect.tscn"))
	player_ship.set("boarding_hook_throw_delay", 12.0)
	wrapper.add_child(player_ship)
	await _wait_frames(owner, wait_frames_after_attach)

	var max_hull_hp := float(player_ship.get("max_hull_hp"))
	if max_hull_hp < 100.0:
		failures.append("player ship runtime safety did not repair max_hull_hp: %.2f" % max_hull_hp)
	_validate_packed_scene_path(player_ship, "fire_effect_scene", "res://scenes/effects/fire_effect.tscn", failures)
	_validate_packed_scene_path(player_ship, "survivor_scene", "res://scenes/effects/survivor.tscn", failures)
	if player_ship.get("loot_scene") != null:
		failures.append("player ship runtime safety should clear loot_scene")
	if player_ship.get("deck_light_player_only") != true:
		failures.append("player ship runtime safety should force deck_light_player_only")
	if absf(float(player_ship.get("boarding_hook_throw_delay")) - 0.55) > 0.01:
		failures.append("player ship runtime safety did not restore boarding_hook_throw_delay")
	if absf(float(player_ship.get("floating_offset")) - 1.35) > 0.01:
		failures.append("player ship runtime safety did not restore floating_offset")
	if player_ship.global_position.distance_to(start_marker.global_position) > 0.01:
		failures.append("player ship runtime safety did not apply PlayerStart transform")
	if not InputMap.has_action("toggle_sail_furl"):
		failures.append("player ship should expose toggle_sail_furl input action")
	if not player_ship.has_method("toggle_sail_furl") or not player_ship.has_method("_update_sail_deployment"):
		failures.append("player ship should expose sail furl controls")
	else:
		var sail_shader_source := FileAccess.get_file_as_string("res://assets/shaders/sail.gdshader")
		if not sail_shader_source.contains("sail_visibility") or not sail_shader_source.contains("sail_visibility <= 0.01"):
			failures.append("furled sail shader should hide fully folded sail cloth")
		player_ship.call("set_sail_furled", true)
		var mast_fold_pivots: Array = player_ship.get("mast_fold_pivots") if player_ship.get("mast_fold_pivots") != null else []
		if not mast_fold_pivots.is_empty() and player_ship.has_method("are_masts_folded") and bool(player_ship.call("are_masts_folded")):
			failures.append("player ship mast pivots should wait until sails are fully furled")
		player_ship.set("sail_deployed_ratio", 1.0)
		player_ship.call("_update_sail_deployment", 1.0)
		var folded_ratio := float(player_ship.get("sail_deployed_ratio"))
		if folded_ratio >= 0.99:
			failures.append("player ship sail furl should lower deployed ratio")
		if not mast_fold_pivots.is_empty() and player_ship.has_method("are_masts_folded") and not bool(player_ship.call("are_masts_folded")):
			failures.append("player ship sail furl should fold available mast pivots after sails are down")
		if player_ship.has_method("_update_sail_visual"):
			player_ship.call("_update_sail_visual")
		var mast_received_deployment := false
		var masts: Array = player_ship.get("masts") if player_ship.get("masts") != null else []
		for mast in masts:
			if is_instance_valid(mast) and mast.has_method("get_sail_deployed_ratio"):
				mast_received_deployment = true
				var mast_ratio := float(mast.call("get_sail_deployed_ratio"))
				if absf(mast_ratio - folded_ratio) > 0.01:
					failures.append("player ship should pass sail deployment ratio to masts")
				var yardarm := mast.get_node_or_null("SailVisual/yardarm") as Node3D
				if not is_instance_valid(yardarm):
					failures.append("player ship mast should include a yardarm visual")
				else:
					mast.call("set_sail_deployed_ratio", 1.0)
					var deployed_y := yardarm.position.y
					mast.call("set_sail_deployed_ratio", 0.0)
					var furled_y := yardarm.position.y
					if furled_y >= deployed_y - 0.5:
						failures.append("furled sail should lower the yardarm with the sail cloth")
					if yardarm.visible:
						failures.append("fully furled sail should hide the yardarm visual")
					mast.call("set_sail_deployed_ratio", mast_ratio)
				break
			if not mast_received_deployment:
				failures.append("player ship masts should expose sail deployment visuals")
			if not mast_fold_pivots.is_empty() and player_ship.has_method("set_masts_folded") and player_ship.has_method("get_mast_fold_ratio"):
				player_ship.call("set_masts_folded", true, true)
				player_ship.set("sail_deployed_ratio", 0.0)
				player_ship.call("set_sail_furled", false)
				player_ship.call("_update_sail_deployment", 1.0)
				if float(player_ship.get("sail_deployed_ratio")) > 0.001:
					failures.append("player ship sail unfurl should wait until mast pivots are raised")
				player_ship.call("set_masts_folded", false, true)
				player_ship.call("_update_sail_deployment", 1.0)
				if float(player_ship.get("sail_deployed_ratio")) <= 0.001:
					failures.append("player ship sail unfurl should raise sails after mast pivots are upright")
			player_ship.call("set_sail_furled", false)
			if not mast_fold_pivots.is_empty() and player_ship.has_method("are_masts_folded") and bool(player_ship.call("are_masts_folded")):
				failures.append("player ship sail unfurl should raise available mast pivots")
		player_ship.set("rudder_health", player_ship.get("rudder_max_health"))
		var open_turn_mult := float(player_ship.call("get_rudder_turn_multiplier"))
		var open_response_mult := float(player_ship.call("get_rudder_response_multiplier"))
		player_ship.call("set_sail_furled", true)
		var furled_turn_mult := float(player_ship.call("get_rudder_turn_multiplier"))
		var furled_response_mult := float(player_ship.call("get_rudder_response_multiplier"))
		if furled_turn_mult <= open_turn_mult * 1.2:
			failures.append("furled sail should improve rudder turn authority")
		if furled_response_mult <= open_response_mult * 1.2:
			failures.append("furled sail should improve rudder response")

		player_ship.set("acceleration", 1000.0)
		player_ship.set("is_rowing", true)
		player_ship.set("rowing_locked", false)
		player_ship.set("rowing_stamina", 100.0)
		player_ship.set("current_speed", 0.0)
		player_ship.call("_update_movement", 0.1)
		var furled_rowing_speed := float(player_ship.get("current_speed"))
		player_ship.call("set_sail_furled", false)
		player_ship.set("current_speed", 0.0)
		player_ship.call("_update_movement", 0.1)
		var open_rowing_speed := float(player_ship.get("current_speed"))
		if furled_rowing_speed <= open_rowing_speed * 1.1:
			failures.append("furled sail should improve rowing speed efficiency")
		player_ship.call("set_rowing", true, -1)
		player_ship.set("current_speed", 0.0)
		player_ship.call("_update_movement", 0.1)
		var reverse_rowing_speed := float(player_ship.get("current_speed"))
		if reverse_rowing_speed >= -0.1:
			failures.append("reverse rowing should move the player ship backward")
		if absf(reverse_rowing_speed) >= open_rowing_speed * 0.65:
			failures.append("reverse rowing should stay slower than forward rowing")

		player_ship.set("stamina_drain_rate", 10.0)
		player_ship.call("set_rowing", true, 1)
		player_ship.call("set_sail_furled", true)
		player_ship.set("rowing_stamina", 100.0)
		player_ship.call("_update_rowing_stamina", 1.0)
		var furled_stamina_loss := 100.0 - float(player_ship.get("rowing_stamina"))
		player_ship.call("set_sail_furled", false)
		player_ship.set("rowing_stamina", 100.0)
		player_ship.call("_update_rowing_stamina", 1.0)
		var open_stamina_loss := 100.0 - float(player_ship.get("rowing_stamina"))
		if furled_stamina_loss >= open_stamina_loss:
			failures.append("furled sail should reduce rowing stamina cost")

		player_ship.set("burn_hull_damage_per_second", 10.0)
		player_ship.set("hull_hp", 100.0)
		player_ship.set("is_burning", true)
		player_ship.set("burn_timer", 5.0)
		player_ship.call("set_sail_furled", true)
		player_ship.call("_update_burning_status", 1.0)
		var furled_fire_damage := 100.0 - float(player_ship.get("hull_hp"))
		player_ship.set("hull_hp", 100.0)
		player_ship.set("is_burning", true)
		player_ship.set("burn_timer", 5.0)
		player_ship.call("set_sail_furled", false)
		player_ship.call("_update_burning_status", 1.0)
		var open_fire_damage := 100.0 - float(player_ship.get("hull_hp"))
		if furled_fire_damage > open_fire_damage * 0.55:
			failures.append("furled sail should reduce fire damage by about half")
		player_ship.set("is_rowing", false)
		player_ship.set("is_burning", false)

	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _run_player_corpse_cleanup_sequence_contract(failures: Array[String]) -> void:
	var player_ship_source := FileAccess.get_file_as_string("res://scripts/entities/ships/player_ship.gd")
	if player_ship_source.is_empty():
		failures.append("player corpse cleanup contract could not read player_ship.gd")
		return
	if not player_ship_source.contains("_get_corpse_cleanup_pickup_point"):
		failures.append("player corpse cleanup should move the actor to the corpse before pickup")
	if not player_ship_source.contains("_get_corpse_cleanup_rail_stand_point"):
		failures.append("player corpse cleanup should move the actor to a rail stand point before throwing")
	if not player_ship_source.contains("_get_corpse_cleanup_actor_local_target"):
		failures.append("player corpse cleanup should move the actor in parent-local coordinates")
	if player_ship_source.contains("tween.tween_property(cleaner, \"global_position\""):
		failures.append("player corpse cleanup actor should not tween global_position off the moving ship")
	if not player_ship_source.contains("_get_corpse_cleanup_carry_rotation"):
		failures.append("player corpse cleanup should rotate the corpse into a carried pose")
	if not player_ship_source.contains("_begin_corpse_cleanup_carry_payload_by_id"):
		failures.append("player corpse cleanup should begin a reusable carry payload")
	if not player_ship_source.contains("_apply_corpse_cleanup_payload_follow"):
		failures.append("player corpse cleanup should keep the corpse following the carry payload anchor")
	if not player_ship_source.contains("CARRY_PAYLOAD_KIND_CORPSE"):
		failures.append("player corpse cleanup should tag the carried payload kind")
	if player_ship_source.contains("tween.tween_property(corpse, \"global_position\", rail_carry_position"):
		failures.append("player corpse cleanup should not use a fixed rail carry point instead of the carry anchor")
	if not player_ship_source.contains("_set_corpse_cleanup_action_by_id"):
		failures.append("player corpse cleanup should name actor actions during cleanup")
	if not player_ship_source.contains("SoldierActionHelper.ACTION_CORPSE_CLEANUP_APPROACH"):
		failures.append("player corpse cleanup should name the approach action")
	if not player_ship_source.contains("SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY"):
		failures.append("player corpse cleanup should name the carry action")
	if not player_ship_source.contains("SoldierActionHelper.ACTION_CORPSE_CLEANUP_THROW"):
		failures.append("player corpse cleanup should name the throw action")
	if not player_ship_source.contains("SoldierShipWorkPriorityHelper.TASK_CORPSE_CLEANUP"):
		failures.append("player corpse cleanup should choose actors through the ship work priority system")
	if player_ship_source.contains("corpse_cleanup_busy"):
		failures.append("player corpse cleanup should use the soldier action naming system instead of a cleanup-specific busy meta")
	if not player_ship_source.contains("CORPSE_CLEANUP_CARRY_FORWARD_OFFSET := 0.08"):
		failures.append("player corpse cleanup carry forward offset should keep the corpse close to the actor")
	if not player_ship_source.contains("CORPSE_CLEANUP_CARRY_SIDE_OFFSET := 0.08"):
		failures.append("player corpse cleanup carry side offset should keep the corpse close to the actor")
	if not player_ship_source.contains("CORPSE_CLEANUP_CARRY_HEIGHT_OFFSET := 0.46"):
		failures.append("player corpse cleanup carry height offset should avoid telekinetic carry spacing")
	if not player_ship_source.contains("_get_corpse_cleanup_carry_payload_offsets"):
		failures.append("player corpse cleanup should feed carry offsets through payload definitions")
	if not player_ship_source.contains("begin_typed_carry_payload"):
		failures.append("player corpse cleanup should use typed carry payload definitions")
	if not player_ship_source.contains("_capture_corpse_cleanup_pickup_pose_by_id"):
		failures.append("player corpse cleanup should capture the corpse pickup pose at pickup time")
	if player_ship_source.contains("var pickup_start_position: Vector3 = corpse.global_position"):
		failures.append("player corpse cleanup should not cache pickup start global_position before the actor approaches")
	if not player_ship_source.contains("_capture_corpse_cleanup_throw_arc_by_id"):
		failures.append("player corpse cleanup should capture the throw arc at throw time")
	if player_ship_source.contains("_apply_corpse_cleanup_throw_arc\").bind(corpse_id, throw_origin"):
		failures.append("player corpse cleanup should not bind a stale throw origin before rail carry completes")
	var approach_index := player_ship_source.find("tween.tween_property(cleaner, \"position\", pickup_actor_position")
	var pickup_index := player_ship_source.find("_apply_corpse_cleanup_payload_pickup")
	var carry_index := player_ship_source.find("tween.tween_property(cleaner, \"position\", rail_actor_position")
	var throw_index := player_ship_source.find("_apply_corpse_cleanup_throw_arc")
	if approach_index == -1 or pickup_index == -1 or carry_index == -1 or throw_index == -1:
		failures.append("player corpse cleanup sequence is missing approach/pickup/carry/throw steps")
	elif not (approach_index < pickup_index and pickup_index < carry_index and carry_index < throw_index):
		failures.append("player corpse cleanup sequence should be approach -> pickup -> rail carry -> throw")

	var soldier_source := FileAccess.get_file_as_string("res://scripts/entities/soldiers/soldier.gd")
	if soldier_source.is_empty():
		failures.append("player corpse cleanup contract could not read soldier.gd")
		return
	if not soldier_source.contains("SoldierActionHelper.is_action_ai_locked(self)"):
		failures.append("named soldier actions should lock regular AI when requested")
	if not soldier_source.contains("begin_named_action"):
		failures.append("soldier should expose a reusable named action entry point")
	if not soldier_source.contains("finish_named_action"):
		failures.append("soldier should expose a reusable named action exit point")
	if not soldier_source.contains("begin_typed_carry_payload"):
		failures.append("soldier should expose typed carry payload entry points")
	if not soldier_source.contains("get_carry_payload_kind"):
		failures.append("soldier should expose the active carried payload kind")
	if soldier_source.contains("corpse_cleanup_busy"):
		failures.append("soldier AI lock should use the reusable action naming system")
	var action_source := FileAccess.get_file_as_string("res://scripts/entities/soldiers/soldier_action_helper.gd")
	if action_source.is_empty():
		failures.append("player corpse cleanup contract could not read soldier_action_helper.gd")
		return
	if not action_source.contains("ACTION_NAME_META"):
		failures.append("soldier action helper should store the active action name")
	if not action_source.contains("ACTION_AI_LOCK_META"):
		failures.append("soldier action helper should store whether the action locks regular AI")
	if not action_source.contains("ACTION_DEFINITIONS"):
		failures.append("soldier action helper should expose an action definition catalog")
	if not action_source.contains("static func begin_known_action"):
		failures.append("soldier action helper should provide a catalog-backed begin API")
	if not action_source.contains("ACTION_CORPSE_CLEANUP_APPROACH"):
		failures.append("soldier action helper should name corpse cleanup approach")
	if not action_source.contains("ACTION_CORPSE_CLEANUP_CARRY"):
		failures.append("soldier action helper should name corpse cleanup carry")
	if not action_source.contains("ACTION_CORPSE_CLEANUP_THROW"):
		failures.append("soldier action helper should name corpse cleanup throw")
	if not action_source.contains("CARRY_ANCHOR_NAME"):
		failures.append("soldier action helper should expose a reusable carry anchor name")
	if not action_source.contains("static func get_or_create_carry_anchor"):
		failures.append("soldier action helper should provide a reusable carry anchor API")
	if not action_source.contains("CARRY_PAYLOAD_KIND_META"):
		failures.append("soldier action helper should name carried payload kinds")
	if not action_source.contains("CARRY_PAYLOAD_DEFINITIONS"):
		failures.append("soldier action helper should define reusable carry payload presets")
	if not action_source.contains("CARRY_PAYLOAD_KIND_CANNONBALL"):
		failures.append("soldier action helper should include a cannonball payload kind")
	if not action_source.contains("CARRY_PAYLOAD_KIND_TOOL"):
		failures.append("soldier action helper should include a tool payload kind")
	if not action_source.contains("CARRY_PAYLOAD_KIND_SUPPLY_CRATE"):
		failures.append("soldier action helper should include a supply crate payload kind")
	if not action_source.contains("static func get_carry_payload_definition"):
		failures.append("soldier action helper should expose carry payload definitions")
	if not action_source.contains("static func begin_typed_carry_payload"):
		failures.append("soldier action helper should begin carry payloads from reusable definitions")
	if not action_source.contains("static func begin_carry_payload"):
		failures.append("soldier action helper should provide a reusable carry payload API")
	if not action_source.contains("static func apply_carry_payload_follow"):
		failures.append("soldier action helper should provide reusable carry payload follow")
	if not action_source.contains("static func begin_action"):
		failures.append("soldier action helper should provide a reusable begin_action API")
	if not action_source.contains("static func finish_action"):
		failures.append("soldier action helper should provide a reusable finish_action API")
	_validate_soldier_action_definition_catalog(failures)
	var visual_source := FileAccess.get_file_as_string("res://scripts/entities/soldiers/soldier_visual_helper.gd")
	if visual_source.is_empty():
		failures.append("player corpse cleanup contract could not read soldier_visual_helper.gd")
		return
	if visual_source.contains("target_position := rest_position + Vector3(0.0, -0.04, -0.06)"):
		failures.append("corpse cleanup carry animation should not lower the actor pose without real animation")


static func _validate_soldier_action_definition_catalog(failures: Array[String]) -> void:
	var rows := SoldierActionHelper.get_action_rows()
	if rows.is_empty():
		failures.append("soldier action definition catalog should not be empty")
	var actions: Dictionary = {}
	for row in rows:
		var action_name := str(row.get(SoldierActionHelper.ACTION_DEF_NAME, "")).strip_edges()
		if action_name.is_empty():
			failures.append("soldier action definition missing name")
			continue
		if actions.has(action_name):
			failures.append("soldier action definition duplicate: %s" % action_name)
		actions[action_name] = row
		if str(row.get(SoldierActionHelper.ACTION_DEF_FAMILY, "")).strip_edges().is_empty():
			failures.append("soldier action definition %s missing family" % action_name)
		if str(row.get(SoldierActionHelper.ACTION_DEF_ANIMATION, "")).strip_edges().is_empty():
			failures.append("soldier action definition %s missing animation name" % action_name)
	var required_actions: Array[String] = [
		SoldierActionHelper.ACTION_CORPSE_CLEANUP_APPROACH,
		SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY,
		SoldierActionHelper.ACTION_CORPSE_CLEANUP_THROW,
		SoldierActionHelper.ACTION_CANNON_RELOAD,
	]
	for action_name in required_actions:
		if not actions.has(action_name):
			failures.append("soldier action definition missing action: %s" % action_name)
	if SoldierActionHelper.get_action_family(SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY) != SoldierActionHelper.ACTION_FAMILY_CORPSE_CLEANUP:
		failures.append("soldier action definition corpse carry family mismatch")
	if SoldierActionHelper.get_action_family(SoldierActionHelper.ACTION_CANNON_RELOAD) != SoldierActionHelper.ACTION_FAMILY_WEAPON_SUPPORT:
		failures.append("soldier action definition cannon reload family mismatch")
	var carry_definition := SoldierActionHelper.get_action_definition(SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY)
	if carry_definition.get(SoldierActionHelper.ACTION_DEF_LOCKS_AI, false) != true:
		failures.append("soldier action definition corpse carry should lock AI")
	var reload_definition := SoldierActionHelper.get_action_definition(SoldierActionHelper.ACTION_CANNON_RELOAD)
	if reload_definition.get(SoldierActionHelper.ACTION_DEF_LOCKS_AI, true) != false:
		failures.append("soldier action definition cannon reload should not lock AI")
	if SoldierActionHelper.get_default_animation_name(SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY) != SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY:
		failures.append("soldier action definition corpse carry animation name mismatch")


static func _run_transparent_vfx_render_priority_contract(failures: Array[String]) -> void:
	_expect_scene_loads("res://scenes/test/transparent_vfx_render_harness.tscn", "transparent VFX render harness should load", failures)
	_expect_file_contains("res://resources/materials/water.tres", "render_priority = 0", "water material should stay at transparent render priority 0", failures)
	_expect_file_contains("res://scenes/effects/ship_wake_trail.tscn", "render_priority = 1", "wake trail should render just above ocean water", failures)
	_expect_file_contains("res://scenes/effects/water_blast.tscn", "render_priority = 4", "water blast floor foam should render above ocean/wake", failures)
	_expect_file_contains("res://scenes/effects/water_blast.tscn", "render_priority = 5", "water blast mist should render above ocean/wake", failures)
	_expect_file_contains("res://scenes/effects/water_blast.tscn", "render_priority = 6", "water blast spray should render above ocean/wake", failures)
	_expect_file_contains("res://scenes/effects/impact_puff.tscn", "render_priority = 12", "impact puff should render above water effects", failures)
	_expect_file_contains("res://scenes/effects/fire_effect.tscn", "render_priority = 17", "fire smoke should render above water without overpainting sails", failures)
	_expect_file_contains("res://scenes/effects/fire_effect.tscn", "render_priority = 18", "fire flames should render above water without overpainting sails", failures)
	_expect_file_contains("res://scenes/effects/fire_effect.tscn", "render_priority = 19", "fire sparks should render above water without overpainting sails", failures)
	_expect_file_contains("res://scenes/effects/fire_pot_explosion.tscn", "render_priority = 18", "fire pot explosion should render above water", failures)
	_expect_file_contains("res://scenes/effects/cannon_muzzle_smoke.tscn", "render_priority = 32", "muzzle smoke should keep its high foreground priority", failures)
	_expect_file_contains("res://scenes/effects/cannon_muzzle_smoke.tscn", "render_priority = 34", "muzzle flash should keep its high foreground priority", failures)


static func _expect_file_contains(path: String, needle: String, message: String, failures: Array[String]) -> void:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		failures.append("render priority contract could not read %s" % path)
		return
	if not source.contains(needle):
		failures.append(message)


static func _expect_scene_loads(path: String, message: String, failures: Array[String]) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append(message)
		return
	var instance := packed.instantiate()
	if not is_instance_valid(instance):
		failures.append("%s: instantiate failed" % message)
		return
	instance.free()


static func _run_player_cannon_slot_authoring_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/ships/player_ship.tscn") as PackedScene
	if packed == null:
		failures.append("player cannon slot authoring contract load failed")
		return
	var wrapper := Node3D.new()
	wrapper.name = "PlayerCannonSlotAuthoringContract"
	owner.add_child(wrapper)
	var player_ship := packed.instantiate() as Node3D
	if player_ship == null:
		failures.append("player cannon slot authoring contract instantiate failed")
		wrapper.queue_free()
		return
	wrapper.add_child(player_ship)
	await _wait_frames(owner, wait_frames_after_attach)

	var cannons_node := player_ship.find_child("Cannons", true, false) as Node3D
	if not is_instance_valid(cannons_node):
		failures.append("player cannon slot authoring missing Cannons node")
		wrapper.queue_free()
		return

	var front_marker := _find_cannon_slot_marker(player_ship, "CannonFront")
	var original_front_pos := Vector3.ZERO
	var original_front_cannon := cannons_node.get_node_or_null("CannonFront") as Node3D
	if is_instance_valid(original_front_cannon):
		original_front_pos = original_front_cannon.position
	if is_instance_valid(front_marker):
		front_marker.position += Vector3(0.37, 0.0, 0.23)
	else:
		failures.append("player cannon slot authoring missing editable CannonFront marker")

	var slot_transforms := ShipAuthoringHelper.get_named_cannon_slot_transforms(player_ship, cannons_node)
	for required_slot in ["CannonFront", "CannonLeft", "CannonRight", "CannonLeftExtra", "CannonRightExtra", "CannonLeftExtraRear", "CannonRightExtraForward"]:
		if not slot_transforms.has(required_slot):
			failures.append("player cannon slot authoring missing marker: %s" % required_slot)
	var summary: Dictionary = player_ship.call("get_ship_authoring_summary") if player_ship.has_method("get_ship_authoring_summary") else {}
	var marker_counts: Dictionary = summary.get("authoring_markers", {})
	if int(marker_counts.get("CannonSlots", 0)) < 7:
		failures.append("player cannon slot authoring summary should count seven cannon markers")

	var upgrade_manager := owner.get_node_or_null("/root/UpgradeManager")
	if not is_instance_valid(upgrade_manager) or not upgrade_manager.has_method("_apply_cannon"):
		failures.append("player cannon slot authoring missing UpgradeManager._apply_cannon")
		wrapper.queue_free()
		return
	upgrade_manager.call("_apply_cannon", player_ship, 5)
	await _wait_frames(owner, 1)

	for slot_name in slot_transforms.keys():
		var cannon := cannons_node.get_node_or_null(str(slot_name)) as Node3D
		if not is_instance_valid(cannon):
			failures.append("player cannon slot authoring did not spawn cannon: %s" % slot_name)
			continue
		var expected_transform: Transform3D = slot_transforms[slot_name]
		if cannon.position.distance_to(expected_transform.origin) > 0.01:
			failures.append("player cannon slot authoring position mismatch for %s: %s vs %s" % [slot_name, cannon.position, expected_transform.origin])
		if str(slot_name) == "CannonFront" and is_instance_valid(original_front_cannon) and cannon.position.distance_to(original_front_pos) < 0.1:
			failures.append("player cannon slot authoring should prefer moved CannonFront marker over existing cannon node")
		var expected_forward := -expected_transform.basis.z.normalized()
		var actual_forward := -cannon.transform.basis.z.normalized()
		if actual_forward.dot(expected_forward) < 0.99:
			failures.append("player cannon slot authoring rotation mismatch for %s" % slot_name)

	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _find_cannon_slot_marker(ship: Node, slot_name: String) -> Marker3D:
	for marker in ShipAuthoringHelper.get_authoring_markers(ship, "CannonSlots"):
		if marker is Marker3D and str(marker.name) == slot_name:
			return marker as Marker3D
	return null


static func _run_player_boarding_anchor_authoring_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/ships/player_ship.tscn") as PackedScene
	if packed == null:
		failures.append("player boarding anchor authoring contract load failed")
		return
	var wrapper := Node3D.new()
	wrapper.name = "PlayerBoardingAnchorAuthoringContract"
	owner.add_child(wrapper)
	var player_ship := packed.instantiate() as Node3D
	if player_ship == null:
		failures.append("player boarding anchor authoring contract instantiate failed")
		wrapper.queue_free()
		return
	wrapper.add_child(player_ship)
	await _wait_frames(owner, wait_frames_after_attach)

	var markers := ShipAuthoringHelper.get_authoring_markers(player_ship, "BoardingAnchors")
	var marker_names := {}
	for marker in markers:
		marker_names[str(marker.name)] = marker
	for required_anchor in ["RightForward", "RightMid", "RightRear", "LeftForward", "LeftMid", "LeftRear", "Bow", "Stern"]:
		if not marker_names.has(required_anchor):
			failures.append("player boarding anchor authoring missing marker: %s" % required_anchor)

	var summary: Dictionary = player_ship.call("get_ship_authoring_summary") if player_ship.has_method("get_ship_authoring_summary") else {}
	var marker_counts: Dictionary = summary.get("authoring_markers", {})
	if int(marker_counts.get("BoardingAnchors", 0)) < 8:
		failures.append("player boarding anchor authoring summary should count eight boarding markers")

	var right_anchor_local: Vector3 = player_ship.call("_get_boarding_rope_source_anchor_local", 1.0, 0.0)
	var left_anchor_local: Vector3 = player_ship.call("_get_boarding_rope_source_anchor_local", -1.0, 0.0)
	var right_mid := marker_names.get("RightMid", null) as Node3D
	var left_mid := marker_names.get("LeftMid", null) as Node3D
	if is_instance_valid(right_mid) and right_anchor_local.distance_to(player_ship.to_local(right_mid.global_position)) > 0.01:
		failures.append("player boarding anchor authoring should use RightMid marker")
	if is_instance_valid(left_mid) and left_anchor_local.distance_to(player_ship.to_local(left_mid.global_position)) > 0.01:
		failures.append("player boarding anchor authoring should use LeftMid marker")

	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _run_player_crew_slot_authoring_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/ships/player_ship.tscn") as PackedScene
	if packed == null:
		failures.append("player crew slot authoring contract load failed")
		return
	var wrapper := Node3D.new()
	wrapper.name = "PlayerCrewSlotAuthoringContract"
	owner.add_child(wrapper)
	var player_ship := packed.instantiate() as Node3D
	if player_ship == null:
		failures.append("player crew slot authoring contract instantiate failed")
		wrapper.queue_free()
		return
	wrapper.add_child(player_ship)
	await _wait_frames(owner, wait_frames_after_attach)

	var soldiers_node := player_ship.get_node_or_null("Soldiers") as Node3D
	if not is_instance_valid(soldiers_node):
		failures.append("player crew slot authoring missing Soldiers node")
		wrapper.queue_free()
		return

	var markers := ShipAuthoringHelper.get_authoring_markers(player_ship, "CrewSlots")
	var marker_names := {}
	for marker in markers:
		marker_names[str(marker.name)] = marker
	for required_slot in ["CrewForwardLeft", "CrewForwardRight", "CrewMidLeft", "CrewMidRight", "CrewRearLeft", "CrewRearRight", "CrewSternLeft", "CrewSternRight"]:
		if not marker_names.has(required_slot):
			failures.append("player crew slot authoring missing marker: %s" % required_slot)

	var summary: Dictionary = player_ship.call("get_ship_authoring_summary") if player_ship.has_method("get_ship_authoring_summary") else {}
	var marker_counts: Dictionary = summary.get("authoring_markers", {})
	if int(marker_counts.get("CrewSlots", 0)) < 8:
		failures.append("player crew slot authoring summary should count eight crew markers")

	var slot_transforms := ShipAuthoringHelper.get_crew_slot_transforms(player_ship, soldiers_node)
	if slot_transforms.size() < 8:
		failures.append("player crew slot authoring helper should expose eight crew transforms")
	var player_deck_height := float(player_ship.get("deck_height")) if player_ship.get("deck_height") != null else 0.4
	for slot_transform in slot_transforms:
		if absf(slot_transform.origin.y - player_deck_height) > 0.05:
			failures.append("player crew slot authoring y should match deck_height: %.2f vs %.2f" % [slot_transform.origin.y, player_deck_height])
			break
	var occupied_slots := {}
	for child in soldiers_node.get_children():
		var soldier := child as Node3D
		if not is_instance_valid(soldier):
			continue
		for index in range(slot_transforms.size()):
			var expected_pos: Vector3 = slot_transforms[index].origin
			if soldier.position.distance_to(expected_pos) <= 0.05:
				occupied_slots[index] = true
				break
	if occupied_slots.size() < 5:
		failures.append("player crew slot authoring should place initial and spawned crew on slots, occupied=%d" % occupied_slots.size())

	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _run_support_ship_spawn_template_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/ships/player_ship.tscn") as PackedScene
	if packed == null:
		failures.append("support ship spawn template contract load failed")
		return
	var wrapper := Node3D.new()
	wrapper.name = "SupportShipSpawnTemplateContract"
	owner.add_child(wrapper)
	var player_ship := packed.instantiate() as Node3D
	if player_ship == null:
		failures.append("support ship spawn template contract player instantiate failed")
		wrapper.queue_free()
		return
	wrapper.add_child(player_ship)
	await _wait_frames(owner, wait_frames_after_attach)

	player_ship.set("support_fleet_limit", 1)
	if not player_ship.has_method("_spawn_or_repair_ally"):
		failures.append("support ship spawn template missing player spawn method")
		wrapper.queue_free()
		return
	player_ship.call("_spawn_or_repair_ally")
	await _wait_frames(owner, wait_frames_after_attach + 8)

	var spawned_support: Node = null
	for child in wrapper.get_children():
		if child == player_ship:
			continue
		if child.get_meta("support_fleet_ship", false) == true:
			spawned_support = child
			break
	if not is_instance_valid(spawned_support):
		failures.append("support ship spawn template did not create support ship child")
		wrapper.queue_free()
		return
	if spawned_support.scene_file_path != "res://scenes/ships/support_ship.tscn":
		failures.append("support ship spawn should instantiate support_ship.tscn, got %s" % spawned_support.scene_file_path)
	if str(spawned_support.get_script().resource_path) != "res://scripts/entities/ships/support_ship.gd":
		failures.append("support ship spawn should use support_ship.gd")
	if spawned_support.get("team") != "player":
		failures.append("support ship spawn team should be player")
	if spawned_support.get_meta("support_fleet_ship", false) != true:
		failures.append("support ship spawn missing support_fleet_ship meta")
	if not spawned_support.has_method("get_ally_ship_role") or str(spawned_support.call("get_ally_ship_role")) != ShipAllyRoleHelper.ROLE_SUPPORT_FLEET:
		failures.append("support ship spawn should be tagged as support_fleet role")
	if ShipAllyRoleHelper.is_captured_minion(spawned_support):
		failures.append("support ship spawn should not consume captured-minion role slots")
	if not spawned_support.has_method("sync_sail_furl_with_flagship"):
		failures.append("support ship should mirror flagship sail furl state")
	else:
		player_ship.call("set_sail_furled", true)
		spawned_support.call("sync_sail_furl_with_flagship", 1.0)
		if spawned_support.get("sail_furled") != true:
			failures.append("support ship did not inherit flagship furled sail state")
		if float(spawned_support.get("sail_deployed_ratio")) >= 0.99:
			failures.append("support ship should reduce sail deployment while flagship is furled")
		player_ship.call("set_sail_furled", false)

	var marker_counts: Dictionary = ShipAuthoringHelper.build_summary(spawned_support).get("authoring_markers", {})
	if int(marker_counts.get("CannonSlots", 0)) < 3:
		failures.append("support ship should expose three authored cannon slots")
	if int(marker_counts.get("BoardingAnchors", 0)) < 8:
		failures.append("support ship should expose eight authored boarding anchors")
	if int(marker_counts.get("CrewSlots", 0)) < 6:
		failures.append("support ship should expose six authored crew slots")

	var cannon_slots := ShipAuthoringHelper.get_named_cannon_slot_transforms(spawned_support, spawned_support)
	var front_cannon := spawned_support.get_node_or_null("FleetCannon_0") as Node3D
	if is_instance_valid(front_cannon) and cannon_slots.has("CannonFront"):
		var front_slot: Transform3D = cannon_slots["CannonFront"]
		if front_cannon.position.distance_to(front_slot.origin) > 0.01:
			failures.append("support ship front cannon should use authored CannonFront slot")

	var soldiers_node := spawned_support.get_node_or_null("Soldiers") as Node3D
	if is_instance_valid(soldiers_node):
		var crew_slots := ShipAuthoringHelper.get_crew_slot_transforms(spawned_support, soldiers_node)
		var occupied_slots := {}
		for child in soldiers_node.get_children():
			var soldier := child as Node3D
			if not is_instance_valid(soldier):
				continue
			for index in range(crew_slots.size()):
				var expected_pos: Vector3 = crew_slots[index].origin
				if soldier.position.distance_to(expected_pos) <= 0.05:
					occupied_slots[index] = true
					break
		if occupied_slots.size() < 5:
			failures.append("support ship spawned crew should use authored CrewSlots, occupied=%d" % occupied_slots.size())

	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _run_ship_ally_role_contract(failures: Array[String]) -> void:
	var rows := ShipAllyRoleHelper.get_role_rows()
	if rows.is_empty():
		failures.append("ship ally role contract role table should not be empty")
	var roles: Dictionary = {}
	for row in rows:
		var role_name := str(row.get(ShipAllyRoleHelper.ROLE_DEF_NAME, "")).strip_edges()
		if role_name.is_empty():
			failures.append("ship ally role contract row missing role name")
			continue
		if roles.has(role_name):
			failures.append("ship ally role contract duplicate role: %s" % role_name)
		roles[role_name] = row
		if str(row.get(ShipAllyRoleHelper.ROLE_DEF_TEAM, "")).strip_edges().is_empty():
			failures.append("ship ally role contract %s missing team" % role_name)
	for role_name in [
		ShipAllyRoleHelper.ROLE_PLAYER_FLAGSHIP,
		ShipAllyRoleHelper.ROLE_SUPPORT_FLEET,
		ShipAllyRoleHelper.ROLE_CAPTURED_MINION,
	]:
		if not roles.has(role_name):
			failures.append("ship ally role contract missing role: %s" % role_name)
	if ShipAllyRoleHelper.role_consumes_capture_slot(ShipAllyRoleHelper.ROLE_PLAYER_FLAGSHIP):
		failures.append("player flagship should not consume capture slots")
	if ShipAllyRoleHelper.role_consumes_capture_slot(ShipAllyRoleHelper.ROLE_SUPPORT_FLEET):
		failures.append("support fleet should not consume capture slots")
	if not ShipAllyRoleHelper.role_consumes_capture_slot(ShipAllyRoleHelper.ROLE_CAPTURED_MINION):
		failures.append("captured minion should consume capture slots")

	var support := MockAllyRoleShip.new()
	ShipAllyRoleHelper.mark_support_ship(support)
	support.add_to_group("captured_minion")
	if ShipAllyRoleHelper.get_ally_role(support) != ShipAllyRoleHelper.ROLE_SUPPORT_FLEET:
		failures.append("explicit support role should win over legacy captured_minion group")
	if ShipAllyRoleHelper.ship_consumes_capture_slot(support):
		failures.append("support role should not consume capture slot even when legacy grouped")

	var legacy_support := MockAllyRoleShip.new()
	legacy_support.set_meta(ShipAllyRoleHelper.LEGACY_SUPPORT_META, true)
	if ShipAllyRoleHelper.get_ally_role(legacy_support) != ShipAllyRoleHelper.ROLE_SUPPORT_FLEET:
		failures.append("legacy support meta should resolve to support_fleet")

	var captured := MockAllyRoleShip.new()
	captured.add_to_group("captured_minion")
	if ShipAllyRoleHelper.get_ally_role(captured) != ShipAllyRoleHelper.ROLE_CAPTURED_MINION:
		failures.append("captured_minion group should resolve to captured role")
	if not ShipAllyRoleHelper.ship_consumes_capture_slot(captured):
		failures.append("captured role should consume capture slot")

	var flagship := MockAllyRoleShip.new()
	flagship.is_player_controlled = true
	if ShipAllyRoleHelper.get_ally_role(flagship) != ShipAllyRoleHelper.ROLE_PLAYER_FLAGSHIP:
		failures.append("player controlled ship should resolve to flagship role")

	var role_ships: Array = [support, legacy_support, captured, flagship]
	if ShipAllyRoleHelper.count_capture_slot_minions(role_ships) != 1:
		failures.append("ship ally role capture slot count should include only captured minions")
	for ship_variant in role_ships:
		var ship := ship_variant as Node
		if is_instance_valid(ship):
			ship.free()


static func _run_hull_authoring_marker_contract(failures: Array[String]) -> void:
	var hull_checks := [
		{
			"path": "res://scenes/ships/hulls/panokseon_hull.tscn",
			"label": "panokseon hull",
			"cannons": 7,
			"weapon_slots": [],
			"anchors": 8,
			"crew": 8,
			"large_crew": true,
		},
		{
			"path": "res://scenes/ships/hulls/maengseon_hull.tscn",
			"label": "maengseon hull",
			"cannons": 3,
			"weapon_slots": [],
			"anchors": 8,
			"crew": 6,
			"large_crew": false,
		},
		{
			"path": "res://scenes/ships/hulls/atakebune_hull.tscn",
			"label": "atakebune hull",
			"cannons": 7,
			"weapon_slots": ["SingigeonFront"],
			"anchors": 8,
			"crew": 8,
			"large_crew": true,
		},
		{
			"path": "res://scenes/ships/hulls/geobukseon_hull.tscn",
			"label": "geobukseon hull",
			"cannons": 7,
			"weapon_slots": [],
			"anchors": 8,
			"crew": 8,
			"large_crew": true,
		},
		{
			"path": "res://scenes/ships/hulls/kobayabune_hull.tscn",
			"label": "kobayabune hull",
			"cannons": 3,
			"weapon_slots": [],
			"anchors": 8,
			"crew": 6,
			"large_crew": false,
		},
		{
			"path": "res://scenes/ships/hulls/sekibune_hull.tscn",
			"label": "sekibune hull",
			"cannons": 3,
			"weapon_slots": [],
			"anchors": 8,
			"crew": 6,
			"large_crew": false,
		},
		{
			"path": "res://scenes/ships/hulls/sekibune_melee_hull.tscn",
			"label": "sekibune melee hull",
			"cannons": 3,
			"weapon_slots": [],
			"anchors": 8,
			"crew": 6,
			"large_crew": false,
		},
	]

	for check in hull_checks:
		var scene_path := str(check["path"])
		var label := str(check["label"])
		var packed := load(scene_path) as PackedScene
		if packed == null:
			failures.append("hull authoring contract load failed: %s" % scene_path)
			continue
		var hull_root := packed.instantiate()
		if hull_root == null:
			failures.append("hull authoring contract instantiate failed: %s" % scene_path)
			continue
		var weapon_slots: Array = check["weapon_slots"]
		_expect_no_persisted_authoring_visuals(scene_path, label, failures)
		var marker_counts: Dictionary = ShipAuthoringHelper.build_summary(hull_root).get("authoring_markers", {})
		_expect_min_authoring_count(marker_counts, label, "DeckArea", 1, failures)
		_expect_min_authoring_count(marker_counts, label, "CannonSlots", int(check["cannons"]), failures)
		_expect_min_authoring_count(marker_counts, label, "WeaponSlots", weapon_slots.size(), failures)
		_expect_min_authoring_count(marker_counts, label, "BoardingAnchors", int(check["anchors"]), failures)
		_expect_min_authoring_count(marker_counts, label, "CrewSlots", int(check["crew"]), failures)
		_expect_authoring_marker_names(hull_root, label, "CannonSlots", ["CannonFront", "CannonLeft", "CannonRight"], failures)
		_expect_authoring_marker_names(hull_root, label, "WeaponSlots", weapon_slots, failures)
		_expect_authoring_marker_names(hull_root, label, "BoardingAnchors", ["RightForward", "RightMid", "RightRear", "LeftForward", "LeftMid", "LeftRear", "Bow", "Stern"], failures)
		var required_crew_slots := ["CrewForwardLeft", "CrewForwardRight", "CrewMidLeft", "CrewMidRight", "CrewRearLeft", "CrewRearRight"]
		if check["large_crew"] == true:
			required_crew_slots.append_array(["CrewSternLeft", "CrewSternRight"])
		_expect_authoring_marker_names(hull_root, label, "CrewSlots", required_crew_slots, failures)
		_expect_authoring_visualizer(hull_root, label, failures)
		_expect_authoring_marker_layout(hull_root, label, failures)
		_expect_runtime_authoring_visuals_absent(hull_root, label, failures)
		hull_root.free()


static func _run_ship_blueprint_weapon_loadout_contract(failures: Array[String]) -> void:
	var all_stats := _load_ship_stats_dictionary(failures)
	if all_stats.is_empty():
		return

	var combat_profiles := _load_combat_profiles(all_stats, failures)
	_validate_combat_profiles(combat_profiles, failures)
	var profiles := _load_weapon_profiles(all_stats, failures)
	_validate_weapon_profiles(profiles, failures)
	var ship_archetypes := _load_ship_archetypes(all_stats, failures)
	_validate_ship_archetypes(ship_archetypes, combat_profiles, profiles, failures)
	_validate_ship_blueprint_crew_contracts(all_stats, ship_archetypes, combat_profiles, failures)
	for type_name_variant in all_stats.keys():
		var type_name := str(type_name_variant)
		if _is_ship_blueprint_meta_key(type_name):
			continue
		var stats_variant: Variant = all_stats[type_name_variant]
		if typeof(stats_variant) != TYPE_DICTIONARY:
			failures.append("ship blueprint %s should be a Dictionary" % type_name)
			continue
		var stats := stats_variant as Dictionary
		_validate_ship_archetype_reference(type_name, stats, ship_archetypes, failures)
		var archetyped_stats := ShipBlueprintHelper.resolve_ship_archetype(stats, ship_archetypes)
		_validate_combat_profile_reference(type_name, archetyped_stats, combat_profiles, failures)
		var resolved_stats := ShipBlueprintHelper.resolve_combat_profile(archetyped_stats, combat_profiles)
		_validate_combat_runtime_fields("ship blueprint %s" % type_name, resolved_stats, failures)
		if not resolved_stats.has("weapon_loadout"):
			continue
		var loadout_variant: Variant = resolved_stats.get("weapon_loadout", [])
		if typeof(loadout_variant) != TYPE_ARRAY:
			failures.append("ship blueprint %s weapon_loadout should be an Array" % type_name)
			continue
		var loadout := loadout_variant as Array
		_validate_weapon_loadout_entries(type_name, resolved_stats, loadout, profiles, failures)


static func _validate_ship_blueprint_crew_contracts(all_stats: Dictionary, ship_archetypes: Dictionary, combat_profiles: Dictionary, failures: Array[String]) -> void:
	var expected_crew_counts := {
		"kobayabune_melee": 4,
		"sekibune_melee": 6,
		"sekibune_cannon": 6,
		"atakebune_mid": 8,
		"atakebune_final": 8,
	}
	var archetype_variant: Variant = all_stats.get(ShipBlueprintHelper.SHIP_ARCHETYPES, {})
	if typeof(archetype_variant) == TYPE_DICTIONARY:
		for archetype_name_variant in (archetype_variant as Dictionary).keys():
			var archetype_stats: Variant = (archetype_variant as Dictionary)[archetype_name_variant]
			if typeof(archetype_stats) == TYPE_DICTIONARY and (archetype_stats as Dictionary).has("boarders"):
				failures.append("ship blueprint archetype %s should not use legacy boarders" % str(archetype_name_variant))

	for type_name_variant in all_stats.keys():
		var type_name := str(type_name_variant)
		if _is_ship_blueprint_meta_key(type_name):
			continue
		var stats_variant: Variant = all_stats[type_name_variant]
		if typeof(stats_variant) != TYPE_DICTIONARY:
			continue
		var stats := stats_variant as Dictionary
		if stats.has("boarders"):
			failures.append("ship blueprint %s should not use legacy boarders" % type_name)
		if not expected_crew_counts.has(type_name):
			continue
		var resolved := ShipBlueprintHelper.resolve_ship_archetype(stats, ship_archetypes)
		resolved = ShipBlueprintHelper.resolve_combat_profile(resolved, combat_profiles)
		var actual_count := _count_crew_composition(resolved)
		var expected_count: int = int(expected_crew_counts[type_name])
		if actual_count != expected_count:
			failures.append("ship blueprint %s crew_composition should total %d, got %d" % [type_name, expected_count, actual_count])


static func _count_crew_composition(stats: Dictionary) -> int:
	var composition_variant: Variant = stats.get("crew_composition", {})
	if typeof(composition_variant) != TYPE_DICTIONARY:
		return 0
	var total := 0
	for count_variant in (composition_variant as Dictionary).values():
		total += maxi(0, int(count_variant))
	return total


static func _run_level_progression_contract(failures: Array[String]) -> void:
	var root := _load_json_dictionary(LEVEL_PROGRESSION_DATA_PATH, "level progression", failures)
	if root.is_empty():
		return
	var levels_variant: Variant = root.get("levels", {})
	if typeof(levels_variant) != TYPE_DICTIONARY:
		failures.append("level progression levels should be a Dictionary")
		return
	for level_key_variant in (levels_variant as Dictionary).keys():
		var row_variant: Variant = (levels_variant as Dictionary)[level_key_variant]
		if typeof(row_variant) != TYPE_DICTIONARY:
			failures.append("level progression level %s should be a Dictionary" % str(level_key_variant))
			continue
		var row := row_variant as Dictionary
		if row.has("boarders"):
			failures.append("level progression level %s should not use legacy boarders" % str(level_key_variant))


static func _load_ship_stats_dictionary(failures: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(ShipBlueprintHelper.STATS_PATH):
		failures.append("ship blueprint loadout contract missing %s" % ShipBlueprintHelper.STATS_PATH)
		return {}
	var file := FileAccess.open(ShipBlueprintHelper.STATS_PATH, FileAccess.READ)
	if file == null:
		failures.append("ship blueprint loadout contract could not open %s" % ShipBlueprintHelper.STATS_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("ship blueprint loadout contract expected ship_stats Dictionary")
		return {}
	return parsed as Dictionary


static func _run_enemy_spawn_rules_contract(failures: Array[String]) -> void:
	var root := _load_json_dictionary(ENEMY_SPAWN_RULES_DATA_PATH, "enemy spawn rules", failures)
	if root.is_empty():
		return

	var all_stats := _load_ship_stats_dictionary(failures)
	var ship_types := _collect_ship_type_references(all_stats)
	var authoring_palette := _load_json_dictionary(AUTHORING_PALETTE_DATA_PATH, "authoring palette", failures)
	var combat_profiles := ShipBlueprintHelper.get_combat_profiles(all_stats)
	var movement_intents := _collect_palette_catalog_entries_by_id(authoring_palette.get("movement_intents", []))
	var spawn_recipes := EnemySpawnerFleetHelper.parse_spawn_recipes(root.get(EnemySpawnerFleetHelper.SPAWN_RECIPES, {}))
	if spawn_recipes.is_empty():
		failures.append("enemy spawn rules should define at least one spawn_recipe")
	var encounter_profiles := EnemySpawnerFleetHelper.parse_encounter_profiles(root.get(EnemySpawnerFleetHelper.ENCOUNTER_PROFILES, {}))
	if encounter_profiles.is_empty():
		failures.append("enemy spawn rules should define at least one encounter_profile")
	var scenario_triggers := EnemySpawnerFleetHelper.parse_scenario_triggers(root.get(EnemySpawnerFleetHelper.SCENARIO_TRIGGERS, []))
	if scenario_triggers.is_empty():
		failures.append("enemy spawn rules should define at least one scenario_trigger")

	_validate_spawn_recipe_definitions(root.get(EnemySpawnerFleetHelper.SPAWN_RECIPES, {}), spawn_recipes, all_stats, failures)

	var formation_variant: Variant = root.get("formation", {})
	if typeof(formation_variant) != TYPE_DICTIONARY:
		failures.append("enemy spawn rules formation should be a Dictionary")
		return
	var formation: Dictionary = formation_variant as Dictionary
	var fleet_templates_variant: Variant = formation.get("fleet_templates", {})
	if typeof(fleet_templates_variant) != TYPE_DICTIONARY:
		failures.append("enemy spawn rules formation.fleet_templates should be a Dictionary")
		return
	var fleet_templates: Dictionary = fleet_templates_variant as Dictionary
	_validate_fleet_template_recipe_references(fleet_templates, spawn_recipes, failures)
	var parsed_templates := EnemySpawnerFleetHelper.parse_fleet_templates(fleet_templates, spawn_recipes)
	for required_class in ["light", "mixed", "heavy"]:
		if not parsed_templates.has(required_class):
			failures.append("enemy spawn rules missing parsed fleet class: %s" % required_class)
	_validate_parsed_fleet_templates(parsed_templates, all_stats, failures)
	_validate_encounter_profile_definitions(root.get(EnemySpawnerFleetHelper.ENCOUNTER_PROFILES, {}), encounter_profiles, parsed_templates, failures)
	_validate_formation_encounter_profile(formation, encounter_profiles, failures)
	var resolved_progression := EnemySpawnerFleetHelper.resolve_fleet_progression(formation, encounter_profiles)
	_validate_fleet_progression("enemy spawn rules active encounter progression", resolved_progression, parsed_templates, failures)
	_validate_scenario_trigger_definitions(root.get(EnemySpawnerFleetHelper.SCENARIO_TRIGGERS, []), scenario_triggers, encounter_profiles, parsed_templates, spawn_recipes, all_stats, combat_profiles, movement_intents, failures)
	var elite_variant: Variant = root.get("elite", {})
	if typeof(elite_variant) != TYPE_DICTIONARY:
		failures.append("enemy spawn rules elite should be a Dictionary")
	else:
		var elite_rules: Dictionary = elite_variant as Dictionary
		var wave_counts_variant: Variant = elite_rules.get("wave_counts", [])
		if typeof(wave_counts_variant) != TYPE_ARRAY:
			failures.append("enemy spawn rules elite.wave_counts should be an Array")
		else:
			var wave_counts: Array = wave_counts_variant as Array
			if wave_counts.size() < int(elite_rules.get("max_elite_spawns", 0)):
				failures.append("enemy spawn rules elite.wave_counts should cover every elite wave")
			if wave_counts.size() >= 3 and (int(wave_counts[1]) < 2 or int(wave_counts[2]) < 2):
				failures.append("enemy spawn rules 5:00 and 7:30 elite waves should spawn at least two mid bosses")
	var boss_templates_variant: Variant = root.get(EnemySpawnerFleetHelper.BOSS_WAVE_TEMPLATES, {})
	var boss_template_mid_counts: Dictionary = {}
	var boss_template_final_counts: Dictionary = {}
	if typeof(boss_templates_variant) != TYPE_DICTIONARY:
		failures.append("enemy spawn rules boss_wave_templates should be a Dictionary")
	else:
		var boss_templates: Dictionary = boss_templates_variant as Dictionary
		for required_template in ["mid_single", "mid_pair", "final"]:
			if not boss_templates.has(required_template):
				failures.append("enemy spawn rules boss_wave_templates missing template: %s" % required_template)
		for template_id_variant in boss_templates.keys():
			var template_id := str(template_id_variant).strip_edges()
			var template_variant: Variant = boss_templates[template_id_variant]
			if template_id.is_empty():
				failures.append("enemy spawn rules boss_wave_templates should not use empty template ids")
				continue
			if typeof(template_variant) != TYPE_DICTIONARY:
				failures.append("enemy spawn rules boss_wave_templates.%s should be a Dictionary" % template_id)
				continue
			var template: Dictionary = template_variant as Dictionary
			var template_ships_variant: Variant = template.get("ships", [])
			if typeof(template_ships_variant) != TYPE_ARRAY:
				failures.append("enemy spawn rules boss_wave_templates.%s.ships should be an Array" % template_id)
				continue
			var template_ships: Array = template_ships_variant as Array
			if template_ships.is_empty():
				failures.append("enemy spawn rules boss_wave_templates.%s.ships should not be empty" % template_id)
			var mid_boss_count := 0
			var final_boss_count := 0
			for ship_index in range(template_ships.size()):
				var ship_variant: Variant = template_ships[ship_index]
				if typeof(ship_variant) != TYPE_DICTIONARY:
					failures.append("enemy spawn rules boss_wave_templates.%s.ships[%d] should be a Dictionary" % [template_id, ship_index])
					continue
				var ship_info: Dictionary = ship_variant as Dictionary
				var ship_type_name := str(ship_info.get("ship_type", "")).strip_edges()
				var ship_count: int = maxi(1, int(ship_info.get("count", 1)))
				if ship_type_name.is_empty():
					failures.append("enemy spawn rules boss_wave_templates.%s.ships[%d].ship_type should be non-empty" % [template_id, ship_index])
				elif not ship_types.has(ship_type_name):
					failures.append("enemy spawn rules boss_wave_templates.%s.ships[%d] unknown ship_type: %s" % [template_id, ship_index, ship_type_name])
				if ship_type_name == "atakebune_mid":
					mid_boss_count += ship_count
				if ship_type_name == "atakebune_final":
					final_boss_count += ship_count
			boss_template_mid_counts[template_id] = mid_boss_count
			boss_template_final_counts[template_id] = final_boss_count
			if template_id == "mid_single" and mid_boss_count < 1:
				failures.append("enemy spawn rules mid_single should spawn at least one mid boss")
			if template_id == "mid_pair" and mid_boss_count < 2:
				failures.append("enemy spawn rules mid_pair should spawn at least two mid bosses")
			if template_id == "final":
				if not bool(template.get("final", false)):
					failures.append("enemy spawn rules final template should set final=true")
				if not bool(template.get("stop_regular_spawns", false)):
					failures.append("enemy spawn rules final template should stop regular spawns")
				if final_boss_count < 1:
					failures.append("enemy spawn rules final template should spawn at least one final boss")

	var boss_progression_variant: Variant = root.get(EnemySpawnerFleetHelper.BOSS_PROGRESSION, {})
	if typeof(boss_progression_variant) != TYPE_DICTIONARY:
		failures.append("enemy spawn rules boss_progression should be a Dictionary")
	else:
		var boss_progression: Dictionary = boss_progression_variant as Dictionary
		if float(boss_progression.get("mid_start_time", -1.0)) < 0.0:
			failures.append("enemy spawn rules boss_progression.mid_start_time should be >= 0")
		if float(boss_progression.get("mid_interval", 0.0)) <= 0.0:
			failures.append("enemy spawn rules boss_progression.mid_interval should be > 0")
		var mid_sequence_variant: Variant = boss_progression.get("mid_sequence", [])
		if typeof(mid_sequence_variant) != TYPE_ARRAY:
			failures.append("enemy spawn rules boss_progression.mid_sequence should be an Array")
		else:
			var mid_sequence: Array = mid_sequence_variant as Array
			if mid_sequence.size() < 3:
				failures.append("enemy spawn rules boss_progression.mid_sequence should cover the three mid-boss beats")
			for sequence_index in range(mid_sequence.size()):
				var template_ref := str(mid_sequence[sequence_index]).strip_edges()
				if template_ref.is_empty():
					failures.append("enemy spawn rules boss_progression.mid_sequence[%d] should be non-empty" % sequence_index)
				elif not boss_template_mid_counts.has(template_ref):
					failures.append("enemy spawn rules boss_progression.mid_sequence[%d] unknown template: %s" % [sequence_index, template_ref])
				elif (sequence_index == 1 or sequence_index == 2) and int(boss_template_mid_counts[template_ref]) < 2:
					failures.append("enemy spawn rules second and third mid-boss beats should use a two-boss template")
		var final_template := str(boss_progression.get("final_template", "")).strip_edges()
		if final_template.is_empty():
			failures.append("enemy spawn rules boss_progression.final_template should be non-empty")
		elif not boss_template_final_counts.has(final_template):
			failures.append("enemy spawn rules boss_progression.final_template unknown template: %s" % final_template)
		elif int(boss_template_final_counts[final_template]) < 1:
			failures.append("enemy spawn rules boss_progression.final_template should spawn a final boss")
		if float(boss_progression.get("final_time", 0.0)) <= 0.0:
			failures.append("enemy spawn rules boss_progression.final_time should be > 0")
	var spawner_script := load("res://scripts/managers/enemy_spawner.gd") as Script
	if spawner_script == null:
		failures.append("enemy spawn rules contract could not load EnemySpawner script")
	else:
		var spawner = spawner_script.new()
		spawner.call("_apply_enemy_spawn_rules_root", root)
		var generated_waves_variant: Variant = spawner.get("boss_waves")
		if typeof(generated_waves_variant) != TYPE_ARRAY:
			failures.append("enemy spawn rules boss_progression should generate runtime boss_waves")
		else:
			var generated_waves: Array = generated_waves_variant as Array
			if generated_waves.size() < 4:
				failures.append("enemy spawn rules boss_progression should generate three mid waves and one final wave")
			var generated_wave_ids: Dictionary = {}
			for generated_wave_variant in generated_waves:
				if typeof(generated_wave_variant) != TYPE_DICTIONARY:
					continue
				var generated_wave: Dictionary = generated_wave_variant as Dictionary
				generated_wave_ids[str(generated_wave.get("id", ""))] = true
			for required_wave_id in ["mid_boss_1", "mid_boss_2", "mid_boss_3", "final_boss"]:
				if not generated_wave_ids.has(required_wave_id):
					failures.append("enemy spawn rules boss_progression did not generate wave: %s" % required_wave_id)
		spawner.free()
	_validate_mid_boss_escort_rules(root.get("mid_boss_escort", []), all_stats, failures)


static func _run_authoring_palette_contract(failures: Array[String]) -> void:
	var palette := _load_json_dictionary(AUTHORING_PALETTE_DATA_PATH, "authoring palette", failures)
	if palette.is_empty():
		return
	_validate_authoring_palette_block_schema(palette, failures)
	var all_stats := _load_ship_stats_dictionary(failures)
	if all_stats.is_empty():
		return
	var enemy_root := _load_json_dictionary(ENEMY_SPAWN_RULES_DATA_PATH, "enemy spawn rules", failures)
	if enemy_root.is_empty():
		return

	var ship_archetypes := ShipBlueprintHelper.get_ship_archetypes(all_stats)
	var ship_types := _collect_ship_type_references(all_stats)
	var weapon_profiles := ShipWeaponLoadoutHelper.get_weapon_profiles(all_stats)
	var combat_profiles := ShipBlueprintHelper.get_combat_profiles(all_stats)
	var spawn_recipes := EnemySpawnerFleetHelper.parse_spawn_recipes(enemy_root.get(EnemySpawnerFleetHelper.SPAWN_RECIPES, {}))
	var encounter_profiles := EnemySpawnerFleetHelper.parse_encounter_profiles(enemy_root.get(EnemySpawnerFleetHelper.ENCOUNTER_PROFILES, {}))
	var scenario_triggers := EnemySpawnerFleetHelper.parse_scenario_triggers(enemy_root.get(EnemySpawnerFleetHelper.SCENARIO_TRIGGERS, []))
	var trigger_references := _collect_scenario_trigger_references(scenario_triggers)

	var formation_variant: Variant = enemy_root.get("formation", {})
	if typeof(formation_variant) != TYPE_DICTIONARY:
		failures.append("authoring palette requires enemy spawn formation data")
		return
	var formation := formation_variant as Dictionary
	var fleet_templates_variant: Variant = formation.get("fleet_templates", {})
	if typeof(fleet_templates_variant) != TYPE_DICTIONARY:
		failures.append("authoring palette requires enemy spawn fleet_templates data")
		return
	var fleet_templates := fleet_templates_variant as Dictionary
	var parsed_templates := EnemySpawnerFleetHelper.parse_fleet_templates(fleet_templates, spawn_recipes)
	var recipe_fleet_classes := _build_spawn_recipe_fleet_class_index(fleet_templates)

	var archetype_ids := _validate_palette_reference_entries("authoring_palette.ship_archetypes", palette.get("ship_archetypes", []), ship_archetypes, failures)
	_validate_palette_coverage("authoring_palette.ship_archetypes", archetype_ids, ship_archetypes, failures)
	var ship_type_ids := _validate_palette_reference_entries("authoring_palette.ship_types", palette.get("ship_types", []), ship_types, failures)
	_validate_palette_coverage("authoring_palette.ship_types", ship_type_ids, ship_types, failures)
	_validate_palette_ship_type_entries(palette.get("ship_types", []), all_stats, ship_archetypes, failures)
	var weapon_ids := _validate_palette_reference_entries("authoring_palette.weapon_profiles", palette.get("weapon_profiles", []), weapon_profiles, failures)
	_validate_palette_coverage("authoring_palette.weapon_profiles", weapon_ids, weapon_profiles, failures)
	var combat_ids := _validate_palette_reference_entries("authoring_palette.combat_profiles", palette.get("combat_profiles", []), combat_profiles, failures)
	_validate_palette_coverage("authoring_palette.combat_profiles", combat_ids, combat_profiles, failures)
	_validate_palette_catalog_entries("authoring_palette.movement_intents", palette.get("movement_intents", []), failures)
	_validate_palette_movement_intent_entries(palette.get("movement_intents", []), failures)
	var recipe_ids := _validate_palette_reference_entries("authoring_palette.spawn_recipes", palette.get("spawn_recipes", []), spawn_recipes, failures)
	_validate_palette_coverage("authoring_palette.spawn_recipes", recipe_ids, spawn_recipes, failures)
	_validate_palette_spawn_recipe_entries(palette.get("spawn_recipes", []), recipe_fleet_classes, parsed_templates, failures)
	var fleet_class_ids := _validate_palette_reference_entries("authoring_palette.fleet_classes", palette.get("fleet_classes", []), parsed_templates, failures)
	_validate_palette_coverage("authoring_palette.fleet_classes", fleet_class_ids, parsed_templates, failures)
	_validate_palette_fleet_class_entries(palette.get("fleet_classes", []), spawn_recipes, recipe_fleet_classes, failures)
	var encounter_ids := _validate_palette_reference_entries("authoring_palette.encounter_profiles", palette.get("encounter_profiles", []), encounter_profiles, failures)
	_validate_palette_coverage("authoring_palette.encounter_profiles", encounter_ids, encounter_profiles, failures)
	var trigger_ids := _validate_palette_reference_entries("authoring_palette.scenario_triggers", palette.get("scenario_triggers", []), trigger_references, failures)
	_validate_palette_coverage("authoring_palette.scenario_triggers", trigger_ids, trigger_references, failures)


static func _run_scenario_action_authoring_negative_contract(failures: Array[String]) -> void:
	var combat_profiles := {
		"gunline": {},
	}
	var movement_intents := {
		"side_board": {
			"mode": "side",
		},
	}
	var cases := [
		{
			"label": "scenario action authoring negative unsupported action",
			"action_type": "spawn_fleet",
			"action": {
				"authoring": {
					"combat_profile": "gunline",
				},
			},
			"expected": "authoring metadata is only supported on spawn_ship or spawn_recipe",
		},
		{
			"label": "scenario action authoring negative non dictionary",
			"action_type": "spawn_ship",
			"action": {
				"authoring": ["gunline"],
			},
			"expected": "authoring should be a Dictionary",
		},
		{
			"label": "scenario action authoring negative empty",
			"action_type": "spawn_recipe",
			"action": {
				"authoring": {},
			},
			"expected": "authoring should include combat_profile or movement_intent",
		},
		{
			"label": "scenario action authoring negative combat profile",
			"action_type": "spawn_ship",
			"action": {
				"authoring": {
					"combat_profile": "missing_profile",
				},
			},
			"expected": "unknown authoring combat_profile: missing_profile",
		},
		{
			"label": "scenario action authoring negative mode without intent",
			"action_type": "spawn_ship",
			"action": {
				"authoring": {
					"combat_profile": "gunline",
					"movement_mode": "side",
				},
			},
			"expected": "movement_mode requires authoring movement_intent",
		},
		{
			"label": "scenario action authoring negative movement intent",
			"action_type": "spawn_ship",
			"action": {
				"authoring": {
					"movement_intent": "missing_intent",
				},
			},
			"expected": "unknown authoring movement_intent: missing_intent",
		},
		{
			"label": "scenario action authoring negative movement mode",
			"action_type": "spawn_ship",
			"action": {
				"authoring": {
					"movement_intent": "side_board",
					"movement_mode": "frontal",
				},
			},
			"expected": "authoring movement_mode mismatch: frontal != side",
		},
	]
	for case in cases:
		var local_failures: Array[String] = []
		_validate_scenario_action_authoring_meta(
			str(case["label"]),
			case["action"] as Dictionary,
			str(case["action_type"]),
			combat_profiles,
			movement_intents,
			local_failures
		)
		_expect_failure_contains(str(case["label"]), local_failures, str(case["expected"]), failures)

	var valid_failures: Array[String] = []
	_validate_scenario_action_authoring_meta(
		"scenario action authoring positive control",
		{
			"authoring": {
				"combat_profile": "gunline",
				"movement_intent": "side_board",
				"movement_mode": "side",
			},
		},
		"spawn_recipe",
		combat_profiles,
		movement_intents,
		valid_failures
	)
	if not valid_failures.is_empty():
		failures.append("scenario action authoring positive control should pass, got %s" % str(valid_failures))

	var integration_failures: Array[String] = []
	var parsed_triggers: Array[Dictionary] = []
	parsed_triggers.append({
		EnemySpawnerFleetHelper.ID: "bad_authoring_mode",
	})
	_validate_scenario_trigger_definitions(
		[
			{
				EnemySpawnerFleetHelper.ID: "bad_authoring_mode",
				EnemySpawnerFleetHelper.CONDITION: {
					EnemySpawnerFleetHelper.ELAPSED_TIME: 0.0,
				},
				EnemySpawnerFleetHelper.ACTIONS: [
					{
						EnemySpawnerFleetHelper.TYPE: "spawn_ship",
						EnemySpawnerFleetHelper.SHIP_TYPE: "demo_ship",
						"authoring": {
							"movement_intent": "side_board",
							"movement_mode": "frontal",
						},
					},
				],
			},
		],
		parsed_triggers,
		{},
		{},
		{},
		{
			"demo_ship": {},
		},
		combat_profiles,
		movement_intents,
		integration_failures
	)
	_expect_failure_contains(
		"scenario trigger authoring negative integration",
		integration_failures,
		"scenario_triggers[0].actions[0] authoring movement_mode mismatch: frontal != side",
		failures
	)


static func _expect_failure_contains(label: String, source_failures: Array[String], expected_fragment: String, failures: Array[String]) -> void:
	for failure in source_failures:
		if failure.contains(expected_fragment):
			return
	failures.append("%s did not produce expected failure containing '%s', got %s" % [label, expected_fragment, str(source_failures)])


static func _load_json_dictionary(path: String, label: String, failures: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		failures.append("%s missing %s" % [label, path])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("%s could not open %s" % [label, path])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("%s expected Dictionary: %s" % [label, path])
		return {}
	return parsed as Dictionary


static func _validate_palette_reference_entries(label: String, entries_variant: Variant, references: Dictionary, failures: Array[String]) -> Dictionary:
	var entry_ids: Dictionary = {}
	if typeof(entries_variant) != TYPE_ARRAY:
		failures.append("%s should be an Array" % label)
		return entry_ids
	var entries: Array = entries_variant as Array
	if entries.is_empty():
		failures.append("%s should include at least one entry" % label)
	for index in range(entries.size()):
		var entry_variant: Variant = entries[index]
		var entry_label := "%s[%d]" % [label, index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % entry_label)
			continue
		var entry := entry_variant as Dictionary
		var entry_id := str(entry.get(EnemySpawnerFleetHelper.ID, "")).strip_edges()
		if entry_id.is_empty():
			failures.append("%s missing id" % entry_label)
			continue
		if entry_ids.has(entry_id):
			failures.append("%s duplicate id: %s" % [entry_label, entry_id])
		entry_ids[entry_id] = true
		if not references.has(entry_id):
			failures.append("%s references unknown id: %s" % [entry_label, entry_id])
		_validate_palette_entry_shape(entry_label, entry, failures)
	return entry_ids


static func _validate_palette_entry_shape(label: String, entry: Dictionary, failures: Array[String]) -> void:
	var display_label := str(entry.get(EnemySpawnerFleetHelper.LABEL, "")).strip_edges()
	if display_label.is_empty():
		failures.append("%s missing label" % label)
	var tags_variant: Variant = entry.get("tags", [])
	if typeof(tags_variant) != TYPE_ARRAY:
		failures.append("%s tags should be an Array" % label)
		return
	var tags: Array = tags_variant as Array
	for tag_index in range(tags.size()):
		var tag := str(tags[tag_index]).strip_edges()
		if tag.is_empty():
			failures.append("%s tags[%d] should be non-empty" % [label, tag_index])


static func _validate_palette_coverage(label: String, entry_ids: Dictionary, references: Dictionary, failures: Array[String]) -> void:
	for id_variant in references.keys():
		var reference_id := str(id_variant).strip_edges()
		if reference_id.is_empty():
			continue
		if not entry_ids.has(reference_id):
			failures.append("%s missing palette entry for %s" % [label, reference_id])


static func _validate_authoring_palette_block_schema(palette: Dictionary, failures: Array[String]) -> void:
	var schema_version := int(palette.get("block_schema_version", 0))
	if schema_version != AUTHORING_PALETTE_BLOCK_SCHEMA_VERSION:
		failures.append("authoring_palette block_schema_version should be %d" % AUTHORING_PALETTE_BLOCK_SCHEMA_VERSION)
	var blocks_variant: Variant = palette.get("assembly_blocks", [])
	if typeof(blocks_variant) != TYPE_ARRAY:
		failures.append("authoring_palette.assembly_blocks should be an Array")
		return
	var blocks: Array = blocks_variant as Array
	if blocks.is_empty():
		failures.append("authoring_palette.assembly_blocks should include at least one block")
	var ids_seen: Dictionary = {}
	var catalogs_seen: Dictionary = {}
	for index in range(blocks.size()):
		var block_variant: Variant = blocks[index]
		var label := "authoring_palette.assembly_blocks[%d]" % index
		if typeof(block_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		var block := block_variant as Dictionary
		var block_id := str(block.get("id", "")).strip_edges()
		var catalog := str(block.get("catalog", "")).strip_edges()
		var display_label := str(block.get("label", "")).strip_edges()
		var slot := str(block.get("slot", "")).strip_edges()
		var kind := str(block.get("kind", "")).strip_edges()
		var source_path := str(block.get("source_path", "")).strip_edges()
		if block_id.is_empty():
			failures.append("%s missing id" % label)
		elif ids_seen.has(block_id):
			failures.append("%s duplicate id: %s" % [label, block_id])
		else:
			ids_seen[block_id] = true
		if display_label.is_empty():
			failures.append("%s missing label" % label)
		if slot.is_empty():
			failures.append("%s missing slot" % label)
		if catalog.is_empty():
			failures.append("%s missing catalog" % label)
		elif not AUTHORING_PALETTE_CATALOGS.has(catalog):
			failures.append("%s unknown catalog: %s" % [label, catalog])
		else:
			if catalogs_seen.has(catalog):
				failures.append("%s duplicate catalog block: %s" % [label, catalog])
			catalogs_seen[catalog] = true
			if typeof(palette.get(catalog, null)) != TYPE_ARRAY:
				failures.append("%s catalog should point to a palette Array: %s" % [label, catalog])
		if not AUTHORING_BLOCK_KINDS.has(kind):
			failures.append("%s unknown kind: %s" % [label, kind])
		if not AUTHORING_BLOCK_SOURCE_PATHS.has(source_path):
			failures.append("%s unknown source_path: %s" % [label, source_path])
		if kind == "action":
			var action_type := str(block.get("action_type", "")).strip_edges()
			if not AUTHORING_BLOCK_ACTION_TYPES.has(action_type):
				failures.append("%s unknown action_type: %s" % [label, action_type])
		elif kind == "authoring_meta":
			var authoring_key := str(block.get("authoring_key", "")).strip_edges()
			if not AUTHORING_BLOCK_AUTHORING_KEYS.has(authoring_key):
				failures.append("%s unknown authoring_key: %s" % [label, authoring_key])
	for catalog in AUTHORING_PALETTE_CATALOGS:
		if not catalogs_seen.has(catalog):
			failures.append("authoring_palette.assembly_blocks missing catalog block: %s" % catalog)


static func _collect_palette_catalog_entries_by_id(entries_variant: Variant) -> Dictionary:
	var entries_by_id: Dictionary = {}
	if typeof(entries_variant) != TYPE_ARRAY:
		return entries_by_id
	var entries: Array = entries_variant as Array
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var entry_id := str(entry.get(EnemySpawnerFleetHelper.ID, "")).strip_edges()
		if entry_id.is_empty():
			continue
		entries_by_id[entry_id] = entry
	return entries_by_id


static func _validate_palette_catalog_entries(label: String, entries_variant: Variant, failures: Array[String]) -> Dictionary:
	var entry_ids: Dictionary = {}
	if typeof(entries_variant) != TYPE_ARRAY:
		failures.append("%s should be an Array" % label)
		return entry_ids
	var entries: Array = entries_variant as Array
	if entries.is_empty():
		failures.append("%s should include at least one entry" % label)
	for index in range(entries.size()):
		var entry_variant: Variant = entries[index]
		var entry_label := "%s[%d]" % [label, index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % entry_label)
			continue
		var entry := entry_variant as Dictionary
		var entry_id := str(entry.get(EnemySpawnerFleetHelper.ID, "")).strip_edges()
		if entry_id.is_empty():
			failures.append("%s missing id" % entry_label)
			continue
		if entry_ids.has(entry_id):
			failures.append("%s duplicate id: %s" % [entry_label, entry_id])
		entry_ids[entry_id] = true
		_validate_palette_entry_shape(entry_label, entry, failures)
		var mode := str(entry.get("mode", "")).strip_edges()
		if mode.is_empty():
			failures.append("%s missing mode" % entry_label)
		var description := str(entry.get("description", "")).strip_edges()
		if description.is_empty():
			failures.append("%s missing description" % entry_label)
	return entry_ids


static func _validate_palette_ship_type_entries(entries_variant: Variant, all_stats: Dictionary, ship_archetypes: Dictionary, failures: Array[String]) -> void:
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for index in range(entries.size()):
		var entry_variant: Variant = entries[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var ship_type_name := str(entry.get(EnemySpawnerFleetHelper.ID, "")).strip_edges()
		if ship_type_name.is_empty() or not all_stats.has(ship_type_name):
			continue
		var stats_variant: Variant = all_stats[ship_type_name]
		if typeof(stats_variant) != TYPE_DICTIONARY:
			continue
		var expected_archetype := ShipBlueprintHelper.get_ship_archetype_name(stats_variant as Dictionary)
		var palette_archetype := str(entry.get(ShipBlueprintHelper.SHIP_ARCHETYPE, "")).strip_edges()
		var label := "authoring_palette.ship_types[%d]" % index
		if palette_archetype.is_empty():
			failures.append("%s missing ship_archetype" % label)
		elif not ship_archetypes.has(palette_archetype):
			failures.append("%s unknown ship_archetype: %s" % [label, palette_archetype])
		elif palette_archetype != expected_archetype:
			failures.append("%s ship_archetype mismatch: %s != %s" % [label, palette_archetype, expected_archetype])


static func _validate_palette_movement_intent_entries(entries_variant: Variant, failures: Array[String]) -> void:
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for index in range(entries.size()):
		var entry_variant: Variant = entries[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var label := "authoring_palette.movement_intents[%d]" % index
		if not entry.has("speed_min") or not entry.has("speed_max"):
			failures.append("%s should define speed_min and speed_max" % label)
			continue
		var speed_min := float(entry.get("speed_min", 0.0))
		var speed_max := float(entry.get("speed_max", 0.0))
		if speed_min < 0.0 or speed_max <= 0.0 or speed_min > speed_max:
			failures.append("%s speed range invalid: %.3f..%.3f" % [label, speed_min, speed_max])
		if not entry.has("sprint") or typeof(entry.get("sprint")) != TYPE_BOOL:
			failures.append("%s sprint should be a bool" % label)
		var family := str(entry.get("family", "")).strip_edges()
		if family.is_empty():
			failures.append("%s should define family" % label)
		elif not AUTHORING_INTENT_FAMILIES.has(family):
			failures.append("%s unknown family: %s" % [label, family])
		var support_tagged := _palette_entry_has_any_tag(entry, ["support", "assist"])
		if family == AUTHORING_INTENT_FAMILY_SUPPORT_RUNTIME and not support_tagged:
			failures.append("%s support family should include support or assist tag" % label)
		elif family == AUTHORING_INTENT_FAMILY_ENEMY_RUNTIME and support_tagged:
			failures.append("%s support-tagged movement intent should not use enemy family" % label)


static func _palette_entry_has_any_tag(entry: Dictionary, required_tags: Array) -> bool:
	var tags_variant: Variant = entry.get("tags", [])
	if typeof(tags_variant) != TYPE_ARRAY:
		return false
	var tags: Array = tags_variant as Array
	for tag_variant in tags:
		var tag := str(tag_variant).strip_edges()
		if required_tags.has(tag):
			return true
	return false


static func _validate_palette_spawn_recipe_entries(entries_variant: Variant, recipe_fleet_classes: Dictionary, parsed_templates: Dictionary, failures: Array[String]) -> void:
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for index in range(entries.size()):
		var entry_variant: Variant = entries[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var recipe_name := str(entry.get(EnemySpawnerFleetHelper.ID, "")).strip_edges()
		var fleet_class := str(entry.get(EnemySpawnerFleetHelper.FLEET_CLASS, "")).strip_edges()
		var label := "authoring_palette.spawn_recipes[%d]" % index
		if fleet_class.is_empty():
			failures.append("%s missing fleet_class" % label)
			continue
		if not parsed_templates.has(fleet_class):
			failures.append("%s unknown fleet_class: %s" % [label, fleet_class])
			continue
		if not _recipe_fleet_class_index_has(recipe_fleet_classes, recipe_name, fleet_class):
			failures.append("%s fleet_class does not include recipe %s" % [label, recipe_name])


static func _validate_palette_fleet_class_entries(entries_variant: Variant, spawn_recipes: Dictionary, recipe_fleet_classes: Dictionary, failures: Array[String]) -> void:
	if typeof(entries_variant) != TYPE_ARRAY:
		return
	var entries: Array = entries_variant as Array
	for index in range(entries.size()):
		var entry_variant: Variant = entries[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry := entry_variant as Dictionary
		var fleet_class := str(entry.get(EnemySpawnerFleetHelper.ID, "")).strip_edges()
		var recipes_variant: Variant = entry.get("recipes", [])
		var label := "authoring_palette.fleet_classes[%d]" % index
		if typeof(recipes_variant) != TYPE_ARRAY:
			failures.append("%s recipes should be an Array" % label)
			continue
		var recipes: Array = recipes_variant as Array
		if recipes.is_empty():
			failures.append("%s should include at least one recipe" % label)
		for recipe_index in range(recipes.size()):
			var recipe_name := str(recipes[recipe_index]).strip_edges()
			if recipe_name.is_empty():
				failures.append("%s recipes[%d] should be non-empty" % [label, recipe_index])
			elif not spawn_recipes.has(recipe_name):
				failures.append("%s recipes[%d] unknown recipe: %s" % [label, recipe_index, recipe_name])
			elif not _recipe_fleet_class_index_has(recipe_fleet_classes, recipe_name, fleet_class):
				failures.append("%s recipes[%d] is not in fleet class %s" % [label, recipe_index, fleet_class])


static func _collect_ship_type_references(all_stats: Dictionary) -> Dictionary:
	var references: Dictionary = {}
	for type_name_variant in all_stats.keys():
		var type_name := str(type_name_variant).strip_edges()
		if type_name.is_empty() or _is_ship_blueprint_meta_key(type_name):
			continue
		var stats_variant: Variant = all_stats[type_name_variant]
		if typeof(stats_variant) == TYPE_DICTIONARY:
			references[type_name] = true
	return references


static func _collect_scenario_trigger_references(scenario_triggers: Array[Dictionary]) -> Dictionary:
	var references: Dictionary = {}
	for trigger in scenario_triggers:
		var trigger_id := str(trigger.get(EnemySpawnerFleetHelper.ID, "")).strip_edges()
		if not trigger_id.is_empty():
			references[trigger_id] = true
	return references


static func _build_spawn_recipe_fleet_class_index(fleet_templates: Dictionary) -> Dictionary:
	var index: Dictionary = {}
	for fleet_class_variant in fleet_templates.keys():
		var fleet_class := str(fleet_class_variant).strip_edges()
		var templates_variant: Variant = fleet_templates[fleet_class_variant]
		if fleet_class.is_empty() or typeof(templates_variant) != TYPE_ARRAY:
			continue
		var templates: Array = templates_variant as Array
		for template_variant in templates:
			if typeof(template_variant) != TYPE_DICTIONARY:
				continue
			var template := template_variant as Dictionary
			var recipe_name := str(template.get(EnemySpawnerFleetHelper.RECIPE, "")).strip_edges()
			if recipe_name.is_empty():
				continue
			if not index.has(recipe_name):
				index[recipe_name] = {}
			var classes_variant: Variant = index[recipe_name]
			if typeof(classes_variant) == TYPE_DICTIONARY:
				(classes_variant as Dictionary)[fleet_class] = true
	return index


static func _recipe_fleet_class_index_has(recipe_fleet_classes: Dictionary, recipe_name: String, fleet_class: String) -> bool:
	if not recipe_fleet_classes.has(recipe_name):
		return false
	var classes_variant: Variant = recipe_fleet_classes[recipe_name]
	if typeof(classes_variant) != TYPE_DICTIONARY:
		return false
	return (classes_variant as Dictionary).has(fleet_class)


static func _validate_spawn_recipe_definitions(raw_recipes_variant: Variant, parsed_recipes: Dictionary, all_stats: Dictionary, failures: Array[String]) -> void:
	if typeof(raw_recipes_variant) != TYPE_DICTIONARY:
		failures.append("enemy spawn rules spawn_recipes should be a Dictionary")
		return
	var raw_recipes: Dictionary = raw_recipes_variant as Dictionary
	for recipe_name_variant in raw_recipes.keys():
		var recipe_name := str(recipe_name_variant)
		var label := "spawn_recipes.%s" % recipe_name
		var recipe_variant: Variant = raw_recipes[recipe_name_variant]
		if typeof(recipe_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		if not parsed_recipes.has(recipe_name):
			failures.append("%s did not parse into a usable spawn recipe" % label)
			continue
		var recipe := parsed_recipes[recipe_name] as Dictionary
		_validate_spawn_formation_type(label, str(recipe.get(EnemySpawnerFleetHelper.FORMATION_TYPE, "")), failures)
		var ships_variant: Variant = recipe.get(EnemySpawnerFleetHelper.SHIPS, [])
		if typeof(ships_variant) != TYPE_ARRAY:
			failures.append("%s ships should be an Array" % label)
			continue
		_validate_spawn_slots(label, ships_variant as Array, all_stats, failures)


static func _validate_encounter_profile_definitions(raw_profiles_variant: Variant, parsed_profiles: Dictionary, parsed_templates: Dictionary, failures: Array[String]) -> void:
	if typeof(raw_profiles_variant) != TYPE_DICTIONARY:
		failures.append("enemy spawn rules encounter_profiles should be a Dictionary")
		return
	var raw_profiles: Dictionary = raw_profiles_variant as Dictionary
	for profile_name_variant in raw_profiles.keys():
		var profile_name := str(profile_name_variant)
		var label := "encounter_profiles.%s" % profile_name
		var profile_variant: Variant = raw_profiles[profile_name_variant]
		if typeof(profile_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		if not parsed_profiles.has(profile_name):
			failures.append("%s did not parse into a usable encounter profile" % label)
			continue
		var profile := parsed_profiles[profile_name] as Dictionary
		var progression_variant: Variant = profile.get(EnemySpawnerFleetHelper.FLEET_PROGRESSION, [])
		if typeof(progression_variant) != TYPE_ARRAY:
			failures.append("%s fleet_progression should be an Array" % label)
			continue
		_validate_fleet_progression("%s.%s" % [label, EnemySpawnerFleetHelper.FLEET_PROGRESSION], progression_variant as Array, parsed_templates, failures)


static func _validate_formation_encounter_profile(formation: Dictionary, encounter_profiles: Dictionary, failures: Array[String]) -> void:
	var profile_name := str(formation.get(EnemySpawnerFleetHelper.ENCOUNTER_PROFILE, "")).strip_edges()
	if profile_name.is_empty():
		if not formation.has(EnemySpawnerFleetHelper.FLEET_PROGRESSION):
			failures.append("enemy spawn rules formation should define encounter_profile or fleet_progression")
		return
	if not encounter_profiles.has(profile_name):
		failures.append("enemy spawn rules formation unknown encounter_profile: %s" % profile_name)


static func _validate_scenario_trigger_definitions(raw_triggers_variant: Variant, parsed_triggers: Array[Dictionary], encounter_profiles: Dictionary, parsed_templates: Dictionary, spawn_recipes: Dictionary, all_stats: Dictionary, combat_profiles: Dictionary, movement_intents: Dictionary, failures: Array[String]) -> void:
	if typeof(raw_triggers_variant) != TYPE_ARRAY:
		failures.append("enemy spawn rules scenario_triggers should be an Array")
		return
	var raw_triggers: Array = raw_triggers_variant as Array
	var seen_ids: Dictionary = {}
	var trigger_references := _collect_scenario_trigger_references(parsed_triggers)
	var ship_types := _collect_ship_type_references(all_stats)
	for trigger_index in range(raw_triggers.size()):
		var trigger_variant: Variant = raw_triggers[trigger_index]
		var label := "scenario_triggers[%d]" % trigger_index
		if typeof(trigger_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		var trigger := trigger_variant as Dictionary
		var trigger_id := str(trigger.get(EnemySpawnerFleetHelper.ID, trigger.get(EnemySpawnerFleetHelper.NAME, ""))).strip_edges()
		if trigger_id.is_empty():
			failures.append("%s missing id" % label)
		elif seen_ids.has(trigger_id):
			failures.append("%s duplicate id: %s" % [label, trigger_id])
		else:
			seen_ids[trigger_id] = true
		var condition_variant: Variant = trigger.get(EnemySpawnerFleetHelper.CONDITION, {})
		if typeof(condition_variant) != TYPE_DICTIONARY:
			failures.append("%s condition should be a Dictionary" % label)
		else:
			var condition := condition_variant as Dictionary
			var elapsed_time := float(condition.get(EnemySpawnerFleetHelper.ELAPSED_TIME, -1.0))
			if elapsed_time < 0.0:
				failures.append("%s condition.elapsed_time should be >= 0" % label)
		var actions_variant: Variant = trigger.get(EnemySpawnerFleetHelper.ACTIONS, [])
		if typeof(actions_variant) != TYPE_ARRAY:
			failures.append("%s actions should be an Array" % label)
			continue
		var actions := actions_variant as Array
		if actions.is_empty():
			failures.append("%s should include at least one action" % label)
		for action_index in range(actions.size()):
			_validate_scenario_action(
				"%s.actions[%d]" % [label, action_index],
				actions[action_index],
				trigger_id,
				encounter_profiles,
				parsed_templates,
				spawn_recipes,
				ship_types,
				trigger_references,
				combat_profiles,
				movement_intents,
				failures
			)
	if parsed_triggers.size() != raw_triggers.size():
		failures.append("enemy spawn rules scenario_triggers parsed %d of %d entries" % [parsed_triggers.size(), raw_triggers.size()])


static func _validate_scenario_action(label: String, action_variant: Variant, current_trigger_id: String, encounter_profiles: Dictionary, parsed_templates: Dictionary, spawn_recipes: Dictionary, ship_types: Dictionary, trigger_references: Dictionary, combat_profiles: Dictionary, movement_intents: Dictionary, failures: Array[String]) -> void:
	if typeof(action_variant) != TYPE_DICTIONARY:
		failures.append("%s should be a Dictionary" % label)
		return
	var action := action_variant as Dictionary
	var action_type := str(action.get(EnemySpawnerFleetHelper.TYPE, "")).strip_edges()
	if not ["set_encounter_profile", "spawn_fleet", "spawn_recipe", "spawn_ship", "run_scenario_trigger", "spawn_mid_boss", "trigger_boss_event", "stop_regular_spawns"].has(action_type):
		failures.append("%s unsupported type: %s" % [label, action_type])
		return
	match action_type:
		"set_encounter_profile":
			var profile_name := str(action.get(EnemySpawnerFleetHelper.PROFILE, "")).strip_edges()
			if profile_name.is_empty() or not encounter_profiles.has(profile_name):
				failures.append("%s unknown encounter profile: %s" % [label, profile_name])
		"spawn_fleet":
			var fleet_class := str(action.get(EnemySpawnerFleetHelper.FLEET_CLASS, "")).strip_edges()
			if fleet_class.is_empty() or not parsed_templates.has(fleet_class):
				failures.append("%s unknown fleet class: %s" % [label, fleet_class])
		"spawn_recipe":
			var recipe_name := str(action.get(EnemySpawnerFleetHelper.RECIPE, "")).strip_edges()
			if recipe_name.is_empty() or not spawn_recipes.has(recipe_name):
				failures.append("%s unknown spawn recipe: %s" % [label, recipe_name])
		"spawn_ship":
			var ship_type_name := str(action.get(EnemySpawnerFleetHelper.SHIP_TYPE, "")).strip_edges()
			if ship_type_name.is_empty() or not ship_types.has(ship_type_name):
				failures.append("%s unknown ship type: %s" % [label, ship_type_name])
		"run_scenario_trigger":
			var trigger_id := str(action.get("trigger", "")).strip_edges()
			if trigger_id.is_empty():
				failures.append("%s missing trigger" % label)
			elif trigger_id == current_trigger_id:
				failures.append("%s should not run itself: %s" % [label, trigger_id])
			elif not trigger_references.has(trigger_id):
				failures.append("%s unknown scenario trigger: %s" % [label, trigger_id])
	_validate_scenario_action_authoring_meta(label, action, action_type, combat_profiles, movement_intents, failures)


static func _validate_scenario_action_authoring_meta(label: String, action: Dictionary, action_type: String, combat_profiles: Dictionary, movement_intents: Dictionary, failures: Array[String]) -> void:
	if not action.has("authoring"):
		return
	if not ["spawn_ship", "spawn_recipe"].has(action_type):
		failures.append("%s authoring metadata is only supported on spawn_ship or spawn_recipe" % label)
		return
	var authoring_variant: Variant = action.get("authoring", {})
	if typeof(authoring_variant) != TYPE_DICTIONARY:
		failures.append("%s authoring should be a Dictionary" % label)
		return
	var authoring: Dictionary = authoring_variant as Dictionary
	var combat_profile := str(authoring.get("combat_profile", "")).strip_edges()
	var movement_intent := str(authoring.get("movement_intent", "")).strip_edges()
	var movement_mode := str(authoring.get("movement_mode", "")).strip_edges()
	var has_movement_speed := authoring.has("movement_speed_min") or authoring.has("movement_speed_max")
	if combat_profile.is_empty() and movement_intent.is_empty():
		failures.append("%s authoring should include combat_profile or movement_intent" % label)
	if not combat_profile.is_empty() and not combat_profiles.has(combat_profile):
		failures.append("%s unknown authoring combat_profile: %s" % [label, combat_profile])
	if movement_intent.is_empty():
		if not movement_mode.is_empty():
			failures.append("%s movement_mode requires authoring movement_intent" % label)
		if has_movement_speed or authoring.has("movement_sprint"):
			failures.append("%s movement parameters require authoring movement_intent" % label)
		return
	if not movement_intents.has(movement_intent):
		failures.append("%s unknown authoring movement_intent: %s" % [label, movement_intent])
		return
	var movement_entry_variant: Variant = movement_intents.get(movement_intent, {})
	var movement_entry: Dictionary = movement_entry_variant as Dictionary if typeof(movement_entry_variant) == TYPE_DICTIONARY else {}
	var expected_mode := str(movement_entry.get("mode", "")).strip_edges()
	var expected_family := str(movement_entry.get("family", "")).strip_edges()
	if not movement_mode.is_empty() and movement_mode != expected_mode:
		failures.append("%s authoring movement_mode mismatch: %s != %s" % [label, movement_mode, expected_mode])
	var movement_family := str(authoring.get("movement_family", authoring.get("family", ""))).strip_edges()
	if not movement_family.is_empty() and movement_family != expected_family:
		failures.append("%s authoring movement_family mismatch: %s != %s" % [label, movement_family, expected_family])
	if has_movement_speed:
		if not authoring.has("movement_speed_min") or not authoring.has("movement_speed_max"):
			failures.append("%s authoring movement speed requires min and max" % label)
		var speed_min := float(authoring.get("movement_speed_min", 0.0))
		var speed_max := float(authoring.get("movement_speed_max", 0.0))
		if speed_min < 0.0 or speed_max <= 0.0 or speed_min > speed_max:
			failures.append("%s authoring movement speed range invalid: %.3f..%.3f" % [label, speed_min, speed_max])
	if authoring.has("movement_sprint") and typeof(authoring.get("movement_sprint")) != TYPE_BOOL:
		failures.append("%s authoring movement_sprint should be a bool" % label)


static func _validate_fleet_progression(label: String, progression: Array, parsed_templates: Dictionary, failures: Array[String]) -> void:
	if progression.is_empty():
		failures.append("%s should include at least one time window" % label)
	for index in range(progression.size()):
		var row_variant: Variant = progression[index]
		var row_label := "%s[%d]" % [label, index]
		if typeof(row_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % row_label)
			continue
		var row := row_variant as Dictionary
		var start_time := float(row.get(EnemySpawnerFleetHelper.START_TIME, 0.0))
		var end_time := float(row.get(EnemySpawnerFleetHelper.END_TIME, 0.0))
		if end_time <= start_time:
			failures.append("%s end_time should be greater than start_time" % row_label)
		var weights_variant: Variant = row.get(EnemySpawnerFleetHelper.FLEET_WEIGHTS, {})
		if typeof(weights_variant) != TYPE_DICTIONARY:
			failures.append("%s fleet_weights should be a Dictionary" % row_label)
			continue
		var weights := EnemySpawnerFleetHelper.parse_fleet_weights(weights_variant)
		if weights.is_empty():
			failures.append("%s should include at least one positive fleet weight" % row_label)
			continue
		for fleet_class_variant in weights.keys():
			var fleet_class := str(fleet_class_variant)
			if not parsed_templates.has(fleet_class):
				failures.append("%s references unknown fleet class: %s" % [row_label, fleet_class])


static func _validate_fleet_template_recipe_references(fleet_templates: Dictionary, spawn_recipes: Dictionary, failures: Array[String]) -> void:
	for class_key_variant in fleet_templates.keys():
		var fleet_class := str(class_key_variant)
		var templates_variant: Variant = fleet_templates[class_key_variant]
		if typeof(templates_variant) != TYPE_ARRAY:
			failures.append("enemy spawn rules fleet_templates.%s should be an Array" % fleet_class)
			continue
		for index in range((templates_variant as Array).size()):
			var template_variant: Variant = (templates_variant as Array)[index]
			var label := "fleet_templates.%s[%d]" % [fleet_class, index]
			if typeof(template_variant) != TYPE_DICTIONARY:
				failures.append("%s should be a Dictionary" % label)
				continue
			var template := template_variant as Dictionary
			var recipe_name := str(template.get(EnemySpawnerFleetHelper.RECIPE, "")).strip_edges()
			if not recipe_name.is_empty() and not spawn_recipes.has(recipe_name):
				failures.append("%s unknown spawn recipe: %s" % [label, recipe_name])
			if recipe_name.is_empty() and not template.has(EnemySpawnerFleetHelper.SHIPS):
				failures.append("%s should define recipe or ships" % label)


static func _validate_parsed_fleet_templates(parsed_templates: Dictionary, all_stats: Dictionary, failures: Array[String]) -> void:
	for class_key_variant in parsed_templates.keys():
		var fleet_class := str(class_key_variant)
		var templates_variant: Variant = parsed_templates[class_key_variant]
		if typeof(templates_variant) != TYPE_ARRAY:
			failures.append("parsed fleet class should be an Array: %s" % fleet_class)
			continue
		for template_index in range((templates_variant as Array).size()):
			var template_variant: Variant = (templates_variant as Array)[template_index]
			if typeof(template_variant) != TYPE_ARRAY:
				failures.append("parsed fleet template should be an Array: %s[%d]" % [fleet_class, template_index])
				continue
			var template := template_variant as Array
			_validate_spawn_slots("parsed fleet_templates.%s[%d]" % [fleet_class, template_index], template, all_stats, failures)
			if not template.is_empty() and typeof(template[0]) == TYPE_DICTIONARY:
				_validate_spawn_formation_type("parsed fleet_templates.%s[%d]" % [fleet_class, template_index], str((template[0] as Dictionary).get(EnemySpawnerFleetHelper.FORMATION_TYPE, "")), failures)


static func _validate_mid_boss_escort_rules(escorts_variant: Variant, all_stats: Dictionary, failures: Array[String]) -> void:
	if typeof(escorts_variant) != TYPE_ARRAY:
		failures.append("enemy spawn rules mid_boss_escort should be an Array")
		return
	var escorts: Array = escorts_variant as Array
	for index in range(escorts.size()):
		var escort_variant: Variant = escorts[index]
		var label := "mid_boss_escort[%d]" % index
		if typeof(escort_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		_validate_spawn_slot(label, escort_variant as Dictionary, all_stats, failures)


static func _validate_spawn_slots(label: String, slots: Array, all_stats: Dictionary, failures: Array[String]) -> void:
	if slots.is_empty():
		failures.append("%s should include at least one ship" % label)
	for index in range(slots.size()):
		var slot_variant: Variant = slots[index]
		if typeof(slot_variant) != TYPE_DICTIONARY:
			failures.append("%s ships[%d] should be a Dictionary" % [label, index])
			continue
		_validate_spawn_slot("%s ships[%d]" % [label, index], slot_variant as Dictionary, all_stats, failures)


static func _validate_spawn_slot(label: String, slot: Dictionary, all_stats: Dictionary, failures: Array[String]) -> void:
	var ship_type_name := str(slot.get(EnemySpawnerFleetHelper.SHIP_TYPE, "")).strip_edges()
	if ship_type_name.is_empty():
		failures.append("%s missing ship_type" % label)
	elif not _is_known_ship_type(ship_type_name, all_stats):
		failures.append("%s unknown ship_type: %s" % [label, ship_type_name])


static func _validate_spawn_formation_type(label: String, formation_type: String, failures: Array[String]) -> void:
	if not ["line_abreast", "column", "wedge", "escort", "echelon"].has(formation_type):
		failures.append("%s has unsupported formation_type: %s" % [label, formation_type])


static func _is_known_ship_type(type_name: String, all_stats: Dictionary) -> bool:
	if not all_stats.has(type_name):
		return false
	return not _is_ship_blueprint_meta_key(type_name)


static func _is_ship_blueprint_meta_key(type_name: String) -> bool:
	return [ShipWeaponLoadoutHelper.WEAPON_PROFILES, ShipBlueprintHelper.COMBAT_PROFILES, ShipBlueprintHelper.SHIP_ARCHETYPES].has(type_name)


static func _load_ship_archetypes(all_stats: Dictionary, failures: Array[String]) -> Dictionary:
	var archetypes_variant: Variant = all_stats.get(ShipBlueprintHelper.SHIP_ARCHETYPES, {})
	if typeof(archetypes_variant) != TYPE_DICTIONARY:
		failures.append("ship blueprint ship_archetypes should be a Dictionary")
		return {}
	return archetypes_variant as Dictionary


static func _validate_ship_archetypes(archetypes: Dictionary, combat_profiles: Dictionary, weapon_profiles: Dictionary, failures: Array[String]) -> void:
	for archetype_name_variant in archetypes.keys():
		var archetype_name := str(archetype_name_variant)
		var archetype_variant: Variant = archetypes[archetype_name_variant]
		var label := "%s.%s" % [ShipBlueprintHelper.SHIP_ARCHETYPES, archetype_name]
		if typeof(archetype_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		var archetype := archetype_variant as Dictionary
		_validate_combat_profile_reference(label, archetype, combat_profiles, failures)
		var resolved_archetype := ShipBlueprintHelper.resolve_combat_profile(archetype, combat_profiles)
		_validate_combat_runtime_fields(label, resolved_archetype, failures)
		if not resolved_archetype.has("weapon_loadout"):
			continue
		var loadout_variant: Variant = resolved_archetype.get("weapon_loadout", [])
		if typeof(loadout_variant) != TYPE_ARRAY:
			failures.append("%s weapon_loadout should be an Array" % label)
			continue
		_validate_weapon_loadout_entries(label, resolved_archetype, loadout_variant as Array, weapon_profiles, failures)


static func _validate_ship_archetype_reference(type_name: String, stats: Dictionary, archetypes: Dictionary, failures: Array[String]) -> void:
	var archetype_name := ShipBlueprintHelper.get_ship_archetype_name(stats)
	if not archetype_name.is_empty() and not archetypes.has(archetype_name):
		failures.append("ship blueprint %s unknown ship_archetype: %s" % [type_name, archetype_name])


static func _load_combat_profiles(all_stats: Dictionary, failures: Array[String]) -> Dictionary:
	var profiles_variant: Variant = all_stats.get(ShipBlueprintHelper.COMBAT_PROFILES, {})
	if typeof(profiles_variant) != TYPE_DICTIONARY:
		failures.append("ship blueprint combat_profiles should be a Dictionary")
		return {}
	return profiles_variant as Dictionary


static func _validate_combat_profiles(profiles: Dictionary, failures: Array[String]) -> void:
	for profile_name_variant in profiles.keys():
		var profile_name := str(profile_name_variant)
		var profile_variant: Variant = profiles[profile_name_variant]
		var label := "%s.%s" % [ShipBlueprintHelper.COMBAT_PROFILES, profile_name]
		if typeof(profile_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		_validate_combat_runtime_fields(label, profile_variant as Dictionary, failures)


static func _validate_combat_profile_reference(type_name: String, stats: Dictionary, profiles: Dictionary, failures: Array[String]) -> void:
	var profile_name := ShipBlueprintHelper.get_combat_profile_name(stats)
	if not profile_name.is_empty() and not profiles.has(profile_name):
		failures.append("ship blueprint %s unknown combat_profile: %s" % [type_name, profile_name])


static func _validate_combat_runtime_fields(label: String, stats: Dictionary, failures: Array[String]) -> void:
	var role_name: String = str(stats.get("combat_role", "")).strip_edges()
	if not role_name.is_empty() and not [ShipCombatModeHelper.ROLE_CHARGER, ShipCombatModeHelper.ROLE_GUNNER].has(role_name):
		failures.append("%s combat_role should be charger or gunner: %s" % [label, role_name])

	var allow_boarding_variant: Variant = stats.get("allow_boarding", null)
	if allow_boarding_variant != null and typeof(allow_boarding_variant) != TYPE_BOOL:
		failures.append("%s allow_boarding should be a bool" % label)

	for positive_float_key in ["preferred_range", "range_tolerance", "retreat_distance", "orbit_distance"]:
		if stats.has(positive_float_key) and float(stats[positive_float_key]) <= 0.0:
			failures.append("%s %s should be positive" % [label, positive_float_key])


static func _load_weapon_profiles(all_stats: Dictionary, failures: Array[String]) -> Dictionary:
	var profiles_variant: Variant = all_stats.get(ShipWeaponLoadoutHelper.WEAPON_PROFILES, {})
	if typeof(profiles_variant) != TYPE_DICTIONARY:
		failures.append("ship blueprint weapon_profiles should be a Dictionary")
		return {}
	return profiles_variant as Dictionary


static func _validate_weapon_profiles(profiles: Dictionary, failures: Array[String]) -> void:
	for profile_name_variant in profiles.keys():
		var profile_name := str(profile_name_variant)
		var profile_variant: Variant = profiles[profile_name_variant]
		var label := "%s.%s" % [ShipWeaponLoadoutHelper.WEAPON_PROFILES, profile_name]
		if typeof(profile_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		var profile := profile_variant as Dictionary
		_validate_weapon_kind(label, profile, failures)
		_validate_weapon_runtime_fields(label, profile, failures)


static func _validate_weapon_loadout_entries(type_name: String, stats: Dictionary, loadout: Array, profiles: Dictionary, failures: Array[String]) -> void:
	var used_names := {}
	var hull_weapon_slot_names: Dictionary = {}
	var loaded_hull_weapon_slots := false
	for index in range(loadout.size()):
		var spec_variant: Variant = loadout[index]
		var label := "%s.weapon_loadout[%d]" % [type_name, index]
		if typeof(spec_variant) != TYPE_DICTIONARY:
			failures.append("%s should be a Dictionary" % label)
			continue
		var raw_spec := spec_variant as Dictionary
		var profile_name := ShipWeaponLoadoutHelper.get_profile_name(raw_spec)
		if not profile_name.is_empty() and not profiles.has(profile_name):
			failures.append("%s unknown weapon profile: %s" % [label, profile_name])
		var spec := ShipWeaponLoadoutHelper.resolve_weapon_profile(raw_spec, profiles)
		_validate_weapon_kind(label, spec, failures)

		var node_name := ShipWeaponLoadoutHelper.get_node_name(spec)
		if node_name.is_empty():
			failures.append("%s missing name" % label)
		elif used_names.has(node_name):
			failures.append("%s duplicates weapon name: %s" % [label, node_name])
		else:
			used_names[node_name] = true

		_validate_weapon_runtime_fields(label, spec, failures)

		var slot_name := ShipWeaponLoadoutHelper.get_slot_name(spec)
		if slot_name.is_empty():
			failures.append("%s missing slot" % label)
		else:
			if not loaded_hull_weapon_slots:
				hull_weapon_slot_names = _load_hull_weapon_slot_names(type_name, stats, failures)
				loaded_hull_weapon_slots = true
			if not hull_weapon_slot_names.has(slot_name):
				failures.append("%s slot not found on hull WeaponSlots/CannonSlots: %s" % [label, slot_name])


static func _validate_weapon_kind(label: String, spec: Dictionary, failures: Array[String]) -> void:
	var kind := ShipWeaponLoadoutHelper.get_kind(spec, "")
	if kind.is_empty():
		failures.append("%s missing kind" % label)
	elif not [ShipWeaponLoadoutHelper.KIND_CANNON, ShipWeaponLoadoutHelper.KIND_SINGIGEON].has(kind):
		failures.append("%s has unsupported kind: %s" % [label, kind])


static func _validate_weapon_runtime_fields(label: String, spec: Dictionary, failures: Array[String]) -> void:
	var scene_path := ShipWeaponLoadoutHelper.get_scene_path(spec)
	if scene_path.is_empty():
		failures.append("%s missing scene" % label)
	elif not ResourceLoader.exists(scene_path):
		failures.append("%s scene path does not exist: %s" % [label, scene_path])
	else:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			failures.append("%s scene is not a PackedScene: %s" % [label, scene_path])

	var team_name := ShipWeaponLoadoutHelper.get_team(spec)
	if not team_name.is_empty() and not ["player", "enemy"].has(team_name):
		failures.append("%s team should be player or enemy: %s" % [label, team_name])

	var projectile_scene_path := ShipWeaponLoadoutHelper.get_projectile_scene_path(spec)
	if not projectile_scene_path.is_empty():
		if not ResourceLoader.exists(projectile_scene_path):
			failures.append("%s projectile_scene path does not exist: %s" % [label, projectile_scene_path])
		else:
			var projectile_packed := load(projectile_scene_path) as PackedScene
			if projectile_packed == null:
				failures.append("%s projectile_scene is not a PackedScene: %s" % [label, projectile_scene_path])

	for positive_float_key in [ShipWeaponLoadoutHelper.FIRE_COOLDOWN, ShipWeaponLoadoutHelper.DETECTION_RANGE, ShipWeaponLoadoutHelper.DETECTION_ARC, ShipWeaponLoadoutHelper.PROJECTILE_SPEED]:
		if spec.has(positive_float_key) and float(spec[positive_float_key]) <= 0.0:
			failures.append("%s %s should be positive" % [label, positive_float_key])


static func _load_hull_weapon_slot_names(type_name: String, stats: Dictionary, failures: Array[String]) -> Dictionary:
	var slot_names := {}
	var hull_path := ShipBlueprintHelper.get_hull_scene_path(type_name, stats)
	if hull_path.is_empty():
		failures.append("ship blueprint %s weapon_loadout missing hull_scene for slot validation" % type_name)
		return slot_names
	var packed := load(hull_path) as PackedScene
	if packed == null:
		failures.append("ship blueprint %s weapon_loadout hull_scene load failed: %s" % [type_name, hull_path])
		return slot_names
	var hull_root := packed.instantiate()
	if hull_root == null:
		failures.append("ship blueprint %s weapon_loadout hull_scene instantiate failed: %s" % [type_name, hull_path])
		return slot_names
	var hull_node := hull_root as Node3D
	if not is_instance_valid(hull_node):
		failures.append("ship blueprint %s weapon_loadout hull_scene root should be Node3D: %s" % [type_name, hull_path])
		hull_root.free()
		return slot_names
	slot_names = ShipAuthoringHelper.get_named_weapon_slot_transforms(hull_node).duplicate()
	hull_root.free()
	return slot_names


static func _expect_min_authoring_count(marker_counts: Dictionary, label: String, container_name: String, expected_count: int, failures: Array[String]) -> void:
	var actual_count := int(marker_counts.get(container_name, 0))
	if actual_count < expected_count:
		failures.append("%s authoring %s should expose at least %d markers, got %d" % [label, container_name, expected_count, actual_count])


static func _expect_authoring_marker_names(root: Node, label: String, container_name: String, required_names: Array, failures: Array[String]) -> void:
	var marker_names := {}
	for marker in ShipAuthoringHelper.get_authoring_markers(root, container_name):
		marker_names[str(marker.name)] = true
	for required_name in required_names:
		if not marker_names.has(str(required_name)):
			failures.append("%s authoring %s missing marker: %s" % [label, container_name, required_name])


static func _expect_authoring_visualizer(root: Node, label: String, failures: Array[String]) -> void:
	var authoring := root.get_node_or_null("Authoring")
	if not is_instance_valid(authoring):
		authoring = root.find_child("Authoring", true, false)
	if not is_instance_valid(authoring):
		failures.append("%s authoring visualizer missing Authoring root" % label)
		return
	var script := authoring.get_script() as Script
	if script == null:
		failures.append("%s authoring visualizer missing script" % label)
		return
	if script.resource_path != "res://scripts/entities/ships/ship_authoring_visualizer.gd":
		failures.append("%s authoring visualizer script mismatch: %s" % [label, script.resource_path])


static func _expect_no_persisted_authoring_visuals(scene_path: String, label: String, failures: Array[String]) -> void:
	var file := FileAccess.open(scene_path, FileAccess.READ)
	if file == null:
		failures.append("%s authoring visualizer could not open scene text: %s" % [label, scene_path])
		return
	var text := file.get_as_text()
	for visual_token in ["__AuthoringVisuals", "DeckAreaVisual", "authoring_visual_kind"]:
		if text.contains(visual_token):
			failures.append("%s authoring visualizer should not persist editor-only node token: %s" % [label, visual_token])


static func _expect_runtime_authoring_visuals_absent(root: Node, label: String, failures: Array[String]) -> void:
	var authoring := root.get_node_or_null("Authoring")
	if not is_instance_valid(authoring):
		authoring = root.find_child("Authoring", true, false)
	if not is_instance_valid(authoring):
		return
	var visual_root := authoring.get_node_or_null("__AuthoringVisuals")
	if is_instance_valid(visual_root):
		failures.append("%s authoring visualizer should not instantiate editor visuals in runtime contract" % label)


static func _expect_authoring_marker_layout(root: Node, label: String, failures: Array[String]) -> void:
	if not (root is Node3D):
		failures.append("%s authoring layout root should be Node3D" % label)
		return
	var root_3d := root as Node3D
	var hull_half_extents := _get_scene_hull_half_extents(root_3d)
	if hull_half_extents.x <= 0.01 or hull_half_extents.y <= 0.01:
		failures.append("%s authoring layout could not determine hull extents" % label)
		return

	_expect_deck_marker_bounds(root_3d, label, "CannonSlots", hull_half_extents, failures)
	_expect_deck_marker_bounds(root_3d, label, "WeaponSlots", hull_half_extents, failures)
	_expect_deck_marker_bounds(root_3d, label, "CrewSlots", hull_half_extents, failures)
	_expect_boarding_anchor_layout(root_3d, label, hull_half_extents, failures)


static func _expect_deck_marker_bounds(root: Node3D, label: String, container_name: String, hull_half_extents: Vector2, failures: Array[String]) -> void:
	var margin := Vector2(0.45, 0.65)
	for marker in ShipAuthoringHelper.get_authoring_markers(root, container_name):
		var local_pos := root.to_local(marker.global_position)
		if absf(local_pos.x) > hull_half_extents.x + margin.x:
			failures.append("%s authoring %s marker outside hull width: %s at %s" % [label, container_name, marker.name, local_pos])
		if absf(local_pos.z) > hull_half_extents.y + margin.y:
			failures.append("%s authoring %s marker outside hull length: %s at %s" % [label, container_name, marker.name, local_pos])


static func _expect_boarding_anchor_layout(root: Node3D, label: String, hull_half_extents: Vector2, failures: Array[String]) -> void:
	var side_min_x := maxf(0.2, hull_half_extents.x * 0.55)
	var side_max_x := hull_half_extents.x + 0.75
	var end_max_z := hull_half_extents.y + 0.8
	var side_anchor_names := ["RightForward", "RightMid", "RightRear", "LeftForward", "LeftMid", "LeftRear"]
	var marker_by_name := {}
	for marker in ShipAuthoringHelper.get_authoring_markers(root, "BoardingAnchors"):
		marker_by_name[str(marker.name)] = marker

	for anchor_name in side_anchor_names:
		var marker := marker_by_name.get(anchor_name, null) as Node3D
		if not is_instance_valid(marker):
			continue
		var local_pos := root.to_local(marker.global_position)
		var expected_sign := 1.0 if str(anchor_name).begins_with("Right") else -1.0
		if signf(local_pos.x) != expected_sign:
			failures.append("%s authoring BoardingAnchors marker on wrong side: %s at %s" % [label, anchor_name, local_pos])
		if absf(local_pos.x) < side_min_x or absf(local_pos.x) > side_max_x:
			failures.append("%s authoring BoardingAnchors side marker should sit near hull edge: %s at %s" % [label, anchor_name, local_pos])
		if absf(local_pos.z) > end_max_z:
			failures.append("%s authoring BoardingAnchors side marker outside hull length: %s at %s" % [label, anchor_name, local_pos])

	var bow := marker_by_name.get("Bow", null) as Node3D
	if is_instance_valid(bow):
		var bow_pos := root.to_local(bow.global_position)
		if bow_pos.z > -hull_half_extents.y * 0.65:
			failures.append("%s authoring Bow anchor should sit near forward end: %s" % [label, bow_pos])
		if absf(bow_pos.x) > hull_half_extents.x + 0.35:
			failures.append("%s authoring Bow anchor should stay centered enough: %s" % [label, bow_pos])

	var stern := marker_by_name.get("Stern", null) as Node3D
	if is_instance_valid(stern):
		var stern_pos := root.to_local(stern.global_position)
		if stern_pos.z < hull_half_extents.y * 0.65:
			failures.append("%s authoring Stern anchor should sit near rear end: %s" % [label, stern_pos])
		if absf(stern_pos.x) > hull_half_extents.x + 0.35:
			failures.append("%s authoring Stern anchor should stay centered enough: %s" % [label, stern_pos])


static func _get_scene_hull_half_extents(root: Node3D) -> Vector2:
	var bounds := {
		"has_bounds": false,
		"min_x": INF,
		"max_x": -INF,
		"min_z": INF,
		"max_z": -INF,
	}
	_collect_scene_mesh_bounds(root, root, bounds)
	if not bool(bounds["has_bounds"]):
		return Vector2.ZERO
	return Vector2(
		maxf(absf(float(bounds["min_x"])), absf(float(bounds["max_x"]))),
		maxf(absf(float(bounds["min_z"])), absf(float(bounds["max_z"])))
	)


static func _collect_scene_mesh_bounds(root: Node3D, node: Node, bounds: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var aabb := mesh_instance.get_aabb()
		var transform_to_root := root.global_transform.affine_inverse() * mesh_instance.global_transform
		for corner in _get_aabb_corners(aabb):
			var local_corner: Vector3 = transform_to_root * corner
			bounds["has_bounds"] = true
			bounds["min_x"] = minf(float(bounds["min_x"]), local_corner.x)
			bounds["max_x"] = maxf(float(bounds["max_x"]), local_corner.x)
			bounds["min_z"] = minf(float(bounds["min_z"]), local_corner.z)
			bounds["max_z"] = maxf(float(bounds["max_z"]), local_corner.z)
	for child in node.get_children():
		_collect_scene_mesh_bounds(root, child, bounds)


static func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var min_pos := aabb.position
	var max_pos := aabb.position + aabb.size
	return [
		Vector3(min_pos.x, min_pos.y, min_pos.z),
		Vector3(max_pos.x, min_pos.y, min_pos.z),
		Vector3(min_pos.x, max_pos.y, min_pos.z),
		Vector3(max_pos.x, max_pos.y, min_pos.z),
		Vector3(min_pos.x, min_pos.y, max_pos.z),
		Vector3(max_pos.x, min_pos.y, max_pos.z),
		Vector3(min_pos.x, max_pos.y, max_pos.z),
		Vector3(max_pos.x, max_pos.y, max_pos.z),
	]


static func _run_soldier_common_action_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/entities/soldiers/soldier.tscn") as PackedScene
	if packed == null:
		failures.append("soldier common action contract load failed")
		return
	var wrapper := Node3D.new()
	wrapper.name = "SoldierCommonActionContract"
	owner.add_child(wrapper)
	var soldier := packed.instantiate() as Node3D
	if soldier == null:
		failures.append("soldier common action contract instantiate failed")
		wrapper.queue_free()
		return
	wrapper.add_child(soldier)
	await _wait_frames(owner, wait_frames_after_attach)

	for method_name in ["begin_boarding_jump_pose", "finish_boarding_jump_pose", "play_cannon_reload_pose", "is_available_for_cannon_reload_pose"]:
		if not soldier.has_method(str(method_name)):
			failures.append("soldier common action missing method: %s" % method_name)

	if soldier.has_method("begin_boarding_jump_pose") and soldier.has_method("finish_boarding_jump_pose"):
		soldier.call("begin_boarding_jump_pose", "boarding")
		await _wait_frames(owner, 1)
		if soldier.has_method("is_jumping_value") and soldier.is_jumping_value() != true:
			failures.append("soldier common boarding pose did not mark jumping")
		if soldier.has_method("get_boarding_status_value") and soldier.get_boarding_status_value() != "boarding":
			failures.append("soldier common boarding pose did not set boarding status")
		if soldier.get("current_state") != soldier.State.BOARDING_JUMP:
			failures.append("soldier common boarding pose did not enter BOARDING_JUMP state")
		soldier.call("finish_boarding_jump_pose", "on_deck")
		await _wait_frames(owner, 1)
		if soldier.has_method("is_jumping_value") and soldier.is_jumping_value() != false:
			failures.append("soldier common boarding pose did not clear jumping")
		if soldier.get("current_state") == soldier.State.BOARDING_JUMP:
			failures.append("soldier common boarding pose remained in BOARDING_JUMP after landing")

	if soldier.has_method("play_cannon_reload_pose"):
		var cannon_marker := Node3D.new()
		cannon_marker.name = "CannonReloadPoseMarker"
		wrapper.add_child(cannon_marker)
		cannon_marker.global_position = soldier.global_position + Vector3(1.0, 0.0, 0.0)
		soldier.call("play_cannon_reload_pose", cannon_marker, 0.2)
		await _wait_frames(owner, 1)
		if soldier.get("current_state") != soldier.State.RELOAD:
			failures.append("soldier common reload pose did not enter RELOAD state")
		await _wait_frames(owner, 20)
		if soldier.get("current_state") == soldier.State.RELOAD:
			failures.append("soldier common reload pose did not return to idle")

	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _run_soldier_ship_work_priority_contract(owner: Node, failures: Array[String]) -> void:
	var work_priority_source := FileAccess.get_file_as_string("res://scripts/entities/soldiers/soldier_ship_work_priority_helper.gd")
	if work_priority_source.is_empty():
		failures.append("soldier ship work priority contract could not read helper")
		return
	for token in [
		"TASK_DECK_DEFENSE",
		"TASK_CORPSE_CLEANUP",
		"TASK_CANNON_RELOAD",
		"TASK_RIGGING_REPAIR",
		"TASK_SHIPHANDLING_STATION",
		"static func get_ship_work_directive",
		"static func score_worker_for_task",
		"static func can_accept_immediate_work",
		"static func get_task_priority_rows",
		"TASK_PRIORITY_TABLE",
		"static func reserve_work_slot",
		"static func release_work_slot",
		"static func is_work_slot_reserved_for_other",
		"WORK_SLOT_RESERVATIONS_META",
		"ACTIVE_WORK_TARGET_LOCAL_META",
		"static func get_active_ship_work_target",
		"static func clear_active_ship_work_target",
		"KEY_SLOT",
		"KEY_LOCAL_TARGET",
	]:
		if not work_priority_source.contains(str(token)):
			failures.append("soldier ship work priority helper missing token: %s" % token)
	if not work_priority_source.contains("PRIORITY_CANNON_RELOAD := 70") or not work_priority_source.contains("PRIORITY_SHIPHANDLING_STATION := 42"):
		failures.append("cannon reload should outrank routine shiphandling station work")
	if not work_priority_source.contains("PRIORITY_RIGGING_REPAIR := 62"):
		failures.append("rigging repair should outrank routine shiphandling work")
	_validate_soldier_ship_work_priority_table(failures)

	var duty_source := FileAccess.get_file_as_string("res://scripts/entities/soldiers/soldier_ship_duty_helper.gd")
	if duty_source.is_empty():
		failures.append("soldier ship work priority contract could not read duty helper")
		return
	if not duty_source.contains("SoldierShipWorkPriorityHelper.find_ship_work_target"):
		failures.append("ship duty helper should delegate to ship work priority helper")

	var soldier_source := FileAccess.get_file_as_string("res://scripts/entities/soldiers/soldier.gd")
	if soldier_source.is_empty():
		failures.append("soldier ship work priority contract could not read soldier.gd")
		return
	if not soldier_source.contains("SoldierShipWorkPriorityHelper.can_accept_immediate_work"):
		failures.append("cannon reload pose availability should honor work priority")
	if not soldier_source.contains("SoldierActionHelper.ACTION_CANNON_RELOAD"):
		failures.append("cannon reload pose should use the named action system")
	if not soldier_source.contains("SoldierShipWorkPriorityHelper.release_work_slot"):
		failures.append("cannon reload pose should release its reserved work slot")

	var base_ship_source := FileAccess.get_file_as_string("res://scripts/entities/ships/base_ship.gd")
	if base_ship_source.is_empty():
		failures.append("soldier ship work priority contract could not read base_ship.gd")
		return
	if not base_ship_source.contains("SoldierShipWorkPriorityHelper.score_worker_for_task"):
		failures.append("cannon reload worker selection should use ship work priority scoring")
	if not base_ship_source.contains("SoldierShipWorkPriorityHelper.reserve_work_slot"):
		failures.append("cannon reload worker selection should reserve the cannon work slot")
	_validate_ship_work_target_tracks_moving_ship(owner, failures)


static func _validate_soldier_ship_work_priority_table(failures: Array[String]) -> void:
	var rows := SoldierShipWorkPriorityHelper.get_task_priority_rows()
	if rows.is_empty():
		failures.append("soldier ship work priority table should not be empty")
	var priorities: Dictionary = {}
	var phases: Dictionary = {}
	for row in rows:
		var task_name := str(row.get(SoldierShipWorkPriorityHelper.KEY_TASK, "")).strip_edges()
		if task_name.is_empty():
			failures.append("soldier ship work priority row missing task")
			continue
		if priorities.has(task_name):
			failures.append("soldier ship work priority duplicate task: %s" % task_name)
		var priority := int(row.get(SoldierShipWorkPriorityHelper.KEY_PRIORITY, SoldierShipWorkPriorityHelper.PRIORITY_NONE))
		priorities[task_name] = priority
		var phase := str(row.get(SoldierShipWorkPriorityHelper.KEY_PHASE, "")).strip_edges()
		var runtime := str(row.get(SoldierShipWorkPriorityHelper.KEY_RUNTIME, "")).strip_edges()
		if phase.is_empty():
			failures.append("soldier ship work priority %s missing phase" % task_name)
		if runtime.is_empty():
			failures.append("soldier ship work priority %s missing runtime" % task_name)
		phases[task_name] = phase
		if SoldierShipWorkPriorityHelper.get_task_priority(task_name) != priority:
			failures.append("soldier ship work priority getter mismatch for %s" % task_name)
	var expected_order: Array[String] = [
		SoldierShipWorkPriorityHelper.TASK_DECK_DEFENSE,
		SoldierShipWorkPriorityHelper.TASK_CORPSE_CLEANUP,
		SoldierShipWorkPriorityHelper.TASK_CANNON_RELOAD,
		SoldierShipWorkPriorityHelper.TASK_RIGGING_REPAIR,
		SoldierShipWorkPriorityHelper.TASK_SHIPHANDLING_STATION,
	]
	for task_name in expected_order:
		if not priorities.has(task_name):
			failures.append("soldier ship work priority missing task: %s" % task_name)
	for index in range(expected_order.size() - 1):
		var higher: String = expected_order[index]
		var lower: String = expected_order[index + 1]
		if priorities.has(higher) and priorities.has(lower) and int(priorities[higher]) <= int(priorities[lower]):
			failures.append("soldier ship work priority order invalid: %s should outrank %s" % [higher, lower])
	if SoldierShipWorkPriorityHelper.get_task_phase(SoldierShipWorkPriorityHelper.TASK_CORPSE_CLEANUP) != SoldierShipWorkPriorityHelper.PHASE_CLEANUP:
		failures.append("soldier ship work priority corpse cleanup phase mismatch")
	if priorities.has(SoldierShipWorkPriorityHelper.TASK_GUNNERY_STATION):
		failures.append("routine gunnery station should not remain in the active ship work priority table")
	if SoldierShipWorkPriorityHelper.get_task_priority(SoldierShipWorkPriorityHelper.TASK_GUNNERY_STATION) != SoldierShipWorkPriorityHelper.PRIORITY_NONE:
		failures.append("routine gunnery station should no longer advertise a ship work priority")
	if SoldierShipWorkPriorityHelper.get_task_priority("unknown") != SoldierShipWorkPriorityHelper.PRIORITY_NONE:
		failures.append("soldier ship work priority unknown task should have no priority")


static func _validate_ship_work_target_tracks_moving_ship(owner: Node, failures: Array[String]) -> void:
	var ship := MockShipWorkShip.new()
	ship.name = "ShipWorkTargetShip"
	var soldier := MockShipWorkSoldier.new()
	soldier.name = "ShipWorkTargetSoldier"
	owner.add_child(ship)
	owner.add_child(soldier)
	ship.global_position = Vector3(3.0, 0.0, -4.0)
	soldier.global_position = ship.to_global(Vector3.ZERO)
	soldier.owned_ship = ship

	var first_target := SoldierShipWorkPriorityHelper.find_ship_work_target(soldier)
	if first_target == Vector3.INF:
		failures.append("ship work target contract could not acquire rowing target")
		ship.queue_free()
		soldier.queue_free()
		return
	var first_local := ship.to_local(first_target)
	ship.global_position += Vector3(12.0, 0.0, -3.0)
	var active_target := SoldierShipWorkPriorityHelper.get_active_ship_work_target(soldier)
	if active_target == Vector3.INF:
		failures.append("ship work active target should persist between heavy AI ticks")
	else:
		var active_local := ship.to_local(active_target)
		if active_local.distance_to(first_local) > 0.01:
			failures.append("ship work active target should track the same ship-local slot while the ship moves")
		if active_target.distance_to(first_target) < 3.0:
			failures.append("ship work active target should move with the ship instead of using a stale global point")

	ship.is_rowing = false
	var stale_target := SoldierShipWorkPriorityHelper.get_active_ship_work_target(soldier)
	if stale_target != Vector3.INF:
		failures.append("ship work active rowing target should clear when rowing stops")
	var idle_target := SoldierShipWorkPriorityHelper.find_ship_work_target(soldier)
	if idle_target != Vector3.INF:
		failures.append("ship work target should stay idle when the ship is not rowing, steering, or moving")

	ship.queue_free()
	soldier.queue_free()


static func _run_soldier_smooth_turn_contract(owner: Node, failures: Array[String]) -> void:
	var helper = load("res://scripts/entities/soldiers/soldier_ai_helper.gd")
	if helper == null:
		failures.append("soldier smooth turn contract missing helper")
		return
	var deck := Node3D.new()
	deck.name = "TiltedDeckTurnContract"
	deck.rotation.z = deg_to_rad(18.0)
	owner.add_child(deck)
	var soldier := Node3D.new()
	soldier.name = "TurnSoldier"
	soldier.position = Vector3.ZERO
	soldier.rotation = Vector3(deg_to_rad(12.0), 0.0, deg_to_rad(-9.0))
	deck.add_child(soldier)
	var target := deck.to_global(Vector3(0.0, 0.0, -5.0))
	helper.call("turn_toward_position", soldier, target, 20.0, 0.1)
	if absf(soldier.rotation.x) > 0.001 or absf(soldier.rotation.z) > 0.001:
		failures.append("soldier smooth turn should keep local x/z upright on tilted deck")
	deck.queue_free()


static func _run_boarding_rope_anchor_height_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var source := BaseShip.new()
	source.name = "RopeAnchorSource"
	var target := BaseShip.new()
	target.name = "RopeAnchorTarget"
	owner.add_child(source)
	owner.add_child(target)
	source.global_position = Vector3(0.0, 0.0, 0.0)
	target.global_position = Vector3(5.0, 1.5, 0.0)
	source.deck_height = 0.4
	target.deck_height = 2.2
	source.boarding_target = target
	await _wait_frames(owner, wait_frames_after_attach)

	var source_anchor_local: Vector3 = source.call("_get_boarding_rope_source_anchor_local", 1.0, 0.0)
	var source_anchor_global: Vector3 = source.to_global(source_anchor_local)
	var target_anchor_global: Vector3 = source.call("_get_boarding_rope_target_anchor_global", source_anchor_global)
	var expected_source_y: float = source.global_position.y + source.deck_height + BaseShip.BOARDING_ROPE_DECK_HEIGHT_OFFSET
	var expected_target_y: float = target.global_position.y + target.deck_height + BaseShip.BOARDING_ROPE_DECK_HEIGHT_OFFSET
	if absf(source_anchor_global.y - expected_source_y) > 0.01:
		failures.append("boarding rope source anchor should follow source deck_height")
	if absf(target_anchor_global.y - expected_target_y) > 0.01:
		failures.append("boarding rope target anchor should follow target deck_height")
	if absf(source_anchor_global.y - target_anchor_global.y) < 0.5:
		failures.append("boarding rope anchors should allow visible vertical difference between ship classes")

	var source_authoring := Node3D.new()
	source_authoring.name = "Authoring"
	source.add_child(source_authoring)
	var source_anchor_group := Node3D.new()
	source_anchor_group.name = "BoardingAnchors"
	source_authoring.add_child(source_anchor_group)
	var source_marker := Marker3D.new()
	source_marker.name = "RightMid"
	source_marker.position = Vector3(1.25, 3.4, 0.2)
	source_anchor_group.add_child(source_marker)

	var target_authoring := Node3D.new()
	target_authoring.name = "Authoring"
	target.add_child(target_authoring)
	var target_anchor_group := Node3D.new()
	target_anchor_group.name = "BoardingAnchors"
	target_authoring.add_child(target_anchor_group)
	var target_marker := Marker3D.new()
	target_marker.name = "LeftMid"
	target_marker.position = Vector3(-1.2, 4.8, 0.2)
	target_anchor_group.add_child(target_marker)

	var authored_source_anchor_local: Vector3 = source.call("_get_boarding_rope_source_anchor_local", 1.0, 0.0)
	if authored_source_anchor_local.distance_to(source_marker.position) > 0.01:
		failures.append("boarding rope source should prefer Authoring/BoardingAnchors marker")
	var authored_source_anchor_global: Vector3 = source.to_global(authored_source_anchor_local)
	var authored_target_anchor_global: Vector3 = source.call("_get_boarding_rope_target_anchor_global", authored_source_anchor_global)
	if authored_target_anchor_global.distance_to(target_marker.global_position) > 0.01:
		failures.append("boarding rope target should prefer nearest Authoring/BoardingAnchors marker")

	source.queue_free()
	target.queue_free()
	await _wait_frames(owner, 1)


static func _run_boarding_landing_contract(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var target := BaseShip.new()
	target.name = "BoardingLandingTarget"
	owner.add_child(target)
	target.global_position = Vector3.ZERO
	target.deck_height = 0.6
	await _wait_frames(owner, wait_frames_after_attach)

	var target_half_ext: Vector2 = target.get_deck_half_extents()
	var approach_from_right := target.to_global(Vector3(target_half_ext.x + 8.0, 0.0, 0.35))
	var landing_right: Vector3 = BaseShipBoardingHelper._get_nearest_deck_landing_local(target, approach_from_right)
	if landing_right.x < 0.0:
		failures.append("boarding landing should stay on nearest right-side deck edge")
	if absf(landing_right.x - (target_half_ext.x - BaseShipBoardingHelper.BOARDING_LANDING_INSET)) > 0.05:
		failures.append("boarding landing should inset from nearest side edge")
	if absf(landing_right.z - 0.35) > 0.05:
		failures.append("boarding landing should preserve nearby along-deck coordinate")

	var approach_from_stern := target.to_global(Vector3(-0.25, 0.0, -target_half_ext.y - 7.0))
	var landing_stern: Vector3 = BaseShipBoardingHelper._get_nearest_deck_landing_local(target, approach_from_stern)
	if landing_stern.z > 0.0:
		failures.append("boarding landing should stay on nearest stern-side deck edge")
	if absf(landing_stern.x + 0.25) > 0.05:
		failures.append("boarding landing should preserve nearby lateral coordinate")

	target.queue_free()
	await _wait_frames(owner, 1)


static func _run_weapon_damage_grouping_contract(failures: Array[String]) -> void:
	var level_manager_script := load("res://scripts/managers/level_manager.gd") as Script
	if level_manager_script == null:
		failures.append("weapon damage grouping contract missing level manager script")
		return
	var lm := level_manager_script.new() as Node
	lm.weapon_damage_stats = {}
	lm.add_player_weapon_damage("cannon:FleetCannon_0", 100.0)
	lm.add_player_weapon_damage("cannon:FleetCannon_1", 75.0)
	lm.add_player_weapon_damage("cannon_crit:CannonRight", 25.0)
	lm.add_player_weapon_damage("bow", 10.0)

	var rows: Array = lm.get_weapon_damage_rows(8)
	var cannon_rows := 0
	var cannon_damage := 0.0
	for row in rows:
		if str(row.get("id", "")) == "cannon":
			cannon_rows += 1
			cannon_damage = float(row.get("damage", 0.0))
	if cannon_rows != 1:
		failures.append("weapon damage grouping should produce exactly one cannon row")
	if absf(cannon_damage - 200.0) > 0.01:
		failures.append("weapon damage grouping should merge all cannon damage")
	lm.queue_free()


static func _run_result_scene_wiring_pass(owner: Node, failures: Array[String], wait_frames_after_attach: int) -> void:
	var packed := load("res://scenes/ui/result_screen.tscn") as PackedScene
	if packed == null:
		failures.append("result scene wiring load failed")
		return
	var result_root := packed.instantiate()
	if result_root == null:
		failures.append("result scene wiring instantiate failed")
		return
	owner.add_child(result_root)
	await _wait_frames(owner, wait_frames_after_attach)
	for node_path in ["Content/TitleBlock/Title", "Content/TitleBlock/Subtitle", "Content/Body/SummaryPanel/Margin/SummaryList", "Content/Body/WeaponPanel/Margin/WeaponList", "ButtonBlock/RestartButton", "ButtonBlock/MainMenuButton"]:
		if result_root.get_node_or_null(str(node_path)) == null:
			failures.append("result scene wiring missing node: %s" % node_path)
	for button_path in ["ButtonBlock/RestartButton", "ButtonBlock/MainMenuButton"]:
		var button := result_root.get_node_or_null(button_path) as BaseButton
		if is_instance_valid(button) and not button.has_meta(UiButtonAudio.WIRED_META):
			failures.append("result scene button missing ui click sound: %s" % button_path)
	var button_block := result_root.get_node_or_null("ButtonBlock") as Control
	var content := result_root.get_node_or_null("Content") as Control
	if is_instance_valid(button_block) and is_instance_valid(content):
		if button_block.get_parent() == content:
			failures.append("result scene ButtonBlock should not be inside scrolling/result content")
		if button_block.anchor_top < 0.98 or button_block.offset_bottom > -8.0:
			failures.append("result scene ButtonBlock should be pinned inside bottom safe area")
	result_root.queue_free()
	await _wait_frames(owner, 1)


static func _run_main_player_effect_scene_wiring_pass(failures: Array[String]) -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		failures.append("main scene wiring load failed")
		return
	var main_root := packed.instantiate()
	if main_root == null:
		failures.append("main scene wiring instantiate failed")
		return
	var player_ship := main_root.get_node_or_null("PlayerShip")
	if not is_instance_valid(player_ship):
		failures.append("main scene wiring missing PlayerShip")
		main_root.queue_free()
		return
	var player_start := main_root.get_node_or_null("PlayerStart") as Node3D
	if not is_instance_valid(player_start):
		failures.append("main scene wiring missing PlayerStart")
	elif player_start.global_position.distance_to(Vector3(-1.709, 0.2, 15.673)) > 0.01:
		failures.append("main scene PlayerStart moved unexpectedly: %s" % player_start.global_position)

	if player_ship.transform != Transform3D.IDENTITY:
		failures.append("main scene PlayerShip should not carry placement override")

	var screen_edge_fx := main_root.get_node_or_null("ScreenEdgeFx") as CanvasLayer
	if not is_instance_valid(screen_edge_fx):
		failures.append("main scene wiring missing ScreenEdgeFx")
	elif screen_edge_fx.layer >= 1:
		failures.append("ScreenEdgeFx should render below gameplay HUD canvas layers")
	elif screen_edge_fx.get_node_or_null("Overlay") == null:
		failures.append("ScreenEdgeFx should include a full-screen Overlay ColorRect")

	var max_hull_hp = player_ship.get("max_hull_hp")
	if max_hull_hp != null and float(max_hull_hp) < 100.0:
		failures.append("main scene PlayerShip max_hull_hp suspiciously low: %.2f" % float(max_hull_hp))

	_validate_packed_scene_path(player_ship, "wood_splinter_scene", "res://scenes/effects/wood_splinter.tscn", failures)
	_validate_packed_scene_path(player_ship, "water_splash_scene", "res://scenes/effects/water_burst.tscn", failures)
	_validate_packed_scene_path(player_ship, "fire_effect_scene", "res://scenes/effects/fire_effect.tscn", failures)
	_validate_packed_scene_path(player_ship, "survivor_scene", "res://scenes/effects/survivor.tscn", failures)
	_run_main_player_ship_text_contract(failures)
	main_root.queue_free()


static func _run_main_player_ship_text_contract(failures: Array[String]) -> void:
	var file := FileAccess.open("res://scenes/main.tscn", FileAccess.READ)
	if file == null:
		failures.append("main scene text contract could not open main.tscn")
		return
	var text := file.get_as_text()
	var marker := "[node name=\"PlayerShip\""
	var start_index := text.find(marker)
	if start_index < 0:
		failures.append("main scene text contract missing PlayerShip block")
		return
	var next_node_index := text.find("\n[node ", start_index + marker.length())
	var block := text.substr(start_index) if next_node_index < 0 else text.substr(start_index, next_node_index - start_index)
	var lines := block.split("\n")
	for line in lines:
		var stripped := str(line).strip_edges()
		if stripped.is_empty() or stripped.begins_with("[node "):
			continue
		var property_end := stripped.find(" =")
		if property_end > 0:
			failures.append("main scene PlayerShip should not override %s" % stripped.substr(0, property_end))


static func _validate_packed_scene_path(node: Node, property_name: String, expected_path: String, failures: Array[String]) -> void:
	var value = node.get(property_name)
	if not (value is PackedScene):
		failures.append("main scene PlayerShip %s is not a PackedScene" % property_name)
		return
	var actual_path := (value as PackedScene).resource_path
	if actual_path != expected_path:
		failures.append("main scene PlayerShip %s mismatch: %s" % [property_name, actual_path])


static func _run_single_scene_wiring_pass(owner: Node, failures: Array[String], scene_path: String, label: String, expected_team: String, expected_player_controlled: bool, expected_groups: Array, required_nodes: Array, forbidden_nodes: Array, require_hull: bool, require_boss_group: bool, expected_allow_boarding, wait_frames_after_attach: int) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("scene wiring load failed: %s" % scene_path)
		return

	var scene_root := packed.instantiate()
	if scene_root == null:
		failures.append("scene wiring instantiate failed: %s" % scene_path)
		return

	var wrapper := Node3D.new()
	wrapper.name = "%s_WiringSmoke" % label.replace(" ", "_")
	owner.add_child(wrapper)
	wrapper.add_child(scene_root)
	await _wait_frames(owner, wait_frames_after_attach)

	if scene_root.has_method("get_team_tag"):
		var actual_team: String = str(scene_root.get_team_tag())
		if actual_team != expected_team:
			failures.append("%s wiring team mismatch: %s" % [label, actual_team])
	if scene_root.has_method("is_player_controlled_ship"):
		var actual_player_controlled: bool = scene_root.is_player_controlled_ship() == true
		if actual_player_controlled != expected_player_controlled:
			failures.append("%s wiring player-controlled mismatch" % label)
	for group_name in expected_groups:
		if not scene_root.is_in_group(str(group_name)):
			failures.append("%s missing group tag: %s" % [label, group_name])
	for node_name in required_nodes:
		if scene_root.get_node_or_null(str(node_name)) == null:
			failures.append("%s missing required node: %s" % [label, node_name])
	for node_name in forbidden_nodes:
		if scene_root.get_node_or_null(str(node_name)) != null:
			failures.append("%s still has forbidden legacy node: %s" % [label, node_name])
	if require_hull and not _has_hull_child(scene_root):
		failures.append("%s missing runtime hull child" % label)
	if require_boss_group and not scene_root.is_in_group("boss"):
		failures.append("%s missing boss group tag after ready" % label)
	if expected_allow_boarding != null:
		var actual_allow_boarding: bool = scene_root.get("allow_boarding") == true
		if actual_allow_boarding != (expected_allow_boarding == true):
			failures.append("%s allow_boarding mismatch" % label)
		if scene_root.has_method("is_boarding_ship") and scene_root.is_boarding_ship() != true and expected_allow_boarding == true:
			failures.append("%s expected boarding-capable ship" % label)
	ShipAuthoringHelper.validate_ship_authoring(scene_root, label, failures)

	scene_root.queue_free()
	wrapper.queue_free()
	await _wait_frames(owner, 1)


static func _has_hull_child(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	for child in ship.get_children():
		if child is Node and str(child.name).contains("Hull"):
			return true
	return false


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
