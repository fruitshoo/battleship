extends CharacterBody3D

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


# 노드 참조
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null


func _ready() -> void:
	# 영구 업그레이드 보너스 적용 (아군 전용)
	if team == "player":
		var _meta_manager_init = get_node_or_null("/root/MetaManager")
		if is_instance_valid(_meta_manager_init) and _meta_manager_init.has_method("get_crew_stat_multiplier"):
			var hp_mult = _meta_manager_init.get_crew_stat_multiplier()
			max_health *= hp_mult
		
	current_health = max_health
	
	# 부모 노드 구조에 따라 배 참조 찾기
	# 구조: Ship -> Soldiers -> Soldier
	var parent = get_parent()
	if parent and parent.name == "Soldiers":
		owned_ship = parent.get_parent()
	elif parent and parent.has_method("get_wind_strength"): # Ship 스크립트 체크
		owned_ship = parent
		
	if team == "player":
		home_ship = owned_ship # 플레이어 진영일 때만 홈 저장
	
	_cached_level_manager = get_tree().root.find_child("LevelManager", true, false)
			
	if not has_node("HandPivot"):
		var pivot = Node3D.new()
		pivot.name = "HandPivot"
		# 캐릭터 오른손 위치
		pivot.position = Vector3(0.3, 0.7, -0.15)
		add_child(pivot)
		
	# 무기 생성 (근접 무기 4종 중 랜덤 1개 + 활)
	var melee_scenes = [
		"res://scenes/entities/weapons/weapon_sword.tscn",
		"res://scenes/entities/weapons/weapon_spear.tscn",
		"res://scenes/entities/weapons/weapon_trident.tscn",
		"res://scenes/entities/weapons/weapon_harpoon.tscn"
	]
	var random_melee_path = melee_scenes[randi() % melee_scenes.size()]
	var sword_scene = load(random_melee_path)
	var bow_scene = load("res://scenes/entities/weapons/weapon_bow.tscn")
	
	if sword_scene:
		weapon_sword = sword_scene.instantiate() as Node3D
		# 수동 생성 노드가 아닐 경우 대비 (HandPivot이 없는 구버전 배 하위 호환)
		var hand = get_node_or_null("HandPivot")
		if hand:
			hand.add_child(weapon_sword)
	if bow_scene:
		weapon_bow = bow_scene.instantiate() as Node3D
		$HandPivot.add_child(weapon_bow)
		
	# 공격력 수치 및 무기 상태 업데이트
	_update_weapon_stats()
		
	# 시작은 무조건 원거리(활)로 세팅 (함선간 교전부터 시작하므로)
	_set_active_weapon("bow")
	
	if nav_agent:
		nav_agent.max_speed = move_speed
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
	
	# 시작 시 랜덤 배회 시작
	_start_wander()
	_update_team_color()
	
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
	if team == "player" and is_instance_valid(meta_manager) and meta_manager.has_method("get_crew_stat_multiplier"):
		mult = meta_manager.get_crew_stat_multiplier()
		
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
			
		_die()
		return
	
	# 고정형(is_stationary) 병사는 AI 로직 실행하지 않음 — 사격만 함
	if is_stationary:
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
			
		var throttle_time = 0.2 if ship_hp_ratio > 0.2 else 0.1
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
		# 다이나믹 무기 스위칭: 가장 가까운 적을 찾아 거리에 따라 무기 변경
		var nearest = find_nearest_enemy()
		if nearest:
			var dist = global_position.distance_to(nearest.global_position)
			if dist <= weapon_switch_distance:
				_set_active_weapon("sword")
			else:
				_set_active_weapon("bow")
		else:
			# 적이 없으면 기본적으로 검을 들고 대기 (또는 활 유지)
			_set_active_weapon("sword")
			
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
	
	# 2. 이동 로직
	if nav_agent:
		# 부하 경감을 위해 목표가 크게 바뀌었을 때만 경로 갱신 (또는 주기적으로)
		if current_global_target.distance_to(last_nav_target_pos) > 0.5:
			nav_agent.target_position = current_global_target
			last_nav_target_pos = current_global_target
		
		if nav_agent.is_navigation_finished():
			# 도착했으면 IDLE로 전환하여 잠시 대기
			wander_timer = randf_range(1.0, 3.0)
			_change_state(State.IDLE)
			return
			
		# 다음 경로점 이동
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		velocity = direction * move_speed
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
	
	# 배의 갑판 범위 내에서 랜덤 좌표 생성 (로컬)
	# 갑판 크기: X(-1.25 ~ 1.25), Z(-3.75 ~ 3.75)
	# 여유를 두고 약간 안쪽으로 잡음
	var random_x = randf_range(-1.0, 1.0)
	var random_z = randf_range(-3.0, 3.0)
	
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

	# 타겟이 죽었으면 IDLE로 전환
	if current_target.get("current_state") == State.DEAD:
		current_target = null
		_change_state(State.IDLE)
		return
	
	# 목표까지 거리 확인
	var distance = global_position.distance_to(current_target.global_position)
	
	# 탐지 범위 밖이면 포기 (다른 배의 적 추적 방지)
	if distance > detection_range:
		current_target = null
		_change_state(State.IDLE)
		return
	
	# 무기 사정거리 호출
	var attack_range = current_weapon.attack_range if current_weapon and "attack_range" in current_weapon else 1.2
	
	if distance <= attack_range:
		_change_state(State.ATTACK)
		return
	
	# NavMesh를 통한 이동
	if nav_agent:
		var target_pos = current_target.global_position
		
		# 대상이 NavMesh 위에 정확히 있지 않을 수 있으므로, 단순 직선 거리로 닫힐 수 있으면 이동 시도
		if distance <= attack_range * 1.5:
			var direction = (target_pos - global_position).normalized()
			velocity = direction * move_speed
			move_and_slide()
			
			if direction.length_squared() > 0.01:
				var target_look = global_position + direction
				target_look.y = global_position.y
				if not global_position.is_equal_approx(target_look):
					look_at(target_look, Vector3.UP)
			return
			
		if target_pos.distance_to(last_nav_target_pos) > 1.0:
			nav_agent.target_position = target_pos
			last_nav_target_pos = target_pos
		
		if not nav_agent.is_navigation_finished():
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
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
	
	# 타겟이 죽었으면 IDLE로 전환
	if current_target.get("current_state") == State.DEAD:
		current_target = null
		_change_state(State.IDLE)
		return
	
	var distance = global_position.distance_to(current_target.global_position)
	
	var attack_range = current_weapon.attack_range if current_weapon and "attack_range" in current_weapon else 1.2
	var attack_cooldown = current_weapon.attack_cooldown if current_weapon and "attack_cooldown" in current_weapon else 1.0
	
	# 사거리 벗어남
	if distance > attack_range * 1.2:
		_change_state(State.MOVE)
		return
	
	# 타겟 바라보기
	look_at(Vector3(current_target.global_position.x, global_position.y, current_target.global_position.z), Vector3.UP)
	
		# 공격
	if attack_timer <= 0:
		_perform_attack()
		attack_timer = current_weapon.attack_cooldown if current_weapon and "attack_cooldown" in current_weapon else 1.0


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
	
	for other in all_soldiers:
		if other == self or not is_instance_valid(other):
			continue
		
		# 죽은 적 무시
		if other.get("current_state") == State.DEAD:
			continue

		# 같은 팀이면 무시
		if other.get("team") == team:
			continue
		
		var distance = global_position.distance_to(other.global_position)
		
		# 1. 동일 함선(`owned_ship`)에 있는 적 체크
		if is_instance_valid(owned_ship) and other.get("owned_ship") == owned_ship:
			if distance < nearest_distance_on_ship:
				nearest_distance_on_ship = distance
				nearest_on_ship = other
		
		# 2. 전역 탐지 범위 체크
		if distance <= detection_range:
			if distance < nearest_distance_global:
				nearest_distance_global = distance
				nearest_global = other
				
	# 같은 배 위에 적이 있다면 거리와 상관없이 우선 반환 (갑판 전투 우선)
	if nearest_on_ship:
		return nearest_on_ship
		
	# 같은 배 위에 적이 없으면 가장 가까운 전역 적 반환
	return nearest_global

