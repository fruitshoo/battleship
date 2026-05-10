extends CanvasLayer

const HudUpgradeInfoHelper = preload("res://scripts/ui/hud/hud_upgrade_info_helper.gd")
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const CARD_WIDTH := 212
const CARD_HEIGHT := 352
const CARD_ART_SIZE := 156
const CARD_PLACEHOLDER_ICON_SIZE := 46
const CARD_CORNER_RADIUS := 18
const CARD_CONTENT_PADDING := 16
const CARD_ENTRY_SCALE := 0.94
const CARD_FOCUS_SCALE := 1.042
const CARD_ENTRY_DELAY := 0.055
const CARD_ENTRY_DURATION := 0.22
const CARD_ENTRY_Y_OFFSET := 16.0
const REWARD_CARD_ENTRY_DELAY := 0.075
const REWARD_CARD_ENTRY_DURATION := 0.34
const REWARD_CARD_ENTRY_SCALE := 0.82
const REWARD_CARD_POP_SCALE := 1.075
const REWARD_CARD_ENTRY_Y_OFFSET := 30.0
const REROLL_ENTRY_DELAY := 0.08
const CARD_SHEEN_DURATION := 0.46
const CARD_FOCUS_LIFT_Y := -5.0
const CARD_CHOICE_FADE_DELAY := 0.05
const CARD_CHOICE_FADE_DURATION := 0.13

## 업그레이드 선택 UI
## 레벨업 시 3개의 카드를 표시, 플레이어가 하나를 선택

signal upgrade_chosen(upgrade_id: String)
signal reroll_requested()

@onready var background: ColorRect = $Background
@onready var root_vbox: VBoxContainer = $VBox
@onready var title_label: Label = $VBox/TitleLabel
@onready var title_spacer: Control = $VBox/Spacer
@onready var cards_container: HBoxContainer = $VBox/CardsContainer
@onready var footer_spacer: Control = $VBox/FooterSpacer
@onready var footer_row: HBoxContainer = $VBox/FooterRow

var card_buttons: Array = []
var card_ids: Array[String] = []
var reroll_button: Button = null
var _current_reroll_count: int = 0

var _focused_index: int = 0
var _input_lock_timer: float = 0.0
var _card_width_px: float = CARD_WIDTH
var _card_height_px: float = CARD_HEIGHT
var _card_art_size_px: float = CARD_ART_SIZE
var _card_art_corner_radius_px: float = 12.0
var _card_placeholder_icon_size_px: int = CARD_PLACEHOLDER_ICON_SIZE
var _card_corner_radius_px: int = CARD_CORNER_RADIUS
var _card_content_padding_px: float = CARD_CONTENT_PADDING
var _cards_separation_px: int = 28
var _title_font_size_px: int = 30
var _track_badge_font_size_px: int = 11
var _level_font_size_px: int = 14
var _name_font_size_px: int = 25
var _effect_heading_font_size_px: int = 11
var _effect_body_font_size_px: int = 13
var _reroll_width_px: float = 200
var _reroll_height_px: float = 46
var _reroll_focused: bool = false
var _display_only_mode: bool = false
var _display_close_timer: float = 0.0
var _display_closing: bool = false
var _display_pause_active: bool = false
var _display_previous_paused: bool = false
var _display_confirm_button: Button = null
var _reward_level_overrides: Dictionary = {}
var _treasure_shimmer: ColorRect = null

func _get_upgrade_track_label(upgrade_id: String, category: int) -> String:
	if upgrade_id in UpgradeManager.CREW_UPGRADE_IDS or upgrade_id in UpgradeManager.SUPPORT_CREW_UPGRADE_IDS:
		return LocaleManager.t("upgrade.track.boarding", "병사")
	if upgrade_id in UpgradeManager.SHIP_UPGRADE_IDS or upgrade_id in UpgradeManager.SUPPORT_SHIP_UPGRADE_IDS or upgrade_id == UpgradeManager.RARE_FLEET_UPGRADE_ID:
		return LocaleManager.t("upgrade.track.ship", "함선")
	var category_name_map := {
		UpgradeManager.Category.ANTI_SHIP: LocaleManager.t("upgrade.track.cannon", "함포"),
		UpgradeManager.Category.ANTI_PERSONNEL: LocaleManager.t("upgrade.track.boarding", "백병전"),
		UpgradeManager.Category.HULL: LocaleManager.t("upgrade.track.hull", "선체"),
		UpgradeManager.Category.SEAMANSHIP: LocaleManager.t("upgrade.track.sailing", "항해"),
		UpgradeManager.Category.SPECIAL: LocaleManager.t("upgrade.track.special", "특수"),
		UpgradeManager.Category.FLEET: LocaleManager.t("upgrade.track.fleet", "지원함"),
	}
	return str(category_name_map.get(category, LocaleManager.t("upgrade.track.default", "강화")))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 일시정지 중에도 작동
	visible = false
	_apply_background_fx()
	_apply_theme()
	_apply_layout_density()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_layout_density)
	if not LocaleManager.locale_changed.is_connected(_on_locale_changed):
		LocaleManager.locale_changed.connect(_on_locale_changed)


func _on_locale_changed(_locale: String) -> void:
	_apply_theme()
	if is_instance_valid(reroll_button) and reroll_button.visible:
		_update_reroll_button(_current_reroll_count)
	if is_instance_valid(_display_confirm_button):
		_display_confirm_button.text = LocaleManager.t("upgrade.confirm", "확인")

