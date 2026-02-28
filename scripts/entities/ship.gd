extends Node3D

## 배 핵심 로직: 실제 범선 물리, 러더 조향, 둥실둥실 효과

# === 이동 관련 ===
@export var max_speed: float = 10.0 # 최대 속도 하향 (12.0 -> 10.0)
@export var rowing_speed: float = 3.0 # 노 젓기 부스트 하향 (4.0 -> 3.0)
@export var acceleration: float = 1.5 # 가속도 하향 (2.0 -> 1.5)
@export var deceleration: float = 1.2 # 감속도 하향 (1.5 -> 1.2)

const CHASER_SHIP_SCRIPT = preload("res://scripts/entities/chaser_ship.gd")

# === 돛 관련 ===
@export var sail_angle: float = 0.0 # 돛 각도 (-90 ~ 90도, 배 기준)

# === 러더(키) 관련 ===
@export var rudder_angle: float = 0.0 # 러더 각도 (-45 ~ 45도)
@export var rudder_speed: float = 120.0 # 러더 회전 속도 (60 -> 120 상향)
@export var rudder_return_speed: float = 80.0 # 러더 자동 복귀 속도 (40 -> 80 상향)
@export var turn_rate: float = 50.0 # 최대 선회율 (25 -> 50 상향)

# === 둥실둥실 효과 ===
@export var bobbing_amplitude: float = 0.3
@export var bobbing_speed: float = 1.0
@export var rocking_amplitude: float = 0.05
@export var rudder_turn_speed: float = 120.0 # Seamanship에 의해 강화됨
@export var has_sextant: bool = false # Sextant 아이템 소지 여부

# === 노 젓기 ===
var is_rowing: bool = false
@export var rowing_stamina: float = 100.0
@export var stamina_drain_rate: float = 15.0 # 노 젓기 시 스태미나 소모 속도
@export var stamina_recovery_rate: float = 5.0

# === 내부 상태 ===
var current_speed: float = 0.0
var base_y: float = 0.0

# === 디버프 및 모디파이어 ===
var speed_mult: float = 1.0
var turn_mult: float = 1.0
var tilt_offset: float = 0.0
var stuck_objects: Array[Node3D] = []

	# === 선체 내구도 ===
@export var max_hull_hp: float = 100.0
var hull_hp: float = 100.0
@export var hull_regen_rate: float = 0.0 # 초당 HP 회복량
var is_sinking: bool = false
var is_burning: bool = false
var burn_timer: float = 0.0
var fire_build_up: float = 0.0 # 화재 누적 수치 (0 ~ 100)
var fire_threshold: float = 100.0 # 화재 발생 임계치
@export var max_crew_count: int = 4 # 아군 병사 정원
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
@export var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")
var _fire_instance: Node3D = null

# 노드 참조
@onready var sail_visual: Node3D = $SailVisual if has_node("SailVisual") else null
@onready var rudder_visual: Node3D = $RudderVisual if has_node("RudderVisual") else null
@onready var wake_trail: GPUParticles3D = $WakeTrail if has_node("WakeTrail") else null

# Oar (노) 레퍼런스 및 상태
@onready var oar_pivot_left: Node3D = $OarBaseLeft/OarPivot if has_node("OarBaseLeft/OarPivot") else null
@onready var oar_pivot_right: Node3D = $OarBaseRight/OarPivot if has_node("OarBaseRight/OarPivot") else null
var _oar_time: float = 0.0

@onready var ship_audio: AudioStreamPlayer3D = $ShipAudio if has_node("ShipAudio") else null

var hull_defense: float = 0.0 # 영구 업그레이드로 상승
var _cached_level_manager: Node = null
var _cached_hud: Node = null
var _cached_um: Node = null


# 부착된 선원(병사) 정보 (동적)# 길군악(노동요) 재생 상태
var _gilgunak_playing: bool = false
var current_crew_count: int = 4

var _flap_timer: float = 0.0
var _wave_timer: float = 2.0
var _current_wind_intake: float = 1.0 # 0.0(쳐짐) ~ 1.0(빵빵함)
var _oars_timer: float = 0.0
var _centrifugal_tilt: float = 0.0 # 원심력에 의한 기울기

# === 병사 자동 보충 ===
@export var crew_respawn_interval: float = 12.0 # 보충 주기 (초)
var crew_respawn_timer: float = 0.0

