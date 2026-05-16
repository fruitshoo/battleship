extends Area3D
const WATER_BLAST_SCENE = preload("res://scenes/effects/water_blast.tscn")
const SOLDIER_CRIT_HIT_SCENE = preload("res://scenes/effects/soldier_crit_hit.tscn")
const VfxSpawnHelper = preload("res://scripts/helpers/vfx_spawn_helper.gd")
const PhysicsFrameProfiler = preload("res://scripts/debug/physics_frame_profiler.gd")

## 화살 (Arrow)
## 병사가 쏘는 원거리 투사체

@export var damage: float = 15.0
@export var speed: float = 25.0 # 초당 이동 거리 (이전 20.0 -> 8.0 -> 14.0 -> 16.0 -> 25.0)
@export var arc_height: float = 2.0 # 포물선 최대 높이
@export var terminal_hit_radius: float = 2.2

const MIN_FLIGHT_DURATION := 0.12
const TERMINAL_VISUAL_CONVERGE_START := 0.42
const TERMINAL_VISUAL_TRACK_RADIUS := 8.0
const SOLDIER_AIM_VERTICAL_OFFSET := 1.05
const SHIP_AIM_VERTICAL_OFFSET := 0.55
const CRIT_EFFECT_DECK_MARGIN := 0.75

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var target_node: Node3D = null # 목표물 참조 (강제 명중 판정용)
var team: String = "player"
var damage_source: String = "bow"
var is_critical_hit: bool = false
var is_fire_arrow: bool = false
var fire_damage: float = 0.0

var progress: float = 0.0
var duration: float = 1.0
var _is_releasing: bool = false
var _rotation_update_timer: float = 0.0

func _ready() -> void:
	pool_reset()


