extends CharacterBody3D
const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")
const SoldierWeaponHelper = preload("res://scripts/entities/soldiers/soldier_weapon_helper.gd")
const SoldierAiHelper = preload("res://scripts/entities/soldiers/soldier_ai_helper.gd")
const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")
const SoldierVisualHelper = preload("res://scripts/entities/soldiers/soldier_visual_helper.gd")
const SoldierCombatHelper = preload("res://scripts/entities/soldiers/soldier_combat_helper.gd")
const SoldierHealthBarHelper = preload("res://scripts/entities/soldiers/soldier_health_bar_helper.gd")
const SoldierCaptainGuardHelper = preload("res://scripts/entities/soldiers/soldier_captain_guard_helper.gd")
const SoldierDeckZoneHelper = preload("res://scripts/entities/soldiers/soldier_deck_zone_helper.gd")
const SoldierShipSpatialCacheHelper = preload("res://scripts/entities/soldiers/soldier_ship_spatial_cache_helper.gd")
const SoldierLimboAIPilot = preload("res://scripts/ai/limbo/soldier_limbo_ai_pilot.gd")
const SoldierAILimboKeys = preload("res://scripts/ai/limbo/soldier_ai_limbo_keys.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const BOW_SCENE = preload("res://scenes/entities/weapons/weapon_bow.tscn")
const SWORD_SCENE = preload("res://scenes/entities/weapons/weapon_sword.tscn")
const SPEARMAN_MELEE_SCENES := [
	preload("res://scenes/entities/weapons/weapon_spear.tscn"),
	preload("res://scenes/entities/weapons/weapon_trident.tscn"),
]
const SURVIVOR_SCENE = preload("res://scenes/effects/survivor.tscn")

## 병사 AI: NavMesh 기반 이동 및 전투

# State는 "지금 몸이 수행하는 행동/포즈"를 나타낸다.
# boarding_status는 보딩 시스템 안에서의 상황(on_deck/boarding/returning/stranded)을 나타낸다.
# 둘을 함께 바꿔야 할 때는 begin_boarding_jump_pose(), finish_boarding_jump_pose() 같은 공통 메서드를 거친다.
enum State {
	IDLE,
	WANDER,
	MOVE,
	ATTACK,
	DEAD,
	BOARDING_JUMP
}

const REST_RECOVERY_HEALTH_PER_SECOND: float = 1.0
const REST_RECOVERY_DELAY_AFTER_DAMAGE: float = 3.0
const ALLY_HEALTH_BAR_DAMAGE_VISIBLE_DURATION: float = 4.2
const EXTERNAL_KNOCKBACK_GRAVITY: float = 18.0
const EXTERNAL_KNOCKBACK_OVERBOARD_DECAY: float = 5.6
const EXTERNAL_KNOCKBACK_DECK_MARGIN: float = 0.18
const EXTERNAL_KNOCKBACK_SNAP_DURATION: float = 0.07
const EXTERNAL_KNOCKBACK_SNAP_MULTIPLIER: float = 1.22
const META_OVERBOARD_KNOCKBACK_VOICE_PLAYED := "overboard_knockback_voice_played"
const META_OWNED_SHIP_CHANGED_MSEC := "owned_ship_changed_msec"
const SFX_OVERBOARD_KNOCKBACK_DEATH := "ballistic_death"
const OVERBOARD_KNOCKBACK_DEATH_PITCH_MIN: float = 1.12
const OVERBOARD_KNOCKBACK_DEATH_PITCH_MAX: float = 1.32
const OVERBOARD_KNOCKBACK_DEATH_PITCH_BOOST_CHANCE: float = 0.28
const OVERBOARD_KNOCKBACK_DEATH_PITCH_BOOST_MIN: float = 1.04
const OVERBOARD_KNOCKBACK_DEATH_PITCH_BOOST_MAX: float = 1.12
const OVERBOARD_KNOCKBACK_DEATH_PITCH_CLAMP_MIN: float = 1.08
const OVERBOARD_KNOCKBACK_DEATH_PITCH_CLAMP_MAX: float = 1.44
const NODE_HAND_PIVOT := "HandPivot"
const NODE_BODY_COLLISION_SHAPE := "CollisionShape3D"
const NODE_FALLBACK_VISUAL_MESH := "MeshInstance3D"
const DEFAULT_HAND_PIVOT_POSITION := Vector3(0.3, 0.7, -0.15)

# === 기본 속성 ===
@export var max_health: float = 70.0: # 인간화 밸런스 조정 (40 -> 70)
	set(value):
		max_health = value
		current_health = max_health
@export var detection_range: float = 35.0 # 적 탐지 범위 (이 밖의 적은 무시)
@export var crit_chance: float = 0.05 # 크리티컬 확률 (5%)
@export var crit_multiplier: float = 2.0 # 크리티컬 데미지 배율
@export var attack_damage: float = 12.0: # 기본 공격력 (근접/원거리 공용)
	set(value):
		attack_damage = value
		if is_inside_tree():
			_update_weapon_stats()

@export var defense: float = 0.0 # 방어력 (피해 감소)

@export var move_speed: float = 3.0
@export var limbo_ai_pilot_enabled: bool = false
@export_file("*.tres") var limbo_ai_pilot_tree_path: String = SoldierLimboAIPilot.DEFAULT_TREE_PATH
@export var team: String = "player": # "player" or "enemy"
	set(value):
		team = value
		if is_inside_tree():
			_setup_soldier_visual()
			_update_team_color()
			_update_weapon_stats()
@export_enum("general", "spearman", "fire_pot", "repeating_crossbow", "singigeon", "daecheolpo") var crew_role: String = "general"
@export var is_captain: bool = false
@export var is_stationary: bool = false # 제자리 고정 (NavMesh 없는 배용)
@export var weapon_switch_distance: float = 4.0 # 무기 교체 거리 (이내면 검, 밖이면 활)하향 (10 -> 4)
@export var is_melee_only: bool = false ## 근접 무기만 사용 (백병전용)
@export var is_ranged_only: bool = false ## 원거리 무기만 사용 (포격 지원용)
@export_group("Visuals")
@export var soldier_visual_scene: PackedScene
@export var player_visual_scene: PackedScene
@export var enemy_visual_scene: PackedScene
@export var captain_visual_scene: PackedScene
@export_range(-0.2, 0.2, 0.005) var visual_deck_offset: float = -0.045
@export_group("")
# === 내부 상태 ===
var current_health: float = 70.0
var current_state: State = State.IDLE
var current_target: Node3D = null
var current_weapon: Node3D = null
var attack_timer: float = 0.0
var wander_timer: float = 0.0
var wander_target_local: Vector3 = Vector3.ZERO # 배 기준 로컬 목표 지점
var decision_timer: float = 0.0 # 의사결정 스로틀링용
var combat_timer: float = 0.0 # 전투/사격 체크 스로틀링용
var rest_recovery_delay_timer: float = 0.0
var ally_health_bar_visible_timer: float = 0.0
var _is_jumping: bool = false # 점프/도선 중인지 여부
var boarding_status: String = "on_deck"
var external_knockback_allows_overboard: bool = false

# 성능 최적화: UpgradeManager 캐싱
var _cached_upgrade_manager: Node = null

var weapon_sword: Node3D = null
var weapon_bow: Node3D = null

# 소속 배 및 매니저 참조
var _owned_ship: Node3D = null
var owned_ship: Node3D:
	get:
		return _owned_ship
	set(value):
		var previous_ship: Node3D = _owned_ship
		_owned_ship = value
		if is_inside_tree():
			EntityRegistry.move_soldier_ship(self, previous_ship, _owned_ship)
		if previous_ship != _owned_ship:
			set_meta(META_OWNED_SHIP_CHANGED_MSEC, Time.get_ticks_msec())
			notify_ai_event("owned_ship_changed")
			_notify_ship_deck_ai_event(previous_ship, "crew_changed")
			_notify_ship_deck_ai_event(_owned_ship, "crew_changed")
var home_ship: Node3D = null # 최초 소속된 플레이어 배 (나포함 침몰 시 복귀용)
var _cached_level_manager: Node = null
var last_nav_target_pos: Vector3 = Vector3.ZERO # 경로 갱신 최적화용
var _lod_dist_to_player: float = 0.0
var _lod_is_combat_priority: bool = false
var _cached_nearest_enemy: Node3D = null
var _nearest_enemy_cache_timer: float = 0.0
var _nearest_enemy_cache_interval_runtime: float = 0.2
var _nearest_enemy_query_frame: int = -1
var _nearest_enemy_query_result: Node3D = null
var attack_validation_timer: float = 0.0
var attack_validation_interval_runtime: float = 0.12
var _limbo_ai_update_timer: float = 0.0
var _limbo_ai_update_interval_runtime: float = 0.08
var _deck_bounds_check_timer: float = 0.0
var _routine_wander_step_timer: float = 0.0
var _routine_support_step_timer: float = 0.0
var _routine_support_step_accum: float = 0.0
var _ai_event_wake_timer: float = 0.0
var _passive_sleep_timer: float = 0.0
static var _ai_load_cache_frame: int = -1
static var _ai_load_multiplier_cache: float = 1.0
var external_knockback_velocity: Vector3 = Vector3.ZERO
var external_knockback_timer: float = 0.0
var external_knockback_snap_timer: float = 0.0

# === 도선 약탈 및 방화 (Boarding Chaos) 페널티 ===
var is_boarder_on_player_ship: bool = false
var chaos_duration_timer: float = 0.0 # 호환/디버그용: 적 도선병은 이제 시간으로 퇴각하지 않음
var chaos_tick_timer: float = 0.0 # 1초마다 데미지 틱
var chaos_damage_per_tick: float = 3.0 # 적 도선병은 퇴각하지 않으므로 지속 피해는 낮게 유지
var _base_max_health_stat: float = 0.0
var _base_attack_damage_stat: float = 0.0
var _base_defense_stat: float = 0.0

const RANGED_DAMAGE_SOURCES := {
	"bow": true,
	"repeating_crossbow": true,
	"daecheolpo": true,
	"ballista": true,
	"singigeon": true,
	"fire_pot": true,
}
const TARGET_STICKY_DETECTION_MULTIPLIER := 1.18
const TARGET_STICKY_LOCAL_SWITCH_RATIO := 0.58
const BOARDING_STATUS_ON_DECK := "on_deck"
const BOARDING_STATUS_BOARDING := "boarding"
const BOARDING_STATUS_RETURNING := "returning"
const BOARDING_STATUS_STRANDED := "stranded"
const INCAPACITATED_ASSIST_ACQUIRE_RANGE := 4.6
const INCAPACITATED_ASSIST_USE_RANGE := 1.15
const INCAPACITATED_ASSIST_STAND_DISTANCE := 1.28
const INCAPACITATED_ASSIST_STAND_REACHED_RANGE := 0.32
const INCAPACITATED_ASSIST_DECK_MARGIN := 0.45
const INCAPACITATED_ASSIST_CHANNEL_DURATION := 2.0
const INCAPACITATED_ASSIST_PROGRESS_DELTA_CAP := 0.18
const INCAPACITATED_ASSIST_PICKUP_MAX_PROGRESS := 0.72
const INCAPACITATED_ASSIST_PICKUP_FORWARD_OFFSET := 0.06
const INCAPACITATED_ASSIST_PICKUP_SIDE_OFFSET := 0.04
const INCAPACITATED_ASSIST_PICKUP_HEIGHT_OFFSET := 0.18
const INCAPACITATED_ASSIST_TARGET_ID_META := "incapacitated_assist_target_id"
const INCAPACITATED_ASSIST_PROGRESS_META := "incapacitated_assist_progress"
const INCAPACITATED_ASSIST_REVIVER_ID_META := "incapacitated_assist_reviver_id"
const INCAPACITATED_ASSIST_PICKUP_START_POSITION_META := "incapacitated_assist_pickup_start_position"
const INCAPACITATED_ASSIST_PICKUP_START_LOCAL_POSITION_META := "incapacitated_assist_pickup_start_local_position"
const INCAPACITATED_ASSIST_PICKUP_START_ROTATION_META := "incapacitated_assist_pickup_start_rotation"

# === 성능 최적화용 캐싱 (성능 저하 방지) ===
static var _cached_soldiers: Array = []
static var _last_soldier_cache_frame: int = -1
static var _cached_player_ships: Array = []
static var _last_player_cache_frame: int = -1
static var _cached_enemy_ships: Array = []
static var _last_enemy_cache_frame: int = -1

static func get_soldiers_cached(tree: SceneTree) -> Array:
	var f = Engine.get_physics_frames()
	if f != _last_soldier_cache_frame:
		_cached_soldiers = EntityRegistry.get_soldiers()
		_last_soldier_cache_frame = f
	return _cached_soldiers

static func get_ships_cached(tree: SceneTree, team_name: String) -> Array:
	var f = Engine.get_physics_frames()
	if team_name == "player":
		if f != _last_player_cache_frame:
			_cached_player_ships = EntityRegistry.get_ships_by_team("player")
			_last_player_cache_frame = f
		return _cached_player_ships
	else:
		if f != _last_enemy_cache_frame:
			_cached_enemy_ships = EntityRegistry.get_ships_by_team("enemy")
			_last_enemy_cache_frame = f
		return _cached_enemy_ships


# 노드 참조 (이제 NavMesh를 사용하지 않습니다)


func _ready() -> void:
	_apply_soldier_rules_data()
	# 영구 업그레이드 보너스 적용 (아군 전용)
	if team == "player":
		var _meta_manager_init = get_node_or_null("/root/MetaManager")
		if is_instance_valid(_meta_manager_init):
			var hp_mult := 1.0
			if _meta_manager_init.has_method("get_crew_health_multiplier"):
				hp_mult *= float(_meta_manager_init.get_crew_health_multiplier())
			max_health *= hp_mult
			if _meta_manager_init.has_method("get_crew_defense_bonus"):
				defense += float(_meta_manager_init.get_crew_defense_bonus())
		
	current_health = max_health
	_cache_base_combat_stats()
	_setup_soldier_visual()
	
	owned_ship = _resolve_owned_ship_from_parent(get_parent())
		
	# 모든 병사에게 home_ship 기록 (원래 소속 배 추적용)
	home_ship = owned_ship
	set_boarding_status(BOARDING_STATUS_ON_DECK)
	
	_cached_level_manager = LevelManagerRegistry.get_level_manager(get_tree())
			
	# 무기 생성
	var hand := ensure_hand_pivot()
	
	# 근접 무기 로드 (Ranged Only가 아닐 때만)
	if not is_ranged_only:
		if SWORD_SCENE and hand:
			weapon_sword = SWORD_SCENE.instantiate() as Node3D
			weapon_sword.set_meta("weapon_id", "sword")
			hand.add_child(weapon_sword)
			
	# 활 로드 (Melee Only가 아닐 때만)
	if not is_melee_only:
		if BOW_SCENE and hand:
			weapon_bow = BOW_SCENE.instantiate() as Node3D
			weapon_bow.set_meta("weapon_id", "bow")
			hand.add_child(weapon_bow)
		
	# 공격력 수치 및 무기 상태 업데이트
	_update_weapon_stats()
		
	# 시작 무기 설정
	if is_melee_only:
		_set_active_weapon("sword")
	else:
		_set_active_weapon("bow") # General이나 Ranged Only는 활부터 시작
	_apply_role_loadout()
	
	# NavMeshAgent 관련 초기화 제거
	
	# 시작 시 랜덤 배회 시작
	_start_wander()
	_update_team_color()
	_update_role_visual()
	
	# AI 실행 시점 분산 (Staggering)
	decision_timer = randf_range(0.0, 0.2)
	combat_timer = randf_range(0.0, 0.12)
	_nearest_enemy_cache_timer = randf_range(0.0, 0.18)
	attack_validation_timer = randf_range(0.0, 0.12)
	_limbo_ai_update_timer = randf_range(0.0, 0.18)
	_deck_bounds_check_timer = randf_range(0.0, 0.16)
	_routine_wander_step_timer = randf_range(0.0, 0.06)
	_routine_support_step_timer = randf_range(0.0, 0.10)
	SoldierSpeechHelper.reset(self)
	
	# 그룹 수동 등록 (검색 정확도 향상)
	add_to_group("soldiers")
	
	# UpgradeManager 캐싱 및 시그널 연결 (매 프레임 노드 탐색 방지)
	_cached_upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(_cached_upgrade_manager):
		if _cached_upgrade_manager.has_signal("upgrade_applied"):
			_cached_upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

	EntityRegistry.register_soldier(self)
	limbo_ai_pilot_tree_path = SoldierLimboAIPilot.resolve_tree_path(self, limbo_ai_pilot_tree_path)


func _exit_tree() -> void:
	EntityRegistry.unregister_soldier(self)


func get_visual_root_node() -> Node3D:
	var visual_root := get_node_or_null(SoldierVisualHelper.VISUAL_ROOT_NAME) as Node3D
	if visual_root != null:
		visual_root.position.y = visual_deck_offset
	return visual_root if visual_root != null else self


func ensure_visual_root_node() -> Node3D:
	var visual_root := get_node_or_null(SoldierVisualHelper.VISUAL_ROOT_NAME) as Node3D
	if visual_root == null:
		visual_root = Node3D.new()
		visual_root.name = SoldierVisualHelper.VISUAL_ROOT_NAME
		add_child(visual_root)
	visual_root.position.y = visual_deck_offset
	return visual_root


func get_custom_visual_node(visual_root: Node = null) -> Node3D:
	var root := visual_root if is_instance_valid(visual_root) else get_visual_root_node()
	if not is_instance_valid(root):
		return null
	var custom_visual := root.get_node_or_null(SoldierVisualHelper.CUSTOM_VISUAL_NAME)
	return custom_visual as Node3D if custom_visual is Node3D else null


func get_fallback_visual_mesh(visual_root: Node = null) -> MeshInstance3D:
	var root := visual_root if is_instance_valid(visual_root) else get_visual_root_node()
	if is_instance_valid(root) and root != self:
		var root_mesh := root.get_node_or_null(NODE_FALLBACK_VISUAL_MESH)
		if root_mesh is MeshInstance3D:
			return root_mesh as MeshInstance3D
	var mesh := get_node_or_null(NODE_FALLBACK_VISUAL_MESH)
	return mesh as MeshInstance3D if mesh is MeshInstance3D else null


func get_hand_pivot() -> Node3D:
	var pivot := get_node_or_null(NODE_HAND_PIVOT)
	if pivot is Node3D:
		return pivot as Node3D
	var visual_root := get_visual_root_node()
	if is_instance_valid(visual_root) and visual_root != self:
		pivot = visual_root.get_node_or_null(NODE_HAND_PIVOT)
		if pivot is Node3D:
			return pivot as Node3D
	return null


func ensure_hand_pivot() -> Node3D:
	var pivot := get_hand_pivot()
	var pivot_parent := _get_hand_pivot_parent()
	if pivot != null:
		if is_instance_valid(pivot_parent) and pivot.get_parent() != pivot_parent:
			var old_global := pivot.global_transform
			var old_parent := pivot.get_parent()
			if old_parent != null:
				old_parent.remove_child(pivot)
			pivot_parent.add_child(pivot)
			if pivot.is_inside_tree():
				pivot.global_transform = old_global
		return pivot
	pivot = Node3D.new()
	pivot.name = NODE_HAND_PIVOT
	if is_instance_valid(pivot_parent):
		pivot_parent.add_child(pivot)
		pivot.position = _get_default_hand_pivot_local_position(pivot_parent)
	else:
		add_child(pivot)
		pivot.position = DEFAULT_HAND_PIVOT_POSITION
	return pivot


func _get_hand_pivot_parent() -> Node3D:
	var visual_root := ensure_visual_root_node()
	if is_instance_valid(visual_root) and visual_root != self:
		return visual_root
	return self


func _get_default_hand_pivot_local_position(parent_node: Node3D) -> Vector3:
	if parent_node == self:
		return DEFAULT_HAND_PIVOT_POSITION
	return DEFAULT_HAND_PIVOT_POSITION - parent_node.position


func get_body_collision_shape() -> CollisionShape3D:
	var shape := get_node_or_null(NODE_BODY_COLLISION_SHAPE)
	return shape as CollisionShape3D if shape is CollisionShape3D else null


func set_body_collision_disabled(disabled: bool) -> void:
	var shape := get_body_collision_shape()
	if shape != null:
		shape.set_deferred("disabled", disabled)


func _resolve_owned_ship_from_parent(parent: Node) -> Node3D:
	if not is_instance_valid(parent):
		return null

	var candidate_ship := parent.get_parent()
	if candidate_ship is Node3D and NodeContractHelper.get_soldiers_container(candidate_ship) == parent:
		return candidate_ship

	if parent is Node3D and parent.has_method("get_wind_strength"):
		return parent

	return null


func _apply_soldier_rules_data() -> void:
	var base_rules: Dictionary = SoldierRulesData.get_section("base")
	if not base_rules.is_empty():
		max_health = float(base_rules.get("max_health", max_health))
		detection_range = float(base_rules.get("detection_range", detection_range))
		crit_chance = float(base_rules.get("crit_chance", crit_chance))
		crit_multiplier = float(base_rules.get("crit_multiplier", crit_multiplier))
		attack_damage = float(base_rules.get("attack_damage", attack_damage))
		defense = float(base_rules.get("defense", defense))
		move_speed = float(base_rules.get("move_speed", move_speed))

	var combat_ranges: Dictionary = SoldierRulesData.get_section("combat_ranges")
	if not combat_ranges.is_empty():
		weapon_switch_distance = float(combat_ranges.get("weapon_switch_distance", weapon_switch_distance))

func _cache_base_combat_stats() -> void:
	_base_max_health_stat = max_health
	_base_attack_damage_stat = attack_damage
	_base_defense_stat = defense

func set_captain_status(enabled: bool, health_multiplier: float = 1.0, attack_multiplier: float = 1.0, defense_bonus: float = 0.0) -> void:
	if _base_max_health_stat <= 0.0:
		_cache_base_combat_stats()

	var previous_max_health: float = maxf(max_health, 0.01)
	var health_ratio: float = clampf(current_health / previous_max_health, 0.0, 1.0)

	is_captain = enabled
	set_meta("is_captain", enabled)

	if enabled:
		max_health = _base_max_health_stat * maxf(health_multiplier, 1.0)
		attack_damage = _base_attack_damage_stat * maxf(attack_multiplier, 1.0)
		defense = _base_defense_stat + maxf(defense_bonus, 0.0)
		is_melee_only = true
		is_ranged_only = false
	else:
		max_health = _base_max_health_stat
		attack_damage = _base_attack_damage_stat
		defense = _base_defense_stat
		is_melee_only = false

	current_health = minf(max_health, maxf(0.0, max_health * health_ratio))

	if is_inside_tree():
		_setup_soldier_visual()
		_update_weapon_stats()
		if enabled:
			_set_active_weapon("sword")
		else:
			_apply_role_loadout()
		_update_role_visual()

func _setup_soldier_visual() -> void:
	SoldierVisualHelper.setup_visual_scene(self, _get_selected_soldier_visual_scene())

func _get_selected_soldier_visual_scene() -> PackedScene:
	if is_captain and captain_visual_scene != null:
		return captain_visual_scene
	if team == "player" and player_visual_scene != null:
		return player_visual_scene
	if team == "enemy" and enemy_visual_scene != null:
		return enemy_visual_scene
	return soldier_visual_scene

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id in ["crew_numbers", "crew_attack", "crew_defense"]:
		_update_weapon_stats()

## 무기 공격력 수치 동기화
func _update_weapon_stats() -> void:
	var damage_bonus_pct := _get_total_weapon_damage_bonus_pct()

	var melee_damage_bonus_pct := damage_bonus_pct
	var melee_damage_add := 0.0
	if _get_melee_weapon_id() in ["spearman", "spear", "trident"]:
		melee_damage_add = _get_spear_damage_add()
	_sync_weapon_damage_bonus(weapon_sword, melee_damage_bonus_pct, melee_damage_add)
	_sync_weapon_damage_bonus(weapon_bow, damage_bonus_pct)


func _sync_weapon_damage_bonus(weapon: Node, damage_bonus_pct: float, damage_add: float = 0.0) -> void:
	if not is_instance_valid(weapon):
		return
	if weapon.has_method("apply_owner_damage_modifiers"):
		weapon.call("apply_owner_damage_modifiers", damage_bonus_pct, damage_add)
	elif weapon.has_method("apply_owner_damage_bonus_pct"):
		weapon.call("apply_owner_damage_bonus_pct", damage_bonus_pct)
	elif "damage" in weapon:
		weapon.damage = (attack_damage + damage_add) * (1.0 + damage_bonus_pct)


func _get_total_weapon_damage_bonus_pct() -> float:
	if team != "player":
		return 0.0
	var meta_manager = get_node_or_null("/root/MetaManager")
	var damage_bonus_pct: float = 0.0
	if is_instance_valid(meta_manager) and meta_manager.has_method("get_crew_damage_bonus_pct"):
		damage_bonus_pct += float(meta_manager.get_crew_damage_bonus_pct())
	if has_meta("damage_bonus_pct"):
		damage_bonus_pct += float(get_meta("damage_bonus_pct"))
	return maxf(0.0, damage_bonus_pct)


func _get_spear_damage_add() -> float:
	if team != "player":
		return 0.0
	if has_meta("spear_damage_add"):
		return maxf(0.0, float(get_meta("spear_damage_add")))
	return 0.0


func _set_active_weapon(type: String) -> void:
	if type == "sword" and weapon_sword:
		current_weapon = weapon_sword
		if weapon_sword.has_method("set_visual_visible"):
			weapon_sword.set_visual_visible(true)
		if weapon_bow and weapon_bow.has_method("set_visual_visible"):
			weapon_bow.set_visual_visible(false)
	elif type == "bow" and weapon_bow:
		current_weapon = weapon_bow
		if weapon_bow.has_method("set_visual_visible"):
			weapon_bow.set_visual_visible(true)
		if weapon_sword and weapon_sword.has_method("set_visual_visible"):
			weapon_sword.set_visual_visible(false)

func apply_crew_role(new_role: String) -> void:
	crew_role = new_role
	set_meta("crew_role", new_role)
	if is_node_ready():
		_apply_role_loadout()
		_update_role_visual()

func equip_weapon(weapon_scene: PackedScene, weapon_id: String = "custom") -> void:
	if weapon_scene == null:
		return
	var hand := ensure_hand_pivot()
	if hand == null:
		return
	if is_instance_valid(weapon_bow):
		weapon_bow.queue_free()
		weapon_bow = null
	weapon_bow = weapon_scene.instantiate() as Node3D
	if weapon_bow == null:
		return
	weapon_bow.set_meta("weapon_id", weapon_id)
	hand.add_child(weapon_bow)
	_update_weapon_stats()
	_set_active_weapon("bow")

func equip_melee_weapon(weapon_scene: PackedScene, weapon_id: String = "melee") -> void:
	if weapon_scene == null:
		return
	var hand := ensure_hand_pivot()
	if hand == null:
		return
	if is_instance_valid(weapon_sword):
		weapon_sword.queue_free()
		weapon_sword = null
	weapon_sword = weapon_scene.instantiate() as Node3D
	if weapon_sword == null:
		return
	weapon_sword.set_meta("weapon_id", weapon_id)
	hand.add_child(weapon_sword)
	_update_weapon_stats()
	if current_weapon == null or current_weapon == weapon_sword:
		_set_active_weapon("sword")

func _get_ranged_weapon_id() -> String:
	return SoldierWeaponHelper.get_ranged_weapon_id(self)

func _get_melee_weapon_id() -> String:
	return SoldierWeaponHelper.get_melee_weapon_id(self)

func _apply_role_loadout() -> void:
	SoldierWeaponHelper.apply_role_loadout(self)

func _ensure_role_marker() -> MeshInstance3D:
	return SoldierVisualHelper.ensure_role_marker(self)

func _update_role_visual() -> void:
	SoldierVisualHelper.update_role_visual(self)

func set_team(new_team: String) -> void:
	var old_team = team
	team = new_team
	EntityRegistry.update_soldier_team(self, old_team, team)
	_update_team_color()
	if old_team != team:
		notify_ai_event("team_changed")
		_notify_ship_deck_ai_event(owned_ship, "crew_team_changed")

func get_team_tag() -> String:
	return team

func get_current_state_value() -> int:
	return current_state

func is_state_value_dead(state_value: Variant) -> bool:
	return state_value != null and int(state_value) == int(State.DEAD)

func get_crit_chance_value() -> float:
	return crit_chance

func get_crit_multiplier_value() -> float:
	return crit_multiplier

func mark_recent_combat_damage() -> void:
	rest_recovery_delay_timer = REST_RECOVERY_DELAY_AFTER_DAMAGE
	if team == "player":
		ally_health_bar_visible_timer = ALLY_HEALTH_BAR_DAMAGE_VISIBLE_DURATION
	notify_ai_event("damaged")

func get_damage_multiplier_value() -> float:
	return float(get_meta("damage_multiplier", 1.0))

func get_weapon_damage_bonus_pct_value() -> float:
	return _get_total_weapon_damage_bonus_pct()

func get_velocity_value() -> Vector3:
	return velocity

func apply_external_knockback(
	direction: Vector3,
	speed: float,
	duration: float = 0.32,
	allow_overboard: bool = false,
	upward_speed: float = 0.0
) -> void:
	if current_state == State.DEAD or _is_jumping:
		return
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	var horizontal_velocity := direction.normalized() * maxf(0.0, speed)
	external_knockback_velocity = horizontal_velocity * EXTERNAL_KNOCKBACK_SNAP_MULTIPLIER
	external_knockback_allows_overboard = allow_overboard
	if external_knockback_allows_overboard:
		external_knockback_velocity.y = maxf(0.0, upward_speed)
		_play_overboard_knockback_voice_once()
	external_knockback_timer = maxf(external_knockback_timer, maxf(0.05, duration))
	external_knockback_snap_timer = maxf(external_knockback_snap_timer, EXTERNAL_KNOCKBACK_SNAP_DURATION)
	current_target = null
	velocity = external_knockback_velocity
	SoldierVisualHelper.play_knockback_pose(self, direction, speed, allow_overboard)


func _play_overboard_knockback_voice_once() -> void:
	if get_meta(META_OVERBOARD_KNOCKBACK_VOICE_PLAYED, false) == true:
		return
	set_meta(META_OVERBOARD_KNOCKBACK_VOICE_PLAYED, true)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		var voice_pitch := randf_range(OVERBOARD_KNOCKBACK_DEATH_PITCH_MIN, OVERBOARD_KNOCKBACK_DEATH_PITCH_MAX)
		if randf() < OVERBOARD_KNOCKBACK_DEATH_PITCH_BOOST_CHANCE:
			voice_pitch *= randf_range(
				OVERBOARD_KNOCKBACK_DEATH_PITCH_BOOST_MIN,
				OVERBOARD_KNOCKBACK_DEATH_PITCH_BOOST_MAX
			)
		audio_manager.play_sfx(
			SFX_OVERBOARD_KNOCKBACK_DEATH,
			global_position,
			clampf(
				voice_pitch,
				OVERBOARD_KNOCKBACK_DEATH_PITCH_CLAMP_MIN,
				OVERBOARD_KNOCKBACK_DEATH_PITCH_CLAMP_MAX
			),
			1.5
		)


func is_combat_disabled() -> bool:
	return current_state == State.DEAD

func is_dead() -> bool:
	return current_state == State.DEAD

func get_owned_ship_node() -> Node3D:
	return owned_ship if is_instance_valid(owned_ship) else null


func get_home_ship_node() -> Node3D:
	return home_ship if is_instance_valid(home_ship) else null


func get_debug_soldier_state_snapshot() -> Dictionary:
	var limbo_requested_tree_path: String = limbo_ai_pilot_tree_path.strip_edges()
	var limbo_enabled_value: bool = limbo_ai_pilot_enabled
	var limbo_resolved_tree_path: String = ""
	if limbo_enabled_value or not limbo_requested_tree_path.is_empty():
		var limbo_resolve_seed: String = limbo_requested_tree_path if not limbo_requested_tree_path.is_empty() else SoldierLimboAIPilot.DEFAULT_TREE_PATH
		limbo_resolved_tree_path = SoldierLimboAIPilot.resolve_tree_path(self, limbo_resolve_seed)
	var limbo_active_tree_path: String = str(get_meta(SoldierLimboAIPilot.META_TREE_PATH, limbo_resolved_tree_path)).strip_edges()
	var limbo_snapshot := {
		"enabled": limbo_enabled_value,
		"requested_tree_path": limbo_requested_tree_path,
		"resolved_tree_path": limbo_resolved_tree_path,
		"tree_path": limbo_active_tree_path,
		"status": str(get_meta(SoldierLimboAIPilot.META_LAST_STATUS, "")),
		"error": str(get_meta(SoldierLimboAIPilot.META_LAST_ERROR, "")).strip_edges(),
		"mode": str(get_meta(SoldierAILimboKeys.META_MODE, "")).strip_edges(),
		"reason": str(get_meta(SoldierAILimboKeys.META_REASON, "")).strip_edges(),
		"target_distance": float(get_meta(SoldierAILimboKeys.META_TARGET_DISTANCE, -1.0)),
	}
	return {
		"name": name,
		"team": team,
		"role": crew_role,
		"state": _get_debug_state_name(),
		"boarding_status": boarding_status,
		"target_name": current_target.name if is_instance_valid(current_target) else "",
		"limbo": limbo_snapshot,
	}


func _get_debug_state_name() -> String:
	match current_state:
		State.IDLE:
			return "idle"
		State.WANDER:
			return "wander"
		State.MOVE:
			return "move"
		State.ATTACK:
			return "attack"
		State.DEAD:
			return "dead"
		State.BOARDING_JUMP:
			return "boarding_jump"
	return "unknown"


func is_dead_soldier() -> bool:
	return current_state == State.DEAD

func is_incapacitated_soldier() -> bool:
	return current_state == State.DEAD and get_meta("incapacitated", false) == true


func is_player_team_soldier() -> bool:
	return team == "player"


func is_enemy_team_soldier() -> bool:
	return team == "enemy"


func get_crew_role_value() -> String:
	return crew_role


func is_ranged_only_value() -> bool:
	return is_ranged_only


func is_melee_only_value() -> bool:
	return is_melee_only


func is_stationary_value() -> bool:
	return is_stationary


func is_jumping_value() -> bool:
	return _is_jumping


func set_boarding_status(next_status: String) -> void:
	var previous_status := boarding_status
	boarding_status = next_status
	set_meta("boarding_status", boarding_status)
	if previous_status != boarding_status:
		notify_ai_event("boarding_status")
		_notify_ship_deck_ai_event(owned_ship, "boarding_status")


func get_boarding_status_value() -> String:
	return boarding_status


func notify_ai_event(reason: String = "") -> void:
	if current_state == State.DEAD:
		return
	if not reason.is_empty():
		set_meta("last_ai_event", reason)
	_ai_event_wake_timer = maxf(_ai_event_wake_timer, 0.42)
	decision_timer = minf(decision_timer, 0.015)
	combat_timer = minf(combat_timer, 0.02)
	_limbo_ai_update_timer = minf(_limbo_ai_update_timer, 0.02)
	_nearest_enemy_cache_timer = 0.0
	_routine_support_step_timer = 0.0
	_passive_sleep_timer = 0.0


func _notify_ship_deck_ai_event(ship: Node3D, reason: String) -> void:
	if not is_instance_valid(ship):
		return
	for other in EntityRegistry.get_soldiers_by_ship(ship):
		if not is_instance_valid(other) or other == self:
			continue
		if other.has_method("notify_ai_event"):
			other.call("notify_ai_event", reason)


func _update_team_color() -> void:
	SoldierVisualHelper.update_team_color(self)


func _physics_process(delta: float) -> void:
	var physics_profile_start := PhysicsFrameProfiler.begin()
	# 바다에 빠지면 사망 (글로벌 Y < -5)
	if is_inside_tree() and global_position.y < -5.0:
		var was_ballistic_collateral: bool = get_meta("ballistic_collateral_pending", false) == true
		set_meta("last_death_cause", "overboard" if was_ballistic_collateral else "drowned")
		set_meta("last_damage_source", "ballistic_collateral" if was_ballistic_collateral else "drowned")
		# 바다에 빠질 때 작은 물보라 이펙트 재생
		var water_explosion_scene = preload("res://scenes/effects/water_blast.tscn")
		if water_explosion_scene:
			var explosion = ScenePool.acquire(get_tree(), water_explosion_scene)
			if explosion.has_method("configure_as_small"):
				explosion.configure_as_small()
			var splash_pos = global_position
			splash_pos.y = 0.05
			# 아직 씬 트리에 없는 노드의 global_position을 설정하면 에러가 발생하므로 position 사용.
			# 루트에 담길 것이므로 position이 global_position과 동일함.
			explosion.position = splash_pos
			get_tree().root.add_child(explosion)
			if explosion.has_method("pool_activate"):
				explosion.pool_activate()
			
		var audio_manager = get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("water_splash_small", global_position, randf_range(0.9, 1.2))
		set_meta("offboard_splash_played", true)
			
		# [최적화] 사망 시 배의 폐선 여부 체크 이벤트 트리거
		if is_instance_valid(home_ship) and home_ship.has_method("check_derelict_status"):
			home_ship.call_deferred("check_derelict_status")
			
		_die()
		PhysicsFrameProfiler.end("soldier_physics", physics_profile_start)
		return

	if SoldierActionHelper.is_action_ai_locked(self):
		velocity = Vector3.ZERO
		if attack_timer > 0:
			attack_timer -= delta
		_update_ally_health_bar(delta)
		PhysicsFrameProfiler.end("soldier_physics", physics_profile_start)
		return

	_ai_event_wake_timer = maxf(0.0, _ai_event_wake_timer - delta)
	_update_ally_health_bar(delta)
	if _try_passive_ai_sleep(delta):
		PhysicsFrameProfiler.end("soldier_physics", physics_profile_start)
		return

	var speech_profile_start := PhysicsFrameProfiler.begin()
	SoldierSpeechHelper.update(self, delta)
	PhysicsFrameProfiler.end("soldier_speech", speech_profile_start)
	var limbo_runtime_profile_start := PhysicsFrameProfiler.begin()
	_update_limbo_ai_pilot_runtime(delta)
	PhysicsFrameProfiler.end("soldier_limbo_runtime", limbo_runtime_profile_start)

	var knockback_profile_start := PhysicsFrameProfiler.begin()
	if _update_external_knockback(delta):
		PhysicsFrameProfiler.end("soldier_external_knockback", knockback_profile_start)
		if attack_timer > 0:
			attack_timer -= delta
		_update_rest_recovery(delta)
		PhysicsFrameProfiler.end("soldier_physics", physics_profile_start)
		return
	PhysicsFrameProfiler.end("soldier_external_knockback", knockback_profile_start)
		
	# === [FIX] 함선 이탈 및 공중 부양 방지 ===
	if not _is_jumping and current_state != State.DEAD:
		# 넉백(velocity) 감쇄
		velocity.x = lerp(velocity.x, 0.0, 5.0 * delta)
		velocity.z = lerp(velocity.z, 0.0, 5.0 * delta)
		
		# 이동 시 충돌 등으로 Y축이 뜨지 않도록 처리
		if velocity.y > 0.0: velocity.y = 0.0
	
	# 고정형(is_stationary) 병사는 AI 로직 실행하지 않음 — 사격만 함
	if is_stationary:
		if not _is_jumping and current_state != State.DEAD:
			if velocity.length_squared() > 0.0001:
				var slide_profile_start := PhysicsFrameProfiler.begin()
				move_and_slide()
				PhysicsFrameProfiler.end("soldier_post_move_slide", slide_profile_start)
			var bounds_profile_start := PhysicsFrameProfiler.begin()
			_run_deck_bounds_check(delta)
			PhysicsFrameProfiler.end("soldier_deck_bounds_check", bounds_profile_start)
		if attack_timer > 0: attack_timer -= delta
		_check_ranged_combat()
		PhysicsFrameProfiler.end("soldier_physics", physics_profile_start)
		return

	# 의사결정 스로틀링 (0.2초마다 고비용 로직 수행)
	decision_timer -= delta
	var run_heavy_logic = false
	if decision_timer <= 0:
		var decision_profile_start := PhysicsFrameProfiler.begin()
		# ✅ 배의 체력이 낮으면 더 민감하게(빨리) 나포 기회 체크 (0.2s -> 0.1s)
		var ship_hp_ratio = 1.0
		if is_instance_valid(owned_ship) and owned_ship.has_method("get_hull_ratio"):
			ship_hp_ratio = owned_ship.get_hull_ratio()

		# === 성능 최적화: 거리 기반 AI LOD (Level of Detail) ===
		var dist_to_player = 0.0
		var player_ships = get_ships_cached(get_tree(), "player")
		if not player_ships.is_empty():
			dist_to_player = global_position.distance_to(player_ships[0].global_position)

		_lod_dist_to_player = dist_to_player
		_lod_is_combat_priority = _is_lod_combat_priority() or _ai_event_wake_timer > 0.0
		var throttle_time = _get_decision_throttle_time(ship_hp_ratio, dist_to_player, _lod_is_combat_priority)

		decision_timer = throttle_time + randf_range(0.0, 0.05)
		run_heavy_logic = true
		if _lod_is_combat_priority:
			var refresh_profile_start := PhysicsFrameProfiler.begin()
			_refresh_nearest_enemy_cache(false)
			PhysicsFrameProfiler.end("soldier_decision_enemy_cache", refresh_profile_start)
		PhysicsFrameProfiler.end("soldier_decision", decision_profile_start)

	_nearest_enemy_cache_timer -= delta

	combat_timer -= delta
	var run_combat_logic: bool = false
	if combat_timer <= 0:
		var combat_throttle_time = _get_combat_throttle_time(_lod_dist_to_player, _lod_is_combat_priority)
		combat_timer = combat_throttle_time + randf_range(0.0, combat_throttle_time * 0.35)
		run_combat_logic = true
		
	# === 적군 도선병 방화(Chaos) 로직 ===
	if team == "enemy" and current_state != State.DEAD:
		# 플레이어 배에 타고 있는지 확인
		if is_instance_valid(owned_ship) and owned_ship.get("team") == "player":
			var chaos_profile_start := PhysicsFrameProfiler.begin()
			_update_boarding_chaos(delta)
			PhysicsFrameProfiler.end("soldier_boarding_chaos", chaos_profile_start)
	
	var state_before_profile := current_state
	var state_profile_start := PhysicsFrameProfiler.begin()
	match current_state:
		State.IDLE:
			_state_idle(delta, run_heavy_logic)
		State.WANDER:
			_state_wander(delta, run_heavy_logic)
		State.MOVE:
			_state_move(delta, run_heavy_logic)
		State.ATTACK:
			_state_attack(delta)
		State.BOARDING_JUMP:
			_state_boarding_jump()
		State.DEAD:
			pass
	PhysicsFrameProfiler.end(_get_state_profile_label(state_before_profile), state_profile_start)
	
	if not _is_jumping and current_state != State.DEAD:
		if current_state == State.IDLE:
			if velocity.length_squared() > 0.0001:
				var slide_profile_start := PhysicsFrameProfiler.begin()
				move_and_slide()
				PhysicsFrameProfiler.end("soldier_post_move_slide", slide_profile_start)
		elif current_state == State.ATTACK:
			if velocity.length_squared() > 0.0001:
				var slide_profile_start := PhysicsFrameProfiler.begin()
				move_and_slide()
				PhysicsFrameProfiler.end("soldier_post_move_slide", slide_profile_start)
		var bounds_profile_start := PhysicsFrameProfiler.begin()
		_run_deck_bounds_check(delta)
		PhysicsFrameProfiler.end("soldier_deck_bounds_check", bounds_profile_start)
			
	# 탈출(Evacuation) 체크: 소속된 나포함이 가라앉고 있으면 홈으로 복귀
	if run_heavy_logic and team == "player" and is_instance_valid(owned_ship) and owned_ship.get("is_dying") == true:
		_try_evacuate_to_home()
	
	# 공격 쿨다운 (캐싱된 업그레이드 수치 사용)
	if attack_timer > 0:
		attack_timer -= delta

	# 원거리 사격 및 무기 스위칭 체크 (전투 스케줄)
	if current_state != State.DEAD and current_state != State.BOARDING_JUMP and run_combat_logic:
		var combat_profile_start := PhysicsFrameProfiler.begin()
		var slot_profile_start := PhysicsFrameProfiler.begin()
		var needs_ranged_slot_check: bool = not is_melee_only and crew_role != "spearman" and is_instance_valid(weapon_bow)
		var ranged_slot_allowed: bool = true
		if needs_ranged_slot_check:
			ranged_slot_allowed = SoldierCombatHelper._can_use_ship_ranged_attack_slot(self)
		PhysicsFrameProfiler.end("soldier_combat_slot_check", slot_profile_start)
		var combat_find_profile_start := PhysicsFrameProfiler.begin()
		var should_run_full_enemy_scan: bool = ranged_slot_allowed or current_state == State.ATTACK or is_instance_valid(current_target)
		var nearest = find_nearest_enemy() if should_run_full_enemy_scan else find_nearest_hostile_on_owned_ship()
		PhysicsFrameProfiler.end("soldier_combat_find_enemy", combat_find_profile_start)
		var combat_weapon_profile_start := PhysicsFrameProfiler.begin()
		SoldierWeaponHelper.update_combat_weapon_choice(self, nearest)
		PhysicsFrameProfiler.end("soldier_combat_weapon_choice", combat_weapon_profile_start)

		if current_state != State.ATTACK:
			var ranged_profile_start := PhysicsFrameProfiler.begin()
			_check_ranged_combat(nearest, ranged_slot_allowed)
			PhysicsFrameProfiler.end("soldier_combat_ranged_check", ranged_profile_start)
			var capture_profile_start := PhysicsFrameProfiler.begin()
			_check_ship_capture_opportunity()
			PhysicsFrameProfiler.end("soldier_combat_capture_check", capture_profile_start)
		PhysicsFrameProfiler.end("soldier_combat", combat_profile_start)

	_update_rest_recovery(delta)
	PhysicsFrameProfiler.end("soldier_physics", physics_profile_start)


func _update_rest_recovery(delta: float) -> void:
	if team != "player" or current_state == State.DEAD:
		return
	if rest_recovery_delay_timer > 0.0:
		rest_recovery_delay_timer = maxf(0.0, rest_recovery_delay_timer - delta)
	if not _can_rest_recover():
		return
	current_health = minf(current_health + REST_RECOVERY_HEALTH_PER_SECOND * delta, max_health)


func _update_ally_health_bar(delta: float) -> void:
	if ally_health_bar_visible_timer > 0.0:
		ally_health_bar_visible_timer = maxf(0.0, ally_health_bar_visible_timer - delta)
	SoldierHealthBarHelper.update(self, ally_health_bar_visible_timer)
	SoldierCaptainGuardHelper.update_warning_ring(self, delta)


func _can_rest_recover() -> bool:
	if current_health >= max_health:
		return false
	if rest_recovery_delay_timer > 0.0:
		return false
	if _is_jumping:
		return false
	if current_state == State.ATTACK or current_state == State.BOARDING_JUMP:
		return false
	if is_instance_valid(current_target):
		return false
	return true


func _update_external_knockback(delta: float) -> bool:
	if external_knockback_timer <= 0.0:
		return false
	if current_state == State.DEAD or _is_jumping:
		external_knockback_timer = 0.0
		external_knockback_velocity = Vector3.ZERO
		external_knockback_snap_timer = 0.0
		external_knockback_allows_overboard = false
		return false
	external_knockback_timer = maxf(0.0, external_knockback_timer - delta)
	var is_snap_phase := external_knockback_snap_timer > 0.0
	external_knockback_snap_timer = maxf(0.0, external_knockback_snap_timer - delta)
	if external_knockback_allows_overboard:
		external_knockback_velocity.y -= EXTERNAL_KNOCKBACK_GRAVITY * delta
	velocity = external_knockback_velocity
	move_and_slide()
	if not external_knockback_allows_overboard:
		_keep_within_owned_ship_bounds()
	if is_snap_phase:
		return true
	var decay_rate := EXTERNAL_KNOCKBACK_OVERBOARD_DECAY if external_knockback_allows_overboard else 7.5
	var decay_t := clampf(delta * decay_rate, 0.0, 1.0)
	if external_knockback_allows_overboard:
		external_knockback_velocity.x = lerpf(external_knockback_velocity.x, 0.0, decay_t)
		external_knockback_velocity.z = lerpf(external_knockback_velocity.z, 0.0, decay_t)
	else:
		external_knockback_velocity = external_knockback_velocity.lerp(Vector3.ZERO, decay_t)
	if external_knockback_timer <= 0.0 or external_knockback_velocity.length_squared() <= 0.01:
		if external_knockback_allows_overboard and _is_outside_owned_ship_deck(EXTERNAL_KNOCKBACK_DECK_MARGIN):
			external_knockback_timer = 0.18
			external_knockback_velocity.x = lerpf(external_knockback_velocity.x, 0.0, 0.3)
			external_knockback_velocity.z = lerpf(external_knockback_velocity.z, 0.0, 0.3)
			external_knockback_velocity.y = minf(external_knockback_velocity.y, -7.0)
			return true
		external_knockback_timer = 0.0
		external_knockback_velocity = Vector3.ZERO
		external_knockback_snap_timer = 0.0
		external_knockback_allows_overboard = false
		velocity = Vector3.ZERO
		_change_state(State.IDLE)
	return true


func _try_passive_ai_sleep(delta: float) -> bool:
	if not _should_use_passive_ai_sleep():
		_passive_sleep_timer = 0.0
		return false
	_passive_sleep_timer -= delta
	if _passive_sleep_timer <= 0.0:
		_passive_sleep_timer = _get_passive_ai_sleep_interval()
		return false
	_tick_passive_ai_sleep_timers(delta)
	velocity = Vector3.ZERO
	return true


func _tick_passive_ai_sleep_timers(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer = maxf(0.0, attack_timer - delta)
	if attack_validation_timer > 0.0:
		attack_validation_timer = maxf(0.0, attack_validation_timer - delta)
	if wander_timer > 0.0:
		wander_timer = maxf(0.0, wander_timer - delta)
	decision_timer -= delta
	combat_timer -= delta
	_limbo_ai_update_timer -= delta
	_nearest_enemy_cache_timer -= delta
	_routine_wander_step_timer -= delta
	_routine_support_step_timer -= delta
	_update_rest_recovery(delta)


func _should_use_passive_ai_sleep() -> bool:
	if _ai_event_wake_timer > 0.0:
		return false
	if current_state != State.IDLE and current_state != State.WANDER:
		return false
	if is_captain or is_stationary or _is_jumping:
		return false
	if boarding_status != BOARDING_STATUS_ON_DECK:
		return false
	if has_named_action():
		return false
	if is_instance_valid(current_target):
		return false
	if not is_instance_valid(owned_ship):
		return false
	if external_knockback_timer > 0.0 or external_knockback_snap_timer > 0.0:
		return false
	if velocity.length_squared() > 0.0009:
		return false
	if float(get_meta("speech_visible_timer", 0.0)) > 0.0:
		return false
	return not _owned_ship_needs_active_deck_ai(owned_ship)


func _owned_ship_needs_active_deck_ai(ship: Node3D) -> bool:
	if not is_instance_valid(ship):
		return true
	if ship.has_method("is_sinking_or_dying") and ship.call("is_sinking_or_dying") == true:
		return true
	if ship.get("is_dying") == true or ship.get("is_sinking") == true:
		return true
	if ship.get("is_burning") == true:
		return true
	if ship.get("deck_is_contested") == true or ship.get("deck_is_overrun") == true:
		return true
	var hostile_count: int = int(ship.get("deck_hostile_boarder_count")) if ship.get("deck_hostile_boarder_count") != null else 0
	if hostile_count > 0:
		return true
	if ship.get("is_boarding") == true:
		return true
	var boarding_target: Variant = ship.get("boarding_target")
	return is_instance_valid(boarding_target)


func _get_passive_ai_sleep_interval() -> float:
	var load_mult := _get_ai_load_multiplier()
	var interval := 0.22
	if _is_passive_ally_ship_crew():
		interval = 0.46
		if _lod_dist_to_player > 24.0:
			interval = 0.68
	elif team == "enemy":
		interval = 0.34
		if _lod_dist_to_player > 40.0:
			interval = 0.56
	else:
		interval = 0.28
		if _lod_dist_to_player > 40.0:
			interval = 0.48
	if EntityRegistry.count_soldiers() > 60:
		interval *= 1.35
	return clampf(interval * minf(load_mult, 1.85) + randf_range(0.0, interval * 0.22), 0.18, 1.15)


func _is_outside_owned_ship_deck(margin: float = 0.0) -> bool:
	if not is_instance_valid(owned_ship):
		return false
	var local_pos: Vector3 = owned_ship.to_local(global_position)
	if SoldierDeckZoneHelper.is_roof(self) and owned_ship.has_method("is_roof_local_position_in_bounds"):
		return owned_ship.call("is_roof_local_position_in_bounds", local_pos) == false
	var half_ext := _get_ship_deck_half_extents(owned_ship)
	var half_width := half_ext.x
	if owned_ship.has_method("get_deck_half_width_at_z"):
		half_width = maxf(0.08, float(owned_ship.call("get_deck_half_width_at_z", clampf(local_pos.z, -half_ext.y, half_ext.y))))
	var deck_height: float = owned_ship.get("deck_height") if "deck_height" in owned_ship else 0.4
	return absf(local_pos.x) > half_width + margin \
		or absf(local_pos.z) > half_ext.y + margin \
		or local_pos.y < deck_height - 0.9


## IDLE 상태: 잠시 대기하다가 다시 배회
func _state_idle(delta: float, run_heavy_logic: bool) -> void:
	SoldierAiHelper.state_idle(self, delta, run_heavy_logic)


## WANDER 상태: 배 위를 랜덤하게 돌아다님 (움직이는 배 대응)
func _state_wander(_delta: float, run_heavy_logic: bool) -> void:
	SoldierAiHelper.state_wander(self, _delta, run_heavy_logic)


## 배회 시작: 새로운 로컬 목표점 설정
func _start_wander() -> void:
	SoldierAiHelper.start_wander(self)


## MOVE 상태 (적 추적)
func _state_move(_delta: float, _run_heavy_logic: bool) -> void:
	SoldierAiHelper.state_move(self, _delta)


## BOARDING_JUMP 상태: 보딩/복귀 점프 중 임시 포즈. 위치 이동은 보딩 tween이 담당한다.
func _state_boarding_jump() -> void:
	velocity = Vector3.ZERO


## ATTACK 상태
func _state_attack(_delta: float) -> void:
	SoldierAiHelper.state_attack(self, _delta)


## 함선 또는 밧줄에 대한 특수 공격 (절단/나포)
func _perform_special_attack(target: Node3D) -> void:
	SoldierCombatHelper.perform_special_attack(self, target)

## 공격 실행
func _perform_attack() -> void:
	SoldierCombatHelper.perform_attack(self)


## 하얀색으로 깜빡임


## 가장 가까운 적 찾기 (탐지 범위 및 동일 함선 우선순위 적용)
func find_nearest_enemy() -> Node3D:
	var query_frame := Engine.get_physics_frames()
	if _nearest_enemy_query_frame == query_frame:
		return _nearest_enemy_query_result
	var sticky_target: Node3D = _get_sticky_current_enemy()
	if is_instance_valid(owned_ship) and is_instance_valid(sticky_target) and _get_target_owned_ship_node(sticky_target) == owned_ship:
		_cached_nearest_enemy = sticky_target
		return _store_nearest_enemy_query_result(sticky_target)
	if is_instance_valid(owned_ship):
		var owned_team: String = owned_ship.get_team_tag() if owned_ship.has_method("get_team_tag") else str(owned_ship.get("team"))
		if owned_team == team:
			var local_hostile := find_nearest_hostile_on_owned_ship()
			if is_instance_valid(sticky_target) and _get_target_owned_ship_node(sticky_target) == owned_ship:
				if is_instance_valid(local_hostile) and local_hostile != sticky_target:
					var sticky_dist_sq: float = _get_planar_distance_sq_to(sticky_target)
					var local_dist_sq: float = _get_planar_distance_sq_to(local_hostile)
					if local_dist_sq < sticky_dist_sq * TARGET_STICKY_LOCAL_SWITCH_RATIO:
						_cached_nearest_enemy = local_hostile
						return _store_nearest_enemy_query_result(local_hostile)
				_cached_nearest_enemy = sticky_target
				return _store_nearest_enemy_query_result(sticky_target)
			if is_instance_valid(local_hostile):
				_cached_nearest_enemy = local_hostile
				return _store_nearest_enemy_query_result(local_hostile)
			var fallback_hostile := _find_nearest_owned_ship_hostile_fallback()
			if is_instance_valid(fallback_hostile):
				_cached_nearest_enemy = fallback_hostile
				return _store_nearest_enemy_query_result(fallback_hostile)
	var limbo_target: Node3D = _get_recent_limbo_target()
	if _is_valid_enemy_target(limbo_target):
		_cached_nearest_enemy = limbo_target
		return _store_nearest_enemy_query_result(limbo_target)
	if is_instance_valid(sticky_target):
		_cached_nearest_enemy = sticky_target
		return _store_nearest_enemy_query_result(sticky_target)
	if _nearest_enemy_cache_timer > 0.0 and is_instance_valid(_cached_nearest_enemy):
		return _store_nearest_enemy_query_result(_cached_nearest_enemy)
	return _store_nearest_enemy_query_result(_refresh_nearest_enemy_cache(true))


func _store_nearest_enemy_query_result(result: Node3D) -> Node3D:
	_nearest_enemy_query_frame = Engine.get_physics_frames()
	_nearest_enemy_query_result = result if is_instance_valid(result) else null
	return _nearest_enemy_query_result


func _get_sticky_current_enemy() -> Node3D:
	if not is_instance_valid(current_target):
		current_target = null
		return null
	var target: Node3D = current_target
	if not _is_valid_enemy_target(target):
		return null
	var max_sticky_distance: float = detection_range * TARGET_STICKY_DETECTION_MULTIPLIER
	if _get_planar_distance_sq_to(target) > max_sticky_distance * max_sticky_distance:
		return null
	return target


func _is_valid_enemy_target(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if SoldierStateHelper.is_dead_soldier(target):
		return false
	var target_ship: Node3D = _get_target_owned_ship_node(target)
	if NodeContractHelper.is_sinking_or_dying(target_ship):
		return false
	var target_team: String = target.get_team_tag() if target.has_method("get_team_tag") else str(target.get("team"))
	return target_team != team


func _get_target_owned_ship_node(target: Node) -> Node3D:
	if not is_instance_valid(target):
		return null
	if target.has_method("get_owned_ship_node"):
		var owned_node: Variant = target.call("get_owned_ship_node")
		return owned_node if is_instance_valid(owned_node) and owned_node is Node3D else null
	var owned_value: Variant = target.get("owned_ship")
	return owned_value if is_instance_valid(owned_value) and owned_value is Node3D else null


func _get_planar_distance_sq_to(target: Node3D) -> float:
	if not is_instance_valid(target):
		return INF
	var dx: float = global_position.x - target.global_position.x
	var dz: float = global_position.z - target.global_position.z
	return dx * dx + dz * dz

func find_nearest_hostile_on_owned_ship() -> Node3D:
	return SoldierShipHelper.find_nearest_hostile_on_owned_ship(self)


func _find_nearest_owned_ship_hostile_fallback() -> Node3D:
	if not is_instance_valid(owned_ship):
		return null
	if NodeContractHelper.is_sinking_or_dying(owned_ship):
		return null
	var candidates: Array = EntityRegistry.get_soldiers_by_ship(owned_ship)
	if candidates.is_empty() and owned_ship.has_method("get_soldiers_container"):
		var soldiers_node: Node = owned_ship.call("get_soldiers_container")
		if is_instance_valid(soldiers_node):
			candidates = soldiers_node.get_children()
	var nearest: Node3D = null
	var nearest_distance_sq: float = INF
	var detection_range_sq: float = detection_range * detection_range
	for other in candidates:
		if other == self or not is_instance_valid(other):
			continue
		if SoldierStateHelper.is_dead_soldier(other):
			continue
		var other_ship: Node3D = _get_target_owned_ship_node(other)
		if NodeContractHelper.is_sinking_or_dying(other_ship):
			continue
		if other.has_method("get_team_tag"):
			if other.call("get_team_tag") == team:
				continue
		elif str(other.get("team")) == team:
			continue
		var other_node := other as Node3D
		if not is_instance_valid(other_node):
			continue
		var dx: float = global_position.x - other_node.global_position.x
		var dz: float = global_position.z - other_node.global_position.z
		var dist_sq: float = dx * dx + dz * dz
		if dist_sq > detection_range_sq:
			continue
		if dist_sq < nearest_distance_sq:
			nearest_distance_sq = dist_sq
			nearest = other_node
	return nearest

## 전이 로직은 통제됨 (개별 나포 기회 체크 삭제)
func _check_ship_capture_opportunity() -> void:
	return

## 홈으로 긴급 복귀 (배가 가라앉을 때)
func _try_evacuate_to_home() -> void:
	SoldierBoardingHelper.try_evacuate_to_home(self)

func _jump_to_ship(target_ship: Node3D, is_capture_attempt: bool = false) -> void:
	SoldierBoardingHelper.jump_to_ship(self, target_ship, is_capture_attempt)

func _teleport_to_ship(_target_ship: Node3D) -> void:
	SoldierBoardingHelper.teleport_to_ship(self, _target_ship)

func _keep_within_owned_ship_bounds() -> void:
	SoldierShipHelper.keep_within_owned_ship_bounds(self)


func _run_deck_bounds_check(delta: float, force: bool = false) -> void:
	if not force and not _should_run_deck_bounds_check(delta):
		return
	if not force and _is_safely_inside_deck_bounds():
		return
	var profile_start := PhysicsFrameProfiler.begin()
	_keep_within_owned_ship_bounds()
	PhysicsFrameProfiler.end("soldier_bounds_check", profile_start)


func _should_run_deck_bounds_check(delta: float) -> bool:
	if current_state == State.DEAD:
		return false
	if not is_instance_valid(owned_ship):
		return false
	if external_knockback_timer > 0.0:
		return true
	if current_state == State.BOARDING_JUMP:
		return true
	var interval := _get_deck_bounds_check_interval()
	_deck_bounds_check_timer -= delta
	if _deck_bounds_check_timer > 0.0:
		return false
	_deck_bounds_check_timer = interval + randf_range(0.0, interval * 0.15)
	return true


func _get_deck_bounds_check_interval() -> float:
	var load_mult := _get_ai_load_multiplier()
	if current_state == State.WANDER:
		return 0.85 * minf(load_mult, 1.8)
	if current_state == State.MOVE:
		if not _lod_is_combat_priority:
			return 0.20 * minf(load_mult, 1.8)
		return 0.12 * minf(load_mult, 1.6)
	if is_stationary:
		return 0.45 * minf(load_mult, 1.7)
	if current_state == State.ATTACK:
		return 0.30 * minf(load_mult, 1.55)
	if _is_passive_ally_ship_crew():
		return 0.45 * minf(load_mult, 1.7)
	return 0.34 * minf(load_mult, 1.5)


func _is_safely_inside_deck_bounds() -> bool:
	if not is_instance_valid(owned_ship):
		return false
	var local_pos: Vector3 = owned_ship.to_local(global_position)
	if SoldierDeckZoneHelper.is_roof(self) and owned_ship.has_method("is_roof_local_position_in_bounds"):
		return owned_ship.call("is_roof_local_position_in_bounds", local_pos) == true
	var half_ext := _get_ship_deck_half_extents(owned_ship)
	if half_ext.x <= 0.01 or half_ext.y <= 0.01:
		return false
	var deck_height: float = owned_ship.get("deck_height") if "deck_height" in owned_ship else 0.4
	if absf(local_pos.y - deck_height) > 0.22:
		return false
	var edge_inset := SoldierShipHelper.DECK_BOUNDS_EDGE_INSET
	var safe_half_z := maxf(0.08, half_ext.y - minf(edge_inset, maxf(0.0, half_ext.y - 0.08)))
	if absf(local_pos.z) > safe_half_z:
		return false
	var half_width := SoldierShipHelper.get_ship_deck_half_width_at_z(owned_ship, local_pos.z, half_ext.x)
	var safe_half_width := maxf(0.08, half_width - minf(edge_inset, maxf(0.0, half_width - 0.08)))
	return absf(local_pos.x) <= safe_half_width


func _get_state_profile_label(state_value: int) -> String:
	match state_value:
		State.IDLE:
			return "soldier_state_idle"
		State.WANDER:
			return "soldier_state_wander"
		State.MOVE:
			return "soldier_state_move"
		State.ATTACK:
			return "soldier_state_attack"
		State.BOARDING_JUMP:
			return "soldier_state_boarding_jump"
		State.DEAD:
			return "soldier_state_dead"
	return "soldier_state_other"


func _get_ship_deck_half_extents(ship: Node3D) -> Vector2:
	return SoldierShipHelper.get_ship_deck_half_extents(self, ship)

## 데미지 받기
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	SoldierLifecycleHelper.take_damage(self, amount, hit_position, damage_source)

func _get_ship_ranged_cover_reduction(damage_source: String) -> float:
	return SoldierLifecycleHelper.get_ship_ranged_cover_reduction(self, damage_source)


## 피격 시 하얀색으로 깜빡임
func _flash_hit(flash_color: Color = Color.WHITE) -> void:
	SoldierVisualHelper.flash_hit(self, flash_color)

func _play_death_pose() -> void:
	SoldierSpeechHelper.hide(self)
	SoldierHealthBarHelper.hide(self)
	SoldierCaptainGuardHelper.hide_warning_ring(self)
	SoldierVisualHelper.play_death_pose(self)

func _play_recovery_pose() -> void:
	SoldierSpeechHelper.reset(self)
	SoldierVisualHelper.play_recovery_pose(self)


func begin_named_action(action_name: String, locks_ai: bool = false, animation_name: String = "") -> void:
	SoldierActionHelper.begin_action(self, action_name, locks_ai, animation_name)


func finish_named_action(action_name: String = "") -> void:
	SoldierActionHelper.finish_action(self, action_name)
	if current_state == State.DEAD:
		_play_death_pose()


func has_named_action(action_name: String = "") -> bool:
	return SoldierActionHelper.has_action(self, action_name)


func get_named_action() -> String:
	return SoldierActionHelper.get_action_name(self)


func configure_carry_anchor(side_sign: float = 1.0, forward_offset: float = 0.08, side_offset: float = 0.08, height_offset: float = 0.46) -> Node3D:
	return SoldierActionHelper.configure_carry_anchor(self, side_sign, forward_offset, side_offset, height_offset)


func get_carry_anchor_global_position() -> Vector3:
	return SoldierActionHelper.get_carry_anchor_global_position(self)


func begin_carry_payload(payload: Node3D, payload_kind: String = "generic", side_sign: float = 1.0, forward_offset: float = 0.08, side_offset: float = 0.08, height_offset: float = 0.46) -> bool:
	return SoldierActionHelper.begin_carry_payload(self, payload, payload_kind, side_sign, forward_offset, side_offset, height_offset)


func begin_typed_carry_payload(payload: Node3D, payload_kind: String = "generic", side_sign: float = 1.0, offset_overrides: Dictionary = {}) -> bool:
	return SoldierActionHelper.begin_typed_carry_payload(self, payload, payload_kind, side_sign, offset_overrides)


func finish_carry_payload(payload: Node3D = null) -> void:
	SoldierActionHelper.finish_carry_payload(self, payload)


func get_carry_payload() -> Node3D:
	return SoldierActionHelper.get_carry_payload(self)


func get_carry_payload_kind() -> String:
	return SoldierActionHelper.get_carry_payload_kind(self)


func begin_cargo_transport_action(action_name: String = "") -> void:
	if action_name.is_empty():
		action_name = SoldierActionHelper.ACTION_CARGO_TRANSPORT_APPROACH
	SoldierActionHelper.begin_cargo_transport_action(self, action_name)


func finish_cargo_transport_action() -> void:
	SoldierActionHelper.finish_cargo_transport_action(self)
	if current_state == State.DEAD:
		_play_death_pose()


func play_cargo_transport_carry_animation() -> void:
	SoldierActionHelper.begin_cargo_transport_action(self, SoldierActionHelper.ACTION_CARGO_TRANSPORT_CARRY)


func finish_cargo_transport_carry_animation() -> void:
	finish_cargo_transport_action()

## 적군 도선병 약탈 및 방화 처리 (초당 DoT 데미지)
func _update_boarding_chaos(delta: float) -> void:
	SoldierLifecycleHelper.update_boarding_chaos(self, delta)

## 휘두르기 이펙트 생성 (이 메서드는 이제 Weapon 씬 자체에서 관리하므로 빈칸)
func _spawn_slash_effect() -> void:
	pass

## 체력 100% 회복 (나포 보상 등)
func heal_full() -> void:
	SoldierLifecycleHelper.heal_full(self)


func _try_assist_incapacitated_ally(delta: float, speed_scale: float, turn_speed: float) -> bool:
	if current_state == State.DEAD:
		return false
	if has_named_action() and not has_named_action(SoldierActionHelper.ACTION_INCAPACITATED_ASSIST):
		_clear_incapacitated_assist_target()
		return false
	if team != "player":
		_clear_incapacitated_assist_target()
		return false
	if not is_instance_valid(owned_ship):
		_clear_incapacitated_assist_target()
		return false
	if is_instance_valid(find_nearest_hostile_on_owned_ship()):
		_clear_incapacitated_assist_target()
		return false

	var assist_target: Node3D = _resolve_incapacitated_assist_target()
	if not is_instance_valid(assist_target):
		_clear_incapacitated_assist_target()
		return false

	var target_pos := assist_target.global_position
	target_pos.y = global_position.y
	var use_range := _get_incapacitated_assist_use_range()
	var distance_to_target: float = global_position.distance_to(target_pos)
	var stand_pos := _get_incapacitated_assist_stand_position(assist_target, use_range)
	var distance_to_stand: float = global_position.distance_to(stand_pos)
	var can_channel := distance_to_target <= use_range or distance_to_stand <= INCAPACITATED_ASSIST_STAND_REACHED_RANGE
	if not can_channel:
		set_meta(INCAPACITATED_ASSIST_PROGRESS_META, 0.0)
		_finish_incapacitated_assist_action(assist_target)
		SoldierAiHelper._move_toward_point(self, stand_pos, speed_scale, delta, turn_speed)
		return true

	current_target = null
	velocity = Vector3.ZERO
	move_and_slide()
	SoldierAiHelper.turn_toward_position(self, target_pos, turn_speed, delta)
	_settle_incapacitated_assist_target_on_deck(assist_target)
	_begin_incapacitated_assist_action(assist_target)
	var progress: float = float(get_meta(INCAPACITATED_ASSIST_PROGRESS_META, 0.0)) + minf(delta, INCAPACITATED_ASSIST_PROGRESS_DELTA_CAP)
	set_meta(INCAPACITATED_ASSIST_PROGRESS_META, progress)
	var channel_duration := _get_incapacitated_assist_channel_duration()
	_apply_incapacitated_assist_pickup_motion(assist_target, progress / channel_duration)
	if progress < channel_duration:
		return true

	_settle_incapacitated_assist_target_on_deck(assist_target)
	SoldierLifecycleHelper.assist_recover_incapacitated(assist_target)
	_clear_incapacitated_assist_target()
	return true


func _begin_incapacitated_assist_action(assist_target: Node3D) -> void:
	if not is_instance_valid(assist_target):
		return
	if has_named_action(SoldierActionHelper.ACTION_INCAPACITATED_ASSIST):
		return
	begin_named_action(
		SoldierActionHelper.ACTION_INCAPACITATED_ASSIST,
		false,
		SoldierActionHelper.ACTION_CARGO_TRANSPORT_CARRY
	)
	set_meta(INCAPACITATED_ASSIST_PICKUP_START_POSITION_META, assist_target.global_position)
	var assist_ship := _get_incapacitated_assist_ship(assist_target)
	if is_instance_valid(assist_ship):
		set_meta(INCAPACITATED_ASSIST_PICKUP_START_LOCAL_POSITION_META, assist_ship.to_local(assist_target.global_position))
	set_meta(INCAPACITATED_ASSIST_PICKUP_START_ROTATION_META, assist_target.rotation)
	begin_typed_carry_payload(
		assist_target,
		SoldierActionHelper.CARRY_PAYLOAD_KIND_CORPSE,
		1.0,
		{
			SoldierActionHelper.PAYLOAD_DEF_FORWARD_OFFSET: INCAPACITATED_ASSIST_PICKUP_FORWARD_OFFSET,
			SoldierActionHelper.PAYLOAD_DEF_SIDE_OFFSET: INCAPACITATED_ASSIST_PICKUP_SIDE_OFFSET,
			SoldierActionHelper.PAYLOAD_DEF_HEIGHT_OFFSET: INCAPACITATED_ASSIST_PICKUP_HEIGHT_OFFSET,
		}
	)


func _finish_incapacitated_assist_action(assist_target: Node3D = null) -> void:
	var was_assist_action := has_named_action(SoldierActionHelper.ACTION_INCAPACITATED_ASSIST)
	if has_named_action(SoldierActionHelper.ACTION_INCAPACITATED_ASSIST):
		finish_named_action(SoldierActionHelper.ACTION_INCAPACITATED_ASSIST)
	if was_assist_action:
		finish_carry_payload(assist_target)
	remove_meta(INCAPACITATED_ASSIST_PICKUP_START_POSITION_META)
	remove_meta(INCAPACITATED_ASSIST_PICKUP_START_LOCAL_POSITION_META)
	remove_meta(INCAPACITATED_ASSIST_PICKUP_START_ROTATION_META)


func _apply_incapacitated_assist_pickup_motion(assist_target: Node3D, normalized_progress: float) -> void:
	if not is_instance_valid(assist_target):
		return
	if not has_meta(INCAPACITATED_ASSIST_PICKUP_START_POSITION_META) \
	or not has_meta(INCAPACITATED_ASSIST_PICKUP_START_ROTATION_META):
		return
	var start_rotation: Vector3 = get_meta(INCAPACITATED_ASSIST_PICKUP_START_ROTATION_META)
	var target_rotation := Vector3(start_rotation.x, rotation.y, start_rotation.z)
	var eased_t: float = smoothstep(0.0, 1.0, clampf(minf(normalized_progress, INCAPACITATED_ASSIST_PICKUP_MAX_PROGRESS), 0.0, 1.0))
	assist_target.global_position = _get_incapacitated_assist_anchor_position(assist_target)
	assist_target.rotation = Vector3(
		lerp_angle(start_rotation.x, target_rotation.x, eased_t),
		lerp_angle(start_rotation.y, target_rotation.y, eased_t),
		lerp_angle(start_rotation.z, target_rotation.z, eased_t)
	)


func _settle_incapacitated_assist_target_on_deck(assist_target: Node3D) -> void:
	if not is_instance_valid(assist_target):
		return
	var settled_position := _get_incapacitated_assist_anchor_position(assist_target)
	settled_position.y = global_position.y
	settled_position = _clamp_incapacitated_assist_position_to_deck(assist_target, settled_position)
	settled_position.y = global_position.y
	assist_target.global_position = settled_position


func _get_incapacitated_assist_anchor_position(assist_target: Node3D) -> Vector3:
	var assist_ship := _get_incapacitated_assist_ship(assist_target)
	if is_instance_valid(assist_ship) and has_meta(INCAPACITATED_ASSIST_PICKUP_START_LOCAL_POSITION_META):
		var stored_local: Variant = get_meta(INCAPACITATED_ASSIST_PICKUP_START_LOCAL_POSITION_META)
		if stored_local is Vector3:
			return assist_ship.to_global(stored_local)
	if has_meta(INCAPACITATED_ASSIST_PICKUP_START_POSITION_META):
		var stored_global: Variant = get_meta(INCAPACITATED_ASSIST_PICKUP_START_POSITION_META)
		if stored_global is Vector3:
			return stored_global
	return assist_target.global_position


func _get_incapacitated_assist_ship(assist_target: Node3D) -> Node3D:
	if is_instance_valid(assist_target):
		var target_ship_value: Variant = assist_target.get("owned_ship")
		var target_ship: Node3D = target_ship_value if is_instance_valid(target_ship_value) and target_ship_value is Node3D else null
		if is_instance_valid(target_ship):
			return target_ship
	if is_instance_valid(owned_ship):
		return owned_ship
	return home_ship


func _get_incapacitated_assist_stand_position(assist_target: Node3D, use_range: float) -> Vector3:
	var target_pos := assist_target.global_position
	target_pos.y = global_position.y
	var away_from_target := global_position - target_pos
	away_from_target.y = 0.0
	if away_from_target.length_squared() <= 0.0001:
		if is_instance_valid(owned_ship):
			away_from_target = owned_ship.global_transform.basis.x
		else:
			away_from_target = Vector3.RIGHT
	away_from_target = away_from_target.normalized()
	var stand_distance := maxf(INCAPACITATED_ASSIST_STAND_DISTANCE, use_range * 0.92)
	var stand_pos := target_pos + away_from_target * stand_distance
	stand_pos.y = global_position.y
	return _clamp_incapacitated_assist_position_to_deck(assist_target, stand_pos, INCAPACITATED_ASSIST_DECK_MARGIN)


func _clamp_incapacitated_assist_position_to_deck(assist_target: Node3D, world_position: Vector3, deck_margin: float = 0.0) -> Vector3:
	var assist_ship := _get_incapacitated_assist_ship(assist_target)
	if not is_instance_valid(assist_ship):
		return world_position

	var local_pos := assist_ship.to_local(world_position)
	var half_ext := _get_ship_deck_half_extents(assist_ship)
	var safe_x := maxf(0.0, half_ext.x - deck_margin)
	var safe_z := maxf(0.0, half_ext.y - deck_margin)
	local_pos.x = clampf(local_pos.x, -safe_x, safe_x)
	local_pos.z = clampf(local_pos.z, -safe_z, safe_z)
	var clamped_pos := assist_ship.to_global(local_pos)
	clamped_pos.y = world_position.y
	return clamped_pos


func _resolve_incapacitated_assist_target() -> Node3D:
	var current_id: int = int(get_meta(INCAPACITATED_ASSIST_TARGET_ID_META, 0))
	if current_id != 0:
		var current_target_node := NodeContractHelper.get_instance_node3d(current_id)
		if is_instance_valid(current_target_node) \
		and current_target_node.get_meta("incapacitated", false) == true \
		and current_target_node.get("owned_ship") == owned_ship:
			var claimed_reviver := NodeContractHelper.get_instance_node(int(current_target_node.get_meta(INCAPACITATED_ASSIST_REVIVER_ID_META, 0)))
			if not is_instance_valid(claimed_reviver) or claimed_reviver == self:
				current_target_node.set_meta(INCAPACITATED_ASSIST_REVIVER_ID_META, get_instance_id())
				return current_target_node

	var nearest_target: Node3D = null
	var nearest_distance_sq: float = INF
	for other in EntityRegistry.get_soldiers_by_ship(owned_ship):
		if other == self or not is_instance_valid(other):
			continue
		if other.get_meta("incapacitated", false) != true:
			continue
		if str(other.get("team")) != team:
			continue
		var claimed_reviver_id: int = int(other.get_meta(INCAPACITATED_ASSIST_REVIVER_ID_META, 0))
		if claimed_reviver_id != 0 and claimed_reviver_id != get_instance_id():
			var claimed_reviver := NodeContractHelper.get_instance_node(claimed_reviver_id)
			if is_instance_valid(claimed_reviver):
				continue
			other.remove_meta(INCAPACITATED_ASSIST_REVIVER_ID_META)
		var distance_sq: float = global_position.distance_squared_to(other.global_position)
		var acquire_range := _get_incapacitated_assist_acquire_range()
		if distance_sq > acquire_range * acquire_range:
			continue
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_target = other
	if is_instance_valid(nearest_target):
		set_meta(INCAPACITATED_ASSIST_TARGET_ID_META, nearest_target.get_instance_id())
		set_meta(INCAPACITATED_ASSIST_PROGRESS_META, 0.0)
		nearest_target.set_meta(INCAPACITATED_ASSIST_REVIVER_ID_META, get_instance_id())
	return nearest_target


func _get_incapacitated_assist_channel_duration() -> float:
	var stat_ship := _get_incapacitated_assist_stat_ship()
	if is_instance_valid(stat_ship) and stat_ship.has_meta("incapacitated_assist_channel_duration"):
		return maxf(0.25, float(stat_ship.get_meta("incapacitated_assist_channel_duration")))
	return INCAPACITATED_ASSIST_CHANNEL_DURATION


func _get_incapacitated_assist_acquire_range() -> float:
	var stat_ship := _get_incapacitated_assist_stat_ship()
	if is_instance_valid(stat_ship) and stat_ship.has_meta("incapacitated_assist_acquire_range"):
		return maxf(INCAPACITATED_ASSIST_USE_RANGE, float(stat_ship.get_meta("incapacitated_assist_acquire_range")))
	return INCAPACITATED_ASSIST_ACQUIRE_RANGE


func _get_incapacitated_assist_use_range() -> float:
	var stat_ship := _get_incapacitated_assist_stat_ship()
	if is_instance_valid(stat_ship) and stat_ship.has_meta("incapacitated_assist_use_range"):
		return maxf(0.5, float(stat_ship.get_meta("incapacitated_assist_use_range")))
	return INCAPACITATED_ASSIST_USE_RANGE


func _get_incapacitated_assist_stat_ship() -> Node:
	if is_instance_valid(owned_ship) and owned_ship.has_meta("incapacitated_assist_channel_duration"):
		return owned_ship
	if is_instance_valid(home_ship) and home_ship.has_meta("incapacitated_assist_channel_duration"):
		return home_ship
	if is_instance_valid(owned_ship) and owned_ship.has_meta("incapacitated_assist_health_ratio"):
		return owned_ship
	if is_instance_valid(home_ship) and home_ship.has_meta("incapacitated_assist_health_ratio"):
		return home_ship
	if is_instance_valid(owned_ship):
		return owned_ship
	return home_ship


func _clear_incapacitated_assist_target() -> void:
	var target_id: int = int(get_meta(INCAPACITATED_ASSIST_TARGET_ID_META, 0))
	var target := NodeContractHelper.get_instance_node3d(target_id) if target_id != 0 else null
	_finish_incapacitated_assist_action(target)
	if target_id != 0:
		if is_instance_valid(target) and int(target.get_meta(INCAPACITATED_ASSIST_REVIVER_ID_META, 0)) == get_instance_id():
			target.remove_meta(INCAPACITATED_ASSIST_REVIVER_ID_META)
	remove_meta(INCAPACITATED_ASSIST_TARGET_ID_META)
	remove_meta(INCAPACITATED_ASSIST_PROGRESS_META)

## 사망 처리
func _die() -> void:
	SoldierLifecycleHelper.die(self)


## 상태 변경
func _change_state(new_state: State) -> void:
	var previous_state := current_state
	current_state = new_state
	if new_state == State.ATTACK and previous_state != State.ATTACK:
		attack_validation_timer = randf_range(0.0, maxf(attack_validation_interval_runtime, 0.08))


## 특정 목표로 이동 명령
func move_to_target(target: Node3D) -> void:
	current_target = target
	_change_state(State.MOVE)


## 특정 위치로 이동
func move_to_position(_target_pos: Vector3) -> void:
	# NavMesh 대신 단순 상태 전환 및 타이머/거리 체크로직 등 필요시 구현 (현재는 MOVE 상태에서 실시간 추적)
	_change_state(State.MOVE)


func begin_boarding_jump_pose(status: String = BOARDING_STATUS_BOARDING) -> void:
	_is_jumping = true
	set_boarding_status(status)
	current_target = null
	velocity = Vector3.ZERO
	_change_state(State.BOARDING_JUMP)
	SoldierVisualHelper.play_boarding_jump_pose(self)


func finish_boarding_jump_pose(status: String = BOARDING_STATUS_ON_DECK) -> void:
	_is_jumping = false
	set_boarding_status(status)
	if current_state == State.DEAD:
		_play_death_pose()
		return
	SoldierVisualHelper.play_recovery_pose(self)
	if current_state == State.BOARDING_JUMP:
		_change_state(State.IDLE)


## 원거리 적 확인 및 사격
func _check_ranged_combat(preferred_nearest: Node3D = null, ranged_slot_allowed: Variant = null) -> void:
	SoldierCombatHelper.check_ranged_combat(self, preferred_nearest, ranged_slot_allowed)

func _is_player_fleet_ai_ship_crew() -> bool:
	if not is_instance_valid(owned_ship):
		return false
	return PlayerFleetRoleHelper.is_support_ship(owned_ship) or PlayerFleetRoleHelper.is_legacy_captured_ship(owned_ship)

func _is_passive_ally_ship_crew() -> bool:
	if not _is_player_fleet_ai_ship_crew():
		return false
	if _is_jumping:
		return false
	if current_state == State.ATTACK or current_state == State.MOVE or current_state == State.BOARDING_JUMP:
		return false
	if is_instance_valid(current_target):
		return false
	if boarding_status != BOARDING_STATUS_ON_DECK:
		return false
	if not is_instance_valid(owned_ship):
		return false
	if owned_ship.get("deck_is_contested") == true or owned_ship.get("deck_is_overrun") == true:
		return false
	if owned_ship.get("is_boarding") == true:
		return false
	var boarding_target: Variant = owned_ship.get("boarding_target")
	if is_instance_valid(boarding_target):
		return false
	return true

func _allow_cross_ship_enemy_scan() -> bool:
	if not is_instance_valid(owned_ship):
		return true
	if PlayerFleetRoleHelper.is_player_flagship(owned_ship):
		return true
	var scan_data := SoldierShipSpatialCacheHelper.get_ship_enemy_scan_data(self)
	var distress_ships: Array = scan_data.get("nearby_ally_distress_ships", [])
	for distress_ship in distress_ships:
		if is_instance_valid(distress_ship):
			return true
	return not _is_passive_ally_ship_crew()

func _should_hold_defensive_deck_position_against(target_ship: Node3D) -> bool:
	if not is_instance_valid(target_ship) or not is_instance_valid(owned_ship):
		return false
	if target_ship == owned_ship:
		return false
	if team != "player":
		return false
	if boarding_status != BOARDING_STATUS_ON_DECK or _is_jumping:
		return false
	if is_instance_valid(home_ship) and owned_ship != home_ship:
		return false
	if owned_ship.get("deck_is_contested") == true or owned_ship.get("deck_is_overrun") == true:
		return false
	var hostile_boarders: int = int(owned_ship.get("deck_hostile_boarder_count")) if owned_ship.get("deck_hostile_boarder_count") != null else 0
	if hostile_boarders > 0:
		return false
	return is_melee_only or crew_role == "spearman"

func _is_lod_combat_priority() -> bool:
	if _is_jumping:
		return true
	if current_state == State.ATTACK:
		return true
	if is_instance_valid(current_target):
		return true
	if is_stationary:
		return true
	if is_instance_valid(owned_ship):
		if owned_ship.get("deck_is_contested") == true or owned_ship.get("deck_is_overrun") == true:
			return true
	return false

func _get_decision_throttle_time(ship_hp_ratio: float, dist_to_player: float, combat_priority: bool) -> float:
	var load_mult := _get_ai_load_multiplier()
	if _is_passive_ally_ship_crew():
		if dist_to_player > 40.0:
			return 1.25 * load_mult
		if dist_to_player > 24.0:
			return 0.95 * load_mult
		return 0.72 * load_mult
	var throttle_time: float = 0.2 if ship_hp_ratio > 0.2 else 0.1
	if combat_priority:
		if dist_to_player > 65.0:
			throttle_time = maxf(throttle_time, 0.35)
		elif dist_to_player > 45.0:
			throttle_time = maxf(throttle_time, 0.25)
		return throttle_time * minf(load_mult, 1.35)

	if dist_to_player > 80.0:
		return 1.25 * load_mult
	if dist_to_player > 60.0:
		return 1.0 * load_mult
	if dist_to_player > 40.0:
		return 0.72 * load_mult
	if dist_to_player > 28.0:
		return 0.48 * load_mult
	return 0.36 * minf(load_mult, 1.35)

func _get_combat_throttle_time(dist_to_player: float, combat_priority: bool) -> float:
	var load_mult := _get_ai_load_multiplier()
	if _is_passive_ally_ship_crew():
		if dist_to_player > 40.0:
			return 0.8 * load_mult
		if dist_to_player > 24.0:
			return 0.55 * load_mult
		return 0.35 * minf(load_mult, 1.35)
	if combat_priority:
		if dist_to_player > 65.0:
			return 0.28 * load_mult
		if dist_to_player > 45.0:
			return 0.2 * load_mult
		if dist_to_player > 28.0:
			return 0.14 * minf(load_mult, 1.45)
		return 0.10 * minf(load_mult, 1.45)

	if dist_to_player > 80.0:
		return 0.95 * load_mult
	if dist_to_player > 60.0:
		return 0.7 * load_mult
	if dist_to_player > 40.0:
		return 0.46 * load_mult
	if dist_to_player > 28.0:
		return 0.28 * load_mult
	return 0.16 * minf(load_mult, 1.3)

func _get_nearest_enemy_cache_interval() -> float:
	var interval := _get_combat_throttle_time(_lod_dist_to_player, _lod_is_combat_priority)
	var load_mult := _get_ai_load_multiplier()
	if _lod_is_combat_priority:
		interval = maxf(interval, 0.16 * minf(load_mult, 1.85))
		if EntityRegistry.count_soldiers() >= 90:
			interval = maxf(interval, 0.22 * minf(load_mult, 1.85))
	return interval

func _get_limbo_ai_update_interval() -> float:
	var load_mult := _get_ai_load_multiplier()
	if _is_far_lod_sleep_candidate():
		return 0.22 * load_mult
	if _is_passive_ally_ship_crew():
		if _lod_dist_to_player > 24.0:
			return 0.20 * load_mult
		return 0.16 * minf(load_mult, 1.45)
	if _lod_is_combat_priority:
		if _lod_dist_to_player > 45.0:
			return 0.14 * load_mult
		if _lod_dist_to_player > 28.0:
			return 0.10 * minf(load_mult, 1.35)
		return 0.10 * minf(load_mult, 1.45)
	if _lod_dist_to_player > 60.0:
		return 0.22 * load_mult
	if _lod_dist_to_player > 40.0:
		return 0.18 * load_mult
	return 0.13 * minf(load_mult, 1.45)

func _get_ai_load_multiplier() -> float:
	var frame := Engine.get_physics_frames()
	if _ai_load_cache_frame == frame:
		return _ai_load_multiplier_cache
	var soldier_count := EntityRegistry.count_soldiers()
	var ship_count := EntityRegistry.count_ships()
	var projectile_count := EntityRegistry.count_projectiles()
	var load_mult := 1.0
	if soldier_count > 28:
		load_mult += minf(0.42, float(soldier_count - 28) * 0.03)
	if soldier_count > 36:
		load_mult += minf(0.65, float(soldier_count - 36) * 0.018)
	if ship_count > 6:
		load_mult += minf(0.22, float(ship_count - 6) * 0.055)
	if ship_count > 10:
		load_mult += minf(0.28, float(ship_count - 10) * 0.025)
	if projectile_count > 20:
		load_mult += minf(0.22, float(projectile_count - 20) * 0.008)
	load_mult *= _get_performance_cpu_interval_scale()
	_ai_load_cache_frame = frame
	_ai_load_multiplier_cache = clampf(load_mult, 1.0, 1.85)
	return _ai_load_multiplier_cache


func _get_performance_cpu_interval_scale() -> float:
	if is_instance_valid(SaveManager) and SaveManager.has_method("get_performance_cpu_interval_scale"):
		return float(SaveManager.call("get_performance_cpu_interval_scale"))
	return 1.0


func _get_routine_wander_step_interval() -> float:
	var load_mult := _get_ai_load_multiplier()
	if _is_passive_ally_ship_crew():
		return 0.38 * minf(load_mult, 1.8)
	if not _lod_is_combat_priority:
		return 0.30 * minf(load_mult, 1.8)
	if not is_instance_valid(current_target) and (current_state == State.IDLE or current_state == State.WANDER):
		return 0.26 * minf(load_mult, 1.8)
	return 0.0


func _should_pause_routine_wander_movement() -> bool:
	if _is_jumping or current_state == State.ATTACK or current_state == State.MOVE or current_state == State.BOARDING_JUMP:
		return false
	if is_instance_valid(current_target):
		return false
	if boarding_status != BOARDING_STATUS_ON_DECK:
		return false
	if not is_instance_valid(owned_ship):
		return false

	var load_mult := _get_ai_load_multiplier()
	if load_mult >= 1.26:
		return true
	var impulse_value: Variant = owned_ship.get("collision_impulse_velocity")
	if impulse_value is Vector3 and (impulse_value as Vector3).length_squared() > 0.01 and load_mult >= 1.12:
		return true
	return false


func _should_run_routine_support_step(delta: float, run_heavy_logic: bool) -> bool:
	if not _should_consider_routine_support_step():
		_routine_support_step_timer = 0.0
		_routine_support_step_accum = 0.0
		return false
	_routine_support_step_accum = minf(_routine_support_step_accum + maxf(delta, 0.0), 0.35)
	if run_heavy_logic:
		return true
	if current_state != State.IDLE and current_state != State.WANDER:
		return true
	var interval := _get_routine_support_step_interval()
	if interval <= 0.0:
		return true
	_routine_support_step_timer -= delta
	if _routine_support_step_timer > 0.0:
		return false
	_routine_support_step_timer = interval + randf_range(0.0, interval * 0.18)
	return true


func _should_consider_routine_support_step() -> bool:
	return team == "player"


func _consume_routine_support_step_delta(fallback_delta: float) -> float:
	var step_delta := _routine_support_step_accum
	_routine_support_step_accum = 0.0
	if step_delta <= 0.0:
		return fallback_delta
	return minf(step_delta, 0.35)


func _get_routine_support_step_interval() -> float:
	var load_mult := _get_ai_load_multiplier()
	if _is_passive_ally_ship_crew():
		return 0.34 * minf(load_mult, 1.8)
	if _lod_is_combat_priority:
		return 0.12 * minf(load_mult, 1.65)
	return 0.22 * minf(load_mult, 1.65)

func _refresh_nearest_enemy_cache(force: bool = false) -> Node3D:
	var limbo_target: Node3D = _get_recent_limbo_target()
	if is_instance_valid(limbo_target):
		_cached_nearest_enemy = limbo_target
		_nearest_enemy_cache_interval_runtime = _get_nearest_enemy_cache_interval()
		_nearest_enemy_cache_timer = _nearest_enemy_cache_interval_runtime
		_store_nearest_enemy_query_result(_cached_nearest_enemy)
		return _cached_nearest_enemy
	if not force and _nearest_enemy_cache_timer > 0.0 and is_instance_valid(_cached_nearest_enemy):
		_store_nearest_enemy_query_result(_cached_nearest_enemy)
		return _cached_nearest_enemy
	_cached_nearest_enemy = SoldierShipHelper.find_nearest_enemy(self)
	_nearest_enemy_cache_interval_runtime = _get_nearest_enemy_cache_interval()
	_nearest_enemy_cache_timer = _nearest_enemy_cache_interval_runtime
	_store_nearest_enemy_query_result(_cached_nearest_enemy)
	return _cached_nearest_enemy


func get_limbo_ai_default_tree_path() -> String:
	var role_name: String = crew_role.strip_edges().to_lower()
	if is_ranged_only or role_name == "repeating_crossbow" or role_name == "singigeon" or role_name == "daecheolpo":
		return SoldierLimboAIPilot.RANGED_TREE_PATH
	if _should_use_boarding_limbo_tree():
		return SoldierLimboAIPilot.BOARDING_TREE_PATH
	return SoldierLimboAIPilot.BOARDER_TREE_PATH


func _should_use_boarding_limbo_tree() -> bool:
	if boarding_status == BOARDING_STATUS_BOARDING or boarding_status == BOARDING_STATUS_RETURNING:
		return true
	var owned_ship_node := owned_ship
	if is_instance_valid(owned_ship_node):
		var boarding_target: Node3D = owned_ship_node.get_boarding_target_ship() if owned_ship_node.has_method("get_boarding_target_ship") else owned_ship_node.get("boarding_target")
		if is_instance_valid(boarding_target) and owned_ship_node.get("is_boarding") == true:
			return true
	if is_instance_valid(home_ship) and is_instance_valid(owned_ship_node) and home_ship != owned_ship_node:
		if _has_active_boarding_link_between_ships(home_ship, owned_ship_node):
			return true
	return false


func _has_active_boarding_link_between_ships(ship_a: Node3D, ship_b: Node3D) -> bool:
	return _ship_has_active_boarding_link_to(ship_a, ship_b) or _ship_has_active_boarding_link_to(ship_b, ship_a)


func _ship_has_active_boarding_link_to(from_ship: Node3D, to_ship: Node3D) -> bool:
	if not is_instance_valid(from_ship) or not is_instance_valid(to_ship):
		return false
	if from_ship.has_method("has_boarding_rope_link_to"):
		return from_ship.has_boarding_rope_link_to(to_ship) == true
	var target_ship: Node3D = from_ship.get_boarding_target_ship() if from_ship.has_method("get_boarding_target_ship") else from_ship.get("boarding_target")
	if target_ship != to_ship:
		return false
	return from_ship.get("_initial_rope_deployed") == true


func _update_limbo_ai_pilot_runtime(delta: float) -> void:
	if not limbo_ai_pilot_enabled:
		return
	if current_state == State.DEAD or current_state == State.BOARDING_JUMP:
		return
	_limbo_ai_update_timer -= delta
	if _limbo_ai_update_timer > 0.0:
		return
	_limbo_ai_update_interval_runtime = _get_limbo_ai_update_interval()
	_limbo_ai_update_timer = _limbo_ai_update_interval_runtime + randf_range(0.0, _limbo_ai_update_interval_runtime * 0.45)
	_update_limbo_ai_pilot(delta)


func _update_limbo_ai_pilot(delta: float) -> void:
	if not limbo_ai_pilot_enabled:
		return
	if current_state == State.DEAD or current_state == State.BOARDING_JUMP:
		return
	var profile_start := PhysicsFrameProfiler.begin()
	if not SoldierLimboAIPilot.tick(self, delta, limbo_ai_pilot_tree_path):
		PhysicsFrameProfiler.end("soldier_limbo_ai", profile_start)
		return
	_apply_limbo_ai_bridge()
	PhysicsFrameProfiler.end("soldier_limbo_ai", profile_start)


func _apply_limbo_ai_bridge() -> void:
	var pilot_target: Node3D = _get_recent_limbo_target()
	var mode: String = _get_recent_limbo_mode()
	if mode.is_empty():
		return
	if is_instance_valid(pilot_target):
		current_target = pilot_target
	elif mode == SoldierAILimboKeys.MODE_WANDER:
		current_target = null
	if current_state == State.DEAD or current_state == State.BOARDING_JUMP:
		return
	if SoldierActionHelper.is_action_ai_locked(self):
		return
	match mode:
		SoldierAILimboKeys.MODE_ATTACK_TARGET:
			if is_instance_valid(pilot_target) and current_state != State.ATTACK:
				_change_state(State.ATTACK)
		SoldierAILimboKeys.MODE_MOVE_TO_TARGET:
			if is_stationary:
				if current_state != State.IDLE:
					_change_state(State.IDLE)
			elif is_instance_valid(pilot_target) and current_state != State.MOVE:
				_change_state(State.MOVE)
		SoldierAILimboKeys.MODE_WANDER:
			if current_state == State.MOVE or current_state == State.ATTACK:
				_change_state(State.IDLE)


func _get_recent_limbo_target() -> Node3D:
	if not limbo_ai_pilot_enabled:
		return null
	var frame: int = int(get_meta(SoldierAILimboKeys.META_FRAME, -1000000))
	if Engine.get_physics_frames() - frame > SoldierAILimboKeys.META_STALE_FRAMES:
		return null
	var target_id: int = int(get_meta(SoldierAILimboKeys.META_TARGET_ID, 0))
	if target_id == 0:
		return null
	return NodeContractHelper.get_instance_node3d(target_id)


func _get_recent_limbo_mode() -> String:
	if not limbo_ai_pilot_enabled:
		return ""
	var frame: int = int(get_meta(SoldierAILimboKeys.META_FRAME, -1000000))
	if Engine.get_physics_frames() - frame > SoldierAILimboKeys.META_STALE_FRAMES:
		return ""
	return str(get_meta(SoldierAILimboKeys.META_MODE, "")).strip_edges()


func _get_recent_limbo_point_for_mode(expected_mode: String) -> Vector3:
	if not limbo_ai_pilot_enabled:
		return Vector3.INF
	var frame: int = int(get_meta(SoldierAILimboKeys.META_FRAME, -1000000))
	if Engine.get_physics_frames() - frame > SoldierAILimboKeys.META_STALE_FRAMES:
		return Vector3.INF
	if str(get_meta(SoldierAILimboKeys.META_MODE, "")).strip_edges() != expected_mode:
		return Vector3.INF
	var point_value: Variant = get_meta(SoldierAILimboKeys.META_POINT, null)
	if point_value is Vector3:
		return point_value as Vector3
	return Vector3.INF

func _is_far_lod_sleep_candidate() -> bool:
	if _lod_is_combat_priority:
		return false
	if current_target != null:
		return false
	if current_state != State.IDLE and current_state != State.WANDER:
		return false
	if _is_passive_ally_ship_crew():
		return _lod_dist_to_player > 24.0
	return _lod_dist_to_player > 60.0

func _find_ranged_target() -> Node3D:
	return SoldierCombatHelper.find_ranged_target(self)

func _perform_range_attack(_target: Node3D) -> void:
	pass
