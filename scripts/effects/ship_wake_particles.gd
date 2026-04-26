extends GPUParticles3D
class_name ShipWakeParticles

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

var _base_position: Vector3
var _base_scale: Vector3 = Vector3.ONE
var _base_amount: int = 20
var _base_values_cached: bool = false
var _current_width_scale: float = 1.0
var _current_length_scale: float = 1.0


func _ready() -> void:
	_cache_base_values()
	_refresh_auto_fit()
	set_wake_state(false, 0.0, 0.0, 0.0)


func set_wake_state(active: bool, speed_ratio: float = 0.0, turn_ratio: float = 0.0, turbulence: float = 0.0) -> void:
	_refresh_auto_fit()
	emitting = active
	var intensity := clampf(maxf(speed_ratio, turbulence * 0.65), 0.0, 1.0)
	if not active:
		intensity = 0.0
	set("amount_ratio", lerpf(idle_amount_ratio, active_amount_ratio, intensity))
	speed_scale = lerpf(idle_speed_scale, active_speed_scale, intensity)
	position = _base_position + Vector3(clampf(turn_ratio, -1.0, 1.0) * turn_offset * _current_width_scale, 0.0, 0.0)


func _cache_base_values() -> void:
	if _base_values_cached:
		return
	_base_position = position
	_base_scale = scale
	_base_amount = amount
	_base_values_cached = true


func _refresh_auto_fit() -> void:
	_cache_base_values()
	_current_width_scale = 1.0
	_current_length_scale = 1.0
	if not auto_fit_to_parent_ship:
		scale = _base_scale
		amount = _base_amount
		return

	var ship := _find_parent_ship()
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


func _find_parent_ship() -> Node:
	var node := get_parent()
	while is_instance_valid(node):
		if node.has_method("get_collision_half_extents") or node.get("base_collision_radius") != null:
			return node
		node = node.get_parent()
	return null


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
