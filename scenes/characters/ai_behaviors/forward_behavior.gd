class_name ForwardBehavior
extends RoleBehavior

const SHOT_DISTANCE := 280.0 # Forwards shoot from further out
const TACKLE_DISTANCE := 15.0
const SPREAD_ASSIST_FACTOR := 0.9

func get_positioning_force() -> Vector2:
	if player_has_ball():
		return get_carrier_positioning()
	elif is_ball_carried_by_teammate():
		return get_attacking_run_positioning()
	else:
		return get_pressing_positioning()

func get_carrier_positioning() -> Vector2:
	# Aggressively advance toward goal
	var target := target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 80, 0.7, 180, 1.0)
	return direction * weight

func get_attacking_run_positioning() -> Vector2:
	# Make runs into attacking space when teammate has ball
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * SPREAD_ASSIST_FACTOR
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 70, 0.3, 100, 1.0)
	return direction * weight

func get_pressing_positioning() -> Vector2:
	# Press high up the field toward the ball
	var on_duty_force := player.weight_on_duty_steering * player.position.direction_to(ball.position)
	
	# But bias toward attacking third
	var attacking_third_target := target_goal.get_center_target_position().lerp(ball.position, 0.7)
	var to_attacking_area := player.position.direction_to(attacking_third_target)
	
	return (on_duty_force * 0.7 + to_attacking_area * 0.3)

func make_decisions() -> void:
	if player_has_ball():
		var distance_to_goal := player.position.distance_to(target_goal.get_center_target_position())
		
		# Forwards prioritize shooting
		if distance_to_goal < SHOT_DISTANCE:
			var shot_direction := player.position.direction_to(target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
		elif has_opponents_nearby():
			# Only pass if under pressure and far from goal
			player.switch_state(Player.State.PASSING)
	
	# Aggressive tackling in attacking third
	if is_ball_carried_by_opponent() and player_is_on_tackle_distance(TACKLE_DISTANCE):
		player.switch_state(Player.State.TACKLING)
