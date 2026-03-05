extends CanvasLayer

## 게임 HUD (Game HUD)
## 레벨, 점수, 바람, 속도, 돌풍 경고 등을 시각화

@onready var level_label: Label = $TopPanel/HBox/LevelLabel
@onready var score_label: Label = $TopPanel/HBox/ScoreLabel
@onready var timer_label: Label = $TopPanel/HBox/TimerLabel
@onready var difficulty_label: Label = $TopPanel/HBox/DifficultyLabel
@onready var enemy_count_label: Label = $SidePanel/VBox/EnemyCountLabel
@onready var crew_label: Label = $SidePanel/VBox/CrewLabel
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
var _player_lookup_cooldown: float = 0.0

# 신규 레이아웃 UI 요소
var hp_bar: ProgressBar = null
var hp_text_label: Label = null
var boss_hp_bar_new: ProgressBar = null
var boss_hp_text_label: Label = null
var stamina_bar: ProgressBar = null
var top_left_container: VBoxContainer = null
var top_right_container: VBoxContainer = null
var bottom_left_container: VBoxContainer = null
var speed_display: Label = null

# --- 도선 UI ---
var boarding_ui: VBoxContainer = null
var boarding_bar: ProgressBar = null
var boarding_label: Label = null

# --- 초요기(소집) UI ---
var merit_bar: ProgressBar = null
var merit_label: Label = null

# 캐싱 변수들
var _last_timer_str: String = ""
var _last_speed_str: String = ""
var _last_xp_text: String = ""
var _last_difficulty_text: String = ""
var _last_combat_stats_text: String = ""

# === 렐릭 UI 변수 ===
var relic_container: HBoxContainer = null
var current_relic_count: int = 0

# === 무기 UI 변수 ===
var weapon_container: HBoxContainer = null
var weapon_slots: Array[PanelContainer] = []
var active_weapons: Dictionary = {} # 무기 ID를 슬롯 인덱스에 매핑
var support_container: HBoxContainer = null
var support_slots: Array[PanelContainer] = []
var active_supports: Dictionary = {} # 보조 업그레이드 ID를 슬롯 인덱스에 매핑
var combat_stats_label: Label = null

func _ready() -> void:
	# 기존 요소 숨기기 & 신규 레이아웃 셋업
	_setup_top_xp_bar()
	_setup_new_layout()
	
	update_level(1)
	update_score(0)
	update_enemy_count(0)
	update_crew_status(4)
	
	if xp_label: xp_label.visible = false # 기존 라벨 숨김
	
	# WindManager 돌풍 시그널 연결
	if is_instance_valid(WindManager):
		if WindManager.has_signal("gust_started"):
			WindManager.gust_started.connect(_on_gust_started)
		if WindManager.has_signal("gust_ended"):
			WindManager.gust_ended.connect(_on_gust_ended)

func _setup_top_xp_bar() -> void:
	xp_bar = ProgressBar.new()
	xp_bar.name = "TopXPBar"
	add_child(xp_bar)
	
	# 상단 가득 차게 설정
	xp_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	xp_bar.custom_minimum_size.y = 18.0 # 내부에 레벨 텍스트를 넣기 위해 두께 확보 (기존 4.0)
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
	
	# === 초요기(공적) 바 추가 ===
	merit_bar = ProgressBar.new()
	merit_bar.name = "TopMeritBar"
	add_child(merit_bar)
	
	merit_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	merit_bar.offset_top = 22.0 # XP 바(두께 18) 바로 아래 여유있게 배치
	merit_bar.custom_minimum_size.y = 12.0 # XP바(18)보다 약간 얇게
	merit_bar.show_percentage = false
	merit_bar.z_index = 10
	
	var mb_bg = StyleBoxFlat.new()
	mb_bg.bg_color = Color(0, 0, 0, 0.3)
	merit_bar.add_theme_stylebox_override("background", mb_bg)
	
	var mb_fg = StyleBoxFlat.new()
	mb_fg.bg_color = Color(1.0, 0.8, 0.2, 0.9) # 금색/주황색 계열
	mb_fg.set_border_width_all(0)
	merit_bar.add_theme_stylebox_override("fill", mb_fg)
	
	merit_label = Label.new()
	merit_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	merit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	merit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	merit_label.add_theme_font_size_override("font_size", 10)
	merit_label.add_theme_color_override("font_outline_color", Color.BLACK)
	merit_label.add_theme_constant_override("outline_size", 3)
	merit_label.text = "공적 포인트 (초요기 대기)"
	merit_bar.add_child(merit_label)
	
	# 컨테이너 오프셋 조정
	var top_panel = get_node_or_null("TopPanel")
	if top_panel:
		top_panel.offset_top = 34.0 # XP(18)+Merit(12)+여백(4)
	
	# SidePanel도 약간 내림
	var side_panel = get_node_or_null("SidePanel")
	if side_panel:
		side_panel.offset_top = 264.0

