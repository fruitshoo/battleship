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

# 신규 레이아웃 UI 요소
var hp_bar: ProgressBar = null
var hp_text_label: Label = null
var boss_hp_bar_new: ProgressBar = null
var boss_hp_text_label: Label = null
var top_left_container: VBoxContainer = null
var top_right_container: VBoxContainer = null
var bottom_left_container: VBoxContainer = null
var bottom_right_container: VBoxContainer = null
var speed_display: Label = null
var cooldown_bar: ProgressBar = null
var cooldown_label: Label = null

# 캐싱 변수들
var _last_timer_str: String = ""
var _last_speed_str: String = ""
var _last_xp_text: String = ""
var _last_difficulty_text: String = ""


func _ready() -> void:
	# 기존 요소 숨기기 & 신규 레이아웃 셋업
	_setup_new_layout()
	
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

func _setup_new_layout() -> void:
	# 1. 기존 거추장스러운 레거시 패널들(컨테이너)을 숨김
	if hull_label: hull_label.visible = false
	if speed_label: speed_label.visible = false
	if wind_label: wind_label.visible = false
	if boss_hp_panel: boss_hp_panel.visible = false
	
	var legacy_top = get_node_or_null("TopPanel")
	if legacy_top: legacy_top.visible = false
	var legacy_side = get_node_or_null("SidePanel")
	if legacy_side: legacy_side.visible = false
	
	# === 좌측 상단 (진행도) ===
	if not top_left_container:
		top_left_container = VBoxContainer.new()
		add_child(top_left_container)
		top_left_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		top_left_container.offset_left = 24
		top_left_container.offset_top = 24
		
		# 기존 라벨들 이동
		if level_label and level_label.get_parent():
			level_label.get_parent().remove_child(level_label)
			top_left_container.add_child(level_label)
			level_label.add_theme_font_size_override("font_size", 18)
		
		if timer_label and timer_label.get_parent():
			timer_label.get_parent().remove_child(timer_label)
			top_left_container.add_child(timer_label)
			timer_label.add_theme_font_size_override("font_size", 14)
			timer_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

	# === 우측 상단 (보상) ===
	if not top_right_container:
		top_right_container = VBoxContainer.new()
		add_child(top_right_container)
		top_right_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		top_right_container.offset_right = -24
		top_right_container.offset_top = 24
		top_right_container.alignment = BoxContainer.ALIGNMENT_END
		top_right_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		
		if score_label and score_label.get_parent():
			score_label.get_parent().remove_child(score_label)
			top_right_container.add_child(score_label)
			score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			score_label.add_theme_font_size_override("font_size", 18)
			score_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
			
		if enemy_count_label and enemy_count_label.get_parent():
			enemy_count_label.get_parent().remove_child(enemy_count_label)
			top_right_container.add_child(enemy_count_label)
			enemy_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			enemy_count_label.add_theme_font_size_override("font_size", 14)
			
		if difficulty_label and difficulty_label.get_parent():
			difficulty_label.get_parent().remove_child(difficulty_label)
			top_right_container.add_child(difficulty_label)
			difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			difficulty_label.add_theme_font_size_override("font_size", 12)
			difficulty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	# === 좌측 하단 (플레이어 상태) ===
	if not bottom_left_container:
		bottom_left_container = VBoxContainer.new()
		add_child(bottom_left_container)
		bottom_left_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		bottom_left_container.offset_left = 24
		bottom_left_container.offset_bottom = -24
		bottom_left_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
		
		# 기존 크루 라벨 이동
		if crew_label and crew_label.get_parent():
			crew_label.get_parent().remove_child(crew_label)
			bottom_left_container.add_child(crew_label)
			crew_label.add_theme_font_size_override("font_size", 14)
		
		# 플레이어 HP 바 생성
		hp_bar = ProgressBar.new()
		hp_bar.custom_minimum_size = Vector2(240, 24)
		hp_bar.show_percentage = false
		bottom_left_container.add_child(hp_bar)
		
		var sb_bg = StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		sb_bg.set_corner_radius_all(4)
		var sb_fg = StyleBoxFlat.new()
		sb_fg.bg_color = Color(0.2, 0.8, 0.3, 0.9)
		sb_fg.set_corner_radius_all(4)
		
		hp_bar.add_theme_stylebox_override("background", sb_bg)
		hp_bar.add_theme_stylebox_override("fill", sb_fg)
		
		hp_text_label = Label.new()
		hp_text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hp_text_label.add_theme_font_size_override("font_size", 14)
		hp_bar.add_child(hp_text_label)

	# === 우측 하단 (속도 및 무기) ===
	if not bottom_right_container:
		bottom_right_container = VBoxContainer.new()
		add_child(bottom_right_container)
		bottom_right_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		bottom_right_container.offset_right = -24
		bottom_right_container.offset_bottom = -24
		bottom_right_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
		bottom_right_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN

		speed_display = Label.new()
		speed_display.add_theme_font_size_override("font_size", 18)
		speed_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bottom_right_container.add_child(speed_display)

		# --- 무기 쿨타임 인디케이터 ---
		var cd_box = VBoxContainer.new()
		cd_box.alignment = BoxContainer.ALIGNMENT_END
		bottom_right_container.add_child(cd_box)
		
		cooldown_label = Label.new()
		cooldown_label.text = "장전 중..."
		cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cooldown_label.add_theme_font_size_override("font_size", 12)
		cooldown_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		cd_box.add_child(cooldown_label)
		
		cooldown_bar = ProgressBar.new()
		cooldown_bar.custom_minimum_size = Vector2(140, 6)
		cooldown_bar.show_percentage = false
		var cd_bg = StyleBoxFlat.new()
		cd_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		cd_bg.set_corner_radius_all(3)
		var cd_fg = StyleBoxFlat.new()
		cd_fg.bg_color = Color(1.0, 0.6, 0.2, 0.9)
		cd_fg.set_corner_radius_all(3)
		cooldown_bar.add_theme_stylebox_override("background", cd_bg)
		cooldown_bar.add_theme_stylebox_override("fill", cd_fg)
		cd_box.add_child(cooldown_bar)

	# === 상단 중앙 (보스 HP 바) ===
	boss_hp_bar_new = ProgressBar.new()
	add_child(boss_hp_bar_new)
	boss_hp_bar_new.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_hp_bar_new.offset_top = 50
	boss_hp_bar_new.custom_minimum_size = Vector2(500, 28)
	boss_hp_bar_new.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_hp_bar_new.show_percentage = false
	boss_hp_bar_new.visible = false
	
	var boss_sb_bg = StyleBoxFlat.new()
	boss_sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	boss_sb_bg.set_corner_radius_all(4)
	
	var boss_sb_fg = StyleBoxFlat.new()
	boss_sb_fg.bg_color = Color(0.9, 0.2, 0.2, 0.9)
	boss_sb_fg.set_corner_radius_all(4)
	
	boss_hp_bar_new.add_theme_stylebox_override("background", boss_sb_bg)
	boss_hp_bar_new.add_theme_stylebox_override("fill", boss_sb_fg)
	
	boss_hp_text_label = Label.new()
	boss_hp_text_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_hp_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boss_hp_bar_new.add_child(boss_hp_text_label)


