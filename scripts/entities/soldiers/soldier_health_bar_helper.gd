extends RefCounted
class_name SoldierHealthBarHelper


const ROOT_NAME := "AllyHealthBar"
const BACK_NAME := "Back"
const FILL_NAME := "Fill"
const BAR_WIDTH := 1.06
const BAR_HEIGHT := 0.092
const BAR_Y := 0.18
const LOW_HEALTH_RATIO := 0.30


static func update(soldier, visible_timer: float) -> void:
	if not _should_show(soldier, visible_timer):
		hide(soldier)
		return
	var ratio: float = clampf(float(soldier.current_health) / maxf(1.0, float(soldier.max_health)), 0.0, 1.0)
	var alpha := 0.92
	if ratio > LOW_HEALTH_RATIO:
		alpha = clampf(visible_timer / 0.55, 0.0, 0.92)
	if alpha <= 0.03:
		hide(soldier)
		return
	var root := _ensure_root(soldier)
	if root == null:
		return
	root.visible = true
	root.position = Vector3(0.0, BAR_Y, 0.0)
	_update_fill(root, ratio, alpha)


static func hide(soldier) -> void:
	var root: Node3D = _get_root(soldier)
	if root != null:
		root.visible = false


static func _should_show(soldier, visible_timer: float) -> bool:
	if not is_instance_valid(soldier):
		return false
	if str(soldier.get("team")) != "player":
		return false
	if int(soldier.get("current_state")) == int(soldier.State.DEAD):
		return false
	var max_health := maxf(1.0, float(soldier.get("max_health")))
	var current_health := clampf(float(soldier.get("current_health")), 0.0, max_health)
	if current_health >= max_health - 0.35:
		return false
	var ratio := current_health / max_health
	return visible_timer > 0.0 or ratio <= LOW_HEALTH_RATIO


static func _ensure_root(soldier) -> Node3D:
	var root: Node3D = _get_root(soldier)
	if root != null:
		return root
	root = Node3D.new()
	root.name = ROOT_NAME
	root.visible = false
	soldier.add_child(root)

	var back: MeshInstance3D = _make_quad(BACK_NAME, Vector2(BAR_WIDTH, BAR_HEIGHT), Color(0.02, 0.018, 0.014, 0.76))
	root.add_child(back)

	var fill: MeshInstance3D = _make_quad(FILL_NAME, Vector2(BAR_WIDTH, BAR_HEIGHT * 0.72), Color(0.22, 0.86, 0.32, 0.96))
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


static func _update_fill(root: Node3D, ratio: float, alpha: float) -> void:
	var fill := root.get_node_or_null(FILL_NAME) as MeshInstance3D
	if fill == null:
		return
	var width: float = maxf(0.015, BAR_WIDTH * ratio)
	var mesh := fill.mesh as QuadMesh
	if mesh != null:
		mesh.size = Vector2(width, BAR_HEIGHT * 0.72)
	fill.position.x = -BAR_WIDTH * 0.5 + width * 0.5
	var material := fill.material_override as StandardMaterial3D
	if material != null:
		var color := _get_fill_color(ratio)
		color.a = alpha
		material.albedo_color = color
	var back := root.get_node_or_null(BACK_NAME) as MeshInstance3D
	if back != null:
		var back_material := back.material_override as StandardMaterial3D
		if back_material != null:
			back_material.albedo_color = Color(0.02, 0.018, 0.014, alpha * 0.82)


static func _get_fill_color(ratio: float) -> Color:
	if ratio <= 0.28:
		return Color(1.0, 0.18, 0.12, 1.0)
	if ratio <= 0.55:
		return Color(1.0, 0.68, 0.18, 1.0)
	return Color(0.26, 0.86, 0.32, 1.0)