func _enter_tree() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	EntityRegistry.register_projectile(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_projectile(self)

func pool_capacity() -> int:
	return 48

func launch(
	spawn_position: Vector3,
	final_target_pos: Vector3,
	final_target_node: Node3D,
	fire_team: String,
	final_damage: float,
	final_damage_source: String,
	arrow_speed: float,
	final_arc_height: float,
	final_is_critical_hit: bool = false
) -> void:
	start_pos = spawn_position
	target_pos = final_target_pos
	target_node = final_target_node
	team = fire_team
	damage = final_damage
	damage_source = final_damage_source
	is_critical_hit = final_is_critical_hit
	speed = arrow_speed
	arc_height = final_arc_height
	progress = 0.0
	_is_releasing = false
	_rotation_update_timer = 0.0
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	monitoring = false
	monitorable = false

	var distance: float = start_pos.distance_to(target_pos)
	duration = distance / speed
	if duration < MIN_FLIGHT_DURATION:
		duration = MIN_FLIGHT_DURATION

	global_position = start_pos
	var look_target: Vector3 = target_pos
	var up_vec := Vector3.UP
	if abs((look_target - global_position).normalized().y) > 0.999:
		up_vec = Vector3.RIGHT
	look_at(look_target, up_vec)

func pool_reset() -> void:
	progress = 0.0
	duration = 1.0
	start_pos = Vector3.ZERO
	target_pos = Vector3.ZERO
	target_node = null
	team = "player"
	damage_source = "bow"
	is_critical_hit = false
	is_fire_arrow = false
	fire_damage = 0.0
	_is_releasing = false
	_rotation_update_timer = 0.0
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	monitoring = false
	monitorable = false

func _release_self() -> void:
	if _is_releasing:
		return
	_is_releasing = true
	if is_inside_tree():
		set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
		call_deferred("_finalize_release")
	else:
		process_mode = Node.PROCESS_MODE_DISABLED
		ScenePool.release(self)

func _finalize_release() -> void:
	if not is_instance_valid(self):
		return
	ScenePool.release(self)

func _physics_process(delta: float) -> void:
	var profile_start := PhysicsFrameProfiler.begin()
	_profiled_physics_process(delta)
	PhysicsFrameProfiler.end("projectile_arrow", profile_start)


func _profiled_physics_process(delta: float) -> void:
	if _is_releasing:
		return
	progress += delta / duration
	
	if progress >= 1.0:
		global_position = _get_visual_target_pos()
		_resolve_terminal_hit(global_position)
		_release_self()
		return
	
	# 수평 이동 (LERP)
	var current_pos = start_pos.lerp(_get_visual_target_pos(), progress)
	
	# 수직 곡선 (sin 이용)
	var y_offset = sin(PI * progress) * arc_height
	current_pos.y += y_offset
	
	# 아주 작은 탄체라 매 physics frame 회전까지 할 필요는 없다.
	_rotation_update_timer += delta
	if _rotation_update_timer >= 0.05 and (current_pos - global_position).length_squared() > 0.001:
		_rotation_update_timer = 0.0
		var dir = (current_pos - global_position).normalized()
		var up_vec = Vector3.UP
		if abs(dir.y) > 0.999:
			up_vec = Vector3.RIGHT
		look_at(current_pos, up_vec)
		
	global_position = current_pos

	# 수면(y=0.0) 타격 감지 기능 추가
	if global_position.y <= 0.0:
		_splash_and_sink()

func _splash_and_sink() -> void:
	# 화살은 스플래시만 작게 재생
	if WATER_BLAST_SCENE:
		var pos := global_position
		pos = Vector3(pos.x, 0.05, pos.z)
		var explosion := VfxSpawnHelper.acquire_world_node3d(get_tree(), WATER_BLAST_SCENE, pos, "water_explosion_small", 2, 60.0)
		if is_instance_valid(explosion):
			if explosion.has_method("configure_as_small"):
				explosion.configure_as_small()
			VfxSpawnHelper.activate(explosion)
		
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_small", global_position, randf_range(0.9, 1.2))
		
	_release_self()

func _get_visual_target_pos() -> Vector3:
	if not is_instance_valid(target_node):
		return target_pos
	if target_node.is_queued_for_deletion():
		return target_pos
	var live_target_pos: Vector3 = _get_arrow_target_aim_point(target_node)
	var planned_to_live := live_target_pos - target_pos
	if planned_to_live.length() > TERMINAL_VISUAL_TRACK_RADIUS:
		planned_to_live = planned_to_live.normalized() * TERMINAL_VISUAL_TRACK_RADIUS
	var converge_t := clampf(
		(progress - TERMINAL_VISUAL_CONVERGE_START) / maxf(1.0 - TERMINAL_VISUAL_CONVERGE_START, 0.001),
		0.0,
		1.0
	)
	converge_t = converge_t * converge_t * (3.0 - 2.0 * converge_t)
	return target_pos + planned_to_live * converge_t


func _resolve_terminal_hit(hit_check_position: Vector3) -> void:
	if not is_instance_valid(target_node):
		return
	if target_node.is_queued_for_deletion():
		return
	if not target_node.is_in_group("soldiers"):
		return
	if NodeContractHelper.get_team_tag(target_node) == team:
		return
	if SoldierStateHelper.is_dead_soldier(target_node):
		return
	var target_aim_point: Vector3 = _get_arrow_target_aim_point(target_node)
	if hit_check_position.distance_to(target_aim_point) > terminal_hit_radius:
		return
	if target_node.has_method("take_damage"):
		var crit_effect_direction := target_node.global_position - start_pos
		var crit_effect_position: Variant = _get_valid_critical_effect_position(target_node) if is_critical_hit else null
		target_node.take_damage(damage, global_position, damage_source)
		if is_critical_hit and crit_effect_position is Vector3:
			_spawn_critical_hit_effect_at_position(crit_effect_position as Vector3, crit_effect_direction)


func _get_arrow_target_aim_point(node: Node) -> Vector3:
	var offset := SOLDIER_AIM_VERTICAL_OFFSET if node.is_in_group("soldiers") else SHIP_AIM_VERTICAL_OFFSET
	return NodeContractHelper.get_projectile_aim_point(node, offset)


func _spawn_critical_hit_effect(target: Node3D, hit_direction: Vector3) -> void:
	if not is_inside_tree() or not is_instance_valid(target):
		return
	var effect_position_variant: Variant = _get_valid_critical_effect_position(target)
	if not effect_position_variant is Vector3:
		return
	_spawn_critical_hit_effect_at_position(effect_position_variant as Vector3, hit_direction)


func _spawn_critical_hit_effect_at_position(effect_position: Vector3, hit_direction: Vector3) -> void:
	if not is_inside_tree() or not effect_position.is_finite():
		return
	var effect := VfxSpawnHelper.acquire_world_node3d(get_tree(), SOLDIER_CRIT_HIT_SCENE, effect_position)
	if not is_instance_valid(effect):
		return
	VfxSpawnHelper.orient_world_node3d(effect, effect_position, hit_direction)
	VfxSpawnHelper.activate(effect)


func _get_valid_critical_effect_position(target: Node3D) -> Variant:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var target_pos := target.global_position
	if not target_pos.is_finite():
		return null
	var owned_ship: Node3D = target.get_owned_ship_node() if target.has_method("get_owned_ship_node") else null
	if not is_instance_valid(owned_ship) or not owned_ship.is_inside_tree():
		return null
	if owned_ship.get("is_sinking") == true or owned_ship.get("is_dying") == true:
		return null
	if owned_ship.has_method("is_sinking_or_dying") and owned_ship.call("is_sinking_or_dying") == true:
		return null
	var local_pos := owned_ship.to_local(target_pos)
	var deck_height: float = float(owned_ship.get("deck_height")) if owned_ship.get("deck_height") != null else 0.4
	if local_pos.y < deck_height - 1.0 or local_pos.y > deck_height + 1.75:
		return null
	var half_ext := Vector2(2.0, 3.0)
	if owned_ship.has_method("get_deck_half_extents"):
		var extents: Variant = owned_ship.call("get_deck_half_extents")
		if extents is Vector2:
			half_ext = extents
	var half_width := half_ext.x
	if owned_ship.has_method("get_deck_half_width_at_z"):
		half_width = maxf(0.08, float(owned_ship.call("get_deck_half_width_at_z", clampf(local_pos.z, -half_ext.y, half_ext.y))))
	if absf(local_pos.z) > half_ext.y + CRIT_EFFECT_DECK_MARGIN or absf(local_pos.x) > half_width + CRIT_EFFECT_DECK_MARGIN:
		return null
	return target_pos + Vector3(0.0, SOLDIER_AIM_VERTICAL_OFFSET, 0.0)
