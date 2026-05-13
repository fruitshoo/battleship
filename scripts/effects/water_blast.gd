extends Node3D


@export_enum("splash", "small", "sink", "corpse_cleanup", "ship_collision") var preset: String = "splash"
@export var lock_to_waterline: bool = true
@export_range(-1.0, 1.0, 0.01) var waterline_y: float = 0.05

@onready var foam_disk: MeshInstance3D = get_node_or_null("FoamDisk")
@onready var column_card: MeshInstance3D = get_node_or_null("ColumnCard")
@onready var splash_cards_root: Node3D = get_node_or_null("SplashCards")
@onready var mist_card: MeshInstance3D = get_node_or_null("MistCard")
@onready var droplet_particles: GPUParticles3D = get_node_or_null("DropletParticles")
@onready var blast_floor_particles: GPUParticles3D = get_node_or_null("floor")
@onready var blast_mist_particles: GPUParticles3D = get_node_or_null("mist")
@onready var blast_spray_particles: GPUParticles3D = get_node_or_null("particles")

var _budget_key_value: String = "water_explosion"
var _budget_limit_value: int = 4
var _budget_distance_value: float = 70.0
var _active: bool = false
var _activate_when_ready: bool = false
var _activation_request_id: int = 0
var _elapsed: float = 0.0
var _duration: float = 0.75
var _intensity_scale: float = 1.0

var _foam_enabled: bool = true
var _foam_start_scale: float = 0.35
var _foam_end_scale: float = 2.2
var _foam_alpha: float = 0.68

var _column_enabled: bool = true
var _column_start_scale: Vector2 = Vector2(0.55, 0.7)
var _column_end_scale: Vector2 = Vector2(1.15, 1.55)
var _column_alpha: float = 0.56

var _splash_cards: Array[MeshInstance3D] = []
var _splash_card_materials: Array = []
var _splash_cards_enabled: bool = true
var _splash_card_count: int = 4
var _splash_card_start_scale: Vector2 = Vector2(0.18, 0.42)
var _splash_card_end_scale: Vector2 = Vector2(0.72, 1.45)
var _splash_card_alpha: float = 0.72
var _splash_card_radius: float = 0.24
var _splash_card_rise: float = 0.34

var _mist_enabled: bool = true
var _mist_start_scale: Vector2 = Vector2(0.7, 0.55)
var _mist_end_scale: Vector2 = Vector2(1.75, 1.25)
var _mist_alpha: float = 0.28

var _droplets_enabled: bool = true
var _blast_particles: Array[GPUParticles3D] = []
var _blast_scale: float = 1.0
var _waterline_lift: float = 0.0
var _foam_material: StandardMaterial3D
var _column_material: StandardMaterial3D
var _mist_material: StandardMaterial3D


func _enter_tree() -> void:
	if _activate_when_ready and is_node_ready():
		_defer_pool_activate()


func _ready() -> void:
	var activate_after_ready := _activate_when_ready
	_cache_nodes()
	_prepare_local_materials()
	_apply_preset()
	pool_reset()
	if _is_prewarm_mode():
		return
	if activate_after_ready:
		_activate_when_ready = true
		pool_activate()


func configure_as_splash() -> void:
	preset = "splash"
	if is_node_ready():
		_apply_preset()


func configure_as_ship_collision() -> void:
	preset = "ship_collision"
	if is_node_ready():
		_apply_preset()


func configure_as_small() -> void:
	preset = "small"
	if is_node_ready():
		_apply_preset()


func configure_as_sink() -> void:
	preset = "sink"
	if is_node_ready():
		_apply_preset()


func configure_as_corpse_cleanup() -> void:
	preset = "corpse_cleanup"
	if is_node_ready():
		_apply_preset()


func set_intensity(scale_value: float) -> void:
	_intensity_scale = clampf(scale_value, 0.4, 4.0)
	if is_node_ready():
		_apply_preset()


func pool_capacity() -> int:
	return 14


