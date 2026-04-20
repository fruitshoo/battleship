@tool
extends "res://scripts/entities/ships/base_ship.gd"
const LevelManagerRegistry = preload("res://scripts/helpers/level_manager_registry.gd")
const ShipTargetingHelper = preload("res://scripts/entities/ships/ship_targeting_helper.gd")
const BossSoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")
const FlagStyleLibrary = preload("res://scripts/props/flag_style_library.gd")
const DebugDrawBridge = preload("res://scripts/helpers/debug_draw_bridge.gd")
const ShipAILimboKeys = preload("res://scripts/ai/limbo/ship_ai_limbo_keys.gd")
const ShipLimboAIPilot = preload("res://scripts/ai/limbo/ship_limbo_ai_pilot.gd")

## 보스 함선 (Boss Ship)
## 거대한 체력, 다수의 포대, 선회 포격 AI

signal boss_died

@export var team: String = "enemy"
@export var move_speed: float = 3.0
@export var orbit_distance: float = 35.0 # 플레이어 주변을 도는 거리
@export_range(0.0, 1.0, 0.01) var orbit_inward_bias: float = 0.34 # 선회 중에도 플레이어 쪽으로 얼마나 파고들지
@export var cannon_scene: PackedScene = preload("res://scenes/entities/launchers/cannon_enemy_heavy.tscn")
@export var singigeon_scene: PackedScene = preload("res://scenes/entities/launchers/singigeon_launcher.tscn")
@export var soldier_scene: PackedScene = preload("res://scenes/entities/soldiers/soldier.tscn")
@export var hull_scene: PackedScene = preload("res://scenes/ships/hulls/atakebune_hull.tscn")
@export var chest_scene: PackedScene = preload("res://scenes/effects/treasure_chest.tscn")
@export var limbo_ai_pilot_enabled: bool = true
@export_file("*.tres") var limbo_ai_pilot_tree_path: String = ShipLimboAIPilot.DEFAULT_TREE_PATH

var target: Node3D = null
var orbit_angle: float = 0.0
var leaking_rate: float = 0.0
var _leak_tick_timer: float = 0.0
var cached_lm: Node = null
var _merit_granted: bool = false
var _victory_reported: bool = false
var _victory_report_retry_count: int = 0
var _defeat_flourish_started: bool = false
var crew_composition: Array[String] = []
var _base_move_speed: float = 0.0
var _base_orbit_inward_bias: float = 0.0

@export var ship_type: String = "atakebune_mid":
	set(value):
		ship_type = value
		if Engine.is_editor_hint():
			_update_editor_hull()
@export var tier: int = 1 ## 1: 중간 보스 (Front/L/R 1개씩), 2: 최종 보스 (고화력)

func _update_editor_hull() -> void:
	for child in get_children():
		if child.name.contains("Hull"):
			child.queue_free()
			
	var stats = load_ship_stats(ship_type)
	if stats.is_empty(): return
	
	var new_hull := ShipBlueprintHelper.load_hull_scene(ship_type, hull_scene, stats)
	if new_hull:
		var inst = new_hull.instantiate()
		inst.name = "EditorHull"
		add_child(inst)
		_cache_hull_references(self )