func _apply_theme() -> void:
	if is_instance_valid(background):
		background.color = Color.WHITE
	if is_instance_valid(title_label):
		title_label.text = LocaleManager.t("upgrade.title", "보강 선택")
		NavalUiTheme.style_heading(title_label, _title_font_size_px)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_instance_valid(cards_container):
		cards_container.add_theme_constant_override("separation", _cards_separation_px)


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 900.0) / 420.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 700.0) / 220.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	_cards_separation_px = roundi(lerpf(14.0, 28.0, density))
	var max_card_width := (maxf(620.0, viewport_size.x - 92.0) - float(_cards_separation_px) * 2.0) / 3.0
	_card_width_px = clampf(max_card_width, 172.0, CARD_WIDTH)
	_card_height_px = roundf(_card_width_px * 1.66)
	_card_art_size_px = roundf(minf(_card_width_px - 28.0, _card_width_px * 0.74))
	_card_art_corner_radius_px = roundf(lerpf(10.0, 12.0, density))
	_card_placeholder_icon_size_px = roundi(lerpf(36.0, CARD_PLACEHOLDER_ICON_SIZE, density))
	_card_corner_radius_px = roundi(lerpf(14.0, CARD_CORNER_RADIUS, density))
	_card_content_padding_px = roundf(lerpf(12.0, CARD_CONTENT_PADDING, density))
	_title_font_size_px = roundi(lerpf(24.0, 30.0, density))
	_track_badge_font_size_px = roundi(lerpf(10.0, 11.0, density))
	_level_font_size_px = roundi(lerpf(12.0, 14.0, density))
	_name_font_size_px = roundi(lerpf(21.0, 25.0, density))
	_effect_heading_font_size_px = roundi(lerpf(10.0, 11.0, density))
	_effect_body_font_size_px = roundi(lerpf(12.0, 13.0, density))
	_reroll_width_px = roundf(clampf(viewport_size.x * 0.22, 176.0, 200.0))
	_reroll_height_px = roundf(lerpf(42.0, 46.0, density))
	var content_width := roundf(_card_width_px * 3.0 + float(_cards_separation_px) * 2.0 + _card_content_padding_px * 2.0)
	if is_instance_valid(root_vbox):
		root_vbox.offset_left = -content_width * 0.5
		root_vbox.offset_right = content_width * 0.5
		root_vbox.offset_top = -roundf(lerpf(176.0, 200.0, density))
		root_vbox.offset_bottom = roundf(lerpf(194.0, 220.0, density))
	if is_instance_valid(title_label):
		NavalUiTheme.style_heading(title_label, _title_font_size_px)
	if is_instance_valid(title_spacer):
		title_spacer.custom_minimum_size.y = roundf(lerpf(14.0, 20.0, density))
	if is_instance_valid(cards_container):
		cards_container.add_theme_constant_override("separation", _cards_separation_px)
	if is_instance_valid(footer_spacer):
		footer_spacer.custom_minimum_size.y = roundf(lerpf(20.0, 28.0, density))
	if is_instance_valid(reroll_button):
		reroll_button.custom_minimum_size = Vector2(_reroll_width_px, _reroll_height_px)
		reroll_button.add_theme_font_size_override("font_size", roundi(lerpf(15.0, 16.0, density)))

func _process(delta: float) -> void:
	if _input_lock_timer > 0:
		_input_lock_timer -= delta
	if _display_only_mode and visible and _display_close_timer > 0.0:
		_display_close_timer -= delta
		if _display_close_timer <= 0.0:
			_close_display_only()

func _unhandled_input(event: InputEvent) -> void:
	if _display_only_mode:
		if visible and (_is_confirm_event(event) or event.is_action_pressed("ui_cancel") or _is_keycode_pressed(event, KEY_ESCAPE)):
			if _is_confirm_event(event) and is_instance_valid(_display_confirm_button) and _display_confirm_button.visible:
				_display_confirm_button.emit_signal("pressed")
			else:
				_close_display_only(true)
			if get_viewport():
				get_viewport().set_input_as_handled()
		return
	if not visible or card_ids.is_empty() or _input_lock_timer > 0:
		return

	if event is InputEventKey and event.is_echo():
		return

	if _is_prev_event(event):
		if not _reroll_focused:
			_focused_index = maxi(0, _focused_index - 1)
		_update_focus()
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_next_event(event):
		if not _reroll_focused:
			_focused_index = mini(card_ids.size() - 1, _focused_index + 1)
		_update_focus()
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_down_event(event):
		if not _reroll_focused and reroll_button and not reroll_button.disabled:
			_reroll_focused = true
			_update_focus()
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_up_event(event):
		if _reroll_focused:
			_reroll_focused = false
			_update_focus()
		if get_viewport():
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		if _reroll_focused and reroll_button and not reroll_button.disabled:
			reroll_button.emit_signal("pressed")
		elif _focused_index >= 0 and _focused_index < card_ids.size():
			_on_choice_pressed(card_ids[_focused_index])
		if get_viewport():
			get_viewport().set_input_as_handled()

func _update_focus(immediate: bool = false) -> void:
	if not immediate and is_instance_valid(AudioManager):
		AudioManager.play_sfx("ui_click", null, 1.2, -6.0) # 피치를 높이고 볼륨을 더 줄임
		
	for i in range(card_buttons.size()):
		var card = card_buttons[i]
		if not is_instance_valid(card):
			continue
		var upgrade_id = card_ids[i]
		var color = UpgradeManager.UPGRADES[upgrade_id].get("color", Color.WHITE)
		var is_focused := i == _focused_index
		_apply_card_focus_visuals(card, color, is_focused, immediate)
			
	if reroll_button:
		if _reroll_focused and not reroll_button.disabled:
			reroll_button.add_theme_stylebox_override("normal", reroll_button.get_theme_stylebox("hover"))
			if immediate:
				reroll_button.scale = Vector2(1.03, 1.03)
			else:
				var focus_tween := create_tween()
				focus_tween.tween_property(reroll_button, "scale", Vector2(1.03, 1.03), 0.12)
		else:
			reroll_button.add_theme_stylebox_override("normal", NavalUiTheme.make_panel_style(Color(0.10, 0.15, 0.20, 0.72), NavalUiTheme.BORDER_GOLD_DIM, 8, 1, 12.0, 7.0, 12.0, 7.0))
			if immediate:
				reroll_button.scale = Vector2.ONE
			else:
				var blur_tween := create_tween()
				blur_tween.tween_property(reroll_button, "scale", Vector2.ONE, 0.12)

