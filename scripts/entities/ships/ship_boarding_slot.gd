extends RefCounted
class_name ShipBoardingSlot

const ID := "id"
const SIDE_SIGN := "side_sign"
const POINT := "point"
const HEADING := "heading"
const BIAS := "bias"

const PORT_BOW := "port_bow"
const STARBOARD_BOW := "starboard_bow"
const PORT_MID := "port_mid"
const STARBOARD_MID := "starboard_mid"


static func build(id: String, side_sign: float, point: Vector3, heading: Vector3, bias: float = 0.0) -> Dictionary:
	return {
		ID: id,
		SIDE_SIGN: side_sign,
		POINT: point,
		HEADING: heading,
		BIAS: bias,
	}


static func get_id(slot: Dictionary, fallback: String = "") -> String:
	var value: Variant = slot.get(ID, fallback)
	return str(value) if value != null else fallback


static func get_side_sign(slot: Dictionary, fallback: float = 0.0) -> float:
	return _get_float(slot, SIDE_SIGN, fallback)


static func get_point(slot: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(slot, POINT, fallback)


static func get_heading(slot: Dictionary, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return _get_vector(slot, HEADING, fallback)


static func get_bias(slot: Dictionary, fallback: float = 0.0) -> float:
	return _get_float(slot, BIAS, fallback)


static func _get_vector(slot: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = slot.get(key, fallback)
	return value if value is Vector3 else fallback


static func _get_float(slot: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = slot.get(key, fallback)
	return float(value) if value != null else fallback
