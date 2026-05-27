@tool
extends "res://scripts/entities/ships/base_ship.gd"
class_name AIShip

const DEBUG_CHASER_LOGS := false
const AIShipSoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")
const SupportFleetCannonRules = preload("res://scripts/entities/ships/support_fleet_cannon_helper.gd")
const AIShipProfileHelper = preload("res://scripts/entities/ships/ai_ship_profile_helper.gd")
const AIShipLoadoutHelper = preload("res://scripts/entities/ships/ai_ship_loadout_helper.gd")
const AIShipRuntimeHelper = preload("res://scripts/entities/ships/ai_ship_runtime_helper.gd")
const AIShipBoardingHelper = preload("res://scripts/entities/ships/ai_ship_boarding_helper.gd")
const AIShipLifecycleHelper = preload("res://scripts/entities/ships/ai_ship_lifecycle_helper.gd")
const AIShipSupportHelper = preload("res://scripts/entities/ships/ai_ship_support_helper.gd")
const FlagSceneLibrary = preload("res://scripts/props/flag_scene_library.gd")
const PhysicsProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const DEFAULT_SOLDIER_SCENE_PATH := "res://scenes/entities/soldiers/soldier.tscn"
const DEFAULT_CANNON_SCENE_PATH := "res://scenes/entities/launchers/cannon_enemy_light.tscn"
const DEFAULT_HULL_SCENE_PATH := "res://scenes/ships/hulls/sekibune_hull.tscn"
const DEFAULT_FIRE_POT_SCENE_PATH := "res://scenes/projectiles/fire_pot.tscn"
const DEFAULT_ENEMY_DRIFTER_XP_SCENE_PATH := "res://scenes/effects/enemy_drifter_xp.tscn"
const DEFER_INITIAL_CREW_SETUP_META := "defer_initial_crew_setup"
const BOARDING_CONTACT_DEFENSE_RADIUS_MIN := 2.4
const BOARDING_CONTACT_DEFENSE_RADIUS_MAX := 5.5
const ENEMY_BOARDING_LATCH_DURATION_BONUS := 0.15
const ENEMY_BOARDING_LATCH_DISTANCE_BONUS := 0.25
const ENEMY_BOARDING_LATCH_SPEED_BONUS := 0.15
const BOARDING_RETRY_COOLDOWN_TARGET_ID_META := "boarding_retry_cooldown_target_id"
const BOARDING_RETRY_COOLDOWN_TIMER_META := "boarding_retry_cooldown_timer"
const DERELICT_STATUS_CHECK_INTERVAL := 0.35

## AI ship runtime
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var team: String = "enemy" # "enemy" or "player"
@export var move_speed: float = 3.5
@export var soldier_scene: PackedScene
@export_range(1, 12, 1) var initial_crew_count: int = 4

@export var cannon_scene: PackedScene
@export var hull_scene: PackedScene
@export var preferred_soldier_type: String = "general" ## "general", "melee", "ranged"
@export var enemy_drifter_xp_scene: PackedScene = preload("res://scenes/effects/enemy_drifter_xp.tscn")
enum CombatRole {CHARGER, GUNNER}
@export var combat_role: CombatRole = CombatRole.CHARGER
@export_range(4.0, 30.0) var preferred_combat_range: float = 14.0
@export_range(0.5, 8.0) var combat_range_tolerance: float = 2.5
@export_range(2.0, 20.0) var retreat_distance: float = 8.0
@export var allow_boarding: bool = true
@export_range(0.2, 3.0, 0.05) var boarding_latch_duration: float = 1.15
@export_range(0.0, 4.0, 0.05) var boarding_latch_distance_pad: float = 1.55
@export_range(1.0, 5.0, 0.05) var boarding_latch_relative_speed_mult: float = 2.8
@export_range(0.5, 6.0, 0.05, "suffix:s") var boarding_retry_cooldown_after_resist: float = 1.0
@export_group("Sail Handling")
@export var sail_furled: bool = false
@export_range(0.0, 1.0, 0.01) var sail_deployed_ratio: float = 1.0
@export_range(0.25, 8.0, 0.05) var sail_furl_rate: float = 0.55
@export_range(0.0, 0.25, 0.01) var furled_sail_drive_ratio: float = 0.0
@export_range(1.0, 2.0, 0.05) var furled_sail_rudder_multiplier: float = 1.0
@export_range(1.0, 2.0, 0.05) var furled_sail_rowing_efficiency_multiplier: float = 1.0
@export_range(0.0, 3.0, 0.1) var furled_sail_rowing_speed_bonus: float = 1.0
@export_range(0.25, 1.0, 0.05) var furled_sail_rowing_stamina_cost_multiplier: float = 0.85
@export_range(0.0, 1.0, 0.05) var furled_sail_fire_damage_multiplier: float = 0.5
@export_group("Boarding Sail AI")
@export var boarding_sail_furl_enabled: bool = true
@export_range(6.0, 40.0, 0.5, "suffix:m") var boarding_sail_furl_distance: float = 30.0
@export_range(10.0, 60.0, 0.5, "suffix:m") var boarding_sail_unfurl_distance: float = 45.0
@export_range(0.0, 5.0, 0.1, "suffix:s") var boarding_sail_unfurl_delay: float = 1.5
@export_range(0.2, 1.0, 0.01) var boarding_furled_drive_ratio: float = 0.82
@export_group("")
@export var formation_role_name: String = "":
	set(value):
		formation_role_name = value
		if not Engine.is_editor_hint() and is_node_ready():
			_apply_formation_role_profile()
@export var limbo_ai_pilot_enabled: bool = false
@export_file("*.tres") var limbo_ai_pilot_tree_path: String = ShipLimboAIPilot.DEFAULT_TREE_PATH
@export_range(0.03, 0.25, 0.01) var limbo_ai_tick_interval: float = 0.07
@export var ship_type: String = "sekibune_melee":
	set(value):
		ship_type = value
		_apply_default_combat_profile_for_ship_type()
		if Engine.is_editor_hint():
			_update_editor_hull()
var has_cannons: bool = true ## JSON에서 로드됨

var target: Node3D = null

# 상태 (State)
var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0


## Legacy export names kept so existing scenes keep their serialized player-fleet crew settings.
@export var minion_respawn_interval: float = 15.0
@export var max_minion_crew: int = 4 # 지원함/legacy 나포함 병사 보충 목표
var minion_respawn_timer: float = 0.0

@export var max_crew: int = 6 # 적선 최대 정원
var enemy_crew_composition: Array[String] = []
var _enemy_crew_spawn_index: int = 0

# === 적 AI 조타 튜닝 ===
@export_range(0.5, 3.0) var ai_rudder_gain: float = 1.2
@export_range(20.0, 160.0) var ai_rudder_response_speed: float = 70.0
@export_range(10.0, 80.0) var ai_max_turn_rate: float = 30.0 # deg/s
@export_range(0.2, 1.0) var ai_turn_authority: float = 0.7
@export_range(4.0, 24.0) var ai_close_turn_soft_radius: float = 12.0
@export_range(0.2, 1.0) var ai_close_turn_scale: float = 0.6
@export_range(0.25, 1.5) var separation_pad_scale: float = 1.0


# === 함대 진형 (Formation) 관련 ===
enum Formation {COLUMN, WING, WEDGE} # WEDGE is kept as a legacy saved-value alias of WING.
static var fleet_formation: Formation = Formation.COLUMN # 공유 진형 설정 (기본: 장사진)
static var support_hold_formation: bool = true # 지원함 자유 교전/진형 유지 토글

var formation_spacing: float = 14.0 # 선박 간 간격 축소 (밀집 대형)

var _wave_timer: float = 0.0 # 물결 소리 타이머
var _last_ai_speed: float = 0.0 # 속도 평활화를 위한 이전 프레임 속도 저장
var _oar_time: float = 0.0
var _derelict_status_check_timer: float = DERELICT_STATUS_CHECK_INTERVAL
var _boarding_sail_unfurl_timer: float = 0.0

# [신규] 스태미나 시스템 (돌격용)
var stamina: float = 100.0
var max_stamina: float = 100.0
var is_sprinting: bool = false
var sprint_multiplier: float = 1.5
var fire_pot_cooldown_timer: float = 0.0
var fire_pot_scene: PackedScene = null

# === 성능 최적화용 캐싱 (성능 저하 방지) ===
static var _cached_minion_list: Array = []
static var _last_minion_cache_frame: int = -1
static var _cached_support_ship_list: Array = []
static var _last_support_ship_cache_frame: int = -1

