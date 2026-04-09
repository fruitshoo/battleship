@tool
extends Node3D
class_name BaseShip
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")
const BaseShipCollisionHelper = preload("res://scripts/entities/ships/base_ship_collision_helper.gd")
const BaseShipBoardingHelper = preload("res://scripts/entities/ships/base_ship_boarding_helper.gd")
const BaseShipCrewHelper = preload("res://scripts/entities/ships/base_ship_crew_helper.gd")
const BaseShipRudderHelper = preload("res://scripts/entities/ships/base_ship_rudder_helper.gd")
const BaseShipStatusHelper = preload("res://scripts/entities/ships/base_ship_status_helper.gd")
const BaseShipVisualHelper = preload("res://scripts/entities/ships/base_ship_visual_helper.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const DEBUG_COMBAT_LOGS := false
const DEBUG_DAMAGE_LOGS := false

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
@export_range(0.75, 1.1) var auto_fit_scale: float = 1.0 ## 선체 자동 충돌 타원 전체 스케일
@export_range(0.0, 2.0) var collision_padding: float = 0.02 ## 충돌 판정 여유치(반폭/반길이에 추가)
@export_range(0.6, 1.0) var deck_bounds_ratio: float = 0.88 ## 병사 덱 이동 범위 축소 비율

# === 돛 관련 ===
@export var sail_angle: float = 0.0 # 돛 각도 (-90 ~ 90도)

# === 러더(키) 관련 ===
@export var rudder_angle: float = 0.0 # 러더 각도 (-45 ~ 45도)
@export_range(10.0, 200.0, 1.0) var rudder_max_health: float = 100.0
var rudder_health: float = 100.0
@export_range(0.1, 0.9, 0.05) var rudder_critical_threshold: float = 0.35
var _rudder_critical_announced: bool = false

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
var combat_crew_alloc: int = 0
var shiphandling_crew_alloc: int = 0
var gunnery_crew_alloc: int = 0
var combat_crew_ratio: float = 0.34
var shiphandling_crew_ratio: float = 0.33
var gunnery_crew_ratio: float = 0.33
var _crew_allocation_eval_left: float = 0.0
@export_range(0.1, 1.5, 0.05) var crew_allocation_eval_interval: float = 0.35

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
var deck_is_contested: bool = false
var deck_is_overrun: bool = false
var deck_friendly_crew_count: int = 0
var deck_hostile_boarder_count: int = 0
var boarding_capture_progress: float = 0.0
var _deck_overrun_announced: bool = false
@export_range(1.0, 12.0, 0.25) var boarding_capture_duration: float = 5.0
@export_range(0.0, 1.0, 0.01) var contested_hull_damage_multiplier: float = 0.68
@export_range(1.0, 100.0, 1.0) var boarding_capture_damage_tick: float = 25.0

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
@export_range(0.05, 1.0) var boarding_rope_throw_duration: float = 0.28
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
@export var water_splash_scene: PackedScene = preload("res://scenes/effects/water_burst.tscn")
@export var impact_puff_scene: PackedScene = preload("res://scenes/effects/impact_puff.tscn")
@export var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")
@export var loot_scene: PackedScene = preload("res://scenes/effects/floating_loot.tscn")
@export_range(0.0, 1.0, 0.01) var floating_loot_drop_chance: float = 0.65
@export var survivor_scene: PackedScene = preload("res://scenes/effects/survivor.tscn")
var _fire_instance: Node3D = null

@export var fire_effect_offset: Vector3 = Vector3(0, 1.5, 0.0)

# === 노드 참조 (이제 HullScene 내부를 스캔) ===
var masts: Array[Node] = []
var rudder_visual: Node3D = null
var wake_trail: Node3D = null
var deck_light: OmniLight3D = null
var _cached_environment_preset_manager: Node = null

@export_group("Mood Lighting")
@export var enable_deck_light: bool = true
@export var disable_deck_light_in_clear_day: bool = true
@export var deck_light_player_only: bool = false
@export var deck_light_energy: float = 1.25
@export var deck_light_range: float = 18.0
@export var deck_light_height: float = 1.8
@export var deck_light_color: Color = Color(1.0, 0.86, 0.68, 1.0)

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
	rudder_health = rudder_max_health
	
	# 돛대, 타륜 등의 레퍼런스 캐싱 (에디터/런타임 공통)
	_cache_hull_references(self )
	_refresh_collision_bounds_from_hull()
	
	if Engine.is_editor_hint():
		return

	# 런타임 전용 로직
	_cache_common_references()
	_refresh_deck_light()
	EntityRegistry.register_ship(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_ship(self)

func _ensure_collision_profile() -> void:
	# 기존 씬의 export 수치를 유지하면서 프로파일을 기본 소스로 승격한다.
	if collision_profile == null:
		collision_profile = ShipCollisionProfile.new()
		collision_profile.base_collision_radius = base_collision_radius
		collision_profile.length_multiplier = length_multiplier
		collision_profile.width_multiplier = width_multiplier
		collision_profile.auto_fit_collision_to_hull = auto_fit_collision_to_hull
		collision_profile.auto_fit_scale = auto_fit_scale
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
	auto_fit_scale = collision_profile.auto_fit_scale
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
	collision_profile.auto_fit_scale = auto_fit_scale
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
		var other_base = NodeContractHelper.get_base_collision_radius_value(other)
		var other_w = NodeContractHelper.get_collision_width_multiplier_value(other)
		var other_l = NodeContractHelper.get_collision_length_multiplier_value(other)
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
		(hull_ext.x + collision_padding) * auto_fit_scale,
		(hull_ext.y + collision_padding) * auto_fit_scale
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
	if stats.has("collision_fit_scale"): auto_fit_scale = float(stats["collision_fit_scale"])
	if stats.has("collision_padding"): collision_padding = float(stats["collision_padding"])
	if stats.has("collision_length_mult"): length_multiplier = float(stats["collision_length_mult"])
	if stats.has("collision_width_mult"): width_multiplier = float(stats["collision_width_mult"])
	
	return stats

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	
	_apply_bobbing_effect()

func set_team(new_team: String) -> void:
	var old_team = get_team_tag()
	var normalized_team = "player" if new_team == "player" else "enemy"
	if "team" in self:
		set("team", normalized_team)

	# 씬 기본 그룹(enemy) 잔존으로 인한 피아식별 꼬임을 막기 위해
	# 팀 변경 시 그룹을 항상 재동기화한다.
	if is_in_group("player"):
		remove_from_group("player")
	if is_in_group("enemy"):
		remove_from_group("enemy")
	add_to_group(normalized_team)

	# Area3D 루트 함선(예: enemy_ship)의 물리 레이어도 팀과 일치시킨다.
	if "collision_layer" in self:
		set("collision_layer", _get_team_collision_layer(normalized_team))
	if "collision_mask" in self:
		set("collision_mask", _get_team_collision_mask(normalized_team))
	if is_inside_tree() and has_method("_sync_contact_area_layers"):
		call_deferred("_sync_contact_area_layers", _get_team_collision_layer(normalized_team))
	EntityRegistry.update_ship_team(self, old_team, normalized_team)

	_update_children_team()

func get_team_tag() -> String:
	var team_value: Variant = get("team")
	if team_value == null:
		return "enemy"
	return str(team_value)

func is_combat_disabled() -> bool:
	return is_dying or is_sinking or is_derelict or hull_hp <= 0.0

func get_hull_hp_value() -> float:
	return hull_hp

func get_base_collision_radius_value() -> float:
	return base_collision_radius

func get_collision_width_multiplier_value() -> float:
	return width_multiplier

func get_collision_length_multiplier_value() -> float:
	return length_multiplier

func get_current_speed_value() -> float:
	return current_speed

func get_move_direction_value() -> Vector3:
	var move_dir: Vector3 = -global_transform.basis.z
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.0001:
		return move_dir.normalized()
	return Vector3.FORWARD

func get_target_ship() -> Node3D:
	if "target" in self:
		var target_value: Variant = get("target")
		return target_value if is_instance_valid(target_value) else null
	return null

func get_ship_type_value() -> String:
	var ship_type_value: Variant = get("ship_type") if "ship_type" in self else null
	if ship_type_value != null:
		return str(ship_type_value)
	return ""

func is_sinking_or_dying() -> bool:
	return is_sinking or is_dying

func is_derelict_ship() -> bool:
	return is_derelict

func is_boarding_ship() -> bool:
	return is_boarding

func get_boarding_target_ship() -> Node3D:
	return boarding_target if is_instance_valid(boarding_target) else null

func is_player_controlled_ship() -> bool:
	if not ("is_player_controlled" in self):
		return false
	return bool(get("is_player_controlled"))

func is_player_team() -> bool:
	return get_team_tag() == "player"

func is_enemy_team() -> bool:
	return get_team_tag() == "enemy"

func get_boarding_attacker_ship() -> Node3D:
	return boarding_attacker if is_instance_valid(boarding_attacker) else null

func set_boarding_attacker_ship(attacker: Node3D) -> void:
	if is_instance_valid(attacker):
		boarding_attacker = attacker
	else:
		boarding_attacker = null

func clear_boarding_attacker_ship() -> void:
	boarding_attacker = null

func _get_team_collision_layer(team_tag: String) -> int:
	return 2 if team_tag == "player" else 4

func _get_team_collision_mask(team_tag: String) -> int:
	return 21 if team_tag == "player" else 2

func _update_children_team() -> void:
	var team_val: String = get_team_tag()
	
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
		wake_trail = null
		oar_pivot_left = null
		oar_pivot_right = null

	# 재귀적으로 내려가며 하드웨어 바인딩
	for child in node.get_children():
		if child.name.begins_with("Mast") and child.has_method("set_sail_angle"):
			if not masts.has(child): masts.append(child)
		elif child.name == "RudderVisual":
			rudder_visual = child
		elif child.name == "WakeTrail" and child is Node3D:
			wake_trail = child as Node3D
		elif child.name == "OarBaseLeft" and child.has_node("OarPivot"):
			oar_pivot_left = child.get_node("OarPivot")
		elif child.name == "OarBaseRight" and child.has_node("OarPivot"):
			oar_pivot_right = child.get_node("OarPivot")
			
		# 자식 노드 재귀 탐색
		if child.get_child_count() > 0:
			_cache_hull_references(child)

func _cache_common_references() -> void:
	BaseShipVisualHelper.cache_common_references(self)

func _on_environment_preset_applied(_preset: int) -> void:
	BaseShipVisualHelper.on_environment_preset_applied(self, _preset)

func _is_clear_day_preset_active() -> bool:
	return BaseShipVisualHelper.is_clear_day_preset_active(self)

func _resolve_deck_light_parent() -> Node3D:
	return BaseShipVisualHelper.resolve_deck_light_parent(self)

func _refresh_deck_light() -> void:
	BaseShipVisualHelper.refresh_deck_light(self)

## 둥실둥실 시각 효과
func _apply_bobbing_effect() -> void:
	BaseShipVisualHelper.apply_bobbing_effect(self)

## 돛 시각화 업데이트
func _update_sail_visual() -> void:
	BaseShipVisualHelper.update_sail_visual(self)

## 러더 시각화 업데이트
func _update_rudder_visual() -> void:
	BaseShipVisualHelper.update_rudder_visual(self)

## 화재 효과 업데이트
func _update_fire_effect() -> void:
	BaseShipStatusHelper.update_fire_effect(self)

func _set_fire_emitting(active: bool) -> void:
	BaseShipStatusHelper.set_fire_emitting(self, active)

func _set_wake_state(active: bool, speed_ratio: float = 0.0, turn_ratio: float = 0.0, turbulence: float = 0.0) -> void:
	BaseShipVisualHelper.set_wake_state(self, active, speed_ratio, turn_ratio, turbulence)

## 함선 충각(Ramming) 시 갑판 위 병사들에게 광역 데미지 및 넉백 부여
func apply_ramming_aoe(damage: float, impact_pos: Vector3) -> void:
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and not (child.has_method("is_dead_soldier") and child.is_dead_soldier()):
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
		if not (child.has_method("is_dead_soldier") and child.is_dead_soldier()):
			count += 1
	return count


func set_preview_deck_state(is_contested: bool, is_overrun: bool = false) -> void:
	deck_is_contested = is_contested
	deck_is_overrun = is_overrun


func has_active_crew_role(role_name: String) -> bool:
	var normalized_role := role_name.strip_edges().to_lower()
	if normalized_role.is_empty():
		return false
	var soldiers_node := get_node_or_null("Soldiers")
	if not is_instance_valid(soldiers_node):
		return false
		for child in soldiers_node.get_children():
			if not is_instance_valid(child):
				continue
			if child.has_method("is_dead_soldier") and child.is_dead_soldier():
				continue
			if child.has_method("get_crew_role_value") and str(child.get_crew_role_value()).strip_edges().to_lower() == normalized_role:
				return true
	return false


func replace_preview_crew_role(from_role: String, to_role: String = "general") -> void:
	var normalized_from := from_role.strip_edges().to_lower()
	var normalized_to := to_role.strip_edges().to_lower()
	if normalized_from.is_empty() or normalized_to.is_empty() or normalized_from == normalized_to:
		return
	var soldiers_node := get_node_or_null("Soldiers")
	if not is_instance_valid(soldiers_node):
		return
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		if child.has_method("is_dead_soldier") and child.is_dead_soldier():
			continue
		if child.has_method("get_crew_role_value") and str(child.get_crew_role_value()).strip_edges().to_lower() != normalized_from:
			continue
		if child.has_method("apply_crew_role"):
			child.apply_crew_role(normalized_to)
		else:
			child.set("crew_role", normalized_to)
			child.set_meta("crew_role", normalized_to)


func set_preview_deck_light_enabled(enabled: bool) -> void:
	enable_deck_light = enabled
	_refresh_deck_light()

## 병사가 사망할 때마다 호출되어, 배의 폐선 여부를 이벤트 방식으로 검사
func check_derelict_status() -> void:
	BaseShipStatusHelper.check_derelict_status(self)


func _update_boarding_state(delta: float) -> void:
	BaseShipStatusHelper.update_boarding_state(self, delta)


func get_hostile_boarder_count() -> int:
	return deck_hostile_boarder_count

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
	var target_fwd = Vector3.ZERO
	
	if "current_speed" in target_node:
		target_fwd = - target_node.global_transform.basis.z
		if target_node.has_method("get_current_speed_value"):
			target_vel = target_fwd * target_node.get_current_speed_value()
		else:
			target_vel = target_fwd * NodeContractHelper.get_current_speed_value(target_node)
	else:
		target_fwd = - target_node.global_transform.basis.z
		target_vel = target_fwd * NodeContractHelper.get_current_speed_value(target_node)
	
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
	return BaseShipCollisionHelper.calculate_collision_repulsion(self)

func _is_engagement_pair(other: Node3D) -> bool:
	if not is_instance_valid(other):
		return false
	var my_target: Node3D = null
	if has_method("get_target_ship"):
		my_target = get_target_ship()
	var my_boarding_target = get_boarding_target_ship()
	var other_target: Node3D = NodeContractHelper.get_target_ship(other)
	var other_boarding_target: Node3D = NodeContractHelper.get_boarding_target_ship(other)
	return my_target == other \
		or my_boarding_target == other \
		or other_target == self \
		or other_boarding_target == self

## 나포 가능한 함대 정원(최대 3척)이 남았는지 확인
func can_capture_more_ships() -> bool:
	return EntityRegistry.count_captured_minions() < 3

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
	BaseShipCollisionHelper.apply_ramming_damage(self, other, impact_speed)

func _spawn_ship_collision_effects(impact_pos: Vector3, impact_speed: float) -> void:
	BaseShipCollisionHelper.spawn_ship_collision_effects(self, impact_pos, impact_speed)


## 데미지 처리 (공통)
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	if is_sinking or is_dying:
		return
	
	var hp_before: float = hull_hp
	if deck_is_contested and _is_contested_hull_damage_source(damage_source):
		amount *= contested_hull_damage_multiplier
	var final_damage = maxf(amount - hull_defense, 1.0)
	hull_hp -= final_damage
	_apply_sail_damage_from_hit(final_damage, damage_source)
	_apply_rudder_damage_from_hit(final_damage, hit_position, damage_source)
	
	if DEBUG_DAMAGE_LOGS and OS.is_debug_build():
		var source_label: String = damage_source if not damage_source.is_empty() else "unknown"
		var ship_label: String = name
		if not get_ship_type_value().is_empty():
			ship_label += "/" + get_ship_type_value()
		print("[DamageLog][%s][%s] source=%s raw=%.1f defense=%.1f final=%.1f hp=%.1f->%.1f" % [
			ship_label,
			get_team_tag(),
			source_label,
			amount,
			hull_defense,
			final_damage,
			hp_before,
			hull_hp,
		])

	if is_derelict and not damage_source.is_empty() and damage_source != "leak" and has_method("_sink_derelict"):
		call_deferred("_sink_derelict")
	
	# 플레이어 무기 피해 집계: 적 함선에만 기록
	if not damage_source.is_empty() and is_enemy_team():
		if is_instance_valid(_cached_level_manager) and _cached_level_manager.has_method("add_player_weapon_damage"):
			_cached_level_manager.add_player_weapon_damage(damage_source, final_damage)
	
	# 피격 이펙트 (파편) - 스로틀링 적용
	var current_time = Time.get_ticks_msec() / 1000.0
	if wood_splinter_scene and (current_time - _last_splinter_time > 0.2):
		_last_splinter_time = current_time
		var splinter = ScenePool.acquire(get_tree(), wood_splinter_scene)
		get_tree().root.add_child(splinter)
		if hit_position != Vector3.ZERO:
			splinter.global_position = hit_position + Vector3(0, 0.5, 0)
		else:
			splinter.global_position = global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1))
		splinter.rotation.y = randf() * TAU
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(final_damage)
		if splinter.has_method("pool_activate"):
			splinter.pool_activate()
			
	_flash_damage(final_damage)
	
	if hull_hp <= 0:
		die()


