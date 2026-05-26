@tool
extends Node
const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")
const UpgradeManagerItemHelper = preload("res://scripts/managers/upgrade_manager_item_helper.gd")
const PlayerShipSupportHelper = preload("res://scripts/entities/ships/player_ship_support_helper.gd")
const SeaSiteRewardHelper = preload("res://scripts/world/sea_sites/sea_site_reward_helper.gd")

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
const ITEM_SYSTEM_ENABLED := false


# 현재 업그레이드 레벨 추적
var current_levels: Dictionary = {}

# 획득한 아이템(아이템) 목록
var acquired_items: Array[String] = []

# 프리로드
var soldier_scene: PackedScene = preload("res://scenes/entities/soldiers/soldier.tscn")
var cannon_scene: PackedScene = preload("res://scenes/entities/launchers/cannon_joseon.tscn")
var default_cannonball_scene: PackedScene = preload("res://scenes/projectiles/cannonball.tscn")
var janggun_scene: PackedScene = preload("res://scenes/entities/launchers/janggun_launcher.tscn")
var ballista_scene: PackedScene = preload("res://scenes/entities/launchers/ballista_launcher.tscn")
var geobukseon_hull_scene: PackedScene = preload("res://scenes/ships/hulls/geobukseon_hull.tscn")

const SHIP_UPGRADE_IDS: Array[String] = [
	"cannon",
	"front_cannon",
	"cannon_damage",
	"cannon_reload",
	"janggun",
	"hull",
	"hull_defense",
	"hull_repair",
	"sailing",
	"rowing",
	"supply_bonus",
	"geobukseon",
	"fleet_signal",
]
const CREW_UPGRADE_IDS: Array[String] = [
	"crew_numbers",
	"boarding_resist",
	"crew_defense",
	"singigeon",
	"fire_pot",
]
const PRIORITY_SHIP_UPGRADE_IDS: Array[String] = [
	"cannon",
	"front_cannon",
	"cannon_damage",
	"janggun",
]
const PRIORITY_CREW_UPGRADE_IDS: Array[String] = [
	"boarding_resist",
]
const PANOKSEON_SUPPORT_UPGRADE_ID: String = "panokseon_upgrade"
const GEOBUKSEON_SUPPORT_UPGRADE_ID: String = "geobukseon_upgrade"
const SUPPORT_SHIP_UPGRADE_IDS: Array[String] = [
	PANOKSEON_SUPPORT_UPGRADE_ID,
	GEOBUKSEON_SUPPORT_UPGRADE_ID,
]
const SUPPORT_CREW_UPGRADE_IDS: Array[String] = []
const ACTIVE_SUPPORT_UPGRADE_IDS: Array[String] = [
	PANOKSEON_SUPPORT_UPGRADE_ID,
	GEOBUKSEON_SUPPORT_UPGRADE_ID,
]
const SUPPORT_SHIP_PROGRESS_MIN_LEVELS: int = 5
const FLEET_SIGNAL_UPGRADE_ID: String = "fleet_signal"
const TREASURE_REWARD_EXCLUDED_IDS: Array[String] = [
	"supply",
	"gold",
]
const TREASURE_REWARD_ROLL_COUNTS: Array[int] = [
	1,
	3,
	5,
]
const TREASURE_REWARD_ROLL_WEIGHTS: Array[float] = [
	0.55,
	0.35,
	0.10,
]
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
	# 기본 좌우 포문은 업그레이드 선택 전부터 장착된 시작 무장이다.
	if current_levels.has("cannon"):
		current_levels["cannon"] = 1

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
		_apply_cannon(ship, 1)
	upgrade_applied.emit("cannon", 1)
	var hud = ship._find_hud() if ship != null and ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_weapon_ui"):
		hud.update_weapon_ui("cannon", 1)

func equip_owned_items() -> void:
	UpgradeManagerItemHelper.equip_owned_items(self)

func refresh_hud_item_icons() -> void:
	UpgradeManagerItemHelper.refresh_hud_item_icons(self)

func is_item_system_enabled() -> bool:
	return ITEM_SYSTEM_ENABLED

func get_ship_upgrade_choices(count: int = 3) -> Array:
	return UpgradeManagerChoiceHelper.build_ship_upgrade_choices(
		UPGRADES,
		current_levels,
		_get_run_upgrade_ids(),
		_get_available_support_ship_upgrade_ids(),
		_get_priority_run_upgrade_ids(),
		_are_support_ship_choices_available(),
		count
	)

func get_command_upgrade_choices(count: int = 3) -> Array:
	return get_ship_upgrade_choices(count)

func _is_fleet_progress_available() -> bool:
	# 지원 함대를 해금했거나 이미 함대 강화가 시작됐으면 백병전 선택지에 함대 강화를 노출한다.
	if int(current_levels.get(FLEET_SIGNAL_UPGRADE_ID, 0)) > 0:
		return true
	for upgrade_id in ACTIVE_SUPPORT_UPGRADE_IDS:
		if int(current_levels.get(upgrade_id, 0)) > 0:
			return true
	return EntityRegistry.count_support_ships() > 0 or EntityRegistry.count_legacy_captured_ships() > 0


func _is_fleet_ship_progress_available() -> bool:
	if not _is_fleet_progress_available():
		return false
	return _get_non_fleet_progress_levels() >= SUPPORT_SHIP_PROGRESS_MIN_LEVELS


func _are_support_ship_choices_available() -> bool:
	return _is_fleet_ship_progress_available() or _is_panokseon_upgrade_choice_available() or _is_geobukseon_upgrade_choice_available()


func _is_panokseon_upgrade_choice_available() -> bool:
	return true


func _is_geobukseon_upgrade_choice_available() -> bool:
	return false


func _get_available_support_ship_upgrade_ids() -> Array[String]:
	var support_ids: Array[String] = []
	for upgrade_id in SUPPORT_SHIP_UPGRADE_IDS:
		if upgrade_id == PANOKSEON_SUPPORT_UPGRADE_ID:
			if _is_panokseon_upgrade_choice_available():
				support_ids.append(upgrade_id)
			continue
		if upgrade_id == GEOBUKSEON_SUPPORT_UPGRADE_ID:
			if _is_geobukseon_upgrade_choice_available():
				support_ids.append(upgrade_id)
			continue
		if _is_fleet_ship_progress_available():
			support_ids.append(upgrade_id)
	return support_ids


func _get_non_fleet_progress_levels() -> int:
	var total_levels := 0
	for upgrade_id in current_levels.keys():
		var upgrade_data: Dictionary = UPGRADES.get(upgrade_id, {})
		if upgrade_data.get("disabled", false) == true:
			continue
		if upgrade_id == FLEET_SIGNAL_UPGRADE_ID:
			continue
		if upgrade_id in ACTIVE_SUPPORT_UPGRADE_IDS:
			continue
		total_levels += int(current_levels.get(upgrade_id, 0))
	return total_levels


func _get_priority_ship_upgrade_ids() -> Array[String]:
	var priority_ids: Array[String] = []
	if int(current_levels.get("cannon", 0)) < 2:
		priority_ids.append("cannon")
	if int(current_levels.get("front_cannon", 0)) < 1 and int(current_levels.get("geobukseon", 0)) <= 0:
		priority_ids.append("front_cannon")
	if int(current_levels.get("cannon_damage", 0)) < 1:
		priority_ids.append("cannon_damage")
	if int(current_levels.get("janggun", 0)) < 2:
		priority_ids.append("janggun")
	return priority_ids


