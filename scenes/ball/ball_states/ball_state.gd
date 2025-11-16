class_name BallState
extends Node

signal state_transition_requested(new_state: BallState)

const GRAVITY := 10.0

var ball : Ball = null
var carrier : Player = null
var player_detection_area : Area2D = null
var animation_player : AnimationPlayer = null
var ball_sprite : Sprite2D = null

func setup(context_ball: Ball) -> void:
	ball = context_ball
	player_detection_area = context_ball.player_detection_area
	animation_player = context_ball.animation_player
	ball_sprite = context_ball.ball_sprite
	
	carrier = context_ball.carrier
	
func set_ball_animation_from_velocity() -> void:
	if ball.velocity == Vector2.ZERO:
		animation_player.play("idle")
	else:
		ball.set_heading()
		ball.flip_sprites()
		animation_player.play("roll")
		
func process_gravity(delta: float, bounciness: float = 0.0) -> void:
	if ball.height > 0:
		ball.height_velocity -= GRAVITY * delta
		ball.height = ball.height_velocity
		if(ball.height <= 0):
			ball.height = 0
			if(bounciness > 0.0 and ball.height_velocity < 0):
				ball.height_velocity = -ball.height_velocity * bounciness
				ball.velocity *= bounciness
			
			
func can_air_interact() -> bool:
	return false

func move_and_bounce(delta: float) -> void:
	var collision := ball.move_and_collide(ball.velocity * delta)
	if collision != null:
		ball.velocity = ball.velocity.bounce(collision.get_normal()) * ball.BOUNCINESS
		ball.switch_state(Ball.State.FREEFORM)
