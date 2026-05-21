@tool
extends "res://scripts/entities/ships/ai_ship.gd"
class_name SupportShip

## Player support fleet ship.
## Keeps support-fleet identity in the scene instead of borrowing enemy_base_ship.tscn.

const SupportSoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")
const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SUPPORT_OVERBOARD_DISPOSAL_IN_PROGRESS_META := "support_overboard_disposal_in_progress"
const SUPPORT_RETREATING_META := "support_retreating"

@export_group("Retreat")
@export var support_retreat_enabled: bool = true
@export_range(8.0, 120.0, 1.0, "suffix:s") var support_retreat_duration: float = 45.0
@export_range(10.0, 220.0, 1.0, "suffix:m") var support_retreat_exit_distance: float = 92.0
@export_range(2.0, 18.0, 0.1, "suffix:s") var support_retreat_exit_duration: float = 8.5
@export_range(0.05, 1.0, 0.05) var support_return_hull_ratio: float = 1.0
@export_group("Overboard Disposal")
@export var support_overboard_disposal_enabled: bool = true
@export_range(0.5, 12.0, 0.25) var support_overboard_disposal_delay: float = 3.0
@export_range(0.5, 8.0, 0.25) var support_overboard_disposal_interval: float = 2.5
@export_range(0.2, 1.5, 0.05) var support_overboard_disposal_throw_duration: float = 0.45
@export_range(0.2, 2.5, 0.05) var support_overboard_disposal_throw_height: float = 0.65
@export_group("")
var support_retreating: bool = false
var _support_retreat_timer: float = 0.0
var _support_retreat_tween: Tween = null
var _support_overboard_disposal_timer: float = 0.0
var _support_overboard_disposal_peace_timer: float = 0.0