func _ready() -> void:
	if Engine.is_editor_hint():
		var has_hull = false
		for child in get_children():
			if child.name.contains("Hull"):
				has_hull = true
				break
		if not has_hull:
			_update_editor_hull()
		_cache_hull_references(self)
		_refresh_collision_bounds_from_hull()
		return

	# JSON 데이터 로드 및 적용
	var stats = load_ship_stats(ship_type)
	if not stats.is_empty():
		ShipBlueprintHelper.apply_boss_stats(self, stats)
		_load_crew_composition_from_stats(stats)
		if tier == 1:
			orbit_inward_bias = 0.42
		else:
			orbit_inward_bias = 0.32

	# 선체(Hull) 씬 인스턴스화 및 추가
	var runtime_hull_scene := ShipBlueprintHelper.load_hull_scene(ship_type, hull_scene, stats)
	if is_instance_valid(runtime_hull_scene):
		var hull_inst = runtime_hull_scene.instantiate()
		add_child(hull_inst)
	else:
		_update_editor_hull()
		
	super._ready()
	hull_hp = max_hull_hp
	_cache_limbo_base_combat_values()
	set_team(team)
	_apply_boss_flag_style()
	add_to_group("boss")
	add_to_group("ships")
	_find_player()
	
	cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
		
	_setup_weapons()
	_setup_soldiers()
	_update_boss_hp_hud()
	call_deferred("_update_boss_hp_hud")

func _apply_boss_flag_style() -> void:
	for mast in masts:
		if mast.has_method("set_flag_style"):
			mast.set_flag_style(FlagStyleLibrary.STYLE_BOSS)
		elif mast.has_method("set_team_color"):
			mast.set_team_color(team)


func _setup_weapons() -> void:
	# 다수의 대포 배치
	var cannons_node = Node3D.new()
	cannons_node.name = NODE_CANNONS
	add_child(cannons_node)
	var stats := ShipBlueprintHelper.load_stats(ship_type)
	var loadout := ShipWeaponLoadoutHelper.get_weapon_loadout(stats, ShipWeaponLoadoutHelper.get_default_boss_loadout(tier))
	loadout = ShipWeaponLoadoutHelper.apply_authored_weapon_slots(self, cannons_node, loadout)
	for spec in loadout:
		match ShipWeaponLoadoutHelper.get_kind(spec):
			ShipWeaponLoadoutHelper.KIND_CANNON:
				_spawn_boss_cannon(cannons_node, spec)
			ShipWeaponLoadoutHelper.KIND_SINGIGEON:
				_spawn_boss_singigeon(spec)

func _spawn_boss_cannon(container: Node, spec: Dictionary) -> void:
	var c = ShipWeaponLoadoutHelper.instantiate_weapon(spec, cannon_scene)
	if not is_instance_valid(c):
		return
	c.name = ShipWeaponLoadoutHelper.get_node_name(spec, "BossCannon")
	container.add_child(c)
	if c is Node3D:
		var cannon_node := c as Node3D
		cannon_node.position = ShipWeaponLoadoutHelper.get_position(spec)
		if ShipWeaponLoadoutHelper.has_basis(spec):
			cannon_node.rotation = ShipWeaponLoadoutHelper.get_basis(spec).get_euler()
		else:
			cannon_node.rotation_degrees.y = ShipWeaponLoadoutHelper.get_rotation_y(spec)
	ShipWeaponLoadoutHelper.apply_weapon_config(c, spec, "enemy")

func _spawn_boss_singigeon(spec: Dictionary) -> void:
	var singigeon = ShipWeaponLoadoutHelper.instantiate_weapon(spec, singigeon_scene)
	if not is_instance_valid(singigeon):
		return
	singigeon.name = ShipWeaponLoadoutHelper.get_node_name(spec, "BossSingigeon")
	add_child(singigeon)
	if singigeon is Node3D:
		var singigeon_node := singigeon as Node3D
		singigeon_node.position = ShipWeaponLoadoutHelper.get_position(spec)
		if ShipWeaponLoadoutHelper.has_basis(spec):
			singigeon_node.rotation = ShipWeaponLoadoutHelper.get_basis(spec).get_euler()
		else:
			singigeon_node.rotation_degrees.y = ShipWeaponLoadoutHelper.get_rotation_y(spec)
	ShipWeaponLoadoutHelper.apply_weapon_config(singigeon, spec, "enemy")

