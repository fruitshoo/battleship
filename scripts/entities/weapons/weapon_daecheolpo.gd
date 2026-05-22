extends "res://scripts/entities/weapons/weapon.gd"

const SOLDIER_AIM_VERTICAL_OFFSET: float = 1.05
const SHIP_AIM_VERTICAL_OFFSET: float = 0.65
const BASE_SOLDIER_DAMAGE: float = 12.0
const BASE_HULL_DAMAGE: float = 8.0
const NODE_MUZZLE := "Muzzle"

@export var shot_scene: PackedScene = preload("res://scenes/projectiles/small_cannonball.tscn")
@export var muzzle_smoke_scene: PackedScene = preload("res://scenes/effects/cannon_muzzle_smoke.tscn")
@export var shoot_cooldown: float = 5.3
@export var max_range: float = 22.0
@export var projectile_speed: float = 36.0
@export_range(0.05, 0.6, 0.01) var muzzle_smoke_scale: float = 0.18
@export var fire_sfx: String = "musket_fire"
@export var ballistic_trace_enabled: bool = true
@export_range(1.0, 18.0, 0.5) var ballistic_trace_max_length: float = 7.5
@export_range(0.01, 0.16, 0.005) var ballistic_trace_width: float = 0.035
@export_range(0.03, 0.18, 0.01) var ballistic_trace_lifetime: float = 0.08
@export var ballistic_trace_color: Color = Color(1.0, 0.78, 0.36, 0.68)

var _owner_damage_bonus_pct: float = 0.0
var _cached_spawn_parent: Node = null
@onready var muzzle: Marker3D = get_node_or_null(NODE_MUZZLE) as Marker3D


func _ready() -> void:
	attack_range = max_range
	attack_cooldown = shoot_cooldown
	_apply_effective_damage()


func can_target_ships() -> bool:
	return true


func apply_owner_damage_bonus_pct(damage_bonus_pct: float) -> void:
	_owner_damage_bonus_pct = maxf(0.0, damage_bonus_pct)
	_apply_effective_damage()


func attack(target: Node3D, attacker: Node3D) -> void:
	if not is_instance_valid(target) or shot_scene == null:
		return
	if target.is_in_group("soldiers") and SoldierStateHelper.is_dead_soldier(target):
		return

	var shot := ScenePool.acquire(attacker.get_tree(), shot_scene) as Node3D
	if not is_instance_valid(shot):
		return

	var target_pos := _get_aim_point(target)
	var spawn_pos := _get_muzzle_position(attacker)
	var travel_time := clampf(spawn_pos.distance_to(target_pos) / maxf(projectile_speed, 1.0), 0.08, 0.55)
	var local_velocity: Vector3 = target.get_velocity_value() if target.has_method("get_velocity_value") else (target.get("velocity") if "velocity" in target else Vector3.ZERO)
	var ship_velocity := Vector3.ZERO
	var target_ship: Node3D = target.get_owned_ship_node() if target.has_method("get_owned_ship_node") else (target if target.has_method("get_hull_ratio") else null)
	if is_instance_valid(target_ship) and target_ship.has_method("get_current_speed_value"):
		var ship_speed: float = target_ship.get_current_speed_value()
		if ship_speed > 0.1:
			var ship_dir: Vector3 = -target_ship.global_transform.basis.z.normalized()
			if target_ship.has_method("get_move_direction_value"):
				ship_dir = target_ship.get_move_direction_value()
			ship_velocity = ship_dir * ship_speed
	target_pos += (local_velocity + ship_velocity) * travel_time * 0.65
	target_pos.x += randf_range(-0.18, 0.18)
	target_pos.z += randf_range(-0.18, 0.18)
	_spawn_ballistic_trace(attacker, spawn_pos, target_pos)
	_spawn_muzzle_effect(attacker, spawn_pos, target_pos)
	_play_fire_sfx(attacker, spawn_pos)

	var team_name: String = attacker.get_team_tag() if attacker.has_method("get_team_tag") else "enemy"
	var shot_damage := damage if target.is_in_group("soldiers") else BASE_HULL_DAMAGE
	if "start_pos" in shot:
		shot.start_pos = spawn_pos
	if "target_pos" in shot:
		shot.target_pos = target_pos
	if "target_node" in shot:
		shot.target_node = target
	if "team" in shot:
		shot.team = team_name
	if "damage" in shot:
		shot.damage = shot_damage
	if "damage_source" in shot:
		shot.damage_source = "daecheolpo"
	if "speed" in shot:
		shot.speed = projectile_speed

	var spawn_parent := _resolve_spawn_parent(attacker.get_tree())
	spawn_parent.add_child(shot)
	shot.global_position = spawn_pos
	if shot.has_method("restart_flight"):
		shot.restart_flight()
	if shot.global_position.distance_squared_to(target_pos) > 0.0001:
		shot.look_at(target_pos, Vector3.UP)


func _spawn_muzzle_effect(attacker: Node3D, spawn_pos: Vector3, target_pos: Vector3) -> void:
	if muzzle_smoke_scene == null or not is_instance_valid(attacker):
		return
	var tree := attacker.get_tree()
	if not is_instance_valid(tree):
		return
	var smoke := ScenePool.acquire(tree, muzzle_smoke_scene)
	if not is_instance_valid(smoke):
		return
	var parent := _resolve_spawn_parent(tree)
	parent.add_child(smoke)
	if smoke is Node3D:
		var smoke_node := smoke as Node3D
		var fire_dir := (target_pos - spawn_pos).normalized()
		if fire_dir.is_zero_approx():
			fire_dir = -attacker.global_transform.basis.z.normalized()
		if fire_dir.is_zero_approx():
			fire_dir = Vector3.FORWARD
		smoke_node.global_transform = Transform3D(Basis.looking_at(fire_dir, Vector3.UP), spawn_pos)
		smoke_node.scale = Vector3.ONE * muzzle_smoke_scale
	if smoke.has_method("pool_activate"):
		smoke.pool_activate()
	else:
		_activate_plain_muzzle_smoke(smoke, tree)


