class_name MidfielderBehavior
extends RoleBehavior

const SHOT_DISTANCE := 220.0
const TACKLE_DISTANCE := 15.0
const SPREAD_ASSIST_FACTOR := 0.8

func get_positioning_force() -> Vector2:
	if player_has_ball():
		return get_carrier_positioning()
	elif is_ball_carried_by_teammate():
		return get_support_positioning()
	else:
		return get_on_duty_positioning()

func get_carrier_positioning() -> Vector2:
	# Midfielders advance toward goal when carrying
	var target := target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 100, 0.5, 200, 0.9)
	return direction * weight

func get_support_positioning() -> Vector2:
	# Spread out to be available for passes
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * SPREAD_ASSIST_FACTOR
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 60, 0.2, 90, 1.0)
	return direction * weight

func get_on_duty_positioning() -> Vector2:
	# Move toward ball based on on-duty weight
	return player.weight_on_duty_steering * player.position.direction_to(ball.position)

func make_decisions() -> void:
	if player_has_ball():
		# Midfielders balance between shooting and passing
		var distance_to_goal := player.position.distance_to(target_goal.get_center_target_position())
		
		if distance_to_goal < SHOT_DISTANCE and not has_opponents_nearby():
			# Take a shot if in reasonable range and not pressured
			var shot_direction := player.position.direction_to(target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
		elif has_opponents_nearby() or distance_to_goal > SHOT_DISTANCE:
			# Pass if pressured or too far from goal
			player.switch_state(Player.State.PASSING)
	
	# Tackle if opponent with ball is nearby
	if is_ball_carried_by_opponent() and player_is_on_tackle_distance(TACKLE_DISTANCE):
		player.switch_state(Player.State.TACKLING)
