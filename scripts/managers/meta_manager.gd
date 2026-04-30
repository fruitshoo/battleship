extends Node

## 메타 업그레이드 매니저 (Meta Manager)
## 영구 스탯 업그레이드 데이터 정의 및 구매 로직

signal meta_upgraded(id: String, new_level: int)

const HULL_HP_BONUS_PER_LEVEL := 24.0
const HULL_DEFENSE_BONUS_PER_LEVEL := 0.75
const SAIL_SPEED_BONUS_PER_LEVEL := 0.05
const XP_GAIN_BONUS_PER_LEVEL := 0.05
const COLLECTION_RADIUS_BONUS_PER_LEVEL := 0.8
const CREW_HEALTH_BONUS_PER_LEVEL := 0.06
const CREW_DAMAGE_BONUS_PER_LEVEL := 0.02
const CREW_DEFENSE_BONUS_PER_LEVEL := 0.5

# 영구 업그레이드 정의
var UPGRADES = {
	"hull_hp": {
		"name": "최대 체력",
		"description": "선체 +24",
		"category": "ship",
		"card_art_path": "res://assets/ui/upgrades/panokseon_upgrade_card.png",
		"base_cost": 260,
		"cost_multiplier": 1.45,
		"max_level": 5
	},
	"hull_defense": {
		"name": "방어력",
		"description": "방어력 +0.75",
		"category": "ship",
		"card_art_path": "res://assets/ui/upgrades/boarding_resist_card.png",
		"base_cost": 360,
		"cost_multiplier": 1.55,
		"max_level": 5
	},
	"sail_speed": {
		"name": "이동 속도",
		"description": "속도 +5%",
		"category": "ship",
		"card_art_path": "res://assets/ui/upgrades/sail_card.png",
		"base_cost": 340,
		"cost_multiplier": 1.5,
		"max_level": 5
	},
	"xp_gain": {
		"name": "경험치 증가",
		"description": "경험치 +5%",
		"category": "utility",
		"base_cost": 320,
		"cost_multiplier": 1.5,
		"max_level": 5
	},
	"pickup_range": {
		"name": "수집 반경",
		"description": "반경 +0.8m",
		"category": "utility",
		"base_cost": 240,
		"cost_multiplier": 1.45,
		"max_level": 5
	},
	"reroll_stock": {
		"name": "재굴림",
		"description": "재굴림 +1",
		"category": "utility",
		"base_cost": 700,
		"cost_multiplier": 1.75,
		"max_level": 2
	},
	"crew_capacity": {
		"name": "병사 수",
		"description": "병사 +1",
		"category": "crew",
		"base_cost": 760,
		"cost_multiplier": 1.7,
		"max_level": 2
	},
	"crew_health": {
		"name": "병사 체력",
		"description": "체력 +6%",
		"category": "crew",
		"base_cost": 360,
		"cost_multiplier": 1.5,
		"max_level": 5
	},
	"crew_attack": {
		"name": "무기",
		"description": "병사 무기 피해 +2%",
		"category": "crew",
		"base_cost": 360,
		"cost_multiplier": 1.55,
		"max_level": 5
	},
	"crew_defense": {
		"name": "병사 방어력",
		"description": "방어력 +0.5",
		"category": "crew",
		"card_art_path": "res://assets/ui/upgrades/crew_defense_card.png",
		"base_cost": 380,
		"cost_multiplier": 1.55,
		"max_level": 5
	}
}

const UPGRADE_ORDER := [
	"hull_hp",
	"hull_defense",
	"sail_speed",
	"xp_gain",
	"pickup_range",
	"reroll_stock",
	"crew_capacity",
	"crew_health",
	"crew_attack",
	"crew_defense",
]

func get_upgrade_level(id: String) -> int:
	var max_level := int(UPGRADES.get(id, {}).get("max_level", 0))
	return clampi(int(SaveManager.get_upgrade_level(id)), 0, max_level)

func get_upgrade_cost(id: String) -> int:
	var level = get_upgrade_level(id)
	var data = UPGRADES[id]
	var raw_cost := float(data["base_cost"]) * pow(float(data["cost_multiplier"]), level)
	return int(round(raw_cost / 10.0) * 10.0)

func buy_upgrade(id: String) -> bool:
	var data = UPGRADES.get(id)
	if not data: return false
	
	var level = get_upgrade_level(id)
	if level >= data["max_level"]:
		print("❌ 최대 레벨 도달")
		return false
		
	var cost = get_upgrade_cost(id)
	if SaveManager.spend_gold(cost):
		var new_level = level + 1
		SaveManager.set_upgrade_level(id, new_level)
		meta_upgraded.emit(id, new_level)
		print("✅ 구매 완료: %s (Lv.%d)" % [LocaleManager.data_text(data, id, "meta_upgrade", "name", id), new_level])
		return true
	
	print("❌ 골드 부족")
	return false

# --- 인게임 스탯 보너스 계산용 ---

func get_hull_hp_bonus() -> float:
	return get_upgrade_level("hull_hp") * HULL_HP_BONUS_PER_LEVEL

func get_hull_defense_bonus() -> float:
	return get_upgrade_level("hull_defense") * HULL_DEFENSE_BONUS_PER_LEVEL

func get_sail_speed_multiplier() -> float:
	return 1.0 + (get_upgrade_level("sail_speed") * SAIL_SPEED_BONUS_PER_LEVEL)

func get_xp_gain_multiplier() -> float:
	return 1.0 + (get_upgrade_level("xp_gain") * XP_GAIN_BONUS_PER_LEVEL)

func get_collection_radius_bonus() -> float:
	return get_upgrade_level("pickup_range") * COLLECTION_RADIUS_BONUS_PER_LEVEL

func get_reroll_bonus() -> int:
	return get_reroll_bonus_for_level(get_upgrade_level("reroll_stock"))

func get_max_crew_bonus() -> int:
	return get_crew_capacity_bonus_for_level(get_upgrade_level("crew_capacity"))

func get_crew_health_multiplier() -> float:
	return 1.0 + (get_upgrade_level("crew_health") * CREW_HEALTH_BONUS_PER_LEVEL)

func get_crew_damage_bonus_pct() -> float:
	return get_upgrade_level("crew_attack") * CREW_DAMAGE_BONUS_PER_LEVEL

func get_crew_defense_bonus() -> float:
	return get_upgrade_level("crew_defense") * CREW_DEFENSE_BONUS_PER_LEVEL

func get_reroll_bonus_for_level(level: int) -> int:
	return clampi(level, 0, 2)

func get_crew_capacity_bonus_for_level(level: int) -> int:
	return clampi(level, 0, 2)

func get_upgrade_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in UPGRADE_ORDER:
		if UPGRADES.has(id):
			ids.append(id)
	for id in UPGRADES.keys():
		if id not in ids:
			ids.append(id)
	return ids

func get_upgrade_ids_for_category(category: String) -> Array[String]:
	var ids: Array[String] = []
	for id in get_upgrade_ids():
		var data: Dictionary = UPGRADES.get(id, {})
		if str(data.get("category", "")) == category:
			ids.append(id)
	return ids
