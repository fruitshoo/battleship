extends Node

## 업그레이드 매니저 (AutoLoad)
## 업그레이드 데이터 및 적용 로직 관리

signal upgrade_applied(upgrade_id: String, new_level: int)

# 업그레이드 정의
# 업그레이드 카테고리
enum Category {ANTI_SHIP, ANTI_PERSONNEL, HULL, NAVIGATION, SPECIAL}

# 업그레이드 정의
var UPGRADES = {
	# --- Primary Weapons (Active) ---
	"crew": {
		"name": "🗡 병사 충원",
		"category": Category.ANTI_PERSONNEL,
		"description": "아군 병사 정원 +1",
		"max_level": 8,
		"color": Color(0.4, 0.8, 1.0)
	},
	"cannon": {
		"name": "💥 대포 추가",
		"category": Category.ANTI_SHIP,
		"description": "대포 +1 (교대 배치)",
		"max_level": 6,
		"color": Color(1.0, 0.5, 0.2)
	},
	"singigeon": {
		"name": "🚀 신기전",
		"category": Category.ANTI_PERSONNEL,
		"description": "로켓 화살 발사기",
		"max_level": 3,
		"color": Color(1.0, 0.3, 0.3),
		"level_desc": {1: "1발", 2: "3발", 3: "5발"}
	},
	"janggun": {
		"name": "🪵 장군전",
		"category": Category.ANTI_SHIP,
		"description": "통나무 미사일 발사기",
		"max_level": 2,
		"color": Color(0.6, 0.4, 0.2),
		"level_desc": {1: "1기 배치", 2: "양현 배치"}
	},
	
	# --- Passive Attributes (Synergies) ---
	"iron_armor": {
		"name": "🛡️ 철갑 강화",
		"category": Category.ANTI_SHIP,
		"description": "[대함 시너지] 대포/장군전 데미지 +25%",
		"max_level": 5,
		"color": Color(0.7, 0.7, 0.8)
	},
	"black_powder": {
		"name": "🧨 화약 숙련",
		"category": Category.ANTI_SHIP,
		"description": "[범위 시너지] 대포/신기전 폭발 반경 +20%",
		"max_level": 5,
		"color": Color(0.3, 0.3, 0.3)
	},
	"fire_arrows": {
		"name": "🔥 불타는 화살",
		"category": Category.ANTI_PERSONNEL,
		"description": "[도트 시너지] 화살/신기전 화상 피해 추가",
		"max_level": 3,
		"color": Color(1.0, 0.6, 0.0)
	},
	"training": {
		"name": "🏃 전투 훈련",
		"category": Category.SPECIAL,
		"description": "[공통 시너지] 모든 무기 쿨다운 -10%, 병사 속도 +15%",
		"max_level": 5,
		"color": Color(0.8, 0.8, 0.2)
	},
	"seamanship": {
		"name": "⛵ 항해술",
		"category": Category.NAVIGATION,
		"description": "[기동 시너지] 선회력 +20%, 노 젓기 효율 +15%",
		"max_level": 5,
		"color": Color(0.4, 1.0, 0.4)
	},
	"carpentry": {
		"name": "🔧 조선술",
		"category": Category.HULL,
		"description": "[함선 시너지] 최대 체력 +30, 자동 수리 +0.5/s",
		"max_level": 5,
		"color": Color(0.6, 0.3, 0.1)
	},
	
	# --- Special / Rare Items ---
	"sextant": {
		"name": "🧭 육분의",
		"category": Category.SPECIAL,
		"description": "[자동화] 바람 방향에 맞춰 돛 자동 최적화",
		"max_level": 1,
		"color": Color(1.0, 0.9, 0.5)
	},
	
	# --- Consumables / Instant ---
	"supply": {
		"name": "📦 보급물자",
		"category": Category.HULL,
		"description": "체력 즉시 회복 및 최대 HP +20",
		"max_level": 99,
		"color": Color(0.5, 1.0, 0.5)
	},
	"gold": {
		"name": "💰 전리품",
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
		"crew":
			_apply_crew(player_ship)
		"cannon":
			_apply_cannon(player_ship, new_level)
		"singigeon":
			_apply_singigeon(player_ship, new_level)
		"janggun":
			_apply_janggun(player_ship, new_level)
		"iron_armor", "black_powder", "fire_arrows", "training":
			# 대부분의 공격 패시브는 실시간 반영되므로 추가 처리 불필요 (무기가 발사 시 체크)
			# 단, Training은 병사 속도에 즉각 반영
			if upgrade_id == "training":
				_apply_training_to_all_soldiers(player_ship)
		"seamanship":
			_apply_seamanship(player_ship)
		"carpentry":
			_apply_carpentry(player_ship)
		"sextant":
			_apply_sextant(player_ship)
		"supply":
			_apply_supply(player_ship)
		"gold":
			_apply_gold()
	
	upgrade_applied.emit(upgrade_id, new_level)
	print("⬆️ 업그레이드 적용: %s Lv.%d" % [UPGRADES[upgrade_id]["name"], new_level])


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
		"crew":
			if ship:
				return "아군 병사 정원 증설\n(현재 %d명 → %d명)" % [ship.max_crew_count, ship.max_crew_count + 1]
		"supply":
			if ship:
				return "선체 수리 및 강화\n(Max HP %d → %d)" % [ship.max_hull_hp, ship.max_hull_hp + 20]
		"iron_armor":
			return "대포/장군전 피해량 +25%%\n(현재 총 보너스: +%d%%)" % (current_lv * 25)
		"black_powder":
			return "폭발 범위 및 화력 강화\n(현재 보너스: +%d%%)" % (current_lv * 20)
		"fire_arrows":
			return "화살/신기전에 화염 속성 부여\n(중첩 시 데미지 강화)"
		"seamanship":
			return "선회력 및 노 젓기 효율 강화\n(현재 Lv.%d)" % current_lv
		"sextant":
			return "자동 항해 장치 설치\n(돛을 바람에 맞춰 자동 조절)"

	if next_level > 1 and upgrade_id not in ["supply", "gold"]:
		return data["description"] + " (Lv.%d)" % next_level
	
	return data["description"]


# === 업그레이드 적용 함수들 ===

func _apply_crew(ship: Node3D) -> void:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return
	
	var soldier = soldier_scene.instantiate()
	soldiers_node.add_child(soldier)
	soldier.set_team("player")
	var offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-2.0, 2.0))
	soldier.position = offset
	
	# 기존 업그레이드 스탯 적용 (중요!)
	_apply_current_stats_to_soldier(soldier)
	
	# 함선의 병사 정원 증가
	if "max_crew_count" in ship:
		ship.max_crew_count += 1

