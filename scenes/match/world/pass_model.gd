class_name PassModel
extends RefCounted

## Pass-success probability from a race along the ball's actual path — the
## physics-based approach of Spearman et al. (2017, "Physics-Based Modeling of
## Pass Probabilities in Soccer"), simplified:
##
##  1. En route: BallPredictor gives the ball's position over time. At each
##     sample, the fastest opponent's time-to-reach that point is compared
##     with when the ball gets there; the chance the ball is cut out is the
##     largest per-sample interception probability (a max, not a product —
##     neighbouring samples are the same defender's same chance, not
##     independent events).
##  2. Arrival: whoever controls the landing point first — the intended
##     receiver (or, for a pass into space, the fastest teammate) vs. the
##     fastest opponent.
##
## Every time comparison goes through the same logistic used for pitch
## control (arrival-time uncertainty σ ≈ 0.45s, Spearman 2018), so a 0.5s head
## start is ~88% and a dead heat 50%. Works equally for a pass to feet and a
## pass into space (a point, not a player), which is what makes through balls
## and switches possible for the v2 AI.

const SIGMA := 0.45
## π/(√3·σ): the logistic's slope for arrival-time differences (seconds).
static var K := PI / (sqrt(3.0) * SIGMA)
## The passer's own body shields the first instant of the pass.
const SKIP_FIRST_S := 0.1
## A pass the receiver can't get to within this long of the ball stopping is
## just a loose ball; beyond it the arrival race decides.
const MAX_FLIGHT_S := 4.0

static func logistic(x: float) -> float:
	return 1.0 / (1.0 + exp(-K * x))

## Probability [param a_time] beats [param b_time] (both seconds).
static func p_first(a_time: float, b_time: float) -> float:
	return logistic(b_time - a_time)

class PassEval:
	var p_success := 0.0
	var p_intercept := 0.0
	var p_reception := 0.0
	var flight_time := 0.0
	var path : BallPredictor.BallPath = null

## Evaluates a kick from [param from] to [param to]. [param receiver] null =
## pass into space (any teammate may collect it). [param passer] is excluded
## from the receiving side.
static func evaluate(from: Vector2, to: Vector2, passer: Player, receiver: Player,
		teammates: Array, opponents: Array) -> PassEval:
	var e := PassEval.new()
	e.path = BallPredictor.for_pass(from, to, MAX_FLIGHT_S)
	var path := e.path
	# When does the ball reach (or stop nearest to) the target?
	var arrive_i := path.size() - 1
	var best_d := INF
	for i in path.size():
		var d := path.positions[i].distance_squared_to(to)
		if d < best_d:
			best_d = d
			arrive_i = i
	e.flight_time = path.times[arrive_i]

	var worst := 0.0
	for i in range(arrive_i + 1):
		var t := path.times[i]
		if t < SKIP_FIRST_S or path.heights[i] > Player.MAX_COLLECT_HEIGHT:
			continue  # too early, or flying over everyone's head
		var pos := path.positions[i]
		var t_def := INF
		for o in opponents:
			t_def = minf(t_def, PitchControl.time_to_reach(pos, o))
		worst = maxf(worst, p_first(t_def, t))
	e.p_intercept = worst

	var t_att := INF
	if receiver != null:
		t_att = PitchControl.time_to_reach(to, receiver)
	else:
		for tm in teammates:
			if tm != passer:
				t_att = minf(t_att, PitchControl.time_to_reach(to, tm))
	var t_opp := INF
	for o in opponents:
		t_opp = minf(t_opp, PitchControl.time_to_reach(to, o))
	# Nobody can collect it before the ball gets there anyway.
	e.p_reception = p_first(maxf(t_att, e.flight_time), maxf(t_opp, e.flight_time))
	e.p_success = (1.0 - e.p_intercept) * e.p_reception
	return e
