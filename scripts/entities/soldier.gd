extends CharacterBody3D
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const BOW_SCENE = preload("res://scenes/entities/weapons/weapon_bow.tscn")
const SURVIVOR_SCENE = preload("res://scenes/effects/survivor.tscn")
const MELEE_WEAPON_SCENES := [
	preload("res://scenes/entities/weapons/weapon_sword.tscn"),
	preload("res://scenes/entities/weapons/weapon_spear.tscn"),
	preload("res://scenes/entities/weapons/weapon_trident.tscn"),
	preload("res://scenes/entities/weapons/weapon_harpoon.tscn"),
]

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
@export var detection_range: float = 25.0 # 적 탐지 범위 (이 밖의 적은 무시)
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
@export var is_stationary: bool = false # 제자리 고정 (NavMesh 없는 배용)
@export var weapon_switch_distance: float = 4.0 # 무기 교체 거리 (이내면 검, 밖이면 활)하향 (10 -> 4)
@export var is_melee_only: bool = false ## 근접 무기만 사용 (백병전용)
@export var is_ranged_only: bool = false ## 원거리 무기만 사용 (포격 지원용)
@export var hit_effect_scene: PackedScene = preload("res://scenes/effects/hit_effect.tscn")

# === 내부 상태 ===
var current_health: float = 70.0
var current_state: State = State.IDLE
var current_target: Node3D = null
var current_weapon: Node3D = null
var attack_timer: float = 0.0
var wander_timer: float = 0.0
var wander_target_local: Vector3 = Vector3.ZERO # 배 기준 로컬 목표 지점
var decision_timer: float = 0.0 # 의사결정 스로틀링용
var home_ground_timer: float = 0.0 # 홈그라운드 체력 재생 타이머
var _is_jumping: bool = false # 점프/도선 중인지 여부

# 성능 최적화: UpgradeManager 캐싱
var _cached_upgrade_manager: Node = null
var _cached_cooldown_mult: float = 1.0

var weapon_sword: Node3D = null
var weapon_bow: Node3D = null

# 소속 배 및 매니저 참조
var owned_ship: Node3D = null
var home_ship: Node3D = null # 최초 소속된 플레이어 배 (나포함 침몰 시 복귀용)
var _cached_level_manager: Node = null
var last_nav_target_pos: Vector3 = Vector3.ZERO # 경로 갱신 최적화용

# === 도선 약탈 및 방화 (Boarding Chaos) 페널티 ===
var is_boarder_on_player_ship: bool = false
var chaos_duration_timer: float = 8.0 # 최대 8초간 약탈 후 도망감
var chaos_tick_timer: float = 0.0 # 1초마다 데미지 틱
var chaos_damage_per_tick: float = 5.0 # 상향: 초당 5의 화재 피해 (배 체력 비례)

const CROSS_SHIP_ENGAGE_MAX_DISTANCE: float = 10.0
const CROSS_SHIP_ENGAGE_SHIP_DISTANCE: float = 12.0
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
		_cached_soldiers = tree.get_nodes_in_group("soldiers")
		_last_soldier_cache_frame = f
	return _cached_soldiers

static func get_ships_cached(tree: SceneTree, team_name: String) -> Array:
	var f = Engine.get_physics_frames()
	if team_name == "player":
		if f != _last_player_cache_frame:
			_cached_player_ships = tree.get_nodes_in_group("player")
			_last_player_cache_frame = f
		return _cached_player_ships
	else:
		if f != _last_enemy_cache_frame:
			_cached_enemy_ships = tree.get_nodes_in_group("enemy")
			_last_enemy_cache_frame = f
		return _cached_enemy_ships


# 노드 참조 (이제 NavMesh를 사용하지 않습니다)


func _ready() -> void:
	# 영구 업그레이드 보너스 적용 (아군 전용)
	if team == "player":
		var _meta_manager_init = get_node_or_null("/root/MetaManager")
		if is_instance_valid(_meta_manager_init):
			var hp_mult := 1.0
			if _meta_manager_init.has_method("get_crew_stat_multiplier"):
				hp_mult *= float(_meta_manager_init.get_crew_stat_multiplier())
			if _meta_manager_init.has_method("get_crew_health_multiplier"):
				hp_mult *= float(_meta_manager_init.get_crew_health_multiplier())
			max_health *= hp_mult
			if _meta_manager_init.has_method("get_crew_defense_bonus"):
				defense += float(_meta_manager_init.get_crew_defense_bonus())
		
	current_health = max_health
	
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
		var sword_scene: PackedScene = MELEE_WEAPON_SCENES[randi() % MELEE_WEAPON_SCENES.size()]
		if sword_scene and hand:
			weapon_sword = sword_scene.instantiate() as Node3D
			hand.add_child(weapon_sword)
			
	# 활 로드 (Melee Only가 아닐 때만)
	if not is_melee_only:
		if BOW_SCENE and hand:
			weapon_bow = BOW_SCENE.instantiate() as Node3D
			hand.add_child(weapon_bow)
		
	# 공격력 수치 및 무기 상태 업데이트
	_update_weapon_stats()
		
	# 시작 무기 설정
	if is_melee_only:
		_set_active_weapon("sword")
	else:
		_set_active_weapon("bow") # General이나 Ranged Only는 활부터 시작
	
	# NavMeshAgent 관련 초기화 제거
	
	# 시작 시 랜덤 배회 시작
	_start_wander()
	_update_team_color()
	
	# AI 실행 시점 분산 (Staggering)
	decision_timer = randf_range(0.0, 0.2)
	
	# 그룹 수동 등록 (검색 정확도 향상)
	add_to_group("soldiers")
	
	# UpgradeManager 캐싱 및 시그널 연결 (매 프레임 노드 탐색 방지)
	_cached_upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(_cached_upgrade_manager):
		_update_cached_cooldown()
		if _cached_upgrade_manager.has_signal("upgrade_applied"):
			_cached_upgrade_manager.upgrade_applied.connect(_on_upgrade_applied)

