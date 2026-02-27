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
@export var max_health: float = 100.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 1.2
@export var detection_range: float = 15.0 # 적 탐지 범위 (이 밖의 적은 무시)
@export var range_attack_limit: float = 20.0 # 화살 사거리
@export var attack_cooldown: float = 1.0
@export var shoot_cooldown: float = 2.0 # 활 쏘기 쿨다운
@export var crit_chance: float = 0.1 # 크리티컬 확률 (10%)
@export var crit_multiplier: float = 2.0 # 크리티컬 데미지 배율
@export var defense: float = 0.0 # 방어력 (피해 감소)

@export var move_speed: float = 3.0
@export var team: String = "player" # "player" or "enemy"
@export var is_stationary: bool = false # 제자리 고정 (NavMesh 없는 배용)
@export var arrow_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@export var hit_effect_scene: PackedScene = preload("res://scenes/effects/hit_effect.tscn")
@export var slash_effect_scene: PackedScene = preload("res://scenes/effects/slash_effect.tscn")

# === 내부 상태 ===
var current_health: float = 100.0
var current_state: State = State.IDLE
var current_target: Node3D = null
var attack_timer: float = 0.0
var shoot_timer: float = 0.0
var wander_timer: float = 0.0
var wander_target_local: Vector3 = Vector3.ZERO # 배 기준 로컬 목표 지점
var decision_timer: float = 0.0 # 의사결정 스로틀링용

# 소속 배 및 매니저 참조
var owned_ship: Node3D = null
var home_ship: Node3D = null # 최초 소속된 플레이어 배 (나포함 침몰 시 복귀용)
var _cached_level_manager: Node = null
var last_nav_target_pos: Vector3 = Vector3.ZERO # 경로 갱신 최적화용

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
		var mult = MetaManager.get_crew_stat_multiplier()
		max_health *= mult
		attack_damage *= mult
	
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
	
	# 무기(검) 절차적 생성
	if not has_node("WeaponPivot"):
		var pivot = Node3D.new()
		pivot.name = "WeaponPivot"
		# 캐릭터 오른손 위치 대략 잡기
		pivot.position = Vector3(0.3, 0.7, -0.15)
		add_child(pivot)
		
		# 검 모델 (BoxMesh)
		var sword = MeshInstance3D.new()
		var sword_mesh = BoxMesh.new()
		sword_mesh.size = Vector3(0.05, 0.05, 0.8) # 얇고 긴 막대
		sword.mesh = sword_mesh
		sword.position = Vector3(0, 0, -0.4) # 피벗 기준 앞으로 뻗음
		pivot.add_child(sword)
	
	if nav_agent:
		nav_agent.max_speed = move_speed
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
	
	# 시작 시 랜덤 배회 시작
	_start_wander()
	_update_team_color()
	
	# 그룹 수동 등록 (검색 정확도 향상)
	add_to_group("soldiers")


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
	if global_position.y < -5.0:
		_die()
		return
	
	# 고정형(is_stationary) 병사는 AI 로직 실행하지 않음 — 사격만 함
	if is_stationary:
		if shoot_timer > 0: shoot_timer -= delta
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
	
	# 공격 쿨다운
	if attack_timer > 0: attack_timer -= delta
	
	var current_shoot_cooldown_mult = 1.0
	if is_instance_valid(UpgradeManager):
		var train_lv = UpgradeManager.current_levels.get("training", 0)
		current_shoot_cooldown_mult = (1.0 - 0.1 * train_lv)
	
	if shoot_timer > 0: shoot_timer -= delta * (1.0 / current_shoot_cooldown_mult)
	
	# 원거리 사격 체크 (스로틀링)
	if run_heavy_logic and current_state != State.ATTACK and current_state != State.DEAD:
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
	
	if distance <= attack_range:
		_change_state(State.ATTACK)
		return
	
	# NavMesh를 통한 이동
	if nav_agent:
		var target_pos = current_target.global_position
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
	
	# 사거리 벗어남
	if distance > attack_range * 1.2:
		_change_state(State.MOVE)
		return
	
	# 타겟 바라보기
	look_at(Vector3(current_target.global_position.x, global_position.y, current_target.global_position.z), Vector3.UP)
	
	# 공격
	if attack_timer <= 0:
		_perform_attack()
		attack_timer = attack_cooldown


