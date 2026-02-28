extends Node3D
class_name ChaserShip

## 추적선 (Chaser Ship)
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var team: String = "enemy" # "enemy" or "player"
@export var move_speed: float = 3.5
@export var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
@export var boarders_count: int = 2 # 도선시킬 병사 수

@export var hp: float = 60.0 # 기본 HP 상향 (대포 일제사격 2회 정도 버팀)
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
@export var loot_scene: PackedScene = preload("res://scenes/effects/floating_loot.tscn")
@export var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")
@export var survivor_scene: PackedScene = preload("res://scenes/effects/survivor.tscn")
@export var cannon_scene: PackedScene = preload("res://scenes/entities/cannon.tscn")
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
var hull_regen_rate: float = 0.0 # 초당 HP 회복량 (나포함도 수리 가능하게)
var hull_defense: float = 0.0 # 피격 데미지 감소량
var _last_splinter_time: float = 0.0 # 파편 생성 쿨다운용

# === 시각 효과 관련 ===
var tilt_offset: float = 0.0
var base_y: float = 0.0
var bobbing_amplitude: float = 0.2
var bobbing_speed: float = 1.1
var rocking_amplitude: float = 0.04

@onready var sail_visual: Node3D = $SailVisual if has_node("SailVisual") else null
@onready var rudder_visual: Node3D = $RudderVisual if has_node("RudderVisual") else null
@onready var oar_pivot_left: Node3D = $OarBaseLeft/OarPivot if has_node("OarBaseLeft/OarPivot") else null
@onready var oar_pivot_right: Node3D = $OarBaseRight/OarPivot if has_node("OarBaseRight/OarPivot") else null
var _oar_time: float = 0.0

@export var max_minion_crew: int = 3
var minion_respawn_timer: float = 0.0
@export var minion_respawn_interval: float = 15.0 # 아군 배보다 조금 더 느림

var sail_angle: float = 0.0 # 돛 각도 (시각적 피드백용)

# === 함대 진형 (Formation) 관련 ===
enum Formation {COLUMN, WING}
static var fleet_formation: Formation = Formation.COLUMN # 공유 진형 설정

var formation_spacing: float = 12.0 # 선박 간 간격

var _wave_timer: float = 0.0 # 물결 소리 타이머

# === 성능 최적화용 캐싱 (성능 저하 방지) ===
static var _cached_minion_list: Array = []
static var _last_minion_cache_frame: int = -1
static var _cached_ships_list: Array = []
static var _last_ships_cache_frame: int = -1