func show_upgrades(choices: Array, rerolls: int = 0) -> void:
	_restore_display_pause()
	_display_only_mode = false
	_display_close_timer = 0.0
	_display_closing = false
	_reward_level_overrides.clear()
	_apply_background_fx()
	_apply_layout_density()
	card_ids = []
	_current_reroll_count = rerolls
	_reroll_focused = false
	if is_instance_valid(footer_spacer):
		footer_spacer.visible = true
	if is_instance_valid(footer_row):
		footer_row.visible = true
	if is_instance_valid(_display_confirm_button):
		_display_confirm_button.visible = false
	
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
	_update_focus(true)
	_prepare_entry_animation()
	
	# 레벨업 시 방향키를 누르고 있었을 경우를 대비해 0.4초간 입력 잠금
	_input_lock_timer = 0.4
	
	visible = true
	
	# 등장 애니메이션 (background + vbox 페이드인)
	background.modulate.a = 0.0
	$VBox.modulate.a = 0.0
	var tween = create_tween().set_parallel(true)
	tween.tween_property(background, "modulate:a", 1.0, 0.3)
	tween.tween_property($VBox, "modulate:a", 1.0, 0.3)
	_animate_cards_in()


func show_reward_results(result: Dictionary, duration: float = -1.0) -> void:
	add_to_group("treasure_reward_popup")
	_display_only_mode = true
	_display_closing = false
	_reward_level_overrides.clear()
	_apply_background_fx()
	_prepare_treasure_reward_fx()
	_apply_layout_density()
	card_ids = []
	_current_reroll_count = 0
	_reroll_focused = false
	_pause_tree_for_display()

	if is_instance_valid(title_label):
		title_label.text = _build_reward_title(result)
	if is_instance_valid(footer_spacer):
		footer_spacer.visible = true
	if is_instance_valid(footer_row):
		footer_row.visible = true
	if is_instance_valid(reroll_button):
		reroll_button.visible = false
	var confirm_button := _ensure_display_confirm_button()
	if is_instance_valid(confirm_button):
		confirm_button.visible = true

	for child in cards_container.get_children():
		child.queue_free()
	card_buttons.clear()

	var choices: Array[String] = []
	var upgrades: Array = result.get("upgrades", [])
	for entry in upgrades:
		if not (entry is Dictionary):
			continue
		var upgrade_id := str(entry.get("upgrade_id", "")).strip_edges()
		if upgrade_id.is_empty() or upgrade_id not in UpgradeManager.UPGRADES:
			continue
		if choices.has(upgrade_id):
			continue
		choices.append(upgrade_id)
		_reward_level_overrides[upgrade_id] = entry

	_fit_reward_layout_to_card_count(choices.size())
	for i in range(choices.size()):
		var upgrade_id := choices[i]
		card_ids.append(upgrade_id)
		var card := _create_card(upgrade_id, i)
		cards_container.add_child(card)
		card_buttons.append(card)

	_focused_index = -1
	_prepare_entry_animation()
	_input_lock_timer = 0.0
	_display_close_timer = duration
	visible = true

	background.modulate.a = 0.0
	$VBox.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(background, "modulate:a", 1.0, 0.26)
	tween.tween_property($VBox, "modulate:a", 1.0, 0.24)
	_animate_cards_in()
	_play_reward_title_pulse()


func _build_reward_title(result: Dictionary) -> String:
	var applied_count := int(result.get("applied_count", 0))
	var requested_count := int(result.get("requested_count", applied_count))
	if applied_count <= 0:
		return LocaleManager.t("upgrade.reward.empty", "보물 획득")
	if requested_count >= 5:
		return LocaleManager.t("upgrade.reward.jackpot", "보물 대박 강화 +{count}", {"count": applied_count})
	if requested_count >= 3:
		return LocaleManager.t("upgrade.reward.rare", "보물 희귀 강화 +{count}", {"count": applied_count})
	return LocaleManager.t("upgrade.reward.normal", "보물 강화 +{count}", {"count": applied_count})


func _get_reward_display_duration(card_count: int) -> float:
	return 2.5 + minf(float(card_count) * 0.4, 1.5)