func _ready() -> void:
	base_y = position.y
	add_to_group("ships")
	
	# 영구 업그레이드 보너스 적용
	if is_in_group("player") or is_player_controlled:
		max_hull_hp += MetaManager.get_hull_hp_bonus()
		max_speed *= MetaManager.get_sail_speed_multiplier()
		hull_defense = MetaManager.get_hull_defense_bonus()
		print("[Ship] 플레이어 배 초기화 (HP: %.0f, 속도: %.1f, 방어: %.1f)" % [max_hull_hp, max_speed, hull_defense])
	
	
	if is_instance_valid(WindManager) and WindManager.has_signal("gust_started"):
		WindManager.gust_started.connect(_on_gust_started)
		
	hull_hp = max_hull_hp
	if is_player_controlled:
		add_to_group("player")
	
	_cache_references()

func _on_gust_started(_angle_offset: float) -> void:
	# 돌풍 시작 시 펄럭임 효과음 (플레이어 배만)
	if is_player_controlled and is_instance_valid(AudioManager):
		AudioManager.play_sfx("sail_flap", global_position, randf_range(0.9, 1.2))


func _cache_references() -> void:
	_cached_level_manager = get_tree().root.find_child("LevelManager", true, false)
	if _cached_level_manager and "hud" in _cached_level_manager:
		_cached_hud = _cached_level_manager.hud
		
	_cached_um = get_tree().root.find_child("UpgradeManager", true, false)


func _process(_delta: float) -> void:
	if is_sinking:
		return
	_update_sail_visual()
	_update_rudder_visual()
	_update_fire_effect()

func _update_fire_effect() -> void:
	# is_burning 상태일 때만 화재 파티클 발생 (불꽃 + 연기 분리형)
	if is_burning and not is_sinking:
		if not is_instance_valid(_fire_instance):
			_fire_instance = fire_effect_scene.instantiate() as Node3D
			add_child(_fire_instance)
			_fire_instance.position = Vector3(0, 1.0, 0.0)
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


# === 제어 관련 ===
@export var is_player_controlled: bool = true


func _physics_process(delta: float) -> void:
	if not is_sinking:
		_apply_bobbing_effect()
	if _flap_timer > 0:
		_flap_timer -= delta
		
	if current_speed > 0.5:
		_wave_timer -= delta
		if _wave_timer <= 0:
			if is_instance_valid(AudioManager):
				AudioManager.play_sfx("wave_splash", global_position, randf_range(0.8, 1.2))
			# 속도가 빠를수록 자주, 느릴수록 드문드문 (최소 1.5초 ~ 최대 4.5초)
			var speed_mod = clamp(current_speed / 5.0, 0.2, 2.0)
			_wave_timer = randf_range(1.5, 3.5) / speed_mod
		
	if is_sinking:
		return
	if is_player_controlled:
		_handle_input(delta)
	_update_movement(delta)
	_update_steering(delta)
	_update_rowing_stamina(delta)
	_update_oar_visual(delta)
	_update_hull_regeneration(delta)
	_update_burning_status(delta)
	_update_crew_respawn(delta)
	
	# 노 젓기 사운드 재생 (주기적)
	if is_rowing and rowing_stamina > 0:
		if _oars_timer <= 0:
			if is_instance_valid(AudioManager):
				AudioManager.play_sfx("oars_rowing", global_position, randf_range(0.95, 1.05))
			_oars_timer = 1.3
		else:
			_oars_timer -= delta
		
		# 길군악(노동요) 시작
		if rowing_stamina > 0.1 and not _gilgunak_playing:
			_gilgunak_playing = true
			if is_instance_valid(AudioManager):
				AudioManager.play_gilgunak(true)
	else:
		_oars_timer = 0.0
		# 길군악 정지
		if _gilgunak_playing:
			_gilgunak_playing = false
			if is_instance_valid(AudioManager):
				AudioManager.play_gilgunak(false)
## 병사 자동 보충 로직
func _update_crew_respawn(delta: float) -> void:
	if is_sinking: return
	
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	# 현재 살아있는 아군 병사 수 체크
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4 and child.get("team") == "player": # 4 = DEAD
			alive_count += 1
			
	if alive_count < max_crew_count:
		crew_respawn_timer += delta
		if crew_respawn_timer >= crew_respawn_interval:
			crew_respawn_timer = 0.0
			add_survivor() # 기존의 add_survivor 로직 재사용 (HUD 메시지 포함됨)
			print("[Crew] 자동 보충! 아군 병사가 합류했습니다. (현재: %d/%d)" % [alive_count + 1, max_crew_count])
	else:
		crew_respawn_timer = 0.0 # 정원이 차면 타이머 초기화

func _update_hull_regeneration(delta: float) -> void:
	if is_sinking or hull_regen_rate <= 0: return
	if hull_hp < max_hull_hp:
		hull_hp = move_toward(hull_hp, max_hull_hp, hull_regen_rate * delta)
		# 60프레임마다 HUD 업데이트 (최적화)
		if Engine.get_physics_frames() % 60 == 0:
			if _cached_hud and _cached_hud.has_method("update_hull_hp"):
				_cached_hud.update_hull_hp(hull_hp, max_hull_hp)


