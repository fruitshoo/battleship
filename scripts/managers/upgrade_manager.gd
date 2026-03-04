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
		"color": Color(1.0, 0.5, 0.2),
		"stats": {"dmg_pct_per_stat": 25, "range_pct_per_stat": 15, "cd_pct_per_stat": 10}
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
	
	"spear_rail": {
		"name": "창 난간",
		"category": Category.ANTI_PERSONNEL,
		"description": "배 측면에 창을 배치하여 도선하는 적에게 자동 데미지",
		"max_level": 5,
		"color": Color(0.7, 0.5, 0.3),
		"stats": {"base_damage": 10.0, "damage_per_lv": 5.0, "base_count": 4, "count_per_lv": 2}
	},
	"fire_pot": {
		"name": "화통",
		"category": Category.ANTI_PERSONNEL,
		"description": "적선 갑판에 화통을 던져 주위의 적 병사들을 불태움",
		"max_level": 5,
		"color": Color(0.9, 0.3, 0.1),
		"stats": {
			"base_damage": 15.0, "damage_per_lv": 5.0,
			"base_radius": 3.0, "radius_per_lv": 0.5,
			"base_cooldown": 6.0, "cooldown_reduce_per_lv": 1.0
		}
	},
	"repeating_crossbow": {
		"name": "연노",
		"category": Category.ANTI_PERSONNEL,
		"description": "활 대신 고속 연속 발사가 가능한 연노를 병사들이 사용",
		"max_level": 5,
		"color": Color(0.6, 0.8, 0.2),
		"stats": {
			"base_damage": 10.0, "damage_per_lv": 2.0,
			"base_cooldown": 2.0, "cooldown_reduce_per_lv": 0.2,
			"burst_delay": 0.15
		}
	},
	"crew_numbers": {
		"name": "병사 충원",
		"category": Category.ANTI_PERSONNEL,
		"description": "최대 정원 증가 및 리스폰 속도 단축",
		"max_level": 5,
		"color": Color(0.4, 0.8, 1.0),
		"stats": {"crew_add": 1, "respawn_mult": 0.8, "respawn_min": 1.0}
	},
	"crew_quality": {
		"name": "정예병 훈련",
		"category": Category.ANTI_PERSONNEL,
		"description": "병사의 체력, 방어력, 공격력 일괄 상승",
		"max_level": 5,
		"color": Color(0.8, 0.8, 0.2),
		"stats": {"base_hp": 40.0, "hp_per_lv": 10.0, "dmg_pct_per_lv": 15, "def_pct_per_lv": 10}
	},
	
	# --- Hull / Navigation (5 Levels) ---
	"hull_defense": {
		"name": "선체 장갑",
		"category": Category.HULL,
		"description": "함선의 최대 체력 및 방어력 증가",
		"max_level": 5,
		"color": Color(0.6, 0.3, 0.1),
		"stats": {"hp_add": 30.0, "heal_on_apply": 20.0, "def_per_lv": 2.0}
	},
	"navigation": {
		"name": "항해 기동",
		"category": Category.NAVIGATION,
		"description": "선회 속도 및 돛 기동력 증가",
		"max_level": 5,
		"color": Color(0.4, 1.0, 0.4),
		"stats": {"turn_mult": 1.15, "stamina_mult": 0.85}
	},
	"supply_bonus": {
		"name": "보급 효율",
		"category": Category.HULL,
		"description": "보급품 획득 시 회복량 및 습득 범위 대폭 증가",
		"max_level": 5,
		"color": Color(0.3, 0.8, 0.3),
		"stats": {"base_radius": 8.0, "radius_per_lv": 2.0, "heal_per_lv": 5.0}
	},
	
	# --- Consumables / Instant ---
	"supply": {
		"name": "보급물자",
		"category": Category.HULL,
		"description": "체력 즉시 소폭 회복",
		"max_level": 99,
		"color": Color(0.5, 1.0, 0.5),
		"stats": {"max_hp_add": 20.0}
	},
	"gold": {
		"name": "전리품",
		"category": Category.SPECIAL,
		"description": "점수 +50",
		"max_level": 99,
		"color": Color(1.0, 0.85, 0.3),
		"stats": {"score_add": 50}
	}
}

# 렐릭(유물) 정의
var RELICS = {
	"sextant": {
		"name": "육분의",
		"description": "돛이 바람의 방향에 맞춰 자동으로 조절됩니다.",
		"icon": "explore", # HUD에 표시할 아이콘(임시)
		"alert_msg": "!! 렐릭 획득: 육분의 !!\n(자동 항해 활성화)"
	},
	"boss_heart": {
		"name": "보스의 심장",
		"description": "임시 보스 드롭 렐릭입니다.",
		"icon": "favorite",
		"alert_msg": "!! 렐릭 획득: 보스의 심장 !!"
	}
}

# 현재 업그레이드 레벨 추적
var current_levels: Dictionary = {}

# 획득한 렐릭(유물) 목록
var acquired_relics: Array[String] = []

# 프리로드
var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
var cannon_scene: PackedScene = preload("res://scenes/entities/cannon.tscn")
var singigeon_scene: PackedScene = preload("res://scenes/entities/singigeon_launcher.tscn")
var janggun_scene: PackedScene = preload("res://scenes/entities/janggun_launcher.tscn")


func _ready() -> void:
	for key in UPGRADES:
		current_levels[key] = 0

## 게임 시작 시 기본 무기 지급
func initialize_default_weapons() -> void:
	# 기본 대포 (Level 1)
	current_levels["cannon"] = 1
	var ship = _get_player_ship()
	var hud = ship._find_hud() if ship != null and ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_weapon_ui"):
		hud.update_weapon_ui("cannon", 1)


## 랜덤 선택지 반환
func get_random_choices(count: int = 3) -> Array:
	var available: Array = []
	
	# 무제한 업그레이드 (보급/돈) 제외하고 선택지 수집
	for id in UPGRADES:
		if id in ["supply", "gold"]:
			continue
		if current_levels[id] < UPGRADES[id]["max_level"]:
			available.append(id)
	
	available.shuffle()
	var choices = available.slice(0, mini(count, available.size()))
	
	# 빈 자리는 보급/돈으로 채움
	var fallbacks = ["supply", "gold"]
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
	
	# 함수명 규칙 기반 자동 디스패치: _apply_{upgrade_id}(ship, level)
	var method_name = "_apply_%s" % upgrade_id
	if has_method(method_name):
		call(method_name, player_ship, new_level)
	else:
		pass # supply_bonus 등 동적 적용 업그레이드는 별도 함수 없이 pass
	
	upgrade_applied.emit(upgrade_id, new_level)
	print("[Upgrade] 업그레이드 적용: %s Lv.%d" % [UPGRADES[upgrade_id]["name"], new_level])
	
	# 무기 종류 업그레이드 시 HUD 무기 슬롯 갱신
	var weapon_ids = ["cannon", "singigeon", "janggun", "spear_rail", "fire_pot", "repeating_crossbow"]
	if upgrade_id in weapon_ids:
		var hud = player_ship._find_hud() if player_ship.has_method("_find_hud") else null
		if hud and hud.has_method("update_weapon_ui"):
			hud.update_weapon_ui(upgrade_id, new_level)


## 현재 레벨의 설명 가져오기 (다음 레벨 기준)
func get_next_description(upgrade_id: String) -> String:
	var data = UPGRADES[upgrade_id]
	var current_lv = current_levels[upgrade_id]
	var next_level = current_lv + 1
	var ship = _get_player_ship()
	
	if "level_desc" in data and next_level in data["level_desc"]:
		return data["level_desc"][next_level]
	
	# 동적 설명 생성 (stats 딕셔너리 참조)
	var s = data.get("stats", {})
	match upgrade_id:
		"cannon":
			var stat_lv = int(next_level / 2)
			if next_level % 2 != 0:
				return "대포 교대 배치 추가 (+1문)"
			else:
				return "대포 데미지 +%d%%, 사거리 +%d%%, 장전 시간 -%d%%" % [
					stat_lv * s.get("dmg_pct_per_stat", 25),
					stat_lv * s.get("range_pct_per_stat", 15),
					stat_lv * s.get("cd_pct_per_stat", 10)]
		"janggun":
			return "대장군전 화력 및 화염/디버프 강화"
		"singigeon":
			return "신기전 발사 개수 및 파괴력 향상"
		"crew_numbers":
			if ship:
				var add = s.get("crew_add", 1)
				var spd = int((1.0 - s.get("respawn_mult", 0.8)) * 100)
				return "정원 증가(%d → %d) 및 리스폰 가속(-%d%%)" % [
					ship.max_crew_count, ship.max_crew_count + add, spd]
		"crew_quality":
			return "병사 최대 HP +%d, 공격력 +%d%%, 피해 감소 +%d%%" % [
				next_level * int(s.get("hp_per_lv", 10)),
				next_level * s.get("dmg_pct_per_lv", 15),
				next_level * s.get("def_pct_per_lv", 10)]
		"hull_defense":
			return "함선 최대 체력 +%d, 장갑 방어력 +%d\n(즉시 체력 +%d 수리)" % [
				int(s.get("hp_add", 30)), int(s.get("def_per_lv", 2)),
				int(s.get("heal_on_apply", 20))]
		"navigation":
			var turn_pct = int((s.get("turn_mult", 1.15) - 1.0) * 100)
			var stam_pct = int((1.0 - s.get("stamina_mult", 0.85)) * 100)
			return "러더 선회 속도 +%d%%, 스태미나 소모 -%d%%" % [turn_pct, stam_pct]
		"spear_rail":
			var total_count = int(s.get("base_count", 4) + int((next_level - 1) / 2.0) * s.get("count_per_lv", 2))
			var total_dmg = int(s.get("base_damage", 10.0) + (next_level - 1) * s.get("damage_per_lv", 5.0))
			return "창 %d개 배치, 도선 시 적 병사에게 %d 데미지" % [total_count, total_dmg]
		"fire_pot":
			var dmg = s.get("base_damage", 15.0) + (next_level - 1) * s.get("damage_per_lv", 5.0)
			var cd = s.get("base_cooldown", 6.0) - (next_level - 1) * s.get("cooldown_reduce_per_lv", 1.0)
			if next_level == 4: cd = 3.5
			if next_level >= 5: cd = 3.0
			return "화염 데미지 %.0f, 발사 대기시간 %.1f초" % [dmg, cd]
		"repeating_crossbow":
			var burst = 3
			if next_level >= 3: burst = 4
			if next_level >= 5: burst = 5
			var dmg = s.get("base_damage", 10.0) + (next_level - 1) * s.get("damage_per_lv", 2.0)
			return "한 번에 %d발 연속 발사, 데미지 %.0f" % [burst, dmg]
		"supply_bonus":
			var radius = s.get("base_radius", 8.0) + (next_level * s.get("radius_per_lv", 2.0))
			var heal = s.get("heal_per_lv", 5.0) * (next_level + 1)
			return "부유물 획득 범위 증가(%.1fm) 및\n체력 회복량 증가(+%.0f)" % [radius, heal]
		"supply":
			return "선체 수리 (즉시 HP +%d 회복)" % int(s.get("max_hp_add", 20))
		"gold":
			return "점수 +%d" % int(s.get("score_add", 50))

	if next_level > 1 and upgrade_id not in ["supply", "gold"]:
		return data["description"] + " (Lv.%d)" % next_level
	
	return data["description"]


# === 업그레이드 적용 함수들 ===

func _apply_crew_numbers(ship: Node3D, _level: int) -> void:
	var s = UPGRADES["crew_numbers"]["stats"]
	if "max_crew_count" in ship:
		ship.max_crew_count += s.get("crew_add", 1)
	if "soldier_respawn_time" in ship:
		ship.soldier_respawn_time = maxf(s.get("respawn_min", 1.0), ship.soldier_respawn_time * s.get("respawn_mult", 0.8))
		
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

func _apply_crew_quality(ship: Node3D, _level: int) -> void:
	var soldiers = _get_player_soldiers(ship)
	var quality_lv = current_levels.get("crew_quality", 0)
	for sol in soldiers:
		_apply_current_stats_to_soldier(sol)
	print("[Crew Quality] 정예병 훈련 Lv.%d 완료!" % quality_lv)

