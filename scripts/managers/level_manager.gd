extends Node

## 레벨 매니저 (Level Manager)
## 게임 시간 경과에 따라 난이도(레벨)를 관리하고 스포너에게 지시

signal level_up(new_level: int)
signal score_changed(new_score: int)
signal enemy_destroyed_count(count: int)

@export var level_duration: float = 45.0 # 난이도 증가 간격 (초)
@export var boss_spawn_time: float = 600.0 # 보스 등장 시간 (초, 기본 10분)
@export var max_level: int = 15
@export var max_hull_hp_cap: float = 400.0 # 레벨업 HP 보너스 상한 (Phase 3 밸런싱)
@export var hud: CanvasLayer = null

var current_level: int = 1
var current_xp: int = 0
var xp_to_next_level: int = 0
var xp_multiplier: float = 1.0 # 업그레이드로 강화 가능
var game_difficulty: int = 1 # 적 난이도 레벨

var current_score: int = 0
var current_time: float = 0.0
var enemies_killed: int = 0
var _boss_triggered: bool = false
var rerolls_available: int = 0

# 레벨별 난이도 설정 (밸런스 조정)
# spawn_interval: 적 생성 간격 (초)
# max_enemies: 동시 최대 적 수
# enemy_speed: 적 이동 속도
# enemy_hp: 적 체력
# boarders: 도선 병사 수
var level_data = {
	1: {"spawn_interval": 6.0, "max_enemies": 2, "enemy_speed": 3.0, "enemy_hp": 3.0, "boarders": 1},
	2: {"spawn_interval": 5.5, "max_enemies": 3, "enemy_speed": 3.2, "enemy_hp": 4.0, "boarders": 1},
	3: {"spawn_interval": 5.0, "max_enemies": 4, "enemy_speed": 3.5, "enemy_hp": 5.0, "boarders": 2},
	4: {"spawn_interval": 4.5, "max_enemies": 5, "enemy_speed": 3.5, "enemy_hp": 5.0, "boarders": 2},
	5: {"spawn_interval": 4.0, "max_enemies": 6, "enemy_speed": 3.8, "enemy_hp": 6.0, "boarders": 2},
	6: {"spawn_interval": 3.5, "max_enemies": 7, "enemy_speed": 3.8, "enemy_hp": 7.0, "boarders": 3},
	7: {"spawn_interval": 3.5, "max_enemies": 8, "enemy_speed": 4.0, "enemy_hp": 8.0, "boarders": 3},
	8: {"spawn_interval": 3.0, "max_enemies": 10, "enemy_speed": 4.0, "enemy_hp": 8.0, "boarders": 3},
	9: {"spawn_interval": 3.0, "max_enemies": 10, "enemy_speed": 4.2, "enemy_hp": 9.0, "boarders": 3},
	10: {"spawn_interval": 2.5, "max_enemies": 12, "enemy_speed": 4.5, "enemy_hp": 10.0, "boarders": 4},
	11: {"spawn_interval": 2.5, "max_enemies": 12, "enemy_speed": 4.5, "enemy_hp": 12.0, "boarders": 4},
	12: {"spawn_interval": 2.0, "max_enemies": 15, "enemy_speed": 4.8, "enemy_hp": 14.0, "boarders": 4},
	13: {"spawn_interval": 2.0, "max_enemies": 15, "enemy_speed": 5.0, "enemy_hp": 16.0, "boarders": 5},
	14: {"spawn_interval": 1.5, "max_enemies": 18, "enemy_speed": 5.2, "enemy_hp": 18.0, "boarders": 5},
	15: {"spawn_interval": 1.5, "max_enemies": 20, "enemy_speed": 5.5, "enemy_hp": 20.0, "boarders": 6},
}

# 참조
@export var enemy_spawner: Node = null

func _ready() -> void:
	add_to_group("level_manager")
	_calculate_next_level_xp()
	
	# 초기 HUD 업데이트
	if hud:
		hud.update_level(current_level)
		hud.update_score(current_score)
		hud.update_xp(current_xp, xp_to_next_level)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build(): return # 이 디버그 키들은 릴리즈 빌드에서는 작동하지 않음
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: # 강제 레벨업
				print("🐞 DEBUG: 강제 레벨업!")
				_set_level(current_level + 1)
			KEY_F2: # 대포 디버그
				_debug_cannons()
			KEY_M: # 메타 업그레이드 상점 (테스트용)
				show_meta_shop()


func _process(delta: float) -> void:
	current_time += delta
	
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
		print("🔥 난이도 상승! Level %d (적 강화)" % game_difficulty)
	
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


