extends RefCounted
class_name HudShipDebugHelper


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
		hud.debug_ship_config_value.text = "설정: 정원 %d | 장군 %d | 지원한도 %d | 노젓기 %s | 속도 %.1f | 선회 %.0f | 방어 %.0f | 보충 %.0f | 장악 %.1f | 배치 C/H/G %.0f/%.0f/%.0f" % [
			max_crew_count_value,
			captain_count_value,
			support_limit,
			rowing_state,
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
