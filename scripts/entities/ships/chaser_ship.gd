@tool
extends "res://scripts/entities/ships/base_ship.gd"
class_name ChaserShip
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const DEBUG_CHASER_LOGS := false
const ChaserShipBoardingHelper = preload("res://scripts/entities/ships/chaser_ship_boarding_helper.gd")
const ChaserShipMinionHelper = preload("res://scripts/entities/ships/chaser_ship_minion_helper.gd")
const ChaserShipSupportHelper = preload("res://scripts/entities/ships/chaser_ship_support_helper.gd")
const ChaserShipAiHelper = preload("res://scripts/entities/ships/chaser_ship_ai_helper.gd")
const DEFAULT_SOLDIER_SCENE_PATH := "res://scenes/entities/soldiers/soldier.tscn"
const DEFAULT_CANNON_SCENE_PATH := "res://scenes/entities/launchers/cannon_enemy_light.tscn"
const DEFAULT_HULL_SCENE_PATH := "res://scenes/ships/hulls/sekibune_hull.tscn"
const DEFAULT_FIRE_POT_SCENE_PATH := "res://scenes/projectiles/fire_pot.tscn"

## 추적선 (Chaser Ship)
## 플레이어를 단순 추적하고, 충돌 시 병사를 도선(Boarding)시키고 자폭

@export var team: String = "enemy" # "enemy" or "player"
@export var move_speed: float = 3.5
@export var soldier_scene: PackedScene
@export var boarders_count: int = 4 # 도선시킬 병사 수 (상향: 2 -> 4)

@export var cannon_scene: PackedScene
@export var hull_scene: PackedScene
@export var preferred_soldier_type: String = "general" ## "general", "melee", "ranged"
enum CombatRole {CHARGER, GUNNER}
@export var combat_role: CombatRole = CombatRole.CHARGER
@export_range(4.0, 30.0) var preferred_combat_range: float = 14.0
@export_range(0.5, 8.0) var combat_range_tolerance: float = 2.5
@export_range(2.0, 20.0) var retreat_distance: float = 8.0
@export var allow_boarding: bool = true
@export var formation_role_name: String = "":
	set(value):
		formation_role_name = value
		if not Engine.is_editor_hint() and is_node_ready():
			_apply_formation_role_profile()
@export var ship_type: String = "sekibune_melee":
	set(value):
		ship_type = value
		_apply_default_combat_profile_for_ship_type()
		if Engine.is_editor_hint():
			_update_editor_hull()
var has_cannons: bool = true ## JSON에서 로드됨

var target: Node3D = null

# 상태 (State)
var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0


@export var minion_respawn_interval: float = 15.0
@export var max_minion_crew: int = 4 # 아군 나포함 최대 정원
var minion_respawn_timer: float = 0.0

@export var max_crew: int = 6 # 적선 최대 정원
var enemy_crew_composition: Array[String] = []
var _enemy_crew_spawn_index: int = 0

# === 적 AI 조타 튜닝 ===
@export_range(0.5, 3.0) var ai_rudder_gain: float = 1.2
@export_range(20.0, 160.0) var ai_rudder_response_speed: float = 70.0
@export_range(10.0, 80.0) var ai_max_turn_rate: float = 30.0 # deg/s
@export_range(0.2, 1.0) var ai_turn_authority: float = 0.7
@export_range(4.0, 24.0) var ai_close_turn_soft_radius: float = 12.0
@export_range(0.2, 1.0) var ai_close_turn_scale: float = 0.6
@export_range(0.25, 1.5) var separation_pad_scale: float = 1.0


# === 함대 진형 (Formation) 관련 ===
enum Formation {COLUMN, WING}
static var fleet_formation: Formation = Formation.COLUMN # 공유 진형 설정 (기본: 장사진)

var formation_spacing: float = 14.0 # 선박 간 간격 축소 (밀집 대형)

var _wave_timer: float = 0.0 # 물결 소리 타이머
var _last_ai_speed: float = 0.0 # 속도 평활화를 위한 이전 프레임 속도 저장
var _oar_time: float = 0.0

# [신규] 스태미나 시스템 (돌격용)
var stamina: float = 100.0
var max_stamina: float = 100.0
var is_sprinting: bool = false
var sprint_multiplier: float = 1.5
var fire_pot_cooldown_timer: float = 0.0
var fire_pot_scene: PackedScene = null

# === 성능 최적화용 캐싱 (성능 저하 방지) ===
static var _cached_minion_list: Array = []
static var _last_minion_cache_frame: int = -1

var _cached_wind_manager: Node = null

static func get_minions_cached(_tree: SceneTree) -> Array:
	var current_frame = Engine.get_physics_frames()
	if current_frame != _last_minion_cache_frame:
		_cached_minion_list = EntityRegistry.get_captured_minions()
		_last_minion_cache_frame = current_frame
	return _cached_minion_list

static func get_ships_cached(_tree: SceneTree) -> Array:
	return ChaserShipAiHelper.get_ships_cached(_tree)


# 최적화 변수
var cached_lm: Node = null
var separation_force: Vector3 = Vector3.ZERO
var separation_timer: float = 0.0
var logic_timer: float = 0.0 # 타겟 체크 등 일반 로직용
@export_range(0.05, 0.5, 0.01) var ai_logic_update_interval: float = 0.2
@export_range(0.0, 0.15, 0.01) var ai_logic_update_jitter: float = 0.05
var _ai_logic_update_interval_runtime: float = 0.2
@export_range(0.05, 0.5, 0.01) var ai_separation_update_interval: float = 0.12
var _ai_separation_update_interval_runtime: float = 0.12

