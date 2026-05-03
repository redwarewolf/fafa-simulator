class_name ClubResource
extends Resource

## Represents a football club — both the player's own club and any opponent.

# Identity
@export var id             : String  ## Stable slug used for file lookups and save data (e.g. "saca-chispas")
@export var display_name   : String  ## Human-readable name (e.g. "Saca Chispas")
@export var team_key       : String  ## Uppercase key matching Player.TEAMS (e.g. "SACA CHISPAS")

# Competition
@export var division       : String  ## "E", "D", "C", "B" or "A"

# Visuals
@export var primary_color  : int     ## Row index in teams-color-palette for the main kit color
@export var secondary_color: int     ## Row index for the secondary / away kit color
@export var logo_path      : String  ## res:// path to the club crest texture

# Finances
@export var budget         : int

# Squad
@export var players        : Array[PlayerResource]


func _init(
	p_id             : String = "",
	p_display_name   : String = "",
	p_team_key       : String = "",
	p_division       : String = "E",
	p_primary_color  : int    = 0,
	p_secondary_color: int    = 0,
	p_logo_path      : String = "",
	p_budget         : int    = 0
) -> void:
	id              = p_id
	display_name    = p_display_name
	team_key        = p_team_key
	division        = p_division
	primary_color   = p_primary_color
	secondary_color = p_secondary_color
	logo_path       = p_logo_path
	budget          = p_budget


## Returns the computed average overall of all players in the squad.
func get_squad_overall() -> int:
	if players.is_empty():
		return 0
	var total := 0
	for p in players:
		total += p.get_overall()
	return total / players.size()
