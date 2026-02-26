extends Node3D

## 추적선 (Chaser Ship)
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var move_speed: float = 3.5 # 플레이어보다 약간 빠르게? (4.0 -> 3.5 너프)
@export var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
@export var boarders_count: int = 2 # 도선시킬 병사 수

@export var hp: float = 60.0 # 기본 HP 상향 (대포 일제사격 2회 정도 버팀)
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
@export var loot_scene: PackedScene = preload("res://scenes/effects/floating_loot.tscn")
@export var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")
var _fire_instance: Node3D = null

var max_hp: float = 60.0
var target: Node3D = null

# 상태 (State)
var is_dying: bool = false
var is_boarding: bool = false
var is_derelict: bool = false # 병사 전멸 시 무력화(폐선) 상태
var is_burning: bool = false
var burn_timer: float = 0.0
var fire_build_up: float = 0.0 # 화재 누적 수치
var fire_threshold: float = 100.0 # 화재 임계치

# 누수(Leaking) 시스템 변수
var leaking_rate: float = 0.0 # 초당 피해량
var _last_splinter_time: float = 0.0 # 파편 생성 쿨다운용
var _visual_children: Array = [] # 침몰 연출용 시각 노드 캐시

func get_hull_ratio() -> float:
	if max_hp <= 0.0:
		return 1.0
	return hp / max_hp

func _update_fire_effect() -> void:
	# is_burning 또는 폐선 상태일 때 화재 파티클 발생 (불꽃 + 연기 분리형)
	if (is_burning or is_derelict) and not is_dying:
		if not is_instance_valid(_fire_instance):
			_fire_instance = fire_effect_scene.instantiate() as Node3D
			add_child(_fire_instance)
			_fire_instance.position = Vector3(0, 1.5, 0.0)
			_set_fire_emitting(true)
		else:
			_set_fire_emitting(true)
	else:
		if is_instance_valid(_fire_instance):
			_set_fire_emitting(false)

func _set_fire_emitting(active: bool) -> void:
	if not is_instance_valid(_fire_instance):
		return
	var flame = _fire_instance.get_node_or_null("FlameParticles") as GPUParticles3D
	var smoke = _fire_instance.get_node_or_null("SmokeParticles") as GPUParticles3D
	
	if flame: flame.emitting = active
	if smoke: smoke.emitting = active

# Boarding Action Variables
var current_sink_offset: float = 0.0 # 가라앉은 깊이
var current_tilt_angle: float = 0.0 # 기울어진 각도
@onready var wake_trail: GPUParticles3D = $WakeTrail if has_node("WakeTrail") else null

# 최적화 변수
var cached_lm: Node = null
var separation_force: Vector3 = Vector3.ZERO
var separation_timer: float = 0.0
var logic_timer: float = 0.0 # 타겟 체크 등 일반 로직용

# 도선 로직 변수
var boarding_timer: float = 0.0
var boarding_interval: float = 1.0
var boarding_target: Node3D = null
var max_boarding_distance: float = 6.0 # 이 거리 이내여야 도선 진행
var boarding_break_distance: float = 10.0 # 이 거리 이상 벌어지면 도선 포기 및 추격 재개
var has_rammed: bool = false # 중복 데미지 방지

func get_radius() -> float:
	return 2.5 # 대략적인 선체 반경 (상황에 맞게 조정)

func _become_derelict() -> void:
	is_derelict = true
	is_boarding = false
	if wake_trail: wake_trail.emitting = false
	
	print("🏴 선원 전멸! 적함이 폐선(Derelict) 상태가 되었습니다.")
	
	# 파티클 하나 띄워줄 수 있다면 좋음 (검은 연기 등)
	# 돛을 내리거나 색상을 어둡게 하는 등의 시각적 처리도 연출 가능
	
	# 임시로 시각적 피드백: 약간 기울어지고 가라앉음 (반파 효과)
	var tilt_tween = create_tween()
	tilt_tween.tween_property(self , "rotation_degrees:z", 5.0, 2.0).set_ease(Tween.EASE_OUT)
	tilt_tween.set_parallel(true)
	tilt_tween.tween_property(self , "global_position:y", global_position.y - 0.2, 2.0).set_ease(Tween.EASE_OUT)
	
	# 도선 방지를 위해 이동 및 회전 정지
	move_speed = 0.0
	
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]