func _setup_new_layout() -> void:
	# 1. 기존 거추장스러운 레거시 패널들(컨테이너)을 숨김
	if hull_label: hull_label.visible = false
	if speed_label: speed_label.visible = false
	if boss_hp_panel: boss_hp_panel.visible = false
	
	var legacy_top = get_node_or_null("TopPanel")
	if legacy_top: legacy_top.visible = false
	var legacy_side = get_node_or_null("SidePanel")
	if legacy_side: legacy_side.visible = false
	
	# === 좌측 상단 (진행도 및 재화) ===
	if not top_left_container:
		top_left_container = VBoxContainer.new()
		add_child(top_left_container)
		top_left_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		top_left_container.offset_left = 24
		top_left_container.offset_top = 32 # XP바(4px)에서 충분히 아래로 (기존 24)
		
		# 레벨 라벨은 XP 바 내부 중앙으로 이동
		_attach_level_label_to_xp_bar()
			
		# --- 렐릭(유물) 슬롯 (Slay the Spire 스타일) ---
		# 금화 등의 텍스트보다 위에 오도록 먼저 컨테이너에 추가
		var relic_margin = MarginContainer.new()
		relic_margin.add_theme_constant_override("margin_bottom", 10) # 아래 라벨들과 약간의 간격 확보
		top_left_container.add_child(relic_margin)
		
		relic_container = HBoxContainer.new()
		relic_container.add_theme_constant_override("separation", 8) # 슬롯 간격
		relic_margin.add_child(relic_container)
		
		# 5개의 빈 슬롯 미리 생성
		for i in range(5):
			var slot_bg = PanelContainer.new()
			slot_bg.custom_minimum_size = Vector2(32, 32)
			
			var slot_sb = StyleBoxFlat.new()
			slot_sb.bg_color = Color(0, 0, 0, 0.5) # 반투명 검은색 배경
			slot_sb.set_corner_radius_all(4)
			slot_sb.border_width_bottom = 1
			slot_sb.border_width_top = 1
			slot_sb.border_width_left = 1
			slot_sb.border_width_right = 1
			slot_sb.border_color = Color(0.3, 0.3, 0.3, 0.8) # 얇은 테두리
			slot_bg.add_theme_stylebox_override("panel", slot_sb)
			
			# 아이콘이 들어갈 라벨 (Material Symbols 폰트를 사용할 것이므로 Label 사용)
			var icon_label = Label.new()
			icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			icon_label.add_theme_font_size_override("font_size", 20)
			
			var icon_font = load("res://assets/fonts/MaterialSymbolsOutlined.ttf")
			if icon_font:
				icon_label.add_theme_font_override("font", icon_font)
				
			slot_bg.add_child(icon_label)
			relic_container.add_child(slot_bg)

		# --- 무기 현황 슬롯 (렐릭 바로 아래) ---
		weapon_container = HBoxContainer.new()
		weapon_container.add_theme_constant_override("separation", 8)
		# 렐릭 마진 하단보다 덜 띄우고 붙여둠
		top_left_container.add_child(weapon_container)
		
		# 3개의 빈 상태 무기 슬롯 생성 (대포, 신기전, 대장군전)
		weapon_slots.clear()
		for i in range(4):
			var w_slot_bg = PanelContainer.new()
			w_slot_bg.custom_minimum_size = Vector2(32, 32)
			
			var w_slot_sb = StyleBoxFlat.new()
			w_slot_sb.bg_color = Color(0, 0, 0, 0.4) # 약간 더 투명한 배경
			w_slot_sb.set_corner_radius_all(4)
			w_slot_sb.border_width_bottom = 1
			w_slot_sb.border_width_top = 1
			w_slot_sb.border_width_left = 1
			w_slot_sb.border_width_right = 1
			w_slot_sb.border_color = Color(0.3, 0.3, 0.3, 0.8)
			w_slot_bg.add_theme_stylebox_override("panel", w_slot_sb)
			
			# 아이콘 (초기엔 빈칸)
			var icon_label = Label.new()
			icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			icon_label.add_theme_font_size_override("font_size", 20)
			
			var icon_font = load("res://assets/fonts/MaterialSymbolsOutlined.ttf")
			if icon_font:
				icon_label.add_theme_font_override("font", icon_font)
			icon_label.name = "Icon"
			w_slot_bg.add_child(icon_label)
			
			# 우측 하단 레벨 텍스트 오버레이 (초기엔 숨김)
			var level_label_overlay = Label.new()
			level_label_overlay.name = "Level"
			level_label_overlay.text = "1"
			level_label_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			level_label_overlay.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			level_label_overlay.add_theme_font_size_override("font_size", 10)
			level_label_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
			level_label_overlay.add_theme_constant_override("outline_size", 3)
			level_label_overlay.visible = false
			
			# 우측 하단에 고정하기 위한 앵커 설정
			level_label_overlay.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			level_label_overlay.offset_left = -16
			level_label_overlay.offset_top = -14
			level_label_overlay.offset_right = -2
			level_label_overlay.offset_bottom = -2
			
			w_slot_bg.add_child(level_label_overlay)
			
			weapon_container.add_child(w_slot_bg)
			weapon_slots.append(w_slot_bg)

		# --- 보조 업그레이드 슬롯 (무기 슬롯 바로 아래) ---
		support_container = HBoxContainer.new()
		support_container.add_theme_constant_override("separation", 8)
		top_left_container.add_child(support_container)

		support_slots.clear()
		for i in range(4):
			var s_slot_bg = PanelContainer.new()
			s_slot_bg.custom_minimum_size = Vector2(32, 32)

			var s_slot_sb = StyleBoxFlat.new()
			s_slot_sb.bg_color = Color(0, 0, 0, 0.35)
			s_slot_sb.set_corner_radius_all(4)
			s_slot_sb.border_width_bottom = 1
			s_slot_sb.border_width_top = 1
			s_slot_sb.border_width_left = 1
			s_slot_sb.border_width_right = 1
			s_slot_sb.border_color = Color(0.25, 0.25, 0.25, 0.8)
			s_slot_bg.add_theme_stylebox_override("panel", s_slot_sb)

			var icon_label = Label.new()
			icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			icon_label.add_theme_font_size_override("font_size", 20)

			var icon_font = load("res://assets/fonts/MaterialSymbolsOutlined.ttf")
			if icon_font:
				icon_label.add_theme_font_override("font", icon_font)
			icon_label.name = "Icon"
			s_slot_bg.add_child(icon_label)

			var level_label_overlay = Label.new()
			level_label_overlay.name = "Level"
			level_label_overlay.text = "1"
			level_label_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			level_label_overlay.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			level_label_overlay.add_theme_font_size_override("font_size", 10)
			level_label_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
			level_label_overlay.add_theme_constant_override("outline_size", 3)
			level_label_overlay.visible = false
			level_label_overlay.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			level_label_overlay.offset_left = -16
			level_label_overlay.offset_top = -14
			level_label_overlay.offset_right = -2
			level_label_overlay.offset_bottom = -2

			s_slot_bg.add_child(level_label_overlay)
			support_container.add_child(s_slot_bg)
			support_slots.append(s_slot_bg)

		# 약간의 간격 확보를 위해 빈 컨테이너 추가
		var spacer = Control.new()
		spacer.custom_minimum_size.y = 10
		top_left_container.add_child(spacer)

		# 골드(점수) 라벨 - 무기 슬롯 아래에 위치
		if score_label and score_label.get_parent():
			score_label.get_parent().remove_child(score_label)
			top_left_container.add_child(score_label)
			score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			score_label.add_theme_font_size_override("font_size", 18)
			score_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))

		# 전투 통계 (격침/병사 처치)
		combat_stats_label = Label.new()
		combat_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		combat_stats_label.add_theme_font_size_override("font_size", 12)
		combat_stats_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		combat_stats_label.text = "[전과] 격침 0 | 병사 0"
		top_left_container.add_child(combat_stats_label)

		# 난이도 라벨 - 유물 슬롯 아래 금화 패널 밑에 위치
		if difficulty_label and difficulty_label.get_parent():
			difficulty_label.get_parent().remove_child(difficulty_label)
			top_left_container.add_child(difficulty_label)
			difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			difficulty_label.add_theme_font_size_override("font_size", 12)
			difficulty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


	# === 상단 중앙 (타이머) ===
	if timer_label:
		var top_center_container = PanelContainer.new()
		add_child(top_center_container)
		top_center_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		top_center_container.offset_top = 40 # XP바 및 화면 상단에서 충분히 격리 (기존 28 -> 40)
		top_center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
		
		# 타이머용 반투명 어두운 배경 스타일박스
		var time_sb = StyleBoxFlat.new()
		time_sb.bg_color = Color(0, 0, 0, 0.35)
		time_sb.set_corner_radius_all(12)
		time_sb.content_margin_left = 16
		time_sb.content_margin_right = 16
		time_sb.content_margin_top = 4
		time_sb.content_margin_bottom = 4
		top_center_container.add_theme_stylebox_override("panel", time_sb)

		if timer_label.get_parent():
			timer_label.get_parent().remove_child(timer_label)
		
		top_center_container.add_child(timer_label)
		timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		timer_label.add_theme_font_size_override("font_size", 22) # 큼직하게
		timer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1)) # 순백색
		
		# 타이머 텍스트 그림자 효과 (가독성 향상)
		timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		timer_label.add_theme_constant_override("shadow_outline_size", 2)

	# 에너미 숫자는 표시하지 않음 (나침반과 겹침 및 불필요)
	if enemy_count_label:
		enemy_count_label.visible = false

	# === 우측 상단 (속도: 나침반 인접) ===
	if not top_right_container:
		top_right_container = VBoxContainer.new()
		add_child(top_right_container)
		top_right_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		top_right_container.offset_right = -24
		top_right_container.offset_top = 248
		top_right_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN

		var speed_panel = PanelContainer.new()
		var speed_panel_style = StyleBoxFlat.new()
		speed_panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
		speed_panel_style.set_corner_radius_all(8)
		speed_panel_style.content_margin_left = 10
		speed_panel_style.content_margin_right = 10
		speed_panel_style.content_margin_top = 4
		speed_panel_style.content_margin_bottom = 4
		speed_panel.add_theme_stylebox_override("panel", speed_panel_style)
		top_right_container.add_child(speed_panel)

		speed_display = Label.new()
		speed_display.add_theme_font_size_override("font_size", 17)
		speed_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		speed_display.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		speed_panel.add_child(speed_display)

	# === 좌측 하단 (플레이어 상태) ===
	if not bottom_left_container:
		bottom_left_container = VBoxContainer.new()
		add_child(bottom_left_container)
		bottom_left_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		bottom_left_container.offset_left = 24
		bottom_left_container.offset_bottom = -24
		bottom_left_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
		
		# 기존 크루 라벨 이동 및 폰트 설정
		if crew_label and crew_label.get_parent():
			crew_label.get_parent().remove_child(crew_label)
			bottom_left_container.add_child(crew_label)
			crew_label.add_theme_font_size_override("font_size", 18) # 아이콘이므로 조금 더 크게
			
			# Material Symbols 폰트 적용
			var icon_font = load("res://assets/fonts/MaterialSymbolsOutlined.ttf")
			if icon_font:
				crew_label.add_theme_font_override("font", icon_font)
		
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
		
		# 플레이어 스태미나 바 생성 (HP바 바로 아래)
		stamina_bar = ProgressBar.new()
		stamina_bar.custom_minimum_size = Vector2(240, 8) # HP바보다 얇게
		stamina_bar.show_percentage = false
		bottom_left_container.add_child(stamina_bar)
		
		var stam_bg = StyleBoxFlat.new()
		stam_bg.bg_color = Color(0.1, 0.1, 0.1, 0.7)
		stam_bg.set_corner_radius_all(2)
		var stam_fg = StyleBoxFlat.new()
		stam_fg.bg_color = Color(1.0, 0.8, 0.2, 0.9) # 노란색/주황색 계열
		stam_fg.set_corner_radius_all(2)
		
		stamina_bar.add_theme_stylebox_override("background", stam_bg)
		stamina_bar.add_theme_stylebox_override("fill", stam_fg)

	# === 상단 중앙 (보스 HP 바) ===
	boss_hp_bar_new = ProgressBar.new()
	add_child(boss_hp_bar_new)
	boss_hp_bar_new.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_hp_bar_new.offset_top = 80 # 타이머 아래 충분한 보호 구역 (기존 65)
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

	# === 화면 중앙 (도선 진행 바) ===
	boarding_ui = VBoxContainer.new()
	add_child(boarding_ui)
	boarding_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	boarding_ui.offset_top = 100 # 보스 HP바보다 아래, 혹은 중앙 부근
	boarding_ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boarding_ui.visible = false
	
	boarding_label = Label.new()
	boarding_label.text = "도선 준비 중..."
	boarding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boarding_label.add_theme_font_size_override("font_size", 16)
	boarding_label.add_theme_color_override("font_outline_color", Color.BLACK)
	boarding_label.add_theme_constant_override("outline_size", 4)
	boarding_ui.add_child(boarding_label)
	
	boarding_bar = ProgressBar.new()
	boarding_bar.custom_minimum_size = Vector2(200, 12)
	boarding_bar.show_percentage = false
	var b_bg = StyleBoxFlat.new()
	b_bg.bg_color = Color(0, 0, 0, 0.4)
	b_bg.set_corner_radius_all(4)
	var b_fg = StyleBoxFlat.new()
	b_fg.bg_color = Color(1.0, 1.0, 1.0, 0.8) # 흰색 계열 (준비 중)
	b_fg.set_corner_radius_all(4)
	boarding_bar.add_theme_stylebox_override("background", b_bg)
	boarding_bar.add_theme_stylebox_override("fill", b_fg)
	boarding_ui.add_child(boarding_bar)


