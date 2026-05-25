extends Control


const GAME_SCENE_PATH := "res://scenes/main.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const MenuInputHelper = preload("res://scripts/ui/menu_input_helper.gd")
const UiButtonAudio = preload("res://scripts/ui/ui_button_audio.gd")
const UiOverlayFx = preload("res://scripts/ui/ui_overlay_fx.gd")
const ModalMenuSkin = preload("res://scripts/ui/menus/modal_menu_skin.gd")
const ShipDefeatIllustration = preload("res://scripts/ui/results/ship_defeat_illustration.gd")
const WEAPON_ICON_TEXTURE_PATHS := {
	"cannon": "res://assets/ui/upgrades/cannon_card.png",
	"janggun": "res://assets/ui/upgrades/janggun_card.png",
	"singigeon": "res://assets/ui/upgrades/singigeon_card.png",
	"bow": "res://assets/ui/support_fleet/support_fleet_bow_icon.png",
	"repeating_crossbow": "res://assets/ui/upgrades/crew_defense_card.png",
	"ballista": "res://assets/ui/upgrades/crew_defense_card.png",
	"sword": "res://assets/ui/upgrades/boarding_resist_card.png",
	"spear": "res://assets/ui/upgrades/jangchang_card.png",
	"trident": "res://assets/ui/upgrades/jangchang_card.png",
	"harpoon": "res://assets/ui/upgrades/jangchang_card.png",
	"crew_numbers": "res://assets/ui/upgrades/jangchang_card.png",
	"boarding_defense": "res://assets/ui/upgrades/boarding_resist_card.png",
	"fire_pot": "res://assets/ui/upgrades/janggun_card.png",
	"ramming": "res://assets/ui/support_fleet/support_fleet_maengseon_icon.png",
	"ramming_aoe": "res://assets/ui/support_fleet/support_fleet_maengseon_icon.png",
	"leak": "res://assets/ui/upgrades/sail_card.png",
	"rock": "res://assets/ui/upgrades/geobukseon_upgrade_card.png",
	"fire": "res://assets/ui/upgrades/janggun_card.png",
}
const SHIP_DEFEAT_TEXTURE_PATHS := {
	"kobayabune": "res://assets/ui/results/ships/kobayabune.png",
	"sekibune": "res://assets/ui/results/ships/sekibune.png",
	"sekibune_cannon": "res://assets/ui/results/ships/sekibune.png",
	"atakebune": "res://assets/ui/results/ships/atakebune.png",
	"atakebune_final": "res://assets/ui/results/ships/atakebune.png",
}
const RESULT_CARD_PLACE_DELAY: float = 0.16
const RESULT_CARD_SCORE_DELAY: float = 0.08
const RESULT_CARD_SCORE_DURATION: float = 0.55
const RESULT_CARD_DEFAULT_SINK_SCORE: int = 25
const RESULT_CARD_CAPTURE_SCORE: int = 25
const RESULT_CARD_PARTICLE_COUNT: int = 12
const RESULT_CARD_SINK_SCORE_BY_TYPE := {
	"atakebune": 120,
	"atakebune_final": 120,
}

@export var background_texture: Texture2D

@onready var background_image: TextureRect = $BackgroundImage
@onready var background_tint: ColorRect = $BackgroundTint
@onready var content: VBoxContainer = $Content
@onready var title_block: VBoxContainer = $Content/TitleBlock
@onready var title_label: Label = $Content/TitleBlock/Title
@onready var subtitle_label: Label = $Content/TitleBlock/Subtitle
@onready var body: HBoxContainer = $Content/Body
@onready var summary_panel: PanelContainer = $Content/Body/SummaryPanel
@onready var summary_margin: MarginContainer = $Content/Body/SummaryPanel/Margin
@onready var summary_list: VBoxContainer = $Content/Body/SummaryPanel/Margin/SummaryList
@onready var weapon_panel: PanelContainer = $Content/Body/WeaponPanel
@onready var weapon_margin: MarginContainer = $Content/Body/WeaponPanel/Margin
@onready var weapon_list: VBoxContainer = $Content/Body/WeaponPanel/Margin/WeaponList
@onready var button_block: HBoxContainer = $ButtonBlock
@onready var restart_button: Button = $ButtonBlock/RestartButton
@onready var main_menu_button: Button = $ButtonBlock/MainMenuButton

