class_name PlayerStateShooting
extends PlayerState

## Convert sho stat (0–100) to actual pixel/s velocity.
## BallStateShot applies NO friction for 1000 ms, so the ball travels:
##   speed × 1.0s pixels before decelerating.
## Max shot distance across all roles is ~280 px (ForwardBehavior),
## so SHOT_SPEED_MAX is tuned so a max-power shot just clears that distance.
const SHOT_SPEED_MIN := 150.0   # sho=0  → ~150 px/s  (~150 px range)
const SHOT_SPEED_MAX := 300.0   # sho=100 → ~300 px/s (~300 px range, just past max shoot distance)

func _enter_tree() -> void:
	animation_player.play("kick")
	
func on_animation_complete() -> void:
	shoot_ball()
	transition_state(Player.State.MOVING)
	
func shoot_ball() -> void:
	var actual_speed := SHOT_SPEED_MIN + (state_data.shot_power / 100.0) * (SHOT_SPEED_MAX - SHOT_SPEED_MIN)
	ball.shoot(state_data.shot_direction * actual_speed)
