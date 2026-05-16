extends RefCounted
class_name SoldierDeckZoneHelper

const META_COMBAT_DECK_ZONE := "combat_deck_zone"
const META_ROOF_BOARDER := "geobuk_roof_boarder"

const ZONE_MAIN := ""
const ZONE_ROOF := "roof"


static func get_zone(soldier: Node) -> String:
	if not is_instance_valid(soldier):
		return ZONE_MAIN
	return str(soldier.get_meta(META_COMBAT_DECK_ZONE, ZONE_MAIN))


static func set_zone(soldier: Node, zone: String) -> void:
	if not is_instance_valid(soldier):
		return
	if zone.is_empty():
		if soldier.has_meta(META_COMBAT_DECK_ZONE):
			soldier.remove_meta(META_COMBAT_DECK_ZONE)
	else:
		soldier.set_meta(META_COMBAT_DECK_ZONE, zone)


static func clear_zone(soldier: Node) -> void:
	set_zone(soldier, ZONE_MAIN)


static func is_in_zone(soldier: Node, zone: String) -> bool:
	return get_zone(soldier) == zone


static func is_roof(soldier: Node) -> bool:
	return is_in_zone(soldier, ZONE_ROOF)


static func can_share_combat_zone(a: Node, b: Node) -> bool:
	var a_zone := get_zone(a)
	var b_zone := get_zone(b)
	if a_zone == b_zone:
		return true
	if a_zone == ZONE_ROOF or b_zone == ZONE_ROOF:
		return _is_same_ship_roof_combat_pair(a, b)
	return true


static func can_ignore_vertical_delta(a: Node, b: Node) -> bool:
	return _is_same_ship_roof_combat_pair(a, b)


static func _is_same_ship_roof_combat_pair(a: Node, b: Node) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	var a_zone := get_zone(a)
	var b_zone := get_zone(b)
	if a_zone == b_zone:
		return false
	if not (a_zone == ZONE_ROOF or b_zone == ZONE_ROOF):
		return false
	var a_ship := _get_owned_ship_node(a)
	var b_ship := _get_owned_ship_node(b)
	if not is_instance_valid(a_ship) or a_ship != b_ship:
		return false
	if NodeContractHelper.is_sinking_or_dying(a_ship):
		return false
	return a_ship.has_method("is_roof_boarding_enabled") and a_ship.call("is_roof_boarding_enabled") == true


static func _get_owned_ship_node(soldier: Node) -> Node:
	if not is_instance_valid(soldier):
		return null
	if soldier.has_method("get_owned_ship_node"):
		var owned_node: Variant = soldier.call("get_owned_ship_node")
		return owned_node if is_instance_valid(owned_node) and owned_node is Node else null
	if soldier.get("owned_ship") != null:
		var owned_value: Variant = soldier.get("owned_ship")
		return owned_value if is_instance_valid(owned_value) and owned_value is Node else null
	return null


static func is_roof_boarder(soldier: Node) -> bool:
	return is_instance_valid(soldier) and soldier.get_meta(META_ROOF_BOARDER, false) == true


static func set_roof_boarder(soldier: Node, enabled: bool) -> void:
	if not is_instance_valid(soldier):
		return
	if enabled:
		soldier.set_meta(META_ROOF_BOARDER, true)
		set_zone(soldier, ZONE_ROOF)
	else:
		if soldier.has_meta(META_ROOF_BOARDER):
			soldier.remove_meta(META_ROOF_BOARDER)
