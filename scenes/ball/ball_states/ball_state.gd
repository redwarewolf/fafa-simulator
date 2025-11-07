class_name BallState
extends Node

signal state_transition_requested(new_state: BallState)

var ball : Ball = null
var carrier : Player = null
var player_detection_area : Area2D = null

func setup(context_ball: Ball) -> void:
	ball = context_ball
	player_detection_area = context_ball.player_detection_area
	carrier = context_ball.carrier
