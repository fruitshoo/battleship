extends Node3D
class_name WakeTrail3D

var _active: bool = false

var emitting: bool:
	get:
		return _active
	set(value):
		_active = value


func set_wake_state(active: bool, speed_ratio: float = 0.0, turn_ratio: float = 0.0, turbulence: float = 0.0) -> void:
	_active = active
