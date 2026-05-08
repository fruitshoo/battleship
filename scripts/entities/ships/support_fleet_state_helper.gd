extends RefCounted
class_name SupportFleetStateHelper

const ShipAllyRoleHelper = preload("res://scripts/entities/ships/ship_ally_role_helper.gd")

const SUPPORT_FLEET_OWNER_ID_META := "support_fleet_owner_id"
const SUPPORT_FLEET_FORMATION_META := "support_fleet_formation"
const SUPPORT_HOLD_FORMATION_META := "support_hold_formation"

const FORMATION_COLUMN := 0
const FORMATION_WING := 1


static func initialize_flagship_state(flagship) -> void:
	if not is_instance_valid(flagship):
		return
	if not flagship.has_meta(SUPPORT_FLEET_FORMATION_META):
		flagship.set_meta(SUPPORT_FLEET_FORMATION_META, FORMATION_COLUMN)
	if not flagship.has_meta(SUPPORT_HOLD_FORMATION_META):
		flagship.set_meta(SUPPORT_HOLD_FORMATION_META, true)


static func set_flagship_formation(flagship, formation_value: int) -> int:
	if not is_instance_valid(flagship):
		return FORMATION_COLUMN
	initialize_flagship_state(flagship)
	var normalized_value := normalize_formation_value(formation_value)
	flagship.set_meta(SUPPORT_FLEET_FORMATION_META, normalized_value)
	return normalized_value


static func get_flagship_formation(flagship) -> int:
	if not is_instance_valid(flagship):
		return FORMATION_COLUMN
	initialize_flagship_state(flagship)
	return normalize_formation_value(int(flagship.get_meta(SUPPORT_FLEET_FORMATION_META, FORMATION_COLUMN)))


static func set_flagship_hold_enabled(flagship, enabled: bool) -> bool:
	if not is_instance_valid(flagship):
		return false
	initialize_flagship_state(flagship)
	flagship.set_meta(SUPPORT_HOLD_FORMATION_META, enabled)
	return enabled


static func is_flagship_hold_enabled(flagship) -> bool:
	if not is_instance_valid(flagship):
		return false
	initialize_flagship_state(flagship)
	return flagship.get_meta(SUPPORT_HOLD_FORMATION_META, true) == true


static func assign_support_ship_to_flagship(support_ship, flagship) -> void:
	if not is_instance_valid(support_ship):
		return
	if not is_instance_valid(flagship):
		if support_ship.has_meta(SUPPORT_FLEET_OWNER_ID_META):
			support_ship.remove_meta(SUPPORT_FLEET_OWNER_ID_META)
		return
	initialize_flagship_state(flagship)
	support_ship.set_meta(SUPPORT_FLEET_OWNER_ID_META, flagship.get_instance_id())


static func get_support_owner_flagship(ship) -> Node3D:
	if not is_instance_valid(ship):
		return null
	var owner_id := int(ship.get_meta(SUPPORT_FLEET_OWNER_ID_META, 0))
	if owner_id != 0:
		var owner_ship := NodeContractHelper.get_instance_node3d(owner_id)
		if is_instance_valid(owner_ship):
			initialize_flagship_state(owner_ship)
			return owner_ship
		ship.remove_meta(SUPPORT_FLEET_OWNER_ID_META)
	return null


static func is_support_owned_by_flagship(support_ship, flagship) -> bool:
	if not is_instance_valid(support_ship) or not is_instance_valid(flagship):
		return false
	var owner_ship := get_support_owner_flagship(support_ship)
	if not is_instance_valid(owner_ship) or owner_ship != flagship:
		return false
	if int(support_ship.get_meta(SUPPORT_FLEET_OWNER_ID_META, 0)) == 0:
		assign_support_ship_to_flagship(support_ship, flagship)
	return true


static func get_effective_formation(ship) -> int:
	if not is_instance_valid(ship):
		return FORMATION_COLUMN
	if ship.has_meta(SUPPORT_FLEET_FORMATION_META) and not ShipAllyRoleHelper.is_player_flagship(ship):
		return normalize_formation_value(int(ship.get_meta(SUPPORT_FLEET_FORMATION_META, FORMATION_COLUMN)))
	var owner_ship := get_support_owner_flagship(ship)
	if is_instance_valid(owner_ship):
		return get_flagship_formation(owner_ship)
	return FORMATION_COLUMN


static func is_effective_hold_enabled(ship) -> bool:
	if not is_instance_valid(ship):
		return false
	if ship.has_meta(SUPPORT_HOLD_FORMATION_META) and not ShipAllyRoleHelper.is_player_flagship(ship):
		return ship.get_meta(SUPPORT_HOLD_FORMATION_META, true) == true
	var owner_ship := get_support_owner_flagship(ship)
	if is_instance_valid(owner_ship):
		return is_flagship_hold_enabled(owner_ship)
	return false


static func normalize_formation_value(raw_value: int) -> int:
	if raw_value == FORMATION_COLUMN:
		return FORMATION_COLUMN
	return FORMATION_WING
