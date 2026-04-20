extends CharacterBody3D
const SoldierWeaponHelper = preload("res://scripts/entities/soldiers/soldier_weapon_helper.gd")
const SoldierAiHelper = preload("res://scripts/entities/soldiers/soldier_ai_helper.gd")
const SoldierActionHelper = preload("res://scripts/entities/soldiers/soldier_action_helper.gd")
const SoldierVisualHelper = preload("res://scripts/entities/soldiers/soldier_visual_helper.gd")
const SoldierCombatHelper = preload("res://scripts/entities/soldiers/soldier_combat_helper.gd")
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
	RELOAD,
	BOARDING_JUMP
}

const REST_RECOVERY_HEALTH_PER_SECOND: float = 3.0
const REST_RECOVERY_DELAY_AFTER_DAMAGE: float = 3.0
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
@export var crit_chance: float = 0.1 # 크리티컬 확률 (10%)
@export var crit_multiplier: float = 2.0 # 크리티컬 데미지 배율
@export var attack_damage: float = 12.0: # 기본 공격력 (근접/원거리 공용)
	set(value):
		attack_damage = value
		if is_inside_tree():
			_update_weapon_stats()

@export var defense: float = 0.0 # 방어력 (피해 감소)

@export var move_speed: float = 3.0
@export var team: String = "player": # "player" or "enemy"
	set(value):
		team = value
		if is_inside_tree():
			_setup_soldier_visual()
			_update_team_color()
			_update_weapon_stats()
@export_enum("general", "spearman", "fire_pot", "repeating_crossbow", "singigeon") var crew_role: String = "general"
@export var is_captain: bool = false
@export var is_stationary: bool = false # 제자리 고정 (NavMesh 없는 배용)
@export var weapon_switch_distance: float = 4.0 # 무기 교체 거리 (이내면 검, 밖이면 활)하향 (10 -> 4)
@export var cross_ship_melee_switch_distance: float = 6.8 # 인접 적선과 교전 시 근접 무기로 전환하는 거리
@export var is_melee_only: bool = false ## 근접 무기만 사용 (백병전용)
@export var is_ranged_only: bool = false ## 원거리 무기만 사용 (포격 지원용)
@export_group("Visuals")
@export var soldier_visual_scene: PackedScene
@export var player_visual_scene: PackedScene
@export var enemy_visual_scene: PackedScene
@export var captain_visual_scene: PackedScene
@export_group("")
# === 내부 상태 ===
var current_health: float = 70.0
var current_state: State = State.IDLE
var current_target: Node3D = null
var current_weapon: Node3D = null
var attack_timer: float = 0.0
var cannon_reload_pose_timer: float = 0.0
var cannon_reload_source: Node3D = null
var wander_timer: float = 0.0
var wander_target_local: Vector3 = Vector3.ZERO # 배 기준 로컬 목표 지점
var decision_timer: float = 0.0 # 의사결정 스로틀링용
var combat_timer: float = 0.0 # 전투/사격 체크 스로틀링용
var rest_recovery_delay_timer: float = 0.0
var _is_jumping: bool = false # 점프/도선 중인지 여부
var boarding_status: String = "on_deck"

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
var home_ship: Node3D = null # 최초 소속된 플레이어 배 (나포함 침몰 시 복귀용)
var _cached_level_manager: Node = null
var last_nav_target_pos: Vector3 = Vector3.ZERO # 경로 갱신 최적화용
var _lod_dist_to_player: float = 0.0
var _lod_is_combat_priority: bool = false
var _cached_nearest_enemy: Node3D = null
var _nearest_enemy_cache_timer: float = 0.0
var _nearest_enemy_cache_interval_runtime: float = 0.2
var soldier_level: int = 1
var soldier_xp: float = 0.0

# === 도선 약탈 및 방화 (Boarding Chaos) 페널티 ===
var is_boarder_on_player_ship: bool = false
var chaos_duration_timer: float = 0.0 # 호환/디버그용: 적 도선병은 이제 시간으로 퇴각하지 않음
var chaos_tick_timer: float = 0.0 # 1초마다 데미지 틱
var chaos_damage_per_tick: float = 3.0 # 적 도선병은 퇴각하지 않으므로 지속 피해는 낮게 유지
var _base_max_health_stat: float = 0.0
var _base_attack_damage_stat: float = 0.0
var _base_defense_stat: float = 0.0

