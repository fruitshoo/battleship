extends RefCounted
class_name UpgradeManagerDataHelper

const SupportFleetCannonRules = preload("res://scripts/entities/ships/support_fleet_cannon_helper.gd")
const CREW_ROLE_GENERAL := "general"
const CREW_ROLE_SPEARMAN := "spearman"
const CREW_ROLE_FIRE_POT := "fire_pot"
const CREW_ROLE_REPEATING_CROSSBOW := "repeating_crossbow"
const CREW_ROLE_SINGIGEON := "singigeon"

static func level_matches(level: int, level_list: Variant) -> bool:
	if level_list is Array:
		for entry in level_list:
			if int(entry) == level:
				return true
	return false

static func get_specialist_unit_count(upgrades: Dictionary, current_levels: Dictionary, upgrade_id: String, level: int = -1) -> int:
	if upgrade_id not in upgrades:
		return 0
	if level < 0:
		level = int(current_levels.get(upgrade_id, 0))
	if level <= 0:
		return 0
	var stats: Dictionary = upgrades[upgrade_id].get("stats", {})
	var thresholds: Variant = stats.get("specialist_levels", [1, 3, 5])
	var count: int = 0
	for threshold in thresholds:
		if level >= int(threshold):
			count += 1
	return count

static func get_supply_bonus_stats(upgrades: Dictionary, current_levels: Dictionary, level: int = -1) -> Dictionary:
	var target_level: int = level
	if target_level < 0:
		target_level = int(current_levels.get("supply_bonus", 0))
	var upgrade_data: Dictionary = upgrades.get("supply_bonus", {})
	var stats: Dictionary = upgrade_data.get("stats", {})
	var radius_bonus: float = 0.0
	for current_level in range(1, target_level + 1):
		if level_matches(current_level, stats.get("radius_levels", [])):
			radius_bonus += float(stats.get("radius_add", 5.0))
	return {
		"radius_bonus": radius_bonus,
	}

static func get_player_crew_roster(upgrades: Dictionary, current_levels: Dictionary, total_crew: int) -> Dictionary:
	var remaining: int = max(0, total_crew)
	var roster := {
		CREW_ROLE_GENERAL: 0,
		CREW_ROLE_SPEARMAN: 0,
		CREW_ROLE_FIRE_POT: 0,
		CREW_ROLE_REPEATING_CROSSBOW: 0,
		CREW_ROLE_SINGIGEON: 0,
	}
	var role_specs: Array[Dictionary] = [
		{"role": CREW_ROLE_SPEARMAN, "upgrade_id": "crew_numbers"},
		{"role": CREW_ROLE_FIRE_POT, "upgrade_id": "fire_pot"},
		{"role": CREW_ROLE_REPEATING_CROSSBOW, "upgrade_id": "repeating_crossbow"},
		{"role": CREW_ROLE_SINGIGEON, "upgrade_id": "singigeon"},
	]
	var desired_caps: Dictionary = {}
	var max_specialist_cap := 0
	for spec in role_specs:
		var role := str(spec["role"])
		var upgrade_id := str(spec["upgrade_id"])
		var cap := get_specialist_unit_count(upgrades, current_levels, upgrade_id)
		desired_caps[role] = cap
		max_specialist_cap = maxi(max_specialist_cap, cap)
	for slot_index in range(max_specialist_cap):
		for spec in role_specs:
			if remaining <= 0:
				break
			var role := str(spec["role"])
			if int(roster[role]) >= int(desired_caps.get(role, 0)):
				continue
			roster[role] = int(roster[role]) + 1
			remaining -= 1
		if remaining <= 0:
			break
	roster[CREW_ROLE_GENERAL] = remaining
	return roster

