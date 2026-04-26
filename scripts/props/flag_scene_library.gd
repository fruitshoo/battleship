extends RefCounted
class_name FlagSceneLibrary

const KIND_PLAYER_FLAGSHIP := "player_flagship"
const KIND_PLAYER_SUPPORT := "player_support"
const KIND_ENEMY_DEFAULT := "enemy_pennant"
const KIND_ENEMY_SEKIBUNE := "enemy_sekibune"
const KIND_ENEMY_ELITE := "enemy_elite_tabs"
const KIND_BOSS := "boss_swallowtail"
const KIND_SITE := "site_marker"

const SCENE_PLAYER_FLAGSHIP := "res://scenes/props/flags/flag_player_flagship.tscn"
const SCENE_PLAYER_SUPPORT := "res://scenes/props/flags/flag_player_support.tscn"
const SCENE_ENEMY_DEFAULT := "res://scenes/props/flags/flag_enemy_pennant.tscn"
const SCENE_ENEMY_SEKIBUNE := "res://scenes/props/flags/flag_enemy_sekibune.tscn"
const SCENE_ENEMY_ELITE := "res://scenes/props/flags/flag_enemy_elite_tabs.tscn"
const SCENE_BOSS := "res://scenes/props/flags/flag_boss_swallowtail.tscn"
const SCENE_SITE := "res://scenes/props/flags/flag_site_marker.tscn"

const KIND_SCENE_PATHS := {
	KIND_PLAYER_FLAGSHIP: SCENE_PLAYER_FLAGSHIP,
	KIND_PLAYER_SUPPORT: SCENE_PLAYER_SUPPORT,
	KIND_ENEMY_DEFAULT: SCENE_ENEMY_DEFAULT,
	KIND_ENEMY_SEKIBUNE: SCENE_ENEMY_SEKIBUNE,
	KIND_ENEMY_ELITE: SCENE_ENEMY_ELITE,
	KIND_BOSS: SCENE_BOSS,
	KIND_SITE: SCENE_SITE,
}


static func get_scene_path(kind: String) -> String:
	return str(KIND_SCENE_PATHS.get(normalize_kind(kind), ""))


static func get_team_kind(team_name: String) -> String:
	var normalized := team_name.strip_edges().to_lower()
	if normalized == "player":
		return KIND_PLAYER_FLAGSHIP
	if normalized == "enemy":
		return KIND_ENEMY_DEFAULT
	return KIND_SITE


static func pick_enemy_kind_for_ship_type(ship_type: String, formation_role: String = "") -> String:
	var type_lower := ship_type.strip_edges().to_lower()
	var role_lower := formation_role.strip_edges().to_lower()
	if role_lower.contains("elite") or role_lower.contains("escort"):
		return KIND_ENEMY_ELITE
	if type_lower.contains("atake") or type_lower.contains("boss"):
		return KIND_BOSS
	if type_lower.contains("sekibune"):
		return KIND_ENEMY_SEKIBUNE
	return KIND_ENEMY_DEFAULT


static func has_kind(kind: String) -> bool:
	return KIND_SCENE_PATHS.has(normalize_kind(kind))


static func normalize_kind(kind: String) -> String:
	var normalized := kind.strip_edges().to_lower()
	match normalized:
		"player_flagship_yellow", "flagship", "player":
			return KIND_PLAYER_FLAGSHIP
		"player_support_teal", "support":
			return KIND_PLAYER_SUPPORT
		"enemy_orange_pennant", "enemy", "kobayabune":
			return KIND_ENEMY_DEFAULT
		"enemy_red_rect", "sekibune":
			return KIND_ENEMY_SEKIBUNE
		"enemy_elite_red_tabs", "elite":
			return KIND_ENEMY_ELITE
		"boss_flag", "boss", "atakebune":
			return KIND_BOSS
		"site_white_marker", "site":
			return KIND_SITE
	return normalized
