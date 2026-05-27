extends Area3D
const WoodSplinter = preload("res://scripts/effects/wood_splinter.gd")
const ShipDamageDecalHelper = preload("res://scripts/effects/ship_damage_decal_helper.gd")
const VfxSpawnHelper = preload("res://scripts/helpers/vfx_spawn_helper.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")
const BallisticCollateralHelper = preload("res://scripts/projectiles/ballistic_collateral_helper.gd")

const CLOSE_RANGE_HULL_FALLOFF_DISTANCE: float = 8.0
const CLOSE_RANGE_HULL_MIN_MULTIPLIER: float = 0.55

## 대포알 (Cannonball)
## 정해진 방향으로 전진하며, 적과 충돌 시 적을 파괴함

@export var speed: float = 50.0
@export var lifetime: float = 2.0 # 사거리 단축 (80 * 2 = 160m)
@export var damage: float = 1.0
@export var homing_strength: float = 0.0 # 유도 제거
@export var homing_duration: float = 0.0 # 유도 제거
@export var crit_chance: float = 0.2 # 20% 크리티컬 확률
@export var crit_multiplier: float = 1.5 # 크리티컬 1.5배 데미지
@export_range(0.0, 24.0, 0.5) var miss_overshoot_distance: float = 8.0
@export_range(4.0, 48.0, 0.5) var min_miss_travel_distance: float = 12.0
@export var impact_smoke_scene: PackedScene = preload("res://scenes/effects/impact_puff.tscn")
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
var water_explosion_scene: PackedScene = preload("res://scenes/effects/water_blast.tscn")

var team: String = "player"
var direction: Vector3 = Vector3.FORWARD
var target_node: Node3D = null
var shooter_label: String = ""
var launch_origin: Vector3 = Vector3.ZERO
var time_alive: float = 0.0
var _life_left: float = 0.0
var _traveled_distance: float = 0.0
var _max_travel_distance: float = -1.0
var _signals_connected: bool = false
var _base_lifetime: float = 0.0
var _base_damage: float = 0.0
var _base_crit_chance: float = 0.0
var _base_crit_multiplier: float = 1.0
var _is_releasing: bool = false

@onready var smoke_trail: GPUParticles3D = get_node_or_null("SmokeTrail")

func set_lifetime_multiplier(mult: float) -> void:
	lifetime *= mult

func get_base_damage() -> float:
	return _base_damage

func pool_capacity() -> int:
	return 24

func launch(spawn_position: Vector3, fire_team: String, fire_direction: Vector3, target: Node3D, final_damage: float, lifetime_mult: float = 1.0, max_travel_distance: float = -1.0) -> void:
	global_position = spawn_position
	team = fire_team
	damage = final_damage
	target_node = target
	shooter_label = ""
	launch_origin = spawn_position
	time_alive = 0.0
	_traveled_distance = 0.0
	has_hit = false
	_is_releasing = false
	direction = fire_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	lifetime = _base_lifetime * lifetime_mult
	_life_left = lifetime
	_max_travel_distance = _resolve_max_travel_distance(spawn_position, target, max_travel_distance)
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	monitoring = false
	monitorable = false
	if team == "player":
		collision_mask = 4
	else:
		collision_mask = 2
	_configure_smoke_trail_for_launch(spawn_position)
	var up_vec = Vector3.UP
	if abs(direction.y) > 0.999:
		up_vec = Vector3.RIGHT
	basis = Basis.looking_at(direction, up_vec)

func pool_reset() -> void:
	has_hit = false
	_is_releasing = false
	time_alive = 0.0
	_life_left = 0.0
	_traveled_distance = 0.0
	_max_travel_distance = -1.0
	target_node = null
	shooter_label = ""
	launch_origin = Vector3.ZERO
	damage = _base_damage
	crit_chance = _base_crit_chance
	crit_multiplier = _base_crit_multiplier
	lifetime = _base_lifetime
	if is_instance_valid(smoke_trail):
		smoke_trail.emitting = false
		smoke_trail.visible = false


func _configure_smoke_trail_for_launch(spawn_position: Vector3) -> void:
	if not is_instance_valid(smoke_trail):
		return
	var enable_trail := true
	if is_inside_tree():
		enable_trail = VfxBudget.allow_spawn(get_tree(), "cannonball_trail", spawn_position, 14, 95.0)
		if team != "player" and VfxBudget.get_continuous_effect_scale() <= 0.48:
			enable_trail = false
	smoke_trail.visible = enable_trail
	if enable_trail:
		smoke_trail.restart()
	smoke_trail.emitting = enable_trail

func _release_self() -> void:
	if _is_releasing:
		return
	_is_releasing = true
	if is_inside_tree():
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
		call_deferred("_finalize_release")
	else:
		monitoring = false
		monitorable = false
		process_mode = Node.PROCESS_MODE_DISABLED
		ScenePool.release(self)

func _finalize_release() -> void:
	if not is_instance_valid(self):
		return
	ScenePool.release(self)