# 도선 로직 변수 (base_ship.gd에서 상속)
var has_rammed: bool = false # 중복 데미지 방지
var _merit_granted: bool = false # 공적 중복 획득 방지

func get_radius() -> float:
	return 2.5 # 대략적인 선체 반경 (상황에 맞게 조정)


func is_gunner_role() -> bool:
	return int(combat_role) == int(CombatRole.GUNNER)


func is_charger_role() -> bool:
	return not is_gunner_role()


func can_board_targets() -> bool:
	return allow_boarding

func get_target_ship() -> Node3D:
	return target if is_instance_valid(target) else null


func can_use_fire_pot_attack() -> bool:
	return false


func set_preview_target(target_ship: Node3D) -> void:
	target = target_ship


func reset_preview_fire_pot_cooldown() -> void:
	fire_pot_cooldown_timer = 0.0


func set_preview_fire_pot_enabled(enabled: bool) -> void:
	if enabled:
		return
	replace_preview_crew_role("fire_pot", "general")


func get_preferred_engagement_range() -> float:
	return preferred_combat_range


func get_engagement_range_tolerance() -> float:
	return combat_range_tolerance


func get_retreat_engagement_distance() -> float:
	return retreat_distance


func _become_derelict() -> void:
	is_boarding = false
	_clear_ropes()
	target = null
	ChaserShipSupportHelper.become_derelict(self)

func _sink_derelict() -> void:
	await ChaserShipSupportHelper.sink_derelict(self)

func _check_offscreen_despawn() -> void:
	ChaserShipSupportHelper.check_offscreen_despawn(self)

func _apply_default_combat_profile_for_ship_type() -> void:
	var type_lower := ship_type.to_lower()
	if type_lower.contains("kobayabune"):
		combat_role = CombatRole.CHARGER
		allow_boarding = true
		preferred_combat_range = 3.8
		combat_range_tolerance = 0.8
		retreat_distance = 3.0
	elif type_lower.contains("cannon") or type_lower.contains("atakebune"):
		combat_role = CombatRole.GUNNER
		allow_boarding = false
		preferred_combat_range = 14.0
		combat_range_tolerance = 2.5
		retreat_distance = 8.0
	else:
		combat_role = CombatRole.CHARGER
		allow_boarding = true
		preferred_combat_range = 4.5
		combat_range_tolerance = 1.0
		retreat_distance = 3.5

func _apply_combat_profile_from_stats(stats: Dictionary) -> void:
	if stats.has("combat_role"):
		var role_name := str(stats["combat_role"]).to_lower()
		combat_role = CombatRole.GUNNER if role_name == "gunner" else CombatRole.CHARGER
	if stats.has("allow_boarding"):
		allow_boarding = stats["allow_boarding"] == true
	if stats.has("preferred_range"):
		preferred_combat_range = float(stats["preferred_range"])
	if stats.has("range_tolerance"):
		combat_range_tolerance = float(stats["range_tolerance"])
	if stats.has("retreat_distance"):
		retreat_distance = float(stats["retreat_distance"])


func _load_enemy_crew_composition_from_stats(stats: Dictionary) -> void:
	enemy_crew_composition.clear()
	_enemy_crew_spawn_index = 0

	var composition_variant: Variant = stats.get("crew_composition", {})
	if typeof(composition_variant) != TYPE_DICTIONARY:
		return

	var composition: Dictionary = composition_variant as Dictionary
	var ordered_types: Array[String] = ["general", "melee", "ranged", "fire_pot"]
	for soldier_type_name in ordered_types:
		var count: int = int(composition.get(soldier_type_name, 0))
		for _i in range(maxi(count, 0)):
			enemy_crew_composition.append(soldier_type_name)


func _get_next_enemy_soldier_type() -> String:
	if enemy_crew_composition.is_empty():
		return preferred_soldier_type

	var composition_size: int = enemy_crew_composition.size()
	var next_type: String = enemy_crew_composition[_enemy_crew_spawn_index % composition_size]
	_enemy_crew_spawn_index = (_enemy_crew_spawn_index + 1) % composition_size
	return next_type


func _configure_spawned_soldier(soldier, soldier_type_name: String) -> void:
	if not is_instance_valid(soldier):
		return

	var normalized_type: String = soldier_type_name.strip_edges().to_lower()
	soldier.crew_role = "general"
	soldier.is_melee_only = false
	soldier.is_ranged_only = false

	match normalized_type:
		"melee":
			soldier.is_melee_only = true
		"ranged":
			soldier.is_ranged_only = true
		"fire_pot":
			soldier.crew_role = "fire_pot"

	if soldier.is_node_ready():
		soldier._apply_role_loadout()
		soldier._update_role_visual()