func _close_display_only(play_sound: bool = false) -> void:
	if not _display_only_mode or _display_closing:
		return
	if play_sound:
		UiButtonAudio.play_click()
	_display_closing = true
	_display_only_mode = false
	card_ids.clear()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(background, "modulate:a", 0.0, 0.2)
	tween.tween_property($VBox, "modulate:a", 0.0, 0.2)
	if is_instance_valid(_treasure_shimmer):
		tween.tween_property(_treasure_shimmer, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(func():
		_restore_display_pause()
		queue_free()
	)


func _pause_tree_for_display() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if not _display_pause_active:
		_display_previous_paused = tree.paused
		_display_pause_active = true
	tree.paused = true


func _restore_display_pause() -> void:
	if not _display_pause_active:
		return
	var tree := get_tree()
	if tree != null:
		tree.paused = _display_previous_paused
	_display_pause_active = false


func _exit_tree() -> void:
	_restore_display_pause()


func _ensure_display_confirm_button() -> Button:
	if not is_instance_valid(_display_confirm_button):
		_display_confirm_button = Button.new()
		_display_confirm_button.text = LocaleManager.t("upgrade.confirm", "확인")
		_display_confirm_button.custom_minimum_size = Vector2(_reroll_width_px, _reroll_height_px)
		_display_confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		NavalUiTheme.apply_hud_button(_display_confirm_button, roundi(lerpf(15.0, 16.0, clampf((get_viewport().get_visible_rect().size.y - 700.0) / 220.0, 0.0, 1.0))))
		UiButtonAudio.wire_button(_display_confirm_button)
		_display_confirm_button.pressed.connect(_close_display_only)
		footer_row.add_child(_display_confirm_button)
	_display_confirm_button.text = LocaleManager.t("upgrade.confirm", "확인")
	_display_confirm_button.custom_minimum_size = Vector2(_reroll_width_px, _reroll_height_px)
	return _display_confirm_button


func _fit_reward_layout_to_card_count(card_count: int) -> void:
	if card_count <= 3:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_width := viewport.get_visible_rect().size.x
	var spacing := 10
	_cards_separation_px = spacing
	var available_width := maxf(620.0, viewport_width - 92.0)
	_card_width_px = clampf((available_width - float(card_count - 1) * float(spacing)) / float(card_count), 136.0, CARD_WIDTH)
	_card_height_px = roundf(_card_width_px * 1.66)
	_card_art_size_px = roundf(minf(_card_width_px - 28.0, _card_width_px * 0.74))
	_card_art_corner_radius_px = 10.0
	_card_placeholder_icon_size_px = roundi(clampf(_card_width_px * 0.22, 30.0, CARD_PLACEHOLDER_ICON_SIZE))
	_card_corner_radius_px = 14
	_card_content_padding_px = roundf(clampf(_card_width_px * 0.07, 10.0, CARD_CONTENT_PADDING))
	_name_font_size_px = roundi(clampf(_card_width_px * 0.12, 17.0, 23.0))
	_effect_heading_font_size_px = 10
	_effect_body_font_size_px = 12
	_level_font_size_px = 12
	if is_instance_valid(cards_container):
		cards_container.add_theme_constant_override("separation", spacing)
	if is_instance_valid(root_vbox):
		var content_width := roundf(_card_width_px * float(card_count) + float(spacing) * float(card_count - 1) + _card_content_padding_px * 2.0)
		root_vbox.offset_left = -content_width * 0.5
		root_vbox.offset_right = content_width * 0.5


func _create_card(upgrade_id: String, _index: int) -> PanelContainer:
	var data = UpgradeManager.UPGRADES[upgrade_id]
	var reward_entry: Dictionary = _reward_level_overrides.get(upgrade_id, {})
	var current_lv := int(reward_entry.get("from_level", UpgradeManager.current_levels[upgrade_id]))
	var next_lv := int(reward_entry.get("to_level", current_lv + 1))
	var color = data.get("color", Color.WHITE)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(_card_width_px, _card_height_px)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW if _display_only_mode else Control.CURSOR_POINTING_HAND
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.085, 0.125, 0.96)
	style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.38)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = _card_corner_radius_px
	style.corner_radius_top_right = _card_corner_radius_px
	style.corner_radius_bottom_left = _card_corner_radius_px
	style.corner_radius_bottom_right = _card_corner_radius_px
	style.content_margin_left = _card_content_padding_px
	style.content_margin_right = _card_content_padding_px
	style.content_margin_top = _card_content_padding_px
	style.content_margin_bottom = _card_content_padding_px
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 10
	card.add_theme_stylebox_override("panel", style)
	if _display_only_mode:
		_apply_reward_card_style(card, style, color)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var art_center := CenterContainer.new()
	art_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var art_frame = _create_card_art_frame(upgrade_id, data, color)
	art_center.add_child(art_frame)
	vbox.add_child(art_center)

	var meta_row := HBoxContainer.new()
	meta_row.alignment = BoxContainer.ALIGNMENT_CENTER
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(_create_track_badge(_get_upgrade_track_label(upgrade_id, int(data["category"])), color))
	var meta_spacer := Control.new()
	meta_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(meta_spacer)
	
	var level_label = Label.new()
	level_label.text = "Lv.%d → Lv.%d" % [current_lv, next_lv] if current_lv > 0 else "NEW!"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	NavalUiTheme.style_gold(level_label, _level_font_size_px)
	meta_row.add_child(level_label)
	vbox.add_child(meta_row)
	
	var name_label = Label.new()
	name_label.text = LocaleManager.data_text(data, upgrade_id, "upgrade", "name", upgrade_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", NavalUiTheme.FONT_SEMIBOLD)
	name_label.add_theme_font_size_override("font_size", _name_font_size_px)
	name_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN.lerp(color, 0.18))
	name_label.add_theme_color_override("font_shadow_color", NavalUiTheme.OUTLINE_DARK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	name_label.add_theme_constant_override("shadow_outline_size", 2)
	vbox.add_child(name_label)
	
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.color = color.lerp(NavalUiTheme.BORDER_GOLD_SOFT, 0.25)
	vbox.add_child(rule)

	var effect_heading := Label.new()
	effect_heading.text = LocaleManager.t("upgrade.effect.result", "강화 결과") if _display_only_mode else LocaleManager.t("upgrade.effect.next", "다음 단계")
	effect_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	NavalUiTheme.style_overlay_caption(effect_heading, _effect_heading_font_size_px, color.lerp(NavalUiTheme.TEXT_ACCENT, 0.35), 1)
	vbox.add_child(effect_heading)

	vbox.add_child(_create_effect_list(upgrade_id, next_lv, data, color))

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 10.0)
	vbox.add_child(spacer)

	card.set_meta("art_frame", art_frame)
	card.set_meta("track_badge", meta_row.get_child(0))
	
	if not _display_only_mode:
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_choice_pressed(upgrade_id)
		)
		card.mouse_entered.connect(func():
			var idx = card_ids.find(upgrade_id)
			if idx != -1:
				_focused_index = idx
				_update_focus()
		)
	
	return card


