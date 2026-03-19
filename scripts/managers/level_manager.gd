extends Node
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const CollisionVisualizer = preload("res://scripts/helpers/collision_visualizer.gd")
const LevelManagerStartupHelper = preload("res://scripts/managers/level_manager_startup_helper.gd")
const LevelManagerProgressionHelper = preload("res://scripts/managers/level_manager_progression_helper.gd")
const LevelManagerUpgradeFlowHelper = preload("res://scripts/managers/level_manager_upgrade_flow_helper.gd")
const DEBUG_LEVEL_LOGS := false

## 레벨 매니저 (Level Manager)
## 게임 시간 경과에 따라 난이도(레벨)를 관리하고 스포너에게 지시

signal level_up(new_level: int)
signal score_changed(new_score: int)
signal merit_full_action_completed() # 지휘 포인트 가득 참 후속 처리 완료


@export var level_duration: float = 45.0 # 난이도 증가 간격 (초)
@export var boss_spawn_time: float = 600.0 # 보스 등장 시간 (초, 기본 10분)
@export var survival_victory_time: float = 600.0 # 생존 승리 시간 (초)
@export var max_level: int = 15
@export var max_hull_hp_cap: float = 800.0 # 레벨업 HP 보너스 상한 (함선 체력 상향에 맞춰 400->800)
@export var hud: CanvasLayer = null
@export_group("Progression Tuning")
@export var level_xp_base: float = 7.0 ## 플레이어 레벨 1->2 기본 필요 XP
@export var level_xp_exponent: float = 1.10 ## 레벨업 필요 XP 성장 곡선 지수
@export var merit_base_points: int = 50 ## 공적 레벨 1 기본 요구치
@export var merit_growth_per_level: int = 10 ## 공적 레벨당 증가치
@export var merit_per_soldier_kill: int = 1 ## 적 병사 1명 처치 시 획득 지휘 포인트

var current_level: int = 1
var current_xp: int = 0
var xp_to_next_level: int = 0
var xp_multiplier: float = 1.0 # 업그레이드로 강화 가능
var game_difficulty: int = 1 # 적 난이도 레벨

var current_score: int = 0
var current_time: float = 0.0
var enemies_killed: int = 0
var ships_sunk: int = 0
var soldiers_killed: int = 0
var weapon_damage_stats: Dictionary = {}
var _boss_triggered: bool = false
var _boss_phase_active: bool = false
var _victory_triggered: bool = false
var rerolls_available: int = 0
var _debug_collision_visuals_enabled: bool = false

const DAMAGE_SOURCE_NAME := {
	"cannon": "대포",
	"singigeon": "신기전병",
	"janggun": "대장군전",
	"crew_numbers": "창병",
	"fire_pot": "화통병",
	"ballista": "팔우노",
	"repeating_crossbow": "연노병",
	"bow": "활",
	"sword": "검",
	"spear": "창",
	"trident": "삼지창",
	"harpoon": "작살",
}

# 공적(Merit) 시스템: 병사(지휘) 업그레이드 전용 트랙
signal merit_changed(current: int, maximum: int, level: int)
signal merit_full()
var merit_points: int = 0
var max_merit_points: int = 50
var merit_level: int = 1

# 레벨별 난이도 설정 (밸런스 조정)
# spawn_interval: 적 생성 간격 (초)
# max_enemies: 동시 최대 적 수
# boarders: 도선 병사 수
var level_data = {
	1: {"spawn_interval": 5.2, "max_enemies": 3, "boarders": 1},
	2: {"spawn_interval": 4.8, "max_enemies": 4, "boarders": 1},
	3: {"spawn_interval": 4.4, "max_enemies": 5, "boarders": 2},
	4: {"spawn_interval": 4.0, "max_enemies": 6, "boarders": 2},
	5: {"spawn_interval": 3.7, "max_enemies": 7, "boarders": 2},
	6: {"spawn_interval": 3.4, "max_enemies": 8, "boarders": 3},
	7: {"spawn_interval": 3.1, "max_enemies": 9, "boarders": 3},
	8: {"spawn_interval": 2.9, "max_enemies": 10, "boarders": 3},
	9: {"spawn_interval": 2.7, "max_enemies": 11, "boarders": 3},
	10: {"spawn_interval": 2.5, "max_enemies": 12, "boarders": 4},
	11: {"spawn_interval": 2.3, "max_enemies": 13, "boarders": 4},
	12: {"spawn_interval": 2.1, "max_enemies": 15, "boarders": 4},
	13: {"spawn_interval": 1.9, "max_enemies": 16, "boarders": 5},
	14: {"spawn_interval": 1.7, "max_enemies": 18, "boarders": 5},
	15: {"spawn_interval": 1.6, "max_enemies": 20, "boarders": 6},
}