func _apply_formation_role_profile() -> void:
	var role_name: String = formation_role_name.strip_edges().to_lower()
	if role_name.is_empty():
		return

	match role_name:
		"vanguard":
			combat_role = CombatRole.CHARGER
			allow_boarding = true
			preferred_combat_range = 3.4
			combat_range_tolerance = 0.7
			retreat_distance = 2.8
			sprint_multiplier = 1.65
			ai_turn_authority = 0.82
			separation_pad_scale = 0.92
		"flanker":
			combat_role = CombatRole.CHARGER
			allow_boarding = true
			preferred_combat_range = 4.6
			combat_range_tolerance = 1.15
			retreat_distance = 3.1
			sprint_multiplier = 1.58
			ai_turn_authority = 0.88
			separation_pad_scale = 0.82
		"gunline":
			combat_role = CombatRole.GUNNER
			allow_boarding = false
			preferred_combat_range = 16.5
			combat_range_tolerance = 3.3
			retreat_distance = 10.0
			ai_turn_authority = 0.58
			separation_pad_scale = 1.1
		"pressure_gunner":
			combat_role = CombatRole.GUNNER
			allow_boarding = false
			preferred_combat_range = 11.5
			combat_range_tolerance = 2.0
			retreat_distance = 6.5
			ai_turn_authority = 0.76
			separation_pad_scale = 0.96

func _update_editor_hull() -> void:
	# 에디터 전용: 선체 미리보기 갱신
	for child in get_children():
		if child.name.contains("Hull"):
			child.queue_free()
	
	var stats = load_ship_stats(ship_type)
	if stats.is_empty(): return
	
	# 함종에 따른 선체 씬 경로 결정 (임시 매핑 - 나포 시스템 등에서 정의한 것과 동일하게)
	var type_lower = ship_type.to_lower()
	var h_path = "res://scenes/ships/hulls/sekibune_hull.tscn"
	if type_lower.contains("kobayabune"):
		h_path = "res://scenes/ships/hulls/kobayabune_hull.tscn"
	elif type_lower == "sekibune_melee":
		h_path = "res://scenes/ships/hulls/sekibune_melee_hull.tscn"
	elif type_lower.contains("panokseon"): h_path = "res://scenes/ships/hulls/panokseon_hull.tscn"
	elif type_lower.contains("atakebune"): h_path = "res://scenes/ships/hulls/atakebune_hull.tscn"
	elif type_lower.contains("maengseon"): h_path = "res://scenes/ships/hulls/maengseon_hull.tscn"
	
	var new_hull = load(h_path)
	if new_hull:
		var inst = new_hull.instantiate()
		inst.name = "EditorHull"
		add_child(inst)
		_cache_hull_references(self ) # BaseShip 메서드 호출

func _ready() -> void:
	_apply_default_combat_profile_for_ship_type()
	if Engine.is_editor_hint():
		# 이미 에디터용 Hull이 있다면 중복 생성 방지
		var has_hull = false
		for child in get_children():
			if child.name.contains("Hull"):
				has_hull = true
				break
		if not has_hull:
			_update_editor_hull()
		return

	# JSON 데이터 로드 및 적용
	_ensure_runtime_scene_refs()
	var stats = load_ship_stats(ship_type)
	if not stats.is_empty():
		if stats.has("hull_hp"): max_hull_hp = stats["hull_hp"]
		if stats.has("move_speed"): move_speed = stats["move_speed"]
		if stats.has("boarders"): boarders_count = stats["boarders"]
		if stats.has("has_cannons"): has_cannons = stats["has_cannons"]
		if stats.has("soldier_type"): preferred_soldier_type = stats["soldier_type"]
		_load_enemy_crew_composition_from_stats(stats)
		if stats.has("separation_pad_scale"): separation_pad_scale = float(stats["separation_pad_scale"])
		_apply_combat_profile_from_stats(stats)
	_apply_formation_role_profile()
		
	# 선체(Hull) 씬 인스턴스화 및 추가 (런타임)
	var runtime_hull_scene: PackedScene = hull_scene
	var type_lower = ship_type.to_lower()
	if type_lower.contains("kobayabune"):
		runtime_hull_scene = load("res://scenes/ships/hulls/kobayabune_hull.tscn")
	elif type_lower == "sekibune_melee":
		runtime_hull_scene = load("res://scenes/ships/hulls/sekibune_melee_hull.tscn")
	elif type_lower.contains("atakebune"):
		runtime_hull_scene = load("res://scenes/ships/hulls/atakebune_hull.tscn")
	elif type_lower.contains("sekibune"):
		runtime_hull_scene = load("res://scenes/ships/hulls/sekibune_hull.tscn")
	elif type_lower.contains("panokseon"):
		runtime_hull_scene = load("res://scenes/ships/hulls/panokseon_hull.tscn")
	elif type_lower.contains("maengseon"):
		runtime_hull_scene = load("res://scenes/ships/hulls/maengseon_hull.tscn")
	if is_instance_valid(runtime_hull_scene):
		var hull_inst = runtime_hull_scene.instantiate()
		add_child(hull_inst)
	else:
		_update_editor_hull()
		
	super._ready()
	if max_hull_hp <= 0: max_hull_hp = 60.0 # Default fallback
	global_position.y = base_y # Keep base_y assignment from BaseShip valid
	_find_player()
	
	# 대포 없는 함선(Chaser)일 경우 자식 중 Cannon 노드들 제거
	if not has_cannons:
		_remove_all_cannons()
	
	# 초기 돛 색상 설정 (Enemy 기본: Red)
	for mast in masts:
		if mast.has_method("set_sail_color"):
			mast.set_sail_color(Color(0.7, 0.1, 0.1, 1.0))
		if mast.has_method("set_team_color"):
			mast.set_team_color("enemy")
	add_to_group("ships")
	set_team(team)
	if team == "player":
		add_to_group("captured_minion")
		EntityRegistry.register_captured_minion(self)
		_apply_minion_visuals()
		_equip_minion_cannons()
		var upgrade_manager = get_node_or_null("/root/UpgradeManager")
		if is_instance_valid(upgrade_manager):
			upgrade_manager.apply_fleet_upgrades_to_ship(self )
	else:
		if is_in_group("captured_minion"):
			remove_from_group("captured_minion")
		EntityRegistry.unregister_captured_minion(self)
	
	_setup_soldiers() # 모든 함선 초기 병사 배치 (팀 속성 반영)
		
	_find_player()
	
	cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	
	_cached_wind_manager = get_node_or_null("/root/WindManager")
	_sync_contact_area_layers()
	_set_contact_areas_enabled(true)
	_configure_ai_logic_throttle()


