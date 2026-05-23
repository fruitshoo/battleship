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
		{
			"path": "res://assets/audio/sfx/sfx_cannon_fire_blast_03.ogg",
			"volume_db": -2.5,
		},
	],
	"cannon_fuse": [
		"res://assets/audio/sfx/sfx_match_sizzle.ogg"
	],
	"cannon_hit": [
		"res://assets/audio/sfx/sfx_cannon_hit_01.ogg",
		"res://assets/audio/sfx/sfx_cannon_hit_02.ogg",
		"res://assets/audio/sfx/sfx_cannon_hit_03.ogg",
		{
			"path": "res://assets/audio/sfx/sfx_explosion_impact.ogg",
			"volume_db": 14.0,
		},
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
	"rocket_launch": [
		"res://assets/audio/sfx/sfx_rocket_launch_01.ogg",
		"res://assets/audio/sfx/sfx_rocket_launch_02.ogg",
		"res://assets/audio/sfx/sfx_rocket_launch_03.ogg",
	],
	"rocket_launch_01": "res://assets/audio/sfx/sfx_rocket_launch_01.ogg",
	"rocket_launch_02": "res://assets/audio/sfx/sfx_rocket_launch_02.ogg",
	"rocket_launch_03": "res://assets/audio/sfx/sfx_rocket_launch_03.ogg",
	"singigeon_launch": [
		"res://assets/audio/sfx/sfx_rocket_launch_whoosh_01.ogg",
		"res://assets/audio/sfx/sfx_rocket_launch_whoosh_02.ogg",
		"res://assets/audio/sfx/sfx_rocket_launch_whoosh_03.ogg",
	],
	"heavy_missle_impact": "res://assets/audio/sfx/sfx_heavy_missle_impact.ogg",
	"wood_break": "res://assets/audio/sfx/sfx_flag_crash.ogg",
	"sail_flap": [
		"res://assets/audio/sfx/sfx_sail_canvas_01.ogg",
		"res://assets/audio/sfx/sfx_sail_canvas_02.ogg",
		"res://assets/audio/sfx/sfx_sail_canvas_03.ogg",
		"res://assets/audio/sfx/sfx_sail_canvas_04.ogg",
		"res://assets/audio/sfx/sfx_sail_canvas_05.ogg",
		"res://assets/audio/sfx/sfx_sail_canvas_06.ogg",
		"res://assets/audio/sfx/sfx_sail_canvas_07.ogg",
		"res://assets/audio/sfx/sfx_sail_canvas_08.ogg",
	],
	"sail_catch": "res://assets/audio/sfx/sfx_flag_flapping.ogg",
	"mast_creak": [
		"res://assets/audio/sfx/sfx_mast_creak_01.ogg",
		"res://assets/audio/sfx/sfx_mast_creak_02.ogg",
		"res://assets/audio/sfx/sfx_mast_creak_03.ogg",
		"res://assets/audio/sfx/sfx_mast_creak_04.ogg",
	],
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
		{
			"path": "res://assets/audio/sfx/sfx_musket_fire_02.ogg",
			"volume_db": -4.0,
		}
	],
	"soldier_hit": [
		"res://assets/audio/sfx/sfx_sword_ting_1.ogg",
		"res://assets/audio/sfx/sfx_sword_ting_2.ogg",
		"res://assets/audio/sfx/sfx_sword_ting_3.ogg",
		"res://assets/audio/sfx/sfx_sword_ting_4.ogg"
	],
	"critical_flesh_hit": [
		"res://assets/audio/sfx/sfx_crit_flesh_slashkut.ogg",
		"res://assets/audio/sfx/sfx_crit_flesh_slice.ogg",
		"res://assets/audio/sfx/sfx_crit_flesh_crush.ogg",
		"res://assets/audio/sfx/sfx_crit_flesh_headshot.ogg",
		"res://assets/audio/sfx/sfx_crit_flesh_soft_impact.ogg",
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
		"res://assets/audio/sfx/sfx_soldier_die_7.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_8.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_9.ogg",
		"res://assets/audio/sfx/sfx_soldier_die_10.ogg",
	],
	"ballistic_death": [
		"res://assets/audio/sfx/sfx_ballistic_death_01.ogg",
		"res://assets/audio/sfx/sfx_ballistic_death_02.ogg",
	],
	"boarding_war_cry": [
		"res://assets/audio/sfx/sfx_boarding_war_cry_1.ogg",
		"res://assets/audio/sfx/sfx_boarding_war_cry_2.ogg",
		"res://assets/audio/sfx/sfx_boarding_war_cry_3.ogg",
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
	"ship_sink_bubbles": "res://assets/audio/sfx/sfx_ship_sink_bubbles_cc0.ogg",
	"ship_collision": "res://assets/audio/sfx/sfx_ship_collision_smash.ogg",
	"cannon_reload": "res://assets/audio/sfx/sfx_metal_drop.ogg",
	"oars_rowing": "res://assets/audio/sfx/sfx_oars.ogg",
	"boss_horn": "res://assets/audio/sfx/sfx_boss_medieval_horn_cc0.ogg",
	"support_foghorn": "res://assets/audio/sfx/sfx_support_foghorn_cc0.ogg",
}

