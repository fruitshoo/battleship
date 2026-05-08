extends RefCounted


static func update_hull_hp(hud, current: float, maximum: float) -> void:
	if hud.hp_bar:
		hud.hp_bar.max_value = maximum

		var tween: Tween = hud.create_tween()
		tween.tween_property(hud.hp_bar, "value", current, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		if hud.hp_text_label:
			hud.hp_text_label.text = "HP %.0f / %.0f" % [current, maximum]

		var ratio := current / maximum
		var fill_style := hud.hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if ratio > 0.6:
				fill_style.bg_color = NavalUiTheme.STATUS_GOOD
			elif ratio > 0.3:
				fill_style.bg_color = NavalUiTheme.STATUS_WARN
			else:
				fill_style.bg_color = NavalUiTheme.STATUS_DANGER


static func update_stamina(hud, current: float, maximum: float) -> void:
	if hud.stamina_bar:
		hud.stamina_bar.max_value = maximum
		hud.stamina_bar.value = current

		var fill_style := hud.stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill_style:
			if current < 1.0:
				fill_style.bg_color = NavalUiTheme.STATUS_DANGER
			else:
				fill_style.bg_color = NavalUiTheme.STATUS_WARN


static func update_xp(hud, current: int, maximum: int) -> void:
	if hud.xp_bar:
		hud.xp_bar.max_value = maximum
		hud.xp_bar.value = current


static func update_ammo_mode_display(hud) -> void:
	if not is_instance_valid(hud.ammo_mode_label):
		return
	if not is_instance_valid(hud.player_ship):
		hud._try_resolve_player_ship()
	if not is_instance_valid(hud.player_ship):
		if hud.ammo_mode_label.visible:
			hud.ammo_mode_label.visible = false
		return
	var ammo_text := "탄종: 실선탄"
	if hud._last_ammo_mode_text != ammo_text:
		hud._last_ammo_mode_text = ammo_text
		hud.ammo_mode_label.text = ammo_text
	hud.ammo_mode_label.visible = false


static func show_gust_warning_message(hud, message: String, duration: float = 0.35) -> void:
	if not hud.gust_warning:
		return
	hud.gust_warning.text = message
	hud.gust_warning.visible = true
	hud._gust_warning_timer = maxf(hud._gust_warning_timer, duration)
