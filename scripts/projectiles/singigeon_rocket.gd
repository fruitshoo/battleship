extends Area3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")

## 신기전 로켓 (Singigeon Rocket)
## 발키리 스타일: 지향사격 기반 다연장 로켓 (짧은 미세 보정만 적용).

@export var speed: float = 32.0
@export var turn_rate_deg: float = 120.0
@export var damage: float = 2.5 # 함선 데미지 하향 (5.0 -> 2.5)
@export var personnel_damage_mult: float = 5.0 # 병사 데미지 배수 하향 (25 -> 5)
@export var lifetime: float = 3.0
@export var blast_radius: float = 3.5
@export var splash_damage_mult: float = 0.35
@export var lock_on_delay: float = 0.12
@export var retarget_radius: float = 16.0
@export var proximity_hit_radius: float = 1.2
@export var homing_duration: float = 0.35
@export var max_homing_distance: float = 14.0
@export var allow_retarget: bool = false
@export var explosion_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")

var team: String = "player"
var shooter: Node3D = null # 이 로켓을 쏜 선박 (오사 방지용)
var target_node: Node3D = null
var launch_direction: Vector3 = Vector3.ZERO

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var has_exploded: bool = false
var _velocity: Vector3 = Vector3.ZERO
var _life_left: float = 0.0
var _lock_on_left: float = 0.0
var _homing_left: float = 0.0

func _ready() -> void:
	global_position = start_pos
	_life_left = lifetime
	_lock_on_left = maxf(0.0, lock_on_delay)
	_homing_left = maxf(0.0, homing_duration)

	var init_dir = launch_direction
	if init_dir.length_squared() < 0.001:
		if is_instance_valid(target_node):
			init_dir = target_node.global_position - global_position
		elif start_pos.distance_squared_to(target_pos) > 0.01:
			init_dir = target_pos - start_pos
		else:
			init_dir = -global_transform.basis.z
	if init_dir.length_squared() < 0.001:
		init_dir = Vector3.FORWARD
	_velocity = init_dir.normalized() * speed
	_face_velocity()
	
	# 발사 사운드 재생 (01, 02, 03 무작위 선택)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		var rand = randf()
		var sfx_name = "rocket_launch_01"
		if rand > 0.66: sfx_name = "rocket_launch_03"
		elif rand > 0.33: sfx_name = "rocket_launch_02"
		
		audio_manager.play_sfx(sfx_name, global_position, randf_range(0.9, 1.1))
	
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	if has_exploded:
		return

	_life_left -= delta
	if _life_left <= 0.0:
		_explode()
		queue_free()
		return

	if _lock_on_left > 0.0:
		_lock_on_left -= delta
	else:
		_homing_left = maxf(0.0, _homing_left - delta)

	var current_dir = _velocity.normalized()
	var desired_dir = current_dir
	if _lock_on_left <= 0.0 and _homing_left > 0.0:
		var homing_target = _resolve_homing_target()
		if is_instance_valid(homing_target):
			var aim_point = homing_target.global_position + Vector3(0.0, 0.4, 0.0)
			var to_target = aim_point - global_position
			if to_target.length_squared() > 0.0001 and to_target.length_squared() <= max_homing_distance * max_homing_distance:
				desired_dir = to_target.normalized()

	var turn_weight = clampf(deg_to_rad(turn_rate_deg) * delta, 0.0, 1.0)
	current_dir = current_dir.slerp(desired_dir, turn_weight).normalized()
	_velocity = current_dir * speed

	var prev_pos = global_position
	global_position += _velocity * delta
	_face_velocity()

	var hit_node = _raycast_hit(prev_pos, global_position)
	if hit_node:
		_on_hit(hit_node)
		return

	if is_instance_valid(target_node) and _lock_on_left <= 0.0:
		if global_position.distance_squared_to(target_node.global_position) <= proximity_hit_radius * proximity_hit_radius:
			_on_hit(target_node)

func _face_velocity() -> void:
	if _velocity.length_squared() <= 0.0001:
		return
	var look_target = global_position + _velocity
	var up_vec = Vector3.UP
	var dir = _velocity.normalized()
	if absf(dir.y) > 0.999:
		up_vec = Vector3.RIGHT
	look_at(look_target, up_vec)

