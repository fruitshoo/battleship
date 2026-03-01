extends Node3D

## 깃발 (Flag) 오브젝트
## 바람 조절기(WindManager)의 방향에 따라 자동으로 펄럭이며 방향을 잡습니다.

@export var color: Color = Color(0.9, 0.1, 0.1):
	set(v):
		color = v
		_update_material()

@export var pole_height: float = 2.0
@export var flag_size: Vector2 = Vector2(1.5, 1.0)

@onready var pole_mesh: MeshInstance3D = $Pole
@onready var flag_mesh: MeshInstance3D = $FlagMesh

func _ready() -> void:
	_update_material()
	_update_dimensions()
	# 초기 무작위성 추가 (모든 깃발이 똑같이 움직이지 않게)
	if flag_mesh:
		var mat = flag_mesh.get_surface_override_material(0)
		if mat:
			# 셰이더 시간 오프셋은 불가능하므로, 그냥 Ready 시점의 차이로 자연스럽게 둠
			pass

func _update_dimensions() -> void:
	if not is_inside_tree(): return
	
	if pole_mesh and pole_mesh.mesh is CylinderMesh:
		var c_mesh = pole_mesh.mesh.duplicate() as CylinderMesh
		c_mesh.height = pole_height
		pole_mesh.mesh = c_mesh
		pole_mesh.position.y = pole_height / 2.0
		
	if flag_mesh and flag_mesh.mesh is PlaneMesh:
		var p_mesh = flag_mesh.mesh.duplicate() as PlaneMesh
		p_mesh.size = flag_size
		flag_mesh.mesh = p_mesh

func _process(_delta: float) -> void:
	if not is_instance_valid(WindManager):
		return
	
	var wind_dir = WindManager.get_wind_direction()
	var wind_str = WindManager.get_wind_strength()
	var wind_3d = Vector3(wind_dir.x, 0, wind_dir.y).normalized()
	
	if wind_3d.length_squared() > 0.01:
		# 1. 깃발 방향 설정 (바람 방향)
		# Basis.looking_at은 -Z를 정렬하므로, 90도 회전해서 X축이 바람 방향이 되게 함
		var target_basis = Basis.looking_at(wind_3d, Vector3.UP)
		flag_mesh.global_basis = target_basis * Basis(Vector3.UP, PI / 2.0)
		
		# 2. 깃발 위치 고정 (깃대 꼭대기)
		# 깃발 Mesh의 오리진이 왼쪽 끝이라면 flag_mesh.position을 조정할 필요 없음
		# 하지만 현재 PlaneMesh는 중심이 오리진이므로, 절반만큼 밀어줌
		flag_mesh.global_position = global_transform * Vector3(0, pole_height, 0) + wind_3d * (flag_size.x * 0.5)
		
		# 3. 펄럭임 파라미터 업데이트
		flag_mesh.set_instance_shader_parameter("wave_speed", 3.0 + wind_str * 5.0)
		flag_mesh.set_instance_shader_parameter("wave_strength", 0.1 + wind_str * 0.3)

func _update_material() -> void:
	if not is_inside_tree() or not flag_mesh: return
	# 인스턴스 셰이더 파라미터로 색상 적용
	flag_mesh.set_instance_shader_parameter("albedo", color)

func set_team_color(team: String) -> void:
	if team == "player":
		color = Color(0.9, 0.1, 0.1)
	else:
		color = Color(0.1, 0.1, 0.1)
