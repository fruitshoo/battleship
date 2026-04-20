extends Node
const CollisionVisualizer = preload("res://scripts/helpers/collision_visualizer.gd")
const DEBUG_LEVEL_LOGS := false
const LEVEL_PROGRESSION_DATA_PATH := "res://data/level_progression.json"
const REWARD_RULES_DATA_PATH := "res://data/reward_rules.json"
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const RESULT_SCENE_PATH := "res://scenes/ui/result_screen.tscn"

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
@export var soldier_kill_xp_reward: int = 5 ## 일반 병사 처치 시 획득 XP
@export var merit_per_soldier_kill: int = 1 ## 적 병사 1명 처치 시 획득 지휘 포인트
@export var drowned_soldier_kill_xp_reward: int = 3 ## 적 병사를 수장시켰을 때 획득 XP
@export var drowned_soldier_kill_merit_reward: int = 0 ## 적 병사를 수장시켰을 때 획득 지휘 포인트
@export var melee_kill_xp_bonus: int = 2 ## 백병전(검/창/작살) 처치 시 추가 XP
@export var melee_kill_merit_bonus: int = 1 ## 백병전(검/창/작살) 처치 시 추가 지휘 포인트
@export var boarding_capture_score_reward: int = 95 ## 나포 성공 시 추가 점수
@export var boarding_capture_xp_reward: int = 35 ## 나포 성공 시 추가 XP
@export var boarding_capture_merit_reward: int = 20 ## 나포 성공 시 추가 지휘 포인트
@export_group("Boss Arena")
@export var mid_boss_arena_half_extents: Vector2 = Vector2(112.0, 84.0)
@export var final_boss_arena_half_extents: Vector2 = Vector2(136.0, 98.0)
@export_range(0.5, 0.95, 0.01) var boss_arena_safe_ratio: float = 0.74
@export_range(0.0, 0.5, 0.01) var boss_arena_headwind_strength: float = 0.18
@export_range(0.0, 4.0, 0.05) var boss_arena_current_strength: float = 1.25
@export_range(0.0, 1.0, 0.01) var boss_arena_warning_threshold: float = 0.22
@export var boss_boundary_hull_scene: PackedScene = preload("res://scenes/ships/hulls/kobayabune_hull.tscn")
@export_range(10.0, 40.0, 0.5) var boss_boundary_spacing: float = 18.0
@export_range(0.6, 2.4, 0.05) var boss_boundary_visual_scale: float = 1.6
@export_range(0.0, 1.0, 0.01) var boss_boundary_height: float = 0.2
@export_range(10.0, 180.0, 1.0) var boss_boundary_duration: float = 60.0

var current_level: int = 1
var current_xp: int = 0
var xp_to_next_level: int = 0
var xp_multiplier: float = 1.0 # 업그레이드로 강화 가능
var game_difficulty: int = 1 # 적 난이도 레벨

var current_score: int = 0
var current_time: float = 0.0
var enemies_killed: int = 0
var ships_sunk: int = 0
var ships_derelicted: int = 0
var soldiers_killed: int = 0
var soldiers_slain: int = 0
var soldiers_drowned: int = 0
var weapon_damage_stats: Dictionary = {}
var _boss_triggered: bool = false
var _boss_phase_active: bool = false
var _victory_triggered: bool = false
var ship_rerolls_available: int = 0
var crew_rerolls_available: int = 0
var _debug_collision_visuals_enabled: bool = false
var _boss_arena_active: bool = false
var _boss_arena_anchor_boss_id: int = -1
var _boss_arena_center: Vector3 = Vector3.ZERO
var _boss_arena_half_extents_runtime: Vector2 = Vector2.ZERO
var _boss_boundary_container: Node3D = null
var _boss_boundary_elapsed: float = 0.0
var _boss_boundary_hidden_for_current_boss: bool = false
var _victory_result_transition_started: bool = false

