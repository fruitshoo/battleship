extends Area3D

## 대포알 (Cannonball)
## 정해진 방향으로 전진하며, 적과 충돌 시 적을 파괴함

@export var speed: float = 80.0
@export var lifetime: float = 2.0 # 사거리 단축 (80 * 2 = 160m)
@export var damage: float = 1.0
@export var homing_strength: float = 0.0 # 유도 제거
@export var homing_duration: float = 0.0 # 유도 제거
@export var crit_chance: float = 0.2 # 20% 크리티컬 확률
@export var crit_multiplier: float = 2.0 # 크리티컬 2배 데미지

var direction: Vector3 = Vector3.FORWARD
var target_node: Node3D = null
var time_alive: float = 0.0

# 포도탄(Grapeshot) 모드 변수
@export var is_grapeshot: bool = false
var grapeshot_splash_radius: float = 4.0
var grapeshot_pellet_damage: float = 25.0

@export var shockwave_scene: PackedScene = preload("res://scenes/effects/shockwave.tscn")

func _spawn_effects(_is_crit: bool = false) -> void:
	if not is_instance_valid(AudioManager): return
	
	if is_grapeshot:
		# 포도탄 흩뿌려지는 소리 (작은 타격음 여러 개)
		AudioManager.play_sfx("impact_wood", global_position, randf_range(1.2, 1.5))
		
		# 포도탄 피격 파티클 연출 (핏빛/나무 파편)
		_spawn_grapeshot_impact()
	else:
		# 일반탄 사운드 믹스: 나무 부서지는 소리만 남김
		AudioManager.play_sfx("impact_wood", global_position, randf_range(0.9, 1.1))
	
	# 사운드만 재생 (쇼크웨이브 제거)

# ==================== 포도탄 시각 효과 초기화 리소스 ====================
static var shared_grape_trail_mesh: Mesh
static var shared_grape_trail_mat: ParticleProcessMaterial
static var shared_grape_impact_mesh: Mesh
static var shared_grape_impact_mat: ParticleProcessMaterial

func _setup_grapeshot_visuals() -> void:
	# 투사체 메쉬 숨기기
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
			
	# 산탄 비행 파티클 (Trail)
	if not shared_grape_trail_mesh:
		shared_grape_trail_mesh = SphereMesh.new()
		shared_grape_trail_mesh.radius = 0.05
		shared_grape_trail_mesh.height = 0.1
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.2, 0.2, 1.0)
		shared_grape_trail_mesh.material = m
		
		shared_grape_trail_mat = ParticleProcessMaterial.new()
		shared_grape_trail_mat.direction = Vector3(0, 0, 1)
		shared_grape_trail_mat.spread = 15.0 # 부채꼴로 퍼지는 산탄 모양
		shared_grape_trail_mat.initial_velocity_min = 2.0
		shared_grape_trail_mat.initial_velocity_max = 5.0
		shared_grape_trail_mat.scale_min = 0.8
		shared_grape_trail_mat.scale_max = 1.5
		
	var trail = GPUParticles3D.new()
	add_child(trail)
	trail.process_material = shared_grape_trail_mat
	trail.draw_pass_1 = shared_grape_trail_mesh
	trail.amount = 30
	trail.lifetime = 0.5
	trail.local_coords = false

func _spawn_grapeshot_impact() -> void:
	if not shared_grape_impact_mesh:
		# 큐브형(BoxMesh) 대신 좀 더 자연스러운 원형/파편형(SphereMesh)으로 변경
		shared_grape_impact_mesh = SphereMesh.new()
		shared_grape_impact_mesh.radius = 0.05
		shared_grape_impact_mesh.height = 0.1
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.1, 0.1, 1.0) # 피 튀기는 색상 (약간 더 어둡게)
		m.roughness = 0.9 # 반사광 줄임
		shared_grape_impact_mesh.material = m
		
		shared_grape_impact_mat = ParticleProcessMaterial.new()
		shared_grape_impact_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		shared_grape_impact_mat.emission_sphere_radius = 1.5 # 넓게 퍼짐
		shared_grape_impact_mat.direction = Vector3(0, 1, 0)
		shared_grape_impact_mat.spread = 90.0
		shared_grape_impact_mat.initial_velocity_min = 5.0
		shared_grape_impact_mat.initial_velocity_max = 10.0
		shared_grape_impact_mat.gravity = Vector3(0, -9.8, 0)
		
	var impact = GPUParticles3D.new()
	get_tree().root.add_child(impact)
	impact.global_position = global_position
	impact.process_material = shared_grape_impact_mat
	impact.draw_pass_1 = shared_grape_impact_mesh
	impact.amount = 50
	impact.explosiveness = 1.0
	impact.one_shot = true
	impact.emitting = true
	get_tree().create_timer(1.0).timeout.connect(impact.queue_free)

