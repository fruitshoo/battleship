extends Node

## 레벨 매니저 (Level Manager)
## 게임 시간 경과에 따라 난이도(레벨)를 관리하고 스포너에게 지시

signal level_up(new_level: int)
signal score_changed(new_score: int)
signal merit_full_action_completed() # (레거시) 기존 함대 자동 소환 트리거


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
var _victory_triggered: bool = false
var rerolls_available: int = 0

const DAMAGE_SOURCE_NAME := {
	"cannon": "대포",
	"singigeon": "신기전",
	"janggun": "대장군전",
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
	1: {"spawn_interval": 6.0, "max_enemies": 2, "boarders": 1},
	2: {"spawn_interval": 5.5, "max_enemies": 3, "boarders": 1},
	3: {"spawn_interval": 5.0, "max_enemies": 4, "boarders": 2},
	4: {"spawn_interval": 4.5, "max_enemies": 5, "boarders": 2},
	5: {"spawn_interval": 4.0, "max_enemies": 6, "boarders": 2},
	6: {"spawn_interval": 3.5, "max_enemies": 7, "boarders": 3},
	7: {"spawn_interval": 3.5, "max_enemies": 8, "boarders": 3},
	8: {"spawn_interval": 3.0, "max_enemies": 10, "boarders": 3},
	9: {"spawn_interval": 3.0, "max_enemies": 10, "boarders": 3},
	10: {"spawn_interval": 2.5, "max_enemies": 12, "boarders": 4},
	11: {"spawn_interval": 2.5, "max_enemies": 12, "boarders": 4},
	12: {"spawn_interval": 2.0, "max_enemies": 15, "boarders": 4},
	13: {"spawn_interval": 2.0, "max_enemies": 15, "boarders": 5},
	14: {"spawn_interval": 1.5, "max_enemies": 18, "boarders": 5},
	15: {"spawn_interval": 1.5, "max_enemies": 20, "boarders": 6},
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
	
	# 초기 HUD 및 난이도(Spawner) 업데이트
	_update_difficulty()
	if hud:
		hud.update_level(current_level)
		hud.update_score(current_score)
		hud.update_xp(current_xp, xp_to_next_level)
		hud.update_merit(merit_points, max_merit_points, merit_level)
		if hud.has_method("update_combat_stats"):
			hud.update_combat_stats(ships_sunk, soldiers_killed)
		if hud.has_method("update_difficulty_ui"):
			hud.update_difficulty_ui(game_difficulty)
		
	# 시작 차단 없이 예열은 백그라운드에서 진행한다.
	call_deferred("_run_startup_prewarm_async")
	
	# 육분의(Sextant) 렐릭 및 기본 무기(대포) 지급
	# 시작 지연을 줄이기 위해 예열 완료를 기다리지 않고 초기 프레임 이후 즉시 적용
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(UpgradeManager):
			UpgradeManager.add_relic("sextant")
			UpgradeManager.initialize_default_weapons()
	)

func _run_startup_prewarm_async() -> void:
	# 백그라운드 예열: 게임 시작을 막지 않도록 비차단 모드로 실행
	await _prewarm_shaders(false)

func _prewarm_shaders(show_blocking_overlay: bool = true) -> void:
	# 1. (선택) 로딩(예열) 화면 생성
	var loading_layer: CanvasLayer = null
	var bg: ColorRect = null
	if show_blocking_overlay:
		loading_layer = CanvasLayer.new()
		loading_layer.layer = 120 # 최상단
		bg = ColorRect.new()
		bg.color = Color.BLACK
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		loading_layer.add_child(bg)
		add_child(loading_layer)
	
	# 2. 쉐이더 예열 씬 목록 (시작 연출을 해치지 않도록 순수 VFX만 대상)
	var scenes_to_warm = [
		preload("res://scenes/effects/muzzle_smoke.tscn"),
		preload("res://scenes/effects/hit_effect.tscn"),
		preload("res://scenes/effects/wood_splinter.tscn"),
		preload("res://scenes/effects/fire_effect.tscn"),
		preload("res://scenes/effects/fire_pot_explosion.tscn"),
		preload("res://scenes/effects/water_explosion.tscn"),
	]
	
	# 조용한 예열을 위해 전용 컨테이너에 붙이되, 실제 재생(emitting/play)은 하지 않는다.
	var container = Node3D.new()
	container.name = "ShaderPrewarmer"
	add_child(container)
	container.position = Vector3(0, -1000, 0)
	container.scale = Vector3.ONE
	
	for scene in scenes_to_warm:
		if scene:
			var inst = scene.instantiate()
			_mark_prewarm_recursive(inst)
			container.add_child(inst)
			
			# 파티클/머티리얼 리소스를 터치해 로딩만 유도 (시각/음향 출력 금지)
			_prime_visual_resources(inst)
			
			# 백그라운드 모드에서는 프레임에 작업을 분산해 시작 프레임 스파이크를 줄인다.
			if not show_blocking_overlay:
				await get_tree().process_frame
			
	# 오디오 매니저의 사전 캐싱 작업 대기 (비동기 완료 보장)
	if not AudioManager.is_prewarm_finished:
		await AudioManager.prewarm_finished
		
	# 프레임 안정화를 위해 추가로 2프레임 대기
	for i in range(2):
		await get_tree().process_frame
	
	# 3. 예열 노드 삭제 및 로딩 화면 페이드 아웃
	container.queue_free()
	print("[Resource] 쉐이더 예열 및 오디오 캐싱 완료")
	
	if show_blocking_overlay and is_instance_valid(bg) and is_instance_valid(loading_layer):
		var tween = create_tween()
		tween.tween_property(bg, "modulate:a", 0.0, 1.0) # 1초 동안 부드럽게 밝아짐
		tween.tween_callback(loading_layer.queue_free)