var CROSS_SHIP_ENGAGE_MAX_DISTANCE: float = 14.5
var CROSS_SHIP_ENGAGE_SHIP_DISTANCE: float = 16.5
const RANGED_DAMAGE_SOURCES := {
	"bow": true,
	"repeating_crossbow": true,
	"ballista": true,
	"singigeon": true,
	"fire_pot": true,
}
const SOLDIER_MAX_LEVEL := 5
const SOLDIER_XP_BASE_REQUIREMENT := 2.0
const SOLDIER_XP_REQUIREMENT_STEP := 2.0
const BOARDING_STATUS_ON_DECK := "on_deck"
const BOARDING_STATUS_BOARDING := "boarding"
const BOARDING_STATUS_RETURNING := "returning"
const BOARDING_STATUS_STRANDED := "stranded"

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
	_apply_soldier_level_stats()
	
	# AI 실행 시점 분산 (Staggering)
	decision_timer = randf_range(0.0, 0.2)
	combat_timer = randf_range(0.0, 0.12)
	_nearest_enemy_cache_timer = randf_range(0.0, 0.18)
	SoldierSpeechHelper.reset(self)
	
	# 그룹 수동 등록 (검색 정확도 향상)
	add_to_group("soldiers")
	
	# UpgradeManager 캐싱 및 시그널 연결 (매 프레임 노드 탐색 방지)
	_cached_upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(_cached_upgrade_manager):
		if _cached_upgrade_manager.has_signal("upgrade_applied"):
			_cached_upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

	EntityRegistry.register_soldier(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_soldier(self)


func get_visual_root_node() -> Node3D:
	var visual_root := get_node_or_null(SoldierVisualHelper.VISUAL_ROOT_NAME) as Node3D
	return visual_root if visual_root != null else self


func ensure_visual_root_node() -> Node3D:
	var visual_root := get_node_or_null(SoldierVisualHelper.VISUAL_ROOT_NAME) as Node3D
	if visual_root != null:
		return visual_root
	visual_root = Node3D.new()
	visual_root.name = SoldierVisualHelper.VISUAL_ROOT_NAME
	add_child(visual_root)
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
	return pivot as Node3D if pivot is Node3D else null


func ensure_hand_pivot() -> Node3D:
	var pivot := get_hand_pivot()
	if pivot != null:
		return pivot
	pivot = Node3D.new()
	pivot.name = NODE_HAND_PIVOT
	pivot.position = DEFAULT_HAND_PIVOT_POSITION
	add_child(pivot)
	return pivot


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
		cross_ship_melee_switch_distance = float(combat_ranges.get("cross_ship_melee_switch_distance", cross_ship_melee_switch_distance))
		CROSS_SHIP_ENGAGE_MAX_DISTANCE = float(combat_ranges.get("cross_ship_engage_max_distance", CROSS_SHIP_ENGAGE_MAX_DISTANCE))
		CROSS_SHIP_ENGAGE_SHIP_DISTANCE = float(combat_ranges.get("cross_ship_engage_ship_distance", CROSS_SHIP_ENGAGE_SHIP_DISTANCE))

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
	if upgrade_id in ["crew_attack", "crew_defense"]:
		_update_weapon_stats()

## 무기 공격력 수치 동기화
func _update_weapon_stats() -> void:
	var damage_bonus_pct := _get_total_weapon_damage_bonus_pct()

	_sync_weapon_damage_bonus(weapon_sword, damage_bonus_pct)
	_sync_weapon_damage_bonus(weapon_bow, damage_bonus_pct)


func _sync_weapon_damage_bonus(weapon: Node, damage_bonus_pct: float) -> void:
	if not is_instance_valid(weapon):
		return
	if weapon.has_method("apply_owner_damage_bonus_pct"):
		weapon.call("apply_owner_damage_bonus_pct", damage_bonus_pct)
	elif "damage" in weapon:
		weapon.damage = attack_damage * (1.0 + damage_bonus_pct)


func _get_total_weapon_damage_bonus_pct() -> float:
	if team != "player":
		return 0.0
	var meta_manager = get_node_or_null("/root/MetaManager")
	var damage_bonus_pct: float = 0.0
	if is_instance_valid(meta_manager) and meta_manager.has_method("get_crew_damage_bonus_pct"):
		damage_bonus_pct += float(meta_manager.get_crew_damage_bonus_pct())
	if has_meta("damage_bonus_pct"):
		damage_bonus_pct += float(get_meta("damage_bonus_pct"))
	if has_meta("soldier_level_damage_bonus_pct"):
		damage_bonus_pct += float(get_meta("soldier_level_damage_bonus_pct"))
	return maxf(0.0, damage_bonus_pct)


func _get_soldier_level_damage_bonus_pct() -> float:
	if team != "player":
		return 0.0
	match clampi(soldier_level, 1, SOLDIER_MAX_LEVEL):
		2:
			return 0.08
		3:
			return 0.16
		4:
			return 0.25
		5:
			return 0.35
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

func _update_level_visual() -> void:
	SoldierVisualHelper.update_level_visual(self)

func add_soldier_xp(amount: float, _reason: String = "") -> void:
	if team != "player":
		return
	if amount <= 0.0:
		return

	soldier_xp += amount
	while soldier_level < SOLDIER_MAX_LEVEL:
		var required_xp := _get_soldier_xp_required_for_next_level()
		if soldier_xp + 0.001 < required_xp:
			break
		soldier_xp -= required_xp
		soldier_level += 1

	if soldier_level >= SOLDIER_MAX_LEVEL:
		soldier_xp = 0.0
	_apply_soldier_level_stats()

func _apply_soldier_level_stats() -> void:
	soldier_level = clampi(soldier_level, 1, SOLDIER_MAX_LEVEL)
	soldier_xp = maxf(soldier_xp, 0.0)
	set_meta("soldier_level", soldier_level)
	set_meta("soldier_xp", soldier_xp)
	set_meta("soldier_level_damage_bonus_pct", _get_soldier_level_damage_bonus_pct())
	if has_meta("soldier_level_attack_bonus"):
		remove_meta("soldier_level_attack_bonus")
	if is_inside_tree():
		_update_weapon_stats()
		_update_level_visual()

func _get_soldier_xp_required_for_next_level() -> float:
	if soldier_level >= SOLDIER_MAX_LEVEL:
		return 0.0
	return SOLDIER_XP_BASE_REQUIREMENT + float(soldier_level - 1) * SOLDIER_XP_REQUIREMENT_STEP

func get_soldier_level_value() -> int:
	return soldier_level

func get_soldier_xp_value() -> float:
	return soldier_xp

func get_soldier_next_level_xp_requirement() -> float:
	return _get_soldier_xp_required_for_next_level()


func set_team(new_team: String) -> void:
	var old_team = team
	team = new_team
	EntityRegistry.update_soldier_team(self, old_team, team)
	_update_team_color()
	if is_inside_tree():
		_apply_soldier_level_stats()

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

func get_damage_multiplier_value() -> float:
	return float(get_meta("damage_multiplier", 1.0))

func get_weapon_damage_bonus_pct_value() -> float:
	return _get_total_weapon_damage_bonus_pct()

func get_velocity_value() -> Vector3:
	return velocity

func is_combat_disabled() -> bool:
	return current_state == State.DEAD

func is_dead() -> bool:
	return current_state == State.DEAD

func get_owned_ship_node() -> Node3D:
	return owned_ship if is_instance_valid(owned_ship) else null


func get_home_ship_node() -> Node3D:
	return home_ship if is_instance_valid(home_ship) else null


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
	boarding_status = next_status
	set_meta("boarding_status", boarding_status)


func get_boarding_status_value() -> String:
	return boarding_status


func _update_team_color() -> void:
	SoldierVisualHelper.update_team_color(self)


func _physics_process(delta: float) -> void:
	# 바다에 빠지면 사망 (글로벌 Y < -5)
	if is_inside_tree() and global_position.y < -5.0:
		set_meta("last_death_cause", "drowned")
		set_meta("last_damage_source", "drowned")
		# 바다에 빠질 때 작은 물보라 이펙트 재생
		var water_explosion_scene = preload("res://scenes/effects/water_burst.tscn")
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
			
		# [최적화] 사망 시 배의 폐선 여부 체크 이벤트 트리거
		if is_instance_valid(home_ship) and home_ship.has_method("check_derelict_status"):
			home_ship.call_deferred("check_derelict_status")
			
		_die()
		return

	if SoldierActionHelper.is_action_ai_locked(self):
		velocity = Vector3.ZERO
		if attack_timer > 0:
			attack_timer -= delta
		return

	SoldierSpeechHelper.update(self, delta)
		
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
			move_and_slide()
			_keep_within_owned_ship_bounds()
		if attack_timer > 0: attack_timer -= delta
		_check_ranged_combat()
		return
	
	# 의사결정 스로틀링 (0.2초마다 고비용 로직 수행)
	decision_timer -= delta
	var run_heavy_logic = false
	if decision_timer <= 0:
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
		_lod_is_combat_priority = _is_lod_combat_priority()
		var throttle_time = _get_decision_throttle_time(ship_hp_ratio, dist_to_player, _lod_is_combat_priority)
			
		decision_timer = throttle_time + randf_range(0.0, 0.05)
		run_heavy_logic = true
		_refresh_nearest_enemy_cache(true)

	_nearest_enemy_cache_timer -= delta

	combat_timer -= delta
	var run_combat_logic: bool = false
	if combat_timer <= 0:
		var combat_throttle_time = _get_combat_throttle_time(_lod_dist_to_player, _lod_is_combat_priority)
		combat_timer = combat_throttle_time + randf_range(0.0, 0.04)
		run_combat_logic = true
		
	# === 적군 도선병 방화(Chaos) 로직 ===
	if team == "enemy" and current_state != State.DEAD:
		# 플레이어 배에 타고 있는지 확인
		if is_instance_valid(owned_ship) and owned_ship.get("team") == "player":
			_update_boarding_chaos(delta)
	
	match current_state:
		State.IDLE:
			_state_idle(delta, run_heavy_logic)
		State.WANDER:
			_state_wander(delta, run_heavy_logic)
		State.MOVE:
			_state_move(delta, run_heavy_logic)
		State.ATTACK:
			_state_attack(delta)
		State.RELOAD:
			_state_cannon_reload(delta)
		State.BOARDING_JUMP:
			_state_boarding_jump()
		State.DEAD:
			pass
	
	if not _is_jumping and current_state != State.DEAD:
		if current_state == State.IDLE:
			if velocity.length_squared() > 0.0001:
				move_and_slide()
		elif current_state == State.ATTACK:
			move_and_slide()
		_keep_within_owned_ship_bounds()
			
	# 탈출(Evacuation) 체크: 소속된 나포함이 가라앉고 있으면 홈으로 복귀
	if run_heavy_logic and team == "player" and is_instance_valid(owned_ship) and owned_ship.get("is_dying") == true:
		_try_evacuate_to_home()
	
	# 공격 쿨다운 (캐싱된 업그레이드 수치 사용)
	if attack_timer > 0:
		attack_timer -= delta

	# 원거리 사격 및 무기 스위칭 체크 (전투 스케줄)
	if current_state != State.DEAD and current_state != State.RELOAD and current_state != State.BOARDING_JUMP and run_combat_logic:
		var nearest = find_nearest_enemy()
		SoldierWeaponHelper.update_combat_weapon_choice(self, nearest)

		if current_state != State.ATTACK:
			_check_ranged_combat()
			_check_ship_capture_opportunity()

	_update_rest_recovery(delta)


func _update_rest_recovery(delta: float) -> void:
	if team != "player" or current_state == State.DEAD:
		return
	if rest_recovery_delay_timer > 0.0:
		rest_recovery_delay_timer = maxf(0.0, rest_recovery_delay_timer - delta)
	if not _can_rest_recover():
		return
	current_health = minf(current_health + REST_RECOVERY_HEALTH_PER_SECOND * delta, max_health)


func _can_rest_recover() -> bool:
	if current_health >= max_health:
		return false
	if rest_recovery_delay_timer > 0.0:
		return false
	if _is_jumping:
		return false
	if current_state == State.ATTACK or current_state == State.RELOAD or current_state == State.BOARDING_JUMP:
		return false
	if is_instance_valid(current_target):
		return false
	return true


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


## RELOAD 상태: 임시 포대 장전 포즈. 실제 애니메이션은 나중에 붙이고 지금은 대포를 바라보며 정지한다.
func _state_cannon_reload(delta: float) -> void:
	cannon_reload_pose_timer = maxf(0.0, cannon_reload_pose_timer - delta)
	velocity = Vector3.ZERO
	if is_instance_valid(cannon_reload_source):
		var look_target: Vector3 = cannon_reload_source.global_position
		look_target.y = global_position.y
		SoldierAiHelper.turn_toward_position(self, look_target, SoldierAiHelper.ATTACK_TURN_SPEED, delta)
	move_and_slide()
	if cannon_reload_pose_timer <= 0.0 or not is_instance_valid(owned_ship) or owned_ship.get("deck_is_contested") == true:
		_finish_cannon_reload_pose()
		_change_state(State.IDLE)


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
	if is_instance_valid(owned_ship):
		var owned_team: String = owned_ship.get_team_tag() if owned_ship.has_method("get_team_tag") else str(owned_ship.get("team"))
		if owned_team == team:
			var local_hostile := find_nearest_hostile_on_owned_ship()
			if is_instance_valid(local_hostile):
				_cached_nearest_enemy = local_hostile
				return local_hostile
	if _nearest_enemy_cache_timer > 0.0 and is_instance_valid(_cached_nearest_enemy):
		return _cached_nearest_enemy
	return _refresh_nearest_enemy_cache(true)

func find_nearest_hostile_on_owned_ship() -> Node3D:
	return SoldierShipHelper.find_nearest_hostile_on_owned_ship(self)

## 전이 로직은 통제됨 (개별 나포 기회 체크 삭제)
func _check_ship_capture_opportunity() -> void:
	return

func _is_ship_pair_in_melee_range(other_ship: Node3D) -> bool:
	return SoldierShipHelper.is_ship_pair_in_melee_range(self, other_ship)


func _get_cross_ship_engage_ship_distance(other_ship: Node3D) -> float:
	return SoldierShipHelper.get_cross_ship_engage_ship_distance(self, other_ship)


func _get_cross_ship_engage_max_distance(other_ship: Node3D) -> float:
	return SoldierShipHelper.get_cross_ship_engage_max_distance(self, other_ship)


func _get_cross_ship_contact_point_local(other_ship: Node3D) -> Vector3:
	return SoldierShipHelper.get_cross_ship_contact_point_local(self, other_ship)


func _get_cross_ship_contact_point_global(other_ship: Node3D) -> Vector3:
	return SoldierShipHelper.get_cross_ship_contact_point_global(self, other_ship)


func _is_in_cross_ship_contact_zone(other_ship: Node3D) -> bool:
	return SoldierShipHelper.is_in_cross_ship_contact_zone(self, other_ship)


func _find_cross_ship_muster_target() -> Vector3:
	return SoldierShipHelper.find_cross_ship_muster_target(self)


func _find_ship_duty_target() -> Vector3:
	return SoldierShipDutyHelper.find_ship_duty_target(self)


func _get_active_ship_duty_target() -> Vector3:
	return SoldierShipDutyHelper.get_active_ship_duty_target(self)


## 홈으로 긴급 복귀 (배가 가라앉을 때)
func _try_evacuate_to_home() -> void:
	SoldierBoardingHelper.try_evacuate_to_home(self)

func _jump_to_ship(target_ship: Node3D, is_capture_attempt: bool = false) -> void:
	SoldierBoardingHelper.jump_to_ship(self, target_ship, is_capture_attempt)

func _teleport_to_ship(_target_ship: Node3D) -> void:
	SoldierBoardingHelper.teleport_to_ship(self, _target_ship)

func _keep_within_owned_ship_bounds() -> void:
	SoldierShipHelper.keep_within_owned_ship_bounds(self)

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


func begin_corpse_cleanup_action(action_name: String = "") -> void:
	if action_name.is_empty():
		action_name = SoldierActionHelper.ACTION_CORPSE_CLEANUP_APPROACH
	SoldierActionHelper.begin_corpse_cleanup_action(self, action_name)


func finish_corpse_cleanup_action() -> void:
	SoldierActionHelper.finish_corpse_cleanup_action(self)
	if current_state == State.DEAD:
		_play_death_pose()


func play_corpse_cleanup_carry_animation() -> void:
	SoldierActionHelper.begin_corpse_cleanup_action(self, SoldierActionHelper.ACTION_CORPSE_CLEANUP_CARRY)


func finish_corpse_cleanup_carry_animation() -> void:
	finish_corpse_cleanup_action()

## 적군 도선병 약탈 및 방화 처리 (초당 DoT 데미지)
func _update_boarding_chaos(delta: float) -> void:
	SoldierLifecycleHelper.update_boarding_chaos(self, delta)

## 휘두르기 이펙트 생성 (이 메서드는 이제 Weapon 씬 자체에서 관리하므로 빈칸)
func _spawn_slash_effect() -> void:
	pass

## 체력 100% 회복 (나포 보상 등)
func heal_full() -> void:
	SoldierLifecycleHelper.heal_full(self)

## 사망 처리
func _die() -> void:
	SoldierLifecycleHelper.die(self)


## 상태 변경
func _change_state(new_state: State) -> void:
	current_state = new_state


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
	_finish_cannon_reload_pose()
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


func is_available_for_cannon_reload_pose() -> bool:
	if current_state == State.DEAD:
		return false
	if SoldierActionHelper.has_action(self) and not SoldierActionHelper.has_action(self, SoldierActionHelper.ACTION_CANNON_RELOAD):
		return false
	if _is_jumping:
		return false
	if is_captain:
		return false
	if is_instance_valid(current_target):
		return false
	if current_state == State.ATTACK or current_state == State.MOVE:
		return false
	if is_instance_valid(owned_ship) and (owned_ship.get("deck_is_contested") == true or owned_ship.get("deck_is_overrun") == true):
		return false
	if not SoldierShipWorkPriorityHelper.can_accept_immediate_work(self, SoldierShipWorkPriorityHelper.TASK_CANNON_RELOAD):
		return false
	return true


func play_cannon_reload_pose(source_node: Node3D, duration: float = 0.9) -> void:
	if not is_available_for_cannon_reload_pose():
		return
	if not SoldierShipWorkPriorityHelper.reserve_work_slot(source_node, self, SoldierShipWorkPriorityHelper.TASK_CANNON_RELOAD, duration + 0.45):
		return
	cannon_reload_source = source_node
	cannon_reload_pose_timer = maxf(cannon_reload_pose_timer, duration)
	current_target = null
	velocity = Vector3.ZERO
	SoldierActionHelper.begin_known_action(self, SoldierActionHelper.ACTION_CANNON_RELOAD)
	_change_state(State.RELOAD)


func _finish_cannon_reload_pose() -> void:
	if is_instance_valid(cannon_reload_source):
		SoldierShipWorkPriorityHelper.release_work_slot(cannon_reload_source, self, SoldierShipWorkPriorityHelper.TASK_CANNON_RELOAD)
	cannon_reload_source = null
	cannon_reload_pose_timer = 0.0
	SoldierActionHelper.finish_action(self, SoldierActionHelper.ACTION_CANNON_RELOAD)

## 원거리 적 확인 및 사격
func _check_ranged_combat() -> void:
	SoldierCombatHelper.check_ranged_combat(self)

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
		if str(owned_ship.get("team")) == "player":
			return true
	return false

func _get_decision_throttle_time(ship_hp_ratio: float, dist_to_player: float, combat_priority: bool) -> float:
	var throttle_time: float = 0.2 if ship_hp_ratio > 0.2 else 0.1
	if combat_priority:
		if dist_to_player > 65.0:
			throttle_time = maxf(throttle_time, 0.35)
		elif dist_to_player > 45.0:
			throttle_time = maxf(throttle_time, 0.25)
		return throttle_time

	if dist_to_player > 80.0:
		return 1.1
	if dist_to_player > 60.0:
		return 0.85
	if dist_to_player > 40.0:
		return 0.55
	if dist_to_player > 28.0:
		return 0.32
	return throttle_time

func _get_combat_throttle_time(dist_to_player: float, combat_priority: bool) -> float:
	if combat_priority:
		if dist_to_player > 65.0:
			return 0.28
		if dist_to_player > 45.0:
			return 0.2
		if dist_to_player > 28.0:
			return 0.14
		return 0.08

	if dist_to_player > 80.0:
		return 0.95
	if dist_to_player > 60.0:
		return 0.7
	if dist_to_player > 40.0:
		return 0.46
	if dist_to_player > 28.0:
		return 0.28
	return 0.16

func _get_nearest_enemy_cache_interval() -> float:
	return _get_combat_throttle_time(_lod_dist_to_player, _lod_is_combat_priority)

func _refresh_nearest_enemy_cache(force: bool = false) -> Node3D:
	if not force and _nearest_enemy_cache_timer > 0.0 and is_instance_valid(_cached_nearest_enemy):
		return _cached_nearest_enemy
	_cached_nearest_enemy = SoldierShipHelper.find_nearest_enemy(self)
	_nearest_enemy_cache_interval_runtime = _get_nearest_enemy_cache_interval()
	_nearest_enemy_cache_timer = _nearest_enemy_cache_interval_runtime
	return _cached_nearest_enemy

func _is_far_lod_sleep_candidate() -> bool:
	if _lod_is_combat_priority:
		return false
	if current_target != null:
		return false
	if current_state != State.IDLE and current_state != State.WANDER:
		return false
	return _lod_dist_to_player > 60.0

func _find_ranged_target() -> Node3D:
	return SoldierCombatHelper.find_ranged_target(self)

func _perform_range_attack(_target: Node3D) -> void:
	pass
