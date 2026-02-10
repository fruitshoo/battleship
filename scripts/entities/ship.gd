extends Node3D

## 배 핵심 로직: 실제 범선 물리, 러더 조향, 둥실둥실 효과

# === 이동 관련 ===
@export var max_speed: float = 12.0 # 최대 속도 (실제 계수 적용 시 약 8.4)
@export var rowing_speed: float = 2.0 # 노 젓기 속도
@export var acceleration: float = 2.0 # 가속도
@export var deceleration: float = 1.5 # 감속도

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

# === 노 젓기 ===
var is_rowing: bool = false
@export var rowing_stamina: float = 100.0
@export var stamina_drain_rate: float = 10.0
@export var stamina_recovery_rate: float = 5.0

# === 내부 상태 ===
var current_speed: float = 0.0
var base_y: float = 0.0

# 노드 참조
@onready var sail_visual: Node3D = $SailVisual if has_node("SailVisual") else null
@onready var rudder_visual: Node3D = $RudderVisual if has_node("RudderVisual") else null


func _ready() -> void:
	base_y = position.y
	if is_player_controlled:
		add_to_group("player")


func _process(_delta: float) -> void:
	_apply_bobbing_effect()
	_update_sail_visual()
	_update_rudder_visual()


# === 제어 관련 ===
@export var is_player_controlled: bool = true


func _physics_process(delta: float) -> void:
	if is_player_controlled:
		_handle_input(delta)
	_update_movement(delta)
	_update_steering(delta)
	_update_rowing_stamina(delta)


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
	
	# W: 노 젓기 활성화, S: 비활성화
	if Input.is_action_pressed("row_forward"):
		set_rowing(true)
	elif Input.is_action_pressed("row_backward"):
		set_rowing(false)


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


## 이동 업데이트
func _update_movement(delta: float) -> void:
	var target_speed: float = 0.0
	
	if is_rowing and rowing_stamina > 0:
		target_speed = rowing_speed
	else:
		target_speed = _calculate_sail_speed()
	
	# 속도 보간
	if target_speed > current_speed:
		current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	else:
		current_speed = move_toward(current_speed, target_speed, deceleration * delta)
	
	# 배의 전방 방향으로 이동 (rotation.y 기준, -Z가 전방)
	#    Godot 좌표계 수정: Vector2(-sin, -cos) 사용
	var forward = Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	position += forward * current_speed * delta
	
	# 디버그: 배 움직임 확인 (5초마다)
	if Engine.get_physics_frames() % 300 == 0 and current_speed > 0.1:
		print("🚢 Ship Position: ", position, " Speed: ", current_speed)
		
	# 웨이크 트레일 제어
	var wake_trail = $WakeTrail
	if wake_trail:
		wake_trail.emitting = current_speed > 0.5


## 러더 기반 조향
func _update_steering(delta: float) -> void:
	# 속도가 있어야 회전 가능! (실제 배처럼)
	if current_speed < 0.1:
		return
	
	# 선회 = 러더 각도 × 현재 속도 비율
	var speed_ratio = current_speed / max_speed
	var actual_turn = (rudder_angle / 45.0) * turn_rate * speed_ratio * delta
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


## 둥실둥실 시각 효과
func _apply_bobbing_effect() -> void:
	var time = Time.get_ticks_msec() * 0.001
	var bob_offset = sin(time * bobbing_speed) * bobbing_amplitude
	position.y = base_y + bob_offset
	rotation.z = sin(time * bobbing_speed * 0.8) * rocking_amplitude


## 돛 시각화 업데이트
func _update_sail_visual() -> void:
	if sail_visual:
		# 시각적으로 반대로 (E키 = 시계방향)
		sail_visual.rotation.y = deg_to_rad(-sail_angle)


## 러더 시각화 업데이트
func _update_rudder_visual() -> void:
	if rudder_visual:
		rudder_visual.rotation.y = deg_to_rad(rudder_angle)


## 노 젓기 스태미나 관리
func _update_rowing_stamina(delta: float) -> void:
	if is_rowing and rowing_stamina > 0:
		rowing_stamina -= stamina_drain_rate * delta
		rowing_stamina = max(0.0, rowing_stamina)
		if rowing_stamina <= 0:
			is_rowing = false
	elif not is_rowing and rowing_stamina < 100.0:
		rowing_stamina += stamina_recovery_rate * delta
		rowing_stamina = min(100.0, rowing_stamina)


## === 공개 메서드 ===

## 돛 각도 설정
func set_sail_angle(angle: float) -> void:
	sail_angle = clamp(angle, -90.0, 90.0)


## 돛 각도 조정
func adjust_sail_angle(delta_angle: float) -> void:
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
