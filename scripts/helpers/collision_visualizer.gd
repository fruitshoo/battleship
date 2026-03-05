@tool
extends Node3D

var _debug_mesh: MeshInstance3D

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		# 게임 런타임 중에는 연산 중지 및 시각화 숨김
		hide()
		set_process(false)
		return
		
	var parent = get_parent()
	if not parent: return
	
	# 부모 함선의 Export 변수 접근
	var r = parent.get("base_collision_radius")
	var w = parent.get("width_multiplier")
	var l = parent.get("length_multiplier")
	
	if r != null and w != null and l != null:
		if not is_instance_valid(_debug_mesh):
			_debug_mesh = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.height = 0.1
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			_debug_mesh.mesh = cyl
			
			var mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1.0, 0.4, 0.0, 0.4) # 주황색 반투명
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			cyl.surface_set_material(0, mat)
			
			add_child(_debug_mesh)
			
		# 타원형 바운더리 크기 실시간 업데이트
		_debug_mesh.scale = Vector3(r * w * 2.0, 1.0, r * l * 2.0)