func _ensure_runtime_scene_refs() -> void:
	if soldier_scene == null:
		soldier_scene = _load_packed_scene(DEFAULT_SOLDIER_SCENE_PATH)
	if cannon_scene == null:
		cannon_scene = _load_packed_scene(DEFAULT_CANNON_SCENE_PATH)
	if hull_scene == null:
		hull_scene = _load_packed_scene(DEFAULT_HULL_SCENE_PATH)
	if fire_pot_scene == null:
		fire_pot_scene = _load_packed_scene(DEFAULT_FIRE_POT_SCENE_PATH)


func _load_packed_scene(path: String) -> PackedScene:
	var loaded_resource: Resource = load(path)
	return loaded_resource as PackedScene if loaded_resource is PackedScene else null

func _sync_contact_area_layers(layer_override: int = -1) -> void:
	var current_layer: int = layer_override
	if current_layer < 0:
		var layer_val = get("collision_layer")
		current_layer = int(layer_val) if layer_val != null else 4
	var proximity_area = get_node_or_null("ProximityArea")
	if proximity_area is Area3D:
		proximity_area.set_deferred("collision_layer", current_layer)
		# 도선/접근 감지는 플레이어 레이어(2)만 본다.
		proximity_area.set_deferred("collision_mask", 2)
		
	var hit_area = get_node_or_null("HitArea")
	if hit_area is Area3D:
		hit_area.set_deferred("collision_layer", current_layer)
		# 피격 영역은 다른 Area를 능동 감지할 필요가 없다.
		hit_area.set_deferred("collision_mask", 0)

func _set_contact_areas_enabled(enabled: bool) -> void:
	var proximity_area = get_node_or_null("ProximityArea")
	if proximity_area is Area3D:
		proximity_area.set_deferred("monitoring", enabled)
		proximity_area.set_deferred("monitorable", enabled)
		var prox_shape = proximity_area.get_node_or_null("CollisionShape3D")
		if prox_shape is CollisionShape3D:
			prox_shape.set_deferred("disabled", not enabled)
			
	var hit_area = get_node_or_null("HitArea")
	if hit_area is Area3D:
		hit_area.set_deferred("monitoring", enabled)
		hit_area.set_deferred("monitorable", enabled)
		var hit_shape = hit_area.get_node_or_null("CollisionShape3D")
		if hit_shape is CollisionShape3D:
			hit_shape.set_deferred("disabled", not enabled)

func _setup_soldiers() -> void:
	if not soldier_scene: return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	# ✅ 기존에 씬에 배치된 병사가 있다면 제거 (중복 및 팀 믹스 방지)
	for child in soldiers_node.get_children():
		child.queue_free()
	
	# 함선 팀에 맞춰 초기 4명 배치
	for i in range(4):
		_spawn_one_soldier(team)

func _spawn_one_soldier(s_team: String, soldier_type_override: String = "") -> void:
	var s = soldier_scene.instantiate()
	var soldier_type_name: String = soldier_type_override.strip_edges().to_lower()
	if soldier_type_name.is_empty():
		if s_team == "enemy":
			soldier_type_name = _get_next_enemy_soldier_type()
		else:
			soldier_type_name = preferred_soldier_type

	s.team = s_team
	s.owned_ship = self
	s.home_ship = self
	_configure_spawned_soldier(s, soldier_type_name)
	$Soldiers.add_child(s)
	s.set_team(s_team)
	_configure_spawned_soldier(s, soldier_type_name)
		
	var offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-2.5, 2.5))
	s.position = offset


