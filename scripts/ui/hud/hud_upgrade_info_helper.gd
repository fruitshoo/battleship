extends RefCounted
const SupportFleetCannonRules = preload("res://scripts/entities/ships/support_fleet_cannon_helper.gd")
const PLAYER_CANNON_BASE_DAMAGE := 22.0
const PLAYER_CANNON_BASE_RANGE := 24.0
const PLAYER_CANNON_BASE_COOLDOWN := 3.2
const PLAYER_HULL_BASE_HP := 200.0
const PLAYER_BASE_MAX_SPEED := 5.2
const PLAYER_ROWING_BASE_SPEED := 2.8
const PLAYER_ROWING_BASE_ACCEL := 1.0
const PLAYER_RAMMING_BOOST_RECHARGE := 18.0
const PLAYER_MAX_ROWING_STAMINA := 100.0
const PLAYER_SAIL_EFFICIENCY := 1.0
const PLAYER_SAIL_TURN_SPEED := 60.0
const PLAYER_SAIL_FURL_RATE := 0.55
const PLAYER_STAMINA_DRAIN_RATE := 10.0
const PLAYER_STAMINA_RECOVERY_RATE := 8.5
const SOLDIER_MELEE_BASE_DAMAGE := 13.5
const SOLDIER_BOW_BASE_DAMAGE := 18.0
const SUPPORT_FLEET_BASE_RESPAWN_INTERVAL := 30.0
const SUPPORT_FLEET_BASE_LIMIT := 1
static func is_ship_upgrade(hud, upgrade_id: String) -> bool:
	return upgrade_id in hud.SHIP_UPGRADE_IDS

static func is_crew_upgrade(hud, upgrade_id: String) -> bool:
	return upgrade_id in hud.CREW_UPGRADE_IDS

static func get_upgrade_track_name(hud, upgrade_id: String) -> String:
	if is_crew_upgrade(hud, upgrade_id):
		return LocaleManager.t("upgrade.track.boarding", "병사")
	if is_ship_upgrade(hud, upgrade_id):
		return LocaleManager.t("upgrade.track.ship", "함선")
	return LocaleManager.t("upgrade.track.default", "강화")

static func build_upgrade_tooltip_text(hud, upgrade_id: String, level: int) -> String:
	var track_name = get_upgrade_track_name(hud, upgrade_id)
	var name = upgrade_id
	var desc = ""
	var stats: Dictionary = {}
	var max_level = level
	if is_instance_valid(UpgradeManager):
		var upgrades_data = UpgradeManager.get("UPGRADES")
		if upgrades_data is Dictionary:
			var data = (upgrades_data as Dictionary).get(upgrade_id, {})
			if data is Dictionary:
				name = LocaleManager.data_text(data, upgrade_id, "upgrade", "name", upgrade_id)
				desc = LocaleManager.data_text(data, upgrade_id, "upgrade", "description", "")
				stats = data.get("stats", {})
				max_level = int(data.get("max_level", level))
	var spec = build_upgrade_spec_text(upgrade_id, level, stats)
	var text = "[%s] %s  Lv.%d/%d" % [track_name, name, level, max_level]
	if not desc.is_empty():
		text += "\n" + desc
	if not spec.is_empty():
		text += "\n현재 효과: " + spec
	if level >= max_level:
		text += "\n다음 단계: 최대 레벨"
	else:
		var next_spec = build_upgrade_spec_text(upgrade_id, level + 1, stats)
		if not next_spec.is_empty():
			text += "\n다음 단계 효과: " + next_spec
		elif is_instance_valid(UpgradeManager) and UpgradeManager.has_method("get_next_description"):
			var next_desc = str(UpgradeManager.get_next_description(upgrade_id))
			if not next_desc.is_empty():
				text += "\n다음 단계: " + next_desc
	return text

