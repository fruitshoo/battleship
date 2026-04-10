@tool
extends Node
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const ItemDataResource = preload("res://scripts/resource_types/item_data.gd")
const UpgradeManagerChoiceHelper = preload("res://scripts/managers/upgrade_manager_choice_helper.gd")
const UpgradeManagerDataHelper = preload("res://scripts/managers/upgrade_manager_data_helper.gd")
const UpgradeManagerItemHelper = preload("res://scripts/managers/upgrade_manager_item_helper.gd")

## 업그레이드 매니저 (AutoLoad)
## 업그레이드 데이터 및 적용 로직 관리

signal upgrade_applied(upgrade_id: String, new_level: int)

# 업그레이드 정의
# 업그레이드 카테고리
enum Category {ANTI_SHIP, ANTI_PERSONNEL, HULL, SEAMANSHIP, SPECIAL, FLEET}

# 업그레이드 정의 (JSON에서 로드됨)
var UPGRADES = {}

# 아이템 정의 (리소스에서 로드됨, JSON은 fallback)
var ITEMS = {}

const DATA_PATH = "res://data/upgrades.json"
const ITEM_DATA_DIR = "res://resources/items"


# 현재 업그레이드 레벨 추적
var current_levels: Dictionary = {}

# 획득한 아이템(아이템) 목록
var acquired_items: Array[String] = []

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
	"crew_reserve",
	"boarding_resist",
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
	_sync_items_from_save()

func reset_run_upgrades() -> void:
	for key in UPGRADES:
		current_levels[key] = 0

func _sync_items_from_save() -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(SaveManager) and SaveManager.has_method("get_items"):
		acquired_items = SaveManager.get_items()

## 데이터 로드 (업그레이드는 JSON, 아이템은 리소스 우선)
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
				
	if not _load_items_from_resources() and data.has("items"):
		ITEMS = data["items"]

	print("[UpgradeManager] 데이터를 성공적으로 로드했습니다: %d개의 업그레이드, %d개의 아이템" % [UPGRADES.size(), ITEMS.size()])

func _load_items_from_resources() -> bool:
	return UpgradeManagerItemHelper.load_items_from_resources(self)

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

func equip_owned_items() -> void:
	UpgradeManagerItemHelper.equip_owned_items(self)

func refresh_hud_item_icons() -> void:
	UpgradeManagerItemHelper.refresh_hud_item_icons(self)

func get_ship_upgrade_choices(count: int = 3) -> Array:
	return UpgradeManagerChoiceHelper.build_ship_upgrade_choices(
		UPGRADES,
		current_levels,
		SHIP_UPGRADE_IDS,
		SUPPORT_SHIP_UPGRADE_IDS,
		RARE_FLEET_UPGRADE_ID,
		RARE_FLEET_UPGRADE_CHANCE,
		_is_fleet_progress_available(),
		count
	)

func get_command_upgrade_choices(count: int = 3) -> Array:
	return UpgradeManagerChoiceHelper.build_command_upgrade_choices(
		UPGRADES,
		current_levels,
		CREW_UPGRADE_IDS,
		SUPPORT_CREW_UPGRADE_IDS,
		_is_fleet_progress_available(),
		count
	)

func _is_fleet_progress_available() -> bool:
	# 지원 함대를 해금했거나 이미 함대 강화가 시작됐으면 지휘 선택지에 함대 강화를 노출한다.
	if int(current_levels.get(RARE_FLEET_UPGRADE_ID, 0)) > 0:
		return true
	for upgrade_id in ACTIVE_SUPPORT_UPGRADE_IDS:
		if int(current_levels.get(upgrade_id, 0)) > 0:
			return true
	return EntityRegistry.count_captured_minions() > 0

func _collect_choices_from_ids(ids: Array[String], count: int) -> Array:
	return UpgradeManagerChoiceHelper.collect_choices_from_ids(UPGRADES, current_levels, ids, count)

func get_specialist_unit_count(upgrade_id: String, level: int = -1) -> int:
	return UpgradeManagerDataHelper.get_specialist_unit_count(UPGRADES, current_levels, upgrade_id, level)

func get_supply_bonus_stats(level: int = -1) -> Dictionary:
	return UpgradeManagerDataHelper.get_supply_bonus_stats(UPGRADES, current_levels, level)

func get_player_crew_roster(total_crew: int) -> Dictionary:
	return UpgradeManagerDataHelper.get_player_crew_roster(UPGRADES, current_levels, total_crew)