func _process(delta: float) -> void:
	game_time += delta
	_player_lookup_cooldown = maxf(0.0, _player_lookup_cooldown - delta)
	if not is_instance_valid(player_ship):
		_try_resolve_player_ship()

	_update_timer()


	_update_speed_display()
	_update_crew_count()
	_update_hull_display()
	_update_stamina_display()
	_update_boarding_display()
	
	# 돌풍 경고 깜박임
	if _gust_warning_timer > 0:
		_gust_warning_timer -= delta
		# 깜박이는 효과 (0.3초 간격)
		if gust_warning:
			gust_warning.visible = fmod(_gust_warning_timer, 0.6) > 0.3
		if _gust_warning_timer <= 0 and gust_warning:
			gust_warning.visible = false
			gust_warning.text = ""


func _attach_level_label_to_xp_bar() -> void:
	if not level_label or not xp_bar:
		return
	var current_parent = level_label.get_parent()
	if current_parent and current_parent != xp_bar:
		current_parent.remove_child(level_label)
	if level_label.get_parent() != xp_bar:
		xp_bar.add_child(level_label)
	level_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	level_label.add_theme_constant_override("outline_size", 4)


func _try_resolve_player_ship() -> void:
	if is_instance_valid(player_ship):
		return
	if _player_lookup_cooldown > 0.0:
		return
	_player_lookup_cooldown = 0.25
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and p.get("is_player_controlled") == true:
			player_ship = p
			return
	if players.size() > 0 and is_instance_valid(players[0]):
		player_ship = players[0]


