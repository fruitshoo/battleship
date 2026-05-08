class_name LevelManagerUpgradeFlowHelper
extends RefCounted

static func show_upgrade_ui(lm: Node, choice_count: int = 3) -> void:
	if not is_instance_valid(UpgradeManager):
		return

	var choices = UpgradeManager.get_ship_upgrade_choices(choice_count)
	if choices.is_empty():
		return

	lm.get_tree().paused = true

	if is_instance_valid(lm._upgrade_ui_instance):
		lm._upgrade_ui_instance.queue_free()

	lm._upgrade_ui_instance = lm.upgrade_ui_scene.instantiate()
	lm.add_child(lm._upgrade_ui_instance)
	lm._upgrade_ui_instance.upgrade_chosen.connect(lm._on_upgrade_chosen)
	lm._upgrade_ui_instance.reroll_requested.connect(lm._on_reroll_requested)
	lm._upgrade_ui_instance.show_upgrades(choices, lm.ship_rerolls_available)

static func on_reroll_requested(lm: Node) -> void:
	if lm.ship_rerolls_available <= 0:
		return

	lm.ship_rerolls_available -= 1
	var choices = UpgradeManager.get_ship_upgrade_choices(3)
	if lm._upgrade_ui_instance:
		lm._upgrade_ui_instance.show_upgrades(choices, lm.ship_rerolls_available)
		print("[Reroll] Reroll 사용! (남은 횟수: %d)" % lm.ship_rerolls_available)

static func on_upgrade_chosen(lm: Node, upgrade_id: String) -> void:
	UpgradeManager.apply_upgrade(upgrade_id)

	if is_instance_valid(lm._upgrade_ui_instance):
		lm._upgrade_ui_instance.queue_free()
		lm._upgrade_ui_instance = null

	lm.get_tree().paused = false
	
	# 만약 획득한 경험치가 너무 많아 여전히 다음 레벨 요구치를 넘는다면 
	# UI가 닫히고 게임이 재개된 바로 다음 프레임에 곧바로 다시 레벨업을 띄운다
	if lm.get("current_xp") != null and lm.get("xp_to_next_level") != null:
		if lm.current_xp >= lm.xp_to_next_level:
			Callable(LevelManagerProgressionHelper, "add_xp").call_deferred(lm, 0)
