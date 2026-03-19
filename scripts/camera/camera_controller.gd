extends Camera3D

## 3rd Person Camera Controller
## 타겟(배)을 부드럽게 따라다니며 줌/회전 기능 제공

@export var target_path: NodePath
@export_group("Follow Settings")
@export_range(0.5, 12.0) var smooth_speed: float = 3.5
@export_range(-80.0, -20.0) var pitch_degrees: float = -45.0
@export_range(0.0, 30.0) var lead_distance: float = 7.5
@export_range(0.0, 10.0) var lead_smooth_speed: float = 4.5
@export var offset: Vector3 = Vector3(0, 15, 20)

@export_group("Control Settings")
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 10.0
@export var max_zoom: float = 88.0 # +10% 줌아웃 (기존 80.0)
@export_range(1.0, 20.0) var zoom_smooth_speed: float = 12.0
@export var rotation_sensitivity: float = 0.005

@export_group("Fog Settings")
@export_range(0.0, 300.0) var fog_begin_min: float = 90.0
@export_range(0.0, 600.0) var fog_end_min: float = 240.0
@export_range(0.0, 10.0) var fog_begin_zoom_multiplier: float = 2.2
@export_range(0.0, 12.0) var fog_end_zoom_multiplier: float = 6.0

var target: Node3D = null
var current_zoom: float = 0.0
var target_zoom: float = 0.0
var _cam_rotation: Vector2 = Vector2.ZERO
var _smoothed_look_target: Vector3 = Vector3.ZERO

var shake_intensity: float = 0.0
var shake_timer: float = 0.0
var shake_duration: float = 0.0
var _last_zoom: float = -1.0 # 마지막으로 포그가 업데이트된 줌 레벨
var audio_listener: AudioListener3D

func _ready() -> void:
	if target_path:
		target = get_node_or_null(target_path)
	
	current_zoom = offset.length()
	target_zoom = current_zoom
	
	# 초기 회전값 설정
	var rot = transform.basis.get_euler()
	_cam_rotation.x = rot.y
	_cam_rotation.y = rot.x
	if is_instance_valid(target):
		_smoothed_look_target = target.global_position
	
	# 카메라 줌에 따른 오디오 볼륨 불균형 해결을 위한 독립적인 리스너 추가
	audio_listener = AudioListener3D.new()
	add_child(audio_listener)
	audio_listener.make_current()

func _input(event: InputEvent) -> void:
	# 마우스 휠로 줌
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom + zoom_speed, min_zoom, max_zoom)
	
	# 트랙패드 핀치로 줌 (Mac)
	if event is InputEventMagnifyGesture:
		var pinch_zoom_speed = zoom_speed * 5.0
		target_zoom = clamp(target_zoom - (event.factor - 1.0) * pinch_zoom_speed, min_zoom, max_zoom)
	
	# 트랙패드 두 손가락 팬으로 orbit 회전 (Mac)
	if event is InputEventPanGesture:
		_cam_rotation.x -= event.delta.x * rotation_sensitivity * 0.5
		_cam_rotation.y -= event.delta.y * rotation_sensitivity * 0.5
		_cam_rotation.y = clamp(_cam_rotation.y, -PI / 2 + 0.1, 0)
	
	# 우클릭 또는 휠클릭 드래그로 회전
	if event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		_cam_rotation.x -= event.relative.x * rotation_sensitivity
		_cam_rotation.y -= event.relative.y * rotation_sensitivity
		_cam_rotation.y = clamp(_cam_rotation.y, -PI / 2 + 0.1, 0) # 땅 밑으로 안 가게 제한

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	
	current_zoom = move_toward(current_zoom, target_zoom, zoom_smooth_speed * delta)
	
	# 1. 타겟 위치 + 진행 방향 리드
	var target_pos = _get_desired_look_target()
	_smoothed_look_target = _smoothed_look_target.lerp(target_pos, clampf(lead_smooth_speed * delta, 0.0, 1.0))
	
	# 2. 쿼터뷰 고정 각도 (45도 위에서, 약간 뒤에서)
	# 수평 회전은 유저가 조절 가능, 수직 각도는 고정
	var quarter_view_angle = deg_to_rad(pitch_degrees)
	
	# 우클릭 드래그로 수평 회전만 가능
	var rot_basis = Basis.from_euler(Vector3(quarter_view_angle, _cam_rotation.x, 0))
	var final_offset = rot_basis * Vector3(0, 0, current_zoom)
	
	var desired_position = _smoothed_look_target + final_offset
	
	# 3. 부드러운 이동
	global_position = global_position.lerp(desired_position, clampf(smooth_speed * delta, 0.0, 1.0))
	
	# 4. 항상 타겟 바라보기
	look_at(_smoothed_look_target, Vector3.UP)
	
	# 5. 동적 포그 조절 (줌에 따라 안개 거리 조정)
	_update_dynamic_fog()
	
	# 오디오 리스너 위치 고정 (카메라 줌에 상관없이 타겟 근처 유지하되, 약간의 거리감 허용)
	if is_instance_valid(audio_listener):
		# 카메라는 타겟에서 current_zoom 만큼 물러나 있으므로,
		# 로컬 공간에서 앞으로(-Z 방향) 당겨주면 타겟 쪽으로 갑니다.
		# 완전히 0 Z에 두면 거리감이 전혀 없으므로, 줌 아웃의 30% 정도만 거리가 멀어지게 설정합니다.
		var listener_distance = current_zoom * 0.3
		listener_distance = max(listener_distance, min_zoom)
		audio_listener.position = Vector3(0, 0, -current_zoom + listener_distance)
	
	# 6. 화면 흔들림 (Screen Shake)
	if shake_timer > 0:
		shake_timer -= delta
		var damping = shake_timer / max(0.001, shake_duration)
		var shake_offset = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * shake_intensity * damping
		global_position += shake_offset

func shake(intensity: float, duration: float) -> void:
	shake_intensity = intensity
	shake_duration = duration
	shake_timer = duration

func _get_desired_look_target() -> Vector3:
	var base_target := target.global_position
	var speed_ratio := 0.0
	var current_speed_value := 0.0
	var max_speed_value := 0.0
	
	if "current_speed" in target:
		current_speed_value = float(target.get("current_speed"))
	if "max_speed" in target:
		max_speed_value = maxf(float(target.get("max_speed")), 0.01)
	if max_speed_value > 0.0:
		speed_ratio = clampf(current_speed_value / max_speed_value, 0.0, 1.0)
	
	if speed_ratio <= 0.01 or lead_distance <= 0.0:
		return base_target
	
	var forward := Vector3(-sin(target.rotation.y), 0.0, -cos(target.rotation.y)).normalized()
	var lead_strength := speed_ratio * speed_ratio
	return base_target + forward * lead_distance * lead_strength

## 줌 레벨에 따라 안개 시작/끝 거리를 동적으로 조절합니다.
func _update_dynamic_fog() -> void:
	if not environment: return
	# 줌 변화가 없으면 실행 건너뜀: GPU re-upload 방지
	if abs(current_zoom - _last_zoom) < 0.5: return
	_last_zoom = current_zoom
	# 전투에 적당한 줌아웃 위치에서는 시야를 먼저 가리지 않도록,
	# 기본 시작/종료 거리를 확보한 뒤 줌에 따라 더 뒤로 민다.
	environment.fog_depth_begin = maxf(fog_begin_min, current_zoom * fog_begin_zoom_multiplier)
	environment.fog_depth_end = maxf(fog_end_min, current_zoom * fog_end_zoom_multiplier)
