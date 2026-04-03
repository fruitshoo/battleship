extends Area3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")

const CLOSE_RANGE_HULL_FALLOFF_DISTANCE: float = 8.0
const CLOSE_RANGE_HULL_MIN_MULTIPLIER: float = 0.55
const GRAPESHOT_MAX_EFFECTIVE_DISTANCE: float = 13.5

## 대포알 (Cannonball)
## 정해진 방향으로 전진하며, 적과 충돌 시 적을 파괴함

@export var speed: float = 50.0
@export var lifetime: float = 2.0 # 사거리 단축 (80 * 2 = 160m)
@export var damage: float = 1.0
@export var homing_strength: float = 0.0 # 유도 제거
@export var homing_duration: float = 0.0 # 유도 제거
@export var crit_chance: float = 0.2 # 20% 크리티컬 확률
@export var crit_multiplier: float = 1.5 # 크리티컬 1.5배 데미지
@export var impact_smoke_scene: PackedScene = preload("res://scenes/effects/impact_puff.tscn")
@export var wood_splinter_scene: PackedScene = preload("res://scenes/effects/wood_splinter.tscn")
var water_explosion_scene: PackedScene = preload("res://scenes/effects/water_burst.tscn")

var team: String = "player"
var direction: Vector3 = Vector3.FORWARD
var target_node: Node3D = null
var shooter_label: String = ""
var ammo_type: String = "roundshot"
var launch_origin: Vector3 = Vector3.ZERO
var time_alive: float = 0.0
var _life_left: float = 0.0
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

func launch(spawn_position: Vector3, fire_team: String, fire_direction: Vector3, target: Node3D, final_damage: float, lifetime_mult: float = 1.0, next_ammo_type: String = "roundshot") -> void:
	global_position = spawn_position
	team = fire_team
	damage = final_damage
	target_node = target
	ammo_type = next_ammo_type
	shooter_label = ""
	launch_origin = spawn_position
	time_alive = 0.0
	has_hit = false
	_is_releasing = false
	direction = fire_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	lifetime = _base_lifetime * lifetime_mult
	_life_left = lifetime
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	monitoring = false
	monitorable = false
	if team == "player":
		collision_mask = 4
	else:
		collision_mask = 2
	if is_instance_valid(smoke_trail):
		smoke_trail.restart()
		smoke_trail.emitting = true
	var up_vec = Vector3.UP
	if abs(direction.y) > 0.999:
		up_vec = Vector3.RIGHT
	basis = Basis.looking_at(direction, up_vec)

func pool_reset() -> void:
	has_hit = false
	_is_releasing = false
	time_alive = 0.0
	_life_left = 0.0
	target_node = null
	ammo_type = "roundshot"
	shooter_label = ""
	launch_origin = Vector3.ZERO
	damage = _base_damage
	crit_chance = _base_crit_chance
	crit_multiplier = _base_crit_multiplier
	lifetime = _base_lifetime
	if is_instance_valid(smoke_trail):
		smoke_trail.emitting = false

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

func _spawn_effects(_is_crit: bool = false) -> void:
	var audio_manager = get_node_or_null("/root/AudioManager")
	if not is_instance_valid(audio_manager): return
	
	# 나무 부서지는 소리 재생
	if audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("impact_wood", global_position, randf_range(0.9, 1.1))

	# 타격 연기는 발사 연기와 별도 budget을 사용해야 동시에 보여도 막히지 않는다.
	if impact_smoke_scene and VfxBudget.allow_spawn(get_tree(), "hit_effect", global_position, 8, 180.0):
		var smoke = ScenePool.acquire(get_tree(), impact_smoke_scene)
		if smoke.has_method("configure_as_hit"):
			smoke.configure_as_hit()
		if smoke.has_method("set_intensity"):
			var hit_intensity: float = 1.0 + (0.22 if _is_crit else 0.0)
			smoke.set_intensity(clampf(hit_intensity, 1.0, 1.35))
		get_tree().root.add_child(smoke)
		smoke.global_position = global_position
		# 연기는 위쪽으로 퍼지게.
		smoke.global_basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)
		if smoke.has_method("pool_activate"):
			smoke.pool_activate()

	# 포탄이 선체에 꽂힐 때는 목재 파편이 확실히 보여야 한다.
	if wood_splinter_scene and VfxBudget.allow_spawn(get_tree(), "cannon_hit_splinter", global_position, 6, 140.0):
		var splinter = ScenePool.acquire(get_tree(), wood_splinter_scene)
		get_tree().root.add_child(splinter)
		splinter.position = global_position + Vector3(0.0, 0.35, 0.0)
		splinter.rotation.y = randf() * TAU
		if splinter.has_method("set_amount_by_damage"):
			splinter.set_amount_by_damage(damage * (1.0 if _is_crit else 0.8) + 6.0)
		if splinter.has_method("pool_activate"):
			splinter.pool_activate()

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

var has_hit: bool = false

func _on_timeout() -> void:
	if has_hit or _is_releasing: return
	
	# 수명 만료 = 바다에 떨어짐 → 물 폭발 이펙트 생성
	_spawn_water_explosion()
	
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_large", global_position, randf_range(0.8, 1.2))
	_release_self()

