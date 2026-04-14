extends Control

const NavalUiTheme = preload("res://scripts/ui/naval_ui_theme.gd")
const RunResultStore = preload("res://scripts/ui/results/run_result_store.gd")

const GAME_SCENE_PATH := "res://scenes/main.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

@export var background_texture: Texture2D

@onready var background_image: TextureRect = $BackgroundImage
@onready var title_label: Label = $Content/TitleBlock/Title
@onready var subtitle_label: Label = $Content/TitleBlock/Subtitle
@onready var summary_list: VBoxContainer = $Content/Body/SummaryPanel/Margin/SummaryList
@onready var weapon_list: VBoxContainer = $Content/Body/WeaponPanel/Margin/WeaponList
@onready var restart_button: Button = $Content/ButtonBlock/RestartButton
@onready var main_menu_button: Button = $Content/ButtonBlock/MainMenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	get_tree().paused = false
	_apply_background()
	_apply_theme()
	_render_result(RunResultStore.get_latest_result())
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	restart_button.grab_focus()


func _apply_background() -> void:
	if is_instance_valid(background_image):
		background_image.texture = background_texture
		background_image.visible = background_texture != null


func _apply_theme() -> void:
	NavalUiTheme.style_heading(subtitle_label, 18)
	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", 54)
		title_label.add_theme_color_override("font_color", NavalUiTheme.TEXT_MAIN)
		title_label.add_theme_color_override("font_outline_color", NavalUiTheme.OUTLINE_DARK)
		title_label.add_theme_constant_override("outline_size", 3)
	for button in [restart_button, main_menu_button]:
		NavalUiTheme.apply_menu_button(button, 18)


func _render_result(result: Dictionary) -> void:
	title_label.text = str(result.get("title", "항해 결과"))
	subtitle_label.text = str(result.get("outcome", "항해 종료"))

	_clear_children(summary_list)
	_clear_children(weapon_list)

	var survived_seconds: float = float(result.get("survived_seconds", 0.0))
	_add_summary_row("생존 시간", _format_time(survived_seconds))
	_add_summary_row("획득 골드", "%d G" % int(result.get("gold", 0)))
	_add_summary_row("도달 레벨", "Lv.%d" % int(result.get("level", 1)))
	_add_summary_row("격침", "%d척" % int(result.get("ships_sunk", 0)))
	_add_summary_row("나포", "%d척" % int(result.get("ships_derelicted", 0)))
	_add_summary_row("적 병사", "%d명" % int(result.get("soldiers_killed", 0)))
	_add_summary_row("아군 생존", "%d / %d" % [int(result.get("crew_alive", 0)), int(result.get("crew_capacity", 0))])
	_add_summary_row("총 무기 피해", "%.0f" % float(result.get("total_weapon_damage", 0.0)))

	var weapon_rows: Array = result.get("weapon_rows", [])
	if weapon_rows.is_empty():
		_add_weapon_empty_row()
	else:
		for row in weapon_rows:
			_add_weapon_row(row)


func _add_summary_row(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	summary_list.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_muted(label, 18)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_gold(value, 18)
	row.add_child(value)


func _add_weapon_row(row_data: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	weapon_list.add_child(row)

	var name_label := Label.new()
	name_label.text = str(row_data.get("name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NavalUiTheme.style_body(name_label, 18)
	row.add_child(name_label)

	var damage_label := Label.new()
	damage_label.text = "%.0f" % float(row_data.get("damage", 0.0))
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	damage_label.custom_minimum_size = Vector2(120.0, 0.0)
	NavalUiTheme.style_gold(damage_label, 18)
	row.add_child(damage_label)


func _add_weapon_empty_row() -> void:
	var label := Label.new()
	label.text = "기록된 무기 피해 없음"
	NavalUiTheme.style_muted(label, 18)
	weapon_list.add_child(label)


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