var bgm_streams = {
	"main_menu": "res://assets/audio/music/bgm_main_menu_battle_tactics.ogg",
	"gameplay": "res://assets/audio/music/bgm_gameplay_tea_tyme.ogg",
	"boss_taiko": [
		"res://assets/audio/music/bgm_boss_taiko_drumloop_120_cc0.ogg",
		"res://assets/audio/music/bgm_boss_tribe_drum_loop_cc0.ogg",
		"res://assets/audio/music/bgm_boss_taiko_loop_cc0.ogg",
	],
}

const DEFAULT_3D_SFX_VOLUME_DB := -1.5
const DEFAULT_3D_SFX_MAX_DISTANCE := 220.0
const DEFAULT_3D_SFX_UNIT_SIZE := 55.0
const GILGUNAK_VOLUME_DB := -4.0
const MAIN_MENU_BGM := "main_menu"
const GAMEPLAY_BGM := "gameplay"
const BOSS_TAIKO_BGM := "boss_taiko"
const MAIN_MENU_BGM_VOLUME_DB := -8.0
const GAMEPLAY_BGM_VOLUME_DB := -10.0
const BOSS_TAIKO_VOLUME_DB := 1.5
const SFX_ALIASES := {
	"arrow_shoot": "bow_shoot",
	"critical_hit": "soldier_hit",
	"trumpet_war": "support_foghorn",
	"upgrade_select": "level_up",
}
const SFX_PROFILE_DEFAULT_3D := "default_3d"
const SFX_PROFILE_WEAPON_CLOSE := "weapon_close"
const SFX_PROFILE_LIGHT_PROJECTILE := "light_projectile"
const SFX_PROFILE_CANNON_BLAST := "cannon_blast"
const SFX_PROFILE_SHIP_AMBIENT := "ship_ambient"
const SFX_PROFILE_CHARACTER_VOICE := "character_voice"
const SFX_PROFILE_BOARDING_VOICE := "boarding_voice"
const SFX_PROFILE_BATTLE_ALERT := "battle_alert"
# 새 효과음은 보통 SFX_PROFILE_BY_KEY에 용도만 고르고, 값 튜닝이 꼭 필요할 때만 SFX_PROFILE_OVERRIDES를 쓴다.
const SFX_PROFILE_PRESETS := {
	SFX_PROFILE_DEFAULT_3D: {},
	SFX_PROFILE_WEAPON_CLOSE: {
		"volume_db": -3.0,
		"max_distance": 220.0,
		"unit_size": 60.0,
	},
	SFX_PROFILE_LIGHT_PROJECTILE: {
		"volume_db": -7.0,
		"max_distance": 150.0,
		"unit_size": 38.0,
		"pitch_jitter": 0.035,
		"rate_limit_msec": 55,
	},
	SFX_PROFILE_CANNON_BLAST: {
		"volume_db": -1.0,
		"max_distance": 340.0,
		"unit_size": 95.0,
		"pitch_jitter": 0.08,
	},
	SFX_PROFILE_SHIP_AMBIENT: {
		"volume_db": -1.0,
		"max_distance": 260.0,
		"unit_size": 75.0,
	},
	SFX_PROFILE_CHARACTER_VOICE: {
		"volume_db": -1.5,
		"max_distance": 250.0,
		"unit_size": 80.0,
		"pitch_jitter": 0.025,
	},
	SFX_PROFILE_BOARDING_VOICE: {
		"volume_db": -0.5,
		"max_distance": 320.0,
		"unit_size": 110.0,
		"pitch_jitter": 0.025,
	},
	SFX_PROFILE_BATTLE_ALERT: {
		"volume_db": 1.5,
		"non_spatial": true,
	},
}
const SFX_PROFILE_BY_KEY := {
	"cannon_fire": SFX_PROFILE_CANNON_BLAST,
	"cannon_hit": SFX_PROFILE_CANNON_BLAST,
	"wave_splash": SFX_PROFILE_SHIP_AMBIENT,
	"sail_flap": SFX_PROFILE_SHIP_AMBIENT,
	"sail_catch": SFX_PROFILE_SHIP_AMBIENT,
	"mast_creak": SFX_PROFILE_SHIP_AMBIENT,
	"oars_rowing": SFX_PROFILE_SHIP_AMBIENT,
	"ship_sink_bubbles": SFX_PROFILE_SHIP_AMBIENT,
	"ship_collision": SFX_PROFILE_SHIP_AMBIENT,
	"bow_shoot": SFX_PROFILE_LIGHT_PROJECTILE,
	"musket_fire": SFX_PROFILE_LIGHT_PROJECTILE,
	"sword_swing": SFX_PROFILE_WEAPON_CLOSE,
	"soldier_hit": SFX_PROFILE_WEAPON_CLOSE,
	"critical_flesh_hit": SFX_PROFILE_WEAPON_CLOSE,
	"soldier_die": SFX_PROFILE_CHARACTER_VOICE,
	"ballistic_death": SFX_PROFILE_CHARACTER_VOICE,
	"boarding_war_cry": SFX_PROFILE_BOARDING_VOICE,
	"boss_horn": SFX_PROFILE_BATTLE_ALERT,
	"support_foghorn": SFX_PROFILE_BATTLE_ALERT,
}
const SFX_PROFILE_OVERRIDES := {
	"oars_rowing": {
		"max_distance": 240.0,
		"unit_size": 70.0,
	},
	"sail_flap": {
		"volume_db": -0.5,
		"max_distance": 280.0,
		"unit_size": 95.0,
		"pitch_jitter": 0.035,
		"rate_limit_msec": 220,
	},
	"sail_catch": {
		"volume_db": -2.0,
		"max_distance": 260.0,
		"unit_size": 90.0,
		"pitch_jitter": 0.025,
		"rate_limit_msec": 900,
	},
	"mast_creak": {
		"volume_db": -2.0,
		"max_distance": 260.0,
		"unit_size": 90.0,
		"pitch_jitter": 0.04,
		"rate_limit_msec": 900,
	},
	"sword_swing": {
		"volume_db": 0.5,
	},
	"soldier_hit": {
		"volume_db": -2.0,
		"max_distance": 230.0,
		"unit_size": 65.0,
	},
	"critical_flesh_hit": {
		"volume_db": -7.0,
		"max_distance": 190.0,
		"unit_size": 54.0,
		"pitch_jitter": 0.065,
		"rate_limit_msec": 90,
	},
	"cannon_fire": {
		"volume_db": -1.0,
		"max_distance": 360.0,
		"unit_size": 110.0,
		"pitch_jitter": 0.04,
	},
	"cannon_hit": {
		"volume_db": -2.5,
		"max_distance": 320.0,
		"unit_size": 95.0,
		"pitch_jitter": 0.055,
		"rate_limit_msec": 45,
	},
	"cannon_fuse": {
		"volume_db": -12.0,
		"max_distance": 80.0,
		"unit_size": 28.0,
		"pitch_jitter": 0.02,
		"rate_limit_msec": 120,
	},
	"musket_fire": {
		"volume_db": -6.0,
		"max_distance": 190.0,
		"unit_size": 52.0,
		"pitch_jitter": 0.025,
		"rate_limit_msec": 110,
	},
	"ship_sink_bubbles": {
		"volume_db": 1.0,
		"max_distance": 320.0,
		"unit_size": 130.0,
		"pitch_jitter": 0.04,
		"rate_limit_msec": 300,
	},
	"ship_collision": {
		"volume_db": -1.0,
		"max_distance": 290.0,
		"unit_size": 110.0,
		"pitch_jitter": 0.035,
		"rate_limit_msec": 180,
	},
	"ballistic_death": {
		"pitch_jitter": 0.08,
	},
	"support_foghorn": {
		"volume_db": 2.0,
	},
}

