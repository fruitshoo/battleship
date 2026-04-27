extends RefCounted

const ScreenEdgeFxScript = preload("res://scripts/ui/screen_edge_fx.gd")


class PlayerStub extends Node3D:
	var current_speed: float = 0.0
	var max_speed: float = 10.0
	var is_rowing: bool = false
	var rudder_angle: float = 0.0


static func run_contract(owner: Node, failures: Array[String]) -> void:
	var original_enabled: bool = SaveManager.get_setting("screen_edge_fx_enabled", true) == true if is_instance_valid(SaveManager) else true
	var original_strength: float = float(SaveManager.get_setting("screen_edge_fx_strength", 0.75)) if is_instance_valid(SaveManager) else 0.75
	if is_instance_valid(SaveManager):
		SaveManager.set_setting("screen_edge_fx_enabled", true, false)
		SaveManager.set_setting("screen_edge_fx_strength", 0.75, false)

	var player := PlayerStub.new()
	player.name = "PlayerStub"
	owner.add_child(player)

	var fx := CanvasLayer.new()
	fx.name = "ScreenEdgeFxUnderTest"
	fx.set_script(ScreenEdgeFxScript)
	fx.set("player_ship_path", NodePath("../PlayerStub"))

	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color.WHITE
	fx.add_child(overlay)
	owner.add_child(fx)

	await owner.get_tree().process_frame
	await owner.get_tree().process_frame

	var material := overlay.material as ShaderMaterial
	if material == null:
		failures.append("ScreenEdgeFX should attach a ShaderMaterial to its overlay ColorRect.")
		if is_instance_valid(SaveManager):
			SaveManager.set_setting("screen_edge_fx_enabled", original_enabled, false)
			SaveManager.set_setting("screen_edge_fx_strength", original_strength, false)
		_cleanup(owner, fx, player)
		return

	var edge_vignette := float(material.get_shader_parameter("edge_vignette"))
	if edge_vignette <= 0.0:
		failures.append("ScreenEdgeFX should initialize a positive base vignette strength.")
	var edge_blur := float(material.get_shader_parameter("edge_blur"))
	if edge_blur <= 0.0:
		failures.append("ScreenEdgeFX should initialize a positive base edge blur strength.")
	if edge_blur < 0.68:
		failures.append("ScreenEdgeFX default edge blur should be visible enough for gameplay.")
	var shader_code := material.shader.code if material.shader != null else ""
	if not shader_code.contains("textureLod"):
		failures.append("ScreenEdgeFX should use mipmap sampling so ocean edges visibly blur.")

	var initial_boost := float(material.get_shader_parameter("motion_boost"))
	if initial_boost > 0.08:
		failures.append("ScreenEdgeFX should stay near-neutral when the player ship is stationary.")

	player.current_speed = 8.5
	player.is_rowing = true
	player.rudder_angle = 18.0
	for _i in range(12):
		await owner.get_tree().process_frame

	var boosted_motion := float(material.get_shader_parameter("motion_boost"))
	if boosted_motion <= initial_boost + 0.05:
		failures.append("ScreenEdgeFX should increase edge motion blur when rowing at speed.")

	player.current_speed = 0.0
	player.is_rowing = false
	player.rudder_angle = 0.0
	for _j in range(20):
		await owner.get_tree().process_frame

	var recovered_motion := float(material.get_shader_parameter("motion_boost"))
	if recovered_motion >= boosted_motion - 0.03:
		failures.append("ScreenEdgeFX motion boost should settle back down after movement ends.")

	if is_instance_valid(SaveManager):
		SaveManager.set_setting("screen_edge_fx_enabled", false, false)
	for _k in range(4):
		await owner.get_tree().process_frame
	if overlay.visible:
		failures.append("ScreenEdgeFX overlay should hide when the screen-edge effect setting is disabled.")

	if is_instance_valid(SaveManager):
		SaveManager.set_setting("screen_edge_fx_enabled", original_enabled, false)
		SaveManager.set_setting("screen_edge_fx_strength", original_strength, false)
	_cleanup(owner, fx, player)


static func _cleanup(owner: Node, fx: CanvasLayer, player: Node3D) -> void:
	if is_instance_valid(fx):
		owner.remove_child(fx)
		fx.queue_free()
	if is_instance_valid(player):
		owner.remove_child(player)
		player.queue_free()