func _physics_process(delta: float) -> void:
	if has_hit or _is_releasing: return
	
	time_alive += delta
	_life_left -= delta
	if _life_left <= 0.0:
		_on_timeout()
		return
	# 부드러운 유도 (Soft Homing) - 초반만 작동 (사용 시)
	if time_alive < homing_duration and is_instance_valid(target_node):
		var to_target = (target_node.global_position - global_position).normalized()
		direction = direction.lerp(to_target, homing_strength * delta).normalized()
		var up_vec = Vector3.UP
		if abs(direction.y) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(global_position + direction, up_vec)
		
	var move_vec = direction * speed * delta
	var next_pos = global_position + move_vec
	
	# CCD (Continuous Collision Detection)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, next_pos, collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		global_position = result.position
		_check_hit(result.collider)
		return
		
	global_position = next_pos
	
	# 수면(y=0.0) 타격 감지 기능 추가
	if global_position.y <= 0.0:
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
		final_damage *= _get_hull_damage_multiplier_for_ammo(ship)
		
		if ship.has_method("take_damage"):
			if shooter_label.is_empty() and has_meta("shooter_label"):
				shooter_label = str(get_meta("shooter_label"))
			if not shooter_label.is_empty():
				source_id += ":%s" % shooter_label
			ship.take_damage(final_damage, global_position, source_id)
		_apply_crew_damage_for_ammo(ship, global_position)
		
		_spawn_effects(is_crit)
		_release_self()
	else:
		# 침몰 중인 함선에 맞은 거면 무시 (부자연스러운 물폭발 방지)
		var is_sinking = false
		if target.has_method("get") and target.get("is_sinking") == true: is_sinking = true
		elif target.get_parent() and target.get_parent().has_method("get") and target.get_parent().get("is_sinking") == true: is_sinking = true
			
		if not is_sinking:
			# 함선 외의 물체에 부딪혔을 때 → 물 폭발 이펙트 생성
			_spawn_water_explosion()
			var audio_manager = get_node_or_null("/root/AudioManager")
			if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
				audio_manager.play_sfx("water_splash_large", global_position, randf_range(1.0, 1.3))
		
		# 어떤 경우든 부딪히면 삭제
		_release_self()


func _build_damage_source_id(is_crit: bool) -> String:
	var ammo_suffix: String = ""
	match ammo_type:
		"chainshot":
			ammo_suffix = "_chain"
		"grapeshot":
			ammo_suffix = "_grape"
		_:
			ammo_suffix = ""
	if team == "player":
		return "cannon%s%s" % [ammo_suffix, "_crit" if is_crit else ""]
	return "enemy_cannon%s%s" % [ammo_suffix, "_crit" if is_crit else ""]


func _get_hull_damage_multiplier_for_ammo(ship: Node3D) -> float:
	match ammo_type:
		"chainshot":
			return 0.35
		"grapeshot":
			var planar_distance: float = _get_planar_distance_to(ship.global_position)
			if planar_distance > GRAPESHOT_MAX_EFFECTIVE_DISTANCE:
				return 0.03
			var close_t: float = clampf(1.0 - (planar_distance / GRAPESHOT_MAX_EFFECTIVE_DISTANCE), 0.0, 1.0)
			return lerpf(0.03, 0.12, close_t)
		_:
			var close_range_hull_mult: float = _get_close_range_hull_multiplier(ship)
			return close_range_hull_mult


func _apply_crew_damage_for_ammo(ship: Node3D, hit_pos: Vector3) -> void:
	if ammo_type != "grapeshot":
		return
	var planar_distance: float = _get_planar_distance_to(ship.global_position)
	if planar_distance > GRAPESHOT_MAX_EFFECTIVE_DISTANCE:
		return
	var soldiers_node: Node = ship.get_node_or_null("Soldiers")
	if not is_instance_valid(soldiers_node):
		return
	var enemy_soldiers: Array[Node] = []
	for child in soldiers_node.get_children():
		if not is_instance_valid(child):
			continue
		if child.get("current_state") == 4:
			continue
		if str(child.get("team")) == team:
			continue
		enemy_soldiers.append(child)
	if enemy_soldiers.is_empty():
		return

	enemy_soldiers.sort_custom(func(a: Node, b: Node) -> bool:
		return a.global_position.distance_squared_to(hit_pos) < b.global_position.distance_squared_to(hit_pos)
	)
	var close_t: float = clampf(1.0 - (planar_distance / GRAPESHOT_MAX_EFFECTIVE_DISTANCE), 0.0, 1.0)
	var target_count: int = maxi(1, mini(enemy_soldiers.size(), int(round(lerpf(2.0, 5.0, close_t)))))
	var soldier_damage: float = damage * lerpf(0.45, 0.9, close_t)
	for i in range(target_count):
		var soldier: Node = enemy_soldiers[i]
		if soldier.has_method("take_damage"):
			soldier.take_damage(soldier_damage, hit_pos, "grapeshot")


func _get_planar_distance_to(target_pos: Vector3) -> float:
	var planar_delta: Vector3 = target_pos - global_position
	planar_delta.y = 0.0
	return planar_delta.length()


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
	if not VfxBudget.allow_spawn(get_tree(), "water_explosion", global_position, 4, 70.0):
		return
	
	var pos = global_position
	var explosion = ScenePool.acquire(get_tree(), water_explosion_scene)
	if explosion.has_method("configure_as_splash"):
		explosion.configure_as_splash()
	if explosion.has_method("set_intensity"):
		explosion.set_intensity(0.95)
	# 수면 높이에 맞춘 위치를 한 번에 설정
	# 대포알은 root에 추가되므로 position이 global_position과 동일하며, 
	# 씬 트리에 없는 노드의 global_position을 건드리면 에러가 발생하므로 position 사용.
	explosion.position = Vector3(pos.x, 0.2, pos.z)
	get_tree().root.add_child(explosion)
	if explosion.has_method("pool_activate"):
		explosion.pool_activate()