## 키보드 입력 처리
func _handle_input(delta: float) -> void:
	# Q/E: 돛 각도 조절
	# Q/E: 돛 각도 조절
	if Input.is_action_pressed("sail_left"): # Q
		adjust_sail_angle(-60.0 * delta) # 왼쪽(CCW)으로
	if Input.is_action_pressed("sail_right"): # E
		adjust_sail_angle(60.0 * delta) # 오른쪽(CW)으로
	
	# A/D: 러더 조작 (제자리 회전이 아닌 러더!)
	var steer_input = 0.0
	if Input.is_action_pressed("ship_left"):
		steer_input = -1.0
	elif Input.is_action_pressed("ship_right"):
		steer_input = 1.0
	
	steer(steer_input, delta)
	
	# W: 노 젓기 활성화, S: 비활성화 (꾹 누르고 있을 때만)
	if Input.is_action_pressed("row_forward"):
		set_rowing(true)
	elif Input.is_action_pressed("row_backward"):
		set_rowing(true) # S를 눌러도 후진 노젓기이므로 활성화.
	else:
		if is_rowing:
			set_rowing(false)
	
	# F: 함대 진형 토글 (장사진 <-> 학익진)
	if Input.is_key_pressed(KEY_F) and Engine.get_physics_frames() % 30 == 0: # 꾹 누름 방지
		_toggle_fleet_formation()

func _toggle_fleet_formation() -> void:
	if CHASER_SHIP_SCRIPT.fleet_formation == CHASER_SHIP_SCRIPT.Formation.COLUMN:
		CHASER_SHIP_SCRIPT.fleet_formation = CHASER_SHIP_SCRIPT.Formation.WING
		if _cached_level_manager: _cached_level_manager.show_message("함대 진형: 학익진 (Wing)", 2.0)
	else:
		CHASER_SHIP_SCRIPT.fleet_formation = CHASER_SHIP_SCRIPT.Formation.COLUMN
		if _cached_level_manager: _cached_level_manager.show_message("함대 진형: 장사진 (Column)", 2.0)


## 러더 조향 입력 처리
## direction: -1.0 (왼쪽), 1.0 (오른쪽), 0.0 (중립)
func steer(direction: float, delta: float) -> void:
	if direction < -0.1:
		rudder_angle = move_toward(rudder_angle, -45.0, rudder_speed * delta)
	elif direction > 0.1:
		rudder_angle = move_toward(rudder_angle, 45.0, rudder_speed * delta)
	else:
		# 입력이 없으면 러더 자동 복귀
		rudder_angle = move_toward(rudder_angle, 0.0, rudder_return_speed * delta)
	
	# 육분의: 자동 돛 조절
	if has_sextant:
		_auto_adjust_sail(delta)

func _auto_adjust_sail(delta: float) -> void:
	if not is_instance_valid(WindManager): return
	var wind_dir = WindManager.get_wind_direction()
	
	# WindManager: Clockwise (0=N, 90=E)
	# rotation.y: Counter-clockwise (0=N, -90=E)
	var wind_angle = rad_to_deg(atan2(wind_dir.x, -wind_dir.y))
	var ship_angle_ccw = rad_to_deg(rotation.y)
	
	# 선체 기준 상대 바람 각도 계산 (둘 다 시계방향 시스템으로 통일)
	# ship_angle_cw = -ship_angle_ccw
	# rel_wind_cw = wind_angle_cw - ship_angle_cw = wind_angle + ship_angle_ccw
	var rel_wind_angle = wrapf(wind_angle + ship_angle_ccw, -180, 180)
	
	# 이등분선(Bisector) 로직: 돛의 각도를 (상대 바람 각도 / 2)로 설정할 때 
	# 추력(dot(wind, sail) * dot(sail, ship_forward))이 최대가 됨
	var target_sail_angle = rel_wind_angle / 2.0
	
	# 돛 가동 범위 제한 (-90 ~ 90)
	target_sail_angle = clamp(target_sail_angle, -90, 90)
	
	# 부드럽게 조절 (회전 속도 상향)
	sail_angle = move_toward(sail_angle, target_sail_angle, 90.0 * delta)

