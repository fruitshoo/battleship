extends RefCounted
class_name BallisticCollateralHelper

const WATER_SPLASH_SCENE = preload("res://scenes/effects/water_blast.tscn")
const SoldierCombatOverboardHelper = preload("res://scripts/entities/soldiers/soldier_combat_overboard_helper.gd")

const DAMAGE_SOURCE := "ballistic_collateral"
const KIND_CANNON := "cannon"
const KIND_JANGGUN := "janggun"
const META_PENDING := "ballistic_collateral_pending"
const META_NEXT_ALLOWED_MSEC := "ballistic_collateral_next_allowed_msec"
const FORCE_ENV := "BATTLESHIP_FORCE_BALLISTIC_COLLATERAL"

const CANNON_CHANCE: float = 0.045
const JANGGUN_CHANCE: float = 0.07
const EXTRA_THROW_CHANCE: float = 0.18
const MAX_THROW_COUNT: int = 2
const SHIP_COOLDOWN_SECONDS: float = 1.0
const THROW_DURATION: float = 0.82
const THROW_EXIT_PAD_MIN: float = 1.8
const THROW_EXIT_PAD_MAX: float = 2.7
const THROW_ARC_HEIGHT_MIN: float = 2.2
const THROW_ARC_HEIGHT_MAX: float = 3.0
const THROW_ROTATION_DELAY: float = 0.24
const SPLASH_LEAD_PROGRESS: float = 0.99
const FAILSAFE_DEATH_SECONDS: float = 1.35
const BALLISTIC_DEATH_PITCH_MIN: float = 1.12
const BALLISTIC_DEATH_PITCH_MAX: float = 1.32
const BALLISTIC_DEATH_PITCH_BOOST_CHANCE: float = 0.28
const BALLISTIC_DEATH_PITCH_BOOST_MIN: float = 1.04
const BALLISTIC_DEATH_PITCH_BOOST_MAX: float = 1.12
const BALLISTIC_DEATH_PITCH_CLAMP_MIN: float = 1.08
const BALLISTIC_DEATH_PITCH_CLAMP_MAX: float = 1.44


static func try_apply_from_ship_hit(
	source: Node,
	hit_ship: Node3D,
	impact_position: Vector3,
	projectile_kind: String,
	projectile_direction: Vector3 = Vector3.ZERO
) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(hit_ship):
		return false
	if NodeContractHelper.is_sinking_or_dying(hit_ship):
		return false
	var forced := _is_forced()
	if not forced:
		if not _passes_cooldown(hit_ship):
			return false
		if randf() > _get_chance(projectile_kind):
			return false

	var throw_count := _throw_collateral_soldiers(source, hit_ship, impact_position, projectile_kind, projectile_direction)
	if throw_count <= 0:
		return false
	_mark_ship_cooldown(hit_ship)
	return true


static func _throw_collateral_soldiers(
	source: Node,
	hit_ship: Node3D,
	impact_position: Vector3,
	projectile_kind: String,
	projectile_direction: Vector3
) -> int:
	var throw_count := 0
	for index in range(MAX_THROW_COUNT):
		if index > 0 and randf() > _get_extra_throw_chance(projectile_kind):
			break
		var soldier := _find_candidate(hit_ship, impact_position)
		if not is_instance_valid(soldier):
			break
		_throw_soldier_overboard(source, soldier, hit_ship, impact_position, projectile_direction)
		throw_count += 1
	return throw_count


static func _find_candidate(hit_ship: Node3D, impact_position: Vector3) -> Node3D:
	var best: Node3D = null
	var best_score: float = INF
	for candidate in EntityRegistry.get_soldiers_by_ship(hit_ship):
		if not _is_valid_candidate(candidate, hit_ship):
			continue
		var soldier := candidate as Node3D
		var score := _get_outboard_candidate_score(hit_ship, soldier, impact_position)
		if score < best_score:
			best_score = score
			best = soldier
	return best


