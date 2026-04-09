extends Area3D
const HitTargetResolver = preload("res://scripts/helpers/hit_target_resolver.gd")
const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")
const NodeContractHelper = preload("res://scripts/helpers/node_contract_helper.gd")
const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const VfxBudget = preload("res://scripts/helpers/vfx_budget.gd")
const WATER_BURST_SCENE = preload("res://scenes/effects/water_burst.tscn")

## 화살 (Arrow)
## 병사가 쏘는 원거리 투사체

@export var damage: float = 15.0
@export var speed: float = 25.0 # 초당 이동 거리 (이전 20.0 -> 8.0 -> 14.0 -> 16.0 -> 25.0)
@export var arc_height: float = 2.0 # 포물선 최대 높이
@export var terminal_hit_radius: float = 3.8

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var target_node: Node3D = null # 목표물 참조 (강제 명중 판정용)
var team: String = "player"
var damage_source: String = "bow"
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
	final_arc_height: float
) -> void:
	start_pos = spawn_position
	target_pos = final_target_pos
	target_node = final_target_node
	team = fire_team
	damage = final_damage
	damage_source = final_damage_source
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
	if duration < 0.2:
		duration = 0.2

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
	if _is_releasing:
		return
	progress += delta / duration
	
	if progress >= 1.0:
		global_position = target_pos
		_resolve_terminal_hit()
		_release_self()
		return
	
	# 수평 이동 (LERP)
	var current_pos = start_pos.lerp(target_pos, progress)
	
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
	if WATER_BURST_SCENE and VfxBudget.allow_spawn(get_tree(), "water_explosion_small", global_position, 2, 60.0):
		var pos = global_position
		var explosion = ScenePool.acquire(get_tree(), WATER_BURST_SCENE)
		if explosion.has_method("configure_as_small"):
			explosion.configure_as_small()
		explosion.position = Vector3(pos.x, 0.05, pos.z)
		get_tree().root.add_child(explosion)
		if explosion.has_method("pool_activate"):
			explosion.pool_activate()
		
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("water_splash_small", global_position, randf_range(0.9, 1.2))
		
	_release_self()

func _resolve_terminal_hit() -> void:
	if not is_instance_valid(target_node):
		return
	if target_node.is_queued_for_deletion():
		return
	if not target_node.is_in_group("soldiers"):
		return
	if NodeContractHelper.get_team_tag(target_node) == team:
		return
	if global_position.distance_to(target_node.global_position) > terminal_hit_radius:
		return
	if target_node.has_method("take_damage"):
		target_node.take_damage(damage, global_position, damage_source)
