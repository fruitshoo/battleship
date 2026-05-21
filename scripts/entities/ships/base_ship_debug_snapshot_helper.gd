extends RefCounted
class_name BaseShipDebugSnapshotHelper

const ShipAIIntentHelper = preload("res://scripts/entities/ships/ship_ai_intent_helper.gd")


static func build_debug_ship_state_snapshot(ship) -> Dictionary:
	var rowing_stamina_value: float = 0.0
	var max_rowing_stamina_value: float = 1.0
	var current_crew_count_value: int = 0
	var support_fleet_limit_value: int = 0
	var captain_count_value: int = 0
	var is_rowing_value: bool = false
	var sail_furled_value: bool = false
	var sail_deployed_ratio_value: float = 1.0
	var mast_fold_ratio_value: float = ship.get_mast_fold_ratio()
	var crew_respawn_interval_value: float = 0.0
	var limbo_requested_tree_path: String = ""
	var limbo_enabled_value: bool = false
	var limbo_resolved_tree_path: String = ""

	if "rowing_stamina" in ship:
		var rowing_stamina_variant: Variant = ship.get("rowing_stamina")
		if rowing_stamina_variant != null:
			rowing_stamina_value = float(rowing_stamina_variant)
	if "max_rowing_stamina" in ship:
		var max_rowing_stamina_variant: Variant = ship.get("max_rowing_stamina")
		if max_rowing_stamina_variant != null:
			max_rowing_stamina_value = maxf(0.01, float(max_rowing_stamina_variant))
	if "current_crew_count" in ship:
		var current_crew_count_variant: Variant = ship.get("current_crew_count")
		if current_crew_count_variant != null:
			current_crew_count_value = max(0, int(current_crew_count_variant))
	if "support_fleet_limit" in ship:
		var support_fleet_limit_variant: Variant = ship.get("support_fleet_limit")
		if support_fleet_limit_variant != null:
			support_fleet_limit_value = max(0, int(support_fleet_limit_variant))
	if "captain_count" in ship:
		var captain_count_variant: Variant = ship.get("captain_count")
		if captain_count_variant != null:
			captain_count_value = max(0, int(captain_count_variant))
	if "is_rowing" in ship:
		is_rowing_value = ship.get("is_rowing") == true
	if "sail_furled" in ship:
		sail_furled_value = ship.get("sail_furled") == true
	if "sail_deployed_ratio" in ship:
		var sail_deployed_ratio_variant: Variant = ship.get("sail_deployed_ratio")
		if sail_deployed_ratio_variant != null:
			sail_deployed_ratio_value = clampf(float(sail_deployed_ratio_variant), 0.0, 1.0)
	if "crew_respawn_interval" in ship:
		var crew_respawn_interval_variant: Variant = ship.get("crew_respawn_interval")
		if crew_respawn_interval_variant != null:
			crew_respawn_interval_value = float(crew_respawn_interval_variant)
	if "limbo_ai_pilot_tree_path" in ship:
		var limbo_tree_path_variant: Variant = ship.get("limbo_ai_pilot_tree_path")
		if limbo_tree_path_variant != null:
			limbo_requested_tree_path = str(limbo_tree_path_variant).strip_edges()
	if "limbo_ai_pilot_enabled" in ship:
		limbo_enabled_value = ship.get("limbo_ai_pilot_enabled") == true
	if limbo_enabled_value or not limbo_requested_tree_path.is_empty():
		var limbo_resolve_seed := limbo_requested_tree_path if not limbo_requested_tree_path.is_empty() else ShipLimboAIPilot.DEFAULT_TREE_PATH
		limbo_resolved_tree_path = ShipLimboAIPilot.resolve_tree_path(ship, limbo_resolve_seed)
	var limbo_active_tree_path := str(ship.get_meta(ShipLimboAIPilot.META_TREE_PATH, limbo_resolved_tree_path)).strip_edges()
	var limbo_intent := ShipAIIntentHelper.from_limbo_meta(ship)
	var limbo_nav_data: Variant = limbo_intent.get(ShipAIIntentHelper.KEY_NAV, {})
	var limbo_weapon_data: Variant = limbo_intent.get(ShipAIIntentHelper.KEY_WEAPON, {})
	var limbo_special_data: Variant = limbo_intent.get(ShipAIIntentHelper.KEY_SPECIAL, {})
	var limbo_boarding_data: Variant = limbo_intent.get(ShipAIIntentHelper.KEY_BOARDING, {})
	var limbo_support_data: Variant = limbo_intent.get(ShipAIIntentHelper.KEY_SUPPORT, {})
	var limbo_legacy_capture_data: Variant = limbo_intent.get(ShipAIIntentHelper.KEY_LEGACY_CAPTURE, {})
	var limbo_snapshot := {
		"enabled": limbo_enabled_value,
		"requested_tree_path": limbo_requested_tree_path,
		"resolved_tree_path": limbo_resolved_tree_path,
		"tree_path": limbo_active_tree_path,
		"status": str(ship.get_meta(ShipLimboAIPilot.META_LAST_STATUS, "")),
		"error": str(ship.get_meta(ShipLimboAIPilot.META_LAST_ERROR, "")).strip_edges(),
		"range_intent": str(limbo_intent.get(ShipAIIntentHelper.KEY_RANGE_INTENT, "")),
		"target_id": int(limbo_intent.get(ShipAIIntentHelper.KEY_TARGET_ID, 0)),
		"target_distance": float(limbo_intent.get(ShipAIIntentHelper.KEY_TARGET_DISTANCE, -1.0)),
		"pressure_phase": str(limbo_intent.get(ShipAIIntentHelper.KEY_PRESSURE_PHASE, "")),
		"pressure": clampf(float(limbo_intent.get(ShipAIIntentHelper.KEY_PRESSURE, 0.0)), 0.0, 1.0),
		"stance": str(limbo_intent.get(ShipAIIntentHelper.KEY_STANCE, "")),
		"nav_mode": str(limbo_nav_data.get(ShipAIIntentHelper.KEY_MODE, "")).strip_edges() if limbo_nav_data is Dictionary else "",
		"weapon_intent": str(limbo_weapon_data.get(ShipAIIntentHelper.KEY_INTENT, "")).strip_edges() if limbo_weapon_data is Dictionary else "",
		"special_intent": str(limbo_special_data.get(ShipAIIntentHelper.KEY_INTENT, "")).strip_edges() if limbo_special_data is Dictionary else "",
		"boarding_intent": str(limbo_boarding_data.get(ShipAIIntentHelper.KEY_INTENT, "")).strip_edges() if limbo_boarding_data is Dictionary else "",
		"support_mode": str(limbo_support_data.get(ShipAIIntentHelper.KEY_MODE, "")).strip_edges() if limbo_support_data is Dictionary else "",
		"support_target_id": int(limbo_support_data.get(ShipAIIntentHelper.KEY_TARGET_ID, 0)) if limbo_support_data is Dictionary else 0,
		"support_reason": str(limbo_support_data.get(ShipAIIntentHelper.KEY_REASON, "")).strip_edges() if limbo_support_data is Dictionary else "",
		"legacy_capture_mode": str(limbo_legacy_capture_data.get(ShipAIIntentHelper.KEY_MODE, "")).strip_edges() if limbo_legacy_capture_data is Dictionary else "",
		"legacy_capture_target_id": int(limbo_legacy_capture_data.get(ShipAIIntentHelper.KEY_TARGET_ID, 0)) if limbo_legacy_capture_data is Dictionary else 0,
		"legacy_capture_reason": str(limbo_legacy_capture_data.get(ShipAIIntentHelper.KEY_REASON, "")).strip_edges() if limbo_legacy_capture_data is Dictionary else "",
	}

	return {
		"hull_hp": ship.hull_hp,
		"max_hull_hp": ship.max_hull_hp,
		"rowing_stamina": rowing_stamina_value,
		"max_rowing_stamina": max_rowing_stamina_value,
		"current_crew_count": current_crew_count_value,
		"max_crew_count": max(0, int(ship.get("max_crew_count")) if "max_crew_count" in ship and ship.get("max_crew_count") != null else 0),
		"current_speed": ship.current_speed,
		"is_burning": ship.is_burning,
		"support_fleet_limit": support_fleet_limit_value,
		"captain_count": captain_count_value,
		"is_rowing": is_rowing_value,
		"sail_furled": sail_furled_value,
		"sail_deployed_ratio": sail_deployed_ratio_value,
		"masts_folded": ship.masts_folded,
		"mast_fold_ratio": mast_fold_ratio_value,
		"mast_fold_pivot_count": ship.mast_fold_pivots.size(),
		"max_speed": ship.max_speed,
		"turn_rate": ship.turn_rate,
		"hull_defense": ship.hull_defense,
		"fire_build_up": ship.fire_build_up,
		"fire_threshold": ship.fire_threshold,
		"crew_respawn_interval": crew_respawn_interval_value,
		"boarding_capture_duration": ship.boarding_capture_duration,
		"player_fleet_role": ship.get_player_fleet_role(),
		"combat_crew_ratio": ship.combat_crew_ratio,
		"shiphandling_crew_ratio": ship.shiphandling_crew_ratio,
		"gunnery_crew_ratio": ship.gunnery_crew_ratio,
		"limbo": limbo_snapshot,
	}
