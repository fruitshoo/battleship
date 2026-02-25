@tool
extends SceneTree

func _init():
	var root = Node3D.new()
	root.name = "WoodSplinter"
	root.set_script(load("res://scripts/effects/wood_splinter.gd"))
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.35, 0.2, 1.0) # 덜 붉고 짙은 통나무 색상
	material.roughness = 0.8
	
	# Process Material for Cubes
	var proc_cubes = ParticleProcessMaterial.new()
	proc_cubes.direction = Vector3(0, 1, 0)
	proc_cubes.spread = 50.0
	proc_cubes.initial_velocity_max = 12.0
	proc_cubes.angle_min = 0.0
	proc_cubes.angle_max = 360.0
	proc_cubes.angular_velocity_min = -360.0
	proc_cubes.angular_velocity_max = 360.0
	proc_cubes.scale_min = 0.5
	proc_cubes.scale_max = 1.2
	proc_cubes.gravity = Vector3(0, -25, 0)
	
	var cubes = GPUParticles3D.new()
	cubes.name = "Cubes"
	cubes.emitting = false
	cubes.amount = 24
	cubes.lifetime = 1.2
	cubes.one_shot = true
	cubes.explosiveness = 0.95
	cubes.process_material = proc_cubes
	
	var cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(0.4, 0.4, 0.4) # 기존 0.2에서 2배 키움
	cube_mesh.material = material
	cubes.draw_pass_1 = cube_mesh
	
	root.add_child(cubes)
	cubes.owner = root
	
	# Process Material for Planks
	var proc_planks = ParticleProcessMaterial.new()
	proc_planks.direction = Vector3(0, 1, 0)
	proc_planks.spread = 50.0
	proc_planks.initial_velocity_max = 12.0
	proc_planks.angle_min = 0.0
	proc_planks.angle_max = 360.0
	proc_planks.particle_flag_align_y = true # 속도 방향으로 정렬 (궤적을 따라 자연스럽게 날아감)
	# align_y와 축 회전충돌 방지를 위해 각속도 제거 또는 낮춤
	proc_planks.angular_velocity_min = -90.0
	proc_planks.angular_velocity_max = 90.0
	proc_planks.scale_min = 0.5
	proc_planks.scale_max = 1.5
	proc_planks.gravity = Vector3(0, -25, 0)
	
	var planks = GPUParticles3D.new()
	planks.name = "Planks"
	planks.emitting = false
	planks.amount = 6
	planks.lifetime = 1.2
	planks.one_shot = true
	planks.explosiveness = 0.85 # 약간 다른 박자로 터지게
	planks.process_material = proc_planks
	
	var plank_mesh = BoxMesh.new()
	plank_mesh.size = Vector3(0.25, 0.25, 0.8) # 기존 0.15 x 0.6 에서 살짝 더 크고 굵게
	plank_mesh.material = material
	planks.draw_pass_1 = plank_mesh
	
	root.add_child(planks)
	planks.owner = root

	var packed_scene = PackedScene.new()
	packed_scene.pack(root)
	ResourceSaver.save(packed_scene, "res://scenes/effects/wood_splinter.tscn")
	
	print("Successfully generated res://scenes/effects/wood_splinter.tscn with mixed particles!")
	quit()