func _setup_soldiers() -> void:
	if not soldier_scene: return
	
	var soldiers_node = get_soldiers_container()
	if not soldiers_node:
		soldiers_node = Node3D.new()
		soldiers_node.name = NODE_SOLDIERS
		add_child(soldiers_node)
		soldiers_node.position = Vector3(0, 1.0, 0)
	
	var spawn_points: Array[Vector3] = _get_boss_soldier_spawn_points(maxi(crew_composition.size(), 4))
	
	var i = 0
	for pos in spawn_points:
		var s = soldier_scene.instantiate()
		var soldier_type_name: String = _get_crew_type_for_index(i)
		s.team = "enemy"
		s.owned_ship = self
		s.home_ship = self
		_configure_boss_soldier(s, soldier_type_name)
		s.position = pos
		
		# 보스 병사는 엘리트급 체력/데미지 보너스
		s.max_health = 150.0
		s.current_health = s.max_health
		s.attack_damage = 15.0
			
		soldiers_node.add_child(s)
		s.set_team("enemy")
		_configure_boss_soldier(s, soldier_type_name)
		i += 1


func _load_crew_composition_from_stats(stats: Dictionary) -> void:
	crew_composition = ShipBlueprintHelper.build_crew_composition(stats)


func _get_boss_soldier_spawn_points(required_count: int) -> Array[Vector3]:
	var base_points: Array[Vector3] = [
		Vector3(-1.5, 0, -3),
		Vector3(1.5, 0, -3),
		Vector3(-1.5, 0, 3),
		Vector3(1.5, 0, 3),
		Vector3(0.0, 0, -1.5),
		Vector3(0.0, 0, 1.5),
		Vector3(-2.2, 0, 0.0),
		Vector3(2.2, 0, 0.0),
	]
	return base_points.slice(0, clampi(required_count, 1, base_points.size()))


func _get_crew_type_for_index(index: int) -> String:
	if crew_composition.is_empty():
		return "ranged" if index % 2 == 0 else "general"
	return crew_composition[index % crew_composition.size()]


