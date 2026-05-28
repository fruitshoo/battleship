extends GPUParticles3D
class_name ShipWakeParticles

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")

@export_range(0.0, 1.0, 0.01) var idle_amount_ratio: float = 0.35
@export_range(0.0, 1.0, 0.01) var active_amount_ratio: float = 1.0
@export_range(0.1, 2.0, 0.01) var idle_speed_scale: float = 0.75
@export_range(0.1, 2.0, 0.01) var active_speed_scale: float = 1.25
@export_range(0.0, 1.0, 0.01) var turn_offset: float = 0.18
@export var auto_fit_to_parent_ship: bool = true
@export_range(0.5, 8.0, 0.05) var reference_half_width: float = 2.1
@export_range(1.0, 12.0, 0.05) var reference_half_length: float = 4.65
@export_range(0.0, 1.0, 0.01) var auto_fit_strength: float = 0.65
@export_range(0.0, 1.0, 0.01) var amount_auto_fit_strength: float = 0.45
@export_range(0.2, 1.0, 0.01) var min_width_scale: float = 0.55
@export_range(1.0, 2.5, 0.01) var max_width_scale: float = 1.45
@export_range(0.2, 1.0, 0.01) var min_length_scale: float = 0.65
@export_range(1.0, 2.5, 0.01) var max_length_scale: float = 1.55
@export_range(0.05, 2.0, 0.05) var auto_fit_refresh_interval: float = 0.5
@export var distance_lod_enabled: bool = true
@export_range(20.0, 180.0, 1.0) var lod_near_distance: float = 70.0
@export_range(40.0, 240.0, 1.0) var lod_far_distance: float = 130.0
@export_range(0.2, 1.0, 0.01) var lod_far_amount_multiplier: float = 0.48
@export_range(80.0, 320.0, 1.0) var lod_hide_distance: float = 190.0
@export_range(0.05, 2.0, 0.05) var lod_refresh_interval: float = 0.35
@export var load_lod_enabled: bool = true
@export_range(0.45, 1.0, 0.01) var load_lod_min_amount_multiplier: float = 0.68
@export var preserve_player_flagship_wake: bool = true
@export_range(0.25, 1.0, 0.01) var non_player_amount_multiplier: float = 0.82
@export_range(0.2, 1.0, 0.01) var support_amount_multiplier: float = 0.68
@export var offscreen_cull_enabled: bool = true
@export_range(0.0, 0.5, 0.01) var offscreen_cull_viewport_margin: float = 0.12
@export_range(0.0, 180.0, 1.0) var offscreen_cull_min_distance: float = 45.0

var _base_position: Vector3
var _base_scale: Vector3 = Vector3.ONE
var _base_amount: int = 20
var _cached_parent_ship: Node = null
var _base_values_cached: bool = false
var _current_width_scale: float = 1.0
var _current_length_scale: float = 1.0
var _next_auto_fit_refresh_msec: int = 0
var _next_lod_refresh_msec: int = 0
var _lod_amount_multiplier: float = 1.0
var _lod_hidden: bool = false
var _last_amount_ratio: float = -1.0
var _last_speed_scale: float = -1.0


func _enter_tree() -> void:
	_stop_wake_immediately()


func _ready() -> void:
	_stop_wake_immediately()
	_cache_base_values()
	_refresh_auto_fit(true)
	_refresh_distance_lod(true)
	set_wake_state(false, 0.0, 0.0, 0.0)


func set_wake_state(active: bool, speed_ratio: float = 0.0, turn_ratio: float = 0.0, turbulence: float = 0.0) -> void:
	_refresh_auto_fit(false)
	_refresh_distance_lod(false)
	var ship := _get_parent_ship()
	var effective_active := active and not _lod_hidden and is_instance_valid(ship)
	if emitting != effective_active:
		emitting = effective_active
	var intensity := clampf(maxf(speed_ratio, turbulence * 0.65), 0.0, 1.0)
	if not effective_active:
		intensity = 0.0
	var next_amount_ratio := lerpf(idle_amount_ratio, active_amount_ratio, intensity) * _lod_amount_multiplier * _get_load_lod_amount_multiplier()
	var next_speed_scale := lerpf(idle_speed_scale, active_speed_scale, intensity)
	_apply_amount_ratio(next_amount_ratio)
	_apply_speed_scale(next_speed_scale)
	position = _base_position + Vector3(clampf(turn_ratio, -1.0, 1.0) * turn_offset * _current_width_scale, 0.0, 0.0)


func _stop_wake_immediately() -> void:
	emitting = false
	_apply_amount_ratio(0.0)


func _cache_base_values() -> void:
	if _base_values_cached:
		return
	_base_position = position
	_base_scale = scale
	_base_amount = amount
	_base_values_cached = true


func _refresh_auto_fit(force: bool = false) -> void:
	_cache_base_values()
	if not force and auto_fit_refresh_interval > 0.0:
		var now_msec := Time.get_ticks_msec()
		if now_msec < _next_auto_fit_refresh_msec:
			return
		_next_auto_fit_refresh_msec = now_msec + max(1, int(round(auto_fit_refresh_interval * 1000.0)))

	_current_width_scale = 1.0
	_current_length_scale = 1.0
	if not auto_fit_to_parent_ship:
		scale = _base_scale
		amount = _base_amount
		return

	var ship := _get_parent_ship()
	var half_extents := _resolve_ship_half_extents(ship)
	var raw_width_scale := clampf(half_extents.x / maxf(reference_half_width, 0.01), min_width_scale, max_width_scale)
	var raw_length_scale := clampf(half_extents.y / maxf(reference_half_length, 0.01), min_length_scale, max_length_scale)
	_current_width_scale = lerpf(1.0, raw_width_scale, auto_fit_strength)
	_current_length_scale = lerpf(1.0, raw_length_scale, auto_fit_strength)
	scale = Vector3(
		_base_scale.x * _current_width_scale,
		_base_scale.y,
		_base_scale.z * _current_length_scale
	)

	var average_scale := (_current_width_scale + _current_length_scale) * 0.5
	var amount_scale := lerpf(1.0, average_scale, amount_auto_fit_strength)
	amount = maxi(1, int(round(float(_base_amount) * amount_scale)))


