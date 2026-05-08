extends RefCounted
class_name HudShipDebugHelper
const HudSoldierDebugHelper = preload("res://scripts/ui/hud/hud_soldier_debug_helper.gd")
static func sync_ship_debug_panel_from_player(hud) -> void:
	if not is_instance_valid(hud.debug_ship_status_value):
		return
	if not HudLookupHelper.ensure_player_ship(hud):
		hud.debug_ship_status_value.text = "함선 상태: 플레이어 배 없음"
		return
	var player_ship: Node3D = hud.player_ship
	var ship_snapshot: Dictionary = player_ship.call("get_debug_ship_state_snapshot") if player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var hull_hp_value: float = float(ship_snapshot.get("hull_hp", 0.0))
	var max_hull_hp_value: float = maxf(0.01, float(ship_snapshot.get("max_hull_hp", 1.0)))
	var stamina_value: float = float(ship_snapshot.get("rowing_stamina", 0.0))
	var max_stamina_value: float = maxf(0.01, float(ship_snapshot.get("max_rowing_stamina", 1.0)))
	var crew_count: int = int(ship_snapshot.get("current_crew_count", 0))
	var max_crew_count_value: int = int(ship_snapshot.get("max_crew_count", 0))
	var speed_value: float = float(ship_snapshot.get("current_speed", 0.0))
	var fire_state: String = "화재" if ship_snapshot.get("is_burning", false) == true else "정상"
	var rudder_ratio_value: float = float(player_ship.call("get_rudder_health_ratio")) if player_ship.has_method("get_rudder_health_ratio") else 1.0
	hud.debug_ship_status_value.text = "선체 %.0f/%.0f | 스태미나 %.0f/%.0f | 선원 %d/%d | 속도 %.1f | 조타 %.0f%% | %s" % [
		hull_hp_value,
		max_hull_hp_value,
		stamina_value,
		max_stamina_value,
		crew_count,
		max_crew_count_value,
		speed_value,
		rudder_ratio_value * 100.0,
		fire_state
	]
	if is_instance_valid(hud.debug_ship_config_value):
		var support_limit: int = int(ship_snapshot.get("support_fleet_limit", 0))
		var captain_count_value: int = int(ship_snapshot.get("captain_count", 0))
		var rowing_state: String = "ON" if ship_snapshot.get("is_rowing", false) == true else "OFF"
		var max_speed_value: float = float(ship_snapshot.get("max_speed", 0.0))
		var turn_rate_value: float = float(ship_snapshot.get("turn_rate", 0.0))
		var hull_defense_value: float = float(ship_snapshot.get("hull_defense", 0.0))
		var crew_respawn_interval_value: float = float(ship_snapshot.get("crew_respawn_interval", 0.0))
		var boarding_capture_duration_value: float = float(ship_snapshot.get("boarding_capture_duration", 0.0))
		var combat_ratio_value: float = float(ship_snapshot.get("combat_crew_ratio", 0.0))
		var handling_ratio_value: float = float(ship_snapshot.get("shiphandling_crew_ratio", 0.0))
		var gunnery_ratio_value: float = float(ship_snapshot.get("gunnery_crew_ratio", 0.0))
		var mast_fold_text := "접힘 %s %.0f%%" % [
			"ON" if ship_snapshot.get("masts_folded", false) == true else "OFF",
			float(ship_snapshot.get("mast_fold_ratio", 0.0)) * 100.0
		]
		hud.debug_ship_config_value.text = "설정: 정원 %d | 장군 %d | 지원한도 %d | 노젓기 %s | %s | 속도 %.1f | 선회 %.0f | 방어 %.0f | 보충 %.0f | 장악 %.1f | 배치 C/H/G %.0f/%.0f/%.0f" % [
			max_crew_count_value,
			captain_count_value,
			support_limit,
			rowing_state,
			mast_fold_text,
			max_speed_value,
			turn_rate_value,
			hull_defense_value,
			crew_respawn_interval_value,
			boarding_capture_duration_value,
			combat_ratio_value * 100.0,
			handling_ratio_value * 100.0,
			gunnery_ratio_value * 100.0
		]

	if is_instance_valid(hud.debug_enemy_fleet_value):
		var nearest_enemy: Node3D = hud._find_nearest_enemy_ship_for_distance_debug()
		if is_instance_valid(nearest_enemy):
			var ship_type_text: String = nearest_enemy.get_ship_type_value() if nearest_enemy.has_method("get_ship_type_value") else str(nearest_enemy.get("ship_type"))
			var fleet_class_text: String = str(nearest_enemy.get_meta("enemy_fleet_class", ""))
			var formation_type_text: String = str(nearest_enemy.get_meta("enemy_formation_type", ""))
			var formation_label_text: String = str(nearest_enemy.get_meta("enemy_formation_label", ""))
			var role_text: String = str(nearest_enemy.get_meta("enemy_formation_role", ""))
			var parts: Array[String] = []
			if not ship_type_text.is_empty():
				parts.append(ship_type_text)
			if not fleet_class_text.is_empty():
				parts.append("편대 %s" % fleet_class_text)
			if not formation_label_text.is_empty():
				parts.append("이름 %s" % formation_label_text)
			if not formation_type_text.is_empty():
				parts.append("진형 %s" % formation_type_text)
			if not role_text.is_empty():
				parts.append("역할 %s" % role_text)
			hud.debug_enemy_fleet_value.text = "근처 편대: %s" % (" | ".join(parts) if not parts.is_empty() else "정보 없음")
		else:
			hud.debug_enemy_fleet_value.text = "근처 편대: 근처 적선 없음"
	if is_instance_valid(hud.debug_ship_ai_value):
		hud.debug_ship_ai_value.text = _format_limbo_panel_text("플레이어 AI", player_ship, ship_snapshot)
	var focused_enemy_ai_ship: Node3D = null
	if is_instance_valid(hud.debug_enemy_ai_value):
		focused_enemy_ai_ship = _find_priority_enemy_ai_ship(hud)
		var focus_reason := ""
		if is_instance_valid(focused_enemy_ai_ship):
			focus_reason = "boarding run" if focused_enemy_ai_ship == NodeContractHelper.get_boarding_target_ship(player_ship) else "current target" if focused_enemy_ai_ship == NodeContractHelper.get_target_ship(player_ship) else "raid target" if "auto_raid_target" in player_ship and focused_enemy_ai_ship == player_ship.get("auto_raid_target") else "nearby contact"
			focus_reason = "%s -> %s" % [focus_reason, focused_enemy_ai_ship.name]
		var enemy_snapshot: Dictionary = focused_enemy_ai_ship.call("get_debug_ship_state_snapshot") if is_instance_valid(focused_enemy_ai_ship) and focused_enemy_ai_ship.has_method("get_debug_ship_state_snapshot") else {}
		hud.debug_enemy_ai_value.text = _format_limbo_panel_text("적선 AI", focused_enemy_ai_ship, enemy_snapshot, focus_reason)
	if is_instance_valid(hud.debug_ally_ai_value):
		var nearest_ally_ai_ship := _find_nearest_player_limbo_ship(hud)
		var ally_snapshot: Dictionary = nearest_ally_ai_ship.call("get_debug_ship_state_snapshot") if is_instance_valid(nearest_ally_ai_ship) and nearest_ally_ai_ship.has_method("get_debug_ship_state_snapshot") else {}
		var ally_limbo: Dictionary = ally_snapshot.get("limbo", {})
		var support_mode := str(ally_limbo.get("support_mode", "")).strip_edges()
		var ally_mode := str(ally_limbo.get("ally_mode", "")).strip_edges()
		var ally_focus_reason := "rescue run" if support_mode == ShipAILimboKeys.SUPPORT_MODE_RESCUE_FLAGSHIP else "screen threat" if support_mode == ShipAILimboKeys.SUPPORT_MODE_SCREEN_THREAT or ally_mode == ShipAILimboKeys.ALLY_MODE_GUARD_THREAT else "escort flagship" if support_mode == ShipAILimboKeys.SUPPORT_MODE_FOLLOW_FLAGSHIP or ally_mode == ShipAILimboKeys.ALLY_MODE_FOLLOW_FLAGSHIP else "regroup" if support_mode == ShipAILimboKeys.SUPPORT_MODE_REGROUP or ally_mode == ShipAILimboKeys.ALLY_MODE_REGROUP else ""
		var ally_focus_target_id := 0
		if is_instance_valid(nearest_ally_ai_ship):
			ally_focus_target_id = int(nearest_ally_ai_ship.get_meta(ShipAILimboKeys.META_SUPPORT_TARGET_ID, 0)) if not support_mode.is_empty() else int(nearest_ally_ai_ship.get_meta(ShipAILimboKeys.META_ALLY_TARGET_ID, 0))
		var ally_focus_target := NodeContractHelper.get_instance_node3d(ally_focus_target_id) if ally_focus_target_id > 0 else null
		if not is_instance_valid(ally_focus_target) and not ally_focus_reason.is_empty() and (ally_focus_reason == "escort flagship" or ally_focus_reason == "rescue run"):
			ally_focus_target = player_ship
		if not ally_focus_reason.is_empty() and is_instance_valid(ally_focus_target):
			ally_focus_reason = "%s -> %s" % [ally_focus_reason, ally_focus_target.name]
		hud.debug_ally_ai_value.text = _format_limbo_panel_text("아군 AI", nearest_ally_ai_ship, ally_snapshot, ally_focus_reason)
	if is_instance_valid(hud.debug_support_fleet_value):
		hud.debug_support_fleet_value.text = _format_support_fleet_panel_text(player_ship)
	if is_instance_valid(hud.debug_player_soldier_ai_value):
		var player_focus: Dictionary = HudSoldierDebugHelper.find_focus_player_soldier(player_ship, focused_enemy_ai_ship); var focused_player_soldier: Node3D = player_focus.get("soldier", null) as Node3D
		var player_soldier_snapshot: Dictionary = focused_player_soldier.call("get_debug_soldier_state_snapshot") if is_instance_valid(focused_player_soldier) and focused_player_soldier.has_method("get_debug_soldier_state_snapshot") else {}
		hud.debug_player_soldier_ai_value.text = HudSoldierDebugHelper.format_soldier_limbo_panel_text("아군 병사 AI", focused_player_soldier, player_soldier_snapshot, str(player_focus.get("reason", "")).strip_edges())
	if is_instance_valid(hud.debug_enemy_soldier_ai_value):
		var enemy_focus: Dictionary = HudSoldierDebugHelper.find_focus_enemy_soldier(player_ship, focused_enemy_ai_ship)
		var focused_enemy_soldier := enemy_focus.get("soldier", null) as Node3D
		var enemy_soldier_snapshot: Dictionary = focused_enemy_soldier.call("get_debug_soldier_state_snapshot") if is_instance_valid(focused_enemy_soldier) and focused_enemy_soldier.has_method("get_debug_soldier_state_snapshot") else {}
		hud.debug_enemy_soldier_ai_value.text = HudSoldierDebugHelper.format_soldier_limbo_panel_text("적 병사 AI", focused_enemy_soldier, enemy_soldier_snapshot, str(enemy_focus.get("reason", "")).strip_edges())
	hud._ship_debug_ui_syncing = true
	if is_instance_valid(hud.debug_ship_hull_slider):
		hud.debug_ship_hull_slider.value = clampf(hull_hp_value / max_hull_hp_value, 0.0, 1.0)
	if is_instance_valid(hud.debug_ship_hull_value):
		hud.debug_ship_hull_value.text = "%.2f" % clampf(hull_hp_value / max_hull_hp_value, 0.0, 1.0)
	if is_instance_valid(hud.debug_ship_stamina_slider):
		hud.debug_ship_stamina_slider.value = clampf(stamina_value / max_stamina_value, 0.0, 1.0)
	if is_instance_valid(hud.debug_ship_stamina_value):
		hud.debug_ship_stamina_value.text = "%.2f" % clampf(stamina_value / max_stamina_value, 0.0, 1.0)
	hud._ship_debug_ui_syncing = false
