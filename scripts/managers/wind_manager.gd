@tool
extends Node

## 글로벌 바람 시스템 관리
## AutoLoad로 설정하여 모든 배가 접근 가능

var wind_direction: Vector2 = Vector2(1, 0)
@export_range(0.0, 1.0, 0.01) var wind_strength: float = 0.7
var wind_angle_degrees: float = 0.0

@export var drift_enabled: bool = true
@export_range(0.05, 10.0, 0.05) var angle_change_speed: float = 1.2
@export var angle_target_interval_min: float = 5.0
@export var angle_target_interval_max: float = 12.0
@export_range(-180.0, 180.0, 1.0) var max_angle_offset_from_current: float = 20.0

@export var strength_drift_enabled: bool = true
@export_range(0.01, 1.0, 0.01) var strength_change_speed: float = 0.04
@export var strength_target_interval_min: float = 6.0
@export var strength_target_interval_max: float = 14.0
@export_range(0.0, 1.0, 0.01) var min_wind_strength: float = 0.72
@export_range(0.0, 1.0, 0.01) var max_wind_strength: float = 0.88

var _target_wind_angle_degrees: float = 0.0
var _target_wind_strength: float = 0.7
var _angle_target_timer: float = 0.0
var _strength_target_timer: float = 0.0

signal wind_changed(direction: Vector2, strength: float)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	var initial_angle := randf_range(0.0, 360.0)
	set_wind_angle(initial_angle)
	wind_strength = clamp(wind_strength, min_wind_strength, max_wind_strength)
	_target_wind_angle_degrees = wind_angle_degrees
	_target_wind_strength = wind_strength
	_reset_angle_target_timer()
	_reset_strength_target_timer()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var changed := false
	
	if drift_enabled:
		_angle_target_timer -= delta
		if _angle_target_timer <= 0.0:
			_pick_next_angle_target()
		var previous_angle := wind_angle_degrees
		wind_angle_degrees = _move_angle_toward(wind_angle_degrees, _target_wind_angle_degrees, angle_change_speed * delta)
		if not is_equal_approx(previous_angle, wind_angle_degrees):
			_update_direction_from_angle()
			changed = true
	
	if strength_drift_enabled:
		_strength_target_timer -= delta
		if _strength_target_timer <= 0.0:
			_pick_next_strength_target()
		var previous_strength := wind_strength
		wind_strength = move_toward(wind_strength, _target_wind_strength, strength_change_speed * delta)
		if not is_equal_approx(previous_strength, wind_strength):
			changed = true
	
	if changed:
		wind_changed.emit(wind_direction, wind_strength)


func set_wind_direction(direction: Vector2) -> void:
	wind_direction = direction.normalized()
	_update_wind_angle()
	_target_wind_angle_degrees = wind_angle_degrees


func set_wind_angle(angle_degrees: float) -> void:
	wind_angle_degrees = wrapf(angle_degrees, 0.0, 360.0)
	_update_direction_from_angle()
	_target_wind_angle_degrees = wind_angle_degrees


func set_wind_strength(strength: float) -> void:
	wind_strength = clamp(strength, min_wind_strength, max_wind_strength)
	_target_wind_strength = wind_strength


func get_wind_direction() -> Vector2:
	return wind_direction


func get_wind_strength() -> float:
	return wind_strength


func _update_wind_angle() -> void:
	wind_angle_degrees = rad_to_deg(atan2(wind_direction.x, -wind_direction.y))
	if wind_angle_degrees < 0.0:
		wind_angle_degrees += 360.0


func _update_direction_from_angle() -> void:
	var angle_rad := deg_to_rad(wind_angle_degrees)
	wind_direction = Vector2(sin(angle_rad), -cos(angle_rad)).normalized()


func _pick_next_angle_target() -> void:
	var offset := randf_range(-max_angle_offset_from_current, max_angle_offset_from_current)
	_target_wind_angle_degrees = wrapf(wind_angle_degrees + offset, 0.0, 360.0)
	_reset_angle_target_timer()


func _pick_next_strength_target() -> void:
	_target_wind_strength = randf_range(min_wind_strength, max_wind_strength)
	_reset_strength_target_timer()


func _reset_angle_target_timer() -> void:
	_angle_target_timer = randf_range(angle_target_interval_min, angle_target_interval_max)


func _reset_strength_target_timer() -> void:
	_strength_target_timer = randf_range(strength_target_interval_min, strength_target_interval_max)


func _move_angle_toward(from_deg: float, to_deg: float, delta_deg: float) -> float:
	var diff := wrapf(to_deg - from_deg + 180.0, 0.0, 360.0) - 180.0
	if absf(diff) <= delta_deg:
		return wrapf(to_deg, 0.0, 360.0)
	return wrapf(from_deg + signf(diff) * delta_deg, 0.0, 360.0)
