extends Node

## Compares the real ball (in a live match scene, all players frozen) against
## BallPredictor for a set of pass_to() kicks — validates the predictor, and
## surfaces any mismatch between a kick's intended and actual landing.
##   <godot_console.exe> --path . --headless --fixed-fps 60 res://tools/ball_probe.tscn

const WORLD_SCENE := preload("res://scenes/world/world.tscn")

func _ready() -> void:
	MatchConfig.reset_to_defaults()
	MatchConfig.headless = true
	MatchConfig.disable_random_events = true
	MatchConfig.match_seed = 5
	seed(777)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var clubs := ClubFactory.generate_ai_clubs("E", 2, [], [], rng)
	DataLoader.clubs.clear()
	for c in clubs:
		DataLoader.clubs[c.id] = c
	GameState.test_match_teams = [clubs[0].team_key, clubs[1].team_key]
	_run.call_deferred()

func _run() -> void:
	var world : MatchWorld = WORLD_SCENE.instantiate()
	add_child(world)
	for i in 30:
		await get_tree().process_frame
	var ac := world.actors_container
	var ball := ac.ball
	var from := PitchSpace.from_absolute_normalised(Vector2(0.3, 0.5))
	for kick in [["pass", 150.0], ["pass", 280.0], ["pass", 350.0], ["pass", 600.0], ["pass", 900.0], ["pass", 1100.0],
			["long_kick", 500.0], ["long_kick", 800.0]]:
		var kind : String = kick[0]
		var dist : float = kick[1]
		for p in ac.left_team + ac.right_team:
			p.process_mode = Node.PROCESS_MODE_DISABLED
		world.state = MatchWorld.MatchState.EVENT  # no out-of-play restarts during the probe
		ball.carrier = null
		ball.position = from
		ball.height = 0.0
		ball.height_velocity = 0.0
		ball.velocity = Vector2.ZERO
		ball.switch_state(Ball.State.FREEFORM)
		await get_tree().process_frame
		var to := from + Vector2(dist, 0)
		var predicted := BallPredictor.for_pass(from, to, 6.0)
		if kind == "pass":
			ball.pass_to(to)
		else:
			ball.long_kick(to)
		var actual := []
		var max_h := 0.0
		var first_land := -1.0
		var was_air := false
		for f in 360:
			await get_tree().physics_frame
			max_h = maxf(max_h, ball.height)
			if ball.height > 0.0:
				was_air = true
			elif was_air and first_land < 0.0:
				first_land = ball.position.x - from.x
			if f % 30 == 29:
				actual.append(ball.position.x - from.x)
		print("%-9s %4d  max_h %5.1f  first landing %6.0f (%3d%%)  stop %5.0f  actual@0.5s %s" % [
			kind, dist, max_h, first_land, int(100.0 * first_land / dist) if first_land >= 0.0 else -1,
			ball.position.x - from.x, str(actual.slice(0, 6).map(func(v): return int(v)))])
		if kind == "pass":
			var pred := []
			for t in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
				pred.append(int(predicted.position_at(t).x - from.x))
			print("                predicted@0.5s %s" % str(pred))
	get_tree().quit(0)
