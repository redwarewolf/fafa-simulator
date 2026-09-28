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

# ─── Match-analytics events (engine v2 — see docs/match-engine-v2.md) ────────
# Typed, player-carrying counterparts to the name-only ball_possessed above.
# Consumed by MatchStats (headless batch harness) and, from Phase 2, the
# offside judge / restart manager. Nothing in the match flow depends on them.

## A player took control of the ball (Ball.carrier went from anything to them).
signal possession_gained(player: Player)

## A pass was kicked. [param receiver] is the intended teammate, or null for
## an untargeted kick (e.g. a goalkeeper clearance). [param destination] is
## where the ball was aimed (already led for a moving receiver).
signal pass_attempted(passer: Player, receiver: Player, destination: Vector2)

## A shot was struck (ground shot, header, volley or bicycle kick).
signal shot_taken(shooter: Player, origin: Vector2)

## A tackle made contact with the carrier. [param won] = ball changed hands
## (cleanly or via foul); [param foul] = the referee called it.
signal tackle_resolved(tackler: Player, carrier: Player, won: bool, foul: bool)

## A set-piece restart was awarded (Restart.Kind) to [param team] at [param spot].
## Fired for fouls too, alongside foul_called.
signal restart_awarded(kind: int, team: String, spot: Vector2)

## The engine-v2 keeper read a shot: [param p_save] was his save probability,
## [param save] the rolled outcome (GoalkeeperBrain).
signal keeper_decision(keeper: Player, p_save: float, save: bool)

## [param player] failed to control an arriving ball (first touch).
signal heavy_touch(player: Player)

## The assistant flagged [param offender] offside (OffsideJudge).
signal offside_called(offender: Player)
