@tool
extends Node3D

## 깃발 (Flag) 오브젝트
## 바람 조절기(WindManager)의 방향에 따라 자동으로 펄럭이며 방향을 잡습니다.

@export var color: Color = Color(0.9, 0.1, 0.1):
	set(v):
		color = v
		_update_material()

enum Shape {RECTANGLE, TRIANGLE}
@export var flag_shape: Shape = Shape.RECTANGLE:
	set(v):
		flag_shape = v
		_update_material()

@export var pole_height: float = 2.0:
	set(v):
		pole_height = v
		_update_dimensions()

@export var flag_size: Vector2 = Vector2(1.5, 1.0):
	set(v):
		flag_size = v
		_update_dimensions()

@export var use_flag_texture: bool = false:
	set(v):
		use_flag_texture = v
		_update_material()

@export var flag_texture: Texture2D:
	set(v):
		flag_texture = v
		_update_material()

@export var uv_scale: Vector2 = Vector2.ONE:
	set(v):
		uv_scale = v
		_update_material()

@export var uv_offset: Vector2 = Vector2.ZERO:
	set(v):
		uv_offset = v
		_update_material()

@export var flip_u: bool = false:
	set(v):
		flip_u = v
		_update_material()

@export var flip_v: bool = false:
	set(v):
		flip_v = v
		_update_material()

@export_range(0.0, 10.0, 0.1) var wave_speed: float = 5.0:
	set(v):
		wave_speed = v
		_update_material()

@export_range(0.0, 1.0, 0.01) var wave_strength: float = 0.25:
	set(v):
		wave_strength = v
		_update_material()

@export_range(0.0, 5.0, 0.05) var side_drag: float = 1.0:
	set(v):
		side_drag = v
		_update_material()

@export var pole_color: Color = Color(0.35, 0.2, 0.1, 1.0):
	set(v):
		pole_color = v
		_update_pole_material()

@onready var pole_mesh: MeshInstance3D = $Pole
@onready var flag_mesh: MeshInstance3D = $FlagMesh

func _ready() -> void:
	_update_material()
	_update_pole_material()
	_update_dimensions()
	# 초기 무작위성 추가 (모든 깃발이 똑같이 움직이지 않게)
	if flag_mesh:
		var mat = flag_mesh.get_active_material(0)
		if mat:
			# 셰이더 시간 오프셋은 불가능하므로, 그냥 Ready 시점의 차이로 자연스럽게 둠
			pass

func _update_dimensions() -> void:
	if not is_inside_tree(): return
	
	# @onready 변수 대신 직접 찾아서 안전하게 사용 (에디터 툴 모드 대비)
	var p_mesh = get_node_or_null("Pole")
	var f_mesh = get_node_or_null("FlagMesh")
	
	if p_mesh and p_mesh.mesh is CylinderMesh:
		var c_mesh = p_mesh.mesh.duplicate() as CylinderMesh
		c_mesh.height = pole_height
		p_mesh.mesh = c_mesh
		p_mesh.position.y = pole_height / 2.0
		
		if f_mesh and f_mesh.mesh is PlaneMesh:
			var plane_mesh = f_mesh.mesh.duplicate() as PlaneMesh
			plane_mesh.size = flag_size
			f_mesh.mesh = plane_mesh
			# 깃발 상단이 깃대 끝에 오도록 오프셋 적용 (-height/2)
			f_mesh.position.y = pole_height - (flag_size.y * 0.5)