func _is_upgrade_available(upgrade_id: String) -> bool:
	return UpgradeManagerChoiceHelper.is_upgrade_available(UPGRADES, current_levels, upgrade_id)

func _maybe_add_rare_fleet_upgrade(choices: Array, count: int) -> void:
	UpgradeManagerChoiceHelper.maybe_add_rare_fleet_upgrade(
		UPGRADES,
		current_levels,
		choices,
		count,
		RARE_FLEET_UPGRADE_ID,
		RARE_FLEET_UPGRADE_CHANCE
	)

func _fill_with_fallbacks(choices: Array, count: int) -> void:
	UpgradeManagerChoiceHelper.fill_with_fallbacks(choices, count)


## 랜덤 선택지 반환
func get_random_choices(count: int = 3, category_filter: int = -1) -> Array:
	if category_filter == -1:
		return get_ship_upgrade_choices(count)
	if category_filter == Category.FLEET:
		return get_command_upgrade_choices(count)
	return UpgradeManagerChoiceHelper.build_random_choices(UPGRADES, current_levels, count, category_filter)

func _level_matches(level: int, level_list: Variant) -> bool:
	return UpgradeManagerDataHelper.level_matches(level, level_list)

func _sort_choices_by_preferred_order(choices: Array, preferred_ids: Array[String]) -> void:
	UpgradeManagerChoiceHelper.sort_choices_by_preferred_order(choices, preferred_ids)


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
		var minions = EntityRegistry.get_captured_minions()
		for m in minions:
			apply_fleet_upgrades_to_ship(m)
	
	print("[Upgrade] 업그레이드 적용: %s Lv.%d" % [UPGRADES[upgrade_id]["name"], new_level])
	
	# HUD 업그레이드 슬롯 갱신 (함선/병사 트랙 분리)
	var ship_ui_ids = ["cannon", "janggun", "hull_defense", "sailing", "rowing", "supply_bonus", "fleet_signal", "fleet_cannon", "fleet_hull", "supply", "gold"]
	var crew_ui_ids = ["crew_numbers", "crew_reserve", "boarding_resist", "crew_attack", "crew_defense", "singigeon", "fire_pot", "repeating_crossbow", "fleet_crew"]
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

func _apply_crew_numbers(ship: Node3D, level: int) -> void:
	var stats = UPGRADES["crew_numbers"].get("stats", {})
	var thresholds = stats.get("specialist_levels", [1, 3, 5])
	if level in thresholds:
		ship.max_crew_count += 1

	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[CrewFormation] 전열 편성 갱신! (Lv.%d, 정원: %d)" % [level, ship.max_crew_count])

func _apply_crew_reserve(ship: Node3D, level: int) -> void:
	var stats: Dictionary = UPGRADES["crew_reserve"].get("stats", {})
	if "crew_respawn_interval" in ship:
		var base_interval: float = float(ship.get_meta("base_crew_respawn_interval", ship.crew_respawn_interval))
		if not ship.has_meta("base_crew_respawn_interval"):
			ship.set_meta("base_crew_respawn_interval", base_interval)
		var reduce_per_level: float = float(stats.get("respawn_reduce_per_lv", 0.75))
		var min_interval: float = float(stats.get("min_respawn_interval", 9.0))
		ship.crew_respawn_interval = maxf(min_interval, base_interval - (reduce_per_level * float(level)))
	if "crew_respawn_timer" in ship:
		ship.crew_respawn_timer = minf(float(ship.crew_respawn_timer), float(ship.crew_respawn_interval))
	ship.set_meta("survivor_hull_heal_bonus", float(stats.get("survivor_hull_heal_per_lv", 0.5)) * float(level))
	if _level_matches(level, stats.get("instant_restore_levels", [])) and ship.has_method("get_alive_crew_count") and "max_crew_count" in ship:
		if int(ship.call("get_alive_crew_count")) < int(ship.max_crew_count) and ship.has_method("add_survivor"):
			ship.add_survivor()
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[CrewReserve] 예비 병력 Lv.%d (보충 %.1fs)" % [level, float(ship.get("crew_respawn_interval")) if ship.get("crew_respawn_interval") != null else 0.0])

