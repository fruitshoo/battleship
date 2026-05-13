extends VBoxContainer

const SLOT_SIZE := Vector2(42, 42)
const ICON_FONT_SIZE := 20
const LEVEL_FONT_SIZE := 11

var slot_container: HFlowContainer = null
var slots: Array[PanelContainer] = []
var _slot_panel_bg: Color = Color(0, 0, 0, 0.4)
var _slot_border_color: Color = Color(0.3, 0.3, 0.3, 0.8)

func setup_track(title_text: String, title_color: Color, slot_panel_bg: Color, slot_border_color: Color, slot_count: int = 0) -> void:
	if not title_text.strip_edges().is_empty():
		var title = Label.new()
		title.text = title_text
		NavalUiTheme.style_heading(title, 12)
		title.add_theme_color_override("font_color", title_color)
		add_child(title)

	_slot_panel_bg = slot_panel_bg
	_slot_border_color = slot_border_color

	slot_container = HFlowContainer.new()
	slot_container.add_theme_constant_override("separation", 8)
	slot_container.alignment = FlowContainer.ALIGNMENT_BEGIN
	slot_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(slot_container)
	slots.clear()

	for _i in range(slot_count):
		_ensure_slot(_i)

func update_slot(slot_idx: int, upgrade_id: String, level: int, icon_text: String, icon_color: Color, icon_texture: Texture2D = null) -> PanelContainer:
	if slot_idx < 0:
		return null
	_ensure_slot(slot_idx)
	var slot = slots[slot_idx]
	var icon_label = slot.get_node_or_null("Icon") as Label
	var icon_texture_rect = slot.get_node_or_null("IconTexture") as TextureRect
	var lv_label = slot.get_node_or_null("Level") as Label
	if icon_texture_rect:
		icon_texture_rect.texture = icon_texture
		icon_texture_rect.visible = icon_texture != null
	if icon_label:
		NavalUiTheme.apply_emblem(icon_label, icon_text, ICON_FONT_SIZE, icon_color)
		icon_label.visible = icon_texture == null
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
		tween.tween_property(slot_sb, "border_color", icon_color, 0.2)
		tween.tween_property(slot_sb, "border_color", NavalUiTheme.BORDER_GOLD_DIM, 0.5)
	return slot

func _ensure_slot(slot_idx: int) -> void:
	while slots.size() <= slot_idx:
		var slot_bg = _create_slot(_slot_panel_bg, _slot_border_color)
		slot_container.add_child(slot_bg)
		slots.append(slot_bg)

func _create_slot(panel_bg: Color, border_color: Color) -> PanelContainer:
	var slot_bg = PanelContainer.new()
	slot_bg.custom_minimum_size = SLOT_SIZE
	slot_bg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var slot_sb = StyleBoxFlat.new()
	slot_sb = NavalUiTheme.make_slot_style(panel_bg, border_color, 6)
	slot_bg.add_theme_stylebox_override("panel", slot_sb)

	var icon_texture := TextureRect.new()
	icon_texture.name = "IconTexture"
	icon_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_texture.offset_left = 3.0
	icon_texture.offset_top = 3.0
	icon_texture.offset_right = -3.0
	icon_texture.offset_bottom = -3.0
	icon_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_texture.visible = false
	slot_bg.add_child(icon_texture)

	var icon_label = Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.name = "Icon"
	NavalUiTheme.apply_emblem(icon_label, "build", ICON_FONT_SIZE, NavalUiTheme.TEXT_ACCENT)
	slot_bg.add_child(icon_label)

	var level_label_overlay = Label.new()
	level_label_overlay.name = "Level"
	level_label_overlay.text = "1"
	level_label_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label_overlay.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	NavalUiTheme.style_overlay_value(level_label_overlay, LEVEL_FONT_SIZE)
	level_label_overlay.visible = false
	level_label_overlay.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	level_label_overlay.offset_left = -20
	level_label_overlay.offset_top = -16
	level_label_overlay.offset_right = -2
	level_label_overlay.offset_bottom = -2
	slot_bg.add_child(level_label_overlay)
	slot_bg.set_meta("upgrade_id", "")
	slot_bg.set_meta("upgrade_level", 0)
	return slot_bg