func _refresh_distance_lod(force: bool = false) -> void:
	if not distance_lod_enabled:
		_lod_amount_multiplier = 1.0
		_lod_hidden = false
		return
	if not force and lod_refresh_interval > 0.0:
		var now_msec := Time.get_ticks_msec()
		if now_msec < _next_lod_refresh_msec:
			return
		_next_lod_refresh_msec = now_msec + max(1, int(round(lod_refresh_interval * 1000.0)))

	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if not is_instance_valid(camera):
		_lod_amount_multiplier = 1.0
		_lod_hidden = false
		return

	var camera_node := camera as Camera3D
	var distance := camera_node.global_position.distance_to(global_position)
	if distance >= lod_hide_distance:
		_lod_amount_multiplier = 0.0
		_lod_hidden = true
		return
	var ship := _get_parent_ship()
	if _should_hide_non_player_offscreen(camera_node, ship, distance):
		_lod_amount_multiplier = 0.0
		_lod_hidden = true
		return

	_lod_hidden = false
	var fade_range := maxf(lod_far_distance - lod_near_distance, 1.0)
	var far_ratio := clampf((distance - lod_near_distance) / fade_range, 0.0, 1.0)
	_lod_amount_multiplier = lerpf(1.0, lod_far_amount_multiplier, far_ratio)


func _get_load_lod_amount_multiplier() -> float:
	if not load_lod_enabled:
		return 1.0
	var ship := _get_parent_ship()
	if preserve_player_flagship_wake and NodeContractHelper.is_player_controlled_ship(ship):
		return 1.0
	var budget_scale := VfxBudget.get_continuous_effect_scale()
	var normalized_budget := clampf((budget_scale - 0.35) / 0.65, 0.0, 1.0)
	var load_multiplier := lerpf(load_lod_min_amount_multiplier, 1.0, normalized_budget)
	return load_multiplier * _get_non_player_amount_multiplier(ship)


func _apply_amount_ratio(value: float) -> void:
	var clamped_value := clampf(value, 0.0, 1.0)
	if is_equal_approx(_last_amount_ratio, clamped_value):
		return
	_last_amount_ratio = clamped_value
	set("amount_ratio", clamped_value)


func _apply_speed_scale(value: float) -> void:
	if is_equal_approx(_last_speed_scale, value):
		return
	_last_speed_scale = value
	speed_scale = value


func _get_parent_ship() -> Node:
	if is_instance_valid(_cached_parent_ship) and _cached_parent_ship.is_ancestor_of(self):
		return _cached_parent_ship
	_cached_parent_ship = _find_parent_ship()
	return _cached_parent_ship


func _find_parent_ship() -> Node:
	var node := get_parent()
	while is_instance_valid(node):
		if node.has_method("get_collision_half_extents") or node.get("base_collision_radius") != null:
			return node
		node = node.get_parent()
	return null


func _should_hide_non_player_offscreen(camera: Camera3D, ship: Node, distance: float) -> bool:
	if not offscreen_cull_enabled:
		return false
	if not is_instance_valid(camera) or not is_instance_valid(ship):
		return false
	if preserve_player_flagship_wake and NodeContractHelper.is_player_controlled_ship(ship):
		return false
	if distance < offscreen_cull_min_distance:
		return false
	if camera.is_position_behind(global_position):
		return true
	var viewport := get_viewport()
	if viewport == null:
		return false
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return false
	var screen_point := camera.unproject_position(global_position)
	var margin := viewport_size * offscreen_cull_viewport_margin
	var min_point := -margin
	var max_point := viewport_size + margin
	return (
		screen_point.x < min_point.x
		or screen_point.y < min_point.y
		or screen_point.x > max_point.x
		or screen_point.y > max_point.y
	)


func _get_non_player_amount_multiplier(ship: Node) -> float:
	if not is_instance_valid(ship):
		return non_player_amount_multiplier
	if NodeContractHelper.is_player_controlled_ship(ship):
		return 1.0
	if PlayerFleetRoleHelper.is_support_ship(ship):
		return support_amount_multiplier
	return non_player_amount_multiplier


func _resolve_ship_half_extents(ship: Node) -> Vector2:
	if is_instance_valid(ship) and ship.has_method("get_collision_half_extents"):
		var collision_extents: Variant = ship.call("get_collision_half_extents")
		if collision_extents is Vector2:
			return collision_extents as Vector2

	if is_instance_valid(ship):
		var base_radius := _get_float_property(ship, "base_collision_radius", reference_half_length)
		var width_multiplier := _get_float_property(ship, "width_multiplier", reference_half_width / maxf(base_radius, 0.01))
		var length_multiplier := _get_float_property(ship, "length_multiplier", 1.0)
		return Vector2(
			maxf(0.01, base_radius * width_multiplier),
			maxf(0.01, base_radius * length_multiplier)
		)

	return Vector2(reference_half_width, reference_half_length)


func _get_float_property(node: Node, property_name: StringName, fallback: float) -> float:
	if not is_instance_valid(node):
		return fallback
	var value: Variant = node.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback
