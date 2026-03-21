@tool
extends Node
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const RelicDataResource = preload("res://scripts/resource_types/relic_data.gd")
const UpgradeManagerDataHelper = preload("res://scripts/managers/upgrade_manager_data_helper.gd")

## 업그레이드 매니저 (AutoLoad)
## 업그레이드 데이터 및 적용 로직 관리

signal upgrade_applied(upgrade_id: String, new_level: int)

# 업그레이드 정의
# 업그레이드 카테고리
enum Category {ANTI_SHIP, ANTI_PERSONNEL, HULL, SEAMANSHIP, SPECIAL, FLEET}

# 업그레이드 정의 (JSON에서 로드됨)
var UPGRADES = {}

# 렐릭 정의 (리소스에서 로드됨, JSON은 fallback)
var RELICS = {}

const DATA_PATH = "res://data/upgrades.json"
const RELIC_DATA_DIR = "res://resources/relics"


# 현재 업그레이드 레벨 추적
var current_levels: Dictionary = {}

# 획득한 렐릭(유물) 목록
var acquired_relics: Array[String] = []

# 프리로드
var soldier_scene: PackedScene = preload("res://scenes/entities/soldiers/soldier.tscn")
var cannon_scene: PackedScene = preload("res://scenes/entities/launchers/cannon_joseon.tscn")
var cannonball_joseon_scene: PackedScene = preload("res://scenes/projectiles/cannonball_joseon.tscn")
var janggun_scene: PackedScene = preload("res://scenes/entities/launchers/janggun_launcher.tscn")
var ballista_scene: PackedScene = preload("res://scenes/entities/launchers/ballista_launcher.tscn")

const SHIP_UPGRADE_IDS: Array[String] = [
	"cannon",
	"janggun",
	"hull_defense",
	"sailing",
	"rowing",
	"supply_bonus",
]
const CREW_UPGRADE_IDS: Array[String] = [
	"crew_numbers",
	"crew_attack",
	"crew_defense",
	"singigeon",
	"fire_pot",
	"repeating_crossbow",
]
const SUPPORT_SHIP_UPGRADE_IDS: Array[String] = [
	"fleet_cannon",
	"fleet_hull",
]
const SUPPORT_CREW_UPGRADE_IDS: Array[String] = [
	"fleet_crew",
]
const ACTIVE_SUPPORT_UPGRADE_IDS: Array[String] = [
	"fleet_cannon",
	"fleet_hull",
	"fleet_crew",
]
const RARE_FLEET_UPGRADE_ID: String = "fleet_signal"
const RARE_FLEET_UPGRADE_CHANCE: float = 0.08
const CREW_ROLE_GENERAL := "general"
const CREW_ROLE_SPEARMAN := "spearman"
const CREW_ROLE_FIRE_POT := "fire_pot"
const CREW_ROLE_REPEATING_CROSSBOW := "repeating_crossbow"
const CREW_ROLE_SINGIGEON := "singigeon"

func _ready() -> void:
	_load_data_from_json()
	
	for key in UPGRADES:
		current_levels[key] = 0
	_sync_relics_from_save()

func reset_run_upgrades() -> void:
	for key in UPGRADES:
		current_levels[key] = 0

func _sync_relics_from_save() -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(SaveManager) and SaveManager.has_method("get_relics"):
		acquired_relics = SaveManager.get_relics()

## 데이터 로드 (업그레이드는 JSON, 렐릭은 리소스 우선)
func _load_data_from_json() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("UpgradeManager: 데이터 파일을 찾을 수 없습니다: %s" % DATA_PATH)
		return
		
	var file = FileAccess.open(DATA_PATH, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("UpgradeManager: JSON 파싱 오류 (Line %d): %s" % [json.get_error_line(), json.get_error_message()])
		return
		
	var data = json.data
	if data.has("upgrades"):
		UPGRADES = data["upgrades"]
		# Color 값 변환 (Hex -> Color 객체)
		for key in UPGRADES:
			if UPGRADES[key].has("color"):
				UPGRADES[key]["color"] = Color.from_string(UPGRADES[key]["color"], Color.WHITE)
				
	if not _load_relics_from_resources() and data.has("relics"):
		RELICS = data["relics"]

	print("[UpgradeManager] 데이터를 성공적으로 로드했습니다: %d개의 업그레이드, %d개의 렐릭" % [UPGRADES.size(), RELICS.size()])

func _load_relics_from_resources() -> bool:
	RELICS.clear()
	var dir := DirAccess.open(RELIC_DATA_DIR)
	if dir == null:
		return false

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource_path := "%s/%s" % [RELIC_DATA_DIR, file_name]
			var relic_res: Resource = load(resource_path)
			if relic_res != null and relic_res.get_script() == RelicDataResource:
				var relic_id: String = String(relic_res.get("relic_id"))
				if relic_id.is_empty():
					file_name = dir.get_next()
					continue
				var relic_name: String = String(relic_res.get("relic_name"))
				var relic_description: String = String(relic_res.get("description"))
				var relic_icon: String = String(relic_res.get("icon"))
				var relic_alert_msg: String = String(relic_res.get("alert_msg"))
				var icon_texture_variant: Variant = relic_res.get("icon_texture")
				var icon_texture_path: String = ""
				if icon_texture_variant is Texture2D:
					icon_texture_path = (icon_texture_variant as Texture2D).resource_path
				RELICS[relic_id] = {
					"name": relic_name,
					"description": relic_description,
					"icon": relic_icon,
					"icon_texture": icon_texture_path,
					"alert_msg": relic_alert_msg,
					"resource_path": resource_path,
				}
		file_name = dir.get_next()
	dir.list_dir_end()

	return not RELICS.is_empty()

## 게임 시작 시 기본 무기 지급
func initialize_default_weapons() -> void:
	# 기본 대포 (Level 1)
	current_levels["cannon"] = 1
	var ship = _get_player_ship()
	if ship:
		_normalize_player_cannons(ship)
		_sync_player_cannon_layout(ship, 1)
	upgrade_applied.emit("cannon", 1)
	var hud = ship._find_hud() if ship != null and ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_weapon_ui"):
		hud.update_weapon_ui("cannon", 1)

func equip_owned_relics() -> void:
	_sync_relics_from_save()
	var ship = _get_player_ship()
	if not ship:
		return
	for relic_id in acquired_relics:
		if relic_id not in RELICS:
			continue
		_apply_relic_to_ship(relic_id, ship)
	refresh_hud_relic_icons()

func refresh_hud_relic_icons() -> void:
	_sync_relics_from_save()
	var ship = _get_player_ship()
	if not ship:
		return
	for relic_id in acquired_relics:
		if relic_id in RELICS:
			_apply_relic_to_ship(relic_id, ship)
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if not hud:
		return
	if hud.has_method("clear_relic_icons"):
		hud.clear_relic_icons()
	for relic_id in acquired_relics:
		if relic_id not in RELICS:
			continue
		var relic_data = RELICS[relic_id]
		if hud.has_method("add_relic_icon"):
			var relic_icon: Dictionary = _get_relic_icon_payload(relic_id, relic_data)
			if not relic_icon.is_empty():
				hud.add_relic_icon(relic_icon)

func get_ship_upgrade_choices(count: int = 3) -> Array:
	var ship_pool: Array[String] = SHIP_UPGRADE_IDS.duplicate()
	if _is_fleet_progress_available():
		ship_pool.append_array(SUPPORT_SHIP_UPGRADE_IDS)
	var choices = _collect_choices_from_ids(ship_pool, count)
	_maybe_add_rare_fleet_upgrade(choices, count)
	_fill_with_fallbacks(choices, count)
	var preferred_order: Array[String] = ship_pool.duplicate()
	preferred_order.append(RARE_FLEET_UPGRADE_ID)
	preferred_order.append_array(["supply", "gold"])
	_sort_choices_by_preferred_order(choices, preferred_order)
	return choices

func get_command_upgrade_choices(count: int = 3) -> Array:
	var command_pool: Array[String] = CREW_UPGRADE_IDS.duplicate()
	if _is_fleet_progress_available():
		for upgrade_id in SUPPORT_CREW_UPGRADE_IDS:
			command_pool.append(upgrade_id)
	var choices = _collect_choices_from_ids(command_pool, count)
	_sort_choices_by_preferred_order(choices, command_pool)
	return choices

func _is_fleet_progress_available() -> bool:
	# 지원 함대를 해금했거나 이미 함대 강화가 시작됐으면 지휘 선택지에 함대 강화를 노출한다.
	if int(current_levels.get(RARE_FLEET_UPGRADE_ID, 0)) > 0:
		return true
	for upgrade_id in ACTIVE_SUPPORT_UPGRADE_IDS:
		if int(current_levels.get(upgrade_id, 0)) > 0:
			return true
	var tree = get_tree()
	if tree == null:
		return false
	var minions = SceneGroupCache.get_nodes(tree, "captured_minion")
	return not minions.is_empty()

func _collect_choices_from_ids(ids: Array[String], count: int) -> Array:
	var available: Array = []
	for id in ids:
		if not _is_upgrade_available(id):
			continue
		available.append(id)
	available.shuffle()
	return available.slice(0, mini(count, available.size()))

func get_specialist_unit_count(upgrade_id: String, level: int = -1) -> int:
	return UpgradeManagerDataHelper.get_specialist_unit_count(UPGRADES, current_levels, upgrade_id, level)

func get_supply_bonus_stats(level: int = -1) -> Dictionary:
	return UpgradeManagerDataHelper.get_supply_bonus_stats(UPGRADES, current_levels, level)

func get_player_crew_roster(total_crew: int) -> Dictionary:
	return UpgradeManagerDataHelper.get_player_crew_roster(UPGRADES, current_levels, total_crew)

func _is_upgrade_available(upgrade_id: String) -> bool:
	if upgrade_id not in UPGRADES:
		return false
	if UPGRADES[upgrade_id].get("disabled", false) == true:
		return false
	return int(current_levels.get(upgrade_id, 0)) < int(UPGRADES[upgrade_id].get("max_level", 0))

func _maybe_add_rare_fleet_upgrade(choices: Array, count: int) -> void:
	if count <= 0:
		return
	if not _is_upgrade_available(RARE_FLEET_UPGRADE_ID):
		return
	if randf() > RARE_FLEET_UPGRADE_CHANCE:
		return
	if choices.has(RARE_FLEET_UPGRADE_ID):
		return

	if choices.size() >= count and choices.size() > 0:
		var replace_idx = randi() % choices.size()
		choices[replace_idx] = RARE_FLEET_UPGRADE_ID
	else:
		choices.append(RARE_FLEET_UPGRADE_ID)

func _fill_with_fallbacks(choices: Array, count: int) -> void:
	var fallbacks = ["supply", "gold"]
	var guard = 0
	while choices.size() < count and guard < 8:
		var fb = fallbacks[guard % fallbacks.size()]
		if not choices.has(fb):
			choices.append(fb)
		guard += 1


## 랜덤 선택지 반환
func get_random_choices(count: int = 3, category_filter: int = -1) -> Array:
	if category_filter == -1:
		return get_ship_upgrade_choices(count)
	if category_filter == Category.FLEET:
		return get_command_upgrade_choices(count)

	var available: Array = []
	
	# 무제한 업그레이드 (보급/돈) 제외하고 선택지 수집
	for id in UPGRADES:
		if id in ["supply", "gold"]:
			continue
			
		var u = UPGRADES[id]
		if u.get("disabled", false) == true:
			continue
		# 카테고리 필터링 (있을 경우)
		if category_filter != -1 and u.get("category", -1) != category_filter:
			continue
		# 일반 레벨업 시 함대 업그레이드 제외 (카테고리 5 = FLEET)
		if category_filter == -1 and u.get("category", -1) == 5:
			continue
			
		if current_levels[id] < u["max_level"]:
			available.append(id)
	
	available.shuffle()
	var choices = available.slice(0, mini(count, available.size()))
	
	# 함대 업그레이드 필터링 중이면 보급/돈 대신 다른 함대 항목이나 빈 배열을 반환할 수도 있음
	# 여기선 함대 항목이 부족할 경우 보급/돈은 넣지 않음 (함대 강화는 한정적이므로)
	if category_filter == 5:
		return choices
		
	# 빈 자리는 보급/돈으로 채움 (일반 레벨업용)
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

func _level_matches(level: int, level_list: Variant) -> bool:
	return UpgradeManagerDataHelper.level_matches(level, level_list)

func _sort_choices_by_preferred_order(choices: Array, preferred_ids: Array[String]) -> void:
	choices.sort_custom(func(a: String, b: String) -> bool:
		var a_idx := preferred_ids.find(a)
		var b_idx := preferred_ids.find(b)
		if a_idx == -1:
			a_idx = preferred_ids.size() + 100
		if b_idx == -1:
			b_idx = preferred_ids.size() + 100
		return a_idx < b_idx
	)


## 업그레이드 적용
func apply_upgrade(upgrade_id: String) -> void:
	if upgrade_id not in UPGRADES:
		return
	if UPGRADES[upgrade_id].get("disabled", false) == true:
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
		pass # supply_bonus 등 동적 적용 업그레이드는 별도 함수
	
	upgrade_applied.emit(upgrade_id, new_level)
	
	# 함대 업그레이드인 경우 현재 활성화된 모든 미니언에 즉시 적용
	if upgrade_id in ACTIVE_SUPPORT_UPGRADE_IDS:
		var minions = SceneGroupCache.get_nodes(get_tree(), "captured_minion")
		for m in minions:
			apply_fleet_upgrades_to_ship(m)
	
	print("[Upgrade] 업그레이드 적용: %s Lv.%d" % [UPGRADES[upgrade_id]["name"], new_level])
	
	# HUD 업그레이드 슬롯 갱신 (함선/병사 트랙 분리)
	var ship_ui_ids = ["cannon", "janggun", "hull_defense", "sailing", "rowing", "supply_bonus", "fleet_signal", "fleet_cannon", "fleet_hull", "supply", "gold"]
	var crew_ui_ids = ["crew_numbers", "crew_attack", "crew_defense", "singigeon", "fire_pot", "repeating_crossbow", "fleet_crew"]
	var hud = player_ship._find_hud() if player_ship.has_method("_find_hud") else null
	if hud:
		if upgrade_id in ship_ui_ids:
			if hud.has_method("update_ship_upgrade_ui"):
				hud.update_ship_upgrade_ui(upgrade_id, new_level)
			elif hud.has_method("update_weapon_ui"):
				hud.update_weapon_ui(upgrade_id, new_level)
		elif upgrade_id in crew_ui_ids:
			if hud.has_method("update_crew_upgrade_ui"):
				hud.update_crew_upgrade_ui(upgrade_id, new_level)
			elif hud.has_method("update_support_ui"):
				hud.update_support_ui(upgrade_id, new_level)


## 현재 레벨의 설명 가져오기 (다음 레벨 기준)
func get_next_description(upgrade_id: String) -> String:
	return UpgradeManagerDataHelper.get_next_description(UPGRADES, current_levels, upgrade_id)


# === 업그레이드 적용 함수들 ===

func _apply_crew_numbers(ship: Node3D, _level: int) -> void:
	var spearmen = get_specialist_unit_count("crew_numbers")
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[Spearman] 창병 편성 갱신! (%d명)" % spearmen)

func _apply_ballista(ship: Node3D, _level: int) -> void:
	push_warning("UpgradeManager: ballista upgrade is disabled for current gameplay flow.")

func _apply_crew_attack(ship: Node3D, _level: int) -> void:
	var soldiers = _get_player_soldiers(ship)
	var attack_lv = current_levels.get("crew_attack", 0)
	for sol in soldiers:
		_apply_current_stats_to_soldier(sol)
	print("[Crew Attack] 병사 공격력 Lv.%d 완료!" % attack_lv)

func _apply_crew_defense(ship: Node3D, _level: int) -> void:
	var soldiers = _get_player_soldiers(ship)
	var defense_lv = current_levels.get("crew_defense", 0)
	for sol in soldiers:
		_apply_current_stats_to_soldier(sol)
	print("[Crew Defense] 병사 방어력 Lv.%d 완료!" % defense_lv)

func _apply_current_stats_to_soldier(soldier: Node) -> void:
	var attack_lv = int(current_levels.get("crew_attack", 0))
	var defense_lv = int(current_levels.get("crew_defense", 0))
	var attack_stats: Dictionary = UPGRADES["crew_attack"]["stats"]
	var defense_stats: Dictionary = UPGRADES["crew_defense"]["stats"]
	var attack_flat_bonus: float = attack_lv * float(attack_stats.get("attack_add_per_lv", 2.0))
	var defense_flat_bonus: float = defense_lv * float(defense_stats.get("defense_add_per_lv", 1.0))
	soldier.set_meta("attack_flat_bonus", attack_flat_bonus)
	soldier.set_meta("defense_flat_bonus", defense_flat_bonus)
	if soldier.has_meta("damage_multiplier"):
		soldier.remove_meta("damage_multiplier")
	if soldier.has_meta("defense_reduction"):
		soldier.remove_meta("defense_reduction")
	
	if soldier.has_method("apply_crew_role") and "crew_role" in soldier:
		soldier.apply_crew_role(String(soldier.crew_role))

func _apply_hull_defense(ship: Node3D, _level: int) -> void:
	var def_lv = current_levels.get("hull_defense", 0)
	var s = UPGRADES["hull_defense"]["stats"]
	if _level_matches(def_lv, s.get("repair_levels", [])) and "hull_hp" in ship:
		ship.hull_hp += float(s.get("repair_add", 35.0))
	if "hull_defense" in ship:
		var defense_bonus := 0.0
		for level_entry in s.get("def_levels", []):
			if int(level_entry) <= def_lv:
				defense_bonus += float(s.get("def_add", 2.0))
		ship.hull_defense = defense_bonus
	var ranged_block := 0.0
	for level_entry in s.get("crew_ranged_block_levels", []):
		if int(level_entry) <= def_lv:
			ranged_block += float(s.get("crew_ranged_block_add", 0.10))
	ship.set_meta("crew_ranged_damage_reduction", ranged_block)
	if "hull_regen_rate" in ship:
		var regen_bonus := 0.0
		for level_entry in s.get("regen_levels", []):
			if int(level_entry) <= def_lv:
				regen_bonus += float(s.get("regen_add", 1.5))
		ship.hull_regen_rate = regen_bonus
	if "hull_hp" in ship and "max_hull_hp" in ship:
		ship.hull_hp = minf(ship.hull_hp, ship.max_hull_hp)

	var old_rail = ship.get_node_or_null("SpearRail")
	if old_rail:
		old_rail.queue_free()
	if ship.has_meta("spear_rail_damage"):
		ship.remove_meta("spear_rail_damage")
	var visuals = ship.get_node_or_null("HullDefenseVisuals")
	if visuals:
		visuals.queue_free()
	
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	print("[Hull] 선체 장갑 강화 Lv.%d" % def_lv)

func _apply_sailing(ship: Node3D, level: int) -> void:
	var s = UPGRADES["sailing"]["stats"]
	if _level_matches(level, s.get("speed_levels", [])) and "max_speed" in ship:
		ship.max_speed *= float(s.get("speed_mult", 1.08))
	if _level_matches(level, s.get("efficiency_levels", [])) and "sail_efficiency_mult" in ship:
		ship.sail_efficiency_mult *= float(s.get("efficiency_mult", 1.08))
	if _level_matches(level, s.get("turn_levels", [])) and "sail_turn_speed" in ship:
		ship.sail_turn_speed *= float(s.get("turn_mult", 1.15))
	print("[Sailing] 돛 운용 강화 Lv.%d" % level)

func _apply_rowing(ship: Node3D, level: int) -> void:
	var s = UPGRADES["rowing"]["stats"]
	if _level_matches(level, s.get("speed_levels", [])) and "rowing_speed" in ship:
		ship.rowing_speed *= float(s.get("speed_mult", 1.15))
	if _level_matches(level, s.get("accel_levels", [])) and "rowing_acceleration_mult" in ship:
		ship.rowing_acceleration_mult *= float(s.get("accel_mult", 1.2))
	if _level_matches(level, s.get("stamina_add_levels", [])) and "max_rowing_stamina" in ship:
		var stamina_add := float(s.get("stamina_add", 20.0))
		ship.max_rowing_stamina += stamina_add
		if "rowing_stamina" in ship:
			ship.rowing_stamina = minf(ship.max_rowing_stamina, ship.rowing_stamina + stamina_add)
	if _level_matches(level, s.get("drain_levels", [])) and "stamina_drain_rate" in ship:
		ship.stamina_drain_rate *= float(s.get("drain_mult", 0.85))
	if _level_matches(level, s.get("recovery_levels", [])) and "stamina_recovery_rate" in ship:
		ship.stamina_recovery_rate *= float(s.get("recovery_mult", 1.2))
	print("[Rowing] 노 운용 강화 Lv.%d" % level)

func _apply_supply_bonus(ship: Node3D, level: int) -> void:
	print("[SupplyBonus] 보급 효율 강화 Lv.%d" % level)

func _apply_cannon(ship: Node3D, level: int) -> void:
	var cannons_node = _get_player_cannons_node(ship)
	if not cannons_node:
		cannons_node = Node3D.new()
		cannons_node.name = "Cannons"
		ship.add_child(cannons_node)
	_normalize_player_cannons(ship)
	_sync_player_cannon_layout(ship, level)
	# 모든 레벨에서 화력 강화는 cannon.gd의 업그레이드 레벨 참조로 자동 적용됨
	print("[Cannon] 대포 성능 강화 적용 (Lv.%d)" % level)

func _normalize_player_cannons(ship: Node3D) -> void:
	var cannons_node = _get_player_cannons_node(ship)
	if not is_instance_valid(cannons_node):
		return
	for child in cannons_node.get_children():
		_configure_player_cannon(child)

func _sync_player_cannon_layout(ship: Node3D, level: int) -> void:
	var cannons_node = _get_player_cannons_node(ship)
	if not is_instance_valid(cannons_node):
		return

	var slot_specs: Array[Dictionary] = [
		{
			"name": "CannonFront",
			"position": Vector3(0.0, 0.6, -4.8),
			"rotation": Vector3.ZERO,
			"required_level": 1,
		},
		{
			"name": "CannonLeft",
			"position": Vector3(-1.3, 0.6, 0.0),
			"rotation": Vector3(0.0, deg_to_rad(90.0), 0.0),
			"required_level": 1,
		},
		{
			"name": "CannonRight",
			"position": Vector3(1.3, 0.6, 0.0),
			"rotation": Vector3(0.0, deg_to_rad(-90.0), 0.0),
			"required_level": 1,
		},
		{
			"name": "CannonLeftExtra",
			"position": Vector3(-1.3, 0.6, -2.0),
			"rotation": Vector3(0.0, deg_to_rad(90.0), 0.0),
			"required_level": 3,
		},
		{
			"name": "CannonRightExtra",
			"position": Vector3(1.3, 0.6, 2.0),
			"rotation": Vector3(0.0, deg_to_rad(-90.0), 0.0),
			"required_level": 5,
		},
	]

	var desired_names: Dictionary = {}
	for slot in slot_specs:
		desired_names[String(slot["name"])] = true

	var named_nodes: Dictionary = {}
	for child in cannons_node.get_children():
		if not is_instance_valid(child):
			continue
		var child_name := String(child.name)
		if not desired_names.has(child_name):
			if child is Node3D:
				(child as Node3D).visible = false
			child.set_process(false)
			child.set_physics_process(false)
			cannons_node.remove_child(child)
			child.queue_free()
			continue
		if named_nodes.has(child_name):
			if child is Node3D:
				(child as Node3D).visible = false
			child.set_process(false)
			child.set_physics_process(false)
			cannons_node.remove_child(child)
			child.queue_free()
			continue
		named_nodes[child_name] = child

	for slot in slot_specs:
		var node_name := String(slot["name"])
		var required_level := int(slot["required_level"])
		var cannon = named_nodes.get(node_name, null)
		if level < required_level:
			if is_instance_valid(cannon):
				if cannon is Node3D:
					(cannon as Node3D).visible = false
				cannon.set_process(false)
				cannon.set_physics_process(false)
				cannons_node.remove_child(cannon)
				cannon.queue_free()
				named_nodes.erase(node_name)
			continue
		if not is_instance_valid(cannon):
			cannon = cannon_scene.instantiate()
			cannon.name = node_name
			cannons_node.add_child(cannon)
			named_nodes[node_name] = cannon
		if cannon is Node3D:
			var cannon_node := cannon as Node3D
			cannon_node.visible = true
			cannon_node.position = slot["position"]
			cannon_node.rotation = slot["rotation"]
		cannon.set_process(true)
		cannon.set_physics_process(true)
		_configure_player_cannon(cannon)

	if OS.is_debug_build():
		var roster: Array[String] = []
		for child in cannons_node.get_children():
			if is_instance_valid(child):
				roster.append("%s#%s" % [child.name, str(child.get_instance_id())])
		print("[CannonSetup] level=%d active_slots=%s" % [level, ", ".join(roster)])

func _get_player_cannons_node(ship: Node3D) -> Node3D:
	if not is_instance_valid(ship):
		return null

	var preferred_node: Node3D = null
	for child in ship.get_children():
		if not is_instance_valid(child):
			continue
		if String(child.name).contains("Hull"):
			var nested = child.find_child("Cannons", true, false)
			if nested is Node3D:
				preferred_node = nested as Node3D
				break

	if preferred_node == null:
		var any_cannons = ship.find_child("Cannons", true, false)
		if any_cannons is Node3D:
			preferred_node = any_cannons as Node3D

	if preferred_node != null:
		_cleanup_stray_player_cannons_nodes(ship, preferred_node)

	return preferred_node

func _cleanup_stray_player_cannons_nodes(ship: Node3D, keep_node: Node3D) -> void:
	for child in ship.get_children():
		if not is_instance_valid(child):
			continue
		if child == keep_node:
			continue
		if String(child.name) != "Cannons":
			continue
		child.set_process(false)
		child.set_physics_process(false)
		ship.remove_child(child)
		child.queue_free()


func _configure_player_cannon(cannon: Node) -> void:
	if not is_instance_valid(cannon):
		return
	if "team" in cannon:
		cannon.team = "player"
	if "cannonball_scene" in cannon and cannonball_joseon_scene != null:
		cannon.cannonball_scene = cannonball_joseon_scene
	if "fire_cooldown" in cannon:
		cannon.fire_cooldown = 2.5
	if "detection_range" in cannon:
		cannon.detection_range = 24.0


func _apply_singigeon(ship: Node3D, level: int) -> void:
	var launcher = ship.get_node_or_null("SingijeonLauncher")
	if is_instance_valid(launcher):
		launcher.queue_free()
	var rocketeers = get_specialist_unit_count("singigeon", level)
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	var soldiers = _get_player_soldiers(ship)
	for sol in soldiers:
		_apply_current_stats_to_soldier(sol)
	print("[Singigeon] 신기전병 편성 갱신! (Lv.%d, %d명)" % [level, rocketeers])


func _apply_janggun(ship: Node3D, level: int) -> void:
	if level == 1:
		var launcher = janggun_scene.instantiate()
		launcher.name = "JanggunLauncher"
		ship.add_child(launcher)
		launcher.position = Vector3(0, 0.8, 2.0)
	else:
		print("[Janggun] 장군전 화력 및 디버프 강화! (Lv.%d)" % level)


func _apply_fire_pot(_ship: Node3D, level: int) -> void:
	var throwers = get_specialist_unit_count("fire_pot", level)
	if _ship.has_method("_sync_player_crew_roster"):
		_ship._sync_player_crew_roster()
	print("[FirePot] 화통병 편성 갱신! (Lv.%d, %d명)" % [level, throwers])


var repeating_crossbow_scene: PackedScene = preload("res://scenes/entities/weapons/weapon_repeating_crossbow.tscn")

func _apply_repeating_crossbow(ship: Node3D, level: int) -> void:
	var repeaters = get_specialist_unit_count("repeating_crossbow", level)
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	var soldiers = _get_player_soldiers(ship)
	for sol in soldiers:
		_apply_current_stats_to_soldier(sol)
	print("[RepeatingCrossbow] 연노병 편성 갱신! (Lv.%d, %d명)" % [level, repeaters])


func _apply_supply(ship: Node3D, _level: int) -> void:
	var s = UPGRADES["supply"]["stats"]
	var hull_heal: float = float(s.get("hull_heal", 20.0))
	var stamina_recover: float = float(s.get("stamina_recover", 25.0))
	if "hull_hp" in ship and "max_hull_hp" in ship:
		ship.hull_hp = minf(ship.max_hull_hp, ship.hull_hp + hull_heal)
	if "rowing_stamina" in ship and "max_rowing_stamina" in ship:
		ship.rowing_stamina = minf(ship.max_rowing_stamina, ship.rowing_stamina + stamina_recover)
	print("[Supply] 보급! HP: %.0f / %.0f | ST: %.0f / %.0f" % [
		ship.hull_hp,
		ship.max_hull_hp,
		ship.rowing_stamina,
		ship.max_rowing_stamina,
	])
	
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

func _apply_fleet_signal(ship: Node3D, _level: int) -> void:
	if not is_instance_valid(ship):
		return
	_refresh_support_fleet_upgrade_state(ship)
	if ship.has_method("_spawn_or_repair_ally"):
		ship.call_deferred("_spawn_or_repair_ally")
		print("[Support] 지원함 소집 발동!")
		return
	print("[Support] 지원함 소집은 플레이어 함선에서만 사용할 수 있습니다.")

func _apply_fleet_crew(ship: Node3D, level: int) -> void:
	if not is_instance_valid(ship):
		return
	_refresh_support_fleet_upgrade_state(ship)
	var stats: Dictionary = UPGRADES["fleet_crew"].get("stats", {})
	var reduce_levels: int = mini(level, int(stats.get("respawn_reduce_max_level", 4)))
	var reduce_per_level: float = float(stats.get("respawn_reduce_per_lv", 4.0))
	var min_respawn_interval: float = float(stats.get("min_respawn_interval", 14.0))
	var base_interval: float = float(ship.get_meta("base_support_fleet_respawn_interval", ship.support_fleet_respawn_interval))
	var next_respawn_interval: float = maxf(min_respawn_interval, base_interval - (reduce_per_level * float(reduce_levels)))
	if "support_fleet_respawn_timer" in ship and "support_fleet_respawn_interval" in ship:
		if float(ship.support_fleet_respawn_timer) >= float(ship.support_fleet_respawn_interval):
			ship.support_fleet_respawn_timer = 0.0
			if ship.has_method("_spawn_or_repair_ally") and int(current_levels.get("fleet_signal", 0)) > 0:
				ship.call_deferred("_spawn_or_repair_ally")
	if level >= int(stats.get("limit_add_level", 5)):
		if ship.has_method("_spawn_or_repair_ally") and int(current_levels.get("fleet_signal", 0)) > 0:
			ship.call_deferred("_spawn_or_repair_ally")
	print("[Support] 지원함 재합류 강화 Lv.%d (재합류 %.0f초)" % [level, next_respawn_interval])


func _get_player_ship() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var direct_player = tree.root.find_child("PlayerShip", true, false)
	if is_instance_valid(direct_player) and direct_player is Node3D and direct_player.get("is_player_controlled") == true:
		return direct_player
	var players = SceneGroupCache.get_nodes(tree, "player")
	for p in players:
		if is_instance_valid(p) and p.get("is_player_controlled") == true:
			return p
	if players.size() > 0:
		return players[0]
	return null

func _apply_relic_to_ship(relic_id: String, ship: Node3D) -> void:
	var method_name = "_apply_relic_%s" % relic_id
	if has_method(method_name):
		call(method_name, ship)


func add_relic(relic_id: String) -> void:
	if relic_id not in RELICS:
		push_warning("UpgradeManager: 존재하지 않는 렐릭 ID입니다 - %s" % relic_id)
		return

	if acquired_relics.has(relic_id):
		var existing_ship = _get_player_ship()
		if existing_ship:
			# 이미 획득한 렐릭이어도 현재 본선에는 효과를 재적용한다.
			_apply_relic_to_ship(relic_id, existing_ship)
			refresh_hud_relic_icons()
		return
	
	acquired_relics.append(relic_id)
	if is_instance_valid(SaveManager) and SaveManager.has_method("add_relic"):
		SaveManager.add_relic(relic_id)

	var relic_data = RELICS[relic_id]
	var ship = _get_player_ship()
	if ship:
		_apply_relic_to_ship(relic_id, ship)
		refresh_hud_relic_icons()
		var hud = ship._find_hud() if ship.has_method("_find_hud") else null
		if hud and "alert_msg" in relic_data and hud.has_method("show_message"):
			hud.show_message(relic_data["alert_msg"], 3.0)
			
	print("[Relic] %s 획득! - %s" % [relic_data["name"], relic_data["description"]])

func grant_final_boss_relic() -> void:
	if acquired_relics.has("choyogi") == false:
		add_relic("choyogi")
		return
	if acquired_relics.has("ilseongjeongsiui") == false:
		add_relic("ilseongjeongsiui")
		return
	add_relic("boss_heart")

	# === 렐릭 적용 함수들 ===

func _apply_relic_sextant(ship: Node3D) -> void:
	if "has_sextant" in ship:
		ship.has_sextant = true

func _apply_relic_boss_heart(ship: Node3D) -> void:
	if ship.has_meta("relic_boss_heart_applied"):
		return
	ship.set_meta("relic_boss_heart_applied", true)
	if "max_hull_hp" in ship:
		ship.max_hull_hp += 60.0
	if "hull_hp" in ship and "max_hull_hp" in ship:
		ship.hull_hp = minf(ship.hull_hp + 60.0, ship.max_hull_hp)
	if "hull_defense" in ship:
		ship.hull_defense += 2.0
	_update_relic_ship_hud(ship)

func _apply_relic_choyogi(ship: Node3D) -> void:
	if ship.has_meta("relic_choyogi_applied"):
		return
	ship.set_meta("relic_choyogi_applied", true)
	_refresh_support_fleet_upgrade_state(ship)
	if ship.has_method("_spawn_or_repair_ally"):
		ship.call_deferred("_spawn_or_repair_ally")

func _apply_relic_ilseongjeongsiui(ship: Node3D) -> void:
	if ship.has_meta("relic_ilseongjeongsiui_applied"):
		return
	ship.set_meta("relic_ilseongjeongsiui_applied", true)
	if "has_sextant" in ship:
		ship.has_sextant = true

func _update_relic_ship_hud(ship: Node3D) -> void:
	if not ship.has_method("_find_hud"):
		return
	var hud = ship._find_hud()
	if hud and hud.has_method("update_hull_hp") and "hull_hp" in ship and "max_hull_hp" in ship:
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)

func _get_relic_icon_payload(relic_id: String, relic_data: Dictionary) -> Dictionary:
	var payload: Dictionary = {
		"relic_id": relic_id,
		"name": str(relic_data.get("name", relic_id)),
		"description": str(relic_data.get("description", "")),
		"icon_data": null,
	}
	if "icon_texture" in relic_data:
		var icon_texture_path: String = String(relic_data["icon_texture"])
		if not icon_texture_path.is_empty():
			payload["icon_data"] = icon_texture_path
			return payload
	if "icon" in relic_data:
		payload["icon_data"] = relic_data["icon"]
	return payload


## 지원함 업그레이드 일괄 적용 함수
func apply_fleet_upgrades_to_ship(ship: Node3D) -> void:
	if not is_instance_valid(ship): return
	
	# 1. 지원함 대포 업그레이드
	if "fleet_cannon" in current_levels:
		var lv = current_levels["fleet_cannon"]
		if ship.has_method("apply_fleet_weapon_upgrade"):
			ship.apply_fleet_weapon_upgrade(lv)
			
	# 2. 지원함 체력/방어력 업그레이드
	if "fleet_hull" in current_levels:
		var lv: int = int(current_levels["fleet_hull"])
		var s: Dictionary = UPGRADES["fleet_hull"].get("stats", {})
		if "max_hull_hp" in ship:
			var hp_add: float = float(s.get("hp_add", 100.0))
			var prev_level: int = int(ship.get_meta("fleet_hull_level_applied", 0))
			var base_hp: float
			if ship.has_meta("fleet_base_hull_hp"):
				base_hp = float(ship.get_meta("fleet_base_hull_hp"))
			else:
				base_hp = float(ship.max_hull_hp)
				ship.set_meta("fleet_base_hull_hp", base_hp)
			var next_max_hp: float = base_hp + (hp_add * lv)
			ship.max_hull_hp = next_max_hp
			if lv > prev_level:
				ship.hull_hp = minf(ship.hull_hp + (hp_add * float(lv - prev_level)), ship.max_hull_hp)
			else:
				ship.hull_hp = minf(ship.hull_hp, ship.max_hull_hp)
			ship.set_meta("fleet_hull_level_applied", lv)
		if "hull_defense" in ship:
			var def_per_lv: float = float(s.get("def_per_lv", 5.0))
			var base_defense: float
			if ship.has_meta("fleet_base_hull_defense"):
				base_defense = float(ship.get_meta("fleet_base_hull_defense"))
			else:
				base_defense = float(ship.hull_defense)
				ship.set_meta("fleet_base_hull_defense", base_defense)
			ship.hull_defense = base_defense + (def_per_lv * lv)
			
