extends RefCounted
class_name SoldierCombatOverboardHelper


const DEFAULT_ROTATION_DELAY := 0.24


static func make_throw_arc_data(
	start_position: Vector3,
	throw_target: Vector3,
	start_rotation: Vector3,
	arc_height_min: float,
	arc_height_max: float,
	spin_min: Vector3,
	spin_max: Vector3,
	rotation_delay: float = DEFAULT_ROTATION_DELAY,
	control_weight: float = 0.5
) -> Dictionary:
	var arc_control := start_position.lerp(throw_target, clampf(control_weight, 0.0, 1.0))
	arc_control.y = maxf(start_position.y, throw_target.y) + randf_range(arc_height_min, arc_height_max)
	return {
		"start_position": start_position,
		"arc_control": arc_control,
		"throw_target": throw_target,
		"start_rotation": start_rotation,
		"spin_rotation": start_rotation + Vector3(
			randf_range(spin_min.x, spin_max.x),
			randf_range(spin_min.y, spin_max.y),
			randf_range(spin_min.z, spin_max.z)
		),
		"rotation_delay": clampf(rotation_delay, 0.0, 0.85),
	}


static func apply_throw_arc(body: Node3D, arc_data: Dictionary, progress: float) -> void:
	if not is_instance_valid(body):
		return
	var start_position: Vector3 = arc_data.get("start_position", body.global_position)
	var arc_control: Vector3 = arc_data.get("arc_control", start_position)
	var throw_target: Vector3 = arc_data.get("throw_target", start_position)
	var start_rotation: Vector3 = arc_data.get("start_rotation", body.rotation)
	var spin_rotation: Vector3 = arc_data.get("spin_rotation", start_rotation)
	var t := clampf(progress, 0.0, 1.0)
	body.global_position = start_position * ((1.0 - t) * (1.0 - t)) \
		+ arc_control * (2.0 * (1.0 - t) * t) \
		+ throw_target * (t * t)
	var rotation_t := _get_delayed_rotation_progress(t, float(arc_data.get("rotation_delay", DEFAULT_ROTATION_DELAY)))
	body.rotation = Vector3(
		lerp_angle(start_rotation.x, spin_rotation.x, rotation_t),
		lerp_angle(start_rotation.y, spin_rotation.y, rotation_t),
		lerp_angle(start_rotation.z, spin_rotation.z, rotation_t)
	)


static func _get_delayed_rotation_progress(progress: float, rotation_delay: float) -> float:
	var delay := clampf(rotation_delay, 0.0, 0.85)
	if progress <= delay:
		return 0.0
	var rotation_progress := (progress - delay) / maxf(0.001, 1.0 - delay)
	return smoothstep(0.0, 1.0, clampf(rotation_progress, 0.0, 1.0))
