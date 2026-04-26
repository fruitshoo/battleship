extends Node

const ProjectContractTypographyHelper = preload("res://scripts/test/project_contract_typography_helper.gd")

@export var smoke_scene_path: String = "res://scenes/test/preview_base.tscn"
@export var smoke_wait_frames_after_attach: int = 2

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	await ProjectContractTypographyHelper.run_typography_contract_smoke(
		self,
		_failures,
		smoke_scene_path,
		smoke_wait_frames_after_attach
	)
	_report()


func _report() -> void:
	if _failures.is_empty():
		print("[TypographyContract] ok")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[TypographyContract] %s" % failure)
	get_tree().quit(1)
