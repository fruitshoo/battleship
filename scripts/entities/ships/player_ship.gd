@tool
extends "res://scripts/entities/ships/base_ship.gd"


## 배 핵심 로직: 실제 범선 물리, 러더 조향, 둥실둥실 효과

var team: String = "player"

# === 이동 관련 ===
@export var rowing_speed: float = 4.8 # 노 젓기 체감 상향


const CHASER_SHIP_SCRIPT = preload("res://scripts/entities/ships/chaser_ship.gd")
const SOLDIER_SCENE = preload("res://scenes/entities/soldiers/soldier.tscn")
const PLAYER_DEFAULT_WOOD_SPLINTER_SCENE = preload("res://scenes/effects/wood_splinter.tscn")
const PLAYER_DEFAULT_WATER_SPLASH_SCENE = preload("res://scenes/effects/water_burst.tscn")
const PLAYER_DEFAULT_FIRE_EFFECT_SCENE = preload("res://scenes/effects/fire_effect.tscn")
const PLAYER_DEFAULT_SURVIVOR_SCENE = preload("res://scenes/effects/survivor.tscn")
const PlayerShipCrewHelper = preload("res://scripts/entities/ships/player_ship_crew_helper.gd")
const PlayerShipMovementHelper = preload("res://scripts/entities/ships/player_ship_movement_helper.gd")
const PlayerShipSinkHelper = preload("res://scripts/entities/ships/player_ship_sink_helper.gd")
const PlayerShipRuntimeHelper = preload("res://scripts/entities/ships/player_ship_runtime_helper.gd")
const PlayerShipAuxHelper = preload("res://scripts/entities/ships/player_ship_aux_helper.gd")
const PlayerSoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")
const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")
const PlayerShipSupportHelper = preload("res://scripts/entities/ships/player_ship_support_helper.gd")
const PhysicsProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

const PLAYER_MIN_VALID_HULL_HP := 100.0
const PLAYER_FALLBACK_HULL_HP := 200.0
const PLAYER_START_NODE_NAME := "PlayerStart"
const PLAYER_RUNTIME_FLOATING_OFFSET := 1.35
const PLAYER_RUNTIME_DECK_HEIGHT := 0.5
const CORPSE_CLEANUP_CARRY_FORWARD_OFFSET := 0.08
const CORPSE_CLEANUP_CARRY_SIDE_OFFSET := 0.08
const CORPSE_CLEANUP_CARRY_HEIGHT_OFFSET := 0.46
const CORPSE_CLEANUP_PICKUP_START_POSITION_META := "corpse_cleanup_pickup_start_position"
const CORPSE_CLEANUP_PICKUP_START_ROTATION_META := "corpse_cleanup_pickup_start_rotation"
const CORPSE_CLEANUP_THROW_ARC_META := "corpse_cleanup_throw_arc"

# === 러더(키) 관련 ===

@export var rudder_speed: float = 120.0 # 러더 회전 속도 (60 -> 120 상향)
@export var rudder_return_speed: float = 80.0 # 러더 자동 복귀 속도 (40 -> 80 상향)
@export_range(0.5, 3.0, 0.05) var player_rudder_turn_authority: float = 1.35 # 플레이어 러더 회전 반응 보정
# === 둥실둥실 효과 및 육분의 ===

@export var rudder_turn_speed: float = 120.0 # Seamanship에 의해 강화됨

@export var ship_type: String = "panokseon_player":
	set(value):
		ship_type = value
		if Engine.is_editor_hint():
			_update_editor_hull()

@export var hull_scene: PackedScene = preload("res://scenes/ships/hulls/panok_hull.tscn")
@export var has_sextant: bool = false # Sextant 아이템 소지 여부

# === 노 젓기 ===
var is_rowing: bool = false
var rowing_direction: int = 1
var rowing_locked: bool = false
@export var sail_turn_speed: float = 60.0
@export var sail_efficiency_mult: float = 1.0
@export_group("Sail Handling")
@export var sail_furled: bool = false
@export_range(0.0, 1.0, 0.01) var sail_deployed_ratio: float = 1.0
@export_range(0.25, 8.0, 0.05) var sail_furl_rate: float = 0.55
@export_range(0.0, 0.35, 0.01) var misaligned_sail_min_thrust_ratio: float = 0.12
@export_range(0.0, 0.25, 0.01) var furled_sail_drive_ratio: float = 0.0
@export_range(1.0, 2.0, 0.05) var furled_sail_rudder_multiplier: float = 1.3
@export_range(1.0, 2.0, 0.05) var furled_sail_rowing_efficiency_multiplier: float = 1.2
@export_range(0.25, 1.0, 0.05) var furled_sail_rowing_stamina_cost_multiplier: float = 0.78
@export_range(0.0, 1.0, 0.05) var furled_sail_fire_damage_multiplier: float = 0.5
@export_group("")
@export var max_rowing_stamina: float = 100.0
@export var rowing_stamina: float = 100.0
@export var rowing_acceleration_mult: float = 1.0
@export_range(0.1, 0.6, 0.05) var reverse_rowing_speed_ratio: float = 0.35
@export_range(0.2, 1.2, 0.05) var reverse_rowing_acceleration_mult: float = 0.70
@export_range(0.2, 1.0, 0.05) var reverse_rudder_turn_authority_mult: float = 0.65
@export_range(0.5, 2.0, 0.05) var reverse_rowing_stamina_cost_mult: float = 1.05
@export_range(0.2, 0.9, 0.05) var exhausted_rowing_speed_ratio: float = 0.38
@export var stamina_drain_rate: float = 8.0
@export var stamina_recovery_rate: float = 8.5

@export var max_crew_count: int = 5 # 아군 병사 정원 (일반 병사 4 + 장군 1)
@export_range(0, 1, 1) var captain_count: int = 1
@export_range(1.0, 3.0, 0.05) var captain_health_multiplier: float = 1.65
@export_range(1.0, 3.0, 0.05) var captain_attack_multiplier: float = 1.4
@export_range(0.0, 10.0, 0.5) var captain_defense_bonus: float = 2.0
@export var support_fleet_limit: int = 1
@export var support_fleet_respawn_interval: float = 30.0
var support_fleet_respawn_timer: float = 0.0