static func _get_outboard_candidate_score(hit_ship: Node3D, soldier: Node3D, impact_position: Vector3) -> float:
	var ship_local := hit_ship.to_local(soldier.global_position)
	var side_bias := absf(ship_local.x)
	var stern_bow_bias := absf(ship_local.z) * 0.18
	var impact_offset := soldier.global_position - impact_position
	impact_offset.y = 0.0
	var impact_hint := minf(impact_offset.length(), 9.0) * 0.08
	return -side_bias - stern_bow_bias + impact_hint + randf_range(0.0, 1.2)


static func _is_valid_candidate(candidate: Variant, hit_ship: Node3D) -> bool:
	if not is_instance_valid(candidate):
		return false
	if not (candidate is Node3D):
		return false
	var soldier := candidate as Node3D
	if soldier.get_meta(META_PENDING, false) == true:
		return false
	if SoldierStateHelper.is_dead_soldier(soldier):
		return false
	if soldier.has_method("is_jumping_value") and soldier.call("is_jumping_value") == true:
		return false
	var owned_ship: Node = null
	if soldier.has_method("get_owned_ship_node"):
		owned_ship = soldier.call("get_owned_ship_node")
	elif soldier.get("owned_ship") != null:
		owned_ship = soldier.get("owned_ship")
	return owned_ship == hit_ship


static func _throw_soldier_overboard(
	source: Node,
	soldier: Node3D,
	hit_ship: Node3D,
	impact_position: Vector3,
	projectile_direction: Vector3
) -> void:
	if not is_instance_valid(soldier):
		return
	var knock_dir := projectile_direction
	knock_dir.y = 0.0
	if knock_dir.length_squared() <= 0.0001:
		knock_dir = soldier.global_position - impact_position
	knock_dir.y = 0.0
	if knock_dir.length_squared() <= 0.0001 and is_instance_valid(hit_ship):
		knock_dir = _resolve_outboard_direction(hit_ship, soldier)
	if knock_dir.length_squared() <= 0.0001:
		knock_dir = Vector3.FORWARD
	knock_dir = knock_dir.normalized()

	soldier.set_meta(META_PENDING, true)
	soldier.set_meta("last_death_cause", "overboard")
	soldier.set_meta("last_damage_source", DAMAGE_SOURCE)
	soldier.set_meta("overboard_knockback_voice_played", true)
	if "current_health" in soldier:
		soldier.set("current_health", 0.0)
	if "current_target" in soldier:
		soldier.set("current_target", null)
	if "velocity" in soldier:
		soldier.set("velocity", Vector3.ZERO)
	if soldier.has_method("set_body_collision_disabled"):
		soldier.call("set_body_collision_disabled", true)
	soldier.set_physics_process(false)
	_play_ballistic_death_voice(source, soldier.global_position)
	_start_ballistic_throw_tween(source, soldier, hit_ship, knock_dir)
	_schedule_failsafe_death(source, soldier)


static func _resolve_outboard_direction(hit_ship: Node3D, soldier: Node3D) -> Vector3:
	var world_dir := soldier.global_position - hit_ship.global_position
	world_dir.y = 0.0
	return world_dir