func _on_upgrade_applied(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id == "crew_quality":
		_update_cached_cooldown()

func _update_cached_cooldown() -> void:
	if is_instance_valid(_cached_upgrade_manager) and "current_levels" in _cached_upgrade_manager:
		var quality_lv = _cached_upgrade_manager.current_levels.get("crew_quality", 0)
		_cached_cooldown_mult = maxf(0.5, 1.0 - 0.1 * quality_lv)

## 무기 공격력 수치 동기화
func _update_weapon_stats() -> void:
	var meta_manager = get_node_or_null("/root/MetaManager")
	var mult = 1.0
	if team == "player" and is_instance_valid(meta_manager):
		if meta_manager.has_method("get_crew_stat_multiplier"):
			mult *= float(meta_manager.get_crew_stat_multiplier())
		if meta_manager.has_method("get_crew_damage_multiplier"):
			mult *= float(meta_manager.get_crew_damage_multiplier())
		
	if is_instance_valid(weapon_sword):
		# 검은 기본 공격력의 1.25배 (근접 보너스)
		weapon_sword.damage = attack_damage * 1.25 * mult
	if is_instance_valid(weapon_bow):
		weapon_bow.damage = attack_damage * mult


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


func set_team(new_team: String) -> void:
	team = new_team
	_update_team_color()

func _update_team_color() -> void:
	var mesh_instance = $MeshInstance3D
	if mesh_instance:
		var mat = StandardMaterial3D.new()
		if team == "player":
			mat.albedo_color = Color(0.2, 0.4, 0.8) # Blue
		else:
			mat.albedo_color = Color(0.8, 0.2, 0.2) # Red
		mesh_instance.material_override = mat


func _physics_process(delta: float) -> void:
	# 바다에 빠지면 사망 (글로벌 Y < -5)
	if is_inside_tree() and global_position.y < -5.0:
		# 바다에 빠질 때 작은 물보라 이펙트 재생
		var water_explosion_scene = preload("res://scenes/effects/water_explosion.tscn")
		if water_explosion_scene:
			var explosion = water_explosion_scene.instantiate()
			var splash_pos = global_position
			splash_pos.y = 0.05
			# 아직 씬 트리에 없는 노드의 global_position을 설정하면 에러가 발생하므로 position 사용.
			# 루트에 담길 것이므로 position이 global_position과 동일함.
			explosion.position = splash_pos
			explosion.scale = Vector3(0.5, 0.5, 0.5) # 병사 크기에 맞게 축소
			get_tree().root.add_child.call_deferred(explosion)
			
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
			
		var throttle_time = 0.2 if ship_hp_ratio > 0.2 else 0.1
		
		# 플레이어와 멀리 떨어져 있으면(50m 이상) AI 주기를 대폭 늘림 (0.2s -> 0.8s)
		if dist_to_player > 50.0:
			throttle_time = 0.8
		elif dist_to_player > 30.0:
			throttle_time = 0.4
			
		decision_timer = throttle_time + randf_range(0.0, 0.05)
		run_heavy_logic = true
		
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
		if current_state == State.IDLE or current_state == State.ATTACK:
			move_and_slide()
		_keep_within_owned_ship_bounds()
			
	# 탈출(Evacuation) 체크: 소속된 나포함이 가라앉고 있으면 홈으로 복귀
	if run_heavy_logic and team == "player" and is_instance_valid(owned_ship) and owned_ship.get("is_dying") == true:
		_try_evacuate_to_home()
	
	# 공격 쿨다운 (캐싱된 업그레이드 수치 사용)
	var current_cooldown_mult = _cached_cooldown_mult
	
	if attack_timer > 0:
		# 원거리 무기면 쿨다운 감소 버프 적용
		if current_weapon and "max_range" in current_weapon:
			attack_timer -= delta * (1.0 / current_cooldown_mult)
		else:
			attack_timer -= delta
	
	# 원거리 사격 및 무기 스위칭 체크 (스로틀링)
	if run_heavy_logic and current_state != State.DEAD:
		var nearest = find_nearest_enemy()
		if nearest:
			var dist_xz = Vector2(global_position.x - nearest.global_position.x, global_position.z - nearest.global_position.z).length()
			var target_ship = nearest.get("owned_ship")
			var cross_ship_close = is_instance_valid(owned_ship) and is_instance_valid(target_ship) and target_ship != owned_ship and _is_ship_pair_in_melee_range(target_ship)
			if is_melee_only:
				_set_active_weapon("sword")
			elif is_ranged_only:
				_set_active_weapon("bow")
			elif cross_ship_close:
				# 인접한 적선과 난간전이 시작되면 월선보다 근접전을 우선한다.
				_set_active_weapon("sword")
			elif dist_xz <= weapon_switch_distance:
				_set_active_weapon("sword")
			else:
				_set_active_weapon("bow")
		else:
			# 적이 없으면 기본적으로 활을 들고 대기 (Melee Only만 검 유지)
			if is_melee_only:
				_set_active_weapon("sword")
			else:
				_set_active_weapon("bow")
			
		if current_state != State.ATTACK:
			_check_ranged_combat()
			_check_ship_capture_opportunity()


## IDLE 상태: 잠시 대기하다가 다시 배회
func _state_idle(delta: float, run_heavy_logic: bool) -> void:
	# 적 탐색 (스로틀링 적용)
	if run_heavy_logic:
		var enemy = find_nearest_enemy()
		if enemy:
			if is_stationary:
				current_target = enemy
				return
				
			current_target = enemy
			_change_state(State.MOVE)
			return

	# 배회 타이머 체크
	if wander_timer > 0:
		wander_timer -= delta
	else:
		_start_wander()


## WANDER 상태: 배 위를 랜덤하게 돌아다님 (움직이는 배 대응)
func _state_wander(_delta: float, run_heavy_logic: bool) -> void:
	# 적 탐색 (스로틀링 적용)
	if run_heavy_logic:
		var enemy = find_nearest_enemy()
		if enemy:
			if is_stationary:
				current_target = enemy
				_change_state(State.IDLE)
				return
				
			var dist = global_position.distance_to(enemy.global_position)
			if dist < 8.0:
				current_target = enemy
				_change_state(State.MOVE)
				return
	
	if not is_instance_valid(owned_ship):
		_change_state(State.IDLE)
		return
		
	# 1. 로컬 목표점을 현재 월드 좌표로 변환 (배가 움직이니까 매 프레임 갱신)
	var current_global_target = owned_ship.to_global(wander_target_local)
	
	# 2. 이동 로직 (직선 이동)
	var diff = current_global_target - global_position
	var wander_dist = diff.length()
	
	if wander_dist < 0.2:
		# 도착했으면 IDLE로 전환하여 잠시 대기
		wander_timer = randf_range(1.0, 3.0)
		_change_state(State.IDLE)
		return
		
	var direction = diff.normalized()
	velocity = direction * move_speed * 0.5 # 배회는 천천히
	move_and_slide()
	
	# 이동 방향 회전
	if direction.length_squared() > 0.01:
		var target_look = global_position + direction
		target_look.y = global_position.y # Y축 평면 유지
		if not global_position.is_equal_approx(target_look):
			look_at(target_look, Vector3.UP)


## 배회 시작: 새로운 로컬 목표점 설정
func _start_wander() -> void:
	if not is_instance_valid(owned_ship):
		return
	
	# 배의 갑판 범위 내에서 랜덤 좌표 생성 (로컬, 선체 크기 동기화)
	var half_ext = _get_ship_deck_half_extents(owned_ship)
	var random_x = randf_range(-half_ext.x, half_ext.x)
	var random_z = randf_range(-half_ext.y, half_ext.y)
	
	wander_target_local = Vector3(random_x, 0.0, random_z) # Y=0.0 (갑판 지면)
	_change_state(State.WANDER)


## MOVE 상태 (적 추적)
func _state_move(_delta: float, _run_heavy_logic: bool) -> void:
	# 고정형 병사는 이동하지 않음 (적 배 위에서 사격만 함)
	if is_stationary:
		_change_state(State.IDLE)
		return
	
	if not is_instance_valid(current_target):
		_change_state(State.IDLE)
		return

	# 타겟이 죽었거나 다른 배에 있으면 추적 중단
	if current_target.get("current_state") == State.DEAD:
		current_target = null
		_change_state(State.IDLE)
		return
		
	# 목표까지 거리 확인 (2D)
	var pos_self_2d = Vector2(global_position.x, global_position.z)
	var pos_target_2d = Vector2(current_target.global_position.x, current_target.global_position.z)
	var distance_xz = pos_self_2d.distance_to(pos_target_2d)
	
	if is_instance_valid(owned_ship) and current_target.get("owned_ship") != owned_ship:
		var target_ship = current_target.get("owned_ship")
		if not _is_ship_pair_in_melee_range(target_ship):
			_change_state(State.IDLE)
			return
		# 난간전 최대 교전 거리까지는 다른 배 적 추적 허용
		if distance_xz > CROSS_SHIP_ENGAGE_MAX_DISTANCE:
			_change_state(State.IDLE)
			return
	
	# 탐지 범위 밖이면 포기 (다른 배의 적 추적 방지)
	if distance_xz > detection_range:
		current_target = null
		_change_state(State.IDLE)
		return
	
	# 무기 사정거리 호출
	var attack_range = current_weapon.attack_range if current_weapon and "attack_range" in current_weapon else 1.2
	
	if distance_xz <= attack_range:
		# [Legacy] 타겟이 함선일 경우 수동 점프(도선) 시도 제거
		# 이제 함선(BaseShip)의 _transfer_one_soldier 로직에 의해서만 도선합니다.
		# if current_target.has_method("get_hull_ratio") and current_target != owned_ship:
		# 	_jump_to_ship(current_target, true)
		# 	_change_state(State.IDLE)
		# 	return
		_change_state(State.ATTACK)
		return
	
	# 직선 이동 (NavMesh 없이 물리 엔진만 사용)
	var target_pos = current_target.global_position
	var direction = (target_pos - global_position).normalized()
	velocity = direction * move_speed
	move_and_slide()
	
	if direction.length_squared() > 0.01:
		var target_look = global_position + direction
		target_look.y = global_position.y
		if not global_position.is_equal_approx(target_look):
			look_at(target_look, Vector3.UP)


## ATTACK 상태
func _state_attack(_delta: float) -> void:
	if not is_instance_valid(current_target):
		_change_state(State.IDLE)
		return
	
	# 타겟이 죽었거나 같은 팀이 되었으면(나포 등) IDLE로 전환
	if current_target.get("current_state") == State.DEAD or current_target.get("team") == team:
		current_target = null
		_change_state(State.IDLE)
		return
	
	var pos_self_2d = Vector2(global_position.x, global_position.z)
	var pos_target_2d = Vector2(current_target.global_position.x, current_target.global_position.z)
	var distance_xz = pos_self_2d.distance_to(pos_target_2d)
	
	var attack_range = current_weapon.attack_range if current_weapon and "attack_range" in current_weapon else 1.2
	var _attack_cooldown = current_weapon.attack_cooldown if current_weapon and "attack_cooldown" in current_weapon else 1.0
	
	# 사거리 벗어남 (1.2배 여유)
	if distance_xz > attack_range * 1.2:
		_change_state(State.MOVE)
		return
	
	# 타겟 바라보기
	look_at(Vector3(current_target.global_position.x, global_position.y, current_target.global_position.z), Vector3.UP)
	
		# 공격
	if attack_timer <= 0:
		# 타겟이 함선(Ship)일 경우 밧줄 공격 또는 나포 시도 분기
		if current_target.has_method("take_rope_damage") or current_target.has_method("get_hull_ratio"):
			_perform_special_attack(current_target)
		else:
			_perform_attack()
		attack_timer = current_weapon.attack_cooldown if current_weapon and "attack_cooldown" in current_weapon else 1.0


## 함선 또는 밧줄에 대한 특수 공격 (절단/나포)
func _perform_special_attack(target: Node3D) -> void:
	if not is_instance_valid(target): return
	
	# 수비 상황: 우리 배에 걸린 밧줄을 끊어야 하는 경우
	if is_instance_valid(owned_ship) and target == owned_ship.get("boarding_attacker"):
		if team == "player":
			# 밧줄 끊기 (우리 배의 밧줄 HP 깎음)
			if owned_ship.has_method("take_rope_damage"):
				owned_ship.take_rope_damage(attack_damage * 1.5) # 건물/밧줄엔 검술 보너스
				_play_rope_hit_effects()
				return
	
	# 공격 상황: 그냥 공격 (배 자체에는 데미지 주지 않음, 건너가기 위한 타겟팅용)
	# 병사 이동 로직에서 target이 ship이면 가까이 갔을 때 점프함
	_perform_attack()

func _play_rope_hit_effects() -> void:
	# 사운드 및 피격 이펙트 (밧줄 피격 느낌)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("impact_wood", global_position, randf_range(1.1, 1.3))
	
	# 파편 효과
	if is_instance_valid(hit_effect_scene):
		var effect = hit_effect_scene.instantiate()
		get_tree().root.add_child(effect)
		effect.global_position = global_position + (global_transform.basis.z * -1.0)

## 공격 실행
func _perform_attack() -> void:
	if not is_instance_valid(current_target): return
	
	if current_weapon and current_weapon.has_method("attack"):
		current_weapon.attack(current_target, self )
		
	# 시각적 피드백: 런지(Lunge) 애니메이션
	# 현재 바라보는 방향(Forward)으로 몸체를 잠깐 밈
	var _original_transform = $MeshInstance3D.transform
	var tween = create_tween()
	tween.tween_property($MeshInstance3D, "position:z", -0.5, 0.1).as_relative()
	tween.tween_property($MeshInstance3D, "position:z", 0.5, 0.1).as_relative()
	
	# 무기도 휘두르기 (HandPivot)
	var hand_pivot = get_node_or_null("HandPivot")
	if hand_pivot:
		var w_tween = create_tween()
		w_tween.set_parallel(true)
		# 원거리 무기가 아니면 회전
		if current_weapon and not "max_range" in current_weapon:
			w_tween.tween_property(hand_pivot, "rotation:x", -deg_to_rad(60), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			w_tween.tween_property(hand_pivot, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
			
			w_tween.chain().set_parallel(true)
			w_tween.tween_property(hand_pivot, "rotation:x", 0.0, 0.2)
			w_tween.tween_property(hand_pivot, "scale", Vector3.ONE, 0.2)
		else:
			# 활 등 원거리 무기면 반동 느낌
			w_tween.tween_property(hand_pivot, "position:z", 0.2, 0.1).as_relative()
			w_tween.chain().tween_property(hand_pivot, "position:z", -0.2, 0.2).as_relative()


## 하얀색으로 깜빡임


## 가장 가까운 적 찾기 (탐지 범위 및 동일 함선 우선순위 적용)
func find_nearest_enemy() -> Node3D:
	var all_soldiers = get_soldiers_cached(get_tree())
	var nearest_on_ship: Node3D = null
	var nearest_distance_on_ship: float = INF
	
	var nearest_global: Node3D = null
	var nearest_distance_global: float = INF
	
	var detection_range_sq = detection_range * detection_range
	
	for other in all_soldiers:
		if other == self or not is_instance_valid(other):
			continue
		
		# 죽은 적 무시
		if other.get("current_state") == State.DEAD:
			continue

		# 같은 팀이면 무시
		if other.get("team") == team:
			continue
			
		var other_ship = other.get("owned_ship")
		
		# [최적화] Broad-phase Culling: 상대가 다른 배에 타고 있는데 두 배가 멀면 스킵 (2D 기준)
		if is_instance_valid(owned_ship) and is_instance_valid(other_ship) and owned_ship != other_ship:
			var ship_diff_xz = Vector2(owned_ship.global_position.x - other_ship.global_position.x, owned_ship.global_position.z - other_ship.global_position.z)
			if ship_diff_xz.length_squared() > 1600.0: # 40m 기준 (충분히 넉넉하게)
				continue
		
		var pos_diff_xz = Vector2(global_position.x - other.global_position.x, global_position.z - other.global_position.z)
		var dist_sq_xz = pos_diff_xz.length_squared()
		if dist_sq_xz > detection_range_sq:
			continue
		
		# 1. 동일 함선(`owned_ship`)에 있는 적 체크
		if is_instance_valid(owned_ship) and other_ship == owned_ship:
			if dist_sq_xz < nearest_distance_on_ship:
				nearest_distance_on_ship = dist_sq_xz
				nearest_on_ship = other
		
		# 2. 전역 탐지 범위 체크
		# - 원거리 병사나 사거리 긴 무기는 항시 전역 탐지 허용
		# - 근거리 병사도 배가 인접해 있으면(난간전 가능 거리) 다른 배의 적을 인지하도록 함
		var is_ranged = is_ranged_only or (current_weapon and current_weapon.get("max_range") != null and current_weapon.get("max_range") > 5.0)
		var can_cross_ship_engage = false
		if is_instance_valid(owned_ship) and is_instance_valid(other_ship) and owned_ship != other_ship:
			can_cross_ship_engage = _is_ship_pair_in_melee_range(other_ship) and dist_sq_xz < (CROSS_SHIP_ENGAGE_MAX_DISTANCE * CROSS_SHIP_ENGAGE_MAX_DISTANCE)
		else:
			can_cross_ship_engage = dist_sq_xz < 16.0 # 같은 배는 기존 근접 우선 기준 유지
		
		if is_ranged or can_cross_ship_engage:
			if dist_sq_xz < nearest_distance_global:
				nearest_distance_global = dist_sq_xz
				nearest_global = other
	
	# [중요] 근접 공격용 타겟 우선순위: 같은 배 우선 -> 아주 가까운 전역 적
	if is_melee_only:
		return nearest_on_ship if nearest_on_ship else nearest_global
		
	# 원거리 가용 시: 같은 배 우선, 없으면 전역 적
	return nearest_on_ship if nearest_on_ship else nearest_global

## 전이 로직은 통제됨 (개별 나포 기회 체크 삭제)
func _check_ship_capture_opportunity() -> void:
	return

func _is_ship_pair_in_melee_range(other_ship: Node3D) -> bool:
	if not is_instance_valid(owned_ship) or not is_instance_valid(other_ship):
		return false
	var ship_diff_xz = Vector2(owned_ship.global_position.x - other_ship.global_position.x, owned_ship.global_position.z - other_ship.global_position.z)
	return ship_diff_xz.length_squared() <= (CROSS_SHIP_ENGAGE_SHIP_DISTANCE * CROSS_SHIP_ENGAGE_SHIP_DISTANCE)

## 홈으로 긴급 복귀 (배가 가라앉을 때)
func _try_evacuate_to_home() -> void:
	if not is_instance_valid(home_ship) or home_ship == owned_ship: return
	
	var dist = global_position.distance_to(home_ship.global_position)
	if dist < 12.0: # 12미터 이내면 점프해서 복귀
		_jump_to_ship(home_ship)
	else:
		# 너무 멀면 수영 상태는 아직 없으므로 일단 텔레포트 (긴급 구조 애니메이션)
		_teleport_to_ship(home_ship)

func _jump_to_ship(target_ship: Node3D, is_capture_attempt: bool = false) -> void:
	var target_soldiers = target_ship.get_node_or_null("Soldiers")
	if not target_soldiers: target_soldiers = target_ship
	
	_is_jumping = true
	var d_h = target_ship.get("deck_height") if "deck_height" in target_ship else 0.4
	var target_half_ext = _get_ship_deck_half_extents(target_ship)
	var jump_offset = Vector3(
		randf_range(-target_half_ext.x, target_half_ext.x),
		d_h,
		randf_range(-target_half_ext.y, target_half_ext.y)
	)
	
	# === 밧줄(Grappling Hook) 이펙트 ===
	# [Legacy] 개별 병사가 밧줄을 생성하던 로직 제거 (이제 BaseShip에서 중앙 관리함)
	# reparent 시 global_position을 유지하도록 보정
	var start_glob = global_position
	reparent(target_soldiers)
	global_position = start_glob
	
	owned_ship = target_ship
	
	var start_local_pos = position
	var start_local_y = start_local_pos.y
	
	# 수평 이동 거리 계산 (reparent 후 로컬 좌표 기준)
	var horiz_dist = Vector2(start_local_pos.x - jump_offset.x, start_local_pos.z - jump_offset.z).length()
	# 점프 높이를 수평 거리에 비례하게 설정 (최소 2.5, 거리의 40%)
	var jump_height = maxf(2.5, horiz_dist * 0.4)
	# 이동 시간도 거리에 맞게 조절 (최소 0.6초, 최대 1.0초)
	var travel_time = clampf(horiz_dist / 15.0, 0.6, 1.0)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self , "position:x", jump_offset.x, travel_time)
	tween.tween_property(self , "position:z", jump_offset.z, travel_time)
	
	var y_tween = create_tween()
	y_tween.tween_property(self , "position:y", start_local_y + jump_height, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(self , "position:y", jump_offset.y, travel_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	y_tween.finished.connect(func(): _is_jumping = false)
	
	# 도선 시 타이머 리셋 (적군이 플레이어 배로 넘어갈 때)
	if team == "enemy" and is_instance_valid(target_ship) and target_ship.get("team") == "player":
		chaos_duration_timer = 8.0 # 최대 8초 생존 허용
		chaos_tick_timer = 1.0 # 1초 후 첫 틱
	
	if is_capture_attempt:
		tween.finished.connect(func():
			if is_instance_valid(target_ship):
				target_ship.set_meta("being_boarded", false)
		)
	
	if not is_capture_attempt:
		print("[Critical] 함선 침몰! 플레이어 본선으로 긴급 복귀합니다.")

func _teleport_to_ship(_target_ship: Node3D) -> void:
	# 텔레포트 대신 → Survivor(생존자)로 변환하여 바다에 떠있게 함
	if SURVIVOR_SCENE:
		var survivor = SURVIVOR_SCENE.instantiate()
		get_tree().root.add_child.call_deferred(survivor)
		var spawn_pos = global_position
		spawn_pos.y = 0.5 # 수면 높이
		survivor.set_deferred("global_position", spawn_pos)
		print("[Rescue] 병사가 바다에 빠져 생존자가 되었습니다!")
	queue_free()

func _keep_within_owned_ship_bounds() -> void:
	if not is_instance_valid(owned_ship):
		return
		
	var d_height = owned_ship.get("deck_height") if "deck_height" in owned_ship else 0.4
	if position.y != d_height:
		position.y = d_height
		
	var half_ext = _get_ship_deck_half_extents(owned_ship)
	position.x = clampf(position.x, -half_ext.x, half_ext.x)
	position.z = clampf(position.z, -half_ext.y, half_ext.y)

func _get_ship_deck_half_extents(ship: Node3D) -> Vector2:
	if is_instance_valid(ship) and ship.has_method("get_deck_half_extents"):
		var ext = ship.call("get_deck_half_extents")
		if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
			return ext
			
	var radius = ship.get("base_collision_radius") if "base_collision_radius" in ship else 4.5
	var w_mult = ship.get("width_multiplier") if "width_multiplier" in ship else 1.0
	var l_mult = ship.get("length_multiplier") if "length_multiplier" in ship else 1.0
	return Vector2(
		maxf(0.4, radius * w_mult * 0.85),
		maxf(0.8, radius * l_mult * 0.85)
	)

## 데미지 받기
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if current_state == State.DEAD:
		return
	
	# 방어력 적용 (최소 1 데미지)
	var mitigated_damage = maxf(amount - defense, 1.0)
	var quality_reduction = 0.0
	if has_meta("defense_reduction"):
		quality_reduction = clampf(float(get_meta("defense_reduction")), 0.0, 0.9)
	var cover_reduction = _get_ship_ranged_cover_reduction(damage_source)
	var total_reduction = clampf(quality_reduction + cover_reduction, 0.0, 0.9)
	var final_damage = maxf(mitigated_damage * (1.0 - total_reduction), 1.0)
	current_health -= final_damage
	
	# 플레이어 무기 피해 집계: 적 병사에만 기록
	if not damage_source.is_empty() and team == "enemy":
		if _cached_level_manager and _cached_level_manager.has_method("add_player_weapon_damage"):
			_cached_level_manager.add_player_weapon_damage(damage_source, final_damage)
	
	# 피격 사운드
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("soldier_hit", global_position, randf_range(0.9, 1.1))
	
	# 시각적 피드백
	_flash_hit()
	_spawn_hit_effect(hit_position)
	
	# 물리적 피드백: 넉백
	if hit_position != Vector3.ZERO:
		var knockback_dir = (global_position - hit_position).normalized()
		knockback_dir.y = 0
		velocity += knockback_dir * 3.0
		
		# 보복(Retaliation) 로직: 맞은 적을 즉시 타겟팅 시도 (현재 타겟이 없거나 먼 경우)
		if current_state != State.DEAD and (not is_instance_valid(current_target) or randf() < 0.3):
			# 근처의 적 병사를 탐색하여 타겟 갱신 (보복성)
			var attacker_soldier = find_nearest_enemy() # 위에서 개편한 logic 사용
			if attacker_soldier:
				current_target = attacker_soldier
				if current_state == State.IDLE or current_state == State.WANDER:
					_change_state(State.MOVE)
	
	if current_health <= 0:
		_die()

func _get_ship_ranged_cover_reduction(damage_source: String) -> float:
	if damage_source.is_empty():
		return 0.0
	if not RANGED_DAMAGE_SOURCES.has(damage_source):
		return 0.0
	if not is_instance_valid(owned_ship):
		return 0.0
	if owned_ship.get("is_sinking") == true or owned_ship.get("is_dying") == true:
		return 0.0
	# 같은 함선 소속 병사만 엄폐 보너스 적용 (적 도선병은 제외)
	if str(owned_ship.get("team")) != team:
		return 0.0
	if not owned_ship.has_meta("crew_ranged_damage_reduction"):
		return 0.0
	return clampf(float(owned_ship.get_meta("crew_ranged_damage_reduction")), 0.0, 0.6)


## 피격 시 하얀색으로 깜빡임
func _flash_hit(flash_color: Color = Color.WHITE) -> void:
	var mesh = $MeshInstance3D
	if not mesh: return
	
	var tween = create_tween()
	# 하얀색으로 블렌딩 (StandardMaterial3D의 emission을 활용하거나 albedo 조절)
	
	mesh.material_override.emission_enabled = true
	mesh.material_override.emission = flash_color
	mesh.material_override.emission_energy_multiplier = 2.0
	
	tween.tween_property(mesh.material_override, "emission_energy_multiplier", 0.0, 0.1)
	tween.finished.connect(func(): if mesh.material_override: mesh.material_override.emission_enabled = false)

## 적군 도선병 약탈 및 방화 처리 (초당 DoT 데미지)
func _update_boarding_chaos(delta: float) -> void:
	if not is_instance_valid(owned_ship) or not owned_ship.has_method("take_fire_damage"): return
	
	# 내 배에 살아있는 아군 병사가 있는지 확인
	var has_defenders = false
	var soldiers_node = owned_ship.get_node_or_null("Soldiers")
	if soldiers_node:
		for s in soldiers_node.get_children():
			if s.get("team") == "player" and s.get("current_state") != State.DEAD:
				has_defenders = true
				break
				
	# 아군 병사가 남아있다면 방화 효과 중지 (전투 우선)
	if has_defenders:
		return
		
	# 방화 및 약탈 시작
	chaos_duration_timer -= delta
	chaos_tick_timer -= delta
	
	if chaos_tick_timer <= 0:
		chaos_tick_timer = 1.0 # 1초마다 데미지
		owned_ship.take_damage(chaos_damage_per_tick, global_position)
		owned_ship.take_fire_damage(chaos_damage_per_tick, 1.0)
		
		# 시각/청각 피드백: 불꽃 튀는 소리 등
		var audio_manager = get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("impact_wood", global_position, randf_range(1.1, 1.4), -5.0) # 작은 파괴 효과음
			
	# 제한 시간이 지나면 철수 (바다로 도망침)
	if chaos_duration_timer <= 0:
		print("[Combat] 적군이 방화를 마치고 뱃머리에서 뛰어내려 도망칩니다!")
		_teleport_to_ship(null) # 바다(생존자)로 변환하거나 삭제 처리

## 피격 파티클 생성
func _spawn_hit_effect(hit_pos: Vector3) -> void:
	if not hit_effect_scene: return
	var effect = hit_effect_scene.instantiate()
	get_tree().root.add_child(effect)
	
	if hit_pos == Vector3.ZERO:
		effect.global_position = global_position + Vector3(0, 0.8, 0)
	else:
		# 피격 위치에서 약간 띄움 (바닥 뚫림 방지) + 미세 랜덤 오프셋
		var rand_offset = Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1))
		effect.global_position = hit_pos + rand_offset
	
	if effect is GPUParticles3D:
		effect.emitting = true

## 휘두르기 이펙트 생성 (이 메서드는 이제 Weapon 씬 자체에서 관리하므로 빈칸)
func _spawn_slash_effect() -> void:
	pass

## 체력 100% 회복 (나포 보상 등)
func heal_full() -> void:
	if current_state != State.DEAD:
		current_health = max_health
		# (추후 힐링 파티클 이펙트를 여기에 추가할 수 있습니다)

## 사망 처리
func _die() -> void:
	current_state = State.DEAD
	
	# [최적화] 사망 시 배의 폐선 여부 체크 이벤트 트리거 (중복 방지를 방어적으로 처리)
	if is_instance_valid(home_ship) and home_ship.has_method("check_derelict_status"):
		home_ship.call_deferred("check_derelict_status")
	
	# XP 부여 (적군일 경우에만)
	if team == "enemy":
		if _cached_level_manager and _cached_level_manager.has_method("add_xp"):
			_cached_level_manager.add_xp(5) # 병사 처치 XP 상향 (2 -> 5)
		if _cached_level_manager and _cached_level_manager.has_method("add_soldier_kill"):
			_cached_level_manager.add_soldier_kill(1)
		if _cached_level_manager:
			if _cached_level_manager.has_method("add_command_xp_from_soldier_kill"):
				_cached_level_manager.add_command_xp_from_soldier_kill(1)
			elif _cached_level_manager.has_method("add_merit"):
				# 하위 호환: 메서드가 없는 경우 직접 공적(지휘 포인트) 1 지급
				_cached_level_manager.add_merit(1)
	
	# 사망 사운드 및 바다로 떨어지는 물보라 소리
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("soldier_die", global_position)
		# 데드 후 약간의 시간 차를 두고 물보라(풍덩) 소리 재생
		get_tree().create_timer(randf_range(0.3, 0.6)).timeout.connect(func():
			var delay_am = get_node_or_null("/root/AudioManager")
			if is_instance_valid(delay_am) and delay_am.has_method("play_sfx"):
				delay_am.play_sfx("water_splash_small", global_position, randf_range(0.8, 1.2))
		)
	
	# 비활성화 및 그룹에서 제거 (타켓팅 방지)
	set_physics_process(false)
	if is_in_group("soldiers"):
		remove_from_group("soldiers")
	if is_in_group("enemy"):
		remove_from_group("enemy")
	
	# 충돌 비활성화 (물리 처리 중이므로 set_deferred 사용)
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", true)
	
	visible = false
	# queue_free()


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
	# 근접 병사면 제외
	if not current_weapon or not "max_range" in current_weapon:
		return
		
	var attack_cooldown = current_weapon.attack_cooldown if "attack_cooldown" in current_weapon else 2.0
	
	if attack_timer > 0: return
	
	var target = _find_ranged_target()
	if target:
		current_target = target
		_perform_attack()
		attack_timer = attack_cooldown

func _find_ranged_target() -> Node3D:
	var max_range = current_weapon.attack_range if current_weapon and "attack_range" in current_weapon else 20.0
	
	# 1. 병사 탐색: find_nearest_enemy()의 개선된 로직(갑판 우선)을 그대로 활용
	var nearest = find_nearest_enemy()
	if is_instance_valid(nearest):
		var dist_xz = Vector2(global_position.x - nearest.global_position.x, global_position.z - nearest.global_position.z).length()
		if dist_xz <= max_range:
			return nearest
	
	# 2. 함선 탐색: 병사가 없을 경우에만 함선 타겟팅 (기존 로직 유지)
	var enemy_team = "enemy" if team == "player" else "player"
	var ships = get_ships_cached(get_tree(), enemy_team)
	
	# 함대 정원 체크 (나포 가능 여부)
	var minions = SceneGroupCache.get_nodes(get_tree(), "captured_minion")
	var has_room = minions.size() < 3
	
	for ship in ships:
		# ✅ 나포 가능하면 자기가 서 있는 배는 쏘지 않음 (나포 기회 보장)
		if ship == owned_ship and has_room:
			continue
			
		var dist_xz = Vector2(global_position.x - ship.global_position.x, global_position.z - ship.global_position.z).length()
		if dist_xz < max_range:
			return ship
			
	return null

func _perform_range_attack(_target: Node3D) -> void:
	pass
