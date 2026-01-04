class_name PlayerStatePassing
extends PlayerState

func on_animation_complete() -> void:
	var pass_target := get_closest_teammate_in_view()
	if pass_target == null:
		# Me quieren sacar la pelota, que hago? agregar posible logica para tirarla hacia atras o seguir corriendo
		transition_state(Player.State.MOVING)

	else:
		animation_player.play("kick")
		player.velocity = Vector2.ZERO
		ball.pass_to(pass_target.position + pass_target.velocity)
	transition_state(Player.State.MOVING)
	
func get_closest_teammate_in_view() -> Player:
	var players_in_view := teammate_detection_area.get_overlapping_bodies()
	var teammates_in_view := players_in_view.filter(
		func(p: Player): return p != player and p.team == player.team
	)
	teammates_in_view.sort_custom(
		func(p1: Player, p2: Player): return p1.position.distance_squared_to(player.position) < p2.position.distance_squared_to(player.position)
	)
	if teammates_in_view.size() > 0:
		return teammates_in_view[0]
	return null


	