func pool_activate() -> void:
	if not is_inside_tree():
		_activate_when_ready = true
		return
	if _is_parked_in_scene_pool():
		_activate_when_ready = false
		return
	_activate_when_ready = false
	_cache_nodes()
	_prepare_local_materials()
	_apply_preset()
	if not VfxBudget.allow_spawn(get_tree(), _budget_key_value, global_position, _budget_limit_value, _budget_distance_value):
		ScenePool.release(self)
		return

	_align_to_waterline()
	_active = true
	_elapsed = 0.0
	visible = true
	set_process(true)
	_apply_blast_scale()
	_layout_splash_cards()
	_apply_visual_state(0.0)
	_start_droplets()
	_start_blast_particles()


func pool_reset() -> void:
	_activation_request_id += 1
	_activate_when_ready = false
	_cache_nodes()
	_active = false
	_elapsed = 0.0
	_intensity_scale = 1.0
	set_process(false)
	visible = false
	_set_card_visible(foam_disk, false)
	_set_card_visible(column_card, false)
	_set_splash_cards_visible(false)
	_set_card_visible(mist_card, false)
	if is_instance_valid(droplet_particles):
		droplet_particles.emitting = false
		droplet_particles.visible = false
	_stop_blast_particles()


func _defer_pool_activate() -> void:
	_activation_request_id += 1
	var request_id := _activation_request_id
	call_deferred("_pool_activate_deferred", request_id)


func _pool_activate_deferred(request_id: int) -> void:
	if request_id != _activation_request_id:
		return
	pool_activate()


func _is_parked_in_scene_pool() -> bool:
	var parent_node := get_parent()
	return is_instance_valid(parent_node) and parent_node.name == "__ScenePoolRoot"


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var t: float = clampf(_elapsed / maxf(_duration, 0.01), 0.0, 1.0)
	_apply_visual_state(t)
	if _elapsed >= _duration + 0.18:
		ScenePool.release(self)


func _apply_preset() -> void:
	_cache_nodes()
	match preset:
		"small":
			_apply_small_preset()
		"sink":
			_apply_sink_preset()
		"corpse_cleanup":
			_apply_corpse_cleanup_preset()
		"ship_collision":
			_apply_ship_collision_preset()
		_:
			_apply_splash_preset()


func _apply_splash_preset() -> void:
	var intensity := _intensity_scale
	var base_size_scale := lerpf(0.9, 1.45, clampf(inverse_lerp(0.7, 2.0, intensity), 0.0, 1.0))
	var high_speed_scale := lerpf(1.0, 2.0, clampf(inverse_lerp(2.0, 4.0, intensity), 0.0, 1.0))
	var size_scale := base_size_scale * high_speed_scale
	_budget_key_value = "water_explosion"
	_budget_limit_value = 4
	_budget_distance_value = 70.0
	_waterline_lift = 0.0
	_duration = 0.72 + (0.08 * intensity)
	_blast_scale = size_scale

	_foam_enabled = true
	_foam_start_scale = 0.35 * size_scale
	_foam_end_scale = 2.35 * size_scale
	_foam_alpha = 0.72

	_column_enabled = true
	_column_start_scale = Vector2(0.52, 0.78) * size_scale
	_column_end_scale = Vector2(1.15, 1.85) * size_scale
	_column_alpha = 0.72

	_splash_cards_enabled = true
	_splash_card_count = 4
	_splash_card_start_scale = Vector2(0.18, 0.42) * size_scale
	_splash_card_end_scale = Vector2(0.7, 1.45) * size_scale
	_splash_card_alpha = 0.76
	_splash_card_radius = 0.26 * size_scale
	_splash_card_rise = 0.34 * size_scale

	_mist_enabled = true
	_mist_start_scale = Vector2(0.7, 0.55) * size_scale
	_mist_end_scale = Vector2(1.75, 1.25) * size_scale
	_mist_alpha = 0.24

	_droplets_enabled = true
	_configure_droplets(
		clampi(int(round(14.0 * intensity)), 10, 24),
		0.62 + (0.08 * intensity),
		2.6 * intensity,
		6.6 * intensity,
		0.03,
		0.09 * size_scale
	)


