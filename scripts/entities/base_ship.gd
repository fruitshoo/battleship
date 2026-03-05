@tool
class_name BaseShip
extends Node3D

## 함선의 공통 기반 클래스 (물리, 시각 효과, 내구도 관리)

# === 이동 관련 ===
@export var max_speed: float = 10.0
@export var acceleration: float = 1.5
@export var deceleration: float = 1.2
@export var turn_rate: float = 50.0

# === 충돌 및 겹침 방지 (Separation & Repulsion) ===
@export_category("Collision Physics")
@export var collision_profile: ShipCollisionProfile
@export_range(2.0, 15.0) var base_collision_radius: float = 4.5 ## 기본 충돌 및 밀쳐내기 반경
@export_range(0.1, 3.0) var length_multiplier: float = 1.0 ## 앞/뒤 범위를 늘리거나 줄일 비율 (타원형 길이)
@export_range(0.1, 3.0) var width_multiplier: float = 1.0 ## 좌/우 범위를 늘리거나 줄일 비율 (타원형 폭)
@export var auto_fit_collision_to_hull: bool = true ## 선체 메시 기준으로 충돌 타원값 자동 정렬
@export_range(0.0, 2.0) var collision_padding: float = 0.15 ## 충돌 판정 여유치(반폭/반길이에 추가)
@export_range(0.6, 1.0) var deck_bounds_ratio: float = 0.88 ## 병사 덱 이동 범위 축소 비율

# === 돛 관련 ===
@export var sail_angle: float = 0.0 # 돛 각도 (-90 ~ 90도)

# === 러더(키) 관련 ===
@export var rudder_angle: float = 0.0 # 러더 각도 (-45 ~ 45도)

@export var bobbing_amplitude: float = 0.3
@export var bobbing_speed: float = 1.0
@export var rocking_amplitude: float = 0.05
@export var floating_offset: float = 0.2 ## 기본 부력 오프셋 (수면 위로 배를 띄움)
var _centrifugal_tilt: float = 0.0 # 원심력에 의한 기울기

# === 내부 상태 ===
var current_speed: float = 0.0
var base_y: float = 0.0

# === 디버프 및 모디파이어 ===
var speed_mult: float = 1.0
var turn_mult: float = 1.0
var tilt_offset: float = 0.0
var stuck_objects: Array[Node3D] = []

# === 선체 내구도 ===
@export var max_hull_hp: float = 200.0 # 스케일 상향 (100 -> 200)
var hull_hp: float = 200.0
@export var hull_regen_rate: float = 0.0
var hull_defense: float = 0.0
var deck_height: float = 0.4 ## 함종별 병사 안착 높이

var is_sinking: bool = false
var is_dying: bool = false # 터지기 직전 (보스/적선용)
var is_burning: bool = false
var is_derelict: bool = false # 선원 전멸 시 무력화(폐선)
var boarding_attacker: Node3D = null

# === 도선(Boarding) 상태 및 변수 ===
var is_boarding: bool = false
var boarding_timer: float = 0.0
var boarding_interval: float = 1.5
var boarding_prep_timer: float = 0.0
var boarding_prep_duration: float = 2.5
var boarding_target: Node3D = null
var max_boarding_distance: float = 9.0
var boarding_break_distance: float = 12.0
var rope_instances: Array[MeshInstance3D] = []
var boarding_rope_hp: float = 100.0 # 밧줄 내구도 추가
var max_boarding_rope_hp: float = 100.0
@export_range(0.0, 3.0) var boarding_contact_grace_duration: float = 0.8
@export_range(0.0, 2.0) var boarding_hook_throw_delay: float = 0.35
@export_range(0.0, 3.0) var boarding_secondary_rope_delay: float = 0.9
@export_range(0.5, 8.0) var boarding_max_relative_speed: float = 2.5
@export_range(0.4, 1.0) var boarding_side_alignment_max_dot: float = 0.82
@export_range(1, 3) var boarding_initial_rope_count: int = 1
var boarding_contact_timer: float = 0.0
var boarding_hook_timer: float = 0.0
var boarding_secondary_rope_timer: float = 0.0
var _initial_rope_deployed: bool = false
var _full_rope_deployed: bool = false

var fire_build_up: float = 0.0
var fire_threshold: float = 100.0

# === 충돌 및 충각(Ramming) 관련 상태 ===
var _recent_ram_targets: Dictionary = {}
var min_ramming_speed: float = 6.0 # 충돌 데미지가 발생하기 위한 최소 상대 속도 상향 (4.0 -> 6.0)
var broad_phase_padding: float = 2.0 # 충돌 broad-phase 여유 거리
var burn_timer: float = 0.0

var _last_splinter_time: float = 0.0 # 파편 생성 쿨다운 (최적화)
var _hull_half_extents: Vector2 = Vector2(1.5, 4.0) # X:반폭, Y:반길이


@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
@export var water_splash_scene: PackedScene = preload("res://scenes/effects/water_explosion.tscn")
@export var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")
@export var loot_scene: PackedScene = preload("res://scenes/effects/floating_loot.tscn")
@export var survivor_scene: PackedScene = preload("res://scenes/effects/survivor.tscn")
var _fire_instance: Node3D = null

@export var fire_effect_offset: Vector3 = Vector3(0, 1.5, 0.0)

# === 노드 참조 (이제 HullScene 내부를 스캔) ===
var masts: Array[Node] = []
var rudder_visual: Node3D = null
var wake_trail: GPUParticles3D = null

# Oar (노) 레퍼런스
var oar_pivot_left: Node3D = null
var oar_pivot_right: Node3D = null

var _cached_level_manager: Node = null
var _cached_hud: Node = null
var _cached_ocean: Node3D = null
var _cached_audio_manager: Node = null
var _cached_wave_height: float = 0.0
var _wave_sample_timer: float = 0.0
@export_range(0.02, 0.25) var wave_sample_interval: float = 0.08

