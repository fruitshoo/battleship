extends RefCounted
class_name ProjectContractBootstrapHelper



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
		var alert_index_before: int = int(AudioManager.get("current_non_spatial_index"))
		if AudioManager.has_method("set_startup_sfx_muted"):
			AudioManager.set_startup_sfx_muted(true)
		AudioManager.play_sfx("ui_click")
		AudioManager.play_sfx("cannon_fire", Vector3.ZERO)
		AudioManager.play_sfx("boss_horn", Vector3.ZERO)
		await _wait_frames(owner, 1)
		if int(AudioManager.get("current_sfx_index")) != sfx_index_before:
			failures.append("bootstrap smoke muted 3D SFX still advanced audio pool")
		if int(AudioManager.get("current_2d_index")) != ui_index_before:
			failures.append("bootstrap smoke muted 2D SFX still advanced audio pool")
		if int(AudioManager.get("current_non_spatial_index")) != alert_index_before:
			failures.append("bootstrap smoke muted battle alert SFX still advanced audio pool")
		if AudioManager.has_method("set_startup_sfx_muted"):
			AudioManager.set_startup_sfx_muted(false)
		await _validate_battle_alert_audio_pool(owner, failures)
		await _validate_bow_audio_rate_limit(owner, failures)
		if AudioManager.has_method("set_boss_battle_music"):
			var previous_bgm_name := str(AudioManager.get("current_bgm_name"))
			AudioManager.set_boss_battle_music(true)
			await _wait_frames(owner, 1)
			var boss_bgm_name := str(AudioManager.get("current_bgm_name"))
			var bgm_player := AudioManager.get("bgm_player") as AudioStreamPlayer
			if boss_bgm_name != "boss_taiko":
				failures.append("bootstrap smoke boss music did not select taiko BGM")
			elif not is_instance_valid(bgm_player) or not bgm_player.playing:
				failures.append("bootstrap smoke boss taiko BGM did not start")
			elif bgm_player.volume_db < 1.0:
				failures.append("bootstrap smoke boss taiko BGM volume too low: %.1fdB" % bgm_player.volume_db)
			AudioManager.set_boss_battle_music(false)
			if not previous_bgm_name.is_empty() and previous_bgm_name != "boss_taiko" and AudioManager.has_method("play_bgm"):
				AudioManager.play_bgm(previous_bgm_name)
		var level_manager: Node = LevelManagerRegistry.get_level_manager(owner.get_tree())
		if not is_instance_valid(level_manager):
			failures.append("bootstrap smoke missing LevelManager for restart cleanup")
		else:
			var survivor_scene := load("res://scenes/effects/survivor.tscn") as PackedScene
			if survivor_scene == null:
				failures.append("bootstrap smoke restart cleanup could not load survivor scene")
			else:
				var tree := owner.get_tree()
				if tree == null or tree.root == null:
					failures.append("bootstrap smoke restart cleanup missing scene tree root")
				else:
					var root := tree.root
					var survivor := ScenePool.acquire(tree, survivor_scene)
					if not is_instance_valid(survivor):
						failures.append("bootstrap smoke restart cleanup could not acquire survivor")
					else:
						root.add_child(survivor)
						var active_survivor_id: int = survivor.get_instance_id()
						var root_chest_id: int = 0
						var chest_scene := load("res://scenes/effects/treasure_chest.tscn") as PackedScene
						if chest_scene == null:
							failures.append("bootstrap smoke restart cleanup could not load treasure chest scene")
						else:
							var root_chest := chest_scene.instantiate()
							if not is_instance_valid(root_chest):
								failures.append("bootstrap smoke restart cleanup could not instantiate treasure chest")
							else:
								root.add_child(root_chest)
								root_chest_id = root_chest.get_instance_id()
						var pooled_survivor := ScenePool.acquire(tree, survivor_scene)
						if not is_instance_valid(pooled_survivor):
							failures.append("bootstrap smoke restart cleanup could not acquire pooled survivor")
						else:
							root.add_child(pooled_survivor)
							ScenePool.release(pooled_survivor)
							await _wait_frames(owner, 2)

						AudioManager.set_boss_battle_music(true)
						await _wait_frames(owner, 1)
						level_manager.call("_stop_run_audio_state")
						level_manager.call("_clear_root_runtime_pool_residue")
						await _wait_frames(owner, 2)

						if str(AudioManager.get("current_bgm_name")).strip_edges() == "boss_taiko":
							failures.append("bootstrap smoke restart cleanup left boss taiko BGM running")
						var active_survivor := NodeContractHelper.get_instance_node(active_survivor_id)
						if is_instance_valid(active_survivor):
							failures.append("bootstrap smoke restart cleanup left active survivor on root")
						if root_chest_id != 0:
							var root_chest_after_cleanup := NodeContractHelper.get_instance_node(root_chest_id)
							if is_instance_valid(root_chest_after_cleanup):
								failures.append("bootstrap smoke restart cleanup left root treasure chest behind")
						var pool_root := root.get_node_or_null(ScenePool.ROOT_NAME)
						if is_instance_valid(pool_root):
							if pool_root.get_child_count() > 0:
								failures.append("bootstrap smoke restart cleanup left pooled runtime nodes in ScenePool root")
							var store: Variant = pool_root.get_meta(ScenePool.STORE_META, {})
							if store is Dictionary and not (store as Dictionary).is_empty():
								failures.append("bootstrap smoke restart cleanup left ScenePool store entries behind")

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


static func _validate_battle_alert_audio_pool(owner: Node, failures: Array[String]) -> void:
	var sfx_index_before: int = int(AudioManager.get("current_sfx_index"))
	var ui_index_before: int = int(AudioManager.get("current_2d_index"))
	var alert_index_before: int = int(AudioManager.get("current_non_spatial_index"))
	AudioManager.play_sfx("boss_horn", Vector3.ZERO, 1.0, -80.0)
	await _wait_frames(owner, 1)
	if int(AudioManager.get("current_sfx_index")) != sfx_index_before:
		failures.append("bootstrap smoke battle alert used 3D SFX pool")
	if int(AudioManager.get("current_2d_index")) != ui_index_before:
		failures.append("bootstrap smoke battle alert used UI SFX pool")
	if int(AudioManager.get("current_non_spatial_index")) == alert_index_before:
		failures.append("bootstrap smoke battle alert did not use non-spatial SFX pool")


static func _validate_bow_audio_rate_limit(owner: Node, failures: Array[String]) -> void:
	var sfx_index_before: int = int(AudioManager.get("current_sfx_index"))
	var pool_size := maxi(1, int(AudioManager.get("sfx_pool_size")))
	AudioManager.play_sfx("bow_shoot", Vector3.ZERO, 0.92, -80.0)
	AudioManager.play_sfx("bow_shoot", Vector3.ZERO, 0.92, -80.0)
	await _wait_frames(owner, 1)
	var expected_index := (sfx_index_before + 1) % pool_size
	if int(AudioManager.get("current_sfx_index")) != expected_index:
		failures.append("bootstrap smoke bow rate limit did not coalesce repeated bow SFX")


static func _wait_frames(owner: Node, frames: int) -> void:
	if frames <= 0 or not is_instance_valid(owner):
		return
	for _index in range(frames):
		await owner.get_tree().process_frame
