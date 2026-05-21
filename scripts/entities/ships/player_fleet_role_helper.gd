extends RefCounted
class_name PlayerFleetRoleHelper

# Owner for player fleet ship roles.
#
# "Ally" and "captured_minion" are legacy contract names used by older scenes,
# Limbo blackboard keys, and test harnesses. New gameplay should treat this as a
# role classifier for player flagship, support fleet, and legacy captured ships;
# do not add unrelated future ally concepts here without first migrating callers.
const FLEET_ROLE_META := "player_fleet_role"
const LEGACY_ALLY_ROLE_META := "ally_ship_role"
const ALLY_ROLE_META := LEGACY_ALLY_ROLE_META
const LEGACY_SUPPORT_META := "support_fleet_ship"
const ROLE_NONE := "none"
const ROLE_PLAYER_FLAGSHIP := "player_flagship"
const ROLE_SUPPORT_FLEET := "support_fleet"
const ROLE_CAPTURED_MINION := "captured_minion"
const ROLE_LEGACY_CAPTURED_SHIP := ROLE_CAPTURED_MINION
const ROLE_DEF_NAME := "name"
const ROLE_DEF_TEAM := "team"
const ROLE_DEF_CONSUMES_CAPTURE_SLOT := "consumes_capture_slot"
const ROLE_DEF_LEGACY_META := "legacy_meta"
const ROLE_DEF_DESCRIPTION := "description"
const ROLE_DEFINITIONS := {
	ROLE_PLAYER_FLAGSHIP: {
		ROLE_DEF_NAME: ROLE_PLAYER_FLAGSHIP,
		ROLE_DEF_TEAM: "player",
		ROLE_DEF_CONSUMES_CAPTURE_SLOT: false,
		ROLE_DEF_LEGACY_META: "",
		ROLE_DEF_DESCRIPTION: "player controlled flagship",
	},
	ROLE_SUPPORT_FLEET: {
		ROLE_DEF_NAME: ROLE_SUPPORT_FLEET,
		ROLE_DEF_TEAM: "player",
		ROLE_DEF_CONSUMES_CAPTURE_SLOT: false,
		ROLE_DEF_LEGACY_META: LEGACY_SUPPORT_META,
		ROLE_DEF_DESCRIPTION: "player support fleet ship",
	},
	ROLE_CAPTURED_MINION: {
		ROLE_DEF_NAME: ROLE_CAPTURED_MINION,
		ROLE_DEF_TEAM: "player",
		ROLE_DEF_CONSUMES_CAPTURE_SLOT: true,
		ROLE_DEF_LEGACY_META: "captured_minion",
		ROLE_DEF_DESCRIPTION: "legacy captured enemy ship",
	},
}


static func set_fleet_role(ship: Node, role_name: String) -> void:
	if not is_instance_valid(ship):
		return
	var normalized_role := normalize_role_name(role_name)
	if normalized_role.is_empty() or normalized_role == ROLE_NONE:
		clear_fleet_role(ship)
		return
	ship.set_meta(FLEET_ROLE_META, normalized_role)
	if ship.has_meta(LEGACY_ALLY_ROLE_META):
		ship.remove_meta(LEGACY_ALLY_ROLE_META)
	if normalized_role == ROLE_SUPPORT_FLEET:
		ship.set_meta(LEGACY_SUPPORT_META, true)
	elif ship.has_meta(LEGACY_SUPPORT_META):
		ship.remove_meta(LEGACY_SUPPORT_META)


static func set_ally_role(ship: Node, role_name: String) -> void:
	set_fleet_role(ship, role_name)


static func mark_player_flagship(ship: Node) -> void:
	set_fleet_role(ship, ROLE_PLAYER_FLAGSHIP)


static func mark_support_ship(ship: Node) -> void:
	set_fleet_role(ship, ROLE_SUPPORT_FLEET)


static func mark_captured_minion(ship: Node) -> void:
	mark_legacy_captured_ship(ship)


static func mark_legacy_captured_ship(ship: Node) -> void:
	set_fleet_role(ship, ROLE_CAPTURED_MINION)


static func clear_fleet_role(ship: Node) -> void:
	if not is_instance_valid(ship):
		return
	if ship.has_meta(FLEET_ROLE_META):
		ship.remove_meta(FLEET_ROLE_META)
	if ship.has_meta(LEGACY_ALLY_ROLE_META):
		ship.remove_meta(LEGACY_ALLY_ROLE_META)
	if ship.has_meta(LEGACY_SUPPORT_META):
		ship.remove_meta(LEGACY_SUPPORT_META)


static func clear_ally_role(ship: Node) -> void:
	clear_fleet_role(ship)