func _ready() -> void:
	_ensure_collision_profile()
	base_y = position.y + floating_offset
	add_to_group("ships")
	
	hull_hp = max_hull_hp
	
	# 돛대, 타륜 등의 레퍼런스 캐싱 (에디터/런타임 공통)
	_cache_hull_references(self )
	_refresh_collision_bounds_from_hull()
	
	if Engine.is_editor_hint():
		return

	# 런타임 전용 로직
	_cache_common_references()

func _ensure_collision_profile() -> void:
	# 기존 씬의 export 수치를 유지하면서 프로파일을 기본 소스로 승격한다.
	if collision_profile == null:
		collision_profile = ShipCollisionProfile.new()
		collision_profile.base_collision_radius = base_collision_radius
		collision_profile.length_multiplier = length_multiplier
		collision_profile.width_multiplier = width_multiplier
		collision_profile.auto_fit_collision_to_hull = auto_fit_collision_to_hull
		collision_profile.collision_padding = collision_padding
		collision_profile.deck_bounds_ratio = deck_bounds_ratio
		collision_profile.min_ramming_speed = min_ramming_speed
		collision_profile.broad_phase_padding = broad_phase_padding
	_apply_collision_profile()

func _apply_collision_profile() -> void:
	if collision_profile == null:
		return
	base_collision_radius = collision_profile.base_collision_radius
	length_multiplier = collision_profile.length_multiplier
	width_multiplier = collision_profile.width_multiplier
	auto_fit_collision_to_hull = collision_profile.auto_fit_collision_to_hull
	collision_padding = collision_profile.collision_padding
	deck_bounds_ratio = collision_profile.deck_bounds_ratio
	min_ramming_speed = collision_profile.min_ramming_speed
	broad_phase_padding = collision_profile.broad_phase_padding

func _sync_profile_from_runtime() -> void:
	if collision_profile == null:
		return
	collision_profile.base_collision_radius = base_collision_radius
	collision_profile.length_multiplier = length_multiplier
	collision_profile.width_multiplier = width_multiplier
	collision_profile.auto_fit_collision_to_hull = auto_fit_collision_to_hull
	collision_profile.collision_padding = collision_padding
	collision_profile.deck_bounds_ratio = deck_bounds_ratio
	collision_profile.min_ramming_speed = min_ramming_speed
	collision_profile.broad_phase_padding = broad_phase_padding

func get_collision_half_extents() -> Vector2:
	return Vector2(
		base_collision_radius * width_multiplier,
		base_collision_radius * length_multiplier
	)

func get_directional_collision_radius(world_dir: Vector3) -> float:
	var dir = world_dir
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		var half = get_collision_half_extents()
		return maxf(half.x, half.y)
	dir = dir.normalized()
	
	var fwd = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() <= 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	
	var lateral = base_collision_radius * width_multiplier
	var longitudinal = base_collision_radius * length_multiplier
	return lateral + (longitudinal - lateral) * absf(fwd.dot(dir))

func get_collision_distance_to(other: Node3D) -> float:
	if not is_instance_valid(other):
		return 0.0
		
	var diff = other.global_position - global_position
	diff.y = 0.0
	var dir = diff.normalized() if diff.length_squared() > 0.0001 else Vector3.FORWARD
	
	var my_radius = get_directional_collision_radius(dir)
	var other_radius = 0.0
	if other.has_method("get_directional_collision_radius"):
		other_radius = float(other.call("get_directional_collision_radius", -dir))
	else:
		var other_base = other.get("base_collision_radius") if "base_collision_radius" in other else 4.5
		var other_w = other.get("width_multiplier") if "width_multiplier" in other else 1.0
		var other_l = other.get("length_multiplier") if "length_multiplier" in other else 1.0
		var other_fwd = -other.global_transform.basis.z
		other_fwd.y = 0.0
		if other_fwd.length_squared() > 0.0001:
			other_fwd = other_fwd.normalized()
		else:
			other_fwd = -dir
		var other_lateral = other_base * other_w
		var other_longitudinal = other_base * other_l
		other_radius = other_lateral + (other_longitudinal - other_lateral) * absf(other_fwd.dot(-dir))
	
	return my_radius + other_radius

func get_deck_half_extents() -> Vector2:
	var hull_ext = _hull_half_extents
	if hull_ext.x <= 0.01 or hull_ext.y <= 0.01:
		hull_ext = get_collision_half_extents()
	var ratio = clampf(deck_bounds_ratio, 0.6, 1.0)
	return Vector2(
		maxf(0.4, hull_ext.x * ratio),
		maxf(0.8, hull_ext.y * ratio)
	)

func _refresh_collision_bounds_from_hull() -> void:
	var hull_ext = _compute_hull_half_extents()
	if hull_ext.x <= 0.01 or hull_ext.y <= 0.01:
		hull_ext = get_collision_half_extents()
		
	_hull_half_extents = hull_ext
	
	if not auto_fit_collision_to_hull:
		_sync_profile_from_runtime()
		return
		
	var padded = Vector2(
		hull_ext.x + collision_padding,
		hull_ext.y + collision_padding
	)
	var base = maxf(padded.x, padded.y)
	if base <= 0.01:
		return
		
	base_collision_radius = base
	width_multiplier = clampf(padded.x / base, 0.1, 3.0)
	length_multiplier = clampf(padded.y / base, 0.1, 3.0)
	_sync_profile_from_runtime()

func _compute_hull_half_extents() -> Vector2:
	if not is_inside_tree():
		return Vector2.ZERO
		
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(self , meshes)
	if meshes.is_empty():
		return Vector2.ZERO
		
	var preferred: Array[MeshInstance3D] = []
	var fallback: Array[MeshInstance3D] = []
	for mesh in meshes:
		if not is_instance_valid(mesh) or mesh.mesh == null:
			continue
		var lname = mesh.name.to_lower()
		if _is_excluded_bounds_mesh_name(lname):
			continue
		fallback.append(mesh)
		if lname.contains("hull") or lname.contains("shell") or lname.contains("castle"):
			preferred.append(mesh)
			
	var targets = preferred if not preferred.is_empty() else fallback
	if targets.is_empty():
		return Vector2.ZERO
		
	var half_width = 0.0
	var half_length = 0.0
	for mesh in targets:
		var aabb = mesh.get_aabb()
		for corner in _aabb_corners(aabb):
			var local_pt = to_local(mesh.to_global(corner))
			half_width = maxf(half_width, absf(local_pt.x))
			half_length = maxf(half_length, absf(local_pt.z))
			
	if half_width <= 0.01 or half_length <= 0.01:
		return Vector2.ZERO
	return Vector2(half_width, half_length)

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		if child.get_child_count() > 0:
			_collect_mesh_instances(child, out)