static func on_debug_ship_hull_changed(hud, value: float) -> void:
	if hud._ship_debug_ui_syncing:
		return
	if not HudLookupHelper.ensure_player_ship(hud):
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var max_hull_hp_value: float = maxf(0.01, float(ship_snapshot.get("max_hull_hp", 1.0)))
	hud.player_ship.set("hull_hp", clampf(value, 0.0, 1.0) * max_hull_hp_value)
	sync_ship_debug_panel_from_player(hud)
static func on_debug_ship_stamina_changed(hud, value: float) -> void:
	if hud._ship_debug_ui_syncing:
		return
	if not HudLookupHelper.ensure_player_ship(hud):
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var max_stamina_value: float = maxf(0.01, float(ship_snapshot.get("max_rowing_stamina", 1.0)))
	hud.player_ship.set("rowing_stamina", clampf(value, 0.0, 1.0) * max_stamina_value)
	sync_ship_debug_panel_from_player(hud)
static func refill_player_crew_for_debug(hud) -> void:
	if not _ensure_player_ship(hud):
		return
	if hud.player_ship.has_method("_sync_player_crew_roster"):
		hud.player_ship.call("_sync_player_crew_roster")
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	if hud.player_ship.get("crew_respawn_timer") != null and ship_snapshot.get("crew_respawn_interval", null) != null:
		hud.player_ship.set("crew_respawn_timer", float(ship_snapshot.get("crew_respawn_interval", 0.0)))
	if hud.player_ship.has_method("_update_crew_count"):
		hud.player_ship.call("_update_crew_count")
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("선원 보충", 0.7)
static func spawn_support_ship_for_debug(hud) -> void:
	if not _ensure_player_ship(hud):
		return
	if hud.player_ship.has_method("_spawn_or_repair_ally"):
		hud.player_ship.call("_spawn_or_repair_ally")
		hud.show_gust_warning_message("지원함 호출", 0.7)
