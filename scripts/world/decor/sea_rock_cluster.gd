extends Node3D

const ROCK_SHADER := preload("res://assets/shaders/sea_rock_procedural.gdshader")

var _rock_meshes: Array[MeshInstance3D] = []
var _warm_material: ShaderMaterial = null
var _cool_material: ShaderMaterial = null


func _ready() -> void:
	_build_procedural_materials()
	_collect_rock_meshes(self)
	_apply_procedural_materials()


func set_rock_view_fade_alpha(_alpha: float) -> void:
	pass


func _collect_rock_meshes(root: Node) -> void:
	if root is MeshInstance3D:
		_rock_meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_rock_meshes(child)


func _build_procedural_materials() -> void:
	_warm_material = ShaderMaterial.new()
	_warm_material.shader = ROCK_SHADER
	_warm_material.set_shader_parameter("rock_dark", Color(0.08, 0.1, 0.085, 1.0))
	_warm_material.set_shader_parameter("rock_mid", Color(0.2, 0.22, 0.18, 1.0))
	_warm_material.set_shader_parameter("pattern_scale", 1.05)
	_warm_material.set_shader_parameter("wet_darkening", 0.34)
	_warm_material.set_shader_parameter("roughness_value", 0.94)

	_cool_material = ShaderMaterial.new()
	_cool_material.shader = ROCK_SHADER
	_cool_material.set_shader_parameter("rock_dark", Color(0.07, 0.095, 0.095, 1.0))
	_cool_material.set_shader_parameter("rock_mid", Color(0.17, 0.21, 0.2, 1.0))
	_cool_material.set_shader_parameter("pattern_scale", 1.25)
	_cool_material.set_shader_parameter("wet_darkening", 0.38)
	_cool_material.set_shader_parameter("roughness_value", 0.96)


func _apply_procedural_materials() -> void:
	for mesh in _rock_meshes:
		if not is_instance_valid(mesh):
			continue
		mesh.material_override = _cool_material if _uses_cool_material(mesh) else _warm_material


func _uses_cool_material(mesh: MeshInstance3D) -> bool:
	var mesh_name := mesh.name.to_lower()
	return mesh_name.contains("spire") or mesh_name == "submergedbaseb"