func _ready() -> void:
	team = "player"
	if ship_type.strip_edges().is_empty() or ship_type == "sekibune_melee":
		ship_type = "maengseon_ally"
	set_player_fleet_role("support_fleet")
	if Engine.is_editor_hint():
		_remove_runtime_generated_hulls()
		_cache_hull_references(self)
		_refresh_collision_bounds_from_hull()
		return
	limbo_ai_pilot_tree_path = ShipLimboAIPilot.resolve_tree_path(self, limbo_ai_pilot_tree_path)
	super._ready()
	set_player_fleet_role("support_fleet")
	sync_sail_furl_with_flagship(0.0, true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if support_retreating:
		_update_support_retreat(delta)
		return
	sync_sail_furl_with_flagship(delta)
	super._process(delta)
	_update_support_overboard_disposal(delta)


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if support_retreating:
		return
	super.take_damage(amount, hit_position, damage_source)


func die() -> void:
	if support_retreat_enabled and not support_retreating:
		_begin_support_retreat()
		return
	super.die()


func is_combat_disabled() -> bool:
	return support_retreating or super.is_combat_disabled()


func is_sinking_or_dying() -> bool:
	return support_retreating or super.is_sinking_or_dying()


func is_support_retreating() -> bool:
	return support_retreating


func _begin_support_retreat() -> void:
	support_retreating = true
	_support_retreat_timer = 0.0
	set_meta(SUPPORT_RETREATING_META, true)
	BaseShipStatusHelper.clear_fire_effect(self)
	is_boarding = false
	boarding_target = null
	boarding_attacker = null
	deck_is_contested = false
	deck_is_overrun = false
	boarding_capture_progress = 0.0
	target = null
	leaking_rate = 0.0
	hull_hp = 0.0
	_clear_ropes()
	_set_contact_areas_enabled(false)
	_set_wake_state(false)
	current_speed = maxf(current_speed, move_speed * 0.7)
	_set_support_actor_nodes_active(false)
	if is_instance_valid(_support_retreat_tween):
		_support_retreat_tween.kill()
	_support_retreat_tween = create_tween()
	_support_retreat_tween.tween_property(self, "global_position", _get_support_retreat_exit_position(), support_retreat_exit_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_support_retreat_tween.tween_callback(func() -> void:
		if is_instance_valid(self) and support_retreating:
			visible = false
	)
	print("[Support] 지원함이 전선에서 이탈했습니다.")


func _update_support_retreat(delta: float) -> void:
	_support_retreat_timer += delta
	if _support_retreat_timer < support_retreat_duration:
		return
	_return_from_support_retreat()


func _return_from_support_retreat() -> void:
	if is_instance_valid(_support_retreat_tween):
		_support_retreat_tween.kill()
	_support_retreat_tween = null
	support_retreating = false
	if has_meta(SUPPORT_RETREATING_META):
		remove_meta(SUPPORT_RETREATING_META)
	is_dying = false
	is_sinking = false
	is_derelict = false
	is_boarding = false
	deck_is_contested = false
	deck_is_overrun = false
	boarding_capture_progress = 0.0
	global_position = _get_support_return_position()
	_restore_support_crew_after_retreat()
	visible = true
	_set_support_actor_nodes_active(true)
	_set_contact_areas_enabled(true)
	hull_hp = max_hull_hp * clampf(support_return_hull_ratio, 0.05, 1.0)
	current_speed = maxf(float(current_speed), float(move_speed) * 0.6)
	_last_ai_speed = current_speed
	var flagship := _get_support_flagship()
	if is_instance_valid(flagship):
		target = flagship
		look_at(flagship.global_position + (-flagship.global_transform.basis.z * 50.0), Vector3.UP)
	set_meta("support_joining", true)
	set_meta("support_join_stage", 0)
	sync_sail_furl_with_flagship(0.0, true)
	print("[Support] 지원함이 수리 후 복귀했습니다. HP %.0f" % hull_hp)


func _restore_support_crew_after_retreat() -> void:
	var soldiers_node := get_soldiers_container()
	if not is_instance_valid(soldiers_node):
		return
	var roster_count := 0
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		var soldier_team: String = child.get_team_tag() if child.has_method("get_team_tag") else str(child.get("team"))
		var should_remove := soldier_team != "player" or SupportSoldierStateHelper.is_dead_soldier(child)
		if should_remove:
			soldiers_node.remove_child(child)
			child.queue_free()
			continue
		if _counts_as_player_fleet_roster_soldier_node(child):
			roster_count += 1

	var target_count := _get_player_fleet_crew_respawn_target_count()
	while roster_count < target_count:
		_spawn_one_soldier("player")
		roster_count += 1
	reset_player_fleet_crew_respawn_timer()


func _get_support_retreat_exit_position() -> Vector3:
	var flagship := _get_support_flagship()
	var away := global_transform.basis.z
	away.y = 0.0
	if is_instance_valid(flagship):
		away = global_position - flagship.global_position
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = global_transform.basis.z
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = Vector3.BACK
	away = away.normalized()
	var exit_pos := global_position + away * support_retreat_exit_distance
	exit_pos.y = 0.0
	return exit_pos


func _get_support_return_position() -> Vector3:
	var flagship := _get_support_flagship()
	if not is_instance_valid(flagship):
		var fallback := global_position
		fallback.y = 0.0
		return fallback
	var forward: Vector3 = -flagship.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var return_pos: Vector3 = flagship.global_position - forward * 78.0 + right * randf_range(-20.0, 20.0)
	return_pos.y = 0.0
	return return_pos


func _get_support_flagship() -> Node3D:
	var flagship := SupportFleetStateHelper.get_support_owner_flagship(self)
	if not is_instance_valid(flagship) and is_instance_valid(target):
		flagship = target
	return flagship


func _set_support_actor_nodes_active(active: bool) -> void:
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier):
			continue
		if soldier is Node3D:
			(soldier as Node3D).visible = active
		soldier.set_process(active)
		soldier.set_physics_process(active)


func set_sail_furled(furled: bool) -> void:
	var target_furled := bool(furled)
	if sail_furled == target_furled:
		_sync_mast_fold_after_sail_deployment()
		return
	sail_furled = target_furled
	if not sail_furled:
		_sync_mast_fold_with_sail_furl()


func is_sail_furled() -> bool:
	return sail_furled


func get_effective_sail_deployment() -> float:
	var residual_drive := clampf(furled_sail_drive_ratio, 0.0, 1.0)
	var deployed := clampf(sail_deployed_ratio, 0.0, 1.0)
	return clampf(lerpf(residual_drive, 1.0, deployed), 0.0, 1.0)


func sync_sail_furl_with_flagship(delta: float, immediate: bool = false) -> void:
	var flagship := SupportFleetStateHelper.get_support_owner_flagship(self)
	if not is_instance_valid(flagship) and is_instance_valid(target) and target.get("sail_furled") != null:
		flagship = target
	if is_instance_valid(flagship) and flagship.get("sail_furled") != null:
		set_sail_furled(flagship.get("sail_furled") == true)
	if immediate:
		_sync_mast_fold_with_sail_furl(true)
		var target_ratio := _get_target_sail_deployment_ratio()
		sail_deployed_ratio = target_ratio
		return
	var target_ratio := _get_target_sail_deployment_ratio()
	sail_deployed_ratio = move_toward(
		clampf(sail_deployed_ratio, 0.0, 1.0),
		target_ratio,
		maxf(sail_furl_rate, 0.01) * delta
	)
	_sync_mast_fold_after_sail_deployment()


func _sync_mast_fold_with_sail_furl(immediate: bool = false) -> void:
	if mast_fold_pivots.is_empty():
		return
	set_masts_folded(sail_furled, immediate)


func _sync_mast_fold_after_sail_deployment() -> void:
	if mast_fold_pivots.is_empty():
		return
	if sail_furled:
		if sail_deployed_ratio <= 0.001 and not are_masts_folded():
			set_masts_folded(true)
		return
	if are_masts_folded():
		set_masts_folded(false)


func _get_target_sail_deployment_ratio() -> float:
	if sail_furled:
		return 0.0
	if mast_fold_pivots.is_empty():
		return 1.0
	if get_mast_fold_ratio() > 0.001:
		return 0.0
	return 1.0


func refresh_support_fleet_profile_runtime(profile: Dictionary = {}) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return

	var previous_max_hull_hp: float = maxf(float(max_hull_hp), 1.0)
	var previous_hull_ratio: float = clampf(float(hull_hp) / previous_max_hull_hp, 0.0, 1.0)
	var previous_speed: float = float(current_speed)
	var previous_target: Node3D = target if is_instance_valid(target) else null
	var profile_crew_count: int = int(profile.get("crew_count", 0))
	var desired_crew_count: int = maxi(1, profile_crew_count) if profile_crew_count > 0 else maxi(1, int(initial_crew_count))
	var soldiers_node := get_soldiers_container()
	if profile_crew_count <= 0 and is_instance_valid(soldiers_node):
		desired_crew_count = maxi(1, soldiers_node.get_child_count())

	var stats := load_ship_stats(ship_type)
	if stats.is_empty():
		return

	ShipBlueprintHelper.apply_ai_ship_stats(self, stats)
	_load_enemy_crew_composition_from_stats(stats)
	_apply_combat_profile_from_stats(stats)
	_apply_formation_role_profile()
	_rebuild_runtime_hull(stats)
	_cache_hull_references(self)
	_apply_authored_deck_height_if_available()
	_refresh_collision_bounds_from_hull()

	if not has_cannons:
		_remove_all_cannons()
	else:
		_equip_ship_weapons("player", true)

	initial_crew_count = clampi(desired_crew_count, 1, max(1, max_crew))
	set_player_fleet_crew_target_count(initial_crew_count)
	_reconcile_support_crew_count(initial_crew_count)
	hull_hp = minf(max_hull_hp, maxf(1.0, max_hull_hp * previous_hull_ratio))
	current_speed = previous_speed
	_last_ai_speed = previous_speed
	if is_instance_valid(previous_target):
		target = previous_target
	elif has_method("_find_player"):
		_find_player()

	set_player_fleet_role("support_fleet")
	if has_method("add_to_group"):
		add_to_group("support_ship")
		if is_in_group("captured_minion"):
			remove_from_group("captured_minion")
	EntityRegistry.register_support_ship(self)
	EntityRegistry.unregister_legacy_captured_ship(self)
	_apply_minion_visuals()
	_refresh_deck_light()


func _rebuild_runtime_hull(stats: Dictionary) -> void:
	_ensure_hybrid_runtime_hull(ship_type, hull_scene, stats)


func _reconcile_support_crew_count(target_count: int) -> void:
	var soldiers_node := get_soldiers_container()
	if not is_instance_valid(soldiers_node):
		return
	while soldiers_node.get_child_count() > target_count:
		var trailing_soldier := soldiers_node.get_child(soldiers_node.get_child_count() - 1)
		if is_instance_valid(trailing_soldier):
			soldiers_node.remove_child(trailing_soldier)
			trailing_soldier.queue_free()
		else:
			break
	while soldiers_node.get_child_count() < target_count:
		_spawn_one_soldier(team)


func _update_support_overboard_disposal(delta: float) -> void:
	if not support_overboard_disposal_enabled:
		return
	if not _can_run_support_overboard_disposal():
		_support_overboard_disposal_peace_timer = 0.0
		_support_overboard_disposal_timer = 0.0
		return

	_support_overboard_disposal_peace_timer += delta
	if _support_overboard_disposal_peace_timer < support_overboard_disposal_delay:
		return

	_support_overboard_disposal_timer -= delta
	if _support_overboard_disposal_timer > 0.0:
		return
	_support_overboard_disposal_timer = support_overboard_disposal_interval
	_try_dispose_support_overboard_payload()


func _can_run_support_overboard_disposal() -> bool:
	if not is_inside_tree():
		return false
	if is_sinking or is_dying or is_derelict:
		return false
	if deck_is_contested or deck_is_overrun:
		return false
	return _has_alive_support_disposal_actor()


func _has_alive_support_disposal_actor() -> bool:
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != "player":
			continue
		if SupportSoldierStateHelper.is_dead_soldier(soldier):
			continue
		return true
	return false


func _try_dispose_support_overboard_payload() -> void:
	var payload: Node3D = _find_support_overboard_disposal_payload()
	if not is_instance_valid(payload):
		return
	payload.set_meta(SUPPORT_OVERBOARD_DISPOSAL_IN_PROGRESS_META, true)
	_throw_support_payload_overboard(payload)


func _find_support_overboard_disposal_payload() -> Node3D:
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier) or not (soldier is Node3D):
			continue
		if soldier.get_meta(SUPPORT_OVERBOARD_DISPOSAL_IN_PROGRESS_META, false) == true:
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != "enemy":
			continue
		if not SupportSoldierStateHelper.is_dead_soldier(soldier):
			continue
		if SupportSoldierStateHelper.is_incapacitated_soldier(soldier):
			continue
		return soldier as Node3D
	return null