func _ready() -> void:
	# 포도탄 그래픽 셋팅
	if is_grapeshot:
		_setup_grapeshot_visuals()
	
	# 충돌 시그널 연결
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# 3초 뒤 자동 삭제 (바다에 빠짐)
	get_tree().create_timer(lifetime).timeout.connect(_on_timeout)

var has_hit: bool = false

func _on_timeout() -> void:
	if has_hit: return
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
	queue_free()

func _physics_process(delta: float) -> void:
	if has_hit: return
	
	time_alive += delta
	# 부드러운 유도 (Soft Homing) - 초반만 작동
	if time_alive < homing_duration and is_instance_valid(target_node):
		var to_target = (target_node.global_position - global_position).normalized()
		direction = direction.lerp(to_target, homing_strength * delta).normalized()
		look_at(global_position + direction, Vector3.UP)
		
	var move_vec = direction * speed * delta
	var next_pos = global_position + move_vec
	
	# CCD (Continuous Collision Detection, 고속 이동체 터널링 방지)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, next_pos, collision_mask)
	query.collide_with_areas = false # Area3D(ProximityArea) 이중 적중 방지
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		global_position = result.position
		_check_hit(result.collider)
		return
		
	global_position = next_pos


func _on_area_entered(area: Area3D) -> void:
	_check_hit(area)

func _on_body_entered(body: Node3D) -> void:
	_check_hit(body)

func _check_hit(target: Node) -> void:
	if has_hit: return
	has_hit = true
	
	# 적 그룹 확인 (chaser_ship.gd는 enemy 그룹이어야 함)
	if target.is_in_group("enemy") or (target.get_parent() and target.get_parent().is_in_group("enemy")):
		var enemy = target if target.is_in_group("enemy") else target.get_parent()
		
		var is_crit = false
		
		if is_grapeshot:
			# === 포도탄(Grapeshot) 적중 로직 ===
			# 1. 배에는 고정 1.0 데미지 (파괴 방지)
			if enemy.has_method("take_damage"):
				enemy.take_damage(1.0, global_position)
			
			# 2. 반경 내 병사들에게 치명적인 광역(AoE) 피해
			var all_soldiers = get_tree().get_nodes_in_group("soldiers")
			var hit_count = 0
			for s in all_soldiers:
				if is_instance_valid(s) and s.get("team") == "enemy":
					if global_position.distance_to(s.global_position) <= grapeshot_splash_radius:
						if s.has_method("take_damage"):
							s.take_damage(grapeshot_pellet_damage, global_position)
							hit_count += 1
			print("[Damage] 포도탄 명중! 적 병사 %d명 학살" % hit_count)
			
		else:
			# === 일반탄(Round Shot) 적중 로직 ===
			# 크리티컬 계산
			is_crit = randf() < crit_chance
			var final_damage = damage * (crit_multiplier if is_crit else 1.0)
			
			# 적 파괴 로직 수정: take_damage 우선 호출 (충돌 위치 전달)
			if enemy.has_method("take_damage"):
				enemy.take_damage(final_damage, global_position)
			elif enemy.has_method("die"):
				enemy.die()
			else:
				enemy.queue_free()
			
		# 이펙트 및 사운드 재생
		_spawn_effects(is_crit)
			
		# 대포알 자체 삭제
		queue_free()
