class_name ClubResource
extends Resource

## Represents a football club — both the player's own club and any opponent.

# Identity
@export var id             : String  ## Stable slug used for file lookups and save data (e.g. "saca-chispas")
@export var display_name   : String  ## Human-readable name (e.g. "Saca Chispas")
@export var team_key       : String  ## Uppercase key matching Player.TEAMS (e.g. "SACA CHISPAS")

# Competition
@export var division            : String  ## "E", "D", "C", "B" or "A"
@export var tournament_points  : int     ## Points accumulated in the current tournament
@export var matches_played  : int = 0
@export var wins            : int = 0
@export var draws           : int = 0
@export var losses          : int = 0
@export var goals_for       : int = 0
@export var goals_against   : int = 0

# Visuals
@export var primary_color  : Color   ## Main kit / crest primary color
@export var secondary_color: Color   ## Secondary / away kit color
@export var logo_path      : String  ## res:// path to a hand-drawn crest (optional)
@export var logo_template  : int     ## 1 or 2 = which template PNG to use with the logo shader; 0 = none

# Club
@export var budget         : int
@export var fans           : int = 0

const TRIBUNE_CAPACITY_PER_LEVEL := 75

# Squad
@export var players        : Array[PlayerResource]

## Tracks purchased upgrade levels. Keys: "building", "food_sales", "tribune",
## "trainer", "scout", "academy". Value = current level (0 = none).
@export var upgrades       : Dictionary = {}

## Candidate players currently offered by the talent scout. Regenerates when
## the in-game month rolls over. Empty until a scout is hired.
@export var scouted_players    : Array[PlayerResource] = []
@export var scouted_pool_month : int = 0
@export var scouted_pool_year  : int = 0

## Youth academy prospects — not part of the senior squad, don't draw a wage,
## and graduate into `players` at YouthAcademy.GRADUATION_AGE (or earlier, if
## promoted by hand). Empty until the "academy" staff upgrade is hired.
@export var youth_players : Array[PlayerResource] = []

## Unseen-candidate counters, driving the nav badges in hub.gd/club_section.gd
## — how many scout/academy prospects arrived since the player last opened
## that pool. Cleared via GameState.mark_scout_seen()/mark_youth_seen().
@export var scout_unseen : int = 0
@export var youth_unseen : int = 0


func _init(
		p_id                : String = "",
		p_display_name      : String = "",
		p_team_key          : String = "",
		p_division          : String = "E",
		p_primary_color     : Color  = Color.WHITE,
		p_secondary_color   : Color  = Color.WHITE,
		p_logo_path         : String = "",
		p_logo_template     : int    = 0,
		p_budget            : int    = 0,
		p_tournament_points : int    = 0
) -> void:
		id                 = p_id
		display_name       = p_display_name
		team_key           = p_team_key
		division           = p_division
		primary_color      = p_primary_color
		secondary_color    = p_secondary_color
		logo_path          = p_logo_path
		logo_template      = p_logo_template
		budget             = p_budget
		tournament_points  = p_tournament_points

## Returns the computed average overall of all players in the squad.
func get_squad_overall() -> int:
	if players.is_empty():
		return 0
	var total := 0
	for p in players:
		total += p.overall()
	return total / players.size()

## Total upkeep from hired staff, deducted automatically on every date advance
## ("Next Date" press). StaffData's tiers are still labeled/tuned as monthly
## figures — charged in full each date for now, pending a rebalance pass.
func get_staff_upkeep_cost() -> int:
	var total := 0
	for key in ["trainer", "scout", "academy"]:
		var lvl : int = upgrades.get(key, 0)
		if lvl > 0:
			total += StaffData.STAFF[key]["levels"][lvl - 1]["monthly"]
	return total

## Total wages owed to the squad, deducted automatically on every date advance
## ("Next Date" press). PlayerWage's formula is still tuned as a monthly
## figure — charged in full each date for now, pending a rebalance pass.
func get_wage_cost() -> int:
	var total := 0
	for p in players:
		total += PlayerWage.estimate(p)
	return total

## Stadium capacity derived from the tribune upgrade level (0-3 -> 75/150/225/300).
func get_stadium_capacity() -> int:
	var tribune_lvl : int = upgrades.get("tribune", 0)
	return (tribune_lvl + 1) * TRIBUNE_CAPACITY_PER_LEVEL

## Full serialization for save files (career.json) — identity, crest, colors,
## standings and the whole squad. Upgrades/scouted pool/training slots are
## intentionally excluded: those already persist separately via GameState's
## upgrades.json/staff.json, keyed off whichever club is currently player_club.
func to_dict() -> Dictionary:
	var players_data : Array = []
	for p in players:
		players_data.append(p.to_dict())
	return {
		"id": id,
		"display_name": display_name,
		"team_key": team_key,
		"division": division,
		"tournament_points": tournament_points,
		"matches_played": matches_played,
		"wins": wins,
		"draws": draws,
		"losses": losses,
		"goals_for": goals_for,
		"goals_against": goals_against,
		"primary_color": primary_color.to_html(false),
		"secondary_color": secondary_color.to_html(false),
		"logo_path": logo_path,
		"logo_template": logo_template,
		"budget": budget,
		"fans": fans,
		"players": players_data,
	}

static func from_dict(d: Dictionary) -> ClubResource:
	var club := ClubResource.new(
		d.get("id", ""),
		d.get("display_name", ""),
		d.get("team_key", ""),
		d.get("division", "E"),
		Color.html(d.get("primary_color", "ffffff")),
		Color.html(d.get("secondary_color", "ffffff")),
		d.get("logo_path", ""),
		d.get("logo_template", 0),
		d.get("budget", 0),
		d.get("tournament_points", 0)
	)
	club.matches_played = d.get("matches_played", 0)
	club.wins = d.get("wins", 0)
	club.draws = d.get("draws", 0)
	club.losses = d.get("losses", 0)
	club.goals_for = d.get("goals_for", 0)
	club.goals_against = d.get("goals_against", 0)
	club.fans = maxi(FanEconomy.MIN_FANS, d.get("fans", FanEconomy.MIN_FANS))
	for pd in d.get("players", []) as Array:
		club.players.append(PlayerResource.from_dict(pd))
	return club
