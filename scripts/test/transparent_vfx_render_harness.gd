extends Node3D

const FIRE_EFFECT_SCENE := preload("res://scenes/effects/fire_effect.tscn")
const WATER_BLAST_SCENE := preload("res://scenes/effects/water_blast.tscn")
const IMPACT_PUFF_SCENE := preload("res://scenes/effects/impact_puff.tscn")
const FIRE_POT_EXPLOSION_SCENE := preload("res://scenes/effects/fire_pot_explosion.tscn")
const CANNON_MUZZLE_SMOKE_SCENE := preload("res://scenes/effects/cannon_muzzle_smoke.tscn")
const SHIP_WAKE_TRAIL_SCENE := preload("res://scenes/effects/ship_wake_trail.tscn")

@export_range(2.0, 12.0, 0.1) var cycle_seconds: float = 4.5
@export_range(0.5, 8.0, 0.1) var fire_on_seconds: float = 2.6

var _cycle_elapsed: float = 0.0
var _fire_enabled: bool = false
var _fire_effects: Array[Node3D] = []
var _wake: Node = null


func _ready() -> void:
	call_deferred("_setup_harness")


func _setup_harness() -> void:
	_spawn_fire_effect("Slots/FireOverWater")
	_spawn_fire_effect("Slots/FireOverDeck")
	_spawn_fire_effect("Slots/FireBehindSail")
	_spawn_wake_trail()
	_trigger_cycle()
	set_process(true)


func _process(delta: float) -> void:
	_cycle_elapsed += delta
	if _fire_enabled and _cycle_elapsed >= fire_on_seconds:
		_set_fire_enabled(false)
	if _cycle_elapsed >= cycle_seconds:
		_trigger_cycle()


func _trigger_cycle() -> void:
	_cycle_elapsed = 0.0
	_set_fire_enabled(true)
	_spawn_water_blast("Slots/WaterBlast")
	_spawn_water_blast("Slots/DeckWaterBlast", 0.75)
	_spawn_impact_puff("Slots/ImpactPuff")
	_spawn_fire_pot_explosion("Slots/FirePotExplosion")
	_spawn_muzzle_smoke("Slots/MuzzleSmoke")
	if is_instance_valid(_wake) and _wake.has_method("set_wake_state"):
		_wake.call("set_wake_state", true, 0.9, 0.25, 0.3)


func _spawn_fire_effect(marker_path: NodePath) -> void:
	var marker := get_node_or_null(marker_path) as Node3D
	if not is_instance_valid(marker):
		return
	var fire := FIRE_EFFECT_SCENE.instantiate() as Node3D
	if fire == null:
		return
	add_child(fire)
	fire.global_transform = marker.global_transform
	if fire.has_method("set_fire_active"):
		fire.call("set_fire_active", true, true)
	_fire_effects.append(fire)


func _set_fire_enabled(enabled: bool) -> void:
	_fire_enabled = enabled
	for fire in _fire_effects:
		if is_instance_valid(fire) and fire.has_method("set_fire_active"):
			fire.call("set_fire_active", enabled, enabled)


func _spawn_water_blast(marker_path: NodePath, intensity: float = 0.9) -> void:
	var effect := _spawn_scene_at_marker(WATER_BLAST_SCENE, marker_path)
	if not is_instance_valid(effect):
		return
	if effect.has_method("configure_as_splash"):
		effect.call("configure_as_splash")
	if effect.has_method("set_intensity"):
		effect.call("set_intensity", intensity)
	_activate_pooled_effect(effect)


func _spawn_impact_puff(marker_path: NodePath) -> void:
	var effect := _spawn_scene_at_marker(IMPACT_PUFF_SCENE, marker_path)
	if not is_instance_valid(effect):
		return
	if effect.has_method("set_intensity"):
		effect.call("set_intensity", 1.0)
	_activate_pooled_effect(effect)


func _spawn_fire_pot_explosion(marker_path: NodePath) -> void:
	var effect := _spawn_scene_at_marker(FIRE_POT_EXPLOSION_SCENE, marker_path)
	if not is_instance_valid(effect):
		return
	_activate_pooled_effect(effect)


func _spawn_muzzle_smoke(marker_path: NodePath) -> void:
	var effect := _spawn_scene_at_marker(CANNON_MUZZLE_SMOKE_SCENE, marker_path)
	if not is_instance_valid(effect):
		return
	_restart_particles_recursive(effect)
	var lifetime := _get_max_particle_lifetime(effect) + 0.4
	get_tree().create_timer(lifetime).timeout.connect(effect.queue_free)


func _spawn_wake_trail() -> void:
	var marker := get_node_or_null("Slots/WakeTrail") as Node3D
	if not is_instance_valid(marker):
		return
	_wake = SHIP_WAKE_TRAIL_SCENE.instantiate()
	if not is_instance_valid(_wake):
		return
	add_child(_wake)
	if _wake is Node3D:
		(_wake as Node3D).global_transform = marker.global_transform
	_wake.set("auto_fit_to_parent_ship", false)
	if _wake.has_method("set_wake_state"):
		_wake.call("set_wake_state", true, 0.9, 0.0, 0.2)


func _spawn_scene_at_marker(scene: PackedScene, marker_path: NodePath) -> Node:
	var marker := get_node_or_null(marker_path) as Node3D
	if not is_instance_valid(marker) or scene == null:
		return null
	var effect := ScenePool.acquire(get_tree(), scene)
	if not is_instance_valid(effect):
		return null
	add_child(effect)
	if effect is Node3D:
		(effect as Node3D).global_transform = marker.global_transform
	return effect


func _activate_pooled_effect(effect: Node) -> void:
	if effect.has_method("pool_activate"):
		effect.call_deferred("pool_activate")
	else:
		_restart_particles_recursive(effect)


func _restart_particles_recursive(node: Node) -> void:
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.visible = true
		particles.restart()
		particles.emitting = true
	for child in node.get_children():
		_restart_particles_recursive(child)


func _get_max_particle_lifetime(node: Node) -> float:
	var max_lifetime := 0.0
	if node is GPUParticles3D:
		max_lifetime = maxf(max_lifetime, (node as GPUParticles3D).lifetime)
	for child in node.get_children():
		max_lifetime = maxf(max_lifetime, _get_max_particle_lifetime(child))
	return max_lifetime
