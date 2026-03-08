extends Area3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

## 대포알 (Cannonball)
## 정해진 방향으로 전진하며, 적과 충돌 시 적을 파괴함

@export var speed: float = 50.0
@export var lifetime: float = 2.0 # 사거리 단축 (80 * 2 = 160m)
@export var damage: float = 1.0
@export var homing_strength: float = 0.0 # 유도 제거
@export var homing_duration: float = 0.0 # 유도 제거
@export var crit_chance: float = 0.2 # 20% 크리티컬 확률
@export var crit_multiplier: float = 2.0 # 크리티컬 2배 데미지
@export var impact_smoke_scene: PackedScene = preload("res://scenes/effects/muzzle_smoke.tscn")
var water_explosion_scene: PackedScene = preload("res://scenes/effects/water_explosion.tscn")

var team: String = "player"
var direction: Vector3 = Vector3.FORWARD
var target_node: Node3D = null
var time_alive: float = 0.0

func set_lifetime_multiplier(mult: float) -> void:
	lifetime *= mult

func _spawn_effects(_is_crit: bool = false) -> void:
	var audio_manager = get_node_or_null("/root/AudioManager")
	if not is_instance_valid(audio_manager): return
	
	# 나무 부서지는 소리 재생
	if audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("impact_wood", global_position, randf_range(0.9, 1.1))

	# 타격 시 검은 연기(발사 시 나오는 연기 재사용) 생성
	if impact_smoke_scene and VfxBudget.allow_spawn(get_tree(), "muzzle_smoke", global_position, 5, 65.0):
		var smoke = impact_smoke_scene.instantiate()
		smoke.position = global_position
		# 연기는 위쪽으로 퍼지게 (Basis 직접 설정)
		smoke.basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)
		get_tree().root.add_child.call_deferred(smoke)
		if smoke is GPUParticles3D:
			smoke.emitting = true

func _ready() -> void:
	# 팀에 따른 충돌 마스크 자동 설정
	if team == "player":
		# 아군 대포알 → 적군(layer 4) 감시
		collision_mask = 4
	else:
		# 적군 대포알 → 플레이어(layer 2) 감시
		collision_mask = 2
		
	# 충돌 시그널 연결
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# 수명 종료 시 자동 삭제
	get_tree().create_timer(lifetime).timeout.connect(_on_timeout)

var has_hit: bool = false

func _on_timeout() -> void:
	if has_hit: return
	
	# 수명 만료 = 바다에 떨어짐 → 물 폭발 이펙트 생성
	_spawn_water_explosion()
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
	queue_free()

func _physics_process(delta: float) -> void:
	if has_hit: return
	
	time_alive += delta
	# 부드러운 유도 (Soft Homing) - 초반만 작동 (사용 시)
	if time_alive < homing_duration and is_instance_valid(target_node):
		var to_target = (target_node.global_position - global_position).normalized()
		direction = direction.lerp(to_target, homing_strength * delta).normalized()
		var up_vec = Vector3.UP
		if abs(direction.y) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(global_position + direction, up_vec)
		
	var move_vec = direction * speed * delta
	var next_pos = global_position + move_vec
	
	# CCD (Continuous Collision Detection)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, next_pos, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		global_position = result.position
		_check_hit(result.collider)
		return
		
	global_position = next_pos
	
	# 수면(y=0.0) 타격 감지 기능 추가
	if global_position.y <= 0.0:
		_spawn_water_explosion()
		var audio_manager = get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
		has_hit = true
		queue_free()


func _on_area_entered(area: Area3D) -> void:
	_check_hit(area)

func _on_body_entered(body: Node3D) -> void:
	_check_hit(body)

func _check_hit(target: Node) -> void:
	if has_hit: return
	
	# 일단 무언가에 부딪혔으므로 삭제 준비
	has_hit = true
	
	# 적 함선 찾기 로직 강화
	var ship = HitTargetResolver.resolve_ship_from_node(target)
		
	if ship:
		# 피아 식별 (내 팀과 같은 팀이면 통과 - 오사 방지)
		var ship_team = HitTargetResolver.resolve_team_tag(ship)
		if ship_team == team:
			has_hit = false # 아군이면 맞은 걸로 치지 않음 (관통)
			return
		
		# 적중 처리
		var is_crit = randf() < crit_chance
		var final_damage = damage * (crit_multiplier if is_crit else 1.0)
		
		if ship.has_method("take_damage"):
			var source_id = "cannon" if team == "player" else ""
			ship.take_damage(final_damage, global_position, source_id)
		
		_spawn_effects(is_crit)
		queue_free()
	else:
		# 침몰 중인 함선에 맞은 거면 무시 (부자연스러운 물폭발 방지)
		var is_sinking = false
		if target.has_method("get") and target.get("is_sinking") == true: is_sinking = true
		elif target.get_parent() and target.get_parent().has_method("get") and target.get_parent().get("is_sinking") == true: is_sinking = true
			
		if not is_sinking:
			# 함선 외의 물체에 부딪혔을 때 → 물 폭발 이펙트 생성
			_spawn_water_explosion()
			var audio_manager = get_node_or_null("/root/AudioManager")
			if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
				audio_manager.play_sfx("water_splash_large", global_position, randf_range(1.0, 1.3))
	
	# 어떤 경우든 부딪히면 삭제
	queue_free()

func _spawn_water_explosion() -> void:
	if not is_inside_tree() or not water_explosion_scene: return
	if not VfxBudget.allow_spawn(get_tree(), "water_explosion", global_position, 4, 70.0):
		return
	
	var pos = global_position
	var explosion = water_explosion_scene.instantiate()
	# 수면 높이에 맞춘 위치를 한 번에 설정
	# 대포알은 root에 추가되므로 position이 global_position과 동일하며, 
	# 씬 트리에 없는 노드의 global_position을 건드리면 에러가 발생하므로 position 사용.
	explosion.position = Vector3(pos.x, 0.2, pos.z)
	get_tree().root.add_child.call_deferred(explosion)