func _mark_prewarm_recursive(node: Node) -> void:
	node.set_meta("prewarm_mode", true)
	for child in node.get_children():
		_mark_prewarm_recursive(child)

func _prime_visual_resources(node: Node) -> void:
	if node is GPUParticles3D:
		var gpu := node as GPUParticles3D
		gpu.emitting = false
		gpu.process_material = gpu.process_material
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		cpu.emitting = false
		cpu.process_material = cpu.process_material
	elif node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		mesh_inst.mesh = mesh_inst.mesh
		mesh_inst.material_override = mesh_inst.material_override

	for child in node.get_children():
		_prime_visual_resources(child)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build(): return # 이 디버그 키들은 릴리즈 빌드에서는 작동하지 않음
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: # 강제 레벨업
				print("[DEBUG] 강제 레벨업!")
				_set_level(current_level + 1)
			KEY_F2: # 대포 디버그
				_debug_cannons()
			KEY_M: # 메타 업그레이드 상점 (테스트용)
				show_meta_shop()


func _process(delta: float) -> void:
	current_time += delta
	
	# 스테이지 클리어 조건: 일정 시간 생존
	if current_time >= survival_victory_time:
		show_victory()
		return
	
	# 보스 등장 체크 (10분 = 600초)
	if current_time >= boss_spawn_time and not _boss_triggered:
		_boss_triggered = true
		if enemy_spawner:
			enemy_spawner.trigger_boss_event()
	
	# 난이도 자동 증가 (시간 기반)
	var new_difficulty = int(current_time / level_duration) + 1
	new_difficulty = min(new_difficulty, max_level)
	
	if new_difficulty > game_difficulty:
		game_difficulty = new_difficulty
		_update_difficulty()
		if hud and hud.has_method("update_difficulty_ui"):
			hud.update_difficulty_ui(game_difficulty)
		print("[Difficulty] 난이도 상승! Level %d (적 강화)" % game_difficulty)
	
	# 주기적으로 적 수 체크 (HUD용)
	if Engine.get_process_frames() % 30 == 0:
		_update_enemy_count_ui()

func _update_enemy_count_ui() -> void:
	if hud:
		var count = get_tree().get_nodes_in_group("enemy").size()
		hud.update_enemy_count(count)

func add_score(points: int) -> void:
	current_score += points
	enemies_killed += 1
	score_changed.emit(current_score)
	
	# 실시간 골드 저장
	if is_instance_valid(SaveManager):
		SaveManager.add_gold(points)
	
	if hud:
		hud.update_score(current_score)

func add_ship_sunk(count: int = 1) -> void:
	ships_sunk += max(0, count)
	if hud and hud.has_method("update_combat_stats"):
		hud.update_combat_stats(ships_sunk, soldiers_killed)

func add_soldier_kill(count: int = 1) -> void:
	soldiers_killed += max(0, count)
	if hud and hud.has_method("update_combat_stats"):
		hud.update_combat_stats(ships_sunk, soldiers_killed)

func add_command_xp_from_soldier_kill(kill_count: int = 1) -> void:
	var k = max(0, kill_count)
	if k <= 0:
		return
	add_merit(merit_per_soldier_kill * k)