func _get_priority_crew_upgrade_ids() -> Array[String]:
	var priority_ids: Array[String] = []
	if int(current_levels.get("boarding_resist", 0)) < 2:
		priority_ids.append("boarding_resist")
	return priority_ids


func _get_run_upgrade_ids() -> Array[String]:
	var ids: Array[String] = SHIP_UPGRADE_IDS.duplicate()
	if int(current_levels.get("geobukseon", 0)) > 0:
		ids.erase("front_cannon")
	for upgrade_id in CREW_UPGRADE_IDS:
		if upgrade_id not in ids:
			ids.append(upgrade_id)
	return ids


func _get_priority_run_upgrade_ids() -> Array[String]:
	var ids: Array[String] = _get_priority_ship_upgrade_ids()
	for upgrade_id in _get_priority_crew_upgrade_ids():
		if upgrade_id not in ids:
			ids.append(upgrade_id)
	return ids

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

func get_treasure_upgrade_candidate_ids() -> Array[String]:
	var candidate_ids: Array[String] = []
	for upgrade_id in current_levels.keys():
		var id := str(upgrade_id)
		if id in TREASURE_REWARD_EXCLUDED_IDS:
			continue
		if id not in UPGRADES:
			continue
		var upgrade_data: Dictionary = UPGRADES[id]
		if upgrade_data.get("disabled", false) == true:
			continue
		var current_level := int(current_levels.get(id, 0))
		if current_level <= 0:
			continue
		if current_level >= int(upgrade_data.get("max_level", 0)):
			continue
		candidate_ids.append(id)
	return candidate_ids


func apply_treasure_upgrade_reward(forced_upgrade_count: int = -1) -> Dictionary:
	var requested_count := forced_upgrade_count if forced_upgrade_count > 0 else _roll_treasure_upgrade_count()
	var result := {
		"success": false,
		"requested_count": requested_count,
		"applied_count": 0,
		"upgrades": [],
	}
	var aggregate_by_id: Dictionary = {}
	for _i in range(requested_count):
		var candidates := get_treasure_upgrade_candidate_ids()
		if candidates.is_empty():
			break
		var upgrade_id := candidates[randi() % candidates.size()]
		var before_level := int(current_levels.get(upgrade_id, 0))
		apply_upgrade(upgrade_id)
		var after_level := int(current_levels.get(upgrade_id, before_level))
		if after_level <= before_level:
			continue
		var entry: Dictionary = aggregate_by_id.get(upgrade_id, {})
		if entry.is_empty():
			var upgrade_data: Dictionary = UPGRADES.get(upgrade_id, {})
			entry = {
				"upgrade_id": upgrade_id,
				"name": LocaleManager.data_text(upgrade_data, upgrade_id, "upgrade", "name", upgrade_id),
				"from_level": before_level,
				"to_level": after_level,
				"levels_added": after_level - before_level,
				"color": upgrade_data.get("color", Color.WHITE),
			}
		else:
			entry["to_level"] = after_level
			entry["levels_added"] = int(entry.get("levels_added", 0)) + after_level - before_level
		aggregate_by_id[upgrade_id] = entry
		result["applied_count"] = int(result["applied_count"]) + after_level - before_level

	var applied: Array = []
	for upgrade_id in aggregate_by_id.keys():
		applied.append(aggregate_by_id[upgrade_id])
	applied.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	result["upgrades"] = applied
	result["success"] = int(result["applied_count"]) > 0
	return result


func _roll_treasure_upgrade_count() -> int:
	var total_weight := 0.0
	for weight in TREASURE_REWARD_ROLL_WEIGHTS:
		total_weight += maxf(weight, 0.0)
	if total_weight <= 0.0:
		return TREASURE_REWARD_ROLL_COUNTS[0]
	var roll := randf() * total_weight
	var cursor := 0.0
	for i in range(TREASURE_REWARD_ROLL_COUNTS.size()):
		cursor += maxf(TREASURE_REWARD_ROLL_WEIGHTS[i], 0.0)
		if roll <= cursor:
			return TREASURE_REWARD_ROLL_COUNTS[i]
	return TREASURE_REWARD_ROLL_COUNTS.back()


func _fill_with_fallbacks(choices: Array, count: int) -> void:
	UpgradeManagerChoiceHelper.fill_with_fallbacks(choices, count)


## 랜덤 선택지 반환
func get_random_choices(count: int = 3, category_filter: int = -1) -> Array:
	if category_filter == -1:
		return get_ship_upgrade_choices(count)
	if category_filter == Category.FLEET:
		return get_ship_upgrade_choices(count)
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
	
	# 함대 업그레이드인 경우 현재 활성화된 지원함과 legacy 나포함에 즉시 적용
	if upgrade_id in ACTIVE_SUPPORT_UPGRADE_IDS or upgrade_id in ["cannon", "front_cannon", "hull", "hull_defense", "hull_repair"]:
		var fleet_ships: Array = EntityRegistry.get_support_ships()
		fleet_ships.append_array(EntityRegistry.get_legacy_captured_ships())
		for fleet_ship in fleet_ships:
			apply_fleet_upgrades_to_ship(fleet_ship)
	if upgrade_id == "boarding_resist":
		_apply_boarding_resist_to_player_fleet(new_level)
	
	print("[Upgrade] 업그레이드 적용: %s Lv.%d" % [LocaleManager.data_text(UPGRADES[upgrade_id], upgrade_id, "upgrade", "name", upgrade_id), new_level])
	
	# HUD 업그레이드 슬롯 갱신 (함선/병사 트랙 분리)
	var ship_ui_ids = ["cannon", "front_cannon", "cannon_damage", "cannon_reload", "janggun", "hull", "hull_defense", "hull_repair", "sailing", "rowing", "supply_bonus", "geobukseon", "fleet_signal", "panokseon_upgrade", "geobukseon_upgrade", "supply", "gold"]
	var crew_ui_ids = ["crew_numbers", "boarding_resist", "crew_defense", "singigeon", "fire_pot"]
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
	_refresh_player_crew_capacity(ship)

	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	for sol in _get_player_soldiers(ship):
		_apply_current_stats_to_soldier(sol)
	var stats: Dictionary = UPGRADES["crew_numbers"].get("stats", {})
	var spear_damage_add := float(level) * float(stats.get("damage_add_per_lv", 1.0))
	print("[CrewFormation] 장창 Lv.%d 갱신! (장창 피해 +%.0f, 정원: %d)" % [
		level,
		spear_damage_add,
		ship.max_crew_count,
	])

func _refresh_player_crew_capacity(ship: Node3D) -> void:
	if not is_instance_valid(ship) or not "max_crew_count" in ship:
		return
	var base_capacity: int = int(ship.get_meta("base_player_max_crew_count", ship.max_crew_count))
	if not ship.has_meta("base_player_max_crew_count"):
		ship.set_meta("base_player_max_crew_count", base_capacity)
	ship.max_crew_count = max(1, base_capacity)