## XP 획득 및 레벨업 처리
func add_xp(amount: int) -> void:
	current_xp += int(amount * xp_multiplier)
	
	if hud and hud.has_method("update_xp"):
		hud.update_xp(current_xp, xp_to_next_level)
	
	if current_xp >= xp_to_next_level:
		current_xp -= xp_to_next_level
		_set_level(current_level + 1)


func _calculate_next_level_xp() -> void:
	# 레벨업 공식: 16 * (level ^ 1.2)
	# 훨씬 시원시원하게 레벨업 되도록 대폭 상향 조정 (25 -> 16)
	xp_to_next_level = int(16.0 * pow(current_level, 1.2))

var upgrade_ui_scene: PackedScene = preload("res://scenes/ui/upgrade_ui.tscn")
var meta_upgrade_ui_scene: PackedScene = preload("res://scenes/ui/meta_upgrade_ui.tscn")
var _upgrade_ui_instance: CanvasLayer = null

func _set_level(new_level: int) -> void:
	current_level = new_level # 플레이어 레벨은 제한 없음 (보급/돈 무한 가능)
	_calculate_next_level_xp()
	
	level_up.emit(current_level)
	if hud:
		hud.update_level(current_level)
	
	print("⚔️ Level Up! Lv.%d (Next XP: %d)" % [current_level, xp_to_next_level])
	
	# === 레벨업 보상 ===
	# 1. 골드 보상
	add_score(5) # 점수 겸 골드 +5
	
	# 2. 선체 강화 (+10 Max HP, 최대 상한 적용)
	var ship = UpgradeManager._get_player_ship()
	if ship:
		ship.max_hull_hp = minf(ship.max_hull_hp + 10.0, max_hull_hp_cap)
		ship.hull_hp = minf(ship.hull_hp + 10.0, ship.max_hull_hp)
		if hud: hud.update_hull_hp(ship.hull_hp, ship.max_hull_hp)
	
	# 3. 리롤권 지급 (레벨당 1회)
	rerolls_available = 1
	
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("level_up")
	
	_show_upgrade_ui(3) # 일반 레벨업은 3개 선택지


func _show_upgrade_ui(choice_count: int = 3) -> void:
	if not is_instance_valid(UpgradeManager):
		return
	
	var choices = UpgradeManager.get_random_choices(choice_count)
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
		
		var choices = UpgradeManager.get_random_choices(3)
		if _upgrade_ui_instance:
			_upgrade_ui_instance.show_upgrades(choices, rerolls_available)
			print("🎲 Reroll 사용! (남은 횟수: %d)" % rerolls_available)


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
			data["enemy_speed"],
			data.get("enemy_hp", 5.0),
			data.get("boarders", 2)
		)


func _debug_cannons() -> void:
	var ship = get_tree().get_nodes_in_group("player")
	if ship.is_empty():
		print("🐞 플레이어 배 없음!")
		return
	
	var cannons_node = ship[0].get_node_or_null("Cannons")
	if not cannons_node:
		print("🐞 Cannons 노드 없음!")
		return
	
	print("🐞 ============ CANNON DEBUG ============")
	print("🐞 총 대포 수: %d" % cannons_node.get_child_count())
	
	for cannon in cannons_node.get_children():
		var det_area = cannon.get_node_or_null("DetectionArea")
		var _muzzle = cannon.get_node_or_null("Muzzle") # 현재 사용되지 않으나 디버그용 노드 참조 (TODO: 추후 삭제 검토)
		var overlaps = 0
		var monitoring = false
		if det_area:
			monitoring = det_area.monitoring
			overlaps = det_area.get_overlapping_areas().size() + det_area.get_overlapping_bodies().size()
		
		print("🐞 [%s] pos=%s rot_y=%.1f° monitoring=%s overlaps=%d" % [
			cannon.name,
			cannon.position,
			rad_to_deg(cannon.rotation.y),
			monitoring,
			overlaps
		])
	
	# 적 수도 출력
	var enemies = get_tree().get_nodes_in_group("enemy")
	print("🐞 적 수: %d" % enemies.size())
	for e in enemies:
		print("🐞   적 [%s] pos=%s" % [e.name, e.global_position])
	print("🐞 ========================================")


func update_boss_hp(current: float, maximum: float) -> void:
	if hud and hud.has_method("update_boss_hp"):
		hud.update_boss_hp(current, maximum)


func show_victory() -> void:
	# 실시간 저장이므로 여기서는 메시지만 처리
	print("💰 승리! 현재 판에서 %d 골드 획득" % current_score)
	
	if hud and hud.has_method("show_victory"):
		hud.show_victory()


func show_meta_shop() -> void:
	if not meta_upgrade_ui_scene: return
	
	get_tree().paused = true
	var shop = meta_upgrade_ui_scene.instantiate()
	add_child(shop)
	shop.closed.connect(func(): get_tree().paused = false)
