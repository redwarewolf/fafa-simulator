class_name PlayerStateShooting
extends PlayerState

## Shot speed from shot power (0–100). BallStateShot applies no friction for
## its first second, then hands off to FREEFORM, which decelerates at
## Ball.FRICTION_GROUND — so a shot carries well past any goal; the net or the
## out-of-play line stops it.
##
## Real shots travel ~20-30 m/s; at ~21 px/m along the pitch that's ~420-620
## px/s. The pre-Phase-8 range (140-274 px/s, ~7-13 m/s) made shots crawl: a
## keeper that actually reads the ball saved nearly everything
## (docs/match-engine-v2.md Findings #8).
const SHOT_SPEED_MIN := 300.0   # power 0
const SHOT_SPEED_MAX := 560.0   # power 100

func _enter_tree() -> void:
	player.play_anim("kick")

func on_animation_complete() -> void:
	shoot_ball()
	transition_state(Player.State.MOVING)

func shoot_ball() -> void:
	var actual_speed := SHOT_SPEED_MIN + (state_data.shot_power / 100.0) * (SHOT_SPEED_MAX - SHOT_SPEED_MIN)
	GameEvents.shot_taken.emit(player, player.position)
	ball.shoot(state_data.shot_direction * actual_speed)
