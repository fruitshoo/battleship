@tool
extends "res://scripts/entities/ships/chaser_ship.gd"
class_name SupportShip

## Player support fleet ship.
## Keeps support-fleet identity in the scene instead of borrowing enemy_base_ship.tscn.

const SupportSoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")
const SupportFleetStateHelper = preload("res://scripts/entities/ships/support_fleet_state_helper.gd")
const SUPPORT_CORPSE_CLEANUP_IN_PROGRESS_META := "support_corpse_cleanup_in_progress"

@export_group("Post Combat Cleanup")
@export var support_corpse_cleanup_enabled: bool = true
@export_range(0.5, 12.0, 0.25) var support_corpse_cleanup_delay: float = 3.0
@export_range(0.5, 8.0, 0.25) var support_corpse_cleanup_interval: float = 2.5
@export_range(0.2, 1.5, 0.05) var support_corpse_cleanup_throw_duration: float = 0.45
@export_range(0.2, 2.5, 0.05) var support_corpse_cleanup_throw_height: float = 0.65
@export_group("Sail Handling")
@export var sail_furled: bool = false
@export_range(0.0, 1.0, 0.01) var sail_deployed_ratio: float = 1.0
@export_range(0.25, 8.0, 0.05) var sail_furl_rate: float = 2.8
@export_range(0.0, 0.25, 0.01) var furled_sail_drive_ratio: float = 0.0
@export_range(1.0, 2.0, 0.05) var furled_sail_rudder_multiplier: float = 1.3
@export_range(1.0, 2.0, 0.05) var furled_sail_rowing_efficiency_multiplier: float = 1.2
@export_range(0.25, 1.0, 0.05) var furled_sail_rowing_stamina_cost_multiplier: float = 0.85
@export_range(0.0, 1.0, 0.05) var furled_sail_fire_damage_multiplier: float = 0.5
@export_group("")
var _support_corpse_cleanup_timer: float = 0.0
var _support_corpse_cleanup_peace_timer: float = 0.0

func _ready() -> void:
	team = "player"
	if ship_type.strip_edges().is_empty() or ship_type == "sekibune_melee":
		ship_type = "maengseon_ally"
	set_ally_ship_role("support_fleet")
	limbo_ai_pilot_tree_path = ShipLimboAIPilot.resolve_tree_path(self, limbo_ai_pilot_tree_path)
	super._ready()
	set_ally_ship_role("support_fleet")
	sync_sail_furl_with_flagship(0.0, true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	sync_sail_furl_with_flagship(delta)
	super._process(delta)
	_update_support_corpse_cleanup(delta)


func set_sail_furled(furled: bool) -> void:
	sail_furled = bool(furled)


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
		sail_furled = flagship.get("sail_furled") == true
	var target_ratio := 0.0 if sail_furled else 1.0
	if immediate:
		sail_deployed_ratio = target_ratio
		return
	sail_deployed_ratio = move_toward(
		clampf(sail_deployed_ratio, 0.0, 1.0),
		target_ratio,
		maxf(sail_furl_rate, 0.01) * delta
	)


func refresh_support_fleet_profile_runtime(_profile: Dictionary = {}) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return

	var previous_max_hull_hp: float = maxf(float(max_hull_hp), 1.0)
	var previous_hull_ratio: float = clampf(float(hull_hp) / previous_max_hull_hp, 0.0, 1.0)
	var previous_speed: float = float(current_speed)
	var previous_target: Node3D = target if is_instance_valid(target) else null
	var desired_crew_count: int = maxi(1, int(initial_crew_count))
	var soldiers_node := get_soldiers_container()
	if is_instance_valid(soldiers_node):
		desired_crew_count = maxi(1, soldiers_node.get_child_count())

	var stats := load_ship_stats(ship_type)
	if stats.is_empty():
		return

	ShipBlueprintHelper.apply_chaser_stats(self, stats)
	_load_enemy_crew_composition_from_stats(stats)
	_apply_combat_profile_from_stats(stats)
	_apply_formation_role_profile()
	_rebuild_runtime_hull(stats)
	_cache_hull_references(self)
	_refresh_collision_bounds_from_hull()

	if not has_cannons:
		_remove_all_cannons()
	else:
		_equip_minion_cannons()

	initial_crew_count = clampi(desired_crew_count, 1, max(1, max_crew))
	_reconcile_support_crew_count(initial_crew_count)
	hull_hp = minf(max_hull_hp, maxf(1.0, max_hull_hp * previous_hull_ratio))
	current_speed = previous_speed
	_last_ai_speed = previous_speed
	if is_instance_valid(previous_target):
		target = previous_target
	elif has_method("_find_player"):
		_find_player()

	set_ally_ship_role("support_fleet")
	if has_method("add_to_group"):
		add_to_group("captured_minion")
	EntityRegistry.register_captured_minion(self)
	_apply_minion_visuals()
	_refresh_deck_light()


func _rebuild_runtime_hull(stats: Dictionary) -> void:
	for child in get_children():
		if str(child.name).contains("Hull"):
			remove_child(child)
			child.queue_free()
	var runtime_hull_scene: PackedScene = ShipBlueprintHelper.load_hull_scene(ship_type, hull_scene, stats)
	if not is_instance_valid(runtime_hull_scene):
		return
	var hull_inst = runtime_hull_scene.instantiate()
	add_child(hull_inst)


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


func _update_support_corpse_cleanup(delta: float) -> void:
	if not support_corpse_cleanup_enabled:
		return
	if not _can_run_support_corpse_cleanup():
		_support_corpse_cleanup_peace_timer = 0.0
		_support_corpse_cleanup_timer = 0.0
		return

	_support_corpse_cleanup_peace_timer += delta
	if _support_corpse_cleanup_peace_timer < support_corpse_cleanup_delay:
		return

	_support_corpse_cleanup_timer -= delta
	if _support_corpse_cleanup_timer > 0.0:
		return
	_support_corpse_cleanup_timer = support_corpse_cleanup_interval
	_try_cleanup_support_enemy_corpse()


func _can_run_support_corpse_cleanup() -> bool:
	if not is_inside_tree():
		return false
	if is_sinking or is_dying or is_derelict:
		return false
	if deck_is_contested or deck_is_overrun:
		return false
	return _has_alive_support_cleanup_actor()


func _has_alive_support_cleanup_actor() -> bool:
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


func _try_cleanup_support_enemy_corpse() -> void:
	var corpse: Node3D = _find_support_cleanup_enemy_corpse()
	if not is_instance_valid(corpse):
		return
	corpse.set_meta(SUPPORT_CORPSE_CLEANUP_IN_PROGRESS_META, true)
	_throw_support_corpse_overboard(corpse)


func _find_support_cleanup_enemy_corpse() -> Node3D:
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier) or not (soldier is Node3D):
			continue
		if soldier.get_meta(SUPPORT_CORPSE_CLEANUP_IN_PROGRESS_META, false) == true:
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