func _create_card_art_frame(upgrade_id: String, data: Dictionary, color: Color) -> PanelContainer:
	var art_frame := PanelContainer.new()
	art_frame.custom_minimum_size = Vector2(_card_art_size_px, _card_art_size_px)
	art_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art_frame.clip_contents = true
	art_frame.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_emblem_frame_style(color)
	)

	var art_path := str(data.get("card_art_path", "")).strip_edges()
	if not art_path.is_empty() and ResourceLoader.exists(art_path):
		var texture := ResourceLoader.load(art_path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if texture != null:
			var art := TextureRect.new()
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.texture = texture
			art.expand_mode = 1
			art.stretch_mode = 6
			art.material = _make_rounded_card_art_material(
				Vector2(_card_art_size_px, _card_art_size_px),
				_card_art_corner_radius_px
			)
			art_frame.add_child(art)
			_attach_art_sheen(art_frame)
			return art_frame

	var placeholder := CenterContainer.new()
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_frame.add_child(placeholder)

	var placeholder_inner := PanelContainer.new()
	placeholder_inner.custom_minimum_size = Vector2(_card_art_size_px - 18.0, _card_art_size_px - 18.0)
	placeholder_inner.add_theme_stylebox_override("panel", NavalUiTheme.make_emblem_plate_style(color))
	placeholder.add_child(placeholder_inner)

	var icon_wrap := CenterContainer.new()
	icon_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder_inner.add_child(icon_wrap)

	var icon := Label.new()
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.apply_emblem(icon, upgrade_id, _card_placeholder_icon_size_px, color.lerp(NavalUiTheme.TEXT_ACCENT, 0.48))
	icon_wrap.add_child(icon)
	_attach_art_sheen(art_frame)

	return art_frame


func _make_rounded_card_art_material(rect_size: Vector2, corner_radius: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 rect_size = vec2(156.0, 156.0);
uniform float corner_radius_px = 12.0;
uniform float softness_px = 1.25;

float rounded_rect_alpha(vec2 uv) {
	vec2 size = max(rect_size, vec2(1.0));
	float radius = min(corner_radius_px, min(size.x, size.y) * 0.5);
	vec2 half_size = size * 0.5;
	vec2 point = uv * size;
	vec2 delta = abs(point - half_size) - (half_size - vec2(radius));
	float distance = length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0) - radius;
	return 1.0 - smoothstep(0.0, softness_px, distance);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float inherited_alpha = COLOR.a;
	COLOR = vec4(tex.rgb, tex.a * inherited_alpha * rounded_rect_alpha(UV));
}
"""
	material.shader = shader
	material.set_shader_parameter("rect_size", rect_size)
	material.set_shader_parameter("corner_radius_px", corner_radius)
	return material


func _on_choice_pressed(upgrade_id: String) -> void:
	if card_ids.is_empty(): return
	var chosen_id := upgrade_id
	var choice_ids := card_ids.duplicate()
	var chosen_index := choice_ids.find(chosen_id)
	card_ids.clear() # 두 번 눌리는 것 방지
	_input_lock_timer = 0.35
	
	UiButtonAudio.play_upgrade_select()

	_play_choice_selection_animation(chosen_id, choice_ids, chosen_index)


func _play_choice_selection_animation(chosen_id: String, choice_ids: Array, chosen_index: int) -> void:
	if chosen_index < 0:
		_finish_choice_selection(chosen_id)
		return

	var tween := _create_ui_tween()
	tween.set_parallel(true)
	for i in range(card_buttons.size()):
		var card_value = card_buttons[i]
		if not is_instance_valid(card_value) or not (card_value is PanelContainer):
			continue
		var card := card_value as PanelContainer
		var selected := i == chosen_index
		_apply_choice_card_style(card, str(choice_ids[i]), selected)
		if selected:
			tween.tween_property(card, "modulate", Color(1.22, 1.15, 0.92, 1.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			tween.tween_property(card, "modulate:a", 0.22, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var footer_button := _get_visible_footer_button()
	if footer_button:
		tween.tween_property(footer_button, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(background, "modulate:a", 0.0, CARD_CHOICE_FADE_DURATION).set_delay(CARD_CHOICE_FADE_DELAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property($VBox, "modulate:a", 0.0, CARD_CHOICE_FADE_DURATION).set_delay(CARD_CHOICE_FADE_DELAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_finish_choice_selection.bind(chosen_id), CONNECT_ONE_SHOT)


func _create_ui_tween() -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _apply_choice_card_style(card: PanelContainer, upgrade_id: String, selected: bool) -> void:
	if not is_instance_valid(card) or upgrade_id not in UpgradeManager.UPGRADES:
		return
	var color: Color = UpgradeManager.UPGRADES[upgrade_id].get("color", Color.WHITE)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		if selected:
			style.bg_color = Color(0.105, 0.16, 0.22, 0.99)
			style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.82).lightened(0.12)
			style.shadow_size = 22
			style.shadow_color = Color(color.r, color.g, color.b, 0.26)
		else:
			style.bg_color = Color(0.035, 0.055, 0.075, 0.86)
			style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.18)
			style.shadow_size = 4
			style.shadow_color = Color(0.0, 0.0, 0.0, 0.16)
	if selected:
		_play_card_focus_sheen(card)


func _finish_choice_selection(chosen_id: String) -> void:
	visible = false
	upgrade_chosen.emit(chosen_id)


func _on_card_hover(card: PanelContainer, style: StyleBoxFlat, color: Color) -> void:
	style.bg_color = Color(0.09, 0.14, 0.20, 0.98)
	style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.62).lightened(0.08)
	style.shadow_size = 14
	var tween = create_tween()
	tween.tween_property(card, "scale", Vector2(1.035, 1.035), 0.1)


func _on_card_unhover(card: PanelContainer, style: StyleBoxFlat, color: Color) -> void:
	style.bg_color = Color(0.055, 0.085, 0.125, 0.96)
	style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.35)
	style.shadow_size = 10
	var tween = create_tween()
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1)


func _update_reroll_button(count: int) -> void:
	if not reroll_button:
		reroll_button = Button.new()
		reroll_button.custom_minimum_size = Vector2(_reroll_width_px, _reroll_height_px)
		reroll_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		NavalUiTheme.apply_hud_button(reroll_button, roundi(lerpf(15.0, 16.0, clampf((get_viewport().get_visible_rect().size.y - 700.0) / 220.0, 0.0, 1.0))))
		UiButtonAudio.wire_button(reroll_button, -4.0, 1.1)
		reroll_button.pressed.connect(_on_reroll_pressed)
		
		# 마우스 호버 지원
		reroll_button.mouse_entered.connect(func():
			_reroll_focused = true
			_update_focus()
		)
		
		footer_row.add_child(reroll_button)
	
	reroll_button.text = LocaleManager.t("upgrade.reroll_count", "다시 고르기 {count}회", {"count": count}) if count > 0 else LocaleManager.t("upgrade.reroll", "다시 고르기")
	reroll_button.disabled = count <= 0
	reroll_button.visible = true
	if reroll_button.disabled:
		_reroll_focused = false


func _on_reroll_pressed() -> void:
	reroll_requested.emit()


func _create_track_badge(track_label: String, color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.add_theme_stylebox_override(
		"panel",
		NavalUiTheme.make_panel_style(
			Color(color.r, color.g, color.b, 0.10),
			color.lerp(NavalUiTheme.BORDER_GOLD_SOFT, 0.12),
			9,
			1,
			10.0,
			4.0,
			10.0,
			4.0
		)
	)
	var label := Label.new()
	label.text = track_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_overlay_caption(label, _track_badge_font_size_px, color.lerp(NavalUiTheme.TEXT_ACCENT, 0.28), 1)
	badge.add_child(label)
	return badge


func _create_effect_list(upgrade_id: String, next_level: int, data: Dictionary, color: Color) -> VBoxContainer:
	var effect_box := VBoxContainer.new()
	effect_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_box.add_theme_constant_override("separation", 4)
	var lines: Array[String] = _build_card_effect_lines(upgrade_id, next_level, data.get("stats", {}))
	if lines.is_empty():
		var fallback_text := str(UpgradeManager.get_next_description(upgrade_id)).strip_edges()
		if not fallback_text.is_empty():
			lines.append(fallback_text)
	for line_text in lines:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bullet := Label.new()
		bullet.text = "•"
		NavalUiTheme.style_accent(bullet, _effect_body_font_size_px)
		bullet.add_theme_color_override("font_color", color.lerp(NavalUiTheme.TEXT_ACCENT, 0.25))
		row.add_child(bullet)
		var line_label := Label.new()
		line_label.text = line_text
		line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		NavalUiTheme.style_body(line_label, _effect_body_font_size_px)
		row.add_child(line_label)
		effect_box.add_child(row)
	return effect_box


func _build_card_effect_lines(upgrade_id: String, next_level: int, stats: Dictionary) -> Array[String]:
	var spec_text := HudUpgradeInfoHelper.build_upgrade_spec_text(upgrade_id, next_level, stats)
	if spec_text.is_empty():
		return []
	var normalized := spec_text.replace("\n", " | ")
	var raw_parts := normalized.split("|")
	var lines: Array[String] = []
	for raw_part in raw_parts:
		var line := str(raw_part).strip_edges()
		if line.is_empty():
			continue
		lines.append(line)
	return lines


func _apply_background_fx() -> void:
	if not is_instance_valid(background):
		return
	background.material = UiOverlayFx.make_vignette_material(
		Color(0.02, 0.03, 0.05, 0.86),
		Vector2(0.5, 0.46),
		0.72,
		0.34,
		0.16,
		0.26,
		Vector3(0.035, 0.04, 0.03)
	)


func _prepare_treasure_reward_fx() -> void:
	var shimmer := _ensure_treasure_shimmer()
	if not is_instance_valid(shimmer):
		return
	shimmer.visible = true
	shimmer.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(shimmer, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(shimmer, "scale", Vector2.ONE, 0.28).from(Vector2(1.08, 1.08)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _ensure_treasure_shimmer() -> ColorRect:
	if is_instance_valid(_treasure_shimmer):
		return _treasure_shimmer
	_treasure_shimmer = ColorRect.new()
	_treasure_shimmer.name = "TreasureShimmer"
	_treasure_shimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_treasure_shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_treasure_shimmer.color = Color.WHITE
	_treasure_shimmer.material = _make_treasure_shimmer_material()
	add_child(_treasure_shimmer)
	move_child(_treasure_shimmer, mini(background.get_index() + 1, get_child_count() - 1))
	return _treasure_shimmer


func _make_treasure_shimmer_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded, blend_add;

void fragment() {
	vec2 centered = UV - vec2(0.5, 0.46);
	float dist = length(centered);
	float pulse = 0.92 + sin(TIME * 1.6) * 0.08;
	float halo = smoothstep(0.62, 0.08, dist) * 0.13 * pulse;
	float ring = smoothstep(0.055, 0.0, abs(dist - 0.29)) * 0.038;
	float angle = atan(centered.y, centered.x);
	float ray_a = pow(max(0.0, sin(angle * 8.0 + TIME * 0.7)), 12.0);
	float ray_b = pow(max(0.0, sin(angle * 5.0 - TIME * 0.45)), 10.0);
	float rays = (ray_a * 0.026 + ray_b * 0.018) * smoothstep(0.58, 0.16, dist);
	float sweep = smoothstep(0.02, 0.0, abs((UV.x + UV.y * 0.35) - (0.28 + sin(TIME * 0.9) * 0.035))) * 0.026;
	float alpha = halo + ring + rays + sweep;
	vec3 color = mix(vec3(1.0, 0.68, 0.20), vec3(1.0, 0.95, 0.64), smoothstep(0.0, 0.18, alpha));
	COLOR = vec4(color * alpha, alpha);
}
"""
	material.shader = shader
	return material


func _apply_reward_card_style(card: PanelContainer, style: StyleBoxFlat, color: Color) -> void:
	card.set_meta("reward_highlight", true)
	style.bg_color = Color(0.075, 0.105, 0.135, 0.98)
	style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.72).lightened(0.08)
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_width_left = 3
	style.border_width_right = 3
	style.shadow_size = 20
	style.shadow_color = Color(color.r, color.g, color.b, 0.22)