func _configure_boss_soldier(soldier, soldier_type_name: String) -> void:
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

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if is_dying: return
	
	_update_fire_effect()
	_update_sail_visual()
	_update_burning_status(delta)
	_update_hull_regeneration(delta)
	_update_rigging_recovery(delta)
	_update_boarding_state(delta)
	_update_limbo_ai_pilot(delta)
	
	if not is_instance_valid(target) or target.get("is_sinking") == true or target.get("is_dying") == true or target.get("is_dead") == true:
		target = null
		_find_player()
		_set_wake_state(false)
		return
		
	# === 선회(Orbiting) AI ===
	# 플레이어를 중심으로 원을 그리며 이동
	var to_player = target.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() <= 0.001:
		_set_wake_state(false)
		return
	to_player = to_player.normalized()
	var dist = global_position.distance_to(target.global_position)
	
	# 거리가 너무 멀면 접근, 적절하면 선회, 너무 가까우면 뒤로
	var move_dir = Vector3.ZERO
	var range_intent := _get_limbo_range_intent()
	var stance := _get_limbo_stance()
	var orbit_dir := Vector3(-to_player.z, 0, to_player.x)
	if range_intent == ShipAILimboKeys.INTENT_CLOSE_DISTANCE:
		move_dir = _get_limbo_close_move_dir(to_player, orbit_dir, stance)
	elif range_intent == ShipAILimboKeys.INTENT_HOLD:
		move_dir = - to_player
	elif range_intent == ShipAILimboKeys.INTENT_ENGAGE:
		# 플레이어 주변을 시계 방향으로 선회
		move_dir = (orbit_dir + to_player * _get_limbo_orbit_inward_bias(stance)).normalized()
	elif dist > orbit_distance + 5.0:
		move_dir = to_player
	elif dist < orbit_distance - 5.0:
		move_dir = - to_player
	else:
		move_dir = (orbit_dir + to_player * orbit_inward_bias).normalized()

	var limbo_nav_hint := _get_limbo_navigation_hint(target)
	var limbo_speed_mult := 1.0
	if not limbo_nav_hint.is_empty():
		var hinted_move_dir: Vector3 = limbo_nav_hint.get("move_dir", Vector3.ZERO)
		if hinted_move_dir.length_squared() > 0.001:
			move_dir = hinted_move_dir.normalized()
			limbo_speed_mult = clampf(float(limbo_nav_hint.get("speed_mult", 1.0)), 0.1, 1.35)
		
	# === 이동 및 회전 (Separation 및 Hard Collision 포함) ===
	# 1. Separation (부드러운 충돌 방지)
	var sep = _calculate_separation()
	
	# 2. Collision Repulsion (강체 충돌 및 충각 데미지)
	var hard_rep = _calculate_collision_repulsion()
	
	if (sep + hard_rep).length_squared() > 0.001:
		# 보스는 질량이 크므로 다른 배들에 비해 밀려나는 정도를 적게 함 (0.5배 -> 0.3배)
		move_dir = (move_dir.normalized() + (sep + hard_rep) * 0.3).normalized()
	
	# 이동 및 회전
	var target_look = global_position + move_dir
	if not global_position.is_equal_approx(target_look):
		target_look.y = global_position.y
		var look_target = lerp(global_position + -basis.z, target_look, delta * 2.0)
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)
		
	# 이동 (누수율에 비례하여 속도 감소)
	var leak_speed_mult = clamp(1.0 - (leaking_rate * 0.03), 0.4, 1.0)
	
	# === 바람 영향(Wind Force) 적용 ===
	var wind_mult = 1.0
	var wind_manager = get_node_or_null("/root/WindManager")
	if is_instance_valid(wind_manager) and wind_manager.has_method("get_wind_direction"):
		var wind_dir: Vector2 = wind_manager.get_wind_direction()
		var wind_str: float = wind_manager.get_wind_strength()
		
		var ship_forward = Vector2(move_dir.x, move_dir.z).normalized()
		var dot_prod = wind_dir.dot(ship_forward)
		
		# 보스는 덩치가 커서 바람의 영향을 조금 덜 받도록 완화 (0.6 ~ 1.3)
		var base_wind_influence = remap(dot_prod, -1.0, 1.0, 0.6, 1.3)
		wind_mult = lerp(1.0, base_wind_influence, wind_str)
		
	# velocity 계산 및 적용
	var final_velocity = move_dir * move_speed * leak_speed_mult * wind_mult * limbo_speed_mult
	global_position += (final_velocity + hard_rep) * delta
	
	_update_leaking_damage(delta)
		
	# === 둥실둥실 및 기울기 효과 ===
	_apply_bobbing_effect()

func _calculate_separation() -> Vector3:
	if get_meta("derelict_nonblocking", false) == true:
		return Vector3.ZERO

	var force = Vector3.ZERO
	var neighbors = EntityRegistry.get_ships()
	
	for other in neighbors:
		if other == self or not is_instance_valid(other) or other.get("is_dead") or other.get("is_sinking"):
			continue
		if other.get_meta("derelict_nonblocking", false) == true:
			continue
			
		var offset = global_position - other.global_position
		offset.y = 0.0
		var dist_sq = offset.length_squared()
		if dist_sq <= 0.01:
			continue
		
		var dist = sqrt(dist_sq)
		var coll_dist = get_collision_distance_to(other)
		var separation_trigger_dist = coll_dist + 0.2
		
		if dist < separation_trigger_dist:
			var push_dir = offset.normalized()
			var ratio = (separation_trigger_dist - dist) / max(separation_trigger_dist, 0.001)
			force += push_dir * pow(ratio, 2.0) * 1.5
			
	return force

func _find_player() -> void:
	target = ShipTargetingHelper.select_player_target_for(self)

	# 타겟 갱신과 무관하게 HUD 체력바는 즉시 동기화한다.
	_update_boss_hp_hud()


