class_name BallStateShot
extends BallState

const DURATION := 1000 
const SHOT_HEIGHT := 5
const SHOT_SPRITE_SCALE := 0.8

var time_since_shot := Time.get_ticks_msec()

func _enter_tree() -> void:
	set_ball_animation_from_velocity()
	ball_sprite.scale.y = SHOT_SPRITE_SCALE
	ball.height = SHOT_HEIGHT # Escalarlo según poder a futuro.
	time_since_shot = Time.get_ticks_msec()
	

func _physics_process(delta: float) -> void:
	if (Time.get_ticks_msec() - time_since_shot > DURATION): #Escalarlo según poder
		state_transition_requested.emit(Ball.State.FREEFORM)
	ball.move_and_bounce(delta)

func _exit_tree() -> void:
	ball_sprite.scale.y = 1.0
