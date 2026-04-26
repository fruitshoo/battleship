extends Node3D

const FIRE_CRACKLE_STREAM: AudioStream = preload("res://assets/audio/sfx/sfx_fire_crackling.ogg")

var _active: bool = false


func pool_capacity() -> int:
	return 12


func pool_activate() -> void:
	set_fire_active(true, true)


func pool_reset() -> void:
	set_fire_active(false, false)


func set_fire_active(active: bool, play_crackle: bool = true) -> void:
	var changed := active != _active
	_active = active
	visible = active
	if changed:
		_set_particles_emitting(self, active, active)
	_sync_audio(active and play_crackle)


func _set_particles_emitting(node: Node, active: bool, restart_particles: bool) -> void:
	for child in node.get_children():
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			if restart_particles and active:
				particles.restart()
			particles.emitting = active
		_set_particles_emitting(child, active, restart_particles)


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
