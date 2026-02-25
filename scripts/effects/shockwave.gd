extends GPUParticles3D

## 동적 쇼크웨이브 이펙트
## 매번 랜덤 회전, 타이밍, 텍스처 조합을 사용해 반복적으로 보이지 않도록 합니다.

# 사용할 텍스처 풀 (circle, effect, light 시리즈 혼합)
const TEXTURES_RING = [
	"res://assets/vfx/particles/alpha/circle_01_a.png",
	"res://assets/vfx/particles/alpha/circle_02_a.png",
	"res://assets/vfx/particles/alpha/circle_04_a.png",
]
const TEXTURES_INNER = [
	"res://assets/vfx/particles/alpha/effect_01_a.png",
	"res://assets/vfx/particles/alpha/effect_02_a.png",
	"res://assets/vfx/particles/alpha/effect_03_a.png",
	"res://assets/vfx/particles/alpha/light_01_a.png",
]
const TEXTURES_SPARK = [
	"res://assets/vfx/particles/alpha/spark_01_a.png",
	"res://assets/vfx/particles/alpha/spark_04_a.png",
	"res://assets/vfx/particles/alpha/flare_01_a.png",
]

func _ready() -> void:
	# === 외곽 링 레이어 (즉시 방출) ===
	_randomize_and_emit(self)

	# === 내부 파동 레이어 (약간 지연) ===
	if has_node("InnerWave"):
		var inner = $InnerWave
		var delay = randf_range(0.03, 0.08)
		get_tree().create_timer(delay).timeout.connect(func():
			if is_instance_valid(inner):
				_randomize_and_emit(inner)
		)

	# === 스파크 레이어 (또 약간 더 지연) ===
	if has_node("SparkLayer"):
		var spark = $SparkLayer
		var delay2 = randf_range(0.06, 0.12)
		get_tree().create_timer(delay2).timeout.connect(func():
			if is_instance_valid(spark):
				_randomize_and_emit(spark)
		)

	# 최종 정리
	var max_life = lifetime
	if has_node("InnerWave"): max_life = max(max_life, $InnerWave.lifetime)
	if has_node("SparkLayer"): max_life = max(max_life, $SparkLayer.lifetime)
	get_tree().create_timer(max_life + 0.5).timeout.connect(queue_free)


func _randomize_and_emit(node: GPUParticles3D) -> void:
	# 1. 랜덤 회전 — 매번 다른 방향으로 보임
	node.rotation.z = randf() * TAU
	node.rotation.y = randf_range(-0.3, 0.3) # 살짝 기울어짐
	
	# 2. 랜덤 스케일 변동 (±15%)
	var s = randf_range(0.85, 1.15)
	node.scale = Vector3(s, s, s)
	
	# 3. 랜덤 색상 톤 변환 (따뜻한 주황~상큼한 흰색)
	var tint = Color(
		randf_range(0.9, 1.0),
		randf_range(0.7, 1.0),
		randf_range(0.4, 0.9),
		randf_range(0.1, 0.25) # 투명도를 0.35-0.7에서 0.1-0.25로 대폭 하향
	)
	if node.process_material:
		node.process_material = node.process_material.duplicate()
		node.process_material.color = tint

	# 4. 랜덤 텍스처 선택
	var mat: StandardMaterial3D = null
	if node.draw_pass_1 and node.draw_pass_1.material:
		mat = node.draw_pass_1.material.duplicate()
		node.draw_pass_1 = node.draw_pass_1.duplicate()
		node.draw_pass_1.material = mat
	
	if mat:
		var pool: Array
		match node.name:
			"Shockwave": pool = TEXTURES_RING
			"InnerWave": pool = TEXTURES_INNER
			"SparkLayer": pool = TEXTURES_SPARK
			_: pool = TEXTURES_RING
		mat.albedo_texture = load(pool[randi() % pool.size()])
	
	node.emitting = true
