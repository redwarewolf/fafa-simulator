class_name AIBehavior
extends Node

## Per-player entry point the controllable player states (MOVING,
## HOLDING_BALL) call every frame. It hands the frame to the player's
## engine-v2 brain: PlayerBrain for outfield players, GoalkeeperBrain for
## keepers (see scenes/match/brain/ and docs/match-engine-v2.md). Players that
## can't move (SpecialPlayerTypes) have no brain and do nothing.

var ball: Ball = null
var player: Player = null
var opponent_detection_area: Area2D = null

func setup(context_player: Player, context_ball: Ball, context_opponent_detection_area: Area2D) -> void:
	player = context_player
	ball = context_ball
	opponent_detection_area = context_opponent_detection_area

func process_ai() -> void:
	if not SpecialPlayerTypes.movable(player.special_type):
		return
	if player.brain != null:
		player.brain.process()
	elif player.keeper_brain != null:
		player.keeper_brain.process()