func _spawn_effects(_is_crit: bool, impact_position: Vector3, hit_ship: Node3D = null, applied_damage: float = 0.0, damage_source_id: String = "") -> void:
	if not impact_position.is_finite():
		return
	if is_instance_valid(hit_ship):
		ShipDamageDecalHelper.try_spawn_from_ship_hit(hit_ship, maxf(applied_damage, damage), impact_position, damage_source_id)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if not is_instance_valid(audio_manager): return
	
	if audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("cannon_hit", impact_position, randf_range(0.94, 1.06))

	# 타격 연기는 별도 budget을 사용해야 동시에 보여도 막히지 않는다.
	if impact_smoke_scene:
		var smoke := VfxSpawnHelper.acquire_world_node3d(get_tree(), impact_smoke_scene, impact_position, "hit_effect", 10, 100.0)
		if is_instance_valid(smoke):
			if smoke.has_method("set_intensity"):
				var hit_intensity: float = 1.0 + (0.22 if _is_crit else 0.0)
				smoke.set_intensity(clampf(hit_intensity, 1.0, 1.35))
			# 연기는 위쪽으로 퍼지게.
			smoke.global_basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)
			VfxSpawnHelper.activate(smoke)

	# 포탄이 선체에 꽂힐 때는 목재 파편이 확실히 보여야 한다.
	if wood_splinter_scene:
		var splinter_damage := damage * (1.0 if _is_crit else 0.8) + 6.0
		WoodSplinter.spawn_burst(
			get_tree(),
			wood_splinter_scene,
			impact_position + Vector3(0.0, 0.35, 0.0),
			splinter_damage,
			direction,
			"cannon_hit_splinter",
			6,
			140.0
		)

func _ready() -> void:
	_base_lifetime = lifetime
	_base_damage = damage
	_base_crit_chance = crit_chance
	_base_crit_multiplier = crit_multiplier
	pool_reset()
	# 팀에 따른 충돌 마스크 자동 설정
	if team == "player":
		# 아군 대포알 → 적군(layer 4) 감시
		collision_mask = 4
	else:
		# 적군 대포알 → 플레이어(layer 2) 감시
		collision_mask = 2
		
	# 충돌 시그널 연결
	if not _signals_connected:
		area_entered.connect(_on_area_entered)
		body_entered.connect(_on_body_entered)
		_signals_connected = true


