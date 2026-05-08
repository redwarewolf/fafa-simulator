class_name PlayerStateHoldingBall
extends PlayerState

const BALL_HOLD_HEIGHT := 12.0

func _enter_tree() -> void:
	ball.carrier = player
	ball.switch_state(Ball.State.CARRIED)
	ball.height = BALL_HOLD_HEIGHT
	ball.height_velocity = 0.0  # Clear any residual vertical momentum from before catch
	_update_animation()

func _process(_delta: float) -> void:
	ball.height = BALL_HOLD_HEIGHT  # Maintain height each frame, overriding gravity
	ball.height_velocity = 0.0     # Prevent gravity accumulation inside BallStateCarried
	_update_facing()
	_update_animation()
	ai_behavior.process_ai()

## When stationary, face toward the target goal so the keeper always looks forward.
## When moving, heading is driven normally by velocity via Player.set_heading().
## Also keeps the teammate detection cone pointing the right way so pass targets are found.
func _update_facing() -> void:
	if player.velocity.length() < 1.0:
		player.heading = Vector2.LEFT if target_goal.position.x < player.position.x else Vector2.RIGHT
		# Rotate the detection cone to face heading so get_closest_teammate_in_view() works
		teammate_detection_area.rotation = player.heading.angle()

func _exit_tree() -> void:
	ball.height = 0.0
	ball.height_velocity = 0.0  # Clear accumulated gravity so the released ball starts clean

func _update_animation() -> void:
	if player.velocity.length() < 1.0:
		# Show the first hold frame and freeze — don't play idle (arms at sides)
		if animation_player.current_animation != "walk_ball":
			animation_player.play("walk_ball")
			animation_player.seek(0.0, true)
		animation_player.pause()
	else:
		if not animation_player.is_playing() or animation_player.current_animation != "walk_ball":
			animation_player.play("walk_ball")

func can_carry_ball() -> bool:
	return true

func is_holding_ball() -> bool:
	return true