func _apply_crew_reserve(ship: Node3D, level: int) -> void:
	var stats: Dictionary = UPGRADES["crew_reserve"].get("stats", {})
	var assist_duration: float = maxf(
		float(stats.get("min_assist_channel_duration", 0.55)),
		float(stats.get("base_assist_channel_duration", 1.1)) - (float(level) * float(stats.get("assist_channel_reduce_per_lv", 0.1)))
	)
	var assist_health_ratio: float = clampf(
		0.35 + (float(level) * float(stats.get("assist_recovery_health_add_per_lv", 0.07))),
		0.35,
		float(stats.get("max_assist_recovery_health_ratio", 0.7))
	)
	var assist_acquire_range: float = 4.6 + (float(level) * float(stats.get("assist_acquire_range_add_per_lv", 0.45)))
	var assist_use_range: float = 1.15 + (float(level) * float(stats.get("assist_use_range_add_per_lv", 0.04)))
	if ship.has_meta("incapacitated_recovery_delay"):
		ship.remove_meta("incapacitated_recovery_delay")
	if ship.has_meta("incapacitated_recovery_health_ratio"):
		ship.remove_meta("incapacitated_recovery_health_ratio")
	ship.set_meta("incapacitated_assist_channel_duration", assist_duration)
	ship.set_meta("incapacitated_assist_health_ratio", assist_health_ratio)
	ship.set_meta("incapacitated_assist_acquire_range", assist_acquire_range)
	ship.set_meta("incapacitated_assist_use_range", assist_use_range)
	if "crew_respawn_interval" in ship:
		var base_interval: float = float(ship.get_meta("base_crew_respawn_interval", ship.crew_respawn_interval))
		if not ship.has_meta("base_crew_respawn_interval"):
			ship.set_meta("base_crew_respawn_interval", base_interval)
		var reduce_per_level: float = float(stats.get("respawn_reduce_per_lv", 0.75))
		var min_interval: float = float(stats.get("min_respawn_interval", 9.0))
		ship.crew_respawn_interval = maxf(min_interval, base_interval - (reduce_per_level * float(level)))
	if "crew_respawn_timer" in ship:
		ship.crew_respawn_timer = minf(float(ship.crew_respawn_timer), float(ship.crew_respawn_interval))
	if _level_matches(level, stats.get("instant_restore_levels", [])) and ship.has_method("get_alive_crew_count") and "max_crew_count" in ship:
		_recover_incapacitated_player_soldiers(ship)
	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[CrewReserve] 구호 Lv.%d (일으키기 %.2fs, 회복 %.0f%%)" % [level, assist_duration, assist_health_ratio * 100.0])

func _recover_incapacitated_player_soldiers(ship: Node3D) -> int:
	var recovered_count := 0
	for soldier in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(soldier):
			continue
		if soldier.has_method("is_player_team_soldier") and not soldier.is_player_team_soldier():
			continue
		if soldier.has_method("is_incapacitated_soldier") and soldier.is_incapacitated_soldier():
			if soldier.has_method("heal_full"):
				soldier.heal_full()
				recovered_count += 1
	return recovered_count

func _apply_boarding_resist(ship: Node3D, level: int) -> void:
	_apply_boarding_resist_to_ship(ship, level)
	print("[BoardingResist] 창벽 Lv.%d (동시 도선 제한 -%d, 도선 피해 %.1f)" % [
		level,
		_get_boarding_resist_slot_penalty(level),
		_get_boarding_resist_transfer_damage(level),
	])


func _apply_boarding_resist_to_player_fleet(level: int) -> void:
	for player_ship in EntityRegistry.get_ships_by_team("player"):
		_apply_boarding_resist_to_ship(player_ship, level)


func _apply_boarding_resist_to_ship(ship: Node3D, level: int) -> void:
	if not is_instance_valid(ship):
		return
	_clear_legacy_boarding_resist_meta(ship)
	ship.set_meta("enemy_boarding_slot_penalty", _get_boarding_resist_slot_penalty(level))
	ship.set_meta("enemy_boarding_transfer_damage", _get_boarding_resist_transfer_damage(level))


func _clear_legacy_boarding_resist_meta(ship: Node3D) -> void:
	for meta_name in [
		"boarding_capture_duration_multiplier",
		"boarding_defense_damage_per_tick",
		"boarding_capture_damage_reduction",
		"boarding_fire_damage_reduction",
		"player_boarding_wave_limit_bonus",
		"enemy_boarding_interval_multiplier",
		"enemy_boarding_transfer_damage",
	]:
		if ship.has_meta(meta_name):
			ship.remove_meta(meta_name)


func _get_boarding_resist_slot_penalty(level: int) -> int:
	var stats: Dictionary = UPGRADES["boarding_resist"].get("stats", {})
	var penalty := 0
	for threshold in stats.get("enemy_boarding_slot_reduce_levels", [3, 5]):
		if level >= int(threshold):
			penalty += 1
	return penalty


func _get_boarding_resist_transfer_damage(level: int) -> float:
	var stats: Dictionary = UPGRADES["boarding_resist"].get("stats", {})
	return minf(
		float(stats.get("enemy_boarding_max_damage", 40.0)),
		float(level) * float(stats.get("enemy_boarding_damage_per_lv", 8.0))
	)

func _apply_ballista(ship: Node3D, _level: int) -> void:
	push_warning("UpgradeManager: ballista upgrade is disabled for current gameplay flow.")

func _apply_crew_attack(ship: Node3D, _level: int) -> void:
	var soldiers = _get_player_soldiers(ship)
	var attack_lv = current_levels.get("crew_attack", 0)
	for sol in soldiers:
		_apply_current_stats_to_soldier(sol)
	print("[Crew Attack] 무기 Lv.%d 완료!" % attack_lv)

func _apply_crew_defense(ship: Node3D, _level: int) -> void:
	var soldiers = _get_player_soldiers(ship)
	var defense_lv = current_levels.get("crew_defense", 0)
	for sol in soldiers:
		_apply_current_stats_to_soldier(sol)
	print("[Crew Defense] 갑옷 Lv.%d 완료!" % defense_lv)

func _apply_current_stats_to_soldier(soldier: Node) -> void:
	var spear_lv = int(current_levels.get("crew_numbers", 0))
	var defense_lv = int(current_levels.get("crew_defense", 0))
	var spear_stats: Dictionary = UPGRADES["crew_numbers"]["stats"]
	var defense_stats: Dictionary = UPGRADES["crew_defense"]["stats"]
	var damage_bonus_pct: float = 0.0
	var spear_damage_add: float = spear_lv * float(spear_stats.get("damage_add_per_lv", 1.0))
	var defense_flat_bonus: float = defense_lv * float(defense_stats.get("defense_add_per_lv", 1.0))
	damage_bonus_pct += _get_soldier_site_bonus_total(soldier, "crew_damage_pct")
	defense_flat_bonus += _get_soldier_site_bonus_total(soldier, "crew_defense_add")
	soldier.set_meta("damage_bonus_pct", damage_bonus_pct)
	if soldier.has_meta("attack_flat_bonus"):
		soldier.remove_meta("attack_flat_bonus")
	if soldier.has_meta("spear_damage_bonus_pct"):
		soldier.remove_meta("spear_damage_bonus_pct")
	soldier.set_meta("spear_damage_add", spear_damage_add)
	soldier.set_meta("defense_flat_bonus", defense_flat_bonus)
	if soldier.has_meta("damage_multiplier"):
		soldier.remove_meta("damage_multiplier")
	
	if soldier.has_method("apply_crew_role") and "crew_role" in soldier:
		soldier.apply_crew_role(str(soldier.crew_role))


func _get_soldier_site_bonus_total(soldier: Node, bonus_id: String) -> float:
	if not is_instance_valid(soldier):
		return 0.0
	var owned_ship: Variant = soldier.get("owned_ship")
	if is_instance_valid(owned_ship):
		return SeaSiteRewardHelper.get_site_bonus_total(owned_ship as Node, bonus_id)
	var home_ship: Variant = soldier.get("home_ship")
	if is_instance_valid(home_ship):
		return SeaSiteRewardHelper.get_site_bonus_total(home_ship as Node, bonus_id)
	return 0.0