func _process(delta: float) -> void:
	game_time += delta
	_update_timer()
	_update_wind_display()
	_update_speed_display()
	_update_cooldown_display()
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
		level_label.text = "[Lv] %d" % val

func update_score(val: int) -> void:
	if score_label:
		var total_gold = SaveManager.gold if is_instance_valid(SaveManager) else val
		score_label.text = "[Gold] %d (Total %d)" % [val, total_gold]

func update_difficulty_ui(val: int) -> void:
	if difficulty_label:
		var new_text = "[Diff] %d" % val
		if _last_difficulty_text != new_text:
			_last_difficulty_text = new_text
			difficulty_label.text = new_text

func update_enemy_count(val: int) -> void:
	if enemy_count_label:
		enemy_count_label.text = "[Enemy] %d" % val

func update_crew_status(count: int, max_count: int = 4) -> void:
	if crew_label:
		crew_label.text = "[Crew] %d/%d" % [count, max_count]


func _update_timer() -> void:
	if timer_label:
		var total_seconds: int = int(game_time)
		var minutes: int = int(total_seconds / 60.0) # Explicitly use float to avoid lint
		var seconds: int = total_seconds % 60
		var new_str = "[Time] %d:%02d" % [minutes, seconds]
		if _last_timer_str != new_str:
			_last_timer_str = new_str
			timer_label.text = new_str


func _update_wind_display() -> void:
	# 텍스트 형태의 윈드 라벨은 더 이상 사용하지 않음 (이전 잔재, 삭제 예정 또는 나침반이 대체 중)
	pass


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
	# 플레이어 배 찾기
	if not is_instance_valid(player_ship):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_ship = players[0]
	
	if is_instance_valid(player_ship) and player_ship.get("current_speed") != null:
		var speed = player_ship.current_speed
		var mode = "노 젓기" if player_ship.get("is_rowing") else "돛 펼침"
		
		# 속도 표기 (knots 또는 m/s 단위로 시각적 변환)
		var speed_text = "%s : %.1f ㏏" % [mode, speed]
		
		if _last_speed_str != speed_text:
			_last_speed_str = speed_text
			if speed_display:
				speed_display.text = speed_text
			elif speed_label: # 레거시 폴백
				speed_label.text = speed_text


