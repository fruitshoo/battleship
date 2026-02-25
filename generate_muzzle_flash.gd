extends SceneTree

func _init() -> void:
    print("Generating Muzzle Flash Effect Scene...")
    
    var particles = GPUParticles3D.new()
    particles.name = "MuzzleFlash"
    
    # 💥 짧고 강력하게 한 번만 터지도록 설정
    particles.amount = 2
    particles.lifetime = 0.15 # 매우 짧은 시간
    particles.one_shot = true # 한 번만 발사
    particles.explosiveness = 1.0 # 한꺼번에 모두 분출
    particles.randomness = 0.5
    particles.local_coords = false # 월드 좌표로 방출 (대포 방향은 외부에서 주입)
    
    # 1. Mesh 설정
    var mesh = QuadMesh.new()
    mesh.size = Vector2(3.0, 3.0) # 생각보다 크게 터짐
    
    # 2. Material 설정 (빌보드 + 가산 혼합)
    var mat = StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD # 덧셈 혼합 (빛나게)
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    mat.billboard_keep_scale = true
    
    var tex = load("res://assets/vfx/particles/alpha/muzzle_05_a.png") as Texture2D
    mat.albedo_texture = tex
    mat.albedo_color = Color(2.0, 1.0, 0.5, 1.0) # 밝은 노랑/오렌지 빛 (초과값으로 글로우 효과 유도)
    
    mesh.material = mat
    particles.draw_pass_1 = mesh
    
    # 3. Process Material 설정
    var process_mat = ParticleProcessMaterial.new()
    process_mat.direction = Vector3(0, 0, 1) # 기본값, cannon.gd에서 set_fire_direction()으로 덮어씀
    process_mat.spread = 15.0
    process_mat.initial_velocity_min = 2.0
    process_mat.initial_velocity_max = 5.0
    process_mat.gravity = Vector3.ZERO
    
    # 랜덤 각도
    process_mat.angle_min = 0.0
    process_mat.angle_max = 360.0
    
    # 빠르게 커졌다가 사라지는 스케일
    var scale_curve = CurveTexture.new()
    var s_curve = Curve.new()
    s_curve.add_point(Vector2(0.0, 0.5))
    s_curve.add_point(Vector2(0.2, 1.2)) # 순식간에 최대 크기
    s_curve.add_point(Vector2(1.0, 0.0)) # 작아지면서 사라짐
    scale_curve.curve = s_curve
    process_mat.scale_curve = scale_curve
    
    # 색상 페이드 아웃
    var color_ramp = GradientTexture1D.new()
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(1, 1, 1, 1))
    gradient.add_point(0.5, Color(1, 0.8, 0.4, 0.8))
    gradient.add_point(1.0, Color(1, 0.2, 0.0, 0))
    color_ramp.gradient = gradient
    process_mat.color_ramp = color_ramp
    
    particles.process_material = process_mat
    
    # 4. 섬광 조명 추가 (OmniLight3D)
    var light = OmniLight3D.new()
    light.name = "FlashLight"
    light.light_color = Color(1.0, 0.8, 0.3)
    light.light_energy = 3.0
    light.omni_range = 15.0
    
    # 빛이 순식간에 사라지는 스크립트를 연결할 수 있지만
    # 여기서는 파티클 자체의 수명이 다하면 queue_free를 하도록 짠다.
    
    particles.add_child(light)
    light.owner = particles
    
    # 5. 파티클 자동 삭제 + 방향 주입 스크립트
    var script = GDScript.new()
    script.source_code = """
extends GPUParticles3D
@onready var light: OmniLight3D = $FlashLight

func _ready() -> void:
	emitting = true
	# 조명이 수명에 맞춰 천천히 꺼지게 트위닝
	var t = create_tween()
	t.tween_property(light, "light_energy", 0.0, lifetime)
	# 수명이 다하면 자기 삭제
	get_tree().create_timer(lifetime + 0.1).timeout.connect(queue_free)

## cannon.gd에서 발사 방향(월드 좌표계)을 주입
func set_fire_direction(dir: Vector3) -> void:
	var pm = process_material as ParticleProcessMaterial
	if pm:
		pm.direction = dir
"""
    particles.set_script(script)
    
    # Save the scene
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(particles)
    if result == OK:
        var err = ResourceSaver.save(packed_scene, "res://scenes/effects/muzzle_flash.tscn")
        if err == OK:
            print("Successfully saved muzzle_flash.tscn")
        else:
            print("Failed to save: ", err)
    else:
        print("Failed to pack scene: ", result)
    
    quit()