func _is_contested_hull_damage_source(damage_source: String) -> bool:
	if damage_source.is_empty():
		return false
	if damage_source.begins_with("cannon") or damage_source.contains("cannon"):
		return true
	if damage_source.contains("ballista") or damage_source.contains("singigeon"):
		return true
	if damage_source == "janggun" or damage_source.contains("fire"):
		return true
	return false

func _apply_sail_damage_from_hit(final_damage: float, damage_source: String) -> void:
	if masts.is_empty():
		return
	if damage_source == "leak":
		return
	var source_mult: float = 0.0
	var is_ramming_hit: bool = damage_source.begins_with("ramming")
	if damage_source.contains("chain"):
		source_mult = 1.55
	elif damage_source.begins_with("cannon") or damage_source == "janggun":
		source_mult = 1.0
	elif is_ramming_hit:
		# 충각은 선체 전반에 큰 충격을 주기 때문에 돛 손상도 대포보다 약간 더 잘 보이게 한다.
		source_mult = 1.35
	elif damage_source.contains("ballista") or damage_source.contains("singigeon") or damage_source.contains("fire"):
		source_mult = 0.75
	elif damage_source.is_empty() or damage_source == "unknown":
		source_mult = 0.45
	else:
		source_mult = 0.25
	if source_mult <= 0.0:
		return
	var sail_damage_delta: float = clamp((final_damage / 220.0) * source_mult, 0.01, 0.12)
	if is_ramming_hit:
		sail_damage_delta = clamp(sail_damage_delta * 1.2, 0.02, 0.18)
	var intact_masts: Array[Node] = []
	for mast in masts:
		if is_instance_valid(mast) and mast.has_method("add_sail_damage"):
			intact_masts.append(mast)
	if intact_masts.is_empty():
		return
	var chosen_index: int = randi() % intact_masts.size()
	var chosen_mast: Node = intact_masts[chosen_index]
	chosen_mast.call("add_sail_damage", sail_damage_delta)