func _apply_ship_collision_preset() -> void:
	var intensity := _intensity_scale
	var high_speed_t := clampf(inverse_lerp(3.35, 4.0, intensity), 0.0, 1.0)
	var high_speed_boost := lerpf(1.0, 1.18, high_speed_t)
	var size_scale := lerpf(2.55, 3.35, clampf(inverse_lerp(2.2, 4.0, intensity), 0.0, 1.0)) * high_speed_boost
	_budget_key_value = "ship_collision_water_blast"
	_budget_limit_value = 3
	_budget_distance_value = 85.0
	_waterline_lift = 0.0
	_duration = 0.86 + (0.06 * clampf(intensity, 0.0, 4.0))
	_blast_scale = size_scale

	_foam_enabled = true
	_foam_start_scale = 0.42 * size_scale
	_foam_end_scale = 2.95 * size_scale
	_foam_alpha = 0.76

	_column_enabled = true
	_column_start_scale = Vector2(0.7, 0.95) * size_scale
	_column_end_scale = Vector2(1.55, 2.35) * size_scale
	_column_alpha = 0.76

	_splash_cards_enabled = true
	_splash_card_count = 5
	_splash_card_start_scale = Vector2(0.22, 0.5) * size_scale
	_splash_card_end_scale = Vector2(0.95, 1.95) * size_scale
	_splash_card_alpha = 0.78
	_splash_card_radius = 0.34 * size_scale
	_splash_card_rise = 0.43 * size_scale

	_mist_enabled = true
	_mist_start_scale = Vector2(0.85, 0.62) * size_scale
	_mist_end_scale = Vector2(2.35, 1.55) * size_scale
	_mist_alpha = 0.3

	_droplets_enabled = true
	_configure_droplets(
		clampi(int(round(18.0 + intensity * 4.0 + high_speed_t * 5.0)), 18, 39),
		0.76 + (0.06 * intensity),
		4.6 + (1.1 * intensity) + (1.2 * high_speed_t),
		9.0 + (1.8 * intensity) + (2.2 * high_speed_t),
		0.04,
		0.13 * size_scale
	)


func _apply_small_preset() -> void:
	var intensity := _intensity_scale
	var size_scale := lerpf(0.72, 1.05, inverse_lerp(0.7, 2.0, intensity))
	_budget_key_value = "water_explosion_small"
	_budget_limit_value = 2
	_budget_distance_value = 60.0
	_waterline_lift = 0.0
	_duration = 0.46
	_blast_scale = size_scale * 0.58

	_foam_enabled = true
	_foam_start_scale = 0.22 * size_scale
	_foam_end_scale = 1.25 * size_scale
	_foam_alpha = 0.58

	_column_enabled = false
	_splash_cards_enabled = true
	_splash_card_count = 2
	_splash_card_start_scale = Vector2(0.12, 0.25) * size_scale
	_splash_card_end_scale = Vector2(0.42, 0.82) * size_scale
	_splash_card_alpha = 0.5
	_splash_card_radius = 0.11 * size_scale
	_splash_card_rise = 0.16 * size_scale
	_mist_enabled = false
	_droplets_enabled = true
	_configure_droplets(6, 0.44, 1.9 * intensity, 4.2 * intensity, 0.025, 0.065 * size_scale)


func _apply_corpse_cleanup_preset() -> void:
	var intensity := _intensity_scale
	var size_scale := lerpf(0.58, 0.92, inverse_lerp(0.4, 1.2, intensity))
	_budget_key_value = "corpse_cleanup_splash"
	_budget_limit_value = 8
	_budget_distance_value = -1.0
	_waterline_lift = 0.06
	_duration = 0.38 + (0.05 * intensity)
	_blast_scale = size_scale * 0.42

	_foam_enabled = true
	_foam_start_scale = 0.14 * size_scale
	_foam_end_scale = 0.82 * size_scale
	_foam_alpha = 0.46

	_column_enabled = false
	_splash_cards_enabled = true
	_splash_card_count = 2
	_splash_card_start_scale = Vector2(0.08, 0.18) * size_scale
	_splash_card_end_scale = Vector2(0.30, 0.58) * size_scale
	_splash_card_alpha = 0.42
	_splash_card_radius = 0.08 * size_scale
	_splash_card_rise = 0.11 * size_scale

	_mist_enabled = false
	_droplets_enabled = true
	_configure_droplets(5, 0.34, 1.25 * intensity, 3.1 * intensity, 0.022, 0.045 * size_scale)