func _is_excluded_bounds_mesh_name(name_lc: String) -> bool:
	return name_lc.contains("mast") \
		or name_lc.contains("cannon") \
		or name_lc.contains("rudder") \
		or name_lc.contains("oar") \
		or name_lc.contains("blade") \
		or name_lc.contains("shaft") \
		or name_lc.contains("wake") \
		or name_lc.contains("rope")

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p = aabb.position
	var s = aabb.size
	return [
		Vector3(p.x, p.y, p.z),
		Vector3(p.x + s.x, p.y, p.z),
		Vector3(p.x, p.y + s.y, p.z),
		Vector3(p.x, p.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z),
		Vector3(p.x + s.x, p.y, p.z + s.z),
		Vector3(p.x, p.y + s.y, p.z + s.z),
		Vector3(p.x + s.x, p.y + s.y, p.z + s.z)
	]


## JSON 데이터에서 함선 스탯 로드
func load_ship_stats(type_name: String) -> Dictionary:
	# 에디터에서는 파일 접근 빈도를 줄이기 위해 가드 (필요시 호출되도록 함)
	var path = "res://data/ship_stats.json"
	if not FileAccess.file_exists(path):
		print("[BaseShip] Error: ship_stats.json not found!")
		return {}
		
	var file = FileAccess.open(path, FileAccess.READ)
	var json_text = file.get_as_text()
	var data = JSON.parse_string(json_text)
	
	if data == null or not data.has(type_name):
		print("[BaseShip] Warning: Stats for type '%s' not found in JSON." % type_name)
		return {}
		
	var stats = data[type_name]
	
	# 필드가 존재할 경우 인스턴스 변수에 적용
	if stats.has("hull_hp"):
		max_hull_hp = stats["hull_hp"]
		hull_hp = max_hull_hp
	if stats.has("move_speed"): max_speed = stats["move_speed"]
	if stats.has("deck_height"): deck_height = stats["deck_height"]
	if stats.has("hull_defense"): hull_defense = stats["hull_defense"]
	
	return stats

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	
	_apply_bobbing_effect()

func _update_children_team() -> void:
	var team_val = get("team")
	if team_val == null: team_val = "enemy" # 기본값
	
	for child in get_children():
		_recursive_set_team(child, team_val)

func _recursive_set_team(node: Node, new_team: String) -> void:
	if node.has_method("set_team"):
		node.set_team(new_team)
	elif "team" in node:
		node.set("team", new_team)
		
	for child in node.get_children():
		_recursive_set_team(child, new_team)

func _cache_hull_references(node: Node) -> void:
	# 루트 노드(self)에서 호출될 때 캐시 초기화
	if node == self:
		masts.clear()
		rudder_visual = null
		oar_pivot_left = null
		oar_pivot_right = null

	# 재귀적으로 내려가며 하드웨어 바인딩
	for child in node.get_children():
		if child.name.begins_with("Mast") and child.has_method("set_sail_angle"):
			if not masts.has(child): masts.append(child)
		elif child.name == "RudderVisual":
			rudder_visual = child
		elif child.name == "OarBaseLeft" and child.has_node("OarPivot"):
			oar_pivot_left = child.get_node("OarPivot")
		elif child.name == "OarBaseRight" and child.has_node("OarPivot"):
			oar_pivot_right = child.get_node("OarPivot")
			
		# 자식 노드 재귀 탐색
		if child.get_child_count() > 0:
			_cache_hull_references(child)

func _cache_common_references() -> void:
	_cached_level_manager = get_tree().root.find_child("LevelManager", true, false)
	if not _cached_level_manager:
		var lms = get_tree().get_nodes_in_group("level_manager")
		if lms.size() > 0: _cached_level_manager = lms[0]
		
	if _cached_level_manager and "hud" in _cached_level_manager:
		_cached_hud = _cached_level_manager.hud
	
	_cached_audio_manager = get_node_or_null("/root/AudioManager")

## 둥실둥실 시각 효과
func _apply_bobbing_effect() -> void:
	if Engine.is_editor_hint(): return # 에디터에서는 둥실거림 방지
	
	var time = Time.get_ticks_msec() * 0.001
	var dt = get_physics_process_delta_time()
	_wave_sample_timer = maxf(0.0, _wave_sample_timer - dt)
	
	if not is_instance_valid(_cached_ocean):
		# 에디터에서는 메인 루프나 씬 트리 접근 시 주의 필요
		var tree = get_tree()
		if not tree: return
		var ocean = tree.root.find_child("Ocean", true, false)
		if ocean:
			_cached_ocean = ocean
				
	var wave_h = 0.0
	if is_instance_valid(_cached_ocean) and _cached_ocean.has_method("get_wave_height"):
		# 파도 높이는 짧은 간격으로 샘플링해 CPU 부하를 낮춘다.
		if _wave_sample_timer <= 0.0:
			_cached_wave_height = _cached_ocean.get_wave_height(global_position)
			_wave_sample_timer = wave_sample_interval
		wave_h = _cached_wave_height
	else:
		_cached_wave_height = 0.0
		
	# 기존 단순 둥실거림은 진폭을 살짝만 남겨 파도 위의 미세한 진동으로 사용
	var bob_offset = sin(time * bobbing_speed) * bobbing_amplitude * 0.2
	
	# 무거운 배의 관성(Inertia)을 모방하기 위해 부드럽게 보간(Lerp)합니다.
	var target_y = base_y + wave_h + bob_offset
	position.y = lerp(position.y, target_y, 3.0 * dt)
	
	var turn_factor = rudder_angle / 45.0
	var speed_ratio = clamp(current_speed / max_speed, 0.0, 1.0)
	var target_centrifugal = deg_to_rad(-turn_factor * speed_ratio * 12.0)
	
	_centrifugal_tilt = lerp(_centrifugal_tilt, target_centrifugal, 2.5 * dt)
	
	rotation.z = (sin(time * bobbing_speed * 0.8) * rocking_amplitude) + tilt_offset + _centrifugal_tilt

