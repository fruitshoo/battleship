class_name InputSettingsHelper
extends RefCounted

const CONFIRM_POSITION_AUTO := "auto"
const CONFIRM_POSITION_BOTTOM := "bottom"
const CONFIRM_POSITION_RIGHT := "right"
const NINTENDO_LAYOUT_HINTS := [
	"nintendo",
	"switch",
	"joy-con",
	"joycon",
	"pro controller",
	"wii",
]


static func apply_gamepad_confirm_button_layout(confirm_position: String) -> void:
	var resolved_position := resolve_gamepad_confirm_position(confirm_position)
	var confirm_button := JOY_BUTTON_A if resolved_position != CONFIRM_POSITION_RIGHT else JOY_BUTTON_B
	var cancel_button := JOY_BUTTON_B if resolved_position != CONFIRM_POSITION_RIGHT else JOY_BUTTON_A
	_replace_gamepad_face_button("ui_accept", confirm_button)
	_replace_gamepad_face_button("ui_cancel", cancel_button)


static func resolve_gamepad_confirm_position(confirm_position: String, device_descriptions: Array = []) -> String:
	var normalized := confirm_position.strip_edges().to_lower()
	if normalized == CONFIRM_POSITION_BOTTOM or normalized == CONFIRM_POSITION_RIGHT:
		return normalized
	var descriptions: Array = device_descriptions
	if descriptions.is_empty():
		descriptions = _get_connected_gamepad_descriptions()
	return CONFIRM_POSITION_RIGHT if _has_nintendo_layout_device(descriptions) else CONFIRM_POSITION_BOTTOM


static func _get_connected_gamepad_descriptions() -> Array[String]:
	var descriptions: Array[String] = []
	for device in Input.get_connected_joypads():
		var device_id := int(device)
		descriptions.append(Input.get_joy_name(device_id))
		descriptions.append(Input.get_joy_guid(device_id))
	return descriptions


static func _has_nintendo_layout_device(device_descriptions: Array) -> bool:
	for description in device_descriptions:
		var normalized := str(description).strip_edges().to_lower()
		for hint in NINTENDO_LAYOUT_HINTS:
			if normalized.contains(hint):
				return true
	return false


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