func _apply_hull_defense(ship: Node3D, _level: int) -> void:
	var def_lv = current_levels.get("hull_defense", 0)
	var s = UPGRADES["hull_defense"]["stats"]
	if "hull_defense" in ship:
		var base_defense: float
		if ship.has_meta("base_player_hull_defense"):
			base_defense = float(ship.get_meta("base_player_hull_defense"))
		else:
			base_defense = float(ship.hull_defense)
			ship.set_meta("base_player_hull_defense", base_defense)
		var defense_bonus := 0.0
		for level_entry in s.get("def_levels", []):
			if int(level_entry) <= def_lv:
				defense_bonus += float(s.get("def_add", 2.0))
		ship.hull_defense = base_defense + defense_bonus + SeaSiteRewardHelper.get_site_bonus_total(ship, "hull_defense_add")
	ship.set_meta("crew_ranged_cover_defense_bonus", float(def_lv) * float(s.get("crew_ranged_cover_defense_add_per_lv", 0.5)))
	if "hull_hp" in ship and "max_hull_hp" in ship:
		ship.hull_hp = minf(ship.hull_hp, ship.max_hull_hp)

	NodeContractHelper.clear_hull_defense_upgrade_nodes(ship)
	
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	print("[Hull] 선체 장갑 강화 Lv.%d" % def_lv)


func _apply_hull(ship: Node3D, level: int) -> void:
	if not is_instance_valid(ship):
		return
	var stats: Dictionary = UPGRADES.get("hull", {}).get("stats", {})
	var hp_add_per_lv := float(stats.get("hp_add_per_lv", 15.0))
	var ram_pct_per_lv := float(stats.get("ramming_damage_pct_per_lv", 0.07))
	if "max_hull_hp" in ship:
		var base_max_hp: float
		if ship.has_meta("base_player_hull_upgrade_max_hp"):
			base_max_hp = float(ship.get_meta("base_player_hull_upgrade_max_hp"))
		else:
			base_max_hp = float(ship.max_hull_hp)
			ship.set_meta("base_player_hull_upgrade_max_hp", base_max_hp)
		var previous_max_hp := float(ship.max_hull_hp)
		var next_max_hp := base_max_hp + hp_add_per_lv * float(level)
		ship.max_hull_hp = next_max_hp
		if "hull_hp" in ship:
			var gained_hp := maxf(0.0, next_max_hp - previous_max_hp)
			ship.hull_hp = minf(next_max_hp, float(ship.hull_hp) + gained_hp)
	if "ramming_damage_multiplier" in ship:
		var base_ram_mult: float
		if ship.has_meta("base_player_hull_upgrade_ram_mult"):
			base_ram_mult = float(ship.get_meta("base_player_hull_upgrade_ram_mult"))
		else:
			base_ram_mult = float(ship.ramming_damage_multiplier)
			ship.set_meta("base_player_hull_upgrade_ram_mult", base_ram_mult)
		ship.ramming_damage_multiplier = base_ram_mult * (1.0 + ram_pct_per_lv * float(level))

	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp") and "hull_hp" in ship and "max_hull_hp" in ship:
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	print("[Hull] 선체 강화 Lv.%d (내구 +%.0f, 충돌 피해 +%.0f%%)" % [
		level,
		hp_add_per_lv * float(level),
		ram_pct_per_lv * float(level) * 100.0,
	])


func _apply_hull_repair(ship: Node3D, level: int) -> void:
	var stats: Dictionary = UPGRADES["hull_repair"].get("stats", {})
	var regen_rate: float = minf(
		float(stats.get("max_regen", 1.0)),
		float(level) * float(stats.get("regen_per_lv", 0.2))
	)
	regen_rate += SeaSiteRewardHelper.get_site_bonus_total(ship, "hull_regen_add")
	if "hull_regen_rate" in ship:
		ship.hull_regen_rate = regen_rate
	print("[HullRepair] 선체 자동 수리 Lv.%d (%.1f/s)" % [level, regen_rate])

func _apply_sailing(ship: Node3D, level: int) -> void:
	var s = UPGRADES["sailing"]["stats"]
	if _level_matches(level, s.get("speed_levels", [])) and "max_speed" in ship:
		ship.max_speed += float(s.get("speed_add", 1.0))
	if _level_matches(level, s.get("efficiency_levels", [])) and "sail_efficiency_mult" in ship:
		ship.sail_efficiency_mult *= float(s.get("efficiency_mult", 1.08))
	if _level_matches(level, s.get("turn_levels", [])) and "sail_turn_speed" in ship:
		ship.sail_turn_speed *= float(s.get("turn_mult", 1.15))
	if _level_matches(level, s.get("handling_levels", [])):
		var handling_mult := float(s.get("handling_mult", 1.15))
		if "sail_furl_rate" in ship:
			ship.sail_furl_rate *= handling_mult
		if "mast_fold_pivots" in ship and ship.get("mast_fold_pivots") is Array:
			for pivot in ship.get("mast_fold_pivots"):
				if is_instance_valid(pivot) and "fold_duration" in pivot:
					pivot.fold_duration = maxf(0.35, float(pivot.fold_duration) / handling_mult)
	print("[Sailing] 돛 운용 강화 Lv.%d" % level)

func _apply_rowing(ship: Node3D, level: int) -> void:
	var s = UPGRADES["rowing"]["stats"]
	if _level_matches(level, s.get("speed_levels", [])) and "rowing_speed" in ship:
		ship.rowing_speed += float(s.get("speed_add", 1.0))
	if _level_matches(level, s.get("accel_levels", [])) and "rowing_acceleration_mult" in ship:
		ship.rowing_acceleration_mult *= float(s.get("accel_mult", 1.2))
	if _level_matches(level, s.get("ram_boost_duration_levels", [])) and "ramming_boost_duration" in ship:
		ship.ramming_boost_duration = minf(3.0, ship.ramming_boost_duration + float(s.get("ram_boost_duration_add", 0.15)))
	if _level_matches(level, s.get("ram_boost_recharge_levels", [])) and "ramming_boost_recharge_duration" in ship:
		var recharge_mult := clampf(float(s.get("ram_boost_recharge_mult", 0.92)), 0.1, 1.0)
		var min_recharge_duration := maxf(1.0, float(s.get("ram_boost_min_recharge_duration", 8.0)))
		ship.ramming_boost_recharge_duration = maxf(min_recharge_duration, ship.ramming_boost_recharge_duration * recharge_mult)
	if _level_matches(level, s.get("stamina_add_levels", [])) and "max_rowing_stamina" in ship:
		var stamina_add := float(s.get("stamina_add", 25.0))
		ship.max_rowing_stamina += stamina_add
		if "rowing_stamina" in ship:
			ship.rowing_stamina = minf(ship.max_rowing_stamina, ship.rowing_stamina + stamina_add)
	if _level_matches(level, s.get("drain_levels", [])) and "stamina_drain_rate" in ship:
		ship.stamina_drain_rate *= float(s.get("drain_mult", 0.8))
	if _level_matches(level, s.get("recovery_levels", [])) and "stamina_recovery_rate" in ship:
		ship.stamina_recovery_rate *= float(s.get("recovery_mult", 1.25))
	print("[Rowing] 노 운용 강화 Lv.%d" % level)

func _apply_supply_bonus(ship: Node3D, level: int) -> void:
	print("[SupplyBonus] 보급 효율 강화 Lv.%d" % level)