func update_crew_allocation_state(delta: float) -> void:
	BaseShipCrewHelper.update_crew_allocation_state(self, delta)


func get_shiphandling_multiplier() -> float:
	return BaseShipCrewHelper.get_shiphandling_multiplier(self)


func get_gunnery_reload_multiplier() -> float:
	return BaseShipCrewHelper.get_gunnery_reload_multiplier(self)


func get_combat_effectiveness_multiplier() -> float:
	return BaseShipCrewHelper.get_combat_effectiveness_multiplier(self)


func get_effective_boarding_interval() -> float:
	return BaseShipCrewHelper.get_effective_boarding_interval(self)


func get_effective_boarding_capture_duration(attacker_ship: Node = null) -> float:
	return BaseShipCrewHelper.get_effective_boarding_capture_duration(self, attacker_ship)


func _estimate_available_crew_count() -> int:
	return BaseShipCrewHelper.estimate_available_crew_count(self)


func _is_in_gunnery_posture() -> bool:
	return BaseShipCrewHelper.is_in_gunnery_posture(self)


func _get_ship_cannon_range_for_allocation() -> float:
	return BaseShipCrewHelper.get_ship_cannon_range_for_allocation(self)


func _get_nearest_enemy_ship_distance_for_allocation() -> float:
	return BaseShipCrewHelper.get_nearest_enemy_ship_distance_for_allocation(self)


