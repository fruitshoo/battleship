extends RefCounted
class_name BaseShipRudderHelper

static func apply_rudder_damage(ship, amount: float) -> void:
	if amount <= 0.0 or ship.rudder_max_health <= 0.0:
		return
	ship.rudder_health = ship.rudder_max_health
	ship._rudder_critical_announced = false


static func get_rudder_health_ratio(ship) -> float:
	return 1.0


static func get_rudder_turn_multiplier(ship) -> float:
	var handling_mult: float = ship.get_shiphandling_multiplier()
	return maxf(0.60, handling_mult) * get_furled_sail_rudder_multiplier(ship)


static func get_rudder_response_multiplier(ship) -> float:
	var handling_mult: float = ship.get_shiphandling_multiplier()
	return maxf(0.70, handling_mult) * get_furled_sail_rudder_multiplier(ship)


static func get_furled_sail_rudder_multiplier(ship) -> float:
	if "sail_furled" in ship and ship.get("sail_furled") == true:
		if "furled_sail_rudder_multiplier" in ship and ship.get("furled_sail_rudder_multiplier") != null:
			return maxf(1.0, float(ship.get("furled_sail_rudder_multiplier")))
	return 1.0


static func apply_rudder_damage_from_hit(_ship, _final_damage: float, _hit_position: Vector3, _damage_source: String) -> void:
	pass


static func get_stern_hit_factor(ship, hit_position: Vector3) -> float:
	if hit_position == Vector3.ZERO:
		return 0.0
	var to_hit: Vector3 = hit_position - ship.global_position
	to_hit.y = 0.0
	if to_hit.length_squared() <= 0.0001:
		return 0.0
	to_hit = to_hit.normalized()
	var backward: Vector3 = ship.global_transform.basis.z
	backward.y = 0.0
	if backward.length_squared() <= 0.0001:
		backward = Vector3.BACK
	else:
		backward = backward.normalized()
	var stern_alignment: float = backward.dot(to_hit)
	return clampf((stern_alignment - 0.15) / 0.85, 0.0, 1.0)