# 캐시된 스트림
var _cached_streams = {}
var _cached_bgm_streams = {}

# 플레이스홀더 사운드 생성기 (리소스 없을 때 사용)
var placeholder_stream: AudioStreamGenerator
var placeholder_playback: AudioStreamGeneratorPlayback
var _use_placeholder: bool = false

# 풀링 설정
var sfx_pool_size: int = 16
var sfx_pool: Array[AudioStreamPlayer3D] = []
var sfx_2d_pool: Array[AudioStreamPlayer] = []
var sfx_non_spatial_pool: Array[AudioStreamPlayer] = []
var current_sfx_index: int = 0
var current_2d_index: int = 0
var current_non_spatial_index: int = 0
var _last_sfx_play_msec_by_key: Dictionary = {}

# BGM 플레이어
var bgm_player: AudioStreamPlayer
var current_bgm_name: String = ""
var _active_boss_bgm_path: String = ""
var _gameplay_bgm_active: bool = false
var _boss_bgm_active: bool = false

# 예열 완료 신호
signal prewarm_finished
var is_prewarm_finished: bool = false
@export var enable_playback_warmup: bool = true
@export var mute_sfx_until_prewarm_finished: bool = true
var _startup_sfx_muted: bool = false
var _essential_warm_keys: Array[String] = [
	"cannon_fire",
	"cannon_hit",
	"cannon_fuse",
	"cannon_reload",
	"impact_wood",
	"sword_swing",
	"soldier_hit",
	"critical_flesh_hit",
	"bow_shoot",
	"musket_fire",
	"singigeon_launch",
	"level_up",
	"sail_flap",
	"sail_catch",
	"mast_creak",
	"wave_splash",
	"water_splash_large",
	"water_splash_small",
	"ship_sink_bubbles",
	"ship_collision",
	"boss_horn"
]
var _essential_bgm_warm_keys: Array[String] = [
	GAMEPLAY_BGM,
	BOSS_TAIKO_BGM
]
var _web_essential_warm_keys: Array[String] = [
	"ui_click"
]
var _web_persistent_cache_keys: Array[String] = [
	"ui_click",
	"level_up",
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
		p.max_distance = DEFAULT_3D_SFX_MAX_DISTANCE
		p.unit_size = DEFAULT_3D_SFX_UNIT_SIZE
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

	# 2.5. 위치보다 가독성이 중요한 전투 알림음 전용 풀
	for i in range(4):
		var p = AudioStreamPlayer.new()
		p.name = "SFX_Player_NonSpatial_%d" % i
		p.bus = "SFX"
		add_child(p)
		sfx_non_spatial_pool.append(p)
		
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
	for bgm_key in _essential_bgm_warm_keys:
		_load_bgm_stream(bgm_key)
	
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
			await _warm_playback_for_streams(warm_up_player, _cached_streams[key])
		
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


func _warm_playback_for_streams(warm_up_player: AudioStreamPlayer, streams) -> void:
	if streams is Array:
		for entry in streams:
			var stream := _get_sfx_entry_stream(entry)
			if stream is AudioStream:
				warm_up_player.stream = stream
				warm_up_player.play()
				await get_tree().process_frame
	elif streams is AudioStream:
		warm_up_player.stream = streams
		warm_up_player.play()
		await get_tree().process_frame

func set_startup_sfx_muted(muted: bool) -> void:
	_startup_sfx_muted = muted

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
	var resolved_key := _resolve_sfx_key(key)
	if _cached_streams.has(resolved_key):
		return
	if not sfx_streams.has(resolved_key):
		return
	if OS.has_feature("web") and not _should_persist_cache(resolved_key):
		return
		
	var path = sfx_streams[resolved_key]
	if path is Array:
		var loaded_arr = []
		for p in path:
			var loaded_entry = _load_sfx_entry(p, true)
			if loaded_entry != null:
				loaded_arr.append(loaded_entry)
		if loaded_arr.size() > 0:
			_cached_streams[resolved_key] = loaded_arr
	elif path is String and ResourceLoader.exists(path):
		_cached_streams[resolved_key] = _load_audio_resource(path, true)
	elif path is AudioStream:
		_cached_streams[resolved_key] = path

func _get_warm_keys() -> Array[String]:
	if OS.has_feature("web"):
		return _web_essential_warm_keys
	return _essential_warm_keys

func _should_persist_cache(key: String) -> bool:
	if not OS.has_feature("web"):
		return true
	return _resolve_sfx_key(key) in _web_persistent_cache_keys

func _load_audio_resource(path: String, persist_cache: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var cache_mode := ResourceLoader.CACHE_MODE_REUSE
	if OS.has_feature("web") and not persist_cache:
		cache_mode = ResourceLoader.CACHE_MODE_IGNORE
	return ResourceLoader.load(path, "", cache_mode) as AudioStream

func _load_stream_for_playback(stream_name: String):
	var resolved_name := _resolve_sfx_key(stream_name)
	if _cached_streams.has(resolved_name):
		var cached = _cached_streams[resolved_name]
		if cached is Array:
			if cached.size() > 0:
				return cached.pick_random()
			return null
		return cached
	
	if not sfx_streams.has(resolved_name):
		return null
	
	var path = sfx_streams[resolved_name]
	if path is Array:
		var loaded_arr = []
		for p in path:
			var loaded_entry = _load_sfx_entry(p, _should_persist_cache(resolved_name))
			if loaded_entry != null:
				loaded_arr.append(loaded_entry)
		if loaded_arr.is_empty():
			return null
		if _should_persist_cache(resolved_name):
			_cached_streams[resolved_name] = loaded_arr
		return loaded_arr.pick_random()
	
	if path is String and ResourceLoader.exists(path):
		var loaded_stream = _load_audio_resource(path, _should_persist_cache(resolved_name))
		if _should_persist_cache(resolved_name):
			_cached_streams[resolved_name] = loaded_stream
		return loaded_stream
	
	if path is AudioStream:
		if _should_persist_cache(resolved_name):
			_cached_streams[resolved_name] = path
		return path
	
	return null

func _load_sfx_entry(entry, persist_cache: bool):
	if entry is String:
		if ResourceLoader.exists(entry):
			return _load_audio_resource(entry, persist_cache)
		return null
	if entry is Dictionary:
		var path := str(entry.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			return null
		var stream := _load_audio_resource(path, persist_cache)
		if not stream:
			return null
		return {
			"stream": stream,
			"volume_db": float(entry.get("volume_db", 0.0)),
		}
	if entry is AudioStream:
		return entry
	return null

func _get_sfx_entry_stream(entry) -> AudioStream:
	if entry is AudioStream:
		return entry
	if entry is Dictionary:
		return entry.get("stream") as AudioStream
	return null

func _get_sfx_entry_volume_db(entry) -> float:
	if entry is Dictionary:
		return float(entry.get("volume_db", 0.0))
	return 0.0

func _load_bgm_stream(stream_name: String) -> AudioStream:
	if not bgm_streams.has(stream_name):
		return null
	var path := _resolve_bgm_path(stream_name)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _cached_bgm_streams.has(path):
		return _cached_bgm_streams[path]
	var stream := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as AudioStream
	if stream:
		_set_stream_loop(stream, true)
		_cached_bgm_streams[path] = stream
	return stream

func _resolve_bgm_path(stream_name: String) -> String:
	var entry = bgm_streams.get(stream_name, "")
	if entry is String:
		return str(entry)
	if entry is Array:
		if stream_name == BOSS_TAIKO_BGM:
			if _active_boss_bgm_path.is_empty() or not ResourceLoader.exists(_active_boss_bgm_path):
				_active_boss_bgm_path = _pick_bgm_variant_path(entry)
			return _active_boss_bgm_path
		return _pick_bgm_variant_path(entry)
	return ""

func _pick_bgm_variant_path(variants: Array) -> String:
	var valid_paths: Array[String] = []
	for variant in variants:
		var path := str(variant)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		valid_paths.append(path)
	if valid_paths.is_empty():
		return ""
	return valid_paths.pick_random()

func _set_stream_loop(stream: AudioStream, enabled: bool) -> void:
	if not stream:
		return
	for property_info in stream.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		if property_name == "loop":
			stream.set("loop", enabled)
			return
		if property_name == "loop_mode":
			stream.set("loop_mode", AudioStreamWAV.LOOP_FORWARD if enabled else AudioStreamWAV.LOOP_DISABLED)
			return

func _resolve_sfx_key(stream_name: String) -> String:
	return SFX_ALIASES.get(stream_name, stream_name)

func _get_sfx_profile(stream_name: String) -> Dictionary:
	var resolved_name := _resolve_sfx_key(stream_name)
	var profile_name := str(SFX_PROFILE_BY_KEY.get(resolved_name, SFX_PROFILE_DEFAULT_3D))
	if SFX_PROFILE_BY_KEY.has(stream_name):
		profile_name = str(SFX_PROFILE_BY_KEY[stream_name])

	var profile := {}
	if SFX_PROFILE_PRESETS.has(profile_name):
		_merge_sfx_profile(profile, SFX_PROFILE_PRESETS[profile_name])
	if SFX_PROFILE_OVERRIDES.has(resolved_name):
		_merge_sfx_profile(profile, SFX_PROFILE_OVERRIDES[resolved_name])
	if stream_name != resolved_name and SFX_PROFILE_OVERRIDES.has(stream_name):
		_merge_sfx_profile(profile, SFX_PROFILE_OVERRIDES[stream_name])
	return profile


func _merge_sfx_profile(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		target[key] = source[key]


func _should_skip_sfx_for_rate_limit(resolved_name: String, profile: Dictionary) -> bool:
	var min_interval_msec := int(profile.get("rate_limit_msec", 0))
	if min_interval_msec <= 0:
		return false
	var now_msec := Time.get_ticks_msec()
	var last_msec := int(_last_sfx_play_msec_by_key.get(resolved_name, -1000000))
	if now_msec - last_msec < min_interval_msec:
		return true
	_last_sfx_play_msec_by_key[resolved_name] = now_msec
	return false


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
	if _startup_sfx_muted:
		return
	if not is_prewarm_finished and mute_sfx_until_prewarm_finished:
		# 시작 예열 중에는 온디맨드 로드도 막아 첫 전투 프레임 끊김을 피한다.
		return
	var resolved_name := _resolve_sfx_key(stream_name)
	var profile := _get_sfx_profile(stream_name)
	if _should_skip_sfx_for_rate_limit(resolved_name, profile):
		return
	# 1. 리소스 확인 및 동적 로드
	var stream_entry = _load_stream_for_playback(stream_name)
	var stream := _get_sfx_entry_stream(stream_entry)
	var variant_volume_db := _get_sfx_entry_volume_db(stream_entry)
	
	# 2. 리소스가 없으면 디버그용 비프음 재생 (선택사항)
	if not stream:
		if _use_placeholder and placeholder_playback:
			_play_placeholder_beep()
		return

	var non_spatial := bool(profile.get("non_spatial", false))
	if position != null and not non_spatial:
		# 3D 재생 (3D Player Pool 사용)
		var player = sfx_pool[current_sfx_index]
		player.stream = stream
		player.global_position = position
		var pitch_jitter := float(profile.get("pitch_jitter", 0.1))
		player.pitch_scale = pitch_scale + randf_range(-pitch_jitter, pitch_jitter)
		player.volume_db = volume_db + variant_volume_db + DEFAULT_3D_SFX_VOLUME_DB + float(profile.get("volume_db", 0.0))
		player.max_distance = float(profile.get("max_distance", DEFAULT_3D_SFX_MAX_DISTANCE))
		player.unit_size = float(profile.get("unit_size", DEFAULT_3D_SFX_UNIT_SIZE))
		player.play()
		
		# 인덱스 순환
		current_sfx_index = (current_sfx_index + 1) % sfx_pool.size()
	else:
		# 2D 재생 (UI 또는 전투 알림음)
		var player: AudioStreamPlayer
		if non_spatial and not sfx_non_spatial_pool.is_empty():
			player = sfx_non_spatial_pool[current_non_spatial_index]
			current_non_spatial_index = (current_non_spatial_index + 1) % sfx_non_spatial_pool.size()
		else:
			player = sfx_2d_pool[current_2d_index]
			current_2d_index = (current_2d_index + 1) % sfx_2d_pool.size()
		player.stream = stream
		player.pitch_scale = pitch_scale
		player.bus = "SFX" if non_spatial else "UI"
		player.volume_db = volume_db + variant_volume_db + float(profile.get("volume_db", 0.0))
		player.play()

func play_sfx_random_pitch(
	stream_name: String,
	position = null,
	min_pitch: float = 0.9,
	max_pitch: float = 1.1,
	volume_db: float = 0.0
) -> void:
	var low_pitch := minf(min_pitch, max_pitch)
	var high_pitch := maxf(min_pitch, max_pitch)
	play_sfx(stream_name, position, randf_range(low_pitch, high_pitch), volume_db)

## 배경음 재생
func play_bgm(stream_name: String, _fade_duration: float = 1.0) -> void:
	if current_bgm_name == stream_name and is_instance_valid(bgm_player) and bgm_player.playing:
		return
	var stream := _load_bgm_stream(stream_name)
	if not stream:
		push_warning("[Audio] BGM 리소스를 찾을 수 없습니다: %s" % stream_name)
		return
	current_bgm_name = stream_name
	bgm_player.stream = stream
	bgm_player.volume_db = _get_bgm_volume_db(stream_name)
	bgm_player.play()

func stop_bgm(stream_name: String = "") -> void:
	if stream_name != "" and current_bgm_name != stream_name:
		return
	if is_instance_valid(bgm_player):
		bgm_player.stop()
	current_bgm_name = ""

func set_boss_battle_music(active: bool) -> void:
	_boss_bgm_active = active
	if active:
		play_bgm(BOSS_TAIKO_BGM)
	else:
		if current_bgm_name == BOSS_TAIKO_BGM:
			stop_bgm(BOSS_TAIKO_BGM)
		_active_boss_bgm_path = ""
		if _gameplay_bgm_active:
			play_bgm(GAMEPLAY_BGM)


func play_gameplay_music() -> void:
	_gameplay_bgm_active = true
	if not _boss_bgm_active and current_bgm_name != BOSS_TAIKO_BGM:
		play_bgm(GAMEPLAY_BGM)


func stop_gameplay_music() -> void:
	_gameplay_bgm_active = false
	_boss_bgm_active = false
	if current_bgm_name == GAMEPLAY_BGM:
		stop_bgm(GAMEPLAY_BGM)


func play_main_menu_music() -> void:
	play_bgm(MAIN_MENU_BGM)


func stop_main_menu_music() -> void:
	stop_bgm(MAIN_MENU_BGM)


func _get_bgm_volume_db(stream_name: String) -> float:
	if stream_name == BOSS_TAIKO_BGM:
		return BOSS_TAIKO_VOLUME_DB
	if stream_name == GAMEPLAY_BGM:
		return GAMEPLAY_BGM_VOLUME_DB
	if stream_name == MAIN_MENU_BGM:
		return MAIN_MENU_BGM_VOLUME_DB
	return 0.0
## === 길군악(노동요) 전용 재생 시스템 ===
var _gilgunak_player: AudioStreamPlayer = null

func _setup_gilgunak() -> void:
	_gilgunak_player = AudioStreamPlayer.new()
	_gilgunak_player.name = "GilgunakPlayer"
	_gilgunak_player.bus = "SFX"
	_gilgunak_player.volume_db = GILGUNAK_VOLUME_DB
	
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