@export_group("Post Combat Cleanup")
@export var corpse_cleanup_enabled: bool = true
@export_range(0.5, 12.0, 0.25) var corpse_cleanup_delay: float = 3.0
@export_range(0.5, 8.0, 0.25) var corpse_cleanup_interval: float = 2.25
@export_range(0.2, 2.0, 0.05) var corpse_cleanup_throw_duration: float = 0.65
var corpse_cleanup_timer: float = 0.0
var corpse_cleanup_peace_timer: float = 0.0

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
var _sail_catch_audio_timer: float = 0.0
var _sail_luff_audio_timer: float = 0.0
var _sail_handling_audio_timer: float = 0.0
var _speed_shift_audio_timer: float = 0.0
var _last_audio_wind_intake: float = 0.0
var _last_audio_speed: float = 0.0

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
var crew_respawn_timer: float = 0.0

# === 자동 공세 월선 (보수적 전술 판단) ===
@export_group("Auto Raid")
@export var auto_raid_enabled: bool = false
@export_range(0.1, 2.0, 0.05) var auto_raid_eval_interval: float = 0.35
@export_range(1, 3, 1) var auto_raid_max_boarders: int = 2
@export_range(1, 8, 1) var auto_raid_min_defenders: int = 3
@export_range(8.0, 28.0, 0.5) var auto_raid_threat_range: float = 18.0
@export_range(0.0, 1.0, 0.01) var auto_raid_min_hull_ratio: float = 0.45
@export_range(12.0, 60.0, 0.5) var manual_boarding_lock_range: float = 34.0
var auto_raid_eval_timer: float = 0.0
var auto_raid_target: Node3D = null
var manual_boarding_target: Node3D = null

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
	_ensure_editor_preview_hull(ship_type, hull_scene)
	_cache_hull_references(self)

func _ready() -> void:
	set_ally_ship_role("player_flagship")
	if Engine.is_editor_hint():
		# 에디터용 Hull이 이미 있다면 중복 생성 방지
		var has_hull = false
		for child in get_children():
			if child.name.contains("Hull"):
				has_hull = true
				break
		if not has_hull:
			_update_editor_hull()
		_cache_hull_references(self)
		_refresh_collision_bounds_from_hull()
		return

	_apply_soldier_rules_data()
	_apply_runtime_scene_safety_defaults()
	var stats := load_ship_stats(ship_type)
	if stats.has("ship_mass_scale"):
		ship_mass_scale = clampf(float(stats["ship_mass_scale"]), 0.35, 4.0)
	_apply_start_marker_transform_from_parent()
	super._ready()
	sail_deployed_ratio = 0.0 if sail_furled else clampf(sail_deployed_ratio, 0.0, 1.0)
	if sail_furled:
		_sync_mast_fold_with_sail_furl(true)
	fire_effect_offset = Vector3(0.0, 0.55, -0.25)
	fire_effect_scale = 1.6
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
	if not has_meta("base_player_max_crew_count"):
		set_meta("base_player_max_crew_count", max_crew_count)
	
	
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


func _apply_runtime_scene_safety_defaults() -> void:
	if max_hull_hp < PLAYER_MIN_VALID_HULL_HP:
		var stats := load_ship_stats(ship_type)
		max_hull_hp = float(stats.get("hull_hp", PLAYER_FALLBACK_HULL_HP))
		hull_hp = max_hull_hp

	wood_splinter_scene = PLAYER_DEFAULT_WOOD_SPLINTER_SCENE
	water_splash_scene = PLAYER_DEFAULT_WATER_SPLASH_SCENE
	fire_effect_scene = PLAYER_DEFAULT_FIRE_EFFECT_SCENE
	survivor_scene = PLAYER_DEFAULT_SURVIVOR_SCENE
	loot_scene = null
	deck_light_player_only = true
	floating_offset = PLAYER_RUNTIME_FLOATING_OFFSET
	var authored_deck_height := ShipAuthoringHelper.get_deck_area_height(self)
	deck_height = authored_deck_height if authored_deck_height > 0.01 else PLAYER_RUNTIME_DECK_HEIGHT

	boarding_contact_grace_duration = 0.5
	boarding_hook_throw_delay = 0.55
	boarding_secondary_rope_delay = 0.45
	boarding_max_relative_speed = 0.28
	boarding_initial_rope_count = 1
	boarding_rope_throw_duration = 0.18