static func build_upgrade_spec_text(upgrade_id: String, level: int, stats: Dictionary) -> String:
	if level <= 0:
		return ""
	var current_levels: Dictionary = UpgradeManager.get("current_levels") if is_instance_valid(UpgradeManager) and UpgradeManager.get("current_levels") is Dictionary else {}
	var upgrades_data: Dictionary = UpgradeManager.get("UPGRADES") if is_instance_valid(UpgradeManager) and UpgradeManager.get("UPGRADES") is Dictionary else {}
	var preview_levels: Dictionary = current_levels.duplicate(true)
	preview_levels[upgrade_id] = level

	match upgrade_id:
		"cannon":
			var player_count: int = SupportFleetCannonRules.get_player_cannon_count_for_level(level, stats)
			if int(preview_levels.get("geobukseon", 0)) > 0:
				player_count = mini(player_count, 4)
			var support_summary := SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(level, stats, preview_levels, upgrades_data)
			return "측면 포문 %d문 | 지원함 %s" % [player_count, support_summary]
		"front_cannon":
			var cannon_level := int(preview_levels.get("cannon", current_levels.get("cannon", 1)))
			var cannon_stats: Dictionary = upgrades_data.get("cannon", {}).get("stats", {})
			var support_summary := SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(cannon_level, cannon_stats, preview_levels, upgrades_data)
			return "전면 대포 1문 | 지원함 %s" % support_summary
		"cannon_damage":
			var dmg_mult := 1.0 + (float(stats.get("dmg_pct_per_lv", 8)) / 100.0) * float(level)
			var shot_damage := PLAYER_CANNON_BASE_DAMAGE * dmg_mult
			return "1발 데미지 %.1f | 포격 +%d%%" % [shot_damage, _percent_delta_from_ratio(dmg_mult)]
		"cannon_reload":
			var cd_mult := maxf(float(stats.get("min_cd_mult", 0.75)), 1.0 - (float(stats.get("cd_pct_per_lv", 4)) / 100.0) * float(level))
			var shot_cooldown := PLAYER_CANNON_BASE_COOLDOWN * cd_mult
			return "재장전 %.2f초 | 재장전 -%d%%" % [shot_cooldown, int(round((1.0 - cd_mult) * 100.0))]
		"singigeon":
			var proc_stats := UpgradeManagerDataHelper.get_singigeon_proc_stats(upgrades_data, current_levels, level)
			var base_damage := float(stats.get("base_damage", 2.5))
			var personnel_mult := float(stats.get("personnel_damage_mult", 5.0))
			var rocket_damage := base_damage * (1.0 + 0.15 * float(level))
			var knockback := float(stats.get("base_knockback_speed", 9.0)) + float(level - 1) * float(stats.get("knockback_speed_per_lv", 0.0))
			var overboard_level := int(stats.get("overboard_knockback_level", 4))
			var knockback_note := "낙수 가능" if level >= overboard_level else "밀침 %.0f" % knockback
			return "활 공격 %.0f%% | 대병 %.0f | %s | 함선별 %.1f초" % [float(proc_stats.get("chance", 0.0)) * 100.0, rocket_damage * personnel_mult, knockback_note, float(proc_stats.get("cooldown", 1.0))]
		"janggun":
			var janggun_cooldown := maxf(
				float(stats.get("min_cooldown", 9.0)),
				float(stats.get("base_cooldown", 12.0)) - float(level - 1) * float(stats.get("cooldown_reduce_per_lv", 0.6))
			)
			return "포문 추가 발사 | 재장전 %.1f초 | 화염/둔화" % janggun_cooldown
		"ballista":
			var dmg = stats.get("base_damage", 45.0) + (level - 1) * stats.get("damage_per_lv", 15.0)
			var pierce = int(stats.get("base_pierce", 3) + (level - 1) * stats.get("pierce_per_lv", 1))
			return "데미지 %.0f | 관통 %d명" % [dmg, pierce]
		"hull_defense":
			var hull_stats := _calculate_hull_defense_stats(level, stats)
			return "선체 방어력 +%.1f | 병사 원거리 엄폐 +%.1f" % [hull_stats["defense"], hull_stats["crew_ranged_cover_defense"]]
		"hull":
			var hp_add := float(stats.get("hp_add_per_lv", 15.0)) * float(level)
			var ram_pct := float(stats.get("ramming_damage_pct_per_lv", 0.07)) * float(level) * 100.0
			return "최대 내구 +%.0f | 충돌 피해 +%.0f%%" % [hp_add, ram_pct]
		"hull_repair":
			var repair_rate: float = minf(float(stats.get("max_regen", 1.0)), float(level) * float(stats.get("regen_per_lv", 0.2)))
			return "선체 자동 수리 %.1f/s" % repair_rate
		"sailing":
			var sailing_stats := _calculate_sailing_stats(level, stats)
			return "돛 최고속 +%.1f | 풍력 효율 +%d%% | 돛 회전 +%d%% | 전환 +%d%%" % [
				float(sailing_stats["max_speed"]) - PLAYER_BASE_MAX_SPEED,
				_percent_delta_from_ratio(float(sailing_stats["efficiency"]) / PLAYER_SAIL_EFFICIENCY),
				_percent_delta_from_ratio(float(sailing_stats["turn_speed"]) / PLAYER_SAIL_TURN_SPEED),
				_percent_delta_from_ratio(float(sailing_stats["furl_rate"]) / PLAYER_SAIL_FURL_RATE),
			]
		"rowing":
			var rowing_stats := _calculate_rowing_stats(level, stats)
			return "노 속도 +%.0f | 노 가속 +%d%% | 충각 회복 +%d%%" % [
				float(rowing_stats["rowing_speed"]) - PLAYER_ROWING_BASE_SPEED,
				_percent_delta_from_ratio(float(rowing_stats["acceleration_mult"]) / PLAYER_ROWING_BASE_ACCEL),
				_percent_delta_from_ratio(PLAYER_RAMMING_BOOST_RECHARGE / float(rowing_stats["ram_boost_recharge_duration"])),
			]
		"supply_bonus":
			var supply_stats := _calculate_supply_bonus_stats(level, stats)
			return "획득 반경 %.1fm" % supply_stats["pickup_radius"]
		"geobukseon":
			var min_hull_ratio := clampf(float(stats.get("transform_hull_min_ratio", 0.5)), 0.0, 1.0)
			return "기함 거북선화 | 선체 최소 %.0f%% 회복 | 도선 면역 | 정면 포문 2문 | 측면 포문 4문 | %s" % [min_hull_ratio * 100.0, _format_ramming_stat_text(stats, 1.2, 1.0)]
		"fleet_signal":
			var signal_fleet_limit := SupportFleetCannonRules.get_support_fleet_limit_for_current_levels(preview_levels, upgrades_data)
			var slot_summary := SupportFleetCannonRules.get_support_slot_summary_for_current_levels(preview_levels, upgrades_data)
			return "맹선 소집 | 한계 %d척 | 편성 %s" % [signal_fleet_limit, slot_summary]
		"panokseon_upgrade":
			var slot_summary := SupportFleetCannonRules.get_support_slot_summary_for_current_levels(preview_levels, upgrades_data)
			return "판옥선 포격함 1척 합류 | 편성 %s" % slot_summary
		"geobukseon_upgrade":
			var slot_summary := SupportFleetCannonRules.get_support_slot_summary_for_current_levels(preview_levels, upgrades_data)
			return "거북선 방호함 1척 합류 | 도선 면역 | %s | 편성 %s" % [_format_ramming_stat_text(stats, 1.12, 0.72), slot_summary]
		"crew_reserve":
			var assist_duration := maxf(float(stats.get("min_assist_channel_duration", 0.55)), float(stats.get("base_assist_channel_duration", 1.1)) - (float(level) * float(stats.get("assist_channel_reduce_per_lv", 0.1))))
			var assist_health_ratio := clampf(0.35 + (float(level) * float(stats.get("assist_recovery_health_add_per_lv", 0.07))), 0.35, float(stats.get("max_assist_recovery_health_ratio", 0.7)))
			var assist_range := 4.6 + (float(level) * float(stats.get("assist_acquire_range_add_per_lv", 0.45)))
			var reserve_respawn_interval := maxf(float(stats.get("min_respawn_interval", 10.5)), 12.0 - (float(level) * float(stats.get("respawn_reduce_per_lv", 0.25))))
			return "일으키기 %.2f초 | 복귀 체력 %.0f%% | 구호 반경 %.1fm | 보충 %.1f초" % [assist_duration, assist_health_ratio * 100.0, assist_range, reserve_respawn_interval]
		"boarding_resist":
			var slot_penalty := 0
			for threshold in stats.get("enemy_boarding_slot_reduce_levels", [3, 5]):
				if level >= int(threshold):
					slot_penalty += 1
			var slot_note := " | 동시 도선 한계 -%d" % slot_penalty if slot_penalty > 0 else ""
			var boarding_damage := minf(float(stats.get("enemy_boarding_max_damage", 40.0)), float(level) * float(stats.get("enemy_boarding_damage_per_lv", 8.0)))
			return "도선 피해 %.0f%s" % [boarding_damage, slot_note]
		"crew_numbers":
			var spear_damage_add := float(stats.get("damage_add_per_lv", 1.0)) * level
			return "장창 피해 +%.0f" % spear_damage_add
		"crew_attack":
			var damage_bonus_pct := float(stats.get("damage_bonus_pct_per_lv", 0.06)) * level
			var melee_damage := SOLDIER_MELEE_BASE_DAMAGE * (1.0 + damage_bonus_pct)
			var bow_damage := SOLDIER_BOW_BASE_DAMAGE * (1.0 + damage_bonus_pct)
			return "무기 피해 +%.0f%% | 근접 %.1f | 활 %.1f" % [damage_bonus_pct * 100.0, melee_damage, bow_damage]
		"crew_defense":
			var defense_bonus := float(stats.get("defense_add_per_lv", 1.0)) * level
			return "병사 방어력 +%.0f" % defense_bonus
		"fire_pot":
			var throwers = int(UpgradeManager.get_specialist_unit_count("fire_pot", level)) if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("get_specialist_unit_count") else 0
			var fp_dmg = stats.get("base_damage", 15.0) + (level - 1) * stats.get("damage_per_lv", 5.0)
			var fp_cd = maxf(1.0, stats.get("base_cooldown", 6.0) - (level - 1) * stats.get("cooldown_reduce_per_lv", 1.0))
			if level == 4:
				fp_cd = 3.5
			if level >= 5:
				fp_cd = 3.0
			var ignite_pct: int = int(round(clampf(float(stats.get("base_ignition_chance", 0.25)) + float(level - 1) * float(stats.get("ignition_chance_per_lv", 0.075)), 0.0, float(stats.get("max_ignition_chance", 0.65))) * 100.0))
			return "전투 화통 %d명 | 폭발 %.0f | 착화 %d%% | 재사용 %.1f초" % [throwers, fp_dmg, ignite_pct, fp_cd]
		"repeating_crossbow":
			var repeaters = int(UpgradeManager.get_specialist_unit_count("repeating_crossbow", level)) if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("get_specialist_unit_count") else 0
			var burst = 3
			if level >= 3:
				burst = 4
			var rc_dmg = stats.get("base_damage", 7.0) + (level - 1) * stats.get("damage_per_lv", 1.0)
			return "연노 운용 %d명 | 연사 %d발 | 1발 %.0f" % [repeaters, burst, rc_dmg]
		"supply":
			return "선체 회복 +%d" % int(stats.get("hull_heal", 20.0))
		"gold":
			return "포인트 +%d" % int(stats.get("score_add", 50))
	return ""

