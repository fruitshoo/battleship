extends Node3D

const FIRE_CRACKLE_STREAM: AudioStream = preload("res://assets/audio/sfx/sfx_fire_crackling.ogg")
const EXTINGUISH_EXTRA_SECONDS := 0.2
const EXTINGUISH_MIN_SECONDS := 0.6
const EXTINGUISH_MAX_SECONDS := 3.0

var _active: bool = false
var _extinguish_timer: float = 0.0


func _ready() -> void:
	pool_reset()


func pool_capacity() -> int:
	return 12


func pool_activate() -> void:
	set_fire_active(true, true)


func pool_reset() -> void:
	_active = false
	_extinguish_timer = 0.0
	visible = false
	set_process(false)
	_set_particles_emitting(self, false, false)
	_sync_audio(false)


func set_fire_active(active: bool, play_crackle: bool = true) -> void:
	if active:
		_start_fire(play_crackle)
	else:
		_extinguish_fire()


func _process(delta: float) -> void:
	if _active or _extinguish_timer <= 0.0:
		return
	_extinguish_timer -= delta
	if _extinguish_timer <= 0.0:
		_finish_extinguish()


func _start_fire(play_crackle: bool) -> void:
	var changed := not _active
	_active = true
	_extinguish_timer = 0.0
	visible = true
	set_process(false)
	if changed:
		_set_particles_emitting(self, true, true)
	_sync_audio(play_crackle)


func _extinguish_fire() -> void:
	var was_active := _active
	_active = false
	if was_active:
		_set_particles_emitting(self, false, false)
		_extinguish_timer = _get_extinguish_seconds()
		visible = true
		set_process(true)
	elif _extinguish_timer <= 0.0:
		_finish_extinguish()
	_sync_audio(false)


func _finish_extinguish() -> void:
	_extinguish_timer = 0.0
	visible = false
	set_process(false)


func _set_particles_emitting(node: Node, active: bool, restart_particles: bool) -> void:
	for child in node.get_children():
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			if restart_particles and active:
				particles.restart()
			particles.visible = active
			particles.emitting = active
		_set_particles_emitting(child, active, restart_particles)


func _get_extinguish_seconds() -> float:
	return clampf(_get_max_particle_lifetime(self) + EXTINGUISH_EXTRA_SECONDS, EXTINGUISH_MIN_SECONDS, EXTINGUISH_MAX_SECONDS)


func _get_max_particle_lifetime(node: Node) -> float:
	var max_lifetime := 0.0
	for child in node.get_children():
		if child is GPUParticles3D:
			max_lifetime = maxf(max_lifetime, (child as GPUParticles3D).lifetime)
		max_lifetime = maxf(max_lifetime, _get_max_particle_lifetime(child))
	return max_lifetime


func _sync_audio(should_play: bool) -> void:
	_sync_audio_recursive(self, should_play)


func _sync_audio_recursive(node: Node, should_play: bool) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer3D:
			var player := child as AudioStreamPlayer3D
			if player.stream == null:
				player.stream = FIRE_CRACKLE_STREAM
			if should_play:
				if not player.playing:
					player.play()
			elif player.playing:
				player.stop()
		_sync_audio_recursive(child, should_play)
