class_name InputSettingsHelper
extends RefCounted

const CONFIRM_POSITION_BOTTOM := "bottom"
const CONFIRM_POSITION_RIGHT := "right"


static func apply_gamepad_confirm_button_layout(confirm_position: String) -> void:
	var confirm_button := JOY_BUTTON_A if confirm_position != CONFIRM_POSITION_RIGHT else JOY_BUTTON_B
	var cancel_button := JOY_BUTTON_B if confirm_position != CONFIRM_POSITION_RIGHT else JOY_BUTTON_A
	_replace_gamepad_face_button("ui_accept", confirm_button)
	_replace_gamepad_face_button("ui_cancel", cancel_button)


static func _replace_gamepad_face_button(action_name: String, button_index: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var face_buttons := [JOY_BUTTON_A, JOY_BUTTON_B]
	for event in InputMap.action_get_events(action_name):
		if event is InputEventJoypadButton and face_buttons.has((event as InputEventJoypadButton).button_index):
			InputMap.action_erase_event(action_name, event)
	var joy_event := InputEventJoypadButton.new()
	joy_event.button_index = button_index
	InputMap.action_add_event(action_name, joy_event)