static func _format_ramming_stat_text(stats: Dictionary, fallback_damage_mult: float, fallback_knockback_mult: float) -> String:
	var damage_mult := float(stats.get("ramming_damage_multiplier", fallback_damage_mult))
	var knockback_mult := float(stats.get("ramming_knockback_multiplier", fallback_knockback_mult))
	var damage_pct := int(round((damage_mult - 1.0) * 100.0))
	var knockback_pct := int(round(knockback_mult * 100.0))
	return "충각 피해 +%d%% | 밀어냄 강도 %d%%" % [damage_pct, knockback_pct]

static func get_upgrade_icon(upgrade_id: String) -> String:
	var icon_map = {
		"cannon": "sports_baseball",
		"cannon_damage": "local_fire_department",
		"cannon_reload": "timer",
		"singigeon": "rocket_launch",
		"janggun": "hardware",
		"ballista": "arrow_selector_tool",
		"hull_defense": "shield",
		"hull": "directions_boat",
		"hull_repair": "healing",
		"sailing": "air",
		"rowing": "rowing",
		"supply_bonus": "medical_services",
		"geobukseon": "shield",
		"fleet_signal": "groups",
		"panokseon_upgrade": "fort",
		"geobukseon_upgrade": "shield",
		"crew_numbers": "swords",
		"crew_attack": "swords",
		"crew_defense": "shield",
		"fire_pot": "local_fire_department",
		"repeating_crossbow": "bolt",
		"supply": "healing",
		"gold": "paid",
	}
	return icon_map.get(upgrade_id, "build")

