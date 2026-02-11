extends Node3D

## 추적선 (Chaser Ship)
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var move_speed: float = 3.5 # 플레이어보다 약간 빠르게? (4.0 -> 3.5 너프)
@export var soldier_scene: PackedScene = preload("res://scenes/soldier.tscn")
@export var boarders_count: int = 2 # 도선시킬 병사 수

@export var hp: float = 5.0 # 체력 상향 (1.0 -> 5.0)
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")

var target: Node3D = null
var is_dying: bool = false
@onready var wake_trail: GPUParticles3D = $WakeTrail if has_node("WakeTrail") else null

# 데미지 처리 (hit_position 추가됨)
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_dying: return
	hp -= amount
	
	# 피격 이펙트 (파편)
	if wood_splinter_scene:
		var splinter = wood_splinter_scene.instantiate()
		get_tree().root.add_child(splinter)
		
		if hit_position != Vector3.ZERO:
			splinter.global_position = hit_position + Vector3(0, 0.5, 0)
		else:
			var offset = Vector3(randf_range(-0.5, 0.5), 1.5, randf_range(-0.5, 0.5))
			splinter.global_position = global_position + offset
		splinter.rotation.y = randf() * TAU
	
	if hp <= 0:
		die()

func die() -> void:
	if is_dying: return
	is_dying = true
	
	# 점수 및 XP 추가
	var lm = get_tree().root.find_child("LevelManager", true, false)
	if lm:
		if lm.has_method("add_score"):
			lm.add_score(100)
		if lm.has_method("add_xp"):
			lm.add_xp(30)
	
	# 물리 및 충돌 비활성화 (Area3D 대응)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# 항적 끄기
	if wake_trail:
		wake_trail.emitting = false
	
	# 침몰 애니메이션 (기울어지며 가라앉음)
	var sink_tween = create_tween()
	sink_tween.set_parallel(true)
	
	# 무작위 기울기
	var tilt_x = randf_range(-15.0, 15.0)
	var tilt_z = randf_range(-10.0, 10.0)
	sink_tween.tween_property(self, "rotation_degrees:x", tilt_x, 3.0).set_ease(Tween.EASE_OUT)
	sink_tween.tween_property(self, "rotation_degrees:z", tilt_z, 3.0).set_ease(Tween.EASE_OUT)
	
	# 아래로 가라앉음
	sink_tween.tween_property(self, "global_position:y", global_position.y - 5.0, 3.5).set_ease(Tween.EASE_IN)
	
	sink_tween.set_parallel(false)
	sink_tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	if is_dying: return
	
	# 타겟 유효성 및 침몰 상태 체크
	if not is_instance_valid(target) or target.get("is_sinking"):
		target = null
		_find_player()
		
		# 타겟이 없으면 정지 및 항적 비활성화
		if not is_instance_valid(target):
			if wake_trail: wake_trail.emitting = false
			return
	
	# 1. 목표 지점 계산 (Galley Intercept Logic)
	var target_pos = Vector3.ZERO
	var dist_to_player = global_position.distance_to(target.global_position)
	
	# 공격 로직: "동양 갤리선 전술" - 예측 요격 후 충돌 (Intercept & Ram)
	if dist_to_player < 25.0:
		# 25m 이내: 예측 불필요, 즉시 충돌(Ram) 시도
		target_pos = target.global_position
	else:
		# 25m 밖: 플레이어의 이동 경로를 예측하여 앞질러감 (Intercept)
		var target_velocity = Vector3.ZERO
		# Ship.gd의 변수 직접 접근 (current_speed, rotation)
		if target.get("current_speed"):
			var target_speed = target.get("current_speed")
			# 플레이어의 전방 벡터 (Ship.gd 기준: -Z가 전방)
			# 주의: rotation.y가 라디안인지 각도인지 확인 필요 (Ship.gd는 라디안 사용)
			var target_forward = Vector3(-sin(target.rotation.y), 0, -cos(target.rotation.y))
			target_velocity = target_forward * target_speed
		
		# 예상 소요 시간 (거리 / 내 속도)
		var time_to_reach = dist_to_player / move_speed
		
		# 예측 지점 = 현재 위치 + (속도 * 시간)
		# 너무 먼 미래를 예측하면 엉뚱한 곳으로 가므로 시간 제한 (최대 3초)
		time_to_reach = min(time_to_reach, 3.0)
		target_pos = target.global_position + (target_velocity * time_to_reach)

	# 2. 이동 및 회전 (Separation 포함)
	var direction = (target_pos - global_position).normalized()
	
	# Separation (함선 간 겹침 방지)
	var separation_force = _calculate_separation()
	if separation_force.length_squared() > 0.001:
		direction = (direction + separation_force * 1.5).normalized() # 밀어내는 힘 반영 가중치 1.5
	
	var target_rotation_y = atan2(-direction.x, -direction.z)
	
	# 부드러운 회전 (Lerp) - 노 젓기(Rowing)로 선회력이 좋음 (1.5 -> 3.0 상향)
	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * 3.0)
	
	# 전진
	translate(Vector3.FORWARD * move_speed * delta)
	
	# 항적 제어
	if wake_trail:
		wake_trail.emitting = move_speed > 0.5