# 참조
@export var enemy_spawner: Node = null

func _ready() -> void:
	add_to_group("level_manager")
	if is_instance_valid(MetaManager) and MetaManager.has_method("get_xp_gain_multiplier"):
		xp_multiplier = float(MetaManager.get_xp_gain_multiplier())
	_calculate_next_level_xp()
	max_merit_points = _get_merit_requirement(merit_level)
	merit_points = clamp(merit_points, 0, max_merit_points)
	LevelManagerStartupHelper.initialize(self)

func _run_startup_prewarm_async() -> void:
	await LevelManagerStartupHelper.run_startup_prewarm_async(self)

func _prewarm_shaders(show_blocking_overlay: bool = true) -> void:
	await LevelManagerStartupHelper.prewarm_shaders(self, show_blocking_overlay)

func _mark_prewarm_recursive(node: Node) -> void:
	LevelManagerStartupHelper._mark_prewarm_recursive(node)

func _prime_visual_resources(node: Node) -> void:
	LevelManagerStartupHelper._prime_visual_resources(node)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ship_health_bars"):
		if hud and hud.has_method("toggle_ship_health_bars"):
			hud.toggle_ship_health_bars()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_stat_panel"):
		if hud and hud.has_method("toggle_stat_panel"):
			hud.toggle_stat_panel()
		get_viewport().set_input_as_handled()
		return
	if not OS.is_debug_build(): return # 이 디버그 키들은 릴리즈 빌드에서는 작동하지 않음
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: # 강제 레벨업
				print("[DEBUG] 강제 레벨업!")
				_set_level(current_level + 1)
			KEY_F2: # 대포 디버그
				_debug_cannons()
			KEY_F3: # 충돌 외곽선 시각화
				_toggle_collision_visualizers()
			KEY_F4: # sekibune melee 테스트 소환
				_debug_spawn_test_ship("sekibune_melee", 18.0, 0.0)
			KEY_F5: # sekibune cannon 테스트 소환
				_debug_spawn_test_ship("sekibune_cannon", 20.0, 10.0)
			KEY_F6: # 충돌 시각화 모드 순환
				_cycle_collision_visualizer_mode()
			KEY_F9: # 지원함 디버그 추가
				_debug_spawn_support_ship()
			KEY_F10: # 지원함 추종 상태 덤프
				_debug_dump_support_fleet_state()
			KEY_M: # 메타 업그레이드 상점 (테스트용)
				show_meta_shop()


func _process(delta: float) -> void:
	if _boss_phase_active:
		current_time = boss_spawn_time
	else:
		current_time += delta
	
	# 보스 등장 체크 (10분 = 600초)
	if boss_spawn_time > 0.0 and current_time >= boss_spawn_time and not _boss_triggered:
		current_time = boss_spawn_time
		_boss_triggered = true
		_boss_phase_active = true
		if enemy_spawner:
			enemy_spawner.trigger_boss_event()
	
	# 보스전이 없는 구성일 때만 시간 생존 승리 적용
	var use_survival_victory: bool = survival_victory_time > 0.0 and (boss_spawn_time <= 0.0 or survival_victory_time < boss_spawn_time)
	if use_survival_victory and current_time >= survival_victory_time:
		show_victory()
		return
	
	# 난이도 자동 증가 (시간 기반)
	var new_difficulty = int(current_time / level_duration) + 1
	new_difficulty = min(new_difficulty, max_level)
	
	if new_difficulty > game_difficulty:
		game_difficulty = new_difficulty
		_update_difficulty()
		if hud and hud.has_method("update_difficulty_ui"):
			hud.update_difficulty_ui(game_difficulty)
		if DEBUG_LEVEL_LOGS:
			print("[Difficulty] 난이도 상승! Level %d (적 강화)" % game_difficulty)

func add_score(points: int) -> void:
	LevelManagerProgressionHelper.add_score(self, points)

func add_ship_sunk(count: int = 1) -> void:
	LevelManagerProgressionHelper.add_ship_sunk(self, count)

func add_soldier_kill(count: int = 1) -> void:
	LevelManagerProgressionHelper.add_soldier_kill(self, count)

func add_command_xp_from_soldier_kill(kill_count: int = 1) -> void:
	LevelManagerProgressionHelper.add_command_xp_from_soldier_kill(self, kill_count)

func add_player_weapon_damage(source_id: String, amount: float) -> void:
	LevelManagerProgressionHelper.add_player_weapon_damage(self, source_id, amount)

func get_total_weapon_damage() -> float:
	return LevelManagerProgressionHelper.get_total_weapon_damage(self)