func _apply_start_marker_transform_from_parent() -> void:
	var parent_node := get_parent() as Node3D
	if not is_instance_valid(parent_node):
		return
	var start_marker := parent_node.get_node_or_null(PLAYER_START_NODE_NAME) as Node3D
	if not is_instance_valid(start_marker):
		return
	global_transform = start_marker.global_transform


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
	var direct_upgrade_bootstrap_enabled: bool = _probe_flag_enabled("BATTLESHIP_ENABLE_PLAYER_UPGRADE_BOOTSTRAP")
	if is_player_controlled and is_instance_valid(_cached_um) and direct_upgrade_bootstrap_enabled and not _probe_flag_enabled("BATTLESHIP_SKIP_PLAYER_UPGRADE_BOOTSTRAP"):
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
	var profile_start := PhysicsProfiler.begin()
	
	# 기본 물리 프로세스 (둥실거림 등)
	super._physics_process(delta)
	if _flap_timer > 0:
		_flap_timer -= delta
		
	var motion_speed := absf(current_speed)
	if motion_speed > 0.5:
		_wave_timer -= delta
		if _wave_timer <= 0:
			if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
				_cached_audio_manager.play_sfx("wave_splash", global_position, randf_range(0.8, 1.2), 3.0)
			# 속도가 빠를수록 자주, 느릴수록 드문드문 (최소 1.5초 ~ 최대 4.5초)
			var speed_mod = clamp(motion_speed / 5.0, 0.2, 2.0)
			_wave_timer = randf_range(1.5, 3.5) / speed_mod
		
	if is_player_controlled:
		_handle_input(delta)
	if has_sextant:
		_auto_adjust_sail(delta)
	_update_sail_deployment(delta)
	update_crew_allocation_state(delta)
	_update_movement(delta)
	_update_steering(delta)
	_update_rowing_stamina(delta)
	_update_oar_visual(delta)
	_update_hull_regeneration(delta)
	_update_burning_status(delta)
	_update_rigging_recovery(delta)
	_update_boarding_state(delta)
	var support_profile_start := PhysicsProfiler.begin()
	_update_support_fleet_respawn(delta)
	_update_crew_respawn(delta)
	_update_auto_boarding_raid(delta)
	_update_fire_pot_logic(delta)
	_update_corpse_cleanup(delta)
	PhysicsProfiler.end("player_support_boarding", support_profile_start)
	
	if is_boarding:
		_process_boarding_common(delta)
		
	PlayerShipRuntimeHelper.update_rowing_audio(self, delta)
	PlayerShipRuntimeHelper.update_sail_wind_audio(self, delta)
	PhysicsProfiler.end("player_ship_physics", profile_start)
				

func _unhandled_input(event: InputEvent) -> void:
	if is_sinking or is_dying or not is_player_controlled: return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("toggle_fleet_formation"):
			_toggle_fleet_formation()
			return
		if event.is_action_pressed("cycle_fleet_formation"):
			_cycle_fleet_formation()
			return
		# 치트키: F2 누르면 바로 백병전 업그레이드
		if OS.is_debug_build() and event.keycode == KEY_F2:
			if is_instance_valid(_cached_level_manager):
				_cached_level_manager.add_merit(999)
		if OS.is_debug_build() and event.keycode == KEY_F3:
			toggle_masts_folded()
			if is_instance_valid(_cached_hud) and _cached_hud.has_method("show_message"):
				var fold_text := "돛대 접힘" if are_masts_folded() else "돛대 펼침"
				_cached_hud.show_message("%s (debug)" % fold_text, 1.0)
				
		pass

func _execute_merit_action() -> void:
	if not is_instance_valid(_cached_level_manager): return
		
	if _cached_level_manager.merit_points < _cached_level_manager.max_merit_points:
		if _cached_hud and _cached_hud.has_method("show_message"):
			_cached_hud.show_message("백병전 포인트가 부족합니다!", 1.5)
		return
		
	# 백병전 포인트 소비
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
	if _has_nearby_enemy_pressure_for_respawn():
		return

	var soldiers_node = get_soldiers_container()
	if not soldiers_node: return

	if get_alive_crew_count() <= 0:
		crew_respawn_timer = 0.0
		return

	# 전투불능 병사는 정원을 차지하므로 자동 보충으로 대체하지 않는다.
	var respawn_target_count: int = int(max_crew_count)
	var roster_count: int = PlayerShipCrewHelper.get_player_roster_count(self)

	if roster_count < respawn_target_count:
		crew_respawn_timer += delta
		if crew_respawn_timer >= crew_respawn_interval:
			crew_respawn_timer = 0.0
			if PlayerShipCrewHelper.add_respawn_crew(self):
				_sync_player_crew_roster()
				print("[Crew] 자동 보충! 아군 병사가 합류했습니다. (현재: %d/%d)" % [roster_count + 1, respawn_target_count])
	else:
		crew_respawn_timer = 0.0 # 정원이 차면 타이머 초기화

func _has_nearby_enemy_pressure_for_respawn() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var pressure_range: float = maxf(12.0, auto_raid_threat_range)
	var pressure_range_sq: float = pressure_range * pressure_range
	for other in _get_ships_cached(tree):
		if not is_instance_valid(other) or other == self:
			continue
		if other.get("team") != "enemy":
			continue
		if other.has_method("is_combat_disabled") and other.is_combat_disabled():
			continue
		var planar_delta: Vector3 = other.global_position - global_position
		planar_delta.y = 0.0
		if planar_delta.length_squared() <= pressure_range_sq:
			return true
	return false

func _update_corpse_cleanup(delta: float) -> void:
	if not corpse_cleanup_enabled:
		return
	if not _can_run_corpse_cleanup():
		corpse_cleanup_peace_timer = 0.0
		corpse_cleanup_timer = 0.0
		return

	corpse_cleanup_peace_timer += delta
	if corpse_cleanup_peace_timer < corpse_cleanup_delay:
		return

	corpse_cleanup_timer -= delta
	if corpse_cleanup_timer > 0.0:
		return
	corpse_cleanup_timer = corpse_cleanup_interval
	_try_cleanup_enemy_corpse()


func _can_run_corpse_cleanup() -> bool:
	if is_sinking or is_dying or is_derelict:
		return false
	if deck_is_contested or deck_is_overrun:
		return false
	if is_boarding:
		return false
	if _has_nearby_enemy_pressure_for_respawn():
		return false
	return true


func _try_cleanup_enemy_corpse() -> void:
	var corpse: Node3D = _find_cleanup_enemy_corpse()
	if not is_instance_valid(corpse):
		return
	var cleaner: Node3D = _find_corpse_cleanup_actor(corpse)
	if not is_instance_valid(cleaner):
		return
	if not SoldierShipWorkPriorityHelper.reserve_work_slot(corpse, cleaner, SoldierShipWorkPriorityHelper.TASK_CORPSE_CLEANUP, corpse_cleanup_throw_duration + 4.0):
		return

	corpse.set_meta("corpse_cleanup_in_progress", true)
	_set_corpse_cleanup_actor_action(cleaner, SoldierActionHelper.ACTION_CORPSE_CLEANUP_APPROACH)
	_prepare_cleaner_for_corpse_cleanup(cleaner, corpse)
	_throw_corpse_overboard(cleaner, corpse)


