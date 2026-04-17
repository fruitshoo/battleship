@tool
extends "res://scripts/entities/ships/chaser_ship.gd"
class_name SupportShip

## Player support fleet ship.
## Keeps support-fleet identity in the scene instead of borrowing enemy_ship.tscn.

func _ready() -> void:
	team = "player"
	if ship_type.strip_edges().is_empty() or ship_type == "sekibune_melee":
		ship_type = "maengseon_ally"
	set_ally_ship_role("support_fleet")
	super._ready()
	set_ally_ship_role("support_fleet")