func _apply_current_stats_to_soldier(soldier: Node) -> void:
	# Training 반영 (속도)
	var train_lv = current_levels.get("training", 0)
	if train_lv > 0:
		soldier.move_speed *= (1.0 + 0.15 * train_lv)
	
	# Fire Arrows 등 공격 속성은 발사 시점에 UpgradeManager 참조


func _apply_cannon(ship: Node3D, level: int) -> void:
	var cannons_node = ship.get_node_or_null("Cannons")
	if not cannons_node:
		cannons_node = Node3D.new()
		cannons_node.name = "Cannons"
		ship.add_child(cannons_node)
	
	var cannon = cannon_scene.instantiate()
	cannons_node.add_child(cannon)
	
	# 고정된 대포 위치 정의 (기존 대포는 z=0, Side는 x=±1.3)
	var positions = [
		Vector3(1.3, 0.6, -2.0), # Lv1: 우측 선수 (Fore-Right)
		Vector3(-1.3, 0.6, -2.0), # Lv2: 좌측 선수 (Fore-Left)
		Vector3(1.3, 0.6, 2.0), # Lv3: 우측 선미 (Aft-Right)
		Vector3(-1.3, 0.6, 2.0) # Lv4: 좌측 선미 (Aft-Left)
	]
	
	if level <= positions.size():
		var pos = positions[level - 1]
		cannon.position = pos
		# 우측(x>0)이면 -90도(우향), 좌측(x<0)이면 90도(좌향)
		var rot_y = -90.0 if pos.x > 0 else 90.0
		cannon.rotation.y = deg_to_rad(rot_y)
		print("💥 대포 추가! (Lv.%d, 위치: %s)" % [level, pos])
	else:
		# 예외 처리: 혹시 더 추가된다면 기존 방식대로 뒤쪽으로 나열
		var side = 1 if level % 2 == 1 else -1
		var z_offset = 2.0 + (level - 5) * 1.0
		cannon.position = Vector3(side * 1.3, 0.6, z_offset)
		cannon.rotation.y = deg_to_rad(-90.0 if side == 1 else 90.0)