func _resolve_homing_target() -> Node3D:
	if not is_instance_valid(target_node):
		target_node = null
	if _is_valid_ship_target(target_node):
		return target_node
	if not allow_retarget:
		return null

	var enemy_group = "enemy" if team == "player" else "player"
	var best_target: Node3D = null
	var best_dist_sq = retarget_radius * retarget_radius

	for candidate in get_tree().get_nodes_in_group(enemy_group):
		if not (candidate is Node3D):
			continue
		var ship := candidate as Node3D
		if not _is_valid_ship_target(ship):
			continue

		var dist_sq = global_position.distance_squared_to(ship.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_target = ship

	target_node = best_target
	return best_target

func _is_valid_ship_target(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	if not (ship is Node3D):
		return false
	var ship_3d := ship as Node3D
	if ship_3d.is_queued_for_deletion():
		return false
	if shooter and (ship_3d == shooter or ship_3d.get_parent() == shooter):
		return false
	if ship_3d.get("is_derelict") == true:
		return false
	if ship_3d.get("is_sinking") == true:
		return false

	var target_group = "enemy" if team == "player" else "player"
	return HitTargetResolver.resolve_team_tag(ship_3d) == target_group

func _raycast_hit(from_pos: Vector3, to_pos: Vector3) -> Node:
	var world = get_world_3d()
	if not world:
		return null
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [self]
	var result = world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result.get("collider")

func _on_hit(target: Node) -> void:
	if has_exploded: return
	
	var hit_obj = HitTargetResolver.resolve_ship_from_node(target)
	if not is_instance_valid(hit_obj) or not _is_valid_ship_target(hit_obj):
		return

	# 직격 + 주변 스플래시 피해
	_explode(hit_obj)
	queue_free()

func _apply_damage(target_node: Node, scale: float = 1.0) -> void:
	if not is_instance_valid(target_node): return
	
	# 데미지 보정 (블랙 파우더 업그레이드 등)
	var dmg_mult = 1.0
	var fire_lv = 0
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and "current_levels" in upgrade_manager:
		var singigeon_lv = upgrade_manager.current_levels.get("singigeon", 0)
		dmg_mult += (0.15 * singigeon_lv) # 레벨당 데미지 15% 증가
		fire_lv = int(singigeon_lv / 3.0) # 3레벨마다 화염 데미지 상승

	if target_node.has_method("take_damage"):
		var final_damage = damage * dmg_mult * scale
		if target_node is CharacterBody3D or target_node.is_in_group("soldiers"):
			final_damage *= personnel_damage_mult
		
		var source_id = "singigeon" if team == "player" else ""
		target_node.take_damage(final_damage, global_position, source_id)
		
		# 점화 효과
		if fire_lv > 0 and target_node.has_method("take_fire_damage"):
			target_node.take_fire_damage(fire_lv * 2.0, 5.0)
	elif target_node.has_method("die"):
		target_node.die()

func _explode(primary_target: Node3D = null) -> void:
	if has_exploded:
		return
	has_exploded = true

	if is_instance_valid(primary_target):
		_apply_damage(primary_target, 1.0)
	var splash_targets = _find_splash_targets()
	for ship in splash_targets:
		if ship == primary_target:
			continue
		_apply_damage(ship, splash_damage_mult)

	# 트레일 중단
	var trail = get_node_or_null("RocketTrail")
	if trail:
		trail.emitting = false
	
	# 폭발 VFX(화염/연기) 제거 - 요청에 따라 나무 파편(take_damage 내에 있음)만 남김
	# 폭발 사운드는 타격감 유지를 위해 남겨둠
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("impact_wood", global_position, randf_range(0.7, 0.9))

func _find_splash_targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var enemy_group = "enemy" if team == "player" else "player"
	var radius_sq = blast_radius * blast_radius
	for node in get_tree().get_nodes_in_group(enemy_group):
		if not (node is Node3D):
			continue
		var ship := node as Node3D
		if not _is_valid_ship_target(ship):
			continue
		if global_position.distance_squared_to(ship.global_position) <= radius_sq:
			out.append(ship)
	return out
