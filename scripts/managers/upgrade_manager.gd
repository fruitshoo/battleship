extends Node

## 업그레이드 매니저 (AutoLoad)
## 업그레이드 데이터 및 적용 로직 관리

signal upgrade_applied(upgrade_id: String, new_level: int)

# 업그레이드 정의
var UPGRADES = {
	"crew": {
		"name": "🗡 병사 충원",
		"description": "아군 병사 +1",
		"max_level": 6,
		"color": Color(0.4, 0.8, 1.0)
	},
	"cannon": {
		"name": "💥 대포 추가",
		"description": "대포 +1 (좌/우 교대 배치)",
		"max_level": 4,
		"color": Color(1.0, 0.5, 0.2)
	},
	"singigeon": {
		"name": "🚀 신기전",
		"description": "로켓 화살 발사기",
		"max_level": 3,
		"color": Color(1.0, 0.3, 0.3),
		"level_desc": {
			1: "로켓 화살 1발",
			2: "3발 부채꼴 발사",
			3: "5발 연발 사격"
		}
	},
	"janggun": {
		"name": "🪵 장군전",
		"description": "통나무 미사일 (고데미지)",
		"max_level": 2,
		"color": Color(0.6, 0.4, 0.2),
		"level_desc": {
			1: "통나무 미사일 1기",
			2: "양현에 2기 배치"
		}
	},
	"sail": {
		"name": "⛵ 돛 업그레이드",
		"description": "최대 속도 +15%",
		"max_level": 3,
		"color": Color(0.8, 1.0, 0.8)
	},
	"rowing": {
		"name": "🚣 노 업그레이드",
		"description": "노 젓기 속도 +20%\n스태미나 소모 -10%",
		"max_level": 3,
		"color": Color(0.9, 0.9, 0.5)
	},
	"supply": {
		"name": "📦 보급물자",
		"description": "선체 HP 전체 회복\n최대 HP +20",
		"max_level": 99,
		"color": Color(0.5, 1.0, 0.5)
	},
	"crit_up": {
		"name": "🎯 급소 훈련",
		"description": "크리티컬 확률 +5%\n크리티컬 데미지 +25%",
		"max_level": 5,
		"color": Color(1.0, 0.8, 0.2)
	},
	"defense_up": {
		"name": "🛡️ 갑주 강화",
		"description": "병사 방어력 +3",
		"max_level": 5,
		"color": Color(0.4, 0.6, 1.0)
	},
	"maintenance": {
		"name": "🔧 보수 및 정비",
		"description": "줄어든 병사 즉시 완충\nPassive: 선체 자동 회복 +0.5/s",
		"max_level": 5,
		"color": Color(0.7, 0.5, 0.9)
	},
	"gold": {
		"name": "💰 전리품",
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
		if fb not in choices:
			choices.append(fb)
		else:
			break
	
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
		"sail":
			_apply_sail(player_ship)
		"rowing":
			_apply_rowing(player_ship)
		"supply":
			_apply_supply(player_ship)
		"crit_up":
			_apply_crit_up(player_ship)
		"defense_up":
			_apply_defense_up(player_ship)
		"maintenance":
			_apply_maintenance(player_ship)
		"gold":
			_apply_gold()
	
	upgrade_applied.emit(upgrade_id, new_level)
	print("⬆️ 업그레이드 적용: %s Lv.%d" % [UPGRADES[upgrade_id]["name"], new_level])


## 현재 레벨의 설명 가져오기 (다음 레벨 기준)
func get_next_description(upgrade_id: String) -> String:
	var data = UPGRADES[upgrade_id]
	var next_level = current_levels[upgrade_id] + 1
	
	if "level_desc" in data and next_level in data["level_desc"]:
		return data["level_desc"][next_level]
	
	if next_level > 1:
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
	
	# 함선의 병사 정원 증가
	if "max_crew_count" in ship:
		ship.max_crew_count += 1


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


func _apply_sail(ship: Node3D) -> void:
	if "max_speed" in ship:
		ship.max_speed *= 1.15
		print("⛵ 돛 업그레이드! 최대속도: %.1f" % ship.max_speed)


func _apply_rowing(ship: Node3D) -> void:
	if "rowing_speed" in ship:
		ship.rowing_speed *= 1.20
	if "stamina_drain_rate" in ship:
		ship.stamina_drain_rate *= 0.90
	print("🚣 노 업그레이드! 속도: %.1f, 소모: %.1f" % [
		ship.get("rowing_speed"), ship.get("stamina_drain_rate")])


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


func _apply_crit_up(ship: Node3D) -> void:
	var soldiers = _get_player_soldiers(ship)
	for s in soldiers:
		s.crit_chance = minf(s.crit_chance + 0.05, 0.5) # 최대 50%
		s.crit_multiplier += 0.25
	print("🎯 급소 훈련! 병사 %d명 적용 (crit: +5%%, dmg: +25%%)" % soldiers.size())


func _apply_defense_up(ship: Node3D) -> void:
	var soldiers = _get_player_soldiers(ship)
	for s in soldiers:
		s.defense += 3.0
	print("🛡️ 갑주 강화! 병사 %d명 적용 (defense: +3)" % soldiers.size())


func _get_player_soldiers(ship: Node3D) -> Array:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return []
	var result = []
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != null:
			result.append(child)
	return result

func _apply_maintenance(ship: Node3D) -> void:
	# 1. 병사 즉시 보충 (현재 정원까지)
	if ship.has_method("replenish_crew"):
		ship.replenish_crew(soldier_scene)
	
	# 2. 자동 회복 기능 추가/강화
	if "hull_regen_rate" in ship:
		ship.hull_regen_rate += 0.5 # 레벨당 초당 0.5씩 회복 증가
	
	# 3. 체력도 일부 즉시 회복 (보너스)
	if "hull_hp" in ship:
		ship.hull_hp = minf(ship.hull_hp + 20.0, ship.max_hull_hp)
		var hud = ship._find_hud() if ship.has_method("_find_hud") else null
		if hud and hud.has_method("update_hull_hp"):
			hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	
	print("🔧 보수 완료! 병사 완충 및 자동 회복율 %.1f/s" % ship.get("hull_regen_rate"))
