extends Node

## 메타 업그레이드 매니저 (Meta Manager)
## 영구 스탯 업그레이드 데이터 정의 및 구매 로직

signal meta_upgraded(id: String, new_level: int)

# 영구 업그레이드 정의
var UPGRADES = {
	"hull_hp": {
		"name": "선체 강화",
		"description": "기본 체력 +20",
		"base_cost": 500,
		"cost_multiplier": 1.5,
		"max_level": 5
	},
	"hull_defense": {
		"name": "견고한 보루",
		"description": "배의 방어력 (피해 감소) +2",
		"base_cost": 800,
		"cost_multiplier": 1.8,
		"max_level": 5
	},
	"sail_speed": {
		"name": "순풍 숙련",
		"description": "기본 추진력 +10%",
		"base_cost": 600,
		"cost_multiplier": 1.6,
		"max_level": 5
	},
	"crew_power": {
		"name": "정예병 훈련",
		"description": "병사 공격력/체력 +15%",
		"base_cost": 700,
		"cost_multiplier": 1.7,
		"max_level": 5
	}
}

func get_upgrade_cost(id: String) -> int:
	var level = SaveManager.get_upgrade_level(id)
	var data = UPGRADES[id]
	return int(data["base_cost"] * pow(data["cost_multiplier"], level))

func buy_upgrade(id: String) -> bool:
	var data = UPGRADES.get(id)
	if not data: return false
	
	var level = SaveManager.get_upgrade_level(id)
	if level >= data["max_level"]:
		print("❌ 최대 레벨 도달")
		return false
		
	var cost = get_upgrade_cost(id)
	if SaveManager.spend_gold(cost):
		var new_level = level + 1
		SaveManager.set_upgrade_level(id, new_level)
		meta_upgraded.emit(id, new_level)
		print("✅ 구매 완료: %s (Lv.%d)" % [data["name"], new_level])
		return true
	
	print("❌ 골드 부족")
	return false

# --- 인게임 스탯 보너스 계산용 ---

func get_hull_hp_bonus() -> float:
	return SaveManager.get_upgrade_level("hull_hp") * 20.0

func get_hull_defense_bonus() -> float:
	return SaveManager.get_upgrade_level("hull_defense") * 2.0

func get_sail_speed_multiplier() -> float:
	return 1.0 + (SaveManager.get_upgrade_level("sail_speed") * 0.1)

func get_crew_stat_multiplier() -> float:
	return 1.0 + (SaveManager.get_upgrade_level("crew_power") * 0.15)