static func get_fleet_role(ship: Node) -> String:
	if not is_instance_valid(ship):
		return ROLE_NONE
	var meta_role := normalize_role_name(str(ship.get_meta(FLEET_ROLE_META, "")))
	if meta_role.is_empty() or meta_role == ROLE_NONE:
		meta_role = normalize_role_name(str(ship.get_meta(LEGACY_ALLY_ROLE_META, "")))
	if not meta_role.is_empty() and meta_role != ROLE_NONE:
		return meta_role
	if _has_legacy_support_flag(ship):
		return ROLE_SUPPORT_FLEET
	if _is_player_controlled_property(ship):
		return ROLE_PLAYER_FLAGSHIP
	# The group is still a shared legacy discovery bucket. Explicit support role
	# metadata wins above, so support ships do not consume capture slots.
	if ship.is_in_group("captured_minion"):
		return ROLE_CAPTURED_MINION
	return ROLE_NONE


static func get_ally_role(ship: Node) -> String:
	return get_fleet_role(ship)


static func is_player_flagship(ship: Node) -> bool:
	return get_fleet_role(ship) == ROLE_PLAYER_FLAGSHIP


static func is_support_ship(ship: Node) -> bool:
	return get_fleet_role(ship) == ROLE_SUPPORT_FLEET


static func is_panokseon_support(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	var ship_type_value: Variant = ship.get("ship_type")
	# These *_ally ship_type ids are saved/tested support profile ids. Rename only
	# with a data migration pass.
	return str(ship_type_value).strip_edges().to_lower() == "panokseon_ally"


static func is_geobukseon_support(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	var ship_type_value: Variant = ship.get("ship_type")
	return str(ship_type_value).strip_edges().to_lower() == "geobukseon_ally"


static func is_heavy_support(ship: Node) -> bool:
	return is_panokseon_support(ship) or is_geobukseon_support(ship)


static func is_captured_minion(ship: Node) -> bool:
	return is_legacy_captured_ship(ship)


static func is_legacy_captured_ship(ship: Node) -> bool:
	return get_fleet_role(ship) == ROLE_CAPTURED_MINION


static func is_player_fleet_ship(ship: Node) -> bool:
	return _get_team_tag(ship) == "player"


static func is_player_owned_ship(ship: Node) -> bool:
	return is_player_fleet_ship(ship)


static func ship_consumes_capture_slot(ship: Node) -> bool:
	return role_consumes_capture_slot(get_fleet_role(ship))


static func role_consumes_capture_slot(role_name: String) -> bool:
	return bool(get_role_definition(role_name).get(ROLE_DEF_CONSUMES_CAPTURE_SLOT, false))


static func get_role_definition(role_name: String) -> Dictionary:
	var normalized_role := normalize_role_name(role_name)
	var definition: Dictionary = ROLE_DEFINITIONS.get(normalized_role, {})
	if definition.is_empty():
		return {
			ROLE_DEF_NAME: normalized_role,
			ROLE_DEF_TEAM: "",
			ROLE_DEF_CONSUMES_CAPTURE_SLOT: false,
			ROLE_DEF_LEGACY_META: "",
			ROLE_DEF_DESCRIPTION: "",
		}
	return definition.duplicate(true)


static func get_role_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for role_name in ROLE_DEFINITIONS.keys():
		var definition: Dictionary = ROLE_DEFINITIONS[role_name]
		rows.append(definition.duplicate(true))
	return rows


static func count_captured_minions(ships: Array) -> int:
	return count_legacy_captured_ships(ships)


static func count_legacy_captured_ships(ships: Array) -> int:
	return count_capture_slot_ships(ships)


static func count_capture_slot_minions(ships: Array) -> int:
	return count_capture_slot_ships(ships)


static func count_capture_slot_ships(ships: Array) -> int:
	var count := 0
	for ship in ships:
		if is_instance_valid(ship) and ship_consumes_capture_slot(ship):
			count += 1
	return count


static func normalize_role_name(role_name: String) -> String:
	var normalized := role_name.strip_edges().to_lower().replace(" ", "_")
	match normalized:
		"", "none":
			return ROLE_NONE
		"flagship", "player", "player_ship", "player_controlled", "player_flagship":
			return ROLE_PLAYER_FLAGSHIP
		"support", "support_ship", "support_fleet", "support_fleet_ship":
			return ROLE_SUPPORT_FLEET
		"captured", "minion", "captured_ship", "captured_minion":
			return ROLE_CAPTURED_MINION
	return normalized


static func _has_legacy_support_flag(ship: Node) -> bool:
	return is_instance_valid(ship) and ship.get_meta(LEGACY_SUPPORT_META, false) == true


static func _is_player_controlled_property(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	var controlled_value: Variant = ship.get("is_player_controlled")
	return controlled_value == true


static func _get_team_tag(ship: Node) -> String:
	if not is_instance_valid(ship):
		return ""
	if ship.has_method("get_team_tag"):
		return str(ship.call("get_team_tag"))
	var team_value: Variant = ship.get("team")
	return str(team_value) if team_value != null else ""
