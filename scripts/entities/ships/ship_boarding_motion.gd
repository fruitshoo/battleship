extends RefCounted
class_name ShipBoardingMotion

const HEADING_DIR := "heading_dir"
const DESIRED_SPEED := "desired_speed"
const CORRECTION_VELOCITY := "correction_velocity"
const PARALLEL_HOLD := "parallel_hold"


static func build(
	heading_dir: Vector3,
	desired_speed: float,
	correction_velocity: Vector3 = Vector3.ZERO,
	parallel_hold: bool = false
) -> Dictionary:
	return {
		HEADING_DIR: heading_dir,
		DESIRED_SPEED: desired_speed,
		CORRECTION_VELOCITY: correction_velocity,
		PARALLEL_HOLD: parallel_hold,
	}


static func get_heading_dir(motion: Dictionary, fallback: Vector3 = Vector3.FORWARD) -> Vector3:
	return _get_vector(motion, HEADING_DIR, fallback)


static func get_desired_speed(motion: Dictionary, fallback: float = 0.0) -> float:
	return _get_float(motion, DESIRED_SPEED, fallback)


static func get_correction_velocity(motion: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(motion, CORRECTION_VELOCITY, fallback)


static func is_parallel_hold(motion: Dictionary, fallback: bool = false) -> bool:
	var value: Variant = motion.get(PARALLEL_HOLD, fallback)
	return value == true


static func _get_vector(motion: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = motion.get(key, fallback)
	return value if value is Vector3 else fallback


static func _get_float(motion: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = motion.get(key, fallback)
	return float(value) if value != null else fallback