func _apply_current_stats_to_soldier(soldier: Node) -> void:
	var quality_lv = current_levels.get("crew_quality", 0)
	var s = UPGRADES["crew_quality"]["stats"]
	if quality_lv > 0:
		var new_max_hp = s.get("base_hp", 40.0) + (quality_lv * s.get("hp_per_lv", 10.0))
		if "max_health" in soldier:
			soldier.max_health = new_max_hp
			soldier.current_health = minf(soldier.current_health + s.get("hp_per_lv", 10.0), soldier.max_health)
		
		# 추가 공격력 / 방어력 설정 등은 soldier에 넘길 수 있음
		var dmg_mult = 1.0 + (quality_lv * s.get("dmg_pct_per_lv", 15) / 100.0)
		soldier.set_meta("damage_multiplier", dmg_mult)
		soldier.set_meta("defense_reduction", quality_lv * s.get("def_pct_per_lv", 10) / 100.0)
	
	# 연노 업그레이드 여부 확인 및 장착 (새로 스폰된 병사에게 자동 적용)
	var rc_lv = current_levels.get("repeating_crossbow", 0)
	if rc_lv > 0:
		if soldier.has_method("equip_weapon"):
			# 이 병사가 원거리 병사인지 확인 (현재 weapon_bow 등 max_range가 있는 무기 사용 중인지 여부)
			if soldier.current_weapon and soldier.current_weapon.has_method("attack") and "max_range" in soldier.current_weapon:
				soldier.equip_weapon(repeating_crossbow_scene)

func _apply_hull_defense(ship: Node3D, _level: int) -> void:
	var def_lv = current_levels.get("hull_defense", 0)
	var s = UPGRADES["hull_defense"]["stats"]
	if "max_hull_hp" in ship:
		ship.max_hull_hp += s.get("hp_add", 30.0)
		ship.hull_hp += s.get("heal_on_apply", 20.0)
	if "hull_defense" in ship:
		ship.hull_defense = def_lv * s.get("def_per_lv", 2.0)
	
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	print("[Hull] 선체 장갑 강화 Lv.%d" % def_lv)

func _apply_navigation(ship: Node3D, _level: int) -> void:
	var nav_lv = current_levels.get("navigation", 0)
	var s = UPGRADES["navigation"]["stats"]
	if "rudder_turn_speed" in ship:
		ship.rudder_turn_speed *= s.get("turn_mult", 1.15)
	if "stamina_drain_rate" in ship:
		ship.stamina_drain_rate *= s.get("stamina_mult", 0.85)
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


var spear_scene: PackedScene = preload("res://scenes/entities/weapons/weapon_spear.tscn")

func _apply_spear_rail(ship: Node3D, level: int) -> void:
	# SpearRail 컨테이너 가져오거나 생성
	var rail_node = ship.get_node_or_null("SpearRail")
	if not rail_node:
		rail_node = Node3D.new()
		rail_node.name = "SpearRail"
		ship.add_child(rail_node)
	
	# 기존 창 모두 제거 후 재배치 (레벨에 맞게 새로 배치)
	for child in rail_node.get_children():
		child.queue_free()
	
	var s = UPGRADES["spear_rail"]["stats"]
	var spear_count = int(s.get("base_count", 4) + int((level - 1) / 2.0) * s.get("count_per_lv", 2))
	var spear_damage = s.get("base_damage", 10.0) + (level - 1) * s.get("damage_per_lv", 5.0)
	
	# 배의 측면에 창을 균등하게 배치 (좌우 번갈아가며)
	# 배 크기: 대략 좌우 ±1.5, 전후 -3.5 ~ 3.5
	var ship_half_width = 1.5
	var ship_front = -3.0
	var ship_back = 3.0
	var ship_length = ship_back - ship_front
	
	for i in range(spear_count):
		var spear = spear_scene.instantiate()
		rail_node.add_child(spear)
		
		# 좌우 번갈아 배치
		var side = 1.0 if i % 2 == 0 else -1.0
		var row_index = int(i / 2.0)
		var z_pos = ship_front + (row_index + 0.5) * (ship_length / max(int(spear_count / 2.0), 1))
		
		spear.position = Vector3(side * ship_half_width, 0.3, z_pos)
		# 좌측은 외부로 기울임, 우측도 외부로 기울임
		spear.rotation_degrees = Vector3(0, 0, side * -30.0)
		# 창을 약간 작게 조정 (배 난간 크기에 맞게)
		spear.scale = Vector3(0.7, 0.7, 0.7)
	
	# 배에 창 난간 데미지 메타데이터 저장 (병사 도선 시 참조)
	ship.set_meta("spear_rail_damage", spear_damage)
	print("[SpearRail] 창 난간 Lv.%d: 창 %d개 배치, 도선 데미지 %.0f" % [level, spear_count, spear_damage])