func _calculate_separation() -> Vector3:
	var force = Vector3.ZERO
	var neighbors = get_tree().get_nodes_in_group("ships")
	var separation_dist = 6.0 # 함선 폭이 3, 길이가 8이므로 평균적인 안전 거리
	
	# 성능을 위해 주변 함선이 많을 때만 계산하거나, 최대 척수 제한
	var max_checks = min(neighbors.size(), 10)
	for i in range(max_checks):
		var other = neighbors[i]
		if other == self or not is_instance_valid(other) or other.get("is_sinking"):
			continue
			
		var dist = global_position.distance_to(other.global_position)
		if dist < separation_dist and dist > 0.1:
			var push_dir = (global_position - other.global_position).normalized()
			# 가까울수록 더 강하게 밀어내며, 거리에 따른 가중치 부여
			var strength = (separation_dist - dist) / separation_dist
			force += push_dir * strength * 5.0 # 밀어내는 강도 계수
			
	return force

## 이동 업데이트
func _update_movement(delta: float) -> void:
	var target_speed: float = _calculate_sail_speed()
	
	# 노 젓기: 기존 속도에 '추가' (Additive)
	if is_rowing and rowing_stamina > 0:
		target_speed += rowing_speed
	
	# 속도 보간
	target_speed *= speed_mult
	
	if target_speed > current_speed:
		current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, target_speed, deceleration * delta)
	
	# 배의 전방 방향으로 이동 (rotation.y 기준, -Z가 전방)
	#    Godot 좌표계 수정: Vector2(-sin, -cos) 사용
	var forward = Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	var velocity = forward * current_speed
	
	# === 겹침 방지 (Separation) 적용 ===
	var sep = _calculate_separation()
	velocity += sep
	
	position += velocity * delta
	
	# 물결 이펙트 (속도가 있거나 분리력이 있을 때)
	if wake_trail:
		wake_trail.emitting = current_speed > 0.5 or sep.length() > 0.2
	
	# 도선 중이거나 폐선일 때는 이동하지 않음
func _update_steering(delta: float) -> void:
	# 속도가 있어야 회전 가능! (실제 배처럼)
	if current_speed < 0.1:
		return
	
	# 선회 = 러더 각도 × 현재 속도 비율 × 선회 디버프
	var speed_ratio = current_speed / max_speed
	var actual_turn = (rudder_angle / 45.0) * turn_rate * speed_ratio * turn_mult * delta
	# 러더가 오른쪽이면 배는 왼쪽으로 (물이 러더를 밀어서)
	rotation.y -= deg_to_rad(actual_turn)


## 실제 범선 물리: 돛 기반 속도 계산
func _calculate_sail_speed() -> float:
	if not is_instance_valid(WindManager):
		return 0.0
	
	var wind_dir: Vector2 = WindManager.get_wind_direction()
	var wind_str: float = WindManager.get_wind_strength()
	
	# 1) 돛의 월드 각도 계산 (배 rotation.y + 돛 각도)
	#    주의: 시각적 회전(Visual)은 -sail_angle (시계방향)
	#    물리에서도 이를 반영하도록 -deg_to_rad(sail_angle) 사용
	var ship_angle_rad = rotation.y
	var sail_world_rad = ship_angle_rad - deg_to_rad(sail_angle)
	
	# 2) 돛의 법선 벡터 (돛 면에 수직인 방향)
	#    화살표가 배의 뒤쪽(+Z)을 가리킴 (Local +Z)
	#    Visual rotation과 World angle 계산을 일치시키기 위해 음수 적용
	var sail_normal = - Vector2(sin(sail_world_rad), cos(sail_world_rad))
	
	# 3) 바람이 돛에 가하는 힘 (수직 성분)
	#    내적 (dot product):
	#    - 양수: 바람이 화살표 방향으로 붊 (순풍/측풍) -> 추진력 발생
	#    - 음수: 바람이 화살표 반대로 붊 (역풍/맞바람) -> 추진력 없음
	var dot_prod = wind_dir.dot(sail_normal)
	var wind_force = max(0.0, dot_prod)
	
	# 4) 배 전방 벡터
	var ship_forward = Vector2(-sin(ship_angle_rad), -cos(ship_angle_rad))
	
	# 5) 돛이 받은 힘을 배 전방으로 투영
	#    돛이 배 전방을 향해 밀어주는 정도
	var forward_component = sail_normal.dot(ship_forward)
	
	# 6) 최종 추진력
	#    wind_force(바람 받는 양) * forward_component(앞으로 미는 효율)
	#    forward_component가 음수면(돛이 뒤를 향함) 배가 뒤로 가진 않음 (0 처리)
	var thrust = wind_force * max(0.0, forward_component)
	
	# 시각 효과를 위해 바람 받는 양 저장
	_current_wind_intake = wind_force
	
	# 디버그: 물리 계산 값 확인
	if Input.is_action_just_pressed("ui_accept"):
		print("=== Physics Debug ===")
		print("Wind Dir: ", wind_dir)
		print("Sail Angle: ", sail_angle, " deg")
		print("Sail Arrow (Normal): ", sail_normal)
		print("Ship Forward: ", ship_forward)
		print("Dot Product (wind·sail): ", dot_prod)
		print("Wind Force: ", wind_force)
		print("Forward Component: ", forward_component)
		print("Thrust: ", thrust)
		print("Current Speed: ", current_speed)
		print("=====================")

	return thrust * max_speed * wind_str


