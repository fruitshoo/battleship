extends Node

const SoldierVisualHelper = preload("res://scripts/entities/soldiers/soldier_visual_helper.gd")
const SoldierWeaponHelper = preload("res://scripts/entities/soldiers/soldier_weapon_helper.gd")
const SoldierAiHelper = preload("res://scripts/entities/soldiers/soldier_ai_helper.gd")
const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")
const SoldierScript = preload("res://scripts/entities/soldiers/soldier.gd")
const SOLDIER_SCENE = preload("res://scenes/entities/soldiers/soldier.tscn")


class MockShip:
	extends Node3D

	var team: String = "player"
	var is_sinking: bool = false
	var is_dying: bool = false
	var derelict_checks: int = 0
	var base_collision_radius: float = 4.5
	var width_multiplier: float = 1.0
	var length_multiplier: float = 1.0
	var deck_height: float = 0.0

	func get_team_tag() -> String:
		return team

	func is_sinking_or_dying() -> bool:
		return is_sinking or is_dying

	func check_derelict_status() -> void:
		derelict_checks += 1


class MockWeapon:
	extends Node3D

	var attack_range: float = 1.2
	var max_range: float = 0.0
	var weapon_id: String = ""

	func _init(next_weapon_id: String = "", next_attack_range: float = 1.2, next_max_range: float = 0.0) -> void:
		weapon_id = next_weapon_id
		attack_range = next_attack_range
		max_range = next_max_range
		set_meta("weapon_id", weapon_id)

	func set_visual_visible(_make_visible: bool) -> void:
		pass


