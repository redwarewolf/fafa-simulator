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

func setup(p_actors: ActorsContainer) -> void:
	actors = p_actors
	ball = p_actors.ball

func _ready() -> void:
	control.update_all(actors.left_team, actors.right_team)

func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var rows_per_frame := ceili(float(PitchControlGrid.ROWS) / FRAMES_PER_REFRESH)
	control.update_rows(rows_per_frame, actors.left_team, actors.right_team)
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