## 돛 시각화 업데이트
func _update_sail_visual() -> void:
	for mast in masts:
		if is_instance_valid(mast) and mast.has_method("set_sail_angle"):
			mast.set_sail_angle(sail_angle)

## 러더 시각화 업데이트
func _update_rudder_visual() -> void:
	if rudder_visual:
		rudder_visual.rotation.y = deg_to_rad(rudder_angle)

## 화재 효과 업데이트
func _update_fire_effect() -> void:
	if (is_burning or is_derelict) and not is_sinking and not is_dying:
		if not is_instance_valid(_fire_instance):
			_fire_instance = fire_effect_scene.instantiate() as Node3D
			add_child(_fire_instance)
			_fire_instance.position = fire_effect_offset
			_set_fire_emitting(true)
		else:
			_set_fire_emitting(true)
	else:
		if is_instance_valid(_fire_instance):
			_set_fire_emitting(false)

func _set_fire_emitting(active: bool) -> void:
	if not is_instance_valid(_fire_instance): return
	var flame = _fire_instance.get_node_or_null("FlameParticles") as GPUParticles3D
	var smoke = _fire_instance.get_node_or_null("SmokeParticles") as GPUParticles3D
	if flame: flame.emitting = active
	if smoke: smoke.emitting = active

## 함선 충각(Ramming) 시 갑판 위 병사들에게 광역 데미지 및 넉백 부여
func apply_ramming_aoe(damage: float, impact_pos: Vector3) -> void:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and child.get("current_state") != 4: # 4 = DEAD
			# 병사들에게 충격파 데미지 전달
			child.take_damage(damage, impact_pos)
			
			# 물리적 비틀거림/스턴 연출을 위해 일시적으로 공격 타이머 초기화 (딜레이 보장)
			if "attack_timer" in child:
				child.attack_timer = max(child.attack_timer, 1.5)
			
			# 약간 띄우는 넉백 효과 추가 (중력이 없으므로 XZ축으로만 흔들림 유도)
			if "velocity" in child:
				# XZ축 랜덤 넉발만 적용
				var push = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
				child.velocity += push * 2.0
				
	print("[%s] 함선 충돌로 인해 갑판 위 병사들이 %d의 충격 피해를 입었습니다." % [name, int(damage)])

## 현재 생존 중인 선원(병사) 수 반환
func get_alive_crew_count() -> int:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return 0
	
	var count = 0
	for child in soldiers_node.get_children():
		# current_state != 4 (DEAD) 인 병사만 카운트
		if child.get("current_state") != 4:
			count += 1
	return count

## 병사가 사망할 때마다 호출되어, 배의 폐선 여부를 이벤트 방식으로 검사
func check_derelict_status() -> void:
	if is_derelict or is_dying or is_sinking: return
	
	# 내 배가 home_ship인 생존 병사가 있는지 확인
	var all_crew_dead = true
	var soldiers_node = get_node_or_null("Soldiers")
	
	# 자신이 소유한 병사(갑판 위 병사) 중 생존자 확인
	if soldiers_node:
		for child in soldiers_node.get_children():
			if child.get("current_state") != 4: # NOT DEAD
				all_crew_dead = false
				break
				
	# 만약 밧줄 등을 타고 다른 배로 넘어간 내 병사(home_ship == self)도 고려해야 한다면, 전역 검사 필요
	if all_crew_dead:
		var all_soldiers = get_tree().get_nodes_in_group("soldiers")
		for s in all_soldiers:
			# 다른 배에 넘어가 있더라도 여전히 살아서 싸우고 있는 내 선원이 있다면 폐선 아님
			if s.get("home_ship") == self and s.get("current_state") != 4:
				all_crew_dead = false
				break
				
	if all_crew_dead:
		if has_method("_become_derelict"):
			call("_become_derelict")

## 도선 시 상대방을 끌어당기는 힘(장력) 계산
func _calculate_boarding_pull() -> Vector3:
	var target_node = null
	if is_boarding and is_instance_valid(boarding_target):
		target_node = boarding_target
	elif is_instance_valid(boarding_attacker):
		target_node = boarding_attacker
		
	if not target_node:
		return Vector3.ZERO
		
	var target_pos = target_node.global_position
	var diff = target_pos - global_position
	var dist = diff.length()
	var dir = diff / max(dist, 0.001)
	
	# 1. 스프링 힘 (F = k * x) — 가속도(m/s²) 단위
	var rest_length = 8.5 # 충격 완화를 위해 거리 상향 (6.2 -> 8.5)
	var spring_k = 4.0
	var stretch = dist - rest_length
	
	# 거리가 rest_length보다 작으면(겹치려 하면) 밀어내는 반발력(Repulsion) 발생
	var propulsion_force = Vector3.ZERO
	if stretch < 0:
		# 작을수록 더 강하게 밀어냄 (제곱 비례)
		var repulsion_k = 8.0
		propulsion_force = - dir * (abs(stretch) * repulsion_k)
		stretch = 0 # 인동력은 발생시키지 않음
	
	# 거리가 도선 한계치(9.0)에 가까워지면 힘을 점진적으로 증가
	var tension_multiplier = 1.0
	if dist > 8.5:
		tension_multiplier = 1.0 + (dist - 8.5) * 2.0
		
	var spring_force = dir * (stretch * spring_k * tension_multiplier)
	
	# 2. 일방향 밧줄 댐핑 (One-way Damping)
	var final_damping_force = Vector3.ZERO
	var target_vel = Vector3.ZERO
	var my_vel = Vector3.ZERO
	
	if "current_speed" in target_node:
		var target_fwd = - target_node.global_transform.basis.z
		target_vel = target_fwd * target_node.get("current_speed")
	
	var my_fwd = - global_transform.basis.z
	my_vel = my_fwd * current_speed
	
	var rel_vel = target_vel - my_vel
	var rel_vel_on_rope = rel_vel.dot(dir)
	
	# 멀어질 때만 저항 (가속도 단위)
	if rel_vel_on_rope > 0:
		var damping_c = 3.0
		final_damping_force = dir * (rel_vel_on_rope * damping_c)
	
	# 3. 최종 힘 계산 및 제한 (가속도 상한)
	var final_pull = spring_force + propulsion_force + final_damping_force
	var max_pull_accel = 18.0 # 최대 가속도 상향 (15.0 -> 18.0)
	if final_pull.length() > max_pull_accel:
		final_pull = final_pull.normalized() * max_pull_accel
		
	return final_pull