static func get_next_description(upgrades: Dictionary, current_levels: Dictionary, upgrade_id: String) -> String:
	var data: Dictionary = upgrades[upgrade_id]
	var current_lv: int = int(current_levels.get(upgrade_id, 0))
	var next_level: int = current_lv + 1

	if "level_desc" in data and next_level in data["level_desc"]:
		return data["level_desc"][next_level]

	var s: Dictionary = data.get("stats", {})
	var preview_levels: Dictionary = current_levels.duplicate(true)
	preview_levels[upgrade_id] = next_level
	match upgrade_id:
		"cannon":
			var player_count: int = SupportFleetCannonRules.get_player_cannon_count_for_level(next_level, s)
			var support_summary := SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(next_level, s, preview_levels, upgrades)
			return "측면 포문 %d문 | 지원함 %s" % [player_count, support_summary]
		"front_cannon":
			var cannon_level := int(preview_levels.get("cannon", current_levels.get("cannon", 1)))
			var cannon_stats: Dictionary = upgrades.get("cannon", {}).get("stats", {})
			var support_summary := SupportFleetCannonRules.get_support_cannon_summary_for_current_levels(cannon_level, cannon_stats, preview_levels, upgrades)
			return "전면 대포 1문 해금 | 지원함 %s" % support_summary
		"cannon_damage":
			return "대포 데미지 +%d%%" % int(s.get("dmg_pct_per_lv", 8))
		"cannon_reload":
			return "대포 재장전 -%d%%" % int(s.get("cd_pct_per_lv", 4))
		"janggun":
			var janggun_cooldown := maxf(
				float(s.get("min_cooldown", 9.0)),
				float(s.get("base_cooldown", 12.0)) - float(next_level - 1) * float(s.get("cooldown_reduce_per_lv", 0.6))
			)
			return "포문 장군전 재장전 %.1f초 | 화염/둔화 강화" % janggun_cooldown
		"singigeon":
			var rocketeers: int = get_specialist_unit_count(upgrades, current_levels, "singigeon", next_level)
			var rocket_base_damage: float = float(s.get("base_damage", 2.5))
			var rocket_damage: float = rocket_base_damage * (1.0 + 0.15 * float(next_level))
			var personnel_damage: float = rocket_damage * float(s.get("personnel_damage_mult", 5.0))
			var cooldown: float = maxf(2.2, float(s.get("base_cooldown", 5.0)) - (float(next_level - 1) * float(s.get("cooldown_reduce_per_lv", 0.35))))
			var knockback: float = float(s.get("base_knockback_speed", 9.0)) + float(next_level - 1) * float(s.get("knockback_speed_per_lv", 0.0))
			var overboard_level: int = int(s.get("overboard_knockback_level", 4))
			var knockback_note := "낙수 가능" if next_level >= overboard_level else "밀침 %.0f" % knockback
			return "신기전 운용 %d명 | 대병 %.0f | %s | 재사용 %.1f초" % [rocketeers, personnel_damage, knockback_note, cooldown]
		"crew_numbers":
			var spearmen: int = get_specialist_unit_count(upgrades, current_levels, "crew_numbers", next_level)
			return "창병 전환 %d명" % spearmen
		"crew_reserve":
			var assist_duration: float = maxf(float(s.get("min_assist_channel_duration", 0.55)), float(s.get("base_assist_channel_duration", 1.1)) - (float(next_level) * float(s.get("assist_channel_reduce_per_lv", 0.1))))
			var assist_health_ratio: float = clampf(0.35 + (float(next_level) * float(s.get("assist_recovery_health_add_per_lv", 0.07))), 0.35, float(s.get("max_assist_recovery_health_ratio", 0.7)))
			var assist_range: float = 4.6 + (float(next_level) * float(s.get("assist_acquire_range_add_per_lv", 0.45)))
			return "일으키기 %.2f초 | 복귀 체력 %.0f%% | 구호 반경 %.1fm" % [assist_duration, assist_health_ratio * 100.0, assist_range]
		"boarding_resist":
			var defense_damage: float = minf(float(s.get("boarding_defense_max_damage_per_tick", 7.0)), float(next_level) * float(s.get("boarding_defense_damage_per_tick_per_lv", 1.4)))
			var capture_reduce_pct: int = int(round(float(next_level) * float(s.get("capture_damage_reduction_per_lv", 0.06)) * 100.0))
			var boarding_fire_reduce_pct: int = int(round(float(next_level) * float(s.get("boarding_fire_reduce_per_lv", 0.1)) * 100.0))
			return "도선병 피해 %.1f/초 | 장악 피해 -%d%% | 화염 -%d%%" % [defense_damage, capture_reduce_pct, boarding_fire_reduce_pct]
		"crew_attack":
			return "무기 피해 +%.0f%%" % [next_level * float(s.get("damage_bonus_pct_per_lv", 0.06)) * 100.0]
		"crew_defense":
			var defense_bonus: float = next_level * float(s.get("defense_add_per_lv", 1.0))
			var damage_reduction: float = clampf(float(next_level) * float(s.get("damage_reduction_per_lv", 0.04)), 0.0, float(s.get("max_damage_reduction", 0.22)))
			return "병사 방어력 +%.0f | 받는 피해 -%.0f%%" % [defense_bonus, damage_reduction * 100.0]
		"hull_defense":
			if level_matches(next_level, s.get("def_levels", [])):
				return "선체 방어력 +%.1f" % float(s.get("def_add", 1.0))
			return "선체 보강"
		"hull_repair":
			var regen_rate: float = minf(float(s.get("max_regen", 1.0)), float(next_level) * float(s.get("regen_per_lv", 0.2)))
			return "선체 자동 수리 %.1f/s" % regen_rate
		"sailing":
			var sailing_parts: Array[String] = []
			if level_matches(next_level, s.get("speed_levels", [])):
				sailing_parts.append("돛 최고 속도 +%d%%" % int(round((float(s.get("speed_mult", 1.08)) - 1.0) * 100.0)))
			if level_matches(next_level, s.get("efficiency_levels", [])):
				sailing_parts.append("풍력 효율 +%d%%" % int(round((float(s.get("efficiency_mult", 1.08)) - 1.0) * 100.0)))
			if level_matches(next_level, s.get("turn_levels", [])):
				sailing_parts.append("돛 회전 속도 +%d%%" % int(round((float(s.get("turn_mult", 1.15)) - 1.0) * 100.0)))
			if level_matches(next_level, s.get("handling_levels", [])):
				sailing_parts.append("돛 전환 속도 +%d%%" % int(round((float(s.get("handling_mult", 1.15)) - 1.0) * 100.0)))
			if not sailing_parts.is_empty():
				return " | ".join(sailing_parts)
			return "돛 운용 성능 향상"
		"rowing":
			var rowing_parts: Array[String] = []
			if level_matches(next_level, s.get("speed_levels", [])):
				rowing_parts.append("노젓기 속도 +%d%%" % int(round((float(s.get("speed_mult", 1.15)) - 1.0) * 100.0)))
			if level_matches(next_level, s.get("accel_levels", [])):
				rowing_parts.append("노젓기 가속 +%d%%" % int(round((float(s.get("accel_mult", 1.2)) - 1.0) * 100.0)))
			if not rowing_parts.is_empty():
				return " | ".join(rowing_parts)
			if level_matches(next_level, s.get("stamina_add_levels", [])):
				return "최대 스태미나 +%d" % int(s.get("stamina_add", 25.0))
			if level_matches(next_level, s.get("drain_levels", [])):
				return "스태미나 소모 -%d%%" % int(round((1.0 - float(s.get("drain_mult", 0.8))) * 100.0))
			if level_matches(next_level, s.get("recovery_levels", [])):
				return "스태미나 회복 +%d%%" % int(round((float(s.get("recovery_mult", 1.25)) - 1.0) * 100.0))
			return "노 운용 성능 향상"
		"fire_pot":
			var throwers: int = get_specialist_unit_count(upgrades, current_levels, "fire_pot", next_level)
			var dmg: float = s.get("base_damage", 15.0) + (next_level - 1) * s.get("damage_per_lv", 5.0)
			var cd: float = s.get("base_cooldown", 6.0) - (next_level - 1) * s.get("cooldown_reduce_per_lv", 1.0)
			var ignite_pct: int = int(round(clampf(float(s.get("base_ignition_chance", 0.25)) + float(next_level - 1) * float(s.get("ignition_chance_per_lv", 0.075)), 0.0, float(s.get("max_ignition_chance", 0.65))) * 100.0))
			if next_level == 4:
				cd = 3.5
			if next_level >= 5:
				cd = 3.0
			return "전투 화통 %d명 | 화염 %.0f | 착화 %d%% | 재사용 %.1f초" % [throwers, dmg, ignite_pct, cd]
		"repeating_crossbow":
			var repeaters: int = get_specialist_unit_count(upgrades, current_levels, "repeating_crossbow", next_level)
			var burst: int = 3
			if next_level >= 3:
				burst = 4
			var repeater_damage: float = s.get("base_damage", 7.0) + (next_level - 1) * s.get("damage_per_lv", 1.0)
			return "연노 운용 %d명 | %d연발 | 피해 %.0f" % [repeaters, burst, repeater_damage]
		"supply_bonus":
			if level_matches(next_level, s.get("radius_levels", [])):
				return "획득 반경 +%.1fm" % float(s.get("radius_add", 2.0))
			return "획득 반경 강화"
		"ballista":
			var ballista_damage: float = s.get("base_damage", 45.0) + (next_level - 1) * s.get("damage_per_lv", 15.0)
			var pierce: int = int(s.get("base_pierce", 3) + (next_level - 1) * s.get("pierce_per_lv", 1))
			return "관통 화살 데미지 %.0f, 최대 %d명 관통 및 넉백" % [ballista_damage, pierce]
		"fleet_signal":
			var signal_limit := SupportFleetCannonRules.get_support_fleet_limit_for_current_levels(preview_levels, upgrades)
			var signal_summary := SupportFleetCannonRules.get_support_slot_summary_for_current_levels(preview_levels, upgrades)
			return "맹선 소집 | 한계 %d척 | 편성 %s" % [signal_limit, signal_summary]
		"panokseon_upgrade":
			var panokseon_summary := SupportFleetCannonRules.get_support_slot_summary_for_current_levels(preview_levels, upgrades)
			return "판옥선 포격함 1척 합류 | 편성 %s" % panokseon_summary
		"supply":
			return "선체 회복 +%d | 스태미나 회복 +%d" % [int(s.get("hull_heal", 20)), int(s.get("stamina_recover", 25))]
		"gold":
			return "골드 +%d" % int(s.get("score_add", 50))

	if next_level > 1 and upgrade_id not in ["supply", "gold"]:
		return LocaleManager.data_text(data, upgrade_id, "upgrade", "description", "") + " (Lv.%d)" % next_level

	return LocaleManager.data_text(data, upgrade_id, "upgrade", "description", "")
