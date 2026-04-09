@tool
extends Node

## 오디오 매니저 (AudioManager)
## 게임 내 모든 사운드(SFX, BGM)를 총괄 관리하는 싱글톤
## 3D 위치 기반 사운드 재생 및 풀링(Pooling) 지원

# 사운드 리소스 (플레이스홀더)
# 실제 파일이 없으므로, 나중에 리소스 경로만 바꾸면 작동하도록 설정
# preload는 컴파일 타임에 파일이 있어야 하므로, 안전을 위해 load() 사용
var sfx_streams = {
	"cannon_fire": [
		"res://assets/audio/sfx/sfx_cannon_fire.ogg",
		"res://assets/audio/sfx/sfx_cannon_fire_02.ogg"
	],
	"cannon_fuse": [
		"res://assets/audio/sfx/sfx_match_sizzle.ogg",
		"res://assets/audio/sfx/sfx_steam_hiss.ogg"
	],
	"impact_wood": "res://assets/audio/sfx/sfx_flag_crash.ogg", # 나무 부러지는/부딪히는 소리
	"ui_click": [
		"res://assets/audio/sfx/sfx_ui_click_1.ogg",
		"res://assets/audio/sfx/sfx_ui_click_2.ogg",
		"res://assets/audio/sfx/sfx_ui_click_3.ogg",
		"res://assets/audio/sfx/sfx_ui_click_4.ogg",
		"res://assets/audio/sfx/sfx_ui_click_5.ogg",
	],
	"level_up": "res://assets/audio/sfx/sfx_levelup.ogg",
	"rocket_launch": "res://assets/audio/sfx/sfx_explosion_impact.ogg",
	"rocket_launch_01": "res://assets/audio/sfx/sfx_rocket_launch_01.ogg",
	"rocket_launch_02": "res://assets/audio/sfx/sfx_rocket_launch_02.ogg",
	"rocket_launch_03": "res://assets/audio/sfx/sfx_rocket_launch_03.ogg",
	"heavy_missle_impact": "res://assets/audio/sfx/sfx_heavy_missle_impact.ogg",
	"wood_break": "res://assets/audio/sfx/sfx_flag_crash.ogg",
	"sail_flap": "res://assets/audio/sfx/sfx_flag_flapping.ogg",
	"sword_swing": [
		"res://assets/audio/sfx/sfx_sword_swing_1.ogg",
		"res://assets/audio/sfx/sfx_sword_swing_2.ogg",
		"res://assets/audio/sfx/sfx_sword_swing_3.ogg",
		"res://assets/audio/sfx/sfx_sword_swing_4.ogg"
	],
	"bow_shoot": [
		"res://assets/audio/sfx/sfx_bow_01.ogg",
		"res://assets/audio/sfx/sfx_bow_02.ogg"
	],
	"musket_fire": [
		"res://assets/audio/sfx/sfx_musket_fire.ogg",
		"res://assets/audio/sfx/sfx_musket_fire_02.ogg"
	],
	"soldier_hit": [
		"res://assets/audio/sfx/sfx_sword_ting_1.ogg",
		"res://assets/audio/sfx/sfx_sword_ting_2.ogg",
		"res://assets/audio/sfx/sfx_sword_ting_3.ogg",
		"res://assets/audio/sfx/sfx_sword_ting_4.ogg"
	],
	"wave_splash": [
		"res://assets/audio/sfx/sfx_wave_01.ogg",
		"res://assets/audio/sfx/sfx_wave_02.ogg",
		"res://assets/audio/sfx/sfx_wave_03.ogg"
	],
	"treasure_collect": [
		"res://assets/audio/sfx/sfx_pickup_1.ogg",
		"res://assets/audio/sfx/sfx_pickup_2.ogg",
		"res://assets/audio/sfx/sfx_pickup_3.ogg"
	],
	"soldier_die": [
		"res://assets/audio/sfx/sfx_soldier_die_1.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_2.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_3.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_4.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_5.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_6.ogg",
	],
	"water_splash_large": [
		"res://assets/audio/sfx/sfx_water_splash_large_1.ogg",
		"res://assets/audio/sfx/sfx_water_splash_large_2.ogg",
		"res://assets/audio/sfx/sfx_water_splash_large_3.ogg",
	],
	"water_splash_small": [
		"res://assets/audio/sfx/sfx_water_splash_small_1.ogg",
		"res://assets/audio/sfx/sfx_water_splash_small_2.ogg",
		"res://assets/audio/sfx/sfx_water_splash_small_3.ogg",
	],
	"cannon_reload": "res://assets/audio/sfx/sfx_metal_drop.mp3",
	"oars_rowing": "res://assets/audio/sfx/sfx_oars.ogg",
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

# 예열 완료 신호
signal prewarm_finished
var is_prewarm_finished: bool = false
@export var enable_playback_warmup: bool = false
@export var mute_sfx_until_prewarm_finished: bool = true
var _essential_warm_keys: Array[String] = [
	"cannon_fire",
	"impact_wood",
	"sword_swing",
	"musket_fire",
	"wave_splash",
	"water_splash_large"
]
var _web_essential_warm_keys: Array[String] = [
	"ui_click"
]
var _web_persistent_cache_keys: Array[String] = [
	"ui_click",
	"sword_swing",
	"soldier_hit",
	"bow_shoot",
	"treasure_collect",
	"water_splash_small"
]

func _ready() -> void:
	if Engine.is_editor_hint(): return
	
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
		p.bus = "UI" # UI 전용 버스 사용
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
	
	# 오디오 버스 진단 보고서 출력
	if OS.is_debug_build():
		_print_bus_status()
	
	# 엔진 기동 시 필수 오디오만 빠르게 예열 (시작 프레임 차단 방지)
	call_deferred("_preload_essential_audio")

## 필수 효과음 사전 캐싱 (오디오 끊김 방지용)
func _preload_essential_audio() -> void:
	var warm_keys = _get_warm_keys()
	for key in warm_keys:
		_cache_stream_for_key(key)
	
	# 기본값은 재생 없는 캐시-only 예열: 시작 시 어색한 소리 출력 방지
	if enable_playback_warmup:
		var warm_up_player = AudioStreamPlayer.new()
		warm_up_player.name = "AudioWarmupPlayer"
		warm_up_player.volume_linear = 0.0 # 완전 무음
		warm_up_player.bus = "SFX"
		add_child(warm_up_player)
		
		for key in warm_keys:
			if not _cached_streams.has(key):
				continue
			var s = _cached_streams[key]
			if s is Array:
				if s.size() > 0 and s[0] is AudioStream:
					warm_up_player.stream = s[0]
					warm_up_player.play()
					await get_tree().process_frame
			elif s is AudioStream:
				warm_up_player.stream = s
				warm_up_player.play()
				await get_tree().process_frame
		
		warm_up_player.queue_free()

	is_prewarm_finished = true
	prewarm_finished.emit()
	print("[Resource] 필수 오디오 예열 완료")
	
	# 웹 빌드는 모든 효과음을 미리 캐시하면 탭 메모리 사용량이 급격히 커진다.
	# 필수 사운드만 유지하고 나머지는 온디맨드 로드한다.
	if OS.has_feature("web"):
		return
	
	# 나머지 효과음은 백그라운드로 지연 캐싱
	call_deferred("_preload_secondary_audio")

func _preload_secondary_audio() -> void:
	var step := 0
	for key in sfx_streams.keys():
		if key in _get_warm_keys():
			continue
		_cache_stream_for_key(key)
		step += 1
		if step % 4 == 0:
			await get_tree().process_frame
	print("[Resource] 보조 오디오 캐싱 완료")

func _cache_stream_for_key(key: String) -> void:
	if _cached_streams.has(key):
		return
	if not sfx_streams.has(key):
		return
	if OS.has_feature("web") and not _should_persist_cache(key):
		return
		
	var path = sfx_streams[key]
	if path is Array:
		var loaded_arr = []
		for p in path:
			if p is String and ResourceLoader.exists(p):
				loaded_arr.append(_load_audio_resource(p, true))
		if loaded_arr.size() > 0:
			_cached_streams[key] = loaded_arr
	elif path is String and ResourceLoader.exists(path):
		_cached_streams[key] = _load_audio_resource(path, true)
	elif path is AudioStream:
		_cached_streams[key] = path

func _get_warm_keys() -> Array[String]:
	if OS.has_feature("web"):
		return _web_essential_warm_keys
	return _essential_warm_keys

func _should_persist_cache(key: String) -> bool:
	if not OS.has_feature("web"):
		return true
	return key in _web_persistent_cache_keys

func _load_audio_resource(path: String, persist_cache: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var cache_mode := ResourceLoader.CACHE_MODE_REUSE
	if OS.has_feature("web") and not persist_cache:
		cache_mode = ResourceLoader.CACHE_MODE_IGNORE
	return ResourceLoader.load(path, "", cache_mode) as AudioStream

func _load_stream_for_playback(stream_name: String):
	if _cached_streams.has(stream_name):
		var cached = _cached_streams[stream_name]
		if cached is Array:
			if cached.size() > 0:
				return cached.pick_random()
			return null
		return cached
	
	if not sfx_streams.has(stream_name):
		return null
	
	var path = sfx_streams[stream_name]
	if path is Array:
		var loaded_arr = []
		for p in path:
			if p is String and ResourceLoader.exists(p):
				loaded_arr.append(_load_audio_resource(p, _should_persist_cache(stream_name)))
		if loaded_arr.is_empty():
			return null
		if _should_persist_cache(stream_name):
			_cached_streams[stream_name] = loaded_arr
		return loaded_arr.pick_random()
	
	if path is String and ResourceLoader.exists(path):
		var loaded_stream = _load_audio_resource(path, _should_persist_cache(stream_name))
		if _should_persist_cache(stream_name):
			_cached_streams[stream_name] = loaded_stream
		return loaded_stream
	
	if path is AudioStream:
		if _should_persist_cache(stream_name):
			_cached_streams[stream_name] = path
		return path
	
	return null


## 오디오 버스 상태 진단 로직
func _print_bus_status() -> void:
	print("--- Audio Bus Diagnostic Report ---")
	var bus_count = AudioServer.bus_count
	for i in range(bus_count):
		var b_name = AudioServer.get_bus_name(i)
		var b_volume = AudioServer.get_bus_volume_db(i)
		var b_mute = AudioServer.is_bus_mute(i)
		var b_solo = AudioServer.is_bus_solo(i)
		var b_send = AudioServer.get_bus_send(i)
		
		var status_str = "[%d] %s: Volume: %.1fdB, Mute: %s, Solo: %s, Send: %s" % [
			i, b_name, b_volume, str(b_mute), str(b_solo), b_send
		]
		print(status_str)
	print("---------------------------------------")


## 효과음 재생 (3D 위치)
## position이 null이면 2D로 재생
func play_sfx(stream_name: String, position = null, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	# 1. 리소스 확인 및 동적 로드
	var stream = _load_stream_for_playback(stream_name)
	if not is_prewarm_finished and mute_sfx_until_prewarm_finished:
		# 시작 예열 중에는 실제 재생만 막고 캐시는 유지한다.
		return
	
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
		player.volume_db = volume_db
		player.play()
		
		# 인덱스 순환
		current_sfx_index = (current_sfx_index + 1) % sfx_pool.size()
	else:
		# 2D 재생 (UI 등)
		var player = sfx_2d_pool[current_2d_index]
		player.stream = stream
		player.pitch_scale = pitch_scale
		player.volume_db = volume_db
		player.play()
		
		current_2d_index = (current_2d_index + 1) % sfx_2d_pool.size()

## 배경음 재생
func play_bgm(stream_name: String, _fade_duration: float = 1.0) -> void:
	if current_bgm_name == stream_name: return
	current_bgm_name = stream_name
	
	# TODO: BGM 리소스가 있으면 여기서 재생 및 페이드인/아웃 구현
	print("[Audio] Play BGM: %s" % stream_name)
## === 길군악(노동요) 전용 재생 시스템 ===
var _gilgunak_player: AudioStreamPlayer = null

func _setup_gilgunak() -> void:
	_gilgunak_player = AudioStreamPlayer.new()
	_gilgunak_player.name = "GilgunakPlayer"
	_gilgunak_player.bus = "Master" # 버스 안전을 위해 Master로 설정
	_gilgunak_player.volume_db = 6.0
	
	var stream = load("res://assets/audio/sfx/sfx_gilgunak.ogg") as AudioStream
	if stream:
		_gilgunak_player.stream = stream
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		print("[AudioManager] 44.1kHz 길군악 플레이어 준비 완료")
	else:
		print("!! [AudioManager] 길군악 파일 로드 실패")
	
	add_child(_gilgunak_player)


## 길군악 재생/정지 토글
func play_gilgunak(active: bool) -> void:
	if not _gilgunak_player:
		_setup_gilgunak()
	
	if active:
		if not _gilgunak_player.playing:
			_gilgunak_player.play()
		_gilgunak_player.stream_paused = false
	else:
		if _gilgunak_player.playing:
			_gilgunak_player.stream_paused = true
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
