extends RefCounted
class_name SoldierBoardingPrepBarHelper


const ROOT_NAME := "BoardingPrepBar"
const BACK_NAME := "Back"
const FILL_NAME := "Fill"
const BAR_WIDTH := 1.18
const BAR_HEIGHT := 0.096
const BAR_Y := 2.08
const META_DISPLAY_RATIO := "boarding_prep_bar_display_ratio"
const META_LAST_UPDATE_MSEC := "boarding_prep_bar_last_update_msec"
const DISPLAY_CATCH_UP_SPEED := 4.2
const DISPLAY_RESET_GAP_SECONDS := 0.75


static func update(soldier, ratio: float, urgent: bool = false) -> void:
	if not is_instance_valid(soldier):
		return
	var root := _ensure_root(soldier)
	if root == null:
		return
	root.visible = true
	root.position = Vector3(0.0, BAR_Y + (0.08 if bool(soldier.get("is_captain")) else 0.0), 0.0)
	var display_ratio := _get_smoothed_display_ratio(root, ratio)
	_update_fill(root, display_ratio, urgent)


static func hide(soldier) -> void:
	var root: Node3D = _get_root(soldier)
	if root != null:
		root.visible = false


static func _ensure_root(soldier) -> Node3D:
	var root: Node3D = _get_root(soldier)
	if root != null:
		return root
	root = Node3D.new()
	root.name = ROOT_NAME
	root.visible = false
	soldier.add_child(root)

	var back: MeshInstance3D = _make_quad(BACK_NAME, Vector2(BAR_WIDTH, BAR_HEIGHT), Color(0.02, 0.014, 0.01, 0.82))
	root.add_child(back)

	var fill: MeshInstance3D = _make_quad(FILL_NAME, Vector2(BAR_WIDTH, BAR_HEIGHT * 0.72), Color(1.0, 0.48, 0.16, 0.96))
	fill.position.z = 0.003
	root.add_child(fill)
	return root


static func _get_root(soldier) -> Node3D:
	if not is_instance_valid(soldier):
		return null
	var root: Node = soldier.get_node_or_null(ROOT_NAME)
	return root as Node3D if root is Node3D else null


static func _make_quad(node_name: String, size: Vector2, color: Color) -> MeshInstance3D:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = _make_material(color)
	return instance


static func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	return material


static func _update_fill(root: Node3D, ratio: float, urgent: bool) -> void:
	var fill := root.get_node_or_null(FILL_NAME) as MeshInstance3D
	if fill == null:
		return
	var width: float = maxf(0.018, BAR_WIDTH * ratio)
	var mesh := fill.mesh as QuadMesh
	if mesh != null:
		mesh.size = Vector2(width, BAR_HEIGHT * 0.72)
	fill.position.x = -BAR_WIDTH * 0.5 + width * 0.5
	var fill_material := fill.material_override as StandardMaterial3D
	if fill_material != null:
		fill_material.albedo_color = Color(1.0, 0.22, 0.12, 0.98) if urgent else Color(1.0, 0.52, 0.16, 0.94)
	var back := root.get_node_or_null(BACK_NAME) as MeshInstance3D
	if back != null:
		var back_material := back.material_override as StandardMaterial3D
		if back_material != null:
			back_material.albedo_color = Color(0.02, 0.014, 0.01, 0.82)


static func _get_smoothed_display_ratio(root: Node3D, target_ratio: float) -> float:
	var target := pow(clampf(target_ratio, 0.0, 1.0), 1.65)
	var now_msec := Time.get_ticks_msec()
	var previous_msec := int(root.get_meta(META_LAST_UPDATE_MSEC, now_msec))
	root.set_meta(META_LAST_UPDATE_MSEC, now_msec)
	var delta := clampf(float(now_msec - previous_msec) / 1000.0, 0.0, 0.12)
	var display := float(root.get_meta(META_DISPLAY_RATIO, 0.0))
	if float(now_msec - previous_msec) / 1000.0 > DISPLAY_RESET_GAP_SECONDS:
		display = 0.0
	if target < display:
		display = target
	else:
		var weight := 1.0 - exp(-DISPLAY_CATCH_UP_SPEED * delta)
		display = lerpf(display, target, clampf(weight, 0.0, 1.0))
		if target - display < 0.01:
			display = target
	display = clampf(display, 0.0, 1.0)
	root.set_meta(META_DISPLAY_RATIO, display)
	return display