static func get_minions_cached(tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_minion_cache_frame:
		_cached_minion_list = tree.get_nodes_in_group("captured_minion")
		_last_minion_cache_frame = current_frame
	return _cached_minion_list

static func get_ships_cached(tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_ships_cache_frame:
		_cached_ships_list = tree.get_nodes_in_group("ships")
		_last_ships_cache_frame = current_frame
	return _cached_ships_list

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
var max_boarding_distance: float = 10.0 # 이 거리 이내여야 도선 진행 (회비 반경 고려 6.0 -> 10.0)
var boarding_break_distance: float = 15.0 # 밧줄이 끊어지는 거리 (10.0 -> 15.0 상향)
var has_rammed: bool = false # 중복 데미지 방지
var rope_instances: Array[MeshInstance3D] = [] # 그레플링 훅용 밧줄들

func get_radius() -> float:
	return 2.5 # 대략적인 선체 반경 (상황에 맞게 조정)

func _become_derelict() -> void:
	is_derelict = true
	is_boarding = false
	if wake_trail: wake_trail.emitting = false
	
	print("[Status] 선원 전멸! 적함이 폐선(Derelict) 상태가 되었습니다.")
	
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
	hp = max_hp
	base_y = global_position.y
	_find_player()
	
	# 초기 돛 색상 설정 (Enemy 기본: Red)
	if sail_visual:
		var mesh = sail_visual.get_node_or_null("SailMesh") as MeshInstance3D
		if mesh:
			mesh.set_instance_shader_parameter("albedo", Color(0.7, 0.1, 0.1, 1.0))
	add_to_group("ships")
	if team == "player":
		add_to_group("player")
		add_to_group("captured_minion")
		_apply_minion_visuals()
	else:
		add_to_group("enemy")
		
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
			# 방어력 적용된 수치로 파편 양 계산
			splinter.set_amount_by_damage(maxf(amount - hull_defense, 1.0))
	
	var final_damage = maxf(amount - hull_defense, 1.0)
	hp -= final_damage
	
	if hp <= 0:
		die()

func die() -> void:
	if is_dying: return
	is_dying = true
	
	# ✅ 배 위의 아군(player) 병사를 Survivor로 전환 (침몰 전 처리)
	_evacuate_player_soldiers_as_survivors()
	
	# 밧줄 제거
	_clear_ropes()
	
	# 침몰 시작 시 타겟 그룹에서 제외 (대포가 시체를 쏘지 않게 함)
	if is_in_group("enemy"):
		remove_from_group("enemy")
	if is_in_group("player"):
		remove_from_group("player")
	if is_in_group("captured_minion"):
		remove_from_group("captured_minion")
	
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
		
	# 4. 생존자(Survivor) 스폰 추가 (30% 확률)
	if survivor_scene and randf() < 0.3:
		var survivor = survivor_scene.instantiate()
		get_tree().root.add_child.call_deferred(survivor)
		var s_offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
		survivor.set_deferred("global_position", global_position + s_offset)
		print("[Rescue] 구출 가능한 생존자가 발생했습니다!")

## 침몰 시 배 위의 아군(player) 병사를 Survivor로 전환
func _evacuate_player_soldiers_as_survivors() -> void:
	if not survivor_scene: return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	var converted_count = 0
	for child in soldiers_node.get_children():
		if child.get("team") == "player" and child.get("current_state") != 4: # NOT DEAD
			# 병사 위치 저장 후 생존자 스폰
			var spawn_pos = child.global_position
			spawn_pos.y = 0.5 # 수면 높이
			
			var survivor = survivor_scene.instantiate()
			get_tree().root.add_child.call_deferred(survivor)
			survivor.set_deferred("global_position", spawn_pos)
			
			# 병사 즉시 제거
			child.queue_free()
			converted_count += 1
	
	if converted_count > 0:
		print("[Critical] 아군 병사 %d명이 바다로 뛰어들었습니다!" % converted_count)

func _process(delta: float) -> void:
	if is_dying: return
	
	_update_fire_effect()
	_auto_adjust_sail(delta)
	_update_sail_visual(delta)
	_update_oar_visual(delta)
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	
	if is_derelict:
		leaking_rate += 0.2 * delta
		# 폐선 상태일 때는 타겟 초기화 (공격 중단)
		target = null
		is_boarding = false
		_clear_ropes()
		
	if team == "player":
		_update_minion_respawn(delta)

func _update_hull_regeneration(delta: float) -> void:
	if is_dying or hull_regen_rate <= 0: return
	
	# 데미지를 입었을 때만 회복
	if hp < max_hp:
		hp = move_toward(hp, max_hp, hull_regen_rate * delta)

func _physics_process(delta: float) -> void:
	if is_dying: return
	
	_update_wave_sounds(delta)
	
	# 0. 아군 나포함(Minion)은 전용 AI 수행 (최우선)
	if team == "player":
		_process_minion_ai(delta)
		return
	
	# === 폐선(Derelict) 체크 (적군 전용) ===
	if is_derelict:
		# 폐선 상태면 둥둥 떠있기만 함 (로직 정지)
		# 바다에 천천히 떠밀려감
		position += Vector3.BACK * 0.2 * delta
		if wake_trail: wake_trail.emitting = false
		return
	
	# 병사 전멸 시 폐선화
	if logic_timer <= 0:
		var alive_soldiers = 0
		if has_node("Soldiers"):
			for child in $Soldiers.get_children():
				if child.get("current_state") != 4:
					alive_soldiers += 1
		if alive_soldiers == 0:
			_become_derelict()
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
	var move_dir = (target_pos - global_position).normalized()
	
	# Separation (함선 간 겹침 방지) - 계산은 스로틀링됨
	if separation_force.length_squared() > 0.001:
		# 분리력을 이동 방향에 부드럽게 합성 (강도 1.5배 적용)
		move_dir = (move_dir + separation_force * 1.5).normalized()
	
	var target_rotation_y = atan2(-move_dir.x, -move_dir.z)
	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 3.0)
	
	# 전진 (누수율에 비례하여 속도 감소)
	var leak_speed_mult = clamp(1.0 - (leaking_rate * 0.05), 0.3, 1.0)
	var final_velocity = move_dir * move_speed * leak_speed_mult
	
	# 직접 이동 (translate 대신 부모와 동일한 방식)
	position += final_velocity * delta
	
	# === 누수(Leaking) 데미지 ===
	if leaking_rate > 0:
		take_damage(leaking_rate * delta)
		
	# === 시각적 효과 (둥실둥실 및 기울기) ===
	_apply_visual_effects(delta)

func _apply_visual_effects(_delta: float) -> void:
	var time = Time.get_ticks_msec() * 0.001
	var bob_offset = sin(time * bobbing_speed) * bobbing_amplitude
	
	# 수면 위 높이 유지 (사망 시 tween에 의해 덮어씌워짐)
	if not is_dying:
		global_position.y = base_y + bob_offset
		rotation.z = (sin(time * bobbing_speed * 0.85) * rocking_amplitude) + tilt_offset
	
	# 항적 제어
	if wake_trail:
		wake_trail.emitting = move_speed > 0.5

func _update_logic_throttled() -> void:
	# 타겟 유효성 및 침몰 상태 체크
	if not is_instance_valid(target) or target.get("is_sinking"):
		target = null
		_find_player()
	
	# Separation 계산 (전체 함선 대상)
	separation_force = _calculate_separation()

## 주변 함선들로부터 멀어지려는 힘 계산
func _calculate_separation() -> Vector3:
	var force = Vector3.ZERO
	var neighbors = get_ships_cached(get_tree())
	var count = 0
	var separation_dist = 6.0 # 함선 폭/길이 고려한 간격
	
	var max_checks = min(neighbors.size(), 15)
	for i in range(max_checks):
		var other = neighbors[i]
		if other == self or not is_instance_valid(other) or other.get("is_dying"):
			continue
			
		var dist = global_position.distance_to(other.global_position)
		if dist < separation_dist and dist > 0.001:
			var push_dir = (global_position - other.global_position).normalized()
			# 가까울수록 더 강하게 밀어냄
			force += push_dir * (separation_dist - dist) / separation_dist
			count += 1
			
	if count > 0:
		force = (force / count) * 4.0 # 밀어내는 강도 계수
		
	return force

func _process_boarding(delta: float) -> void:
	if not is_instance_valid(boarding_target):
		die()
		return
	
	# 선체 고정 (플레이어 배 근처에 머물기)
	var target_pos = boarding_target.global_position
	var dist = global_position.distance_to(target_pos)
	
	if dist > 7.0: # 회피 거리(6.0)보다 약간 먼 거리까지 접근을 허용
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
		print("[Boarding] 밧줄이 팽팽해지다가 끊어졌습니다! 도선 중단.")
		_clear_ropes()
		is_boarding = false
		boarding_timer = 0.0
		# target은 이미 boarding_target이었으므로 그대로 유지됨
		
	# 밧줄 비주얼 업데이트
	_update_ropes()

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
		var start_global = s.global_position
		s.call_deferred("reparent", target_soldiers_node)
		
		# 점프 효과 (Tween)
		var jump_offset = Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-2.0, 2.0))
		var end_global = boarding_target.global_transform * jump_offset
		
		# 0.5초간 깔끔한 점프 애니메이션
		var tween = create_tween()
		tween.set_parallel(true)
		
		# X, Z 수평 이동
		tween.tween_property(s, "global_position:x", end_global.x, 0.5).set_trans(Tween.TRANS_LINEAR)
		tween.tween_property(s, "global_position:z", end_global.z, 0.5).set_trans(Tween.TRANS_LINEAR)
		
		# Y축 포물선 (위로 솟았다가 내려옴)
		var mid_y = max(start_global.y, end_global.y) + 2.0
		var y_tween = create_tween()
		y_tween.tween_property(s, "global_position:y", mid_y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		y_tween.tween_property(s, "global_position:y", end_global.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
		# 상태 설정
		if s.has_method("set_team"):
			# 이 배의 팀을 따름 (나포된 후라면 player, 적 상태라면 enemy)
			s.set_team(team)
		if s.get("is_stationary"): s.set("is_stationary", false)
		
		print("[Action] 병사 1명 월선! (팀: %s)" % team)
	else:
		# 더 이상 넘길 병사가 없으면 임무 조기 종료 (폐선 상태로 전환)
		print("[Status] 모든 병사 도선 완료. 무인선 상태로 표류합니다.")
		_become_derelict()


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		# 나포된 배가 아닌 진짜 플레이어 배(Ship.gd)를 찾음
		# is_player_controlled는 변수이므로 get()으로 확인
		if p.get("is_player_controlled") == true:
			if not p.get("is_sinking"):
				target = p
				break
	
	# 위에서 못 찾으면 (captured_minion이 아닌) player 그룹 중 아무나
	if not is_instance_valid(target):
		for p in players:
			if not p.is_in_group("captured_minion") and not p.get("is_sinking"):
				target = p
				break

## 나포(Capture) 처리
func capture_ship() -> void:
	if team == "player": return
	
	# 기존 함대 수 체크
	var minions = get_tree().get_nodes_in_group("captured_minion")
	if minions.size() >= 3:
		# ✅ 정원 초과 시 나포 대신 배를 파괴함
		print("[Limitation] 함대 정원 초과! 적함을 파괴합니다.")
		die()
		return
			
	team = "player"
	
	# ✅ 상태 초기화 및 긴급 수리 (나포 후 즉시 가라앉는 현상 방지)
	is_derelict = false
	is_burning = false
	fire_build_up = 0.0
	leaking_rate = 0.0
	hp = max(hp, max_hp * 0.3) # 최소 30% 체력으로 복구
	
	is_boarding = false
	_clear_ropes()
	move_speed = 3.2 # 플레이어 배 보조를 위해 약간 하향
	
	# 그룹 변경
	if is_in_group("enemy"): remove_from_group("enemy")
	add_to_group("player")
	add_to_group("captured_minion")
	
	# 자식들(대포, 병사) 팀 변경 및 UI 알림
	_update_children_team()
	_apply_minion_visuals()
	
	if is_instance_valid(cached_lm) and cached_lm.has_method("show_message"):
		cached_lm.show_message("적군 함선을 나포했습니다!", 3.0)
	
	# 플레이어 업그레이드 스탯 적용 (수리 등)
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("apply_fleet_stats_to_minion"):
		UpgradeManager.apply_fleet_stats_to_minion(self )
	
	# 나포 직후 플레이어를 찾아 즉시 따라가기 시작
	target = null
	_find_player()
	
	# ✅ 나포함 무장 자동 장착 (전방, 좌, 우)
	_equip_minion_cannons()
	
	print("[Capture] 나포 성공! 함대에 합류합니다. (target: %s)" % str(target))

func _equip_minion_cannons() -> void:
	if not cannon_scene: return
	
	# 장착 위치 정의 (전방, 좌측, 우측)
	var spawn_points = [
		{"pos": Vector3(0, 0.8, -3.5), "rot": 0}, # 전방
		{"pos": Vector3(-1.0, 0.8, -0.5), "rot": 90}, # 좌측 (90도 회전)
		{"pos": Vector3(1.0, 0.8, -0.5), "rot": - 90} # 우측 (-90도 회전)
	]
	
	for p in spawn_points:
		var cannon = cannon_scene.instantiate()
		add_child(cannon)
		cannon.position = p["pos"]
		cannon.rotation_degrees.y = p["rot"]
		# 팀 설정 (중요: 아군 오사 방지)
		if cannon.has_method("set_team"):
			cannon.set_team("player")
		elif "team" in cannon:
			cannon.set("team", "player")

func _update_children_team() -> void:
	# 대포 및 기타 컴포넌트 팀 변경 (재귀적 수행)
	for child in get_children():
		_recursive_set_team(child, "player")
			
	# 병사 팀 변경
	if has_node("Soldiers"):
		for s in $Soldiers.get_children():
			if s.has_method("set_team"):
				s.set_team("player")
				s.owned_ship = self

func _recursive_set_team(node: Node, new_team: String) -> void:
	if node.has_method("set_team"):
		node.set_team(new_team)
	if "team" in node:
		node.set("team", new_team)
	for child in node.get_children():
		_recursive_set_team(child, new_team)

func _apply_minion_visuals() -> void:
	# 돛 색상 변경 (흰색/파란색 조화) - instance uniform 사용
	var mesh = get_node_or_null("SailVisual/SailMesh") as MeshInstance3D
	if mesh:
		mesh.set_instance_shader_parameter("albedo", Color(0.9, 0.9, 1.0, 1.0)) # 밝은 하늘색/흰색
	
	# 연기 효과 중지 (폐선 상태에서 났던 것)
	if is_instance_valid(_fire_instance):
		_set_fire_emitting(false)

func _update_sail_visual(_delta: float) -> void:
	if sail_visual:
		# 돛 물리 시각적 회전 적용
		sail_visual.rotation.y = deg_to_rad(-sail_angle)

		# 적함도 바람의 영향을 시각적으로 표현하기 위해 간단한 계산
		var wind_intake = 1.0
		if is_instance_valid(WindManager):
			var wind_dir = WindManager.get_wind_direction()
			# 돛의 정면(바람이 들어오는 쪽)은 -Z 방향
			var sail_fwd = - sail_visual.global_transform.basis.z
			var sail_fwd_2d = Vector2(sail_fwd.x, sail_fwd.z).normalized()
			wind_intake = max(0.0, wind_dir.dot(sail_fwd_2d))
			
		var mesh = sail_visual.get_node_or_null("SailMesh") as MeshInstance3D
		if mesh:
			mesh.set_instance_shader_parameter("wind_strength", wind_intake)

func _auto_adjust_sail(delta: float) -> void:
	if not is_instance_valid(WindManager): return
	var wind_dir = WindManager.get_wind_direction()
	
	# ship.gd의 로직과 유사하게 자동 조절
	var ship_angle_rad = rotation.y
	var wind_angle_rad = atan2(wind_dir.x, wind_dir.y)
	
	var rel_wind_angle = rad_to_deg(wrapf(wind_angle_rad - ship_angle_rad, -PI, PI))
	var target_sail_angle = rel_wind_angle / 2.0
	target_sail_angle = clamp(target_sail_angle, -90, 90)
	
	sail_angle = move_toward(sail_angle, target_sail_angle, 60.0 * delta)

## 동양식 노(Ro/Yuloh) 8자 젓기 애니메이션
func _update_oar_visual(delta: float) -> void:
	var has_oars = oar_pivot_left or oar_pivot_right
	if not has_oars: return
	
	var is_moving = not is_derelict and move_speed > 0.5 and is_instance_valid(target)
	
	if is_moving:
		_oar_time += delta * 1.8 # 적함은 조금 더 느리고 장중하게 노를 저음
		
		# 8자 모션 (Lissajous curve 기반 Sculling)
		var sweep_angle = sin(_oar_time) * 0.2
		var twist_angle = sin(_oar_time * 2.0) * 0.1
		
		if oar_pivot_left:
			oar_pivot_left.rotation.x = sweep_angle
			oar_pivot_left.rotation.z = twist_angle
		if oar_pivot_right:
			oar_pivot_right.rotation.x = sweep_angle
			oar_pivot_right.rotation.z = - twist_angle
	else:
		if oar_pivot_left:
			oar_pivot_left.rotation.x = lerp_angle(oar_pivot_left.rotation.x, 0.0, delta * 2.0)
			oar_pivot_left.rotation.z = lerp_angle(oar_pivot_left.rotation.z, 0.0, delta * 2.0)
		if oar_pivot_right:
			oar_pivot_right.rotation.x = lerp_angle(oar_pivot_right.rotation.x, 0.0, delta * 2.0)
			oar_pivot_right.rotation.z = lerp_angle(oar_pivot_right.rotation.z, 0.0, delta * 2.0)

## 나포함 AI 로직 (플레이어 호위 및 적 탐지)
func _process_minion_ai(delta: float) -> void:
	if not is_instance_valid(target):
		_find_player()
		return
		
	# 1. 내 순번(Index) 확인 (캐시 사용으로 성능 최적화)
	var minions = get_minions_cached(get_tree())
	var my_index = minions.find(self )
	if my_index == -1: my_index = 0
	
	# 2. 진형에 따른 목표 상대 위치(Relative Target) 계산
	var offset = Vector3.ZERO
	var formation_dist = formation_spacing * (my_index + 1)
	
	match fleet_formation:
		Formation.COLUMN:
			# 장사진: 플레이어 뒤로 일렬 (인덱스에 따라 거리 증가)
			offset = Vector3(0, 0, formation_dist)
		Formation.WING:
			# 학익진: 좌우 번갈아가며 V자 배치
			var side = 1 if my_index % 2 == 0 else -1
			var row = floor(my_index / 2.0) + 1
			offset = Vector3(8.0 * side * row, 0, 8.0 * row)
	
	# 3. 월드 목표 지점 계산
	var target_pos = target.to_global(offset)
	var dist_to_target = global_position.distance_to(target_pos)
	
	# 플레이어의 실제 현재 속도 가져오기 (동기화 용도)
	var player_speed = target.get("current_speed")
	if player_speed == null: player_speed = 0.0
	
	# 4. 이동 및 회전 로직
	var direction = (target_pos - global_position).normalized()
	
	if dist_to_target > 1.5:
		# 목표 지점 바라보기 (부드럽게)
		var target_rot = atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * 2.5)
		
		# 속도 결정: 멀면 속도 보정, 가까우면 플레이어 속도에 수렴
		var final_move_speed = move_speed
		if dist_to_target > 10.0:
			final_move_speed *= 1.5 # 추격 모드
		elif dist_to_target < 5.0:
			# 플레이어 속도와 동기화 시도 (플레이어가 느리면 같이 느려짐)
			final_move_speed = max(player_speed * 1.1, 1.5)
		
		# 실제 이동
		translate(Vector3.FORWARD * final_move_speed * delta)
	elif dist_to_target > 0.4:
		# 근접 정렬 단계 (천천히 속도와 방향을 맞춤)
		var target_fwd = - target.global_transform.basis.z
		var head_rot = atan2(-target_fwd.x, -target_fwd.z)
		rotation.y = lerp_angle(rotation.y, head_rot, delta * 2.0)
		
		# 플레이어 속도에 근접하게 이동
		var sync_speed = lerp(move_speed * 0.5, player_speed, 0.5)
		translate(Vector3.FORWARD * sync_speed * delta)
	else:
		# 정지 또는 완전 동기화 상태
		var target_fwd = - target.global_transform.basis.z
		var head_rot = atan2(-target_fwd.x, -target_fwd.z)
		rotation.y = lerp_angle(rotation.y, head_rot, delta * 3.0)
		
		# 목표 지점에 거의 도달했으므로 플레이어 속도와 동일하게 유지
		if player_speed > 0.1:
			translate(Vector3.FORWARD * player_speed * delta)
	
	if wake_trail:
		wake_trail.emitting = dist_to_target > 2.0 or player_speed > 1.0

func _update_wave_sounds(delta: float) -> void:
	if is_dying or is_derelict: return
	
	# 현재 속도 대략적 파악 (적함/나포함 공통 로직을 위해)
	# 여기서는 move_speed와 이동 여부로 판단
	var speed = move_speed
	# 멈춰있을 때는 소리 안나게 (target 없거나 거리 가까워서 멈춘 경우 등)
	if not is_instance_valid(target): speed = 0.0
	
	if speed > 0.5:
		_wave_timer -= delta
		if _wave_timer <= 0:
			if is_instance_valid(AudioManager):
				AudioManager.play_sfx("wave_splash", global_position, randf_range(0.8, 1.2))
			var speed_mod = clamp(speed / 5.0, 0.4, 1.5)
			_wave_timer = randf_range(2.0, 4.5) / speed_mod

func _update_minion_respawn(delta: float) -> void:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4: # NOT DEAD
			alive_count += 1
			
	if alive_count < max_minion_crew:
		minion_respawn_timer += delta
		if minion_respawn_timer >= minion_respawn_interval:
			minion_respawn_timer = 0.0
			_respawn_minion_soldier()

func _respawn_minion_soldier() -> void:
	if not soldier_scene: return
	var s = soldier_scene.instantiate()
	$Soldiers.add_child(s)
	s.set_team("player")
	s.owned_ship = self
	var offset = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-2.0, 2.0))
	s.position = offset
	print("[Crew] 나포함 병사 자생적 보충 완료.")


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