## 밧줄 연결 전/후로 배끼리 겹치는(통과하는) 것을 막아주는 강한 물리 반발력
func _calculate_collision_repulsion() -> Vector3:
	var force = Vector3.ZERO
	var neighbors = get_tree().get_nodes_in_group("ships")
	
	for other in neighbors:
		if other == self or not is_instance_valid(other) or other.get("is_dying") or other.get("is_sinking"):
			continue
			
		var diff = other.global_position - global_position
		diff.y = 0.0
		var dist_sq = diff.length_squared()
		var my_half = get_collision_half_extents()
		var other_half = Vector2(
			other.base_collision_radius * other.width_multiplier,
			other.base_collision_radius * other.length_multiplier
		)
		var broad_phase_dist = maxf(my_half.x, my_half.y) + maxf(other_half.x, other_half.y) + broad_phase_padding
		
		# 빠른 거절(Broad-phase) 검사 - 선체 크기에 맞는 동적 반경 사용
		if dist_sq > broad_phase_dist * broad_phase_dist:
			continue
			
		var dist = sqrt(dist_sq)
		var dir = diff / max(dist, 0.001)
		var my_fwd = - global_transform.basis.z
		my_fwd.y = 0.0
		if my_fwd.length_squared() > 0.0001:
			my_fwd = my_fwd.normalized()
		else:
			my_fwd = dir
		var other_fwd = - other.global_transform.basis.z
		other_fwd.y = 0.0
		if other_fwd.length_squared() > 0.0001:
			other_fwd = other_fwd.normalized()
		else:
			other_fwd = -dir
		
		# 타원형(Capsule/Ellipse) 콜리전 근사
		# 방향 벡터(dir)와 내적(dot)을 통해 정면/후면(가로축) 이면 ~4.5m, 측면이면 ~2.0m 의 반경을 도출
		var my_radius = get_directional_collision_radius(dir)
		var other_radius = 0.0
		if other.has_method("get_directional_collision_radius"):
			other_radius = float(other.call("get_directional_collision_radius", -dir))
		else:
			other_radius = other.base_collision_radius * other.width_multiplier + (other.base_collision_radius * other.length_multiplier - other.base_collision_radius * other.width_multiplier) * absf(other_fwd.dot(-dir))
		var coll_dist = my_radius + other_radius
		var is_engagement_pair = _is_engagement_pair(other)
		# 교전/도선 대상과는 더 깊게 붙은 뒤 반발이 시작되도록 허용
		if is_engagement_pair:
			coll_dist *= 0.90
		
		if dist < coll_dist:
			var compression = coll_dist - dist
			var target_speed = 0.0
			if "current_speed" in other:
				target_speed = other.current_speed
			var pre_collision_speed = current_speed
			var pre_my_vel = my_fwd * pre_collision_speed
			var pre_other_vel = other_fwd * target_speed
			# 중심점 기준 충돌 방향(나 -> 상대방)으로의 접근 속도 투영
			var approach_speed = (pre_my_vel - pre_other_vel).dot(dir)
			
			# 교전 대상 쌍은 반발력을 낮춰 충돌 직전 멈춤 느낌을 줄임
			var repulsion_strength = 24.0 if is_engagement_pair else 40.0
			var head_on_pair = my_fwd.dot(dir) > 0.72 and other_fwd.dot(-dir) > 0.72
			var high_speed_head_on = head_on_pair and approach_speed >= min_ramming_speed * 0.85
			# 정면 충돌은 "튕김"보다 "충돌 후 정지"가 느껴지도록 반발력을 더 낮춤
			if is_engagement_pair and head_on_pair:
				repulsion_strength *= 0.18
			elif high_speed_head_on:
				repulsion_strength *= 0.12
			var penetration_ratio = compression / maxf(coll_dist, 0.001)
			# 깊은 겹침에서는 강한 복원력을 걸어 통과를 방지
			if penetration_ratio > 0.22:
				if high_speed_head_on:
					repulsion_strength = maxf(repulsion_strength, 26.0)
				else:
					repulsion_strength = maxf(repulsion_strength, 72.0)
			var repulsion_force = -dir * (compression * repulsion_strength)
			# 정면 충돌은 후방(역방향) 튕김 성분을 제거해 "충돌 후 멈춤" 감각을 강화
			if (is_engagement_pair and head_on_pair) or high_speed_head_on:
				var backward_component = minf(0.0, repulsion_force.dot(my_fwd))
				if backward_component < 0.0:
					repulsion_force -= my_fwd * backward_component
			force += repulsion_force
			
			# 충돌로 인해 배가 미끄러지지 않고(Sliding 안됨) 아예 멈춰버리는 현상 완화
			# 상대방이 내 바로 '정면'(dot > 0.8)에 있을 때만 감속하고, 빗겨맞거나 측면이면 그대로 미끄러지며 나아감
			if current_speed > 0.5:
				if my_fwd.dot(dir) > 0.8:
					if high_speed_head_on:
						current_speed = lerp(current_speed, 0.0, 0.72)
					elif is_engagement_pair:
						var stop_blend = 0.48 if head_on_pair else 0.24
						current_speed = lerp(current_speed, 0.0, stop_blend)
					else:
						current_speed = lerp(current_speed, 0.0, 0.1)
					
			# ========================
			# [신규] 충각(Ramming) 데미지 발생 트리거
			# ========================
			# 접근 속도가 일정 수치 이상일 때만 강한 충돌로 인정 (가까이서 비벼질 때는 데미지 무시)
			# 접근 속도가 일정 수치 이상일 때만 강한 충돌로 인정
			if approach_speed >= min_ramming_speed:
				apply_ramming_damage(other, approach_speed)
				# [FIX] 여기서 other.apply_ramming_damage를 호출하지 않습니다.
				# 모든 배가 각자의 _calculate_collision_repulsion에서 자신에게 가해지는 데미지를 계산하므로,
				# 여기서 상대를 호출하면 중복 데미지가 발생합니다.
					
	return force

