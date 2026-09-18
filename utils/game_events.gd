## GameEvents — global signal bus for match lifecycle events.
## All scenes communicate goal/reset/kickoff lifecycle through this autoload.
extends Node

## Emitted when a player takes possession of the ball.
signal ball_possessed(player_name: String)

## Emitted when the ball is released (shot, passed, tackled, or reset).
signal ball_released

## Emitted each frame (IN_PLAY only) with the current elapsed match time in seconds.
signal match_time_updated(elapsed: float)

## Emitted when a team concedes a goal.
## [param team] is the name of the team that conceded (i.e. the goal was scored ON them).
signal team_scored(team: String)

## Emitted after score has been updated so HUD can refresh.
signal score_changed

## Emitted to reset ball and players to spawn positions.
signal team_reset

## Emitted by ActorsContainer once all players are back at their spawn positions.
signal kickoff_ready

## Emitted by the world state machine to start play after a reset.
signal kickoff_started

## Emitted when match time expires.
signal game_over

## Emitted when a successful tackle is ruled a foul (see Player.on_tackle_player).
## [param fouled_player] will take the free kick; [param incident_position] is
## where the foul happened, for the referee to run to.
signal foul_called(fouled_player: Player, incident_position: Vector2)