func get_preferred_engagement_range() -> float:
	return orbit_distance


func get_engagement_range_tolerance() -> float:
	return 5.0


func _cache_limbo_base_combat_values() -> void:
	_base_move_speed = move_speed
	_base_orbit_inward_bias = orbit_inward_bias


func _update_limbo_ai_pilot(delta: float) -> void:
	if not limbo_ai_pilot_enabled:
		return
	ShipLimboAIPilot.tick(self, delta, limbo_ai_pilot_tree_path)
	_apply_limbo_pilot_modifiers()
	_draw_limbo_ai_debug()


func _get_limbo_range_intent() -> String:
	if not limbo_ai_pilot_enabled:
		return ""
	return str(get_meta(ShipAILimboKeys.META_INTENT, ""))


func _get_limbo_stance() -> String:
	if not limbo_ai_pilot_enabled:
		return ""
	return str(get_meta(ShipAILimboKeys.META_STANCE, ""))


func _apply_limbo_pilot_modifiers() -> void:
	if _base_move_speed <= 0.0:
		_cache_limbo_base_combat_values()
	var pressure := clampf(float(get_meta(ShipAILimboKeys.META_PRESSURE, 0.0)), 0.0, 1.0)
	var stance := _get_limbo_stance()
	var stance_speed_mult := 1.0
	if stance == ShipAILimboKeys.STANCE_DESPERATE_PUSH:
		stance_speed_mult = 1.06
	elif stance == ShipAILimboKeys.STANCE_WITHDRAW:
		stance_speed_mult = 0.96
	move_speed = _base_move_speed * lerp(1.0, 1.12, pressure) * stance_speed_mult
	orbit_inward_bias = clampf(_base_orbit_inward_bias + pressure * 0.12, 0.0, 1.0)


func _get_limbo_orbit_inward_bias(stance: String) -> float:
	return clampf(orbit_inward_bias + _get_limbo_stance_inward_bonus(stance), 0.0, 1.0)


func _get_limbo_stance_inward_bonus(stance: String) -> float:
	match stance:
		ShipAILimboKeys.STANCE_BOMBARD:
			return -0.06
		ShipAILimboKeys.STANCE_ORBIT_PRESSURE:
			return 0.04
		ShipAILimboKeys.STANCE_DESPERATE_PUSH:
			return 0.16
	return 0.0


func _get_limbo_close_move_dir(to_player: Vector3, orbit_dir: Vector3, stance: String) -> Vector3:
	if stance == ShipAILimboKeys.STANCE_DESPERATE_PUSH:
		return (to_player + orbit_dir * 0.22).normalized()
	return to_player


func _get_limbo_navigation_hint(target_node: Node3D) -> Dictionary:
	if not limbo_ai_pilot_enabled or not is_instance_valid(target_node):
		return {}
	var nav_target_id := int(get_meta(ShipAILimboKeys.META_NAV_TARGET_ID, 0))
	if nav_target_id != target_node.get_instance_id():
		return {}
	var nav_frame := int(get_meta(ShipAILimboKeys.META_NAV_FRAME, -1000000))
	if Engine.get_physics_frames() - nav_frame > 4:
		return {}
	var nav_mode := str(get_meta(ShipAILimboKeys.META_NAV_MODE, "")).strip_edges()
	if nav_mode.is_empty() or nav_mode == "limbo_bombard":
		return {}
	var desired_value: Variant = get_meta(ShipAILimboKeys.META_NAV_DESIRED_POINT, null)
	if not (desired_value is Vector3):
		return {}
	var desired_point: Vector3 = desired_value
	var move_vector: Vector3 = desired_point - global_position
	move_vector.y = 0.0
	if move_vector.length_squared() <= 0.001:
		return {}
	return {
		"move_dir": move_vector.normalized(),
		"speed_mult": float(get_meta(ShipAILimboKeys.META_NAV_SPEED_MULT, 1.0)),
		"mode": nav_mode,
		"desired_point": desired_point,
	}


