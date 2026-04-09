@tool
extends "res://scripts/entities/ships/base_ship.gd"


## 배 핵심 로직: 실제 범선 물리, 러더 조향, 둥실둥실 효과

var team: String = "player"

# === 이동 관련 ===
@export var rowing_speed: float = 4.8 # 노 젓기 체감 상향


const CHASER_SHIP_SCRIPT = preload("res://scripts/entities/ships/chaser_ship.gd")
const SoldierRulesData = preload("res://scripts/helpers/soldier_rules_data.gd")
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const ENEMY_SHIP_SCENE = preload("res://scenes/ships/enemy_ship.tscn")
const MAENGSEON_HULL_SCENE = preload("res://scenes/ships/hulls/maengseon_hull.tscn")
const JOSEON_CANNON_SCENE = preload("res://scenes/entities/launchers/cannon_joseon.tscn")
const SOLDIER_SCENE = preload("res://scenes/entities/soldiers/soldier.tscn")
const PlayerShipCrewHelper = preload("res://scripts/entities/ships/player_ship_crew_helper.gd")
const PlayerShipMovementHelper = preload("res://scripts/entities/ships/player_ship_movement_helper.gd")
const PlayerShipSinkHelper = preload("res://scripts/entities/ships/player_ship_sink_helper.gd")
const PlayerShipRuntimeHelper = preload("res://scripts/entities/ships/player_ship_runtime_helper.gd")
const PlayerShipAuxHelper = preload("res://scripts/entities/ships/player_ship_aux_helper.gd")
const PlayerShipSupportHelper = preload("res://scripts/entities/ships/player_ship_support_helper.gd")

# === 러더(키) 관련 ===

@export var rudder_speed: float = 120.0 # 러더 회전 속도 (60 -> 120 상향)
@export var rudder_return_speed: float = 80.0 # 러더 자동 복귀 속도 (40 -> 80 상향)
# === 둥실둥실 효과 및 육분의 ===

@export var rudder_turn_speed: float = 120.0 # Seamanship에 의해 강화됨

@export var ship_type: String = "panokseon_player":
	set(value):
		ship_type = value
		if Engine.is_editor_hint():
			_update_editor_hull()

@export var hull_scene: PackedScene = preload("res://scenes/ships/hulls/panokseon_hull.tscn")
@export var has_sextant: bool = false # Sextant 아이템 소지 여부

# === 노 젓기 ===
var is_rowing: bool = false
var rowing_locked: bool = false
@export var sail_turn_speed: float = 60.0
@export var sail_efficiency_mult: float = 1.0
@export var max_rowing_stamina: float = 100.0
@export var rowing_stamina: float = 100.0
@export var rowing_acceleration_mult: float = 1.0
@export_range(0.2, 0.9, 0.05) var exhausted_rowing_speed_ratio: float = 0.55
@export var stamina_recovery_unlock_threshold: float = 25.0
@export var stamina_drain_rate: float = 10.0 # 노 젓기 시 스태미나 소모 속도 완화
@export var stamina_recovery_rate: float = 6.5

@export var max_crew_count: int = 5 # 아군 병사 정원 (일반 병사 4 + 장군 1)
@export_range(0, 1, 1) var captain_count: int = 1
@export_range(1.0, 3.0, 0.05) var captain_health_multiplier: float = 1.65
@export_range(1.0, 3.0, 0.05) var captain_attack_multiplier: float = 1.4
@export_range(0.0, 10.0, 0.5) var captain_defense_bonus: float = 2.0
@export var support_fleet_limit: int = 1
@export var support_fleet_respawn_interval: float = 30.0
var support_fleet_respawn_timer: float = 0.0
@export_enum("roundshot", "chainshot", "grapeshot") var current_cannon_ammo: String = "roundshot"

@onready var ship_audio: AudioStreamPlayer3D = $ShipAudio

var _cached_um: Node = null
var _cached_wind_manager: Node = null

# 부착된 선원(병사) 정보 (동적)# 길군악(노동요) 재생 상태
var _gilgunak_playing: bool = false
var current_crew_count: int = 5