func get_weapon_damage_rows(max_rows: int = 8) -> Array:
	return LevelManagerProgressionHelper.get_weapon_damage_rows(self, max_rows)


## XP 획득 및 레벨업 처리
func add_xp(amount: int) -> void:
	LevelManagerProgressionHelper.add_xp(self, amount)

## 공적 (Merit) 획득
func add_merit(amount: int) -> void:
	LevelManagerProgressionHelper.add_merit(self, amount)
		
func consume_merit() -> void:
	# 공적 소비 시 병사 업그레이드 UI를 띄움
	_show_fleet_upgrade_ui()
	
	merit_points = 0
	merit_changed.emit(merit_points, max_merit_points, merit_level)
	if hud and hud.has_method("update_merit"):
		hud.update_merit(merit_points, max_merit_points, merit_level)


func _show_fleet_upgrade_ui() -> void:
	LevelManagerUpgradeFlowHelper.show_fleet_upgrade_ui(self)


func _on_fleet_upgrade_chosen(upgrade_id: String) -> void:
	LevelManagerUpgradeFlowHelper.on_fleet_upgrade_chosen(self, upgrade_id)


func _finalize_merit_levelup(upgrade_id: String) -> void:
	LevelManagerUpgradeFlowHelper.finalize_merit_levelup(self, upgrade_id)


func _calculate_next_level_xp() -> void:
	LevelManagerProgressionHelper.calculate_next_level_xp(self)


func _get_merit_requirement(level: int) -> int:
	return LevelManagerProgressionHelper.get_merit_requirement(self, level)

var upgrade_ui_scene: PackedScene = preload("res://scenes/ui/upgrade_ui.tscn")
var meta_upgrade_ui_scene: PackedScene = preload("res://scenes/ui/meta_upgrade_ui.tscn")
var _upgrade_ui_instance: CanvasLayer = null

func _set_level(new_level: int) -> void:
	LevelManagerProgressionHelper.set_level(self, new_level)


func _show_upgrade_ui(choice_count: int = 3) -> void:
	LevelManagerUpgradeFlowHelper.show_upgrade_ui(self, choice_count)


func _on_reroll_requested() -> void:
	LevelManagerUpgradeFlowHelper.on_reroll_requested(self)


func _on_upgrade_chosen(upgrade_id: String) -> void:
	LevelManagerUpgradeFlowHelper.on_upgrade_chosen(self, upgrade_id)


func _update_difficulty() -> void:
	LevelManagerProgressionHelper.update_difficulty(self)


func _debug_cannons() -> void:
	var ship = SceneGroupCache.get_nodes(get_tree(), "player")
	if ship.is_empty():
		print("[DEBUG] 플레이어 배 없음!")
		return
	
	var cannons_node = ship[0].get_node_or_null("Cannons")
	if not cannons_node:
		print("[DEBUG] Cannons 노드 없음!")
		return
	
	print("[DEBUG] ============ CANNON DEBUG ============")
	print("[DEBUG] 총 대포 수: %d" % cannons_node.get_child_count())
	
	for cannon in cannons_node.get_children():
		var det_area = cannon.get_node_or_null("DetectionArea")
		var overlaps = 0
		var monitoring = false
		if det_area:
			monitoring = det_area.monitoring
			overlaps = det_area.get_overlapping_areas().size() + det_area.get_overlapping_bodies().size()
		
		print("[DEBUG] [%s] pos=%s rot_y=%.1f° monitoring=%s overlaps=%d" % [
			cannon.name,
			cannon.position,
			rad_to_deg(cannon.rotation.y),
			monitoring,
			overlaps
		])
	
	# 적 수도 출력
	var enemies = SceneGroupCache.get_nodes(get_tree(), "enemy")
	print("[DEBUG] 적 수: %d" % enemies.size())
	for e in enemies:
		print("[DEBUG]   적 [%s] pos=%s" % [e.name, e.global_position])
	print("[DEBUG] ========================================")

func _toggle_collision_visualizers() -> void:
	_debug_collision_visuals_enabled = not _debug_collision_visuals_enabled
	CollisionVisualizer.set_runtime_enabled(_debug_collision_visuals_enabled)
	for node in get_tree().get_nodes_in_group("collision_visualizers"):
		if node and node.has_method("_refresh_visibility"):
			node.call("_refresh_visibility")
	print("[DEBUG] 충돌 시각화: %s" % ("ON" if _debug_collision_visuals_enabled else "OFF"))

func _debug_spawn_test_ship(ship_type_name: String, distance: float, lateral_offset: float) -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_spawn_ship"):
		return
	enemy_spawner.debug_spawn_ship(ship_type_name, distance, lateral_offset)

