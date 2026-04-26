extends Node

const ResponsiveUiContractLogic = preload("res://scripts/test/responsive_ui_contract_logic.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	await ResponsiveUiContractLogic.run_contract(self, _failures)
	if _failures.is_empty():
		print("[ResponsiveUiContract] ok")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[ResponsiveUiContract] %s" % failure)
	get_tree().quit(1)