var _flap_timer: float = 0.0
var _wave_timer: float = 2.0
var _current_wind_intake: float = 1.0 # 0.0(쳐짐) ~ 1.0(빵빵함)
var _oars_timer: float = 0.0
var _oar_time: float = 0.0

# 성능 최적화: ships 그룹 캐싱 (프레임당 1회 조회)
static var _cached_ships: Array = []
static var _last_ships_frame: int = -1

static func _get_ships_cached(tree: SceneTree) -> Array:
	var f = Engine.get_physics_frames()
	if f != _last_ships_frame:
		_cached_ships = EntityRegistry.get_ships()
		_last_ships_frame = f
	return _cached_ships


# === 병사 자동 보충 ===
@export var crew_respawn_interval: float = 12.0 # 보충 주기 (초)
@export_range(1, 20, 1) var survivor_merit_reward: int = 5
var crew_respawn_timer: float = 0.0

# === 자동 공세 월선 (보수적 전술 판단) ===
@export_group("Auto Raid")
@export var auto_raid_enabled: bool = true
@export_range(0.1, 2.0, 0.05) var auto_raid_eval_interval: float = 0.35
@export_range(1, 3, 1) var auto_raid_max_boarders: int = 2
@export_range(1, 8, 1) var auto_raid_min_defenders: int = 3
@export_range(8.0, 28.0, 0.5) var auto_raid_threat_range: float = 18.0
@export_range(0.0, 1.0, 0.01) var auto_raid_min_hull_ratio: float = 0.45
var auto_raid_eval_timer: float = 0.0
var auto_raid_target: Node3D = null

# === 방어 무기 (화통) 로직 변수 ===
var fire_pot_cooldown_timer: float = 0.0
var fire_pot_scene: PackedScene = preload("res://scenes/projectiles/fire_pot.tscn")

var boarding_scan_timer: float = 0.0
const CREW_ROLE_GENERAL := "general"
const CREW_ROLE_SPEARMAN := "spearman"
const CREW_ROLE_FIRE_POT := "fire_pot"
const CREW_ROLE_REPEATING_CROSSBOW := "repeating_crossbow"
const CREW_ROLE_SINGIGEON := "singigeon"

func _update_editor_hull() -> void:
	# 에디터 전용: 선체 미리보기 갱신
	for child in get_children():
		if child.name.contains("Hull"):
			child.queue_free()
			
	var stats = load_ship_stats(ship_type)
	if stats.is_empty(): return
	
	var type_lower = ship_type.to_lower()
	var h_path = "res://scenes/ships/hulls/panokseon_hull.tscn"
	if type_lower.contains("sekibune"): h_path = "res://scenes/ships/hulls/sekibune_hull.tscn"
	elif type_lower.contains("atakebune"): h_path = "res://scenes/ships/hulls/atakebune_hull.tscn"
	elif type_lower.contains("maengseon"): h_path = "res://scenes/ships/hulls/maengseon_hull.tscn"
	
	var new_hull = load(h_path)
	if new_hull:
		var inst = new_hull.instantiate()
		inst.name = "EditorHull"
		add_child(inst)
		_cache_hull_references(self )

func _ready() -> void:
	if Engine.is_editor_hint():
		# 에디터용 Hull이 이미 있다면 중복 생성 방지
		var has_hull = false
		for child in get_children():
			if child.name.contains("Hull"):
				has_hull = true
				break
		if not has_hull:
			_update_editor_hull()
		return

	_apply_soldier_rules_data()
	super._ready()
	fire_effect_offset = Vector3(0, 1.0, 0.0)
	print("[Ship] Total masts connected: ", masts.size())
	
	# 영구 업그레이드 보너스 적용
	if is_in_group("player") or is_player_controlled:
		var meta_manager = get_node_or_null("/root/MetaManager")
		if is_instance_valid(meta_manager):
			if meta_manager.has_method("get_hull_hp_bonus"): max_hull_hp += meta_manager.get_hull_hp_bonus()
			if meta_manager.has_method("get_sail_speed_multiplier"): max_speed *= meta_manager.get_sail_speed_multiplier()
			if meta_manager.has_method("get_hull_defense_bonus"): hull_defense = meta_manager.get_hull_defense_bonus()
			if meta_manager.has_method("get_max_crew_bonus"): max_crew_count += int(meta_manager.get_max_crew_bonus())
		print("[Ship] 플레이어 배 초기화 (HP: %.0f, 속도: %.1f, 방어: %.1f, 병사 정원: %d)" % [max_hull_hp, max_speed, hull_defense, max_crew_count])
	
	
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	hull_hp = max_hull_hp
	if is_player_controlled:
		add_to_group("player")
	
	_cache_references()
	if not _probe_flag_enabled("BATTLESHIP_SKIP_PLAYER_CREW_SYNC"):
		_sync_player_crew_roster()
	if not has_meta("base_support_fleet_limit"):
		set_meta("base_support_fleet_limit", support_fleet_limit)
	if not has_meta("base_support_fleet_respawn_interval"):
		set_meta("base_support_fleet_respawn_interval", support_fleet_respawn_interval)


