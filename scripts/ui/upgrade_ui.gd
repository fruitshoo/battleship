extends CanvasLayer

const HudUpgradeInfoHelper = preload("res://scripts/ui/hud_upgrade_info_helper.gd")
const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")

## 업그레이드 선택 UI
## 레벨업 시 3개의 카드를 표시, 플레이어가 하나를 선택

signal upgrade_chosen(upgrade_id: String)
signal reroll_requested()

@onready var background: ColorRect = $Background
@onready var title_label: Label = $VBox/TitleLabel
@onready var cards_container: HBoxContainer = $VBox/CardsContainer
@onready var footer_row: HBoxContainer = $VBox/FooterRow

var card_buttons: Array = []
var card_ids: Array[String] = []
var reroll_button: Button = null

var _focused_index: int = 0
var _input_lock_timer: float = 0.0

func _get_upgrade_track_label(upgrade_id: String, category: int) -> String:
	if upgrade_id in UpgradeManager.CREW_UPGRADE_IDS or upgrade_id in UpgradeManager.SUPPORT_CREW_UPGRADE_IDS:
		return "병사"
	if upgrade_id in UpgradeManager.SHIP_UPGRADE_IDS or upgrade_id in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS or upgrade_id == UpgradeManager.RARE_FLEET_UPGRADE_ID:
		return "함선"
	var category_name_map := {
		UpgradeManager.Category.ANTI_SHIP: "함포",
		UpgradeManager.Category.ANTI_PERSONNEL: "병사",
		UpgradeManager.Category.HULL: "선체",
		UpgradeManager.Category.SEAMANSHIP: "항해",
		UpgradeManager.Category.SPECIAL: "특수",
		UpgradeManager.Category.FLEET: "지원함",
	}
	return str(category_name_map.get(category, "강화"))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 일시정지 중에도 작동
	visible = false
	_apply_theme()

func _apply_theme() -> void:
	if is_instance_valid(background):
		background.color = Color(0.02, 0.03, 0.05, 0.72)
	if is_instance_valid(title_label):
		NavalUiTheme.style_heading(title_label, 24)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _process(delta: float) -> void:
	if _input_lock_timer > 0:
		_input_lock_timer -= delta

func _unhandled_input(event: InputEvent) -> void:
	if not visible or card_ids.is_empty() or _input_lock_timer > 0:
		return
		
	# 키보드 에코(반복 입력) 무시 및 이미 눌러진 키 무시
	if event is InputEventKey and event.is_echo():
		return
		
	# A, D, Left, Right 화살표로 포커스 이동
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.keycode == KEY_A and event.pressed):
		_focused_index = maxi(0, _focused_index - 1)
		_update_focus()
		if get_viewport(): get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.keycode == KEY_D and event.pressed):
		var max_index = card_ids.size() - 1
		if reroll_button and not reroll_button.disabled:
			max_index += 1 # 리롤 버튼 포함
		_focused_index = mini(max_index, _focused_index + 1)
		_update_focus()
		if get_viewport(): get_viewport().set_input_as_handled()
		
	# Space나 Enter로 선택
	elif event.is_action_pressed("ui_accept") or (event is InputEventKey and event.keycode == KEY_SPACE and event.pressed and not event.is_echo()):
		if _focused_index < card_ids.size():
			_on_choice_pressed(card_ids[_focused_index])
		elif _focused_index == card_ids.size() and reroll_button and not reroll_button.disabled:
			_on_reroll_pressed()
		if get_viewport(): get_viewport().set_input_as_handled()

func _update_focus() -> void:
	# 사운드 재생 (이동음)
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("ui_click", null, 1.2, -6.0) # 피치를 높이고 볼륨을 더 줄임
		
	for i in range(card_buttons.size()):
		var card = card_buttons[i]
		var style = card.get_theme_stylebox("panel") as StyleBoxFlat
		var upgrade_id = card_ids[i]
		var color = UpgradeManager.UPGRADES[upgrade_id].get("color", Color.WHITE)
		
		# 선택된 카드와 아닌 카드의 비주얼 업데이트 (기존 hover 함수 재활용)
		if i == _focused_index:
			_on_card_hover(card, style, color)
		else:
			_on_card_unhover(card, style, color)
			
	# 리롤 버튼 포커스 처리
	if reroll_button:
		var style = reroll_button.get_theme_stylebox("normal") as StyleBoxFlat
		if _focused_index == card_ids.size():
			# 리롤 버튼 호버 효과 (임시)
			reroll_button.add_theme_stylebox_override("normal", reroll_button.get_theme_stylebox("hover"))
			reroll_button.scale = Vector2(1.05, 1.05)
		else:
			reroll_button.add_theme_stylebox_override("normal", style)
			reroll_button.scale = Vector2(1.0, 1.0)

