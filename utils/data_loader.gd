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
				var full_name := player["name"] as String
				var skin := player["skin"] as Player.SkinColor
				var role := player["role"] as Player.Role
				var speed := player["speed"] as float
				var power := player["power"] as float
				var player_resource := PlayerResource.new(full_name,skin, role,speed,power)
				squads.get(team_name).append(player_resource)
		assert(players.size() == 6)
	squad_file.close()

func get_team(team: String) -> Array:
	if squads.has(team):
		return squads[team]
	else:
		printerr("The squad: " + team + " doesnt exist")
		return []
