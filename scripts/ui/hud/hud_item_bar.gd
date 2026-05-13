extends MarginContainer

const SLOT_SIZE := Vector2(50, 50)
const SLOT_BADGES := {
	"항해": "항",
	"함대": "함",
	"전투": "전",
	"선체": "선",
	"전리품": "품",
}

var item_container: HBoxContainer = null
var current_item_count: int = 0

func _ready() -> void:
	add_theme_constant_override("margin_top", 10)
	item_container = HBoxContainer.new()
	item_container.layout_direction = Control.LAYOUT_DIRECTION_RTL
	item_container.add_theme_constant_override("separation", 8)
	add_child(item_container)

func clear_icons() -> void:
	if not is_instance_valid(item_container):
		return
	for child in item_container.get_children():
		child.queue_free()
	current_item_count = 0

func add_icon(icon_data) -> PanelContainer:
	if current_item_count >= 5 or not is_instance_valid(item_container):
		return null

	var slot_bg: PanelContainer = _create_slot(icon_data)
	item_container.add_child(slot_bg)
	var icon_control := slot_bg.get_child(0) as Control
	var slot_sb := slot_bg.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	slot_bg.add_theme_stylebox_override("panel", slot_sb)

	var tween = create_tween()
	tween.tween_property(slot_sb, "border_color", NavalUiTheme.BORDER_GOLD, 0.2)
	if icon_control:
		tween.parallel().tween_property(icon_control, "scale", Vector2(1.2, 1.2), 0.2)
		tween.tween_property(icon_control, "scale", Vector2(1.0, 1.0), 0.2)
	tween.tween_property(slot_sb, "border_color", NavalUiTheme.BORDER_GOLD_DIM, 0.5)

	current_item_count += 1
	return slot_bg

func _create_slot(icon_data) -> PanelContainer:
	var slot_bg = PanelContainer.new()
	slot_bg.custom_minimum_size = SLOT_SIZE

	var slot_sb := NavalUiTheme.make_slot_style(NavalUiTheme.PANEL_BG_DARK, NavalUiTheme.BORDER_GOLD_DIM, 6)
	slot_bg.add_theme_stylebox_override("panel", slot_sb)

	var icon_texture := _resolve_icon_texture(icon_data)
	if icon_texture != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = SLOT_SIZE - Vector2(6, 6)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_bg.add_child(icon_rect)
		_add_slot_badge(slot_bg, icon_data)
		return slot_bg

	var icon_label = Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	NavalUiTheme.apply_emblem(icon_label, str(_extract_icon_data(icon_data)), 23, NavalUiTheme.TEXT_MAIN)

	slot_bg.add_child(icon_label)
	_add_slot_badge(slot_bg, icon_data)
	return slot_bg

func _resolve_icon_texture(icon_data) -> Texture2D:
	var resolved_icon_data = _extract_icon_data(icon_data)
	if resolved_icon_data is Texture2D:
		return resolved_icon_data
	if resolved_icon_data is String:
		var icon_path := str(resolved_icon_data)
		if icon_path.begins_with("res://") and ResourceLoader.exists(icon_path, "Texture2D"):
			return load(icon_path) as Texture2D
	return null

func _extract_icon_data(icon_data):
	if icon_data is Dictionary:
		return icon_data.get("icon_data", "")
	return icon_data


func _add_slot_badge(slot_bg: PanelContainer, icon_data) -> void:
	var badge_text := _get_slot_badge(icon_data)
	if badge_text.is_empty():
		return
	var badge := Label.new()
	badge.text = badge_text
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(16, 14)
	badge.anchor_left = 1.0
	badge.anchor_top = 1.0
	badge.anchor_right = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -17.0
	badge.offset_top = -15.0
	badge.offset_right = -2.0
	badge.offset_bottom = -1.0
	NavalUiTheme.style_overlay_caption(badge, 9, NavalUiTheme.TEXT_GOLD, 2)
	slot_bg.add_child(badge)


func _get_slot_badge(icon_data) -> String:
	var slot_name := _get_slot_name(icon_data)
	return str(SLOT_BADGES.get(slot_name, "품"))


func _get_slot_name(icon_data) -> String:
	if icon_data is Dictionary:
		var slot_name := str(icon_data.get("slot", "전리품")).strip_edges()
		return slot_name if not slot_name.is_empty() else "전리품"
	return "전리품"
