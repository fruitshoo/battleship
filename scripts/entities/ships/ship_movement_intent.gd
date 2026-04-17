extends RefCounted
class_name ShipMovementIntent

const TARGET_POS := "target_pos"
const DESIRED_POINT := "desired_point"
const HEADING_POINT := "heading_point"
const DIST_TO_TARGET := "dist_to_target"
const DESIRED_SPEED_MULT := "desired_speed_mult"
const PERMIT_SPRINT := "permit_sprint"
const DIR_TO_TARGET := "dir_to_target"
const MODE := "mode"


static func build(
	target_pos: Vector3,
	desired_point: Vector3,
	heading_point: Vector3,
	dist_to_target: float,
	desired_speed_mult: float = 1.0,
	permit_sprint: bool = true,
	dir_to_target: Vector3 = Vector3.ZERO,
	mode: String = ""
) -> Dictionary:
	return {
		TARGET_POS: target_pos,
		DESIRED_POINT: desired_point,
		HEADING_POINT: heading_point,
		DIST_TO_TARGET: dist_to_target,
		DESIRED_SPEED_MULT: desired_speed_mult,
		PERMIT_SPRINT: permit_sprint,
		DIR_TO_TARGET: dir_to_target,
		MODE: mode,
	}


static func build_partial(
	desired_point: Vector3,
	heading_point: Vector3,
	desired_speed_mult: float = 1.0,
	permit_sprint: bool = true,
	mode: String = ""
) -> Dictionary:
	var intent := {
		DESIRED_POINT: desired_point,
		HEADING_POINT: heading_point,
		DESIRED_SPEED_MULT: desired_speed_mult,
		PERMIT_SPRINT: permit_sprint,
	}
	if not mode.strip_edges().is_empty():
		intent[MODE] = mode.strip_edges()
	return intent


static func get_target_pos(intent: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(intent, TARGET_POS, fallback)


static func get_desired_point(intent: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(intent, DESIRED_POINT, fallback)


static func get_heading_point(intent: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(intent, HEADING_POINT, fallback)


static func get_dist_to_target(intent: Dictionary, fallback: float = 0.0) -> float:
	return _get_float(intent, DIST_TO_TARGET, fallback)


static func get_desired_speed_mult(intent: Dictionary, fallback: float = 1.0) -> float:
	return _get_float(intent, DESIRED_SPEED_MULT, fallback)


static func get_permit_sprint(intent: Dictionary, fallback: bool = true) -> bool:
	var value: Variant = intent.get(PERMIT_SPRINT, fallback)
	return value == true


static func get_dir_to_target(intent: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(intent, DIR_TO_TARGET, fallback)


static func get_mode(intent: Dictionary, fallback: String = "") -> String:
	var value: Variant = intent.get(MODE, fallback)
	return str(value).strip_edges() if value != null else fallback


static func _get_vector(intent: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = intent.get(key, fallback)
	return value if value is Vector3 else fallback


static func _get_float(intent: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = intent.get(key, fallback)
	return float(value) if value != null else fallback
