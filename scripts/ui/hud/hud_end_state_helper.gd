extends RefCounted


static func show_game_over(hud) -> void:
	if hud._game_over_transitioning:
		return
	if hud.game_over_label:
		hud.game_over_label.text = "!!! SHIP DESTROYED !!!"
		hud.game_over_label.visible = true
		var tween: Tween = hud.create_tween()
		hud.game_over_label.modulate.a = 0.0
		tween.tween_property(hud.game_over_label, "modulate:a", 1.0, 1.0)
	hud.get_tree().paused = true
	if is_instance_valid(hud.game_over_overlay):
		hud.game_over_overlay.show_overlay("함선이 침몰했습니다. 항구로 복귀합니다.", 4.0)


static func show_victory(hud) -> void:
	if hud.victory_label:
		hud.victory_label.text = "[!] VICTORY [!]"
		hud.victory_label.visible = true
		var tween: Tween = hud.create_tween()
		hud.victory_label.modulate.a = 0.0
		tween.tween_property(hud.victory_label, "modulate:a", 1.0, 2.0)


static func show_victory_result_transition(hud, subtitle: String, countdown: float) -> void:
	if hud.victory_label:
		hud.victory_label.visible = false
	if is_instance_valid(hud.victory_result_overlay):
		hud.victory_result_overlay.show_overlay(subtitle, countdown, "전적 보기")


static func show_victory_with_damage(hud, rows: Array, total_damage: float) -> void:
	if not hud.victory_label:
		return
	var lines: Array[String] = []
	lines.append("[!] VICTORY [!]")
	lines.append("총 무기 피해: %.0f" % total_damage)
	if rows.is_empty():
		lines.append("무기 데미지 통계 없음")
	else:
		lines.append("----- 무기별 데미지 -----")
		for row in rows:
			var name := str(row.get("name", "?"))
			var dmg := float(row.get("damage", 0.0))
			lines.append("%s : %.0f" % [name, dmg])

	hud.victory_label.text = "\n".join(lines)
	hud.victory_label.visible = true
	hud.victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud.victory_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hud.victory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.victory_label.offset_left = -320.0
	hud.victory_label.offset_top = -180.0
	hud.victory_label.offset_right = 320.0
	hud.victory_label.offset_bottom = 220.0
	NavalUiTheme.style_status_banner(hud.victory_label, 24, NavalUiTheme.TEXT_GOLD, 4)

	var tween: Tween = hud.create_tween()
	hud.victory_label.modulate.a = 0.0
	tween.tween_property(hud.victory_label, "modulate:a", 1.0, 0.8)


static func setup_game_over_overlay(hud) -> void:
	if is_instance_valid(hud.game_over_overlay):
		return
	hud.game_over_overlay = hud.HudGameOverOverlay.new()
	hud.game_over_overlay.return_requested.connect(hud._return_to_main_menu)
	hud.add_child(hud.game_over_overlay)


static func setup_victory_result_overlay(hud) -> void:
	if is_instance_valid(hud.victory_result_overlay):
		return
	hud.victory_result_overlay = hud.HudGameOverOverlay.new()
	hud.victory_result_overlay.return_requested.connect(hud._go_to_result_scene)
	hud.add_child(hud.victory_result_overlay)


static func return_to_main_menu(hud) -> void:
	if hud._game_over_transitioning:
		return
	hud._game_over_transitioning = true
	if is_instance_valid(hud.game_over_overlay):
		hud.game_over_overlay.hide_overlay()
	hud.get_tree().paused = false
	hud.get_tree().change_scene_to_file(hud.MAIN_MENU_SCENE_PATH)


static func go_to_result_scene(hud) -> void:
	if hud._victory_result_transitioning:
		return
	hud._victory_result_transitioning = true
	if is_instance_valid(hud.victory_result_overlay):
		hud.victory_result_overlay.hide_overlay()
	var lm := LevelManagerRegistry.get_level_manager(hud.get_tree())
	if is_instance_valid(lm) and lm.has_method("go_to_result_scene_now"):
		lm.go_to_result_scene_now()
	else:
		hud.get_tree().paused = false
		Engine.time_scale = 1.0
		hud.get_tree().change_scene_to_file("res://scenes/ui/result_screen.tscn")
