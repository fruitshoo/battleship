extends RefCounted
class_name UpgradeManagerDataHelper

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
	var heal_bonus: float = 0.0
	var stamina_recovery_bonus: float = 0.0
	for current_level in range(1, target_level + 1):
		if level_matches(current_level, stats.get("radius_levels", [])):
			radius_bonus += float(stats.get("radius_add", 5.0))
		if level_matches(current_level, stats.get("heal_levels", [])):
			heal_bonus += float(stats.get("heal_add", 10.0))
		if level_matches(current_level, stats.get("stamina_recovery_levels", [])):
			stamina_recovery_bonus += float(stats.get("stamina_recovery_add", 20.0))
	return {
		"radius_bonus": radius_bonus,
		"heal_bonus": heal_bonus,
		"stamina_recovery_bonus": stamina_recovery_bonus,
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
	var spearman_count: int = mini(get_specialist_unit_count(upgrades, current_levels, "crew_numbers"), remaining)
	roster[CREW_ROLE_SPEARMAN] = spearman_count
	remaining -= spearman_count
	var repeater_count: int = mini(get_specialist_unit_count(upgrades, current_levels, "repeating_crossbow"), remaining)
	roster[CREW_ROLE_REPEATING_CROSSBOW] = repeater_count
	remaining -= repeater_count
	var singigeon_count: int = mini(get_specialist_unit_count(upgrades, current_levels, "singigeon"), remaining)
	roster[CREW_ROLE_SINGIGEON] = singigeon_count
	remaining -= singigeon_count
	var fire_pot_count: int = mini(get_specialist_unit_count(upgrades, current_levels, "fire_pot"), remaining)
	roster[CREW_ROLE_FIRE_POT] = fire_pot_count
	remaining -= fire_pot_count
	roster[CREW_ROLE_GENERAL] = remaining
	return roster

static func get_next_description(upgrades: Dictionary, current_levels: Dictionary, upgrade_id: String) -> String:
	var data: Dictionary = upgrades[upgrade_id]
	var current_lv: int = int(current_levels.get(upgrade_id, 0))
	var next_level: int = current_lv + 1

	if "level_desc" in data and next_level in data["level_desc"]:
		return data["level_desc"][next_level]

	var s: Dictionary = data.get("stats", {})
	match upgrade_id:
		"cannon":
			var player_count := int(s.get("player_base_cannon_count", 3))
			for entry in s.get("player_extra_cannon_levels", [2, 3, 4, 5]):
				if next_level >= int(entry):
					player_count += 1
			var support_count := int(s.get("support_base_cannon_count", 1))
			for entry in s.get("player_extra_cannon_levels", [2, 3, 4, 5]):
				if next_level >= int(entry):
					support_count += 1
			support_count = mini(support_count, int(s.get("support_max_cannon_count", 3)))
			return "포문 %d문 | 지원함 %d문" % [player_count, support_count]
		"cannon_damage":
			return "대포 데미지 +%d%%" % int(s.get("dmg_pct_per_lv", 8))
		"cannon_reload":
			return "대포 재장전 -%d%%" % int(s.get("cd_pct_per_lv", 4))
		"janggun":
			return "대장군전 파괴력 및 디버프 효과(화염/둔화) 대폭 강화"
		"singigeon":
			var rocketeers: int = get_specialist_unit_count(upgrades, current_levels, "singigeon", next_level)
			var rocket_base_damage: float = float(s.get("base_damage", 2.5))
			var rocket_damage: float = rocket_base_damage * (1.0 + 0.15 * float(next_level))
			var cooldown: float = maxf(2.2, float(s.get("base_cooldown", 5.0)) - (float(next_level - 1) * float(s.get("cooldown_reduce_per_lv", 0.35))))
			return "신기전 %d명 | 로켓 %.1f | 재사용 %.1f초" % [rocketeers, rocket_damage, cooldown]
		"crew_numbers":
			var spearmen: int = get_specialist_unit_count(upgrades, current_levels, "crew_numbers", next_level)
			return "창병 %d명 편성" % spearmen
		"crew_reserve":
			var recovery_delay: float = maxf(
				float(s.get("min_incapacitated_recovery_delay", 7.0)),
				16.0 - (float(next_level) * float(s.get("incapacitated_recovery_reduce_per_lv", 1.8)))
			)
			var recovery_health_ratio: float = clampf(
				0.35 + (float(next_level) * float(s.get("incapacitated_recovery_health_add_per_lv", 0.08))),
				0.35,
				float(s.get("max_incapacitated_recovery_health_ratio", 0.75))
			)
			return "전투불능 회복 %.1f초 | 회복 체력 %.0f%%" % [recovery_delay, recovery_health_ratio * 100.0]
		"boarding_resist":
			var capture_delay_pct: int = int(round(float(next_level) * float(s.get("capture_duration_mult_per_lv", 0.08)) * 100.0))
			var boarding_fire_reduce_pct: int = int(round(float(next_level) * float(s.get("boarding_fire_reduce_per_lv", 0.08)) * 100.0))
			return "적 장악 %d%% 지연 | 갑판 혼란 피해 -%d%%" % [capture_delay_pct, boarding_fire_reduce_pct]
		"crew_attack":
			return "무기 피해 +%.0f%%" % [next_level * float(s.get("damage_bonus_pct_per_lv", 0.06)) * 100.0]
		"crew_defense":
			var defense_bonus: float = next_level * float(s.get("defense_add_per_lv", 1.0))
			var damage_reduction: float = clampf(
				float(next_level) * float(s.get("damage_reduction_per_lv", 0.04)),
				0.0,
				float(s.get("max_damage_reduction", 0.22))
			)
			return "병사 방어력 +%.0f | 받는 피해 -%.0f%%" % [defense_bonus, damage_reduction * 100.0]
		"hull_defense":
			if level_matches(next_level, s.get("repair_levels", [])):
				if level_matches(next_level, s.get("regen_levels", [])):
					return "즉시 수리 +%d 및 선체 재생 +%.1f/s" % [
						int(s.get("repair_add", 35.0)),
						float(s.get("regen_add", 1.5)),
					]
				return "즉시 수리 +%d" % int(s.get("repair_add", 35.0))
			if level_matches(next_level, s.get("def_levels", [])):
				return "선체 방어력 +%d" % int(s.get("def_add", 2.0))
			if level_matches(next_level, s.get("crew_ranged_block_levels", [])):
				return "병사 원거리 피해 -%d%%" % int(round(float(s.get("crew_ranged_block_add", 0.10)) * 100.0))
			if level_matches(next_level, s.get("regen_levels", [])):
				return "선체 재생 +%.1f/s" % float(s.get("regen_add", 1.5))
			return "선체 보강"
		"sailing":
			var sailing_parts: Array[String] = []
			if level_matches(next_level, s.get("speed_levels", [])):
				sailing_parts.append("돛 최고 속도 +%d%%" % int(round((float(s.get("speed_mult", 1.08)) - 1.0) * 100.0)))
			if level_matches(next_level, s.get("efficiency_levels", [])):
				sailing_parts.append("풍력 효율 +%d%%" % int(round((float(s.get("efficiency_mult", 1.08)) - 1.0) * 100.0)))
			if level_matches(next_level, s.get("turn_levels", [])):
				sailing_parts.append("돛 회전 속도 +%d%%" % int(round((float(s.get("turn_mult", 1.15)) - 1.0) * 100.0)))
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
				return "최대 스태미나 +%d" % int(s.get("stamina_add", 20.0))
			if level_matches(next_level, s.get("drain_levels", [])):
				return "스태미나 소모 -%d%%" % int(round((1.0 - float(s.get("drain_mult", 0.85))) * 100.0))
			if level_matches(next_level, s.get("recovery_levels", [])):
				return "스태미나 회복 +%d%%" % int(round((float(s.get("recovery_mult", 1.2)) - 1.0) * 100.0))
			return "노 운용 성능 향상"
		"fire_pot":
			var throwers: int = get_specialist_unit_count(upgrades, current_levels, "fire_pot", next_level)
			var dmg: float = s.get("base_damage", 15.0) + (next_level - 1) * s.get("damage_per_lv", 5.0)
			var cd: float = s.get("base_cooldown", 6.0) - (next_level - 1) * s.get("cooldown_reduce_per_lv", 1.0)
			if next_level == 4:
				cd = 3.5
			if next_level >= 5:
				cd = 3.0
			return "화통 %d명 | 화염 %.0f | 재사용 %.1f초" % [throwers, dmg, cd]
		"repeating_crossbow":
			var repeaters: int = get_specialist_unit_count(upgrades, current_levels, "repeating_crossbow", next_level)
			var burst: int = 3
			if next_level >= 3:
				burst = 4
			if next_level >= 5:
				burst = 5
			var repeater_damage: float = s.get("base_damage", 10.0) + (next_level - 1) * s.get("damage_per_lv", 2.0)
			return "연노 %d명 | %d연발 | 피해 %.0f" % [repeaters, burst, repeater_damage]
		"supply_bonus":
			if level_matches(next_level, s.get("radius_levels", [])):
				return "보급 습득 반경 +%.1fm" % float(s.get("radius_add", 5.0))
			if level_matches(next_level, s.get("heal_levels", [])):
				return "보급 회복량 +%.0f" % float(s.get("heal_add", 10.0))
			if level_matches(next_level, s.get("stamina_recovery_levels", [])):
				return "보급 스태미나 회복 +%d" % int(s.get("stamina_recovery_add", 20.0))
			return "보급 운용 성능 향상"
		"ballista":
			var ballista_damage: float = s.get("base_damage", 45.0) + (next_level - 1) * s.get("damage_per_lv", 15.0)
			var pierce: int = int(s.get("base_pierce", 3) + (next_level - 1) * s.get("pierce_per_lv", 1))
			return "관통 화살 데미지 %.0f, 최대 %d명 관통 및 넉백" % [ballista_damage, pierce]
		"fleet_signal":
			if next_level >= int(s.get("limit_add_level", 2)):
				return "판옥선 포격 편대 해금 | 지원함 한계 +%d | 즉시 추가 소집" % int(s.get("limit_add", 1))
			return "희귀 카드: 지원함을 호출합니다.\n(이미 지원함이 있으면 수리 및 재정비)"
		"fleet_crew":
			var reduce_per_level: float = float(s.get("respawn_reduce_per_lv", 4.0))
			var max_reduce_levels: int = int(s.get("respawn_reduce_max_level", 4))
			var reduce_levels: int = mini(next_level, max_reduce_levels)
			var min_respawn_interval: float = float(s.get("min_respawn_interval", 14.0))
			var respawn_interval: float = maxf(min_respawn_interval, 30.0 - (reduce_per_level * float(reduce_levels)))
			if next_level >= int(s.get("limit_add_level", 5)):
				return "지원함 재합류 %.0f초 | 지원함 한계 +%d" % [respawn_interval, int(s.get("limit_add", 1))]
			return "지원함 재합류 %.0f초" % respawn_interval
		"supply":
			return "선체 수리 (즉시 HP +%d 회복)" % int(s.get("max_hp_add", 20))
		"gold":
			return "점수 +%d" % int(s.get("score_add", 50))

	if next_level > 1 and upgrade_id not in ["supply", "gold"]:
		return data["description"] + " (Lv.%d)" % next_level

	return data["description"]
