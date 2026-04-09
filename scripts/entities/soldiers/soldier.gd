extends CharacterBody3D
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const SoldierRulesData = preload("res://scripts/helpers/soldier_rules_data.gd")
const SoldierBoardingHelper = preload("res://scripts/entities/soldiers/soldier_boarding_helper.gd")
const SoldierShipHelper = preload("res://scripts/entities/soldiers/soldier_ship_helper.gd")
const SoldierShipDutyHelper = preload("res://scripts/entities/soldiers/soldier_ship_duty_helper.gd")
const SoldierWeaponHelper = preload("res://scripts/entities/soldiers/soldier_weapon_helper.gd")
const SoldierAiHelper = preload("res://scripts/entities/soldiers/soldier_ai_helper.gd")
const SoldierVisualHelper = preload("res://scripts/entities/soldiers/soldier_visual_helper.gd")
const SoldierCombatHelper = preload("res://scripts/entities/soldiers/soldier_combat_helper.gd")
const SoldierLifecycleHelper = preload("res://scripts/entities/soldiers/soldier_lifecycle_helper.gd")
const BOW_SCENE = preload("res://scenes/entities/weapons/weapon_bow.tscn")
const SWORD_SCENE = preload("res://scenes/entities/weapons/weapon_sword.tscn")
const SPEARMAN_MELEE_SCENES := [
	preload("res://scenes/entities/weapons/weapon_spear.tscn"),
	preload("res://scenes/entities/weapons/weapon_trident.tscn"),
]
const SURVIVOR_SCENE = preload("res://scenes/effects/survivor.tscn")

## 병사 AI: NavMesh 기반 이동 및 전투

enum State {
	IDLE,
	WANDER,
	MOVE,
	ATTACK,
	DEAD
}

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
			_update_team_color()
			_update_weapon_stats()
@export_enum("general", "spearman", "fire_pot", "repeating_crossbow", "singigeon") var crew_role: String = "general"
@export var is_captain: bool = false
@export var is_stationary: bool = false # 제자리 고정 (NavMesh 없는 배용)
@export var weapon_switch_distance: float = 4.0 # 무기 교체 거리 (이내면 검, 밖이면 활)하향 (10 -> 4)
@export var cross_ship_melee_switch_distance: float = 6.8 # 인접 적선과 교전 시 근접 무기로 전환하는 거리
@export var is_melee_only: bool = false ## 근접 무기만 사용 (백병전용)
@export var is_ranged_only: bool = false ## 원거리 무기만 사용 (포격 지원용)
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
var home_ground_timer: float = 0.0 # 홈그라운드 체력 재생 타이머
var _is_jumping: bool = false # 점프/도선 중인지 여부

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

# === 도선 약탈 및 방화 (Boarding Chaos) 페널티 ===
var is_boarder_on_player_ship: bool = false
var chaos_duration_timer: float = 8.0 # 최대 8초간 약탈 후 도망감
var chaos_tick_timer: float = 0.0 # 1초마다 데미지 틱
var chaos_damage_per_tick: float = 5.0 # 상향: 초당 5의 화재 피해 (배 체력 비례)
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
	
	# 부모 노드 구조에 따라 배 참조 찾기
	# 구조: Ship -> Soldiers -> Soldier
	var parent = get_parent()
	if parent and parent.name == "Soldiers":
		owned_ship = parent.get_parent()
	elif parent and parent.has_method("get_wind_strength"): # Ship 스크립트 체크
		owned_ship = parent
		
	# 모든 병사에게 home_ship 기록 (원래 소속 배 추적용)
	home_ship = owned_ship
	
	_cached_level_manager = get_tree().root.find_child("LevelManager", true, false)
			
	if not has_node("HandPivot"):
		var pivot = Node3D.new()
		pivot.name = "HandPivot"
		# 캐릭터 오른손 위치
		pivot.position = Vector3(0.3, 0.7, -0.15)
		add_child(pivot)
		
	# 무기 생성
	var hand = get_node_or_null("HandPivot")
	
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
		_update_weapon_stats()
		if enabled:
			_set_active_weapon("sword")
		else:
			_apply_role_loadout()
		_update_role_visual()

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id in ["crew_attack", "crew_defense"]:
		_update_weapon_stats()