func _is_engagement_pair(other: Node3D) -> bool:
	if not is_instance_valid(other):
		return false
	var my_target = get("target")
	var my_boarding_target = get("boarding_target")
	var other_target = other.get("target")
	var other_boarding_target = other.get("boarding_target")
	return my_target == other \
		or my_boarding_target == other \
		or other_target == self \
		or other_boarding_target == self

## 나포 가능한 함대 정원(최대 3척)이 남았는지 확인
func can_capture_more_ships() -> bool:
	var minions = get_tree().get_nodes_in_group("captured_minion")
	return minions.size() < 3

## 밧줄에 데미지 적용
func take_rope_damage(amount: float) -> void:
	boarding_rope_hp -= amount
	# 시각적 깜빡임 (빨간색)
	for mesh in rope_instances:
		var mat = mesh.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.2, 0.2) # 적색 깜빡임
			get_tree().create_timer(0.1).timeout.connect(func():
				if is_instance_valid(mat): mat.albedo_color = Color(0.4, 0.3, 0.2)
			)
			
	if boarding_rope_hp <= 0:
		print("[Boarding] 밧줄이 병사에 의해 절단되었습니다.")
		_cancel_boarding()

## 충격(충각) 타격 로직 - 타원형 각도 판정 포함
func apply_ramming_damage(other: Node3D, impact_speed: float) -> void:
	if is_sinking or is_dying: return
	
	# 중복 피격 방지 쿨다운 (1.0초 이내 재충돌 무시) 상향 (0.5 -> 1.0)
	var current_time = Time.get_ticks_msec() / 1000.0
	if _recent_ram_targets.has(other):
		if current_time - _recent_ram_targets[other] < 1.0:
			return
	_recent_ram_targets[other] = current_time
	
	# 내 전방 벡터와 상대를 향하는 벡터 계산
	var my_fwd = Vector3(-sin(rotation.y), 0, -cos(rotation.y)).normalized()
	var dir_to_other = (other.global_position - global_position).normalized()
	
	# 내적(Dot Product): 1.0 이면 정면, 0.0 이면 측면
	var dot = abs(my_fwd.dot(dir_to_other))
	
	# 상대방 입장에서의 내적 (상대방도 나를 정면으로 바라보는지, 측면을 내어주었는지)
	var _other_dot = 1.0 # 기본값 (보수적)
	if other.has_method("get_rotation"):
		var other_fwd = Vector3(-sin(other.rotation.y), 0, -cos(other.rotation.y)).normalized()
		_other_dot = abs(other_fwd.dot(-dir_to_other))
	
	# 측면 가중치를 완화해 과도한 충돌 피해를 줄인다.
	# 내적(Dot)이 1(정면)에 가까울 수록 0.30배, 0(측면)에 가까울 수록 1.25배
	var angle_mult = remap(dot, 0.0, 1.0, 1.25, 0.30)
	
	# 속도 선형 비례 유지하되 계수를 낮춰 충각 피해를 전반적으로 완화한다.
	var final_ram_damage = impact_speed * 2.8 * angle_mult
	
	# 시각 및 청각 피드백 (임팩트)
	if impact_speed >= min_ramming_speed:
		var impact_pos = (global_position + other.global_position) * 0.5
		impact_pos.y = 0.5
		
		# 강한 임팩트일 때만 사운드 및 흔들림 적용
		if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
			_cached_audio_manager.play_sfx("impact_wood", global_position, randf_range(0.6, 0.8), 5.0)
			
		var cam = get_tree().root.get_camera_3d()
		if cam and cam.has_method("shake"):
			# 세게 부딪힐 수록 화면이 많이 흔들림
			cam.shake(clamp(impact_speed * 0.05, 0.2, 0.6), 0.3)
			
		# 충돌 대상들 범위에 충격파 (배 위 병사 데미지)
		apply_ramming_aoe(clamp(impact_speed * 1.5, 5.0, 20.0), impact_pos)
	
	print("[Ramming] 충각 발생! (속도: %.1f) - 내 각도계수: %.2f -> 입은 피해: %.1f" % [impact_speed, angle_mult, final_ram_damage])
	take_damage(final_ram_damage, (global_position + other.global_position) * 0.5)


## 데미지 처리 (공통)
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if is_sinking or is_dying:
		return
		
	var final_damage = maxf(amount - hull_defense, 1.0)
	hull_hp -= final_damage
	
	# 플레이어 무기 피해 집계: 적 함선에만 기록
	if not damage_source.is_empty() and get("team") == "enemy":
		if is_instance_valid(_cached_level_manager) and _cached_level_manager.has_method("add_player_weapon_damage"):
			_cached_level_manager.add_player_weapon_damage(damage_source, final_damage)
	
	# 피격 이펙트 (파편) - 스로틀링 적용
	var current_time = Time.get_ticks_msec() / 1000.0
	if wood_splinter_scene and (current_time - _last_splinter_time > 0.2):
		_last_splinter_time = current_time
		var splinter = wood_splinter_scene.instantiate()
		get_tree().root.add_child(splinter)
		if hit_position != Vector3.ZERO:
			splinter.global_position = hit_position + Vector3(0, 0.5, 0)
		else:
			splinter.global_position = global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1))
		splinter.rotation.y = randf() * TAU
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(final_damage)
			
	_flash_damage(final_damage)
	
	if hull_hp <= 0:
		die()