func _update_cooldown_display() -> void:
	if not cooldown_bar or not is_instance_valid(player_ship):
		return
		
	# 메인 대포 찾기
	var cannons = player_ship.find_child("Cannons", true, false)
	if cannons and cannons.get_child_count() > 0:
		var main_cannon = cannons.get_child(0)
		if main_cannon.get("cooldown_timer") != null:
			var current_cd = main_cannon.cooldown_timer
			var max_cd = main_cannon.call("_get_current_cooldown") if main_cannon.has_method("_get_current_cooldown") else main_cannon.get("fire_cooldown")
			
			if max_cd > 0:
				var progress = clamp(1.0 - (current_cd / max_cd), 0.0, 1.0)
				cooldown_bar.value = progress * 100
				
				# 준비 완료 시 디자인 변경
				var fill_style = cooldown_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if progress >= 1.0:
					cooldown_label.text = "발사 대기"
					cooldown_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
					if fill_style: fill_style.bg_color = Color(0.4, 1.0, 0.4, 0.9)
				else:
					cooldown_label.text = "장전 중..."
					cooldown_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
					if fill_style: fill_style.bg_color = Color(1.0, 0.6, 0.2, 0.9)


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
		gust_warning.text = "!! [GUST] %s !!" % dir
		gust_warning.visible = true
		_gust_warning_timer = 3.5

func _on_gust_ended() -> void:
	if gust_warning:
		gust_warning.text = ""
		gust_warning.visible = false
		_gust_warning_timer = 0.0


## === 선체 HP ===

func update_hull_hp(current: float, maximum: float) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		
		# 잔상 효과를 위해 트윈 애니메이션 적용
		var tween = create_tween()
		tween.tween_property(hp_bar, "value", current, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
		if hp_text_label:
			hp_text_label.text = "HP %.0f / %.0f" % [current, maximum]
			
		# 색상: HP 비율에 따라 색 변경 (녹색 -> 노랑 -> 빨강)
		var ratio = current / maximum
		var fill_style = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if ratio > 0.6:
				fill_style.bg_color = Color(0.2, 0.8, 0.3, 0.9)
			elif ratio > 0.3:
				fill_style.bg_color = Color(0.9, 0.7, 0.1, 0.9)
			else:
				fill_style.bg_color = Color(0.9, 0.2, 0.2, 0.9)
	elif hull_label: # 레거시 지원
		var ratio = current / maximum
		var bar_length = 10
		var filled = clamp(int(ratio * bar_length), 0, bar_length)
		var bar = "█".repeat(filled) + "░".repeat(bar_length - filled)
		hull_label.text = "[HP] %s %.0f" % [bar, current]


## === XP 진행도 ===

func update_xp(current: int, maximum: int) -> void:
	if xp_bar:
		xp_bar.max_value = maximum
		xp_bar.value = current
	
	if xp_label:
		# 기존 라벨도 혹시 모르니 데이터는 유지 (숨겨진 상태)
		var new_text = "[XP] %d/%d" % [current, maximum]
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
		game_over_label.text = "!!! SHIP DESTROYED !!!"
		game_over_label.visible = true
		# 페이드인
		var tween = create_tween()
		game_over_label.modulate.a = 0.0
		tween.tween_property(game_over_label, "modulate:a", 1.0, 1.0)


func update_boss_hp(current: float, maximum: float) -> void:
	if boss_hp_bar_new:
		boss_hp_bar_new.max_value = maximum
		boss_hp_bar_new.visible = current > 0
		
		var tween = create_tween()
		tween.tween_property(boss_hp_bar_new, "value", current, 0.2)
		
		if boss_hp_text_label:
			boss_hp_text_label.text = "BOSS: %.0f/%.0f" % [current, maximum]
	elif boss_hp_panel: # 레거시 폴백
		boss_hp_panel.visible = true
		var ratio = current / maximum
		var bar_length = 20
		var filled = int(ratio * bar_length)
		var bar = "█".repeat(filled) + "░".repeat(bar_length - filled)
		boss_hp_label.text = "[BOSS] %s %.0f/%.0f" % [bar, current, maximum]
		
		if current <= 0:
			boss_hp_panel.visible = false


func show_victory() -> void:
	if victory_label:
		victory_label.text = "[!] VICTORY [!]"
		victory_label.visible = true
		var tween = create_tween()
		victory_label.modulate.a = 0.0
		tween.tween_property(victory_label, "modulate:a", 1.0, 2.0)