func _draw_limbo_ai_debug() -> void:
	if not DebugDrawBridge.is_channel_enabled(DebugDrawBridge.CHANNEL_AI_INTENT) or not DebugDrawBridge.can_draw():
		return
	var stance := _get_limbo_stance()
	var range_intent := _get_limbo_range_intent()
	var phase := str(get_meta(ShipAILimboKeys.META_PRESSURE_PHASE, ShipAILimboKeys.PHASE_STABLE))
	var pressure := clampf(float(get_meta(ShipAILimboKeys.META_PRESSURE, 0.0)), 0.0, 1.0)
	var target_distance := float(get_meta(ShipAILimboKeys.META_TARGET_DISTANCE, 0.0))
	var nav_mode := str(get_meta(ShipAILimboKeys.META_NAV_MODE, "")).strip_edges()
	var color := _get_limbo_stance_color(stance)
	var label := "LimboAI %s\nrange:%s phase:%s p:%.2f dist:%.1f\nnav:%s" % [
		stance if not stance.is_empty() else "-",
		range_intent if not range_intent.is_empty() else "-",
		phase,
		pressure,
		target_distance,
		nav_mode if not nav_mode.is_empty() else "-",
	]
	DebugDrawBridge.draw_text(global_position + Vector3.UP * 4.4, label, color, 0.0, 16)
	if is_instance_valid(target):
		DebugDrawBridge.draw_line_raised(global_position, target.global_position, 2.35, color, 0.0, 0.026)
		DebugDrawBridge.draw_circle_xz(target.global_position, get_preferred_engagement_range(), color, 1.1, 0.0, 72, 0.024)
		var limbo_nav_hint := _get_limbo_navigation_hint(target)
		if not limbo_nav_hint.is_empty():
			var desired_point: Vector3 = limbo_nav_hint.get("desired_point", global_position)
			DebugDrawBridge.draw_marker(desired_point, color, "", 0.0, 0.28, 1.5)
			DebugDrawBridge.draw_line_raised(global_position, desired_point, 1.4, color, 0.0, 0.032)


func _get_limbo_stance_color(stance: String) -> Color:
	match stance:
		ShipAILimboKeys.STANCE_CLOSE_DISTANCE:
			return Color(0.35, 0.95, 1.0, 0.88)
		ShipAILimboKeys.STANCE_ORBIT_PRESSURE:
			return Color(1.0, 0.75, 0.22, 0.9)
		ShipAILimboKeys.STANCE_WITHDRAW:
			return Color(0.5, 0.74, 1.0, 0.88)
		ShipAILimboKeys.STANCE_DESPERATE_PUSH:
			return Color(1.0, 0.18, 0.12, 0.94)
		_:
			return Color(0.86, 1.0, 0.36, 0.88)

func _update_boss_hp_hud() -> void:
	if not is_instance_valid(cached_lm):
		cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(cached_lm) and cached_lm.has_method("update_boss_hp"):
		cached_lm.update_boss_hp(maxf(hull_hp, 0.0), max_hull_hp)

func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, damage_source: String = "") -> void:
	super.take_damage(amount, hit_position, damage_source)
	_update_boss_hp_hud()

