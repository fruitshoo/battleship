extends Area3D

const WoodSplinter = preload("res://scripts/effects/wood_splinter.gd")
const VfxSpawnHelper = preload("res://scripts/helpers/vfx_spawn_helper.gd")
const SOLDIER_CRIT_HIT_SCENE = preload("res://scenes/effects/soldier_crit_hit.tscn")
const DEFAULT_SHIP_IMPACT_PUFF_SCENE = preload("res://scenes/effects/impact_puff.tscn")
const DEFAULT_WOOD_SPLINTER_SCENE = preload("res://scenes/effects/wood_splinter.tscn")
const SOLDIER_AIM_VERTICAL_OFFSET: float = 1.05
const SHIP_AIM_VERTICAL_OFFSET: float = 0.65
const MIN_FLIGHT_DURATION: float = 0.08
const TERMINAL_HIT_RADIUS: float = 1.6
const SHIP_HIT_FEEDBACK_DAMAGE_FLOOR: float = 24.0
const SHIP_HIT_FEEDBACK_Y_OFFSET: float = 0.35
const SOLDIER_HIT_EFFECT_DECK_MARGIN: float = 0.55

@export var damage: float = 24.0
@export var speed: float = 58.0

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var target_node: Node3D = null
var team: String = "enemy"
var damage_source: String = "small_cannonball"

var progress: float = 0.0
var duration: float = 1.0
var _is_releasing: bool = false


func _ready() -> void:
	pool_reset()


func _enter_tree() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	EntityRegistry.register_projectile(self)


func _exit_tree() -> void:
	EntityRegistry.unregister_projectile(self)


func pool_capacity() -> int:
	return 32


func restart_flight() -> void:
	progress = 0.0
	_is_releasing = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	monitoring = false
	monitorable = false
	var distance := start_pos.distance_to(target_pos)
	duration = maxf(distance / maxf(speed, 1.0), MIN_FLIGHT_DURATION)
	global_position = start_pos


func pool_reset() -> void:
	progress = 0.0
	duration = 1.0
	start_pos = Vector3.ZERO
	target_pos = Vector3.ZERO
	target_node = null
	team = "enemy"
	damage_source = "small_cannonball"
	_is_releasing = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	monitoring = false
	monitorable = false


func _physics_process(delta: float) -> void:
	if _is_releasing:
		return
	progress += delta / duration
	var next_pos := start_pos.lerp(_get_visual_target_pos(), clampf(progress, 0.0, 1.0))
	if next_pos.distance_squared_to(global_position) > 0.0001:
		look_at(next_pos, Vector3.UP)
	global_position = next_pos
	if progress >= 1.0:
		_resolve_terminal_hit(global_position)
		_release_self()


func _get_visual_target_pos() -> Vector3:
	if not is_instance_valid(target_node) or target_node.is_queued_for_deletion():
		return target_pos
	var live_target_pos := _get_target_aim_point(target_node)
	return target_pos.lerp(live_target_pos, clampf(progress, 0.0, 1.0))


func _resolve_terminal_hit(hit_position: Vector3) -> void:
	if not is_instance_valid(target_node) or target_node.is_queued_for_deletion():
		return
	if target_node.is_in_group("soldiers"):
		if NodeContractHelper.get_team_tag(target_node) == team:
			return
		if SoldierStateHelper.is_dead_soldier(target_node):
			return
		if hit_position.distance_to(_get_target_aim_point(target_node)) > TERMINAL_HIT_RADIUS:
			return
		if target_node.has_method("take_damage"):
			var hit_effect_position: Variant = _get_valid_soldier_hit_effect_position(target_node as Node3D)
			target_node.take_damage(damage, hit_position, damage_source)
			if hit_effect_position is Vector3:
				_spawn_hit_spark(hit_effect_position as Vector3)
		return

	var ship := HitTargetResolver.resolve_ship_from_node(target_node)
	if not is_instance_valid(ship):
		return
	if HitTargetResolver.resolve_team_tag(ship) == team:
		return
	if ship.has_method("is_sinking_or_dying") and ship.is_sinking_or_dying():
		return
	if ship.has_method("take_damage"):
		var impact_position := _resolve_ship_impact_position(ship, hit_position)
		_spawn_ship_hit_feedback(ship, impact_position)
		ship.take_damage(damage, impact_position, damage_source)


func _get_target_aim_point(node: Node) -> Vector3:
	var offset := SOLDIER_AIM_VERTICAL_OFFSET if node.is_in_group("soldiers") else SHIP_AIM_VERTICAL_OFFSET
	return NodeContractHelper.get_projectile_aim_point(node, offset)


func _spawn_hit_spark(effect_position: Vector3) -> void:
	if not is_inside_tree():
		return
	var effect := VfxSpawnHelper.acquire_world_node3d(get_tree(), SOLDIER_CRIT_HIT_SCENE, effect_position)
	if not is_instance_valid(effect):
		return
	VfxSpawnHelper.activate(effect)


func _get_valid_soldier_hit_effect_position(target: Node3D) -> Variant:
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
	if absf(local_pos.z) > half_ext.y + SOLDIER_HIT_EFFECT_DECK_MARGIN or absf(local_pos.x) > half_width + SOLDIER_HIT_EFFECT_DECK_MARGIN:
		return null
	return target_pos + Vector3(0.0, SOLDIER_AIM_VERTICAL_OFFSET, 0.0)


func _resolve_ship_impact_position(ship: Node3D, hit_position: Vector3) -> Vector3:
	if hit_position != Vector3.ZERO and hit_position.is_finite():
		return hit_position
	return _get_target_aim_point(ship)


func _spawn_ship_hit_feedback(ship: Node3D, impact_position: Vector3) -> void:
	if not is_inside_tree() or not is_instance_valid(ship):
		return
	var effect_position := impact_position + Vector3(0.0, SHIP_HIT_FEEDBACK_Y_OFFSET, 0.0)
	_spawn_ship_impact_puff(ship, effect_position)
	_spawn_ship_impact_splinters(ship, effect_position, impact_position - global_position)
	var audio_manager = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_manager) and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("impact_wood", effect_position, randf_range(0.9, 1.08), 1.5)


func _spawn_ship_impact_puff(ship: Node3D, effect_position: Vector3) -> void:
	var scene: PackedScene = DEFAULT_SHIP_IMPACT_PUFF_SCENE
	if "impact_puff_scene" in ship and ship.get("impact_puff_scene") != null:
		scene = ship.get("impact_puff_scene") as PackedScene
	if scene == null:
		return
	var puff := VfxSpawnHelper.acquire_world_node3d(get_tree(), scene, effect_position, "small_cannonball_ship_hit", 5, 90.0)
	if not is_instance_valid(puff):
		return
	if puff.has_method("set_intensity"):
		puff.set_intensity(1.15)
	VfxSpawnHelper.activate(puff)


func _spawn_ship_impact_splinters(ship: Node3D, effect_position: Vector3, impact_direction: Vector3) -> void:
	var scene: PackedScene = DEFAULT_WOOD_SPLINTER_SCENE
	if "wood_splinter_scene" in ship and ship.get("wood_splinter_scene") != null:
		scene = ship.get("wood_splinter_scene") as PackedScene
	if scene == null:
		return
	WoodSplinter.spawn_burst(
		get_tree(),
		scene,
		effect_position,
		maxf(damage, SHIP_HIT_FEEDBACK_DAMAGE_FLOOR),
		impact_direction,
		"small_cannonball_splinter",
		4,
		90.0
	)


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
