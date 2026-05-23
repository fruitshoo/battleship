class_name LevelManagerStartupHelper
extends RefCounted

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

const STARTUP_BLOCKING_PREWARM_MIN_SECONDS: float = 1.6
const STARTUP_POOL_PREWARM_DEFAULT: int = 4
const STARTUP_POOL_PREWARM_MAX: int = 12
const STARTUP_POOL_PREWARM_COUNTS := {
	"res://scenes/effects/water_blast.tscn": 8,
	"res://scenes/effects/water_blast_big.tscn": 4,
	"res://scenes/effects/cannon_muzzle_smoke.tscn": 8,
	"res://scenes/effects/impact_puff.tscn": 8,
	"res://scenes/effects/wood_splinter.tscn": 6,
	"res://scenes/projectiles/fire_pot.tscn": 6,
	"res://scenes/projectiles/cannonball.tscn": 10,
	"res://scenes/projectiles/small_cannonball.tscn": 10,
	"res://scenes/projectiles/arrow.tscn": 10,
	"res://scenes/projectiles/ballista_bolt.tscn": 8,
	"res://scenes/projectiles/janggun_missile.tscn": 6,
	"res://scenes/projectiles/singigeon_rocket.tscn": 12,
}

static func initialize(lm: Node) -> void:
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	lm._update_difficulty()
	if lm.hud:
		lm.hud.update_level(lm.current_level)
		lm.hud.update_score(lm.current_score)
		lm.hud.update_xp(lm.current_xp, lm.xp_to_next_level)
		if lm.hud.has_method("update_combat_stats"):
			lm.hud.update_combat_stats(lm.ships_sunk, lm.ships_derelicted, lm.soldiers_killed, lm.soldiers_slain, lm.soldiers_drowned)
		if lm.hud.has_method("update_difficulty_ui"):
			lm.hud.update_difficulty_ui(lm.game_difficulty)

	_start_run_music()

	# 시작 직후 짧은 로딩 오버레이 안에서 예열을 끝내 첫 전투 끊김을 줄인다.
	if not _env_flag_enabled("BATTLESHIP_SKIP_STARTUP_PREWARM"):
		lm.call_deferred("_run_startup_bootstrap_async")
	else:
		var lm_id: int = lm.get_instance_id()
		lm.get_tree().create_timer(0.1).timeout.connect(func():
			var level_manager := NodeContractHelper.get_instance_node(lm_id)
			if is_instance_valid(level_manager):
				_apply_startup_default_equipment(level_manager)
				if level_manager.has_method("_maybe_start_run_prologue"):
					level_manager.call_deferred("_maybe_start_run_prologue")
		)


static func _start_run_music() -> void:
	if is_instance_valid(AudioManager) and AudioManager.has_method("play_gameplay_music"):
		AudioManager.play_gameplay_music()

static func run_startup_bootstrap_async(lm: Node) -> void:
	await prewarm_shaders(lm, true, true)

static func run_startup_prewarm_async(lm: Node) -> void:
	await prewarm_shaders(lm, false)

static func prewarm_shaders(lm: Node, show_blocking_overlay: bool = true, include_startup_equipment: bool = false) -> void:
	var start_msec: int = Time.get_ticks_msec()
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
		NavalUiTheme.style_loading_message(loading_label, 24)
		loading_layer.add_child(loading_label)
		lm.add_child(loading_layer)

	var pooled_scenes_to_warm = [
		preload("res://scenes/effects/wood_splinter.tscn"),
		preload("res://scenes/effects/impact_puff.tscn"),
		preload("res://scenes/effects/fire_effect.tscn"),
		preload("res://scenes/effects/fire_pot_explosion.tscn"),
		preload("res://scenes/effects/water_blast.tscn"),
		preload("res://scenes/effects/water_blast_big.tscn"),
		preload("res://scenes/effects/cannon_muzzle_smoke.tscn"),
		preload("res://scenes/projectiles/fire_pot.tscn"),
		preload("res://scenes/projectiles/cannonball.tscn"),
		preload("res://scenes/projectiles/small_cannonball.tscn"),
		preload("res://scenes/projectiles/arrow.tscn"),
		preload("res://scenes/projectiles/ballista_bolt.tscn"),
		preload("res://scenes/projectiles/janggun_missile.tscn"),
		preload("res://scenes/projectiles/singigeon_rocket.tscn"),
	]
	var visual_scenes_to_warm = [
		preload("res://scenes/ships/hulls/kobayabune_hull.tscn"),
		preload("res://scenes/ships/hulls/sekibune_hull.tscn"),
		preload("res://scenes/ships/hulls/atakebune_hull.tscn"),
		preload("res://scenes/ships/hulls/panok_hull.tscn"),
		preload("res://scenes/entities/launchers/cannon.tscn"),
		preload("res://scenes/entities/launchers/cannon_enemy_light.tscn"),
		preload("res://scenes/entities/launchers/cannon_enemy_medium.tscn"),
		preload("res://scenes/entities/launchers/cannon_enemy_heavy.tscn"),
	]
	var instantiate_only_scenes_to_warm = [
		preload("res://scenes/ships/enemy_base_ship.tscn"),
		preload("res://scenes/ships/enemy_ship.tscn"),
		preload("res://scenes/ships/enemy_melee_ship.tscn"),
		preload("res://scenes/ships/enemy_gunner_ship.tscn"),
		preload("res://scenes/ships/enemy_firepot_ship.tscn"),
		preload("res://scenes/ships/boss_ship.tscn"),
	]

	var container := Node3D.new()
	container.name = "ShaderPrewarmer"
	lm.add_child(container)
	# 카메라 근처 혹은 렌더링 가능한 범위 내에 두어야 쉐이더가 인스턴싱됨 (프러스텀 컬링 방지)
	container.position = Vector3(0, 5, -5) 
	container.scale = Vector3(0.01, 0.01, 0.01) # 아주 작게 만들어 화면엔 안 보이게 함
	container.visible = true

	for scene in pooled_scenes_to_warm:
		if scene:
			var inst = scene.instantiate()
			_mark_prewarm_recursive(inst)
			_prepare_prewarmer_visual_instance(inst)
			container.add_child(inst)
			_prime_visual_resources(inst)
			# 첫 전투 volley에서 즉석 instantiate가 몰리지 않도록 풀을 여러 개 채운다.
			_prewarm_scene_pool_instances(lm.get_tree(), scene)
			if not show_blocking_overlay:
				await lm.get_tree().process_frame

	for scene in visual_scenes_to_warm:
		if scene:
			var inst = scene.instantiate()
			_mark_prewarm_recursive(inst)
			_prepare_prewarmer_visual_instance(inst)
			container.add_child(inst)
			_prime_visual_resources(inst)
			if not show_blocking_overlay:
				await lm.get_tree().process_frame

	for scene in instantiate_only_scenes_to_warm:
		if scene:
			var inst = scene.instantiate()
			_mark_prewarm_recursive(inst)
			_prime_visual_resources(inst)
			inst.free()
			if not show_blocking_overlay:
				await lm.get_tree().process_frame

	if not AudioManager.is_prewarm_finished:
		await AudioManager.prewarm_finished

	if include_startup_equipment:
		_apply_startup_default_equipment(lm)
		for i in range(6):
			await lm.get_tree().process_frame

	for i in range(2):
		await lm.get_tree().process_frame

	if show_blocking_overlay:
		await _wait_for_minimum_startup_overlay(lm, start_msec)

	container.queue_free()
	print("[Resource] 쉐이더 예열 및 오디오 캐싱 완료")
	if is_instance_valid(AudioManager) and AudioManager.has_method("set_startup_sfx_muted"):
		AudioManager.set_startup_sfx_muted(false)

	if show_blocking_overlay and is_instance_valid(bg) and is_instance_valid(loading_layer):
		var tween = lm.create_tween()
		tween.tween_property(bg, "modulate:a", 0.0, 1.0)
		tween.tween_callback(loading_layer.queue_free)
	if lm.has_method("_maybe_start_run_prologue"):
		lm.call_deferred("_maybe_start_run_prologue")


