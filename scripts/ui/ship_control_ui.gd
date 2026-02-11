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


func _ready() -> void:
	if has_node(controlled_ship):
		ship = get_node(controlled_ship)
	
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
	
	# 바람 각도를 라디안으로 변환하여 화살표 회전
	var wind_angle_rad = deg_to_rad(WindManager.wind_angle_degrees)
	wind_arrow.rotation = wind_angle_rad


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