func _apply_geobukseon(ship: Node3D, _level: int) -> void:
	if not is_instance_valid(ship):
		return
	var stats: Dictionary = UPGRADES.get("geobukseon", {}).get("stats", {})
	var ship_type_name := str(stats.get("ship_type", "geobukseon_player")).strip_edges()
	if ship_type_name.is_empty():
		ship_type_name = "geobukseon_player"
	var hull_scene_path := str(stats.get("hull_scene", "")).strip_edges()
	var hull_scene_to_apply := geobukseon_hull_scene
	if not hull_scene_path.is_empty():
		var loaded_hull := load(hull_scene_path)
		if loaded_hull is PackedScene:
			hull_scene_to_apply = loaded_hull as PackedScene

	var rig_state := _capture_player_rig_state(ship)
	if "ship_type" in ship:
		ship.ship_type = ship_type_name
	if "hull_scene" in ship:
		ship.hull_scene = hull_scene_to_apply
	if "blocks_boarding" in ship:
		ship.blocks_boarding = bool(stats.get("blocks_boarding", true))
	if "ship_mass_scale" in ship:
		ship.ship_mass_scale = clampf(float(stats.get("ship_mass_scale", 2.05)), 0.35, 4.0)
		if "collision_profile" in ship and ship.collision_profile != null:
			ship.collision_profile.ship_mass_scale = ship.ship_mass_scale
	if "ramming_damage_multiplier" in ship:
		var geobuk_ram_mult := maxf(0.1, float(stats.get("ramming_damage_multiplier", 1.2)))
		ship.set_meta("base_player_hull_upgrade_ram_mult", geobuk_ram_mult)
		var hull_stats: Dictionary = UPGRADES.get("hull", {}).get("stats", {})
		var hull_level := int(current_levels.get("hull", 0))
		ship.ramming_damage_multiplier = geobuk_ram_mult * (1.0 + float(hull_stats.get("ramming_damage_pct_per_lv", 0.07)) * float(hull_level))
	if "ramming_knockback_multiplier" in ship:
		ship.ramming_knockback_multiplier = clampf(float(stats.get("ramming_knockback_multiplier", 1.0)), 0.0, 3.0)
	if "ramming_boost_recharge_multiplier" in ship:
		ship.ramming_boost_recharge_multiplier = clampf(float(stats.get("ram_boost_recharge_mult", 1.0)), 0.1, 1.0)
	if "hull_defense" in ship:
		var geobuk_base_defense := maxf(0.0, float(stats.get("hull_defense", 2.0)))
		ship.set_meta("base_player_hull_defense", geobuk_base_defense)
		var def_stats: Dictionary = UPGRADES.get("hull_defense", {}).get("stats", {})
		var def_level := int(current_levels.get("hull_defense", 0))
		var defense_bonus := 0.0
		for level_entry in def_stats.get("def_levels", []):
			if int(level_entry) <= def_level:
				defense_bonus += float(def_stats.get("def_add", 1.0))
		ship.hull_defense = geobuk_base_defense + defense_bonus + SeaSiteRewardHelper.get_site_bonus_total(ship, "hull_defense_add")
	ship.set_meta("crew_ranged_cover_base_defense", maxf(0.0, float(stats.get("crew_ranged_cover_defense", 3.0))))

	_swap_player_hull_scene(ship, hull_scene_to_apply, "GeobukseonHull")
	if ship.has_method("_cache_hull_references"):
		ship.call("_cache_hull_references", ship)
	if ship.has_method("_apply_authored_deck_height_if_available"):
		ship.call("_apply_authored_deck_height_if_available")
	if ship.has_method("_refresh_collision_bounds_from_hull"):
		ship.call("_refresh_collision_bounds_from_hull")
	if ship.has_method("_sync_player_crew_roster"):
		ship.call("_sync_player_crew_roster")
	_restore_player_rig_state_after_hull_swap(ship, rig_state)

	_apply_geobukseon_transform_heal(ship, stats)
	_sync_player_cannon_layout(ship, maxi(1, int(current_levels.get("cannon", 1))))
	_play_geobukseon_transform_sfx(ship)
	print("[Geobukseon] 기함을 거북선으로 변경했습니다. 도선 면역, 측면 포문 전용")

func _capture_player_rig_state(ship: Node3D) -> Dictionary:
	if not is_instance_valid(ship):
		return {}
	var state := {
		"sail_furled": false,
		"sail_deployed_ratio": 1.0,
		"masts_folded": false,
		"mast_fold_ratio": 0.0,
	}
	if "sail_furled" in ship:
		state["sail_furled"] = bool(ship.get("sail_furled"))
	if "sail_deployed_ratio" in ship:
		state["sail_deployed_ratio"] = clampf(float(ship.get("sail_deployed_ratio")), 0.0, 1.0)
	if ship.has_method("are_masts_folded"):
		state["masts_folded"] = bool(ship.call("are_masts_folded"))
	elif "masts_folded" in ship:
		state["masts_folded"] = bool(ship.get("masts_folded"))
	if ship.has_method("get_mast_fold_ratio"):
		state["mast_fold_ratio"] = clampf(float(ship.call("get_mast_fold_ratio")), 0.0, 1.0)
	return state

func _restore_player_rig_state_after_hull_swap(ship: Node3D, rig_state: Dictionary) -> void:
	if not is_instance_valid(ship) or rig_state.is_empty():
		return
	var was_furled := bool(rig_state.get("sail_furled", false))
	var was_masts_folded := bool(rig_state.get("masts_folded", false))
	var previous_mast_fold_ratio := clampf(float(rig_state.get("mast_fold_ratio", 0.0)), 0.0, 1.0)
	var should_fold_masts := was_furled or was_masts_folded or previous_mast_fold_ratio >= 0.5
	var restored_sail_ratio := 0.0 if should_fold_masts else clampf(float(rig_state.get("sail_deployed_ratio", 1.0)), 0.0, 1.0)

	if "sail_furled" in ship:
		ship.set("sail_furled", was_furled)
	if "sail_deployed_ratio" in ship:
		ship.set("sail_deployed_ratio", restored_sail_ratio)
	if ship.has_method("set_masts_folded"):
		ship.call("set_masts_folded", should_fold_masts, true)
	elif "masts_folded" in ship:
		ship.set("masts_folded", should_fold_masts)
	if should_fold_masts:
		_set_player_mast_sail_ratio(ship, 0.0)
	elif ship.has_method("_sync_mast_fold_after_sail_deployment"):
		ship.call("_sync_mast_fold_after_sail_deployment")
	if ship.has_method("_update_sail_visual"):
		ship.call("_update_sail_visual")

func _set_player_mast_sail_ratio(ship: Node3D, ratio: float) -> void:
	if not is_instance_valid(ship) or not ("masts" in ship):
		return
	var masts: Array = ship.get("masts") if ship.get("masts") is Array else []
	for mast in masts:
		if is_instance_valid(mast) and mast.has_method("set_sail_deployed_ratio"):
			mast.call("set_sail_deployed_ratio", ratio)

func _apply_geobukseon_transform_heal(ship: Node3D, stats: Dictionary) -> void:
	if not is_instance_valid(ship):
		return
	if not ("hull_hp" in ship and "max_hull_hp" in ship):
		return
	var max_hull := maxf(1.0, float(ship.max_hull_hp))
	var before := clampf(float(ship.hull_hp), 0.0, max_hull)
	var min_ratio := clampf(float(stats.get("transform_hull_min_ratio", 0.5)), 0.0, 1.0)
	var after := maxf(before, max_hull * min_ratio)
	ship.hull_hp = minf(max_hull, after)
	var hud = ship._find_hud() if ship.has_method("_find_hud") else null
	if hud and hud.has_method("update_hull_hp"):
		hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)

func _play_geobukseon_transform_sfx(ship: Node3D) -> void:
	if not is_instance_valid(ship):
		return
	if not is_instance_valid(AudioManager) or not AudioManager.has_method("play_sfx"):
		return
	AudioManager.play_sfx("support_foghorn", ship.global_position)

