extends CanvasLayer

## 게임 HUD (Game HUD)
## 레벨, 점수, 바람, 속도, 돌풍 경고 등을 시각화

@onready var level_label: Label = $TopPanel/HBox/LevelLabel
@onready var score_label: Label = $TopPanel/HBox/ScoreLabel
@onready var timer_label: Label = $TopPanel/HBox/TimerLabel
@onready var difficulty_label: Label = $TopPanel/HBox/DifficultyLabel
@onready var enemy_count_label: Label = $SidePanel/VBox/EnemyCountLabel
@onready var crew_label: Label = $SidePanel/VBox/CrewLabel
@onready var wind_label: Label = $SidePanel/VBox/WindLabel
@onready var speed_label: Label = $SidePanel/VBox/SpeedLabel
@onready var hull_label: Label = $SidePanel/VBox/HullLabel
@onready var xp_label: Label = $SidePanel/VBox/XPLabel
var xp_bar: ProgressBar = null
@onready var gust_warning: Label = $GustWarning
@onready var game_over_label: Label = $GameOverLabel
@onready var victory_label: Label = $VictoryLabel
@onready var boss_hp_panel: PanelContainer = $BossHPPanel
@onready var boss_hp_label: Label = $BossHPPanel/VBox/BossHPLabel

var game_time: float = 0.0
var _gust_warning_timer: float = 0.0
var player_ship: Node3D = null
var cached_lm: Node = null

# 캐싱 변수들 (텍스트 할당을 줄여 프레임 드랍을 막기 위함)
var _last_timer_str: String = ""
var _last_wind_str: String = ""
var _last_speed_str: String = ""
var _last_xp_text: String = ""
var _last_difficulty_text: String = ""


func _ready() -> void:
	update_level(1)
	update_score(0)
	update_enemy_count(0)
	update_crew_status(4)
	_setup_top_xp_bar()
	
	if xp_label: xp_label.visible = false # 기존 라벨 숨김
	
	# WindManager 돌풍 시그널 연결
	if is_instance_valid(WindManager):
		if WindManager.has_signal("gust_started"):
			WindManager.gust_started.connect(_on_gust_started)
		if WindManager.has_signal("gust_ended"):
			WindManager.gust_ended.connect(_on_gust_ended)
			
	# 레벨매니저 캐싱
	cached_lm = get_tree().root.find_child("LevelManager", true, false)
	if not cached_lm:
		var lm_nodes = get_tree().get_nodes_in_group("level_manager")
		if lm_nodes.size() > 0: cached_lm = lm_nodes[0]

func _setup_top_xp_bar() -> void:
	xp_bar = ProgressBar.new()
	xp_bar.name = "TopXPBar"
	add_child(xp_bar)
	
	# 상단 가득 차게 설정
	xp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	xp_bar.custom_minimum_size.y = 4.0 # 더 얇게 (6 -> 4)
	xp_bar.show_percentage = false
	xp_bar.z_index = 10 # 가장 위에 표시
	
	# 스타일 설정 (Cyan/Blue 계열)
	var sb_bg = StyleBoxFlat.new()
	sb_bg.bg_color = Color(0, 0, 0, 0.3) # 반투명 배경
	xp_bar.add_theme_stylebox_override("background", sb_bg)
	
	var sb_fg = StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.2, 0.7, 1.0, 0.9) # 밝은 사이언
	sb_fg.set_border_width_all(0) # 얇은 바에서는 테두리 제거가 더 깔끔
	xp_bar.add_theme_stylebox_override("fill", sb_fg)
	
	# 다른 UI들이 XP바와 겹치지 않도록 TopPanel 위치 조정
	var top_panel = get_node_or_null("TopPanel")
	if top_panel:
		top_panel.offset_top = 14.0 # XP바(4px) + 여유공간(10px) = 14px
	
	# SidePanel도 약간 내림
	var side_panel = get_node_or_null("SidePanel")
	if side_panel:
		side_panel.offset_top = 264.0 # 기존 260 -> 264


func _process(delta: float) -> void:
	game_time += delta
	_update_timer()
	_update_wind_display()
	_update_speed_display()
	_update_crew_count()
	_update_hull_display()
	_update_xp_display()
	
	# 돌풍 경고 깜박임
	if _gust_warning_timer > 0:
		_gust_warning_timer -= delta
		# 깜박이는 효과 (0.3초 간격)
		if gust_warning:
			gust_warning.visible = fmod(_gust_warning_timer, 0.6) > 0.3
		if _gust_warning_timer <= 0 and gust_warning:
			gust_warning.visible = false
			gust_warning.text = ""