class MockSoldier:
	extends Node3D

	enum State {
		IDLE,
		MOVE,
		ATTACK,
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

	var weapon_sword: Node3D = null
	var weapon_bow: Node3D = null
	var current_weapon: Node3D = null
	var weapon_switch_distance: float = 4.0
	var cross_ship_melee_switch_distance: float = 6.8
	var crew_role: String = "general"
	var is_melee_only: bool = false
	var is_ranged_only: bool = false
	var cross_ship_close: bool = false
	var cross_ship_contact_ready: bool = false
	var detection_range: float = 35.0

	func _flash_hit() -> void:
		pass

	func _play_death_pose() -> void:
		death_pose_count += 1

	func _play_recovery_pose() -> void:
		recovery_pose_count += 1

	func add_soldier_xp(amount: float, _reason: String = "") -> void:
		soldier_xp += amount
		xp_awards += 1

	func _set_active_weapon(type: String) -> void:
		if type == "sword":
			current_weapon = weapon_sword
		elif type == "bow":
			current_weapon = weapon_bow

	func _is_ship_pair_in_melee_range(_other_ship: Node3D) -> bool:
		return cross_ship_close

	func _is_in_cross_ship_contact_zone(_other_ship: Node3D) -> bool:
		return cross_ship_contact_ready

	func _change_state(next_state: int) -> void:
		current_state = next_state

	func get_current_state_value() -> int:
		return current_state

	func get_team_tag() -> String:
		return team

	func get_owned_ship_node() -> Node3D:
		return owned_ship

	func find_nearest_hostile_on_owned_ship() -> Node3D:
		return null


func _ready() -> void:
	var failures: Array[String] = []
	_verify_player_combat_damage_incapacitates(failures)
	_verify_defense_reduction_mitigates_player_damage(failures)
	_verify_heal_full_recovers_incapacitated_player(failures)
	_verify_recovery_uses_ship_medical_upgrade_stats(failures)
	_verify_shipmate_assisted_recovery_recovers_incapacitated_player(failures)
	_verify_shipmate_assist_uses_standoff_without_pushing(failures)
	_verify_player_soldier_level_progression(failures)
	_verify_cross_ship_standoff_prefers_bow_until_melee_reaches(failures)
	_verify_cross_ship_attack_state_exits_unreachable_melee(failures)
	_verify_soldier_visual_slot_contract(failures)
	_verify_dead_boarding_jump_finish_keeps_death_pose(failures)
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


func _verify_shipmate_assisted_recovery_recovers_incapacitated_player(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	ship.set_meta("incapacitated_assist_health_ratio", 0.5)
	var soldiers := Node3D.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)
	var downed = SOLDIER_SCENE.instantiate()
	var helper = SOLDIER_SCENE.instantiate()
	if downed == null or helper == null:
		failures.append("shipmate assist recovery could not instantiate soldier scene")
		return
	downed.team = "player"
	helper.team = "player"
	downed.set("player_visual_scene", null)
	downed.set("enemy_visual_scene", null)
	downed.set("captain_visual_scene", null)
	helper.set("player_visual_scene", null)
	helper.set("enemy_visual_scene", null)
	helper.set("captain_visual_scene", null)
	soldiers.add_child(downed)
	soldiers.add_child(helper)
	downed.owned_ship = ship
	downed.home_ship = ship
	helper.owned_ship = ship
	helper.home_ship = ship
	downed.current_health = 8.0
	downed.global_position = Vector3.ZERO
	helper.global_position = Vector3(0.65, 0.0, 0.0)

	SoldierLifecycleHelper.take_damage(downed, 20.0, Vector3.ZERO, "sword")
	var assist_started: bool = helper._try_assist_incapacitated_ally(0.6, 0.72, 7.0)
	if helper.get_named_action() != SoldierActionHelper.ACTION_INCAPACITATED_ASSIST:
		failures.append("shipmate assist recovery did not enter the revive assist action")
	if SoldierActionHelper.get_action_animation_name(helper) != SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY:
		failures.append("shipmate assist recovery did not reuse the corpse cleanup carry animation")
	if helper.get_carry_payload() != downed:
		failures.append("shipmate assist recovery did not bind the downed ally as a temporary pickup payload")
	var assist_definition := SoldierActionHelper.get_action_definition(SoldierActionHelper.ACTION_INCAPACITATED_ASSIST)
	if assist_definition.get(SoldierActionHelper.ACTION_DEF_LOCKS_AI, true) != false:
		failures.append("shipmate assist recovery action should not lock AI while channeling")
	var downed_during_channel: Vector3 = downed.global_position
	if Vector2(downed_during_channel.x, downed_during_channel.z).distance_to(Vector2.ZERO) > 0.05:
		failures.append("shipmate assist recovery dragged the downed ally away from the fall position during channel")
	var assist_finished: bool = helper._try_assist_incapacitated_ally(0.6, 0.72, 7.0)

	if not assist_started or not assist_finished:
		failures.append("shipmate assist recovery did not engage the incapacitated ally")
	if downed.current_state != SoldierScript.State.IDLE:
		failures.append("shipmate assist recovery did not return incapacitated ally to idle")
	var expected_health: float = downed.max_health * 0.5
	if not is_equal_approx(downed.current_health, expected_health):
		failures.append("shipmate assist recovery did not use ship recovery health ratio: %.2f vs %.2f" % [downed.current_health, expected_health])
	if helper.has_meta("incapacitated_assist_target_id"):
		failures.append("shipmate assist recovery left stale assist target metadata on helper")
	if helper.has_named_action(SoldierActionHelper.ACTION_INCAPACITATED_ASSIST):
		failures.append("shipmate assist recovery left the revive assist action active")
	if helper.get_carry_payload() != null or downed.has_meta(SoldierActionHelper.CARRY_PAYLOAD_OWNER_META):
		failures.append("shipmate assist recovery left stale temporary pickup payload metadata")
	if not is_equal_approx(downed.global_position.y, helper.global_position.y):
		failures.append("shipmate assist recovery did not settle the recovered ally back onto deck height")
	if Vector2(downed.global_position.x, downed.global_position.z).distance_to(Vector2.ZERO) > 0.05:
		failures.append("shipmate assist recovery recovered the ally away from the original fall position")


func _verify_shipmate_assist_uses_standoff_without_pushing(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	ship.set_meta("incapacitated_assist_health_ratio", 0.5)
	var soldiers := Node3D.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)
	var downed = SOLDIER_SCENE.instantiate()
	var helper = SOLDIER_SCENE.instantiate()
	if downed == null or helper == null:
		failures.append("shipmate standoff assist could not instantiate soldier scene")
		return
	downed.team = "player"
	helper.team = "player"
	downed.set("player_visual_scene", null)
	downed.set("enemy_visual_scene", null)
	downed.set("captain_visual_scene", null)
	helper.set("player_visual_scene", null)
	helper.set("enemy_visual_scene", null)
	helper.set("captain_visual_scene", null)
	soldiers.add_child(downed)
	soldiers.add_child(helper)
	downed.owned_ship = ship
	downed.home_ship = ship
	helper.owned_ship = ship
	helper.home_ship = ship
	downed.current_health = 8.0
	downed.global_position = Vector3(3.7, 0.0, 0.0)
	helper.global_position = Vector3(0.4, 0.0, 0.0)

	SoldierLifecycleHelper.take_damage(downed, 20.0, Vector3.ZERO, "sword")
	var target_pos: Vector3 = downed.global_position
	target_pos.y = helper.global_position.y
	var use_range: float = helper._get_incapacitated_assist_use_range()
	var stand_pos: Vector3 = helper._get_incapacitated_assist_stand_position(downed, use_range)
	if stand_pos.distance_to(target_pos) < use_range:
		failures.append("shipmate standoff assist still selected a body-overlapping approach point")
	var half_ext: Vector2 = helper._get_ship_deck_half_extents(ship)
	var local_stand: Vector3 = ship.to_local(stand_pos)
	if absf(local_stand.x) > half_ext.x or absf(local_stand.z) > half_ext.y:
		failures.append("shipmate standoff assist selected an approach point outside the deck")

	var downed_before_approach: Vector3 = downed.global_position
	var approach_started: bool = helper._try_assist_incapacitated_ally(0.18, 0.72, 7.0)
	if not approach_started:
		failures.append("shipmate standoff assist did not engage the downed ally")
	if helper.get_named_action() == SoldierActionHelper.ACTION_INCAPACITATED_ASSIST:
		failures.append("shipmate standoff assist started channeling before reaching its stand point")
	if downed.global_position.distance_to(downed_before_approach) > 0.01:
		failures.append("shipmate standoff assist pushed the downed ally while approaching")

	helper.global_position = stand_pos
	helper._try_assist_incapacitated_ally(0.6, 0.72, 7.0)
	if downed.global_position.distance_to(downed_before_approach) > 0.05:
		failures.append("shipmate standoff assist dragged the downed ally while channeling")
	helper._try_assist_incapacitated_ally(0.6, 0.72, 7.0)
	if downed.current_state != SoldierScript.State.IDLE:
		failures.append("shipmate standoff assist did not recover the ally from its stand point")
	var local_recovered: Vector3 = ship.to_local(downed.global_position)
	if absf(local_recovered.x) > half_ext.x or absf(local_recovered.z) > half_ext.y:
		failures.append("shipmate standoff assist recovered ally outside the deck bounds")


func _verify_player_soldier_level_progression(failures: Array[String]) -> void:
	var soldier = SoldierScript.new()
	soldier.team = "player"
	soldier.add_soldier_xp(1.0, "contract")
	if soldier.get_soldier_level_value() != 1 or not is_equal_approx(soldier.get_soldier_xp_value(), 1.0):
		failures.append("player soldier level changed before reaching level xp requirement")

	soldier.add_soldier_xp(1.0, "contract")
	if soldier.get_soldier_level_value() != 2:
		failures.append("player soldier did not reach level 2 at xp requirement")
	if not is_equal_approx(float(soldier.get_meta("soldier_level_damage_bonus_pct", 0.0)), 0.08):
		failures.append("player soldier level 2 damage bonus was not applied")

	soldier.add_soldier_xp(100.0, "contract")
	if soldier.get_soldier_level_value() != 5:
		failures.append("player soldier level did not clamp at cap")
	if not is_equal_approx(soldier.get_soldier_xp_value(), 0.0):
		failures.append("player soldier xp did not clear at level cap")
	soldier.free()


func _verify_cross_ship_standoff_prefers_bow_until_melee_reaches(failures: Array[String]) -> void:
	var player_ship := _make_ship("player")
	player_ship.global_position = Vector3.ZERO
	var enemy_ship := _make_ship("enemy")
	enemy_ship.global_position = Vector3(5.0, 0.0, 0.0)

	var soldier := _make_soldier("player", player_ship)
	soldier.global_position = Vector3.ZERO
	soldier.weapon_sword = MockWeapon.new("sword", 1.2, 0.0)
	soldier.weapon_bow = MockWeapon.new("bow", 20.0, 20.0)
	add_child(soldier.weapon_sword)
	add_child(soldier.weapon_bow)
	soldier.current_weapon = soldier.weapon_sword
	soldier.cross_ship_close = true
	soldier.cross_ship_contact_ready = true

	var target := _make_soldier("enemy", enemy_ship)
	target.global_position = Vector3(5.0, 0.0, 0.0)

	SoldierWeaponHelper.update_combat_weapon_choice(soldier, target)
	if soldier.current_weapon != soldier.weapon_bow:
		failures.append("cross-ship rail standoff did not prefer bow while melee could not reach")

	target.global_position = Vector3(1.35, 0.0, 0.0)
	SoldierWeaponHelper.update_combat_weapon_choice(soldier, target)
	if soldier.current_weapon != soldier.weapon_sword:
		failures.append("cross-ship close contact did not allow melee after it could reach")


func _verify_cross_ship_attack_state_exits_unreachable_melee(failures: Array[String]) -> void:
	var player_ship := _make_ship("player")
	player_ship.global_position = Vector3.ZERO
	var enemy_ship := _make_ship("enemy")
	enemy_ship.global_position = Vector3(5.0, 0.0, 0.0)

	var soldier := _make_soldier("player", player_ship)
	soldier.global_position = Vector3.ZERO
	soldier.weapon_sword = MockWeapon.new("sword", 1.2, 0.0)
	soldier.weapon_bow = MockWeapon.new("bow", 20.0, 20.0)
	add_child(soldier.weapon_sword)
	add_child(soldier.weapon_bow)
	soldier.current_weapon = soldier.weapon_sword
	soldier.current_state = soldier.State.ATTACK
	soldier.cross_ship_close = true
	soldier.cross_ship_contact_ready = true

	var target := _make_soldier("enemy", enemy_ship)
	target.global_position = Vector3(5.0, 0.0, 0.0)
	soldier.current_target = target

	SoldierAiHelper.state_attack(soldier)
	if soldier.current_state != soldier.State.MOVE:
		failures.append("cross-ship attacker stayed in unreachable melee attack state")

	SoldierWeaponHelper.update_combat_weapon_choice(soldier, target)
	if soldier.current_weapon != soldier.weapon_bow:
		failures.append("cross-ship attacker did not switch to bow after leaving unreachable melee")


func _verify_soldier_visual_slot_contract(failures: Array[String]) -> void:
	var soldier := SOLDIER_SCENE.instantiate()
	if soldier == null:
		failures.append("soldier visual scene contract could not instantiate soldier")
		return
	soldier.team = "player"
	soldier.set("player_visual_scene", null)
	soldier.set("enemy_visual_scene", null)
	soldier.set("captain_visual_scene", null)
	add_child(soldier)

	var visual_root := soldier.get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		failures.append("soldier visual scene contract missing VisualRoot")
		soldier.queue_free()
		return

	var fallback_mesh := soldier.get_node_or_null("VisualRoot/MeshInstance3D") as MeshInstance3D
	if fallback_mesh == null:
		failures.append("soldier visual scene contract missing fallback body mesh")
	if SoldierVisualHelper.get_body_mesh(soldier) != fallback_mesh:
		failures.append("soldier visual helper did not resolve fallback body mesh")
	soldier.set("is_captain", true)
	soldier.call("_update_role_visual")
	if soldier.get_node_or_null("CaptainMarker") != null:
		failures.append("soldier visual helper still creates captain marker")

	var custom_root := Node3D.new()
	custom_root.name = "CustomSoldierVisual"
	var custom_hat := MeshInstance3D.new()
	custom_hat.name = "Hat"
	custom_hat.mesh = BoxMesh.new()
	custom_root.add_child(custom_hat)
	custom_hat.owner = custom_root
	var custom_model_root := Node3D.new()
	custom_model_root.name = "ModelRoot"
	custom_root.add_child(custom_model_root)
	custom_model_root.owner = custom_root
	var custom_body := MeshInstance3D.new()
	custom_body.name = "Body"
	custom_body.mesh = BoxMesh.new()
	custom_model_root.add_child(custom_body)
	custom_body.owner = custom_root
	var custom_scene := PackedScene.new()
	var pack_result := custom_scene.pack(custom_root)
	custom_root.free()
	if pack_result != OK:
		failures.append("soldier visual scene contract could not pack custom visual")
		soldier.queue_free()
		return

	soldier.set("player_visual_scene", custom_scene)
	soldier.call("_setup_soldier_visual")
	var custom_visual := soldier.get_node_or_null("VisualRoot/CustomVisual") as Node3D
	var custom_mesh: MeshInstance3D = null
	if custom_visual != null:
		custom_mesh = custom_visual.get_node_or_null("ModelRoot/Body") as MeshInstance3D
	if custom_visual == null or custom_mesh == null:
		failures.append("soldier visual scene contract did not instantiate custom visual")
	elif SoldierVisualHelper.get_body_mesh(soldier) != custom_mesh:
		failures.append("soldier visual helper did not resolve custom visual body mesh")
	if custom_visual != null and SoldierVisualHelper.get_pose_node(soldier) != custom_visual:
		failures.append("soldier visual helper did not resolve custom visual pose root")
	if fallback_mesh != null and fallback_mesh.visible:
		failures.append("soldier visual scene contract did not hide fallback mesh behind custom visual")

	soldier.queue_free()


func _verify_dead_boarding_jump_finish_keeps_death_pose(failures: Array[String]) -> void:
	var ship := _make_ship("player")
	var soldiers := Node3D.new()
	soldiers.name = "Soldiers"
	ship.add_child(soldiers)

	var soldier := SOLDIER_SCENE.instantiate()
	if soldier == null:
		failures.append("boarding jump death contract could not instantiate soldier")
		return
	soldier.team = "enemy"
	soldier.set("player_visual_scene", null)
	soldier.set("enemy_visual_scene", null)
	soldier.set("captain_visual_scene", null)
	soldiers.add_child(soldier)
	soldier.owned_ship = ship
	soldier.home_ship = ship

	soldier.begin_boarding_jump_pose("boarding")
	SoldierLifecycleHelper.die(soldier)
	var hand_pivot := soldier.get_node_or_null("HandPivot") as Node3D
	if hand_pivot == null:
		failures.append("boarding jump death contract missing hand pivot")
		soldier.queue_free()
		return
	if hand_pivot.visible:
		failures.append("dead boarding jumper did not hide weapon hand on death")

	soldier.finish_boarding_jump_pose("on_deck")

	if soldier.current_state != soldier.State.DEAD:
		failures.append("finishing a dead boarding jump changed the soldier state")
	if soldier.is_jumping_value() != false:
		failures.append("finishing a dead boarding jump did not clear jumping flag")
	if hand_pivot.visible:
		failures.append("finishing a dead boarding jump restored the standing/recovery pose")

	soldier.queue_free()


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
