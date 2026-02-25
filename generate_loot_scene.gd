@tool
extends SceneTree

func _init():
	var root = Area3D.new()
	root.name = "FloatingLoot"
	root.set_script(load("res://scripts/effects/floating_loot.gd"))
	root.set_collision_layer_value(1, false)
	root.set_collision_mask_value(1, true)
	root.set_collision_mask_value(2, true)
	root.set_collision_mask_value(3, true)
	root.set_collision_mask_value(4, true)
	
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var barrel_mesh = CylinderMesh.new()
	barrel_mesh.top_radius = 0.4
	barrel_mesh.bottom_radius = 0.4
	barrel_mesh.height = 1.0
	mesh_instance.mesh = barrel_mesh
	root.add_child(mesh_instance)
	mesh_instance.owner = root
	
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 4.0 # 넉넉한 피격 판정 (자석 효과 후 금방 닿도록)
	collision.shape = sphere_shape
	root.add_child(collision)
	collision.owner = root

	var packed_scene = PackedScene.new()
	packed_scene.pack(root)
	ResourceSaver.save(packed_scene, "res://scenes/effects/floating_loot.tscn")
	
	print("Successfully generated res://scenes/effects/floating_loot.tscn!")
	quit()