func _enter_tree() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	EntityRegistry.register_projectile(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_projectile(self)

var has_hit: bool = false

func _on_timeout() -> void:
	if has_hit or _is_releasing: return
	
	# 수명 만료 = 바다에 떨어짐 → 물 폭발 이펙트 생성
	_draw_projectile_marker("splash", Color(0.25, 0.6, 1.0, 0.95))
	_spawn_water_explosion()
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
	_release_self()

func _physics_process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_physics_process(delta)
	PhysicsFrameProfiler.end("projectile_cannonball", profile_start)


func _profiled_physics_process(delta: float) -> void:
	if has_hit or _is_releasing: return
	
	time_alive += delta
	_life_left -= delta
	if _life_left <= 0.0:
		_on_timeout()
		return
	# 부드러운 유도 (Soft Homing) - 초반만 작동 (사용 시)
	if time_alive < homing_duration and is_instance_valid(target_node):
		var to_target = (NodeContractHelper.get_projectile_aim_point(target_node, 0.55) - global_position).normalized()
		direction = direction.lerp(to_target, homing_strength * delta).normalized()
		var up_vec = Vector3.UP
		if abs(direction.y) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(global_position + direction, up_vec)
		
	var move_vec = direction * speed * delta
	var move_distance := move_vec.length()
	var expires_by_distance := false
	if _max_travel_distance > 0.0:
		var remaining_distance := _max_travel_distance - _traveled_distance
		if remaining_distance <= 0.0:
			_on_travel_limit_reached()
			return
		if move_distance >= remaining_distance:
			move_vec = direction * remaining_distance
			move_distance = remaining_distance
			expires_by_distance = true
	var ray_start := global_position
	var next_pos = global_position + move_vec
	
	# CCD (Continuous Collision Detection)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, next_pos, collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if DebugDrawBridge.projectile_debug_enabled:
		if result:
			DebugDrawBridge.draw_hit_ray(ray_start, next_pos, result.position, true, _debug_hit_label(result.collider), 1.4)
		else:
			DebugDrawBridge.draw_line(ray_start, next_pos, Color(1.0, 0.82, 0.25, 0.45), 0.08, 0.026)
	if result:
		global_position = result.position
		_traveled_distance += ray_start.distance_to(global_position)
		_check_hit(result.collider)
		return

	global_position = next_pos
	_traveled_distance += move_distance
	if expires_by_distance:
		_on_travel_limit_reached()
		return
	
	# 수면(y=0.0) 타격 감지 기능 추가
	if global_position.y <= 0.0:
		_draw_projectile_marker("water", Color(0.25, 0.6, 1.0, 0.95))
		_spawn_water_explosion()
		var audio_manager = get_node_or_null("/root/AudioManager")
		if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
			audio_manager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
		has_hit = true
		_release_self()


func _resolve_max_travel_distance(spawn_position: Vector3, target: Node3D, requested_distance: float) -> float:
	if requested_distance > 0.0:
		return maxf(requested_distance, min_miss_travel_distance)
	if not is_instance_valid(target):
		return -1.0
	var target_distance := spawn_position.distance_to(NodeContractHelper.get_projectile_aim_point(target, 0.55))
	return maxf(target_distance + miss_overshoot_distance, min_miss_travel_distance)


func _on_travel_limit_reached() -> void:
	if has_hit or _is_releasing:
		return
	_draw_projectile_marker("range", Color(0.25, 0.6, 1.0, 0.95))
	_spawn_water_explosion()
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
	has_hit = true
	_release_self()


func _on_area_entered(area: Area3D) -> void:
	_check_hit(area)

func _on_body_entered(body: Node3D) -> void:
	_check_hit(body)

func _check_hit(target: Node) -> void:
	if has_hit or _is_releasing: return
	
	# 일단 무언가에 부딪혔으므로 삭제 준비
	has_hit = true
	
	# 적 함선 찾기 로직 강화
	var ship = HitTargetResolver.resolve_ship_from_node(target)
		
	if ship:
		# 피아 식별 (내 팀과 같은 팀이면 통과 - 오사 방지)
		var ship_team = HitTargetResolver.resolve_team_tag(ship)
		if ship_team == team:
			has_hit = false # 아군이면 맞은 걸로 치지 않음 (관통)
			return
		
		# 적중 처리
		var is_crit = randf() < crit_chance
		var final_damage = damage * (crit_multiplier if is_crit else 1.0)
		var source_id: String = _build_damage_source_id(is_crit)
		final_damage *= _get_hull_damage_multiplier(ship)
		var impact_position := global_position
		
		if ship.has_method("take_damage"):
			if shooter_label.is_empty() and has_meta("shooter_label"):
				shooter_label = str(get_meta("shooter_label"))
			if not shooter_label.is_empty():
				source_id += ":%s" % shooter_label
			ship.take_damage(final_damage, impact_position, source_id)
			BallisticCollateralHelper.try_apply_from_ship_hit(
				self,
				ship,
				impact_position,
				BallisticCollateralHelper.KIND_CANNON,
				direction
			)
		
		_draw_projectile_marker("HIT %s" % ship.name, Color(1.0, 0.22, 0.1, 0.98))
		_spawn_effects(is_crit, impact_position, ship, final_damage, source_id)
		_release_self()
	else:
		# 침몰 중인 함선에 맞은 거면 무시 (부자연스러운 물폭발 방지)
		var is_sinking = NodeContractHelper.is_sinking_or_dying(target)
		if not is_sinking and target.get_parent():
			is_sinking = NodeContractHelper.is_sinking_or_dying(target.get_parent())
			
		if not is_sinking:
			# 함선 외의 물체에 부딪혔을 때 → 물 폭발 이펙트 생성
			_draw_projectile_marker("impact", Color(0.25, 0.6, 1.0, 0.95))
			_spawn_water_explosion()
			var audio_manager = get_node_or_null("/root/AudioManager")
			if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
				audio_manager.play_sfx("water_splash_large", global_position, randf_range(1.0, 1.3))
		
		# 어떤 경우든 부딪히면 삭제
		_release_self()


func _draw_projectile_marker(label: String, color: Color) -> void:
	if not DebugDrawBridge.projectile_debug_enabled:
		return
	DebugDrawBridge.draw_marker(global_position, color, label, 1.6, 0.32, 0.45)


func _debug_hit_label(target: Variant) -> String:
	if target is Node:
		return (target as Node).name
	return "hit"


func _build_damage_source_id(is_crit: bool) -> String:
	if team == "player":
		return "cannon%s" % ("_crit" if is_crit else "")
	return "enemy_cannon%s" % ("_crit" if is_crit else "")


func _get_hull_damage_multiplier(ship: Node3D) -> float:
	return _get_close_range_hull_multiplier(ship)


func _get_close_range_hull_multiplier(ship: Node3D) -> float:
	if not is_instance_valid(ship):
		return 1.0
	if launch_origin == Vector3.ZERO:
		return 1.0
	var planar_distance: float = Vector2(
		ship.global_position.x - launch_origin.x,
		ship.global_position.z - launch_origin.z
	).length()
	if planar_distance >= CLOSE_RANGE_HULL_FALLOFF_DISTANCE:
		return 1.0
	var t: float = clampf(planar_distance / CLOSE_RANGE_HULL_FALLOFF_DISTANCE, 0.0, 1.0)
	return lerpf(CLOSE_RANGE_HULL_MIN_MULTIPLIER, 1.0, t)

func _spawn_water_explosion() -> void:
	if not is_inside_tree() or not water_explosion_scene: return
	var pos := global_position
	pos = Vector3(pos.x, 0.2, pos.z)
	var explosion := VfxSpawnHelper.acquire_world_node3d(get_tree(), water_explosion_scene, pos, "water_explosion", 4, 70.0)
	if not is_instance_valid(explosion):
		return
	if explosion.has_method("configure_as_splash"):
		explosion.configure_as_splash()
	if explosion.has_method("set_intensity"):
		explosion.set_intensity(1.35)
	VfxSpawnHelper.activate(explosion)