func _process(_delta: float) -> void:
	var wind_manager = get_node_or_null("/root/WindManager")
	if not is_instance_valid(wind_manager):
		return
	
	var wind_dir = wind_manager.get_wind_direction()
	var wind_str = wind_manager.get_wind_strength()
	var wind_3d = Vector3(wind_dir.x, 0, wind_dir.y).normalized()
	
	if wind_3d.length_squared() > 0.01:
		# 1. 깃발 방향 설정 (바람 방향)
		# Basis.looking_at은 -Z를 정렬하므로, 90도 회전해서 X축이 바람 방향이 되게 함
		var target_basis = Basis.looking_at(wind_3d, Vector3.UP)
		flag_mesh.global_basis = target_basis * Basis(Vector3.UP, PI / 2.0)
		
		# 2. 깃발 위치 고정 (깃대 꼭대기)
		# 깃발 Mesh의 오리진이 중심이므로, 상단이 깃대에 맞게 Y축으로 -0.5 * height 만큼 내림
		var flag_vertical_offset = Vector3(0, -flag_size.y * 0.5, 0)
		flag_mesh.global_position = global_transform * Vector3(0, pole_height, 0) + flag_vertical_offset + wind_3d * (flag_size.x * 0.5)
		
		# 3. 펄럭임 파라미터 업데이트
		var animated_wave_speed: float = wave_speed * (0.75 + wind_str)
		var animated_wave_strength: float = wave_strength * (0.4 + wind_str * 0.8)
		flag_mesh.set_instance_shader_parameter("wave_speed", animated_wave_speed)
		flag_mesh.set_instance_shader_parameter("wave_strength", animated_wave_strength)
		flag_mesh.set_instance_shader_parameter("side_drag", side_drag)

func _update_material() -> void:
	if not is_inside_tree(): return
	
	var f_mesh = get_node_or_null("FlagMesh")
	if not f_mesh: return

	var material := _ensure_flag_material(f_mesh)
	if material:
		material.set_shader_parameter("flag_texture", flag_texture)
		material.set_shader_parameter("use_flag_texture", use_flag_texture and flag_texture != null)
		material.set_shader_parameter("uv_scale", uv_scale)
		material.set_shader_parameter("uv_offset", uv_offset)
		material.set_shader_parameter("flip_u", flip_u)
		material.set_shader_parameter("flip_v", flip_v)
		material.set_shader_parameter("wave_speed", wave_speed)
		material.set_shader_parameter("wave_strength", wave_strength)
		material.set_shader_parameter("side_drag", side_drag)
	
	f_mesh.set_instance_shader_parameter("albedo", color)
	f_mesh.set_instance_shader_parameter("is_triangular", flag_shape == Shape.TRIANGLE)
	f_mesh.set_instance_shader_parameter("wave_speed", wave_speed)
	f_mesh.set_instance_shader_parameter("wave_strength", wave_strength)
	f_mesh.set_instance_shader_parameter("side_drag", side_drag)


func _update_pole_material() -> void:
	if not is_inside_tree():
		return
	var p_mesh = get_node_or_null("Pole")
	if not p_mesh:
		return
	var source_mat: Material = p_mesh.get_active_material(0)
	var pole_mat: StandardMaterial3D = null
	if source_mat is StandardMaterial3D:
		pole_mat = source_mat
	else:
		pole_mat = StandardMaterial3D.new()
	pole_mat = pole_mat.duplicate() as StandardMaterial3D
	pole_mat.albedo_color = pole_color
	p_mesh.set_surface_override_material(0, pole_mat)


func _ensure_flag_material(f_mesh: MeshInstance3D) -> ShaderMaterial:
	var active_mat := f_mesh.get_active_material(0)
	var shader_mat: ShaderMaterial = null
	if active_mat is ShaderMaterial:
		shader_mat = active_mat
	else:
		var override_mat := f_mesh.get_surface_override_material(0)
		if override_mat is ShaderMaterial:
			shader_mat = override_mat
	if shader_mat == null:
		return null
	var duplicated := shader_mat.duplicate() as ShaderMaterial
	f_mesh.set_surface_override_material(0, duplicated)
	return duplicated

func set_team_color(team: String) -> void:
	if team == "player":
		color = Color(0.9, 0.1, 0.1)
	else:
		color = Color(0.1, 0.1, 0.1)