func _apply_sink_preset() -> void:
	var intensity := _intensity_scale
	var size_scale := lerpf(1.05, 1.75, inverse_lerp(0.7, 2.0, intensity))
	_budget_key_value = "ship_sinking_bubbles"
	_budget_limit_value = 2
	_budget_distance_value = 85.0
	_waterline_lift = 0.0
	_duration = 1.35 + (0.2 * intensity)
	_blast_scale = size_scale * 1.18

	_foam_enabled = true
	_foam_start_scale = 0.65 * size_scale
	_foam_end_scale = 3.35 * size_scale
	_foam_alpha = 0.64

	_column_enabled = true
	_column_start_scale = Vector2(0.8, 0.9) * size_scale
	_column_end_scale = Vector2(1.65, 1.85) * size_scale
	_column_alpha = 0.56

	_splash_cards_enabled = true
	_splash_card_count = 5
	_splash_card_start_scale = Vector2(0.24, 0.5) * size_scale
	_splash_card_end_scale = Vector2(0.95, 1.85) * size_scale
	_splash_card_alpha = 0.68
	_splash_card_radius = 0.42 * size_scale
	_splash_card_rise = 0.42 * size_scale

	_mist_enabled = true
	_mist_start_scale = Vector2(1.0, 0.8) * size_scale
	_mist_end_scale = Vector2(2.8, 1.65) * size_scale
	_mist_alpha = 0.34

	_droplets_enabled = true
	_configure_droplets(
		clampi(int(round(10.0 * intensity)), 8, 18),
		0.78 + (0.12 * intensity),
		1.8 * intensity,
		5.1 * intensity,
		0.028,
		0.08 * size_scale
	)


func _apply_visual_state(t: float) -> void:
	_cache_nodes()
	var out_t := _ease_out_quad(t)
	var late_fade := 1.0 - smoothstep(0.45, 1.0, t)
	var quick_fade := 1.0 - smoothstep(0.18, 0.78, t)

	if _foam_enabled and is_instance_valid(foam_disk):
		var foam_scale := lerpf(_foam_start_scale, _foam_end_scale, out_t)
		_set_card_visible(foam_disk, true)
		foam_disk.scale = Vector3(foam_scale, 1.0, foam_scale)
		_set_material_alpha(_foam_material, _foam_alpha * late_fade)
	else:
		_set_card_visible(foam_disk, false)

	if _column_enabled and is_instance_valid(column_card):
		var column_scale := _column_start_scale.lerp(_column_end_scale, out_t)
		_set_card_visible(column_card, true)
		column_card.scale = Vector3(column_scale.x, column_scale.y, 1.0)
		column_card.position.y = lerpf(0.45, 0.72, out_t)
		_set_material_alpha(_column_material, _column_alpha * quick_fade)
	else:
		_set_card_visible(column_card, false)

	_apply_splash_cards_visual_state(t, out_t, quick_fade)

	if _mist_enabled and is_instance_valid(mist_card):
		var mist_scale := _mist_start_scale.lerp(_mist_end_scale, out_t)
		_set_card_visible(mist_card, true)
		mist_card.scale = Vector3(mist_scale.x, mist_scale.y, 1.0)
		mist_card.position.y = lerpf(0.28, 0.62, out_t)
		_set_material_alpha(_mist_material, _mist_alpha * late_fade)
	else:
		_set_card_visible(mist_card, false)


func _start_droplets() -> void:
	_cache_nodes()
	if not is_instance_valid(droplet_particles):
		return
	droplet_particles.visible = _droplets_enabled
	droplet_particles.emitting = false
	if not _droplets_enabled:
		return
	droplet_particles.restart()
	droplet_particles.emitting = true


