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
@export var attack_range: float = 1.5
@export var range_attack_limit: float = 20.0 # 화살 사거리
@export var attack_cooldown: float = 1.0
@export var shoot_cooldown: float = 2.0 # 활 쏘기 쿨다운

@export var move_speed: float = 3.0
@export var team: String = "player" # "player" or "enemy"
@export var is_stationary: bool = false # 제자리 고정 (NavMesh 없는 배용)
@export var arrow_scene: PackedScene = preload("res://scenes/effects/arrow.tscn")

# === 내부 상태 ===
var current_health: float = 100.0
var current_state: State = State.IDLE
var current_target: Node3D = null
var attack_timer: float = 0.0
var shoot_timer: float = 0.0
var wander_timer: float = 0.0
var wander_target_local: Vector3 = Vector3.ZERO # 배 기준 로컬 목표 지점

# 소속 배 참조
var owned_ship: Node3D = null


# 노드 참조
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null


func _ready() -> void:
	current_health = max_health
	
	# 부모 노드 구조에 따라 배 참조 찾기
	# 구조: Ship -> Soldiers -> Soldier
	var parent = get_parent()
	if parent and parent.name == "Soldiers":
		owned_ship = parent.get_parent()
	elif parent and parent.has_method("get_wind_strength"): # Ship 스크립트 체크
		owned_ship = parent
	
	# 무기(검) 절차적 생성
	if not has_node("WeaponPivot"):
		var pivot = Node3D.new()
		pivot.name = "WeaponPivot"
		# 캐릭터 오른손 위치 대략 잡기
		pivot.position = Vector3(0.4, 1.0, -0.2)
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
	match current_state:
		State.IDLE:
			_state_idle(delta)
		State.WANDER:
			_state_wander(delta)
		State.MOVE:
			_state_move(delta)
		State.ATTACK:
			_state_attack(delta)
		State.DEAD:
			pass # 죽은 상태
	
	# 공격 쿨다운
	if attack_timer > 0: attack_timer -= delta
	if shoot_timer > 0: shoot_timer -= delta
	
	# 원거리 사격 체크
	if current_state != State.ATTACK and current_state != State.DEAD:
		_check_ranged_combat()


## IDLE 상태: 잠시 대기하다가 다시 배회
func _state_idle(delta: float) -> void:
	# 적 탐색
	var enemy = find_nearest_enemy()
	if enemy:
		if is_stationary:
			# 고정형은 MOVE로 가지 않고 IDLE 유지 (사격은 _physics_process에서 함)
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
func _state_wander(_delta: float) -> void:
	# 적 탐색
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
		nav_agent.target_position = current_global_target
		
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
	
	wander_target_local = Vector3(random_x, 0.5, random_z) # Y=0.5 (갑판 위)
	_change_state(State.WANDER)


## MOVE 상태 (적 추적)
func _state_move(_delta: float) -> void:
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
	
	if distance <= attack_range:
		_change_state(State.ATTACK)
		return
	
	# NavMesh를 통한 이동
	if nav_agent:
		nav_agent.target_position = current_target.global_position
		
		if not nav_agent.is_navigation_finished():
			var next_pos = nav_agent.get_next_path_position()
			var direction = (next_pos - global_position).normalized()
			velocity = direction * move_speed
			move_and_slide()
			
			# 이동 방향을 향해 회전
			# look_at 안전 처리: 목표 지점이 현재 위치와 너무 가까우면 회전하지 않음
			if direction.length_squared() > 0.01:
				var target_look = global_position + direction
				target_look.y = global_position.y # Y축 평면 유지
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
	
	if current_target.has_method("take_damage"):
		current_target.take_damage(attack_damage)
		
		# 시각적 피드백: 런지(Lunge) 애니메이션
		# 현재 바라보는 방향(Forward)으로 몸체를 잠깐 밈
		var original_transform = $MeshInstance3D.transform
		var tween = create_tween()
		tween.tween_property($MeshInstance3D, "position:z", -0.5, 0.1).as_relative()
		tween.tween_property($MeshInstance3D, "position:z", 0.5, 0.1).as_relative()
		
		# 무기도 휘두르기 (WeaponPivot이 있다면)
		var weapon_pivot = get_node_or_null("WeaponPivot")
		if weapon_pivot:
			var w_tween = create_tween()
			w_tween.tween_property(weapon_pivot, "rotation:x", -deg_to_rad(45), 0.1) # 내려치기
			w_tween.tween_property(weapon_pivot, "rotation:x", 0.0, 0.2)


## 가장 가까운 적 찾기
func find_nearest_enemy() -> Node3D:
	var all_soldiers = get_tree().get_nodes_in_group("soldiers")
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
		
		# 예외: owned_ship이 같은 경우 (혹시나 같은 배에 다른 팀이 있을 수 있으므로 team 체크가 우선이지만, 안전장치)
		# 하지만 도선 전투에서는 "같은 배 위에서 적과 싸우는" 상황이므로 배가 같다고 무시하면 안됨! 
		# 따라서 owned_ship 체크는 제거하거나, 팀 체크로 대체.
		
		var distance = global_position.distance_to(other.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
	
	return nearest


## 데미지 받기
func take_damage(amount: float) -> void:
	if current_state == State.DEAD:
		return
	
	current_health -= amount
	# print("%s가 %.1f 데미지를 받음! (남은 체력: %.1f)" % [name, amount, current_health])
	
	if current_health <= 0:
		_die()


## 사망 처리
func _die() -> void:
	current_state = State.DEAD
	
	# 비활성화 및 그룹에서 제거 (타겟팅 방지)
	set_physics_process(false)
	remove_from_group("soldiers")
	
	# 충돌 비활성화
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true
	
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
	# 1. 적군 병사 탐색
	var soldiers = get_tree().get_nodes_in_group("soldiers")
	for s in soldiers:
		if s.get("team") != team and s.get("current_state") != State.DEAD:
			var dist = global_position.distance_to(s.global_position)
			if dist < range_attack_limit:
				return s
	
	# 2. 적군 함선 탐색
	var enemy_team = "enemy" if team == "player" else "player"
	var ships = get_tree().get_nodes_in_group(enemy_team)
	for ship in ships:
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
	arrow.start_pos = global_position + Vector3(0, 1.2, 0)
	# 적군 병사면 가슴 높이, 배면 갑판 높이 조준
	arrow.target_pos = target.global_position + Vector3(0, 0.8, 0)
	arrow.team = team
	
	# 거리에 따른 곡선 높이 조절
	var dist = arrow.start_pos.distance_to(arrow.target_pos)
	arrow.arc_height = clamp(dist * 0.3, 1.0, 5.0)
	
	get_tree().root.add_child(arrow)