var _summary_font_size: int = 18
var _subtitle_font_size: int = 18
var _title_font_size: int = 50
var _button_font_size: int = 18
var _weapon_value_width: float = 120.0
var _weapon_icon_size: int = 42
var _ship_card_height: int = 72
var _ship_result_card_width: int = 150
var _ship_result_card_height: int = 214
var _ship_result_art_height: int = 84
var _ship_illustration_width: int = 94
var _last_result: Dictionary = {}
var _action_buttons: Array[Button] = []
var _focused_button_index: int = 0
var _weapon_icon_cache: Dictionary = {}
var _ship_defeat_texture_cache: Dictionary = {}
var _nav_repeater := MenuInputHelper.NavRepeater.new()
var _button_focus := MenuInputHelper.ButtonFocusNavigator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	get_tree().paused = false
	_apply_background()
	_apply_theme()
	_apply_layout_density()
	_render_result(RunResultStore.get_latest_result())
	UiButtonAudio.wire_buttons(self)
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_action_buttons = [restart_button, main_menu_button]
	_button_focus.configure(_action_buttons, _on_action_button_focus_changed)
	call_deferred("_focus_first_action_button")
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func _input(event: InputEvent) -> void:
	var nav := _nav_repeater.consume_event(event)
	if nav.x != 0 or nav.y != 0:
		_move_action_focus(-1 if nav.x < 0 or nav.y < 0 else 1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return
	if MenuInputHelper.is_navigation_axis_event(event):
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return

	if _is_prev_event(event):
		_move_action_focus(-1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_next_event(event):
		_move_action_focus(1)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		_activate_focused_action()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
	elif MenuInputHelper.is_cancel_event(event):
		_on_main_menu_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func _apply_background() -> void:
	if is_instance_valid(background_image):
		background_image.texture = background_texture
		background_image.visible = background_texture != null
	if is_instance_valid(background_tint):
		background_tint.color = Color.WHITE
		background_tint.material = UiOverlayFx.make_vignette_material(
			Color(0.02, 0.035, 0.055, 0.56),
			Vector2(0.5, 0.42),
			0.82,
			0.38,
			0.14,
			0.18,
			Vector3(0.035, 0.03, 0.015)
		)


func _on_action_button_focus_changed(button: Button, _focused: bool) -> void:
	_focused_button_index = _button_focus.get_focused_index()


func _focus_first_action_button() -> void:
	_button_focus.focus_first()
	_focused_button_index = _button_focus.get_focused_index()


func _move_action_focus(direction: int) -> void:
	_button_focus.move_focus(direction)
	_focused_button_index = _button_focus.get_focused_index()


func _activate_focused_action() -> void:
	_button_focus.activate_focused()


func _apply_theme() -> void:
	ModalMenuSkin.apply_modal_section_panel(summary_panel)
	ModalMenuSkin.apply_modal_section_panel(weapon_panel)
	NavalUiTheme.style_caption(subtitle_label, _subtitle_font_size, NavalUiTheme.TEXT_ACCENT)
	if is_instance_valid(title_label):
		NavalUiTheme.style_display_title(title_label, _title_font_size)
	for button in [restart_button, main_menu_button]:
		ModalMenuSkin.apply_action_button_theme(button, button == restart_button)


func _apply_layout_density() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var width_fit: float = clampf((viewport_size.x - 980.0) / 440.0, 0.0, 1.0)
	var height_fit: float = clampf((viewport_size.y - 720.0) / 260.0, 0.0, 1.0)
	var density: float = min(width_fit, height_fit)
	_summary_font_size = roundi(lerpf(15.0, 18.0, density))
	_subtitle_font_size = roundi(lerpf(15.0, 18.0, density))
	_title_font_size = roundi(lerpf(38.0, 50.0, density))
	_button_font_size = roundi(lerpf(16.0, 18.0, density))
	_weapon_value_width = roundf(lerpf(96.0, 120.0, density))
	_weapon_icon_size = roundi(lerpf(34.0, 42.0, density))
	_ship_card_height = roundi(lerpf(74.0, 94.0, density))
	_ship_result_card_width = roundi(clampf(viewport_size.x * 0.13, 132.0, 178.0))
	_ship_result_card_height = roundi(float(_ship_result_card_width) * 1.42)
	_ship_result_art_height = roundi(float(_ship_result_card_width) * 0.56)
	_ship_illustration_width = roundi(float(_ship_result_card_width) - 24.0)
	if is_instance_valid(content):
		var half_width := roundi(clampf(viewport_size.x * 0.44, 430.0, 700.0))
		content.offset_left = -half_width
		content.offset_right = half_width
		content.anchor_top = 0.045
		content.anchor_bottom = 0.86
		content.add_theme_constant_override("separation", roundi(lerpf(12.0, 16.0, density)))
	if is_instance_valid(title_block):
		title_block.add_theme_constant_override("separation", roundi(lerpf(6.0, 8.0, density)))
	if is_instance_valid(body):
		body.add_theme_constant_override("separation", roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(summary_margin):
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			summary_margin.add_theme_constant_override(side, roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(weapon_margin):
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			weapon_margin.add_theme_constant_override(side, roundi(lerpf(14.0, 18.0, density)))
	if is_instance_valid(summary_list):
		summary_list.add_theme_constant_override("separation", roundi(lerpf(9.0, 12.0, density)))
	if is_instance_valid(weapon_list):
		weapon_list.add_theme_constant_override("separation", roundi(lerpf(9.0, 12.0, density)))
	if is_instance_valid(button_block):
		var button_width := roundi(clampf(viewport_size.x * 0.17, 180.0, 220.0))
		button_block.offset_left = -button_width - 18.0
		button_block.offset_right = button_width + 18.0
		button_block.offset_top = roundi(lerpf(-62.0, -70.0, density))
		button_block.offset_bottom = -22.0
		button_block.add_theme_constant_override("separation", roundi(lerpf(10.0, 14.0, density)))
	for button in [restart_button, main_menu_button]:
		if not is_instance_valid(button):
			continue
		button.custom_minimum_size = Vector2(roundi(clampf(viewport_size.x * 0.17, 180.0, 220.0)), roundi(lerpf(42.0, 48.0, density)))
		button.add_theme_font_size_override("font_size", _button_font_size)
	_apply_theme()


func _on_viewport_size_changed() -> void:
	_apply_layout_density()
	if not _last_result.is_empty():
		_render_result(_last_result)


func _render_result(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	var outcome_text := str(result.get("outcome", "")).strip_edges()
	title_label.text = _get_result_title(result)
	subtitle_label.text = outcome_text
	subtitle_label.visible = not outcome_text.is_empty()
	if is_instance_valid(summary_panel):
		summary_panel.visible = false
	if is_instance_valid(body):
		body.alignment = BoxContainer.ALIGNMENT_CENTER
	if is_instance_valid(weapon_panel):
		weapon_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_clear_children(summary_list)
	_clear_children(weapon_list)

	var survived_seconds: float = float(result.get("survived_seconds", 0.0))
	_add_summary_row(LocaleManager.t("result.summary.survived", "생존 시간"), _format_time(survived_seconds))
	_add_summary_row(LocaleManager.t("result.summary.gold", "획득 포인트"), "%d P" % int(result.get("gold", 0)))
	_add_summary_row(LocaleManager.t("result.summary.level", "도달 레벨"), "Lv.%d" % int(result.get("level", 1)))
	_add_summary_row(LocaleManager.t("result.summary.sunk", "격침"), LocaleManager.t("result.value.ships", "{count}척", {"count": int(result.get("ships_sunk", 0))}))
	_add_summary_row(LocaleManager.t("result.summary.captured", "나포"), LocaleManager.t("result.value.ships", "{count}척", {"count": int(result.get("ships_derelicted", 0))}))
	_add_summary_row(LocaleManager.t("result.summary.enemy_soldiers", "적 병사"), LocaleManager.t("result.value.soldiers", "{count}명", {"count": int(result.get("soldiers_killed", 0))}))
	_add_summary_row(LocaleManager.t("result.summary.crew_alive", "아군 생존"), "%d / %d" % [int(result.get("crew_alive", 0)), int(result.get("crew_capacity", 0))])

	_add_ship_defeat_header()
	var ship_rows: Array = result.get("defeated_ship_rows", [])
	if ship_rows.is_empty():
		_add_ship_defeat_empty_row()
	else:
		_add_ship_defeat_cards(ship_rows)


func _get_result_title(result: Dictionary) -> String:
	return str(result.get("title", LocaleManager.t("result.title", "결과")))


func _add_summary_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	summary_list.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_muted(label, _summary_font_size)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_gold(value, _summary_font_size)
	row.add_child(value)


func _add_weapon_row(row_data: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", roundi(maxf(10.0, _weapon_icon_size * 0.34)))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	weapon_list.add_child(row)

	var source_id := str(row_data.get("id", ""))
	row.add_child(_create_weapon_icon(source_id))

	var name_label := Label.new()
	name_label.text = str(row_data.get("name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(name_label, _summary_font_size)
	row.add_child(name_label)

	var damage_label := Label.new()
	damage_label.text = "%.0f" % float(row_data.get("damage", 0.0))
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	damage_label.custom_minimum_size = Vector2(_weapon_value_width, 0.0)
	NavalUiTheme.style_gold(damage_label, _summary_font_size)
	row.add_child(damage_label)


func _create_weapon_icon(source_id: String) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(_weapon_icon_size, _weapon_icon_size)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", _make_weapon_icon_frame_style())

	var texture := _get_weapon_icon_texture(source_id)
	if texture != null:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(_weapon_icon_size, _weapon_icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.texture = texture
		frame.add_child(icon)
		return frame

	var fallback := Label.new()
	fallback.custom_minimum_size = Vector2(_weapon_icon_size, _weapon_icon_size)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.apply_emblem(fallback, source_id, roundi(_weapon_icon_size * 0.43), NavalUiTheme.TEXT_ACCENT)
	frame.add_child(fallback)
	return frame


func _get_weapon_icon_texture(source_id: String) -> Texture2D:
	var normalized := source_id.strip_edges()
	if normalized.is_empty():
		return null
	if _weapon_icon_cache.has(normalized):
		return _weapon_icon_cache[normalized] as Texture2D
	var texture: Texture2D = null
	var path := str(WEAPON_ICON_TEXTURE_PATHS.get(normalized, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_weapon_icon_cache[normalized] = texture
	return texture


func _make_weapon_icon_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.08, 0.72)
	style.border_color = Color(NavalUiTheme.BORDER_GOLD_SOFT.r, NavalUiTheme.BORDER_GOLD_SOFT.g, NavalUiTheme.BORDER_GOLD_SOFT.b, 0.58)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _add_weapon_empty_row() -> void:
	var label := Label.new()
	label.text = LocaleManager.t("result.weapon_damage.empty", "기록된 무기 피해 없음")
	NavalUiTheme.style_muted(label, _summary_font_size)
	weapon_list.add_child(label)


func _add_ship_defeat_header() -> void:
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 10)
	weapon_list.add_child(header)

	var title := Label.new()
	title.text = LocaleManager.t("result.ship_defeats.title", "격파 함선")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(title, _summary_font_size + 1)
	header.add_child(title)

	var caption := Label.new()
	caption.text = LocaleManager.t("result.ship_defeats.caption", "일본 함선별 전과")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	NavalUiTheme.style_muted(caption, max(12, _summary_font_size - 3))
	header.add_child(caption)


func _add_ship_defeat_cards(ship_rows: Array) -> void:
	var valid_rows: Array[Dictionary] = []
	for row in ship_rows:
		if row is Dictionary:
			valid_rows.append(row as Dictionary)
	if valid_rows.is_empty():
		_add_ship_defeat_empty_row()
		return

	var grid := GridContainer.new()
	grid.columns = clampi(valid_rows.size(), 1, 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", roundi(maxf(10.0, float(_ship_result_card_width) * 0.08)))
	grid.add_theme_constant_override("v_separation", roundi(maxf(10.0, float(_ship_result_card_width) * 0.07)))
	weapon_list.add_child(grid)

	for i in range(valid_rows.size()):
		grid.add_child(_create_ship_result_card(valid_rows[i], i))


func _create_ship_result_card(row_data: Dictionary, card_index: int) -> PanelContainer:
	var type_id := str(row_data.get("id", "kobayabune"))
	var sunk: int = int(row_data.get("sunk", 0))
	var derelicted: int = int(row_data.get("derelicted", 0))
	var defeated: int = int(row_data.get("defeated", max(sunk, derelicted)))
	var target_score: int = _get_ship_defeat_score(row_data)
	var accent := _get_ship_type_accent(type_id)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_ship_result_card_width, _ship_result_card_height)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", _make_ship_defeat_card_style(type_id, true))

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", roundi(clampf(float(_ship_result_card_width) * 0.045, 5.0, 9.0)))
	card.add_child(vbox)

	var art_center := CenterContainer.new()
	art_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(art_center)
	art_center.add_child(_create_ship_defeat_art(type_id, _ship_result_art_height))

	var name_label := Label.new()
	name_label.text = _get_ship_type_label(type_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(name_label, max(13, _summary_font_size - 1))
	vbox.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "x%d" % defeated
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	NavalUiTheme.style_gold(count_label, _summary_font_size + 7)
	vbox.add_child(count_label)

	var score_label := Label.new()
	score_label.text = _format_ship_defeat_score(0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_color_override("font_color", accent.lerp(NavalUiTheme.TEXT_ACCENT, 0.45))
	score_label.add_theme_font_override("font", NavalUiTheme.FONT_SEMIBOLD)
	score_label.add_theme_font_size_override("font_size", max(12, _summary_font_size - 2))
	score_label.add_theme_color_override("font_shadow_color", NavalUiTheme.OUTLINE_DARK)
	score_label.add_theme_constant_override("shadow_offset_x", 1)
	score_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(score_label)

	_prepare_ship_defeat_card_intro(card, card_index, score_label, target_score)
	return card


func _prepare_ship_defeat_card_intro(card: Control, card_index: int, score_label: Label, target_score: int) -> void:
	card.modulate.a = 0.0
	card.scale = Vector2(1.12, 1.12)
	card.rotation_degrees = -2.0
	call_deferred("_animate_ship_defeat_card_intro", card, card_index, score_label, target_score)


func _animate_ship_defeat_card_intro(card: Control, card_index: int, score_label: Label, target_score: int) -> void:
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	var delay: float = float(card_index) * RESULT_CARD_PLACE_DELAY
	var tween: Tween = create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		_play_result_card_place_sfx(card_index)
		_spawn_result_card_particles(card)
		_animate_ship_defeat_score(score_label, target_score)
	)
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2(0.96, 0.96), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", 1.2, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(card, "rotation_degrees", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_result_card_place_sfx(card_index: int) -> void:
	if not is_instance_valid(AudioManager):
		return
	var pitch: float = 0.92 + float(card_index % 5) * 0.035
	AudioManager.play_sfx("cannon_reload", null, pitch, -5.0)


func _spawn_result_card_particles(card: Control) -> void:
	if not is_instance_valid(card):
		return
	var origin: Vector2 = card.global_position + Vector2(card.size.x * 0.84, card.size.y * 0.5)
	for i in range(RESULT_CARD_PARTICLE_COUNT):
		var particle := ColorRect.new()
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		particle.color = Color(1.0, randf_range(0.72, 0.92), randf_range(0.28, 0.48), 0.9)
		particle.size = Vector2(randf_range(3.0, 7.0), randf_range(2.0, 5.0))
		particle.position = origin + Vector2(randf_range(-8.0, 8.0), randf_range(-6.0, 6.0))
		particle.rotation = randf_range(-0.5, 0.5)
		particle.z_index = 120
		add_child(particle)

		var drift: Vector2 = Vector2(randf_range(-42.0, 46.0), randf_range(-30.0, 30.0))
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", particle.position + drift, randf_range(0.28, 0.42)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "modulate:a", 0.0, randf_range(0.24, 0.38)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(particle, "scale", Vector2(0.35, 0.35), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.set_parallel(false)
		tween.tween_callback(particle.queue_free)


func _animate_ship_defeat_score(score_label: Label, target_score: int) -> void:
	if not is_instance_valid(score_label):
		return
	var score_tween: Tween = create_tween()
	score_tween.tween_interval(RESULT_CARD_SCORE_DELAY)
	score_tween.tween_method(
		Callable(self, "_set_ship_defeat_score_text").bind(score_label),
		0.0,
		float(maxi(0, target_score)),
		RESULT_CARD_SCORE_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_ship_defeat_score_text(value: float, score_label: Label) -> void:
	if is_instance_valid(score_label):
		score_label.text = _format_ship_defeat_score(roundi(value))


func _get_ship_defeat_score(row_data: Dictionary) -> int:
	var type_id: String = str(row_data.get("id", "")).strip_edges()
	var sink_score: int = int(RESULT_CARD_SINK_SCORE_BY_TYPE.get(type_id, RESULT_CARD_DEFAULT_SINK_SCORE))
	var sunk: int = max(0, int(row_data.get("sunk", 0)))
	var derelicted: int = max(0, int(row_data.get("derelicted", 0)))
	return sunk * sink_score + derelicted * RESULT_CARD_CAPTURE_SCORE


func _format_ship_defeat_score(score: int) -> String:
	return LocaleManager.t("result.ship_defeats.score", "+{score}점", {"score": max(0, score)})


func _create_ship_defeat_art(type_id: String, art_height: int) -> Control:
	var texture := _get_ship_defeat_texture(type_id)
	if texture != null:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(_ship_illustration_width, art_height)
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		frame.add_theme_stylebox_override("panel", _make_ship_defeat_art_frame_style(type_id))

		var art := TextureRect.new()
		art.name = "ShipDefeatTexture"
		art.custom_minimum_size = Vector2(_ship_illustration_width, art_height)
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture = texture
		frame.add_child(art)
		return frame

	var fallback := ShipDefeatIllustration.new()
	fallback.name = "ShipDefeatIllustration"
	fallback.custom_minimum_size = Vector2(_ship_illustration_width, art_height)
	fallback.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fallback.setup(type_id)
	return fallback


func _get_ship_defeat_texture(type_id: String) -> Texture2D:
	var normalized := _normalize_ship_defeat_texture_id(type_id)
	if normalized.is_empty():
		return null
	if _ship_defeat_texture_cache.has(normalized):
		return _ship_defeat_texture_cache[normalized] as Texture2D
	var texture: Texture2D = null
	var path := str(SHIP_DEFEAT_TEXTURE_PATHS.get(normalized, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_ship_defeat_texture_cache[normalized] = texture
	return texture


func _normalize_ship_defeat_texture_id(type_id: String) -> String:
	var normalized := type_id.strip_edges().to_lower()
	if normalized.contains("atake"):
		return "atakebune_final" if normalized.contains("final") else "atakebune"
	if normalized.contains("seki"):
		return "sekibune_cannon" if normalized.contains("cannon") or normalized.contains("gunner") else "sekibune"
	if normalized.contains("kobaya"):
		return "kobayabune"
	return normalized


func _add_ship_defeat_empty_row() -> void:
	var label := Label.new()
	label.text = LocaleManager.t("result.ship_defeats.empty", "격파한 함선 없음")
	NavalUiTheme.style_muted(label, _summary_font_size)
	weapon_list.add_child(label)


func _make_ship_defeat_card_style(type_id: String, card_like: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent := _get_ship_type_accent(type_id)
	style.bg_color = Color(0.045, 0.068, 0.095, 0.94) if card_like else Color(0.035, 0.048, 0.055, 0.72)
	style.border_color = accent.lerp(NavalUiTheme.BORDER_GOLD, 0.34) if card_like else Color(accent.r, accent.g, accent.b, 0.55)
	style.set_border_width_all(2 if card_like else 1)
	style.set_corner_radius_all(12 if card_like else 7)
	var margin: float = roundf(float(_ship_result_card_width) * 0.075) if card_like else 0.0
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	if card_like:
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
		style.shadow_size = 9
	return style


func _make_ship_defeat_art_frame_style(type_id: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var accent := _get_ship_type_accent(type_id)
	style.bg_color = Color(0.02, 0.022, 0.024, 0.74)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.36)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _get_ship_type_accent(type_id: String) -> Color:
	var normalized := type_id.strip_edges().to_lower()
	if normalized.contains("atake"):
		return Color(0.86, 0.56, 0.28, 1.0)
	if normalized.contains("cannon") or normalized.contains("gunner"):
		return Color(0.72, 0.28, 0.24, 1.0)
	if normalized.contains("seki"):
		return Color(0.58, 0.34, 0.24, 1.0)
	return Color(0.72, 0.55, 0.28, 1.0)


func _get_ship_type_label(type_id: String) -> String:
	match type_id.strip_edges().to_lower():
		"kobayabune":
			return LocaleManager.t("result.ship.kobayabune", "고바야부네")
		"sekibune":
			return LocaleManager.t("result.ship.sekibune", "세키부네")
		"sekibune_cannon":
			return LocaleManager.t("result.ship.sekibune_cannon", "대철포 세키부네")
		"atakebune":
			return LocaleManager.t("result.ship.atakebune", "아타케부네")
		"atakebune_final":
			return LocaleManager.t("result.ship.atakebune_final", "대장선 아타케부네")
		_:
			return type_id.capitalize()


func _clear_children(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for child in node.get_children():
		child.queue_free()


func _format_time(seconds: float) -> String:
	var total_seconds: int = max(0, int(seconds))
	return "%02d:%02d" % [int(total_seconds / 60), total_seconds % 60]


func _on_restart_pressed() -> void:
	if is_instance_valid(UpgradeManager) and UpgradeManager.has_method("reset_run_upgrades"):
		UpgradeManager.reset_run_upgrades()
	RunResultStore.clear()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_main_menu_pressed() -> void:
	RunResultStore.clear()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _is_prev_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_any_prev_event(event)


func _is_next_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_any_next_event(event)


func _is_confirm_event(event: InputEvent) -> bool:
	return MenuInputHelper.is_confirm_event(event)