func _ready() -> void:
	max_hp = hp
	_find_player()
	
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]

# 데미지 처리 (hit_position 추가됨)
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_dying: return
	hp -= amount
	
	# 피격 이펙트 (파편) - 무차별 포격 시 파티클 폭발(렉) 방지 및 시각적 분리 현상 방지
	var current_time = Time.get_ticks_msec() / 1000.0
	if wood_splinter_scene and (current_time - _last_splinter_time > 0.2):
		_last_splinter_time = current_time
		var splinter = wood_splinter_scene.instantiate()
		get_tree().root.add_child(splinter)
		
		if hit_position != Vector3.ZERO:
			splinter.global_position = hit_position + Vector3(0, 0.5, 0)
		else:
			var offset = Vector3(randf_range(-0.5, 0.5), 1.5, randf_range(-0.5, 0.5))
			splinter.global_position = global_position + offset
		splinter.rotation.y = randf() * TAU
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(amount)
	
	if hp <= 0:
		die()

func die() -> void:
	if is_dying: return
	is_dying = true
	
	# 침몰 시작 시 타겟 그룹에서 제외 (대포가 시체를 쏘지 않게 함)
	if is_in_group("enemy"):
		remove_from_group("enemy")
	
	# 점수 및 XP 추가
	if is_instance_valid(cached_lm):
		if cached_lm.has_method("add_score"):
			cached_lm.add_score(100)
		if cached_lm.has_method("add_xp"):
			cached_lm.add_xp(30)
	
	# 물리 및 충돌 비활성화 (Area3D 대응)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	if get_node_or_null("CollisionShape3D"):
		get_node("CollisionShape3D").set_deferred("disabled", true)
		
	# 항적 끄기
	if wake_trail:
		wake_trail.emitting = false
		
	# 가라앉는 연출 (침몰 애니메이션)
	var sink_tween = create_tween()
	sink_tween.set_parallel(true)
	
	# 무작위 기울기
	var tilt_x = randf_range(-15.0, 15.0)
	var tilt_z = randf_range(-10.0, 10.0)
	sink_tween.tween_property(self , "rotation_degrees:x", tilt_x, 3.0).set_ease(Tween.EASE_OUT)
	sink_tween.tween_property(self , "rotation_degrees:z", tilt_z, 3.0).set_ease(Tween.EASE_OUT)
	
	# 아래로 가라앉음
	sink_tween.tween_property(self , "global_position:y", global_position.y - 10.0, 5.0).set_ease(Tween.EASE_IN)
	
	leaking_rate = 0.0 # 사망 시 누수 중단
	
	_drop_floating_loot()
	
	sink_tween.set_parallel(false)
	sink_tween.tween_callback(queue_free)

## 화염 데미지 및 상태 이상
func take_fire_damage(dps: float, duration: float) -> void:
	if is_dying: return
	
	if is_burning:
		burn_timer = max(burn_timer, duration)
		leaking_rate += dps * 0.5 # 이미 불타고 있으면 추가 데미지 약화
		return

	# 화재 누적
	fire_build_up += duration * 8.0 # 적 배는 약 2.5 ~ 3발 정도에 점화
	
	if fire_build_up >= fire_threshold:
		is_burning = true
		fire_build_up = fire_threshold
		burn_timer = duration
		leaking_rate += dps

func _update_burning_status(delta: float) -> void:
	if is_burning:
		burn_timer -= delta
		if burn_timer <= 0:
			is_burning = false
			fire_build_up = 0.0
	else:
		# 미발화 시 누적치 감소
		if fire_build_up > 0:
			fire_build_up = move_toward(fire_build_up, 0, 20.0 * delta)