func _refresh_support_fleet_upgrade_state(ship: Node3D) -> void:
	if not is_instance_valid(ship):
		return
	var level: int = int(current_levels.get("fleet_crew", 0))
	var stats: Dictionary = UPGRADES.get("fleet_crew", {}).get("stats", {})
	if "support_fleet_respawn_interval" in ship:
		var base_interval: float = float(ship.get_meta("base_support_fleet_respawn_interval", ship.support_fleet_respawn_interval))
		if not ship.has_meta("base_support_fleet_respawn_interval"):
			ship.set_meta("base_support_fleet_respawn_interval", base_interval)
		var reduce_levels: int = mini(level, int(stats.get("respawn_reduce_max_level", 4)))
		var reduce_per_level: float = float(stats.get("respawn_reduce_per_lv", 4.0))
		var min_respawn_interval: float = float(stats.get("min_respawn_interval", 14.0))
		ship.support_fleet_respawn_interval = maxf(min_respawn_interval, base_interval - (reduce_per_level * float(reduce_levels)))
	if "support_fleet_limit" in ship:
		var base_limit: int = int(ship.get_meta("base_support_fleet_limit", ship.support_fleet_limit))
		if not ship.has_meta("base_support_fleet_limit"):
			ship.set_meta("base_support_fleet_limit", base_limit)
		var relic_bonus: int = 1 if bool(ship.get_meta("relic_choyogi_applied", false)) else 0
		var upgrade_bonus: int = 0
		if level >= int(stats.get("limit_add_level", 5)):
			upgrade_bonus = int(stats.get("limit_add", 1))
		ship.support_fleet_limit = base_limit + relic_bonus + upgrade_bonus


func _get_player_soldiers(ship: Node3D) -> Array:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return []
	var result = []
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != null:
			result.append(child)
	return result
