extends Node3D


func pool_capacity() -> int:
	return 12


func pool_activate() -> void:
	visible = true
	_set_particles_emitting(self, true, true)


func pool_reset() -> void:
	_set_particles_emitting(self, false, false)
	_stop_audio(self)
	visible = false


func _set_particles_emitting(node: Node, active: bool, restart_particles: bool) -> void:
	for child in node.get_children():
		if child is GPUParticles3D:
			var particles := child as GPUParticles3D
			if restart_particles and active:
				particles.restart()
			particles.emitting = active
		_set_particles_emitting(child, active, restart_particles)


func _stop_audio(node: Node) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer3D:
			var player := child as AudioStreamPlayer3D
			if player.playing:
				player.stop()
		_stop_audio(child)
