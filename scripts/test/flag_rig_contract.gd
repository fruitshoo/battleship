extends Node
# @scene_contract_encapsulated

const MAST_SCENE := preload("res://scenes/props/mast.tscn")
const FlagSceneLibrary = preload("res://scripts/props/flag_scene_library.gd")

var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	_verify_scene_registry()
	_verify_scene_mapping()
	await _verify_concrete_flag_scenes()
	await _verify_mast_kind_swaps_scene()
	await _verify_mast_texture_swap_keeps_scene_kind()
	_report()


func _flag_kinds() -> Array[String]:
	return [
		FlagSceneLibrary.KIND_PLAYER_FLAGSHIP,
		FlagSceneLibrary.KIND_PLAYER_SUPPORT,
		FlagSceneLibrary.KIND_ENEMY_DEFAULT,
		FlagSceneLibrary.KIND_ENEMY_SEKIBUNE,
		FlagSceneLibrary.KIND_ENEMY_ELITE,
		FlagSceneLibrary.KIND_BOSS,
		FlagSceneLibrary.KIND_SITE,
	]


func _verify_scene_registry() -> void:
	for kind in _flag_kinds():
		if not FlagSceneLibrary.has_kind(kind):
			_failures.append("missing flag scene kind: %s" % kind)
	if FlagSceneLibrary.get_scene_path(FlagSceneLibrary.KIND_BOSS).find("swallowtail") < 0:
		_failures.append("boss flag kind should map directly to a swallowtail scene")


func _verify_scene_mapping() -> void:
	for kind in _flag_kinds():
		var scene_path := FlagSceneLibrary.get_scene_path(kind)
		if scene_path.is_empty():
			_failures.append("missing flag scene path for kind: %s" % kind)
			continue
		var scene := load(scene_path) as PackedScene
		if scene == null:
			_failures.append("flag scene did not load: %s" % scene_path)


func _verify_concrete_flag_scenes() -> void:
	var boss_scene := load(FlagSceneLibrary.get_scene_path(FlagSceneLibrary.KIND_BOSS)) as PackedScene
	var boss_flag := _instantiate_flag_scene(boss_scene, "boss")
	if boss_flag != null:
		await get_tree().process_frame
		if boss_flag.call("get_flag_shape_name") != "swallowtail":
			_failures.append("boss flag scene did not use swallowtail shape")
		_expect_wind_mode(boss_flag, "boss", "fixed_flutter")
		boss_flag.queue_free()

	var flagship_scene := load(FlagSceneLibrary.get_scene_path(FlagSceneLibrary.KIND_PLAYER_FLAGSHIP)) as PackedScene
	var flagship_flag := _instantiate_flag_scene(flagship_scene, "player flagship")
	if flagship_flag != null:
		await get_tree().process_frame
		_expect_wind_mode(flagship_flag, "player flagship", "fixed_flutter")
		flagship_flag.queue_free()

	var support_scene := load(FlagSceneLibrary.get_scene_path(FlagSceneLibrary.KIND_PLAYER_SUPPORT)) as PackedScene
	var support_flag := _instantiate_flag_scene(support_scene, "support")
	if support_flag != null:
		await get_tree().process_frame
		if support_flag.call("get_flag_shape_name") != "triangle":
			_failures.append("support flag scene should use triangle pennant shape")
		_expect_wind_mode(support_flag, "support", "free_rotate")
		support_flag.queue_free()


func _verify_mast_kind_swaps_scene() -> void:
	var mast := MAST_SCENE.instantiate()
	add_child(mast)
	await get_tree().process_frame
	if not mast.has_method("set_flag_kind") or not mast.has_method("get_flag_shape_name"):
		_failures.append("mast scene does not expose flag kind contract API")
		mast.queue_free()
		return
	mast.call("set_flag_kind", FlagSceneLibrary.KIND_BOSS)
	await get_tree().process_frame
	if mast.call("get_flag_shape_name") != "swallowtail":
		_failures.append("mast kind swap did not install boss swallowtail flag scene")
	mast.queue_free()


func _verify_mast_texture_swap_keeps_scene_kind() -> void:
	var mast := MAST_SCENE.instantiate()
	add_child(mast)
	await get_tree().process_frame
	var texture := _make_test_texture()
	mast.call("set_flag_kind", FlagSceneLibrary.KIND_PLAYER_SUPPORT, texture)
	await get_tree().process_frame
	var flag = mast.call("get_flag_node")
	if not is_instance_valid(flag):
		_failures.append("mast texture swap did not leave an active flag node")
	elif not flag.has_method("get_flag_kind") or str(flag.call("get_flag_kind")) != FlagSceneLibrary.KIND_PLAYER_SUPPORT:
		_failures.append("mast texture swap changed the concrete flag kind")
	elif not flag.has_method("get_flag_texture") or flag.call("get_flag_texture") != texture:
		_failures.append("mast texture swap did not apply the texture to the active flag")
	elif not flag.has_method("is_using_flag_texture") or flag.call("is_using_flag_texture") != true:
		_failures.append("mast texture swap did not enable texture rendering")
	mast.queue_free()


func _instantiate_flag_scene(scene: PackedScene, label: String) -> Node:
	if scene == null:
		_failures.append("missing concrete flag scene: %s" % label)
		return null
	var flag := scene.instantiate()
	add_child(flag)
	await_ready(flag)
	if not is_instance_valid(flag) or not flag.has_method("get_flag_shape_name"):
		_failures.append("flag scene missing common flag API: %s" % label)
		flag.queue_free()
		return null
	return flag


func _expect_wind_mode(flag: Node, label: String, expected: String) -> void:
	if not flag.has_method("get_wind_mode_name"):
		_failures.append("flag scene missing wind mode API: %s" % label)
		return
	var actual := str(flag.call("get_wind_mode_name"))
	if actual != expected:
		_failures.append("%s flag wind mode should be %s, got %s" % [label, expected, actual])


func _make_test_texture() -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.8, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


func await_ready(_node: Node) -> void:
	# The helper intentionally exists for readability; the caller awaits the process frame.
	pass


func _report() -> void:
	if _failures.is_empty():
		print("[FlagRigContract] ok")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FlagRigContract] %s" % failure)
	get_tree().quit(1)