func _configure_droplets(next_amount: int, next_lifetime: float, velocity_min: float, velocity_max: float, scale_min_value: float, scale_max_value: float) -> void:
	_cache_nodes()
	if not is_instance_valid(droplet_particles):
		return
	droplet_particles.amount = max(1, next_amount)
	droplet_particles.lifetime = maxf(next_lifetime, 0.05)
	var mat := _ensure_process_material(droplet_particles)
	if mat:
		mat.initial_velocity_min = velocity_min
		mat.initial_velocity_max = maxf(velocity_max, velocity_min)
		mat.scale_min = scale_min_value
		mat.scale_max = maxf(scale_max_value, scale_min_value)


func _prepare_local_materials() -> void:
	_cache_nodes()
	if _foam_material == null or not is_instance_valid(_foam_material):
		_foam_material = _duplicate_surface_material(foam_disk)
	if _column_material == null or not is_instance_valid(_column_material):
		_column_material = _duplicate_surface_material(column_card)
	if _mist_material == null or not is_instance_valid(_mist_material):
		_mist_material = _duplicate_surface_material(mist_card)
	if _splash_card_materials.size() != _splash_cards.size():
		_splash_card_materials.clear()
		for card in _splash_cards:
			_splash_card_materials.append(_duplicate_surface_material(card))


func _cache_nodes() -> void:
	if not is_instance_valid(foam_disk):
		foam_disk = get_node_or_null("FoamDisk") as MeshInstance3D
	if not is_instance_valid(column_card):
		column_card = get_node_or_null("ColumnCard") as MeshInstance3D
	if not is_instance_valid(splash_cards_root):
		splash_cards_root = get_node_or_null("SplashCards") as Node3D
	if _needs_splash_card_cache():
		_splash_cards.clear()
		if is_instance_valid(splash_cards_root):
			for child in splash_cards_root.get_children():
				if child is MeshInstance3D:
					_splash_cards.append(child as MeshInstance3D)
	if not is_instance_valid(mist_card):
		mist_card = get_node_or_null("MistCard") as MeshInstance3D
	if not is_instance_valid(droplet_particles):
		droplet_particles = get_node_or_null("DropletParticles") as GPUParticles3D
	if not is_instance_valid(blast_floor_particles):
		blast_floor_particles = get_node_or_null("floor") as GPUParticles3D
	if not is_instance_valid(blast_mist_particles):
		blast_mist_particles = get_node_or_null("mist") as GPUParticles3D
	if not is_instance_valid(blast_spray_particles):
		blast_spray_particles = get_node_or_null("particles") as GPUParticles3D
	if _needs_blast_particle_cache():
		_refresh_blast_particles()


func _needs_splash_card_cache() -> bool:
	if _splash_cards.is_empty():
		return true
	for card in _splash_cards:
		if not is_instance_valid(card):
			return true
	return false


func _layout_splash_cards() -> void:
	_cache_nodes()
	if not _splash_cards_enabled or _splash_cards.is_empty():
		_set_splash_cards_visible(false)
		return
	if is_instance_valid(splash_cards_root):
		splash_cards_root.visible = true

	var active_count: int = mini(_splash_card_count, _splash_cards.size())
	var base_angle: float = randf_range(0.0, TAU)
	for i in range(_splash_cards.size()):
		var card: MeshInstance3D = _splash_cards[i]
		var is_active_card: bool = i < active_count
		card.visible = is_active_card
		if not is_active_card:
			continue
		var angle: float = base_angle + (TAU * float(i) / maxf(float(active_count), 1.0)) + randf_range(-0.22, 0.22)
		var radius: float = randf_range(_splash_card_radius * 0.25, _splash_card_radius)
		card.position = Vector3(cos(angle) * radius, randf_range(0.08, 0.2), sin(angle) * radius)
		card.rotation = Vector3(randf_range(-0.08, 0.08), angle + (PI * 0.5), randf_range(-0.2, 0.2))
		card.set_meta("burst_base_y", card.position.y)
		card.set_meta("burst_height_jitter", randf_range(0.82, 1.18))
		card.set_meta("burst_alpha_jitter", randf_range(0.78, 1.08))


