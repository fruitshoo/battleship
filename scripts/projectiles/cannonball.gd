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

func _spawn_effects(_is_crit: bool = false) -> void:
	if not is_instance_valid(AudioManager): return
	
	# 나무 부서지는 소리 재생
	AudioManager.play_sfx("impact_wood", global_position, randf_range(0.9, 1.1))

func _ready() -> void:
	# 충돌 시그널 연결
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# 수명 종료 시 자동 삭제
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
	# 부드러운 유도 (Soft Homing) - 초반만 작동 (사용 시)
	if time_alive < homing_duration and is_instance_valid(target_node):
		var to_target = (target_node.global_position - global_position).normalized()
		direction = direction.lerp(to_target, homing_strength * delta).normalized()
		look_at(global_position + direction, Vector3.UP)
		
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


func _on_area_entered(area: Area3D) -> void:
	_check_hit(area)

func _on_body_entered(body: Node3D) -> void:
	_check_hit(body)

func _check_hit(target: Node) -> void:
	if has_hit: return
	
	# 일단 무언가에 부딪혔으므로 삭제 준비
	has_hit = true
	
	# 적/아군 함선 그룹 확인
	var enemy = null
	if target.is_in_group("enemy") or (target.get_parent() and target.get_parent().is_in_group("enemy")):
		enemy = target if target.is_in_group("enemy") else target.get_parent()
	elif target.is_in_group("player") or (target.get_parent() and target.get_parent().is_in_group("player")):
		enemy = target if target.is_in_group("player") else target.get_parent()
	
	if enemy:
		# 함선 적중 시 데미지 처리
		var is_crit = randf() < crit_chance
		var final_damage = damage * (crit_multiplier if is_crit else 1.0)
		
		if enemy.has_method("take_damage"):
			enemy.take_damage(final_damage, global_position)
		elif enemy.has_method("die"):
			enemy.die()
		else:
			enemy.queue_free()
		
		_spawn_effects(is_crit)
	else:
		# 함선 외의 물체에 부딪혔을 때 (물보라 소리와 함께 삭제)
		if is_instance_valid(AudioManager):
			AudioManager.play_sfx("water_splash_large", global_position, randf_range(1.0, 1.3))
	
	# 어떤 경우든 부딪히면 삭제
	queue_free()
