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
@onready var xp_label: Label = $SidePanel/VBox/XPLabel # 새로운 XP 라벨 필요
@onready var gust_warning: Label = $GustWarning
@onready var game_over_label: Label = $GameOverLabel
@onready var victory_label: Label = $VictoryLabel
@onready var boss_hp_panel: PanelContainer = $BossHPPanel
@onready var boss_hp_label: Label = $BossHPPanel/VBox/BossHPLabel

var game_time: float = 0.0
var _gust_warning_timer: float = 0.0
var player_ship: Node3D = null


func _ready() -> void:
	update_level(1)
	update_score(0)
	update_enemy_count(0)
	update_crew_status(4)
	
	# WindManager 돌풍 시그널 연결
	if is_instance_valid(WindManager):
		if WindManager.has_signal("gust_started"):
			WindManager.gust_started.connect(_on_gust_started)
		if WindManager.has_signal("gust_ended"):
			WindManager.gust_ended.connect(_on_gust_ended)


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
		difficulty_label.text = "🔥 난이도 %d" % val

func update_enemy_count(val: int) -> void:
	if enemy_count_label:
		enemy_count_label.text = "🚢 적: %d" % val

func update_crew_status(count: int, max_count: int = 4) -> void:
	if crew_label:
		crew_label.text = "👥 선원: %d/%d" % [count, max_count]


func _update_timer() -> void:
	if timer_label:
		var minutes = int(game_time) / 60
		var seconds = int(game_time) % 60
		timer_label.text = "⏱ %d:%02d" % [minutes, seconds]


func _update_wind_display() -> void:
	if not wind_label or not is_instance_valid(WindManager):
		return
	
	var angle = WindManager.wind_angle_degrees
	var strength = WindManager.get_wind_strength()
	var direction_name = _angle_to_compass(angle)
	
	# 돌풍 중이면 색상 변경
	if WindManager._gust_blend > 0.1:
		wind_label.add_theme_color_override("font_color", Color(1, 0.6, 0.2, 1))
		wind_label.text = "🌬️ 돌풍! %s %.1f" % [direction_name, strength]
	else:
		wind_label.add_theme_color_override("font_color", Color(0.8, 1, 0.8, 1))
		wind_label.text = "🌬️ %s %.1f" % [direction_name, strength]


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
		speed_label.text = "%s %.1f" % [mode, speed]


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
		var filled = int(ratio * bar_length)
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
	if xp_label:
		var ratio = float(current) / float(maximum)
		var bar_length = 10
		var filled = int(ratio * bar_length)
		var bar = "■".repeat(filled) + "□".repeat(bar_length - filled)
		xp_label.text = "✨ XP %s %d/%d" % [bar, current, maximum]


func _update_xp_display() -> void:
	# LevelManager에서 데이터 가져옴
	if Engine.get_process_frames() % 15 != 0:
		return
		
	var lm = get_tree().root.find_child("LevelManager", true, false)
	if lm:
		if lm.get("current_xp") != null:
			update_xp(lm.current_xp, lm.xp_to_next_level)
		if lm.get("game_difficulty") != null:
			update_difficulty_ui(lm.game_difficulty)


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
