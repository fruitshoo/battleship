extends RefCounted
class_name AIShipProfileHelper


static func apply_default_combat_profile_for_ship_type(ship) -> void:
	var type_lower: String = str(ship.ship_type).to_lower()
	if type_lower.contains("kobayabune"):
		_apply_charger_profile(ship, 3.8, 0.8, 3.0)
	elif type_lower.contains("cannon") or type_lower.contains("atakebune"):
		_apply_gunner_profile(ship, 14.0, 2.5, 8.0)
	else:
		_apply_charger_profile(ship, 4.5, 1.0, 3.5)


static func apply_combat_profile_from_stats(ship, stats: Dictionary) -> void:
	if stats.has("combat_role"):
		var role_name := ShipCombatModeHelper.normalize_role_name(str(stats["combat_role"]))
		ship.combat_role = ShipCombatModeHelper.GUNNER_ROLE_INDEX if role_name == ShipCombatModeHelper.ROLE_GUNNER else ShipCombatModeHelper.CHARGER_ROLE_INDEX
	if stats.has("allow_boarding"):
		ship.allow_boarding = stats["allow_boarding"] == true
	if stats.has("preferred_range"):
		ship.preferred_combat_range = float(stats["preferred_range"])
	if stats.has("range_tolerance"):
		ship.combat_range_tolerance = float(stats["range_tolerance"])
	if stats.has("retreat_distance"):
		ship.retreat_distance = float(stats["retreat_distance"])


static func sync_combat_profile_from_role_accessors(ship) -> void:
	ShipCombatModeHelper.sync_exported_profile_from_accessors(ship)


static func apply_formation_role_profile(ship) -> void:
	var role_name: String = str(ship.formation_role_name).strip_edges().to_lower()
	if role_name.is_empty():
		return

	match role_name:
		"vanguard":
			_apply_charger_profile(ship, 3.4, 0.7, 2.8)
			ship.sprint_multiplier = 1.65
			ship.ai_turn_authority = 0.82
			ship.separation_pad_scale = 0.92
		"flanker":
			_apply_charger_profile(ship, 4.6, 1.15, 3.1)
			ship.sprint_multiplier = 1.58
			ship.ai_turn_authority = 0.88
			ship.separation_pad_scale = 0.82
		"gunline":
			_apply_gunner_profile(ship, 16.5, 3.3, 10.0)
			ship.ai_turn_authority = 0.58
			ship.separation_pad_scale = 1.1
		"pressure_gunner":
			_apply_gunner_profile(ship, 11.5, 2.0, 6.5)
			ship.ai_turn_authority = 0.76
			ship.separation_pad_scale = 0.96


static func _apply_charger_profile(ship, preferred_range: float, range_tolerance: float, retreat_distance: float) -> void:
	ship.combat_role = ShipCombatModeHelper.CHARGER_ROLE_INDEX
	ship.allow_boarding = true
	_apply_range_profile(ship, preferred_range, range_tolerance, retreat_distance)


static func _apply_gunner_profile(ship, preferred_range: float, range_tolerance: float, retreat_distance: float) -> void:
	ship.combat_role = ShipCombatModeHelper.GUNNER_ROLE_INDEX
	ship.allow_boarding = false
	_apply_range_profile(ship, preferred_range, range_tolerance, retreat_distance)


static func _apply_range_profile(ship, preferred_range: float, range_tolerance: float, retreat_distance: float) -> void:
	ship.preferred_combat_range = preferred_range
	ship.combat_range_tolerance = range_tolerance
	ship.retreat_distance = retreat_distance
