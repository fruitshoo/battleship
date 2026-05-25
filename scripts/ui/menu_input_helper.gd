class_name MenuInputHelper
extends RefCounted

const INPUT_DEVICE_KEYBOARD := "keyboard"
const INPUT_DEVICE_GAMEPAD := "gamepad"
const JOYPAD_MOTION_DETECTION_DEADZONE := 0.35
const JOYPAD_NAV_AXIS_ACTIVATE := 0.58
const JOYPAD_NAV_AXIS_RELEASE := 0.32
const JOYPAD_NAV_AXIS_X := 0
const JOYPAD_NAV_AXIS_Y := 1

static var _last_input_device := INPUT_DEVICE_KEYBOARD

class NavRepeater:
	extends RefCounted

	var _joypad_nav_x_latch: int = 0
	var _joypad_nav_y_latch: int = 0

	func reset() -> void:
		_joypad_nav_x_latch = 0
		_joypad_nav_y_latch = 0

	func consume_event(event: InputEvent) -> Vector2i:
		MenuInputHelper.observe_event(event)
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if motion.axis == MenuInputHelper.JOYPAD_NAV_AXIS_X:
				return Vector2i(_consume_axis_direction(motion.axis_value, true), 0)
			if motion.axis == MenuInputHelper.JOYPAD_NAV_AXIS_Y:
				return Vector2i(0, _consume_axis_direction(motion.axis_value, false))
			return Vector2i.ZERO
		if event is InputEventKey and (event as InputEventKey).echo:
			return Vector2i.ZERO
		if MenuInputHelper.is_left_event(event):
			return Vector2i(-1, 0)
		if MenuInputHelper.is_right_event(event):
			return Vector2i(1, 0)
		if MenuInputHelper.is_up_event(event):
			return Vector2i(0, -1)
		if MenuInputHelper.is_down_event(event):
			return Vector2i(0, 1)
		return Vector2i.ZERO

	func _consume_axis_direction(value: float, horizontal: bool) -> int:
		var current_latch := _joypad_nav_x_latch if horizontal else _joypad_nav_y_latch
		if absf(value) <= MenuInputHelper.JOYPAD_NAV_AXIS_RELEASE:
			if horizontal:
				_joypad_nav_x_latch = 0
			else:
				_joypad_nav_y_latch = 0
			return 0
		if absf(value) < MenuInputHelper.JOYPAD_NAV_AXIS_ACTIVATE:
			return 0
		var direction := -1 if value < 0.0 else 1
		if current_latch == direction:
			return 0
		if horizontal:
			_joypad_nav_x_latch = direction
		else:
			_joypad_nav_y_latch = direction
		return direction


class ButtonFocusNavigator:
	extends RefCounted

	var buttons: Array[Button] = []
	var focused_index: int = 0
	var _focus_changed_callback: Callable = Callable()
	var _mouse_focus_allowed_callback: Callable = Callable()

	func configure(
		button_list: Array[Button],
		focus_changed_callback: Callable = Callable(),
		mouse_focus_allowed_callback: Callable = Callable()
	) -> void:
		buttons = button_list.duplicate()
		_focus_changed_callback = focus_changed_callback
		_mouse_focus_allowed_callback = mouse_focus_allowed_callback
		for button in buttons:
			if not is_instance_valid(button):
				continue
			button.focus_entered.connect(func():
				var idx := buttons.find(button)
				if idx != -1:
					focused_index = idx
				_notify_focus_changed(button, true)
			)
			button.focus_exited.connect(func():
				_notify_focus_changed(button, false)
			)
			button.mouse_entered.connect(func():
				if _can_mouse_focus(button):
					button.grab_focus()
			)

	func focus_first() -> void:
		for i in range(buttons.size()):
			var button := buttons[i]
			if _is_focusable(button):
				focused_index = i
				button.grab_focus()
				return

	func move_focus(direction: int) -> void:
		if buttons.is_empty() or direction == 0:
			return
		var button_count := buttons.size()
		for step in range(1, button_count + 1):
			var next_index := posmod(focused_index + direction * step, button_count)
			var button := buttons[next_index]
			if _is_focusable(button):
				focused_index = next_index
				button.grab_focus()
				return

	func activate_focused() -> void:
		if buttons.is_empty():
			return
		if focused_index < 0 or focused_index >= buttons.size():
			focus_first()
			return
		var button := buttons[focused_index]
		if not _is_focusable(button):
			return
		button.emit_signal("pressed")

	func get_focused_index() -> int:
		return focused_index

	func _is_focusable(button: Button) -> bool:
		return is_instance_valid(button) and button.visible and not button.disabled

	func _can_mouse_focus(button: Button) -> bool:
		if not _is_focusable(button):
			return false
		if not _mouse_focus_allowed_callback.is_valid():
			return true
		return bool(_mouse_focus_allowed_callback.call())

	func _notify_focus_changed(button: Button, focused: bool) -> void:
		if _focus_changed_callback.is_valid():
			_focus_changed_callback.call(button, focused)