func _find_cleanup_enemy_corpse() -> Node3D:
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier) or not (soldier is Node3D):
			continue
		if soldier.get_meta("corpse_cleanup_in_progress", false) == true:
			continue
		if SoldierShipWorkPriorityHelper.is_work_slot_reserved_for_other(soldier, null, SoldierShipWorkPriorityHelper.TASK_CORPSE_CLEANUP):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != "enemy":
			continue
		if not PlayerSoldierStateHelper.is_dead_soldier(soldier):
			continue
		if PlayerSoldierStateHelper.is_incapacitated_soldier(soldier):
			continue
		return soldier as Node3D
	return null


func _find_corpse_cleanup_actor(corpse: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance_sq: float = INF
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier) or not (soldier is Node3D):
			continue
		if _is_corpse_cleanup_actor_busy(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != "player":
			continue
		if not SoldierShipWorkPriorityHelper.can_accept_immediate_work(soldier, SoldierShipWorkPriorityHelper.TASK_CORPSE_CLEANUP):
			continue
		if PlayerSoldierStateHelper.is_dead_soldier(soldier):
			continue
		var soldier_node := soldier as Node3D
		var distance_sq: float = soldier_node.global_position.distance_squared_to(corpse.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = soldier_node
	return best


func _prepare_cleaner_for_corpse_cleanup(cleaner: Node3D, corpse: Node3D) -> void:
	if "current_target" in cleaner:
		cleaner.set("current_target", null)
	if "attack_timer" in cleaner:
		cleaner.set("attack_timer", maxf(float(cleaner.get("attack_timer")), corpse_cleanup_throw_duration + 2.0))
	if "velocity" in cleaner:
		cleaner.set("velocity", Vector3.ZERO)
	if cleaner.has_method("_change_state"):
		cleaner.call("_change_state", 0)
	var look_target := Vector3(corpse.global_position.x, cleaner.global_position.y, corpse.global_position.z)
	if not cleaner.global_position.is_equal_approx(look_target):
		cleaner.look_at(look_target, Vector3.UP)


func _is_corpse_cleanup_actor_busy(soldier) -> bool:
	if not is_instance_valid(soldier):
		return true
	if soldier.has_method("has_named_action"):
		return bool(soldier.call("has_named_action"))
	return SoldierActionHelper.has_action(soldier)


func _set_corpse_cleanup_actor_action(cleaner: Node3D, action_name: String) -> void:
	if not is_instance_valid(cleaner):
		return
	if cleaner.has_method("begin_corpse_cleanup_action"):
		cleaner.call("begin_corpse_cleanup_action", action_name)
	else:
		SoldierActionHelper.begin_corpse_cleanup_action(cleaner, action_name)


func _throw_corpse_overboard(cleaner: Node3D, corpse: Node3D) -> void:
	var throw_target: Vector3 = _get_corpse_cleanup_throw_target(corpse)
	var pickup_point: Vector3 = _get_corpse_cleanup_pickup_point(cleaner, corpse)
	var rail_stand_point: Vector3 = _get_corpse_cleanup_rail_stand_point(cleaner, corpse, throw_target)
	var corpse_id: int = corpse.get_instance_id()
	var cleaner_id: int = cleaner.get_instance_id()
	var pickup_actor_position: Vector3 = _get_corpse_cleanup_actor_local_target(cleaner, pickup_point)
	var rail_actor_position: Vector3 = _get_corpse_cleanup_actor_local_target(cleaner, rail_stand_point)
	var pickup_carry_rotation: Vector3 = _get_corpse_cleanup_carry_rotation(corpse, pickup_point, throw_target)
	var rail_carry_rotation: Vector3 = _get_corpse_cleanup_carry_rotation(corpse, rail_stand_point, throw_target)
	var approach_seconds: float = _get_corpse_cleanup_walk_seconds(cleaner.global_position, pickup_point, cleaner)
	var pickup_seconds: float = 0.22
	var carry_seconds: float = _get_corpse_cleanup_walk_seconds(pickup_point, rail_stand_point, cleaner)
	var windup_seconds: float = 0.14
	var throw_seconds: float = maxf(0.25, corpse_cleanup_throw_duration * randf_range(1.05, 1.18))

	_face_corpse_cleanup_actor(cleaner, pickup_point)

	var tween := create_tween()
	tween.tween_property(cleaner, "position", pickup_actor_position, approach_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(Callable(self, "_face_corpse_cleanup_corpse_by_id").bind(cleaner_id, corpse_id))
	tween.tween_callback(Callable(self, "_set_corpse_cleanup_action_by_id").bind(cleaner_id, SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY))
	tween.tween_callback(Callable(self, "_capture_corpse_cleanup_pickup_pose_by_id").bind(corpse_id))
	tween.tween_callback(Callable(self, "_begin_corpse_cleanup_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_method(
		Callable(self, "_apply_corpse_cleanup_payload_pickup").bind(corpse_id, cleaner_id, pickup_carry_rotation),
		0.0,
		1.0,
		pickup_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "_face_corpse_cleanup_actor_by_id").bind(cleaner_id, rail_stand_point))
	tween.tween_callback(Callable(self, "_begin_corpse_cleanup_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_property(cleaner, "position", rail_actor_position, carry_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_method(
		Callable(self, "_apply_corpse_cleanup_payload_follow").bind(corpse_id, cleaner_id, pickup_carry_rotation, rail_carry_rotation),
		0.0,
		1.0,
		carry_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "_face_corpse_cleanup_throw_target_by_id").bind(cleaner_id, corpse_id))
	tween.tween_callback(Callable(self, "_set_corpse_cleanup_action_by_id").bind(cleaner_id, SoldierActionHelper.ACTION_CORPSE_CLEANUP_THROW))
	tween.tween_callback(Callable(self, "_finish_corpse_cleanup_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_interval(windup_seconds)
	tween.tween_callback(Callable(self, "_capture_corpse_cleanup_throw_arc_by_id").bind(corpse_id, cleaner_id))
	tween.tween_method(
		Callable(self, "_apply_corpse_cleanup_throw_arc").bind(corpse_id, cleaner_id),
		0.0,
		1.0,
		throw_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(_finish_corpse_cleanup_throw.bind(corpse_id, cleaner_id))


func _get_corpse_cleanup_pickup_point(cleaner: Node3D, corpse: Node3D) -> Vector3:
	var corpse_local: Vector3 = to_local(corpse.global_position)
	var cleaner_local: Vector3 = to_local(cleaner.global_position)
	var approach_dir: Vector3 = cleaner_local - corpse_local
	approach_dir.y = 0.0
	if approach_dir.length_squared() <= 0.001:
		approach_dir = Vector3(-1.0 if corpse_local.x >= 0.0 else 1.0, 0.0, 0.0)
	approach_dir = approach_dir.normalized()
	var local_point: Vector3 = corpse_local + approach_dir * 0.72
	local_point = _clamp_corpse_cleanup_deck_local(local_point, 0.38)
	var global_point: Vector3 = to_global(local_point)
	global_point.y = cleaner.global_position.y
	return global_point


func _get_corpse_cleanup_rail_stand_point(cleaner: Node3D, corpse: Node3D, throw_target: Vector3) -> Vector3:
	var local_pos: Vector3 = to_local(corpse.global_position)
	var local_throw: Vector3 = to_local(throw_target)
	var side_sign: float = 1.0 if local_throw.x >= 0.0 else -1.0
	var deck_half_width: float = maxf(1.8, _hull_half_extents.x * deck_bounds_ratio)
	var deck_half_length: float = maxf(2.5, _hull_half_extents.y * deck_bounds_ratio)
	local_pos.x = side_sign * maxf(0.3, deck_half_width - 0.58)
	local_pos.z = clampf(local_pos.z, -deck_half_length + 0.32, deck_half_length - 0.32)
	var global_point: Vector3 = to_global(local_pos)
	global_point.y = cleaner.global_position.y
	return global_point


func _get_corpse_cleanup_actor_local_target(cleaner: Node3D, global_target: Vector3) -> Vector3:
	var parent_3d := cleaner.get_parent() as Node3D
	if not is_instance_valid(parent_3d):
		return global_target
	var local_target: Vector3 = parent_3d.to_local(global_target)
	local_target.y = cleaner.position.y
	return local_target


func _get_corpse_cleanup_carry_rotation(corpse: Node3D, actor_position: Vector3, throw_target: Vector3) -> Vector3:
	var to_rail: Vector3 = throw_target - actor_position
	to_rail.y = 0.0
	if to_rail.length_squared() <= 0.001:
		return corpse.rotation + Vector3(deg_to_rad(8.0), 0.0, deg_to_rad(6.0))
	to_rail = to_rail.normalized()
	var yaw := atan2(to_rail.x, to_rail.z)
	var side_roll := deg_to_rad(18.0 if to_local(actor_position).x >= 0.0 else -18.0)
	return Vector3(deg_to_rad(8.0), yaw, side_roll)


func _get_corpse_cleanup_walk_seconds(from_position: Vector3, to_position: Vector3, cleaner: Node3D) -> float:
	var planar_delta: Vector3 = to_position - from_position
	planar_delta.y = 0.0
	var move_speed_value: float = float(cleaner.get("move_speed")) if cleaner.get("move_speed") != null else 3.0
	return clampf(planar_delta.length() / maxf(move_speed_value * 1.05, 0.1), 0.18, 1.45)


func _clamp_corpse_cleanup_deck_local(local_point: Vector3, inset: float) -> Vector3:
	var deck_half_width: float = maxf(1.8, _hull_half_extents.x * deck_bounds_ratio)
	var deck_half_length: float = maxf(2.5, _hull_half_extents.y * deck_bounds_ratio)
	local_point.x = clampf(local_point.x, -deck_half_width + inset, deck_half_width - inset)
	local_point.z = clampf(local_point.z, -deck_half_length + inset, deck_half_length - inset)
	return local_point


func _face_corpse_cleanup_actor(cleaner: Node3D, look_position: Vector3) -> void:
	if not is_instance_valid(cleaner):
		return
	var look_target := Vector3(look_position.x, cleaner.global_position.y, look_position.z)
	if not cleaner.global_position.is_equal_approx(look_target):
		cleaner.look_at(look_target, Vector3.UP)


func _face_corpse_cleanup_actor_by_id(cleaner_id: int, look_position: Vector3) -> void:
	var cleaner := instance_from_id(cleaner_id)
	if is_instance_valid(cleaner) and cleaner is Node3D:
		_face_corpse_cleanup_actor(cleaner as Node3D, look_position)


func _face_corpse_cleanup_corpse_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := instance_from_id(cleaner_id)
	var corpse := instance_from_id(corpse_id)
	if is_instance_valid(cleaner) and cleaner is Node3D and is_instance_valid(corpse) and corpse is Node3D:
		_face_corpse_cleanup_actor(cleaner as Node3D, (corpse as Node3D).global_position)


func _face_corpse_cleanup_throw_target_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := instance_from_id(cleaner_id)
	var corpse := instance_from_id(corpse_id)
	if is_instance_valid(cleaner) and cleaner is Node3D and is_instance_valid(corpse) and corpse is Node3D:
		_face_corpse_cleanup_actor(cleaner as Node3D, _get_corpse_cleanup_throw_target(corpse as Node3D))


func _set_corpse_cleanup_action_by_id(cleaner_id: int, action_name: String) -> void:
	var cleaner := instance_from_id(cleaner_id)
	if is_instance_valid(cleaner) and cleaner is Node3D:
		_set_corpse_cleanup_actor_action(cleaner as Node3D, action_name)


func _begin_corpse_cleanup_carry_payload_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := instance_from_id(cleaner_id)
	var corpse := instance_from_id(corpse_id)
	if is_instance_valid(cleaner) and cleaner is Node3D and is_instance_valid(corpse) and corpse is Node3D:
		_begin_corpse_cleanup_carry_payload(cleaner as Node3D, corpse as Node3D)


func _capture_corpse_cleanup_pickup_pose_by_id(corpse_id: int) -> void:
	var corpse := instance_from_id(corpse_id)
	if not is_instance_valid(corpse) or not (corpse is Node3D):
		return
	var corpse_node := corpse as Node3D
	corpse_node.set_meta(CORPSE_CLEANUP_PICKUP_START_POSITION_META, corpse_node.global_position)
	corpse_node.set_meta(CORPSE_CLEANUP_PICKUP_START_ROTATION_META, corpse_node.rotation)


func _begin_corpse_cleanup_carry_payload(cleaner: Node3D, corpse: Node3D) -> void:
	var side_sign := 1.0 if to_local(cleaner.global_position).x >= 0.0 else -1.0
	var offset_overrides := _get_corpse_cleanup_carry_payload_offsets()
	if cleaner.has_method("begin_typed_carry_payload"):
		cleaner.call(
			"begin_typed_carry_payload",
			corpse,
			SoldierActionHelper.CARRY_PAYLOAD_KIND_CORPSE,
			side_sign,
			offset_overrides
		)
	else:
		SoldierActionHelper.begin_typed_carry_payload(
			cleaner,
			corpse,
			SoldierActionHelper.CARRY_PAYLOAD_KIND_CORPSE,
			side_sign,
			offset_overrides
		)


func _get_corpse_cleanup_carry_payload_offsets() -> Dictionary:
	return {
		SoldierActionHelper.PAYLOAD_DEF_FORWARD_OFFSET: CORPSE_CLEANUP_CARRY_FORWARD_OFFSET,
		SoldierActionHelper.PAYLOAD_DEF_SIDE_OFFSET: CORPSE_CLEANUP_CARRY_SIDE_OFFSET,
		SoldierActionHelper.PAYLOAD_DEF_HEIGHT_OFFSET: CORPSE_CLEANUP_CARRY_HEIGHT_OFFSET,
	}


func _finish_corpse_cleanup_carry_payload_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := instance_from_id(cleaner_id)
	var corpse := instance_from_id(corpse_id)
	if is_instance_valid(cleaner) and cleaner is Node3D:
		if cleaner.has_method("finish_carry_payload") and is_instance_valid(corpse) and corpse is Node3D:
			cleaner.call("finish_carry_payload", corpse)
		else:
			SoldierActionHelper.finish_carry_payload(cleaner, corpse as Node3D if is_instance_valid(corpse) and corpse is Node3D else null)


func _get_corpse_cleanup_throw_origin(cleaner: Node3D, corpse: Node3D, throw_target: Vector3) -> Vector3:
	return _get_corpse_cleanup_throw_origin_from_actor_position(cleaner.global_position, corpse, throw_target)


func _get_corpse_cleanup_throw_origin_from_actor_position(actor_position: Vector3, corpse: Node3D, throw_target: Vector3) -> Vector3:
	var to_rail: Vector3 = throw_target - actor_position
	to_rail.y = 0.0
	if to_rail.length_squared() <= 0.001:
		to_rail = corpse.global_position - actor_position
		to_rail.y = 0.0
	if to_rail.length_squared() <= 0.001:
		to_rail = Vector3.RIGHT
	to_rail = to_rail.normalized()
	var origin := actor_position + to_rail * 0.62
	origin.y = maxf(corpse.global_position.y, actor_position.y + 0.48)
	return origin


func _apply_corpse_cleanup_payload_pickup(progress: float, corpse_id: int, cleaner_id: int, target_rotation: Vector3) -> void:
	var corpse := instance_from_id(corpse_id)
	var cleaner := instance_from_id(cleaner_id)
	if not is_instance_valid(corpse) or not (corpse is Node3D) or not is_instance_valid(cleaner) or not (cleaner is Node3D):
		return
	var corpse_node := corpse as Node3D
	var start_position: Vector3 = corpse_node.get_meta(CORPSE_CLEANUP_PICKUP_START_POSITION_META, corpse_node.global_position)
	var start_rotation: Vector3 = corpse_node.get_meta(CORPSE_CLEANUP_PICKUP_START_ROTATION_META, corpse_node.rotation)
	SoldierActionHelper.apply_carry_payload_pickup(cleaner, corpse_node, progress, start_position, start_rotation, target_rotation)
	if progress >= 1.0:
		if corpse_node.has_meta(CORPSE_CLEANUP_PICKUP_START_POSITION_META):
			corpse_node.remove_meta(CORPSE_CLEANUP_PICKUP_START_POSITION_META)
		if corpse_node.has_meta(CORPSE_CLEANUP_PICKUP_START_ROTATION_META):
			corpse_node.remove_meta(CORPSE_CLEANUP_PICKUP_START_ROTATION_META)


func _apply_corpse_cleanup_payload_follow(progress: float, corpse_id: int, cleaner_id: int, start_rotation: Vector3, target_rotation: Vector3) -> void:
	var corpse := instance_from_id(corpse_id)
	var cleaner := instance_from_id(cleaner_id)
	if not is_instance_valid(corpse) or not (corpse is Node3D) or not is_instance_valid(cleaner) or not (cleaner is Node3D):
		return
	SoldierActionHelper.apply_carry_payload_follow(cleaner, corpse, progress, start_rotation, target_rotation)


func _capture_corpse_cleanup_throw_arc_by_id(corpse_id: int, cleaner_id: int) -> void:
	var corpse := instance_from_id(corpse_id)
	var cleaner := instance_from_id(cleaner_id)
	if not is_instance_valid(corpse) or not (corpse is Node3D) or not is_instance_valid(cleaner) or not (cleaner is Node3D):
		return
	var corpse_node := corpse as Node3D
	var cleaner_node := cleaner as Node3D
	var throw_target: Vector3 = _get_corpse_cleanup_throw_target(corpse_node)
	var throw_origin: Vector3 = _get_corpse_cleanup_throw_origin(cleaner_node, corpse_node, throw_target)
	var start_position: Vector3 = corpse_node.global_position
	var arc_control: Vector3 = throw_origin.lerp(throw_target, 0.52)
	arc_control.y = maxf(maxf(start_position.y, throw_origin.y), throw_target.y) + randf_range(1.85, 2.45)
	corpse_node.set_meta(CORPSE_CLEANUP_THROW_ARC_META, {
		"start_position": start_position,
		"arc_control": arc_control,
		"throw_target": throw_target,
		"start_rotation": corpse_node.rotation,
		"spin_rotation": corpse_node.rotation + Vector3(randf_range(1.7, 2.8), randf_range(-0.9, 0.9), randf_range(-1.8, 1.8)),
	})


func _apply_corpse_cleanup_throw_arc(progress: float, corpse_id: int, cleaner_id: int) -> void:
	var corpse := instance_from_id(corpse_id)
	if not is_instance_valid(corpse) or not (corpse is Node3D):
		return
	var corpse_node := corpse as Node3D
	if not corpse_node.has_meta(CORPSE_CLEANUP_THROW_ARC_META):
		_capture_corpse_cleanup_throw_arc_by_id(corpse_id, cleaner_id)
	var arc_data: Dictionary = corpse_node.get_meta(CORPSE_CLEANUP_THROW_ARC_META, {})
	if arc_data.is_empty():
		return
	var start_position: Vector3 = arc_data.get("start_position", corpse_node.global_position)
	var arc_control: Vector3 = arc_data.get("arc_control", start_position)
	var throw_target: Vector3 = arc_data.get("throw_target", start_position)
	var start_rotation: Vector3 = arc_data.get("start_rotation", corpse_node.rotation)
	var spin_rotation: Vector3 = arc_data.get("spin_rotation", start_rotation)
	var t: float = clampf(progress, 0.0, 1.0)
	var eased_t: float = smoothstep(0.0, 1.0, t)
	var arc_pos: Vector3 = start_position * ((1.0 - t) * (1.0 - t)) \
		+ arc_control * (2.0 * (1.0 - t) * t) \
		+ throw_target * (t * t)
	corpse_node.global_position = arc_pos
	corpse_node.rotation = Vector3(
		lerp_angle(start_rotation.x, spin_rotation.x, eased_t),
		lerp_angle(start_rotation.y, spin_rotation.y, eased_t),
		lerp_angle(start_rotation.z, spin_rotation.z, eased_t)
	)
	if progress >= 1.0 and corpse_node.has_meta(CORPSE_CLEANUP_THROW_ARC_META):
		corpse_node.remove_meta(CORPSE_CLEANUP_THROW_ARC_META)


func _get_corpse_cleanup_throw_target(corpse: Node3D) -> Vector3:
	var local_pos: Vector3 = to_local(corpse.global_position)
	var side_sign: float = 1.0 if local_pos.x >= 0.0 else -1.0
	var deck_half_width: float = maxf(1.8, _hull_half_extents.x * deck_bounds_ratio)
	var deck_half_length: float = maxf(2.5, _hull_half_extents.y * deck_bounds_ratio)
	local_pos.x = side_sign * (deck_half_width + randf_range(3.0, 4.2))
	local_pos.z = clampf(local_pos.z, -deck_half_length, deck_half_length)
	var global_target: Vector3 = to_global(local_pos)
	global_target.y = 0.05
	return global_target


func _finish_corpse_cleanup_throw(corpse_id: int, cleaner_id: int) -> void:
	var corpse := instance_from_id(corpse_id)
	var cleaner := instance_from_id(cleaner_id)
	if is_instance_valid(corpse):
		if corpse is Node3D:
			_play_corpse_cleanup_splash((corpse as Node3D).global_position)
		_grant_corpse_cleanup_merit()
		SoldierShipWorkPriorityHelper.release_work_slot(corpse, cleaner, SoldierShipWorkPriorityHelper.TASK_CORPSE_CLEANUP)
		corpse.queue_free()
	if is_instance_valid(cleaner):
		if cleaner.has_method("finish_corpse_cleanup_action"):
			cleaner.call("finish_corpse_cleanup_action")
		else:
			SoldierActionHelper.finish_corpse_cleanup_action(cleaner)


func _grant_corpse_cleanup_merit() -> void:
	if not is_instance_valid(_cached_level_manager) or not _cached_level_manager.has_method("add_merit"):
		return
	var merit_reward: int = max(0, int(_cached_level_manager.get("corpse_cleanup_merit_reward")))
	if merit_reward <= 0:
		return
	_cached_level_manager.add_merit(merit_reward)


func _play_corpse_cleanup_splash(splash_pos: Vector3) -> void:
	if water_splash_scene:
		var splash = ScenePool.acquire(get_tree(), water_splash_scene)
		if is_instance_valid(splash):
			get_tree().root.add_child(splash)
			if splash is Node3D:
				(splash as Node3D).global_position = Vector3(splash_pos.x, 0.05, splash_pos.z)
			if splash.has_method("configure_as_corpse_cleanup"):
				splash.configure_as_corpse_cleanup()
			elif splash.has_method("configure_as_splash"):
				splash.configure_as_splash()
			elif splash.has_method("configure_as_small"):
				splash.configure_as_small()
			if splash.has_method("pool_activate"):
				splash.call_deferred("pool_activate")
	if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
		_cached_audio_manager.play_sfx("water_splash_small", splash_pos, randf_range(0.85, 1.15), 2.0)

func _update_auto_boarding_raid(delta: float) -> void:
	PlayerShipCrewHelper.update_auto_boarding_raid(self, delta)

func _toggle_manual_boarding_intent() -> void:
	PlayerShipCrewHelper.toggle_manual_boarding_intent(self)

func _clear_manual_boarding_intent() -> void:
	PlayerShipCrewHelper.clear_manual_boarding_intent(self)

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

func _cycle_fleet_formation() -> void:
	PlayerShipRuntimeHelper.cycle_fleet_formation(self)


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


func set_sail_furled(furled: bool) -> void:
	var target_furled := bool(furled)
	if sail_furled == target_furled:
		_sync_mast_fold_after_sail_deployment()
		return
	sail_furled = target_furled
	if not sail_furled:
		_sync_mast_fold_with_sail_furl()
	if sail_furled:
		_play_sail_handling_sound(false, 2.0)
	else:
		if mast_fold_pivots.is_empty():
			_play_sail_handling_sound(true, 2.0)
	if is_instance_valid(_cached_hud) and _cached_hud.has_method("show_message"):
		var message := "돛 접음: 조타·노젓기 강화 / 화재 피해 감소" if sail_furled else "돛 펼침: 항해 속도 회복"
		_cached_hud.show_message(message, 1.4)
	_sync_support_fleet_sail_furl()


func toggle_sail_furl() -> void:
	set_sail_furled(not sail_furled)


func is_sail_furled() -> bool:
	return sail_furled


func get_effective_sail_deployment() -> float:
	var residual_drive := clampf(furled_sail_drive_ratio, 0.0, 1.0)
	var deployed := clampf(sail_deployed_ratio, 0.0, 1.0)
	return clampf(lerpf(residual_drive, 1.0, deployed), 0.0, 1.0)


func _update_sail_deployment(delta: float) -> void:
	var target_ratio := _get_target_sail_deployment_ratio()
	var previous_ratio := clampf(sail_deployed_ratio, 0.0, 1.0)
	sail_deployed_ratio = move_toward(
		previous_ratio,
		target_ratio,
		maxf(sail_furl_rate, 0.01) * delta
	)
	_update_sail_deployment_audio(previous_ratio, sail_deployed_ratio, target_ratio, delta)
	_sync_mast_fold_after_sail_deployment()


func _sync_mast_fold_with_sail_furl(immediate: bool = false) -> void:
	if mast_fold_pivots.is_empty():
		return
	set_masts_folded(sail_furled, immediate)


func _sync_mast_fold_after_sail_deployment() -> void:
	if mast_fold_pivots.is_empty():
		return
	if sail_furled:
		if sail_deployed_ratio <= 0.001 and not are_masts_folded():
			set_masts_folded(true)
		return
	if are_masts_folded():
		set_masts_folded(false)


func _get_target_sail_deployment_ratio() -> float:
	if sail_furled:
		return 0.0
	if mast_fold_pivots.is_empty():
		return 1.0
	if get_mast_fold_ratio() > 0.001:
		return 0.0
	return 1.0


func set_masts_folded(folded: bool, immediate: bool = false) -> void:
	var was_folded := masts_folded
	super.set_masts_folded(folded, immediate)
	if immediate or was_folded == masts_folded:
		return
	_play_mast_fold_sound(masts_folded)


func _update_sail_deployment_audio(previous_ratio: float, current_ratio: float, target_ratio: float, delta: float) -> void:
	_sail_handling_audio_timer = maxf(0.0, _sail_handling_audio_timer - delta)
	if absf(current_ratio - previous_ratio) <= 0.0005:
		return
	if _sail_handling_audio_timer > 0.0:
		return
	var raising := current_ratio > previous_ratio
	_play_sail_handling_sound(raising)
	var nearly_done := absf(current_ratio - target_ratio) <= 0.035
	_sail_handling_audio_timer = randf_range(0.85, 1.18) if nearly_done else randf_range(0.55, 0.82)


func _play_sail_handling_sound(raising: bool, volume_db: float = 2.5) -> void:
	if not is_instance_valid(_cached_audio_manager) or not _cached_audio_manager.has_method("play_sfx"):
		return
	var pitch := randf_range(1.02, 1.15) if raising else randf_range(0.82, 0.96)
	_cached_audio_manager.play_sfx("sail_flap", global_position, pitch, volume_db)
	_sail_handling_audio_timer = maxf(_sail_handling_audio_timer, randf_range(0.42, 0.65))


func _play_mast_fold_sound(folding: bool) -> void:
	if not is_instance_valid(_cached_audio_manager) or not _cached_audio_manager.has_method("play_sfx"):
		return
	var pitch := randf_range(0.72, 0.86) if folding else randf_range(0.88, 1.04)
	var volume := 2.0 if folding else 0.5
	_cached_audio_manager.play_sfx("mast_creak", global_position, pitch, volume)


func _sync_support_fleet_sail_furl() -> void:
	if not is_inside_tree():
		return
	var support_ships: Array = PlayerShipSupportHelper.get_support_fleet_ships(self)
	for support_ship in support_ships:
		if not is_instance_valid(support_ship):
			continue
		if support_ship.has_method("set_sail_furled"):
			support_ship.call("set_sail_furled", sail_furled)
		if "sail_deployed_ratio" in support_ship:
			support_ship.set("sail_deployed_ratio", sail_deployed_ratio)


## 노 젓기 활성화/비활성화
func set_rowing(active: bool, direction: int = 1) -> void:
	is_rowing = active
	if active:
		rowing_direction = -1 if direction < 0 else 1


## 노 젓기 토글
func toggle_rowing() -> void:
	set_rowing(not is_rowing, 1)


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
func add_survivor(allow_over_capacity: bool = false) -> bool:
	return PlayerShipCrewHelper.add_survivor(self, allow_over_capacity)

func add_respawn_crew() -> bool:
	return PlayerShipCrewHelper.add_respawn_crew(self)

## 갑판 방어 무기 2: 화통 투척 로직 (병사가 수행)
func _update_fire_pot_logic(delta: float) -> void:
	PlayerShipCrewHelper.update_fire_pot_logic(self, delta)