func _swap_player_hull_scene(ship: Node3D, hull_scene_to_apply: PackedScene, hull_name: String) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(hull_scene_to_apply):
		return
	var old_hull: Node3D = null
	if ship.has_method("get_direct_hull_child"):
		var old_hull_variant: Variant = ship.call("get_direct_hull_child", true)
		old_hull = _as_valid_node3d(old_hull_variant)
	var insert_index := ship.get_child_count()
	var old_transform := Transform3D.IDENTITY
	if is_instance_valid(old_hull):
		insert_index = old_hull.get_index()
		old_transform = old_hull.transform
		if "deck_light" in ship and is_instance_valid(ship.deck_light) and old_hull.is_ancestor_of(ship.deck_light):
			ship.deck_light = null
		ship.remove_child(old_hull)
		old_hull.queue_free()

	var hull_instance := hull_scene_to_apply.instantiate() as Node3D
	if not is_instance_valid(hull_instance):
		return
	hull_instance.name = hull_name
	hull_instance.transform = old_transform
	ship.add_child(hull_instance)
	if insert_index < ship.get_child_count() - 1:
		ship.move_child(hull_instance, insert_index)

func _apply_cannon(ship: Node3D, level: int) -> void:
	var cannons_node := NodeContractHelper.ensure_cannons_container(ship)
	if not is_instance_valid(cannons_node):
		return
	_normalize_player_cannons(ship)
	_sync_player_cannon_layout(ship, maxi(1, level))
	print("[Cannon] 포문 배치 적용 (Lv.%d)" % level)

func _apply_front_cannon(ship: Node3D, level: int) -> void:
	NodeContractHelper.ensure_cannons_container(ship)
	_sync_player_cannon_layout(ship, maxi(1, int(current_levels.get("cannon", 1))))
	print("[Cannon] 전면 포문 배치 적용 (Lv.%d)" % level)

func _normalize_player_cannons(ship: Node3D) -> void:
	var cannons_node = _get_player_cannons_node(ship)
	if not is_instance_valid(cannons_node):
		return
	for child in cannons_node.get_children():
		_configure_player_cannon(child)

func _sync_player_cannon_layout(ship: Node3D, level: int) -> void:
	var effective_level := maxi(1, level)
	var cannons_node = _get_player_cannons_node(ship)
	if not is_instance_valid(cannons_node):
		return

	var authored_slots := ShipAuthoringHelper.get_named_weapon_slot_transforms(ship, cannons_node)
	var slot_specs := _get_player_cannon_loadout(ship)
	slot_specs = ShipWeaponLoadoutHelper.apply_authored_weapon_slots(ship, cannons_node, slot_specs)

	var desired_names: Dictionary = {}
	for slot in slot_specs:
		desired_names[ShipWeaponLoadoutHelper.get_node_name(slot)] = true

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

	# Hull scene에서 직접 손본 기본 포대 위치를 런타임 업그레이드 동기화가 덮어쓰지 않게 한다.
	# 명시적인 CannonSlots 마커가 있으면 그 마커가 최우선 authoring source다.
	for slot in slot_specs:
		var slot_name := ShipWeaponLoadoutHelper.get_slot_name(slot)
		var node_name := ShipWeaponLoadoutHelper.get_node_name(slot)
		var existing_cannon = named_nodes.get(node_name, null)
		var existing_cannon_node := _as_valid_node3d(existing_cannon)
		if existing_cannon_node != null and not authored_slots.has(slot_name):
			slot[ShipWeaponLoadoutHelper.POSITION] = existing_cannon_node.position
			slot[ShipWeaponLoadoutHelper.BASIS] = existing_cannon_node.transform.basis

	for slot in slot_specs:
		var node_name := ShipWeaponLoadoutHelper.get_node_name(slot)
		var required_level := ShipWeaponLoadoutHelper.get_required_level(slot)
		var cannon = named_nodes.get(node_name, null)
		if effective_level < required_level or not ShipWeaponLoadoutHelper.is_unlocked_for_levels(slot, current_levels):
			if is_instance_valid(cannon):
				var hidden_cannon_node := _as_valid_node3d(cannon)
				if hidden_cannon_node != null:
					hidden_cannon_node.visible = false
				cannon.set_process(false)
				cannon.set_physics_process(false)
				cannons_node.remove_child(cannon)
				cannon.queue_free()
				named_nodes.erase(node_name)
			continue

		if not is_instance_valid(cannon):
			cannon = ShipWeaponLoadoutHelper.instantiate_weapon(slot, cannon_scene)
			if not is_instance_valid(cannon):
				continue
			cannon.name = node_name
			cannons_node.add_child(cannon)
			named_nodes[node_name] = cannon

		var cannon_node := _as_valid_node3d(cannon)
		if cannon_node == null:
			continue
		cannon_node.visible = true
		cannon_node.position = ShipWeaponLoadoutHelper.get_position(slot)
		if ShipWeaponLoadoutHelper.has_basis(slot):
			cannon_node.rotation = ShipWeaponLoadoutHelper.get_basis(slot).get_euler()
		else:
			cannon_node.rotation = Vector3.ZERO
			cannon_node.rotation_degrees.y = ShipWeaponLoadoutHelper.get_rotation_y(slot)
		cannon.set_process(true)
		cannon.set_physics_process(true)
		_configure_player_cannon(cannon, slot)

	if OS.is_debug_build():
		var roster: Array[String] = []
		for child in cannons_node.get_children():
			if is_instance_valid(child):
				roster.append("%s#%s" % [child.name, str(child.get_instance_id())])
		print("[CannonSetup] level=%d active_slots=%s" % [effective_level, ", ".join(roster)])

func _get_player_cannon_loadout(ship: Node3D) -> Array[Dictionary]:
	var fallback := ShipWeaponLoadoutHelper.get_default_player_cannon_loadout()
	var ship_type_name := "panokseon_player"
	if is_instance_valid(ship):
		if ship.has_method("get_ship_type_value"):
			var method_value := str(ship.call("get_ship_type_value")).strip_edges()
			if not method_value.is_empty():
				ship_type_name = method_value
		elif "ship_type" in ship:
			var property_value := str(ship.get("ship_type")).strip_edges()
			if not property_value.is_empty():
				ship_type_name = property_value

	var loadout := ShipWeaponLoadoutHelper.get_weapon_loadout_for_type(ship_type_name, fallback)
	var cannons: Array[Dictionary] = []
	for spec in loadout:
		if ShipWeaponLoadoutHelper.get_kind(spec) == ShipWeaponLoadoutHelper.KIND_CANNON:
			cannons.append(spec)
	return cannons

func _get_player_cannons_node(ship: Node3D) -> Node3D:
	if not is_instance_valid(ship):
		return null

	var preferred_node := NodeContractHelper.get_cannons_container(ship)

	if preferred_node != null:
		_cleanup_stray_player_cannons_nodes(ship, preferred_node)

	return preferred_node


func _as_valid_node3d(value: Variant) -> Node3D:
	if not is_instance_valid(value):
		return null
	return value as Node3D if value is Node3D else null

func _cleanup_stray_player_cannons_nodes(ship: Node3D, keep_node: Node3D) -> void:
	for child in ship.get_children():
		if not is_instance_valid(child):
			continue
		if child == keep_node:
			continue
		if str(child.name) != NodeContractHelper.SHIP_NODE_CANNONS:
			continue
		child.set_process(false)
		child.set_physics_process(false)
		ship.remove_child(child)
		child.queue_free()


