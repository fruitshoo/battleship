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
@export var max_zoom: float = 50.0
@export var rotation_sensitivity: float = 0.005

var target: Node3D = null
var current_zoom: float = 0.0
var _cam_rotation: Vector2 = Vector2.ZERO

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
	
	# 우클릭 드래그로 회전
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_cam_rotation.x -= event.relative.x * rotation_sensitivity
		_cam_rotation.y -= event.relative.y * rotation_sensitivity
		_cam_rotation.y = clamp(_cam_rotation.y, -PI / 2 + 0.1, 0) # 땅 밑으로 안 가게 제한

func _process(delta: float) -> void:
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