func _drop_floating_loot() -> void:
	if not loot_scene: return
	
	# 1~3개의 부유물 드랍
	var loot_count = randi_range(1, 3)
	for i in range(loot_count):
		var loot = loot_scene.instantiate()
		get_tree().root.add_child.call_deferred(loot)
		
		# 랜덤 오프셋 (수면 위 Y=0 근처 둥둥)
		var offset_x = randf_range(-2.0, 2.0)
		var offset_z = randf_range(-2.0, 2.0)
		
		# 콜백으로 위치 설정 (충돌 안전)
		var spawn_pos = Vector3(global_position.x + offset_x, 0.5, global_position.z + offset_z)
		loot.set_deferred("global_position", spawn_pos)

func _process(delta: float) -> void:
	if is_dying: return
	
	_update_fire_effect()
	_update_burning_status(delta)
	
	if is_derelict:
		leaking_rate += 0.2 * delta

func _physics_process(delta: float) -> void:
	if is_dying: return
	
	# === 폐선(Derelict) 빙의 로직 ===
	if not is_derelict:
		# 쏼 나서 빌지 판단은 스로틸링(감속 티머에 연동)
		# 검사는 로직 타이머가 매번 실행될 때만 (0.2초마다)
		if logic_timer <= 0:
			var alive_soldiers = 0
			if has_node("Soldiers"):
				for child in $Soldiers.get_children():
					if child.get("current_state") != 4:
						alive_soldiers += 1
			if alive_soldiers == 0:
				_become_derelict()
				return
	else:
		# 폐선 상태면 둥둥 떠있기만 함 (로직 정지)
		# 물결에 흔들리는 연출 등 추가 가능
		if wake_trail: wake_trail.emitting = false
		return

	# 도선(Boarding) 상태 로직
	if is_boarding:
		_process_boarding(delta)
		return

	# 1. 고비용 로직 스로틀링 (0.2초마다)
	logic_timer -= delta
	if logic_timer <= 0:
		logic_timer = 0.2
		_update_logic_throttled()

	if not is_instance_valid(target):
		if wake_trail: wake_trail.emitting = false
		return
	
	# 2. 목표 지점 계산 (Galley Intercept Logic)
	var target_pos = target.global_position
	var dist_to_player = global_position.distance_to(target_pos)
	
	if dist_to_player >= 25.0:
		# 예측 이동 (Intercept)
		var target_speed = target.get("current_speed")
		if target_speed:
			var target_forward = Vector3(-sin(target.rotation.y), 0, -cos(target.rotation.y))
			var time_to_reach = min(dist_to_player / move_speed, 3.0)
			target_pos += target_forward * target_speed * time_to_reach

	# 3. 이동 및 회전 (Separation 포함)
	var direction = (target_pos - global_position).normalized()
	
	# Separation (함선 간 겹침 방지) - 계산은 스로틀링됨
	if separation_force.length_squared() > 0.001:
		direction = (direction + separation_force * 1.5).normalized()
	
	var target_rotation_y = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 3.0)
	
	# 전진
	translate(Vector3.FORWARD * move_speed * delta)
	
	# === 누수(Leaking) 시각 효과 및 데미지 ===
	if leaking_rate > 0:
		take_damage(leaking_rate * delta)
		
		# HP 비율에 따라 서서히 가라앉음
		var hp_ratio = 1.0 - (hp / max_hp)
		# 최대 0.8m 가라앉고, 최대 10도 기울어짐
		var target_sink = hp_ratio * 0.8
		var target_tilt = hp_ratio * 10.0
		
		current_sink_offset = lerp(current_sink_offset, target_sink, delta)
		current_tilt_angle = lerp(current_tilt_angle, target_tilt, delta)
		
		# 시각적 반영 (Mesh 등을 찾아서 오프셋 주는 것이 좋지만, 
		# 간단히 self 위치/회전 조정 — translation이 매 프레임 초기화되지 않는다면 작동)
		# Node3D의 자식들이 있다면 그 자식들의 transform을 조정하는 것이 안전함
		# 시각적 반영 (Mesh 등 시각 노드만 오프셋)
		# Soldiers나 CollisionShape 등을 같이 이동시키면 물리/전투 로직이 꼬이므로 제외
		# 싱크 비주얼: 자식 노드 이니셜 쿨스 (1회만 실행)
		if _visual_children.is_empty():
			for child in get_children():
				if child.name == "Soldiers" or child is CollisionShape3D or child is Area3D: continue
				if child is MeshInstance3D or (child is Node3D and not child is GPUParticles3D):
					child.set_meta("init_y", child.position.y)
					child.set_meta("init_rot_z", child.rotation_degrees.z)
					_visual_children.append(child)
		
		for child in _visual_children:
			if not is_instance_valid(child): continue
			child.position.y = child.get_meta("init_y") - current_sink_offset
			child.rotation_degrees.z = child.get_meta("init_rot_z") + current_tilt_angle
	
	# 항적 제어
	if wake_trail:
		wake_trail.emitting = move_speed > 0.5