var fire_pot_scene: PackedScene = preload("res://scenes/weapons/fire_pot_launcher.tscn")

func _apply_fire_pot(ship: Node3D, level: int) -> void:
	if level == 1:
		var launcher = fire_pot_scene.instantiate()
		launcher.name = "FirePotLauncher"
		ship.add_child(launcher)
		# 투척수 위치 (배 중앙 살짝 뒤)
		launcher.position = Vector3(0, 0.8, 1.0)
		print("[FirePot] 화통 투척 준비 완료! (Lv.1)")
	else:
		print("[FirePot] 화통 데미지/쿨다운 강화! (Lv.%d)" % level)


var repeating_crossbow_scene: PackedScene = preload("res://scenes/entities/weapons/weapon_repeating_crossbow.tscn")

func _apply_repeating_crossbow(ship: Node3D, level: int) -> void:
	print("[RepeatingCrossbow] 병사 연노 업그레이드 발동! (Lv.%d)" % level)
	
	# 이미 배치된 아군 병사들의 무기를 연노로 일괄 교체
	var soldiers = _get_player_soldiers(ship)
	for sol in soldiers:
		if sol.has_method("equip_weapon"):
			# 기존 원거리 무기를 장착 중인 병사만 연노로 갱신 (근접 병사가 있다면 무시)
			if sol.current_weapon and sol.current_weapon.has_method("attack") and "max_range" in sol.current_weapon:
				sol.equip_weapon(repeating_crossbow_scene)


func _apply_supply(ship: Node3D, _level: int) -> void:
	var s = UPGRADES["supply"]["stats"]
	var add = s.get("max_hp_add", 20.0)
	if "max_hull_hp" in ship:
		ship.max_hull_hp += add
	if "hull_hp" in ship:
		ship.hull_hp = ship.max_hull_hp
	print("[Supply] 보급! HP: %.0f / %.0f" % [ship.hull_hp, ship.max_hull_hp])
	
	# HUD 업데이트
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)


func _apply_gold(_ship: Node3D, _level: int) -> void:
	var s = UPGRADES["gold"]["stats"]
	var pts = int(s.get("score_add", 50))
	var level_mgr = get_tree().get_first_node_in_group("level_manager")
	if level_mgr and level_mgr.has_method("add_score"):
		level_mgr.add_score(pts)
	else:
		for node in get_tree().root.get_children():
			if node.has_method("add_score"):
				node.add_score(pts)
				break
	print("[Gold] 전리품! 점수 +%d" % pts)


func _get_player_ship() -> Node3D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null


func add_relic(relic_id: String) -> void:
	if relic_id not in RELICS:
		push_warning("UpgradeManager: 존재하지 않는 렐릭 ID입니다 - %s" % relic_id)
		return
		
	if acquired_relics.has(relic_id):
		return
		
	var ship = _get_player_ship()
	if not ship: return
	
	acquired_relics.append(relic_id)
	
	# 함수명 규칙 기반 자동 디스패치: _apply_relic_{relic_id}(ship)
	var method_name = "_apply_relic_%s" % relic_id
	if has_method(method_name):
		call(method_name, ship)
	
	# HUD 공통 업데이트 로직
	var relic_data = RELICS[relic_id]
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	
	if hud:
		if "icon" in relic_data and hud.has_method("add_relic_icon"):
			hud.add_relic_icon(relic_data["icon"])
			
		if "alert_msg" in relic_data and hud.has_method("show_message"):
			hud.show_message(relic_data["alert_msg"], 3.0)
			
	print("[Relic] %s 획득! - %s" % [relic_data["name"], relic_data["description"]])

# === 렐릭 적용 함수들 ===

func _apply_relic_sextant(ship: Node3D) -> void:
	if "has_sextant" in ship:
		ship.has_sextant = true


func _get_player_soldiers(ship: Node3D) -> Array:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return []
	var result = []
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != null:
			result.append(child)
	return result
