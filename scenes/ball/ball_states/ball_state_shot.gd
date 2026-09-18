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
		# This state never calls process_gravity, so height/height_velocity are
		# still sitting at their _enter_tree values (SHOT_HEIGHT, 0) no matter
		# how long the shot has been flying. Left alone, FREEFORM sees
		# height > 0 and picks FRICTION_AIR (35) instead of FRICTION_GROUND
		# (250) — gravity then takes about another full second to bring height
		# back to 0, during which the ball barely decelerates at all. That
		# stacked a second near-frictionless phase onto every shot, making it
		# travel roughly twice as far as SHOT_SPEED implies. Ground it here so
		# FREEFORM applies real ground friction immediately.
		ball.height = 0.0
		ball.height_velocity = 0.0
		state_transition_requested.emit(Ball.State.FREEFORM)
	else:
		move_and_bounce(delta)

func _exit_tree() -> void:
	ball_sprite.scale.y = 1.0
