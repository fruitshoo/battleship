extends RefCounted
class_name BaseShipRudderHelper

static func apply_rudder_damage(ship, amount: float) -> void:
	if amount <= 0.0 or ship.rudder_max_health <= 0.0:
		return
	var prev_ratio: float = get_rudder_health_ratio(ship)
	ship.rudder_health = clampf(ship.rudder_health - amount, 0.0, ship.rudder_max_health)
	var current_ratio: float = get_rudder_health_ratio(ship)
	if current_ratio <= ship.rudder_critical_threshold and prev_ratio > ship.rudder_critical_threshold and not ship._rudder_critical_announced:
		ship._rudder_critical_announced = true
		if is_instance_valid(ship._cached_hud) and ship._cached_hud.has_method("show_gust_warning_message"):
			ship._cached_hud.show_gust_warning_message("조타 손상", 0.9)
	elif current_ratio > ship.rudder_critical_threshold:
		ship._rudder_critical_announced = false


static func get_rudder_health_ratio(ship) -> float:
	if ship.rudder_max_health <= 0.0:
		return 1.0
	return clampf(ship.rudder_health / ship.rudder_max_health, 0.0, 1.0)


static func get_rudder_turn_multiplier(ship) -> float:
	var rudder_ratio: float = get_rudder_health_ratio(ship)
	var handling_mult: float = ship.get_shiphandling_multiplier()
	var compounded_penalty: float = lerpf(0.72, 1.0, rudder_ratio)
	return lerpf(0.35, 1.0, rudder_ratio) * handling_mult * compounded_penalty


static func get_rudder_response_multiplier(ship) -> float:
	var rudder_ratio: float = get_rudder_health_ratio(ship)
	var handling_mult: float = ship.get_shiphandling_multiplier()
	var compounded_penalty: float = lerpf(0.78, 1.0, rudder_ratio)
	return lerpf(0.45, 1.0, rudder_ratio) * handling_mult * compounded_penalty


static func apply_rudder_damage_from_hit(ship, final_damage: float, hit_position: Vector3, damage_source: String) -> void:
	if ship.rudder_max_health <= 0.0 or damage_source.is_empty() or damage_source == "leak":
		return
	var source_mult: float = 0.0
	if damage_source.begins_with("ramming"):
		source_mult = 0.7
	elif damage_source.contains("cannon"):
		source_mult = 0.18
	elif damage_source.contains("ballista") or damage_source.contains("singigeon") or damage_source.contains("fire"):
		source_mult = 0.10
	if source_mult <= 0.0:
		return
	var stern_factor: float = get_stern_hit_factor(ship, hit_position)
	var damage_mult: float = lerpf(0.45, 1.8, stern_factor)
	var rudder_damage: float = (final_damage * source_mult) * damage_mult
	if damage_source.begins_with("ramming"):
		rudder_damage = maxf(rudder_damage, 10.0 * damage_mult)
	apply_rudder_damage(ship, clampf(rudder_damage, 0.0, ship.rudder_max_health * 0.45))


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
