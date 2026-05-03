class_name GoalieBehavior
extends RoleBehavior

const PROXIMITY_CONCERN := 10.0

func calculate_target_zone(_ball_zone: FieldZones.Zone) -> FieldZones.Zone:
	return home_zone  # Goalie never leaves their zone

func get_fine_positioning_force() -> Vector2:
	var top := own_goal.get_top_target_position()
	var bottom := own_goal.get_bottom_target_position()
	var center := player.spawn_position
	var target_y := clampf(ball.position.y, top.y, bottom.y)
	var destination := Vector2(center.x, target_y)
	var direction := player.position.direction_to(destination)
	var distance_to_destination := player.position.distance_to(destination)
	var weight := clampf(distance_to_destination / PROXIMITY_CONCERN, 0.0, 1.0)
	return weight * direction

func make_fine_decisions() -> void:
	if ball.is_headed_for_scoring_area(
		own_goal.get_top_target_position(),
		own_goal.get_bottom_target_position()
	):
		player.switch_state(Player.State.DIVING)
