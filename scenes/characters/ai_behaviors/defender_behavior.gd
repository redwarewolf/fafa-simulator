class_name DefenderBehavior
extends RoleBehavior

const SHOT_DISTANCE := 250.0
const TACKLE_DISTANCE := 15.0

## Defenders stay 1 depth behind the ball, capped between own defense (1) and own center (3).
func calculate_target_zone(ball_zone: FieldZones.Zone) -> FieldZones.Zone:
	var ball_depth := field_zones.get_zone_depth(ball_zone, _is_left_team)
	var target_depth := clampi(ball_depth - 1, 1, 3)
	return _zone_from_depth(target_depth)

func get_fine_positioning_force() -> Vector2:
	if player_has_ball():
		return _carrier_positioning()
	elif is_ball_carried_by_teammate():
		return _support_positioning()
	else:
		return _defensive_positioning()

func _carrier_positioning() -> Vector2:
	var target := target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 150, 0.3, 300, 0.7)
	return direction * weight

func _support_positioning() -> Vector2:
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * 0.6
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 60, 0.2, 90, 1.0)
	return direction * weight

func _defensive_positioning() -> Vector2:
	var goal_center := own_goal.get_center_target_position()
	var ball_to_goal := ball.position.direction_to(goal_center)
	var defensive_position := ball.position + ball_to_goal * 100.0
	var direction := player.position.direction_to(defensive_position)
	return direction * player.weight_on_duty_steering

func make_fine_decisions() -> void:
	if player_has_ball():
		if has_opponents_nearby():
			player.switch_state(Player.State.PASSING)
		elif player.position.distance_to(target_goal.get_center_target_position()) < SHOT_DISTANCE:
			var shot_direction := player.position.direction_to(target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
	if is_ball_carried_by_opponent() and player_is_on_tackle_distance(TACKLE_DISTANCE):
		player.switch_state(Player.State.TACKLING)

