extends Node3D

@export var shared_material: Material

func _ready() -> void:
	if shared_material == null:
		return
	_apply_material_recursive(self)

func _apply_material_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			mesh_instance.material_override = shared_material
		_apply_material_recursive(child)