func _update_logic_throttled() -> void:
	# 타겟 유효성 및 침몰 상태 체크
	if not is_instance_valid(target) or target.get("is_sinking"):
		target = null
		_find_player()
	
	# Separation 계산 (N^2 가능성 있으므로 주기를 더 길게 가져감)
	separation_force = _calculate_separation()

func _process_boarding(delta: float) -> void:
	if not is_instance_valid(boarding_target):
		die()
		return
	
	# 선체 고정 (플레이어 배 근처에 머물기)
	var target_pos = boarding_target.global_position
	var dist = global_position.distance_to(target_pos)
	
	if dist > 4.5:
		var dir = (target_pos - global_position).normalized()
		global_position += dir * move_speed * 0.5 * delta
		
	# 회전도 플레이어 바라보게 유지
	var look_dir = (target_pos - global_position).normalized()
	var target_rot = atan2(-look_dir.x, -look_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, delta * 2.0)
	
	# 타이머 기반 병사 전이
	# 배가 충분히 가까울 때만 타이머 진행 (날아다니는 현상 방지)
	if dist <= max_boarding_distance:
		boarding_timer += delta
		if boarding_timer >= boarding_interval:
			boarding_timer = 0.0
			_transfer_one_soldier()
	
	# 너무 멀어지면 도선 포기 및 추격 상태로 복귀
	if dist > boarding_break_distance:
		print("📡 거리가 너무 멀어 도선 중단. 추격 재개.")
		is_boarding = false
		boarding_timer = 0.0
		# target은 이미 boarding_target이었으므로 그대로 유지됨