static func _apply_startup_default_equipment(_lm: Node) -> void:
	if not is_instance_valid(UpgradeManager):
		return
	if UpgradeManager.has_method("initialize_default_weapons"):
		UpgradeManager.initialize_default_weapons()
	if UpgradeManager.has_method("is_item_system_enabled") and not UpgradeManager.is_item_system_enabled():
		return
	# 초요기/일성정시는 현재 시작 기본 아이템으로 장착한다.
	if not (is_instance_valid(SaveManager) and SaveManager.has_method("has_item") and SaveManager.has_item("choyogi")):
		UpgradeManager.add_item("choyogi")
	if not (is_instance_valid(SaveManager) and SaveManager.has_method("has_item") and SaveManager.has_item("ilseongjeongsiui")):
		UpgradeManager.add_item("ilseongjeongsiui")
	if UpgradeManager.has_method("equip_owned_items"):
		UpgradeManager.equip_owned_items()
	if UpgradeManager.has_method("refresh_hud_item_icons"):
		UpgradeManager.refresh_hud_item_icons()


static func _wait_for_minimum_startup_overlay(lm: Node, start_msec: int) -> void:
	var elapsed_sec: float = float(Time.get_ticks_msec() - start_msec) / 1000.0
	var remaining_sec: float = STARTUP_BLOCKING_PREWARM_MIN_SECONDS - elapsed_sec
	if remaining_sec <= 0.0:
		return
	await lm.get_tree().create_timer(remaining_sec).timeout

static func _mark_prewarm_recursive(node: Node) -> void:
	node.set_meta("prewarm_mode", true)
	for child in node.get_children():
		_mark_prewarm_recursive(child)


static func _prepare_prewarmer_visual_instance(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Area3D:
		var area := node as Area3D
		area.monitoring = false
		area.monitorable = false
	for child in node.get_children():
		_prepare_prewarmer_visual_instance(child)

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

static func _prewarm_scene_pool_instances(tree: SceneTree, scene: PackedScene) -> void:
	if tree == null or scene == null:
		return
	var warm_count: int = _get_scene_pool_prewarm_count(scene)
	for i in range(warm_count):
		var inst := ScenePool.acquire(tree, scene)
		if not is_instance_valid(inst):
			continue
		_prepare_pool_warm_instance(tree, inst)
		ScenePool.release(inst)


static func _prepare_pool_warm_instance(tree: SceneTree, inst: Node) -> void:
	if not is_instance_valid(inst):
		return
	inst.process_mode = Node.PROCESS_MODE_DISABLED
	if inst is Node3D:
		(inst as Node3D).visible = false
	if inst is Area3D:
		var area := inst as Area3D
		area.monitoring = false
		area.monitorable = false
	if not inst.is_inside_tree():
		tree.root.add_child(inst)
	_mark_prewarm_recursive(inst)
	_prime_visual_resources(inst)
	if inst.has_method("pool_reset"):
		inst.call("pool_reset")


static func _get_scene_pool_prewarm_count(scene: PackedScene) -> int:
	var scene_path: String = scene.resource_path
	if STARTUP_POOL_PREWARM_COUNTS.has(scene_path):
		return clampi(int(STARTUP_POOL_PREWARM_COUNTS[scene_path]), 1, STARTUP_POOL_PREWARM_MAX)
	return STARTUP_POOL_PREWARM_DEFAULT


static func _env_flag_enabled(name: String) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
