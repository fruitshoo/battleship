@tool
extends Node3D

static var runtime_enabled: bool = false
static var runtime_mode: int = 0

@export var show_in_editor: bool = false

const MODE_ALL := 0
const MODE_BASE := 1
const MODE_SEPARATION := 2
const MODE_GUARD := 3

var _debug_mesh: MeshInstance3D
var _separation_mesh: MeshInstance3D
var _guard_mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("collision_visualizers")
	_ensure_debug_meshes()
	_refresh_visibility()
	set_process(true)

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() and not runtime_enabled:
		_refresh_visibility()
		return
		
	var parent = get_parent()
	if not parent: return
	
	# 부모 함선의 Export 변수 접근
	var r = parent.get("base_collision_radius")
	var w = parent.get("width_multiplier")
	var l = parent.get("length_multiplier")
	
	if r != null and w != null and l != null:
		_ensure_debug_meshes()
		# 타원형 바운더리 크기 실시간 업데이트
		_debug_mesh.scale = Vector3(r * w * 2.0, 1.0, r * l * 2.0)
		_debug_mesh.position = Vector3(0.0, 0.35, 0.0)
		var separation_pad := _get_separation_padding(parent)
		_separation_mesh.scale = Vector3((r * w + separation_pad) * 2.0, 1.0, (r * l + separation_pad) * 2.0)
		_separation_mesh.position = Vector3(0.0, 1.0, 0.0)
		var guard_scale := _get_guard_scale(parent)
		_guard_mesh.scale = Vector3(r * w * 2.0 * guard_scale, 1.0, r * l * 2.0 * guard_scale)
		_guard_mesh.position = Vector3(0.0, 1.65, 0.0)
		_refresh_visibility()

func _refresh_visibility() -> void:
	var visible_now := (Engine.is_editor_hint() and show_in_editor) or (not Engine.is_editor_hint() and runtime_enabled)
	visible = visible_now
	if is_instance_valid(_debug_mesh):
		_debug_mesh.visible = visible_now and _is_mesh_visible(MODE_BASE)
	if is_instance_valid(_separation_mesh):
		_separation_mesh.visible = visible_now and _is_mesh_visible(MODE_SEPARATION)
	if is_instance_valid(_guard_mesh):
		_guard_mesh.visible = visible_now and _is_mesh_visible(MODE_GUARD) and _get_guard_scale(get_parent()) < 0.999

static func set_runtime_enabled(enabled: bool) -> void:
	runtime_enabled = enabled

static func cycle_runtime_mode() -> int:
	runtime_mode = wrapi(runtime_mode + 1, 0, 4)
	return runtime_mode

func _ensure_debug_meshes() -> void:
	if is_instance_valid(_debug_mesh) and is_instance_valid(_separation_mesh) and is_instance_valid(_guard_mesh):
		return

	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.mesh = _create_ring_mesh(Color(1.0, 0.45, 0.05, 0.32), Color(1.0, 0.45, 0.05), 0.8)
	add_child(_debug_mesh)
	_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_separation_mesh = MeshInstance3D.new()
	_separation_mesh.mesh = _create_ring_mesh(Color(1.0, 0.9, 0.2, 0.28), Color(1.0, 0.9, 0.2), 0.65)
	add_child(_separation_mesh)
	_separation_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_guard_mesh = MeshInstance3D.new()
	_guard_mesh.mesh = _create_ring_mesh(Color(0.45, 0.95, 1.0, 0.3), Color(0.45, 0.95, 1.0), 0.75)
	add_child(_guard_mesh)
	_guard_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _create_ring_mesh(fill_color: Color, emission_color: Color, emission_energy: float) -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.height = 0.05
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = fill_color
	mat.emission_enabled = true
	mat.emission = emission_color
	mat.emission_energy_multiplier = emission_energy
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.surface_set_material(0, mat)
	return cyl

func _get_separation_padding(parent: Node) -> float:
	if not is_instance_valid(parent):
		return 0.0
	var base_pad := 0.18
	match parent.name:
		"PlayerShip":
			base_pad = 0.12
		"BossShip":
			base_pad = 0.20
	var pad_scale = parent.get("separation_pad_scale")
	if pad_scale != null:
		base_pad *= float(pad_scale)
	return base_pad

func _get_guard_scale(parent: Node) -> float:
	if not is_instance_valid(parent):
		return 1.0
	match parent.name:
		"EnemyShip":
			return 0.93
		"BossShip":
			return 0.93
		_:
			return 1.0

func _is_mesh_visible(mode: int) -> bool:
	return runtime_mode == MODE_ALL or runtime_mode == mode
