extends Area3D

## 신기전 로켓 (Singigeon Rocket)
## 빠르게 직선 비행, 적 충돌 시 범위 피해 및 화약 연기 효과

@export var speed: float = 70.0 # 속도 약간 상향
@export var damage: float = 4.0 # 데미지 약간 상향
@export var lifetime: float = 3.0
@export var blast_radius: float = 3.5

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var progress: float = 0.0
var duration: float = 1.0
@export var arc_height: float = 3.0 # 신기전은 작고 빠르므로 낮은 궤적

var smoke_particles: GPUParticles3D
var fire_particles: GPUParticles3D

func _ready() -> void:
	# 거리 기반 비행 시간 계산
	var distance = start_pos.distance_to(target_pos)
	duration = distance / speed
	if duration < 0.3: duration = 0.3
	
	global_position = start_pos
	
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)
	
	_setup_effects()

# === 최적화를 위한 정적 공유 리소스 ===
static var shared_smoke_mesh: Mesh
static var shared_smoke_mat: StandardMaterial3D
static var shared_fire_mat: ParticleProcessMaterial # 추진체 화염
static var shared_smoke_process_mat: ParticleProcessMaterial # 연기 프로세스

func _setup_effects() -> void:
	# 리소스 초기화 (최초 1회)
	if not shared_smoke_mesh:
		shared_smoke_mesh = SphereMesh.new()
		shared_smoke_mesh.radius = 0.2
		shared_smoke_mesh.height = 0.4
		
		shared_smoke_mat = StandardMaterial3D.new()
		shared_smoke_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		shared_smoke_mat.vertex_color_use_as_albedo = true
		shared_smoke_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		shared_smoke_mesh.material = shared_smoke_mat
		
		shared_smoke_process_mat = ParticleProcessMaterial.new()
		shared_smoke_process_mat.gravity = Vector3(0, 0.5, 0)
		shared_smoke_process_mat.direction = Vector3(0, 0, 1)
		shared_smoke_process_mat.spread = 10.0
		shared_smoke_process_mat.initial_velocity_min = 2.0
		shared_smoke_process_mat.initial_velocity_max = 5.0
		shared_smoke_process_mat.scale_min = 0.5
		shared_smoke_process_mat.scale_max = 1.2
		shared_smoke_process_mat.color = Color(0.4, 0.4, 0.4, 0.6)

		shared_fire_mat = ParticleProcessMaterial.new()
		shared_fire_mat.gravity = Vector3.ZERO
		shared_fire_mat.initial_velocity_min = 1.0
		shared_fire_mat.initial_velocity_max = 2.0
		shared_fire_mat.scale_min = 0.2
		shared_fire_mat.scale_max = 0.4
		shared_fire_mat.color = Color(1.0, 0.5, 0.2, 1.0)

	# 1. 연기 트레일 (GPU Particles)
	smoke_particles = GPUParticles3D.new()
	add_child(smoke_particles)
	smoke_particles.process_material = shared_smoke_process_mat
	smoke_particles.amount = 100
	smoke_particles.lifetime = 1.5
	smoke_particles.local_coords = false
	smoke_particles.draw_pass_1 = shared_smoke_mesh

	# 2. 화염 효과 (추진체)
	fire_particles = GPUParticles3D.new()
	add_child(fire_particles)
	fire_particles.process_material = shared_fire_mat
	fire_particles.amount = 20
	fire_particles.lifetime = 0.1
	fire_particles.draw_pass_1 = shared_smoke_mesh # 구체 메쉬 공유

func _physics_process(delta: float) -> void:
	progress += delta / duration
	
	if progress >= 1.0:
		_explode()
		queue_free()
		return
	
	# 수평 LERP
	var current_pos = start_pos.lerp(target_pos, progress)
	
	# 수직 Arc (sin)
	var y_offset = sin(PI * progress) * arc_height
	current_pos.y += y_offset
	
	# 방향 회전
	if (current_pos - global_position).length_squared() > 0.001:
		look_at(current_pos, Vector3.UP)
		
	global_position = current_pos

func _on_hit(target: Node) -> void:
	var enemy = target if target.is_in_group("enemy") else target.get_parent()
	if not (enemy and enemy.is_in_group("enemy")):
		return
	
	_explode()
	queue_free()

static var shared_exp_mesh: Mesh
static var shared_exp_process_mat: ParticleProcessMaterial

func _explode() -> void:
	# 폭발 리소스 초기화 (최초 1회)
	if not shared_exp_mesh:
		shared_exp_mesh = SphereMesh.new()
		shared_exp_mesh.radius = 0.1
		shared_exp_mesh.height = 0.2
		var mesh_mat = StandardMaterial3D.new()
		mesh_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mesh_mat.vertex_color_use_as_albedo = true
		shared_exp_mesh.material = mesh_mat
		
		shared_exp_process_mat = ParticleProcessMaterial.new()
		shared_exp_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		shared_exp_process_mat.emission_sphere_radius = 0.5
		shared_exp_process_mat.spread = 180.0
		shared_exp_process_mat.initial_velocity_min = 5.0
		shared_exp_process_mat.initial_velocity_max = 10.0
		shared_exp_process_mat.gravity = Vector3(0, -2, 0)
		shared_exp_process_mat.scale_min = 0.5
		shared_exp_process_mat.scale_max = 2.0
		shared_exp_process_mat.color = Color(1.0, 0.6, 0.2, 1.0)

	var exp_node = GPUParticles3D.new()
	get_tree().root.add_child(exp_node)
	exp_node.global_position = global_position
	exp_node.process_material = shared_exp_process_mat
	exp_node.amount = 50
	exp_node.one_shot = true
	exp_node.explosiveness = 1.0
	exp_node.draw_pass_1 = shared_exp_mesh
	exp_node.emitting = true
	
	# 데미지 처리
	var all_enemies = get_tree().get_nodes_in_group("enemy")
	for e in all_enemies:
		if is_instance_valid(e):
			var dist = global_position.distance_to(e.global_position)
			if dist <= blast_radius:
				if e.has_method("take_damage"):
					e.take_damage(damage, global_position)
				elif e.has_method("die"):
					e.die()
	
	# 파티클 정리
	get_tree().create_timer(2.0).timeout.connect(exp_node.queue_free)