static func _start_ballistic_throw_tween(source: Node, soldier: Node3D, hit_ship: Node3D, throw_dir: Vector3) -> void:
	if not is_instance_valid(soldier) or not soldier.is_inside_tree():
		return
	var tree := soldier.get_tree()
	if is_instance_valid(source) and source.is_inside_tree():
		tree = source.get_tree()
	var start_position := soldier.global_position
	var throw_target := _resolve_projectile_throw_target(hit_ship, start_position, throw_dir)
	var arc_data := SoldierCombatOverboardHelper.make_throw_arc_data(
		start_position,
		throw_target,
		soldier.rotation,
		THROW_ARC_HEIGHT_MIN,
		THROW_ARC_HEIGHT_MAX,
		Vector3(1.9, -1.1, -2.2),
		Vector3(3.1, 1.1, 2.2),
		THROW_ROTATION_DELAY
	)
	var soldier_id := soldier.get_instance_id()
	arc_data["splash_played"] = false
	var tween := soldier.create_tween()
	tween.tween_method(func(progress: float) -> void:
		_apply_ballistic_throw_arc(soldier_id, arc_data, progress)
		if progress >= SPLASH_LEAD_PROGRESS and arc_data.get("splash_played", false) != true:
			arc_data["splash_played"] = true
			_play_overboard_disposal_splash(tree, arc_data.get("throw_target", throw_target))
			_mark_offboard_splash_played(soldier_id)
	, 0.0, 1.0, THROW_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		if arc_data.get("splash_played", false) != true:
			arc_data["splash_played"] = true
			_play_overboard_disposal_splash(tree, arc_data.get("throw_target", throw_target))
			_mark_offboard_splash_played(soldier_id)
		_finish_pending_overboard_death(soldier_id)
	)


static func _apply_ballistic_throw_arc(soldier_id: int, arc_data: Dictionary, progress: float) -> void:
	var soldier := NodeContractHelper.get_instance_node3d(soldier_id)
	if not is_instance_valid(soldier):
		return
	SoldierCombatOverboardHelper.apply_throw_arc(soldier, arc_data, progress)


static func _resolve_projectile_throw_target(hit_ship: Node3D, start_position: Vector3, throw_dir: Vector3) -> Vector3:
	var world_dir := throw_dir
	world_dir.y = 0.0
	if world_dir.length_squared() <= 0.0001:
		if is_instance_valid(hit_ship):
			world_dir = start_position - hit_ship.global_position
			world_dir.y = 0.0
	if world_dir.length_squared() <= 0.0001:
		world_dir = Vector3.FORWARD
	world_dir = world_dir.normalized()
	if not is_instance_valid(hit_ship):
		var fallback_target := start_position + world_dir * 7.0
		fallback_target.y = 0.05
		return fallback_target

	var local_start := hit_ship.to_local(start_position)
	var local_dir := hit_ship.global_basis.inverse() * world_dir
	local_dir.y = 0.0
	if local_dir.length_squared() <= 0.0001:
		local_dir = Vector3.FORWARD
	local_dir = local_dir.normalized()
	var deck_half := _get_ship_deck_half_extents(hit_ship)
	var exit_t := _get_rect_exit_distance(local_start, local_dir, deck_half)
	var local_target := local_start + local_dir * (exit_t + randf_range(THROW_EXIT_PAD_MIN, THROW_EXIT_PAD_MAX))
	local_target.y = 0.05
	return hit_ship.to_global(local_target)


static func _get_ship_deck_half_extents(hit_ship: Node3D) -> Vector2:
	if is_instance_valid(hit_ship) and hit_ship.has_method("get_deck_half_extents"):
		var deck_half: Variant = hit_ship.call("get_deck_half_extents")
		if deck_half is Vector2:
			return deck_half as Vector2
	if is_instance_valid(hit_ship) and hit_ship.has_method("get_collision_half_extents"):
		var collision_half: Variant = hit_ship.call("get_collision_half_extents")
		if collision_half is Vector2:
			return collision_half as Vector2
	return Vector2(2.0, 4.0)


static func _get_rect_exit_distance(local_start: Vector3, local_dir: Vector3, deck_half: Vector2) -> float:
	var best_t := INF
	if absf(local_dir.x) > 0.001:
		var edge_x := (deck_half.x + 0.35) * signf(local_dir.x)
		var tx := (edge_x - local_start.x) / local_dir.x
		if tx > 0.05:
			best_t = minf(best_t, tx)
	if absf(local_dir.z) > 0.001:
		var edge_z := (deck_half.y + 0.35) * signf(local_dir.z)
		var tz := (edge_z - local_start.z) / local_dir.z
		if tz > 0.05:
			best_t = minf(best_t, tz)
	if best_t == INF:
		return 6.0
	return clampf(best_t, 2.2, 9.5)


