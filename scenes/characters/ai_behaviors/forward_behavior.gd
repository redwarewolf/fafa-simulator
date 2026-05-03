class_name ForwardBehavior
extends RoleBehavior

const SHOT_DISTANCE := 280.0
const TACKLE_DISTANCE := 15.0
const SPREAD_ASSIST_FACTOR := 0.9

## Forwards press high — min own center (3), max opponent mid (5).
## They don't track all the way into opp defense; they stay available for counter-attacks.
func calculate_target_zone(ball_zone: FieldZones.Zone) -> FieldZones.Zone:
	var ball_depth := field_zones.get_zone_depth(ball_zone, _is_left_team)
	var target_depth := clampi(ball_depth, 3, 5)
	return _zone_from_depth(target_depth)

func get_fine_positioning_force() -> Vector2:
	if player_has_ball():
		return _carrier_positioning()
	elif is_ball_carried_by_teammate():
		return _attacking_run_positioning()
	else:
		return _pressing_positioning()

func _carrier_positioning() -> Vector2:
	var target := target_goal.get_center_target_position()
	var direction := player.position.direction_to(target)
	var weight := get_bicircular_weight(player.position, target, 80, 0.7, 180, 1.0)
	return direction * weight

func _attacking_run_positioning() -> Vector2:
	var spawn_difference := ball.carrier.spawn_position - player.spawn_position
	var assist_destination := ball.carrier.position - spawn_difference * SPREAD_ASSIST_FACTOR
	var direction := player.position.direction_to(assist_destination)
	var weight := get_bicircular_weight(player.position, assist_destination, 70, 0.3, 100, 1.0)
	return direction * weight

func _pressing_positioning() -> Vector2:
	var on_duty_force := player.weight_on_duty_steering * player.position.direction_to(ball.position)
	var attacking_third_target := target_goal.get_center_target_position().lerp(ball.position, 0.7)
	var to_attacking_area := player.position.direction_to(attacking_third_target)
	return on_duty_force * 0.7 + to_attacking_area * 0.3

func make_fine_decisions() -> void:
	if player_has_ball():
		var distance_to_goal := player.position.distance_to(target_goal.get_center_target_position())
		if distance_to_goal < SHOT_DISTANCE:
			var shot_direction := player.position.direction_to(target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
		elif has_opponents_nearby():
			player.switch_state(Player.State.PASSING)
	if is_ball_carried_by_opponent() and player_is_on_tackle_distance(TACKLE_DISTANCE):
		player.switch_state(Player.State.TACKLING)

