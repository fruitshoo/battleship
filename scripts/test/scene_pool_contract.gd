extends Node3D

const ScenePool = preload("res://scripts/helpers/scene_pool.gd")
const POOLED_TEST_NODE := preload("res://scenes/test/pooled_test_node.tscn")


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	var gameplay_parent := Node3D.new()
	gameplay_parent.name = "GameplayParent"
	add_child(gameplay_parent)

	var pooled_node := ScenePool.acquire(get_tree(), POOLED_TEST_NODE) as Node3D
	_assert_true("acquire_returns_node", is_instance_valid(pooled_node))
	gameplay_parent.add_child(pooled_node)
	pooled_node.global_position = Vector3(7.0, 1.0, -3.0)

	ScenePool.release(pooled_node)
	await get_tree().process_frame
	await get_tree().process_frame

	var pool_root := get_tree().root.get_node_or_null(ScenePool.ROOT_NAME)
	_assert_true("pool_root_exists", is_instance_valid(pool_root))
	_assert_true("released_node_reparented_to_pool_root", pooled_node.get_parent() == pool_root)
	_assert_true("released_node_hidden", not pooled_node.visible)

	var reacquired_node := ScenePool.acquire(get_tree(), POOLED_TEST_NODE) as Node3D
	_assert_true("reacquired_same_node", reacquired_node == pooled_node)
	_assert_true("reacquired_detached", reacquired_node.get_parent() == null)
	_assert_true("reacquired_visible", reacquired_node.visible)

	print("[ScenePoolContract] ok")
	get_tree().quit(0)


func _assert_true(label: String, value: bool) -> void:
	if value:
		return
	push_error("[ScenePoolContract] %s expected true" % label)
	get_tree().quit(1)