func update_level(val: int) -> void:
	if level_label:
		level_label.text = "⚔️ Lv.%d" % val

func update_score(val: int) -> void:
	if score_label:
		var total_gold = SaveManager.gold if is_instance_valid(SaveManager) else val
		score_label.text = "💰 %d (Total %d)" % [val, total_gold]

func update_difficulty_ui(val: int) -> void:
	if difficulty_label:
		var new_text = "🔥 난이도 %d" % val
		if _last_difficulty_text != new_text:
			_last_difficulty_text = new_text
			difficulty_label.text = new_text

func update_enemy_count(val: int) -> void:
	if enemy_count_label:
		enemy_count_label.text = "🚢 적: %d" % val

func update_crew_status(count: int, max_count: int = 4) -> void:
	if crew_label:
		crew_label.text = "👥 선원: %d/%d" % [count, max_count]


func _update_timer() -> void:
	if timer_label:
		var total_seconds: int = int(game_time)
		var minutes: int = total_seconds / 60
		var seconds: int = total_seconds % 60
		var new_str = "⏱ %d:%02d" % [minutes, seconds]
		if _last_timer_str != new_str:
			_last_timer_str = new_str
			timer_label.text = new_str


func _update_wind_display() -> void:
	if not wind_label or not is_instance_valid(WindManager):
		return
	
	var angle = WindManager.wind_angle_degrees
	var strength = WindManager.get_wind_strength()
	var direction_name = _angle_to_compass(angle)
	
	# 카메라 기준 상대 풍향 화살표 계산
	var screen_arrow = _get_screen_wind_arrow(angle)
	
	# 돌풍 중이면 색상 변경
	var wind_text = ""
	var wind_color = Color.WHITE
	
	if WindManager._gust_blend > 0.1:
		wind_color = Color(1, 0.6, 0.2, 1)
		wind_text = "🌬️ 돌풍! %s %s %.1f" % [screen_arrow, direction_name, strength]
	else:
		wind_color = Color(0.8, 1, 0.8, 1)
		wind_text = "🌬️ %s %s %.1f" % [screen_arrow, direction_name, strength]
		
	if _last_wind_str != wind_text:
		_last_wind_str = wind_text
		wind_label.text = wind_text
		wind_label.add_theme_color_override("font_color", wind_color)


## 카메라 회전을 고려하여 화면 기준 풍향 화살표 반환
func _get_screen_wind_arrow(wind_angle_deg: float) -> String:
	var cam = get_viewport().get_camera_3d()
	var cam_yaw_deg = 0.0
	if cam and cam.get("_cam_rotation"):
		cam_yaw_deg = rad_to_deg(cam._cam_rotation.x)
	
	# 풍향에서 카메라 수평 회전을 빼면 화면 기준 상대 각도
	var relative = fmod(wind_angle_deg - cam_yaw_deg + 720.0, 360.0)
	
	# 8방위 화살표 (화면 기준: 0=위)
	const ARROWS = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	var idx = int((relative + 22.5) / 45.0) % 8
	return ARROWS[idx]


func _update_speed_display() -> void:
	if not speed_label:
		return
	
	# 플레이어 배 찾기
	if not is_instance_valid(player_ship):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_ship = players[0]
	
	if is_instance_valid(player_ship) and player_ship.get("current_speed") != null:
		var speed = player_ship.current_speed
		var mode = "🚣" if player_ship.get("is_rowing") else "⛵"
		var speed_text = "%s %.1f" % [mode, speed]
		
		if _last_speed_str != speed_text:
			_last_speed_str = speed_text
			speed_label.text = speed_text


func _update_crew_count() -> void:
	# 매 프레임은 과하므로 30프레임마다
	if Engine.get_process_frames() % 30 != 0:
		return
	
	if not is_instance_valid(player_ship):
		return
	
	# 플레이어 배의 Soldiers 노드에서 살아있는 병사 수
	var soldiers_node = player_ship.get_node_or_null("Soldiers")
	if soldiers_node:
		var alive_count = 0
		for soldier in soldiers_node.get_children():
			if soldier.get("current_state") != null and soldier.current_state != 4: # 4 = DEAD
				if soldier.get("team") == "player":
					alive_count += 1
		
		var max_val = player_ship.get("max_crew_count") if player_ship.get("max_crew_count") != null else 4
		update_crew_status(alive_count, max_val)


