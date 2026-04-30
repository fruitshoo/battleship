extends RefCounted


static func process_hud(hud, delta: float) -> void:
	sync_game_time(hud, delta)
	if hud._gust_warning_timer > 0.0:
		hud._gust_warning_timer = maxf(0.0, hud._gust_warning_timer - delta)
		if hud.gust_warning:
			hud.gust_warning.visible = true
	elif hud.gust_warning and hud.gust_warning.visible:
		hud.gust_warning.visible = false
	hud._player_lookup_cooldown = maxf(0.0, hud._player_lookup_cooldown - delta)
	if not is_instance_valid(hud.player_ship):
		hud._try_resolve_player_ship()
	hud._update_upgrade_tooltip_state(delta)
	hud._update_upgrade_tooltip_position()
	hud._item_refresh_retry_left = maxf(0.0, hud._item_refresh_retry_left - delta)
	if hud._item_refresh_retry_left <= 0.0 and hud.item_bar and is_instance_valid(UpgradeManager):
		var owned_items = UpgradeManager.acquired_items if "acquired_items" in UpgradeManager else []
		if owned_items is Array and hud.item_bar.current_item_count < owned_items.size():
			hud._item_refresh_retry_left = 0.5
			hud._refresh_owned_item_icons()
	if is_instance_valid(hud.sail_debug_panel) and hud.sail_debug_panel.visible:
		hud.sail_debug_sync_left = maxf(0.0, hud.sail_debug_sync_left - delta)
		if hud.sail_debug_sync_left <= 0.0:
			hud.sail_debug_sync_left = 0.2
			hud._sync_sail_debug_panel_from_player()
			hud._sync_debug_tools_panel_state()
	if hud.show_ship_health_bars:
		hud._update_ship_health_bars(true)
	hud._update_player_status_overlay(true)
	hud._hud_refresh_left -= delta
	if hud._hud_refresh_left <= 0.0:
		hud._hud_refresh_left = hud.hud_refresh_interval
		hud._update_timer()
		hud._update_speed_display()
		hud._update_force_panel()
		hud._update_hull_display()
		hud._update_stamina_display()
		hud._update_player_status_overlay(false)
		hud._update_boarding_display()
		hud._update_capture_opportunity_display()
		hud._update_boss_hp_display()
		hud._update_ammo_mode_display()
		hud._update_distance_debug_display()
		hud._update_ship_health_bars(false)
	hud.HudStatPanelHelper.process_stat_panel(hud, delta)


static func sync_game_time(hud, delta: float) -> void:
	if not is_instance_valid(hud._cached_level_manager):
		hud._cached_level_manager = LevelManagerRegistry.get_level_manager(hud.get_tree())
	if is_instance_valid(hud._cached_level_manager) and hud._cached_level_manager.get("current_time") != null:
		hud.game_time = float(hud._cached_level_manager.current_time)
	else:
		hud.game_time += delta
