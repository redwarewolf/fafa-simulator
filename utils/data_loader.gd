extends Node

## Clubs are no longer loaded from static JSON at startup — every club in the
## game now comes from ClubFactory (a fully procedural Division E, generated
## by Team Creation on New Game or restored by GameState.load_career()) and
## is registered here at runtime. The original hand-authored preset clubs
## (assets/json/clubs/*.json) stay on disk, unused, in case they're wanted
## again later.

## All active clubs keyed by their stable id (e.g. "deportivo-rayo-test").
var clubs : Dictionary[String, ClubResource]


## Returns the ClubResource for the given stable id, or null if not found.
func get_club(id: String) -> ClubResource:
	if clubs.has(id):
		return clubs[id]
	printerr("DataLoader: club not found: ", id)
	return null


## Returns all clubs in the given division.
func get_clubs_in_division(division: String) -> Array[ClubResource]:
	var result : Array[ClubResource] = []
	for club in clubs.values():
		if club.division == division:
			result.append(club)
	return result


## Returns the player array for a club by its stable id (convenience helper).
func get_team(id: String) -> Array[PlayerResource]:
	var club := get_club(id)
	if club == null:
		return []
	return club.players


## Returns the ClubResource whose team_key matches the given key (e.g. "SACA CHISPAS").
## Used by ActorsContainer which identifies teams by their uppercase key.
func get_club_by_team_key(team_key: String) -> ClubResource:
	for club in clubs.values():
		if club.team_key == team_key:
			return club
	printerr("DataLoader: no club found with team_key: ", team_key)
	return null
