extends "res://scripts/entities/weapons/weapon.gd"

@export var arrow_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@export var shoot_cooldown: float = 2.0
@export var max_range: float = 25.0

func _ready() -> void:
	damage = 12.0
	attack_range = max_range
	attack_cooldown = shoot_cooldown

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not arrow_scene: return
	
	var arrow = arrow_scene.instantiate() as Node3D
	# 발사 위치는 활(또는 병사 가슴 위치) 부근으로 약간 보정
	var spawn_pos = attacker.global_position
	spawn_pos.y += 0.8
	
	# 기본 타겟 위치
	var current_target_pos = target.global_position
	current_target_pos.y += 0.5
	
	# === 예측 샷 (Predictive Aiming) ===
	var arrow_speed = 25.0
	var distance = spawn_pos.distance_to(current_target_pos)
	var time_to_reach = distance / arrow_speed
	
	# 타겟의 이동 속도(velocity)를 기반으로 미래 위치 예측
	var local_vel = target.get("velocity") if "velocity" in target else Vector3.ZERO
	
	# 타겟이 배 위에 타고 있는 경우 배의 이동 속도 합산
	var node = target
	var ship = null
	while node and node != target.get_tree().root:
		if "current_speed" in node:
			ship = node
			break
		node = node.get_parent()
		
	var ship_vel = Vector3.ZERO
	if ship and "current_speed" in ship:
		var s_speed = ship.get("current_speed")
		if s_speed > 0.1:
			var s_dir = - ship.global_transform.basis.z.normalized()
			
			# chaser_ship의 move_dir가 있다면 그것을 사용
			if "move_dir" in ship and typeof(ship.get("move_dir")) == TYPE_VECTOR3:
				s_dir = ship.get("move_dir").normalized()
				
			ship_vel = s_dir * s_speed
			
	var total_vel = local_vel + ship_vel
	current_target_pos += total_vel * time_to_reach * 0.85 # 85% 예측

	
	# 약간의 오차 (흩뿌림) 적용 - 기존보다 하향하여 명중률 상승 (-0.2 ~ 0.2)
	current_target_pos.x += randf_range(-0.2, 0.2)
	current_target_pos.z += randf_range(-0.2, 0.2)
	
	# 데이터 설정 (SceneTree에 추가하기 전에 설정하여 _ready에서 사용 가능하게 함)
	if "start_pos" in arrow: arrow.start_pos = spawn_pos
	if "target_pos" in arrow: arrow.target_pos = current_target_pos
	if "speed" in arrow: arrow.speed = arrow_speed # 속도 강제 동기화
	
	var dmg_mult = attacker.get_meta("damage_multiplier") if attacker.has_meta("damage_multiplier") else 1.0
	if "damage" in arrow: arrow.damage = damage * dmg_mult
	
	# 병사 팀 정보 전달
	if "team" in arrow:
		if "team" in attacker:
			arrow.team = attacker.get("team")
			
	# 거리에 따른 곡선 조절
	if "arc_height" in arrow:
		var dist = spawn_pos.distance_to(current_target_pos)
		arrow.arc_height = clamp(dist * 0.3, 1.0, 5.0)
	
	# 레벨 매니저 또는 부모 트리에 추가 (이 시점에 _ready 실행됨)
	var lm = attacker.get_tree().root.find_child("LevelManager", true, false)
	if lm:
		lm.add_child(arrow)
	else:
		attacker.get_tree().root.add_child(arrow)
		
	# 위치 및 방향 최종 보정
	arrow.global_position = spawn_pos
	arrow.look_at(current_target_pos, Vector3.UP)
	
	# 활 쏘는 소리
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("arrow_shoot", attacker.global_position, randf_range(0.9, 1.1))
