class_name PlayerStateDiving
extends PlayerState

const DURATION_DIVE := 500

var time_start_dive := Time.get_ticks_msec()

func _enter_tree() -> void:
	# Predict where the ball will cross the goal line so the keeper dives to intercept,
	# not just where the ball is right now.
	var goal_x := player.spawn_position.x
	var predicted_y := ball.position.y
	if not is_zero_approx(ball.velocity.x):
		var t := (goal_x - ball.position.x) / ball.velocity.x
		if t > 0.0:
			predicted_y = ball.position.y + ball.velocity.y * t
	var target_dive := Vector2(goal_x, predicted_y)
	var direction := player.position.direction_to(target_dive)
	if direction.y > 0:
		player.play_anim("dive_down")
	else:
		player.play_anim("dive_up")
	player.velocity = direction * player.speed
	time_start_dive = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - time_start_dive > DURATION_DIVE:
		player.velocity = Vector2.ZERO
		transition_state(Player.State.RECOVERING)
