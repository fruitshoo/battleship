@tool
extends "res://scripts/entities/ships/base_ship.gd"


## 배 핵심 로직: 실제 범선 물리, 러더 조향, 둥실둥실 효과

var team: String = "player"

@export_category("Player Ship")
@export_group("Movement / Rudder")
@export var rowing_speed: float = 2.8


const SOLDIER_SCENE = preload("res://scenes/entities/soldiers/soldier.tscn")
const PLAYER_DEFAULT_WOOD_SPLINTER_SCENE = preload("res://scenes/effects/wood_splinter.tscn")
const PLAYER_DEFAULT_WATER_SPLASH_SCENE = preload("res://scenes/effects/water_blast.tscn")
const PLAYER_DEFAULT_IMPACT_PUFF_SCENE = preload("res://scenes/effects/impact_puff.tscn")
const PLAYER_DEFAULT_FIRE_EFFECT_SCENE = preload("res://scenes/effects/fire_effect.tscn")
const PLAYER_DEFAULT_SURVIVOR_SCENE = preload("res://scenes/effects/survivor.tscn")
const PlayerShipCrewHelper = preload("res://scripts/entities/ships/player_ship_crew_helper.gd")
const PlayerShipMovementHelper = preload("res://scripts/entities/ships/player_ship_movement_helper.gd")
const PlayerShipSinkHelper = preload("res://scripts/entities/ships/player_ship_sink_helper.gd")
const PlayerShipRuntimeHelper = preload("res://scripts/entities/ships/player_ship_runtime_helper.gd")
const PlayerShipCargoTransportHelper = preload("res://scripts/entities/ships/player_ship_cargo_transport_helper.gd")
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
const CARGO_TRANSPORT_CARRY_FORWARD_OFFSET := 0.08
const CARGO_TRANSPORT_CARRY_SIDE_OFFSET := 0.08
const CARGO_TRANSPORT_CARRY_HEIGHT_OFFSET := 0.46
const CARGO_TRANSPORT_PICKUP_START_POSITION_META := "cargo_transport_pickup_start_position"
const CARGO_TRANSPORT_PICKUP_START_ROTATION_META := "cargo_transport_pickup_start_rotation"
const CARGO_TRANSPORT_THROW_ARC_META := "cargo_transport_throw_arc"
const CARGO_TRANSPORT_STOW_POSE_META := "cargo_transport_stow_pose"
const CARGO_TRANSPORT_STAIR_NODE_NAME := "panok_stair"
const CARGO_TRANSPORT_STAIR_TOP_NODE_NAME := "CrewStairTop"
const CARGO_TRANSPORT_STAIR_BOTTOM_NODE_NAME := "CrewStairBottom"
const CARGO_TRANSPORT_STAIR_TOP_META := "cargo_transport_stair_top"
const CARGO_TRANSPORT_STAIR_BOTTOM_META := "cargo_transport_stair_bottom"
const ROOF_CARGO_TRANSPORT_ARC_META := "roof_cargo_transport_arc"

@export var rudder_speed: float = 95.0
@export var rudder_return_speed: float = 65.0
@export_range(0.5, 3.0, 0.05) var player_rudder_turn_authority: float = 1.05 # 플레이어 러더 회전 반응 보정
@export var rudder_turn_speed: float = 95.0 # Seamanship에 의해 강화됨

@export_group("Identity / Hull")
@export var ship_type: String = "panokseon_player":
	set(value):
		ship_type = value
		if Engine.is_editor_hint():
			_update_editor_hull()

@export var hull_scene: PackedScene = preload("res://scenes/ships/hulls/panok_hull.tscn")
@export var is_player_controlled: bool = true
@export var has_sextant: bool = false # Sextant 아이템 소지 여부

@export_group("Sail Handling")
var is_rowing: bool = false
var rowing_direction: int = 1
var rowing_locked: bool = false
@export var sail_turn_speed: float = 60.0
@export var sail_efficiency_mult: float = 1.0
@export var sail_furled: bool = false
@export_range(0.0, 1.0, 0.01) var sail_deployed_ratio: float = 1.0
@export_range(0.25, 8.0, 0.05) var sail_furl_rate: float = 0.55
@export_range(0.0, 0.35, 0.01) var misaligned_sail_min_thrust_ratio: float = 0.12
@export_range(0.0, 0.25, 0.01) var furled_sail_drive_ratio: float = 0.0
@export_range(1.0, 2.0, 0.05) var furled_sail_rudder_multiplier: float = 1.0
@export_range(1.0, 2.0, 0.05) var furled_sail_rowing_efficiency_multiplier: float = 1.0
@export_range(0.0, 3.0, 0.1) var furled_sail_rowing_speed_bonus: float = 1.0
@export_range(0.25, 1.0, 0.05) var furled_sail_rowing_stamina_cost_multiplier: float = 0.78
@export_range(0.0, 1.0, 0.05) var furled_sail_fire_damage_multiplier: float = 0.5

@export_group("Rowing / Reverse")
@export var max_rowing_stamina: float = 100.0
var rowing_stamina: float = 100.0
@export var rowing_acceleration_mult: float = 1.0
@export_range(0.1, 0.6, 0.05) var reverse_rowing_speed_ratio: float = 0.35
@export_range(0.2, 1.2, 0.05) var reverse_rowing_acceleration_mult: float = 0.70
@export_range(0.2, 1.0, 0.05) var reverse_rudder_turn_authority_mult: float = 0.65
@export_range(0.05, 0.9, 0.01) var exhausted_rowing_speed_ratio: float = 0.12
@export var stamina_drain_rate: float = 6.0
@export var stamina_recovery_rate: float = 8.5

@export_group("Ramming Boost")
@export_range(0.4, 3.0, 0.05) var ramming_boost_duration: float = 1.35
@export_range(4.0, 45.0, 0.5) var ramming_boost_recharge_duration: float = 12.0
@export_range(0.1, 1.0, 0.05) var ramming_boost_recharge_multiplier: float = 1.0
@export_range(1.0, 2.0, 0.05) var ramming_boost_speed_multiplier: float = 1.55
@export_range(1.0, 6.0, 0.1) var ramming_boost_acceleration_multiplier: float = 3.8
@export_range(0.0, 8.0, 0.1) var ramming_boost_impulse_speed: float = 3.4
@export_range(0.2, 1.0, 0.05) var ramming_boost_turn_multiplier: float = 0.68
@export_range(1.0, 4.0, 0.05) var ramming_boost_damage_multiplier: float = 2.6
@export_group("")
var ramming_boost_active: bool = false
var ramming_boost_charge: float = 1.0
var ramming_boost_timer: float = 0.0
var ramming_boost_input_was_pressed: bool = false
var ramming_boost_blocked_message_timer: float = 0.0
var ramming_boost_hit_registered: bool = false

