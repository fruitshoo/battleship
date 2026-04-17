extends RefCounted
class_name SoldierSpeechHelper

const SPEECH_LABEL_NAME := "SpeechLabel"
const SPEECH_LABEL_META := "speech_label_instance"
const SPEECH_TIMER_META := "speech_timer"
const SPEECH_VISIBLE_TIMER_META := "speech_visible_timer"
const SPEECH_DURATION_META := "speech_duration"
const SPEECH_LAST_CONTEXT_META := "speech_last_context"
const SoldierStateHelper = preload("res://scripts/entities/soldiers/soldier_state_helper.gd")

const CAPTAIN_GENERAL_LINES: Array[String] = [
	"대열을 지켜라!",
	"돛을 보아라!",
	"침착하게 버텨라!",
	"기함을 중심으로!",
]
const CAPTAIN_RANGED_LINES: Array[String] = [
	"사격 준비!",
	"활을 당겨라!",
	"틈을 노려라!",
	"거리 유지!",
]
const CAPTAIN_MELEE_LINES: Array[String] = [
	"들이쳐라!",
	"갑판을 사수하라!",
	"물러서지 마라!",
	"지금이다!",
]
const CAPTAIN_DANGER_LINES: Array[String] = [
	"기함을 지켜라!",
	"적이 갑판에 올랐다!",
	"지원함을 불러라!",
	"버텨라!",
]
const CREW_RANGED_LINES: Array[String] = [
	"쏩니다!",
	"맞춰라!",
	"거리가 됩니다!",
]
const CREW_MELEE_LINES: Array[String] = [
	"막아!",
	"붙었다!",
	"밀어내!",
]
const CREW_DANGER_LINES: Array[String] = [
	"갑판에 적!",
	"위험합니다!",
	"도와줘!",
]
const ENEMY_BOARDING_LINES: Array[String] = [
	"갑판을 빼앗아라!",
	"조선 배에 올랐다!",
	"몰아붙여!",
	"물러서지 마라!",
]


static func reset(soldier) -> void:
	soldier.set_meta(SPEECH_TIMER_META, randf_range(2.0, 5.0) if bool(soldier.get("is_captain")) else randf_range(10.0, 22.0))
	soldier.set_meta(SPEECH_VISIBLE_TIMER_META, 0.0)
	soldier.set_meta(SPEECH_DURATION_META, 2.0)
	soldier.set_meta(SPEECH_LAST_CONTEXT_META, "")
	hide(soldier)


static func update(soldier, delta: float) -> void:
	if not _can_speak(soldier):
		hide(soldier)
		return

	var label := _ensure_label(soldier)
	if label == null:
		return

	var context := _get_context(soldier)
	var previous_context := str(soldier.get_meta(SPEECH_LAST_CONTEXT_META, ""))
	if context != previous_context:
		soldier.set_meta(SPEECH_LAST_CONTEXT_META, context)
		if context == "enemy_boarding":
			var current_timer := float(soldier.get_meta(SPEECH_TIMER_META, 0.0))
			soldier.set_meta(SPEECH_TIMER_META, minf(current_timer, randf_range(0.4, 1.2)))

	var duration: float = float(soldier.get_meta(SPEECH_DURATION_META, 2.0))
	var visible_timer: float = float(soldier.get_meta(SPEECH_VISIBLE_TIMER_META, 0.0))
	if visible_timer > 0.0:
		visible_timer = maxf(0.0, visible_timer - delta)
		soldier.set_meta(SPEECH_VISIBLE_TIMER_META, visible_timer)
		var fade_in: float = clampf((duration - visible_timer) / 0.18, 0.0, 1.0)
		var fade_out: float = clampf(visible_timer / 0.32, 0.0, 1.0)
		var alpha: float = minf(fade_in, fade_out)
		label.visible = alpha > 0.03
		label.modulate = _get_label_color(soldier, alpha)
		label.position.y = _get_label_base_height(soldier) + (1.0 - alpha) * 0.12 + sin(Time.get_ticks_msec() * 0.004) * 0.025
		return

	hide(soldier)
	var timer: float = float(soldier.get_meta(SPEECH_TIMER_META, randf_range(8.0, 16.0))) - delta
	if timer > 0.0:
		soldier.set_meta(SPEECH_TIMER_META, timer)
		return

	var lines := _get_lines_for_context(soldier, context)
	if lines.is_empty():
		soldier.set_meta(SPEECH_TIMER_META, _get_next_interval(soldier, context))
		return

	duration = 2.0 if bool(soldier.get("is_captain")) else 1.45
	soldier.set_meta(SPEECH_DURATION_META, duration)
	soldier.set_meta(SPEECH_VISIBLE_TIMER_META, duration)
	soldier.set_meta(SPEECH_TIMER_META, _get_next_interval(soldier, context))
	label.text = str(lines.pick_random())
	label.visible = true
	label.modulate = _get_label_color(soldier, 0.0)


static func hide(soldier) -> void:
	var label := _get_label(soldier)
	if label == null:
		return
	label.visible = false
	label.modulate = _get_label_color(soldier, 0.0)


