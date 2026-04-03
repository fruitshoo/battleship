@tool
extends Node3D

static var runtime_enabled: bool = false
var tracked_ship: Node3D = null

const RING_RADII: Array[float] = [2.0, 4.0, 6.0, 8.0, 10.0]
const RING_COLORS: Array[Color] = [
	Color(0.46, 0.95, 1.0, 0.16),
	Color(0.46, 0.95, 1.0, 0.16),
	Color(0.95, 0.88, 0.28, 0.18),
	Color(0.95, 0.64, 0.24, 0.18),
	Color(1.0, 0.36, 0.24, 0.2),
]

var _rings: Array[MeshInstance3D] = []
var _cannon_range_ring: MeshInstance3D = null
var _cannon_range_refresh_left: float = 0.0
var _pulse_time: float = 0.0

func _ready() -> void:
	add_to_group("distance_debug_visualizers")
	top_level = true
	_ensure_rings()
	_ensure_cannon_range_ring()
	_sync_world_transform()
	_refresh_visibility()
	set_process(true)


func _process(_delta: float) -> void:
	_sync_world_transform()
	_update_cannon_range_ring(_delta)
	_update_pulse_animation(_delta)
	_refresh_visibility()


func _update_pulse_animation(delta: float) -> void:
	if not runtime_enabled and not Engine.is_editor_hint():
		return
	_pulse_time += delta * 2.0
	var pulse_val = (sin(_pulse_time) + 1.0) * 0.5 # 0.0 ~ 1.0
	
	for i in range(_rings.size()):
		var ring = _rings[i]
		if is_instance_valid(ring) and ring.mesh and ring.mesh.surface_get_material(0):
			var mat = ring.mesh.surface_get_material(0) as StandardMaterial3D
			mat.emission_energy_multiplier = (0.3 + pulse_val * 0.4) * (0.55 if i < 2 else 0.7)


static func set_runtime_enabled(enabled: bool) -> void:
	runtime_enabled = enabled


func _refresh_visibility() -> void:
	var visible_now: bool = Engine.is_editor_hint() or runtime_enabled
	visible = visible_now
	for ring in _rings:
		if is_instance_valid(ring):
			ring.visible = visible_now
	if is_instance_valid(_cannon_range_ring):
		_cannon_range_ring.visible = visible_now and _cannon_range_ring.scale.x > 0.01


func _ensure_rings() -> void:
	if not _rings.is_empty():
		return
	for index in range(RING_RADII.size()):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _create_ring_mesh(RING_COLORS[index], 0.55 if index < 2 else 0.7)
		mesh_instance.scale = Vector3(RING_RADII[index] * 2.0, 1.0, RING_RADII[index] * 2.0)
		mesh_instance.position = Vector3(0.0, 0.92 + float(index) * 0.1, 0.0)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_instance)
		_rings.append(mesh_instance)


func _ensure_cannon_range_ring() -> void:
	if is_instance_valid(_cannon_range_ring):
		return
	_cannon_range_ring = MeshInstance3D.new()
	_cannon_range_ring.mesh = _create_ring_mesh(Color(1.0, 0.93, 0.54, 0.13), 0.5)
	_cannon_range_ring.scale = Vector3.ZERO
	_cannon_range_ring.position = Vector3(0.0, 0.86, 0.0)
	_cannon_range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cannon_range_ring)

func _create_ring_mesh(fill_color: Color, emission_energy: float) -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.height = 0.04
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = fill_color
	mat.emission_enabled = true
	mat.emission = Color(fill_color.r, fill_color.g, fill_color.b, 1.0)
	mat.emission_energy_multiplier = emission_energy * 0.6
	mat.no_depth_test = true # 항상 함선 위에 보이도록 설정
	mat.render_priority = 10 # 렌더링 순위 상향
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.surface_set_material(0, mat)
	return cyl


func _sync_world_transform() -> void:
	var target_ship: Node3D = tracked_ship
	if not is_instance_valid(target_ship):
		target_ship = get_parent_node_3d()
	if not is_instance_valid(target_ship):
		return
	var anchor_pos := target_ship.global_position
	global_transform = Transform3D(Basis.IDENTITY, Vector3(anchor_pos.x, anchor_pos.y, anchor_pos.z))


func _update_cannon_range_ring(delta: float) -> void:
	if not is_instance_valid(_cannon_range_ring):
		return
	_cannon_range_refresh_left = maxf(0.0, _cannon_range_refresh_left - delta)
	if _cannon_range_refresh_left > 0.0:
		return
	_cannon_range_refresh_left = 0.35
	var owner_ship := get_parent_node_3d()
	if not is_instance_valid(owner_ship):
		owner_ship = tracked_ship
	if not is_instance_valid(owner_ship):
		_cannon_range_ring.scale = Vector3.ZERO
		return
	var cannon_range: float = _get_owner_cannon_range(owner_ship)
	if cannon_range <= 0.01:
		_cannon_range_ring.scale = Vector3.ZERO
		return
	_cannon_range_ring.scale = Vector3(cannon_range * 2.0, 1.0, cannon_range * 2.0)


func _get_owner_cannon_range(owner_ship: Node) -> float:
	var max_range: float = 0.0
	var stack: Array[Node] = [owner_ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.has_method("_get_current_range"):
			max_range = maxf(max_range, float(node.call("_get_current_range")))
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return max_range