func _angle_to_compass(angle_deg: float) -> String:
	# 8방위 변환
	var normalized = fmod(angle_deg + 360.0, 360.0)
	if normalized < 22.5 or normalized >= 337.5:
		return "N"
	elif normalized < 67.5:
		return "NE"
	elif normalized < 112.5:
		return "E"
	elif normalized < 157.5:
		return "SE"
	elif normalized < 202.5:
		return "S"
	elif normalized < 247.5:
		return "SW"
	elif normalized < 292.5:
		return "W"
	else:
		return "NW"


func _on_gust_started(angle_offset: float) -> void:
	if gust_warning:
		var dir = "→" if angle_offset > 0 else "←"
		gust_warning.text = "⚡ 돌풍 %s ⚡" % dir
		gust_warning.visible = true
		_gust_warning_timer = 3.5

func _on_gust_ended() -> void:
	if gust_warning:
		gust_warning.text = ""
		gust_warning.visible = false
		_gust_warning_timer = 0.0


## === 선체 HP ===

func update_hull_hp(current: float, maximum: float) -> void:
	if hull_label:
		var ratio = current / maximum
		var bar_length = 10
		var filled = clamp(int(ratio * bar_length), 0, bar_length)
		var bar = "█".repeat(filled) + "░".repeat(bar_length - filled)
		hull_label.text = "🛡 %s %.0f" % [bar, current]
		
		# 색상: HP에 따라 녹색 → 노랑 → 빨강
		if ratio > 0.6:
			hull_label.add_theme_color_override("font_color", Color(0.4, 1, 0.4, 1))
		elif ratio > 0.3:
			hull_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))
		else:
			hull_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))


## === XP 진행도 ===

func update_xp(current: int, maximum: int) -> void:
	if xp_bar:
		xp_bar.max_value = maximum
		xp_bar.value = current
	
	if xp_label:
		# 기존 라벨도 혹시 모르니 데이터는 유지 (숨겨진 상태)
		var new_text = "✨ XP %d/%d" % [current, maximum]
		if _last_xp_text != new_text:
			_last_xp_text = new_text
			xp_label.text = new_text


func _update_xp_display() -> void:
	# LevelManager에서 데이터 가져옴
	if Engine.get_process_frames() % 15 != 0:
		return
		
	if is_instance_valid(cached_lm):
		if cached_lm.get("current_xp") != null:
			update_xp(cached_lm.current_xp, cached_lm.xp_to_next_level)
		if cached_lm.get("game_difficulty") != null:
			update_difficulty_ui(cached_lm.game_difficulty)


func _update_hull_display() -> void:
	# 30프레임마다 체크
	if Engine.get_process_frames() % 30 != 0:
		return
	if is_instance_valid(player_ship) and player_ship.get("hull_hp") != null:
		update_hull_hp(player_ship.hull_hp, player_ship.max_hull_hp)


func show_game_over() -> void:
	if game_over_label:
		game_over_label.text = "💀 SHIP DESTROYED 💀"
		game_over_label.visible = true
		# 페이드인
		var tween = create_tween()
		game_over_label.modulate.a = 0.0
		tween.tween_property(game_over_label, "modulate:a", 1.0, 1.0)


func update_boss_hp(current: float, maximum: float) -> void:
	if boss_hp_panel:
		boss_hp_panel.visible = true
		var ratio = current / maximum
		var bar_length = 20
		var filled = int(ratio * bar_length)
		var bar = "█".repeat(filled) + "░".repeat(bar_length - filled)
		boss_hp_label.text = "👑 BOSS: %s %.0f/%.0f" % [bar, current, maximum]
		
		if current <= 0:
			boss_hp_panel.visible = false


func show_victory() -> void:
	if victory_label:
		victory_label.text = "🚩 VICTORY 🚩"
		victory_label.visible = true
		var tween = create_tween()
		victory_label.modulate.a = 0.0
		tween.tween_property(victory_label, "modulate:a", 1.0, 2.0)
