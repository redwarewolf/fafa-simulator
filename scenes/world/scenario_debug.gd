class_name ScenarioDebug
extends RefCounted

## Dev-only scripted match situations for checking a specific AI behavior in
## isolation instead of only ever eyeballing a full 90-minute sim — Phase 0 of
## docs/ai-overhaul.md. Teleports a handful of already-spawned players (plus
## the ball) into a named layout and freezes everyone else out of the way, so
## the normal AIBehavior/RoleAI/TeamTacticalState loop takes over from there
## unmodified — this only sets up the starting position, it isn't a separate
## simulation. Bound to number keys in MatchWorld._unhandled_input(), gated
## behind DebugDraw.ENABLED so it can never fire in a normal playthrough.
##
## [param pos] values are GLOBAL normalized pitch fractions — x=0 at the left
## edge (left team's own goal line), x=1 at the right edge, y=0 top touchline,
## y=1 bottom touchline — NOT the per-team-relative convention Formations.ALL
## uses, since a scenario has to place both teams in one shared frame.

const SCENARIOS: Dictionary = {
	# Left team breaks 2v1 on the right team's last defender + keeper.
	"2v1_break": [
		{ "team": "left", "role": Positions.Role.ST, "pos": Vector2(0.68, 0.50), "vel": Vector2(120, 0), "has_ball": true },
		{ "team": "left", "role": Positions.Role.LW, "pos": Vector2(0.70, 0.28), "vel": Vector2(110, 0) },
		{ "team": "right", "role": Positions.Role.CB, "pos": Vector2(0.82, 0.46) },
		{ "team": "right", "role": Positions.Role.GK, "pos": Vector2(0.96, 0.50) },
	],
	# Left team takes a corner against the right team's goal.
	"corner_defense": [
		{ "team": "left", "role": Positions.Role.ST, "pos": Vector2(0.985, 0.03), "has_ball": true },
		{ "team": "left", "role": Positions.Role.LW, "pos": Vector2(0.85, 0.42) },
		{ "team": "left", "role": Positions.Role.RW, "pos": Vector2(0.85, 0.58) },
		{ "team": "left", "role": Positions.Role.CM, "pos": Vector2(0.80, 0.50) },
		{ "team": "right", "role": Positions.Role.GK, "pos": Vector2(0.965, 0.50) },
		{ "team": "right", "role": Positions.Role.CB, "pos": Vector2(0.88, 0.44) },
		{ "team": "right", "role": Positions.Role.LB, "pos": Vector2(0.90, 0.62) },
	],
	# Right team's keeper builds out from the back under a left-team press.
	"goal_kick_buildup": [
		{ "team": "right", "role": Positions.Role.GK, "pos": Vector2(0.96, 0.50), "has_ball": true },
		{ "team": "right", "role": Positions.Role.CB, "pos": Vector2(0.82, 0.40) },
		{ "team": "right", "role": Positions.Role.CDM, "pos": Vector2(0.70, 0.50) },
		{ "team": "left", "role": Positions.Role.ST, "pos": Vector2(0.75, 0.50) },
		{ "team": "left", "role": Positions.Role.LW, "pos": Vector2(0.78, 0.38) },
		{ "team": "left", "role": Positions.Role.RW, "pos": Vector2(0.78, 0.62) },
	],
}

## Freezes every player, then un-freezes and repositions only the ones listed
## in [param scenario_name], and places the ball at whichever entry has
## has_ball=true. Everyone else stays disabled (PROCESS_MODE_DISABLED) so they
## can't interfere — same mechanism MatchWorld already uses for kickoff/foul
## restarts (see Player.is_restart_taker).
static func apply(scenario_name: String, actors_container: ActorsContainer) -> void:
	var entries: Array = SCENARIOS.get(scenario_name, [])
	if entries.is_empty():
		push_warning("ScenarioDebug: unknown scenario '%s'" % scenario_name)
		return

	for p in actors_container.left_team + actors_container.right_team:
		p.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

	var used: Dictionary = {}  # Player -> true, so two entries never grab the same body
	var ball_pos := actors_container.ball.position
	for entry: Dictionary in entries:
		var roster: Array[Player] = actors_container.left_team if entry["team"] == "left" else actors_container.right_team
		var candidate: Player = null
		for p in roster:
			if p.role == entry["role"] and not used.has(p):
				candidate = p
				break
		if candidate == null:
			push_warning("ScenarioDebug: no unused %s on %s team for scenario '%s'" % [
				Positions.label(entry["role"]), entry["team"], scenario_name])
			continue
		used[candidate] = true
		candidate.set_deferred("process_mode", Node.PROCESS_MODE_INHERIT)
		var world_pos := _norm_to_world(entry["pos"])
		candidate.position = world_pos
		candidate.velocity = entry.get("vel", Vector2.ZERO)
		if entry.get("has_ball", false):
			ball_pos = world_pos

	actors_container.ball.position = ball_pos
	actors_container.ball.velocity = Vector2.ZERO
	actors_container.ball.height = 0.0
	print("ScenarioDebug: applied '%s'" % scenario_name)

static func _norm_to_world(p: Vector2) -> Vector2:
	return Vector2(
		ActorsContainer.FIELD_LEFT + p.x * (ActorsContainer.FIELD_RIGHT - ActorsContainer.FIELD_LEFT),
		ActorsContainer.FIELD_TOP + p.y * (ActorsContainer.FIELD_BOTTOM - ActorsContainer.FIELD_TOP)
	)