## 둥실둥실 시각 효과 (반드시 _physics_process에서 호출할 것)
func _apply_bobbing_effect() -> void:
	var time = Time.get_ticks_msec() * 0.001
	var bob_offset = sin(time * bobbing_speed) * bobbing_amplitude
	
	# 물리 충돌(Jitter)을 방지하기 위해 반드시 _physics_process에서 position.y를 직접 갱신
	position.y = base_y + bob_offset
	
	# 원심력에 의한 기울기 (회전 방향의 반대로 기움)
	var turn_factor = rudder_angle / 45.0
	var speed_ratio = clamp(current_speed / max_speed, 0.0, 1.0)
	var target_centrifugal = deg_to_rad(-turn_factor * speed_ratio * 12.0) # 최대 12도 기울어짐
	
	var dt = get_physics_process_delta_time()
	_centrifugal_tilt = lerp(_centrifugal_tilt, target_centrifugal, 2.5 * dt)
	
	# 기본 요동 + 장군전 등에 의한 기울기(tilt_offset) + 원심력 회전 기울기
	rotation.z = (sin(time * bobbing_speed * 0.8) * rocking_amplitude) + tilt_offset + _centrifugal_tilt


## 돛 시각화 업데이트
func _update_sail_visual() -> void:
	if sail_visual:
		# 시각적으로 반대로 (E키 = 시계방향)
		sail_visual.rotation.y = deg_to_rad(-sail_angle)
		
		# 돛 물리 시뮬레이션 (Shader 연동) - instance uniform은 MeshInstance3D에 직접 적용
		var mesh = sail_visual.get_node_or_null("SailMesh") as MeshInstance3D
		if mesh:
			mesh.set_instance_shader_parameter("wind_strength", _current_wind_intake)


## 러더 시각화 업데이트
func _update_rudder_visual() -> void:
	if rudder_visual:
		rudder_visual.rotation.y = deg_to_rad(rudder_angle)

## 동양식 노(Ro/Yuloh) 8자 젓기 애니메이션
func _update_oar_visual(delta: float) -> void:
	var has_oars = oar_pivot_left or oar_pivot_right
	if not has_oars: return
	
	# 수동으로 젓고 있거나, 배가 어느 정도 속도로 이동 중일 때 노를 저음
	var is_actively_rowing = is_rowing and rowing_stamina > 0
	var is_moving_fast = current_speed > 1.0
	
	if is_actively_rowing or is_moving_fast:
		var row_speed = 2.2 if is_actively_rowing else 1.2 # 수동일 때 더 역동적이지만 너무 빠르지 않게
		_oar_time += delta * row_speed
		
		# 8자 모션 (Lissajous curve 기반 Sculling)
		var sweep_angle = sin(_oar_time) * 0.2 # 진폭을 0.4 -> 0.2로 줄여 얌전하게
		var twist_angle = sin(_oar_time * 2.0) * 0.1 # 비틀기 진폭도 0.2 -> 0.1로 감소
		
		# 좌우(Yaw) 대신 앞뒤(Pitch - X축)로 흔들고(sweep), Z축으로 비틂(twist)
		if oar_pivot_left:
			oar_pivot_left.rotation.x = sweep_angle
			oar_pivot_left.rotation.z = twist_angle
		if oar_pivot_right:
			# 양쪽 노가 동시에 앞뒤로 움직이도록 sweep_angle은 동일하게 적용
			oar_pivot_right.rotation.x = sweep_angle
			oar_pivot_right.rotation.z = - twist_angle
	else:
		# 노를 젓지 않을 때는 천천히 중앙으로 복귀
		if oar_pivot_left:
			oar_pivot_left.rotation.x = lerp_angle(oar_pivot_left.rotation.x, 0.0, delta * 2.0)
			oar_pivot_left.rotation.z = lerp_angle(oar_pivot_left.rotation.z, 0.0, delta * 2.0)
		if oar_pivot_right:
			oar_pivot_right.rotation.x = lerp_angle(oar_pivot_right.rotation.x, 0.0, delta * 2.0)
			oar_pivot_right.rotation.z = lerp_angle(oar_pivot_right.rotation.z, 0.0, delta * 2.0)