func _transfer_one_soldier() -> void:
	if not is_instance_valid(boarding_target): return
	
	var target_soldiers_node = boarding_target.get_node_or_null("Soldiers")
	if not target_soldiers_node: target_soldiers_node = boarding_target
	
	# 내 배에서 살아있는 병사 하나 찾기
	var s = null
	if has_node("Soldiers"):
		for child in $Soldiers.get_children():
			if child.get("current_state") != 4: # NOT DEAD
				s = child
				break
	
	if s:
		# 월선 실행 (Jump Animation 포함)
		var _start_global = s.global_position
		s.call_deferred("reparent", target_soldiers_node)
		
		# 점프 효과 (Tween)
		var jump_offset = Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-2.0, 2.0))
		var end_global = boarding_target.global_position + jump_offset
		
		# 0.4초간 포물선 점프 애니메이션
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(s, "global_position:x", end_global.x, 0.4)
		tween.tween_property(s, "global_position:z", end_global.z, 0.4)
		# Y축은 포물선
		s.global_position.y += 1.5 # 순간적으로 높임
		tween.tween_property(s, "global_position:y", end_global.y, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
		# 상태 설정
		if s.has_method("set_team"): s.set_team("enemy")
		if s.get("is_stationary"): s.set("is_stationary", false)
		
		print("🏃 적군 1명 월선! (남은 병사 수 체크 중)")
	else:
		# 더 이상 넘길 병사가 없으면 임무 조기 종료 (자폭)
		print("🏳️ 모든 병사 도선 완료. 적함 침몰.")
		die()


## 주변 적함들로부터 멀어지려는 힘 계산
func _calculate_separation() -> Vector3:
	# separation 타이머 사용하여 빈도 더 줄일 수도 있음
	var force = Vector3.ZERO
	# Engine.get_main_loop().get_nodes_in_group 대신 SceneTree의 매개인스턴스 사용
	var neighbors = get_tree().get_nodes_in_group("enemy")
	var count = 0
	var separation_dist = 5.0 # 함선 간 최소 유지 거리 (반경)
	
	# 최대 비교 개수 제한하여 극단적인 프레임 드랍 방지 (예: 10척만)
	var max_checks = min(neighbors.size(), 15)
	
	for i in range(max_checks):
		var other = neighbors[i]
		if other == self or not is_instance_valid(other) or other.get("is_dying"):
			continue
			
		var dist = global_position.distance_to(other.global_position)
		if dist < separation_dist and dist > 0.001:
			# 가까울수록 더 강하게 밀어냄 (거리에 반비례)
			var push_dir = (global_position - other.global_position).normalized()
			force += push_dir / dist
			count += 1
			
	if count > 0:
		force = force / count
		
	return force


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		# 침몰 중이 아닌 배만 타겟으로 잡음
		if not p.get("is_sinking"):
			target = p
			break


## 충돌 감지 (Area3D signal 연결 필요)
func _on_body_entered(body: Node3D) -> void:
	# 플레이어와 충돌했는지 확인 (StaticBody/CharacterBody 등)
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		_board_ship(body)

func _on_area_entered(area: Area3D) -> void:
	# 플레이어의 감지 영역(ProximityArea)과 충돌했는지 확인
	# ProximityArea의 부모가 PlayerShip인지 확인
	var parent = area.get_parent()
	if parent and parent.is_in_group("player"):
		_board_ship(parent)


func _board_ship(target_ship: Node3D) -> void:
	if is_dying or is_boarding: return
	
	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not (ship_node and ship_node.is_in_group("player")):
			return

	# === 무력화(폐선) 상태일 경우 나포 판정 ===
	if is_derelict:
		print("📦 플레이어가 폐선에 접근! 나포 성공.")
		if ship_node.has_method("capture_derelict_ship"):
			ship_node.capture_derelict_ship()
		# 달달하게 보상 주고 배는 가라앉음
		die()
		return

	# 1. 초기 충돌 효과 (최초 1회만)
	if not has_rammed:
		has_rammed = true
		var ram_damage = move_speed * 4.0
		if ship_node.has_method("take_damage"):
			ship_node.take_damage(ram_damage, global_position)
		# 자신도 시각적 파편 효과를 위해 데미지 (죽지는 않을 정도)
		take_damage(1.0, global_position)
		
		# 충격 피드백 강화 (화면 흔들림 및 묵직한 사운드)
		if is_instance_valid(AudioManager):
			AudioManager.play_sfx("impact_wood", global_position, randf_range(0.6, 0.8)) # 더 낮고 묵직한 피치
		
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake"):
			# 대포보다는 길고 묵직한 진동 (세기 0.4, 시간 0.3초)
			cam.shake(0.4, 0.3)
			
		print("💥 충격적 충돌 발생! 도선 시작.")

	# 2. 도선 상태 진입
	is_boarding = true
	boarding_target = ship_node
	boarding_timer = 0.0 # 즉시 첫 병사가 넘어가지 않도록 0으로 초기화


# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("💧 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	print("🩹 누수 완화. 남은 누수율: %.1f" % leaking_rate)