## 주변 적함들로부터 멀어지려는 힘 계산
func _calculate_separation() -> Vector3:
	var force = Vector3.ZERO
	var neighbors = get_tree().get_nodes_in_group("enemy")
	var count = 0
	var separation_dist = 5.0 # 함선 간 최소 유지 거리 (반경)
	
	for other in neighbors:
		if other == self or other.get("is_dying"):
			continue
			
		var dist = global_position.distance_to(other.global_position)
		if dist < separation_dist and dist > 0.001:
			# 가까울수록 더 강하게 밀어냄 (거리에 반비례)
			var push_dir = (global_position - other.global_position).normalized()
			force += push_dir / dist
			count += 1
			
	if count > 0:
		force = force / count
		
	return force


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		# 침몰 중이 아닌 배만 타겟으로 잡음
		if not p.get("is_sinking"):
			target = p
			break


## 충돌 감지 (Area3D signal 연결 필요)
func _on_body_entered(body: Node3D) -> void:
	# 플레이어와 충돌했는지 확인 (StaticBody/CharacterBody 등)
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		_board_ship(body)

func _on_area_entered(area: Area3D) -> void:
	# 플레이어의 감지 영역(ProximityArea)과 충돌했는지 확인
	# ProximityArea의 부모가 PlayerShip인지 확인
	var parent = area.get_parent()
	if parent and parent.is_in_group("player"):
		_board_ship(parent)


func _board_ship(target_ship: Node3D) -> void:
	if is_dying: return
	
	# 대상이 진짜 배인지 확인 (충돌체가 배의 자식일 수 있음)
	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not ship_node or not ship_node.is_in_group("player"):
			return # 배가 아니면 무시

	# 1. 충돌(Ram) 데미지 및 연출 적용
	var ram_damage = move_speed * 5.0 # 속도 기반 데미지
	var collision_pos = global_position # 대략적인 충돌 위치
	
	# 플레이어에게 데미지 (VFX 포함)
	if ship_node.has_method("take_damage"):
		ship_node.take_damage(ram_damage, collision_pos)
	
	# 자신(적함)에게도 충돌 데미지 연출 (VFX 트리거를 위해)
	take_damage(hp, collision_pos) # 자폭 수준의 데미지
	
	print("💥 충돌 발생! (VFX 트리거됨)")

	# 2. 병사 '월선' 처리 (리페어런팅)
	if soldier_scene:
		var target_soldiers_node = ship_node.get_node_or_null("Soldiers")
		if not target_soldiers_node:
			target_soldiers_node = ship_node
		
		# 내 배에 있는 병사들 가져오기
		var my_soldiers = []
		if has_node("Soldiers"):
			my_soldiers = $Soldiers.get_children()
		
		var transferred_count = 0
		for s in my_soldiers:
			if transferred_count >= boarders_count: break
			if s.get("current_state") == 4: continue # 죽은 병사는 제외 (4 = DEAD)
			
			# 물리 콜백 중 리페어런팅 에러 방지를 위해 지연 호출
			s.call_deferred("reparent", target_soldiers_node)
			
			# 위치 보정 (플레이어 배 위로 점프 느낌) - 역시 지연 처리 필요할 수 있음
			var jump_offset = Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5))
			s.set_deferred("global_position", ship_node.global_position + jump_offset)
			
			# 상태 초기화 및 적군 설정
			if s.has_method("set_team"): s.set_team("enemy")
			if s.get("is_stationary"): s.set("is_stationary", false)
			
			transferred_count += 1
		
		# 부족한 병사만큼 새로 생성 (백업)
		for i in range(boarders_count - transferred_count):
			var new_s = soldier_scene.instantiate()
			target_soldiers_node.add_child(new_s)
			new_s.set_team("enemy")
			var spawn_offset = Vector3(randf_range(-1, 1), 1.0, randf_range(-2, 2))
			new_s.global_position = ship_node.global_position + spawn_offset
	
	# 3. 자폭 (침몰 연출 호출)
	die()