const DAMAGE_SOURCE_NAME := {
	"cannon": "대포",
	"singigeon": "신기전",
	"janggun": "대장군전",
	"crew_numbers": "창병",
	"fire_pot": "화통",
	"ballista": "팔우노",
	"repeating_crossbow": "연노",
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
	LevelManagerRegistry.register_level_manager(self)
	_load_level_progression_data()
	_load_reward_rules_data()
	if is_instance_valid(MetaManager) and MetaManager.has_method("get_xp_gain_multiplier"):
		xp_multiplier = float(MetaManager.get_xp_gain_multiplier())
	_calculate_next_level_xp()
	max_merit_points = _get_merit_requirement(merit_level)
	merit_points = clamp(merit_points, 0, max_merit_points)
	LevelManagerStartupHelper.initialize(self)


func _exit_tree() -> void:
	LevelManagerRegistry.unregister_level_manager(self)


func _load_level_progression_data() -> void:
	if not FileAccess.file_exists(LEVEL_PROGRESSION_DATA_PATH):
		return

	var file: FileAccess = FileAccess.open(LEVEL_PROGRESSION_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[LevelManager] level_progression.json을 열 수 없어 기본값을 사용합니다.")
		return

	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[LevelManager] level_progression.json 파싱 실패. 기본값을 사용합니다.")
		return

	var root: Dictionary = parsed as Dictionary
	_apply_level_progression_root(root)


func _apply_level_progression_root(root: Dictionary) -> void:
	var levels_variant: Variant = root.get("levels", {})
	if typeof(levels_variant) == TYPE_DICTIONARY:
		var loaded_levels: Dictionary = _parse_level_progression_levels(levels_variant as Dictionary)
		if not loaded_levels.is_empty():
			level_data = loaded_levels
			max_level = _get_highest_level_key(level_data)

	var xp_curve_variant: Variant = root.get("xp_curve", {})
	if typeof(xp_curve_variant) == TYPE_DICTIONARY:
		var xp_curve: Dictionary = xp_curve_variant as Dictionary
		level_xp_base = float(xp_curve.get("level_xp_base", level_xp_base))
		level_xp_exponent = float(xp_curve.get("level_xp_exponent", level_xp_exponent))

	var merit_curve_variant: Variant = root.get("merit_curve", {})
	if typeof(merit_curve_variant) == TYPE_DICTIONARY:
		var merit_curve: Dictionary = merit_curve_variant as Dictionary
		merit_base_points = int(merit_curve.get("merit_base_points", merit_base_points))
		merit_growth_per_level = int(merit_curve.get("merit_growth_per_level", merit_growth_per_level))


func _parse_level_progression_levels(levels_root: Dictionary) -> Dictionary:
	var parsed_levels: Dictionary = {}
	for key_variant in levels_root.keys():
		var key_text: String = str(key_variant)
		if not key_text.is_valid_int():
			continue
		var level_index: int = int(key_text)
		var row_variant: Variant = levels_root[key_variant]
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant as Dictionary
		parsed_levels[level_index] = {
			"spawn_interval": float(row.get("spawn_interval", 5.0)),
			"max_enemies": int(row.get("max_enemies", 3)),
			"boarders": int(row.get("boarders", 1))
		}
	return parsed_levels


func _get_highest_level_key(levels: Dictionary) -> int:
	var highest: int = 1
	for key_variant in levels.keys():
		var level_key: int = int(key_variant)
		if level_key > highest:
			highest = level_key
	return highest


func _load_reward_rules_data() -> void:
	if not FileAccess.file_exists(REWARD_RULES_DATA_PATH):
		return

	var file: FileAccess = FileAccess.open(REWARD_RULES_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[LevelManager] reward_rules.json을 열 수 없어 기본값을 사용합니다.")
		return

	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[LevelManager] reward_rules.json 파싱 실패. 기본값을 사용합니다.")
		return

	var root: Dictionary = parsed as Dictionary
	_apply_reward_rules_root(root)


func _apply_reward_rules_root(root: Dictionary) -> void:
	var soldier_kill_variant: Variant = root.get("soldier_kill", {})
	if typeof(soldier_kill_variant) == TYPE_DICTIONARY:
		var soldier_kill: Dictionary = soldier_kill_variant as Dictionary
		soldier_kill_xp_reward = int(soldier_kill.get("xp", soldier_kill_xp_reward))
		merit_per_soldier_kill = int(soldier_kill.get("merit", merit_per_soldier_kill))

	var drowned_variant: Variant = root.get("soldier_drowned", {})
	if typeof(drowned_variant) == TYPE_DICTIONARY:
		var soldier_drowned: Dictionary = drowned_variant as Dictionary
		drowned_soldier_kill_xp_reward = int(soldier_drowned.get("xp", drowned_soldier_kill_xp_reward))
		drowned_soldier_kill_merit_reward = int(soldier_drowned.get("merit", drowned_soldier_kill_merit_reward))

	var melee_variant: Variant = root.get("melee_bonus", {})
	if typeof(melee_variant) == TYPE_DICTIONARY:
		var melee_bonus: Dictionary = melee_variant as Dictionary
		melee_kill_xp_bonus = int(melee_bonus.get("xp", melee_kill_xp_bonus))
		melee_kill_merit_bonus = int(melee_bonus.get("merit", melee_kill_merit_bonus))

	var capture_variant: Variant = root.get("boarding_capture", {})
	if typeof(capture_variant) == TYPE_DICTIONARY:
		var boarding_capture: Dictionary = capture_variant as Dictionary
		boarding_capture_score_reward = int(boarding_capture.get("score", boarding_capture_score_reward))
		boarding_capture_xp_reward = int(boarding_capture.get("xp", boarding_capture_xp_reward))
		boarding_capture_merit_reward = int(boarding_capture.get("merit", boarding_capture_merit_reward))

func _run_startup_prewarm_async() -> void:
	await LevelManagerStartupHelper.run_startup_prewarm_async(self)

func _run_startup_bootstrap_async() -> void:
	await LevelManagerStartupHelper.run_startup_bootstrap_async(self)

func _prewarm_shaders(show_blocking_overlay: bool = true) -> void:
	await LevelManagerStartupHelper.prewarm_shaders(self, show_blocking_overlay)

func _mark_prewarm_recursive(node: Node) -> void:
	LevelManagerStartupHelper._mark_prewarm_recursive(node)

func _prime_visual_resources(node: Node) -> void:
	LevelManagerStartupHelper._prime_visual_resources(node)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not get_tree().paused:
			var pause_menu = PAUSE_MENU_SCENE.instantiate()
			add_child(pause_menu)
		if get_viewport(): get_viewport().set_input_as_handled()
		return
		
	if event.is_action_pressed("toggle_ship_health_bars"):
		if hud and hud.has_method("toggle_ship_health_bars"):
			hud.toggle_ship_health_bars()
		if get_viewport(): get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_stat_panel"):
		if hud and hud.has_method("toggle_stat_panel"):
			hud.toggle_stat_panel()
		if get_viewport(): get_viewport().set_input_as_handled()
		return
	if not OS.is_debug_build(): return # 이 디버그 키들은 릴리즈 빌드에서는 작동하지 않음
	if event is InputEventKey and event.pressed and not event.is_echo():
		# Alternate debug shortcuts for macOS / non-function-key keyboards.
		# Use physical keys so they still work while Korean input is active.
		if event.ctrl_pressed and event.shift_pressed:
			match event.physical_keycode:
				KEY_J:
					_debug_adjust_player_sail_damage(0.15)
					return
				KEY_K:
					_debug_adjust_player_sail_damage(-0.15)
					return
				KEY_U:
					_debug_adjust_player_sail_burn(0.15)
					return
				KEY_I:
					_debug_adjust_player_sail_burn(-0.15)
					return
				KEY_R:
					_debug_reset_player_sail_state()
					return
		match event.keycode:
			KEY_F1: # 강제 레벨업
				print("[DEBUG] 강제 레벨업!")
				_set_level(current_level + 1)
			KEY_F2: # 대포 디버그
				_debug_cannons()
			KEY_F3: # 선박 영역 시각화
				_toggle_collision_visualizers()
			KEY_F4: # sekibune melee 테스트 소환
				_debug_spawn_test_ship("sekibune_melee", 18.0, 0.0)
			KEY_F5: # sekibune cannon 테스트 소환
				_debug_spawn_test_ship("sekibune_cannon", 20.0, 10.0)
			KEY_F6: # 선박 영역 모드 순환
				_cycle_collision_visualizer_mode()
			KEY_F7: # 중간 보스 디버그 소환
				_debug_spawn_mid_boss()
			KEY_F8: # 최종 보스 디버그 소환
				_debug_spawn_final_boss()
			KEY_F9: # 지원함 디버그 추가
				_debug_spawn_support_ship()
			KEY_F10: # 지원함 추종 상태 덤프
				_debug_dump_support_fleet_state()
			KEY_F11: # 돛 손상 디버그 조절 / Ctrl로 초기화
				if event.ctrl_pressed:
					_debug_reset_player_sail_state()
				elif event.shift_pressed:
					_debug_adjust_player_sail_damage(-0.15)
				else:
					_debug_adjust_player_sail_damage(0.15)
			KEY_F12: # 돛 burn 디버그 조절
				if event.shift_pressed:
					_debug_adjust_player_sail_burn(-0.15)
				else:
					_debug_adjust_player_sail_burn(0.15)
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


func _update_boss_arena_state(delta: float) -> void:
	var boss_ship: Node3D = _get_active_boss_ship()
	if not is_instance_valid(boss_ship):
		_boss_arena_active = false
		_boss_arena_anchor_boss_id = -1
		_boss_boundary_elapsed = 0.0
		_boss_boundary_hidden_for_current_boss = false
		_clear_boss_boundary_markers()
		return
	var boss_id: int = boss_ship.get_instance_id()
	if _boss_arena_anchor_boss_id != boss_id:
		_boss_boundary_elapsed = 0.0
		_boss_boundary_hidden_for_current_boss = false
	_boss_arena_active = true
	_boss_arena_anchor_boss_id = boss_id
	var player_ship: Node3D = EntityRegistry.get_first_ship_by_team("player") as Node3D
	if is_instance_valid(player_ship):
		_boss_arena_center = (player_ship.global_position + boss_ship.global_position) * 0.5
	else:
		_boss_arena_center = boss_ship.global_position
	_boss_arena_center.y = 0.0
	var boss_tier: int = int(boss_ship.get("tier")) if boss_ship.get("tier") != null else 1
	_boss_arena_half_extents_runtime = final_boss_arena_half_extents if boss_tier >= 2 else mid_boss_arena_half_extents
	_clear_boss_boundary_markers()


func _get_active_boss_ship() -> Node3D:
	var bosses: Array = EntityRegistry.get_ships_by_team("enemy")
	for boss in bosses:
		if not is_instance_valid(boss):
			continue
		if not boss.is_in_group("boss"):
			continue
		if boss.get("is_dying") == true or boss.get("is_sinking") == true:
			continue
		return boss as Node3D
	return null


func is_boss_arena_active() -> bool:
	return false


func get_boss_arena_pressure(world_pos: Vector3) -> float:
	return 0.0


func get_boss_arena_current(world_pos: Vector3) -> Vector3:
	return Vector3.ZERO


func get_boss_arena_headwind_multiplier(world_pos: Vector3, forward_dir: Vector3) -> float:
	return 1.0


func get_boss_arena_display_wind_direction(world_pos: Vector3, base_wind_dir: Vector2) -> Vector2:
	return base_wind_dir.normalized()

func get_boss_arena_warning_text(world_pos: Vector3) -> String:
	return ""


func _clear_boss_boundary_markers() -> void:
	if is_instance_valid(_boss_boundary_container):
		_boss_boundary_container.queue_free()
	_boss_boundary_container = null


func _rebuild_boss_boundary_markers(boss_ship: Node3D) -> void:
	_clear_boss_boundary_markers()
	if not is_instance_valid(boss_boundary_hull_scene) or not is_instance_valid(boss_ship):
		return
	_boss_boundary_container = Node3D.new()
	_boss_boundary_container.name = "BossBoundaryMarkers"
	var root_3d: Node3D = get_tree().current_scene as Node3D
	if is_instance_valid(root_3d):
		root_3d.add_child(_boss_boundary_container)
	else:
		get_parent().add_child(_boss_boundary_container)

	var arena_forward: Vector3 = boss_ship.global_position - _boss_arena_center
	arena_forward.y = 0.0
	if arena_forward.length_squared() <= 0.0001:
		arena_forward = Vector3(0.0, 0.0, -1.0)
	else:
		arena_forward = arena_forward.normalized()
	var arena_rear: Vector3 = -arena_forward
	var arena_right: Vector3 = arena_forward.cross(Vector3.UP).normalized()

	var rear_half_width: float = _boss_arena_half_extents_runtime.x * 0.86
	var rear_depth: float = _boss_arena_half_extents_runtime.y * 0.94
	var flank_x: float = _boss_arena_half_extents_runtime.x * 0.96
	var flank_start: float = _boss_arena_half_extents_runtime.y * 0.28
	var flank_end: float = _boss_arena_half_extents_runtime.y * 0.82

	var x: float = -rear_half_width
	while x <= rear_half_width + 0.1:
		var rear_pos: Vector3 = _boss_arena_center + arena_rear * rear_depth + arena_right * x
		_spawn_boss_boundary_marker(rear_pos)
		x += boss_boundary_spacing

	var dist: float = flank_start
	while dist <= flank_end + 0.1:
		var left_pos: Vector3 = _boss_arena_center + arena_rear * dist - arena_right * flank_x
		var right_pos: Vector3 = _boss_arena_center + arena_rear * dist + arena_right * flank_x
		_spawn_boss_boundary_marker(left_pos)
		_spawn_boss_boundary_marker(right_pos)
		dist += boss_boundary_spacing


func _spawn_boss_boundary_marker(world_pos: Vector3) -> void:
	if not is_instance_valid(_boss_boundary_container) or not is_instance_valid(boss_boundary_hull_scene):
		return
	var marker := Node3D.new()
	marker.position = Vector3(world_pos.x, boss_boundary_height, world_pos.z)
	marker.scale = Vector3.ONE * boss_boundary_visual_scale
	_boss_boundary_container.add_child(marker)

	var hull_visual := boss_boundary_hull_scene.instantiate()
	marker.add_child(hull_visual)
	_disable_boundary_processing_recursive(hull_visual)

	marker.look_at(_boss_arena_center, Vector3.UP)
	marker.rotate_y(PI * 0.5)


func _disable_boundary_processing_recursive(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		_disable_boundary_processing_recursive(child)

func add_score(points: int) -> void:
	LevelManagerProgressionHelper.add_score(self, points)

func add_ship_sunk(count: int = 1) -> void:
	LevelManagerProgressionHelper.add_ship_sunk(self, count)

func add_ship_derelict(count: int = 1) -> void:
	LevelManagerProgressionHelper.add_ship_derelict(self, count)

func add_soldier_kill(count: int = 1, cause: String = "combat") -> void:
	LevelManagerProgressionHelper.add_soldier_kill(self, count, cause)

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
	var reroll_bonus: int = 0
	if is_instance_valid(MetaManager) and MetaManager.has_method("get_reroll_bonus"):
		reroll_bonus = int(MetaManager.get_reroll_bonus())
	crew_rerolls_available = 1 + reroll_bonus
	_show_fleet_upgrade_ui()
	
	merit_points = 0
	merit_changed.emit(merit_points, max_merit_points, merit_level)
	if hud and hud.has_method("update_merit"):
		hud.update_merit(merit_points, max_merit_points, merit_level)


func _show_fleet_upgrade_ui() -> void:
	LevelManagerUpgradeFlowHelper.show_fleet_upgrade_ui(self)


func _on_fleet_upgrade_chosen(upgrade_id: String) -> void:
	LevelManagerUpgradeFlowHelper.on_fleet_upgrade_chosen(self, upgrade_id)

func _on_fleet_reroll_requested() -> void:
	LevelManagerUpgradeFlowHelper.on_fleet_reroll_requested(self)


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

func _debug_force_fleet_level_up() -> void:
	LevelManagerUpgradeFlowHelper.show_fleet_upgrade_ui(self)


func _show_upgrade_ui(choice_count: int = 3) -> void:
	LevelManagerUpgradeFlowHelper.show_upgrade_ui(self, choice_count)


func _on_reroll_requested() -> void:
	LevelManagerUpgradeFlowHelper.on_reroll_requested(self)


func _on_upgrade_chosen(upgrade_id: String) -> void:
	LevelManagerUpgradeFlowHelper.on_upgrade_chosen(self, upgrade_id)


func _update_difficulty() -> void:
	LevelManagerProgressionHelper.update_difficulty(self)


func _debug_cannons() -> void:
	var player_ship: Node3D = EntityRegistry.get_first_ship_by_team("player") as Node3D
	if not is_instance_valid(player_ship):
		print("[DEBUG] 플레이어 배 없음!")
		return

	var cannons_node := NodeContractHelper.get_cannons_container(player_ship)
	if not cannons_node:
		print("[DEBUG] Cannons 노드 없음!")
		return
	
	print("[DEBUG] ============ CANNON DEBUG ============")
	print("[DEBUG] 총 대포 수: %d" % cannons_node.get_child_count())
	
	for cannon in cannons_node.get_children():
		var overlaps = 0
		var monitoring = false
		var snapshot: Dictionary = cannon.call("get_debug_cannon_snapshot") if cannon.has_method("get_debug_cannon_snapshot") else {}
		monitoring = bool(snapshot.get("detection_monitoring", false))
		overlaps = int(snapshot.get("detection_overlap_count", 0))
		
		print("[DEBUG] [%s] pos=%s rot_y=%.1f° monitoring=%s overlaps=%d" % [
			cannon.name,
			cannon.position,
			rad_to_deg(cannon.rotation.y),
			monitoring,
			overlaps
		])
	
	# 적 수도 출력
	var enemies = EntityRegistry.get_ships_by_team("enemy")
	print("[DEBUG] 적 수: %d" % enemies.size())
	for e in enemies:
		print("[DEBUG]   적 [%s] pos=%s" % [e.name, e.global_position])
	print("[DEBUG] ========================================")

func _toggle_collision_visualizers() -> void:
	_set_collision_visualizers_enabled(not _debug_collision_visuals_enabled)


func _set_collision_visualizers_enabled(enabled: bool) -> void:
	_debug_collision_visuals_enabled = enabled
	CollisionVisualizer.set_runtime_enabled(enabled)
	for node in get_tree().get_nodes_in_group("collision_visualizers"):
		if node and node.has_method("_refresh_visibility"):
			node.call("_refresh_visibility")
	print("[DEBUG] 선박 영역 시각화: %s" % ("ON" if enabled else "OFF"))

func _debug_spawn_test_ship(ship_type_name: String, distance: float, lateral_offset: float, authoring_meta: Variant = null) -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_spawn_ship"):
		return
	enemy_spawner.debug_spawn_ship(ship_type_name, distance, lateral_offset, authoring_meta)


func _debug_spawn_fleet(fleet_class: String) -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_spawn_fleet"):
		return
	enemy_spawner.debug_spawn_fleet(fleet_class)


func _debug_spawn_recipe(recipe_name: String, authoring_meta: Variant = null) -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_spawn_recipe"):
		return
	enemy_spawner.debug_spawn_recipe(recipe_name, authoring_meta)


func _debug_set_encounter_profile(profile_name: String) -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_set_encounter_profile"):
		return
	var applied: bool = bool(enemy_spawner.debug_set_encounter_profile(profile_name))
	print("[DEBUG] encounter_profile %s: %s" % [profile_name, "OK" if applied else "FAIL"])


func _debug_run_scenario_trigger(trigger_id: String) -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_run_scenario_trigger"):
		return
	var applied: bool = bool(enemy_spawner.debug_run_scenario_trigger(trigger_id))
	print("[DEBUG] scenario_trigger %s: %s" % [trigger_id, "OK" if applied else "FAIL"])


func _debug_spawn_mid_boss() -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_spawn_mid_boss"):
		return
	enemy_spawner.debug_spawn_mid_boss()


func _debug_spawn_final_boss() -> void:
	if not enemy_spawner or not enemy_spawner.has_method("debug_spawn_final_boss"):
		return
	_boss_triggered = true
	_boss_phase_active = true
	current_time = maxf(current_time, boss_spawn_time)
	enemy_spawner.debug_spawn_final_boss()


func _cycle_collision_visualizer_mode() -> void:
	var mode = CollisionVisualizer.cycle_runtime_mode()
	for node in get_tree().get_nodes_in_group("collision_visualizers"):
		if node and node.has_method("_refresh_visibility"):
			node.call("_refresh_visibility")
	print("[DEBUG] 선박 영역 시각화 모드: %s" % CollisionVisualizer.get_mode_name(mode))

func _debug_spawn_support_ship() -> void:
	var player_ship: Node3D = EntityRegistry.get_first_ship_by_team("player") as Node3D
	if not is_instance_valid(player_ship):
		print("[DEBUG] 플레이어 배 없음!")
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
	var player_ship: Node3D = EntityRegistry.get_first_ship_by_team("player") as Node3D
	if not is_instance_valid(player_ship):
		print("[DEBUG] 플레이어 배 없음!")
		return
	if not player_ship.has_method("_get_support_fleet_ships"):
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
		var join_state: bool = support_ship.get_meta("support_joining", false) == true
		_draw_support_fleet_debug(support_ship, lead_name, slot_dist, rel_depth, join_state)
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


func _draw_support_fleet_debug(support_ship: Node, lead_name: String, slot_dist: float, rel_depth: float, join_state: bool) -> void:
	if not (support_ship is Node3D) or not DebugDrawBridge.can_draw():
		return
	var ship_3d := support_ship as Node3D
	var target_pos_variant: Variant = support_ship.get_meta("support_debug_target_pos", Vector3.INF)
	if not (target_pos_variant is Vector3):
		return
	var target_pos := target_pos_variant as Vector3
	if target_pos == Vector3.INF:
		return
	var color := Color(0.35, 0.95, 1.0, 0.95) if not join_state else Color(1.0, 0.86, 0.28, 0.95)
	DebugDrawBridge.draw_marker(target_pos, color, "%s slot" % ship_3d.name, 4.0, 0.32, 1.05)
	DebugDrawBridge.draw_line_raised(ship_3d.global_position, target_pos, 1.15, color, 4.0, 0.04)
	DebugDrawBridge.draw_arrow(
		ship_3d.global_position + Vector3.UP * 1.55,
		target_pos + Vector3.UP * 1.55,
		color,
		4.0,
		0.55,
		0.04
	)
	DebugDrawBridge.draw_text(
		ship_3d.global_position + Vector3.UP * 2.2,
		"%s -> %s | %.1fm | depth %.1f" % [ship_3d.name, lead_name, slot_dist, rel_depth],
		color,
		4.0,
		18
	)


func _get_debug_player_ship() -> Node3D:
	var player_ship: Node3D = EntityRegistry.get_first_ship_by_team("player") as Node3D
	if not is_instance_valid(player_ship):
		return null
	return player_ship


func _get_debug_player_masts() -> Array[Node]:
	var player_ship: Node3D = _get_debug_player_ship()
	if not is_instance_valid(player_ship):
		return []
	var mast_nodes: Array[Node] = []
	var raw_masts = player_ship.get("masts")
	if raw_masts is Array:
		for mast in raw_masts:
			if is_instance_valid(mast):
				mast_nodes.append(mast)
	return mast_nodes


func _show_debug_hud_message(message: String, duration: float = 0.9) -> void:
	if hud and hud.has_method("show_gust_warning_message"):
		hud.show_gust_warning_message(message, duration)
	print("[DEBUG] %s" % message)


func _debug_adjust_player_sail_damage(delta: float) -> void:
	var masts: Array[Node] = _get_debug_player_masts()
	if masts.is_empty():
		_show_debug_hud_message("돛 디버그 대상 없음")
		return
	var first_mast: Node = masts[0]
	var current_damage: float = 0.0
	var current_burn: float = 0.0
	if first_mast.has_method("get_sail_damage"):
		current_damage = float(first_mast.get_sail_damage())
	if first_mast.has_method("get_burn_amount"):
		current_burn = float(first_mast.get_burn_amount())
	var target_damage: float = clampf(current_damage + delta, 0.0, 1.0)
	for mast in masts:
		if not is_instance_valid(mast):
			continue
		mast.set("sail_damage", target_damage)
	_show_debug_hud_message("돛 손상 %.2f | burn %.2f" % [target_damage, current_burn])


func _debug_adjust_player_sail_burn(delta: float) -> void:
	var masts: Array[Node] = _get_debug_player_masts()
	if masts.is_empty():
		_show_debug_hud_message("돛 디버그 대상 없음")
		return
	var first_mast: Node = masts[0]
	var current_damage: float = 0.0
	var current_burn: float = 0.0
	if first_mast.has_method("get_sail_damage"):
		current_damage = float(first_mast.get_sail_damage())
	if first_mast.has_method("get_burn_amount"):
		current_burn = float(first_mast.get_burn_amount())
	var target_burn: float = clampf(current_burn + delta, 0.0, 1.0)
	for mast in masts:
		if not is_instance_valid(mast):
			continue
		if mast.has_method("set_burn_amount"):
			mast.set_burn_amount(target_burn)
		else:
			mast.set("burn_amount", target_burn)
	_show_debug_hud_message("돛 손상 %.2f | burn %.2f" % [current_damage, target_burn])


func _debug_reset_player_sail_state() -> void:
	var masts: Array[Node] = _get_debug_player_masts()
	if masts.is_empty():
		_show_debug_hud_message("돛 디버그 대상 없음")
		return
	for mast in masts:
		if not is_instance_valid(mast):
			continue
		mast.set("sail_damage", 0.0)
		if mast.has_method("set_burn_amount"):
			mast.set_burn_amount(0.0)
		else:
			mast.set("burn_amount", 0.0)
	_show_debug_hud_message("돛 손상 초기화")


func update_boss_hp(current: float, maximum: float) -> void:
	if hud and hud.has_method("update_boss_hp"):
		hud.update_boss_hp(current, maximum)


func show_victory() -> void:
	if _victory_triggered:
		return
	_victory_triggered = true
	RunResultStore.set_latest_result(_build_victory_result())
	
	# 실시간 저장이므로 여기서는 메시지만 처리
	print("[Win] 승리! 현재 판에서 %d 골드 획득" % current_score)
	
	if hud:
		if hud.has_method("show_victory_with_damage"):
			hud.show_victory_with_damage(get_weapon_damage_rows(8), get_total_weapon_damage())
		elif hud.has_method("show_victory"):
			hud.show_victory()
	_schedule_result_scene_transition()


func _build_victory_result() -> Dictionary:
	var player_ship: Node = EntityRegistry.get_first_ship_by_team("player")
	var crew_alive: int = 0
	var crew_capacity: int = 0
	var support_count: int = 0
	var hull_hp: float = 0.0
	var hull_hp_max: float = 0.0
	if is_instance_valid(player_ship):
		crew_alive = int(player_ship.call("get_alive_crew_count")) if player_ship.has_method("get_alive_crew_count") else 0
		if player_ship.get("max_crew_count") != null:
			crew_capacity = int(player_ship.get("max_crew_count"))
		if player_ship.has_method("_get_support_fleet_ships"):
			support_count = player_ship.call("_get_support_fleet_ships").size()
		if player_ship.get("current_hull_hp") != null:
			hull_hp = float(player_ship.get("current_hull_hp"))
		if player_ship.get("max_hull_hp") != null:
			hull_hp_max = float(player_ship.get("max_hull_hp"))
	var result: Dictionary = {
		"title": "항해 결과",
		"outcome": _get_victory_outcome_text(),
		"survived_seconds": current_time,
		"gold": current_score,
		"level": current_level,
		"difficulty": game_difficulty,
		"ships_sunk": ships_sunk,
		"ships_derelicted": ships_derelicted,
		"soldiers_killed": soldiers_killed,
		"soldiers_slain": soldiers_slain,
		"soldiers_drowned": soldiers_drowned,
		"crew_alive": crew_alive,
		"crew_capacity": crew_capacity,
		"support_count": support_count,
		"hull_hp": hull_hp,
		"hull_hp_max": hull_hp_max,
		"total_weapon_damage": get_total_weapon_damage(),
		"weapon_rows": get_weapon_damage_rows(12),
	}
	return result


func _get_victory_outcome_text() -> String:
	if _boss_triggered:
		return "최종 보스 격침"
	return "항해 생존"


func _schedule_result_scene_transition() -> void:
	if _victory_result_transition_started:
		return
	if DisplayServer.get_name() == "headless":
		return
	_victory_result_transition_started = true
	var timer := get_tree().create_timer(2.2, true, false, true)
	timer.timeout.connect(_go_to_result_scene)


func _go_to_result_scene() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(RESULT_SCENE_PATH)


func show_meta_shop() -> void:
	if not meta_upgrade_ui_scene: return
	
	get_tree().paused = true
	var shop = meta_upgrade_ui_scene.instantiate()
	shop.title_text = "[항구] 영구 강화"
	shop.close_button_text = "항해 복귀"
	add_child(shop)
	var level_manager_id: int = get_instance_id()
	shop.closed.connect(func():
		var level_manager := instance_from_id(level_manager_id) as Node
		if is_instance_valid(level_manager):
			level_manager.get_tree().paused = false
	)
