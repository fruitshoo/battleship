extends GPUParticles3D
class_name ShipWakeParticles

@export_range(0.0, 1.0, 0.01) var idle_amount_ratio: float = 0.35
@export_range(0.0, 1.0, 0.01) var active_amount_ratio: float = 1.0
@export_range(0.1, 2.0, 0.01) var idle_speed_scale: float = 0.75
@export_range(0.1, 2.0, 0.01) var active_speed_scale: float = 1.25
@export_range(0.0, 1.0, 0.01) var turn_offset: float = 0.18

var _base_position: Vector3


func _ready() -> void:
	_base_position = position
	set_wake_state(false, 0.0, 0.0, 0.0)


func set_wake_state(active: bool, speed_ratio: float = 0.0, turn_ratio: float = 0.0, turbulence: float = 0.0) -> void:
	emitting = active
	var intensity := clampf(maxf(speed_ratio, turbulence * 0.65), 0.0, 1.0)
	if not active:
		intensity = 0.0
	set("amount_ratio", lerpf(idle_amount_ratio, active_amount_ratio, intensity))
	speed_scale = lerpf(idle_speed_scale, active_speed_scale, intensity)
	position = _base_position + Vector3(clampf(turn_ratio, -1.0, 1.0) * turn_offset, 0.0, 0.0)
