extends "res://scripts/entities/weapons/weapon.gd"

@export var arrow_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@export var shoot_cooldown: float = 2.0
@export var max_range: float = 25.0

# 연발 설정
var burst_count: int = 3
var burst_delay: float = 0.15

func _ready() -> void:
	damage = 10.0 # 기존 활(12)보다 단발은 약하지만 연사로 총합은 높음
	attack_range = max_range
	attack_cooldown = shoot_cooldown
	
	# 업그레이드 매니저 체킹 
	var um = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(um) and "current_levels" in um:
		var lv = um.current_levels.get("repeating_crossbow", 1)
		# 레벨에 따른 발사수 증가 (Lv1: 3, Lv3: 4, Lv5: 5)
		if lv >= 1: burst_count = 3
		if lv >= 3: burst_count = 4
		if lv >= 5: burst_count = 5
		
		# 연노 스탯이 정의되어 있으면 적용
		if "repeating_crossbow" in um.UPGRADES:
			var s = um.UPGRADES["repeating_crossbow"]["stats"]
			damage = s.get("base_damage", 10.0) + (lv - 1) * s.get("damage_per_lv", 2.0)
			attack_cooldown = s.get("base_cooldown", 2.0) - (lv - 1) * s.get("cooldown_reduce_per_lv", 0.2)
			burst_delay = s.get("burst_delay", 0.15)
			
	# 최소 쿨다운 보장 (버스트 쏘는 시간보다 짧으면 꼬임 방지)
	if attack_cooldown < burst_count * burst_delay + 0.5:
		attack_cooldown = burst_count * burst_delay + 0.5

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not arrow_scene: return
	
	# 발사 위치는 활 부근으로 약간 보정
	var spawn_pos = attacker.global_position
	spawn_pos.y += 0.8
	
	# 코루틴으로 연사 처리
	_fire_burst(target, attacker, spawn_pos)


func _fire_burst(target: Node3D, attacker: Node3D, spawn_pos: Vector3) -> void:
	for i in range(burst_count):
		if not is_instance_valid(target) or not is_instance_valid(attacker):
			break
			
		# 적이 도중에 죽었으면 발사 중단
		if target.has_method("get") and target.get("current_state") == 3: # 3 = DEAD
			break
			
		var arrow = arrow_scene.instantiate() as Node3D
		var current_target_pos = target.global_position
		current_target_pos.y += 0.5
		
		# === 예측 샷 (Predictive Aiming) ===
		var arrow_speed = 30.0 # 연노 화살은 약간 더 빠름
		var distance = spawn_pos.distance_to(current_target_pos)
		var time_to_reach = distance / arrow_speed
		
		if time_to_reach < 0.2:
			time_to_reach = 0.2
			
		var local_vel = target.get("velocity") if "velocity" in target else Vector3.ZERO
		
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
				if "move_dir" in ship and typeof(ship.get("move_dir")) == TYPE_VECTOR3:
					s_dir = ship.get("move_dir").normalized()
				ship_vel = s_dir * s_speed
				
		var total_vel = local_vel + ship_vel
		current_target_pos += total_vel * time_to_reach * 0.85
		
		# 약간의 오차 (흩뿌림) 적용 - 연사 시 오차를 더 크게 (현실감)
		current_target_pos.x += randf_range(-0.4, 0.4)
		current_target_pos.z += randf_range(-0.4, 0.4)
		
		# 데이터 설정
		if "start_pos" in arrow: arrow.start_pos = spawn_pos
		if "target_pos" in arrow: arrow.target_pos = current_target_pos
		if "target_node" in arrow: arrow.target_node = target
		if "speed" in arrow: arrow.speed = arrow_speed
		
		var dmg_mult = attacker.get_meta("damage_multiplier") if attacker.has_meta("damage_multiplier") else 1.0
		if "damage" in arrow: arrow.damage = damage * dmg_mult
		
		if "team" in arrow and "team" in attacker:
			arrow.team = attacker.get("team")
				
		if "arc_height" in arrow:
			var dist = spawn_pos.distance_to(current_target_pos)
			arrow.arc_height = clamp(dist * 0.2, 0.5, 3.0) # 연노는 궤적이 더 낮음 (빠석궁)
		
		# 씬 트리에 추가
		var lm = attacker.get_tree().root.find_child("LevelManager", true, false)
		if lm:
			lm.add_child(arrow)
		else:
			attacker.get_tree().root.add_child(arrow)
			
		arrow.global_position = spawn_pos
		arrow.look_at(current_target_pos, Vector3.UP)
		
		if is_instance_valid(AudioManager):
			AudioManager.play_sfx("arrow_shoot", attacker.global_position, randf_range(1.1, 1.3)) # 조금 높은 피치
			
		# 다음 발사 대기
		if i < burst_count - 1:
			await attacker.get_tree().create_timer(burst_delay).timeout
