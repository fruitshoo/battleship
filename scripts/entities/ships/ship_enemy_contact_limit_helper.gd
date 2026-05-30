extends RefCounted
class_name ShipEnemyContactLimitHelper

const LIMIT_SHIP_COUNT := 12
const TIMESLICE_FRAMES := 3
const COLLISION_MAX_CONTACTS := 3
const GUARD_MAX_CHECKS := 2


static func should_limit(ship_team: String, other_team: String, ship_count: int) -> bool:
	return ship_count >= LIMIT_SHIP_COUNT and ship_team == "enemy" and other_team == "enemy"


static func is_timeslice_active(ship: Node, other_ship: Node, current_frame: int) -> bool:
	if not is_instance_valid(ship) or not is_instance_valid(other_ship):
		return false
	var pair_hash := get_pair_hash(ship, other_ship)
	return pair_hash % TIMESLICE_FRAMES == current_frame % TIMESLICE_FRAMES


static func get_max_collision_contacts() -> int:
	return COLLISION_MAX_CONTACTS


static func get_max_guard_checks() -> int:
	return GUARD_MAX_CHECKS


static func get_pair_hash(ship: Node, other_ship: Node) -> int:
	var ship_id: int = ship.get_instance_id()
	var other_id: int = other_ship.get_instance_id()
	return absi(ship_id * 31 + other_id * 17)