func _apply_soldier_rules_data() -> void:
	var captain_rules: Dictionary = SoldierRulesData.get_section("captain")
	if captain_rules.is_empty():
		return
	captain_count = clampi(int(captain_rules.get("count", captain_count)), 0, max_crew_count)
	captain_health_multiplier = float(captain_rules.get("health_multiplier", captain_health_multiplier))
	captain_attack_multiplier = float(captain_rules.get("attack_multiplier", captain_attack_multiplier))
	captain_defense_bonus = float(captain_rules.get("defense_bonus", captain_defense_bonus))

func _cache_references() -> void:
	_cached_level_manager = LevelManagerRegistry.get_level_manager(get_tree())
	if _cached_level_manager and "hud" in _cached_level_manager:
		_cached_hud = _cached_level_manager.hud
		
	_cached_um = get_tree().root.find_child("UpgradeManager", true, false)
	if is_player_controlled and is_instance_valid(_cached_um) and not _probe_flag_enabled("BATTLESHIP_SKIP_PLAYER_UPGRADE_BOOTSTRAP"):
		if _cached_um.has_method("equip_owned_items"):
			_cached_um.call_deferred("equip_owned_items")
		if _cached_um.has_method("refresh_hud_item_icons"):
			_cached_um.call_deferred("refresh_hud_item_icons")


func _probe_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_sinking or is_dying:
		return
	_update_sail_visual()
	_update_rudder_visual()
	_update_fire_effect()


# === 제어 관련 ===
@export var is_player_controlled: bool = true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if is_sinking or is_dying:
		return
	
	# 기본 물리 프로세스 (둥실거림 등)
	super._physics_process(delta)
	if _flap_timer > 0:
		_flap_timer -= delta
		
	if current_speed > 0.5:
		_wave_timer -= delta
		if _wave_timer <= 0:
			if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
				_cached_audio_manager.play_sfx("wave_splash", global_position, randf_range(0.8, 1.2), 3.0)
			# 속도가 빠를수록 자주, 느릴수록 드문드문 (최소 1.5초 ~ 최대 4.5초)
			var speed_mod = clamp(current_speed / 5.0, 0.2, 2.0)
			_wave_timer = randf_range(1.5, 3.5) / speed_mod
		
	if is_player_controlled:
		_handle_input(delta)
	if has_sextant:
		_auto_adjust_sail(delta)
	update_crew_allocation_state(delta)
	_update_movement(delta)
	_update_steering(delta)
	_update_rowing_stamina(delta)
	_update_oar_visual(delta)
	_update_hull_regeneration(delta)
	_update_burning_status(delta)
	_update_boarding_state(delta)
	_update_support_fleet_respawn(delta)
	_update_crew_respawn(delta)
	_update_auto_boarding_raid(delta)
	_update_fire_pot_logic(delta)
	
	if is_boarding:
		_process_boarding_common(delta)
		
	PlayerShipRuntimeHelper.update_rowing_audio(self, delta)
				

func _unhandled_input(event: InputEvent) -> void:
	if is_sinking or is_dying or not is_player_controlled: return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			cycle_cannon_ammo()
			return
		# 치트키: F2 누르면 바로 지휘(병영) 레벨업
		if OS.is_debug_build() and event.keycode == KEY_F2:
			if is_instance_valid(_cached_level_manager):
				_cached_level_manager.add_merit(999)
				
		# if event.keycode == KEY_F:
		# 	_execute_merit_action()
		pass