func die() -> void:
	if is_dying: return
	is_dying = true
	
	# ✅ 배 위의 병사들을 원래 배로 복귀시키고, 복귀 불가 시 생존자로 전환
	_evacuate_soldiers_to_home()
	_evacuate_player_soldiers_as_survivors()
	
	# 밧줄 및 도선 공격자 정보 제거
	if is_instance_valid(boarding_target) and boarding_target.has_method("get_boarding_attacker_ship") and boarding_target.get_boarding_attacker_ship() == self:
		boarding_target.clear_boarding_attacker_ship()
	_clear_ropes()
	
	# 침몰 시작 시 타겟 그룹에서 제외 (대포가 시체를 쏘지 않게 함)
	if is_in_group("enemy"):
		remove_from_group("enemy")
	if is_in_group("player"):
		remove_from_group("player")
	if is_in_group("captured_minion"):
		remove_from_group("captured_minion")
	EntityRegistry.unregister_captured_minion(self)
	
	# 점수 및 XP 추가
	if is_instance_valid(cached_lm):
		if team == "enemy" and cached_lm.has_method("add_ship_sunk"):
			cached_lm.add_ship_sunk(1)
		if cached_lm.has_method("add_score"):
			cached_lm.add_score(80)
		if cached_lm.has_method("add_xp"):
			cached_lm.add_xp(30)
			
		# 공적 포인트(Merit) 추가 (격침 시에도 부여, 중복 방지)
		if not _merit_granted and cached_lm.has_method("add_merit"):
			cached_lm.add_merit(20)
			_merit_granted = true
	
		# 물리 및 충돌 비활성화 (Area3D 대응)
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		_set_contact_areas_enabled(false)
			
		# 항적 끄기
		_set_wake_state(false)
		
	# 가라앉는 연출 (침몰 애니메이션)
	var sink_tween = create_tween()
	sink_tween.set_parallel(true)
	
	# 무작위 기울기
	var tilt_x = randf_range(-15.0, 15.0)
	var tilt_z = randf_range(-10.0, 10.0)
	sink_tween.tween_property(self , "rotation_degrees:x", tilt_x, 3.0).set_ease(Tween.EASE_OUT)
	sink_tween.tween_property(self , "rotation_degrees:z", tilt_z, 3.0).set_ease(Tween.EASE_OUT)
	
	# 아래로 깊게 가라앉음 + 페이드 아웃
	var sink_duration = 6.0
	sink_tween.tween_property(self , "global_position:y", global_position.y - 15.0, sink_duration).set_ease(Tween.EASE_IN)
	
	# (메쉬 투명도 조절 대신 셰이더 수심 효과로 대체)
	
	leaking_rate = 0.0 # 사망 시 누수 중단
	
	_drop_floating_loot()
	
	sink_tween.set_parallel(false)
	sink_tween.tween_callback(queue_free)


func _drop_floating_loot() -> void:
	ChaserShipSupportHelper.drop_floating_loot(self)

## 침몰 시 배 위의 아군(player) 병사를 Survivor로 전환
func _evacuate_player_soldiers_as_survivors() -> void:
	ChaserShipSupportHelper.evacuate_player_soldiers_as_survivors(self)

## 침몰 시 배 위의 병사들을 원래 배(home_ship)로 복귀시킴
func _evacuate_soldiers_to_home() -> void:
	ChaserShipSupportHelper.evacuate_soldiers_to_home(self)


## 생존자 구조 및 병사 합류 처리 (나포함용)
func add_survivor() -> bool:
	if is_dying: return false
	
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return false
	
	# 현재 살아있는 병사 수 체크
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4: # NOT DEAD
			alive_count += 1
		else:
			child.queue_free() # 시체 정리
			
	# 나포함 전용 정원(max_minion_crew) 체크
	if alive_count >= max_minion_crew:
		print("[Rescue] 정원 초과 합류! (현재 인원: %d/%d)" % [alive_count + 1, max_minion_crew])
		# 정원 초과 시에도 합류는 허용하여 생존자가 배에 부딪혀 튕겨나가는 것을 방지함
		
	# 병사 생성
	var s = soldier_scene.instantiate()
	soldiers_node.add_child(s)
	s.set_team("player")
	
	# 위치 설정 (갑판 위 랜덤)
	var offset = Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-1.5, 1.5))
	s.position = offset
	
	print("[Crew] 나포함이 생존자를 구조했습니다! (현재: %d/%d)" % [alive_count + 1, max_minion_crew])
	return true

func _process(delta: float) -> void:
	if is_dying: return
	
	_update_fire_effect()
	_auto_adjust_sail(delta)
	_update_sail_visual()
	_update_oar_visual(delta)
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	_update_boarding_state(delta)
	_update_enemy_fire_pot_logic(delta)
	
	if is_derelict:
		leaking_rate += 0.2 * delta
		# 폐선 상태일 때는 타겟 초기화 (공격 중단)
		target = null
		
	if team == "player":
		_update_minion_respawn(delta)

	_update_leaking_damage(delta)



func _update_leaking_damage(delta: float) -> void:
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
		return
	_leak_tick_timer += delta
	while _leak_tick_timer >= 1.0:
		_leak_tick_timer -= 1.0
		take_damage(leaking_rate, global_position, "leak")


func _update_enemy_fire_pot_logic(delta: float) -> void:
	if not can_use_fire_pot_attack():
		return
	ChaserShipSupportHelper.update_enemy_fire_pot_logic(self, delta)


func _physics_process(delta: float) -> void:
	ChaserShipAiHelper.process_physics(self, delta)

func _update_logic_throttled() -> void:
	ChaserShipAiHelper.update_logic_throttled(self)


func _configure_ai_logic_throttle() -> void:
	ChaserShipAiHelper.configure_logic_throttle(self)


func get_ai_logic_update_interval() -> float:
	return ChaserShipAiHelper.get_logic_update_interval_for_ship(self)


func get_ai_separation_update_interval() -> float:
	return ChaserShipAiHelper.get_separation_update_interval_for_ship(self)

## 주변 함선들로부터 멀어지려는 힘 계산
func _calculate_separation() -> Vector3:
	return ChaserShipAiHelper.calculate_separation(self)

func _process_boarding(delta: float) -> void:
	ChaserShipBoardingHelper.process_boarding(self, delta)