func update_level(val: int) -> void:
	if level_label:
		level_label.text = "[Lv] %d" % val

func update_score(val: int) -> void:
	if score_label:
		var total_gold = SaveManager.gold if is_instance_valid(SaveManager) else val
		score_label.text = "[Gold] %d (Total %d)" % [val, total_gold]

func update_combat_stats(ship_sunk: int, soldiers_killed: int) -> void:
	var text = "[전과] 격침 %d | 병사 %d" % [ship_sunk, soldiers_killed]
	if _last_combat_stats_text == text:
		return
	_last_combat_stats_text = text
	if combat_stats_label:
		combat_stats_label.text = text

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
		var icons = char(0xe7ef) + " " # group 아이콘
		for i in range(max_count):
			if i < count:
				icons += char(0xe061) # filled capsule/circle
			else:
				icons += char(0xe836) # empty capsule/circle
		crew_label.text = icons


func _update_timer() -> void:
	if timer_label:
		var total_seconds: int = int(game_time)
		var minutes: int = int(total_seconds / 60.0) # Explicitly use float to avoid lint
		var seconds: int = total_seconds % 60
		var new_str = "[Time] %d:%02d" % [minutes, seconds]
		if _last_timer_str != new_str:
			_last_timer_str = new_str
			timer_label.text = new_str


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
	if not is_instance_valid(player_ship):
		return
	if player_ship.get("current_speed") == null:
		return
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