func _attach_art_sheen(art_frame: PanelContainer) -> void:
	if not is_instance_valid(art_frame) or art_frame.has_meta("art_sheen"):
		return
	var sheen := ColorRect.new()
	sheen.name = "ArtSheen"
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.color = Color.WHITE
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float sweep = -0.45;
uniform float width = 0.16;
uniform float intensity = 0.0;
uniform vec2 rect_size = vec2(156.0, 156.0);
uniform float corner_radius_px = 12.0;
uniform float softness_px = 1.25;

float rounded_rect_alpha(vec2 uv) {
	vec2 size = max(rect_size, vec2(1.0));
	float radius = min(corner_radius_px, min(size.x, size.y) * 0.5);
	vec2 half_size = size * 0.5;
	vec2 point = uv * size;
	vec2 delta = abs(point - half_size) - (half_size - vec2(radius));
	float distance = length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0) - radius;
	return 1.0 - smoothstep(0.0, softness_px, distance);
}

void fragment() {
	float diagonal = UV.x + UV.y * 0.72;
	float band = smoothstep(sweep - width, sweep, diagonal) * (1.0 - smoothstep(sweep, sweep + width, diagonal));
	float alpha = band * intensity * rounded_rect_alpha(UV);
	vec3 tint = vec3(1.0, 0.96, 0.84) * alpha;
	COLOR = vec4(tint, alpha);
}
"""
	material.shader = shader
	material.set_shader_parameter("sweep", -0.45)
	material.set_shader_parameter("width", 0.16)
	material.set_shader_parameter("intensity", 0.0)
	material.set_shader_parameter("rect_size", Vector2(_card_art_size_px, _card_art_size_px))
	material.set_shader_parameter("corner_radius_px", _card_art_corner_radius_px)
	sheen.material = material
	art_frame.add_child(sheen)
	art_frame.set_meta("art_sheen", sheen)


func _play_card_focus_sheen(card: PanelContainer, peak_intensity: float = 0.22, duration: float = CARD_SHEEN_DURATION) -> void:
	if not is_instance_valid(card):
		return
	var art_frame_value = card.get_meta("art_frame", null)
	if not is_instance_valid(art_frame_value) or not (art_frame_value is PanelContainer):
		return
	var art_frame := art_frame_value as PanelContainer
	var sheen_value = art_frame.get_meta("art_sheen", null)
	if not is_instance_valid(sheen_value) or not (sheen_value is ColorRect):
		return
	var sheen := sheen_value as ColorRect
	var sheen_material := sheen.material as ShaderMaterial
	if sheen_material == null:
		return
	sheen_material.set_shader_parameter("sweep", -0.35)
	sheen_material.set_shader_parameter("intensity", 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(func(v: float): sheen_material.set_shader_parameter("sweep", v), -0.35, 1.4, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float): sheen_material.set_shader_parameter("intensity", v), 0.0, peak_intensity, 0.14)
	tween.chain()
	tween.tween_method(func(v: float): sheen_material.set_shader_parameter("intensity", v), peak_intensity, 0.0, 0.18)


func _prepare_entry_animation() -> void:
	for i in range(card_buttons.size()):
		var card = card_buttons[i]
		if not is_instance_valid(card):
			continue
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		if _display_only_mode:
			card.scale = Vector2(REWARD_CARD_ENTRY_SCALE, REWARD_CARD_ENTRY_SCALE)
			card.position.y = REWARD_CARD_ENTRY_Y_OFFSET
			card.rotation = deg_to_rad(lerpf(-2.4, 2.4, float(i) / maxf(float(card_buttons.size() - 1), 1.0)))
		else:
			card.scale = Vector2(CARD_ENTRY_SCALE, CARD_ENTRY_SCALE)
			card.position.y = CARD_ENTRY_Y_OFFSET
	var footer_button := _get_visible_footer_button()
	if footer_button:
		footer_button.pivot_offset = footer_button.custom_minimum_size * 0.5
		footer_button.modulate = Color(1.0, 1.0, 1.0, 0.0)
		footer_button.scale = Vector2(0.96, 0.96)


func _animate_cards_in() -> void:
	if _display_only_mode:
		_animate_reward_cards_in()
		return
	for i in range(card_buttons.size()):
		var card = card_buttons[i]
		if not is_instance_valid(card):
			continue
		var target_scale := Vector2(CARD_FOCUS_SCALE, CARD_FOCUS_SCALE) if i == _focused_index else Vector2.ONE
		var target_y := CARD_FOCUS_LIFT_Y if i == _focused_index else 0.0
		var tween := create_tween()
		tween.tween_interval(CARD_ENTRY_DELAY * float(i))
		tween.set_parallel(true)
		tween.tween_property(card, "modulate:a", 1.0, CARD_ENTRY_DURATION)
		tween.tween_property(card, "scale", target_scale, CARD_ENTRY_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position:y", target_y, CARD_ENTRY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var footer_button := _get_visible_footer_button()
	if footer_button:
		var reroll_tween := create_tween()
		reroll_tween.tween_interval(CARD_ENTRY_DELAY * float(card_buttons.size()) + REROLL_ENTRY_DELAY)
		reroll_tween.set_parallel(true)
		reroll_tween.tween_property(footer_button, "modulate:a", 1.0, 0.18)
		reroll_tween.tween_property(footer_button, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _focused_index >= 0 and _focused_index < card_buttons.size():
		var sheen_tween := create_tween()
		sheen_tween.tween_interval(CARD_ENTRY_DELAY * float(_focused_index) + 0.12)
		sheen_tween.tween_callback(func():
			if _focused_index >= 0 and _focused_index < card_buttons.size():
				var focused_card = card_buttons[_focused_index]
				if is_instance_valid(focused_card) and focused_card is PanelContainer:
					_play_card_focus_sheen(focused_card)
		)


func _animate_reward_cards_in() -> void:
	for i in range(card_buttons.size()):
		var card = card_buttons[i]
		if not is_instance_valid(card):
			continue
		var tween := create_tween()
		tween.tween_interval(REWARD_CARD_ENTRY_DELAY * float(i))
		tween.set_parallel(true)
		tween.tween_property(card, "modulate:a", 1.0, REWARD_CARD_ENTRY_DURATION * 0.72)
		tween.tween_property(card, "scale", Vector2(REWARD_CARD_POP_SCALE, REWARD_CARD_POP_SCALE), REWARD_CARD_ENTRY_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position:y", -4.0, REWARD_CARD_ENTRY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation", 0.0, REWARD_CARD_ENTRY_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain()
		tween.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var sheen_tween := create_tween()
		sheen_tween.tween_interval(REWARD_CARD_ENTRY_DELAY * float(i) + 0.16)
		sheen_tween.tween_callback(func():
			if is_instance_valid(card) and card is PanelContainer:
				_play_card_focus_sheen(card, 0.34, 0.58)
		)
	var footer_button := _get_visible_footer_button()
	if footer_button:
		var footer_tween := create_tween()
		footer_tween.tween_interval(REWARD_CARD_ENTRY_DELAY * float(card_buttons.size()) + 0.12)
		footer_tween.set_parallel(true)
		footer_tween.tween_property(footer_button, "modulate:a", 1.0, 0.18)
		footer_tween.tween_property(footer_button, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_reward_title_pulse() -> void:
	if not is_instance_valid(title_label):
		return
	title_label.pivot_offset = title_label.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(title_label, "scale", Vector2(1.08, 1.08), 0.18).from(Vector2(0.95, 0.95)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(title_label, "modulate", Color(1.25, 1.12, 0.78, 1.0), 0.16).from(Color(1.0, 1.0, 1.0, 0.0))
	tween.chain()
	tween.tween_property(title_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(title_label, "modulate", Color.WHITE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _get_visible_footer_button() -> Button:
	if is_instance_valid(_display_confirm_button) and _display_confirm_button.visible:
		return _display_confirm_button
	if is_instance_valid(reroll_button) and reroll_button.visible:
		return reroll_button
	return null


func _apply_card_focus_visuals(card: PanelContainer, color: Color, focused: bool, immediate: bool) -> void:
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		if focused:
			style.bg_color = Color(0.09, 0.14, 0.20, 0.98)
			style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.62).lightened(0.08)
			style.shadow_size = 16
			style.shadow_color = Color(color.r, color.g, color.b, 0.18)
		else:
			style.bg_color = Color(0.055, 0.085, 0.125, 0.96)
			style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.35)
			style.shadow_size = 10
			style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)

	var target_scale := Vector2(CARD_FOCUS_SCALE, CARD_FOCUS_SCALE) if focused else Vector2.ONE
	var target_y := CARD_FOCUS_LIFT_Y if focused else 0.0
	if immediate:
		card.scale = target_scale
		card.position.y = target_y
	else:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "scale", target_scale, 0.12)
		tween.tween_property(card, "position:y", target_y, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var art_frame_value = card.get_meta("art_frame", null)
	if is_instance_valid(art_frame_value) and art_frame_value is PanelContainer:
		var art_frame := art_frame_value as PanelContainer
		art_frame.self_modulate = Color.WHITE
		var art_style := art_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if art_style != null:
			art_style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD, 0.52 if focused else 0.34)
			art_style.shadow_size = 10 if focused else 0
			art_style.shadow_color = Color(color.r, color.g, color.b, 0.14)
		var sheen_value = art_frame.get_meta("art_sheen", null)
		if is_instance_valid(sheen_value) and sheen_value is ColorRect:
			var sheen := sheen_value as ColorRect
			var sheen_material := sheen.material as ShaderMaterial
			if sheen_material != null and not focused:
				sheen_material.set_shader_parameter("intensity", 0.0)

	var track_badge_value = card.get_meta("track_badge", null)
	if is_instance_valid(track_badge_value) and track_badge_value is PanelContainer:
		var track_badge := track_badge_value as PanelContainer
		var badge_style := track_badge.get_theme_stylebox("panel") as StyleBoxFlat
		if badge_style != null:
			badge_style.bg_color = Color(color.r, color.g, color.b, 0.16 if focused else 0.10)
			badge_style.border_color = color.lerp(NavalUiTheme.BORDER_GOLD_SOFT, 0.20 if focused else 0.12)
	if focused and not immediate:
		_play_card_focus_sheen(card)


func _is_prev_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_left") or _is_physical_key_pressed(event, KEY_A)


func _is_next_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_right") or _is_physical_key_pressed(event, KEY_D)


func _is_up_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or _is_physical_key_pressed(event, KEY_W)


func _is_down_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_down") or _is_physical_key_pressed(event, KEY_S)


func _is_confirm_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or _is_keycode_pressed(event, KEY_SPACE) or _is_keycode_pressed(event, KEY_ENTER) or _is_keycode_pressed(event, KEY_KP_ENTER)


func _is_physical_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keycode


func _is_keycode_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