static func get_upgrade_icon_texture_path(upgrade_id: String) -> String:
	if is_instance_valid(UpgradeManager):
		var upgrades_data = UpgradeManager.get("UPGRADES")
		if upgrades_data is Dictionary:
			var upgrade_data = (upgrades_data as Dictionary).get(upgrade_id, {})
			if upgrade_data is Dictionary:
				var card_art_path := str((upgrade_data as Dictionary).get("card_art_path", "")).strip_edges()
				if not card_art_path.is_empty() and ResourceLoader.exists(card_art_path):
					return card_art_path
	for path in [
		"res://assets/ui/upgrades/%s_icon.png" % upgrade_id,
		"res://assets/ui/upgrades/%s.png" % upgrade_id,
		"res://assets/ui/upgrades/%s_card.png" % upgrade_id,
	]:
		if ResourceLoader.exists(path):
			return path
	return ""

static func get_upgrade_color(upgrade_id: String) -> Color:
	var color_map = {
		"cannon": Color(1.0, 0.7, 0.3),
		"cannon_damage": Color(1.0, 0.55, 0.25),
		"cannon_reload": Color(1.0, 0.82, 0.35),
		"singigeon": Color(1.0, 0.4, 0.4),
		"janggun": Color(0.8, 0.5, 0.2),
		"ballista": Color(0.9, 0.6, 0.25),
		"hull_defense": Color(0.75, 0.45, 0.2),
		"hull": Color(0.72, 0.48, 0.28),
		"hull_repair": Color(0.35, 0.85, 0.55),
		"sailing": Color(0.35, 0.84, 1.0),
		"rowing": Color(1.0, 0.78, 0.32),
		"supply_bonus": Color(0.35, 0.95, 0.35),
		"geobukseon": Color(0.62, 0.78, 0.58),
		"fleet_signal": Color(1.0, 0.75, 0.35),
		"panokseon_upgrade": Color(0.84, 0.7, 0.35),
		"geobukseon_upgrade": Color(0.62, 0.78, 0.58),
		"crew_numbers": Color(0.5, 0.82, 1.0),
		"crew_attack": Color(1.0, 0.9, 0.35),
		"crew_defense": Color(0.55, 0.8, 1.0),
		"fire_pot": Color(0.93, 0.42, 0.2),
		"repeating_crossbow": Color(0.65, 0.95, 0.35),
		"supply": Color(0.55, 0.95, 0.6),
		"gold": Color(1.0, 0.86, 0.3),
	}
	return color_map.get(upgrade_id, Color.WHITE)