func _flash_damage(amount: float = 10.0) -> void:
	var shake_mult = clamp(amount / 10.0, 0.15, 2.0)
	var shake_tween = create_tween()
	shake_tween.tween_property(self , "rotation:z", rocking_amplitude * 3.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", -rocking_amplitude * 2.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", 0.0, 0.2)

## 화염 데미지
func take_fire_damage(_dps: float, duration: float) -> void:
	if is_burning:
		burn_timer = max(burn_timer, duration)
		return
		
	fire_build_up += duration * 6.0
	if fire_build_up >= fire_threshold:
		is_burning = true
		fire_build_up = fire_threshold
		burn_timer = duration
		print("[Status] 배에 불이 붙었습니다!")

func _update_burning_status(delta: float) -> void:
	if is_burning:
		hull_hp = move_toward(hull_hp, 0, 2.0 * delta)
		if hull_hp <= 0:
			die()
			
		burn_timer -= delta
		if burn_timer <= 0:
			is_burning = false
			fire_build_up = 0.0
	else:
		if fire_build_up > 0:
			fire_build_up = move_toward(fire_build_up, 0, 15.0 * delta)

func _update_hull_regeneration(delta: float) -> void:
	if is_sinking or is_dying or hull_regen_rate <= 0: return
	
	if hull_hp < max_hull_hp:
		hull_hp = move_toward(hull_hp, max_hull_hp, hull_regen_rate * delta)

func get_hull_ratio() -> float:
	if max_hull_hp <= 0.0: return 1.0
	return hull_hp / max_hull_hp

## 가상 함수 분리용 (자식 클래스에서 오버라이드)
func die() -> void:
	pass

# ==========================================
# === 공통 도선(Boarding) 밧줄 처리 로직 ===
# ==========================================

func _spawn_ropes(count_override: int = -1) -> void:
	_clear_ropes()
	var count = count_override if count_override > 0 else randi_range(2, 3)
	count = max(1, count)
	for i in range(count):
		var mesh_instance = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.04
		cylinder.bottom_radius = 0.04
		cylinder.height = 1.0 # 기본 길이는 1로 설정 (scale로 조절)
		mesh_instance.mesh = cylinder
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.3, 0.2)
		mat.roughness = 0.9
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.material_override = mat
		
		add_child(mesh_instance)
		
		var offset_z = 0.0
		if count > 1:
			offset_z = lerp(-2.0, 2.0, float(i) / float(count - 1))
		var offset = Vector3(1.0, 0.8, offset_z)
		if is_instance_valid(boarding_target):
			var to_target = (boarding_target.global_position - global_position).normalized()
			var local_to_target = global_transform.basis.inverse() * to_target
			if local_to_target.x < 0: offset.x = -1.0
			
		mesh_instance.position = offset
		mesh_instance.set_meta("anchor_offset", offset)
		rope_instances.append(mesh_instance)

func _update_ropes() -> void:
	if not is_instance_valid(boarding_target):
		_clear_ropes()
		return
		
	var target_center = boarding_target.global_position + Vector3(0, 0.5, 0)
	
	for rope in rope_instances:
		if not is_instance_valid(rope): continue
		
		var offset = rope.get_meta("anchor_offset")
		var start_pos = global_transform * offset
		var dist = start_pos.distance_to(target_center)
		
		var mid_pos = start_pos + (target_center - start_pos) * 0.5
		rope.global_transform = Transform3D().looking_at(target_center - mid_pos, Vector3.UP)
		rope.global_position = mid_pos
		
		rope.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
		rope.scale = Vector3(1.0, dist, 1.0)

func _clear_ropes() -> void:
	for rope in rope_instances:
		if is_instance_valid(rope):
			rope.queue_free()
	rope_instances.clear()

func _is_boarding_contact_stable() -> bool:
	if not is_instance_valid(boarding_target):
		return false
		
	var diff = boarding_target.global_position - global_position
	diff.y = 0.0
	if diff.length_squared() < 0.01:
		return false
	var dir = diff.normalized()
	
	var my_fwd = -global_transform.basis.z
	my_fwd.y = 0.0
	if my_fwd.length_squared() > 0.001:
		my_fwd = my_fwd.normalized()
	else:
		my_fwd = dir
		
	var target_fwd = -boarding_target.global_transform.basis.z
	target_fwd.y = 0.0
	if target_fwd.length_squared() > 0.001:
		target_fwd = target_fwd.normalized()
	else:
		target_fwd = -dir
		
	var my_head_on = absf(my_fwd.dot(dir))
	var target_head_on = absf(target_fwd.dot(-dir))
	
	var target_speed = boarding_target.get("current_speed") if "current_speed" in boarding_target else 0.0
	var my_vel = my_fwd * current_speed
	var target_vel = target_fwd * target_speed
	var closing_speed = absf((my_vel - target_vel).dot(dir))
	
	# 완전 정면 대치여도 속도가 충분히 낮으면 밧줄을 허용한다.
	var both_head_on = my_head_on > boarding_side_alignment_max_dot and target_head_on > boarding_side_alignment_max_dot
	if both_head_on and closing_speed > maxf(1.2, boarding_max_relative_speed * 0.5):
		return false
		
	return closing_speed <= boarding_max_relative_speed * 1.35

