@tool
extends Node3D
class_name BaseShip

const PlayerFleetRoleHelper = preload("res://scripts/entities/ships/player_fleet_role_helper.gd")
const BaseShipSoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")
const BaseShipBoardingRopeVisualHelper = preload("res://scripts/entities/ships/base_ship_boarding_rope_visual_helper.gd")
const BaseShipDamageHelper = preload("res://scripts/entities/ships/base_ship_damage_helper.gd")
const BaseShipDebugSnapshotHelper = preload("res://scripts/entities/ships/base_ship_debug_snapshot_helper.gd")
const BaseShipHullBoundsHelper = preload("res://scripts/entities/ships/base_ship_hull_bounds_helper.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const DEBUG_COMBAT_LOGS := false
const PLAYER_CREW_RAMMING_AOE_MULTIPLIER := 0.35
const DAMAGE_ROCK_FORWARD_MULT := 0.9
const DAMAGE_ROCK_BACK_MULT := 0.65
const NODE_PROXIMITY_AREA := NodeContractHelper.SHIP_NODE_PROXIMITY_AREA
const NODE_HIT_AREA := NodeContractHelper.SHIP_NODE_HIT_AREA
const NODE_SOLDIERS := NodeContractHelper.SHIP_NODE_SOLDIERS
const NODE_CANNONS := NodeContractHelper.SHIP_NODE_CANNONS
const NODE_SPEAR_RAIL := NodeContractHelper.SHIP_NODE_SPEAR_RAIL
const NODE_HULL_DEFENSE_VISUALS := NodeContractHelper.SHIP_NODE_HULL_DEFENSE_VISUALS
const NODE_SINGIGEON_LAUNCHER := NodeContractHelper.SHIP_NODE_SINGIGEON_LAUNCHER
const NODE_JANGGUN_LAUNCHER := NodeContractHelper.SHIP_NODE_JANGGUN_LAUNCHER
const SHIP_SINK_BUBBLES_SFX := "ship_sink_bubbles"
const SHIP_SINK_BUBBLES_DEFAULT_DELAY := 0.35
const SHIP_SINK_BUBBLES_VOLUME_DB := -1.5
const SHIP_SINK_BUBBLES_PITCH_MIN := 0.94
const SHIP_SINK_BUBBLES_PITCH_MAX := 1.06
const RUNTIME_GENERATED_HULL_META := "runtime_generated_hull"
const CREW_RANGED_COVER_BASE_DEFENSE_META := "crew_ranged_cover_base_defense"

## 함선의 공통 기반 클래스 (물리, 시각 효과, 내구도 관리)

@export_category("Base Ship")
@export_group("Movement")
@export var max_speed: float = 10.0
@export var acceleration: float = 1.5
@export var deceleration: float = 1.2
@export var turn_rate: float = 50.0

@export_group("Collision / Deck")
@export var collision_profile: ShipCollisionProfile
@export_range(2.0, 15.0) var base_collision_radius: float = 4.5 ## 기본 충돌 및 밀쳐내기 반경
@export_range(0.1, 3.0) var length_multiplier: float = 1.0 ## 앞/뒤 범위를 늘리거나 줄일 비율 (타원형 길이)
@export_range(0.1, 3.0) var width_multiplier: float = 1.0 ## 좌/우 범위를 늘리거나 줄일 비율 (타원형 폭)
@export var auto_fit_collision_to_hull: bool = true ## 선체 메시 기준으로 충돌 타원값 자동 정렬
@export var auto_fit_contact_areas_to_hull: bool = true ## 선체 메시 기준으로 HitArea/ProximityArea 박스 자동 정렬
@export var prefer_authoring_boarding_anchors: bool = true ## Authoring/BoardingAnchors 마커가 있으면 밧줄 연결점으로 우선 사용
@export_range(0.75, 1.1) var auto_fit_scale: float = 1.0 ## 선체 자동 충돌 타원 전체 스케일
@export_range(0.0, 2.0) var collision_padding: float = 0.02 ## 충돌 판정 여유치(반폭/반길이에 추가)
@export_range(0.6, 1.0) var deck_bounds_ratio: float = 0.88 ## 병사 덱 이동 범위 축소 비율
@export_range(0.35, 4.0, 0.05) var ship_mass_scale: float = 1.0 ## 충돌/보딩에서 쓰는 상대 질량감
@export_range(0, 24, 1) var max_dead_bodies_on_deck: int = 10 ## 갑판에 남겨둘 시체 상한. 초과분은 오래된 것부터 조용히 정리한다.

@export_group("Sail")
@export var sail_angle: float = 0.0 # 돛 각도 (-90 ~ 90도)
@export_group("Sail Wear")
@export var hull_sail_wear_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var hull_sail_wear_max_damage: float = 0.5
@export_range(0.25, 3.0, 0.05) var hull_sail_wear_curve: float = 1.05

@export_group("Rudder")
@export var rudder_angle: float = 0.0 # 러더 각도 (-45 ~ 45도)
@export_range(10.0, 200.0, 1.0) var rudder_max_health: float = 100.0
var rudder_health: float = 100.0
@export_range(0.1, 0.9, 0.05) var rudder_critical_threshold: float = 0.35
var _rudder_critical_announced: bool = false

@export_group("Field Repair")
@export var rigging_field_repair_enabled: bool = false
@export_range(0.0, 60.0, 0.5) var rigging_repair_delay: float = 10.0
@export_range(0.2, 1.0, 0.05) var rigging_repair_target_ratio: float = 0.65
@export_range(0.0, 0.25, 0.005) var sail_field_repair_rate: float = 0.035
@export_range(0.0, 20.0, 0.25) var rudder_field_repair_rate: float = 4.0
var _rigging_repair_cooldown: float = 0.0
var _rigging_repair_feedback_pending: bool = false
var _rigging_repair_active_feedback_shown: bool = false
var _rigging_repair_complete_feedback_shown: bool = false

@export_group("Floating / Hit Sway")
@export var bobbing_amplitude: float = 0.3
@export var bobbing_speed: float = 1.0
@export var rocking_amplitude: float = 0.05
@export var floating_offset: float = 0.55 ## 기본 부력 오프셋 (수면 위로 배를 띄움)
@export_group("Anchor Impact Sway")
@export var anchor_impact_sway_enabled: bool = true
@export_range(0.0, 18.0, 0.5) var anchor_impact_max_pitch_degrees: float = 5.0
@export_range(0.0, 8.0, 0.1) var anchor_impact_impulse: float = 1.7
@export_range(1.0, 80.0, 1.0) var anchor_impact_stiffness: float = 36.0
@export_range(0.0, 24.0, 0.5) var anchor_impact_damping: float = 8.5
@export_group("")
var _centrifugal_tilt: float = 0.0 # 원심력에 의한 기울기
var _anchor_impact_pitch: float = 0.0
var _anchor_impact_pitch_velocity: float = 0.0

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
@export_group("Crew Allocation")
@export_range(0.1, 1.5, 0.05) var crew_allocation_eval_interval: float = 0.35

@export_group("Hull Health")
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
@export_group("Boarding Capture")
@export_range(1.0, 12.0, 0.25) var boarding_capture_duration: float = 5.0
@export_range(0.0, 1.0, 0.01) var contested_hull_damage_multiplier: float = 0.68
@export_range(1.0, 100.0, 1.0) var boarding_capture_damage_tick: float = 25.0

@export var blocks_boarding: bool = false ## 거북선처럼 구조적으로 적 도선을 허용하지 않는 선체.
var is_boarding: bool = false
var boarding_timer: float = 0.0
var boarding_interval: float = 1.0
var boarding_prep_timer: float = 0.0
var boarding_prep_duration: float = 0.0
var boarding_target: Node3D = null
var max_boarding_distance: float = 9.0
var boarding_break_distance: float = 12.0
var rope_instances: Array[MeshInstance3D] = []
const BOARDING_ROPE_RADIUS := 0.18
const BOARDING_ROPE_EXTRA_CULL_MARGIN := 24.0
const BOARDING_ROPE_DECK_HEIGHT_OFFSET := 0.85
const BOARDING_ROPE_MIN_ANCHOR_HEIGHT := 0.65
const BOARDING_ROPE_NORMAL_ALBEDO := Color(1.0, 0.88, 0.52, 1.0)
const BOARDING_ROPE_NORMAL_EMISSION := Color(1.0, 0.66, 0.24, 1.0)
const BOARDING_ROPE_STRAIN_ALBEDO := Color(1.0, 0.18, 0.08, 1.0)
const BOARDING_ROPE_STRAIN_EMISSION := Color(1.0, 0.06, 0.02, 1.0)
const BOARDING_HOOK_NORMAL_ALBEDO := Color(1.0, 0.86, 0.52, 0.95)
const BOARDING_HOOK_NORMAL_EMISSION := Color(1.0, 0.72, 0.28, 1.0)
const BOARDING_HOOK_STRAIN_ALBEDO := Color(1.0, 0.20, 0.08, 0.98)
const BOARDING_HOOK_STRAIN_EMISSION := Color(1.0, 0.08, 0.02, 1.0)
const BOARDING_PULL_BASE_REST_LENGTH := 8.5
const BOARDING_PULL_EDGE_SLACK := 0.25
const BOARDING_PULL_MIN_REST_LENGTH := 4.25
const BOARDING_PULL_MAX_REST_LENGTH := 18.0
const BOARDING_PULL_VELOCITY_MAX := 5.8
const BOARDING_PULL_DEFENDER_ACCEL_MULT := 0.22
const BOARDING_PULL_DEFENDER_VELOCITY_MAX_MULT := 0.28
const BOARDING_PULL_VELOCITY_DAMPING := 1.7
const BOARDING_PULL_VELOCITY_RELEASE_DAMPING := 8.5
@export_range(0.0, 3.0) var boarding_contact_grace_duration: float = 0.45
@export_range(0.0, 2.0) var boarding_hook_throw_delay: float = 0.35
@export_range(0.0, 3.0) var boarding_secondary_rope_delay: float = 0.9
@export_range(0.5, 8.0) var boarding_max_relative_speed: float = 2.5
@export_range(1, 3) var boarding_initial_rope_count: int = 1
@export_range(0.05, 1.0) var boarding_rope_throw_duration: float = 0.28
var boarding_contact_timer: float = 0.0
var boarding_hook_timer: float = 0.0
var boarding_secondary_rope_timer: float = 0.0
var _initial_rope_deployed: bool = false
var _full_rope_deployed: bool = false
var boarding_pull_velocity: Vector3 = Vector3.ZERO
var boarding_rope_visual_pulse: float = 0.0
var _boarding_rope_visual_tween: Tween = null

var fire_build_up: float = 0.0
var fire_threshold: float = 100.0
@export_group("Fire")
@export_range(0.0, 1.0, 0.01) var fire_damage_ignition_chance_per_point: float = 0.012
@export_range(0.0, 1.0, 0.01) var fire_pot_ignition_chance: float = 0.25
@export_range(0.1, 20.0, 0.1) var fire_pot_burn_duration: float = 5.0
@export_range(0.0, 20.0, 0.1) var burn_hull_damage_per_second: float = 2.0
@export_range(0.0, 10.0, 0.1) var burning_crew_damage_per_second: float = 1.0
@export_range(0.25, 3.0, 0.05) var burning_crew_damage_tick_interval: float = 1.0

var _recent_ram_targets: Dictionary = {}
var min_ramming_speed: float = 6.0 # 충돌 데미지가 발생하기 위한 최소 상대 속도 상향 (4.0 -> 6.0)
@export_group("Ramming")
@export_range(0.25, 3.0, 0.05) var ramming_damage_multiplier: float = 1.0 ## 이 배가 상대에게 주는 충돌 피해 배율.
@export_range(0.0, 3.0, 0.05) var ramming_knockback_multiplier: float = 0.0 ## 이 배가 충각으로 상대에게 주는 밀림 배율.
var collision_impulse_velocity: Vector3 = Vector3.ZERO
var broad_phase_padding: float = 2.0 # 충돌 broad-phase 여유 거리
var burn_timer: float = 0.0

var _last_splinter_time: float = 0.0 # 파편 생성 쿨다운 (최적화)
var _hull_half_extents: Vector2 = Vector2(1.5, 4.0) # X:반폭, Y:반길이


@export_group("Effect Scenes")
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
@export var water_splash_scene: PackedScene = preload("res://scenes/effects/water_blast.tscn")
@export var impact_puff_scene: PackedScene = preload("res://scenes/effects/impact_puff.tscn")
@export var fire_effect_scene: PackedScene = preload("res://scenes/effects/fire_effect.tscn")
@export var loot_scene: PackedScene = preload("res://scenes/effects/floating_loot.tscn")
@export_range(0.0, 1.0, 0.01) var floating_loot_drop_chance: float = 1.0
@export var survivor_scene: PackedScene = preload("res://scenes/effects/survivor.tscn")
var _fire_instance: Node3D = null

@export var fire_effect_offset: Vector3 = Vector3(0.0, 0.55, -0.25)
@export var fire_effect_offset_randomness: Vector3 = Vector3(0.65, 0.05, 1.1)
@export_range(0.25, 4.0, 0.05) var fire_effect_scale: float = 1.6
@export_range(0.0, 0.6, 0.01) var fire_effect_scale_randomness: float = 0.18

# === 노드 참조 (이제 HullScene 내부를 스캔) ===
var masts: Array[Node] = []
var mast_fold_pivots: Array[Node] = []
var masts_folded: bool = false
var rudder_visual: Node3D = null
var anchor_visuals: Array[Node3D] = []
var _anchor_visual_rest_transforms: Dictionary = {}
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
var oar_pivots_left: Array[Node3D] = []
var oar_pivots_right: Array[Node3D] = []

var _cached_level_manager: Node = null
var _cached_hud: Node = null
var _cached_ocean: Node3D = null
var _cached_audio_manager: Node = null
var _cached_wave_height: float = 0.0
var _wave_sample_timer: float = 0.0
@export_group("Performance")
@export_range(0.02, 0.25) var wave_sample_interval: float = 0.08

func _ready() -> void:
	_ensure_collision_profile()
	base_y = position.y + floating_offset
	add_to_group("ships")
	
	hull_hp = max_hull_hp
	rudder_health = rudder_max_health
	
	# 돛대, 타륜 등의 레퍼런스 캐싱 (에디터/런타임 공통)
	_cache_hull_references(self)
	_apply_authored_deck_height_if_available()
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
		collision_profile.ship_mass_scale = ship_mass_scale
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
	ship_mass_scale = collision_profile.ship_mass_scale

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
	collision_profile.ship_mass_scale = ship_mass_scale

func get_collision_half_extents() -> Vector2:
	return ShipContactGeometry.get_soft_collision_half_extents(self)

func get_directional_collision_radius(world_dir: Vector3) -> float:
	return ShipContactGeometry.get_directional_collision_radius(self, world_dir)

func get_collision_distance_to(other: Node3D) -> float:
	return ShipContactGeometry.get_collision_distance_between(self, other)

func get_deck_half_extents() -> Vector2:
	var authored_deck_extents := ShipAuthoringHelper.get_deck_area_half_extents(self)
	if authored_deck_extents.x > 0.01 and authored_deck_extents.y > 0.01:
		return authored_deck_extents
	var hull_ext = _hull_half_extents
	if hull_ext.x <= 0.01 or hull_ext.y <= 0.01:
		hull_ext = get_collision_half_extents()
	var ratio = clampf(deck_bounds_ratio, 0.6, 1.0)
	return Vector2(
		maxf(0.4, hull_ext.x * ratio),
		maxf(0.8, hull_ext.y * ratio)
	)

func get_deck_half_width_at_z(local_z: float) -> float:
	var authored_width := ShipAuthoringHelper.get_deck_area_half_width_at_z(self, local_z)
	if authored_width > 0.01:
		return authored_width
	return get_deck_half_extents().x

func _refresh_collision_bounds_from_hull() -> void:
	BaseShipHullBoundsHelper.refresh_collision_bounds_from_hull(self)

func _sync_contact_area_shapes_from_hull() -> void:
	BaseShipHullBoundsHelper.sync_contact_area_shapes_from_hull(self)

func _get_contact_area_height(area_name: String) -> float:
	return BaseShipHullBoundsHelper.get_contact_area_height(self, area_name)

func _fit_contact_area_box_shape(area_name: String, size: Vector3) -> void:
	BaseShipHullBoundsHelper.fit_contact_area_box_shape(self, area_name, size)

func _sync_contact_area_layers(layer_override: int = -1) -> void:
	BaseShipHullBoundsHelper.sync_contact_area_layers(self, layer_override)

func _set_contact_areas_enabled(enabled: bool) -> void:
	BaseShipHullBoundsHelper.set_contact_areas_enabled(self, enabled)

func _set_contact_area_enabled(area_name: String, enabled: bool) -> void:
	BaseShipHullBoundsHelper.set_contact_area_enabled(self, area_name, enabled)

func _get_opposing_team_collision_layer(team_name: String) -> int:
	return BaseShipHullBoundsHelper.get_opposing_team_collision_layer(team_name)

func _compute_hull_half_extents() -> Vector2:
	return BaseShipHullBoundsHelper.compute_hull_half_extents(self)

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	BaseShipHullBoundsHelper.collect_hull_bounds_mesh_instances(node, out)

func _is_excluded_bounds_mesh_name(name_lc: String) -> bool:
	return BaseShipHullBoundsHelper.is_excluded_hull_bounds_mesh_name(name_lc)

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	return BaseShipHullBoundsHelper.get_hull_bounds_aabb_corners(aabb)


## JSON 데이터에서 함선 스탯 로드
func load_ship_stats(type_name: String) -> Dictionary:
	var stats := ShipBlueprintHelper.load_stats(type_name)
	if stats.is_empty():
		return {}
	
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
	if stats.has("ship_mass_scale"):
		ship_mass_scale = clampf(float(stats["ship_mass_scale"]), 0.35, 4.0)
		if collision_profile != null:
			collision_profile.ship_mass_scale = ship_mass_scale
	if stats.has("blocks_boarding"): blocks_boarding = stats["blocks_boarding"] == true
	if stats.has("ramming_damage_multiplier"):
		ramming_damage_multiplier = maxf(0.1, float(stats["ramming_damage_multiplier"]))
	if stats.has("ramming_knockback_multiplier"):
		ramming_knockback_multiplier = clampf(float(stats["ramming_knockback_multiplier"]), 0.0, 3.0)
	if stats.has("crew_ranged_cover_defense"):
		set_meta(CREW_RANGED_COVER_BASE_DEFENSE_META, maxf(0.0, float(stats["crew_ranged_cover_defense"])))
	
	return stats

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	
	_apply_bobbing_effect()

func get_ramming_damage_multiplier_value() -> float:
	return maxf(0.1, ramming_damage_multiplier)

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

func are_weapons_disabled() -> bool:
	return is_combat_disabled() or deck_is_overrun

func can_be_boarded_by(attacker_ship: Node = null) -> bool:
	if not blocks_boarding:
		return true
	return can_be_roof_boarded_by(attacker_ship)

func can_be_roof_boarded_by(attacker_ship: Node = null) -> bool:
	if not is_roof_boarding_enabled():
		return false
	if get_team_tag() != "player":
		return false
	if not is_instance_valid(attacker_ship):
		return false
	var attacker_team: String = attacker_ship.get_team_tag() if attacker_ship.has_method("get_team_tag") else str(attacker_ship.get("team"))
	return attacker_team == "enemy"

func is_roof_boarding_enabled() -> bool:
	var type_name := get_ship_type_value().strip_edges().to_lower()
	if not (type_name.contains("geobukseon") or type_name.contains("turtle")):
		return false
	return not ShipAuthoringHelper.get_authoring_markers(self, ShipAuthoringHelper.ROOF_BOARDING_POINTS).is_empty()

func get_roof_boarding_landing_local(approach_global: Vector3) -> Vector3:
	var fallback := Vector3(0.0, maxf(deck_height + 1.1, 1.7), 0.0)
	return _get_nearest_authoring_marker_local(ShipAuthoringHelper.ROOF_BOARDING_POINTS, approach_global, fallback)

func clamp_roof_boarding_landing_local(local_position: Vector3) -> Vector3:
	return _clamp_roof_local_position(local_position)

func is_roof_local_position_in_bounds(local_position: Vector3) -> bool:
	if not is_roof_boarding_enabled():
		return false
	var clamped := _clamp_roof_local_position(local_position)
	return local_position.distance_squared_to(clamped) <= 0.04

func get_hull_hp_value() -> float:
	return hull_hp

func get_projectile_aim_point(vertical_offset: float = 0.55) -> Vector3:
	var base_position := global_position if is_inside_tree() else position
	return base_position + Vector3(0.0, maxf(0.55, deck_height + maxf(0.0, vertical_offset)), 0.0)

func get_ship_authoring_summary() -> Dictionary:
	return ShipAuthoringHelper.build_summary(self)

func _apply_authored_deck_height_if_available() -> bool:
	var authored_deck_height := ShipAuthoringHelper.get_deck_area_height(self)
	if authored_deck_height <= 0.01:
		return false
	deck_height = authored_deck_height
	return true

func get_proximity_area() -> Area3D:
	var area := get_node_or_null(NODE_PROXIMITY_AREA)
	return area as Area3D if area is Area3D else null

func get_hit_area() -> Area3D:
	var area := get_node_or_null(NODE_HIT_AREA)
	return area as Area3D if area is Area3D else null

func get_contact_area(area_name: String) -> Area3D:
	match area_name:
		NODE_PROXIMITY_AREA:
			return get_proximity_area()
		NODE_HIT_AREA:
			return get_hit_area()
		_:
			var area := get_node_or_null(area_name)
			return area as Area3D if area is Area3D else null

func get_soldiers_container() -> Node:
	return get_node_or_null(NODE_SOLDIERS)

func get_direct_hull_child(include_runtime_generated: bool = true) -> Node3D:
	for child in get_children():
		if not is_instance_valid(child) or not (child is Node3D):
			continue
		if not str(child.name).contains("Hull"):
			continue
		if not include_runtime_generated and _is_runtime_generated_hull(child):
			continue
		return child as Node3D
	return null

func get_authored_hull_child() -> Node3D:
	for child in get_children():
		if not is_instance_valid(child) or not (child is Node3D):
			continue
		if not str(child.name).contains("Hull"):
			continue
		if _is_runtime_generated_hull(child):
			continue
		return child as Node3D
	return null

func _is_runtime_generated_hull(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if bool(node.get_meta(RUNTIME_GENERATED_HULL_META, false)):
		return true
	return str(node.name) == "EditorHull"

func _remove_runtime_generated_hulls() -> void:
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if not str(child.name).contains("Hull"):
			continue
		if not _is_runtime_generated_hull(child):
			continue
		remove_child(child)
		child.queue_free()

func _ensure_hybrid_runtime_hull(type_name: String, fallback: PackedScene, stats: Dictionary) -> Node3D:
	var authored_hull := get_authored_hull_child()
	if is_instance_valid(authored_hull):
		_remove_runtime_generated_hulls()
		return authored_hull

	_remove_runtime_generated_hulls()
	var runtime_hull_scene: PackedScene = ShipBlueprintHelper.load_hull_scene(type_name, fallback, stats)
	if not is_instance_valid(runtime_hull_scene):
		return null
	var hull_inst := runtime_hull_scene.instantiate() as Node3D
	if not is_instance_valid(hull_inst):
		return null
	hull_inst.set_meta(RUNTIME_GENERATED_HULL_META, true)
	add_child(hull_inst)
	return hull_inst

func _ensure_editor_preview_hull(type_name: String, fallback: PackedScene, stats: Dictionary = {}) -> Node3D:
	var authored_hull := get_authored_hull_child()
	if is_instance_valid(authored_hull):
		_remove_runtime_generated_hulls()
		return authored_hull

	_remove_runtime_generated_hulls()
	var resolved_stats := stats
	if resolved_stats.is_empty():
		resolved_stats = load_ship_stats(type_name)
	if resolved_stats.is_empty():
		return null
	var preview_scene := ShipBlueprintHelper.load_hull_scene(type_name, fallback, resolved_stats)
	if not is_instance_valid(preview_scene):
		return null
	var preview := preview_scene.instantiate() as Node3D
	if not is_instance_valid(preview):
		return null
	preview.name = "EditorHull"
	preview.set_meta(RUNTIME_GENERATED_HULL_META, true)
	add_child(preview)
	return preview

func get_cannons_container() -> Node3D:
	var preferred_node: Node3D = null
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if str(child.name).contains("Hull"):
			var nested := child.find_child(NODE_CANNONS, true, false)
			if nested is Node3D:
				preferred_node = nested as Node3D
				break

	if preferred_node == null:
		var any_cannons := find_child(NODE_CANNONS, true, false)
		if any_cannons is Node3D:
			preferred_node = any_cannons as Node3D

	return preferred_node

func ensure_cannons_container() -> Node3D:
	var cannons_node := get_cannons_container()
	if is_instance_valid(cannons_node):
		return cannons_node
	cannons_node = Node3D.new()
	cannons_node.name = NODE_CANNONS
	add_child(cannons_node)
	return cannons_node


func enforce_dead_body_limit() -> void:
	if max_dead_bodies_on_deck <= 0:
		return
	var bodies: Array[Node] = []
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier):
			continue
		if not BaseShipSoldierStateHelper.is_dead_soldier(soldier):
			continue
		if BaseShipSoldierStateHelper.is_incapacitated_soldier(soldier):
			continue
		if soldier.get_meta("cargo_transport_in_progress", false) == true:
			continue
		if soldier.get_meta("support_overboard_disposal_in_progress", false) == true:
			continue
		bodies.append(soldier)

	var overflow := bodies.size() - max_dead_bodies_on_deck
	if overflow <= 0:
		return
	bodies.sort_custom(func(a: Node, b: Node) -> bool:
		var a_frame := int(a.get_meta("dead_body_order", 0)) if is_instance_valid(a) else 0
		var b_frame := int(b.get_meta("dead_body_order", 0)) if is_instance_valid(b) else 0
		return a_frame < b_frame
	)
	for index in range(mini(overflow, bodies.size())):
		var body := bodies[index]
		if is_instance_valid(body):
			body.queue_free()

func clear_hull_defense_upgrade_nodes() -> void:
	_queue_scene_contract_child(NODE_SPEAR_RAIL)
	_queue_scene_contract_child(NODE_HULL_DEFENSE_VISUALS)
	if has_meta("spear_rail_damage"):
		remove_meta("spear_rail_damage")

func clear_singigeon_launcher() -> void:
	_queue_scene_contract_child(NODE_SINGIGEON_LAUNCHER)

func install_janggun_launcher(launcher_scene: PackedScene, local_position: Vector3 = Vector3(0.0, 0.8, 2.0)) -> Node3D:
	var existing := get_node_or_null(NODE_JANGGUN_LAUNCHER)
	if existing is Node3D:
		return existing as Node3D
	if launcher_scene == null:
		return null
	var launcher := launcher_scene.instantiate()
	if not (launcher is Node3D):
		if is_instance_valid(launcher):
			launcher.queue_free()
		return null
	launcher.name = NODE_JANGGUN_LAUNCHER
	add_child(launcher)
	var launcher_node := launcher as Node3D
	launcher_node.position = local_position
	return launcher_node

func _queue_scene_contract_child(child_name: String) -> void:
	var child := get_node_or_null(child_name)
	if is_instance_valid(child):
		child.queue_free()

func get_base_collision_radius_value() -> float:
	return base_collision_radius

func get_collision_width_multiplier_value() -> float:
	return width_multiplier

func get_collision_length_multiplier_value() -> float:
	return length_multiplier

func get_current_speed_value() -> float:
	return current_speed

func apply_collision_impulse(impulse_velocity: Vector3) -> void:
	impulse_velocity.y = 0.0
	if impulse_velocity.length_squared() <= 0.0001:
		return
	collision_impulse_velocity += impulse_velocity
	var max_impulse_speed := 11.0
	if collision_impulse_velocity.length() > max_impulse_speed:
		collision_impulse_velocity = collision_impulse_velocity.normalized() * max_impulse_speed

func consume_collision_impulse_velocity(delta: float) -> Vector3:
	var impulse := collision_impulse_velocity
	collision_impulse_velocity = collision_impulse_velocity.move_toward(Vector3.ZERO, 14.0 * delta)
	return impulse

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

func play_sink_bubbles(delay_seconds: float = SHIP_SINK_BUBBLES_DEFAULT_DELAY, volume_db: float = SHIP_SINK_BUBBLES_VOLUME_DB) -> void:
	if delay_seconds <= 0.0:
		_play_sink_bubbles_now(volume_db)
		return
	var tree := get_tree()
	if not is_instance_valid(tree):
		return
	var ship_id := get_instance_id()
	tree.create_timer(delay_seconds).timeout.connect(func() -> void:
		var ship := NodeContractHelper.get_instance_node(ship_id)
		if not is_instance_valid(ship):
			return
		if ship.has_method("_play_sink_bubbles_now"):
			ship.call("_play_sink_bubbles_now", volume_db)
	)

func _play_sink_bubbles_now(volume_db: float = SHIP_SINK_BUBBLES_VOLUME_DB) -> void:
	if not is_instance_valid(_cached_audio_manager):
		_cached_audio_manager = get_node_or_null("/root/AudioManager")
	if not is_instance_valid(_cached_audio_manager) or not _cached_audio_manager.has_method("play_sfx"):
		return
	if _cached_audio_manager.has_method("play_sfx_random_pitch"):
		_cached_audio_manager.play_sfx_random_pitch(
			SHIP_SINK_BUBBLES_SFX,
			global_position,
			SHIP_SINK_BUBBLES_PITCH_MIN,
			SHIP_SINK_BUBBLES_PITCH_MAX,
			volume_db
		)
	else:
		_cached_audio_manager.play_sfx(
			SHIP_SINK_BUBBLES_SFX,
			global_position,
			randf_range(SHIP_SINK_BUBBLES_PITCH_MIN, SHIP_SINK_BUBBLES_PITCH_MAX),
			volume_db
		)

func is_derelict_ship() -> bool:
	return is_derelict

func is_boarding_ship() -> bool:
	return is_boarding

func get_boarding_target_ship() -> Node3D:
	return boarding_target if is_instance_valid(boarding_target) else null

func has_boarding_rope_link_to(other_ship: Node3D) -> bool:
	return is_boarding and is_instance_valid(other_ship) and get_boarding_target_ship() == other_ship and _initial_rope_deployed and has_active_boarding_rope_visual()

func has_active_boarding_rope_visual() -> bool:
	for rope in rope_instances:
		if is_instance_valid(rope):
			return true
	return false

func is_player_controlled_ship() -> bool:
	return PlayerFleetRoleHelper.is_player_flagship(self)

func set_player_fleet_role(role_name: String) -> void:
	PlayerFleetRoleHelper.set_fleet_role(self, role_name)

func get_player_fleet_role() -> String:
	return PlayerFleetRoleHelper.get_fleet_role(self)

# Legacy compatibility wrappers for old scenes and cached script references.
# New code should use set_player_fleet_role/get_player_fleet_role.
func set_ally_ship_role(role_name: String) -> void:
	set_player_fleet_role(role_name)

func get_ally_ship_role() -> String:
	return get_player_fleet_role()

func is_player_flagship() -> bool:
	return PlayerFleetRoleHelper.is_player_flagship(self)

func is_support_fleet_ship() -> bool:
	return PlayerFleetRoleHelper.is_support_ship(self)

func is_ally_support_ship() -> bool:
	return is_support_fleet_ship()

func is_player_team() -> bool:
	return get_team_tag() == "player"

func is_enemy_team() -> bool:
	return get_team_tag() == "enemy"


func get_debug_ship_state_snapshot() -> Dictionary:
	return BaseShipDebugSnapshotHelper.build_debug_ship_state_snapshot(self)


func get_debug_crew_snapshot() -> Dictionary:
	return BaseShipCrewHelper.build_debug_crew_snapshot(self)

func get_boarding_attacker_ship() -> Node3D:
	return boarding_attacker if is_instance_valid(boarding_attacker) else null

func set_boarding_attacker_ship(attacker: Node3D) -> void:
	if is_instance_valid(attacker):
		boarding_attacker = attacker
	else:
		boarding_attacker = null

func clear_boarding_attacker_ship() -> void:
	boarding_attacker = null

func set_masts_folded(folded: bool, immediate: bool = false) -> void:
	masts_folded = bool(folded)
	for pivot in mast_fold_pivots:
		if is_instance_valid(pivot) and pivot.has_method("set_folded"):
			pivot.call("set_folded", masts_folded, immediate)
	if masts_folded:
		for mast in masts:
			if is_instance_valid(mast) and mast.has_method("set_sail_deployed_ratio"):
				mast.call("set_sail_deployed_ratio", 0.0)

func toggle_masts_folded(immediate: bool = false) -> void:
	set_masts_folded(not masts_folded, immediate)

func are_masts_folded() -> bool:
	return masts_folded

func get_mast_fold_ratio() -> float:
	if mast_fold_pivots.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for pivot in mast_fold_pivots:
		if is_instance_valid(pivot) and pivot.has_method("get_fold_ratio"):
			total += float(pivot.call("get_fold_ratio"))
			count += 1
	return total / float(count) if count > 0 else 0.0

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
		mast_fold_pivots.clear()
		rudder_visual = null
		anchor_visuals.clear()
		_anchor_visual_rest_transforms.clear()
		wake_trail = null
		oar_pivot_left = null
		oar_pivot_right = null
		oar_pivots_left.clear()
		oar_pivots_right.clear()

	# 재귀적으로 내려가며 하드웨어 바인딩
	for child in node.get_children():
		if child.name.begins_with("Mast") and child.has_method("set_sail_angle"):
			if not masts.has(child): masts.append(child)
		elif child.name.begins_with("MastPivot") and child.has_method("set_folded"):
			if not mast_fold_pivots.has(child): mast_fold_pivots.append(child)
		elif child.name == "RudderVisual":
			rudder_visual = child
		elif child.name == "Anchor" and child is Node3D:
			var anchor_node := child as Node3D
			if not anchor_visuals.has(anchor_node):
				anchor_visuals.append(anchor_node)
				_anchor_visual_rest_transforms[anchor_node.get_instance_id()] = anchor_node.transform
		elif child.name == "WakeTrail" and child is Node3D:
			wake_trail = child as Node3D
		elif child.name.begins_with("OarBaseLeft") and child.has_node("OarPivot"):
			var left_pivot := child.get_node("OarPivot") as Node3D
			if is_instance_valid(left_pivot) and not oar_pivots_left.has(left_pivot):
				oar_pivots_left.append(left_pivot)
				if not is_instance_valid(oar_pivot_left):
					oar_pivot_left = left_pivot
		elif child.name.begins_with("OarBaseRight") and child.has_node("OarPivot"):
			var right_pivot := child.get_node("OarPivot") as Node3D
			if is_instance_valid(right_pivot) and not oar_pivots_right.has(right_pivot):
				oar_pivots_right.append(right_pivot)
				if not is_instance_valid(oar_pivot_right):
					oar_pivot_right = right_pivot
			
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
	var soldiers_node = get_soldiers_container()
	if not soldiers_node: return
	
	var applied_min: float = INF
	var applied_max: float = 0.0
	var hit_count: int = 0
	for child in soldiers_node.get_children():
		if child.has_method("take_damage") and BaseShipSoldierStateHelper.is_alive_soldier(child):
			var child_team: String = child.get_team_tag() if child.has_method("get_team_tag") else str(child.get("team"))
			var final_damage: float = damage * PLAYER_CREW_RAMMING_AOE_MULTIPLIER if child_team == "player" else damage
			applied_min = minf(applied_min, final_damage)
			applied_max = maxf(applied_max, final_damage)
			hit_count += 1
			# 병사들에게 충격파 데미지 전달
			child.take_damage(final_damage, impact_pos, "ramming_aoe")
			
			# 물리적 비틀거림/스턴 연출을 위해 일시적으로 공격 타이머 초기화 (딜레이 보장)
			if "attack_timer" in child:
				child.attack_timer = max(child.attack_timer, 1.5)
			
			# 약간 띄우는 넉백 효과 추가 (중력이 없으므로 XZ축으로만 흔들림 유도)
			if "velocity" in child:
				# XZ축 랜덤 넉발만 적용
				var push = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized()
				child.velocity += push * 2.0

	if hit_count <= 0:
		return
	if is_equal_approx(applied_min, applied_max):
		print("[%s] 함선 충돌로 인해 갑판 위 병사들이 %d의 충격 피해를 입었습니다." % [name, int(applied_max)])
	else:
		print("[%s] 함선 충돌로 인해 갑판 위 병사들이 %.1f~%.1f의 충격 피해를 입었습니다." % [name, applied_min, applied_max])

## 현재 생존 중인 선원(병사) 수 반환
func get_alive_crew_count() -> int:
	var soldiers_node = get_soldiers_container()
	if not soldiers_node: return 0
	
	var ship_team: String = get_team_tag()
	var count = 0
	for child in soldiers_node.get_children():
		var child_team: String = child.get_team_tag() if child.has_method("get_team_tag") else str(child.get("team"))
		if child_team != ship_team:
			continue
		# DEAD 상태가 아닌 병사만 카운트
		if BaseShipSoldierStateHelper.is_alive_soldier(child):
			count += 1
	return count


func request_cannon_reload_pose(cannon_node: Node3D, duration: float = 0.9) -> void:
	if not SoldierShipWorkPriorityHelper.are_crew_work_directives_enabled():
		return
	if not is_instance_valid(cannon_node):
		return
	if deck_is_contested or deck_is_overrun:
		return
	if SoldierShipWorkPriorityHelper.is_work_slot_reserved_for_other(cannon_node, null, SoldierShipWorkPriorityHelper.TASK_CANNON_RELOAD):
		return
	var own_team: String = get_team_tag()
	var best_soldier: Node3D = null
	var best_score: float = -INF
	var max_distance_sq: float = 64.0
	for soldier in EntityRegistry.get_soldiers_by_ship(self):
		if not is_instance_valid(soldier):
			continue
		var soldier_team: String = soldier.get_team_tag() if soldier.has_method("get_team_tag") else str(soldier.get("team"))
		if soldier_team != own_team:
			continue
		if not soldier.has_method("is_available_for_cannon_reload_pose") or not soldier.is_available_for_cannon_reload_pose():
			continue
		var work_score: float = SoldierShipWorkPriorityHelper.score_worker_for_task(
			soldier,
			SoldierShipWorkPriorityHelper.TASK_CANNON_RELOAD,
			cannon_node.global_position,
			max_distance_sq,
			cannon_node
		)
		if work_score <= best_score:
			continue
		best_score = work_score
		best_soldier = soldier
	if is_instance_valid(best_soldier) \
			and best_soldier.has_method("play_cannon_reload_pose") \
			and SoldierShipWorkPriorityHelper.reserve_work_slot(cannon_node, best_soldier, SoldierShipWorkPriorityHelper.TASK_CANNON_RELOAD, duration + 0.45):
		best_soldier.play_cannon_reload_pose(cannon_node, duration)


func set_preview_deck_state(is_contested: bool, is_overrun: bool = false) -> void:
	deck_is_contested = is_contested
	deck_is_overrun = is_overrun


func has_active_crew_role(role_name: String) -> bool:
	var normalized_role := role_name.strip_edges().to_lower()
	if normalized_role.is_empty():
		return false
	var soldiers_node := get_soldiers_container()
	if not is_instance_valid(soldiers_node):
		return false
		for child in soldiers_node.get_children():
			if not is_instance_valid(child):
				continue
			if BaseShipSoldierStateHelper.is_dead_soldier(child):
				continue
			if child.has_method("get_crew_role_value") and str(child.get_crew_role_value()).strip_edges().to_lower() == normalized_role:
				return true
	return false


func replace_preview_crew_role(from_role: String, to_role: String = "general") -> void:
	var normalized_from := from_role.strip_edges().to_lower()
	var normalized_to := to_role.strip_edges().to_lower()
	if normalized_from.is_empty() or normalized_to.is_empty() or normalized_from == normalized_to:
		return
	var soldiers_node := get_soldiers_container()
	if not is_instance_valid(soldiers_node):
		return
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		if BaseShipSoldierStateHelper.is_dead_soldier(child):
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


func _get_nearest_authoring_marker_local(container_name: String, reference_global: Vector3, fallback_local: Vector3) -> Vector3:
	var markers := ShipAuthoringHelper.get_authoring_markers(self, container_name)
	if markers.is_empty():
		return fallback_local
	var best_marker: Node3D = null
	var best_distance_sq := INF
	for marker in markers:
		if not is_instance_valid(marker):
			continue
		var distance_sq := marker.global_position.distance_squared_to(reference_global)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_marker = marker
	if not is_instance_valid(best_marker):
		return fallback_local
	return to_local(best_marker.global_position)


func _clamp_roof_local_position(local_position: Vector3) -> Vector3:
	var markers := ShipAuthoringHelper.get_authoring_markers(self, ShipAuthoringHelper.ROOF_SURFACE_POINTS)
	if markers.is_empty():
		markers = ShipAuthoringHelper.get_authoring_markers(self, ShipAuthoringHelper.ROOF_BOARDING_POINTS)
	if markers.is_empty():
		return local_position
	var half_ext := Vector2(1.6, 3.6)
	var roof_y := local_position.y
	for marker in markers:
		var local_marker := to_local(marker.global_position)
		half_ext.x = maxf(half_ext.x, absf(local_marker.x))
		half_ext.y = maxf(half_ext.y, absf(local_marker.z))
		roof_y = local_marker.y
	return Vector3(
		clampf(local_position.x, -half_ext.x - 0.25, half_ext.x + 0.25),
		roof_y,
		clampf(local_position.z, -half_ext.y - 0.35, half_ext.y + 0.35)
	)


## 병사가 사망할 때마다 호출되어, 배의 폐선 여부를 이벤트 방식으로 검사
func check_derelict_status() -> void:
	BaseShipStatusHelper.check_derelict_status(self)


func _update_boarding_state(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	BaseShipStatusHelper.update_boarding_state(self, delta)
	PhysicsFrameProfiler.end("ship_boarding_state", profile_start)


func get_hostile_boarder_count() -> int:
	return deck_hostile_boarder_count

## 도선 시 상대방을 끌어당기는 힘(장력) 계산
func _calculate_boarding_pull() -> Vector3:
	var target_node = null
	if is_boarding and is_instance_valid(boarding_target):
		if not has_boarding_rope_link_to(boarding_target):
			return Vector3.ZERO
		target_node = boarding_target
	elif is_instance_valid(boarding_attacker):
		if not _has_incoming_boarding_rope_link(boarding_attacker):
			return Vector3.ZERO
		target_node = boarding_attacker
		
	if not target_node:
		return Vector3.ZERO
		
	var target_pos = target_node.global_position
	var diff = target_pos - global_position
	var dist = diff.length()
	var dir = diff / max(dist, 0.001)
	
	# 1. 스프링 힘 (F = k * x) — 가속도(m/s²) 단위
	var contact_distance := _get_boarding_pull_contact_distance(target_node)
	var rest_length := _get_boarding_pull_rest_length(contact_distance)
	var pull_size_scale := _get_boarding_pull_size_scale(contact_distance)
	var enemy_boarding_pull_mult: float = _get_enemy_boarding_pull_multiplier(target_node)
	var pull_role_accel_mult: float = _get_boarding_pull_role_accel_multiplier(target_node)
	var spring_k = 3.6 * enemy_boarding_pull_mult * pull_size_scale
	var stretch = dist - rest_length
	
	# 밧줄은 당기는 힘만 준다. 가까워졌을 때 반대로 밀면 충돌 가드와 서로 싸우며
	# 도선 중인 배가 앞뒤로 진동하므로, 느슨한 구간에서는 장력을 0으로 둔다.
	if stretch < 0:
		stretch = 0
	
	# 거리가 도선 한계치(9.0)에 가까워지면 힘을 점진적으로 증가
	var tension_multiplier = 1.0
	if dist > rest_length:
		tension_multiplier = 1.0 + (dist - rest_length) * 1.25
		
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
		var damping_c = 2.8 * enemy_boarding_pull_mult * pull_size_scale
		final_damping_force = dir * (rel_vel_on_rope * damping_c)
	
	# 3. 최종 힘 계산 및 제한 (가속도 상한)
	var final_pull = (spring_force + final_damping_force) * pull_role_accel_mult
	var max_pull_accel = 15.5 * enemy_boarding_pull_mult * pull_size_scale * pull_role_accel_mult
	if final_pull.length() > max_pull_accel:
		final_pull = final_pull.normalized() * max_pull_accel
		
	return final_pull


func _calculate_boarding_pull_velocity(delta: float) -> Vector3:
	var pull_accel := _calculate_boarding_pull()
	if pull_accel.length_squared() > 0.0001:
		boarding_pull_velocity += pull_accel * delta
		boarding_pull_velocity.y = 0.0
		var max_velocity := _get_boarding_pull_velocity_max()
		if boarding_pull_velocity.length() > max_velocity:
			boarding_pull_velocity = boarding_pull_velocity.normalized() * max_velocity
		boarding_pull_velocity = boarding_pull_velocity.move_toward(Vector3.ZERO, BOARDING_PULL_VELOCITY_DAMPING * delta)
	else:
		boarding_pull_velocity = boarding_pull_velocity.move_toward(Vector3.ZERO, BOARDING_PULL_VELOCITY_RELEASE_DAMPING * delta)
	return boarding_pull_velocity


func _get_boarding_pull_velocity_max() -> float:
	var target_node: Node = null
	if is_boarding and is_instance_valid(boarding_target):
		target_node = boarding_target
	elif is_instance_valid(boarding_attacker):
		target_node = boarding_attacker
	var contact_distance := _get_boarding_pull_contact_distance(target_node) if is_instance_valid(target_node) else 0.0
	return BOARDING_PULL_VELOCITY_MAX * _get_boarding_pull_size_scale(contact_distance) * _get_boarding_pull_role_velocity_multiplier(target_node)


func _get_boarding_pull_contact_distance(target_node: Node) -> float:
	if not (target_node is Node3D):
		return 0.0
	if not has_method("get_collision_distance_to"):
		return 0.0
	return maxf(0.0, get_collision_distance_to(target_node as Node3D))


func _get_boarding_pull_rest_length(contact_distance: float) -> float:
	if contact_distance <= 0.01:
		return BOARDING_PULL_BASE_REST_LENGTH
	return clampf(
		contact_distance + BOARDING_PULL_EDGE_SLACK,
		BOARDING_PULL_MIN_REST_LENGTH,
		BOARDING_PULL_MAX_REST_LENGTH
	)


func _get_boarding_pull_size_scale(contact_distance: float) -> float:
	if contact_distance <= 0.01:
		return 1.0
	return clampf(maxf(1.0, contact_distance / BOARDING_PULL_BASE_REST_LENGTH), 1.0, 1.55)


func _get_enemy_boarding_pull_multiplier(target_node: Node) -> float:
	var attacker_node: Node = null
	if is_boarding:
		attacker_node = self
	elif is_instance_valid(boarding_attacker) and target_node == boarding_attacker:
		attacker_node = boarding_attacker
	if is_instance_valid(attacker_node) and attacker_node.has_method("get_team_tag") and attacker_node.call("get_team_tag") == "enemy":
		return 1.08
	return 1.0


func _get_boarding_pull_role_accel_multiplier(target_node: Node) -> float:
	if is_boarding and is_instance_valid(boarding_target) and target_node == boarding_target:
		return 1.0
	if is_instance_valid(boarding_attacker) and target_node == boarding_attacker:
		return BOARDING_PULL_DEFENDER_ACCEL_MULT
	return 1.0


func _get_boarding_pull_role_velocity_multiplier(target_node: Node) -> float:
	if is_boarding and is_instance_valid(boarding_target) and target_node == boarding_target:
		return 1.0
	if is_instance_valid(boarding_attacker) and target_node == boarding_attacker:
		var attacker_mass := BaseShipCollisionHelper.get_ship_mass_scale(target_node)
		var defender_mass := BaseShipCollisionHelper.get_ship_mass_scale(self)
		var mass_ratio := clampf(attacker_mass / maxf(defender_mass, 0.001), 0.35, 1.25)
		return BOARDING_PULL_DEFENDER_VELOCITY_MAX_MULT * mass_ratio
	return 1.0

func _has_incoming_boarding_rope_link(attacker_node: Node) -> bool:
	if not is_instance_valid(attacker_node):
		return false
	if attacker_node.has_method("has_boarding_rope_link_to"):
		return attacker_node.call("has_boarding_rope_link_to", self) == true
	if attacker_node.get("is_boarding") != true:
		return false
	if attacker_node.has_method("get_boarding_target_ship"):
		if attacker_node.call("get_boarding_target_ship") != self:
			return false
	elif attacker_node.get("boarding_target") != self:
		return false
	if attacker_node.get("_initial_rope_deployed") != true:
		return false
	var ropes_variant: Variant = attacker_node.get("rope_instances")
	if ropes_variant is Array:
		var ropes: Array = ropes_variant
		for rope in ropes:
			if is_instance_valid(rope):
				return true
		return false
	return true

## 밧줄 연결 전/후로 배끼리 겹치는(통과하는) 것을 막아주는 강한 물리 반발력
func _calculate_collision_repulsion() -> Vector3:
	var profile_start := PhysicsFrameProfiler.begin()
	var result := BaseShipCollisionHelper.calculate_collision_repulsion(self)
	PhysicsFrameProfiler.end("ship_collision_repulsion", profile_start)
	return result

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
	return PlayerFleetRoleHelper.count_legacy_captured_ships(EntityRegistry.get_legacy_captured_ships()) < 3

## 충격(충각) 타격 로직 - 타원형 각도 판정 포함
func apply_ramming_damage(other: Node3D, impact_speed: float) -> void:
	BaseShipCollisionHelper.apply_ramming_damage(self, other, impact_speed)

func _spawn_ship_collision_effects(impact_pos: Vector3, impact_speed: float) -> void:
	BaseShipCollisionHelper.spawn_ship_collision_effects(self, impact_pos, impact_speed)


## 데미지 처리 (공통)
func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	BaseShipDamageHelper.apply_hull_damage(self, amount, hit_position, damage_source)


func _is_contested_hull_damage_source(damage_source: String) -> bool:
	return BaseShipDamageHelper.is_contested_hull_damage_source(damage_source)

func _apply_sail_damage_from_hit(_final_damage: float, _damage_source: String) -> void:
	pass


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


func _mark_rigging_damage_for_repair() -> void:
	BaseShipStatusHelper.mark_rigging_damage_for_repair(self)


func _update_rigging_recovery(delta: float) -> void:
	BaseShipStatusHelper.update_rigging_recovery(self, delta)

func _flash_damage(amount: float = 10.0) -> void:
	var shake_mult = clamp(amount / 16.0, 0.08, 0.9)
	var shake_tween = create_tween()
	shake_tween.tween_property(self , "rotation:z", rocking_amplitude * DAMAGE_ROCK_FORWARD_MULT * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", -rocking_amplitude * DAMAGE_ROCK_BACK_MULT * shake_mult, 0.1)
	shake_tween.tween_property(self , "rotation:z", 0.0, 0.2)

func _trigger_anchor_impact_sway(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	BaseShipVisualHelper.trigger_anchor_impact_sway(self, amount, hit_position, damage_source)

## 화염 데미지
func take_fire_damage(dps: float, duration: float) -> void:
	BaseShipStatusHelper.take_fire_damage(self, dps, duration)

func try_ignite_fire(chance: float, duration: float) -> bool:
	return BaseShipStatusHelper.try_ignite_fire(self, chance, duration)

func add_fire_buildup(amount: float) -> void:
	BaseShipStatusHelper.try_ignite_fire(self, clampf(amount / maxf(fire_threshold, 1.0), 0.0, 1.0), fire_pot_burn_duration)

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
	BaseShipBoardingRopeVisualHelper.spawn_ropes(self, count_override)

func _update_ropes(delta: float = 0.0) -> void:
	BaseShipBoardingRopeVisualHelper.update_ropes(self, delta)

func pulse_boarding_rope_feedback(intensity: float = 1.0) -> void:
	BaseShipBoardingRopeVisualHelper.pulse_feedback(self, intensity)

func _get_boarding_rope_visual_resist_ratio() -> float:
	return BaseShipBoardingRopeVisualHelper.get_visual_resist_ratio(self)

func _get_boarding_rope_source_anchor_local(side_sign: float, along_offset: float) -> Vector3:
	return BaseShipBoardingRopeVisualHelper.get_source_anchor_local(self, side_sign, along_offset)

func _get_boarding_rope_target_anchor_global(start_global: Vector3) -> Vector3:
	return BaseShipBoardingRopeVisualHelper.get_target_anchor_global(self, start_global)

func _get_boarding_rope_target_deck_half_extents(target_ship: Node3D) -> Vector2:
	return BaseShipBoardingRopeVisualHelper.get_target_deck_half_extents(target_ship)

func _get_boarding_rope_local_anchor_height(ship_node: Node) -> float:
	return BaseShipBoardingRopeVisualHelper.get_local_anchor_height(ship_node)

func _clear_ropes(reset_pull_velocity: bool = true) -> void:
	BaseShipBoardingRopeVisualHelper.clear_ropes(self, reset_pull_velocity)

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
	var my_ext: Vector2 = get_deck_half_extents()
	var target_ext: Vector2 = target_ship.get_deck_half_extents() if target_ship.has_method("get_deck_half_extents") else Vector2(2.0, 3.0)
	var size_pressure: float = maxf(0.0, (my_ext.y + target_ext.y) - 8.0)
	var contact_limit: float = clampf(0.55 + size_pressure * 0.025, 0.55, 0.72)
	var parallel_min: float = clampf(0.2 - size_pressure * 0.03, -0.05, 0.2)
	return my_contact_abs <= contact_limit and target_contact_abs <= contact_limit and parallel_dot >= parallel_min

func _is_boarding_contact_stable() -> bool:
	if not is_instance_valid(boarding_target):
		return false

	var contact_mode: String = ShipBoardingMetaHelper.get_contact_mode(self)
	if contact_mode == ShipBoardingMetaHelper.CONTACT_HEAD_ON or contact_mode == ShipBoardingMetaHelper.CONTACT_CLEANUP:
		var relaxed_state = _get_boarding_alignment_state(boarding_target)
		var closing_speed: float = float(relaxed_state.get("closing_speed", 0.0)) if not relaxed_state.is_empty() else 0.0
		var center_distance: float = global_position.distance_to(boarding_target.global_position)
		var contact_distance: float = get_collision_distance_to(boarding_target)
		var stable_distance: float = maxf(max_boarding_distance + 0.6, contact_distance + 1.0)
		return center_distance <= stable_distance and closing_speed <= boarding_max_relative_speed * 5.0

	if not _is_side_boarding_approach(boarding_target):
		return false

	var state = _get_boarding_alignment_state(boarding_target)
	if state.is_empty():
		return false
	var closing_speed: float = float(state["closing_speed"])
	return closing_speed <= boarding_max_relative_speed * 1.35

func _process_boarding_common(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	BaseShipBoardingHelper.process_boarding_common(self, delta)
	PhysicsFrameProfiler.end("ship_boarding_common", profile_start)

func _cancel_boarding() -> void:
	BaseShipBoardingHelper.cancel_boarding(self)

func _transfer_one_soldier() -> void:
	BaseShipBoardingHelper.transfer_one_soldier(self)
