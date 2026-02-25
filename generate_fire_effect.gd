extends SceneTree

func _init() -> void:
    print("Generating Fire/Smoke Effect Scene...")
    var particles = GPUParticles3D.new()
    particles.name = "FireEffect"
    particles.amount = 12
    particles.lifetime = 2.0
    particles.explosiveness = 0.0
    particles.randomness = 0.3
    # Use global coordinates so it leaves a trail
    particles.local_coords = false
    
    # 1. Create QuadMesh for the particles
    var mesh = QuadMesh.new()
    mesh.size = Vector2(2.5, 2.5)
    
    # 2. Create the StandardMaterial3D (Billboard + Flipbook)
    var mat = StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    
    # Billboard settings for particles
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    mat.billboard_keep_scale = true
    
    # Load flipbook texture
    var tex = load("res://assets/vfx/flipbooks/wispy_smoke_01_8x8.tga") as Texture2D
    mat.albedo_texture = tex
    # Tint the smoke slightly dark/grayish with some transparency
    mat.albedo_color = Color(0.3, 0.3, 0.3, 0.8)
    
    # Set up particles animation
    mat.particles_anim_h_frames = 8
    mat.particles_anim_v_frames = 8
    mat.particles_anim_loop = false
    
    mesh.material = mat
    particles.draw_pass_1 = mesh
    
    # 3. Create ParticleProcessMaterial
    var process_mat = ParticleProcessMaterial.new()
    # Emission box (slightly spread out)
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process_mat.emission_box_extents = Vector3(1.0, 0.2, 1.0)
    
    # Upward movement
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 20.0
    process_mat.initial_velocity_min = 1.0
    process_mat.initial_velocity_max = 3.0
    process_mat.gravity = Vector3(0, 0.5, 0) # slight upward pull
    
    # Rotation & Scale
    process_mat.angle_min = 0.0
    process_mat.angle_max = 360.0 # Random initial rotation
    process_mat.scale_min = 0.8
    process_mat.scale_max = 1.5
    
    # Scale curved over time (start small, grow big)
    var scale_curve = CurveTexture.new()
    var s_curve = Curve.new()
    s_curve.add_point(Vector2(0.0, 0.5))
    s_curve.add_point(Vector2(1.0, 1.5))
    scale_curve.curve = s_curve
    process_mat.scale_curve = scale_curve
    
    # Color fade out over time
    var color_ramp = GradientTexture1D.new()
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(1, 1, 1, 1))
    gradient.add_point(0.7, Color(1, 1, 1, 0.8))
    gradient.add_point(1.0, Color(1, 1, 1, 0))
    color_ramp.gradient = gradient
    process_mat.color_ramp = color_ramp
    
    # Animation frames configuration (0 to 1 over lifetime)
    process_mat.anim_speed_min = 1.0
    process_mat.anim_speed_max = 1.0
    process_mat.anim_offset_min = 0.0
    process_mat.anim_offset_max = 0.0
    
    particles.process_material = process_mat
    
    # Set up OmniLight3D for fire glow effect
    var light = OmniLight3D.new()
    light.name = "FireLight"
    light.light_color = Color(1.0, 0.5, 0.1) # Orange/Red
    light.light_energy = 2.0
    light.omni_range = 10.0
    light.position = Vector3(0, 1, 0)
    
    particles.add_child(light)
    light.owner = particles
    
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(particles)
    if result == OK:
        var err = ResourceSaver.save(packed_scene, "res://scenes/effects/fire_effect.tscn")
        if err == OK:
            print("Successfully saved fire_effect.tscn")
        else:
            print("Failed to save: ", err)
    else:
        print("Failed to pack scene: ", result)
    
    quit()
