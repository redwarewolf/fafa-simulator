class_name PlayerState
extends Node

signal state_transition_requested(new_state: Player.State, state_data: PlayerStateData)

var player : Player = null
var ball : Ball = null
var animation_player : AnimationPlayer = null
var state_data : PlayerStateData = PlayerStateData.new()
var teammate_detection_area : Area2D = null
var ball_detection_area : Area2D = null
var own_goal : Goal
var target_goal : Goal

func setup(context_player: Player, context_state_data: PlayerStateData) -> void:
	player = context_player
	ball = context_player.ball
	animation_player = player.animation_player
	state_data = context_state_data
	teammate_detection_area =  context_player.teammate_detection_area
	ball_detection_area = context_player.ball_detection_area
	own_goal = context_player.own_goal
	target_goal = context_player.target_goal

func transition_state(new_state: Player.State, context_state_data : PlayerStateData = PlayerStateData.new()) -> void:
	state_transition_requested.emit(new_state, context_state_data)

func on_animation_complete() -> void:
	pass