func _apply_splash_cards_visual_state(t: float, _out_t: float, quick_fade: float) -> void:
	if not _splash_cards_enabled or _splash_cards.is_empty():
		_set_splash_cards_visible(false)
		return
	var active_count: int = mini(_splash_card_count, _splash_cards.size())
	for i in range(_splash_cards.size()):
		var card: MeshInstance3D = _splash_cards[i]
		if not is_instance_valid(card):
			continue
		var is_active_card: bool = i < active_count
		card.visible = is_active_card
		if not is_active_card:
			continue
		var stagger: float = 0.035 * float(i)
		var local_t: float = clampf((t - stagger) / maxf(1.0 - stagger, 0.01), 0.0, 1.0)
		var local_out_t: float = _ease_out_quad(local_t)
		var scale_2d: Vector2 = _splash_card_start_scale.lerp(_splash_card_end_scale, local_out_t)
		var height_jitter: float = float(card.get_meta("burst_height_jitter", 1.0))
		var alpha_jitter: float = float(card.get_meta("burst_alpha_jitter", 1.0))
		card.scale = Vector3(scale_2d.x, scale_2d.y * height_jitter, 1.0)
		card.position.y = float(card.get_meta("burst_base_y", 0.12)) + (_splash_card_rise * local_out_t * height_jitter)
		_set_material_alpha(_get_splash_card_material(i), _splash_card_alpha * quick_fade * alpha_jitter)


func _duplicate_surface_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if not is_instance_valid(mesh):
		return null
	var material := mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		return null
	var local_material := material.duplicate() as StandardMaterial3D
	local_material.resource_local_to_scene = true
	mesh.set_surface_override_material(0, local_material)
	return local_material


func _set_material_alpha(material: StandardMaterial3D, alpha: float) -> void:
	if material == null:
		return
	var color := material.albedo_color
	color.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = color


func _set_card_visible(card: MeshInstance3D, is_visible: bool) -> void:
	if is_instance_valid(card):
		card.visible = is_visible


func _set_splash_cards_visible(is_visible: bool) -> void:
	if is_instance_valid(splash_cards_root):
		splash_cards_root.visible = is_visible
	for card in _splash_cards:
		_set_card_visible(card, is_visible)


func _needs_blast_particle_cache() -> bool:
	if _blast_particles.is_empty():
		return true
	for particles in _blast_particles:
		if not is_instance_valid(particles):
			return true
	return false


func _refresh_blast_particles() -> void:
	_blast_particles.clear()
	for particles in [blast_floor_particles, blast_mist_particles, blast_spray_particles]:
		if is_instance_valid(particles):
			_blast_particles.append(particles)
	if _blast_particles.is_empty():
		for child in get_children():
			if child is GPUParticles3D:
				_blast_particles.append(child as GPUParticles3D)


func _start_blast_particles() -> void:
	_cache_nodes()
	for particles in _blast_particles:
		if not is_instance_valid(particles):
			continue
		particles.visible = true
		particles.emitting = false
		particles.restart()
		particles.emitting = true


func _stop_blast_particles() -> void:
	for particles in _blast_particles:
		if not is_instance_valid(particles):
			continue
		particles.emitting = false
		particles.visible = false


func _apply_blast_scale() -> void:
	scale = Vector3.ONE * _blast_scale


func _align_to_waterline() -> void:
	if not lock_to_waterline:
		return
	var pos := global_position
	pos.y = waterline_y + _waterline_lift
	global_position = pos


func _get_splash_card_material(index: int) -> StandardMaterial3D:
	if index < 0 or index >= _splash_card_materials.size():
		return null
	return _splash_card_materials[index] as StandardMaterial3D


func _ease_out_quad(t: float) -> float:
	var clamped := clampf(t, 0.0, 1.0)
	return 1.0 - ((1.0 - clamped) * (1.0 - clamped))


func _is_prewarm_mode() -> bool:
	var n: Node = self
	while is_instance_valid(n):
		if n.has_meta("prewarm_mode") and n.get_meta("prewarm_mode") == true:
			return true
		n = n.get_parent()
	return false


func _ensure_process_material(particles: GPUParticles3D) -> ParticleProcessMaterial:
	if not is_instance_valid(particles):
		return null
	if not (particles.process_material is ParticleProcessMaterial):
		return null
	var mat := particles.process_material as ParticleProcessMaterial
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		particles.process_material = mat
	return mat
