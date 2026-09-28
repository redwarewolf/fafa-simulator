extends Node

## Integration check for Phase 2 rules in a real (headless) match scene:
## kicks the ball at each line in turn and checks the restart awarded.
##   <godot_console.exe> --path . --headless --fixed-fps 60 res://tools/rules_probe.tscn
## Exits 1 if any case fails.

const WORLD_SCENE := preload("res://scenes/world/world.tscn")

var _last_award := {}

func _ready() -> void:
	MatchConfig.reset_to_defaults()
	MatchConfig.headless = true
	MatchConfig.disable_random_events = true
	MatchConfig.match_seed = 99
	seed(4242)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var clubs := ClubFactory.generate_ai_clubs("E", 2, [], [], rng)
	DataLoader.clubs.clear()
	for c in clubs:
		DataLoader.clubs[c.id] = c
	GameState.test_match_teams = [clubs[0].team_key, clubs[1].team_key]
	GameEvents.restart_awarded.connect(func(kind, team, spot): _last_award = {"kind": kind, "team": team, "spot": spot})
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	var world : MatchWorld = WORLD_SCENE.instantiate()
	add_child(world)
	# Let the kickoff happen.
	var guard := 0
	while world.state != MatchWorld.MatchState.IN_PLAY and guard < 900:
		await get_tree().process_frame
		guard += 1
	var ac := world.actors_container
	var failures := 0
	var cy := (PitchSpace.TOP_Y + PitchSpace.BOTTOM_Y) * 0.5
	var cases := [
		# [name, start (abs-normalised), target px, last toucher side ("L"/"R"), expected kind, expected awarded side]
		["throw-in top, L touched", Vector2(0.5, 0.2), Vector2(1150, 60), "L", Restart.Kind.THROW_IN, "R"],
		["throw-in bottom, R touched", Vector2(0.4, 0.8), Vector2(950, 1200), "R", Restart.Kind.THROW_IN, "L"],
		["right goal line wide, L touched", Vector2(0.9, 0.15), Vector2(2400, 250), "L", Restart.Kind.GOAL_KICK, "R"],
		["right goal line wide, R touched", Vector2(0.9, 0.15), Vector2(2400, 250), "R", Restart.Kind.CORNER, "L"],
		["left goal line wide, L touched", Vector2(0.1, 0.85), Vector2(-100, 1000), "L", Restart.Kind.CORNER, "R"],
	]
	for c in cases:
		# Wait for any previous restart to finish. With every player frozen the
		# restart can only end by its safety timeout (RESTART_TIMEOUT + the
		# kind's set-up time — 32s for a corner).
		guard = 0
		while world.state != MatchWorld.MatchState.IN_PLAY and guard < 2400:
			await get_tree().process_frame
			guard += 1
		# A goal kick from the previous case leaves the keeper holding the
		# ball (and about to distribute it) — release it first.
		for p in ac.left_team + ac.right_team:
			p.process_mode = Node.PROCESS_MODE_DISABLED
			if p.current_state != null and p.current_state.is_holding_ball():
				p.switch_state(Player.State.MOVING)
		await _frames(2)
		_last_award = {}
		var toucher : Player = ac.left_team[1] if c[3] == "L" else ac.right_team[1]
		var ball := ac.ball
		ball.carrier = null
		ball.position = PitchSpace.from_absolute_normalised(c[1])
		ball.height = 0.0
		ball.height_velocity = 0.0
		ball.switch_state(Ball.State.FREEFORM)
		ball.last_touch = toucher
		ball.velocity = ball.position.direction_to(c[2]) * 900.0
		# Freeze everyone for the duration of the case: a disabled body also
		# leaves the physics world, so nobody intercepts, tackles or picks up
		# the ball — this probes the rules, not the AI.
		for p in ac.left_team + ac.right_team:
			p.process_mode = Node.PROCESS_MODE_DISABLED
		await _frames(120)
		var want_team : String = ac.team_left if c[5] == "L" else ac.team_right
		var ok : bool = not _last_award.is_empty() and _last_award["kind"] == c[4] and _last_award["team"] == want_team
		print("%s  %s  → %s" % ["PASS" if ok else "FAIL", c[0], str(_last_award)])
		if not ok:
			failures += 1
	# ─── Offside: staged positions, real OffsideJudge ────────────────────────
	# Left team attacks right (x→1). Right team's outfielders sit at depth 0.75
	# (left-team frame), keeper at 0.98 → the offside line is 0.75.
	var offside_cases := [
		["receiver beyond the line → offside", 0.85, true],
		["receiver level-ish behind the line → onside", 0.70, false],
	]
	for oc in offside_cases:
		guard = 0
		while world.state != MatchWorld.MatchState.IN_PLAY and guard < 2400:
			await get_tree().process_frame
			guard += 1
		for p in ac.left_team + ac.right_team:
			p.process_mode = Node.PROCESS_MODE_DISABLED
			if p.current_state != null and p.current_state.is_holding_ball():
				p.switch_state(Player.State.MOVING)
		await _frames(2)
		for i in ac.right_team.size():
			var d : Player = ac.right_team[i]
			var depth := 0.98 if d.role == Positions.Role.GK else 0.75
			d.position = PitchSpace.from_normalised(Vector2(depth, 0.1 + 0.08 * i), true)
		var passer : Player = ac.left_team[1]
		var receiver : Player = ac.left_team[2]
		for i in ac.left_team.size():
			ac.left_team[i].position = PitchSpace.from_normalised(Vector2(0.3, 0.1 + 0.08 * i), true)
		passer.position = PitchSpace.from_normalised(Vector2(0.6, 0.5), true)
		receiver.position = PitchSpace.from_normalised(Vector2(oc[1], 0.55), true)
		_last_award = {}
		# The previous (timed-out) corner leaves "no offside from the next
		# kick" armed — that exemption would swallow this staged pass.
		world._offside_judge.exempt_next_kick = false
		ac.ball.carrier = passer
		GameEvents.pass_attempted.emit(passer, receiver, receiver.position)
		ac.ball.carrier = null
		ac.ball.carrier = receiver
		await _frames(3)
		var called : bool = not _last_award.is_empty() and _last_award["kind"] == Restart.Kind.OFFSIDE
		var ok : bool = called == oc[2]
		print("%s  %s  → %s" % ["PASS" if ok else "FAIL", oc[0], str(_last_award)])
		if not ok:
			failures += 1
		ac.ball.carrier = null
	var total := cases.size() + offside_cases.size()
	print("\nrules probe: %d/%d passed" % [total - failures, total])
	get_tree().quit(1 if failures > 0 else 0)
