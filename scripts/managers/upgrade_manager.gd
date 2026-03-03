extends Node

## 업그레이드 매니저 (AutoLoad)
## 업그레이드 데이터 및 적용 로직 관리

signal upgrade_applied(upgrade_id: String, new_level: int)

# 업그레이드 정의
# 업그레이드 카테고리
enum Category {ANTI_SHIP, ANTI_PERSONNEL, HULL, NAVIGATION, SPECIAL, FLEET}

# 업그레이드 정의
var UPGRADES = {
	# --- Primary Weapons (8 Levels) ---
	"cannon": {
		"name": "대포",
		"category": Category.ANTI_SHIP,
		"description": "대포 1문 추가 또는 데미지/사거리 강화",
		"max_level": 8,
		"color": Color(1.0, 0.5, 0.2)
	},
	"janggun": {
		"name": "대장군전",
		"category": Category.ANTI_SHIP,
		"description": "화력 강화 및 명중 시 화염/이속저하 디버프",
		"max_level": 8,
		"color": Color(0.6, 0.4, 0.2)
	},
	"singigeon": {
		"name": "신기전",
		"category": Category.ANTI_PERSONNEL,
		"description": "발사 개수 추가 및 데미지/사거리 강화",
		"max_level": 8,
		"color": Color(1.0, 0.3, 0.3)
	},
	
	# --- Crew / Boarding (5 Levels) ---
	"crew_numbers": {
		"name": "병사 충원",
		"category": Category.ANTI_PERSONNEL,
		"description": "최대 정원 증가 및 리스폰 속도 단축",
		"max_level": 5,
		"color": Color(0.4, 0.8, 1.0)
	},
	"crew_quality": {
		"name": "정예병 훈련",
		"category": Category.ANTI_PERSONNEL,
		"description": "병사의 체력, 방어력, 공격력 일괄 상승",
		"max_level": 5,
		"color": Color(0.8, 0.8, 0.2)
	},
	
	# --- Hull / Navigation (5 Levels) ---
	"hull_defense": {
		"name": "선체 장갑",
		"category": Category.HULL,
		"description": "함선의 최대 체력 및 방어력 증가",
		"max_level": 5,
		"color": Color(0.6, 0.3, 0.1)
	},
	"navigation": {
		"name": "항해 기동",
		"category": Category.NAVIGATION,
		"description": "선회 속도 및 돛 기동력 증가",
		"max_level": 5,
		"color": Color(0.4, 1.0, 0.4)
	},
	"supply_bonus": {
		"name": "보급 효율",
		"category": Category.HULL,
		"description": "보급품 획득 시 회복량 및 습득 범위 대폭 증가",
		"max_level": 5,
		"color": Color(0.3, 0.8, 0.3)
	},
	
	# --- Special / Rare Items ---
	"sextant": {
		"name": "육분의",
		"category": Category.SPECIAL,
		"description": "[자동화] 바람 방향에 맞춰 돛 자동 최적화",
		"max_level": 1,
		"color": Color(1.0, 0.9, 0.5)
	},
	
	# --- Consumables / Instant ---
	"supply": {
		"name": "보급물자",
		"category": Category.HULL,
		"description": "체력 즉시 소폭 회복",
		"max_level": 99,
		"color": Color(0.5, 1.0, 0.5)
	},
	"gold": {
		"name": "전리품",
		"category": Category.SPECIAL,
		"description": "점수 +50",
		"max_level": 99,
		"color": Color(1.0, 0.85, 0.3)
	}
}

# 현재 업그레이드 레벨 추적
var current_levels: Dictionary = {}

# 프리로드
var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
var cannon_scene: PackedScene = preload("res://scenes/entities/cannon.tscn")
var singigeon_scene: PackedScene = preload("res://scenes/entities/singigeon_launcher.tscn")
var janggun_scene: PackedScene = preload("res://scenes/entities/janggun_launcher.tscn")


func _ready() -> void:
	for key in UPGRADES:
		current_levels[key] = 0


## 랜덤 선택지 반환
func get_random_choices(count: int = 3) -> Array:
	var available: Array = []
	
	# 무제한 업그레이드 (보급/돈) 제외하고 선택지 수집
	for id in UPGRADES:
		if id in ["supply", "gold", "maintenance"]:
			continue
		if current_levels[id] < UPGRADES[id]["max_level"]:
			available.append(id)
	
	available.shuffle()
	var choices = available.slice(0, mini(count, available.size()))
	
	# 빈 자리는 보급/돈/정비로 채움
	var fallbacks = ["supply", "gold", "maintenance"]
	while choices.size() < count:
		var fb = fallbacks[choices.size() % fallbacks.size()]
		# 이미 선택된 것이거나, (혹시나) 정비가 만렙이면서 병사가 풀이면 패스 (일단은 무조건 허용)
		if fb not in choices:
			choices.append(fb)
		else:
			# 더 이상 추가할 fallback이 없으면 중단
			if choices.size() >= fallbacks.size(): break
			# 다음 fallback 시도
			continue
	
	return choices