static func stop_player_ship_for_debug(hud) -> void:
	if not _ensure_player_ship(hud):
		return
	hud.player_ship.set("current_speed", 0.0)
	if "is_rowing" in hud.player_ship:
		hud.player_ship.set("is_rowing", false)
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("함선 정지", 0.7)
static func toggle_player_ship_fire_for_debug(hud) -> void:
	if not _ensure_player_ship(hud):
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var is_burning_now: bool = ship_snapshot.get("is_burning", false) == true
	hud.player_ship.set("is_burning", not is_burning_now)
	if ship_snapshot.get("fire_build_up", null) != null and ship_snapshot.get("fire_threshold", null) != null:
		if is_burning_now:
			hud.player_ship.set("fire_build_up", 0.0)
		else:
			hud.player_ship.set("fire_build_up", float(ship_snapshot.get("fire_threshold", 0.0)))
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("화재 %s" % ("해제" if is_burning_now else "적용"), 0.7)
static func toggle_player_rowing_for_debug(hud) -> void:
	if not _ensure_player_ship(hud):
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var next_rowing: bool = ship_snapshot.get("is_rowing", false) != true
	if hud.player_ship.has_method("set_rowing"):
		hud.player_ship.call("set_rowing", next_rowing)
	else:
		hud.player_ship.set("is_rowing", next_rowing)
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("노젓기 %s" % ("ON" if next_rowing else "OFF"), 0.7)
static func auto_adjust_player_sail_for_debug(hud) -> void:
	if not _ensure_player_ship(hud):
		return
	if hud.player_ship.has_method("_auto_adjust_sail"):
		hud.player_ship.call("_auto_adjust_sail", 0.35)
	hud.show_gust_warning_message("돛 정렬", 0.7)