static func _play_ballistic_death_voice(source: Node, position: Vector3) -> void:
	if not is_instance_valid(source):
		return
	var audio_manager := source.get_node_or_null("/root/AudioManager")
	if not is_instance_valid(audio_manager) or not audio_manager.has_method("play_sfx"):
		return
	var voice_pitch := randf_range(BALLISTIC_DEATH_PITCH_MIN, BALLISTIC_DEATH_PITCH_MAX)
	if randf() < BALLISTIC_DEATH_PITCH_BOOST_CHANCE:
		voice_pitch *= randf_range(BALLISTIC_DEATH_PITCH_BOOST_MIN, BALLISTIC_DEATH_PITCH_BOOST_MAX)
	audio_manager.play_sfx(
		"ballistic_death",
		position,
		clampf(voice_pitch, BALLISTIC_DEATH_PITCH_CLAMP_MIN, BALLISTIC_DEATH_PITCH_CLAMP_MAX),
		1.5
	)


static func _play_overboard_disposal_splash(tree: SceneTree, splash_pos: Vector3) -> void:
	if not is_instance_valid(tree):
		return
	var splash = ScenePool.acquire(tree, WATER_SPLASH_SCENE)
	if is_instance_valid(splash):
		tree.root.add_child(splash)
		if splash is Node3D:
			(splash as Node3D).global_position = Vector3(splash_pos.x, 0.05, splash_pos.z)
		if splash.has_method("configure_as_overboard_disposal"):
			splash.configure_as_overboard_disposal()
		elif splash.has_method("configure_as_splash"):
			splash.configure_as_splash()
		elif splash.has_method("configure_as_small"):
			splash.configure_as_small()
		if splash.has_method("pool_activate"):
			splash.call("pool_activate")
	var audio_manager := tree.root.get_node_or_null("AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_small", splash_pos, randf_range(0.85, 1.15), 2.0)


static func _mark_offboard_splash_played(soldier_id: int) -> void:
	var soldier := NodeContractHelper.get_instance_node(soldier_id)
	if is_instance_valid(soldier):
		soldier.set_meta("offboard_splash_played", true)


static func _schedule_failsafe_death(source: Node, soldier: Node3D) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var soldier_id := soldier.get_instance_id()
	source.get_tree().create_timer(FAILSAFE_DEATH_SECONDS).timeout.connect(func() -> void:
		_finish_pending_overboard_death(soldier_id)
	)


static func _finish_pending_overboard_death(soldier_id: int) -> void:
	var soldier := NodeContractHelper.get_instance_node(soldier_id)
	if not is_instance_valid(soldier):
		return
	if soldier.get_meta(META_PENDING, false) != true:
		return
	if SoldierStateHelper.is_dead_soldier(soldier):
		return
	soldier.set_meta("last_death_cause", "overboard")
	soldier.set_meta("last_damage_source", DAMAGE_SOURCE)
	if soldier.has_method("_die"):
		soldier.call("_die")
	else:
		soldier.queue_free()


static func _passes_cooldown(hit_ship: Node3D) -> bool:
	var now := Time.get_ticks_msec()
	var next_allowed := int(hit_ship.get_meta(META_NEXT_ALLOWED_MSEC, 0))
	return now >= next_allowed


static func _mark_ship_cooldown(hit_ship: Node3D) -> void:
	var next_allowed := Time.get_ticks_msec() + int(SHIP_COOLDOWN_SECONDS * 1000.0)
	hit_ship.set_meta(META_NEXT_ALLOWED_MSEC, next_allowed)


static func _get_chance(projectile_kind: String) -> float:
	match projectile_kind:
		KIND_JANGGUN:
			return JANGGUN_CHANCE
		_:
			return CANNON_CHANCE


static func _get_extra_throw_chance(_projectile_kind: String) -> float:
	return EXTRA_THROW_CHANCE


static func _is_forced() -> bool:
	var value := OS.get_environment(FORCE_ENV).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes"
