extends SceneTree

func _init():
	var player = AudioStreamPlayer.new()
	var stream = load("res://assets/audio/sfx/sfx_gilgunak.wav") as AudioStream
	player.stream = stream
	get_root().add_child(player)
	print("Stream is null? ", stream == null)
	player.play()
	print("Is playing? ", player.playing)
	quit()
