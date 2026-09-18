class_name PlayerStateDispossessed
extends PlayerState

## The clean-strip counterpart to PlayerStateHurt (see Player.on_tackle_player) —
## a successful tackle that wasn't ruled a foul. Same ball-tumble/recovery
## shape as being hurt, but reuses Player.dodge_hop()'s small bounce instead of
## the "hurt" animation, so it reads as a non-aggressive dispossession rather
## than an injury.
const DURATION_DISPOSSESSED := 400
const AIR_FRICTION := 35.0
const HOP_HEIGHT_VELOCITY := 1.0
const BALL_TUMBLE_SPEED := 100.0

var time_start_dispossessed := Time.get_ticks_msec()

func _enter_tree() -> void:
	time_start_dispossessed = Time.get_ticks_msec()
	player.height_velocity = HOP_HEIGHT_VELOCITY
	player.height = 0.05
	if ball.carrier == player:
		ball.tumble(state_data.hurt_direction * BALL_TUMBLE_SPEED)

func _process(delta: float) -> void:
	if Time.get_ticks_msec() - time_start_dispossessed > DURATION_DISPOSSESSED:
		transition_state(Player.State.RECOVERING)
	player.velocity = player.velocity.move_toward(Vector2.ZERO, delta * AIR_FRICTION)