func apply_rudder_damage(amount: float) -> void:
	BaseShipRudderHelper.apply_rudder_damage(self, amount)


func get_rudder_health_ratio() -> float:
	return BaseShipRudderHelper.get_rudder_health_ratio(self)


func get_rudder_turn_multiplier() -> float:
	return BaseShipRudderHelper.get_rudder_turn_multiplier(self)


func get_rudder_response_multiplier() -> float:
	return BaseShipRudderHelper.get_rudder_response_multiplier(self)


func _apply_rudder_damage_from_hit(final_damage: float, hit_position: Vector3, damage_source: String) -> void:
	BaseShipRudderHelper.apply_rudder_damage_from_hit(self, final_damage, hit_position, damage_source)


func _get_stern_hit_factor(hit_position: Vector3) -> float:
	return BaseShipRudderHelper.get_stern_hit_factor(self, hit_position)

func _flash_damage(amount: float = 10.0) -> void:
	var shake_mult = clamp(amount / 10.0, 0.15, 2.0)
	var shake_tween = create_tween()
	shake_tween.tween_property(self , "rotation:z", rocking_amplitude * 3.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", -rocking_amplitude * 2.0 * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", 0.0, 0.2)

## 화염 데미지
func take_fire_damage(_dps: float, duration: float) -> void:
	BaseShipStatusHelper.take_fire_damage(self, duration)