func _on_gust_started(_angle_offset: float) -> void:
	if gust_warning:
		gust_warning.text = "!! 바람이 거세집니다 !!"
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
		
func update_stamina(current: float, maximum: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = maximum
		# 스태미나는 즉각적인 피드백이 중요하므로 바로 설정하거나 아주 짧은 트윈 사용
		stamina_bar.value = current
		
		# 소진 시 색상 변경 (버건디/어두운 빨강)
		var fill_style = stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if current < 1.0:
				fill_style.bg_color = Color(0.6, 0.1, 0.1, 0.9)
			else:
				fill_style.bg_color = Color(1.0, 0.8, 0.2, 0.9)


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


## === 초요기 진행도 ===
func update_merit(current: int, maximum: int, level: int = 1) -> void:
	if merit_bar:
		merit_bar.max_value = maximum
		
		# 차오르는 효과를 위해 트윈 사용
		var tween = create_tween()
		tween.tween_property(merit_bar, "value", current, 0.3).set_trans(Tween.TRANS_SINE)
		
		if merit_label:
			if current >= maximum:
				merit_label.text = "[ 함대 LEVEL UP! ]"
				merit_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
				
				# 가득 찼을 때 번쩍이는 연출
				var style = merit_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if style:
					style.bg_color = Color(1.0, 1.0, 0.5, 1.0) # 더 밝은 색으로
			else:
				merit_label.text = "공적 Lv.%d (%d / %d)" % [level, current, maximum]
				merit_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
				
				# 원래 색으로
				var style_normal = merit_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if style_normal:
					style_normal.bg_color = Color(1.0, 0.8, 0.2, 0.9)


func add_relic_icon(icon_text: String) -> void:
	if not relic_container or current_relic_count >= 5: return
	
	var slots = relic_container.get_children()
	if current_relic_count < slots.size():
		var slot_bg = slots[current_relic_count]
		var icon_label = slot_bg.get_child(0)
		if icon_label is Label:
			icon_label.text = icon_text
			var slot_sb = slot_bg.get_theme_stylebox("panel").duplicate()
			slot_bg.add_theme_stylebox_override("panel", slot_sb)
			
			var tween = create_tween()
			tween.tween_property(slot_sb, "border_color", Color(1, 0.8, 0.2, 1.0), 0.2)
			tween.tween_property(icon_label, "scale", Vector2(1.2, 1.2), 0.2)
			tween.tween_property(icon_label, "scale", Vector2(1.0, 1.0), 0.2)
			tween.tween_property(slot_sb, "border_color", Color(0.6, 0.5, 0.1, 0.8), 0.5)
			
		current_relic_count += 1


## 무기 슬롯 업데이트 (획득 순서대로 빈 칸에 채워넣기)
func update_weapon_ui(weapon_id: String, level: int) -> void:
	if level <= 0: return
	
	# 무기별 아이콘 매핑 (Material Symbols)
	var icon_map = {
		"cannon": "sports_baseball", # 대포 (둥근 포탄)
		"singigeon": "rocket_launch", # 신기전 (로켓)
		"janggun": "hardware", # 대장군전 (망치/무거운 쇳덩이 이미지)
	}
	# 무기별 색상 매핑
	var color_map = {
		"cannon": Color(1.0, 0.7, 0.3), # 주황
		"singigeon": Color(1.0, 0.4, 0.4), # 빨강
		"janggun": Color(0.8, 0.5, 0.2), # 황갈색
	}
	
	var actual_icon = icon_map.get(weapon_id, "help")
	var actual_color = color_map.get(weapon_id, Color.WHITE)
	
	# 이미 등록된 무기인지 확인
	var slot_idx = -1
	if active_weapons.has(weapon_id):
		slot_idx = active_weapons[weapon_id]
	else:
		# 신규 획득: 빈 슬롯 앞쪽부터 순서대로 채워넣기
		slot_idx = active_weapons.size()
		if slot_idx >= weapon_slots.size():
			return # 슬롯 수를 초과하면 표시하지 않음
		active_weapons[weapon_id] = slot_idx
	
	# UI 갱신
	var slot = weapon_slots[slot_idx]
	var icon_label = slot.get_node_or_null("Icon") as Label
	var lv_label = slot.get_node_or_null("Level") as Label
	
	if icon_label:
		icon_label.text = actual_icon
		icon_label.add_theme_color_override("font_color", actual_color)
		
	if lv_label:
		lv_label.text = str(level)
		lv_label.visible = true
	
	# 슬롯 테두리를 무기 색으로 잠깐 반짝이게 (획득/레벨업 피드백)
	var slot_sb = slot.get_theme_stylebox("panel")
	if slot_sb:
		slot_sb = slot_sb.duplicate()
		slot.add_theme_stylebox_override("panel", slot_sb)
		var tween = create_tween()
		tween.tween_property(slot_sb, "border_color", actual_color, 0.2)
		tween.tween_property(slot_sb, "border_color", Color(0.4, 0.4, 0.4, 0.8), 0.5)


## 보조 업그레이드 슬롯 업데이트 (획득 순서대로 빈 칸에 채워넣기)
func update_support_ui(upgrade_id: String, level: int) -> void:
	if level <= 0:
		return

	var icon_map = {
		"crew_numbers": "group_add",
		"crew_quality": "military_tech",
		"hull_defense": "shield",
		"navigation": "explore",
		"supply_bonus": "medical_services",
	}
	var color_map = {
		"crew_numbers": Color(0.5, 0.8, 1.0),
		"crew_quality": Color(1.0, 0.9, 0.35),
		"hull_defense": Color(0.75, 0.45, 0.2),
		"navigation": Color(0.45, 1.0, 0.45),
		"supply_bonus": Color(0.35, 0.95, 0.35),
	}

	var actual_icon = icon_map.get(upgrade_id, "build")
	var actual_color = color_map.get(upgrade_id, Color.WHITE)

	var slot_idx = -1
	if active_supports.has(upgrade_id):
		slot_idx = active_supports[upgrade_id]
	else:
		slot_idx = active_supports.size()
		if slot_idx >= support_slots.size():
			return
		active_supports[upgrade_id] = slot_idx

	var slot = support_slots[slot_idx]
	var icon_label = slot.get_node_or_null("Icon") as Label
	var lv_label = slot.get_node_or_null("Level") as Label

	if icon_label:
		icon_label.text = actual_icon
		icon_label.add_theme_color_override("font_color", actual_color)

	if lv_label:
		lv_label.text = str(level)
		lv_label.visible = true

	var slot_sb = slot.get_theme_stylebox("panel")
	if slot_sb:
		slot_sb = slot_sb.duplicate()
		slot.add_theme_stylebox_override("panel", slot_sb)
		var tween = create_tween()
		tween.tween_property(slot_sb, "border_color", actual_color, 0.2)
		tween.tween_property(slot_sb, "border_color", Color(0.35, 0.35, 0.35, 0.8), 0.5)


func _update_hull_display() -> void:
	# 30프레임마다 체크
	if Engine.get_process_frames() % 30 != 0:
		return
	if is_instance_valid(player_ship) and player_ship.get("hull_hp") != null:
		update_hull_hp(player_ship.hull_hp, player_ship.max_hull_hp)

func _update_stamina_display() -> void:
	if Engine.get_process_frames() % 5 != 0: # 스태미나는 좀 더 자주 업데이트 (60fps 기준 약 12번/초)
		return
	if is_instance_valid(player_ship) and player_ship.get("rowing_stamina") != null:
		update_stamina(player_ship.rowing_stamina, 100.0) # 기본 100.0 유지

func _update_boarding_display() -> void:
	if not boarding_ui or not is_instance_valid(player_ship):
		return
		
	var is_boarding = player_ship.get("is_boarding") == true
	var prep_timer = player_ship.get("boarding_prep_timer") if "boarding_prep_timer" in player_ship else 0.0
	var prep_duration = player_ship.get("boarding_prep_duration") if "boarding_prep_duration" in player_ship else 2.5
	
	if is_boarding:
		boarding_ui.visible = true
		if prep_timer < prep_duration:
			# 예열 단계
			boarding_label.text = "도선 준비 중 (밧줄 고정)..."
			boarding_bar.value = (prep_timer / prep_duration) * 100
			var fill = boarding_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill: fill.bg_color = Color(1.0, 1.0, 1.0, 0.7)
		else:
			# 실제 도선(병사 이동) 단계
			boarding_label.text = "도선 진행 중!"
			boarding_bar.value = 100
			var fill = boarding_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill: fill.bg_color = Color(0.2, 0.8, 1.0, 0.8) # 하늘색
	else:
		boarding_ui.visible = false


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

func show_victory_with_damage(rows: Array, total_damage: float) -> void:
	if not victory_label:
		return
	var lines: Array[String] = []
	lines.append("[!] VICTORY [!]")
	lines.append("총 무기 피해: %.0f" % total_damage)
	if rows.is_empty():
		lines.append("무기 데미지 통계 없음")
	else:
		lines.append("----- 무기별 데미지 -----")
		for row in rows:
			var name = str(row.get("name", "?"))
			var dmg = float(row.get("damage", 0.0))
			lines.append("%s : %.0f" % [name, dmg])
	
	victory_label.text = "\n".join(lines)
	victory_label.visible = true
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	victory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_label.offset_left = -320.0
	victory_label.offset_top = -180.0
	victory_label.offset_right = 320.0
	victory_label.offset_bottom = 220.0
	victory_label.add_theme_font_size_override("font_size", 24)
	
	var tween = create_tween()
	victory_label.modulate.a = 0.0
	tween.tween_property(victory_label, "modulate:a", 1.0, 0.8)
