extends Node

const LimboAISmokeTickTaskScript = preload("res://scripts/test/limboai_smoke_tick_task.gd")

const REQUIRED_CLASSES: Array[String] = [
	"BTPlayer",
	"BehaviorTree",
	"BlackboardPlan",
	"LimboHSM",
	"LimboState",
]
const TICK_META_NAME := "limbo_smoke_ticks"

var _failed := false


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	_assert_limboai_classes_registered()
	if _failed:
		get_tree().quit(1)
		return

	var agent := Node.new()
	agent.name = "LimboSmokeAgent"
	agent.set_meta(TICK_META_NAME, 0)
	add_child(agent)

	var behavior_tree := BehaviorTree.new()
	behavior_tree.resource_name = "LimboSmokeTree"
	var tick_task := LimboAISmokeTickTaskScript.new()
	tick_task.tick_meta_name = TICK_META_NAME
	behavior_tree.root_task = tick_task

	var player := BTPlayer.new()
	player.name = "LimboSmokeBTPlayer"
	add_child(player)
	player.set_scene_root_hint(self)
	player.agent_node = player.get_path_to(agent)
	player.behavior_tree = behavior_tree
	player.active = true

	await get_tree().process_frame
	player.update(0.016)
	await get_tree().process_frame

	var tick_count := int(agent.get_meta(TICK_META_NAME, 0))
	if tick_count <= 0:
		_fail("BTPlayer did not tick smoke task")

	if _failed:
		get_tree().quit(1)
		return
	print("[LimboAISmokeContract] ok ticks=%d" % tick_count)
	get_tree().quit(0)


func _assert_limboai_classes_registered() -> void:
	for class_id in REQUIRED_CLASSES:
		if not ClassDB.class_exists(class_id):
			_fail("missing LimboAI class: %s" % class_id)


func _fail(message: String) -> void:
	_failed = true
	push_error("[LimboAISmokeContract] %s" % message)