func add_player_weapon_damage(source_id: String, amount: float) -> void:
	if source_id.is_empty():
		return
	if amount <= 0.0:
		return
	var current = float(weapon_damage_stats.get(source_id, 0.0))
	weapon_damage_stats[source_id] = current + amount

func get_total_weapon_damage() -> float:
	var total := 0.0
	for key in weapon_damage_stats.keys():
		total += float(weapon_damage_stats[key])
	return total

func get_weapon_damage_rows(max_rows: int = 8) -> Array:
	var rows: Array = []
	for key in weapon_damage_stats.keys():
		var dmg = float(weapon_damage_stats[key])
		if dmg <= 0.0:
			continue
		rows.append({
			"id": key,
			"name": DAMAGE_SOURCE_NAME.get(key, key),
			"damage": dmg
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("damage", 0.0)) > float(b.get("damage", 0.0))
	)
	if rows.size() > max_rows:
		return rows.slice(0, max_rows)
	return rows


## XP 획득 및 레벨업 처리
func add_xp(amount: int) -> void:
	current_xp += int(amount * xp_multiplier)
	
	if hud and hud.has_method("update_xp"):
		hud.update_xp(current_xp, xp_to_next_level)
	
	if current_xp >= xp_to_next_level:
		current_xp -= xp_to_next_level
		_set_level(current_level + 1)

## 공적 (Merit) 획득
func add_merit(amount: int) -> void:
	if merit_points >= max_merit_points: return # 이미 꽉 찼으면 무시
	
	merit_points = min(merit_points + amount, max_merit_points)
	merit_changed.emit(merit_points, max_merit_points, merit_level)
	
	if hud and hud.has_method("update_merit"):
		hud.update_merit(merit_points, max_merit_points, merit_level)
		
	if merit_points >= max_merit_points:
		merit_full.emit()
		print("[Command] 지휘 포인트가 가득 찼습니다! 병사 업그레이드를 시작합니다.")
		consume_merit() # 자동 소비 및 UI 팝업
		
func consume_merit() -> void:
	# 공적 소비 시 병사 업그레이드 UI를 띄움
	_show_fleet_upgrade_ui()
	
	merit_points = 0
	merit_changed.emit(merit_points, max_merit_points, merit_level)
	if hud and hud.has_method("update_merit"):
		hud.update_merit(merit_points, max_merit_points, merit_level)


func _show_fleet_upgrade_ui() -> void:
	if not is_instance_valid(UpgradeManager): return
	
	# 지휘 업그레이드 선택지 (병사 + 해금 시 함대)
	var choices = UpgradeManager.get_command_upgrade_choices(3)
	if choices.is_empty():
		# 병사 업그레이드가 더 이상 없으면 레벨만 올리고 종료
		_finalize_merit_levelup("")
		return
		
	get_tree().paused = true
	
	if is_instance_valid(_upgrade_ui_instance):
		_upgrade_ui_instance.queue_free()
		
	_upgrade_ui_instance = upgrade_ui_scene.instantiate()
	add_child(_upgrade_ui_instance)
	
	# 지휘 업그레이드용 특별 라벨 설정
	if _upgrade_ui_instance.has_node("VBox/TitleLabel"):
		_upgrade_ui_instance.get_node("VBox/TitleLabel").text = "지휘 강화 (병사/함대)"
	
	# 지휘 레벨업은 리롤권 0개 고정
	_upgrade_ui_instance.show_upgrades(choices, 0)
	
	# 전용 콜백 연결
	_upgrade_ui_instance.upgrade_chosen.connect(_on_fleet_upgrade_chosen)


func _on_fleet_upgrade_chosen(upgrade_id: String) -> void:
	# 병사 업그레이드 적용
	UpgradeManager.apply_upgrade(upgrade_id)
	
	# 지휘 레벨 수치 상승 처리
	_finalize_merit_levelup(upgrade_id)
	
	# UI 제거 및 게임 재개
	if is_instance_valid(_upgrade_ui_instance):
		_upgrade_ui_instance.queue_free()
		_upgrade_ui_instance = null
	
	get_tree().paused = false


func _finalize_merit_levelup(upgrade_id: String) -> void:
	merit_level += 1
	max_merit_points = _get_merit_requirement(merit_level)
	
	print("[Command] Troop Upgraded! Level %d (%s)" % [merit_level, upgrade_id])
	
	if hud and hud.has_method("update_merit"):
		hud.update_merit(merit_points, max_merit_points, merit_level)


func _calculate_next_level_xp() -> void:
	# 레벨업 공식: base * (level ^ exponent)
	# 조정 가능한 곡선으로 관리
	xp_to_next_level = max(1, int(level_xp_base * pow(current_level, level_xp_exponent)))