## 업그레이드 적용
func apply_upgrade(upgrade_id: String) -> void:
	if upgrade_id not in UPGRADES:
		return
	if current_levels[upgrade_id] >= UPGRADES[upgrade_id]["max_level"]:
		return
	
	current_levels[upgrade_id] += 1
	var new_level = current_levels[upgrade_id]
	
	var player_ship = _get_player_ship()
	if not player_ship:
		push_warning("UpgradeManager: 플레이어 배를 찾을 수 없습니다")
		return
	
	match upgrade_id:
		"crew_numbers":
			_apply_crew_numbers(player_ship, new_level)
		"crew_quality":
			_apply_crew_quality_to_all_soldiers(player_ship)
		"cannon":
			_apply_cannon(player_ship, new_level)
		"singigeon":
			_apply_singigeon(player_ship, new_level)
		"janggun":
			_apply_janggun(player_ship, new_level)
		"hull_defense":
			_apply_hull_defense(player_ship)
		"navigation":
			_apply_navigation(player_ship)
		"supply_bonus":
			pass # Applied dynamically when picking up supplies
		"sextant":
			_apply_sextant(player_ship)
		"supply":
			_apply_supply(player_ship)
		"gold":
			_apply_gold()
	
	upgrade_applied.emit(upgrade_id, new_level)
	print("[Upgrade] 업그레이드 적용: %s Lv.%d" % [UPGRADES[upgrade_id]["name"], new_level])


## 현재 레벨의 설명 가져오기 (다음 레벨 기준)
func get_next_description(upgrade_id: String) -> String:
	var data = UPGRADES[upgrade_id]
	var current_lv = current_levels[upgrade_id]
	var next_level = current_lv + 1
	var ship = _get_player_ship()
	
	if "level_desc" in data and next_level in data["level_desc"]:
		return data["level_desc"][next_level]
	
	# 동적 설명 생성
	match upgrade_id:
		"cannon":
			if next_level % 2 != 0:
				return "대포 +1문 추가 (교대 배치)"
			else:
				return "대포 데미지 및 사거리/장전속도 향상"
		"janggun":
			return "대장군전 화력 및 화염/디버프 강화"
		"singigeon":
			return "신기전 발사 개수 및 파괴력 향상"
		"crew_numbers":
			if ship:
				return "정원 증가(%d → %d) 및 리스폰 가속" % [ship.max_crew_count, ship.max_crew_count + 1]
		"crew_quality":
			return "병사 최대 HP/방어력/공격력 일괄 강화"
		"hull_defense":
			return "함선 최대 체력 및 방어력 강화\n(즉시 일부 체력 수리)"
		"navigation":
			return "러더 선회 속도 및 돛 기동성 증가"
		"supply_bonus":
			return "해상 보급 획득 시 회복량 및 습득 범위 증가"
		"supply":
			return "선체 수리 (즉시 소폭 회복)"
		"sextant":
			return "자동 항해 장치 설치\n(돛을 바람에 맞춰 자동 조절)"

	if next_level > 1 and upgrade_id not in ["supply", "gold"]:
		return data["description"] + " (Lv.%d)" % next_level
	
	return data["description"]


# === 업그레이드 적용 함수들 ===

func _apply_crew_numbers(ship: Node3D, _level: int) -> void:
	if "max_crew_count" in ship:
		ship.max_crew_count += 1
	if "soldier_respawn_time" in ship:
		ship.soldier_respawn_time = maxf(1.0, ship.soldier_respawn_time * 0.8) # 리스폰 속도 20%씩 단축
		
	# 바로 1명 스폰 시도
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return
	var soldier = soldier_scene.instantiate()
	soldiers_node.add_child(soldier)
	soldier.set_team("player")
	var offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-2.0, 2.0))
	soldier.position = offset
	var current_max = ship.get("max_crew_count") if "max_crew_count" in ship else 0
	print("[Crew] 병사 정원 증가! (현재 최대: %d)" % current_max)

func _apply_crew_quality_to_all_soldiers(ship: Node3D) -> void:
	var soldiers = _get_player_soldiers(ship)
	var quality_lv = current_levels.get("crew_quality", 0)
	for s in soldiers:
		_apply_current_stats_to_soldier(s)
	print("[Crew Quality] 정예병 훈련 Lv.%d 완료!" % quality_lv)

func _apply_current_stats_to_soldier(soldier: Node) -> void:
	var quality_lv = current_levels.get("crew_quality", 0)
	if quality_lv > 0:
		# 체력 증가 (+10 per level)
		var base_max_hp = 40.0
		var new_max_hp = base_max_hp + (quality_lv * 10.0)
		if "max_health" in soldier:
			soldier.max_health = new_max_hp
			soldier.current_health = minf(soldier.current_health + 10.0, soldier.max_health)
		
		# 공격력 증가 (+15% per level) / 방어력 증가 (피해감소율 +10% per level)
		soldier.set_meta("damage_multiplier", 1.0 + (quality_lv * 0.15))
		soldier.set_meta("defense_reduction", quality_lv * 0.1)

