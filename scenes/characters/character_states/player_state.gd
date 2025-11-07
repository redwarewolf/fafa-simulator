class_name PlayerState
extends Node

signal state_transition_requested(new_state: Player.State)

var player : Player = null
var animation_player : AnimationPlayer = null

func setup(context_player: Player) -> void:
	player = context_player
	animation_player = player.animation_player