static func _percent_delta_from_ratio(ratio: float) -> int:
	return int(round((ratio - 1.0) * 100.0))

static func _level_matches(level: int, level_list: Variant) -> bool:
	if level_list is Array:
		for entry in level_list:
			if int(entry) == level:
				return true
	return false

static func _calculate_sailing_stats(level: int, stats: Dictionary) -> Dictionary:
	var max_speed := PLAYER_BASE_MAX_SPEED
	var efficiency := PLAYER_SAIL_EFFICIENCY
	var turn_speed := PLAYER_SAIL_TURN_SPEED
	var furl_rate := PLAYER_SAIL_FURL_RATE
	for current_level in range(1, level + 1):
		if _level_matches(current_level, stats.get("speed_levels", [])):
			max_speed += float(stats.get("speed_add", 1.0))
		if _level_matches(current_level, stats.get("efficiency_levels", [])):
			efficiency *= float(stats.get("efficiency_mult", 1.08))
		if _level_matches(current_level, stats.get("turn_levels", [])):
			turn_speed *= float(stats.get("turn_mult", 1.15))
		if _level_matches(current_level, stats.get("handling_levels", [])):
			furl_rate *= float(stats.get("handling_mult", 1.15))
	return {
		"max_speed": max_speed,
		"efficiency": efficiency,
		"turn_speed": turn_speed,
		"furl_rate": furl_rate,
	}