func die() -> void:
	if is_dying: return
	is_dying = true
	if is_instance_valid(cached_lm) and cached_lm.has_method("update_boss_hp"):
		cached_lm.update_boss_hp(0.0, max_hull_hp)
	_play_final_boss_defeat_flourish()
	_try_report_final_boss_victory()
	
	# ✅ 배 위의 아군(player) 병사를 Survivor로 전환 (침몰 전 처리)
	_evacuate_player_soldiers_as_survivors()
	
	# 침몰 시작 시 타겟 그룹에서 제외
	if is_in_group("enemy"):
		remove_from_group("enemy")
	
	boss_died.emit()
	print("[Boss] 보스 격침!")
	if is_instance_valid(cached_lm):
		if cached_lm.has_method("add_ship_sunk"):
			cached_lm.add_ship_sunk(1)
		# 규칙 통일: 함선 격침은 XP/점수 지급
		if cached_lm.has_method("add_score"):
			cached_lm.add_score(400)
		if cached_lm.has_method("add_xp"):
			cached_lm.add_xp(100)
	
	# 공적 포인트(Merit) 추가 (보스는 대량의 공적 부여)
	if not _merit_granted and is_instance_valid(cached_lm) and cached_lm.has_method("add_merit"):
		cached_lm.add_merit(50)
		_merit_granted = true

	_drop_treasure_chest()
	
	# 침몰 효과 (회전하며 가라앉음)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self , "position:y", -5.0, 4.0)
	tween.tween_property(self , "rotation:z", deg_to_rad(25.0), 3.0)
	
	var boss_id: int = get_instance_id()
	tween.chain().tween_callback(func():
		var boss_ship = instance_from_id(boss_id)
		if not is_instance_valid(boss_ship):
			return
		boss_ship.call("_try_report_final_boss_victory")
	)
	
	# 아이템은 최종 보스(tier 2 이상)만 드롭한다.
	if tier >= 2 and is_instance_valid(UpgradeManager) and UpgradeManager.has_method("grant_final_boss_item"):
		UpgradeManager.grant_final_boss_item()
	
	# 생존자 대량 스폰 (보스 격침 보너스: 3~5명)
	if survivor_scene:
		var count = randi_range(3, 5)
		for i in range(count):
			var survivor = ScenePool.acquire(get_tree(), survivor_scene)
			get_tree().root.add_child.call_deferred(survivor)
			var offset = Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-4.0, 4.0))
			survivor.set_deferred("global_position", global_position + offset)
	
	# 삭제 지연
	leaking_rate = 0.0 # 사망 시 누수 중단
	get_tree().create_timer(5.0).timeout.connect(queue_free)


func _play_final_boss_defeat_flourish() -> void:
	if tier < 2 or _defeat_flourish_started:
		return
	_defeat_flourish_started = true
	if not is_instance_valid(cached_lm):
		cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	if is_instance_valid(cached_lm) and "hud" in cached_lm:
		_cached_hud = cached_lm.hud
	if is_instance_valid(_cached_hud) and _cached_hud.has_method("show_gust_warning_message"):
		_cached_hud.show_gust_warning_message("최종 보스 격침!", 2.4)
	if not is_instance_valid(_cached_audio_manager):
		_cached_audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(_cached_audio_manager) and _cached_audio_manager.has_method("play_sfx"):
		_cached_audio_manager.play_sfx("rocket_launch", global_position, 0.75, 6.0)
		_cached_audio_manager.play_sfx("water_splash_large", global_position, 0.8, 5.0)
		_cached_audio_manager.play_sfx("level_up", null, 0.9, 0.0)
	_spawn_final_boss_defeat_splashes()
	_start_final_boss_defeat_slowdown()


func _spawn_final_boss_defeat_splashes() -> void:
	if not water_splash_scene:
		return
	var splash_offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-3.2, 0.0, -2.6),
		Vector3(3.0, 0.0, 2.4),
	]
	for offset in splash_offsets:
		var splash = ScenePool.acquire(get_tree(), water_splash_scene)
		get_tree().root.add_child(splash)
		splash.global_position = global_position + offset
		splash.global_position.y = 0.15
		if splash.has_method("configure_as_sink"):
			splash.configure_as_sink()
		if splash.has_method("set_intensity"):
			splash.set_intensity(1.35)
		if splash.has_method("pool_activate"):
			splash.pool_activate()