func _apply_boarding_resist(ship: Node3D, level: int) -> void:
	var stats: Dictionary = UPGRADES["boarding_resist"].get("stats", {})
	var duration_bonus: float = float(stats.get("capture_duration_mult_per_lv", 0.14)) * float(level)
	var capture_damage_reduction: float = float(stats.get("capture_damage_reduction_per_lv", 0.08)) * float(level)
	var boarding_fire_reduction: float = float(stats.get("boarding_fire_reduce_per_lv", 0.12)) * float(level)
	ship.set_meta("boarding_capture_duration_multiplier", 1.0 + duration_bonus)
	ship.set_meta("boarding_capture_damage_reduction", clampf(capture_damage_reduction, 0.0, 0.75))
	ship.set_meta("boarding_fire_damage_reduction", clampf(boarding_fire_reduction, 0.0, 0.75))
	print("[BoardingResist] 갑판 방어 Lv.%d (장악 %.0f%% 지연)" % [level, duration_bonus * 100.0])

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
		soldier.apply_crew_role(str(soldier.crew_role))

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
		desired_names[str(slot["name"])] = true

	var named_nodes: Dictionary = {}
	for child in cannons_node.get_children():
		if not is_instance_valid(child):
			continue
		var child_name := str(child.name)
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
		var node_name := str(slot["name"])
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
		if str(child.name).contains("Hull"):
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
		if str(child.name) != "Cannons":
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
	
	var stats = UPGRADES["singigeon"].get("stats", {})
	var thresholds = stats.get("specialist_levels", [1, 3, 5])
	if level in thresholds:
		ship.max_crew_count += 1
		
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[Singigeon] 신기전병 편성 갱신! (Lv.%d, 정원: %d)" % [level, ship.max_crew_count])


func _apply_janggun(ship: Node3D, level: int) -> void:
	if level == 1:
		var launcher = janggun_scene.instantiate()
		launcher.name = "JanggunLauncher"
		ship.add_child(launcher)
		launcher.position = Vector3(0, 0.8, 2.0)
	else:
		print("[Janggun] 장군전 화력 및 디버프 강화! (Lv.%d)" % level)


func _apply_fire_pot(ship: Node3D, level: int) -> void:
	var stats = UPGRADES["fire_pot"].get("stats", {})
	var thresholds = stats.get("specialist_levels", [1, 3, 5])
	if level in thresholds:
		ship.max_crew_count += 1
		
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[FirePot] 화통병 편성 갱신! (Lv.%d, 정원: %d)" % [level, ship.max_crew_count])


var repeating_crossbow_scene: PackedScene = preload("res://scenes/entities/weapons/weapon_repeating_crossbow.tscn")

func _apply_repeating_crossbow(ship: Node3D, level: int) -> void:
	var stats = UPGRADES["repeating_crossbow"].get("stats", {})
	var thresholds = stats.get("specialist_levels", [1, 3, 5])
	if level in thresholds:
		ship.max_crew_count += 1
		
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[RepeatingCrossbow] 연노병 편성 갱신! (Lv.%d, 정원: %d)" % [level, ship.max_crew_count])


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
	var level_mgr = LevelManagerRegistry.get_level_manager(get_tree())
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
	if _should_skip_support_fleet_autospawn():
		print("[Support] 지원함 자동 소환 건너뜀 (probe)")
		return
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
	var reduce_per_level: float = float(stats.get("respawn_reduce_per_lv", 3.0))
	var min_respawn_interval: float = float(stats.get("min_respawn_interval", 18.0))
	var base_interval: float = float(ship.get_meta("base_support_fleet_respawn_interval", ship.support_fleet_respawn_interval))
	var next_respawn_interval: float = maxf(min_respawn_interval, base_interval - (reduce_per_level * float(reduce_levels)))
	if "support_fleet_respawn_timer" in ship and "support_fleet_respawn_interval" in ship:
		if float(ship.support_fleet_respawn_timer) >= float(ship.support_fleet_respawn_interval):
			ship.support_fleet_respawn_timer = 0.0
			if not _should_skip_support_fleet_autospawn() and ship.has_method("_spawn_or_repair_ally") and int(current_levels.get("fleet_signal", 0)) > 0:
				ship.call_deferred("_spawn_or_repair_ally")
	if level >= int(stats.get("limit_add_level", 5)):
		if not _should_skip_support_fleet_autospawn() and ship.has_method("_spawn_or_repair_ally") and int(current_levels.get("fleet_signal", 0)) > 0:
			ship.call_deferred("_spawn_or_repair_ally")
	print("[Support] 지원함 재합류 강화 Lv.%d (재합류 %.0f초)" % [level, next_respawn_interval])