var _cached_wind_manager: Node = null

static func get_minions_cached(_tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_minion_cache_frame:
		_cached_minion_list = EntityRegistry.get_legacy_captured_ships()
		_last_minion_cache_frame = current_frame
	return _cached_minion_list

static func get_support_ships_cached(_tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_support_ship_cache_frame:
		_cached_support_ship_list = EntityRegistry.get_support_ships()
		_last_support_ship_cache_frame = current_frame
	return _cached_support_ship_list

static func get_ships_cached(_tree: SceneTree) -> Array:
	return AIShipRuntimeHelper.get_ships_cached(_tree)


# 최적화 변수
var cached_lm: Node = null
var separation_force: Vector3 = Vector3.ZERO
var separation_timer: float = 0.0
var logic_timer: float = 0.0 # 타겟 체크 등 일반 로직용
var _limbo_ai_tick_timer: float = 0.0
var _limbo_ai_tick_accum: float = 0.0
var _support_ai_update_phase: int = -1
var _support_ai_accum_delta: float = 0.0
@export_range(0.05, 0.5, 0.01) var ai_logic_update_interval: float = 0.16
@export_range(0.0, 0.15, 0.01) var ai_logic_update_jitter: float = 0.035
var _ai_logic_update_interval_runtime: float = 0.16
@export_range(0.05, 0.5, 0.01) var ai_separation_update_interval: float = 0.09
var _ai_separation_update_interval_runtime: float = 0.09

# 도선 로직 변수 (base_ship.gd에서 상속)
var has_rammed: bool = false # 중복 데미지 방지
var _bonus_xp_granted: bool = false

func get_radius() -> float:
	return 2.5 # 대략적인 선체 반경 (상황에 맞게 조정)


func is_gunner_role() -> bool:
	return int(combat_role) == int(CombatRole.GUNNER)


func is_charger_role() -> bool:
	return not is_gunner_role()


func can_board_targets() -> bool:
	return allow_boarding

func get_target_ship() -> Node3D:
	return target if is_instance_valid(target) else null

func _mark_boarding_impact(target_ship: Node3D, grace_duration: float = 1.25) -> void:
	if not is_instance_valid(target_ship):
		return
	set_meta("boarding_impact_target_id", target_ship.get_instance_id())
	set_meta("boarding_impact_grace_timer", grace_duration)


func apply_boarding_retry_cooldown(target_ship: Node3D, duration: float = -1.0) -> void:
	if not is_instance_valid(target_ship):
		return
	var cooldown := boarding_retry_cooldown_after_resist if duration < 0.0 else duration
	set_meta(BOARDING_RETRY_COOLDOWN_TARGET_ID_META, target_ship.get_instance_id())
	set_meta(BOARDING_RETRY_COOLDOWN_TIMER_META, maxf(0.0, cooldown))
	if has_meta("boarding_impact_target_id") and int(get_meta("boarding_impact_target_id", 0)) == target_ship.get_instance_id():
		remove_meta("boarding_impact_target_id")
		if has_meta("boarding_impact_grace_timer"):
			remove_meta("boarding_impact_grace_timer")
	_clear_boarding_latch()


func _is_boarding_retry_cooling_down(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if not has_meta(BOARDING_RETRY_COOLDOWN_TIMER_META):
		return false
	if float(get_meta(BOARDING_RETRY_COOLDOWN_TIMER_META, 0.0)) <= 0.0:
		return false
	return int(get_meta(BOARDING_RETRY_COOLDOWN_TARGET_ID_META, 0)) == target_ship.get_instance_id()


func _update_boarding_retry_cooldown(delta: float) -> void:
	if not has_meta(BOARDING_RETRY_COOLDOWN_TIMER_META):
		return
	var timer := maxf(0.0, float(get_meta(BOARDING_RETRY_COOLDOWN_TIMER_META, 0.0)) - delta)
	if timer <= 0.0:
		remove_meta(BOARDING_RETRY_COOLDOWN_TIMER_META)
		remove_meta(BOARDING_RETRY_COOLDOWN_TARGET_ID_META)
		return
	set_meta(BOARDING_RETRY_COOLDOWN_TIMER_META, timer)


func _has_recent_boarding_impact(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if not has_meta("boarding_impact_grace_timer"):
		return false
	if float(get_meta("boarding_impact_grace_timer", 0.0)) <= 0.0:
		return false
	return int(get_meta("boarding_impact_target_id", 0)) == target_ship.get_instance_id()


func can_use_fire_pot_attack() -> bool:
	return false


func get_limbo_ai_default_tree_path() -> String:
	var team_tag := get_team_tag()
	if team_tag == "player":
		if PlayerFleetRoleHelper.is_support_ship(self):
			return ShipLimboAIPilot.SUPPORT_TREE_PATH
		if PlayerFleetRoleHelper.is_legacy_captured_ship(self):
			return ShipLimboAIPilot.LEGACY_CAPTURE_TREE_PATH
	elif team_tag == "enemy":
		return ShipLimboAIPilot.ENEMY_GUNNER_TREE_PATH if is_gunner_role() else ShipLimboAIPilot.ENEMY_BOARDER_TREE_PATH
	return ShipLimboAIPilot.DEFAULT_TREE_PATH


func set_preview_target(target_ship: Node3D) -> void:
	target = target_ship


func reset_preview_fire_pot_cooldown() -> void:
	fire_pot_cooldown_timer = 0.0


func set_preview_fire_pot_enabled(enabled: bool) -> void:
	if enabled:
		return
	replace_preview_crew_role("fire_pot", "general")


func get_preferred_engagement_range() -> float:
	return preferred_combat_range


func get_engagement_range_tolerance() -> float:
	return combat_range_tolerance


func get_retreat_engagement_distance() -> float:
	return retreat_distance


func _become_derelict() -> void:
	is_boarding = false
	_clear_ropes()
	target = null
	AIShipLifecycleHelper.become_derelict(self)

func _sink_derelict() -> void:
	await AIShipLifecycleHelper.sink_derelict(self)


func _ignite_derelict_from_contact(source_ship: Node3D = null) -> void:
	AIShipLifecycleHelper.ignite_derelict_from_contact(self, source_ship)


func _check_offscreen_despawn() -> void:
	AIShipLifecycleHelper.check_offscreen_despawn(self)

func _apply_default_combat_profile_for_ship_type() -> void:
	AIShipProfileHelper.apply_default_combat_profile_for_ship_type(self)

func _apply_combat_profile_from_stats(stats: Dictionary) -> void:
	AIShipProfileHelper.apply_combat_profile_from_stats(self, stats)


func _sync_combat_profile_from_role_accessors() -> void:
	AIShipProfileHelper.sync_combat_profile_from_role_accessors(self)


func _load_enemy_crew_composition_from_stats(stats: Dictionary) -> void:
	AIShipLoadoutHelper.load_enemy_crew_composition_from_stats(self, stats)


func _get_next_enemy_soldier_type() -> String:
	return AIShipLoadoutHelper.get_next_enemy_soldier_type(self)


func _configure_spawned_soldier(soldier, soldier_type_name: String) -> void:
	AIShipLoadoutHelper.configure_spawned_soldier(soldier, soldier_type_name)


func _apply_formation_role_profile() -> void:
	AIShipProfileHelper.apply_formation_role_profile(self)

func _update_editor_hull() -> void:
	_ensure_editor_preview_hull(ship_type, hull_scene)
	_cache_hull_references(self) # BaseShip 메서드 호출

func _ready() -> void:
	_apply_default_combat_profile_for_ship_type()
	if Engine.is_editor_hint():
		# 이미 에디터용 Hull이 있다면 중복 생성 방지
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

	# JSON 데이터 로드 및 적용
	_ensure_runtime_scene_refs()
	var stats = load_ship_stats(ship_type)
	if not stats.is_empty():
		ShipBlueprintHelper.apply_ai_ship_stats(self, stats)
		_load_enemy_crew_composition_from_stats(stats)
		_apply_combat_profile_from_stats(stats)
	_apply_formation_role_profile()
		
	# 씬에 직접 배치된 hull이 있으면 그대로 쓰고, 없을 때만 데이터 기반 hull을 생성한다.
	var hull_inst := _ensure_hybrid_runtime_hull(ship_type, hull_scene, stats)
	if not is_instance_valid(hull_inst):
		_update_editor_hull()
	limbo_ai_pilot_tree_path = ShipLimboAIPilot.resolve_tree_path(self, limbo_ai_pilot_tree_path)
		
	super._ready()
	if max_hull_hp <= 0: max_hull_hp = 60.0 # Default fallback
	global_position.y = base_y # Keep base_y assignment from BaseShip valid
	_find_player()
	
	# 대포 없는 AI 함선일 경우 자식 중 Cannon 노드들 제거
	if not has_cannons:
		_remove_all_cannons()
	
	# 초기 팀 표식 설정. 돛 색은 선체/돛대 기본 재질을 유지한다.
	var enemy_flag_kind := FlagSceneLibrary.pick_enemy_kind_for_ship_type(ship_type, formation_role_name)
	for mast in masts:
		if mast.has_method("set_flag_kind"):
			mast.set_flag_kind(enemy_flag_kind)
		elif mast.has_method("set_team_color"):
			mast.set_team_color("enemy")
	add_to_group("ships")
	set_team(team)
	if team == "player":
		if get_player_fleet_role() == PlayerFleetRoleHelper.ROLE_NONE:
			set_player_fleet_role(PlayerFleetRoleHelper.ROLE_CAPTURED_MINION)
		if PlayerFleetRoleHelper.is_support_ship(self):
			add_to_group("support_ship")
			if is_in_group("captured_minion"):
				remove_from_group("captured_minion")
			EntityRegistry.unregister_legacy_captured_ship(self)
			EntityRegistry.register_support_ship(self)
		else:
			add_to_group("captured_minion")
			EntityRegistry.unregister_support_ship(self)
			EntityRegistry.register_legacy_captured_ship(self)
		_apply_minion_visuals()
		_equip_ship_weapons("player", true)
		var upgrade_manager = get_node_or_null("/root/UpgradeManager")
		if is_instance_valid(upgrade_manager):
			upgrade_manager.apply_fleet_upgrades_to_ship(self )
	else:
		if is_in_group("support_ship"):
			remove_from_group("support_ship")
		if is_in_group("captured_minion"):
			remove_from_group("captured_minion")
		EntityRegistry.unregister_support_ship(self)
		EntityRegistry.unregister_legacy_captured_ship(self)
		if has_cannons:
			_equip_ship_weapons("enemy", false)
	
	if get_meta(DEFER_INITIAL_CREW_SETUP_META, false) == true:
		remove_meta(DEFER_INITIAL_CREW_SETUP_META)
		call_deferred("_setup_soldiers_staggered")
	else:
		_setup_soldiers() # 모든 함선 초기 병사 배치 (팀 속성 반영)
		
	_find_player()
	
	cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	_sync_contact_area_layers()
	_set_contact_areas_enabled(true)
	_configure_ai_logic_throttle()


func _ensure_runtime_scene_refs() -> void:
	if soldier_scene == null:
		soldier_scene = _load_packed_scene(DEFAULT_SOLDIER_SCENE_PATH)
	if cannon_scene == null:
		cannon_scene = _load_packed_scene(DEFAULT_CANNON_SCENE_PATH)
	if hull_scene == null:
		hull_scene = _load_packed_scene(DEFAULT_HULL_SCENE_PATH)
	if fire_pot_scene == null:
		fire_pot_scene = _load_packed_scene(DEFAULT_FIRE_POT_SCENE_PATH)


func _load_packed_scene(path: String) -> PackedScene:
	var loaded_resource: Resource = load(path)
	return loaded_resource as PackedScene if loaded_resource is PackedScene else null

func _setup_soldiers() -> void:
	AIShipLoadoutHelper.setup_soldiers(self)


func _setup_soldiers_staggered() -> void:
	await AIShipLoadoutHelper.setup_soldiers_staggered(self)

func _spawn_one_soldier(s_team: String, soldier_type_override: String = "") -> void:
	AIShipLoadoutHelper.spawn_one_soldier(self, s_team, soldier_type_override)


func die() -> void:
	if is_dying: return
	var was_derelict_disposal: bool = is_derelict or get_meta("derelict_burning_down", false) == true or get_meta("derelict_contact_ignition_started", false) == true
	BaseShipStatusHelper.clear_fire_effect(self)
	is_dying = true
	
	# ✅ 배 위의 병사들을 원래 배로 복귀시키고, 복귀 불가 시 생존자로 전환
	_evacuate_soldiers_to_home()
	_evacuate_player_soldiers_as_survivors()
	_spawn_enemy_drifter_xp_pickups()
	
	# 밧줄 및 도선 공격자 정보 제거
	if is_instance_valid(boarding_target) and boarding_target.has_method("get_boarding_attacker_ship") and boarding_target.get_boarding_attacker_ship() == self:
		boarding_target.clear_boarding_attacker_ship()
	_clear_ropes()
	
	# 침몰 시작 시 타겟 그룹에서 제외 (대포가 시체를 쏘지 않게 함)
	if is_in_group("enemy"):
		remove_from_group("enemy")
	if is_in_group("player"):
		remove_from_group("player")
	if is_in_group("captured_minion"):
		remove_from_group("captured_minion")
	EntityRegistry.unregister_legacy_captured_ship(self)
	
	# 격침 통계와 골드는 즉시 처리하고, XP는 침몰 부유물 회수로 지급한다.
	if is_instance_valid(cached_lm):
		if team == "enemy" and cached_lm.has_method("add_ship_sunk") and get_meta("derelict_sink_stat_accounted", false) != true:
			set_meta("derelict_sink_stat_accounted", true)
			cached_lm.add_ship_sunk(1, self)
		if not was_derelict_disposal and cached_lm.has_method("add_score"):
			cached_lm.add_score(25)
			
		if not was_derelict_disposal and not _bonus_xp_granted and cached_lm.has_method("add_bonus_xp"):
			cached_lm.add_bonus_xp(20)
			_bonus_xp_granted = true
	
		# 물리 및 충돌 비활성화 (Area3D 대응)
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		_set_contact_areas_enabled(false)
			
		# 항적 끄기
		_set_wake_state(false)
		
	# 가라앉는 연출 (침몰 애니메이션)
	var sink_tween = create_tween()
	sink_tween.set_parallel(true)
	
	# 무작위 기울기
	var tilt_x = randf_range(-15.0, 15.0)
	var tilt_z = randf_range(-10.0, 10.0)
	sink_tween.tween_property(self , "rotation_degrees:x", tilt_x, 3.0).set_ease(Tween.EASE_OUT)
	sink_tween.tween_property(self , "rotation_degrees:z", tilt_z, 3.0).set_ease(Tween.EASE_OUT)
	
	# 아래로 깊게 가라앉음 + 페이드 아웃
	var sink_duration = 6.0
	sink_tween.tween_property(self , "global_position:y", global_position.y - 15.0, sink_duration).set_ease(Tween.EASE_IN)
	play_sink_bubbles(0.25, -1.25)
	
	# (메쉬 투명도 조절 대신 셰이더 수심 효과로 대체)
	
	leaking_rate = 0.0 # 사망 시 누수 중단
	
	_drop_floating_loot()
	
	sink_tween.set_parallel(false)
	sink_tween.tween_callback(queue_free)


func _drop_floating_loot() -> void:
	AIShipLifecycleHelper.drop_floating_loot(self, true)

func _spawn_enemy_drifter_xp_pickups() -> void:
	AIShipLifecycleHelper.spawn_enemy_drifter_xp_pickups(self)

## 침몰 시 배 위의 아군(player) 병사를 Survivor로 전환
func _evacuate_player_soldiers_as_survivors() -> void:
	AIShipLifecycleHelper.evacuate_player_soldiers_as_survivors(self)

## 침몰 시 배 위의 병사들을 원래 배(home_ship)로 복귀시킴
func _evacuate_soldiers_to_home() -> void:
	AIShipLifecycleHelper.evacuate_soldiers_to_home(self)


## 생존자 구조 및 병사 합류 처리 (나포함용)
func add_survivor(_allow_over_capacity: bool = true) -> bool:
	if is_dying:
		return false
	if not soldier_scene:
		return false
	var soldiers_node = get_soldiers_container()
	if not soldiers_node:
		return false
	
	# 전투불능 병사는 회복 대기 중인 로스터로 취급한다.
	var roster_count = 0
	for child in soldiers_node.get_children():
		if _counts_as_minion_roster_soldier_node(child):
			roster_count += 1
		elif AIShipSoldierStateHelper.is_dead_soldier(child):
			child.queue_free() # 시체 정리

	# 나포함 전용 정원(max_minion_crew) 체크
	if roster_count >= max_minion_crew:
		return BaseShipCrewHelper.train_existing_crew_from_survivor(self)
		
	_spawn_one_soldier("player")
	print("[Crew] 나포함이 생존자를 구조했습니다! (현재: %d/%d)" % [roster_count + 1, max_minion_crew])
	return true

func _get_next_crew_spawn_transform(fallback_x: float, fallback_z: float) -> Transform3D:
	return AIShipLoadoutHelper.get_next_crew_spawn_transform(self, fallback_x, fallback_z)

func _process(delta: float) -> void:
	if is_dying: return
	
	_update_fire_effect()
	_auto_adjust_sail(delta)
	_update_sail_visual()
	_update_oar_visual(delta)
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	_update_rigging_recovery(delta)
	_update_boarding_retry_cooldown(delta)
	_update_boarding_state(delta)
	_update_derelict_status_check(delta)
	_update_enemy_fire_pot_logic(delta)

	if is_derelict:
		# 폐선 상태일 때는 타겟 초기화 (공격 중단)
		target = null

	if team == "player":
		_update_player_fleet_crew_respawn(delta)

	_update_leaking_damage(delta)


func _update_derelict_status_check(delta: float) -> void:
	if is_derelict or is_sinking or is_dying:
		return
	if get_team_tag() != "enemy":
		return
	_derelict_status_check_timer -= delta
	if _derelict_status_check_timer > 0.0:
		return
	_derelict_status_check_timer = DERELICT_STATUS_CHECK_INTERVAL
	check_derelict_status()



func _update_leaking_damage(delta: float) -> void:
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
		return
	_leak_tick_timer += delta
	while _leak_tick_timer >= 1.0:
		_leak_tick_timer -= 1.0
		take_damage(leaking_rate, global_position, "leak")


func _update_enemy_fire_pot_logic(delta: float) -> void:
	if not can_use_fire_pot_attack():
		return
	AIShipLifecycleHelper.update_enemy_fire_pot_logic(self, delta)


func _physics_process(delta: float) -> void:
	var profile_start := PhysicsProfiler.begin()
	var limbo_profile_start := PhysicsProfiler.begin()
	_update_limbo_ai_pilot(delta)
	PhysicsProfiler.end("ai_ship_limbo_ai_pilot", limbo_profile_start)
	_update_boarding_sail_furl(delta)
	var ai_profile_start := PhysicsProfiler.begin()
	AIShipRuntimeHelper.process_physics(self, delta)
	PhysicsProfiler.end("ai_ship_process_total", ai_profile_start)
	PhysicsProfiler.end("ai_ship_physics", profile_start)

func _update_logic_throttled() -> void:
	AIShipRuntimeHelper.update_logic_throttled(self)


func _configure_ai_logic_throttle() -> void:
	AIShipRuntimeHelper.configure_logic_throttle(self)


func get_ai_logic_update_interval() -> float:
	return AIShipRuntimeHelper.get_logic_update_interval_for_ship(self)


func get_ai_separation_update_interval() -> float:
	return AIShipRuntimeHelper.get_separation_update_interval_for_ship(self)

## 주변 함선들로부터 멀어지려는 힘 계산
func _calculate_separation() -> Vector3:
	return AIShipRuntimeHelper.calculate_separation(self)

func _process_boarding(delta: float) -> void:
	var profile_start := PhysicsProfiler.begin()
	AIShipBoardingHelper.process_boarding(self, delta)
	PhysicsProfiler.end("ai_ship_boarding", profile_start)

func _apply_neighbor_ship_guards(prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null) -> Vector3:
	var profile_start := PhysicsProfiler.begin()
	var result := AIShipBoardingHelper.apply_neighbor_ship_guards(self, prev_pos, proposed_pos, excluded_ship)
	PhysicsProfiler.end("ship_neighbor_guards", profile_start)
	return result

func _apply_ship_collision_guard(other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = 0.94, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	return AIShipBoardingHelper.apply_ship_collision_guard(self, other_ship, prev_pos, proposed_pos, safe_ratio, impact_speed_hint, emit_collision_event)


func _find_player() -> void:
	AIShipRuntimeHelper.find_player(self)


func _update_limbo_ai_pilot(delta: float) -> void:
	if not limbo_ai_pilot_enabled:
		_limbo_ai_tick_timer = 0.0
		_limbo_ai_tick_accum = 0.0
		return
	var team_tag := get_team_tag()
	if team_tag != "enemy" and not (
		team_tag == "player"
		and (PlayerFleetRoleHelper.is_support_ship(self) or PlayerFleetRoleHelper.is_legacy_captured_ship(self))
	):
		_limbo_ai_tick_timer = 0.0
		_limbo_ai_tick_accum = 0.0
		return
	_limbo_ai_tick_accum += delta
	_limbo_ai_tick_timer -= delta
	if _limbo_ai_tick_timer > 0.0:
		return
	var tick_delta := _limbo_ai_tick_accum
	_limbo_ai_tick_accum = 0.0
	var load_mult := AIShipRuntimeHelper.get_load_multiplier(self)
	_limbo_ai_tick_timer = maxf(0.03, limbo_ai_tick_interval * load_mult)
	var profile_start := PhysicsProfiler.begin()
	ShipLimboAIPilot.tick(self, tick_delta, limbo_ai_pilot_tree_path)
	PhysicsProfiler.end("ship_limbo_ai", profile_start)

## Legacy capture flow. Capture gameplay is currently disabled/hidden, but the
## role, group, and registry names remain for old tests and saved scene contracts.
func capture_ship() -> void:
	if team == "player": return
	
	# 기존 함대 수 체크 (정예 함선 1척 체제)
	if PlayerFleetRoleHelper.count_legacy_captured_ships(EntityRegistry.get_legacy_captured_ships()) >= 1:
		# ✅ 정원 초과 시 나포 대신 배를 파괴함
		print("[Limitation] 함대 정원 초과! 적함을 파괴합니다.")
		die()
		return
			
	set_team("player")
	set_player_fleet_role(PlayerFleetRoleHelper.ROLE_CAPTURED_MINION)
	set_sail_furled(false)
	
	# ✅ 상태 초기화 및 긴급 수리 (나포 후 즉시 가라앉는 현상 방지)
	is_dying = false
	is_derelict = false
	is_burning = false
	fire_build_up = 0.0
	leaking_rate = 0.0
	hull_hp = max(hull_hp, max_hull_hp * 0.3) # 최소 30% 체력으로 복구
	
	# ✅ 나포 완료 시 도선 상태 및 밧줄 강제 해제 (공격자/방어자 모두)
	_cancel_boarding()
	if is_instance_valid(boarding_attacker):
		boarding_attacker._cancel_boarding()
		boarding_attacker = null
	
	# 철저한 물리적/시각적 리셋 (잠수함화 및 기울기 고정 방지)
	tilt_offset = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	base_y = 0.0 # 수면 높이 기준점 재설정
	global_position.y = 0.0
	
	# 실행 중일 수 있는 모든 트윈 애니메이션(침몰 모션 등) 강제 종료
	var tweens = get_tree().get_processed_tweens()
	for tween in tweens:
		# 이 노드나 관련 속성을 다루는 트윈이라고 확신할 순 없지만
		# Godot 4에서는 bind_node를 통해 엮인 트윈은 자동으로 정리되긴 함
		pass
	# 대신 명시적으로 y 위치를 고정해버림
	
	# (is_boarding, boarding_target, _clear_ropes 등은 _cancel_boarding()에서 이미 처리됨)
	
	# 플레이어의 현재 업그레이드된 최대 속도를 상속받아 평준화 (기본치 3.2 대신)
	var current_limbo_tree_path := limbo_ai_pilot_tree_path.strip_edges()
	if (
		current_limbo_tree_path.is_empty()
		or current_limbo_tree_path == ShipLimboAIPilot.DEFAULT_TREE_PATH
		or current_limbo_tree_path == ShipLimboAIPilot.ENEMY_BOARDER_TREE_PATH
		or current_limbo_tree_path == ShipLimboAIPilot.ENEMY_GUNNER_TREE_PATH
	):
		limbo_ai_pilot_tree_path = ShipLimboAIPilot.resolve_tree_path(self, ShipLimboAIPilot.DEFAULT_TREE_PATH)
	var players = EntityRegistry.get_ships_by_team("player")
	if players.size() > 0 and players[0].get("is_player_controlled"):
		move_speed = players[0].get("max_speed")
	else:
		move_speed = 10.0 # 하드코딩된 예비값
	
	if not is_in_group("captured_minion"):
		add_to_group("captured_minion")
		EntityRegistry.register_legacy_captured_ship(self)

	
	# 자식들(대포, 병사) 팀 변경 및 UI 알림
	_update_children_team_for_capture()
	_refresh_deck_light()
	_apply_minion_visuals()

	if is_instance_valid(cached_lm):
		var capture_score_reward: int = max(0, int(cached_lm.get("boarding_capture_score_reward")))
		var capture_xp_reward: int = max(0, int(cached_lm.get("boarding_capture_xp_reward")))
		var capture_bonus_xp_reward: int = max(0, int(cached_lm.get("boarding_capture_bonus_xp_reward")))
		if capture_score_reward > 0 and cached_lm.has_method("add_score"):
			cached_lm.add_score(capture_score_reward)
		if capture_xp_reward > 0 and cached_lm.has_method("add_xp"):
			cached_lm.add_xp(capture_xp_reward)
		if capture_bonus_xp_reward > 0 and cached_lm.has_method("add_bonus_xp"):
			cached_lm.add_bonus_xp(capture_bonus_xp_reward)
	
	if is_instance_valid(cached_lm) and cached_lm.has_method("show_message"):
		cached_lm.show_message("적군 함선을 나포했습니다!", 3.0)
	
	# 플레이어 업그레이드 스탯 적용 (수리 등)
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_stats_to_minion"):
		upgrade_manager.apply_fleet_stats_to_minion(self )
	
	# 나포 직후 플레이어를 찾아 즉시 따라가기 시작
	target = null
	_find_player()
	
	# 나포함 무장 자동 장착 및 현재 함대 업그레이드 적용
	_equip_ship_weapons("player", true)
	upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager):
		upgrade_manager.apply_fleet_upgrades_to_ship(self )
		
	print("[Capture] 나포 성공! 함대에 합류합니다. (target: %s)" % str(target))

func _store_boarding_contact_anchor(target_ship: Node3D) -> void:
	AIShipBoardingHelper.store_boarding_contact_anchor(self, target_ship)

func _equip_minion_cannons() -> void:
	_equip_ship_weapons("player", true)

func _equip_ship_weapons(fallback_team: String = "", gate_by_fleet_upgrades: bool = false) -> void:
	AIShipLoadoutHelper.equip_ship_weapons(self, fallback_team, gate_by_fleet_upgrades)

func _update_children_team_for_capture() -> void:
	AIShipLoadoutHelper.update_children_team_for_capture(self)

func _remove_all_cannons() -> void:
	AIShipLoadoutHelper.remove_all_cannons(self)

func _recursive_remove_cannons(node: Node) -> void:
	AIShipLoadoutHelper.recursive_remove_cannons(node)

func _apply_minion_visuals() -> void:
	# 돛 색상 변경 (흰색/파란색 조화) - instance uniform 사용
	for mast in masts:
		if mast.has_method("set_sail_color"):
			mast.set_sail_color(Color(0.9, 0.9, 1.0, 1.0)) # 밝은 하늘색/흰색
		if mast.has_method("set_flag_kind"):
			mast.set_flag_kind(FlagSceneLibrary.KIND_PLAYER_SUPPORT)
		elif mast.has_method("set_team_color"):
			mast.set_team_color("player")
			
	# 연기 효과 중지 (폐선 상태에서 났던 것)
	if is_instance_valid(_fire_instance):
		_set_fire_emitting(false)


func _auto_adjust_sail(delta: float) -> void:
	if not is_instance_valid(_cached_wind_manager) or not _cached_wind_manager.has_method("get_wind_direction"):
		return
	if sail_furled and sail_deployed_ratio <= 0.001:
		return
	var wind_dir = _cached_wind_manager.get_wind_direction()

	# 플레이어 배와 같은 기준으로 상대풍을 계산해 돛이 바람을 향해 자연스럽게 따라가게 한다.
	var wind_angle = rad_to_deg(atan2(wind_dir.x, -wind_dir.y))
	var ship_angle_ccw = rad_to_deg(rotation.y)
	var rel_wind_angle = wrapf(wind_angle + ship_angle_ccw, -180.0, 180.0)
	var target_sail_angle = clamp(rel_wind_angle / 2.0, -90.0, 90.0)
	sail_angle = move_toward(sail_angle, target_sail_angle, 60.0 * delta)


func set_sail_furled(furled: bool) -> void:
	var target_furled := bool(furled)
	if sail_furled == target_furled:
		_sync_mast_fold_after_sail_deployment()
		return
	sail_furled = target_furled
	if not sail_furled:
		_sync_mast_fold_with_sail_furl()


func is_sail_furled() -> bool:
	return sail_furled


func get_effective_sail_deployment() -> float:
	var residual_drive := clampf(furled_sail_drive_ratio, 0.0, 1.0)
	if _is_boarding_sail_behavior_enabled():
		residual_drive = clampf(boarding_furled_drive_ratio, 0.0, 1.0)
	var deployed := clampf(sail_deployed_ratio, 0.0, 1.0)
	return clampf(lerpf(residual_drive, 1.0, deployed), 0.0, 1.0)


func _update_boarding_sail_furl(delta: float) -> void:
	if not _is_boarding_sail_behavior_enabled():
		if sail_deployed_ratio < 0.999 or are_masts_folded():
			_update_sail_deployment(delta)
		return
	if is_derelict or is_sinking or is_dying:
		return
	if not is_instance_valid(target):
		set_sail_furled(false)
		_update_sail_deployment(delta)
		return
	var distance_to_target := global_position.distance_to(target.global_position)
	if distance_to_target <= boarding_sail_furl_distance:
		_boarding_sail_unfurl_timer = 0.0
		set_sail_furled(true)
	elif distance_to_target >= maxf(boarding_sail_unfurl_distance, boarding_sail_furl_distance + 1.0):
		_boarding_sail_unfurl_timer += delta
		if _boarding_sail_unfurl_timer >= boarding_sail_unfurl_delay:
			set_sail_furled(false)
	else:
		_boarding_sail_unfurl_timer = 0.0
	_update_sail_deployment(delta)


func _is_boarding_sail_behavior_enabled() -> bool:
	if not boarding_sail_furl_enabled:
		return false
	if get_team_tag() != "enemy":
		return false
	if not allow_boarding or is_gunner_role():
		return false
	var type_lower := ship_type.strip_edges().to_lower()
	return type_lower.contains("sekibune") and not type_lower.contains("cannon") and not type_lower.contains("gunner")


func _update_sail_deployment(delta: float) -> void:
	var target_ratio := _get_target_sail_deployment_ratio()
	sail_deployed_ratio = move_toward(
		clampf(sail_deployed_ratio, 0.0, 1.0),
		target_ratio,
		maxf(sail_furl_rate, 0.01) * delta
	)
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

## 동양식 노(Ro/Yuloh) 8자 젓기 애니메이션
func _update_oar_visual(delta: float) -> void:
	var left_oars := _get_oar_pivots(true)
	var right_oars := _get_oar_pivots(false)
	if left_oars.is_empty() and right_oars.is_empty():
		return
	
	var is_moving = not is_derelict and move_speed > 0.5 and is_instance_valid(target)
	
	if is_moving:
		# 적함은 조금 더 느리고 장중하게 노를 저음 (돌격 시 2배 가속)
		var oar_speed = 3.6 if is_sprinting else 1.8
		_oar_time += delta * oar_speed
		
		# 8자 모션 (Lissajous curve 기반 Sculling)
		for i in range(left_oars.size()):
			_apply_sculling_oar_motion(left_oars[i], _oar_time + float(i) * 0.24, 1.0)
		for i in range(right_oars.size()):
			_apply_sculling_oar_motion(right_oars[i], _oar_time + float(i) * 0.24 + 0.12, -1.0)
	else:
		for pivot in left_oars:
			_relax_oar_pivot(pivot, delta)
		for pivot in right_oars:
			_relax_oar_pivot(pivot, delta)

func _get_oar_pivots(left_side: bool) -> Array:
	var pivots: Array = oar_pivots_left if left_side else oar_pivots_right
	if not pivots.is_empty():
		return pivots
	var fallback: Node3D = oar_pivot_left if left_side else oar_pivot_right
	return [fallback] if is_instance_valid(fallback) else []

func _apply_sculling_oar_motion(pivot: Node3D, phase: float, side_sign: float) -> void:
	if not is_instance_valid(pivot):
		return
	var sweep_angle := sin(phase) * 0.34
	var lift_angle := cos(phase * 2.0) * 0.055 - 0.025
	var feather_angle := sin(phase + PI * 0.35) * 0.16
	pivot.rotation.x = lift_angle
	pivot.rotation.y = feather_angle * side_sign
	pivot.rotation.z = sweep_angle * side_sign

func _relax_oar_pivot(pivot: Node3D, delta: float) -> void:
	if not is_instance_valid(pivot):
		return
	pivot.rotation.x = lerp_angle(pivot.rotation.x, 0.0, delta * 2.0)
	pivot.rotation.y = lerp_angle(pivot.rotation.y, 0.0, delta * 2.0)
	pivot.rotation.z = lerp_angle(pivot.rotation.z, 0.0, delta * 2.0)

## 나포함 AI 로직 (플레이어 호위 및 적 탐지)
func _process_support_ai(delta: float) -> void:
	var profile_start := PhysicsProfiler.begin()
	var tick_delta := _consume_support_ai_delta(delta)
	if tick_delta <= 0.0:
		AIShipSupportHelper.continue_support_motion(self, delta)
		PhysicsProfiler.end("support_ai", profile_start)
		return
	AIShipSupportHelper.process_support_ai(self, tick_delta, delta)
	PhysicsProfiler.end("support_ai", profile_start)


func _consume_support_ai_delta(delta: float) -> float:
	if not _should_throttle_support_ai():
		_support_ai_accum_delta = 0.0
		return delta
	_support_ai_accum_delta = minf(_support_ai_accum_delta + maxf(delta, 0.0), 0.16)
	var interval_frames := _get_support_ai_frame_interval()
	if interval_frames <= 1:
		var immediate_delta := _support_ai_accum_delta
		_support_ai_accum_delta = 0.0
		return immediate_delta
	if _support_ai_update_phase < 0:
		_support_ai_update_phase = abs(hash("%s:%s" % [get_instance_id(), ship_type])) % interval_frames
	var frame := Engine.get_physics_frames()
	if (frame + _support_ai_update_phase) % interval_frames != 0:
		return 0.0
	var tick_delta := _support_ai_accum_delta
	_support_ai_accum_delta = 0.0
	return tick_delta


func _should_throttle_support_ai() -> bool:
	if team != "player":
		return false
	if is_boarding or is_dying or is_sinking or is_derelict:
		return false
	return PlayerFleetRoleHelper.is_support_ship(self) or PlayerFleetRoleHelper.is_legacy_captured_ship(self)


func _get_support_ai_frame_interval() -> int:
	var support_assist_target_id: int = int(get_meta("support_assist_target_id", 0))
	var is_joining_support: bool = get_meta("support_joining", false) == true
	if support_assist_target_id != 0 or is_joining_support:
		return 2
	var load_mult := AIShipRuntimeHelper.get_load_multiplier(self)
	var interval := 2
	if load_mult >= 1.35:
		interval = 3
	if PlayerFleetRoleHelper.is_heavy_support(self) and load_mult >= 1.15:
		interval = max(interval, 3)
	return clampi(interval, 1, 4)


func _update_support_ai_idle_visuals() -> void:
	_update_rudder_visual()
	_apply_bobbing_effect()
	var speed_ratio := clampf(current_speed / maxf(max_speed, 0.01), 0.0, 1.0)
	_set_wake_state(current_speed > 0.4, speed_ratio, 0.0, 0.0)

func _update_wave_sounds(delta: float) -> void:
	AIShipRuntimeHelper.update_wave_sounds(self, delta)

func _update_player_fleet_crew_respawn(delta: float) -> void:
	if deck_is_contested or deck_is_overrun:
		return
	var soldiers_node = get_soldiers_container()
	if not soldiers_node: return
	
	var alive_count = 0
	var roster_count = 0
	for child in soldiers_node.get_children():
		if _counts_as_player_fleet_roster_soldier_node(child):
			roster_count += 1
		if _is_alive_soldier_node(child):
			alive_count += 1

	if alive_count <= 0 and not _can_player_fleet_crew_respawn_without_alive_crew():
		minion_respawn_timer = 0.0
		return

	var respawn_target_count := _get_player_fleet_crew_respawn_target_count()
	if roster_count < respawn_target_count:
		minion_respawn_timer += delta
		if minion_respawn_timer >= minion_respawn_interval:
			minion_respawn_timer = 0.0
			_respawn_player_fleet_crew_soldier()
	else:
		minion_respawn_timer = 0.0


func _get_player_fleet_crew_respawn_target_count() -> int:
	if PlayerFleetRoleHelper.is_support_ship(self):
		return clampi(maxi(int(initial_crew_count), int(max_minion_crew)), 1, maxi(1, int(max_crew)))
	return max_minion_crew


func _can_player_fleet_crew_respawn_without_alive_crew() -> bool:
	return PlayerFleetRoleHelper.is_support_ship(self)


func _respawn_player_fleet_crew_soldier() -> void:
	_spawn_one_soldier("player")
	var log_label := "지원함" if PlayerFleetRoleHelper.is_support_ship(self) else "나포함"
	print("[Crew] %s 병사 보충 완료." % log_label)


func set_player_fleet_crew_target_count(target_count: int) -> void:
	max_minion_crew = clampi(target_count, 1, maxi(1, int(max_crew)))


func reset_player_fleet_crew_respawn_timer() -> void:
	minion_respawn_timer = 0.0


func _update_minion_respawn(delta: float) -> void:
	_update_player_fleet_crew_respawn(delta)


func _get_minion_respawn_target_count() -> int:
	return _get_player_fleet_crew_respawn_target_count()


func _can_minion_respawn_without_alive_crew() -> bool:
	return _can_player_fleet_crew_respawn_without_alive_crew()


func _respawn_minion_soldier() -> void:
	_respawn_player_fleet_crew_soldier()


## 충돌 감지 (Area3D signal 연결 필요)
## 함대 업그레이드 (대포 수량 조절 등)
func apply_fleet_weapon_upgrade(level: int, current_levels: Dictionary = {}) -> void:
	var cannons = []
	for child in get_children():
		if child.name.begins_with("FleetCannon_"):
			cannons.append(child)

	var effective_level := maxi(level, 1)
	var active_cannon_names := SupportFleetCannonRules.get_active_support_cannon_names_for_ship_type(ship_type, effective_level, current_levels)

	var active_count := 0
	for cannon in cannons:
		var should_enable := active_cannon_names.has(str(cannon.name))
		if should_enable:
			cannon.visible = true
			cannon.set_process(true)
			cannon.set_physics_process(true)
			active_count += 1
		else:
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)

	print("[Fleet] 공유 포문 적용: Lv.%d (지원함 대포 %d문 활성화)" % [level, active_count])


func _is_alive_soldier_node(soldier: Node) -> bool:
	return AIShipSoldierStateHelper.is_alive_soldier(soldier)


func _counts_as_player_fleet_roster_soldier_node(soldier: Node) -> bool:
	if not is_instance_valid(soldier):
		return false
	var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
	if soldier_team != "player":
		return false
	return AIShipSoldierStateHelper.is_alive_soldier(soldier) or AIShipSoldierStateHelper.is_incapacitated_soldier(soldier)


func _counts_as_minion_roster_soldier_node(soldier: Node) -> bool:
	return _counts_as_player_fleet_roster_soldier_node(soldier)


## 함선 수리 (초요기 보너스)
func repair_ship(percent: float) -> void:
	var amt = max_hull_hp * percent
	hull_hp = minf(hull_hp + amt, max_hull_hp)
	print("[Fleet] 함선 수리됨: +%d HP" % amt)


func _on_body_entered(body: Node3D) -> void:
	if not can_board_targets():
		return
	# 플레이어와 충돌했는지 확인 (StaticBody/CharacterBody 등)
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		var ship_node := body if body.is_in_group("player") else body.get_parent()
		if is_instance_valid(ship_node) and ship_node is Node3D:
			_mark_boarding_impact(ship_node as Node3D)
		_board_ship(body)

func _on_area_entered(area: Area3D) -> void:
	if not can_board_targets():
		return
	# 피격용 히트박스는 도선 트리거에서 제외
	if area.is_in_group("ship_hitbox"):
		return
	
	# 플레이어 선박의 접근 영역과 접촉했는지 확인
	if area.is_in_group("player"):
		_board_ship(area)
	elif area.is_in_group("ship_proximity"):
		var role_parent = area.get_parent()
		if role_parent and role_parent.is_in_group("player"):
			_board_ship(role_parent)


func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0

func _board_ship(target_ship: Node3D) -> void:
	if not can_board_targets():
		return
	if is_dying or is_boarding: return
	
	# 생존 병사가 없으면 도선 시도 불가
	if get_alive_crew_count() <= 0:
		return
	
	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not (ship_node and ship_node.is_in_group("player")):
			return
			
	# === 아군 체크 (동일 팀이면 도선 무시) ===
	if ship_node.get("team") == team:
		return
	if _is_boarding_retry_cooling_down(ship_node):
		return
	if not ShipCombatModeHelper.can_be_boarded(ship_node, self):
		return
		
	# === 플레이어 팀 체크 (상대 배에 올라타는 것 제한) ===
	# 나포(Capture) 상황이 아닌 일반 전투 중에는 아군 병사가 적선으로 넘어가지 않게 함
	if team == "player":
		return

	# === 무력화(폐선) 상태인 배는 이미 도선이 불필요함 (나포는 player_ship.gd의 boarding scan으로 처리) ===
	if is_derelict:
		return

	# 선미 추격이나 정면 비비기에서 바로 밧줄이 걸리지 않도록,
	# 측면 접현이 성립할 때만 실제 도선 상태로 들어간다.
	var can_side_board: bool = _is_side_boarding_approach(ship_node)
	var can_head_on_board: bool = _can_force_head_on_boarding(ship_node)
	var can_cleanup_board: bool = _can_force_cleanup_boarding(ship_node)
	if not can_side_board and not can_head_on_board and not can_cleanup_board:
		var latch_mode: String = _get_active_boarding_latch_mode(ship_node)
		if latch_mode.is_empty():
			return
	if not _has_recent_boarding_impact(ship_node):
		return

	# 1. 초기 충돌 효과 (최초 1회만)
	if not has_rammed:
		has_rammed = true
		if DEBUG_COMBAT_LOGS:
			print("[Impact] 충돌 발생! 도선 시작.")
		
	# 2. 도선(Boarding) 연결 로직
	if ship_node != boarding_target:
		boarding_target = ship_node

	var active_latch_mode: String = _get_active_boarding_latch_mode(ship_node)
	is_boarding = true
	boarding_target = ship_node
	if can_side_board:
		ShipBoardingMetaHelper.set_contact_mode(self, ShipBoardingMetaHelper.CONTACT_SIDE)
	elif can_head_on_board:
		ShipBoardingMetaHelper.set_contact_mode(self, ShipBoardingMetaHelper.CONTACT_HEAD_ON)
	else:
		var contact_mode: String = ShipBoardingMetaHelper.CONTACT_CLEANUP if active_latch_mode.is_empty() else active_latch_mode
		ShipBoardingMetaHelper.set_contact_mode(self, contact_mode)
	_store_boarding_contact_anchor(ship_node)
	var hold_forward: Vector3 = -global_transform.basis.z
	hold_forward.y = 0.0
	if hold_forward.length_squared() > 0.001:
		ShipBoardingMetaHelper.set_hold_forward(self, hold_forward.normalized())

	# 도선 대상에게 내가 공격자임을 알림 (사격 중지 규칙용)
	if boarding_target.has_method("set_boarding_attacker_ship"):
		boarding_target.set_boarding_attacker_ship(self)

	_clear_ropes()
	boarding_timer = 0.0
	boarding_prep_timer = 0.0
	boarding_contact_timer = 0.0
	boarding_hook_timer = 0.0
	boarding_secondary_rope_timer = 0.0
	ShipBoardingMetaHelper.set_motion_settle_timer(self, 0.0)
	_initial_rope_deployed = false
	_full_rope_deployed = false
	_clear_boarding_latch()

	if DEBUG_COMBAT_LOGS:
		print("[Boarding] 접점 확보! 접현 후 갈고리 투척을 준비합니다.")


func _show_boarding_start_feedback(target_ship: Node) -> void:
	if not is_instance_valid(target_ship) or not target_ship.is_in_group("player"):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var next_allowed: float = float(target_ship.get_meta("boarding_start_message_next_time", 0.0))
	if now < next_allowed:
		return
	target_ship.set_meta("boarding_start_message_next_time", now + 2.25)

	var hud: Node = null
	if target_ship.has_method("_find_hud"):
		var found_hud: Variant = target_ship.call("_find_hud")
		if found_hud is Node:
			hud = found_hud
	if not is_instance_valid(hud) and "_cached_hud" in target_ship:
		var cached_hud: Variant = target_ship.get("_cached_hud")
		if cached_hud is Node:
			hud = cached_hud
	if not is_instance_valid(hud):
		return
	var message := LocaleManager.t("hud.boarding.grapple_attached", "갈고리가 걸렸습니다! 갑판 방어!")
	if hud.has_method("show_message"):
		hud.show_message(message, 1.8)
	elif hud.has_method("show_gust_warning_message"):
		hud.show_gust_warning_message(message, 1.8)


func _count_boarding_contact_defenders(target_ship: Node3D) -> int:
	if not is_instance_valid(target_ship):
		return 0
	var target_team: String = target_ship.get_team_tag() if target_ship.has_method("get_team_tag") else str(target_ship.get("team"))
	if target_team.is_empty():
		return 0
	var contact_local: Vector3 = _get_boarding_contact_point_on_target_local(target_ship)
	var contact_radius: float = _get_boarding_contact_defense_radius(target_ship)
	var contact_radius_sq: float = contact_radius * contact_radius
	var defenders: int = 0
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if not is_instance_valid(soldier):
			continue
		if AIShipSoldierStateHelper.is_dead_soldier(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != target_team:
			continue
		var soldier_local: Vector3 = target_ship.to_local(soldier.global_position)
		var diff_xz := Vector2(soldier_local.x - contact_local.x, soldier_local.z - contact_local.z)
		if diff_xz.length_squared() <= contact_radius_sq:
			defenders += 1
	return defenders


func _has_remote_engaged_boarding_defenders(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	var hostile_boarders: int = int(target_ship.get("deck_hostile_boarder_count")) if target_ship.get("deck_hostile_boarder_count") != null else 0
	if target_ship.get("deck_is_contested") == true or hostile_boarders > 0:
		return true
	var target_team: String = target_ship.get_team_tag() if target_ship.has_method("get_team_tag") else str(target_ship.get("team"))
	if target_team.is_empty():
		return false
	var contact_local: Vector3 = _get_boarding_contact_point_on_target_local(target_ship)
	var remote_radius: float = _get_boarding_contact_defense_radius(target_ship) * 1.15
	var remote_radius_sq: float = remote_radius * remote_radius
	for soldier in EntityRegistry.get_soldiers_by_ship(target_ship):
		if not is_instance_valid(soldier):
			continue
		if AIShipSoldierStateHelper.is_dead_soldier(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != target_team:
			continue
		var current_target: Variant = soldier.get("current_target") if "current_target" in soldier else null
		if not is_instance_valid(current_target):
			continue
		var target_of_soldier_team: String = current_target.get_team_tag() if current_target.has_method("get_team_tag") else str(current_target.get("team"))
		if target_of_soldier_team == target_team:
			continue
		var soldier_local: Vector3 = target_ship.to_local(soldier.global_position)
		var diff_xz := Vector2(soldier_local.x - contact_local.x, soldier_local.z - contact_local.z)
		if diff_xz.length_squared() > remote_radius_sq:
			return true
	return false


func _get_boarding_contact_point_on_target_local(target_ship: Node3D) -> Vector3:
	var half_ext: Vector2 = target_ship.get_deck_half_extents() if target_ship.has_method("get_deck_half_extents") else Vector2(2.0, 3.0)
	var attacker_local: Vector3 = target_ship.to_local(global_position)
	var width_ratio: float = absf(attacker_local.x / maxf(half_ext.x, 0.01))
	var length_ratio: float = absf(attacker_local.z / maxf(half_ext.y, 0.01))
	var contact_span_ratio: float = 0.84 if maxf(half_ext.x, half_ext.y) >= 5.6 else 0.72
	var edge_inset := 0.32
	var contact_local := Vector3.ZERO
	if width_ratio > length_ratio:
		var safe_half_x: float = maxf(0.08, half_ext.x - minf(edge_inset, maxf(0.0, half_ext.x - 0.08)))
		contact_local.x = (1.0 if attacker_local.x >= 0.0 else -1.0) * safe_half_x
		contact_local.z = clampf(attacker_local.z, -half_ext.y * contact_span_ratio, half_ext.y * contact_span_ratio)
	else:
		contact_local.x = clampf(attacker_local.x, -half_ext.x * contact_span_ratio, half_ext.x * contact_span_ratio)
		var safe_half_z: float = maxf(0.08, half_ext.y - minf(edge_inset, maxf(0.0, half_ext.y - 0.08)))
		contact_local.z = (1.0 if attacker_local.z >= 0.0 else -1.0) * safe_half_z
	return contact_local


func _get_boarding_contact_defense_radius(target_ship: Node3D) -> float:
	var half_ext: Vector2 = target_ship.get_deck_half_extents() if target_ship.has_method("get_deck_half_extents") else Vector2(2.0, 3.0)
	return clampf(maxf(half_ext.x, half_ext.y) * 0.28 + 1.0, BOARDING_CONTACT_DEFENSE_RADIUS_MIN, BOARDING_CONTACT_DEFENSE_RADIUS_MAX)


func _can_force_head_on_boarding(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if is_gunner_role():
		return false
	if not target_ship.is_in_group("player"):
		return false
	var enemy_crew: int = int(target_ship.call("get_alive_crew_count")) if target_ship.has_method("get_alive_crew_count") else 0
	if target_ship.has_method("is_boarding_ship") and target_ship.is_boarding_ship():
		return true
	var state: Dictionary = _get_boarding_alignment_state(target_ship)
	if state.is_empty():
		return false
	var my_contact_dot: float = float(state.get("my_contact_dot", -1.0))
	var target_contact_dot: float = float(state.get("target_contact_dot", 1.0))
	var target_contact_abs: float = absf(float(state.get("target_contact_dot", 1.0)))
	var closing_speed: float = float(state.get("closing_speed", 999.0))
	var center_distance: float = global_position.distance_to(target_ship.global_position)
	var collision_distance: float = get_collision_distance_to(target_ship)
	if center_distance > collision_distance + 1.0:
		return false
	if enemy_crew <= 0:
		return true
	var bow_to_side_contact: bool = (
		my_contact_dot >= 0.58
		and target_contact_abs <= 0.72
		and center_distance <= collision_distance + 0.85
		and closing_speed <= boarding_max_relative_speed * 2.6
	)
	if bow_to_side_contact:
		return true
	var head_to_head_contact: bool = (
		my_contact_dot >= 0.70
		and target_contact_dot >= 0.72
		and center_distance <= collision_distance + 0.70
		and closing_speed <= boarding_max_relative_speed * 3.4
	)
	if head_to_head_contact:
		return true
	if enemy_crew == 1 and center_distance <= collision_distance + 0.45:
		return true
	return enemy_crew <= 1 and my_contact_dot >= 0.52 and target_contact_abs <= 0.92 and closing_speed <= boarding_max_relative_speed * 2.4


func _can_start_boarding_latched(target_ship: Node3D, dist_to_target: float, can_side_board: bool, can_head_on_board: bool, can_cleanup_board: bool, delta: float) -> bool:
	if not is_instance_valid(target_ship) or is_gunner_role() or not can_board_targets():
		_clear_boarding_latch()
		return false
	if not target_ship.is_in_group("player"):
		_clear_boarding_latch()
		return false
	if _is_boarding_retry_cooling_down(target_ship):
		_clear_boarding_latch()
		return false
	if dist_to_target > _get_boarding_latch_distance(target_ship):
		_decay_boarding_latch(target_ship, delta)
		return not _get_active_boarding_latch_mode(target_ship).is_empty()

	var latch_mode: String = ""
	if can_side_board:
		latch_mode = ShipBoardingMetaHelper.CONTACT_SIDE
	elif can_head_on_board:
		latch_mode = ShipBoardingMetaHelper.CONTACT_HEAD_ON
	elif can_cleanup_board:
		latch_mode = ShipBoardingMetaHelper.CONTACT_CLEANUP
	elif _is_relaxed_boarding_latch_contact(target_ship, dist_to_target):
		latch_mode = ShipBoardingMetaHelper.CONTACT_SIDE

	if not latch_mode.is_empty():
		ShipBoardingMetaHelper.set_latch(
			self,
			target_ship.get_instance_id(),
			boarding_latch_duration + _get_enemy_boarding_latch_duration_bonus(),
			latch_mode
		)
		return true

	_decay_boarding_latch(target_ship, delta)
	return not _get_active_boarding_latch_mode(target_ship).is_empty()


func _is_relaxed_boarding_latch_contact(target_ship: Node3D, dist_to_target: float) -> bool:
	if dist_to_target > _get_boarding_latch_distance(target_ship):
		return false
	var state: Dictionary = _get_boarding_alignment_state(target_ship)
	if state.is_empty():
		return false
	var my_contact_abs: float = absf(float(state.get("my_contact_dot", 1.0)))
	var target_contact_abs: float = absf(float(state.get("target_contact_dot", 1.0)))
	var parallel_dot: float = float(state.get("parallel_dot", -1.0))
	var closing_speed: float = float(state.get("closing_speed", 999.0))
	var relative_speed_mult: float = boarding_latch_relative_speed_mult + _get_enemy_boarding_latch_speed_bonus()
	return my_contact_abs <= 0.78 \
		and target_contact_abs <= 0.88 \
		and parallel_dot >= -0.28 \
		and closing_speed <= boarding_max_relative_speed * relative_speed_mult


func _get_boarding_latch_distance(target_ship: Node3D) -> float:
	var collision_distance: float = get_collision_distance_to(target_ship) if is_instance_valid(target_ship) else max_boarding_distance
	var distance_bonus: float = _get_enemy_boarding_latch_distance_bonus()
	return maxf(max_boarding_distance + boarding_latch_distance_pad + distance_bonus, collision_distance + 1.15 + distance_bonus)


func _get_active_boarding_latch_mode(target_ship: Node3D) -> String:
	if not is_instance_valid(target_ship):
		return ""
	if not has_meta(ShipBoardingMetaHelper.KEY_LATCH_TIMER) or ShipBoardingMetaHelper.get_latch_timer(self) <= 0.0:
		return ""
	if ShipBoardingMetaHelper.get_latch_target_id(self) != target_ship.get_instance_id():
		return ""
	if global_position.distance_to(target_ship.global_position) > _get_boarding_latch_distance(target_ship) + 0.75:
		return ""
	return ShipBoardingMetaHelper.get_latch_mode(self)


func _decay_boarding_latch(target_ship: Node3D, delta: float) -> void:
	if not has_meta(ShipBoardingMetaHelper.KEY_LATCH_TIMER):
		return
	if not is_instance_valid(target_ship) or ShipBoardingMetaHelper.get_latch_target_id(self) != target_ship.get_instance_id():
		_clear_boarding_latch()
		return
	var remaining: float = ShipBoardingMetaHelper.get_latch_timer(self) - delta
	if remaining <= 0.0 or global_position.distance_to(target_ship.global_position) > _get_boarding_latch_distance(target_ship) + 0.75:
		_clear_boarding_latch()
		return
	ShipBoardingMetaHelper.set_latch_timer(self, remaining)


func _clear_boarding_latch() -> void:
	ShipBoardingMetaHelper.clear_latch_meta(self)


func _get_enemy_boarding_latch_duration_bonus() -> float:
	return ENEMY_BOARDING_LATCH_DURATION_BONUS if get_team_tag() == "enemy" else 0.0


func _get_enemy_boarding_latch_distance_bonus() -> float:
	return ENEMY_BOARDING_LATCH_DISTANCE_BONUS if get_team_tag() == "enemy" else 0.0


func _get_enemy_boarding_latch_speed_bonus() -> float:
	return ENEMY_BOARDING_LATCH_SPEED_BONUS if get_team_tag() == "enemy" else 0.0


func _can_force_cleanup_boarding(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship):
		return false
	if is_gunner_role():
		return false
	if not target_ship.is_in_group("player"):
		return false
	var enemy_crew: int = int(target_ship.call("get_alive_crew_count")) if target_ship.has_method("get_alive_crew_count") else 0
	if enemy_crew > 0:
		return false
	if target_ship.has_method("is_derelict_ship") and target_ship.is_derelict_ship():
		return false
	var center_distance: float = global_position.distance_to(target_ship.global_position)
	var collision_distance: float = get_collision_distance_to(target_ship)
	var state: Dictionary = _get_boarding_alignment_state(target_ship)
	var closing_speed: float = float(state.get("closing_speed", 0.0)) if not state.is_empty() else 0.0
	var crewless_boarding_distance: float = maxf(collision_distance + 4.25, max_boarding_distance + 1.5)
	if center_distance > crewless_boarding_distance:
		return false
	return closing_speed <= boarding_max_relative_speed * 5.0

# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