func _cycle_collision_visualizer_mode() -> void:
	var mode = CollisionVisualizer.cycle_runtime_mode()
	for node in get_tree().get_nodes_in_group("collision_visualizers"):
		if node and node.has_method("_refresh_visibility"):
			node.call("_refresh_visibility")
	var mode_name := "ALL"
	match mode:
		CollisionVisualizer.MODE_BASE:
			mode_name = "BASE"
		CollisionVisualizer.MODE_SEPARATION:
			mode_name = "SEPARATION"
		CollisionVisualizer.MODE_GUARD:
			mode_name = "GUARD"
	print("[DEBUG] 충돌 시각화 모드: %s" % mode_name)

func _debug_spawn_support_ship() -> void:
	var players = SceneGroupCache.get_nodes(get_tree(), "player")
	if players.is_empty():
		print("[DEBUG] 플레이어 배 없음!")
		return
	var player_ship = players[0]
	if not is_instance_valid(player_ship):
		print("[DEBUG] 플레이어 배 유효하지 않음!")
		return
	if not player_ship.has_method("_spawn_or_repair_ally"):
		print("[DEBUG] 플레이어 배에 지원함 소환 함수 없음!")
		return

	var current_support_count: int = 0
	if player_ship.has_method("_get_support_fleet_ships"):
		current_support_count = player_ship._get_support_fleet_ships().size()

	if current_support_count >= int(player_ship.support_fleet_limit):
		player_ship.support_fleet_limit = current_support_count + 1

	player_ship._spawn_or_repair_ally()
	print("[DEBUG] 지원함 디버그 추가: 현재 %d척 / 한계 %d" % [
		current_support_count + 1,
		int(player_ship.support_fleet_limit)
	])

func _debug_dump_support_fleet_state() -> void:
	var players = SceneGroupCache.get_nodes(get_tree(), "player")
	if players.is_empty():
		print("[DEBUG] 플레이어 배 없음!")
		return
	var player_ship = players[0]
	if not is_instance_valid(player_ship) or not player_ship.has_method("_get_support_fleet_ships"):
		print("[DEBUG] 지원함 상태 확인 불가!")
		return
	var support_ships: Array = player_ship._get_support_fleet_ships()
	print("[DEBUG] ===== SUPPORT FLEET STATE =====")
	print("[DEBUG] player_pos=%s player_speed=%.2f" % [player_ship.global_position, float(player_ship.get("current_speed"))])
	print("[DEBUG] support_count=%d limit=%d" % [support_ships.size(), int(player_ship.support_fleet_limit)])
	for support_ship in support_ships:
		if not is_instance_valid(support_ship):
			continue
		var lead_name: String = str(support_ship.get_meta("support_debug_lead_name", "none"))
		var slot_dist: float = float(support_ship.get_meta("support_debug_slot_dist", -1.0))
		var rel_depth: float = float(support_ship.get_meta("support_debug_rel_depth", 0.0))
		var lead_speed: float = float(support_ship.get_meta("support_debug_lead_speed", 0.0))
		var target_speed: float = float(support_ship.get_meta("support_debug_target_speed", 0.0))
		var join_state: bool = bool(support_ship.get_meta("support_joining", false))
		print("[DEBUG] %s pos=%s speed=%.2f lead=%s slot_dist=%.2f rel_depth=%.2f lead_speed=%.2f target_speed=%.2f joining=%s" % [
			support_ship.name,
			support_ship.global_position,
			float(support_ship.get("current_speed")),
			lead_name,
			slot_dist,
			rel_depth,
			lead_speed,
			target_speed,
			join_state
		])
	print("[DEBUG] ===============================")


func update_boss_hp(current: float, maximum: float) -> void:
	if hud and hud.has_method("update_boss_hp"):
		hud.update_boss_hp(current, maximum)


func show_victory() -> void:
	if _victory_triggered:
		return
	_victory_triggered = true
	
	# 실시간 저장이므로 여기서는 메시지만 처리
	print("[Win] 승리! 현재 판에서 %d 골드 획득" % current_score)
	
	if hud:
		if hud.has_method("show_victory_with_damage"):
			hud.show_victory_with_damage(get_weapon_damage_rows(8), get_total_weapon_damage())
		elif hud.has_method("show_victory"):
			hud.show_victory()


func show_meta_shop() -> void:
	if not meta_upgrade_ui_scene: return
	
	get_tree().paused = true
	var shop = meta_upgrade_ui_scene.instantiate()
	shop.title_text = "[항구] 영구 강화"
	shop.close_button_text = "항해 복귀"
	add_child(shop)
	shop.closed.connect(func(): get_tree().paused = false)