func show_upgrades(choices: Array, rerolls: int = 0) -> void:
	card_ids = []
	
	# 기존 카드 제거
	for child in cards_container.get_children():
		child.queue_free()
	card_buttons.clear()
	
	# 카드 생성
	for i in range(choices.size()):
		var upgrade_id = choices[i]
		card_ids.append(upgrade_id)
		
		var card = _create_card(upgrade_id, i)
		cards_container.add_child(card)
		card_buttons.append(card)
	
	# 리롤 버튼 관리
	_update_reroll_button(rerolls)
	
	_focused_index = 0
	_update_focus()
	
	# 레벨업 시 방향키를 누르고 있었을 경우를 대비해 0.4초간 입력 잠금
	_input_lock_timer = 0.4
	
	visible = true
	
	# 등장 애니메이션 (background + vbox 페이드인)
	background.modulate.a = 0.0
	$VBox.modulate.a = 0.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(background, "modulate:a", 1.0, 0.3)
	tween.tween_property($VBox, "modulate:a", 1.0, 0.3)


func _create_card(upgrade_id: String, _index: int) -> PanelContainer:
	var data = UpgradeManager.UPGRADES[upgrade_id]
	var current_lv = UpgradeManager.current_levels[upgrade_id]
	var next_lv = current_lv + 1
	var color = data.get("color", Color.WHITE)
	
	# 카드 컨테이너
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(200, 280)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 스타일
	var style = StyleBoxFlat.new()
	style.bg_color = NavalUiTheme.PANEL_BG
	style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.35)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	style.shadow_size = 6
	card.add_theme_stylebox_override("panel", style)
	
	# 내부 VBox
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)
	
	# 카테고리 라벨
	var cat_label = Label.new()
	cat_label.text = "[%s]" % _get_upgrade_track_label(upgrade_id, int(data["category"]))
	cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cat_color = color.lerp(NavalUiTheme.TEXT_GOLD, 0.55)
	NavalUiTheme.style_muted(cat_label, 12)
	cat_label.add_theme_color_override("font_color", cat_color)
	vbox.add_child(cat_label)
	
	# 이름 라벨
	var name_label = Label.new()
	name_label.text = data["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
	name_label.add_theme_constant_override("outline_size", 3)
	vbox.add_child(name_label)
	
	# 레벨 라벨
	var level_label = Label.new()
	level_label.text = "Lv.%d → Lv.%d" % [current_lv, next_lv] if current_lv > 0 else "NEW!"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_gold(level_label, 14)
	vbox.add_child(level_label)
	
	# 구분선
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)
	
	# 설명
	var desc_label = Label.new()
	var next_spec: String = HudUpgradeInfoHelper.build_upgrade_spec_text(upgrade_id, next_lv, data.get("stats", {}))
	if next_spec.is_empty():
		desc_label.text = UpgradeManager.get_next_description(upgrade_id)
	else:
		desc_label.text = "다음 효과: " + next_spec
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	NavalUiTheme.style_body(desc_label, 15)
	vbox.add_child(desc_label)
	
	# 여백
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	# 선택 버튼
	var button = Button.new()
	button.text = "선택"
	button.custom_minimum_size = Vector2(0, 40)
	NavalUiTheme.apply_hud_button(button, 18)
	button.pressed.connect(_on_choice_pressed.bind(upgrade_id))
	vbox.add_child(button)
	
	# 호버 효과용 마우스 이벤트 (마우스 작동도 유지)
	card.mouse_entered.connect(func():
		var idx = card_ids.find(upgrade_id)
		if idx != -1:
			_focused_index = idx
			_update_focus()
	)
	
	return card


func _on_choice_pressed(upgrade_id: String) -> void:
	if card_ids.is_empty(): return
	var chosen_id = upgrade_id
	card_ids.clear() # 두 번 눌리는 것 방지
	
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("ui_click", null, 1.0, -4.0)
	
	# 시그널 발생
	upgrade_chosen.emit(chosen_id)
	
	# 페이드아웃
	var tween = create_tween().set_parallel(true)
	tween.tween_property(background, "modulate:a", 0.0, 0.2)
	tween.tween_property($VBox, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(func():
		visible = false
	)


func _on_card_hover(card: PanelContainer, style: StyleBoxFlat, color: Color) -> void:
	style.bg_color = NavalUiTheme.PANEL_BG_SOFT
	style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.55).lightened(0.1)
	# 스케일 효과
	var tween = create_tween()
	tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.1)


func _on_card_unhover(card: PanelContainer, style: StyleBoxFlat, color: Color) -> void:
	style.bg_color = NavalUiTheme.PANEL_BG
	style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.35)
	var tween = create_tween()
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1)


func _update_reroll_button(count: int) -> void:
	if not reroll_button:
		reroll_button = Button.new()
		reroll_button.custom_minimum_size = Vector2(180, 50)
		reroll_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		NavalUiTheme.apply_hud_button(reroll_button, 16)
		
		reroll_button.pressed.connect(_on_reroll_pressed)
		
		# 마우스 호버 지원
		reroll_button.mouse_entered.connect(func():
			_focused_index = card_ids.size()
			_update_focus()
		)
		
		footer_row.add_child(reroll_button)
	
	reroll_button.text = "Reroll (%d)" % count
	reroll_button.disabled = count <= 0
	reroll_button.visible = true


func _on_reroll_pressed() -> void:
	# 사운드
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("ui_click", null, 1.1, -4.0)
	
	reroll_requested.emit()
