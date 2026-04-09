extends "res://scripts/entities/weapons/weapon.gd"
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

@export var arrow_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@export var shoot_cooldown: float = 2.0
@export var max_range: float = 20.0

# 연발 설정
var burst_count: int = 3
var burst_delay: float = 0.15
var _cached_spawn_parent: Node = null

func _ready() -> void:
	refresh_upgrade_stats()

func refresh_upgrade_stats() -> void:
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
	
	# 코루틴으로 연사 처리
	_fire_burst(target, attacker)


func _fire_burst(target: Node3D, attacker: Node3D) -> void:
	for i in range(burst_count):
		if not is_instance_valid(target) or not is_instance_valid(attacker):
			break
			
		# 적이 도중에 죽었으면 발사 중단
		if target.has_method("get_current_state_value") and target.get_current_state_value() == 3: # 3 = DEAD
			break
			
		# 발사 위치는 활 부근으로 약간 보정 (매번 갱신)
		var spawn_pos = attacker.global_position
		spawn_pos.y += 0.8
		
		var current_target_pos = target.global_position
		current_target_pos.y += 0.5
		
		# === 예측 샷 (Predictive Aiming) ===
		var arrow_speed = 30.0 # 연노 화살은 약간 더 빠름
		var distance = spawn_pos.distance_to(current_target_pos)
		var time_to_reach = distance / arrow_speed
		
		if time_to_reach < 0.2:
			time_to_reach = 0.2
			
		var local_vel: Vector3 = target.get_velocity_value() if target.has_method("get_velocity_value") else (target.get("velocity") if "velocity" in target else Vector3.ZERO)
		
		var ship = _resolve_parent_ship(target)
			
		var ship_vel = Vector3.ZERO
		if ship and ship.has_method("get_current_speed_value"):
			var s_speed = ship.get_current_speed_value()
			if s_speed > 0.1:
				var s_dir = ship.get_move_direction_value() if ship.has_method("get_move_direction_value") else -ship.global_transform.basis.z.normalized()
				ship_vel = s_dir * s_speed
				
		var total_vel = local_vel + ship_vel
		current_target_pos += total_vel * time_to_reach * 0.92
		
		# 약간의 오차 (흩뿌림) 적용 - 연사 시 오차를 더 크게 (현실감)
		current_target_pos.x += randf_range(-0.22, 0.22)
		current_target_pos.z += randf_range(-0.22, 0.22)
		
		var dmg_mult = attacker.get_meta("damage_multiplier") if attacker.has_meta("damage_multiplier") else 1.0
		var team_name: String = attacker.get_team_tag() if attacker.has_method("get_team_tag") else "player"
		var dist = spawn_pos.distance_to(current_target_pos)
		var final_arc_height: float = clamp(dist * 0.2, 0.5, 3.0) # 연노는 궤적이 더 낮음 (빠석궁)
		
		# 씬 트리에 추가
		var spawn_parent = _resolve_spawn_parent(attacker.get_tree())
		var arrow = ScenePool.acquire(attacker.get_tree(), arrow_scene) as Node3D
		spawn_parent.add_child(arrow)
		if arrow.has_method("launch"):
			arrow.launch(
				spawn_pos,
				current_target_pos,
				target,
				team_name,
				damage * dmg_mult,
				"repeating_crossbow",
				arrow_speed,
				final_arc_height
			)
			
		arrow.global_position = spawn_pos
		arrow.look_at(current_target_pos, Vector3.UP)
		
		var audio_manager = attacker.get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager):
			audio_manager.play_sfx("arrow_shoot", attacker.global_position, randf_range(1.1, 1.3), 4.0) # 조금 높은 피치, 볼륨 증가
			
		# 다음 발사 대기
		if i < burst_count - 1:
			await attacker.get_tree().create_timer(burst_delay).timeout

func _resolve_parent_ship(node: Node, max_depth: int = 6) -> Node3D:
	var current = node
	var depth = 0
	while is_instance_valid(current) and depth <= max_depth:
		if current is Node3D and "current_speed" in current:
			return current as Node3D
		current = current.get_parent()
		depth += 1
	return null

func _resolve_spawn_parent(tree: SceneTree) -> Node:
	if is_instance_valid(_cached_spawn_parent):
		return _cached_spawn_parent
	var lm = LevelManagerRegistry.get_level_manager(tree)
	if is_instance_valid(lm):
		_cached_spawn_parent = lm
		return _cached_spawn_parent
	_cached_spawn_parent = tree.root
	return _cached_spawn_parent