## 나포 기회 확인
func _check_ship_capture_opportunity() -> void:
	# 아군 병사가 아닐 경우 무시
	if team != "player": return
	if not is_instance_valid(owned_ship): return
	
	# 상황 1: 이미 적선 위에 올라탄 경우 (기존 나포 트리거)
	if owned_ship.is_in_group("enemy") and not owned_ship.is_in_group("player"):
		# 해당 배에 살아있는 적군이 있는지 확인
		var enemy_count = 0
		var soldiers_node = owned_ship.get_node_or_null("Soldiers")
		if soldiers_node:
			for child in soldiers_node.get_children():
				if child.get("team") == "enemy" and child.get("current_state") != State.DEAD:
					enemy_count += 1
					
		# 적군이 한 명도 없으면 나포 실행
		if enemy_count == 0:
			# [추가] 만약 이 배의 선원들이 다른 배(보통 플레이어 배)로 도선 중이라면, 그곳의 적들도 소탕해야 함
			var b_target = owned_ship.get("boarding_target")
			if is_instance_valid(b_target):
				var target_soldiers = b_target.get_node_or_null("Soldiers")
				var has_active_boarders = false
				if target_soldiers:
					for boarder in target_soldiers.get_children():
						# 원래 적팀(enemy)이었던 병사가 타겟 배 위에 살아있는지 확인
						if boarder.get("team") == "enemy" and boarder.get("current_state") != State.DEAD:
							has_active_boarders = true
							break
				
				if has_active_boarders:
					# 아직 플레이어 배 위에 적이 남아있으므로 나포를 보류함
					return

			if owned_ship.has_method("capture_ship"):
				owned_ship.capture_ship()
			elif owned_ship.has_method("capture_derelict_ship"):
				owned_ship.capture_derelict_ship()
		return # 이미 다른 배 위이므로 아래 로직(주변 배 찾기)은 실행 않음

	# 상황 2: 본선 혹은 아군 함선에 있으면서, 주변의 비어있는 적선(폐선) 탐색하여 뛰어들기
	if owned_ship.is_in_group("player"):
		# [핵심] 갑판 방어 우선: 내 배에 적군이 침투해 백병전이 진행 중이거나, 아군 병사가 나 혼자라면 나포를 보류함
		var in_combat = false
		var alive_friends_count = 0
		var own_soldiers = owned_ship.get_node_or_null("Soldiers")
		if own_soldiers:
			for c in own_soldiers.get_children():
				if c.get("current_state") != State.DEAD:
					if c.get("team") != team:
						in_combat = true
						break
					elif c.get("team") == team:
						alive_friends_count += 1
		
		if in_combat or alive_friends_count <= 1:
			return # 백병전 방어에 집중 (표적 탐색 중단) 또는 배를 지키기 위해 잔류
			
		var enemy_ships = get_ships_cached(get_tree(), "enemy")
		for ship in enemy_ships:
			# 폐선 상태이고 나포되지 않은 배인 경우
			if ship.get("is_derelict") == true and not ship.is_in_group("player"):
				var dist = global_position.distance_to(ship.global_position)
				if dist < 12.0:
					# 중복 방지: 이미 그 배로 뛰어드는 중인 동료가 있는지 확인
					# (배의 메타데이터나 특정 플래그를 활용)
					if ship.get_meta("being_boarded", false):
						continue
					
					# 이미 배 위에 누군가 타고 있는지 확인
					var p_count = 0
					var s_node = ship.get_node_or_null("Soldiers")
					if s_node:
						for c in s_node.get_children():
							if c.get("team") == "player" and c.get("current_state") != State.DEAD:
								p_count += 1
					
					if p_count == 0:
						# 나포 결정!
						ship.set_meta("being_boarded", true)
						print("[Action] 빈 배 발견! 나포를 위해 뛰어듭니다.")
						_jump_to_ship(ship, true) # 나포용 점프
						return # 한 번에 한 척만 타겟팅

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
	
	reparent(target_soldiers)
	owned_ship = target_ship
	
	var start_local_y = position.y
	var jump_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-2.0, 2.0))
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self , "position:x", jump_offset.x, 0.6)
	tween.tween_property(self , "position:z", jump_offset.z, 0.6)
	
	var y_tween = create_tween()
	y_tween.tween_property(self , "position:y", start_local_y + 2.5, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(self , "position:y", jump_offset.y, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 도선 시 타이머 리셋 (적군이 플레이어 배로 넘어갈 때)
	if team == "enemy" and is_instance_valid(target_ship) and target_ship.get("team") == "player":
		chaos_duration_timer = 8.0 # 최대 8초 생존 허용
		chaos_tick_timer = 1.0 # 1초 후 첫 틱
	
	if is_capture_attempt:
		tween.finished.connect(func():
			if is_instance_valid(target_ship):
				target_ship.set_meta("being_boarded", false)
				_check_ship_capture_opportunity() # 착지 후 즉시 나포 체크
		)
	
	if not is_capture_attempt:
		print("[Critical] 함선 침몰! 플레이어 본선으로 긴급 복귀합니다.")

func _teleport_to_ship(_target_ship: Node3D) -> void:
	# 텔레포트 대신 → Survivor(생존자)로 변환하여 바다에 떠있게 함
	var survivor_scn = load("res://scenes/effects/survivor.tscn")
	if survivor_scn:
		var survivor = survivor_scn.instantiate()
		get_tree().root.add_child.call_deferred(survivor)
		var spawn_pos = global_position
		spawn_pos.y = 0.5 # 수면 높이
		survivor.set_deferred("global_position", spawn_pos)
		print("[Rescue] 병사가 바다에 빠져 생존자가 되었습니다!")
	queue_free()

## 데미지 받기
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.DEAD:
		return
	
	# 방어력 적용 (최소 1 데미지)
	var final_damage = maxf(amount - defense, 1.0)
	current_health -= final_damage
	
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
	
	# XP 부여 (적군일 경우에만)
	if team == "enemy":
		if _cached_level_manager and _cached_level_manager.has_method("add_xp"):
			_cached_level_manager.add_xp(5) # 병사 처치 XP 상향 (2 -> 5)
	
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
func move_to_position(target_pos: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = target_pos
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
		var dist = global_position.distance_to(nearest.global_position)
		if dist <= max_range:
			return nearest
	
	# 2. 함선 탐색: 병사가 없을 경우에만 함선 타겟팅 (기존 로직 유지)
	var enemy_team = "enemy" if team == "player" else "player"
	var ships = get_ships_cached(get_tree(), enemy_team)
	
	# 함대 정원 체크 (나포 가능 여부)
	var minions = get_tree().get_nodes_in_group("captured_minion")
	var has_room = minions.size() < 2
	
	for ship in ships:
		# ✅ 나포 가능하면 자기가 서 있는 배는 쏘지 않음 (나포 기회 보장)
		if ship == owned_ship and has_room:
			continue
			
		var dist = global_position.distance_to(ship.global_position)
		if dist < max_range:
			return ship
			
	return null

func _perform_range_attack(_target: Node3D) -> void:
	pass