func _apply_singigeon(ship: Node3D, level: int) -> void:
	if level == 1:
		# 최초 배치: 발사기 인스턴스 생성
		var launcher = singigeon_scene.instantiate()
		launcher.name = "SingijeonLauncher"
		ship.add_child(launcher)
		launcher.position = Vector3(0, 0.5, -3.5) # 배 앞쪽
		launcher.upgrade_to_level(1)
	else:
		# 기존 발사기 업그레이드
		var launcher = ship.get_node_or_null("SingijeonLauncher")
		if launcher:
			launcher.upgrade_to_level(level)


func _apply_janggun(ship: Node3D, level: int) -> void:
	if level == 1:
		# 1기: 배 중앙 뒤쪽
		var launcher = janggun_scene.instantiate()
		launcher.name = "JanggunLauncher1"
		ship.add_child(launcher)
		launcher.position = Vector3(0, 0.8, 2.0)
	elif level == 2:
		# 2기: 양현에 추가
		var launcher2 = janggun_scene.instantiate()
		launcher2.name = "JanggunLauncher2"
		ship.add_child(launcher2)
		launcher2.position = Vector3(-1.5, 0.8, 1.0)


func _apply_seamanship(ship: Node3D) -> void:
	# 선회력 및 노 젓기 강화
	if "rudder_turn_speed" in ship:
		ship.rudder_turn_speed *= 1.2
	if "stamina_drain_rate" in ship:
		ship.stamina_drain_rate *= 0.85
	print("⛵ 항해술 강화! 선회 속도 및 효율 증가.")


func _apply_supply(ship: Node3D) -> void:
	if "max_hull_hp" in ship:
		ship.max_hull_hp += 20.0
	if "hull_hp" in ship:
		ship.hull_hp = ship.max_hull_hp
	print("📦 보급! HP: %.0f / %.0f" % [ship.hull_hp, ship.max_hull_hp])
	
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
	print("💰 전리품! 점수 +50")


func _get_player_ship() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null


func _apply_training_to_all_soldiers(ship: Node3D) -> void:
	var soldiers = _get_player_soldiers(ship)
	for s in soldiers:
		s.move_speed *= 1.15

func _apply_carpentry(ship: Node3D) -> void:
	if "max_hull_hp" in ship:
		ship.max_hull_hp += 30.0
		ship.hull_hp += 30.0 # 보너스로 현재 체력도 증가
	if "hull_regen_rate" in ship:
		ship.hull_regen_rate += 0.5
	
	# HUD 업데이트
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	print("🔧 조선술 업그레이드! 선체 내구도 및 수리 능력 강화.")

func _apply_sextant(ship: Node3D) -> void:
	if "has_sextant" in ship:
		ship.has_sextant = true
	print("🧭 육분의 장착! 이제 돛이 자동으로 조절됩니다.")


func _get_player_soldiers(ship: Node3D) -> Array:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return []
	var result = []
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != null:
			result.append(child)
	return result
