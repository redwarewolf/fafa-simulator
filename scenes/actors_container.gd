class_name ActorsContainer
extends Node2D

const DURATION_WEIGHT_CACHE := 200 # Tal vez deba aumentar esta variable de refresco para performance
const PLAYER_PREFAB := preload("res://scenes/characters/player.tscn")

@export var ball : Ball
@export var goal_left : Goal
@export var goal_right : Goal

@export var team_left : String
@export var team_right : String

@onready var spawns_left : Node2D = $SpawnsLeft
@onready var spawns_right : Node2D = %SpawnsRight

var left_team : Array[Player] = []
var right_team : Array[Player] = []

var time_since_last_cache_refresh := Time.get_ticks_msec()

func _ready() -> void:
	left_team = spawn_players(team_left, goal_left, spawns_left)
	right_team = spawn_players(team_right, goal_right, spawns_right)
	for player in left_team:
		player.teammates = left_team
	for player in right_team:
		player.teammates = right_team
	
func spawn_players(team : String, own_goal : Goal,spawns) -> Array[Player]:
	var player_nodes : Array[Player] = []
	var players := DataLoader.get_team(team)
	var target_goal := goal_right if own_goal == goal_left else goal_left
	for i in players.size():
		var player_position := spawns.get_child(i).global_position as Vector2
		var player_data := players[i] as PlayerResource
		var player := spawn_player(player_position, own_goal, target_goal, player_data, team)
		player_nodes.append(player)
		add_child(player)
	return player_nodes
	
func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - time_since_last_cache_refresh > DURATION_WEIGHT_CACHE:
		time_since_last_cache_refresh = Time.get_ticks_msec()
		set_on_duty_weights()
		
func spawn_player(player_position : Vector2, own_goal: Goal, target_goal: Goal, player_data : PlayerResource, team: String) -> Player:
	var player := PLAYER_PREFAB.instantiate()
	return player.initialize(player_position, ball, own_goal, target_goal, player_data, team )	

func set_on_duty_weights() -> void:
	for team in [left_team, right_team]:
		var players : Array[Player] = team.filter(
			func(p: Player) : return p.role != Player.Role.GOALIE
		)
		players.sort_custom(func(p1: Player, p2 : Player):
			return p1.spawn_position.distance_squared_to(ball.position) < p2.spawn_position.distance_squared_to(ball.position))
			
		for i in range(players.size()):
			players[i].weight_on_duty_steering = 1 - ease(float(i) / 10.0, 0.1) #Revisar con mas jugadores aumentar el 10.0 a un numero mayor
			