func _get_player_ship() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var direct_player = tree.root.find_child("PlayerShip", true, false)
	if is_instance_valid(direct_player) and direct_player is Node3D and direct_player.get("is_player_controlled") == true:
		return direct_player
	var players = EntityRegistry.get_ships_by_team("player")
	for p in players:
		if is_instance_valid(p) and p.get("is_player_controlled") == true:
			return p
	if players.size() > 0:
		return players[0]
	return null

func _apply_item_to_ship(item_id: String, ship: Node3D) -> void:
	var method_name = "_apply_item_%s" % item_id
	if has_method(method_name):
		call(method_name, ship)


func add_item(item_id: String) -> void:
	UpgradeManagerItemHelper.add_item(self, item_id)

func grant_final_boss_item() -> void:
	if acquired_items.has("choyogi") == false:
		add_item("choyogi")
		return
	if acquired_items.has("ilseongjeongsiui") == false:
		add_item("ilseongjeongsiui")
		return
	add_item("boss_heart")

	# === 아이템 적용 함수들 ===

func _apply_item_sextant(ship: Node3D) -> void:
	if "has_sextant" in ship:
		ship.has_sextant = true

func _apply_item_boss_heart(ship: Node3D) -> void:
	if ship.has_meta("item_boss_heart_applied"):
		return
	ship.set_meta("item_boss_heart_applied", true)
	if "max_hull_hp" in ship:
		ship.max_hull_hp += 60.0
	if "hull_hp" in ship and "max_hull_hp" in ship:
		ship.hull_hp = minf(ship.hull_hp + 60.0, ship.max_hull_hp)
	if "hull_defense" in ship:
		ship.hull_defense += 2.0
	_update_item_ship_hud(ship)

func _apply_item_choyogi(ship: Node3D) -> void:
	if ship.has_meta("item_choyogi_applied"):
		return
	ship.set_meta("item_choyogi_applied", true)
	_refresh_support_fleet_upgrade_state(ship)
	if not _should_skip_support_fleet_autospawn() and ship.has_method("_spawn_or_repair_ally"):
		ship.call_deferred("_spawn_or_repair_ally")

func _apply_item_ilseongjeongsiui(ship: Node3D) -> void:
	if ship.has_meta("item_ilseongjeongsiui_applied"):
		return
	ship.set_meta("item_ilseongjeongsiui_applied", true)
	if "has_sextant" in ship:
		ship.has_sextant = true

func _update_item_ship_hud(ship: Node3D) -> void:
	if not ship.has_method("_find_hud"):
		return
	var hud = ship._find_hud()
	if hud and hud.has_method("update_hull_hp") and "hull_hp" in ship and "max_hull_hp" in ship:
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)


func _should_skip_support_fleet_autospawn() -> bool:
	return _env_flag_enabled("BATTLESHIP_DISABLE_SUPPORT_FLEET_AUTOSPAWN")


func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"

func _get_item_icon_payload(item_id: String, item_data: Dictionary) -> Dictionary:
	return UpgradeManagerItemHelper.get_item_icon_payload(item_id, item_data)


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
		var reduce_per_level: float = float(stats.get("respawn_reduce_per_lv", 3.0))
		var min_respawn_interval: float = float(stats.get("min_respawn_interval", 18.0))
		ship.support_fleet_respawn_interval = maxf(min_respawn_interval, base_interval - (reduce_per_level * float(reduce_levels)))
	if "support_fleet_limit" in ship:
		var base_limit: int = int(ship.get_meta("base_support_fleet_limit", ship.support_fleet_limit))
		if not ship.has_meta("base_support_fleet_limit"):
			ship.set_meta("base_support_fleet_limit", base_limit)
		var item_bonus: int = 1 if ship.get_meta("item_choyogi_applied", false) == true else 0
		var upgrade_bonus: int = 0
		if level >= int(stats.get("limit_add_level", 5)):
			upgrade_bonus = int(stats.get("limit_add", 1))
		ship.support_fleet_limit = base_limit + item_bonus + upgrade_bonus


func _get_player_soldiers(ship: Node3D) -> Array:
	var soldiers_node = ship.get_node_or_null("Soldiers")
	if not soldiers_node:
		return []
	var result = []
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != null:
			result.append(child)
	return result