## 노 젓기 스태미나 관리
func _update_rowing_stamina(delta: float) -> void:
	if is_rowing and rowing_stamina > 0:
		rowing_stamina -= 10.0 * delta # 노를 저으면 스태미나 소모 (기존 15 -> 10으로 완화)
		rowing_stamina = max(0.0, rowing_stamina)
		if rowing_stamina <= 0:
			is_rowing = false
	elif not is_rowing and rowing_stamina < 100.0:
		rowing_stamina += 15.0 * delta # 쉬면 스태미나 회복 (기존 10 -> 15로 상향)
		rowing_stamina = min(100.0, rowing_stamina)


## === 공개 메서드 ===

## 돛 각도 설정
func set_sail_angle(angle: float) -> void:
	sail_angle = clamp(angle, -90.0, 90.0)


## 돛 각도 조정
func adjust_sail_angle(delta_angle: float) -> void:
	if abs(delta_angle) > 0.0 and _flap_timer <= 0:
		if is_instance_valid(AudioManager):
			AudioManager.play_sfx("sail_flap", global_position, randf_range(0.8, 1.2))
		_flap_timer = randf_range(1.5, 3.0)
		
	set_sail_angle(sail_angle + delta_angle)


## 노 젓기 활성화/비활성화
func set_rowing(active: bool) -> void:
	if active and rowing_stamina > 0:
		is_rowing = true
	else:
		is_rowing = false


## 노 젓기 토글
func toggle_rowing() -> void:
	if rowing_stamina > 0:
		is_rowing = not is_rowing


## === 선체 내구도 시스템 ===

## 데미지 처리 (인터페이스 통일)
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_sinking:
		return
		
	# 방어력 적용 (최소 1 데미지)
	var final_damage = maxf(amount - hull_defense, 1.0)
	hull_hp -= final_damage
	
	# 피격 이펙트 (파편)
	if wood_splinter_scene:
		var splinter = wood_splinter_scene.instantiate()
		get_tree().root.add_child(splinter)
		if hit_position != Vector3.ZERO:
			splinter.global_position = hit_position + Vector3(0, 0.5, 0)
		else:
			var offset = Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1))
			splinter.global_position = global_position + offset
		splinter.rotation.y = randf() * TAU
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(final_damage)
	
	# HUD 업데이트
	if _cached_hud and _cached_hud.has_method("update_hull_hp"):
		_cached_hud.update_hull_hp(hull_hp, max_hull_hp)
	
	# 피격 플래시 (빨간 깜빡임) 및 흔들림
	_flash_damage(final_damage)
	
	if hull_hp <= 0:
		_game_over()
	
## 누수(DoT) 추가 및 제거
func add_leak(_amount: float) -> void:
	# 아군 배는 기본 regen이 있으므로, 화재 도트데미지를 regen 감소분이나 별도 데미지로 처리 가능. 임시로 regen 깎는 형태로 도입하거나 직접 데미지를 가함.
	# 지금은 별도 leaking 변수 없이, 주기적으로 데미지를 주어야 하지만 임시로 무시하거나 틱 데미지 구현 (필요시 추가)
	pass

func remove_leak(_amount: float) -> void:
	pass

## 화염 데미지 및 상태 이상 (Fire Status Effect)
func take_fire_damage(_dps: float, duration: float) -> void:
	if is_burning:
		burn_timer = max(burn_timer, duration)
		return
		
	# 누적 수치 증가 (데미지와 지속 시간에 비례)
	fire_build_up += duration * 6.0 # 화살 한 대당 약 30 누적 (약 4발 정도면 점화)
	
	if fire_build_up >= fire_threshold:
		is_burning = true
		fire_build_up = fire_threshold
		burn_timer = duration
		print("[Status] 배에 불이 붙었습니다!")

func _update_burning_status(delta: float) -> void:
	if is_burning:
		# 화상 중일 때 체력을 조금씩 깎습니다.
		hull_hp = move_toward(hull_hp, 0, 2.0 * delta)
		
		# 60프레임마다 HUD 업데이트 (최적화)
		if Engine.get_physics_frames() % 60 == 0:
			if _cached_hud and _cached_hud.has_method("update_hull_hp"):
				_cached_hud.update_hull_hp(hull_hp, max_hull_hp)
				
		if hull_hp <= 0:
			_game_over()
				
		burn_timer -= delta
		if burn_timer <= 0:
			is_burning = false
			fire_build_up = 0.0 # 불이 꺼지면 누적치 초기화
	else:
		# 불이 붙지 않은 상태라면 누적 수치 서서히 감소 (자연 소화/냉각)
		if fire_build_up > 0:
			fire_build_up = move_toward(fire_build_up, 0, 15.0 * delta)

