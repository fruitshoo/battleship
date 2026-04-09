extends Node3D

const MastDamagePresets = preload("res://scripts/props/mast_damage_presets.gd")
const PRESETS := MastDamagePresets.ALL


func _ready() -> void:
	call_deferred("_apply_presets")


func _apply_presets() -> void:
	for index in PRESETS.size():
		var preview_name := "PreviewShip%d" % (index + 1)
		var ship: Node3D = get_node_or_null(preview_name)
		if not is_instance_valid(ship):
			continue
		var preset: Dictionary = PRESETS[index]
		_apply_ship_preset(ship, preset)


func _apply_ship_preset(ship: Node3D, preset: Dictionary) -> void:
	var mast: Node = ship.get_node_or_null("Mast")
	if is_instance_valid(mast):
		if mast.has_method("set_sail_damage"):
			mast.call("set_sail_damage", float(preset.get("damage", 0.0)))
		if mast.has_method("set_burn_amount"):
			mast.call("set_burn_amount", float(preset.get("burn", 0.0)))
		if mast.has_method("set_hole_alpha_strength"):
			mast.call("set_hole_alpha_strength", float(preset.get("hole", 0.0)))

	var label: Label3D = ship.get_node_or_null("StateLabel")
	if is_instance_valid(label):
		label.text = str(preset.get("name", "Preset"))