func _configure_player_cannon(cannon: Node, spec: Dictionary = {}) -> void:
	if not is_instance_valid(cannon):
		return
	ShipWeaponLoadoutHelper.apply_weapon_config(cannon, spec, "player")
	if "cannonball_scene" in cannon and default_cannonball_scene != null and not spec.has(ShipWeaponLoadoutHelper.PROJECTILE_SCENE):
		cannon.cannonball_scene = default_cannonball_scene
	if "fire_cooldown" in cannon and not spec.has(ShipWeaponLoadoutHelper.FIRE_COOLDOWN):
		cannon.fire_cooldown = 3.2
	if "detection_range" in cannon and not spec.has(ShipWeaponLoadoutHelper.DETECTION_RANGE):
		cannon.detection_range = 24.0


func _apply_singigeon(ship: Node3D, level: int) -> void:
	NodeContractHelper.clear_singigeon_launcher(ship)

	_refresh_player_crew_capacity(ship)

	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	var arrow_stats := UpgradeManagerDataHelper.get_singigeon_arrow_stats(UPGRADES, current_levels, level)
	print("[Singigeon] 신기전 Lv.%d 갱신! (활 공격 전환, 대병 %.0f, 정원: %d)" % [
		level,
		float(arrow_stats.get("personnel_damage", 0.0)),
		ship.max_crew_count,
	])


func _apply_janggun(ship: Node3D, level: int) -> void:
	NodeContractHelper.install_janggun_launcher(ship, janggun_scene, Vector3(0.0, 0.8, 2.0))
	print("[Janggun] 포문 장군전 운용 갱신! (Lv.%d)" % level)


func _apply_fire_pot(ship: Node3D, level: int) -> void:
	_refresh_player_crew_capacity(ship)
	var stats: Dictionary = UPGRADES["fire_pot"].get("stats", {})
	if "fire_pot_ignition_chance" in ship:
		ship.fire_pot_ignition_chance = clampf(
			float(stats.get("base_ignition_chance", 0.45)) + float(level - 1) * float(stats.get("ignition_chance_per_lv", 0.075)),
			0.0,
			float(stats.get("max_ignition_chance", 0.75))
		)
	if "fire_pot_burn_duration" in ship:
		ship.fire_pot_burn_duration = float(stats.get("burn_duration", 7.0))

	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[FirePot] 화통 Lv.%d 갱신! (배치: %d명, 정원: %d)" % [
		level,
		get_specialist_unit_count("fire_pot"),
		ship.max_crew_count,
	])


var repeating_crossbow_scene: PackedScene = preload("res://scenes/entities/weapons/weapon_repeating_crossbow.tscn")

func _apply_repeating_crossbow(ship: Node3D, level: int) -> void:
	_refresh_player_crew_capacity(ship)

	if ship.has_method("_sync_player_crew_roster"):
		ship._sync_player_crew_roster()
	print("[RepeatingCrossbow] 연노 Lv.%d 갱신! (배치: %d명, 정원: %d)" % [
		level,
		get_specialist_unit_count("repeating_crossbow"),
		ship.max_crew_count,
	])