## 선체 HP 비율 반환
func get_hull_ratio() -> float:
	return hull_hp / max_hull_hp


## 피격 시 빨간 깜빡임 및 흔들림
func _flash_damage(amount: float = 10.0) -> void:
	# 배 기울기 충격 효과 (데미지량에 비례하여 강도 조절)
	# 10.0 데미지를 기준으로 배율 계산 (최소 0.15배 ~ 최대 2.0배)
	var shake_mult = clamp(amount / 10.0, 0.15, 2.0)
	
	var shake_tween = create_tween()
	shake_tween.tween_property(self , "rotation:z", rocking_amplitude * 3.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", -rocking_amplitude * 2.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", 0.0, 0.2)


## 게임 오버 (침몰)
func _game_over() -> void:
	if is_sinking:
		return
	is_sinking = true
	is_player_controlled = false
	current_speed = 0.0
	
	print("[Critical] 배가 침몰합니다!")
	
	# 침몰 애니메이션 (기울어지면서 깊게 가라앉음 + 페이드 아웃)
	var sink_tween = create_tween()
	sink_tween.set_parallel(true)
	var sink_duration = 6.0
	sink_tween.tween_property(self , "position:y", position.y - 12.0, sink_duration).set_ease(Tween.EASE_IN)
	sink_tween.tween_property(self , "rotation:z", deg_to_rad(25.0), sink_duration).set_ease(Tween.EASE_IN)
	sink_tween.tween_property(self , "rotation:x", deg_to_rad(15.0), sink_duration).set_ease(Tween.EASE_IN)
	
	# (메쉬 투명도 조절 대신 셰이더 수심 효과로 대체)
	
	sink_tween.set_parallel(false)
	sink_tween.tween_callback(func():
		# 플레이어 배는 queue_free 하지 않음 (게임오버 상태 유지 필요할 수 있음)
		# 다만 시각적으로는 완전히 가라앉은 상태
		pass
	)

# 재귀적으로 모든 메쉬의 transparency속성을 트윈합니다.
func _fade_out_meshes(node: Node, tween: Tween, duration: float) -> void:
	if node is MeshInstance3D:
		tween.parallel().tween_property(node, "transparency", 1.0, duration).set_ease(Tween.EASE_IN)
	
	for child in node.get_children():
		_fade_out_meshes(child, tween, duration)
	
	# HUD에 게임 오버 표시
	if _cached_hud and _cached_hud.has_method("show_game_over"):
		_cached_hud.show_game_over()
	
	# 실시간 저장이므로 여기서는 메시지만 처리
	if _cached_level_manager and _cached_level_manager.get("current_score") != null:
		print("[GameOver] 침몰! 현재 판에서 %d 골드 획득" % _cached_level_manager.current_score)


func _find_hud() -> Node:
	if _cached_hud: return _cached_hud
	if _cached_level_manager and _cached_level_manager.get("hud"):
		return _cached_level_manager.hud
	return null


## 장군전 등 물체가 배에 박혔을 때 호출
func add_stuck_object(obj: Node3D, s_mult: float, t_mult: float) -> void:
	if not obj in stuck_objects:
		stuck_objects.append(obj)
		speed_mult *= s_mult
		turn_mult *= t_mult
		
		# 기울기 추가 (랜덤 방향으로 5~10도)
		var tilt_dir = 1.0 if obj.global_position.x > global_position.x else -1.0
		var new_tilt = deg_to_rad(randf_range(5.0, 10.0)) * tilt_dir
		
		# 전체 기울기 제한 (최대 12도 정도로 캡 적용)
		tilt_offset = clamp(tilt_offset + new_tilt, -deg_to_rad(12.0), deg_to_rad(12.0))
		
		print("[Impact] 배에 물체가 박힘! (현재 속도 배율: %.2f, 선회 배율: %.2f, 최종 기울기: %.1f)" % [speed_mult, turn_mult, rad_to_deg(tilt_offset)])
		
		# HUD 알림 (선택 사항)
		if _cached_hud and _cached_hud.has_method("show_message"):
			_cached_hud.show_message("!! 기동성 저하 기동성 저하 !!", 2.0)

func remove_stuck_object(obj: Node3D, s_mult: float, t_mult: float) -> void:
	if obj in stuck_objects:
		stuck_objects.erase(obj)
		# 복구 (나누기)
		speed_mult /= s_mult
		turn_mult /= t_mult
		speed_mult = min(1.0, speed_mult)
		turn_mult = min(1.0, turn_mult)
		# 기울기 원복 (완전 복구는 아닐 수 있지만 일단 0으로 수렴)
		tilt_offset *= 0.5
		if stuck_objects.is_empty():
			tilt_offset = 0.0

