class_name DefenderBehavior
extends RoleBehavior

const DEFENSIVE_LINE_FACTOR := 0.25 # Stay in defensive third
const SHOT_DISTANCE := 250.0
const TACKLE_DISTANCE := 15.0

func get_positioning_force() -> Vector2:
	if player_has_ball():
		return get_carrier_positioning()
	elif is_ball_carried_by_teammate():
		return get_support_positioning()
	else:
		return get_defensive_positioning()

func get_carrier_positioning() -> Vector2:
	# When defender has ball, advance cautiously toward midfield
	var target := target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 150, 0.3, 300, 0.7)
	return direction * weight

func get_support_positioning() -> Vector2:
	# Support teammate but stay back
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * 0.6 # Less aggressive than midfielders
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 60, 0.2, 90, 1.0)
	return direction * weight

func get_defensive_positioning() -> Vector2:
	# Stay between ball and own goal
	var goal_center := own_goal.get_center_target_position()
	var ball_to_goal := ball.position.direction_to(goal_center)
	var defensive_position := ball.position + ball_to_goal * 100.0
	
	var direction := player.position.direction_to(defensive_position)
	var weight := player.weight_on_duty_steering
	return direction * weight

func make_decisions() -> void:
	if player_has_ball():
		# Defenders prioritize safe passes over shots
		if has_opponents_nearby():
			player.switch_state(Player.State.PASSING)
		elif player.position.distance_to(target_goal.get_center_target_position()) < SHOT_DISTANCE:
			# Only shoot if very close and no better option
			var shot_direction := player.position.direction_to(target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
	
	# Tackle if ball carrier is nearby
	if is_ball_carried_by_opponent() and player_is_on_tackle_distance(TACKLE_DISTANCE):
		player.switch_state(Player.State.TACKLING)