func _spawn_ballistic_trace(attacker: Node3D, spawn_pos: Vector3, target_pos: Vector3) -> void:
	if not ballistic_trace_enabled or not is_instance_valid(attacker):
		return
	var tree := attacker.get_tree()
	if not is_instance_valid(tree):
		return
	if not spawn_pos.is_finite() or not target_pos.is_finite():
		return
	var trace_vector := target_pos - spawn_pos
	var distance := trace_vector.length()
	if distance <= 0.1:
		return
	if not VfxBudget.allow_spawn(tree, "daecheolpo_trace", spawn_pos, 10, 90.0):
		return

	var direction := trace_vector / distance
	var start := spawn_pos + direction * 0.22
	var length := minf(distance, ballistic_trace_max_length) * randf_range(0.82, 1.08)
	var end := start + direction * length
	var center := start.lerp(end, 0.5)

	var mesh := BoxMesh.new()
	var width := ballistic_trace_width * randf_range(0.78, 1.18)
	mesh.size = Vector3(width, width, maxf(0.1, length))

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = _jitter_trace_color(ballistic_trace_color)
	material.emission_enabled = true
	material.emission = Color(material.albedo_color.r, material.albedo_color.g, material.albedo_color.b, 1.0)
	material.emission_energy_multiplier = 0.65
	material.render_priority = 18

	var trace := MeshInstance3D.new()
	trace.name = "DaecheolpoTrace"
	trace.mesh = mesh
	trace.material_override = material
	trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trace.extra_cull_margin = 0.5

	var parent := _resolve_spawn_parent(tree)
	parent.add_child(trace)
	trace.global_transform = Transform3D(_trace_basis(direction), center)

	var fade_color := material.albedo_color
	fade_color.a = 0.0
	var tween := trace.create_tween()
	tween.set_parallel(true)
	tween.tween_property(material, "albedo_color", fade_color, ballistic_trace_lifetime)
	tween.tween_property(trace, "scale", Vector3(0.2, 0.2, 1.0), ballistic_trace_lifetime)
	tween.set_parallel(false)
	tween.tween_callback(trace.queue_free)


func _trace_basis(direction: Vector3) -> Basis:
	var dir := direction.normalized()
	if dir.is_zero_approx():
		dir = Vector3.FORWARD
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.96:
		up = Vector3.RIGHT
	return Basis.looking_at(dir, up)


func _jitter_trace_color(base_color: Color) -> Color:
	return Color(
		clampf(base_color.r * randf_range(0.92, 1.12), 0.0, 1.4),
		clampf(base_color.g * randf_range(0.88, 1.08), 0.0, 1.4),
		clampf(base_color.b * randf_range(0.78, 1.06), 0.0, 1.2),
		clampf(base_color.a * randf_range(0.78, 1.0), 0.0, 1.0)
	)


func _play_fire_sfx(attacker: Node3D, spawn_pos: Vector3) -> void:
	var audio_manager = attacker.get_node_or_null("/root/AudioManager") if is_instance_valid(attacker) else null
	if not is_instance_valid(audio_manager) or not audio_manager.has_method("play_sfx"):
		return
	audio_manager.play_sfx(fire_sfx, spawn_pos, randf_range(0.96, 1.04))


func _get_muzzle_position(attacker: Node3D) -> Vector3:
	if is_instance_valid(muzzle):
		return muzzle.global_position
	return attacker.global_position + Vector3(0.0, 0.95, 0.0)


func _activate_plain_muzzle_smoke(smoke: Node, tree: SceneTree) -> void:
	var max_lifetime := _restart_plain_muzzle_particles(smoke)
	if max_lifetime <= 0.0:
		ScenePool.release(smoke)
		return
	tree.create_timer(max_lifetime + 0.25).timeout.connect(func() -> void:
		ScenePool.release(smoke)
	)


func _restart_plain_muzzle_particles(node: Node) -> float:
	var max_lifetime := 0.0
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.visible = true
		particles.restart()
		particles.emitting = true
		max_lifetime = maxf(max_lifetime, particles.lifetime)
	for child in node.get_children():
		max_lifetime = maxf(max_lifetime, _restart_plain_muzzle_particles(child))
	return max_lifetime


func _apply_effective_damage() -> void:
	damage = BASE_SOLDIER_DAMAGE * (1.0 + _owner_damage_bonus_pct)


func _get_aim_point(target: Node) -> Vector3:
	var offset := SOLDIER_AIM_VERTICAL_OFFSET if target.is_in_group("soldiers") else SHIP_AIM_VERTICAL_OFFSET
	return NodeContractHelper.get_projectile_aim_point(target, offset)


func _resolve_spawn_parent(tree: SceneTree) -> Node:
	if is_instance_valid(_cached_spawn_parent):
		return _cached_spawn_parent
	var lm = LevelManagerRegistry.get_level_manager(tree)
	if is_instance_valid(lm):
		_cached_spawn_parent = lm
		return _cached_spawn_parent
	_cached_spawn_parent = tree.root
	return _cached_spawn_parent