func _apply_neighbor_ship_guards(prev_pos: Vector3, proposed_pos: Vector3, excluded_ship: Node3D = null) -> Vector3:
	return ChaserShipBoardingHelper.apply_neighbor_ship_guards(self, prev_pos, proposed_pos, excluded_ship)

func _apply_ship_collision_guard(other_ship: Node3D, prev_pos: Vector3, proposed_pos: Vector3, safe_ratio: float = 0.94, impact_speed_hint: float = 0.0, emit_collision_event: bool = true) -> Vector3:
	return ChaserShipBoardingHelper.apply_ship_collision_guard(self, other_ship, prev_pos, proposed_pos, safe_ratio, impact_speed_hint, emit_collision_event)

func _emit_guarded_collision(other_ship: Node3D, impact_speed_hint: float) -> void:
	ChaserShipBoardingHelper.emit_guarded_collision(self, other_ship, impact_speed_hint)

func _soften_collision_speed() -> void:
	ChaserShipBoardingHelper.soften_collision_speed(self)


func _find_player() -> void:
	ChaserShipAiHelper.find_player(self)

## 나포(Capture) 처리
func capture_ship() -> void:
	if team == "player": return
	
	# 기존 함대 수 체크 (정예 함선 1척 체제)
	if EntityRegistry.count_captured_minions() >= 1:
		# ✅ 정원 초과 시 나포 대신 배를 파괴함
		print("[Limitation] 함대 정원 초과! 적함을 파괴합니다.")
		die()
		return
			
	set_team("player")
	
	# ✅ 상태 초기화 및 긴급 수리 (나포 후 즉시 가라앉는 현상 방지)
	is_dying = false
	is_derelict = false
	is_burning = false
	fire_build_up = 0.0
	leaking_rate = 0.0
	hull_hp = max(hull_hp, max_hull_hp * 0.3) # 최소 30% 체력으로 복구
	
	# ✅ 나포 완료 시 도선 상태 및 밧줄 강제 해제 (공격자/방어자 모두)
	_cancel_boarding()
	if is_instance_valid(boarding_attacker):
		boarding_attacker._cancel_boarding()
		boarding_attacker = null
	
	# 철저한 물리적/시각적 리셋 (잠수함화 및 기울기 고정 방지)
	tilt_offset = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	base_y = 0.0 # 수면 높이 기준점 재설정
	global_position.y = 0.0
	
	# 실행 중일 수 있는 모든 트윈 애니메이션(침몰 모션 등) 강제 종료
	var tweens = get_tree().get_processed_tweens()
	for tween in tweens:
		# 이 노드나 관련 속성을 다루는 트윈이라고 확신할 순 없지만
		# Godot 4에서는 bind_node를 통해 엮인 트윈은 자동으로 정리되긴 함
		pass
	# 대신 명시적으로 y 위치를 고정해버림
	
	# (is_boarding, boarding_target, _clear_ropes 등은 _cancel_boarding()에서 이미 처리됨)
	
	# 플레이어의 현재 업그레이드된 최대 속도를 상속받아 평준화 (기본치 3.2 대신)
	var players = EntityRegistry.get_ships_by_team("player")
	if players.size() > 0 and players[0].get("is_player_controlled"):
		move_speed = players[0].get("max_speed")
	else:
		move_speed = 10.0 # 하드코딩된 예비값
	
	if not is_in_group("captured_minion"):
		add_to_group("captured_minion")
		EntityRegistry.register_captured_minion(self)

	
	# 자식들(대포, 병사) 팀 변경 및 UI 알림
	_update_children_team_for_capture()
	_refresh_deck_light()
	_apply_minion_visuals()

	if is_instance_valid(cached_lm):
		var capture_score_reward: int = max(0, int(cached_lm.get("boarding_capture_score_reward")))
		var capture_xp_reward: int = max(0, int(cached_lm.get("boarding_capture_xp_reward")))
		var capture_merit_reward: int = max(0, int(cached_lm.get("boarding_capture_merit_reward")))
		if capture_score_reward > 0 and cached_lm.has_method("add_score"):
			cached_lm.add_score(capture_score_reward)
		if capture_xp_reward > 0 and cached_lm.has_method("add_xp"):
			cached_lm.add_xp(capture_xp_reward)
		if capture_merit_reward > 0 and cached_lm.has_method("add_merit"):
			cached_lm.add_merit(capture_merit_reward)
	
	if is_instance_valid(cached_lm) and cached_lm.has_method("show_message"):
		cached_lm.show_message("적군 함선을 나포했습니다!", 3.0)
	
	# 플레이어 업그레이드 스탯 적용 (수리 등)
	var upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("apply_fleet_stats_to_minion"):
		upgrade_manager.apply_fleet_stats_to_minion(self )
	
	# 나포 직후 플레이어를 찾아 즉시 따라가기 시작
	target = null
	_find_player()
	
	# ✅ 나포함 무장 자동 장착 및 현재 함대 업그레이드 적용
	_equip_minion_cannons()
	upgrade_manager = get_node_or_null("/root/UpgradeManager")
	if is_instance_valid(upgrade_manager):
		upgrade_manager.apply_fleet_upgrades_to_ship(self )
		
	print("[Capture] 나포 성공! 함대에 합류합니다. (target: %s)" % str(target))

