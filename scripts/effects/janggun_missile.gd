extends Area3D

## 장군전 미사일 (Janggun Missile)
## 느리지만 고데미지 통나무 미사일. 범위 피해.

@export var speed: float = 25.0
@export var damage: float = 12.0 # 즉발 데미지 대폭 하향 (60 -> 12)
@export var dot_damage: float = 4.0 # 누수 데미지 (초당 4.0)
@export var speed_debuff: float = 0.7 # 속도 30% 감소
@export var turn_debuff: float = 0.6 # 선회 40% 감소
@export var stick_duration: float = 15.0 # 박혀있는 시간 (10 -> 15)

@export var arc_height: float = 8.0

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var progress: float = 0.0
var duration: float = 1.0
var is_stuck: bool = false
var is_sinking: bool = false
var target_ship: Node3D = null

func _ready() -> void:
	var distance = start_pos.distance_to(target_pos)
	duration = distance / speed
	if duration < 0.5: duration = 0.5
	
	global_position = start_pos
	
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	if is_stuck or is_sinking: return
	
	progress += delta / duration
	
	if progress >= 1.0:
		# 바다에 빠짐
		_splash_and_sink()
		return
	
	var current_pos = start_pos.lerp(target_pos, progress)
	var y_offset = sin(PI * progress) * arc_height
	current_pos.y += y_offset
	
	if (current_pos - global_position).length_squared() > 0.001:
		look_at(current_pos, Vector3.UP)
		
	global_position = current_pos

func _on_hit(target: Node) -> void:
	if is_stuck: return
	
	var ship = target if target.is_in_group("enemy") or target.is_in_group("player") else null
	if not ship:
		var p = target.get_parent()
		if p and (p.is_in_group("enemy") or p.is_in_group("player")):
			ship = p
	
	if ship:
		_play_impact_vfx() # 임팩트 이펙트 재생
		_stick_to_ship(ship)

func _stick_to_ship(ship: Node3D) -> void:
	is_stuck = true
	target_ship = ship
	
	# 데미지 주기
	if ship.has_method("take_damage"):
		ship.take_damage(damage, global_position)
	
	# 물리/충돌 끄기
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# 함선에 고정 (Reparent) - 물리 콜백 중 리페어런팅 에러 방지를 위해 지연 호출
	call_deferred("reparent", ship)
	
	# 디버프 적용
	if ship.has_method("add_stuck_object"):
		ship.add_stuck_object(self, speed_debuff, turn_debuff)
	
	if ship.has_method("add_leak"):
		ship.add_leak(dot_damage)
	
	print("🪵 장군전이 함선에 박혔습니다! (즉발:%.0f, 누수:%.1f/s)" % [damage, dot_damage])
	
	# 일정 시간 후 제거
	get_tree().create_timer(stick_duration).timeout.connect(_unstick)

func _unstick() -> void:
	if is_instance_valid(target_ship) and target_ship.has_method("remove_stuck_object"):
		target_ship.remove_stuck_object(self, speed_debuff, turn_debuff)
	
	if is_instance_valid(target_ship) and target_ship.has_method("remove_leak"):
		target_ship.remove_leak(dot_damage)
	
	queue_free()

static var shared_exp_mesh: Mesh
static var shared_exp_process_mat: ParticleProcessMaterial

func _splash_and_sink() -> void:
	if is_sinking: return
	is_sinking = true
	
	# 물보라 효과 (나중에 리소소 공유 적용 가능)
	var tween = create_tween()
	tween.tween_property(self, "position:y", position.y - 2.0, 1.0)
	tween.tween_callback(queue_free)

# 충격 시 폭발 효과용 (데미지랑 별개로 비주얼용으로 남겨둘 수 있음, 하지만 현재는 박히는 로직이 우선)
func _play_impact_vfx() -> void:
	if not shared_exp_mesh:
		shared_exp_mesh = SphereMesh.new()
		shared_exp_mesh.radius = 0.15
		shared_exp_mesh.height = 0.3
		var mesh_mat = StandardMaterial3D.new()
		mesh_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mesh_mat.vertex_color_use_as_albedo = true
		shared_exp_mesh.material = mesh_mat
		
		shared_exp_process_mat = ParticleProcessMaterial.new()
		shared_exp_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		shared_exp_process_mat.emission_sphere_radius = 1.0
		shared_exp_process_mat.spread = 180.0
		shared_exp_process_mat.initial_velocity_min = 8.0
		shared_exp_process_mat.initial_velocity_max = 15.0
		shared_exp_process_mat.gravity = Vector3(0, -3, 0)
		shared_exp_process_mat.scale_min = 1.0
		shared_exp_process_mat.scale_max = 3.0
		shared_exp_process_mat.color = Color(1.0, 0.4, 0.1, 1.0)

	var exp_node = GPUParticles3D.new()
	get_tree().root.add_child(exp_node)
	exp_node.global_position = global_position
	exp_node.process_material = shared_exp_process_mat
	exp_node.amount = 80
	exp_node.one_shot = true
	exp_node.explosiveness = 1.0
	exp_node.draw_pass_1 = shared_exp_mesh
	exp_node.emitting = true
	get_tree().create_timer(2.0).timeout.connect(exp_node.queue_free)