func _execute_merit_action() -> void:
	if not is_instance_valid(_cached_level_manager): return
		
	if _cached_level_manager.merit_points < _cached_level_manager.max_merit_points:
		if _cached_hud and _cached_hud.has_method("show_message"):
			_cached_hud.show_message("지휘 포인트가 부족합니다!", 1.5)
		return
		
	# 지휘 포인트 소비 (병영 업그레이드 UI)
	_cached_level_manager.consume_merit()

func _spawn_or_repair_ally() -> void:
	PlayerShipSupportHelper.spawn_or_repair_ally(self)

func _get_support_fleet_ships() -> Array:
	return PlayerShipSupportHelper.get_support_fleet_ships(self)

func _get_offscreen_ally_spawn_position() -> Vector3:
	return PlayerShipSupportHelper.get_offscreen_ally_spawn_position(self)

## 병사 자동 보충 로직
func _update_crew_respawn(delta: float) -> void:
	if is_sinking: return
	if deck_is_contested:
		return
	
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	# 현재 살아있는 아군 병사 수 체크
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4 and child.get("team") == "player": # 4 = DEAD
			alive_count += 1
			
	if alive_count < max_crew_count:
		crew_respawn_timer += delta
		if crew_respawn_timer >= crew_respawn_interval:
			crew_respawn_timer = 0.0
			add_survivor() # 기존의 add_survivor 로직 재사용 (HUD 메시지 포함됨)
			_sync_player_crew_roster()
			print("[Crew] 자동 보충! 아군 병사가 합류했습니다. (현재: %d/%d)" % [alive_count + 1, max_crew_count])
	else:
		crew_respawn_timer = 0.0 # 정원이 차면 타이머 초기화

func _update_auto_boarding_raid(delta: float) -> void:
	PlayerShipCrewHelper.update_auto_boarding_raid(self, delta)

func _update_support_fleet_respawn(delta: float) -> void:
	PlayerShipSupportHelper.update_support_fleet_respawn(self, delta)

func _get_desired_player_crew_roles() -> Dictionary:
	return PlayerShipCrewHelper.get_desired_player_crew_roles(self)

func _get_soldier_role(soldier: Node) -> String:
	return PlayerShipCrewHelper.get_soldier_role(self, soldier)

func _spawn_player_soldier(soldiers_node: Node, role: String) -> Node:
	return PlayerShipCrewHelper.spawn_player_soldier(self, soldiers_node, role)

func _sync_player_crew_roster() -> void:
	PlayerShipCrewHelper.sync_player_crew_roster(self)

## 키보드 입력 처리
func _handle_input(delta: float) -> void:
	PlayerShipRuntimeHelper.handle_input(self, delta)

func _toggle_fleet_formation() -> void:
	PlayerShipRuntimeHelper.toggle_fleet_formation(self)


## 러더 조향 입력 처리
## direction: -1.0 (왼쪽), 1.0 (오른쪽), 0.0 (중립)
func steer(direction: float, delta: float) -> void:
	var rudder_response_mult: float = get_rudder_response_multiplier()
	if direction < -0.1:
		rudder_angle = move_toward(rudder_angle, -45.0, rudder_speed * rudder_response_mult * delta)
	elif direction > 0.1:
		rudder_angle = move_toward(rudder_angle, 45.0, rudder_speed * rudder_response_mult * delta)
	else:
		# 입력이 없으면 러더 자동 복귀
		rudder_angle = move_toward(rudder_angle, 0.0, rudder_return_speed * rudder_response_mult * delta)

func _auto_adjust_sail(delta: float) -> void:
	PlayerShipMovementHelper.auto_adjust_sail(self, delta)

func _calculate_separation() -> Vector3:
	return PlayerShipMovementHelper.calculate_separation(self)

## 도선(밧줄) 연결 시 이동 방해(Snare/Drag) 배수 계산
func _get_boarding_drag_multiplier() -> float:
	return PlayerShipMovementHelper.get_boarding_drag_multiplier(self)