static func toggle_player_masts_folded_for_debug(hud) -> void:
	if not _ensure_player_ship(hud):
		return
	if not hud.player_ship.has_method("toggle_masts_folded"):
		hud.show_gust_warning_message("돛대 접힘 API 없음", 0.8)
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var pivot_count := int(ship_snapshot.get("mast_fold_pivot_count", 0))
	if pivot_count <= 0 and "mast_fold_pivots" in hud.player_ship:
		var pivots = hud.player_ship.get("mast_fold_pivots")
		if pivots is Array:
			pivot_count = pivots.size()
	if pivot_count <= 0:
		hud.show_gust_warning_message("접힘 돛대 없음", 0.8)
		return
	hud.player_ship.call("toggle_masts_folded")
	var folded: bool = hud.player_ship.has_method("are_masts_folded") and bool(hud.player_ship.call("are_masts_folded"))
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("돛대 %s" % ("접힘" if folded else "펼침"), 0.8)
static func adjust_player_crew_capacity_for_debug(hud, delta_amount: int) -> void:
	if not _ensure_player_ship(hud):
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var current_value: int = int(ship_snapshot.get("max_crew_count", 0))
	var next_value: int = clampi(current_value + delta_amount, 1, 12)
	hud.player_ship.set("max_crew_count", next_value)
	var captain_value: int = int(ship_snapshot.get("captain_count", 0))
	if captain_value > next_value:
		hud.player_ship.set("captain_count", next_value)
	if hud.player_ship.has_method("_sync_player_crew_roster"):
		hud.player_ship.call("_sync_player_crew_roster")
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("정원 %d" % next_value, 0.7)
static func adjust_player_captain_count_for_debug(hud, delta_amount: int) -> void:
	if not _ensure_player_ship(hud):
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var max_crew_count_value: int = int(ship_snapshot.get("max_crew_count", 0))
	var current_value: int = int(ship_snapshot.get("captain_count", 0))
	var next_value: int = clampi(current_value + delta_amount, 0, max_crew_count_value)
	hud.player_ship.set("captain_count", next_value)
	if hud.player_ship.has_method("_sync_player_crew_roster"):
		hud.player_ship.call("_sync_player_crew_roster")
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("장군 %d" % next_value, 0.7)
static func adjust_player_support_limit_for_debug(hud, delta_amount: int) -> void:
	if not _ensure_player_ship(hud):
		return
	var ship_snapshot: Dictionary = hud.player_ship.call("get_debug_ship_state_snapshot") if hud.player_ship.has_method("get_debug_ship_state_snapshot") else {}
	var current_value: int = int(ship_snapshot.get("support_fleet_limit", 0))
	var next_value: int = clampi(current_value + delta_amount, 0, 4)
	hud.player_ship.set("support_fleet_limit", next_value)
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("지원한도 %d" % next_value, 0.7)
static func adjust_player_ship_float_for_debug(hud, property_name: String, delta_value: float, min_value: float, max_value: float, label: String) -> void:
	if not _ensure_player_ship(hud):
		return
	if hud.player_ship.get(property_name) == null:
		hud.show_gust_warning_message("속성 없음: %s" % property_name, 0.8)
		return
	var current_value: float = float(hud.player_ship.get(property_name))
	var next_value: float = clampf(current_value + delta_value, min_value, max_value)
	hud.player_ship.set(property_name, next_value)
	sync_ship_debug_panel_from_player(hud)
	hud.show_gust_warning_message("%s %.1f" % [label, next_value], 0.7)

