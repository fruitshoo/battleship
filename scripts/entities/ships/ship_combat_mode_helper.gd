extends RefCounted
class_name ShipCombatModeHelper

const ROLE_CHARGER := "charger"
const ROLE_GUNNER := "gunner"

const CHARGER_ROLE_INDEX := 0
const GUNNER_ROLE_INDEX := 1


static func is_gunner(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("is_gunner_role"):
		return ship.call("is_gunner_role") == true
	var role_value: Variant = ship.get("combat_role")
	return int(role_value) == GUNNER_ROLE_INDEX if role_value != null else false


static func is_charger(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("is_charger_role"):
		return ship.call("is_charger_role") == true
	return not is_gunner(ship)


static func can_board(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_method("can_board_targets"):
		return ship.call("can_board_targets") == true
	var allow_boarding: Variant = ship.get("allow_boarding")
	return allow_boarding == true if allow_boarding != null else false


static func can_be_boarded(target_ship: Node, attacker_ship: Node = null) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if target_ship.has_method("can_be_boarded_by"):
		return target_ship.call("can_be_boarded_by", attacker_ship) == true
	var blocks_boarding: Variant = target_ship.get("blocks_boarding")
	return blocks_boarding != true if blocks_boarding != null else true


static func preferred_range(ship: Node, fallback: float = 14.0) -> float:
	if not is_instance_valid(ship):
		return fallback
	if ship.has_method("get_preferred_engagement_range"):
		return float(ship.call("get_preferred_engagement_range"))
	var value: Variant = ship.get("preferred_combat_range")
	return float(value) if value != null else fallback


static func range_tolerance(ship: Node, fallback: float = 2.5) -> float:
	if not is_instance_valid(ship):
		return fallback
	if ship.has_method("get_engagement_range_tolerance"):
		return float(ship.call("get_engagement_range_tolerance"))
	var value: Variant = ship.get("combat_range_tolerance")
	return float(value) if value != null else fallback


static func retreat_distance(ship: Node, fallback: float = 8.0) -> float:
	if not is_instance_valid(ship):
		return fallback
	if ship.has_method("get_retreat_engagement_distance"):
		return float(ship.call("get_retreat_engagement_distance"))
	var value: Variant = ship.get("retreat_distance")
	return float(value) if value != null else fallback


static func normalize_role_name(role_name: String) -> String:
	var normalized := role_name.strip_edges().to_lower()
	return ROLE_GUNNER if normalized == ROLE_GUNNER else ROLE_CHARGER


static func sync_exported_profile_from_accessors(ship: Node) -> void:
	if not is_instance_valid(ship):
		return
	if ship.get("combat_role") != null:
		ship.set("combat_role", GUNNER_ROLE_INDEX if is_gunner(ship) else CHARGER_ROLE_INDEX)
	if ship.get("allow_boarding") != null:
		ship.set("allow_boarding", can_board(ship))
	if ship.get("preferred_combat_range") != null:
		ship.set("preferred_combat_range", preferred_range(ship))
	if ship.get("combat_range_tolerance") != null:
		ship.set("combat_range_tolerance", range_tolerance(ship))
	if ship.get("retreat_distance") != null:
		ship.set("retreat_distance", retreat_distance(ship))