## 이동 업데이트
func _update_movement(delta: float) -> void:
	PlayerShipMovementHelper.update_movement(self, delta)

func _update_steering(delta: float) -> void:
	PlayerShipMovementHelper.update_steering(self, delta)


## 실제 범선 물리: 돛 기반 속도 계산
func _calculate_sail_speed() -> float:
	return PlayerShipMovementHelper.calculate_sail_speed(self)


## 동양식 노(Ro/Yuloh) 8자 젓기 애니메이션
func _update_oar_visual(delta: float) -> void:
	PlayerShipMovementHelper.update_oar_visual(self, delta)

## 노 젓기 스태미나 관리
func _update_rowing_stamina(delta: float) -> void:
	PlayerShipMovementHelper.update_rowing_stamina(self, delta)


## === 공개 메서드 ===

## 돛 각도 설정
func set_sail_angle(angle: float) -> void:
	sail_angle = clamp(angle, -90.0, 90.0)


## 돛 각도 조정
func adjust_sail_angle(delta_angle: float) -> void:
	if abs(delta_angle) > 0.0 and _flap_timer <= 0:
		var audio_manager = get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("sail_flap", global_position, randf_range(0.8, 1.2))
		_flap_timer = randf_range(1.5, 3.0)
		
	set_sail_angle(sail_angle + delta_angle)


## 노 젓기 활성화/비활성화
func set_rowing(active: bool) -> void:
	is_rowing = active


## 노 젓기 토글
func toggle_rowing() -> void:
	is_rowing = not is_rowing


func cycle_cannon_ammo() -> void:
	var ammo_order: Array[String] = ["roundshot", "chainshot", "grapeshot"]
	var current_index: int = ammo_order.find(current_cannon_ammo)
	if current_index < 0:
		current_index = 0
	current_cannon_ammo = ammo_order[(current_index + 1) % ammo_order.size()]
	if _cached_hud and _cached_hud.has_method("show_message"):
		_cached_hud.show_message("탄종: %s" % _get_cannon_ammo_display_name(), 1.1)


func _get_cannon_ammo_display_name() -> String:
	match current_cannon_ammo:
		"chainshot":
			return "사슬탄"
		"grapeshot":
			return "포도탄"
		_:
			return "실선탄"


## === 선체 내구도 시스템 ===

## 게임 오버 (침몰)
func die() -> void:
	PlayerShipSinkHelper.die(self)

func _disable_combat_modules_on_sink() -> void:
	PlayerShipSinkHelper.disable_combat_modules_on_sink(self)

func _disable_combat_subtree(node: Node) -> void:
	PlayerShipSinkHelper.disable_combat_subtree(self, node)

# 재귀적으로 모든 메쉬의 transparency속성을 트윈합니다.
func _fade_out_meshes(node: Node, tween: Tween, duration: float) -> void:
	PlayerShipSinkHelper.fade_out_meshes(self, node, tween, duration)


func _find_hud() -> Node:
	return PlayerShipSinkHelper.find_hud(self)


## 장군전 등 물체가 배에 박혔을 때 호출
func add_stuck_object(obj: Node3D, s_mult: float, t_mult: float) -> void:
	PlayerShipAuxHelper.add_stuck_object(self, obj, s_mult, t_mult)

func remove_stuck_object(obj: Node3D, s_mult: float, t_mult: float) -> void:
	PlayerShipAuxHelper.remove_stuck_object(self, obj, s_mult, t_mult)

## 폐선 나포 (Capture Derelict Ship) 보상 처리
func capture_derelict_ship() -> void:
	PlayerShipRuntimeHelper.capture_derelict_ship(self)

## 병사 보충 (Maintenance 전용)
func replenish_crew(soldier_scene: PackedScene) -> void:
	PlayerShipRuntimeHelper.replenish_crew(self, soldier_scene)

## 생존자 구조 및 병사 합류 처리
func add_survivor() -> bool:
	return PlayerShipCrewHelper.add_survivor(self)

## 갑판 방어 무기 2: 화통 투척 로직 (병사가 수행)
func _update_fire_pot_logic(delta: float) -> void:
	PlayerShipCrewHelper.update_fire_pot_logic(self, delta)
