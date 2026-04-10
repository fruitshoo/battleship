class_name LevelManagerStartupHelper
extends RefCounted

const ScenePool = preload("res://scripts/helpers/scene_pool.gd")

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
			lm.hud.update_combat_stats(lm.ships_sunk, lm.ships_derelicted, lm.soldiers_killed, lm.soldiers_slain, lm.soldiers_drowned)
		if lm.hud.has_method("update_difficulty_ui"):
			lm.hud.update_difficulty_ui(lm.game_difficulty)

	# 시작 직후 짧은 로딩 오버레이 안에서 예열을 끝내 첫 전투 끊김을 줄인다.
	if not _env_flag_enabled("BATTLESHIP_SKIP_STARTUP_PREWARM"):
		lm.call_deferred("_prewarm_shaders", true)

	# 초요기/일성정시는 현재 시작 기본 아이템으로 장착한다.
	lm.get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(UpgradeManager):
			UpgradeManager.initialize_default_weapons()
		if is_instance_valid(UpgradeManager):
			if not (is_instance_valid(SaveManager) and SaveManager.has_method("has_item") and SaveManager.has_item("choyogi")):
				UpgradeManager.add_item("choyogi")
			if not (is_instance_valid(SaveManager) and SaveManager.has_method("has_item") and SaveManager.has_item("ilseongjeongsiui")):
				UpgradeManager.add_item("ilseongjeongsiui")
			if UpgradeManager.has_method("equip_owned_items"):
				UpgradeManager.equip_owned_items()
	)

static func run_startup_prewarm_async(lm: Node) -> void:
	await prewarm_shaders(lm, false)

static func prewarm_shaders(lm: Node, show_blocking_overlay: bool = true) -> void:
	var loading_layer: CanvasLayer = null
	var bg: ColorRect = null
	var loading_label: Label = null
	if is_instance_valid(AudioManager) and AudioManager.has_method("set_startup_sfx_muted"):
		AudioManager.set_startup_sfx_muted(true)
	if show_blocking_overlay:
		loading_layer = CanvasLayer.new()
		loading_layer.layer = 120
		loading_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		bg = ColorRect.new()
		bg.color = Color.BLACK
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		loading_layer.add_child(bg)
		loading_label = Label.new()
		loading_label.text = "로딩 중"
		loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		loading_label.set_anchors_preset(Control.PRESET_CENTER)
		loading_label.position = Vector2(-120.0, -16.0)
		loading_label.size = Vector2(240.0, 32.0)
		loading_label.add_theme_font_size_override("font_size", 24)
		loading_label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82, 0.96))
		loading_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
		loading_label.add_theme_constant_override("shadow_offset_x", 2)
		loading_label.add_theme_constant_override("shadow_offset_y", 2)
		loading_layer.add_child(loading_label)
		lm.add_child(loading_layer)

	var scenes_to_warm = [
		preload("res://scenes/effects/impact_puff.tscn"),
		preload("res://scenes/effects/wood_splinter.tscn"),
		preload("res://scenes/effects/fire_effect.tscn"),
		preload("res://scenes/effects/fire_pot_explosion.tscn"),
		preload("res://scenes/effects/water_burst.tscn"),
		preload("res://scenes/projectiles/cannonball.tscn"),
		preload("res://scenes/projectiles/cannonball_joseon.tscn"),
		preload("res://scenes/projectiles/cannonball_japanese.tscn"),
		preload("res://scenes/projectiles/cannonball_enemy_light.tscn"),
		preload("res://scenes/projectiles/cannonball_enemy_medium.tscn"),
		preload("res://scenes/projectiles/cannonball_enemy_heavy.tscn"),
		preload("res://scenes/projectiles/arrow.tscn"),
		preload("res://scenes/projectiles/ballista_bolt.tscn"),
		preload("res://scenes/projectiles/janggun_missile.tscn"),
		preload("res://scenes/projectiles/singigeon_rocket.tscn"),
	]

	var container := Node3D.new()
	container.name = "ShaderPrewarmer"
	lm.add_child(container)
	# 카메라 근처 혹은 렌더링 가능한 범위 내에 두어야 쉐이더가 인스턴싱됨 (프러스텀 컬링 방지)
	container.position = Vector3(0, 5, -5) 
	container.scale = Vector3(0.01, 0.01, 0.01) # 아주 작게 만들어 화면엔 안 보이게 함
	container.visible = true

	for scene in scenes_to_warm:
		if scene:
			var inst = scene.instantiate()
			_mark_prewarm_recursive(inst)
			container.add_child(inst)
			_prime_visual_resources(inst)
			# 모든 전투 관련 씬을 풀에 미리 등록
			_prewarm_scene_pool_instance(lm.get_tree(), scene)
			if not show_blocking_overlay:
				await lm.get_tree().process_frame

	if not AudioManager.is_prewarm_finished:
		await AudioManager.prewarm_finished

	for i in range(2):
		await lm.get_tree().process_frame

	container.queue_free()
	print("[Resource] 쉐이더 예열 및 오디오 캐싱 완료")
	if is_instance_valid(AudioManager) and AudioManager.has_method("set_startup_sfx_muted"):
		AudioManager.set_startup_sfx_muted(false)

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
		gpu.emitting = true # 실제 방출을 시도해야 파이프라인이 생성됨
		gpu.one_shot = true
		gpu.restart()
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		cpu.emitting = true
		cpu.one_shot = true
		cpu.restart()
	elif node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		# 렌더링 강제 유도
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_inst.mesh:
			var _m = mesh_inst.mesh

	for child in node.get_children():
		_prime_visual_resources(child)

static func _prewarm_scene_pool_instance(tree: SceneTree, scene: PackedScene) -> void:
	if tree == null or scene == null:
		return
	var inst := ScenePool.acquire(tree, scene)
	if not is_instance_valid(inst):
		return
	if not inst.is_inside_tree():
		tree.root.add_child(inst)
		if inst is Node3D:
			(inst as Node3D).visible = false
	if inst.has_method("pool_reset"):
		inst.call("pool_reset")
	ScenePool.release(inst)


static func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
