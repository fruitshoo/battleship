extends "res://scripts/entities/weapons/weapon.gd"
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

const BASE_DAMAGE: float = 18.0
const OWNER_ATTACK_BONUS_SCALE: float = 0.55

@export var arrow_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@export var shoot_cooldown: float = 2.0
@export var max_range: float = 20.0
var _cached_spawn_parent: Node = null

func _ready() -> void:
	damage = BASE_DAMAGE
	attack_range = max_range
	attack_cooldown = shoot_cooldown


func apply_owner_attack_damage(owner_attack_damage: float) -> void:
	var owner_bonus: float = maxf(0.0, owner_attack_damage - 12.0)
	damage = BASE_DAMAGE + (owner_bonus * OWNER_ATTACK_BONUS_SCALE)

func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or not arrow_scene: return
	
	var arrow = ScenePool.acquire(attacker.get_tree(), arrow_scene) as Node3D
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
	
	# arrow.gd 내부의 duration 최소값(0.2)과 동기화하여 근거리 예측 오류 방지
	if time_to_reach < 0.2:
		time_to_reach = 0.2
		
	# 타겟의 이동 속도(velocity)를 기반으로 미래 위치 예측
	var local_vel: Vector3 = target.get_velocity_value() if target.has_method("get_velocity_value") else (target.get("velocity") if "velocity" in target else Vector3.ZERO)
	
	# 타겟이 배 위에 타고 있는 경우 배의 이동 속도 합산
	var ship = _resolve_parent_ship(target)
		
	var ship_vel = Vector3.ZERO
	if ship and ship.has_method("get_current_speed_value"):
		var s_speed = ship.get_current_speed_value()
		if s_speed > 0.1:
			var s_dir = - ship.global_transform.basis.z.normalized()
			
			# chaser_ship의 move_dir가 있다면 그것을 사용
			if ship.has_method("get_move_direction_value"):
				s_dir = ship.get_move_direction_value()
				
			ship_vel = s_dir * s_speed
			
	var total_vel = local_vel + ship_vel
	current_target_pos += total_vel * time_to_reach * 0.92 # 예측을 조금 더 적극적으로

	
	# 약간의 오차 (흩뿌림) 적용 - 기존보다 하향하여 명중률 상승 (-0.2 ~ 0.2)
	current_target_pos.x += randf_range(-0.12, 0.12)
	current_target_pos.z += randf_range(-0.12, 0.12)
	
	var dmg_mult = attacker.get_meta("damage_multiplier") if attacker.has_meta("damage_multiplier") else 1.0
	var team_name: String = attacker.get_team_tag() if attacker.has_method("get_team_tag") else "player"
	var dist = spawn_pos.distance_to(current_target_pos)
	var final_arc_height: float = clamp(dist * 0.3, 1.0, 5.0)
	
	# 레벨 매니저 또는 부모 트리에 추가 (이 시점에 _ready 실행됨)
	var spawn_parent = _resolve_spawn_parent(attacker.get_tree())
	spawn_parent.add_child(arrow)
	if arrow.has_method("launch"):
		arrow.launch(
			spawn_pos,
			current_target_pos,
			target,
			team_name,
			damage * dmg_mult,
			"bow",
			arrow_speed,
			final_arc_height
		)
		
	# 위치 및 방향 최종 보정
	arrow.global_position = spawn_pos
	arrow.look_at(current_target_pos, Vector3.UP)
	
	# 활 쏘는 소리
	var audio_manager = attacker.get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager):
		audio_manager.play_sfx("arrow_shoot", attacker.global_position, randf_range(0.9, 1.1))

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