func _get_merit_requirement(level: int) -> int:
	# 공적 레벨 요구량: base + (level - 1) * growth
	return max(1, merit_base_points + (level - 1) * merit_growth_per_level)

var upgrade_ui_scene: PackedScene = preload("res://scenes/ui/upgrade_ui.tscn")
var meta_upgrade_ui_scene: PackedScene = preload("res://scenes/ui/meta_upgrade_ui.tscn")
var _upgrade_ui_instance: CanvasLayer = null

func _set_level(new_level: int) -> void:
	current_level = new_level # 플레이어 레벨은 제한 없음 (보급/돈 무한 가능)
	_calculate_next_level_xp()
	
	level_up.emit(current_level)
	if hud:
		hud.update_level(current_level)
	
	print("[LevelUp] Level Up! Lv.%d (Next XP: %d)" % [current_level, xp_to_next_level])
	
	# === 레벨업 보상 ===
	# 1. 골드 보상
	add_score(5) # 점수 겸 골드 +5
	
	# 2. 선체 강화 (+20 Max HP, 최대 상한 적용)
	var ship = UpgradeManager._get_player_ship()
	if ship:
		ship.max_hull_hp = minf(ship.max_hull_hp + 20.0, max_hull_hp_cap)
		ship.hull_hp = minf(ship.hull_hp + 20.0, ship.max_hull_hp)
		if hud: hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	
	# 3. 리롤권 지급 (기본 1회 + 영구 업그레이드 보너스)
	var reroll_bonus := 0
	if is_instance_valid(MetaManager) and MetaManager.has_method("get_reroll_bonus"):
		reroll_bonus = int(MetaManager.get_reroll_bonus())
	rerolls_available = 1 + reroll_bonus
	
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("level_up")
	
	_show_upgrade_ui(3) # 일반 레벨업은 3개 선택지


func _show_upgrade_ui(choice_count: int = 3) -> void:
	if not is_instance_valid(UpgradeManager):
		return
	
	var choices = UpgradeManager.get_ship_upgrade_choices(choice_count)
	if choices.is_empty():
		return
	
	# 게임 일시정지 (이미 일시정지 중일 수 있음 - 상자 획득 시)
	get_tree().paused = true
	
	# UI 생성 (기존 UI가 있다면 제거)
	if is_instance_valid(_upgrade_ui_instance):
		_upgrade_ui_instance.queue_free()
		
	_upgrade_ui_instance = upgrade_ui_scene.instantiate()
	add_child(_upgrade_ui_instance)
	_upgrade_ui_instance.upgrade_chosen.connect(_on_upgrade_chosen)
	_upgrade_ui_instance.reroll_requested.connect(_on_reroll_requested)
	
	# 상자 보상인 경우 리롤권을 더 줄 수 있음 (현재는 레벨업 로직과 동일하게 1개 유지 확인)
	_upgrade_ui_instance.show_upgrades(choices, rerolls_available)


func _on_reroll_requested() -> void:
	if rerolls_available > 0:
		rerolls_available -= 1
		
		var choices = UpgradeManager.get_ship_upgrade_choices(3)
		if _upgrade_ui_instance:
			_upgrade_ui_instance.show_upgrades(choices, rerolls_available)
			print("[Reroll] Reroll 사용! (남은 횟수: %d)" % rerolls_available)


func _on_upgrade_chosen(upgrade_id: String) -> void:
	# 업그레이드 적용
	UpgradeManager.apply_upgrade(upgrade_id)
	
	# UI 제거
	if is_instance_valid(_upgrade_ui_instance):
		_upgrade_ui_instance.queue_free()
		_upgrade_ui_instance = null
	
	# 게임 재개
	get_tree().paused = false


func _update_difficulty() -> void:
	if not enemy_spawner:
		return
		
	# 난이도는 game_difficulty를 따름
	var data = level_data.get(game_difficulty, level_data[max_level])
	
	# 스포너 설정 업데이트
	if enemy_spawner.has_method("set_difficulty"):
		enemy_spawner.set_difficulty(
			data["spawn_interval"],
			data["max_enemies"],
			data.get("boarders", 2)
		)


func _debug_cannons() -> void:
	var ship = get_tree().get_nodes_in_group("player")
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
	var enemies = get_tree().get_nodes_in_group("enemy")
	print("[DEBUG] 적 수: %d" % enemies.size())
	for e in enemies:
		print("[DEBUG]   적 [%s] pos=%s" % [e.name, e.global_position])
	print("[DEBUG] ========================================")


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