func _start_final_boss_defeat_slowdown() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var previous_time_scale: float = Engine.time_scale
	if previous_time_scale <= 0.45:
		return
	Engine.time_scale = 0.38
	var tree := get_tree()
	if not is_instance_valid(tree):
		Engine.time_scale = previous_time_scale
		return
	var restore_time_scale := func() -> void:
		if Engine.time_scale <= 0.45:
			Engine.time_scale = previous_time_scale
	tree.create_timer(0.42, true, false, true).timeout.connect(restore_time_scale, CONNECT_ONE_SHOT)


func _try_report_final_boss_victory() -> void:
	if _victory_reported or tier < 2:
		return
	if not is_instance_valid(cached_lm):
		cached_lm = LevelManagerRegistry.get_level_manager(get_tree())
	if not is_instance_valid(cached_lm) or not cached_lm.has_method("show_victory"):
		if _victory_report_retry_count < 3:
			_victory_report_retry_count += 1
			call_deferred("_try_report_final_boss_victory")
		return
	_victory_reported = true
	cached_lm.show_victory()


func _drop_treasure_chest() -> void:
	if not chest_scene:
		return
	var chest = chest_scene.instantiate()
	if chest == null:
		return
	get_tree().root.add_child(chest)
	chest.global_position = global_position
	chest.global_position.y = 0.0
	print("[Boss] 보스 격침! 보물 상자 드랍.")

## 침몰 시 배 위의 아군(player) 병사를 Survivor로 전환
func _evacuate_player_soldiers_as_survivors() -> void:
	if not survivor_scene: return
	var soldiers_node = get_soldiers_container()
	if not soldiers_node: return
	
	var converted_count = 0
	for child in soldiers_node.get_children():
		if child.get("team") == "player" and _is_alive_soldier_node(child):
			# 병사 위치 저장 후 생존자 스폰
			var spawn_pos = child.global_position
			spawn_pos.y = 0.5 # 수면 높이
			
			var survivor = ScenePool.acquire(get_tree(), survivor_scene)
			get_tree().root.add_child.call_deferred(survivor)
			survivor.set_deferred("global_position", spawn_pos)
			
			# 병사 즉시 제거
			child.queue_free()
			converted_count += 1
	
	if converted_count > 0:
		print("[Critical] 보함 침몰! 아군 병사 %d명이 바다로 뛰어들었습니다!" % converted_count)


func _is_alive_soldier_node(soldier: Node) -> bool:
	return BossSoldierStateHelper.is_alive_soldier(soldier)


# 누수 추가/제거
func add_leak(amount: float) -> void:
	leaking_rate += amount
	print("[Status] 보스 함선에 누수 발생! 초당 데미지: %.1f" % leaking_rate)

func remove_leak(amount: float) -> void:
	leaking_rate = maxf(0.0, leaking_rate - amount)
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
	print("[Status] 보스 누수 완화. 남은 누수율: %.1f" % leaking_rate)

func _update_leaking_damage(delta: float) -> void:
	if leaking_rate <= 0.0:
		_leak_tick_timer = 0.0
		return
	_leak_tick_timer += delta
	while _leak_tick_timer >= 1.0:
		_leak_tick_timer -= 1.0
		take_damage(leaking_rate, global_position, "leak")

# === 장군전 등 특수 피격 로직 ===
func add_stuck_object(obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	# 보스는 속도 저하보다는 시각적 기울기만 적용
	var tilt_dir = 1.0 if obj.global_position.x > global_position.x else -1.0
	var new_tilt = deg_to_rad(randf_range(3.0, 6.0)) * tilt_dir # 보스는 덜 기웃거림
	tilt_offset = clamp(tilt_offset + new_tilt, -deg_to_rad(10.0), deg_to_rad(10.0))

func remove_stuck_object(_obj: Node3D, _s_mult: float, _t_mult: float) -> void:
	tilt_offset *= 0.5
	if tilt_offset < 0.01: tilt_offset = 0.0
