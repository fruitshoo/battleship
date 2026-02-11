extends Area3D

## 대포알 (Cannonball)
## 정해진 방향으로 전진하며, 적과 충돌 시 적을 파괴함

@export var speed: float = 100.0 # Increased speed from 80.0 to 100.0
@export var lifetime: float = 3.0 # 사거리 대신 시간으로 제한
@export var damage: float = 1.0
@export var homing_strength: float = 0.0 # 유도 제거
@export var homing_duration: float = 0.0 # 유도 제거

var direction: Vector3 = Vector3.FORWARD
var target_node: Node3D = null
var time_alive: float = 0.0

func _spawn_effects() -> void:
	# 사운드 재생
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("impact_wood", global_position)

	# 시각 이펙트 (기존 로직)
	# Note: The original instruction snippet for _spawn_effects included lines from _ready().
	# Assuming the intent was to add the SFX and keep existing _ready() logic separate.
	# If there was an explosion_scene or visual effect logic intended here, it was not fully provided.

func _ready() -> void:
	# 3초 뒤 자동 삭제
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	
	# 신호 연결
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	time_alive += delta
	# 부드러운 유도 (Soft Homing) - 초반만 작동
	if time_alive < homing_duration and is_instance_valid(target_node):
		var to_target = (target_node.global_position - global_position).normalized()
		direction = direction.lerp(to_target, homing_strength * delta).normalized()
		look_at(global_position + direction, Vector3.UP)
		
	global_position += direction * speed * delta


func _on_area_entered(area: Area3D) -> void:
	_check_hit(area)

func _on_body_entered(body: Node3D) -> void:
	_check_hit(body)

func _check_hit(target: Node) -> void:
	# 적 그룹 확인 (chaser_ship.gd는 enemy 그룹이어야 함)
	if target.is_in_group("enemy") or (target.get_parent() and target.get_parent().is_in_group("enemy")):
		var enemy = target if target.is_in_group("enemy") else target.get_parent()
		
		# 적 파괴 로직 수정: take_damage 우선 호출 (충돌 위치 전달)
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, global_position)
		elif enemy.has_method("die"):
			enemy.die()
		else:
			enemy.queue_free()
			
		# 이펙트 및 사운드 재생
		_spawn_effects()
			
		# 대포알도 삭제
		queue_free()
