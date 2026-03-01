extends Node3D

## 돛대 (Mast) 오브젝트
## 자체적으로 돛 각도 회전 및 펄럭임 제어

@export var max_wind_intake: float = 1.0 # 모델별 바람 허용량 조절 가능

@onready var sail_visual: Node3D = $SailVisual
@onready var sail_mesh: MeshInstance3D = $SailVisual/SailMesh
@onready var flag: Node3D = $SailVisual/Flag

var sail_angle: float = 0.0

func set_sail_angle(angle: float) -> void:
	sail_angle = angle

func _process(_delta: float) -> void:
	if not is_instance_valid(WindManager): return
	
	# 바람 방향에 따른 돛대 회전은 배 본체(ship.gd, chaser_ship.gd)에서 _auto_adjust_sail 등을 통해 
	# sail_angle 변수를 직접 설정하도록 위임하거나, 
	# 독립적으로 돛대가 스스로 최적의 각도를 찾는 로직을 넣을 수 있습니다.
	# 현재는 기존 ship.gd/chaser_ship.gd의 구조를 최대한 유지하도록 속성만 제공
	
	if sail_visual:
		sail_visual.rotation.y = deg_to_rad(-sail_angle)
		
		# 바람 intake 계산 (돛의 정면 -Z 방향)
		var wind_dir = WindManager.get_wind_direction()
		var sail_fwd = - sail_visual.global_transform.basis.z
		var sail_fwd_2d = Vector2(sail_fwd.x, sail_fwd.z).normalized()
		var _current_wind_intake = max(0.0, wind_dir.dot(sail_fwd_2d)) * max_wind_intake
		
		if sail_mesh:
			sail_mesh.set_instance_shader_parameter("wind_strength", _current_wind_intake)

func set_team_color(team: String) -> void:
	if flag and flag.has_method("set_team_color"):
		flag.set_team_color(team)

func set_sail_color(color: Color) -> void:
	if sail_mesh:
		sail_mesh.set_instance_shader_parameter("albedo", color)
