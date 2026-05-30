extends RefCounted
class_name SoldierLifecycleHelper


const BloodDeckDecalHelper = preload("res://scripts/effects/blood_deck_decal_helper.gd")
const SoldierCaptainGuardHelper = preload("res://scripts/entities/soldiers/soldier_captain_guard_helper.gd")
const SoldierDeckZoneHelper = preload("res://scripts/entities/soldiers/soldier_deck_zone_helper.gd")

const MELEE_DAMAGE_SOURCES := {
	"sword": true,
	"spear": true,
	"trident": true,
	"harpoon": true,
}
const PLAYER_INCAPACITATED_RECOVERY_DELAY: float = 16.0
const PLAYER_INCAPACITATED_RECOVERY_HEALTH_RATIO: float = 0.35
const PLAYER_INCAPACITATED_MIN_RECOVERY_DELAY: float = 3.0
const SUPPORT_RESCUE_BOARDING_PURPOSE := ShipBoardingMetaHelper.PURPOSE_SUPPORT_RESCUE
const ENEMY_SINKING_REWARD_ACCOUNTED_META := "enemy_sinking_reward_accounted"
const SOLDIER_DEATH_PITCH_MIN: float = 1.18
const SOLDIER_DEATH_PITCH_MAX: float = 1.32
const SOLDIER_DEATH_VOLUME_DB: float = -1.0
const SOLDIER_SINKING_DEATH_VOLUME_DB: float = -10.0
const SOLDIER_SINKING_SPLASH_VOLUME_DB: float = -6.0
const DEFAULT_SHIP_RANGED_COVER_DEFENSE_BONUS: float = 1.0
const SHIP_RANGED_COVER_BASE_DEFENSE_META := "crew_ranged_cover_base_defense"
const COMBAT_INCAPACITATION_CHANCE_META := "combat_incapacitation_chance"
const SHIP_COMBAT_INCAPACITATION_CHANCE_META := "crew_combat_incapacitation_chance"


