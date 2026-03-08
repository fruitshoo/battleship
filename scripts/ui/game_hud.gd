extends CanvasLayer
const MATERIAL_SYMBOLS_FONT = preload("res://assets/fonts/MaterialSymbolsOutlined.ttf")
const SceneGroupCache = preload("res://scripts/helpers/scene_group_cache.gd")
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

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
var active_weapons: Dictionary = {} # 함선 업그레이드 ID -> 슬롯 인덱스
var support_container: HBoxContainer = null
var support_slots: Array[PanelContainer] = []
var active_supports: Dictionary = {} # 병사 업그레이드 ID -> 슬롯 인덱스
var combat_stats_label: Label = null
var upgrade_tooltip_panel: PanelContainer = null
var upgrade_tooltip_label: Label = null
var _tooltip_slot_ref: PanelContainer = null
var _tooltip_hover_slot: PanelContainer = null
var _tooltip_hover_elapsed: float = 0.0
var _tooltip_tween: Tween = null
var game_over_panel: PanelContainer = null
var game_over_subtitle: Label = null
var game_over_button: Button = null
var _game_over_return_timer: float = -1.0
var _game_over_transitioning: bool = false

const UPGRADE_TOOLTIP_SHOW_DELAY: float = 0.14
const UPGRADE_TOOLTIP_OFFSET := Vector2(18.0, 16.0)
const UPGRADE_TOOLTIP_MIN_WIDTH: float = 320.0