static func _ensure_player_ship(hud) -> bool:
	if not HudLookupHelper.ensure_player_ship(hud):
		hud.show_gust_warning_message("플레이어 배 없음", 0.8)
		return false
	return true
static func _find_priority_enemy_ai_ship(hud) -> Node3D:
	if not is_instance_valid(hud.player_ship):
		return null
	var player_ship: Node3D = hud.player_ship
	var candidate_sources: Array = [
		NodeContractHelper.get_boarding_target_ship(player_ship),
		NodeContractHelper.get_target_ship(player_ship),
		player_ship.get("auto_raid_target") as Node3D if "auto_raid_target" in player_ship else null,
	]
	for candidate in candidate_sources:
		if _is_valid_enemy_ai_focus_ship(hud, candidate):
			return candidate
	return hud._find_nearest_enemy_ship_for_distance_debug()
static func _is_valid_enemy_ai_focus_ship(hud, candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or not is_instance_valid(hud.player_ship):
		return false
	if candidate == hud.player_ship:
		return false
	if NodeContractHelper.is_sinking_or_dying(candidate):
		return false
	return NodeContractHelper.get_team_tag(candidate) != NodeContractHelper.get_team_tag(hud.player_ship)
static func _format_limbo_panel_text(label: String, ship: Node3D, ship_snapshot: Dictionary, focus_reason: String = "") -> String:
	if not is_instance_valid(ship):
		return "%s: 없음" % label
	var ship_name: String = ship.name
	if ship.has_method("get_ship_type_value"):
		var ship_type_name := str(ship.call("get_ship_type_value")).strip_edges()
		if not ship_type_name.is_empty():
			ship_name = "%s (%s)" % [ship.name, ship_type_name]
	var limbo: Dictionary = ship_snapshot.get("limbo", {})
	if limbo.is_empty() or limbo.get("enabled", false) != true:
		var manual_suffix := " | focus %s" % focus_reason if not focus_reason.is_empty() else ""
		return "%s: %s | 수동/비활성%s" % [label, ship_name, manual_suffix]
	var tree_path := str(limbo.get("tree_path", "")).strip_edges()
	var tree_name := tree_path.get_file().get_basename() if not tree_path.is_empty() else "-"
	var primary_mode: String = str(limbo.get("support_mode", "")).strip_edges()
	if primary_mode.is_empty():
		primary_mode = str(limbo.get("ally_mode", "")).strip_edges()
	if primary_mode.is_empty():
		primary_mode = str(limbo.get("stance", "")).strip_edges()
	var action_intent: String = str(limbo.get("weapon_intent", "")).strip_edges()
	if action_intent.is_empty():
		action_intent = str(limbo.get("special_intent", "")).strip_edges()
	if action_intent.is_empty():
		action_intent = str(limbo.get("boarding_intent", "")).strip_edges()
	var details: Array[String] = []
	if not primary_mode.is_empty():
		details.append("mode %s" % primary_mode)
	if not focus_reason.is_empty():
		details.append("focus %s" % focus_reason)
	var range_intent := str(limbo.get("range_intent", "")).strip_edges()
	if not range_intent.is_empty():
		details.append("range %s" % range_intent)
	if not action_intent.is_empty():
		details.append("act %s" % action_intent)
	var nav_mode := str(limbo.get("nav_mode", "")).strip_edges()
	if not nav_mode.is_empty():
		details.append("nav %s" % nav_mode)
	var pressure_phase := str(limbo.get("pressure_phase", "")).strip_edges()
	if not pressure_phase.is_empty():
		details.append("phase %s" % pressure_phase)
	var target_distance := float(limbo.get("target_distance", -1.0))
	if target_distance >= 0.0:
		details.append("%.1fm" % target_distance)
	var reason := str(limbo.get("support_reason", "")).strip_edges()
	if reason.is_empty():
		reason = str(limbo.get("ally_reason", "")).strip_edges()
	match reason:
		"formation_hold": reason = "hold line"
		"outside_recall": reason = "too far"
		"nearby_threat": reason = "near threat"
		"flagship_deck_emergency": reason = "deck emergency"
		"flagship_deck_emergency_with_threat": reason = "deck emergency + threat"
		"flagship_boarder": reason = "flagship boarder"
		"flagship_manual_boarding": reason = "manual boarding"
		"debug_rescue": reason = "rescue drill"
	if not reason.is_empty():
		details.append("why %s" % reason)
	var error_text := str(limbo.get("error", "")).strip_edges()
	if not error_text.is_empty():
		details.append("err %s" % error_text)
	return "%s: %s | tree %s\n%s" % [
		label,
		ship_name,
		tree_name,
		" | ".join(details) if not details.is_empty() else "state 없음",
	]
static func _find_nearest_player_limbo_ship(hud) -> Node3D:
	if not is_instance_valid(hud.player_ship):
		return null
	var nearest_ship: Node3D = null
	var nearest_distance_sq: float = INF
	for ship in EntityRegistry.get_ships_by_team("player"):
		var candidate := ship as Node3D
		if not is_instance_valid(candidate) or candidate == hud.player_ship:
			continue
		if NodeContractHelper.is_sinking_or_dying(candidate):
			continue
		if candidate.get("limbo_ai_pilot_enabled") != true:
			continue
		var planar_delta := Vector2(
			candidate.global_position.x - hud.player_ship.global_position.x,
			candidate.global_position.z - hud.player_ship.global_position.z
		)
		var dist_sq := planar_delta.length_squared()
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
			nearest_ship = candidate
	return nearest_ship


static func _format_support_fleet_panel_text(player_ship: Node3D) -> String:
	if not is_instance_valid(player_ship):
		return "지원함 진형: 플레이어 배 없음"
	if not player_ship.has_method("_get_support_fleet_ships"):
		return "지원함 진형: API 없음"
	var support_ships: Array = player_ship.call("_get_support_fleet_ships")
	var rows: Array[String] = []
	for support in support_ships:
		var support_ship := support as Node3D
		if not is_instance_valid(support_ship):
			continue
		rows.append(_format_support_fleet_row(player_ship, support_ship, rows.size() + 1))
	var formation_text := _get_support_formation_text(player_ship)
	var hold_text := "유지 ON" if _get_meta_bool(player_ship, "support_hold_formation", true) else "유지 OFF"
	if rows.is_empty():
		return "지원함 진형: 0척 | %s | %s" % [formation_text, hold_text]
	return "지원함 진형: %d척 | %s | %s\n%s" % [
		rows.size(),
		formation_text,
		hold_text,
		"\n".join(rows)
	]


static func _format_support_fleet_row(player_ship: Node3D, support_ship: Node3D, row_index: int) -> String:
	var ship_type_text := _get_ship_type_text(support_ship)
	var role_text := _get_ship_role_text(support_ship)
	var mode_text := str(support_ship.get_meta("support_debug_mode", "-")).strip_edges()
	if mode_text.is_empty():
		mode_text = "-"
	var join_text := _get_support_join_stage_text(support_ship)
	var lead_text := str(support_ship.get_meta("support_debug_lead_name", "-")).strip_edges()
	if lead_text.is_empty():
		lead_text = "-"
	var slot_dist := float(support_ship.get_meta("support_debug_slot_dist", -1.0))
	var rel_depth := float(support_ship.get_meta("support_debug_rel_depth", 0.0))
	var lead_speed := float(support_ship.get_meta("support_debug_lead_speed", 0.0))
	var target_speed := float(support_ship.get_meta("support_debug_target_speed", 0.0))
	var player_speed := float(support_ship.get_meta("support_debug_player_speed", 0.0))
	var player_gap := _get_planar_distance(player_ship, support_ship)
	var parts: Array[String] = [
		"#%d %s(%s)" % [row_index, support_ship.name, ship_type_text],
		"role %s" % role_text,
		"mode %s%s" % [mode_text, join_text],
		"lead %s" % lead_text,
		"slot %.1fm" % slot_dist if slot_dist >= 0.0 else "slot -",
		"depth %.1f" % rel_depth,
		"spd P%.1f/L%.1f/T%.1f" % [player_speed, lead_speed, target_speed],
		"gap %.1fm" % player_gap,
	]
	var turn_text := _get_support_turn_text(support_ship)
	if not turn_text.is_empty():
		parts.append(turn_text)
	var avoid_text := _get_support_avoid_text(support_ship)
	if not avoid_text.is_empty():
		parts.append(avoid_text)
	var assist_target := str(support_ship.get_meta("support_debug_assist_target", "")).strip_edges()
	if not assist_target.is_empty():
		parts.append("assist %s" % assist_target)
	return " | ".join(parts)


static func _get_support_formation_text(player_ship: Node3D) -> String:
	var formation_value := int(player_ship.get_meta("support_fleet_formation", 0))
	return "호위진" if formation_value != 0 else "장사진"


static func _get_support_join_stage_text(support_ship: Node3D) -> String:
	if not support_ship.has_meta("support_join_stage"):
		return ""
	var stage := int(support_ship.get_meta("support_join_stage", 1))
	return "/rear" if stage <= 0 else "/slot"


static func _get_support_turn_text(support_ship: Node3D) -> String:
	var turn_mode: bool = _get_meta_bool(support_ship, "support_debug_turn_mode", false)
	var turn_angle := float(support_ship.get_meta("support_debug_turn_angle", 0.0))
	var turn_blend := float(support_ship.get_meta("support_debug_turn_blend", 0.0))
	if not turn_mode and absf(turn_angle) < 0.1 and turn_blend <= 0.01:
		return ""
	return "turn %.0f b%.2f%s" % [turn_angle, turn_blend, " ON" if turn_mode else ""]


static func _get_support_avoid_text(support_ship: Node3D) -> String:
	var hazard: bool = _get_meta_bool(support_ship, "support_debug_pre_avoid_hazard", false)
	var lateral := float(support_ship.get_meta("support_debug_pre_avoid_lateral", 0.0))
	if not hazard and absf(lateral) < 0.01:
		return ""
	return "avoid %s %.1f" % ["H" if hazard else "-", lateral]


static func _get_ship_type_text(ship: Node3D) -> String:
	if ship.has_method("get_ship_type_value"):
		var method_type := str(ship.call("get_ship_type_value")).strip_edges()
		if not method_type.is_empty():
			return method_type
	var property_type := str(ship.get("ship_type")).strip_edges()
	return property_type if not property_type.is_empty() else "-"


static func _get_ship_role_text(ship: Node3D) -> String:
	var role_text := str(ship.get("formation_role_name")).strip_edges()
	return role_text if not role_text.is_empty() else "-"


static func _get_planar_distance(a: Node3D, b: Node3D) -> float:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return 0.0
	var delta := Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z)
	return delta.length()


static func _get_meta_bool(node: Node, key: String, fallback: bool) -> bool:
	if not is_instance_valid(node):
		return fallback
	var value: Variant = node.get_meta(key, fallback)
	match typeof(value):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value) != 0
		TYPE_FLOAT:
			return not is_zero_approx(float(value))
		TYPE_STRING:
			var text := str(value).strip_edges().to_lower()
			if text == "true" or text == "on" or text == "1":
				return true
			if text == "false" or text == "off" or text == "0":
				return false
	return fallback