@export_group("Boarding Rope Resistance")
@export_range(0.05, 1.0, 0.01) var boarding_rope_resist_first_gain: float = 0.10
@export_range(0.0, 0.4, 0.01) var boarding_rope_resist_repeat_gain: float = 0.02
@export_range(0.1, 2.0, 0.05) var boarding_rope_resist_input_window: float = 0.65
@export_range(0.0, 1.5, 0.05) var boarding_rope_resist_decay_rate: float = 0.30
@export_range(0.2, 2.0, 0.05) var boarding_rope_resist_target_lock_grace: float = 0.80
@export_group("")
var boarding_rope_resist_progress: float = 0.0
var boarding_rope_resist_last_direction: int = 0
var boarding_rope_resist_input_window_timer: float = 0.0
var boarding_rope_resist_sfx_timer: float = 0.0
var boarding_rope_resist_stick_latch_direction: int = 0
var boarding_rope_resist_target: Node3D = null
var boarding_rope_resist_target_lock_timer: float = 0.0

@export_group("Crew / Captain")
@export var max_crew_count: int = 5 # 아군 병사 정원 (일반 병사 4 + 장군 1)
@export_range(0, 1, 1) var captain_count: int = 1
@export_range(1.0, 3.0, 0.05) var captain_health_multiplier: float = 1.65
@export_range(1.0, 3.0, 0.05) var captain_attack_multiplier: float = 1.4
@export_range(0.0, 10.0, 0.5) var captain_defense_bonus: float = 2.0

@export_group("Support Fleet")
@export var support_fleet_limit: int = 1

@export_group("Deck Cargo Transport")
@export var cargo_transport_enabled: bool = true
@export_range(0.5, 12.0, 0.25) var cargo_transport_delay: float = 3.0
@export_range(0.5, 8.0, 0.25) var cargo_transport_interval: float = 2.25
@export_range(0.2, 2.0, 0.05) var cargo_transport_throw_duration: float = 0.65
var cargo_transport_timer: float = 0.0
var cargo_transport_peace_timer: float = 0.0

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


@export_group("Crew Respawn Compatibility")
@export var auto_crew_respawn_enabled: bool = false
@export var crew_respawn_interval: float = 12.0 # 자동 보충이 켜졌을 때의 보충 주기 (초)
var crew_respawn_timer: float = 0.0

@export_group("Crew Stair")
@export var crew_stair_node_name: String = CARGO_TRANSPORT_STAIR_NODE_NAME
@export var crew_stair_top_node_name: String = CARGO_TRANSPORT_STAIR_TOP_NODE_NAME
@export var crew_stair_bottom_node_name: String = CARGO_TRANSPORT_STAIR_BOTTOM_NODE_NAME
@export var crew_stair_fallback_local_position: Vector3 = Vector3(0.0, 1.2, 2.93)
@export var crew_stair_stand_offset: Vector3 = Vector3(0.0, 0.0, -0.65)
@export var crew_stair_below_deck_drop: float = 1.25
@export var crew_stair_fallback_descent_local_offset: Vector3 = Vector3(0.0, -1.25, -0.9)
@export var crew_stair_descend_duration: float = 0.42
@export var crew_stair_return_duration: float = 0.55
@export var crew_stair_stow_duration: float = 0.48
@export var crew_stair_respawn_offset: Vector3 = Vector3(0.0, 0.0, -0.38)
@export_group("")

@export_group("Auto Raid Compatibility")
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

const CREW_ROLE_GENERAL := "general"
const CREW_ROLE_SPEARMAN := "spearman"
const CREW_ROLE_FIRE_POT := "fire_pot"
const CREW_ROLE_REPEATING_CROSSBOW := "repeating_crossbow"
const CREW_ROLE_SINGIGEON := "singigeon"

func _update_editor_hull() -> void:
	_ensure_editor_preview_hull(ship_type, hull_scene)
	_cache_hull_references(self)

func _ready() -> void:
	set_player_fleet_role("player_flagship")
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
		if not has_meta("base_player_hull_defense"):
			set_meta("base_player_hull_defense", hull_defense)
		var meta_manager = get_node_or_null("/root/MetaManager")
		if is_instance_valid(meta_manager):
			if meta_manager.has_method("get_hull_hp_bonus"): max_hull_hp += meta_manager.get_hull_hp_bonus()
			if meta_manager.has_method("get_sail_speed_multiplier"): max_speed *= meta_manager.get_sail_speed_multiplier()
			if meta_manager.has_method("get_hull_defense_bonus"): hull_defense = float(get_meta("base_player_hull_defense")) + meta_manager.get_hull_defense_bonus()
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
		_sync_player_crew_roster(true)
	if not has_meta("base_support_fleet_limit"):
		set_meta("base_support_fleet_limit", support_fleet_limit)


func _apply_runtime_scene_safety_defaults() -> void:
	if max_hull_hp < PLAYER_MIN_VALID_HULL_HP:
		var stats := load_ship_stats(ship_type)
		max_hull_hp = float(stats.get("hull_hp", PLAYER_FALLBACK_HULL_HP))
		hull_hp = max_hull_hp

	wood_splinter_scene = PLAYER_DEFAULT_WOOD_SPLINTER_SCENE
	water_splash_scene = PLAYER_DEFAULT_WATER_SPLASH_SCENE
	impact_puff_scene = PLAYER_DEFAULT_IMPACT_PUFF_SCENE
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
	_update_ramming_boost(delta)
	_update_boarding_rope_resistance(delta)
	if _is_auto_sail_control_enabled():
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
	_update_crew_respawn(delta)
	_update_auto_boarding_raid(delta)
	_update_fire_pot_logic(delta)
	_update_cargo_transport(delta)
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
		# 치트키: F2 누르면 바로 메인 경험치를 지급
		if OS.is_debug_build() and event.keycode == KEY_F2:
			if is_instance_valid(_cached_level_manager):
				_cached_level_manager.add_bonus_xp(999)
		if OS.is_debug_build() and event.keycode == KEY_F3:
			toggle_masts_folded()
			if is_instance_valid(_cached_hud) and _cached_hud.has_method("show_message"):
				var fold_text := "돛대 접힘" if are_masts_folded() else "돛대 펼침"
				_cached_hud.show_message("%s (debug)" % fold_text, 1.0)
				
		pass

func _spawn_or_repair_support_ship() -> void:
	PlayerShipSupportHelper.spawn_or_repair_support_ship(self)

func _get_support_fleet_ships() -> Array:
	return PlayerShipSupportHelper.get_support_fleet_ships(self)

func _get_offscreen_support_spawn_position() -> Vector3:
	return PlayerShipSupportHelper.get_offscreen_support_spawn_position(self)

## 병사 자동 보충 로직
func _update_crew_respawn(delta: float) -> void:
	if not auto_crew_respawn_enabled:
		crew_respawn_timer = 0.0
		return
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

func _update_cargo_transport(delta: float) -> void:
	PlayerShipCargoTransportHelper.update_cargo_transport(self, delta)


func _can_run_cargo_transport() -> bool:
	return PlayerShipCargoTransportHelper.can_run_cargo_transport(self)


func _try_cleanup_enemy_corpse() -> void:
	PlayerShipCargoTransportHelper.try_cleanup_corpse(self)


func _find_cleanup_corpse() -> Node3D:
	return PlayerShipCargoTransportHelper.find_cleanup_corpse(self)


