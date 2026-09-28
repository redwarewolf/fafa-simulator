class_name MatchContext
extends Node

## The shared world model every v2 brain reads (docs/match-engine-v2.md
## Phase 3). It decides nothing: it maintains the pitch-control surface
## (staggered over frames), answers space/value queries, and draws the
## analytics debug overlays. Created by ActorsContainer when any side runs
## the v2 AI or an analytics overlay is on — v1-only matches skip its cost.

## A full pitch-control refresh is spread over this many frames (20 Hz at 60fps).
const FRAMES_PER_REFRESH := 3

var actors: ActorsContainer = null
var ball: Ball = null
var control := PitchControlGrid.new()
## Microseconds spent in the most recent _process — for the Phase 9 budget.
var last_update_usec := 0

## The most recent pass kicked: {"passer", "receiver", "left": bool, "time": s},
## or empty. Cleared when anyone gains possession or play restarts.
var last_pass := {}
## Refreshed by refresh_tactical() at the team-brain tick rate: where the loose
## ball is going, and each side's fastest player to it.
var ball_path : BallPredictor.BallPath = null
var first_left := {"player": null, "time": INF}
var first_right := {"player": null, "time": INF}

func setup(p_actors: ActorsContainer) -> void:
	actors = p_actors
	ball = p_actors.ball

func _ready() -> void:
	control.update_all(actors.left_team, actors.right_team)
	GameEvents.pass_attempted.connect(_on_pass_attempted)
	GameEvents.possession_gained.connect(_on_possession_gained)
	GameEvents.restart_awarded.connect(_on_restart)
	GameEvents.team_reset.connect(_clear_pass)
	refresh_tactical()

func _exit_tree() -> void:
	for pair in [
		[GameEvents.pass_attempted, _on_pass_attempted],
		[GameEvents.possession_gained, _on_possession_gained],
		[GameEvents.restart_awarded, _on_restart],
		[GameEvents.team_reset, _clear_pass],
	]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])

func _on_pass_attempted(passer: Player, receiver: Player, _dest: Vector2) -> void:
	last_pass = {"passer": passer, "receiver": receiver, "left": passer.is_left_team, "time": MatchClock.now()}

func _on_possession_gained(_p: Player) -> void:
	_clear_pass()

func _on_restart(_kind: int, _team: String, _spot: Vector2) -> void:
	_clear_pass()

func _clear_pass() -> void:
	last_pass = {}

## Called once per team-brain tick (ActorsContainer) so both teams' brains
## share one ball prediction instead of each recomputing it.
func refresh_tactical() -> void:
	ball_path = BallPredictor.for_ball(ball, 3.0)
	if ball.carrier == null:
		first_left = BallPredictor.first_to_ball(ball_path, active(actors.left_team))
		first_right = BallPredictor.first_to_ball(ball_path, active(actors.right_team))
	else:
		first_left = {"player": null, "time": INF}
		first_right = {"player": null, "time": INF}

## Players currently able to act (not frozen for a restart).
static func active(team: Array) -> Array:
	return team.filter(func(p): return p.process_mode != Node.PROCESS_MODE_DISABLED)

func first_to_ball(team_left: bool) -> Dictionary:
	return first_left if team_left else first_right

## The offside line faced by the side attacking from [param attack_left], as
## a depth in that side's frame (0 own goal → 1 goal attacked).
func offside_depth(attack_left: bool) -> float:
	var defenders := actors.right_team if attack_left else actors.left_team
	var depths := []
	for d in defenders:
		depths.append(PitchSpace.normalised(d.position, attack_left).x)
	return OffsideJudge.offside_line(depths, PitchSpace.normalised(ball.position, attack_left).x)

## Ball prediction / first-to-ball refresh interval (s).
const TACTICAL_REFRESH_S := 0.1
var _next_tactical := 0.0

func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var rows_per_frame := ceili(float(PitchControlGrid.ROWS) / FRAMES_PER_REFRESH)
	control.update_rows(rows_per_frame, actors.left_team, actors.right_team)
	AIProfile.end("pitch_control", t0)
	if MatchClock.now() >= _next_tactical:
		_next_tactical = MatchClock.now() + TACTICAL_REFRESH_S
		var t1 := AIProfile.begin()
		refresh_tactical()
		AIProfile.end("ball_prediction", t1)
	last_update_usec = Time.get_ticks_usec() - t0
	if DebugDraw.ENABLED:
		_draw_debug()

# ─── Queries ────────────────────────────────────────────────────────────────

## Probability [param team_left]'s side controls world point [param p].
func control_at(p: Vector2, team_left: bool) -> float:
	return control.control_at(p, team_left)

## Expected threat of [param p] for the side attacking from [param team_left].
static func xt_at(p: Vector2, team_left: bool) -> float:
	return XtGrid.at(p, team_left)

## Possession value of standing at [param p] with the ball, for
## [param team_left]: the threat of the spot, weighted by how securely that
## side controls it. The positional currency off-ball positioning trades in.
func value_at(p: Vector2, team_left: bool) -> float:
	return XtGrid.at(p, team_left) * control_at(p, team_left)

# ─── Debug overlays ─────────────────────────────────────────────────────────

func _draw_debug() -> void:
	if DebugDraw.SHOW_PITCH_CONTROL:
		var half := Vector2(
			(PitchSpace.RIGHT_BOTTOM_X - PitchSpace.LEFT_BOTTOM_X) / PitchControlGrid.COLS,
			(PitchSpace.BOTTOM_Y - PitchSpace.TOP_Y) / PitchControlGrid.ROWS) * 0.5
		for i in control.centres.size():
			var v := control.control_left[i] * 2.0 - 1.0
			var col := Color(0.2, 0.4, 1.0, absf(v) * 0.35) if v > 0.0 else Color(1.0, 0.2, 0.2, absf(v) * 0.35)
			DebugDraw.rect_filled(Rect2(control.centres[i] - half, half * 2.0), col)
	if DebugDraw.SHOW_XT:
		for i in control.centres.size():
			var xt := XtGrid.at(control.centres[i], true)
			DebugDraw.cross(control.centres[i], Color(1, 1, 0, clampf(xt * 4.0, 0.05, 1.0)), 4.0)
	if DebugDraw.SHOW_BALL_PREDICTION and ball.carrier == null:
		var path := BallPredictor.for_ball(ball)
		for i in range(1, path.size()):
			DebugDraw.line(path.positions[i - 1], path.positions[i], Color(1, 1, 1, 0.8))
	if DebugDraw.SHOW_PASS_FAN and ball.carrier != null:
		var carrier := ball.carrier
		for tm in carrier.get_teammates():
			if tm == carrier:
				continue
			var e := PassModel.evaluate(carrier.position, tm.position, carrier, tm, carrier.get_teammates(), carrier.get_opponents())
			DebugDraw.line(carrier.position, tm.position, Color(1.0 - e.p_success, e.p_success, 0.2, 0.9))
