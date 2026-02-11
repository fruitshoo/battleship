extends Node

## 오디오 매니저 (AudioManager)
## 게임 내 모든 사운드(SFX, BGM)를 총괄 관리하는 싱글톤
## 3D 위치 기반 사운드 재생 및 풀링(Pooling) 지원

# 사운드 리소스 (플레이스홀더)
# 실제 파일이 없으므로, 나중에 리소스 경로만 바꾸면 작동하도록 설정
# preload는 컴파일 타임에 파일이 있어야 하므로, 안전을 위해 load() 사용
var sfx_streams = {
	"cannon_fire": "res://resources/audio/sfx_cannon_fire.tres",
	"impact_wood": "res://resources/audio/sfx_impact_wood.tres",
	"ui_click": "res://resources/audio/sfx_ui_click.tres",
	"level_up": "res://resources/audio/sfx_level_up.tres",
	"rocket_launch": "res://resources/audio/sfx_rocket_launch.tres",
	"wood_break": null,
	"sword_swing": null,
	"bow_shoot": null,
	"soldier_hit": null,
	"soldier_die": null,
}

# 캐시된 스트림
var _cached_streams = {}

# 플레이스홀더 사운드 생성기 (리소스 없을 때 사용)
var placeholder_stream: AudioStreamGenerator
var placeholder_playback: AudioStreamGeneratorPlayback
var _use_placeholder: bool = true

# 풀링 설정
var sfx_pool_size: int = 16
var sfx_pool: Array[AudioStreamPlayer3D] = []
var sfx_2d_pool: Array[AudioStreamPlayer] = []
var current_sfx_index: int = 0
var current_2d_index: int = 0

# BGM 플레이어
var bgm_player: AudioStreamPlayer
var current_bgm_name: String = ""

func _ready() -> void:
	# 1. 3D SFX 풀 생성
	for i in range(sfx_pool_size):
		var p = AudioStreamPlayer3D.new()
		p.name = "SFX_Player_3D_%d" % i
		p.max_distance = 100.0
		p.unit_size = 10.0
		p.bus = "SFX"
		add_child(p)
		sfx_pool.append(p)
		
	# 2. 2D SFX 풀 생성 (UI용)
	for i in range(8):
		var p = AudioStreamPlayer.new()
		p.name = "SFX_Player_2D_%d" % i
		p.bus = "SFX"
		add_child(p)
		sfx_2d_pool.append(p)
		
	# 3. BGM 플레이어 생성
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM_Player"
	bgm_player.bus = "Music"
	add_child(bgm_player)
	
	# 4. 플레이스홀더 제너레이터 초기화
	var generator_player = AudioStreamPlayer.new()
	generator_player.name = "PlaceholderGenerator"
	generator_player.bus = "SFX"
	add_child(generator_player)
	
	placeholder_stream = AudioStreamGenerator.new()
	placeholder_stream.mix_rate = 44100
	placeholder_stream.buffer_length = 0.1
	generator_player.stream = placeholder_stream
	generator_player.play()
	
	placeholder_playback = generator_player.get_stream_playback()
	
	process_mode = Node.PROCESS_MODE_ALWAYS # 일시정지 중에도 UI 소리는 나야 함


## 효과음 재생 (3D 위치)
## position이 null이면 2D로 재생
func play_sfx(stream_name: String, position = null, pitch_scale: float = 1.0) -> void:
	# 1. 리소스 확인 및 동적 로드
	var stream = null
	
	if _cached_streams.has(stream_name):
		stream = _cached_streams[stream_name]
	elif sfx_streams.has(stream_name):
		var path = sfx_streams[stream_name]
		if path is String and ResourceLoader.exists(path):
			stream = load(path)
			_cached_streams[stream_name] = stream
		elif path is AudioStream: # 이미 리소스인 경우 (코드에서 직접 넣었을 때)
			stream = path
			_cached_streams[stream_name] = stream
	
	# 2. 리소스가 없으면 디버그용 비프음 재생 (선택사항)
	if not stream:
		if _use_placeholder and placeholder_playback:
			_play_placeholder_beep()
		return

	if position != null:
		# 3D 재생 (3D Player Pool 사용)
		var player = sfx_pool[current_sfx_index]
		player.stream = stream
		player.global_position = position
		player.pitch_scale = pitch_scale + randf_range(-0.1, 0.1) # 약간의 피치 변동으로 자연스럽게
		player.play()
		
		# 인덱스 순환
		current_sfx_index = (current_sfx_index + 1) % sfx_pool.size()
	else:
		# 2D 재생 (UI 등)
		var player = sfx_2d_pool[current_2d_index]
		player.stream = stream
		player.pitch_scale = pitch_scale
		player.play()
		
		current_2d_index = (current_2d_index + 1) % sfx_2d_pool.size()

## 배경음 재생
func play_bgm(stream_name: String, fade_duration: float = 1.0) -> void:
	if current_bgm_name == stream_name: return
	current_bgm_name = stream_name
	
	# TODO: BGM 리소스가 있으면 여기서 재생 및 페이드인/아웃 구현
	print("🎵 [Audio] Play BGM: %s" % stream_name)


func _play_placeholder_beep() -> void:
	if not placeholder_playback: return
	
	# 간단한 사각파 생성
	var phase = 0.0
	var increment = 440.0 / 44100.0
	var frames = placeholder_playback.get_frames_available()
	
	if frames > 0:
		var buffer = PackedVector2Array()
		buffer.resize(frames)
		
		for i in range(frames):
			var val = 1.0 if fmod(phase, 1.0) > 0.5 else -1.0
			val *= 0.1 # 볼륨 조절
			buffer[i] = Vector2(val, val)
			phase += increment
			
		placeholder_playback.push_buffer(buffer)