func _process_boarding_common(delta: float) -> void:
	if not is_instance_valid(boarding_target):
		_cancel_boarding()
		return
		
	# 밧줄 HP가 바닥나면 해제
	if boarding_rope_hp <= 0:
		_cancel_boarding()
		return
		
	var target_pos = boarding_target.global_position
	var dist = global_position.distance_to(target_pos)
	
	if dist > boarding_break_distance:
		print("[Boarding] 밧줄이 끊어졌습니다. 도선 중단.")
		_cancel_boarding()
		return
	
	# 유효 거리 밖에서는 접촉 안정화 상태를 되감아, 재접근 연출을 유도
	if dist > max_boarding_distance:
		boarding_contact_timer = maxf(0.0, boarding_contact_timer - delta * 2.0)
		boarding_hook_timer = 0.0
		boarding_secondary_rope_timer = 0.0
		if _initial_rope_deployed and dist > (max_boarding_distance + 0.8):
			_clear_ropes()
			_initial_rope_deployed = false
			_full_rope_deployed = false
		return
		
	boarding_contact_timer += delta
	if boarding_contact_timer < boarding_contact_grace_duration:
		return
		
	var stable_contact = _is_boarding_contact_stable()
	if not stable_contact:
		# 장시간 근접 대치 시 안정성 판정을 강제로 통과시켜 무한 대기를 방지
		var force_hook_after = boarding_contact_grace_duration + 1.2
		if boarding_contact_timer < force_hook_after:
			boarding_contact_timer = maxf(boarding_contact_grace_duration * 0.6, boarding_contact_timer - delta * 1.4)
			return
		
	boarding_hook_timer += delta
	if not _initial_rope_deployed:
		if boarding_hook_timer >= boarding_hook_throw_delay:
			_spawn_ropes(boarding_initial_rope_count)
			_initial_rope_deployed = true
			_full_rope_deployed = boarding_initial_rope_count >= 2
			boarding_secondary_rope_timer = 0.0
			print("[Boarding] 갈고리 투척 성공, 밧줄 연결 시작.")
		return
		
	if not _full_rope_deployed:
		boarding_secondary_rope_timer += delta
		if boarding_secondary_rope_timer >= boarding_secondary_rope_delay:
			_spawn_ropes()
			_full_rope_deployed = true
			print("[Boarding] 추가 밧줄이 연결되었습니다.")
		
	if boarding_prep_timer < boarding_prep_duration:
		boarding_prep_timer += delta
	else:
		boarding_timer += delta
		if boarding_timer >= boarding_interval:
			boarding_timer = 0.0
			_transfer_one_soldier()
		
	_update_ropes()

func _cancel_boarding() -> void:
	if is_instance_valid(boarding_target) and boarding_target.get("boarding_attacker") == self:
		boarding_target.set("boarding_attacker", null)
	_clear_ropes()
	is_boarding = false
	boarding_timer = 0.0
	boarding_prep_timer = 0.0
	boarding_contact_timer = 0.0
	boarding_hook_timer = 0.0
	boarding_secondary_rope_timer = 0.0
	_initial_rope_deployed = false
	_full_rope_deployed = false
	boarding_rope_hp = max_boarding_rope_hp # HP 리셋

func _transfer_one_soldier() -> void:
	if not is_instance_valid(boarding_target): return
	
	var target_soldiers_node = boarding_target.get_node_or_null("Soldiers")
	if not target_soldiers_node: target_soldiers_node = boarding_target
	
	var team_prop = get("team") if "team" in self else "enemy"
	
	# 난간 근접전 우선: 상대 갑판에 수비병이 남아있으면 월선을 보류한다.
	var defenders_alive = 0
	if target_soldiers_node:
		for child in target_soldiers_node.get_children():
			if child.get("current_state") != 4 and child.get("team") != team_prop:
				defenders_alive += 1
	if defenders_alive > 0:
		return
	
	var s = null
	
	if has_node("Soldiers"):
		var soldiers = $Soldiers.get_children()
		
		# 1. 방어 판단: 내 배에 침입한 적군과 아군 비율 확인
		var enemy_count_on_deck = 0
		var ally_count_on_deck = 0
		for child in soldiers:
			if child.get("current_state") != 4: # NOT DEAD
				if child.get("team") != team_prop:
					enemy_count_on_deck += 1
				else:
					ally_count_on_deck += 1
					
		# 아군이 적군보다 많으면 방어 충분 → 도선 계속 진행
		# 아군이 적군 이하이면 방어 인원 부족 → 증원 우선 (return하지 않음)
		if enemy_count_on_deck > 0 and ally_count_on_deck > enemy_count_on_deck:
			return
			
		# 2. 아군 병사 선택
		for child in soldiers:
			if child.get("current_state") != 4 and child.get("team") == team_prop:
				s = child
				break
				
	if s:
		var start_global = s.global_position
		s.call_deferred("reparent", target_soldiers_node)
		
		# 점프 애니메이션 세팅
		var target_half_ext = Vector2(1.0, 1.5)
		if boarding_target.has_method("get_deck_half_extents"):
			var ext = boarding_target.call("get_deck_half_extents")
			if ext is Vector2 and ext.x > 0.01 and ext.y > 0.01:
				target_half_ext = ext
		var target_deck_h = boarding_target.get("deck_height") if "deck_height" in boarding_target else 0.5
		var jump_offset = Vector3(
			randf_range(-target_half_ext.x, target_half_ext.x),
			target_deck_h,
			randf_range(-target_half_ext.y, target_half_ext.y)
		)
		var end_global = boarding_target.global_transform * jump_offset
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(s, "global_position:x", end_global.x, 0.5).set_trans(Tween.TRANS_LINEAR)
		tween.tween_property(s, "global_position:z", end_global.z, 0.5).set_trans(Tween.TRANS_LINEAR)
		
		var mid_y = max(start_global.y, end_global.y) + 2.0
		var y_tween = create_tween()
		y_tween.tween_property(s, "global_position:y", mid_y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		y_tween.tween_property(s, "global_position:y", end_global.y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
		if s.has_method("set_team"):
			s.set_team(team_prop)
			
		s.set("owned_ship", boarding_target)
		
		# 폭발병 로직 (임시)
		if team_prop == "enemy" and boarding_target.get("team") == "player":
			s.set("boarder_explosion_timer", 8.0)
			
		if s.get("is_stationary"): s.set("is_stationary", false)
		
		print("[Action] 병사 1명 월선! (팀: %s, 대상: %s)" % [team_prop, boarding_target.name])
	else:
		if has_method("_become_derelict") and not is_in_group("player"):
			print("[Status] 모든 병사 도선 완료. 무인선 상태로 표류합니다.")
			call("_become_derelict")
		else:
			print("[Status] 도선할 병사가 더 이상 없습니다.")
			_cancel_boarding()