func _find_cleanup_enemy_corpse() -> Node3D:
	return PlayerShipCargoTransportHelper.find_cleanup_enemy_corpse(self)


func _is_roof_corpse(corpse: Node3D) -> bool:
	return PlayerShipCargoTransportHelper.is_roof_corpse(corpse)


func _find_cleanup_corpse_by_team(target_team: String) -> Node3D:
	return PlayerShipCargoTransportHelper.find_cleanup_corpse_by_team(self, target_team)


func _find_cargo_transport_actor(corpse: Node3D) -> Node3D:
	return PlayerShipCargoTransportHelper.find_cargo_transport_actor(self, corpse)


func _prepare_cleaner_for_cargo_transport(cleaner: Node3D, corpse: Node3D) -> void:
	PlayerShipCargoTransportHelper.prepare_cleaner(self, cleaner, corpse)


func _is_cargo_transport_actor_busy(soldier) -> bool:
	return PlayerShipCargoTransportHelper.is_actor_busy(soldier)


func _set_cargo_transport_actor_action(cleaner: Node3D, action_name: String) -> void:
	PlayerShipCargoTransportHelper.set_actor_action(cleaner, action_name)


func _throw_payload_overboard(cleaner: Node3D, corpse: Node3D) -> void:
	var throw_target: Vector3 = _get_cargo_transport_throw_target(corpse)
	var pickup_point: Vector3 = _get_cargo_transport_pickup_point(cleaner, corpse)
	var rail_stand_point: Vector3 = _get_cargo_transport_rail_stand_point(cleaner, corpse, throw_target)
	var corpse_id: int = corpse.get_instance_id()
	var cleaner_id: int = cleaner.get_instance_id()
	var pickup_actor_position: Vector3 = _get_cargo_transport_actor_local_target(cleaner, pickup_point)
	var rail_actor_position: Vector3 = _get_cargo_transport_actor_local_target(cleaner, rail_stand_point)
	var pickup_carry_rotation: Vector3 = _get_cargo_transport_carry_rotation(corpse, pickup_point, throw_target)
	var rail_carry_rotation: Vector3 = _get_cargo_transport_carry_rotation(corpse, rail_stand_point, throw_target)
	var approach_seconds: float = _get_cargo_transport_walk_seconds(cleaner.global_position, pickup_point, cleaner)
	var pickup_seconds: float = 0.22
	var carry_seconds: float = _get_cargo_transport_walk_seconds(pickup_point, rail_stand_point, cleaner)
	var windup_seconds: float = 0.14
	var throw_seconds: float = maxf(0.25, cargo_transport_throw_duration * randf_range(1.05, 1.18))

	_face_cargo_transport_actor(cleaner, pickup_point)

	var tween := create_tween()
	tween.tween_property(cleaner, "position", pickup_actor_position, approach_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(Callable(self, "_face_cargo_transport_corpse_by_id").bind(cleaner_id, corpse_id))
	tween.tween_callback(Callable(self, "_set_cargo_transport_action_by_id").bind(cleaner_id, SoldierActionHelper.ACTION_CARGO_TRANSPORT_CARRY))
	tween.tween_callback(Callable(self, "_capture_cargo_transport_pickup_pose_by_id").bind(corpse_id))
	tween.tween_callback(Callable(self, "_begin_cargo_transport_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_method(
		Callable(self, "_apply_cargo_transport_payload_pickup").bind(corpse_id, cleaner_id, pickup_carry_rotation),
		0.0,
		1.0,
		pickup_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "_face_cargo_transport_actor_by_id").bind(cleaner_id, rail_stand_point))
	tween.tween_callback(Callable(self, "_begin_cargo_transport_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_property(cleaner, "position", rail_actor_position, carry_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_method(
		Callable(self, "_apply_cargo_transport_payload_follow").bind(corpse_id, cleaner_id, pickup_carry_rotation, rail_carry_rotation),
		0.0,
		1.0,
		carry_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "_face_cargo_transport_throw_target_by_id").bind(cleaner_id, corpse_id))
	tween.tween_callback(Callable(self, "_set_cargo_transport_action_by_id").bind(cleaner_id, SoldierActionHelper.ACTION_CARGO_TRANSPORT_THROW))
	tween.tween_callback(Callable(self, "_finish_cargo_transport_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_interval(windup_seconds)
	tween.tween_callback(Callable(self, "_capture_cargo_transport_throw_arc_by_id").bind(corpse_id, cleaner_id))
	tween.tween_method(
		Callable(self, "_apply_cargo_transport_throw_arc").bind(corpse_id, cleaner_id),
		0.0,
		1.0,
		throw_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(_finish_cargo_transport_throw.bind(corpse_id, cleaner_id))


func _throw_roof_payload_overboard(corpse: Node3D) -> void:
	if not is_instance_valid(corpse):
		return
	corpse.set_meta("cargo_transport_in_progress", true)
	var corpse_id: int = corpse.get_instance_id()
	_capture_roof_cargo_transport_throw_arc(corpse)
	var throw_seconds: float = maxf(0.28, cargo_transport_throw_duration * randf_range(0.95, 1.12))
	var tween := create_tween()
	tween.tween_method(
		Callable(self, "_apply_roof_cargo_transport_throw_arc").bind(corpse_id),
		0.0,
		1.0,
		throw_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(_finish_roof_cargo_transport_throw.bind(corpse_id))


func _stow_friendly_corpse_below_deck(cleaner: Node3D, corpse: Node3D) -> void:
	var stair_path: Dictionary = get_crew_stair_descent_points()
	var stair_top: Vector3 = stair_path.get("top", get_crew_stair_global_position())
	var stair_bottom: Vector3 = stair_path.get("bottom", stair_top + Vector3.DOWN * maxf(0.1, crew_stair_below_deck_drop))
	var stair_top_local: Vector3 = stair_path.get("top_local", to_local(stair_top))
	var stair_bottom_local: Vector3 = stair_path.get("bottom_local", to_local(stair_bottom))
	var stair_stand_point: Vector3 = _get_cargo_transport_stair_stand_point(cleaner)
	var pickup_point: Vector3 = _get_cargo_transport_pickup_point(cleaner, corpse)
	var corpse_id: int = corpse.get_instance_id()
	var cleaner_id: int = cleaner.get_instance_id()
	var pickup_actor_position: Vector3 = _get_cargo_transport_actor_local_target(cleaner, pickup_point)
	var stair_actor_position: Vector3 = _get_cargo_transport_actor_local_target(cleaner, stair_stand_point)
	var below_deck_actor_position: Vector3 = _get_cargo_transport_actor_local_target(cleaner, stair_bottom, true)
	var pickup_carry_rotation: Vector3 = _get_cargo_transport_carry_rotation(corpse, pickup_point, stair_top)
	var stair_carry_rotation: Vector3 = _get_cargo_transport_carry_rotation(corpse, stair_stand_point, stair_bottom)
	var approach_seconds: float = _get_cargo_transport_walk_seconds(cleaner.global_position, pickup_point, cleaner)
	var pickup_seconds: float = 0.22
	var carry_seconds: float = _get_cargo_transport_walk_seconds(pickup_point, stair_stand_point, cleaner)

	_face_cargo_transport_actor(cleaner, pickup_point)

	var tween := create_tween()
	tween.tween_property(cleaner, "position", pickup_actor_position, approach_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(Callable(self, "_face_cargo_transport_corpse_by_id").bind(cleaner_id, corpse_id))
	tween.tween_callback(Callable(self, "_set_cargo_transport_action_by_id").bind(cleaner_id, SoldierActionHelper.ACTION_CARGO_TRANSPORT_CARRY))
	tween.tween_callback(Callable(self, "_capture_cargo_transport_pickup_pose_by_id").bind(corpse_id))
	tween.tween_callback(Callable(self, "_begin_cargo_transport_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_method(
		Callable(self, "_apply_cargo_transport_payload_pickup").bind(corpse_id, cleaner_id, pickup_carry_rotation),
		0.0,
		1.0,
		pickup_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "_face_cargo_transport_actor_by_id").bind(cleaner_id, stair_top))
	tween.tween_callback(Callable(self, "_begin_cargo_transport_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_property(cleaner, "position", stair_actor_position, carry_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_method(
		Callable(self, "_apply_cargo_transport_payload_follow").bind(corpse_id, cleaner_id, pickup_carry_rotation, stair_carry_rotation),
		0.0,
		1.0,
		carry_seconds
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "_store_cargo_transport_stair_path_by_id").bind(corpse_id, stair_top_local, stair_bottom_local))
	tween.tween_callback(Callable(self, "_face_cargo_transport_actor_by_id").bind(cleaner_id, stair_bottom))
	tween.tween_property(cleaner, "position", below_deck_actor_position, maxf(0.08, crew_stair_descend_duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(
		Callable(self, "_apply_cargo_transport_payload_follow").bind(corpse_id, cleaner_id, stair_carry_rotation, stair_carry_rotation),
		0.0,
		1.0,
		maxf(0.08, crew_stair_descend_duration)
	).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "_finish_cargo_transport_carry_payload_by_id").bind(cleaner_id, corpse_id))
	tween.tween_callback(Callable(self, "_capture_cargo_transport_stow_pose_by_id").bind(corpse_id))
	tween.tween_method(
		Callable(self, "_apply_cargo_transport_stow_below_deck").bind(corpse_id),
		0.0,
		1.0,
		maxf(0.12, crew_stair_stow_duration)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(cleaner, "position", stair_actor_position, maxf(0.08, crew_stair_return_duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_finish_friendly_cargo_transport_stow.bind(corpse_id, cleaner_id))


func _get_cargo_transport_pickup_point(cleaner: Node3D, corpse: Node3D) -> Vector3:
	return PlayerShipCargoTransportHelper.get_pickup_point(self, cleaner, corpse)


func _get_cargo_transport_stair_stand_point(cleaner: Node3D) -> Vector3:
	return PlayerShipCargoTransportHelper.get_stair_stand_point(self, cleaner)


func _get_cargo_transport_rail_stand_point(cleaner: Node3D, corpse: Node3D, throw_target: Vector3) -> Vector3:
	return PlayerShipCargoTransportHelper.get_rail_stand_point(self, cleaner, corpse, throw_target)


func _get_cargo_transport_actor_local_target(cleaner: Node3D, global_target: Vector3, preserve_target_y: bool = false) -> Vector3:
	return PlayerShipCargoTransportHelper.get_actor_local_target(cleaner, global_target, preserve_target_y)


func _get_cargo_transport_carry_rotation(corpse: Node3D, actor_position: Vector3, throw_target: Vector3) -> Vector3:
	return PlayerShipCargoTransportHelper.get_carry_rotation(self, corpse, actor_position, throw_target)


func _get_cargo_transport_walk_seconds(from_position: Vector3, to_position: Vector3, cleaner: Node3D) -> float:
	return PlayerShipCargoTransportHelper.get_walk_seconds(from_position, to_position, cleaner)


func _clamp_cargo_transport_deck_local(local_point: Vector3, inset: float) -> Vector3:
	return PlayerShipCargoTransportHelper.clamp_deck_local(self, local_point, inset)


func _face_cargo_transport_actor(cleaner: Node3D, look_position: Vector3) -> void:
	PlayerShipCargoTransportHelper.face_actor(cleaner, look_position)


func _face_cargo_transport_actor_by_id(cleaner_id: int, look_position: Vector3) -> void:
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	if is_instance_valid(cleaner):
		_face_cargo_transport_actor(cleaner, look_position)


func _face_cargo_transport_corpse_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	var corpse := NodeContractHelper.get_instance_node3d(corpse_id)
	if is_instance_valid(cleaner) and is_instance_valid(corpse):
		_face_cargo_transport_actor(cleaner, corpse.global_position)


func _face_cargo_transport_throw_target_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	var corpse := NodeContractHelper.get_instance_node3d(corpse_id)
	if is_instance_valid(cleaner) and is_instance_valid(corpse):
		_face_cargo_transport_actor(cleaner, _get_cargo_transport_throw_target(corpse))


func _set_cargo_transport_action_by_id(cleaner_id: int, action_name: String) -> void:
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	if is_instance_valid(cleaner):
		_set_cargo_transport_actor_action(cleaner, action_name)


func _begin_cargo_transport_carry_payload_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	var corpse := NodeContractHelper.get_instance_node3d(corpse_id)
	if is_instance_valid(cleaner) and is_instance_valid(corpse):
		_begin_cargo_transport_carry_payload(cleaner, corpse)


func _capture_cargo_transport_pickup_pose_by_id(corpse_id: int) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	if not is_instance_valid(corpse_node):
		return
	corpse_node.set_meta(CARGO_TRANSPORT_PICKUP_START_POSITION_META, corpse_node.global_position)
	corpse_node.set_meta(CARGO_TRANSPORT_PICKUP_START_ROTATION_META, corpse_node.rotation)


func _begin_cargo_transport_carry_payload(cleaner: Node3D, corpse: Node3D) -> void:
	var side_sign := 1.0 if to_local(cleaner.global_position).x >= 0.0 else -1.0
	var offset_overrides := _get_cargo_transport_carry_payload_offsets()
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


func _get_cargo_transport_carry_payload_offsets() -> Dictionary:
	return PlayerShipCargoTransportHelper.get_transport_payload_offsets()


func _finish_cargo_transport_carry_payload_by_id(cleaner_id: int, corpse_id: int) -> void:
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	var corpse := NodeContractHelper.get_instance_node3d(corpse_id)
	if is_instance_valid(cleaner):
		if cleaner.has_method("finish_carry_payload") and is_instance_valid(corpse):
			cleaner.call("finish_carry_payload", corpse)
		else:
			SoldierActionHelper.finish_carry_payload(cleaner, corpse)


func _get_cargo_transport_throw_origin(cleaner: Node3D, corpse: Node3D, throw_target: Vector3) -> Vector3:
	return PlayerShipCargoTransportHelper.get_throw_origin(cleaner, corpse, throw_target)


func _get_cargo_transport_throw_origin_from_actor_position(actor_position: Vector3, corpse: Node3D, throw_target: Vector3) -> Vector3:
	return PlayerShipCargoTransportHelper.get_throw_origin_from_actor_position(actor_position, corpse, throw_target)


func _apply_cargo_transport_payload_pickup(progress: float, corpse_id: int, cleaner_id: int, target_rotation: Vector3) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	if not is_instance_valid(corpse_node) or not is_instance_valid(cleaner):
		return
	var start_position: Vector3 = corpse_node.get_meta(CARGO_TRANSPORT_PICKUP_START_POSITION_META, corpse_node.global_position)
	var start_rotation: Vector3 = corpse_node.get_meta(CARGO_TRANSPORT_PICKUP_START_ROTATION_META, corpse_node.rotation)
	SoldierActionHelper.apply_carry_payload_pickup(cleaner, corpse_node, progress, start_position, start_rotation, target_rotation)
	if progress >= 1.0:
		if corpse_node.has_meta(CARGO_TRANSPORT_PICKUP_START_POSITION_META):
			corpse_node.remove_meta(CARGO_TRANSPORT_PICKUP_START_POSITION_META)
		if corpse_node.has_meta(CARGO_TRANSPORT_PICKUP_START_ROTATION_META):
			corpse_node.remove_meta(CARGO_TRANSPORT_PICKUP_START_ROTATION_META)


func _apply_cargo_transport_payload_follow(progress: float, corpse_id: int, cleaner_id: int, start_rotation: Vector3, target_rotation: Vector3) -> void:
	var corpse := NodeContractHelper.get_instance_node3d(corpse_id)
	var cleaner := NodeContractHelper.get_instance_node3d(cleaner_id)
	if not is_instance_valid(corpse) or not is_instance_valid(cleaner):
		return
	SoldierActionHelper.apply_carry_payload_follow(cleaner, corpse, progress, start_rotation, target_rotation)


func _capture_cargo_transport_throw_arc_by_id(corpse_id: int, cleaner_id: int) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	var cleaner_node := NodeContractHelper.get_instance_node3d(cleaner_id)
	if not is_instance_valid(corpse_node) or not is_instance_valid(cleaner_node):
		return
	var throw_target: Vector3 = _get_cargo_transport_throw_target(corpse_node)
	var throw_origin: Vector3 = _get_cargo_transport_throw_origin(cleaner_node, corpse_node, throw_target)
	var start_position: Vector3 = corpse_node.global_position
	var arc_control: Vector3 = throw_origin.lerp(throw_target, 0.52)
	arc_control.y = maxf(maxf(start_position.y, throw_origin.y), throw_target.y) + randf_range(1.85, 2.45)
	corpse_node.set_meta(CARGO_TRANSPORT_THROW_ARC_META, {
		"start_position": start_position,
		"arc_control": arc_control,
		"throw_target": throw_target,
		"start_rotation": corpse_node.rotation,
		"spin_rotation": corpse_node.rotation + Vector3(randf_range(1.7, 2.8), randf_range(-0.9, 0.9), randf_range(-1.8, 1.8)),
	})


func _apply_cargo_transport_throw_arc(progress: float, corpse_id: int, cleaner_id: int) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	if not is_instance_valid(corpse_node):
		return
	if not corpse_node.has_meta(CARGO_TRANSPORT_THROW_ARC_META):
		_capture_cargo_transport_throw_arc_by_id(corpse_id, cleaner_id)
	var arc_data: Dictionary = corpse_node.get_meta(CARGO_TRANSPORT_THROW_ARC_META, {})
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
	if progress >= 1.0 and corpse_node.has_meta(CARGO_TRANSPORT_THROW_ARC_META):
		corpse_node.remove_meta(CARGO_TRANSPORT_THROW_ARC_META)


func _capture_roof_cargo_transport_throw_arc(corpse: Node3D) -> void:
	if not is_instance_valid(corpse):
		return
	var start_position: Vector3 = corpse.global_position
	var throw_target: Vector3 = _get_roof_cargo_transport_throw_target(corpse)
	var arc_control: Vector3 = start_position.lerp(throw_target, 0.48)
	arc_control.y = maxf(start_position.y, throw_target.y) + randf_range(1.45, 2.05)
	corpse.set_meta(ROOF_CARGO_TRANSPORT_ARC_META, {
		"start_position": start_position,
		"arc_control": arc_control,
		"throw_target": throw_target,
		"start_rotation": corpse.rotation,
		"spin_rotation": corpse.rotation + Vector3(randf_range(1.6, 2.7), randf_range(-0.9, 0.9), randf_range(-1.6, 1.6)),
	})


func _apply_roof_cargo_transport_throw_arc(progress: float, corpse_id: int) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	if not is_instance_valid(corpse_node):
		return
	var arc_data: Dictionary = corpse_node.get_meta(ROOF_CARGO_TRANSPORT_ARC_META, {})
	if arc_data.is_empty():
		_capture_roof_cargo_transport_throw_arc(corpse_node)
		arc_data = corpse_node.get_meta(ROOF_CARGO_TRANSPORT_ARC_META, {})
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
	if progress >= 1.0 and corpse_node.has_meta(ROOF_CARGO_TRANSPORT_ARC_META):
		corpse_node.remove_meta(ROOF_CARGO_TRANSPORT_ARC_META)


func _capture_cargo_transport_stow_pose_by_id(corpse_id: int) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	if not is_instance_valid(corpse_node):
		return
	var fallback_bottom_local := to_local(get_crew_stair_global_position()) + crew_stair_fallback_descent_local_offset
	var stair_bottom_local: Vector3 = corpse_node.get_meta(
		CARGO_TRANSPORT_STAIR_BOTTOM_META,
		fallback_bottom_local
	)
	corpse_node.set_meta(CARGO_TRANSPORT_STOW_POSE_META, {
		"start_position": corpse_node.global_position,
		"target_local_position": stair_bottom_local,
		"start_rotation": corpse_node.rotation,
	})


func _apply_cargo_transport_stow_below_deck(progress: float, corpse_id: int) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	if not is_instance_valid(corpse_node):
		return
	var pose: Dictionary = corpse_node.get_meta(CARGO_TRANSPORT_STOW_POSE_META, {})
	if pose.is_empty():
		_capture_cargo_transport_stow_pose_by_id(corpse_id)
		pose = corpse_node.get_meta(CARGO_TRANSPORT_STOW_POSE_META, {})
	if pose.is_empty():
		return
	var t: float = smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	var start_position: Vector3 = pose.get("start_position", corpse_node.global_position)
	var target_local_position: Vector3 = pose.get("target_local_position", to_local(get_crew_stair_global_position()))
	var target_position: Vector3 = to_global(target_local_position)
	corpse_node.global_position = start_position.lerp(target_position, t)
	corpse_node.scale = corpse_node.scale.lerp(Vector3.ONE * 0.82, t)
	if progress >= 1.0 and corpse_node.has_meta(CARGO_TRANSPORT_STOW_POSE_META):
		corpse_node.remove_meta(CARGO_TRANSPORT_STOW_POSE_META)


func _store_cargo_transport_stair_path_by_id(corpse_id: int, stair_top_local: Vector3, stair_bottom_local: Vector3) -> void:
	var corpse_node := NodeContractHelper.get_instance_node3d(corpse_id)
	if not is_instance_valid(corpse_node):
		return
	corpse_node.set_meta(CARGO_TRANSPORT_STAIR_TOP_META, stair_top_local)
	corpse_node.set_meta(CARGO_TRANSPORT_STAIR_BOTTOM_META, stair_bottom_local)


func _get_cargo_transport_throw_target(corpse: Node3D) -> Vector3:
	return PlayerShipCargoTransportHelper.get_throw_target(self, corpse)


func _get_roof_cargo_transport_throw_target(corpse: Node3D) -> Vector3:
	return PlayerShipCargoTransportHelper.get_roof_throw_target(self, corpse)


func _finish_cargo_transport_throw(corpse_id: int, cleaner_id: int) -> void:
	var corpse := NodeContractHelper.get_instance_node(corpse_id)
	var cleaner := NodeContractHelper.get_instance_node(cleaner_id)
	if is_instance_valid(corpse):
		if corpse is Node3D:
			_play_overboard_disposal_splash((corpse as Node3D).global_position)
		_grant_cargo_transport_xp()
		SoldierShipWorkPriorityHelper.release_work_slot(corpse, cleaner, SoldierShipWorkPriorityHelper.TASK_CARGO_TRANSPORT)
		corpse.queue_free()
	if is_instance_valid(cleaner):
		if cleaner.has_method("finish_cargo_transport_action"):
			cleaner.call("finish_cargo_transport_action")
		else:
			SoldierActionHelper.finish_cargo_transport_action(cleaner)


func _finish_roof_cargo_transport_throw(corpse_id: int) -> void:
	var corpse := NodeContractHelper.get_instance_node(corpse_id)
	if not is_instance_valid(corpse):
		return
	if corpse is Node3D:
		_play_overboard_disposal_splash((corpse as Node3D).global_position)
	_grant_cargo_transport_xp()
	corpse.queue_free()


func _finish_friendly_cargo_transport_stow(corpse_id: int, cleaner_id: int) -> void:
	var corpse := NodeContractHelper.get_instance_node(corpse_id)
	var cleaner := NodeContractHelper.get_instance_node(cleaner_id)
	if is_instance_valid(corpse):
		if corpse.has_meta(CARGO_TRANSPORT_STAIR_TOP_META):
			corpse.remove_meta(CARGO_TRANSPORT_STAIR_TOP_META)
		if corpse.has_meta(CARGO_TRANSPORT_STAIR_BOTTOM_META):
			corpse.remove_meta(CARGO_TRANSPORT_STAIR_BOTTOM_META)
		SoldierShipWorkPriorityHelper.release_work_slot(corpse, cleaner, SoldierShipWorkPriorityHelper.TASK_CARGO_TRANSPORT)
		corpse.queue_free()
	if is_instance_valid(cleaner):
		if cleaner.has_method("finish_cargo_transport_action"):
			cleaner.call("finish_cargo_transport_action")
		else:
			SoldierActionHelper.finish_cargo_transport_action(cleaner)


func _grant_cargo_transport_xp() -> void:
	PlayerShipCargoTransportHelper.grant_xp(self)


func _play_overboard_disposal_splash(splash_pos: Vector3) -> void:
	PlayerShipCargoTransportHelper.play_overboard_disposal_splash(self, splash_pos)


func get_crew_stair_global_position() -> Vector3:
	var marker_path := _get_authored_crew_stair_descent_points()
	if not marker_path.is_empty():
		return marker_path.get("top", to_global(crew_stair_fallback_local_position))
	var stair_node := find_child(crew_stair_node_name, true, false) as Node3D
	if is_instance_valid(stair_node):
		return stair_node.global_position
	return to_global(crew_stair_fallback_local_position)


func get_crew_stair_descent_points() -> Dictionary:
	var marker_path := _get_authored_crew_stair_descent_points()
	if not marker_path.is_empty():
		return marker_path
	var stair_node := find_child(crew_stair_node_name, true, false) as Node3D
	if is_instance_valid(stair_node):
		var mesh_instance := stair_node as MeshInstance3D
		if is_instance_valid(mesh_instance) and is_instance_valid(mesh_instance.mesh):
			var aabb: AABB = mesh_instance.mesh.get_aabb()
			var min_corner: Vector3 = aabb.position
			var max_corner: Vector3 = aabb.position + aabb.size
			var local_top := Vector3(0.0, max_corner.y, min_corner.z)
			var local_bottom := Vector3(0.0, min_corner.y, max_corner.z)
			var top: Vector3 = mesh_instance.global_transform * local_top
			var bottom: Vector3 = mesh_instance.global_transform * local_bottom
			if top.y < bottom.y:
				var swap := top
				top = bottom
				bottom = swap
			var mesh_resolved_points := _resolve_crew_stair_descent_local_points(to_local(top), to_local(bottom))
			var mesh_resolved_top_local: Vector3 = mesh_resolved_points.get("top_local", to_local(top))
			var mesh_resolved_bottom_local: Vector3 = mesh_resolved_points.get("bottom_local", to_local(bottom))
			return {
				"top": to_global(mesh_resolved_top_local),
				"bottom": to_global(mesh_resolved_bottom_local),
				"top_local": mesh_resolved_top_local,
				"bottom_local": mesh_resolved_bottom_local,
			}
		var stair_top := stair_node.global_position
		var stair_bottom := stair_node.global_position + global_transform.basis * crew_stair_fallback_descent_local_offset
		var node_resolved_points := _resolve_crew_stair_descent_local_points(to_local(stair_top), to_local(stair_bottom))
		var node_resolved_top_local: Vector3 = node_resolved_points.get("top_local", to_local(stair_top))
		var node_resolved_bottom_local: Vector3 = node_resolved_points.get("bottom_local", to_local(stair_bottom))
		return {
			"top": to_global(node_resolved_top_local),
			"bottom": to_global(node_resolved_bottom_local),
			"top_local": node_resolved_top_local,
			"bottom_local": node_resolved_bottom_local,
		}
	var fallback_resolved_points := _resolve_crew_stair_descent_local_points(
		crew_stair_fallback_local_position,
		crew_stair_fallback_local_position + crew_stair_fallback_descent_local_offset
	)
	var fallback_resolved_top_local: Vector3 = fallback_resolved_points.get("top_local", crew_stair_fallback_local_position)
	var fallback_resolved_bottom_local: Vector3 = fallback_resolved_points.get(
		"bottom_local",
		crew_stair_fallback_local_position + crew_stair_fallback_descent_local_offset
	)
	return {
		"top": to_global(fallback_resolved_top_local),
		"bottom": to_global(fallback_resolved_bottom_local),
		"top_local": fallback_resolved_top_local,
		"bottom_local": fallback_resolved_bottom_local,
	}


func _get_authored_crew_stair_descent_points() -> Dictionary:
	var top_marker := find_child(crew_stair_top_node_name, true, false) as Node3D
	var bottom_marker := find_child(crew_stair_bottom_node_name, true, false) as Node3D
	if not is_instance_valid(top_marker) or not is_instance_valid(bottom_marker):
		return {}
	var top_local := to_local(top_marker.global_position)
	var bottom_local := to_local(bottom_marker.global_position)
	if top_local.y < bottom_local.y:
		var swap := top_local
		top_local = bottom_local
		bottom_local = swap
	return {
		"top": to_global(top_local),
		"bottom": to_global(bottom_local),
		"top_local": top_local,
		"bottom_local": bottom_local,
	}


func _resolve_crew_stair_descent_local_points(top_local: Vector3, bottom_local: Vector3) -> Dictionary:
	var resolved_top := top_local
	var resolved_bottom := bottom_local
	var min_drop := maxf(0.35, crew_stair_below_deck_drop * 0.65)
	if resolved_top.y - resolved_bottom.y < min_drop:
		resolved_bottom.y = resolved_top.y - maxf(0.1, crew_stair_below_deck_drop)
	var desired_z_drop := -absf(crew_stair_fallback_descent_local_offset.z)
	if desired_z_drop < -0.01 and resolved_bottom.z > resolved_top.z + desired_z_drop * 0.35:
		resolved_bottom.z = resolved_top.z + desired_z_drop
	return {
		"top_local": resolved_top,
		"bottom_local": resolved_bottom,
	}


func get_crew_respawn_global_position() -> Vector3:
	var stair_path := get_crew_stair_descent_points()
	var local_pos: Vector3 = stair_path.get("top_local", to_local(get_crew_stair_global_position())) + crew_stair_respawn_offset
	local_pos = _clamp_cargo_transport_deck_local(local_pos, 0.32)
	local_pos.y = float(deck_height) if "deck_height" in self else local_pos.y
	return to_global(local_pos)

func _update_auto_boarding_raid(delta: float) -> void:
	PlayerShipCrewHelper.update_auto_boarding_raid(self, delta)

func _toggle_manual_boarding_intent() -> void:
	PlayerShipCrewHelper.toggle_manual_boarding_intent(self)

func _clear_manual_boarding_intent() -> void:
	PlayerShipCrewHelper.clear_manual_boarding_intent(self)

func _get_desired_player_crew_roles() -> Dictionary:
	return PlayerShipCrewHelper.get_desired_player_crew_roles(self)

func _get_soldier_role(soldier: Node) -> String:
	return PlayerShipCrewHelper.get_soldier_role(self, soldier)

func _spawn_player_soldier(soldiers_node: Node, role: String) -> Node:
	return PlayerShipCrewHelper.spawn_player_soldier(self, soldiers_node, role)

func _sync_player_crew_roster(allow_spawn_missing: bool = false) -> void:
	var initial_sync_done := bool(get_meta("player_crew_initial_roster_synced", false))
	var can_spawn_missing := allow_spawn_missing or not initial_sync_done
	PlayerShipCrewHelper.sync_player_crew_roster(self, can_spawn_missing)
	if not initial_sync_done:
		set_meta("player_crew_initial_roster_synced", true)

## 키보드 입력 처리
func _handle_input(delta: float) -> void:
	PlayerShipRuntimeHelper.handle_input(self, delta)

func _toggle_fleet_formation() -> void:
	PlayerShipRuntimeHelper.toggle_fleet_formation(self)

func _cycle_fleet_formation() -> void:
	PlayerShipRuntimeHelper.cycle_fleet_formation(self)


func try_activate_ramming_boost() -> bool:
	if ramming_boost_active:
		return false
	if not _can_activate_ramming_boost_with_sail_state():
		_show_ramming_boost_blocked_message()
		return false
	if ramming_boost_charge < 1.0:
		return false
	ramming_boost_active = true
	ramming_boost_timer = maxf(0.05, ramming_boost_duration)
	ramming_boost_hit_registered = false
	ramming_boost_charge = 0.0
	var boosted_floor := maxf(min_ramming_speed + 0.45, max_speed * 0.72)
	var boosted_cap := get_ramming_boost_target_speed()
	current_speed = minf(maxf(current_speed + ramming_boost_impulse_speed, boosted_floor), boosted_cap)
	if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
		_cached_audio_manager.play_sfx("wave_splash", global_position, randf_range(0.94, 1.08), 2.5)
	return true


func _update_ramming_boost(delta: float) -> void:
	ramming_boost_blocked_message_timer = maxf(0.0, ramming_boost_blocked_message_timer - delta)
	if ramming_boost_active:
		ramming_boost_timer = maxf(0.0, ramming_boost_timer - delta)
		if ramming_boost_timer <= 0.0:
			ramming_boost_active = false
			if not ramming_boost_hit_registered:
				ramming_boost_charge = maxf(ramming_boost_charge, 0.35)
		return
	if ramming_boost_charge < 1.0:
		ramming_boost_charge = minf(1.0, ramming_boost_charge + delta / get_ramming_boost_recharge_duration_value())


func _can_activate_ramming_boost_with_sail_state() -> bool:
	if not sail_furled:
		return false
	if sail_deployed_ratio > 0.02:
		return false
	if not mast_fold_pivots.is_empty() and not are_masts_folded():
		return false
	return true


func _show_ramming_boost_blocked_message() -> void:
	if ramming_boost_blocked_message_timer > 0.0:
		return
	ramming_boost_blocked_message_timer = 0.8
	if is_instance_valid(_cached_hud) and _cached_hud.has_method("show_message"):
		_cached_hud.show_message(LocaleManager.t("hud.ram_boost.need_folded_masts", "돛을 완전히 접어야 충각 돌진 가능"), 1.2)


func is_ramming_boost_active() -> bool:
	return ramming_boost_active and ramming_boost_timer > 0.0


func get_ramming_boost_charge_ratio() -> float:
	if is_ramming_boost_active():
		return clampf(ramming_boost_timer / maxf(0.05, ramming_boost_duration), 0.0, 1.0)
	return clampf(ramming_boost_charge, 0.0, 1.0)


func get_ramming_boost_recharge_duration_value() -> float:
	return maxf(0.1, ramming_boost_recharge_duration * clampf(ramming_boost_recharge_multiplier, 0.1, 1.0))


func should_show_ramming_boost_gauge() -> bool:
	return is_ramming_boost_active() or _can_activate_ramming_boost_with_sail_state()


func get_ramming_boost_target_speed() -> float:
	return maxf(max_speed, min_ramming_speed) * maxf(1.0, ramming_boost_speed_multiplier)


func get_ramming_boost_turn_multiplier() -> float:
	return ramming_boost_turn_multiplier if is_ramming_boost_active() else 1.0


func notify_ramming_boost_hit() -> void:
	if is_ramming_boost_active():
		ramming_boost_hit_registered = true


func get_ramming_damage_multiplier_value() -> float:
	var boost_mult := ramming_boost_damage_multiplier if is_ramming_boost_active() else 1.0
	return maxf(0.1, ramming_damage_multiplier) * boost_mult


func try_resist_incoming_boarding_rope(direction: int) -> bool:
	if direction == 0:
		return false
	var attacker := _get_resistable_boarding_attacker()
	if not is_instance_valid(attacker):
		_reset_boarding_rope_resistance()
		return false
	var normalized_direction := -1 if direction < 0 else 1
	var alternated := boarding_rope_resist_last_direction != 0 \
		and boarding_rope_resist_last_direction != normalized_direction \
		and boarding_rope_resist_input_window_timer > 0.0
	var gain := boarding_rope_resist_repeat_gain
	if boarding_rope_resist_last_direction == 0 or boarding_rope_resist_input_window_timer <= 0.0:
		gain = boarding_rope_resist_first_gain
	elif alternated:
		gain = boarding_rope_resist_first_gain
		_play_rope_resist_tension_sfx(false)
	boarding_rope_resist_progress = clampf(boarding_rope_resist_progress + gain, 0.0, 1.0)
	if attacker.has_method("pulse_boarding_rope_feedback"):
		var pulse_intensity := 0.42 if not alternated else 0.82
		attacker.call("pulse_boarding_rope_feedback", pulse_intensity)
	boarding_rope_resist_target = attacker
	boarding_rope_resist_target_lock_timer = boarding_rope_resist_target_lock_grace
	boarding_rope_resist_last_direction = normalized_direction
	boarding_rope_resist_input_window_timer = boarding_rope_resist_input_window
	if boarding_rope_resist_progress >= 1.0:
		_break_incoming_boarding_rope(attacker)
	return true


func get_boarding_rope_resist_ratio() -> float:
	return clampf(boarding_rope_resist_progress, 0.0, 1.0) if is_instance_valid(_get_resistable_boarding_attacker()) else 0.0


func _update_boarding_rope_resistance(delta: float) -> void:
	boarding_rope_resist_sfx_timer = maxf(0.0, boarding_rope_resist_sfx_timer - delta)
	boarding_rope_resist_target_lock_timer = maxf(0.0, boarding_rope_resist_target_lock_timer - delta)
	if is_instance_valid(boarding_rope_resist_target) and boarding_rope_resist_target_lock_timer <= 0.0:
		_reset_boarding_rope_resistance()
		return
	if not is_instance_valid(_get_resistable_boarding_attacker()):
		_reset_boarding_rope_resistance()
		return
	boarding_rope_resist_input_window_timer = maxf(0.0, boarding_rope_resist_input_window_timer - delta)
	if boarding_rope_resist_input_window_timer <= 0.0:
		boarding_rope_resist_last_direction = 0
	boarding_rope_resist_progress = maxf(0.0, boarding_rope_resist_progress - boarding_rope_resist_decay_rate * delta)


func _get_resistable_boarding_attacker() -> Node3D:
	if _is_resistable_boarding_attacker(boarding_rope_resist_target):
		return boarding_rope_resist_target
	if boarding_rope_resist_target != null:
		_reset_boarding_rope_resistance()
	var attacker := _select_resistable_boarding_attacker()
	boarding_rope_resist_target = attacker
	return attacker


func _select_resistable_boarding_attacker() -> Node3D:
	var best_attacker: Node3D = null
	var best_score := -INF
	for candidate in _get_ships_cached(get_tree()):
		if not _is_resistable_boarding_attacker(candidate):
			continue
		var candidate_ship := candidate as Node3D
		var score := _get_boarding_rope_resist_target_score(candidate_ship)
		if score > best_score:
			best_score = score
			best_attacker = candidate_ship
	return best_attacker


func _is_resistable_boarding_attacker(attacker: Variant) -> bool:
	if not is_instance_valid(attacker):
		return false
	if not (attacker is Node3D):
		return false
	if attacker == self:
		return false
	var attacker_team: String = attacker.get_team_tag() if attacker.has_method("get_team_tag") else str(attacker.get("team"))
	if attacker_team != "enemy":
		return false
	if attacker.get("is_boarding") != true:
		return false
	if attacker.has_method("get_boarding_target_ship") and attacker.call("get_boarding_target_ship") != self:
		return false
	if attacker.has_method("has_boarding_rope_link_to") and attacker.call("has_boarding_rope_link_to", self) != true:
		return false
	return true


func _get_boarding_rope_resist_target_score(attacker: Node3D) -> float:
	var prep_duration := maxf(0.001, float(attacker.get("boarding_prep_duration")))
	var prep_ratio := clampf(float(attacker.get("boarding_prep_timer")) / prep_duration, 0.0, 1.0)
	var interval := maxf(0.001, float(attacker.call("get_effective_boarding_interval")) if attacker.has_method("get_effective_boarding_interval") else float(attacker.get("boarding_interval")))
	var timer_ratio := clampf(float(attacker.get("boarding_timer")) / interval, 0.0, 1.0)
	var distance_score := 0.0
	if is_instance_valid(attacker):
		distance_score = -global_position.distance_to(attacker.global_position) * 0.001
	return prep_ratio * 2.0 + timer_ratio + distance_score


func _break_incoming_boarding_rope(attacker: Node3D) -> void:
	if not is_instance_valid(attacker):
		_reset_boarding_rope_resistance()
		return
	_play_rope_resist_tension_sfx(true)
	if attacker.has_method("pulse_boarding_rope_feedback"):
		attacker.call("pulse_boarding_rope_feedback", 1.0)
	if attacker.has_method("apply_boarding_retry_cooldown"):
		attacker.call("apply_boarding_retry_cooldown", self)
	if attacker.has_method("_cancel_boarding"):
		attacker.call("_cancel_boarding")
	elif attacker.has_method("_clear_ropes"):
		attacker.call("_clear_ropes")
	if get_boarding_attacker_ship() == attacker:
		clear_boarding_attacker_ship()
	_reset_boarding_rope_resistance()


func _reset_boarding_rope_resistance() -> void:
	boarding_rope_resist_progress = 0.0
	boarding_rope_resist_last_direction = 0
	boarding_rope_resist_input_window_timer = 0.0
	boarding_rope_resist_target_lock_timer = 0.0
	boarding_rope_resist_target = null


func _play_rope_resist_tension_sfx(break_sound: bool) -> void:
	if not is_instance_valid(_cached_audio_manager) or not _cached_audio_manager.has_method("play_sfx"):
		return
	if boarding_rope_resist_sfx_timer > 0.0 and not break_sound:
		return
	boarding_rope_resist_sfx_timer = 0.18
	if break_sound:
		_cached_audio_manager.play_sfx("soldier_hit", global_position, randf_range(1.22, 1.38), -4.0)
		return
	_cached_audio_manager.play_sfx("soldier_hit", global_position, randf_range(0.78, 0.92), -8.0)


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

func _is_auto_sail_control_enabled() -> bool:
	if not is_instance_valid(SaveManager):
		return has_sextant
	return str(SaveManager.get_setting("sail_control_mode", "manual")) == "auto"

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
		var message := "돛 접음: 노 속도 +1 / 화재 피해 감소 / 충각 돌진 가능" if sail_furled else "돛 펼침: 항해 속도 회복"
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

func trigger_boarding_overrun_game_over() -> void:
	PlayerShipSinkHelper.trigger_boarding_overrun_game_over(self)

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
