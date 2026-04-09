extends RefCounted
class_name ProjectContractBootstrapHelper

const PreviewHarnessHelper = preload("res://scripts/test/preview_harness_helper.gd")


static func run_bootstrap_contract_smoke(owner: Node, failures: Array[String], smoke_scene_path: String, wait_frames_after_attach: int) -> void:
	var packed := load(smoke_scene_path) as PackedScene
	if packed == null:
		failures.append("bootstrap smoke scene load failed: %s" % smoke_scene_path)
		return

	var smoke_root := packed.instantiate()
	if smoke_root == null:
		failures.append("bootstrap smoke scene instantiate failed: %s" % smoke_scene_path)
		return

	owner.add_child(smoke_root)
	PreviewHarnessHelper.setup_common(smoke_root, false, true)
	await _wait_frames(owner, wait_frames_after_attach + 1)

	if not is_instance_valid(AudioManager):
		failures.append("bootstrap smoke missing AudioManager autoload")
	else:
		if AudioManager.get("is_prewarm_finished") != true and AudioManager.has_signal("prewarm_finished"):
			await AudioManager.prewarm_finished
			await _wait_frames(owner, 1)
		if AudioManager.get("is_prewarm_finished") != true:
			failures.append("bootstrap smoke audio prewarm did not finish")
		if AudioManager.get("_startup_sfx_muted") == true:
			failures.append("bootstrap smoke startup audio mute flag remained enabled")
		var sfx_index_before: int = int(AudioManager.get("current_sfx_index"))
		var ui_index_before: int = int(AudioManager.get("current_2d_index"))
		if AudioManager.has_method("set_startup_sfx_muted"):
			AudioManager.set_startup_sfx_muted(true)
		AudioManager.play_sfx("ui_click")
		AudioManager.play_sfx("cannon_fire", Vector3.ZERO)
		await _wait_frames(owner, 1)
		if int(AudioManager.get("current_sfx_index")) != sfx_index_before:
			failures.append("bootstrap smoke muted 3D SFX still advanced audio pool")
		if int(AudioManager.get("current_2d_index")) != ui_index_before:
			failures.append("bootstrap smoke muted 2D SFX still advanced audio pool")
		if AudioManager.has_method("set_startup_sfx_muted"):
			AudioManager.set_startup_sfx_muted(false)

	var prewarm_wrapper := Node3D.new()
	prewarm_wrapper.name = "BootstrapPrewarmSmoke"
	prewarm_wrapper.set_meta("prewarm_mode", true)
	smoke_root.add_child(prewarm_wrapper)

	var effect_paths := [
		"res://scenes/effects/impact_puff.tscn",
		"res://scenes/effects/water_burst.tscn",
		"res://scenes/effects/fire_effect.tscn",
	]
	for effect_path in effect_paths:
		var effect_scene := load(effect_path) as PackedScene
		if effect_scene == null:
			failures.append("bootstrap smoke effect load failed: %s" % effect_path)
			continue
		var effect_instance := effect_scene.instantiate()
		if effect_instance == null:
			failures.append("bootstrap smoke effect instantiate failed: %s" % effect_path)
			continue
		prewarm_wrapper.add_child(effect_instance)
		await _wait_frames(owner, 1)
		_validate_prewarm_effect_state(effect_instance, effect_path, failures)

	smoke_root.queue_free()
	await _wait_frames(owner, 1)


static func _validate_prewarm_effect_state(effect_root: Node, effect_path: String, failures: Array[String]) -> void:
	if not is_instance_valid(effect_root):
		failures.append("bootstrap smoke invalid effect instance: %s" % effect_path)
		return
	var stack: Array[Node] = [effect_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node is GPUParticles3D and (node as GPUParticles3D).emitting:
			failures.append("bootstrap smoke prewarm particle emitted unexpectedly: %s" % effect_path)
		if node is AudioStreamPlayer3D and (node as AudioStreamPlayer3D).playing:
			failures.append("bootstrap smoke prewarm audio played unexpectedly: %s" % effect_path)
		for child in node.get_children():
			if child is Node:
				stack.append(child)


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