## 공격 실행
func _perform_attack() -> void:
	if not is_instance_valid(current_target): return
	
	# 크리티컬 히트 판정
	var final_damage = attack_damage
	var is_crit = randf() < crit_chance
	if is_crit:
		final_damage *= crit_multiplier
	
	# 사운드 재생
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("sword_swing", global_position)
	
	if current_target.has_method("take_damage"):
		current_target.take_damage(final_damage, global_position)
		
		# 시각적 피드백: 런지(Lunge) 애니메이션
		# 현재 바라보는 방향(Forward)으로 몸체를 잠깐 밈
		var _original_transform = $MeshInstance3D.transform
		var tween = create_tween()
		tween.tween_property($MeshInstance3D, "position:z", -0.5, 0.1).as_relative()
		tween.tween_property($MeshInstance3D, "position:z", 0.5, 0.1).as_relative()
		
		# 무기도 휘두르기 (WeaponPivot이 있다면)
		var weapon_pivot = get_node_or_null("WeaponPivot")
		if weapon_pivot:
			var w_tween = create_tween()
			w_tween.set_parallel(true)
			w_tween.tween_property(weapon_pivot, "rotation:x", -deg_to_rad(60), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			w_tween.tween_property(weapon_pivot, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
			
			w_tween.chain().set_parallel(true)
			w_tween.tween_property(weapon_pivot, "rotation:x", 0.0, 0.2)
			w_tween.tween_property(weapon_pivot, "scale", Vector3.ONE, 0.2)
		
		# 슬래시(휘두르기) 이펙트 생성
		_spawn_slash_effect()


## 하얀색으로 깜빡임


## 가장 가까운 적 찾기 (탐지 범위 제한)
func find_nearest_enemy() -> Node3D:
	var all_soldiers = get_soldiers_cached(get_tree())
	var nearest: Node3D = null
	var nearest_distance: float = INF
	
	for other in all_soldiers:
		if other == self:
			continue
		
		# 죽은 적 무시
		if other.get("current_state") == State.DEAD:
			continue

		# 같은 팀이면 무시
		if other.get("team") == team:
			continue
		
		var distance = global_position.distance_to(other.global_position)
		
		# 탐지 범위 밖의 적은 무시 (다른 배의 적을 쫓아가지 않음)
		if distance > detection_range:
			continue
		
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
	
	return nearest

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
			if owned_ship.has_method("capture_ship"):
				owned_ship.capture_ship()
			elif owned_ship.has_method("capture_derelict_ship"):
				owned_ship.capture_derelict_ship()
		return # 이미 다른 배 위이므로 아래 로직(주변 배 찾기)은 실행 않음

	# 상황 2: 본선 혹은 아군 함선에 있으면서, 주변의 비어있는 적선(폐선) 탐색하여 뛰어들기
	if owned_ship.is_in_group("player"):
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
						print("🚀 빈 배 발견! 나포를 위해 뛰어듭니다.")
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
	
	var start_pos = global_position
	reparent(target_soldiers)
	owned_ship = target_ship
	
	var jump_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-2.0, 2.0))
	var end_pos = target_ship.global_transform * jump_offset
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self , "global_position:x", end_pos.x, 0.6)
	tween.tween_property(self , "global_position:z", end_pos.z, 0.6)
	
	var y_tween = create_tween()
	y_tween.tween_property(self , "global_position:y", start_pos.y + 2.5, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(self , "global_position:y", end_pos.y, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	if is_capture_attempt:
		tween.finished.connect(func():
			if is_instance_valid(target_ship):
				target_ship.set_meta("being_boarded", false)
				_check_ship_capture_opportunity() # 착지 후 즉시 나포 체크
		)
	
	if not is_capture_attempt:
		print("⚓ 함선 침몰! 플레이어 본선으로 긴급 복귀합니다.")

func _teleport_to_ship(_target_ship: Node3D) -> void:
	# 텔레포트 대신 → Survivor(생존자)로 변환하여 바다에 떠있게 함
	var survivor_scn = load("res://scenes/effects/survivor.tscn")
	if survivor_scn:
		var survivor = survivor_scn.instantiate()
		get_tree().root.add_child.call_deferred(survivor)
		var spawn_pos = global_position
		spawn_pos.y = 0.5 # 수면 높이
		survivor.set_deferred("global_position", spawn_pos)
		print("🏊 병사가 바다에 빠져 생존자가 되었습니다!")
	queue_free()

## 데미지 받기
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.DEAD:
		return
	
	# 방어력 적용 (최소 1 데미지)
	var final_damage = maxf(amount - defense, 1.0)
	current_health -= final_damage
	
	# 피격 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("soldier_hit", global_position, randf_range(0.9, 1.1))
	
	# 시각적 피드백
	_flash_hit()
	_spawn_hit_effect(hit_position)
	
	# 물리적 피드백: 넉백
	if hit_position != Vector3.ZERO:
		var knockback_dir = (global_position - hit_position).normalized()
		knockback_dir.y = 0
		velocity += knockback_dir * 3.0
	
	if current_health <= 0:
		_die()


## 피격 시 하얀색으로 깜빡임
func _flash_hit() -> void:
	var mesh = $MeshInstance3D
	if not mesh: return
	
	var tween = create_tween()
	# 하얀색으로 블렌딩 (StandardMaterial3D의 emission을 활용하거나 albedo 조절)
	
	mesh.material_override.emission_enabled = true
	mesh.material_override.emission = Color.WHITE
	mesh.material_override.emission_energy_multiplier = 2.0
	
	tween.tween_property(mesh.material_override, "emission_energy_multiplier", 0.0, 0.1)
	tween.finished.connect(func(): if mesh.material_override: mesh.material_override.emission_enabled = false)

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

## 휘두르기 이펙트 생성
func _spawn_slash_effect() -> void:
	if not slash_effect_scene: return
	var effect = slash_effect_scene.instantiate()
	get_tree().root.add_child(effect)
	
	# 병사 앞쪽에 생성
	var forward = - global_transform.basis.z
	effect.global_position = global_position + forward * 0.8 + Vector3(0, 0.7, 0)
	
	# 방향 맞추기
	if current_target:
		effect.look_at(current_target.global_position + Vector3(0, 1.0, 0), Vector3.UP)

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
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("soldier_die", global_position)
		# 데드 후 약간의 시간 차를 두고 물보라(풍덩) 소리 재생
		get_tree().create_timer(randf_range(0.3, 0.6)).timeout.connect(func():
			if is_instance_valid(AudioManager):
				AudioManager.play_sfx("water_splash_small", global_position, randf_range(0.8, 1.2))
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
	if shoot_timer > 0: return
	
	var target = _find_ranged_target()
	if target:
		_perform_range_attack(target)
		shoot_timer = shoot_cooldown

func _find_ranged_target() -> Node3D:
	# 1. 적군 병사 탐색 (캐시 사용으로 성능 최적화)
	var soldiers = get_soldiers_cached(get_tree())
	for s in soldiers:
		if s.get("team") != team and s.get("current_state") != State.DEAD:
			var dist = global_position.distance_to(s.global_position)
			if dist < range_attack_limit:
				return s
	
	# 2. 적군 함선 탐색
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
		if dist < range_attack_limit:
			return ship
			
	return null

func _perform_range_attack(target: Node3D) -> void:
	if not arrow_scene: return
	
	# 타겟 방향 바라보기
	var look_pos = target.global_position
	look_pos.y = global_position.y
	if not global_position.is_equal_approx(look_pos):
		look_at(look_pos, Vector3.UP)

	# 화살 발사
	var arrow = arrow_scene.instantiate()
	
	# 데이터 설정 (SceneTree에 추가하기 전에 설정하여 _ready에서 사용 가능하게 함)
	arrow.start_pos = global_position + Vector3(0, 0.8, 0)
	# 적군 병사면 가슴 높이, 배면 갑판 높이 조준
	arrow.target_pos = target.global_position + Vector3(0, 0.5, 0)
	arrow.team = team
	
	# 시너지 반영: 불화살 (플레이어 진영 전용)
	if team == "player" and is_instance_valid(UpgradeManager):
		var fire_lv = UpgradeManager.current_levels.get("fire_arrows", 0)
		if fire_lv > 0:
			arrow.is_fire_arrow = true
			arrow.fire_damage = fire_lv * 1.5
	
	# 거리에 따른 곡선 높이 조절
	var dist = arrow.start_pos.distance_to(arrow.target_pos)
	arrow.arc_height = clamp(dist * 0.3, 1.0, 5.0)
	
	# 발사 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("bow_shoot", global_position)
	
	get_tree().root.add_child(arrow)
