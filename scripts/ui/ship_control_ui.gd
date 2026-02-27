extends Control

## 배 조작 UI: 돛 각도, 러더, 노 젓기, 바람 표시

# 참조할 배
@export var controlled_ship: NodePath

var ship: Node3D = null

# UI 노드들
@onready var sail_angle_label: Label = %SailAngleLabel if has_node("%SailAngleLabel") else null
@onready var sail_left_btn: Button = %SailLeftButton if has_node("%SailLeftButton") else null
@onready var sail_right_btn: Button = %SailRightButton if has_node("%SailRightButton") else null
@onready var rowing_btn: Button = %RowingButton if has_node("%RowingButton") else null
@onready var speed_label: Label = %SpeedLabel if has_node("%SpeedLabel") else null
@onready var stamina_bar: ProgressBar = %StaminaBar if has_node("%StaminaBar") else null
@onready var wind_indicator: Control = %WindIndicator if has_node("%WindIndicator") else null
@onready var wind_arrow: Node2D = %Arrow if has_node("%Arrow") else null
@onready var compass_wheel: Node2D = %CompassWheel if has_node("%CompassWheel") else null


func _ready() -> void:
	if has_node(controlled_ship):
		ship = get_node(controlled_ship)
	
	# 불필요한 패널들의 부모 컨테이너(VBoxContainer) 전체를 숨겨서 배경 박스까지 완전히 제거
	var vbox = get_node_or_null("VBoxContainer")
	if vbox:
		vbox.visible = false
		
	# 나침반의 사각형 배경(WindPanel)을 투명하게 만들고 상단 라벨 숨기기
	var wind_panel = get_node_or_null("WindPanel")
	if wind_panel:
		wind_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var wind_label_title = wind_panel.get_node_or_null("VBox/Label")
		if wind_label_title:
			wind_label_title.visible = false
	
	# 안전을 위해 개별 버튼들도 숨김 처리 유지
	if sail_left_btn: sail_left_btn.visible = false
	if sail_right_btn: sail_right_btn.visible = false
	if rowing_btn: rowing_btn.visible = false
	
	if sail_angle_label: sail_angle_label.visible = false
	if speed_label: speed_label.visible = false
	if stamina_bar: stamina_bar.visible = false
	
	# 버튼 연결은 기능 유지를 위해 놔둠 (나중에 모바일 대응 등을 위해)
	if sail_left_btn:
		sail_left_btn.pressed.connect(_on_sail_left_pressed)
	if sail_right_btn:
		sail_right_btn.pressed.connect(_on_sail_right_pressed)
	if rowing_btn:
		rowing_btn.pressed.connect(_on_rowing_pressed)


func _process(_delta: float) -> void:
	if not is_instance_valid(ship):
		return
	
	_update_sail_display()
	_update_speed_display()
	_update_stamina_display()
	_update_wind_indicator()


func _update_sail_display() -> void:
	if sail_angle_label:
		var rudder_text = ""
		if ship.get("rudder_angle") != null:
			rudder_text = " | 러더: %.0f도" % ship.rudder_angle
		sail_angle_label.text = "돛: %.0f도%s" % [ship.sail_angle, rudder_text]


func _update_speed_display() -> void:
	if speed_label:
		var mode_text = "노 젓기" if ship.is_rowing else "돛"
		speed_label.text = "속도: %.1f [%s]" % [ship.current_speed, mode_text]


func _update_stamina_display() -> void:
	if stamina_bar:
		stamina_bar.value = ship.rowing_stamina
		stamina_bar.max_value = 100.0


func _update_wind_indicator() -> void:
	if not wind_arrow or not is_instance_valid(WindManager):
		return
	
	# 활성화된 3D 카메라 정보 가져오기
	var cam = get_viewport().get_camera_3d()
	var cam_yaw = 0.0
	if is_instance_valid(cam):
		cam_yaw = cam.global_rotation.y
	
	# 1. 눈금판(N, E, S, W) 회전: 카메라 시점에 맞춰 나침반 회전
	if compass_wheel:
		compass_wheel.rotation = cam_yaw
	
	# 2. 바람 화살표 회전: 카메라 시점 기준으로 상대적 바람 방향 표시
	# 글로벌 바람 각도(deg) + 카메라 회전(rad)
	var wind_angle_rad = deg_to_rad(WindManager.wind_angle_degrees)
	wind_arrow.rotation = wind_angle_rad + cam_yaw


func _on_sail_left_pressed() -> void:
	if ship:
		ship.adjust_sail_angle(-10.0)


func _on_sail_right_pressed() -> void:
	if ship:
		ship.adjust_sail_angle(10.0)


func _on_rowing_pressed() -> void:
	if ship:
		ship.toggle_rowing()
		if rowing_btn:
			rowing_btn.text = "노 젓기 중지" if ship.is_rowing else "노 젓기"