func _apply_supply(ship: Node3D, _level: int) -> void:
	var s = UPGRADES["supply"]["stats"]
	var hull_heal: float = float(s.get("hull_heal", 20.0))
	if "hull_hp" in ship and "max_hull_hp" in ship:
		ship.hull_hp = minf(ship.max_hull_hp, ship.hull_hp + hull_heal)
	print("[Supply] 보급! HP: %.0f / %.0f" % [
		ship.hull_hp,
		ship.max_hull_hp,
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
	print("[Points] 전리품! 포인트 +%d" % pts)

func _apply_fleet_signal(ship: Node3D, _level: int) -> void:
	if not is_instance_valid(ship):
		return
	var reconcile_state := reconcile_support_fleet(ship, "fleet_signal", {
		"allow_autospawn": true,
		"spawn_now": true,
	})
	if reconcile_state.get("autospawn_skipped", false):
		print("[Support] 지원함 자동 소환 건너뜀 (probe)")
		return
	if reconcile_state.get("spawn_requested", false):
		print("[Support] 지원함 소집 발동!")
		return
	print("[Support] 지원함 소집은 플레이어 함선에서만 사용할 수 있습니다.")

func _apply_panokseon_upgrade(ship: Node3D, _level: int) -> void:
	if not is_instance_valid(ship):
		return
	var reconcile_state := reconcile_support_fleet(ship, "panokseon_upgrade", {
		"allow_autospawn": true,
		"spawn_now": true,
	})
	if reconcile_state.get("autospawn_skipped", false):
		print("[Support] 판옥선 자동 보강 건너뜀 (probe)")
		return
	if reconcile_state.get("spawn_requested", false):
		print("[Support] 판옥선 포격함이 지원 함대에 합류했습니다!")
		return
	print("[Support] 판옥선 포격함 합류에 실패했습니다.")

func _apply_geobukseon_upgrade(ship: Node3D, _level: int) -> void:
	if not is_instance_valid(ship):
		return
	var reconcile_state := reconcile_support_fleet(ship, "geobukseon_upgrade", {
		"allow_autospawn": true,
		"spawn_now": true,
		"require_signal_unlock": true,
	})
	if reconcile_state.get("autospawn_skipped", false):
		print("[Support] 거북선 자동 보강 건너뜀 (probe)")
		return
	if reconcile_state.get("spawn_requested", false):
		print("[Support] 거북선 방호함이 지원 함대에 합류했습니다!")
		return
	print("[Support] 거북선은 지원함 해금 후 사용할 수 있습니다.")

func _apply_fleet_crew(ship: Node3D, level: int) -> void:
	if not is_instance_valid(ship):
		return
	_refresh_support_fleet_upgrade_state(ship)
	print("[Support] 지원함 재합류 업그레이드는 비활성화되었습니다. (Lv.%d 무시)" % level)


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
	if not ITEM_SYSTEM_ENABLED:
		return
	UpgradeManagerItemHelper.add_item(self, item_id)

func grant_final_boss_item() -> void:
	if not ITEM_SYSTEM_ENABLED:
		return
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
	apply_upgrade(FLEET_SIGNAL_UPGRADE_ID)

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
	
	# 1. 지원함 대포 수는 플레이어 포문 업그레이드를 공유하되 지원함 상한을 둔다.
	if ship.has_method("apply_fleet_weapon_upgrade"):
		ship.apply_fleet_weapon_upgrade(maxi(1, int(current_levels.get("cannon", 1))), current_levels)
			
	# 2. 지원함 선체는 별도 업그레이드가 아니라 플레이어 선체 업그레이드를 공유한다.
	_apply_shared_hull_upgrade_to_fleet_ship(ship)
	if int(current_levels.get("boarding_resist", 0)) > 0:
		_apply_boarding_resist_to_ship(ship, int(current_levels.get("boarding_resist", 0)))


func _apply_shared_hull_upgrade_to_fleet_ship(ship: Node3D) -> void:
	if not is_instance_valid(ship):
		return
	var hull_lv: int = int(current_levels.get("hull", 0))
	var hull_stats: Dictionary = UPGRADES.get("hull", {}).get("stats", {})
	if not hull_stats.is_empty():
		if "max_hull_hp" in ship:
			var base_max_hp: float
			if ship.has_meta("fleet_base_shared_max_hull_hp"):
				base_max_hp = float(ship.get_meta("fleet_base_shared_max_hull_hp"))
			else:
				base_max_hp = float(ship.max_hull_hp)
				ship.set_meta("fleet_base_shared_max_hull_hp", base_max_hp)
			var previous_max_hp := float(ship.max_hull_hp)
			var next_max_hp := base_max_hp + float(hull_stats.get("hp_add_per_lv", 15.0)) * float(hull_lv)
			ship.max_hull_hp = next_max_hp
			if "hull_hp" in ship:
				ship.hull_hp = minf(next_max_hp, float(ship.hull_hp) + maxf(0.0, next_max_hp - previous_max_hp))
		if "ramming_damage_multiplier" in ship:
			var base_ram_mult: float
			if ship.has_meta("fleet_base_shared_ram_damage_multiplier"):
				base_ram_mult = float(ship.get_meta("fleet_base_shared_ram_damage_multiplier"))
			else:
				base_ram_mult = float(ship.ramming_damage_multiplier)
				ship.set_meta("fleet_base_shared_ram_damage_multiplier", base_ram_mult)
			ship.ramming_damage_multiplier = base_ram_mult * (1.0 + float(hull_stats.get("ramming_damage_pct_per_lv", 0.07)) * float(hull_lv))

	var lv: int = int(current_levels.get("hull_defense", 0))
	var s: Dictionary = UPGRADES.get("hull_defense", {}).get("stats", {})

	if not s.is_empty() and "hull_defense" in ship:
		var base_defense: float
		if ship.has_meta("fleet_base_shared_hull_defense"):
			base_defense = float(ship.get_meta("fleet_base_shared_hull_defense"))
		else:
			base_defense = float(ship.hull_defense)
			ship.set_meta("fleet_base_shared_hull_defense", base_defense)
		var defense_bonus := 0.0
		for level_entry in s.get("def_levels", []):
			if int(level_entry) <= lv:
				defense_bonus += float(s.get("def_add", 2.0))
		ship.hull_defense = base_defense + defense_bonus + SeaSiteRewardHelper.get_site_bonus_total(ship, "hull_defense_add")
		ship.set_meta("crew_ranged_cover_defense_bonus", float(lv) * float(s.get("crew_ranged_cover_defense_add_per_lv", 0.5)))

	if "hull_regen_rate" in ship:
		var repair_lv: int = int(current_levels.get("hull_repair", 0))
		var repair_stats: Dictionary = UPGRADES.get("hull_repair", {}).get("stats", {})
		var base_regen: float
		if ship.has_meta("fleet_base_shared_hull_regen_rate"):
			base_regen = float(ship.get_meta("fleet_base_shared_hull_regen_rate"))
		else:
			base_regen = float(ship.hull_regen_rate)
			ship.set_meta("fleet_base_shared_hull_regen_rate", base_regen)
		var regen_bonus: float = minf(
			float(repair_stats.get("max_regen", 1.0)),
			float(repair_lv) * float(repair_stats.get("regen_per_lv", 0.2))
		)
		regen_bonus += SeaSiteRewardHelper.get_site_bonus_total(ship, "hull_regen_add")
		ship.hull_regen_rate = base_regen + regen_bonus

	if "hull_hp" in ship and "max_hull_hp" in ship:
		ship.hull_hp = minf(float(ship.hull_hp), float(ship.max_hull_hp))
		ship.set_meta("fleet_shared_hull_level_applied", lv)
			
func reconcile_support_fleet(ship: Node3D, _reason: String = "", options: Dictionary = {}) -> Dictionary:
	var state := _sync_support_fleet_upgrade_state(ship)
	if state.is_empty():
		return state
	if not bool(options.get("allow_autospawn", false)):
		return state
	if _should_skip_support_fleet_autospawn():
		state["autospawn_skipped"] = true
		return state
	var require_signal_unlock: bool = options.get("require_signal_unlock", false) == true
	if require_signal_unlock and int(current_levels.get(FLEET_SIGNAL_UPGRADE_ID, 0)) <= 0:
		state["autospawn_blocked"] = "fleet_signal_locked"
		return state
	var should_spawn: bool = options.get("spawn_now", false) == true
	if options.get("spawn_if_respawn_ready", false) == true:
		var timer_ready := "support_fleet_respawn_timer" in ship and "support_fleet_respawn_interval" in ship
		if timer_ready and float(ship.support_fleet_respawn_timer) >= float(ship.support_fleet_respawn_interval):
			ship.support_fleet_respawn_timer = 0.0
			should_spawn = true
	if options.get("spawn_if_limit_increased", false) == true and state.get("support_limit_increased", false):
		should_spawn = true
	if should_spawn and ship.has_method("_spawn_or_repair_support_ship"):
		ship.call_deferred("_spawn_or_repair_support_ship")
		state["spawn_requested"] = true
	return state


func _refresh_support_fleet_upgrade_state(ship: Node3D) -> void:
	_sync_support_fleet_upgrade_state(ship)


func _sync_support_fleet_upgrade_state(ship: Node3D) -> Dictionary:
	if not is_instance_valid(ship):
		return {}
	var previous_respawn_interval: float = float(ship.get("support_fleet_respawn_interval")) if "support_fleet_respawn_interval" in ship else 0.0
	var previous_limit: int = int(ship.get("support_fleet_limit")) if "support_fleet_limit" in ship else 0
	if "support_fleet_respawn_interval" in ship:
		var base_interval: float = float(ship.get_meta("base_support_fleet_respawn_interval", ship.support_fleet_respawn_interval))
		if not ship.has_meta("base_support_fleet_respawn_interval"):
			ship.set_meta("base_support_fleet_respawn_interval", base_interval)
		ship.support_fleet_respawn_interval = base_interval
	if "support_fleet_limit" in ship:
		var base_limit: int = int(ship.get_meta("base_support_fleet_limit", ship.support_fleet_limit))
		if not ship.has_meta("base_support_fleet_limit"):
			ship.set_meta("base_support_fleet_limit", base_limit)
		var upgrade_bonus: int = _get_support_fleet_limit_upgrade_bonus()
		var squadron_bonus: int = _get_runtime_support_squadron_limit_bonus()
		ship.support_fleet_limit = base_limit + upgrade_bonus + squadron_bonus
	if PlayerFleetRoleHelper.is_player_flagship(ship):
		PlayerShipSupportHelper.refresh_support_fleet_composition(ship)
	return {
		"support_fleet_respawn_interval": float(ship.get("support_fleet_respawn_interval")) if "support_fleet_respawn_interval" in ship else previous_respawn_interval,
		"support_fleet_limit": int(ship.get("support_fleet_limit")) if "support_fleet_limit" in ship else previous_limit,
		"support_limit_increased": ("support_fleet_limit" in ship) and int(ship.get("support_fleet_limit")) > previous_limit,
	}


func _get_support_fleet_limit_upgrade_bonus() -> int:
	var upgrade_bonus: int = 0
	var signal_level: int = int(current_levels.get("fleet_signal", 0))
	var signal_stats: Dictionary = UPGRADES.get("fleet_signal", {}).get("stats", {})
	if signal_level >= int(signal_stats.get("limit_add_level", 999)):
		upgrade_bonus += int(signal_stats.get("limit_add", 0))
	return upgrade_bonus


func _get_runtime_support_squadron_limit_bonus() -> int:
	var squadron_bonus := PlayerShipSupportSquadronHelper.get_support_limit_bonus_for_levels(current_levels, UPGRADES)
	if int(current_levels.get(FLEET_SIGNAL_UPGRADE_ID, 0)) <= 0 and squadron_bonus > 0:
		squadron_bonus -= 1
	return squadron_bonus


func _get_player_soldiers(ship: Node3D) -> Array:
	var soldiers_node = NodeContractHelper.get_soldiers_container(ship)
	if not soldiers_node:
		return []
	var result = []
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != null:
			result.append(child)
	return result
