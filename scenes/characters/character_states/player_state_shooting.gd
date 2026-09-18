class_name PlayerStateShooting
extends PlayerState

## Convert sho stat (0–100) to actual pixel/s velocity.
## BallStateShot applies NO friction for 1000 ms, then hands off to FREEFORM,
## which decelerates it at Ball.FRICTION_GROUND (150 px/s²) to a stop. Total
## distance a shot can cover before dying is speed×1.0s (hot phase) PLUS
## speed²/(2×150) (the extra ground it covers while decelerating) — NOT just
## speed×1.0s. A max-power shot (274) covers 274+274²/300 ≈ 524px before
## stopping, comfortably past a full-power forward's own 420px effective
## shot range (SHOT_DISTANCE × up to 1.0, see
## OnBallUtility.effective_shot_range) — so the range here is intentionally
## generous. (A prior pass at this file assumed the ball simply stops dead at
## the 1s mark and cranked these way up to compensate, which made shots look
## like unrealistic rockets — reverted.)
## These were retuned down from 150/300 when FRICTION_GROUND dropped 200→150
## (see Ball.FRICTION_GROUND) specifically to keep total shot distance
## unchanged — lower ground friction alone would have let the same speed
## carry noticeably farther, since shots (unlike pass_to()) don't size their
## launch speed off distance-to-target.
const SHOT_SPEED_MIN := 140.0   # sho=0  → ~140 px/s
const SHOT_SPEED_MAX := 274.0   # sho=100 → ~274 px/s

func _enter_tree() -> void:
	player.play_anim("kick")
	
func on_animation_complete() -> void:
	shoot_ball()
	transition_state(Player.State.MOVING)
	
func shoot_ball() -> void:
	var actual_speed := SHOT_SPEED_MIN + (state_data.shot_power / 100.0) * (SHOT_SPEED_MAX - SHOT_SPEED_MIN)
	ball.shoot(state_data.shot_direction * actual_speed)
