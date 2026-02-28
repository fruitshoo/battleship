extends Camera3D

## 3rd Person Camera Controller
## 타겟(배)을 부드럽게 따라다니며 줌/회전 기능 제공

@export var target_path: NodePath
@export_group("Follow Settings")
@export var smooth_speed: float = 3.0 # 5.0에서 3.0으로 낮춤 (약간 지연감 있게)
@export var offset: Vector3 = Vector3(0, 15, 20)

@export_group("Control Settings")
@export var zoom_speed: float = 2.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 150.0
@export var rotation_sensitivity: float = 0.005

var target: Node3D = null
var current_zoom: float = 0.0
var _cam_rotation: Vector2 = Vector2.ZERO

var shake_intensity: float = 0.0
var shake_timer: float = 0.0
var shake_duration: float = 0.0
var _last_zoom: float = -1.0 # 마지막으로 포그가 업데이트된 줌 레벨

func _ready() -> void:
	print("=== Camera Controller Ready ===")
	print("Target Path: ", target_path)
	
	if target_path:
		target = get_node(target_path)
		if target:
			print("✅ Target found: ", target.name)
		else:
			print("❌ Target NOT found!")
	else:
		print("❌ No target_path set!")
	
	current_zoom = offset.length()
	
	# 초기 회전값 설정
	var rot = transform.basis.get_euler()
	_cam_rotation.x = rot.y
	_cam_rotation.y = rot.x
	print("Initial zoom: ", current_zoom)
	print("================================")

func _input(event: InputEvent) -> void:
	# 마우스 휠로 줌
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom = clamp(current_zoom - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom = clamp(current_zoom + zoom_speed, min_zoom, max_zoom)
	
	# 트랙패드 핀치로 줌 (Mac)
	if event is InputEventMagnifyGesture:
		var pinch_zoom_speed = zoom_speed * 5.0
		current_zoom = clamp(current_zoom - (event.factor - 1.0) * pinch_zoom_speed, min_zoom, max_zoom)
	
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
		
	# 1. 타겟 위치
	var target_pos = target.global_position
	
	# 2. 쿼터뷰 고정 각도 (45도 위에서, 약간 뒤에서)
	# 수평 회전은 유저가 조절 가능, 수직 각도는 고정
	var quarter_view_angle = deg_to_rad(-45.0) # 위에서 45도 각도로 내려다봄
	
	# 우클릭 드래그로 수평 회전만 가능
	var rot_basis = Basis.from_euler(Vector3(quarter_view_angle, _cam_rotation.x, 0))
	var final_offset = rot_basis * Vector3(0, 0, current_zoom)
	
	var desired_position = target_pos + final_offset
	
	# 3. 부드러운 이동
	global_position = global_position.lerp(desired_position, smooth_speed * delta)
	
	# 4. 항상 타겟 바라보기
	look_at(target_pos, Vector3.UP)
	
	# 5. 동적 포그 조절 (줌에 따라 안개 거리 조정)
	_update_dynamic_fog()
	
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

## 줌 레벨에 따라 안개 시작/끝 거리를 동적으로 조절합니다.
func _update_dynamic_fog() -> void:
	if not environment: return
	# 줌 변화가 없으면 실행 건너뜀: GPU re-upload 방지
	if abs(current_zoom - _last_zoom) < 0.5: return
	_last_zoom = current_zoom
	
	# 안개가 항상 플레이어(타겟) 주변에는 끼지 않도록 줌 거리보다 약간 뒤에서 시작하게 설정
	# 줌이 멀어질수록 안개가 시작되는 지점도 멀어지게 하여 가시성을 확보함.
	environment.fog_depth_begin = current_zoom * 1.5
	environment.fog_depth_end = current_zoom * 4.5