func _equip_minion_cannons() -> void:
	if not cannon_scene: return
	
	# 중복 방지: 선체에 미리 달려있는 대포가 있다면 제거 후 FleetCannon으로 통일
	_remove_all_cannons()
	
	# 장착 위치 정의 (전방, 좌측, 우측)
	var spawn_points = [
		{"pos": Vector3(0, 0.8, -3.5), "rot": 0}, # 전방
		{"pos": Vector3(-1.0, 0.8, -0.5), "rot": 90}, # 좌측 (90도 회전)
		{"pos": Vector3(1.0, 0.8, -0.5), "rot": - 90} # 우측 (-90도 회전)
	]
	
	var i = 0
	for p in spawn_points:
		var cannon = cannon_scene.instantiate()
		cannon.name = "FleetCannon_" + str(i)
		add_child(cannon)
		cannon.position = p["pos"]
		cannon.rotation_degrees.y = p["rot"]
		# 팀 설정
		if cannon.has_method("set_team"):
			cannon.set_team("player")
		
		# 초기 레벨에선 전방 대포(index 0) 외에는 비활성
		if i > 0:
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)
		i += 1

func _update_children_team_for_capture() -> void:
	# 나포 시에 명시적으로 다시 한 번 호출 (BaseShip의 것을 사용)
	_update_children_team()
	
	# 병사 팀 변경
	for s in $Soldiers.get_children():
		if s.has_method("set_team"):
			s.set_team("player")
			s.owned_ship = self

func _remove_all_cannons() -> void:
	# 선체 내부에 포함된 대포들까지 모두 찾아서 제거
	_recursive_remove_cannons(self )

