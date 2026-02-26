extends Node

## 오디오 매니저 (AudioManager)
## 게임 내 모든 사운드(SFX, BGM)를 총괄 관리하는 싱글톤
## 3D 위치 기반 사운드 재생 및 풀링(Pooling) 지원

# 사운드 리소스 (플레이스홀더)
# 실제 파일이 없으므로, 나중에 리소스 경로만 바꾸면 작동하도록 설정
# preload는 컴파일 타임에 파일이 있어야 하므로, 안전을 위해 load() 사용
var sfx_streams = {
	"cannon_fire": [
		"res://assets/audio/sfx/sfx_cannon_fire.wav",
		"res://assets/audio/sfx/sfx_cannon_fire_02.wav"
	],
	"cannon_fuse": [
		"res://assets/audio/sfx/sfx_match_sizzle.wav",
		"res://assets/audio/sfx/sfx_steam_hiss.wav"
	],
	"impact_wood": "res://assets/audio/sfx/sfx_flag_crash.wav", # 나무 부러지는/부딪히는 소리
	"ui_click": [
		"res://assets/audio/sfx/sfx_ui_click_1.wav",
		"res://assets/audio/sfx/sfx_ui_click_2.wav",
		"res://assets/audio/sfx/sfx_ui_click_3.wav",
		"res://assets/audio/sfx/sfx_ui_click_4.wav",
		"res://assets/audio/sfx/sfx_ui_click_5.wav",
	],
	"level_up": "res://assets/audio/sfx/sfx_levelup.wav",
	"rocket_launch": "res://assets/audio/sfx/sfx_explosion_impact.wav", # 로켓/폭발음
	"wood_break": "res://assets/audio/sfx/sfx_flag_crash.wav",
	"sail_flap": "res://assets/audio/sfx/sfx_flag_flapping.wav",
	"sword_swing": [
		"res://assets/audio/sfx/sfx_sword_swing_1.wav",
		"res://assets/audio/sfx/sfx_sword_swing_2.wav",
		"res://assets/audio/sfx/sfx_sword_swing_3.wav",
		"res://assets/audio/sfx/sfx_sword_swing_4.wav"
	],
	"bow_shoot": [
		"res://assets/audio/sfx/sfx_bow_01.wav",
		"res://assets/audio/sfx/sfx_bow_02.wav"
	],
	"musket_fire": [
		"res://assets/audio/sfx/sfx_musket_fire.wav",
		"res://assets/audio/sfx/sfx_musket_fire_02.wav"
	],
	"soldier_hit": [
		"res://assets/audio/sfx/sfx_sword_ting_1.wav",
		"res://assets/audio/sfx/sfx_sword_ting_2.wav",
		"res://assets/audio/sfx/sfx_sword_ting_3.wav",
		"res://assets/audio/sfx/sfx_sword_ting_4.wav"
	],
	"wave_splash": [
		"res://assets/audio/sfx/sfx_wave_01.wav",
		"res://assets/audio/sfx/sfx_wave_02.wav",
		"res://assets/audio/sfx/sfx_wave_03.wav"
	],
	"treasure_collect": [
		"res://assets/audio/sfx/sfx_pickup_1.wav",
		"res://assets/audio/sfx/sfx_pickup_2.wav",
		"res://assets/audio/sfx/sfx_pickup_3.wav"
	],
	"soldier_die": [
		"res://assets/audio/sfx/sfx_soldier_die_1.wav",
		"res://assets/audio/sfx/sfx_soldier_die_2.wav",
		"res://assets/audio/sfx/sfx_soldier_die_3.wav",
		"res://assets/audio/sfx/sfx_soldier_die_4.wav",
		"res://assets/audio/sfx/sfx_soldier_die_5.wav",
		"res://assets/audio/sfx/sfx_soldier_die_6.wav",
	],
	"water_splash_large": [
		"res://assets/audio/sfx/sfx_water_splash_large_1.wav",
		"res://assets/audio/sfx/sfx_water_splash_large_2.wav",
		"res://assets/audio/sfx/sfx_water_splash_large_3.wav",
	],
	"water_splash_small": [
		"res://assets/audio/sfx/sfx_water_splash_small_1.wav",
		"res://assets/audio/sfx/sfx_water_splash_small_2.wav",
		"res://assets/audio/sfx/sfx_water_splash_small_3.wav",
	],
	"cannon_reload": "res://assets/audio/sfx/sfx_metal_drop.mp3",
	"oars_rowing": "res://assets/audio/sfx/sfx_oars.wav",
	"gilgunak": "res://assets/audio/sfx/sfx_gilgunak.wav",
}

# 캐시된 스트림
var _cached_streams = {}

# 플레이스홀더 사운드 생성기 (리소스 없을 때 사용)
var placeholder_stream: AudioStreamGenerator
var placeholder_playback: AudioStreamGeneratorPlayback
var _use_placeholder: bool = false

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
		var cached = _cached_streams[stream_name]
		if cached is Array:
			if cached.size() > 0: stream = cached.pick_random()
		else:
			stream = cached
	elif sfx_streams.has(stream_name):
		var path = sfx_streams[stream_name]
		if path is Array:
			var loaded_arr = []
			for p in path:
				if p is String and ResourceLoader.exists(p):
					loaded_arr.append(load(p))
			if loaded_arr.size() > 0:
				_cached_streams[stream_name] = loaded_arr
				stream = loaded_arr.pick_random()
		elif path is String and ResourceLoader.exists(path):
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
func play_bgm(stream_name: String, _fade_duration: float = 1.0) -> void:
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


## === 길군악(노동요) 전용 재생 시스템 ===
var _gilgunak_player: AudioStreamPlayer = null

func _setup_gilgunak() -> void:
	_gilgunak_player = AudioStreamPlayer.new()
	_gilgunak_player.name = "GilgunakPlayer"
	_gilgunak_player.bus = "Master" # 버스 문제를 배제하기 위해 Master로 고정
	_gilgunak_player.volume_db = 10.0 # 확실히 들리게 상향
	
	var stream = load("res://assets/audio/sfx/sfx_gilgunak.wav") as AudioStream
	if stream:
		_gilgunak_player.stream = stream
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		print("✅ [AudioManager] 길군악 플레이어 준비 완료 (Bus: Master, Vol: 10dB)")
	else:
		print("⚠️ [AudioManager] 길군악 파일 로드 실패 (경로 확인 필요)")
	
	add_child(_gilgunak_player)


## 길군악 재생/정지 토글
func play_gilgunak(active: bool) -> void:
	if not _gilgunak_player:
		_setup_gilgunak()
	
	# 버스 음소거 체크 (디버그용)
	var bus_idx = AudioServer.get_bus_index(_gilgunak_player.bus)
	if AudioServer.is_bus_mute(bus_idx):
		print("⚠️ [AudioManager] 주의: %s 버스가 현재 음소거 상태입니다!" % _gilgunak_player.bus)

	if active:
		if not _gilgunak_player.playing:
			_gilgunak_player.play()
			print("🎶 [AudioManager] 길군악 재생 시작")
		_gilgunak_player.stream_paused = false
	else:
		if _gilgunak_player.playing:
			_gilgunak_player.stream_paused = true
			print("⏸️ [AudioManager] 길군악 일시정지")