func _update_burning_status(delta: float) -> void:
	BaseShipStatusHelper.update_burning_status(self, delta)

func _update_hull_regeneration(delta: float) -> void:
	BaseShipStatusHelper.update_hull_regeneration(self, delta)

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
		mesh_instance.set_meta("deploy_progress", 0.0)
		mesh_instance.set_meta("deploy_duration", maxf(0.05, boarding_rope_throw_duration + randf_range(-0.06, 0.08)))
		rope_instances.append(mesh_instance)

func _update_ropes(delta: float = 0.0) -> void:
	if not is_instance_valid(boarding_target):
		_clear_ropes()
		return
		
	var target_center = boarding_target.global_position + Vector3(0, 0.5, 0)
	
	for rope in rope_instances:
		if not is_instance_valid(rope): continue
		
		var offset = rope.get_meta("anchor_offset", Vector3.ZERO)
		var start_pos = global_transform * offset
		
		var deploy_progress = float(rope.get_meta("deploy_progress", 1.0))
		var deploy_duration = maxf(0.05, float(rope.get_meta("deploy_duration", boarding_rope_throw_duration)))
		if deploy_progress < 1.0:
			deploy_progress = clampf(deploy_progress + (delta / deploy_duration), 0.0, 1.0)
			rope.set_meta("deploy_progress", deploy_progress)
		
		# 밧줄 투척 연출: 시작점에서 목표점까지 전개 길이가 점진적으로 늘어난다.
		var current_end = start_pos.lerp(target_center, deploy_progress)
		var dist = maxf(0.05, start_pos.distance_to(current_end))
		
		var mid_pos = start_pos + (current_end - start_pos) * 0.5
		rope.global_transform = Transform3D().looking_at(current_end - mid_pos, Vector3.UP)
		rope.global_position = mid_pos
		
		rope.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
		rope.scale = Vector3(1.0, dist, 1.0)