func _recursive_remove_cannons(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("fire") or "cannonball_scene" in child: # 대포 노드 판별
			child.queue_free()
		else:
			_recursive_remove_cannons(child)

func _apply_minion_visuals() -> void:
	# 돛 색상 변경 (흰색/파란색 조화) - instance uniform 사용
	for mast in masts:
		if mast.has_method("set_sail_color"):
			mast.set_sail_color(Color(0.9, 0.9, 1.0, 1.0)) # 밝은 하늘색/흰색
		if mast.has_method("set_team_color"):
			mast.set_team_color("player")
			
	# 연기 효과 중지 (폐선 상태에서 났던 것)
	if is_instance_valid(_fire_instance):
		_set_fire_emitting(false)


func _auto_adjust_sail(delta: float) -> void:
	if not is_instance_valid(_cached_wind_manager) or not _cached_wind_manager.has_method("get_wind_direction"):
		return
	var wind_dir = _cached_wind_manager.get_wind_direction()

	# 플레이어 배와 같은 기준으로 상대풍을 계산해 돛이 바람을 향해 자연스럽게 따라가게 한다.
	var wind_angle = rad_to_deg(atan2(wind_dir.x, -wind_dir.y))
	var ship_angle_ccw = rad_to_deg(rotation.y)
	var rel_wind_angle = wrapf(wind_angle + ship_angle_ccw, -180.0, 180.0)
	var target_sail_angle = clamp(rel_wind_angle / 2.0, -90.0, 90.0)
	sail_angle = move_toward(sail_angle, target_sail_angle, 60.0 * delta)

## 동양식 노(Ro/Yuloh) 8자 젓기 애니메이션
func _update_oar_visual(delta: float) -> void:
	var has_oars = oar_pivot_left or oar_pivot_right
	if not has_oars: return
	
	var is_moving = not is_derelict and move_speed > 0.5 and is_instance_valid(target)
	
	if is_moving:
		# 적함은 조금 더 느리고 장중하게 노를 저음 (돌격 시 2배 가속)
		var oar_speed = 3.6 if is_sprinting else 1.8
		_oar_time += delta * oar_speed
		
		# 8자 모션 (Lissajous curve 기반 Sculling)
		var sweep_angle = sin(_oar_time) * 0.2
		var twist_angle = sin(_oar_time * 2.0) * 0.1
		
		if oar_pivot_left:
			oar_pivot_left.rotation.x = sweep_angle
			oar_pivot_left.rotation.z = twist_angle
		if oar_pivot_right:
			oar_pivot_right.rotation.x = sweep_angle
			oar_pivot_right.rotation.z = - twist_angle
	else:
		if oar_pivot_left:
			oar_pivot_left.rotation.x = lerp_angle(oar_pivot_left.rotation.x, 0.0, delta * 2.0)
			oar_pivot_left.rotation.z = lerp_angle(oar_pivot_left.rotation.z, 0.0, delta * 2.0)
		if oar_pivot_right:
			oar_pivot_right.rotation.x = lerp_angle(oar_pivot_right.rotation.x, 0.0, delta * 2.0)
			oar_pivot_right.rotation.z = lerp_angle(oar_pivot_right.rotation.z, 0.0, delta * 2.0)

## 나포함 AI 로직 (플레이어 호위 및 적 탐지)
func _process_minion_ai(delta: float) -> void:
	ChaserShipMinionHelper.process_minion_ai(self, delta)

func _update_wave_sounds(delta: float) -> void:
	ChaserShipAiHelper.update_wave_sounds(self, delta)

func _update_minion_respawn(delta: float) -> void:
	if deck_is_contested:
		return
	var soldiers_node = get_node_or_null("Soldiers")
	if not soldiers_node: return
	
	var alive_count = 0
	for child in soldiers_node.get_children():
		if child.get("current_state") != 4: # NOT DEAD
			alive_count += 1
			
	if alive_count < max_minion_crew:
		minion_respawn_timer += delta
		if minion_respawn_timer >= minion_respawn_interval:
			minion_respawn_timer = 0.0
			_respawn_minion_soldier()

func _respawn_minion_soldier() -> void:
	_spawn_one_soldier("player")
	print("[Crew] 나포함 병사 자생적 보충 완료.")


## 충돌 감지 (Area3D signal 연결 필요)
## 함대 업그레이드 (대포 수량 조절 등)
func apply_fleet_weapon_upgrade(level: int) -> void:
	# 대포 노드들 찾기
	var cannons = []
	for child in get_children():
		if child.name.begins_with("FleetCannon_"):
			cannons.append(child)
	
	# 레벨에 따라 활성화 (Lv1: 1문, Lv2: 2문, Lv3+: 3문)
	var active_count = 1
	if level >= 2: active_count = 2
	if level >= 3: active_count = 3
	
	for i in range(cannons.size()):
		var cannon = cannons[i]
		if i < active_count:
			cannon.visible = true
			cannon.set_process(true)
			cannon.set_physics_process(true)
		else:
			cannon.visible = false
			cannon.set_process(false)
			cannon.set_physics_process(false)
	
	print("[Fleet] 함대 무장 업그레이드 적용: Lv.%d (대포 %d문 활성화)" % [level, active_count])


## 함선 수리 (초요기/공적 보너스)
func repair_ship(percent: float) -> void:
	var amt = max_hull_hp * percent
	hull_hp = minf(hull_hp + amt, max_hull_hp)
	print("[Fleet] 함선 수리됨: +%d HP" % amt)


func _on_body_entered(body: Node3D) -> void:
	if not can_board_targets():
		return
	# 플레이어와 충돌했는지 확인 (StaticBody/CharacterBody 등)
	if body.is_in_group("player") or (body.get_parent() and body.get_parent().is_in_group("player")):
		_board_ship(body)

func _on_area_entered(area: Area3D) -> void:
	if not can_board_targets():
		return
	# 피격용 히트박스는 도선 트리거에서 제외
	if area.is_in_group("ship_hitbox"):
		return
	
	# 플레이어 선박의 접근 영역과 접촉했는지 확인
	if area.is_in_group("player"):
		_board_ship(area)
	elif area.is_in_group("ship_proximity"):
		var role_parent = area.get_parent()
		if role_parent and role_parent.is_in_group("player"):
			_board_ship(role_parent)


func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0

func _board_ship(target_ship: Node3D) -> void:
	if not can_board_targets():
		return
	if is_dying or is_boarding: return
	
	# 생존 병사가 없으면 도선 시도 불가
	if get_alive_crew_count() <= 0:
		return
	
	var ship_node = target_ship
	if not ship_node.is_in_group("player"):
		ship_node = target_ship.get_parent()
		if not (ship_node and ship_node.is_in_group("player")):
			return
			
	# === 아군 체크 (동일 팀이면 도선 무시) ===
	if ship_node.get("team") == team:
		return
		
	# === 플레이어 팀 체크 (상대 배에 올라타는 것 제한) ===
	# 나포(Capture) 상황이 아닌 일반 전투 중에는 아군 병사가 적선으로 넘어가지 않게 함
	if team == "player":
		return

	# === 무력화(폐선) 상태인 배는 이미 도선이 불필요함 (나포는 player_ship.gd의 boarding scan으로 처리) ===
	if is_derelict:
		return

	# 선미 추격이나 정면 비비기에서 바로 밧줄이 걸리지 않도록,
	# 측면 접현이 성립할 때만 실제 도선 상태로 들어간다.
	if not _is_side_boarding_approach(ship_node):
		return

	# 1. 초기 충돌 효과 (최초 1회만)
	if not has_rammed:
		has_rammed = true
		if DEBUG_COMBAT_LOGS:
			print("[Impact] 충돌 발생! 도선 시작.")
		
	# 2. 도선(Boarding) 연결 로직
	if ship_node != boarding_target:
		boarding_target = ship_node

	# 2. 도선 상태 진입 (조건부)
	var my_crew = get_alive_crew_count()
	var enemy_crew = 0
	if ship_node.has_method("get_alive_crew_count"):
		enemy_crew = ship_node.get_alive_crew_count()
		
	if my_crew > enemy_crew:
		is_boarding = true
		boarding_target = ship_node
		
		# 도선 대상에게 내가 공격자임을 알림 (사격 중지 규칙용)
		if boarding_target.has_method("set_boarding_attacker_ship"):
			boarding_target.set_boarding_attacker_ship(self)
			
		_clear_ropes()
		boarding_timer = 0.0
		boarding_prep_timer = 0.0
		boarding_contact_timer = 0.0
		boarding_hook_timer = 0.0
		boarding_secondary_rope_timer = 0.0
		_initial_rope_deployed = false
		_full_rope_deployed = false
		
		if DEBUG_COMBAT_LOGS:
			print("[Boarding] 병력 우위! 접현 후 갈고리 투척을 준비합니다. (아군 %d vs 적군 %d)" % [my_crew, enemy_crew])
	else:
		if DEBUG_COMBAT_LOGS:
			print("[Skirmish] 병력 우위 부족으로 도선하지 않고 대치합니다. (아군 %d vs 적군 %d)" % [my_crew, enemy_crew])

# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
	print("[Status] 누수 완화. 남은 누수율: %.1f" % leaking_rate)
