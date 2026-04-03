extends Node

var squads : Dictionary[String, Array]

func _init() -> void:
	var squad_file := FileAccess.open("res://assets/json/squads.json", FileAccess.READ)
	if squad_file == null:
		printerr("Could not find Squads.json File at res://assets/json/squads.json")
	var squad_text := squad_file.get_as_text()
	var json := JSON.new()
	if json.parse(squad_text) != OK:
		printerr("Could not parse squads.json")
	for team_data in json.data:
		var team_name := team_data["team"] as String
		var players := team_data["players"] as Array
		if not squads.has(team_name):
			squads.set(team_name, [])
			for player in players:
				var player_resource := PlayerResource.new(
					player["name"] as String,
					player["skin"] as Player.SkinColor,
					player["role"] as Player.Role,
					player["age"] as int,
					player["quality"] as PlayerResource.Quality,
					player["pac"] as int,
					player["sho"] as int,
					player["pas"] as int,
					player["dri"] as int,
					player["def"] as int,
					player["phy"] as int
				)
				squads.get(team_name).append(player_resource)
	squad_file.close()

func get_team(team: String) -> Array:
	if squads.has(team):
		return squads[team]
	else:
		printerr("The squad: " + team + " doesnt exist")
		return []