static func is_confirm_event(event: InputEvent) -> bool:
	observe_event(event)
	return event.is_action_pressed("ui_accept") \
		or is_keycode_pressed(event, KEY_SPACE) \
		or is_keycode_pressed(event, KEY_ENTER) \
		or is_keycode_pressed(event, KEY_KP_ENTER)


static func is_cancel_event(event: InputEvent) -> bool:
	observe_event(event)
	return event.is_action_pressed("ui_cancel") or is_keycode_pressed(event, KEY_ESCAPE)


static func is_left_event(event: InputEvent) -> bool:
	observe_event(event)
	if event is InputEventJoypadMotion:
		return false
	return event.is_action_pressed("ui_left") or is_physical_key_pressed(event, KEY_A)


static func is_right_event(event: InputEvent) -> bool:
	observe_event(event)
	if event is InputEventJoypadMotion:
		return false
	return event.is_action_pressed("ui_right") or is_physical_key_pressed(event, KEY_D)


static func is_up_event(event: InputEvent) -> bool:
	observe_event(event)
	if event is InputEventJoypadMotion:
		return false
	return event.is_action_pressed("ui_up") or is_physical_key_pressed(event, KEY_W)


static func is_down_event(event: InputEvent) -> bool:
	observe_event(event)
	if event is InputEventJoypadMotion:
		return false
	return event.is_action_pressed("ui_down") or is_physical_key_pressed(event, KEY_S)


static func is_menu_prev_event(event: InputEvent) -> bool:
	return is_up_event(event) or is_physical_key_pressed(event, KEY_A)


static func is_menu_next_event(event: InputEvent) -> bool:
	return is_down_event(event) or is_physical_key_pressed(event, KEY_D)


static func is_any_prev_event(event: InputEvent) -> bool:
	return is_left_event(event) or is_up_event(event)


static func is_any_next_event(event: InputEvent) -> bool:
	return is_right_event(event) or is_down_event(event)


static func observe_event(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		if button_event.pressed:
			_last_input_device = INPUT_DEVICE_GAMEPAD
	elif event is InputEventJoypadMotion:
		var motion_event := event as InputEventJoypadMotion
		if absf(motion_event.axis_value) >= JOYPAD_MOTION_DETECTION_DEADZONE:
			_last_input_device = INPUT_DEVICE_GAMEPAD
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			_last_input_device = INPUT_DEVICE_KEYBOARD
	elif event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		if mouse_button_event.pressed:
			_last_input_device = INPUT_DEVICE_KEYBOARD


static func get_last_input_device() -> String:
	return _last_input_device


static func is_gamepad_last_used() -> bool:
	return _last_input_device == INPUT_DEVICE_GAMEPAD


static func is_navigation_axis_event(event: InputEvent) -> bool:
	return event is InputEventJoypadMotion \
		and ((event as InputEventJoypadMotion).axis == JOYPAD_NAV_AXIS_X \
			or (event as InputEventJoypadMotion).axis == JOYPAD_NAV_AXIS_Y)


static func is_physical_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == keycode


static func is_keycode_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