static func _calculate_rowing_stats(level: int, stats: Dictionary) -> Dictionary:
	var rowing_speed := PLAYER_ROWING_BASE_SPEED
	var acceleration_mult := PLAYER_ROWING_BASE_ACCEL
	var ram_boost_recharge_duration := PLAYER_RAMMING_BOOST_RECHARGE
	var max_stamina := PLAYER_MAX_ROWING_STAMINA
	var drain_rate := PLAYER_STAMINA_DRAIN_RATE
	var recovery_rate := PLAYER_STAMINA_RECOVERY_RATE
	for current_level in range(1, level + 1):
		if _level_matches(current_level, stats.get("speed_levels", [])):
			rowing_speed += float(stats.get("speed_add", 1.0))
		if _level_matches(current_level, stats.get("accel_levels", [])):
			acceleration_mult *= float(stats.get("accel_mult", 1.2))
		if _level_matches(current_level, stats.get("ram_boost_recharge_levels", [])):
			ram_boost_recharge_duration = maxf(
				float(stats.get("ram_boost_min_recharge_duration", 10.5)),
				ram_boost_recharge_duration * float(stats.get("ram_boost_recharge_mult", 0.92))
			)
		if _level_matches(current_level, stats.get("stamina_add_levels", [])):
			max_stamina += float(stats.get("stamina_add", 20.0))
		if _level_matches(current_level, stats.get("drain_levels", [])):
			drain_rate *= float(stats.get("drain_mult", 0.85))
		if _level_matches(current_level, stats.get("recovery_levels", [])):
			recovery_rate *= float(stats.get("recovery_mult", 1.2))
	return {
		"rowing_speed": rowing_speed,
		"acceleration_mult": acceleration_mult,
		"ram_boost_recharge_duration": ram_boost_recharge_duration,
		"max_stamina": max_stamina,
		"drain_rate": drain_rate,
		"recovery_rate": recovery_rate,
	}

static func _calculate_hull_defense_stats(level: int, stats: Dictionary) -> Dictionary:
	var defense := 0.0
	for current_level in range(1, level + 1):
		if _level_matches(current_level, stats.get("def_levels", [])):
			defense += float(stats.get("def_add", 2.0))
	var crew_ranged_cover_defense := float(level) * float(stats.get("crew_ranged_cover_defense_add_per_lv", 0.0))
	return {
		"defense": defense,
		"crew_ranged_cover_defense": crew_ranged_cover_defense,
	}

static func _calculate_supply_bonus_stats(level: int, stats: Dictionary) -> Dictionary:
	var pickup_radius: float = float(stats.get("base_radius", 8.0))
	for current_level in range(1, level + 1):
		if _level_matches(current_level, stats.get("radius_levels", [])):
			pickup_radius += float(stats.get("radius_add", 5.0))
	return {
		"pickup_radius": pickup_radius,
	}