func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0

func _board_ship(target_ship: Node3D) -> void:
	if is_dying or is_boarding: return
	
	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not (ship_node and ship_node.is_in_group("player")):
			return
			
	# === 아군 체크 (동일 팀이면 도선 무시) ===
	if ship_node.get("team") == team:
		return
		
	# === 플레이어 팀 체크 (상대 배에 올라타는 것 제한) ===
	# 나포(Capture) 상황이 아닌 일반 전투 중에는 아군 병사가 적선으로 넘어가지 않게 함
	if team == "player":
		return

	# === 무력화(폐선) 상태일 경우 나포 판정 ===
	if is_derelict:
		print("[Capture] 플레이어가 폐선에 접근! 나포 성공.")
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
			
		print("[Impact] 충격적 충돌 발생! 도선 시작.")

	# 2. 도선 상태 진입
	is_boarding = true
	boarding_target = ship_node
	boarding_timer = 0.0 # 즉시 첫 병사가 넘어가지 않도록 0으로 초기화
	
	# 그레플링 훅 생성
	if is_instance_valid(boarding_target):
		_spawn_ropes()

func _spawn_ropes() -> void:
	_clear_ropes()
	# 2~3개의 밧줄 생성
	var count = randi_range(2, 3)
	for i in range(count):
		var mesh_instance = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.04
		cylinder.bottom_radius = 0.04
		cylinder.height = 1.0 # 기본 길이는 1로 설정 (scale로 조절)
		mesh_instance.mesh = cylinder
		
		# 회색/갈색 로프 재질
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.3, 0.2)
		mat.roughness = 0.9
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # 투명도 허용
		mesh_instance.material_override = mat
		
		# 이 배의 자식으로 추가
		add_child(mesh_instance)
		
		# 초기 오프셋 (배의 측면 앞/뒤)
		var offset = Vector3(1.0, 0.8, lerp(-2.0, 2.0, float(i) / (count - 1)))
		# 플레이어 배가 어느 쪽에 있는지에 따라 X좌표 반전
		var to_target = (boarding_target.global_position - global_position).normalized()
		var local_to_target = global_transform.basis.inverse() * to_target
		if local_to_target.x < 0: offset.x = -1.0
		
		mesh_instance.position = offset
		rope_instances.append(mesh_instance)

