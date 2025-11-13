class_name ActorsContainer
extends Node2D

const PLAYER_PREFAB := preload("res://scenes/characters/player.tscn")

@export var ball : Ball
@export var goal_left : Goal
@export var goal_right : Goal

@export var team_left : String
@export var team_right : String

@onready var spawns_left : Node2D = $SpawnsLeft
@onready var spawns_right : Node2D = %SpawnsRight


func _ready() -> void:
	spawn_players(team_left, goal_left, spawns_left)
	spawn_players(team_right, goal_right, spawns_right)
	
func spawn_players(team : String, own_goal : Goal,spawns) -> void:
	var players := DataLoader.get_team(team)
	var target_goal := goal_right if own_goal == goal_left else goal_left
	for i in players.size():
		var player_position := spawns.get_child(i).global_position as Vector2
		var player_data := players[i] as PlayerResource
		var player := spawn_player(player_position, own_goal, target_goal, player_data)
		add_child(player)
		
func spawn_player(player_position : Vector2, own_goal: Goal, target_goal: Goal, player_data : PlayerResource) -> Player:
	var player := PLAYER_PREFAB.instantiate()
	return player.initialize(player_position, ball, own_goal, target_goal, player_data )	