static func take_damage(soldier, amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if soldier.current_state == soldier.State.DEAD:
		return
	if soldier.get_meta("ballistic_collateral_pending", false) == true:
		return

	var defense_bonus: float = 0.0
	if soldier.has_meta("defense_flat_bonus"):
		defense_bonus = maxf(0.0, float(soldier.get_meta("defense_flat_bonus")))
	defense_bonus += get_ship_ranged_cover_defense_bonus(soldier, damage_source)
	var final_damage: float = maxf(amount - (soldier.defense + defense_bonus), 1.0)
	final_damage = SoldierCaptainGuardHelper.apply_damage_protection(soldier, final_damage)
	if final_damage > 0.001:
		soldier.current_health -= final_damage
	soldier.set_meta("last_damage_source", damage_source)
	if soldier.has_method("mark_recent_combat_damage"):
		soldier.mark_recent_combat_damage()
	soldier.set_meta("last_death_cause", "combat")

	if final_damage > 0.001 and not damage_source.is_empty() and soldier.team == "enemy":
		if soldier._cached_level_manager and soldier._cached_level_manager.has_method("add_player_weapon_damage"):
			soldier._cached_level_manager.add_player_weapon_damage(damage_source, final_damage)

	if soldier.has_method("_flash_hit"):
		soldier._flash_hit()

	if final_damage > 0.001:
		BloodDeckDecalHelper.try_spawn_from_soldier_damage(soldier, final_damage, hit_position, damage_source)

	if final_damage > 0.001 and hit_position != Vector3.ZERO and soldier.current_state != soldier.State.DEAD:
		var knock_dir: Vector3 = soldier.global_position - hit_position
		knock_dir.y = 0.0
		if knock_dir.length_squared() > 0.001:
			knock_dir = knock_dir.normalized()
			soldier.velocity += knock_dir * minf(final_damage * 0.2, 3.5)

	if soldier.current_health <= 0.0:
		if _should_incapacitate_instead_of_die(soldier):
			incapacitate(soldier)
			return
		die(soldier)


static func get_ship_ranged_cover_reduction(soldier, damage_source: String) -> float:
	return 0.0


static func get_ship_ranged_cover_defense_bonus(soldier, damage_source: String) -> float:
	if not soldier.RANGED_DAMAGE_SOURCES.has(damage_source):
		return 0.0
	if not is_instance_valid(soldier.owned_ship):
		return 0.0
	if soldier.team == "enemy" and soldier.owned_ship.get("team") == "player":
		return 0.0
	if soldier.current_state == soldier.State.DEAD:
		return 0.0
	if SoldierDeckZoneHelper.is_roof(soldier):
		return 0.0
	var base_bonus: float = DEFAULT_SHIP_RANGED_COVER_DEFENSE_BONUS
	if soldier.owned_ship.has_meta(SHIP_RANGED_COVER_BASE_DEFENSE_META):
		base_bonus = maxf(0.0, float(soldier.owned_ship.get_meta(SHIP_RANGED_COVER_BASE_DEFENSE_META)))
	var upgrade_bonus: float = 0.0
	if soldier.owned_ship.has_meta("crew_ranged_cover_defense_bonus"):
		upgrade_bonus = maxf(0.0, float(soldier.owned_ship.get_meta("crew_ranged_cover_defense_bonus")))
	return base_bonus + upgrade_bonus


static func update_boarding_chaos(soldier, delta: float) -> void:
	if soldier.current_state == soldier.State.DEAD:
		return
	if not is_instance_valid(soldier.owned_ship):
		return
	if soldier.team != "enemy":
		return
	if soldier.owned_ship.get("team") != "player":
		return

	soldier.is_boarder_on_player_ship = true
	if not is_instance_valid(soldier.current_target):
		var nearest_target: Node3D = _find_nearest_hostile_on_owned_ship(soldier)
		if is_instance_valid(nearest_target) and soldier.has_method("move_to_target"):
			soldier.move_to_target(nearest_target)
	if _is_fighting_defender_on_owned_ship(soldier) or _is_support_rescue_boarding_active(soldier.owned_ship):
		soldier.chaos_tick_timer = maxf(soldier.chaos_tick_timer, 0.35)
		return

	soldier.chaos_tick_timer -= delta

	if soldier.chaos_tick_timer <= 0.0:
		soldier.chaos_tick_timer = 1.0
		var chaos_damage: float = soldier.chaos_damage_per_tick
		if soldier.owned_ship.has_method("take_fire_damage"):
			soldier.owned_ship.take_fire_damage(chaos_damage, 2.0)
		elif soldier.owned_ship.has_method("take_damage"):
			soldier.owned_ship.take_damage(chaos_damage, soldier.global_position, "boarding_fire")


static func _is_fighting_defender_on_owned_ship(soldier) -> bool:
	if not is_instance_valid(soldier.owned_ship):
		return false
	if not is_instance_valid(soldier.current_target):
		return false
	var target: Node = soldier.current_target
	if SoldierStateHelper.is_dead_soldier(target):
		return false
	if not SoldierDeckZoneHelper.can_share_combat_zone(soldier, target):
		return false
	var target_team: String = target.get_team_tag() if target.has_method("get_team_tag") else str(target.get("team"))
	if target_team == soldier.team:
		return false
	var target_ship: Variant = target.get("owned_ship") if target.get("owned_ship") != null else null
	if is_instance_valid(target_ship):
		return target_ship == soldier.owned_ship
	var parent := target.get_parent()
	if parent == soldier.owned_ship:
		return true
	if is_instance_valid(parent) and parent.get_parent() == soldier.owned_ship:
		return true
	return false


static func _is_support_rescue_boarding_active(player_ship: Node) -> bool:
	if not is_instance_valid(player_ship):
		return false
	for support_ship in EntityRegistry.get_ships_by_team("player"):
		if not is_instance_valid(support_ship) or support_ship == player_ship:
			continue
		if support_ship.get_meta("support_fleet_ship", false) != true:
			continue
		if support_ship.get("is_boarding") != true:
			continue
		if support_ship.get("boarding_target") != player_ship:
			continue
		if not ShipBoardingMetaHelper.is_boarding_purpose(support_ship, SUPPORT_RESCUE_BOARDING_PURPOSE):
			continue
		return true
	return false


static func _find_nearest_hostile_on_owned_ship(soldier) -> Node3D:
	if not is_instance_valid(soldier.owned_ship):
		return null
	var candidates: Array = []
	var soldiers_node: Node = NodeContractHelper.get_soldiers_container(soldier.owned_ship)
	if is_instance_valid(soldiers_node):
		candidates = soldiers_node.get_children()
	for registered_soldier in EntityRegistry.get_soldiers_by_ship(soldier.owned_ship):
		if not candidates.has(registered_soldier):
			candidates.append(registered_soldier)
	var nearest: Node3D = null
	var nearest_distance_sq: float = INF
	for other in candidates:
		if other == soldier or not is_instance_valid(other):
			continue
		if not (other is Node3D):
			continue
		if SoldierStateHelper.is_dead_soldier(other):
			continue
		var other_team: String = other.get_team_tag() if other.has_method("get_team_tag") else str(other.get("team"))
		if other_team == soldier.team:
			continue
		if not SoldierDeckZoneHelper.can_share_combat_zone(soldier, other):
			continue
		var other_node := other as Node3D
		var distance_sq: float = soldier.global_position.distance_squared_to(other_node.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = other_node
	return nearest


static func heal_full(soldier) -> void:
	if soldier.current_state == soldier.State.DEAD and soldier.get_meta("incapacitated", false) == true:
		_recover_incapacitated_now(soldier, 1.0)
		return
	if soldier.current_state != soldier.State.DEAD:
		soldier.current_health = soldier.max_health


static func assist_recover_incapacitated(soldier) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.get_meta("incapacitated", false) != true:
		return false
	var recovery_ratio := _get_incapacitated_recovery_health_ratio(soldier)
	if is_instance_valid(soldier.owned_ship) and soldier.owned_ship.has_meta("incapacitated_assist_health_ratio"):
		recovery_ratio = clampf(float(soldier.owned_ship.get_meta("incapacitated_assist_health_ratio")), 0.05, 1.0)
	elif is_instance_valid(soldier.home_ship) and soldier.home_ship.has_meta("incapacitated_assist_health_ratio"):
		recovery_ratio = clampf(float(soldier.home_ship.get_meta("incapacitated_assist_health_ratio")), 0.05, 1.0)
	_recover_incapacitated_now(soldier, recovery_ratio)
	return true


static func incapacitate(soldier) -> void:
	if soldier.current_state == soldier.State.DEAD:
		return

	soldier.current_state = soldier.State.DEAD
	soldier.current_target = null
	soldier.attack_timer = 0.0
	soldier.is_boarder_on_player_ship = false
	soldier.current_health = 0.0
	soldier.velocity = Vector3.ZERO
	soldier.set_meta("incapacitated", true)
	soldier.set_meta("incapacitated_recovery_pending", true)
	soldier.remove_meta("incapacitated_assist_reviver_id")

	if is_instance_valid(soldier.home_ship) and soldier.home_ship.has_method("check_derelict_status"):
		soldier.home_ship.call_deferred("check_derelict_status")

	_snap_dead_body_to_deck(soldier)
	soldier.set_physics_process(false)
	if soldier.is_in_group("soldiers"):
		soldier.remove_from_group("soldiers")

	_set_body_collision_disabled(soldier, true)

	if soldier.has_method("_play_death_pose"):
		soldier._play_death_pose()

	_schedule_incapacitated_recovery(soldier)


static func die(soldier) -> void:
	if soldier.current_state == soldier.State.DEAD:
		if soldier.get_meta("incapacitated", false) == true:
			soldier.remove_meta("incapacitated")
			soldier.remove_meta("incapacitated_recovery_pending")
		else:
			return

	soldier.current_state = soldier.State.DEAD
	soldier.current_target = null
	soldier.attack_timer = 0.0
	soldier.is_boarder_on_player_ship = false
	soldier.current_health = 0.0
	soldier.set_meta("dead_body_order", Engine.get_physics_frames())
	soldier.remove_meta("incapacitated_assist_reviver_id")

	if is_instance_valid(soldier.home_ship) and soldier.home_ship.has_method("check_derelict_status"):
		soldier.home_ship.call_deferred("check_derelict_status")

	if soldier.team == "enemy":
		_apply_enemy_kill_rewards(soldier)

	var is_offboard_death := _is_offboard_death_context(soldier)
	if not is_offboard_death:
		_snap_dead_body_to_deck(soldier)
	var death_position: Vector3 = soldier.global_position
	var is_sinking_death := _is_sinking_death_context(soldier)
	var death_volume_db := SOLDIER_SINKING_DEATH_VOLUME_DB if is_sinking_death else SOLDIER_DEATH_VOLUME_DB
	var splash_volume_db := SOLDIER_SINKING_SPLASH_VOLUME_DB if is_sinking_death else 0.0
	var should_play_splash: bool = not is_offboard_death or soldier.get_meta("offboard_splash_played", false) != true
	var should_play_death_voice: bool = not (
		is_offboard_death and soldier.get_meta("overboard_knockback_voice_played", false) == true
	)
	var tree: SceneTree = soldier.get_tree()
	var audio_manager = soldier.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		if should_play_death_voice:
			if audio_manager.has_method("play_sfx_random_pitch"):
				audio_manager.play_sfx_random_pitch(
					"soldier_die",
					death_position,
					SOLDIER_DEATH_PITCH_MIN,
					SOLDIER_DEATH_PITCH_MAX,
					death_volume_db
				)
			else:
				audio_manager.play_sfx(
					"soldier_die",
					death_position,
					randf_range(SOLDIER_DEATH_PITCH_MIN, SOLDIER_DEATH_PITCH_MAX),
					death_volume_db
				)
		if should_play_splash and is_instance_valid(tree):
			tree.create_timer(randf_range(0.3, 0.6)).timeout.connect(func():
				var main_loop := Engine.get_main_loop() as SceneTree
				if not is_instance_valid(main_loop):
					return
				var delay_am = main_loop.root.get_node_or_null("AudioManager")
				if is_instance_valid(delay_am) and delay_am.has_method("play_sfx"):
					delay_am.play_sfx("water_splash_small", death_position, randf_range(0.8, 1.2), splash_volume_db)
			)

	soldier.set_physics_process(false)
	if soldier.is_in_group("soldiers"):
		soldier.remove_from_group("soldiers")
	if soldier.is_in_group("enemy"):
		soldier.remove_from_group("enemy")

	_set_body_collision_disabled(soldier, true)
	if is_offboard_death:
		soldier.visible = false
		soldier.queue_free()
		return

	var owned_ship_team: String = ""
	if is_instance_valid(soldier.owned_ship):
		owned_ship_team = str(soldier.owned_ship.get("team"))
	var should_show_death_pose: bool = soldier.team == "player" or soldier.team == "enemy" or owned_ship_team == "player"
	if should_show_death_pose and soldier.has_method("_play_death_pose"):
		soldier._play_death_pose()
	else:
		soldier.visible = false
	if _try_start_roof_death_overboard(soldier):
		return
	if is_instance_valid(soldier.owned_ship) and soldier.owned_ship.has_method("enforce_dead_body_limit"):
		soldier.owned_ship.call_deferred("enforce_dead_body_limit")


static func _snap_dead_body_to_deck(soldier) -> void:
	if not is_instance_valid(soldier):
		return
	if not is_instance_valid(soldier.owned_ship):
		return
	if soldier.has_method("_keep_within_owned_ship_bounds"):
		soldier._keep_within_owned_ship_bounds()


static func _try_start_roof_death_overboard(soldier) -> bool:
	if not is_instance_valid(soldier):
		return false
	if soldier.team != "enemy":
		return false
	if not SoldierDeckZoneHelper.is_roof(soldier):
		return false
	if not is_instance_valid(soldier.owned_ship):
		return false
	if str(soldier.owned_ship.get("team")) != "player":
		return false
	if not soldier.owned_ship.has_method("try_throw_roof_death_overboard"):
		return false
	return bool(soldier.owned_ship.call("try_throw_roof_death_overboard", soldier))


static func _is_offboard_death_context(soldier) -> bool:
	var death_cause: String = str(soldier.get_meta("last_death_cause", "combat"))
	if death_cause == "drowned" or death_cause == "overboard":
		return true
	var last_damage_source: String = str(soldier.get_meta("last_damage_source", ""))
	return last_damage_source == "drowned" or last_damage_source == "overboard"


static func _is_sinking_death_context(soldier) -> bool:
	if soldier.get_meta(ENEMY_SINKING_REWARD_ACCOUNTED_META, false) == true:
		return true
	if _is_ship_sinking_or_dying(soldier.owned_ship):
		return true
	return _is_ship_sinking_or_dying(soldier.home_ship)


static func _is_ship_sinking_or_dying(ship) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.has_method("is_sinking_or_dying") and ship.is_sinking_or_dying():
		return true
	return ship.get("is_sinking") == true or ship.get("is_dying") == true


static func _should_incapacitate_instead_of_die(soldier) -> bool:
	if soldier.get_meta("disable_incapacitation", false) == true:
		return false
	if soldier.team != "player":
		return false
	var death_cause: String = str(soldier.get_meta("last_death_cause", "combat"))
	if death_cause == "drowned":
		return false
	var last_damage_source: String = str(soldier.get_meta("last_damage_source", ""))
	if last_damage_source == "drowned":
		return false
	if is_instance_valid(soldier.owned_ship):
		if soldier.owned_ship.has_method("is_sinking_or_dying") and soldier.owned_ship.is_sinking_or_dying():
			return false
		if soldier.owned_ship.get("is_sinking") == true or soldier.owned_ship.get("is_dying") == true:
			return false
	var chance := _get_combat_incapacitation_chance(soldier)
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	return randf() < chance


static func _get_combat_incapacitation_chance(soldier) -> float:
	if not is_instance_valid(soldier):
		return 0.0
	if soldier.has_meta(COMBAT_INCAPACITATION_CHANCE_META):
		return clampf(float(soldier.get_meta(COMBAT_INCAPACITATION_CHANCE_META)), 0.0, 1.0)
	if is_instance_valid(soldier.owned_ship) and soldier.owned_ship.has_meta(SHIP_COMBAT_INCAPACITATION_CHANCE_META):
		return clampf(float(soldier.owned_ship.get_meta(SHIP_COMBAT_INCAPACITATION_CHANCE_META)), 0.0, 1.0)
	if is_instance_valid(soldier.home_ship) and soldier.home_ship.has_meta(SHIP_COMBAT_INCAPACITATION_CHANCE_META):
		return clampf(float(soldier.home_ship.get_meta(SHIP_COMBAT_INCAPACITATION_CHANCE_META)), 0.0, 1.0)
	return 0.0


static func _schedule_incapacitated_recovery(soldier) -> void:
	var tree: SceneTree = soldier.get_tree()
	if not is_instance_valid(tree):
		return
	var soldier_id: int = soldier.get_instance_id()
	tree.create_timer(_get_incapacitated_recovery_delay(soldier)).timeout.connect(func() -> void:
		_try_recover_incapacitated_by_id(soldier_id)
	)


static func _try_recover_incapacitated_by_id(soldier_id: int) -> void:
	var soldier := NodeContractHelper.get_instance_node(soldier_id)
	if not is_instance_valid(soldier):
		return
	_try_recover_incapacitated(soldier)


static func _try_recover_incapacitated(soldier) -> void:
	if not is_instance_valid(soldier):
		return
	if soldier.get_meta("incapacitated", false) != true:
		return
	if not is_instance_valid(soldier.owned_ship):
		_schedule_incapacitated_recovery(soldier)
		return
	if soldier.owned_ship.has_method("is_sinking_or_dying") and soldier.owned_ship.is_sinking_or_dying():
		return
	if soldier.owned_ship.get("is_sinking") == true or soldier.owned_ship.get("is_dying") == true:
		return
	if _has_hostile_on_owned_ship(soldier):
		_schedule_incapacitated_recovery(soldier)
		return

	_recover_incapacitated_now(soldier, _get_incapacitated_recovery_health_ratio(soldier))


static func _recover_incapacitated_now(soldier, health_ratio: float) -> void:
	soldier.remove_meta("incapacitated")
	soldier.remove_meta("incapacitated_recovery_pending")
	soldier.remove_meta("incapacitated_assist_reviver_id")
	soldier.current_health = maxf(8.0, soldier.max_health * health_ratio)
	soldier.current_target = null
	soldier.attack_timer = 1.2
	soldier.current_state = soldier.State.IDLE
	if not soldier.is_in_group("soldiers"):
		soldier.add_to_group("soldiers")
	_set_body_collision_disabled(soldier, false)
	if soldier.has_method("_play_recovery_pose"):
		soldier._play_recovery_pose()
	if soldier.has_method("add_soldier_xp"):
		soldier.add_soldier_xp(1.0, "recovery")
	soldier.set_physics_process(true)
	if is_instance_valid(soldier.owned_ship) and soldier.owned_ship.has_method("_sync_player_crew_roster"):
		soldier.owned_ship.call_deferred("_sync_player_crew_roster")
	elif is_instance_valid(soldier.home_ship) and soldier.home_ship.has_method("_sync_player_crew_roster"):
		soldier.home_ship.call_deferred("_sync_player_crew_roster")
	if is_instance_valid(soldier.home_ship) and soldier.home_ship.has_method("check_derelict_status"):
		soldier.home_ship.call_deferred("check_derelict_status")


static func _has_hostile_on_owned_ship(soldier) -> bool:
	for other in EntityRegistry.get_soldiers_by_ship(soldier.owned_ship):
		if other == soldier or not is_instance_valid(other):
			continue
		if SoldierStateHelper.is_dead_soldier(other):
			continue
		var other_team: String = other.get_team_tag() if other.has_method("get_team_tag") else str(other.get("team"))
		if other_team != soldier.team:
			return true
	return false


static func _set_body_collision_disabled(soldier, disabled: bool) -> void:
	if is_instance_valid(soldier) and soldier.has_method("set_body_collision_disabled"):
		soldier.call("set_body_collision_disabled", disabled)


static func _get_incapacitated_recovery_delay(soldier) -> float:
	var stat_ship := _get_incapacitated_recovery_stat_ship(soldier)
	if is_instance_valid(stat_ship) and stat_ship.has_meta("incapacitated_recovery_delay"):
		return maxf(PLAYER_INCAPACITATED_MIN_RECOVERY_DELAY, float(stat_ship.get_meta("incapacitated_recovery_delay")))
	return PLAYER_INCAPACITATED_RECOVERY_DELAY


static func _get_incapacitated_recovery_health_ratio(soldier) -> float:
	var stat_ship := _get_incapacitated_recovery_stat_ship(soldier)
	if is_instance_valid(stat_ship) and stat_ship.has_meta("incapacitated_recovery_health_ratio"):
		return clampf(float(stat_ship.get_meta("incapacitated_recovery_health_ratio")), 0.05, 1.0)
	return PLAYER_INCAPACITATED_RECOVERY_HEALTH_RATIO


static func _get_incapacitated_recovery_stat_ship(soldier) -> Node:
	if is_instance_valid(soldier.owned_ship) and soldier.owned_ship.has_meta("incapacitated_recovery_delay"):
		return soldier.owned_ship
	if is_instance_valid(soldier.home_ship) and soldier.home_ship.has_meta("incapacitated_recovery_delay"):
		return soldier.home_ship
	if is_instance_valid(soldier.owned_ship) and soldier.owned_ship.has_meta("incapacitated_recovery_health_ratio"):
		return soldier.owned_ship
	if is_instance_valid(soldier.home_ship) and soldier.home_ship.has_meta("incapacitated_recovery_health_ratio"):
		return soldier.home_ship
	if is_instance_valid(soldier.owned_ship):
		return soldier.owned_ship
	return soldier.home_ship


static func _apply_melee_kill_bonus(soldier) -> void:
	var last_damage_source: String = str(soldier.get_meta("last_damage_source", ""))
	if not MELEE_DAMAGE_SOURCES.has(last_damage_source):
		return

	var lm = soldier._cached_level_manager
	if not is_instance_valid(lm):
		return

	var xp_bonus: int = max(0, int(lm.get("melee_kill_xp_bonus")))
	var bonus_xp: int = max(0, int(lm.get("melee_kill_bonus_xp")))
	if xp_bonus > 0 and lm.has_method("add_xp"):
		lm.add_xp(xp_bonus)
	if bonus_xp > 0 and lm.has_method("add_bonus_xp"):
		lm.add_bonus_xp(bonus_xp)


static func _apply_enemy_kill_rewards(soldier) -> void:
	if soldier.get_meta("disable_kill_rewards", false) == true:
		return
	if soldier.get_meta(ENEMY_SINKING_REWARD_ACCOUNTED_META, false) == true:
		return
	var lm = soldier._cached_level_manager
	if not is_instance_valid(lm):
		return

	var death_cause: String = str(soldier.get_meta("last_death_cause", "combat"))
	if death_cause == "drowned":
		var drown_xp: int = max(0, int(lm.get("drowned_soldier_kill_xp_reward")))
		var drown_bonus_xp: int = max(0, int(lm.get("drowned_soldier_kill_bonus_xp_reward")))
		if drown_xp > 0 and lm.has_method("add_xp"):
			lm.add_xp(drown_xp)
		if drown_bonus_xp > 0 and lm.has_method("add_bonus_xp"):
			lm.add_bonus_xp(drown_bonus_xp)
		if lm.has_method("add_soldier_kill"):
			lm.add_soldier_kill(1, "drowned")
		return

	var combat_xp: int = max(0, int(lm.get("soldier_kill_xp_reward")))
	if combat_xp > 0 and lm.has_method("add_xp"):
		lm.add_xp(combat_xp)
	if lm.has_method("add_soldier_kill"):
		lm.add_soldier_kill(1, "combat")
	if lm.has_method("add_bonus_xp_from_soldier_kill"):
		lm.add_bonus_xp_from_soldier_kill(1)
	_apply_melee_kill_bonus(soldier)