func _update_ropes() -> void:
	if not is_instance_valid(boarding_target):
		_clear_ropes()
		return
		
	# 플레이어의 중앙 위치 대신, 선체 범위를 고려한 타겟 포인트 설정 (간략화)
	var target_center = boarding_target.global_position + Vector3(0, 0.5, 0)
	
	for rope in rope_instances:
		if not is_instance_valid(rope): continue
		
		var start_pos = rope.global_position
		var dist = start_pos.distance_to(target_center)
		
		# 방향 및 길이 업데이트
		rope.look_at(target_center, Vector3.UP)
		# CylinderMesh는 초기 상태에서 Y축이 위임. look_at은 -Z를 바라보게 함. 
		# 이를 보정하기 위해 X축으로 90도 회전
		rope.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
		
		# 스케일 조절 (CylinderMesh의 height가 1이므로 dist만큼 scale)
		rope.scale.y = dist # CylinderMesh의 height 방향이 스케일됨
		# 밧줄 굵기 유지
		rope.scale.x = 1.0
		rope.scale.z = 1.0
		
		# 밧줄의 중심이 중간에 오도록 위치 보정 (또는 Cylinder Mesh의 중심 이동)
		# Cylinder의 피봇은 중앙이므로, 시작점에서 타겟 방향으로 절반만큼 이동시킨 위치에 놓아야 함
		# rope.global_position은 이미 고정된 offset 위치이므로 
		# 로컬 스케일은 중앙 기준이라, 배에 붙은 지점을 한쪽 끝으로 만들려면 추가 오프셋 필요
		# CylinderMesh의 길이를 2로 하고 피봇을 한끝으로 옮기거나, 위치를 매 프레임 재계산
		var dir = (target_center - start_pos).normalized()
		rope.global_position = start_pos + dir * dist * 0.5

func _clear_ropes() -> void:
	for rope in rope_instances:
		if is_instance_valid(rope):
			rope.queue_free()
	rope_instances.clear()


# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
