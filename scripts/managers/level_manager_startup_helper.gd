class_name LevelManagerStartupHelper
extends RefCounted

const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")

static func initialize(lm: Node) -> void:
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	lm._update_difficulty()
	if lm.hud:
		lm.hud.update_level(lm.current_level)
		lm.hud.update_score(lm.current_score)
		lm.hud.update_xp(lm.current_xp, lm.xp_to_next_level)
		lm.hud.update_merit(lm.merit_points, lm.max_merit_points, lm.merit_level)
		if lm.hud.has_method("update_combat_stats"):
			lm.hud.update_combat_stats(lm.ships_sunk, lm.soldiers_killed)
		if lm.hud.has_method("update_difficulty_ui"):
			lm.hud.update_difficulty_ui(lm.game_difficulty)

	# 시작 차단 없이 예열은 백그라운드에서 진행한다.
	lm.call_deferred("_run_startup_prewarm_async")

	# 초요기/일성정시는 현재 시작 기본 렐릭으로 장착한다.
	lm.get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(UpgradeManager):
			UpgradeManager.initialize_default_weapons()
		if is_instance_valid(UpgradeManager):
			if not (is_instance_valid(SaveManager) and SaveManager.has_method("has_relic") and SaveManager.has_relic("choyogi")):
				UpgradeManager.add_relic("choyogi")
			if not (is_instance_valid(SaveManager) and SaveManager.has_method("has_relic") and SaveManager.has_relic("ilseongjeongsiui")):
				UpgradeManager.add_relic("ilseongjeongsiui")
			if UpgradeManager.has_method("equip_owned_relics"):
				UpgradeManager.equip_owned_relics()
	)

static func run_startup_prewarm_async(lm: Node) -> void:
	await prewarm_shaders(lm, false)

static func prewarm_shaders(lm: Node, show_blocking_overlay: bool = true) -> void:
	var loading_layer: CanvasLayer = null
	var bg: ColorRect = null
	if show_blocking_overlay:
		loading_layer = CanvasLayer.new()
		loading_layer.layer = 120
		bg = ColorRect.new()
		bg.color = Color.BLACK
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		loading_layer.add_child(bg)
		lm.add_child(loading_layer)

	var scenes_to_warm = [
		preload("res://scenes/effects/impact_puff.tscn"),
		preload("res://scenes/effects/wood_splinter.tscn"),
		preload("res://scenes/effects/fire_effect.tscn"),
		preload("res://scenes/effects/fire_pot_explosion.tscn"),
		preload("res://scenes/effects/water_burst.tscn"),
	]

	var container := Node3D.new()
	container.name = "ShaderPrewarmer"
	lm.add_child(container)
	container.position = Vector3(0, -1000, 0)
	container.scale = Vector3.ONE

	for scene in scenes_to_warm:
		if scene:
			var inst = scene.instantiate()
			_mark_prewarm_recursive(inst)
			container.add_child(inst)
			_prime_visual_resources(inst)
			if not show_blocking_overlay:
				await lm.get_tree().process_frame

	if not AudioManager.is_prewarm_finished:
		await AudioManager.prewarm_finished

	for i in range(2):
		await lm.get_tree().process_frame

	container.queue_free()
	print("[Resource] 쉐이더 예열 및 오디오 캐싱 완료")

	if show_blocking_overlay and is_instance_valid(bg) and is_instance_valid(loading_layer):
		var tween = lm.create_tween()
		tween.tween_property(bg, "modulate:a", 0.0, 1.0)
		tween.tween_callback(loading_layer.queue_free)

static func _mark_prewarm_recursive(node: Node) -> void:
	node.set_meta("prewarm_mode", true)
	for child in node.get_children():
		_mark_prewarm_recursive(child)

static func _prime_visual_resources(node: Node) -> void:
	if node is GPUParticles3D:
		var gpu := node as GPUParticles3D
		gpu.emitting = false
		gpu.process_material = gpu.process_material
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		cpu.emitting = false
		cpu.process_material = cpu.process_material
	elif node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		mesh_inst.mesh = mesh_inst.mesh
		mesh_inst.material_override = mesh_inst.material_override

	for child in node.get_children():
		_prime_visual_resources(child)
