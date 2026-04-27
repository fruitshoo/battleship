extends RefCounted
class_name UiButtonAudio


const WIRED_META := "ui_button_audio_wired"
const DEFAULT_VOLUME_DB := -5.0
const DEFAULT_PITCH_SCALE := 1.0
const UPGRADE_SELECT_VOLUME_DB := -3.0
const UPGRADE_SELECT_PITCH_SCALE := 1.06
const PITCH_JITTER := 0.04


static func wire_buttons(root: Node, volume_db: float = DEFAULT_VOLUME_DB, pitch_scale: float = DEFAULT_PITCH_SCALE) -> void:
	if not is_instance_valid(root):
		return
	_wire_buttons_recursive(root, volume_db, pitch_scale)


static func wire_button(button: BaseButton, volume_db: float = DEFAULT_VOLUME_DB, pitch_scale: float = DEFAULT_PITCH_SCALE) -> void:
	if not is_instance_valid(button):
		return
	if button.has_meta(WIRED_META):
		return
	button.set_meta(WIRED_META, true)
	button.pressed.connect(func() -> void:
		play_click(volume_db, pitch_scale)
	)


static func play_click(volume_db: float = DEFAULT_VOLUME_DB, pitch_scale: float = DEFAULT_PITCH_SCALE) -> void:
	if not is_instance_valid(AudioManager):
		return
	AudioManager.play_sfx("ui_click", null, pitch_scale + randf_range(-PITCH_JITTER, PITCH_JITTER), volume_db)


static func play_upgrade_select(volume_db: float = UPGRADE_SELECT_VOLUME_DB, pitch_scale: float = UPGRADE_SELECT_PITCH_SCALE) -> void:
	if not is_instance_valid(AudioManager):
		return
	AudioManager.play_sfx("upgrade_select", null, pitch_scale, volume_db)


static func _wire_buttons_recursive(node: Node, volume_db: float, pitch_scale: float) -> void:
	if node is BaseButton:
		wire_button(node as BaseButton, volume_db, pitch_scale)
	for child in node.get_children():
		_wire_buttons_recursive(child, volume_db, pitch_scale)
