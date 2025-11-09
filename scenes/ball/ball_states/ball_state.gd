class_name BallState
extends Node

signal state_transition_requested(new_state: BallState)

var ball : Ball = null
var carrier : Player = null
var player_detection_area : Area2D = null
var animation_player : AnimationPlayer = null
var ball_sprite : Sprite2D = null

func setup(context_ball: Ball) -> void:
	ball = context_ball
	player_detection_area = context_ball.player_detection_area
	animation_player = context_ball.animation_player
	ball_sprite = context_ball.ball_sprite
	
	carrier = context_ball.carrier
