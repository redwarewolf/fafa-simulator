class_name PlayerStateDiving
extends PlayerState

const DURATION_DIVE := 500

var time_start_dive := MatchClock.now_ms()
var _duration := DURATION_DIVE

func _enter_tree() -> void:
	var target_dive : Vector2
	if state_data.has_dive:
		# Engine-v2 keeper (GoalkeeperBrain): the brain already solved where
		# to go and how fast — reaching the ball, or falling just short.
		target_dive = state_data.dive_target
		player.velocity = player.position.direction_to(target_dive) * state_data.dive_speed
		_duration = state_data.dive_duration_ms
	else:
		# Predict where the ball will cross the goal line so the keeper dives to intercept,
		# not just where the ball is right now.
		var goal_x := player.spawn_position.x
		var predicted_y := ball.position.y
		if not is_zero_approx(ball.velocity.x):
			var t := (goal_x - ball.position.x) / ball.velocity.x
			if t > 0.0:
				predicted_y = ball.position.y + ball.velocity.y * t
		target_dive = Vector2(goal_x, predicted_y)
		player.velocity = player.position.direction_to(target_dive) * player.speed
	if target_dive.y > player.position.y:
		player.play_anim("dive_down")
	else:
		player.play_anim("dive_up")
	time_start_dive = MatchClock.now_ms()

func _process(_delta: float) -> void:
	if state_data.has_dive and player.position.distance_to(state_data.dive_target) < 3.0:
		player.velocity = Vector2.ZERO  # arrived — hold the stretch until the dive ends
	if MatchClock.now_ms() - time_start_dive > _duration:
		player.velocity = Vector2.ZERO
		if player.keeper_brain != null:
			player.keeper_brain.on_dive_finished()
		transition_state(Player.State.RECOVERING)
