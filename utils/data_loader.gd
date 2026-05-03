extends Node

const CLUBS_DIR := "res://assets/json/clubs/"

## All loaded clubs keyed by their stable id (e.g. "saca-chispas").
var clubs : Dictionary[String, ClubResource]


func _init() -> void:
	var dir := DirAccess.open(CLUBS_DIR)
	if dir == null:
		printerr("DataLoader: could not open clubs directory: ", CLUBS_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_club(CLUBS_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_club(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("DataLoader: could not open ", path)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		printerr("DataLoader: could not parse ", path)
		file.close()
		return
	file.close()

	var d : Dictionary = json.data
	var club := ClubResource.new(
		d.get("id", ""),
		d.get("display_name", ""),
		d.get("team_key", ""),
		d.get("division", "E"),
		d.get("primary_color", 0),
		d.get("secondary_color", 0),
		d.get("logo_path", ""),
		d.get("budget", 0)
	)

	for p in d.get("players", []) as Array:
		club.players.append(PlayerResource.new(
			p["name"] as String,
			p["skin"] as Player.SkinColor,
			p["role"] as Player.Role,
			p["age"] as int,
			p["quality"] as PlayerResource.Quality,
			p["pac"] as int,
			p["sho"] as int,
			p["pas"] as int,
			p["dri"] as int,
			p["def"] as int,
			p["phy"] as int
		))

	clubs[club.id] = club


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