const SHIP_UPGRADE_IDS := [
	"cannon", "singigeon", "janggun", "ballista",
	"hull_defense", "navigation", "supply_bonus", "fleet_signal",
	"fleet_cannon", "fleet_hull", "supply", "gold"
]
const CREW_UPGRADE_IDS := [
	"crew_numbers", "crew_quality", "fire_pot", "repeating_crossbow",
	"fleet_crew"
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 기존 요소 숨기기 & 신규 레이아웃 셋업
	_setup_top_xp_bar()
	_setup_new_layout()
	_setup_game_over_panel()
	
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
	merit_label.text = "지휘 포인트 (병영 강화 대기)"
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
	_setup_upgrade_tooltip()
	
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
			
			if MATERIAL_SYMBOLS_FONT:
				icon_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
				
			slot_bg.add_child(icon_label)
			relic_container.add_child(slot_bg)

		# --- 함선 업그레이드 슬롯 ---
		var ship_title = Label.new()
		ship_title.text = "[함선 업그레이드]"
		ship_title.add_theme_font_size_override("font_size", 12)
		ship_title.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
		top_left_container.add_child(ship_title)

		weapon_container = HBoxContainer.new()
		weapon_container.add_theme_constant_override("separation", 8)
		top_left_container.add_child(weapon_container)
		
		# 함선 업그레이드 슬롯 4칸
		weapon_slots.clear()
		for i in range(4):
			var w_slot_bg = PanelContainer.new()
			w_slot_bg.custom_minimum_size = Vector2(32, 32)
			w_slot_bg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			
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
			
			if MATERIAL_SYMBOLS_FONT:
				icon_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
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
			w_slot_bg.set_meta("upgrade_id", "")
			w_slot_bg.set_meta("upgrade_level", 0)
			_bind_upgrade_slot_hover(w_slot_bg)
			
			weapon_container.add_child(w_slot_bg)
			weapon_slots.append(w_slot_bg)

		# --- 병사 업그레이드 슬롯 ---
		var crew_title = Label.new()
		crew_title.text = "[병사 업그레이드]"
		crew_title.add_theme_font_size_override("font_size", 12)
		crew_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
		top_left_container.add_child(crew_title)

		support_container = HBoxContainer.new()
		support_container.add_theme_constant_override("separation", 8)
		top_left_container.add_child(support_container)

		support_slots.clear()
		for i in range(4):
			var s_slot_bg = PanelContainer.new()
			s_slot_bg.custom_minimum_size = Vector2(32, 32)
			s_slot_bg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

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

			if MATERIAL_SYMBOLS_FONT:
				icon_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
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
			s_slot_bg.set_meta("upgrade_id", "")
			s_slot_bg.set_meta("upgrade_level", 0)
			_bind_upgrade_slot_hover(s_slot_bg)
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
			if MATERIAL_SYMBOLS_FONT:
				crew_label.add_theme_font_override("font", MATERIAL_SYMBOLS_FONT)
		
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
	_update_game_over_return(delta)
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
	_update_upgrade_tooltip_state(delta)
	_update_upgrade_tooltip_position()
	
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
	var players = SceneGroupCache.get_nodes(get_tree(), "player")
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
				merit_label.text = "[ 병영 LEVEL UP! ]"
				merit_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
				
				# 가득 찼을 때 번쩍이는 연출
				var style = merit_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if style:
					style.bg_color = Color(1.0, 1.0, 0.5, 1.0) # 더 밝은 색으로
			else:
				merit_label.text = "지휘 Lv.%d (%d / %d)" % [level, current, maximum]
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


func _setup_upgrade_tooltip() -> void:
	if is_instance_valid(upgrade_tooltip_panel):
		return
	upgrade_tooltip_panel = PanelContainer.new()
	upgrade_tooltip_panel.visible = false
	upgrade_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_tooltip_panel.z_index = 300
	upgrade_tooltip_panel.custom_minimum_size = Vector2(UPGRADE_TOOLTIP_MIN_WIDTH, 0)
	upgrade_tooltip_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	add_child(upgrade_tooltip_panel)

	var tip_style = StyleBoxFlat.new()
	tip_style.bg_color = Color(0.03, 0.045, 0.075, 0.96)
	tip_style.border_color = Color(0.9, 0.85, 0.6, 0.9)
	tip_style.border_width_top = 1
	tip_style.border_width_bottom = 1
	tip_style.border_width_left = 1
	tip_style.border_width_right = 1
	tip_style.set_corner_radius_all(8)
	tip_style.shadow_color = Color(0, 0, 0, 0.45)
	tip_style.shadow_size = 6
	tip_style.content_margin_left = 12
	tip_style.content_margin_right = 12
	tip_style.content_margin_top = 10
	tip_style.content_margin_bottom = 10
	upgrade_tooltip_panel.add_theme_stylebox_override("panel", tip_style)

	upgrade_tooltip_label = Label.new()
	upgrade_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upgrade_tooltip_label.add_theme_font_size_override("font_size", 12)
	upgrade_tooltip_label.add_theme_constant_override("line_spacing", 2)
	upgrade_tooltip_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	upgrade_tooltip_label.custom_minimum_size = Vector2(UPGRADE_TOOLTIP_MIN_WIDTH - 24.0, 0.0)
	upgrade_tooltip_panel.add_child(upgrade_tooltip_label)

func _bind_upgrade_slot_hover(slot: PanelContainer) -> void:
	slot.mouse_entered.connect(_on_upgrade_slot_mouse_entered.bind(slot))
	slot.mouse_exited.connect(_on_upgrade_slot_mouse_exited.bind(slot))

func _on_upgrade_slot_mouse_entered(slot: PanelContainer) -> void:
	if not is_instance_valid(upgrade_tooltip_panel) or not is_instance_valid(upgrade_tooltip_label):
		return
	var upgrade_id = str(slot.get_meta("upgrade_id", ""))
	var level = int(slot.get_meta("upgrade_level", 0))
	if upgrade_id.is_empty() or level <= 0:
		return
	_tooltip_hover_slot = slot
	_tooltip_hover_elapsed = 0.0
	if _tooltip_slot_ref != slot and is_instance_valid(upgrade_tooltip_panel) and upgrade_tooltip_panel.visible:
		_show_upgrade_tooltip(slot)

func _on_upgrade_slot_mouse_exited(slot: PanelContainer) -> void:
	if _tooltip_hover_slot == slot:
		_tooltip_hover_slot = null
		_tooltip_hover_elapsed = 0.0
	if _tooltip_slot_ref != slot:
		return
	_tooltip_slot_ref = null
	_hide_upgrade_tooltip()

func _update_upgrade_tooltip_state(delta: float) -> void:
	if is_instance_valid(_tooltip_hover_slot):
		_tooltip_hover_elapsed += delta
		if (not is_instance_valid(upgrade_tooltip_panel) or not upgrade_tooltip_panel.visible) and _tooltip_hover_elapsed >= UPGRADE_TOOLTIP_SHOW_DELAY:
			_show_upgrade_tooltip(_tooltip_hover_slot)

func _show_upgrade_tooltip(slot: PanelContainer) -> void:
	if not is_instance_valid(upgrade_tooltip_panel) or not is_instance_valid(upgrade_tooltip_label):
		return
	var upgrade_id = str(slot.get_meta("upgrade_id", ""))
	var level = int(slot.get_meta("upgrade_level", 0))
	if upgrade_id.is_empty() or level <= 0:
		return
	_tooltip_slot_ref = slot
	upgrade_tooltip_label.text = _build_upgrade_tooltip_text(upgrade_id, level)
	_apply_upgrade_tooltip_theme(_get_upgrade_color(upgrade_id))
	upgrade_tooltip_panel.visible = true
	upgrade_tooltip_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if is_instance_valid(_tooltip_tween):
		_tooltip_tween.kill()
	_tooltip_tween = create_tween()
	_tooltip_tween.tween_property(upgrade_tooltip_panel, "modulate:a", 1.0, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_update_upgrade_tooltip_position()

func _hide_upgrade_tooltip(instant: bool = false) -> void:
	if not is_instance_valid(upgrade_tooltip_panel):
		return
	if is_instance_valid(_tooltip_tween):
		_tooltip_tween.kill()
	_tooltip_tween = null
	if instant or not upgrade_tooltip_panel.visible:
		upgrade_tooltip_panel.visible = false
		upgrade_tooltip_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
		return
	_tooltip_tween = create_tween()
	_tooltip_tween.tween_property(upgrade_tooltip_panel, "modulate:a", 0.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tooltip_tween.finished.connect(_on_upgrade_tooltip_fade_out_finished, CONNECT_ONE_SHOT)

func _on_upgrade_tooltip_fade_out_finished() -> void:
	if not is_instance_valid(upgrade_tooltip_panel):
		return
	upgrade_tooltip_panel.visible = false
	upgrade_tooltip_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _apply_upgrade_tooltip_theme(accent_color: Color) -> void:
	if not is_instance_valid(upgrade_tooltip_panel):
		return
	var tip_style = upgrade_tooltip_panel.get_theme_stylebox("panel")
	if not (tip_style is StyleBoxFlat):
		return
	var style_copy = (tip_style as StyleBoxFlat).duplicate()
	var accent = accent_color.lerp(Color.WHITE, 0.15)
	accent.a = 0.95
	style_copy.border_color = accent
	upgrade_tooltip_panel.add_theme_stylebox_override("panel", style_copy)

func _update_upgrade_tooltip_position() -> void:
	if not is_instance_valid(upgrade_tooltip_panel) or not upgrade_tooltip_panel.visible:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var panel_size = upgrade_tooltip_panel.size
	if panel_size.x <= 1.0:
		panel_size = upgrade_tooltip_panel.custom_minimum_size
	var pos = mouse_pos + UPGRADE_TOOLTIP_OFFSET
	pos.x = clampf(pos.x, 12.0, maxf(12.0, viewport_size.x - panel_size.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, viewport_size.y - panel_size.y - 12.0))
	upgrade_tooltip_panel.position = pos

func _is_ship_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in SHIP_UPGRADE_IDS

func _is_crew_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in CREW_UPGRADE_IDS

func _build_upgrade_tooltip_text(upgrade_id: String, level: int) -> String:
	var track_name = "함선" if _is_ship_upgrade(upgrade_id) else "병사"
	var name = upgrade_id
	var desc = ""
	var stats: Dictionary = {}
	var max_level = level
	if is_instance_valid(UpgradeManager):
		var upgrades_data = UpgradeManager.get("UPGRADES")
		if upgrades_data is Dictionary:
			var data = (upgrades_data as Dictionary).get(upgrade_id, {})
			if data is Dictionary:
				name = str(data.get("name", upgrade_id))
				desc = str(data.get("description", ""))
				stats = data.get("stats", {})
				max_level = int(data.get("max_level", level))
	var spec = _build_upgrade_spec_text(upgrade_id, level, stats)
	var text = "[%s] %s  Lv.%d/%d" % [track_name, name, level, max_level]
	if not desc.is_empty():
		text += "\n" + desc
	if not spec.is_empty():
		text += "\n현재 효과: " + spec
	if level >= max_level:
		text += "\n다음 단계: 최대 레벨"
	elif is_instance_valid(UpgradeManager) and UpgradeManager.has_method("get_next_description"):
		var next_desc = str(UpgradeManager.get_next_description(upgrade_id))
		if not next_desc.is_empty():
			text += "\n다음 단계: " + next_desc
	return text

func _build_upgrade_spec_text(upgrade_id: String, level: int, stats: Dictionary) -> String:
	match upgrade_id:
		"cannon":
			return "화력 +%d%% | 사거리 +%d%% | 장전속도 +%d%%" % [
				int(stats.get("dmg_pct_per_lv", 20) * level),
				int(stats.get("range_pct_per_lv", 10) * level),
				int(stats.get("cd_pct_per_lv", 8) * level),
			]
		"singigeon":
			var shot_count = 2 if level <= 2 else (3 if level <= 4 else 4)
			return "연사 발수 %d발 | 확산 사격 강화" % shot_count
		"janggun":
			return "명중 시 화염/둔화 디버프 강화"
		"ballista":
			var dmg = stats.get("base_damage", 45.0) + (level - 1) * stats.get("damage_per_lv", 15.0)
			var pierce = int(stats.get("base_pierce", 3) + (level - 1) * stats.get("pierce_per_lv", 1))
			return "데미지 %.0f | 관통 %d명" % [dmg, pierce]
		"hull_defense":
			var ranged_block = clampf(
				float(level) * float(stats.get("crew_ranged_block_per_lv", 0.06)),
				0.0,
				float(stats.get("crew_ranged_block_max", 0.30))
			)
			return "최대 체력 +%d | 방어력 +%.1f" % [
				int(stats.get("hp_add", 30.0) * level),
				level * float(stats.get("def_per_lv", 2.0)),
			] + " | 원거리 피해 -%d%%" % int(round(ranged_block * 100.0))
		"navigation":
			var turn_pct = int((pow(float(stats.get("turn_mult", 1.15)), level) - 1.0) * 100.0)
			var stamina_save = int((1.0 - pow(float(stats.get("stamina_mult", 0.85)), level)) * 100.0)
			return "선회 +%d%% | 스태미나 소모 -%d%%" % [turn_pct, stamina_save]
		"supply_bonus":
			var radius = stats.get("base_radius", 8.0) + level * stats.get("radius_per_lv", 2.0)
			var heal = stats.get("heal_per_lv", 5.0) * level
			return "획득 반경 %.1fm | 추가 회복 +%.0f" % [radius, heal]
		"fleet_signal":
			return "희귀 카드: 지원 함대 소집"
		"fleet_cannon":
			return "지원 함선 화력 +%d%% | 재장전 +%d%%" % [
				int(stats.get("dmg_pct_per_lv", 25) * level),
				int(stats.get("cd_pct_per_lv", 10) * level),
			]
		"fleet_hull":
			return "지원 함선 체력 +%d | 방어력 +%d" % [
				int(stats.get("hp_add", 100) * level),
				int(stats.get("def_per_lv", 5) * level),
			]
		"fleet_crew":
			var respawn_gain = int((1.0 - pow(float(stats.get("respawn_mult", 0.7)), level)) * 100.0)
			return "지원 함선 병사 리스폰 +%d%%" % respawn_gain
		"crew_numbers":
			var crew_add = int(stats.get("crew_add", 1) * level)
			var respawn_gain = int((1.0 - pow(float(stats.get("respawn_mult", 0.8)), level)) * 100.0)
			return "병사 정원 +%d | 리스폰 속도 +%d%%" % [crew_add, respawn_gain]
		"crew_quality":
			return "병사 HP +%d | 공격력 +%d%% | 피해 감소 +%d%%" % [
				int(stats.get("hp_per_lv", 10) * level),
				int(stats.get("dmg_pct_per_lv", 15) * level),
				int(stats.get("def_pct_per_lv", 10) * level),
			]
		"fire_pot":
			var fp_dmg = stats.get("base_damage", 15.0) + (level - 1) * stats.get("damage_per_lv", 5.0)
			var fp_cd = maxf(1.0, stats.get("base_cooldown", 6.0) - (level - 1) * stats.get("cooldown_reduce_per_lv", 1.0))
			return "폭발 데미지 %.0f | 재사용 %.1f초" % [fp_dmg, fp_cd]
		"repeating_crossbow":
			var burst = 3
			if level >= 3:
				burst = 4
			if level >= 5:
				burst = 5
			var rc_dmg = stats.get("base_damage", 10.0) + (level - 1) * stats.get("damage_per_lv", 2.0)
			return "연사 %d발 | 1발 데미지 %.0f" % [burst, rc_dmg]
		"supply":
			return "즉시 최대체력 +%d" % int(stats.get("max_hp_add", 20.0))
		"gold":
			return "점수 +%d" % int(stats.get("score_add", 50))
	return ""

func _get_upgrade_icon(upgrade_id: String) -> String:
	var icon_map = {
		"cannon": "sports_baseball",
		"singigeon": "rocket_launch",
		"janggun": "hardware",
		"ballista": "arrow_selector_tool",
		"hull_defense": "shield",
		"navigation": "explore",
		"supply_bonus": "medical_services",
		"fleet_signal": "groups",
		"fleet_cannon": "flaky",
		"fleet_hull": "security",
		"fleet_crew": "diversity_3",
		"crew_numbers": "group_add",
		"crew_quality": "military_tech",
		"fire_pot": "local_fire_department",
		"repeating_crossbow": "bolt",
		"supply": "healing",
		"gold": "paid",
	}
	return icon_map.get(upgrade_id, "build")

func _get_upgrade_color(upgrade_id: String) -> Color:
	var color_map = {
		"cannon": Color(1.0, 0.7, 0.3),
		"singigeon": Color(1.0, 0.4, 0.4),
		"janggun": Color(0.8, 0.5, 0.2),
		"ballista": Color(0.9, 0.6, 0.25),
		"hull_defense": Color(0.75, 0.45, 0.2),
		"navigation": Color(0.45, 1.0, 0.45),
		"supply_bonus": Color(0.35, 0.95, 0.35),
		"fleet_signal": Color(1.0, 0.75, 0.35),
		"fleet_cannon": Color(1.0, 0.45, 0.85),
		"fleet_hull": Color(0.3, 1.0, 0.8),
		"fleet_crew": Color(0.35, 0.9, 1.0),
		"crew_numbers": Color(0.5, 0.8, 1.0),
		"crew_quality": Color(1.0, 0.9, 0.35),
		"fire_pot": Color(0.93, 0.42, 0.2),
		"repeating_crossbow": Color(0.65, 0.95, 0.35),
		"supply": Color(0.55, 0.95, 0.6),
		"gold": Color(1.0, 0.86, 0.3),
	}
	return color_map.get(upgrade_id, Color.WHITE)

func _update_upgrade_track_slot(upgrade_id: String, level: int, track: String) -> void:
	if level <= 0:
		return
	var actual_icon = _get_upgrade_icon(upgrade_id)
	var actual_color = _get_upgrade_color(upgrade_id)
	var slots = weapon_slots if track == "ship" else support_slots
	if slots.is_empty():
		return

	var slot_idx = -1
	if track == "ship":
		if active_weapons.has(upgrade_id):
			slot_idx = active_weapons[upgrade_id]
		else:
			slot_idx = active_weapons.size()
			if slot_idx >= slots.size():
				return
			active_weapons[upgrade_id] = slot_idx
	else:
		if active_supports.has(upgrade_id):
			slot_idx = active_supports[upgrade_id]
		else:
			slot_idx = active_supports.size()
			if slot_idx >= slots.size():
				return
			active_supports[upgrade_id] = slot_idx

	var slot = slots[slot_idx]
	var icon_label = slot.get_node_or_null("Icon") as Label
	var lv_label = slot.get_node_or_null("Level") as Label
	if icon_label:
		icon_label.text = actual_icon
		icon_label.add_theme_color_override("font_color", actual_color)
	if lv_label:
		lv_label.text = str(level)
		lv_label.visible = true

	slot.set_meta("upgrade_id", upgrade_id)
	slot.set_meta("upgrade_level", level)

	var slot_sb = slot.get_theme_stylebox("panel")
	if slot_sb:
		slot_sb = slot_sb.duplicate()
		slot.add_theme_stylebox_override("panel", slot_sb)
		var tween = create_tween()
		tween.tween_property(slot_sb, "border_color", actual_color, 0.2)
		tween.tween_property(slot_sb, "border_color", Color(0.35, 0.35, 0.35, 0.8), 0.5)

func update_ship_upgrade_ui(upgrade_id: String, level: int) -> void:
	_update_upgrade_track_slot(upgrade_id, level, "ship")

func update_crew_upgrade_ui(upgrade_id: String, level: int) -> void:
	_update_upgrade_track_slot(upgrade_id, level, "crew")

## 레거시 호환: 무기 슬롯 업데이트 -> 함선/병사 슬롯으로 라우팅
func update_weapon_ui(weapon_id: String, level: int) -> void:
	if _is_crew_upgrade(weapon_id):
		update_crew_upgrade_ui(weapon_id, level)
		return
	update_ship_upgrade_ui(weapon_id, level)

## 레거시 호환: 보조 슬롯 업데이트 -> 함선/병사 슬롯으로 라우팅
func update_support_ui(upgrade_id: String, level: int) -> void:
	if _is_crew_upgrade(upgrade_id):
		update_crew_upgrade_ui(upgrade_id, level)
		return
	update_ship_upgrade_ui(upgrade_id, level)


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
	if _game_over_transitioning:
		return
	if game_over_label:
		game_over_label.text = "!!! SHIP DESTROYED !!!"
		game_over_label.visible = true
		# 페이드인
		var tween = create_tween()
		game_over_label.modulate.a = 0.0
		tween.tween_property(game_over_label, "modulate:a", 1.0, 1.0)
	_game_over_return_timer = 4.0
	get_tree().paused = true
	if is_instance_valid(game_over_panel):
		game_over_panel.visible = true
		game_over_panel.modulate.a = 0.0
		_update_game_over_button_text()
		var panel_tween = create_tween()
		panel_tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.25)


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

func _setup_game_over_panel() -> void:
	if is_instance_valid(game_over_panel):
		return
	game_over_panel = PanelContainer.new()
	game_over_panel.visible = false
	game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_panel.z_index = 400
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game_over_panel.offset_left = -180.0
	game_over_panel.offset_top = 54.0
	game_over_panel.offset_right = 180.0
	game_over_panel.offset_bottom = 150.0

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.86, 0.32, 0.24, 0.9)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_bottom = 16.0
	game_over_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(game_over_panel)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.theme_override_constants.separation = 10
	game_over_panel.add_child(vbox)

	game_over_subtitle = Label.new()
	game_over_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_over_subtitle.add_theme_font_size_override("font_size", 14)
	game_over_subtitle.add_theme_color_override("font_color", Color(0.83, 0.86, 0.89))
	game_over_subtitle.text = "함선이 침몰했습니다. 항구로 복귀합니다."
	vbox.add_child(game_over_subtitle)

	game_over_button = Button.new()
	game_over_button.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_button.custom_minimum_size = Vector2(220.0, 42.0)
	game_over_button.text = "메인 메뉴로"
	game_over_button.pressed.connect(_return_to_main_menu)
	vbox.add_child(game_over_button)

func _update_game_over_return(delta: float) -> void:
	if _game_over_return_timer < 0.0 or _game_over_transitioning:
		return
	_game_over_return_timer = maxf(0.0, _game_over_return_timer - delta)
	_update_game_over_button_text()
	if _game_over_return_timer <= 0.0:
		_return_to_main_menu()

func _update_game_over_button_text() -> void:
	if not is_instance_valid(game_over_button):
		return
	if _game_over_return_timer < 0.0:
		game_over_button.text = "메인 메뉴로"
		return
	game_over_button.text = "메인 메뉴로 (%.0f)" % ceil(_game_over_return_timer)

func _return_to_main_menu() -> void:
	if _game_over_transitioning:
		return
	_game_over_transitioning = true
	_game_over_return_timer = -1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