func _apply_hull_defense(ship: Node3D) -> void:
	var def_lv = current_levels.get("hull_defense", 0)
	if "max_hull_hp" in ship:
		ship.max_hull_hp += 30.0 # 5단계까지 총 +150
		ship.hull_hp += 20.0 # 즉시 체력 일부 회복
	if "hull_defense" in ship:
		ship.hull_defense = def_lv * 2.0 # 단계당 방어력 +2
	
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	print("[Hull] 선체 장갑 강화 Lv.%d" % def_lv)

func _apply_navigation(ship: Node3D) -> void:
	var nav_lv = current_levels.get("navigation", 0)
	if "rudder_turn_speed" in ship:
		ship.rudder_turn_speed *= 1.15 # 선회 15%씩 증가
	if "stamina_drain_rate" in ship:
		ship.stamina_drain_rate *= 0.85
	print("[Navigation] 항해 기동 강화 Lv.%d" % nav_lv)

func _apply_cannon(ship: Node3D, level: int) -> void:
	var cannons_node = ship.get_node_or_null("Cannons")
	if not cannons_node:
		cannons_node = Node3D.new()
		cannons_node.name = "Cannons"
		ship.add_child(cannons_node)
	
	if level % 2 != 0:
		# 홀수 레벨: 대포 추가 (1, 3, 5, 7) -> 총 4기 배치
		var count_idx = int((level + 1) / 2.0)
		var cannon = cannon_scene.instantiate()
		cannons_node.add_child(cannon)
		
		var positions = [
			Vector3(1.3, 0.6, -2.0), # Lv1 -> 우측 선수
			Vector3(-1.3, 0.6, -2.0), # Lv3 -> 좌측 선수
			Vector3(1.3, 0.6, 2.0), # Lv5 -> 우측 선미
			Vector3(-1.3, 0.6, 2.0) # Lv7 -> 좌측 선미
		]
		
		var pos = positions[0]
		if count_idx <= positions.size():
			pos = positions[count_idx - 1]
		else:
			var side = 1 if count_idx % 2 == 1 else -1
			var z_offset = 2.0 + (count_idx - 4) * 1.0
			pos = Vector3(side * 1.3, 0.6, z_offset)

		cannon.position = pos
		var rot_y = -90.0 if pos.x > 0 else 90.0
		cannon.rotation.y = deg_to_rad(rot_y)
		print("[Cannon] 대포 추가! (위치: %s)" % pos)
	else:
		# 짝수 레벨: 화력 강화 (별도 적용 없이 cannon.gd에서 upgrade_manager 상태 조회)
		print("[Cannon] 대포 화력/장전/사거리 강화! (Lv.%d)" % level)


func _apply_singigeon(ship: Node3D, level: int) -> void:
	if level == 1:
		var launcher = singigeon_scene.instantiate()
		launcher.name = "SingijeonLauncher"
		ship.add_child(launcher)
		launcher.position = Vector3(0, 0.5, -3.5) # 배 앞쪽
		launcher.upgrade_to_level(level)
	else:
		var launcher = ship.get_node_or_null("SingijeonLauncher")
		if launcher:
			launcher.upgrade_to_level(level)


func _apply_janggun(ship: Node3D, level: int) -> void:
	if level == 1:
		var launcher = janggun_scene.instantiate()
		launcher.name = "JanggunLauncher"
		ship.add_child(launcher)
		launcher.position = Vector3(0, 0.8, 2.0)
	else:
		print("[Janggun] 장군전 화력 및 디버프 강화! (Lv.%d)" % level)


func _apply_supply(ship: Node3D) -> void:
	if "max_hull_hp" in ship:
		ship.max_hull_hp += 20.0
	if "hull_hp" in ship:
		ship.hull_hp = ship.max_hull_hp
	print("[Supply] 보급! HP: %.0f / %.0f" % [ship.hull_hp, ship.max_hull_hp])
	
	# HUD 업데이트
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)


func _apply_gold() -> void:
	var level_mgr = get_tree().get_first_node_in_group("level_manager")
	if level_mgr and level_mgr.has_method("add_score"):
		level_mgr.add_score(50)
	else:
		# 직접 LevelManager 찾기
		for node in get_tree().root.get_children():
			if node.has_method("add_score"):
				node.add_score(50)
				break
	print("[Gold] 전리품! 점수 +50")


func _get_player_ship() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null


func _apply_sextant(ship: Node3D) -> void:
	if "has_sextant" in ship:
		ship.has_sextant = true
	print("[Item] 육분의 장착! 이제 돛이 자동으로 조절됩니다.")


func _get_player_soldiers(ship: Node3D) -> Array:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return []
	var result = []
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != null:
			result.append(child)
	return result