func _throw_support_corpse_overboard(corpse: Node3D) -> void:
	var corpse_id: int = corpse.get_instance_id()
	var start_position: Vector3 = corpse.global_position
	var target_position: Vector3 = _get_support_corpse_cleanup_throw_target(corpse)
	var start_rotation: Vector3 = corpse.rotation
	var target_rotation: Vector3 = start_rotation + Vector3(
		randf_range(1.1, 2.0),
		randf_range(-0.8, 0.8),
		randf_range(-1.3, 1.3)
	)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		Callable(self, "_apply_support_corpse_cleanup_throw_arc").bind(corpse_id, start_position, target_position, start_rotation, target_rotation),
		0.0,
		1.0,
		maxf(0.1, support_corpse_cleanup_throw_duration)
	)
	tween.finished.connect(_finish_support_corpse_cleanup.bind(corpse_id, target_position))


func _get_support_corpse_cleanup_throw_target(corpse: Node3D) -> Vector3:
	var local_pos: Vector3 = to_local(corpse.global_position)
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


func _apply_support_corpse_cleanup_throw_arc(
	progress: float,
	corpse_id: int,
	start_position: Vector3,
	target_position: Vector3,
	start_rotation: Vector3,
	target_rotation: Vector3
) -> void:
	var corpse := instance_from_id(corpse_id)
	if not is_instance_valid(corpse) or not (corpse is Node3D):
		return
	var corpse_node := corpse as Node3D
	var arc_position := start_position.lerp(target_position, progress)
	arc_position.y += sin(progress * PI) * support_corpse_cleanup_throw_height
	corpse_node.global_position = arc_position
	corpse_node.rotation = start_rotation.lerp(target_rotation, progress)


func _finish_support_corpse_cleanup(corpse_id: int, splash_position: Vector3) -> void:
	var corpse := instance_from_id(corpse_id)
	if not is_instance_valid(corpse) or not (corpse is Node):
		return
	_play_support_corpse_cleanup_splash(splash_position)
	var corpse_node := corpse as Node
	if corpse_node.has_meta(SUPPORT_CORPSE_CLEANUP_IN_PROGRESS_META):
		corpse_node.remove_meta(SUPPORT_CORPSE_CLEANUP_IN_PROGRESS_META)
	corpse_node.queue_free()


func _play_support_corpse_cleanup_splash(splash_position: Vector3) -> void:
	if is_instance_valid(water_splash_scene):
		var splash = ScenePool.acquire(get_tree(), water_splash_scene)
		if is_instance_valid(splash):
			get_tree().root.add_child(splash)
			if splash is Node3D:
				(splash as Node3D).global_position = Vector3(splash_position.x, base_y + 0.05, splash_position.z)
			if splash.has_method("configure_as_corpse_cleanup"):
				splash.configure_as_corpse_cleanup()
			elif splash.has_method("configure_as_small"):
				splash.configure_as_small()
			if splash.has_method("set_intensity"):
				splash.set_intensity(0.6)
			if splash.has_method("pool_activate"):
				splash.pool_activate()
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_small", splash_position, randf_range(0.85, 1.15), 1.5)
