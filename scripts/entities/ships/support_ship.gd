@tool
extends "res://scripts/entities/ships/chaser_ship.gd"
class_name SupportShip

## Player support fleet ship.
## Keeps support-fleet identity in the scene instead of borrowing enemy_base_ship.tscn.

func _ready() -> void:
	team = "player"
	if ship_type.strip_edges().is_empty() or ship_type == "sekibune_melee":
		ship_type = "maengseon_ally"
	set_ally_ship_role("support_fleet")
	limbo_ai_pilot_tree_path = ShipLimboAIPilot.resolve_tree_path(self, limbo_ai_pilot_tree_path)
	super._ready()
	set_ally_ship_role("support_fleet")
