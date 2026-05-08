class_name PlayerStatePassing
extends PlayerState

func _enter_tree() -> void:
	animation_player.play("kick")
	player.velocity = Vector2.ZERO

func on_animation_complete() -> void:
	var pass_target := get_closest_teammate_in_view()

	if pass_target == null:
		# Nobody ahead — try a back-pass to any teammate on the team
		pass_target = _get_closest_teammate_anywhere()

	if pass_target != null:
		print("[%s] ⚽ PASS → %s (dist=%.1f)" % [
			player.full_name, pass_target.full_name,
			player.position.distance_to(pass_target.position)])
		DebugDraw.line(player.position, pass_target.position, Color.GREEN, 2.0)
		DebugDraw.cross(pass_target.position, Color.GREEN, 5.0, 2.0)
		ball.pass_to(pass_target.position)
	else:
		# Truly nobody available — keep the ball and dribble
		print("[%s] ⚽ PASS — no target anywhere, keeping ball" % player.full_name)
		# ball.carrier remains set, ball stays in CARRIED — player will resume dribbling

	transition_state(Player.State.MOVING)

## Searches the full team list regardless of detection area — used as back-pass fallback.
func _get_closest_teammate_anywhere() -> Player:
	var all_teammates := player.get_teammates().filter(
		func(p: Player): return p != player and p.team == player.team
	)
	all_teammates.sort_custom(
		func(a: Player, b: Player):
			return a.position.distance_squared_to(player.position) < b.position.distance_squared_to(player.position)
	)
	return all_teammates[0] if all_teammates.size() > 0 else null

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

