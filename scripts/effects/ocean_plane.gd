extends MeshInstance3D
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")

## 플레이어를 따라다니는 수면 평면
## 작은 메시 하나로 무한 바다처럼 보이게 하는 표준 기법 (포그로 경계 숨김)

@export var follow_target_path: NodePath
@export var grid_size: float = 50.0 # 50미터 단위로 이동 (바다 축소 대응)

var _target: Node3D = null
var _shader_material: ShaderMaterial = null

func _ready() -> void:
	# Y는 항상 0 (수면)으로 고정
	global_position.y = 0.0
	add_to_group("ocean")
	_resolve_shader_material()
	_sync_shader_params()

func _resolve_shader_material() -> void:
	var mat = material_override
	if not mat and mesh:
		mat = mesh.surface_get_material(0)
	if mat is ShaderMaterial:
		_shader_material = mat

# === CPU 파도 연산용 파라미터 ===
var sea_height: float = 0.6
var sea_choppy: float = 4.0
var sea_speed: float = 0.8
var sea_freq: float = 0.16
var iter_geometry: int = 2 # CPU 최적화를 위해 반복 횟수(octaves)를 2로 제한

func _sync_shader_params() -> void:
	_resolve_shader_material()
	if _shader_material:
		var h = _shader_material.get_shader_parameter("sea_height")
		if h != null: sea_height = h
		var c = _shader_material.get_shader_parameter("sea_choppy")
		if c != null: sea_choppy = c
		var s = _shader_material.get_shader_parameter("sea_speed")
		if s != null: sea_speed = s
		var f = _shader_material.get_shader_parameter("sea_freq")
		if f != null: sea_freq = f

# GPU 셰이더의 hash12 이식
func _hash12(p: Vector2) -> float:
	var px = int(floor(p.x)) & 0xFFFFFFFF
	var py = int(floor(p.y)) & 0xFFFFFFFF
	var qx = (px * 1597334677) & 0xFFFFFFFF
	var qy = (py * 3812015801) & 0xFFFFFFFF
	var n = ((qx ^ qy) * 1597334677) & 0xFFFFFFFF
	return float(n) / 4294967295.0

# GPU 셰이더의 noise 이식
func _noise(p: Vector2) -> float:
	var i = p.floor()
	var f = p - i
	var u = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var h00 = _hash12(i + Vector2(0.0, 0.0))
	var h10 = _hash12(i + Vector2(1.0, 0.0))
	var h01 = _hash12(i + Vector2(0.0, 1.0))
	var h11 = _hash12(i + Vector2(1.0, 1.0))
	var mix_y1 = lerp(h00, h10, u.x)
	var mix_y2 = lerp(h01, h11, u.x)
	return -1.0 + 2.0 * lerp(mix_y1, mix_y2, u.y)

# GPU 셰이더의 sea_octave 이식
func _sea_octave(uv: Vector2, choppy: float) -> float:
	var n = _noise(uv)
	uv.x += n
	uv.y += n
	var wv_x = 1.0 - abs(sin(uv.x))
	var wv_y = 1.0 - abs(sin(uv.y))
	var swv_x = abs(cos(uv.x))
	var swv_y = abs(cos(uv.y))
	wv_x = lerp(wv_x, swv_x, wv_x)
	wv_y = lerp(wv_y, swv_y, wv_y)
	return pow(1.0 - pow(wv_x * wv_y, 0.65), choppy)

func get_wave_height(global_pos: Vector3) -> float:
	var time = Time.get_ticks_msec() * 0.001
	var freq = sea_freq
	var amp = sea_height
	var choppy = sea_choppy
	var uv = Vector2(global_pos.x, global_pos.z)
	uv.x *= 0.75
	var h = 0.0
	
	for i in range(iter_geometry):
		var d = _sea_octave((uv + Vector2(1.0, 1.0) * time * sea_speed) * freq, choppy)
		d += _sea_octave((uv - Vector2(1.0, 1.0) * time * sea_speed) * freq, choppy)
		h += d * amp
		
		var nx = uv.x * 1.6 + uv.y * 1.2
		var ny = uv.x * -1.2 + uv.y * 1.6
		uv.x = nx
		uv.y = ny
		
		freq *= 1.9
		amp *= 0.22
		choppy = lerp(choppy, 1.0, 0.2)
		
	return h

func _process(_delta: float) -> void:
	# 타겟이 없으면 매 프레임 찾기 시도 (초기화 타이밍 문제 해결)
	if not is_instance_valid(_target):
		_target = SceneGroupCache.get_first(get_tree(), "player") as Node3D
		if not is_instance_valid(_target):
			return # 타겟 찾을 때까지 대기
	
	# 격차 이동 로직 (Grid Snapping)
	var target_pos = _target.global_position
	
	var new_x = round(target_pos.x / grid_size) * grid_size
	var new_z = round(target_pos.z / grid_size) * grid_size
	if abs(global_position.x - new_x) > 0.1 or abs(global_position.z - new_z) > 0.1:
		global_position.x = new_x
		global_position.z = new_z

	if _shader_material:
		_shader_material.set_shader_parameter("player_center_ws", _target.global_position)