## 무기 공격력 수치 동기화
func _update_weapon_stats() -> void:
	var meta_manager = get_node_or_null("/root/MetaManager")
	var mult: float = 1.0
	var attack_flat_bonus: float = 0.0
	if team == "player" and is_instance_valid(meta_manager):
		if meta_manager.has_method("get_crew_damage_bonus"):
			attack_flat_bonus += float(meta_manager.get_crew_damage_bonus())
	if has_meta("attack_flat_bonus"):
		attack_flat_bonus += float(get_meta("attack_flat_bonus"))
	var effective_attack: float = attack_damage + attack_flat_bonus
		
	if is_instance_valid(weapon_sword):
		# 검은 기본 공격력의 1.25배 (근접 보너스)
		weapon_sword.damage = effective_attack * 1.25 * mult
	if is_instance_valid(weapon_bow):
		if weapon_bow.has_method("apply_owner_attack_damage"):
			weapon_bow.apply_owner_attack_damage(effective_attack * mult)
		else:
			weapon_bow.damage = effective_attack * mult


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
	var hand = get_node_or_null("HandPivot")
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
	var hand = get_node_or_null("HandPivot")
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
	team = new_team
	_update_team_color()

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
		
	# === 아군 홈그라운드(수비) 버프 로직 ===
	if team == "player" and current_state != State.DEAD:
		# 자신의 배(본선 또는 나포함)에 타고 있는지 확인
		var is_on_home_ground = (is_instance_valid(owned_ship) and owned_ship.get("team") == "player")
		
		if is_on_home_ground:
			# 1. 크리티컬 확률 상승 (기본 10% -> 25%)
			crit_chance = 0.25
			
			# 2. 체력 지속 재생 (초당 3)
			home_ground_timer -= delta
			if home_ground_timer <= 0:
				home_ground_timer = 1.0
				if current_health < max_health:
					current_health = minf(current_health + 3.0, max_health)
					# 체력 재생 시각 효과 (초록색 십자가 등, 힐링 파티클이 있다면)
					# 여기서는 간단히 조용히 회복만 처리하거나, 체력이 낮을 때만 회복했다고 표시
		else:
			# 적 배로 공격하러 갔을 때는 기본 크리티컬로 롤백
			crit_chance = 0.1
		
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
	if current_state != State.DEAD and run_combat_logic:
		var nearest = find_nearest_enemy()
		SoldierWeaponHelper.update_combat_weapon_choice(self, nearest)

		if current_state != State.ATTACK:
			_check_ranged_combat()
			_check_ship_capture_opportunity()


## IDLE 상태: 잠시 대기하다가 다시 배회
func _state_idle(delta: float, run_heavy_logic: bool) -> void:
	SoldierAiHelper.state_idle(self, delta, run_heavy_logic)


## WANDER 상태: 배 위를 랜덤하게 돌아다님 (움직이는 배 대응)
func _state_wander(_delta: float, run_heavy_logic: bool) -> void:
	SoldierAiHelper.state_wander(self, run_heavy_logic)


## 배회 시작: 새로운 로컬 목표점 설정
func _start_wander() -> void:
	SoldierAiHelper.start_wander(self)


## MOVE 상태 (적 추적)
func _state_move(_delta: float, _run_heavy_logic: bool) -> void:
	SoldierAiHelper.state_move(self)


## ATTACK 상태
func _state_attack(_delta: float) -> void:
	SoldierAiHelper.state_attack(self)


## 함선 또는 밧줄에 대한 특수 공격 (절단/나포)
func _perform_special_attack(target: Node3D) -> void:
	SoldierCombatHelper.perform_special_attack(self, target)

func _play_rope_hit_effects() -> void:
	SoldierCombatHelper.play_rope_hit_effects(self)

## 공격 실행
func _perform_attack() -> void:
	SoldierCombatHelper.perform_attack(self)


## 하얀색으로 깜빡임


## 가장 가까운 적 찾기 (탐지 범위 및 동일 함선 우선순위 적용)
func find_nearest_enemy() -> Node3D:
	if _nearest_enemy_cache_timer > 0.0 and is_instance_valid(_cached_nearest_enemy):
		return _cached_nearest_enemy
	return _refresh_nearest_enemy_cache(true)

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