func _throw_support_payload_overboard(payload: Node3D) -> void:
	var payload_id: int = payload.get_instance_id()
	var start_position: Vector3 = payload.global_position
	var target_position: Vector3 = _get_support_overboard_disposal_throw_target(payload)
	var start_rotation: Vector3 = payload.rotation
	var target_rotation: Vector3 = start_rotation + Vector3(
		randf_range(1.1, 2.0),
		randf_range(-0.8, 0.8),
		randf_range(-1.3, 1.3)
	)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		Callable(self, "_apply_support_overboard_disposal_throw_arc").bind(payload_id, start_position, target_position, start_rotation, target_rotation),
		0.0,
		1.0,
		maxf(0.1, support_overboard_disposal_throw_duration)
	)
	tween.finished.connect(_finish_support_overboard_disposal.bind(payload_id, target_position))


func _get_support_overboard_disposal_throw_target(payload: Node3D) -> Vector3:
	var local_pos: Vector3 = to_local(payload.global_position)
	var half_extents: Vector2 = get_deck_half_extents()
	var side_sign := 1.0 if local_pos.x >= 0.0 else -1.0
	var target_local := Vector3(
		side_sign * (half_extents.x + 1.1),
		0.0,
		clampf(local_pos.z, -half_extents.y, half_extents.y)
	)
	var target_global: Vector3 = to_global(target_local)
	target_global.y = base_y + 0.05
	return target_global


