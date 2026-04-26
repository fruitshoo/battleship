extends Node

const ScreenEdgeFxContractLogic = preload("res://scripts/test/screen_edge_fx_contract_logic.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	await ScreenEdgeFxContractLogic.run_contract(self, _failures)
	if _failures.is_empty():
		print("[ScreenEdgeFxContract] ok")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[ScreenEdgeFxContract] %s" % failure)
	get_tree().quit(1)