static func _can_speak(soldier) -> bool:
	if not is_instance_valid(soldier):
		return false
	var team := str(soldier.get("team"))
	if team != "player" and not _is_enemy_boarder_on_player_ship(soldier):
		return false
	if SoldierStateHelper.is_dead_soldier(soldier):
		return false
	if bool(soldier.get("_is_jumping")):
		return false
	return true


static func _ensure_label(soldier) -> Label3D:
	var label := _get_label(soldier)
	if label != null:
		return label
	label = soldier.get_node_or_null(SPEECH_LABEL_NAME) as Label3D
	if label == null:
		label = Label3D.new()
		label.name = SPEECH_LABEL_NAME
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.extra_cull_margin = 16.0
		label.visible = false
		soldier.add_child(label)
	soldier.set_meta(SPEECH_LABEL_META, label)
	_configure_label(soldier, label)
	return label


static func _get_label(soldier) -> Label3D:
	if soldier.has_meta(SPEECH_LABEL_META):
		var label := soldier.get_meta(SPEECH_LABEL_META) as Label3D
		if is_instance_valid(label):
			return label
	return null


static func _configure_label(soldier, label: Label3D) -> void:
	var is_captain := bool(soldier.get("is_captain"))
	label.position = Vector3(0.0, _get_label_base_height(soldier), 0.0)
	label.font_size = 72 if is_captain else 64
	label.outline_size = 16 if is_captain else 14
	label.extra_cull_margin = 16.0
	label.no_depth_test = true
	label.render_priority = 20
	label.outline_render_priority = 21
	label.modulate = _get_label_color(soldier, 0.0)


static func _get_label_base_height(soldier) -> float:
	return 2.28 if bool(soldier.get("is_captain")) else 1.95


static func _get_label_color(soldier, alpha: float) -> Color:
	if bool(soldier.get("is_captain")):
		return Color(1.0, 0.9, 0.45, alpha)
	if _is_enemy_boarder_on_player_ship(soldier):
		return Color(1.0, 0.45, 0.35, alpha)
	return Color(0.88, 0.95, 1.0, alpha)


static func _get_context(soldier) -> String:
	if _is_enemy_boarder_on_player_ship(soldier):
		return "enemy_boarding"
	if _is_danger_context(soldier):
		return "danger"
	if int(soldier.get("current_state")) == int(soldier.State.ATTACK):
		return "melee" if _is_current_weapon_melee(soldier) else "ranged"
	if is_instance_valid(soldier.get("current_target")):
		return "melee" if _is_current_weapon_melee(soldier) else "ranged"
	return "moving"


static func _get_lines_for_context(soldier, context: String) -> Array[String]:
	if _is_enemy_boarder_on_player_ship(soldier):
		return ENEMY_BOARDING_LINES

	var is_captain := bool(soldier.get("is_captain"))
	if is_captain:
		match context:
			"danger":
				return CAPTAIN_DANGER_LINES
			"melee":
				return CAPTAIN_MELEE_LINES
			"ranged":
				return CAPTAIN_RANGED_LINES
			_:
				return CAPTAIN_GENERAL_LINES

	match context:
		"danger":
			return CREW_DANGER_LINES
		"melee":
			return CREW_MELEE_LINES
		"ranged":
			return CREW_RANGED_LINES
		_:
			return []


static func _get_next_interval(soldier, context: String) -> float:
	if _is_enemy_boarder_on_player_ship(soldier):
		return randf_range(8.0, 14.0)

	if bool(soldier.get("is_captain")):
		match context:
			"danger":
				return randf_range(5.5, 9.0)
			"melee":
				return randf_range(6.5, 11.0)
			"ranged":
				return randf_range(7.5, 12.0)
			_:
				return randf_range(9.0, 15.0)

	match context:
		"danger":
			return randf_range(11.0, 18.0)
		"melee":
			return randf_range(14.0, 24.0)
		"ranged":
			return randf_range(16.0, 28.0)
		_:
			return randf_range(24.0, 40.0)


static func _is_current_weapon_melee(soldier) -> bool:
	var weapon := soldier.get("current_weapon") as Node3D
	if not is_instance_valid(weapon):
		return false
	var weapon_id := str(weapon.get_meta("weapon_id", ""))
	if weapon_id in ["sword", "spearman", "spear", "trident", "harpoon"]:
		return true
	return not ("max_range" in weapon)


static func _is_danger_context(soldier) -> bool:
	var owned_ship = soldier.get("owned_ship")
	if not is_instance_valid(owned_ship):
		return false
	if owned_ship.get("deck_is_contested") == true or owned_ship.get("deck_is_overrun") == true:
		return true
	var boarder_count_variant: Variant = owned_ship.get("deck_hostile_boarder_count")
	return boarder_count_variant != null and int(boarder_count_variant) > 0


static func _is_enemy_boarder_on_player_ship(soldier) -> bool:
	if not is_instance_valid(soldier):
		return false
	if str(soldier.get("team")) != "enemy":
		return false
	var owned_ship = soldier.get("owned_ship")
	if not is_instance_valid(owned_ship):
		return false
	var owned_team := ""
	if owned_ship.has_method("get_team_tag"):
		owned_team = str(owned_ship.get_team_tag())
	else:
		owned_team = str(owned_ship.get("team"))
	return owned_team == "player"