func _clear_ropes() -> void:
	for rope in rope_instances:
		if is_instance_valid(rope):
			rope.queue_free()
	rope_instances.clear()

func _get_boarding_alignment_state(target_ship: Node3D) -> Dictionary:
	if not is_instance_valid(target_ship):
		return {}

	var diff = target_ship.global_position - global_position
	diff.y = 0.0
	if diff.length_squared() < 0.01:
		return {}
	var dir = diff.normalized()

	var my_fwd = -global_transform.basis.z
	my_fwd.y = 0.0
	if my_fwd.length_squared() > 0.001:
		my_fwd = my_fwd.normalized()
	else:
		my_fwd = dir

	var target_fwd = -target_ship.global_transform.basis.z
	target_fwd.y = 0.0
	if target_fwd.length_squared() > 0.001:
		target_fwd = target_fwd.normalized()
	else:
		target_fwd = -dir

	var my_contact_dot: float = my_fwd.dot(dir)
	var target_contact_dot: float = target_fwd.dot(-dir)
	var parallel_dot: float = my_fwd.dot(target_fwd)

	var target_speed = NodeContractHelper.get_current_speed_value(target_ship)
	var my_vel = my_fwd * current_speed
	var target_vel = target_fwd * target_speed
	var closing_speed = absf((my_vel - target_vel).dot(dir))

	return {
		"dir": dir,
		"my_fwd": my_fwd,
		"target_fwd": target_fwd,
		"my_contact_dot": my_contact_dot,
		"target_contact_dot": target_contact_dot,
		"parallel_dot": parallel_dot,
		"closing_speed": closing_speed,
	}

func _is_side_boarding_approach(target_ship: Node3D) -> bool:
	var state = _get_boarding_alignment_state(target_ship)
	if state.is_empty():
		return false

	var my_contact_abs: float = absf(float(state["my_contact_dot"]))
	var target_contact_abs: float = absf(float(state["target_contact_dot"]))
	var parallel_dot: float = float(state["parallel_dot"])
	return my_contact_abs <= 0.55 and target_contact_abs <= 0.55 and parallel_dot >= 0.2

func _is_boarding_contact_stable() -> bool:
	if not is_instance_valid(boarding_target):
		return false

	if not _is_side_boarding_approach(boarding_target):
		return false

	var state = _get_boarding_alignment_state(boarding_target)
	if state.is_empty():
		return false
	var closing_speed: float = float(state["closing_speed"])
	return closing_speed <= boarding_max_relative_speed * 1.35

func _process_boarding_common(delta: float) -> void:
	BaseShipBoardingHelper.process_boarding_common(self, delta)

func _cancel_boarding() -> void:
	BaseShipBoardingHelper.cancel_boarding(self)

func _transfer_one_soldier() -> void:
	BaseShipBoardingHelper.transfer_one_soldier(self)
