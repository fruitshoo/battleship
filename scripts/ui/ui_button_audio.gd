extends RefCounted
class_name UiButtonAudio


const WIRED_META := "ui_button_audio_wired"
const SELECT_WIRED_META := "ui_select_audio_wired"
const DEFAULT_VOLUME_DB := -5.0
const DEFAULT_PITCH_SCALE := 1.0
const NAV_VOLUME_DB := -8.0
const NAV_PITCH_SCALE := 1.16
const UPGRADE_SELECT_VOLUME_DB := -3.0
const UPGRADE_SELECT_PITCH_SCALE := 1.06
const PITCH_JITTER := 0.04
const NAV_RATE_LIMIT_MSEC := 80
const CLICK_NAV_SUPPRESS_MSEC := 140

static var _last_nav_msec: int = -1000000
static var _last_nav_control_id: int = 0
static var _last_focus_ref: WeakRef = null
static var _suppress_nav_until_msec: int = 0


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
	wire_selectable(button)
	button.pressed.connect(func() -> void:
		play_click(volume_db, pitch_scale)
	)


static func wire_selectable(control: Control, volume_db: float = NAV_VOLUME_DB, pitch_scale: float = NAV_PITCH_SCALE) -> void:
	if not is_instance_valid(control):
		return
	if control.has_meta(SELECT_WIRED_META):
		return
	control.set_meta(SELECT_WIRED_META, true)
	control.focus_entered.connect(func() -> void:
		_play_select_for_control(control, volume_db, pitch_scale, false)
	)
	control.mouse_entered.connect(func() -> void:
		_play_select_for_control(control, volume_db, pitch_scale, true)
	)


static func wire_selectables(controls: Array, volume_db: float = NAV_VOLUME_DB, pitch_scale: float = NAV_PITCH_SCALE) -> void:
	for control in controls:
		if control is Control:
			wire_selectable(control as Control, volume_db, pitch_scale)


static func play_click(volume_db: float = DEFAULT_VOLUME_DB, pitch_scale: float = DEFAULT_PITCH_SCALE) -> void:
	if not is_instance_valid(AudioManager):
		return
	_suppress_nav_until_msec = Time.get_ticks_msec() + CLICK_NAV_SUPPRESS_MSEC
	AudioManager.play_sfx("ui_click", null, pitch_scale + randf_range(-PITCH_JITTER, PITCH_JITTER), volume_db)


static func play_nav(volume_db: float = NAV_VOLUME_DB, pitch_scale: float = NAV_PITCH_SCALE) -> void:
	if not is_instance_valid(AudioManager):
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < _suppress_nav_until_msec:
		return
	if now_msec - _last_nav_msec < NAV_RATE_LIMIT_MSEC:
		return
	_last_nav_msec = now_msec
	_last_nav_control_id = 0
	AudioManager.play_sfx("ui_click", null, pitch_scale + randf_range(-PITCH_JITTER, PITCH_JITTER), volume_db)


static func play_upgrade_select(volume_db: float = UPGRADE_SELECT_VOLUME_DB, pitch_scale: float = UPGRADE_SELECT_PITCH_SCALE) -> void:
	if not is_instance_valid(AudioManager):
		return
	_suppress_nav_until_msec = Time.get_ticks_msec() + CLICK_NAV_SUPPRESS_MSEC
	AudioManager.play_sfx("upgrade_select", null, pitch_scale, volume_db)


static func _play_select_for_control(control: Control, volume_db: float, pitch_scale: float, skip_if_focused: bool) -> void:
	if not is_instance_valid(control) or not control.visible:
		return
	if control is BaseButton and (control as BaseButton).disabled:
		return
	if skip_if_focused and control.has_focus():
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < _suppress_nav_until_msec:
		_record_focus(control)
		return
	var control_id := control.get_instance_id()
	if control_id == _last_nav_control_id and now_msec - _last_nav_msec < NAV_RATE_LIMIT_MSEC:
		_record_focus(control)
		return
	var last_focus = _last_focus_ref.get_ref() if _last_focus_ref != null else null
	if not is_instance_valid(last_focus):
		_record_focus(control)
		if not skip_if_focused:
			return
	if last_focus == control:
		return
	_record_focus(control)
	_last_nav_msec = now_msec
	_last_nav_control_id = control_id
	if is_instance_valid(AudioManager):
		AudioManager.play_sfx("ui_click", null, pitch_scale + randf_range(-PITCH_JITTER, PITCH_JITTER), volume_db)


static func _record_focus(control: Control) -> void:
	_last_focus_ref = weakref(control)


static func _wire_buttons_recursive(node: Node, volume_db: float, pitch_scale: float) -> void:
	if node is BaseButton:
		wire_button(node as BaseButton, volume_db, pitch_scale)
	for child in node.get_children():
		_wire_buttons_recursive(child, volume_db, pitch_scale)