func _apply_support_overboard_disposal_throw_arc(
	progress: float,
	payload_id: int,
	start_position: Vector3,
	target_position: Vector3,
	start_rotation: Vector3,
	target_rotation: Vector3
) -> void:
	var payload_node := NodeContractHelper.get_instance_node3d(payload_id)
	if not is_instance_valid(payload_node):
		return
	var arc_position := start_position.lerp(target_position, progress)
	arc_position.y += sin(progress * PI) * support_overboard_disposal_throw_height
	payload_node.global_position = arc_position
	payload_node.rotation = start_rotation.lerp(target_rotation, progress)


func _finish_support_overboard_disposal(payload_id: int, splash_position: Vector3) -> void:
	var payload_node := NodeContractHelper.get_instance_node(payload_id)
	if not is_instance_valid(payload_node):
		return
	_play_support_overboard_disposal_splash(splash_position)
	if payload_node.has_meta(SUPPORT_OVERBOARD_DISPOSAL_IN_PROGRESS_META):
		payload_node.remove_meta(SUPPORT_OVERBOARD_DISPOSAL_IN_PROGRESS_META)
	payload_node.queue_free()


func _play_support_overboard_disposal_splash(splash_position: Vector3) -> void:
	if is_instance_valid(water_splash_scene):
		var splash = ScenePool.acquire(get_tree(), water_splash_scene)
		if is_instance_valid(splash):
			get_tree().root.add_child(splash)
			if splash is Node3D:
				(splash as Node3D).global_position = Vector3(splash_position.x, base_y + 0.05, splash_position.z)
			if splash.has_method("configure_as_overboard_disposal"):
				splash.configure_as_overboard_disposal()
			elif splash.has_method("configure_as_small"):
				splash.configure_as_small()
			if splash.has_method("pool_activate"):
				splash.pool_activate()
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_small", splash_position, randf_range(0.85, 1.15), 1.5)
