extends Area3D
class_name EnemyDrifterXP

const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const FieldItemHelper = preload("res://scripts/effects/field_item_helper.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

@export var xp_amount: int = 3
@export var soldier_count: int = 1
@export_range(2.0, 12.0, 0.25) var base_magnet_radius: float = 8.0
@export_range(0.5, 12.0, 0.25) var magnet_speed: float = 7.5
@export_range(0.5, 4.0, 0.05) var collection_contact_margin: float = 0.7
@export_range(0.3, 4.0, 0.05) var float_speed: float = 1.5
@export_range(0.05, 0.8, 0.05) var float_height: float = 0.2
@export_range(0.1, 2.0, 0.05) var rotation_speed: float = 0.45
@export_range(-0.5, 2.0, 0.05) var waterline_offset: float = -0.05
@export_range(-0.5, 1.0, 0.05) var visual_waterline_offset: float = 0.22
@export_range(0.2, 3.0, 0.05) var wave_tilt_strength: float = 0.7
@export_range(8.0, 180.0, 1.0) var lifetime: float = 70.0
@export_range(0.05, 0.5, 0.05) var player_search_interval: float = 0.2
@export_range(0.03, 0.3, 0.01) var wave_sample_interval: float = 0.1

var target_player: Node3D = null
var current_magnet_speed: float = 0.0
var base_y: float = 0.0
var time_alive: float = 0.0
var is_collected: bool = false
var is_expiring: bool = false
var _cached_lm: Node = null
var _cached_um: Node = null
var _cached_ocean: Node = null
var _cached_wave_height: float = 0.0
var _cached_wave_tilt := Vector2.ZERO
var _wave_sample_timer: float = 0.0
var _player_search_timer: float = 0.0
var _visual_rest_scale: Vector3 = Vector3.ONE
var _float_phase: float = 0.0

@onready var visual: Node3D = $Visual if has_node("Visual") else ($MeshInstance3D if has_node("MeshInstance3D") else self)


func _ready() -> void:
	add_to_group("enemy_drifter_xp")
	if _env_flag_enabled("BATTLESHIP_GAUNTLET_DISABLE_RECOVERY"):
		ScenePool.release(self)
		return
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	pool_reset()


func pool_capacity() -> int:
	return 80


func configure(next_xp_amount: int, next_soldier_count: int = 1) -> void:
	xp_amount = max(0, next_xp_amount)
	soldier_count = max(1, next_soldier_count)


func pool_reset() -> void:
	time_alive = 0.0
	is_collected = false
	is_expiring = false
	target_player = null
	current_magnet_speed = 0.0
	_player_search_timer = randf_range(0.0, player_search_interval)
	_wave_sample_timer = randf_range(0.0, wave_sample_interval)
	_float_phase = randf_range(0.0, TAU)
	base_y = global_position.y
	_cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	_cached_um = get_node_or_null("/root/UpgradeManager")
	_cached_ocean = get_tree().get_first_node_in_group("ocean") if is_inside_tree() else null
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	if visual:
		_visual_rest_scale = Vector3.ONE * (0.78 + minf(0.45, float(soldier_count - 1) * 0.12))
		visual.position.y = visual_waterline_offset
		visual.scale = Vector3.ZERO
		var tween := create_tween()
		tween.tween_property(visual, "scale", _visual_rest_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if visual is GeometryInstance3D:
			(visual as GeometryInstance3D).extra_cull_margin = 1.0


func _physics_process(delta: float) -> void:
	if is_collected or not is_inside_tree():
		return
	time_alive += delta
	_wave_sample_timer = maxf(0.0, _wave_sample_timer - delta)
	_player_search_timer = maxf(0.0, _player_search_timer - delta)
	if not is_expiring and time_alive > lifetime:
		_expire_and_free()
	if is_expiring:
		return

	if is_instance_valid(target_player) and (not target_player.is_inside_tree() or NodeContractHelper.is_sinking_or_dying(target_player)):
		target_player = null
	if not is_instance_valid(target_player) and _player_search_timer <= 0.0:
		_player_search_timer = player_search_interval
		_find_target_player()

	if is_instance_valid(target_player) and target_player.is_inside_tree():
		var dist: float = global_position.distance_to(target_player.global_position)
		var radius := _get_current_magnet_radius()
		var lock_radius := radius * 1.35
		var within_pull_zone := dist <= radius or (current_magnet_speed > 0.1 and dist <= lock_radius)
		if within_pull_zone:
			var pull_target := FieldItemHelper.get_ship_side_anchor(self, target_player, false)
			var pull_distance := global_position.distance_to(pull_target)
			var ship_speed_bonus := maxf(0.0, NodeContractHelper.get_current_speed_value(target_player)) * 0.75
			var desired_speed := magnet_speed + ship_speed_bonus + (16.0 / maxf(pull_distance, 0.8))
			current_magnet_speed = move_toward(current_magnet_speed, desired_speed, 24.0 * delta)
			FieldItemHelper.move_item_toward_ship_side_anchor(self, target_player, current_magnet_speed * delta)
			_apply_floating(delta)
			if _is_close_enough_to_collect(target_player):
				_collect_by_proximity()
		else:
			current_magnet_speed = 0.0
			_apply_floating(delta)
	else:
		_apply_floating(delta)


func _apply_floating(delta: float) -> void:
	var has_ocean_surface := is_instance_valid(_cached_ocean) and _cached_ocean.has_method("get_wave_height")
	if has_ocean_surface:
		if _wave_sample_timer <= 0.0:
			_sample_ocean_surface()
			_wave_sample_timer = wave_sample_interval
	var target_y := FieldItemHelper.get_floating_waterline_target_y(
		base_y,
		time_alive,
		float_speed,
		float_height,
		_float_phase,
		waterline_offset,
		_cached_wave_height,
		has_ocean_surface
	)
	position.y = lerp(position.y, target_y, 4.0 * delta)
	FieldItemHelper.apply_floating_visual_motion(visual, delta, time_alive, float_speed, _float_phase, _cached_wave_tilt, wave_tilt_strength, rotation_speed)


func _sample_ocean_surface() -> void:
	var sample := FieldItemHelper.sample_ocean_surface(self, _cached_ocean)
	_cached_wave_height = float(sample.get("height", 0.0))
	_cached_wave_tilt = sample.get("tilt", Vector2.ZERO)


func _find_target_player() -> void:
	target_player = FieldItemHelper.find_closest_player_ship(self, _get_current_magnet_radius())


func _get_current_magnet_radius() -> float:
	return FieldItemHelper.get_current_magnet_radius(self, base_magnet_radius, _cached_um)


func _on_body_entered(body: Node3D) -> void:
	if is_collected:
		return
	var ship := FieldItemHelper.get_ship_from_node(body)
	if ship != null and ship.is_in_group("player"):
		_try_collect(ship)


func _on_area_entered(area: Area3D) -> void:
	if is_collected:
		return
	var ship := FieldItemHelper.get_ship_from_node(area)
	if ship != null and ship.is_in_group("player"):
		_try_collect(ship)


func _collect_by_proximity() -> void:
	if is_collected or not is_instance_valid(target_player):
		return
	_try_collect(target_player)


func _try_collect(player_ship: Node3D) -> void:
	if is_collected or not is_instance_valid(player_ship):
		return
	if not _is_close_enough_to_collect(player_ship):
		target_player = player_ship
		return
	is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_grant_reward(player_ship)
	_finish_collection_effect()


func _is_close_enough_to_collect(player_ship: Node3D) -> bool:
	return FieldItemHelper.is_item_close_to_ship_edge(self, player_ship, collection_contact_margin)


func _grant_reward(player_ship: Node3D) -> void:
	if not is_instance_valid(_cached_lm):
		_cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(_cached_lm) and xp_amount > 0 and _cached_lm.has_method("add_xp"):
		_cached_lm.add_xp(xp_amount)
	if is_instance_valid(_cached_lm) and _cached_lm.get("hud") != null:
		var hud: Variant = _cached_lm.get("hud")
		if is_instance_valid(hud) and hud.has_method("show_message"):
			hud.call("show_message", "표류 적병 수습: XP +%d" % xp_amount, 1.5)
	var audio_manager := get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("treasure_collect", null, randf_range(0.9, 1.05))
	target_player = player_ship


func _finish_collection_effect() -> void:
	if visual:
		var tween := create_tween()
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		var self_id := get_instance_id()
		tween.tween_callback(func(): ScenePool.release_by_instance_id(self_id))
	else:
		ScenePool.release(self)


func _expire_and_free() -> void:
	is_expiring = true
	is_collected = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 1.6, 2.5)
	if visual:
		tween.tween_property(visual, "scale", Vector3.ZERO, 2.5)
	var self_id := get_instance_id()
	tween.chain().tween_callback(func(): ScenePool.release_by_instance_id(self_id))


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