## 폐선 나포 (Capture Derelict Ship) 보상 처리
func capture_derelict_ship() -> void:
	print("[Capture] 폐선 나포 성공! 보상을 획득합니다.")
	# 1. 아군 전원 체력 회복
	var soldiers_node = get_node_or_null("Soldiers")
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.has_method("heal_full") and child.get("current_state") != 4: # 4 = DEAD
				child.heal_full()
	
	# 2. 병사 1명 보충 (최대치 초과 안하게)
	# ship.gd에는 soldier_scene이 export 되어있지 않으므로, LevelManager나 임시 캐싱본 활용 필수
	# 기존 replenish_crew()에서 주입받는 구조이므로 여기선 LevelManager를 통해 Instantiate 시도
	var alive_count = 0
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.get("current_state") != 4: alive_count += 1
		
		if alive_count < max_crew_count and is_instance_valid(_cached_level_manager) and _cached_level_manager.has_node("LevelLogic"):
			# 약간의 하드코딩 우회 (보통 GameManager/LevelManager 등에 soldier_scene이 있음)
			# 또는 chaser_ship.gd처럼 load("res://scenes/soldier.tscn") 사용
			var fallback_scene = preload("res://scenes/soldier.tscn")
			var s = fallback_scene.instantiate()
			soldiers_node.add_child(s)
			s.set_team("player")
			var offset = Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-2.5, 2.5))
			s.position = offset
			if is_instance_valid(_cached_um) and _cached_um.has_method("_apply_current_stats_to_soldier"):
				_cached_um._apply_current_stats_to_soldier(s)
			print("[Crew] 포로 구출! 아군 병사 1명 합류.")
			
	# 3. 사운드 및 피드백 재생
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("treasure_collect", global_position) # 획득음 재활용

## 병사 보충 (Maintenance 전용)
func replenish_crew(soldier_scene: PackedScene) -> void:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node or not soldier_scene: return
	
	# 현재 살아있는 아군 병사 수 체크
	var alive_count = 0
	for child in soldiers_node.get_children():
		var is_alive = child.get("current_state") != 4
		var is_player = child.get("team") == "player"
		
		if is_alive and is_player:
			alive_count += 1
		elif not is_alive:
			# 죽은 병사 시체는 제거 (새로 뽑기 위해)
			child.queue_free()
	
	# 부족한 만큼 생성
	var to_add = max_crew_count - alive_count # 부족한 만큼 생성
	for i in range(to_add):
		var s = soldier_scene.instantiate()
		soldiers_node.add_child(s)
		s.set_team("player")
		var offset = Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-2.5, 2.5))
		s.position = offset
		
		# 업그레이드 매니저 통해서 현재 스탯 적용
		if is_instance_valid(_cached_um) and _cached_um.has_method("_apply_current_stats_to_soldier"):
			_cached_um._apply_current_stats_to_soldier(s)
	
	print("[Crew] 병사 보충 완료! (현재: %d/%d)" % [max_crew_count, max_crew_count])

## 생존자 구조 및 병사 합류 처리
func add_survivor() -> bool:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return false
	
	# 현재 살아있는 병사 수 체크
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4: # NOT DEAD
			alive_count += 1
		else:
			# 죽은 병사는 미리 제거
			child.queue_free()
			
	if alive_count >= max_crew_count:
		print("[Crew] 정원 초과 합류! (현재 인원: %d/%d)" % [alive_count + 1, max_crew_count])
		# 정원 초과 시에도 합류는 허용하되 메시지만 다르게 표시 가능
		
	# 병사 생성
	var soldier_scene = load("res://scenes/soldier.tscn")
	var s = soldier_scene.instantiate()
	soldiers_node.add_child(s)
	s.set_team("player")
	
	# 위치 설정 (갑판 위 랜덤)
	var offset = Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-2.5, 2.5))
	s.position = offset
	
	# 업그레이드 스탯 적용
	if is_instance_valid(_cached_um) and _cached_um.has_method("_apply_current_stats_to_soldier"):
		_cached_um._apply_current_stats_to_soldier(s)
		
	print("[Rescue] 생존자 구조 성공! 아군 병사 1명 합류. (현재: %d/%d)" % [alive_count + 1, max_crew_count])
	
	# HUD 메시지 표시
	if _cached_hud and _cached_hud.has_method("show_message"):
		_cached_hud.show_message("생존자 구조 완료!", 2.0)
	
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("soldier_hit", global_position, 1.5) # 약간 높은 피치로 구조음 대용
		
	return true
