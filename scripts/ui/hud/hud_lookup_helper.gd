extends RefCounted
class_name HudLookupHelper

const EntityRegistry = preload("res://scripts/helpers/entity_registry.gd")


static func try_resolve_player_ship(hud) -> void:
	if is_instance_valid(hud.player_ship):
		return
	if hud._player_lookup_cooldown > 0.0:
		return
	hud._player_lookup_cooldown = 0.25
	var players = EntityRegistry.get_ships_by_team("player")
	for ship in players:
		if is_instance_valid(ship) and ship.get("is_player_controlled") == true:
			hud.player_ship = ship
			return
	if players.size() > 0 and is_instance_valid(players[0]):
		hud.player_ship = players[0]


static func ensure_player_ship(hud) -> bool:
	if not is_instance_valid(hud.player_ship):
		try_resolve_player_ship(hud)
	return is_instance_valid(hud.player_ship)
