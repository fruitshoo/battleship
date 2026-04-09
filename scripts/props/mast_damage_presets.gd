extends RefCounted
class_name MastDamagePresets

const CLEAN := {"name": "Clean", "damage": 0.0, "burn": 0.0, "hole": 0.0}
const WEAR := {"name": "Wear", "damage": 0.37, "burn": 0.0, "hole": 1.91}
const BURNED := {"name": "Burned", "damage": 0.40, "burn": 1.0, "hole": 1.91}
const WRECKED := {"name": "Wrecked", "damage": 0.50, "burn": 1.0, "hole": 2.0}

const ALL := [
	CLEAN,
	WEAR,
	BURNED,
	WRECKED,
]
