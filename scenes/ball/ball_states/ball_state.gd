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
		if ball.velocity.x >= 0:
			animation_player.play("roll")
		else:
			animation_player.play_backwards("roll")
		animation_player.advance(0)
		
func process_gravity(delta: float, bounciness: float = 0.0) -> void:
	if ball.height > 0 or ball.height_velocity > 0:
		ball.height_velocity -= GRAVITY * delta
		ball.height += ball.height_velocity
		if ball.height <= 0:
			ball.height = 0
			if bounciness > 0.0 and ball.height_velocity < 0:
				ball.height_velocity = -ball.height_velocity * bounciness
				ball.velocity *= Ball.GROUND_BOUNCE_ROLL
			
			
func can_air_interact() -> bool:
	return false

func move_and_bounce(delta: float) -> void:
	var collision := ball.move_and_collide(ball.velocity * delta)
	if collision != null:
		# A keeper's own kick leaving his (always-on) hands collider: pass
		# through instead of "parrying" it dead at his feet. PassTracer found
		# engine-v2 keeper passes rated 0.98 completing 41% — the ball stopped
		# 0.3s after release and the keeper re-collected it, or an opponent did.
		var own := _player_owning(collision.get_collider())
		if own != null and own.keeper_brain != null and ball.is_kick_cooldown(own):
			ball.position += collision.get_remainder()
			return
		ball.velocity = ball.velocity.bounce(collision.get_normal()) * ball.BOUNCINESS
		ball.switch_state(Ball.State.FREEFORM)
		var toucher := _player_owning(collision.get_collider())
		if toucher != null:
			ball.last_touch = toucher  # e.g. a keeper's parry off GoalieHands
			if toucher.keeper_brain != null:
				toucher.keeper_brain.on_ball_contact()  # engine-v2 keeper: catch or parry
		var obstacle := collision.get_collider() as Player
		if obstacle != null and SpecialPlayerTypes.bounces_ball(obstacle.special_type):
			obstacle.get_hurt(ball.global_position.direction_to(obstacle.global_position))

## The Player a collider belongs to (the body itself, or an ancestor — the
## keeper's GoalieHands body is a child of the Player), or null for walls/goals.
static func _player_owning(collider: Object) -> Player:
	var node := collider as Node
	while node != null:
		if node is Player:
			return node
		node = node.get_parent()
	return null
