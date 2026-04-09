extends Area3D
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

## 화통 (Fire Pot)
## 포물선으로 날아가 착탄 시 폭발하며 범위 데미지(화염)를 줍니다.

@export var damage: float = 15.0
@export var explosion_radius: float = 3.0
@export var lifetime: float = 3.0

var team: String = "player"
var target_pos: Vector3 = Vector3.ZERO
var start_pos: Vector3 = Vector3.ZERO
var time_alive: float = 0.0
var flight_duration: float = 1.0 # 1초 동안 날아감
var arc_height: float = 3.0

var explosion_scene: PackedScene = preload("res://scenes/effects/fire_pot_explosion.tscn")
var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")

var has_exploded: bool = false
var velocity: Vector3 = Vector3.ZERO
var _life_left: float = 0.0
var _rotation_update_timer: float = 0.0

func _ready() -> void:
	pool_reset()


func _enter_tree() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	EntityRegistry.register_projectile(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_projectile(self)

func pool_capacity() -> int:
	return 20

func pool_reset() -> void:
	monitoring = false
	monitorable = false
	has_exploded = false
	time_alive = 0.0
	velocity = Vector3.ZERO
	_life_left = lifetime
	_rotation_update_timer = 0.0

func setup_flight(start: Vector3, target: Vector3, flight_time: float = 1.0, arc: float = 3.0) -> void:
	start_pos = start
	target_pos = target
	flight_duration = flight_time
	arc_height = arc
	
	# 초기 방향 설정 (시각적)
	var up_vec = Vector3.UP
	if abs((target_pos - global_position).normalized().y) > 0.999:
		up_vec = Vector3.RIGHT
	look_at(target_pos, up_vec)

func _physics_process(delta: float) -> void:
	if has_exploded: return
	_life_left -= delta
	if _life_left <= 0.0:
		explode()
		return
	
	time_alive += delta
	var t = min(time_alive / flight_duration, 1.0)
	
	# XZ 평면 선형 보간, Y축 포물선 (sin 그래프)
	var current_pos = start_pos.lerp(target_pos, t)
	current_pos.y += sin(t * PI) * arc_height
	
	var last_pos = global_position
	global_position = current_pos
	
	# 작은 투사체라 회전 갱신 빈도를 낮춰도 충분히 자연스럽다.
	_rotation_update_timer += delta
	var frame_dir = current_pos - last_pos
	if _rotation_update_timer >= 0.05 and frame_dir.length_squared() > 0.001:
		_rotation_update_timer = 0.0
		var dir = frame_dir.normalized()
		var up_vec = Vector3.UP
		if abs(dir.y) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(current_pos + dir, up_vec)
	
	# 시각적으로 빙글빙글 돌기
	if has_node("Visual"):
		$Visual.rotate_x(15.0 * delta)
	
	if t >= 1.0:
		explode()

func explode() -> void:
	if has_exploded: return
	has_exploded = true
	
	# 1. 폭발 이펙트 
	if explosion_scene and VfxBudget.allow_spawn(get_tree(), "fire_pot_explosion", global_position, 3, 65.0):
		var expl = ScenePool.acquire(get_tree(), explosion_scene)
		expl.position = global_position
		get_tree().root.add_child.call_deferred(expl)
	
	# 2. 바닥 잔여 화염 이펙트 (1.5초)
	if fire_effect_scene and VfxBudget.allow_spawn(get_tree(), "fire_effect", global_position, 2, 55.0):
		var fire = ScenePool.acquire(get_tree(), fire_effect_scene)
		fire.position = global_position
		if fire is GPUParticles3D:
			fire.emitting = true
		get_tree().root.add_child.call_deferred(fire)
		
		var timer = get_tree().create_timer(1.5)
		timer.timeout.connect(func(): if is_instance_valid(fire): ScenePool.release(fire))
	
	# 3. 사운드
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("explosion_small", global_position, randf_range(0.9, 1.2))
	
	# 4. 범위 데미지 처리 (물리 질의)
	_apply_area_damage()
	
	# 자신 삭제를 객체 풀 반납으로 변경
	ScenePool.release(self)

func _apply_area_damage() -> void:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = global_transform
	# 선박/병사/환경 기본 레이어만 대상으로 제한해 폭발 쿼리 비용을 줄인다.
	query.collision_mask = 7
	
	var results = space_state.intersect_shape(query)
	for result in results:
		var col = result.collider
		
		# 같은 팀(player면 player)에게는 데미지 주지 않음
		if NodeContractHelper.get_team_tag(col) == team:
			continue
			
		# 함선(Ship) 본체에도 화통 폭발 데미지와 화재 유발 적용
		if col.is_in_group("ship") and col.has_method("take_damage"):
			var source_id = "fire_pot" if team == "player" else ""
			col.take_damage(damage * 1.5, global_position, source_id) # 배에는 데미지 1.5배
			if col.has_method("add_fire_buildup"):
				col.add_fire_buildup(30.0) # 화재 게이지 폭증
			elif col.has_method("apply_status_effect"):
				col.apply_status_effect("burn", 5.0)
				
		# 적 병사(Soldier)에게 데미지
		elif col.has_method("take_damage") and NodeContractHelper.get_team_tag(col) != team:
			var soldier_source = "fire_pot" if team == "player" else ""
			col.take_damage(damage, global_position, soldier_source)
			# 불타는 효과를 줄 수 있다면 추가
			if col.has_method("apply_status_effect"):
				col.apply_status_effect("burn", 3.0)
