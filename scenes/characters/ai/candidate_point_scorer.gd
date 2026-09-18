class_name CandidatePointScorer
extends RefCounted

## Scores discrete off-ball target-position candidates instead of summing
## steering vectors. A vector sum can only produce a blended average of its
## inputs, which can cancel into a directionless (or just mediocre) result —
## it has no way to represent "there's a specific better pocket of space over
## there." Scoring a handful of alternatives independently and picking the
## best one can. See RoleAI._choose_off_ball_target for the candidate
## generation this scores.

const W_SPACE := 0.4
const W_PROGRESSION := 0.5
const W_LOSE_MARK := 0.8
const CROWD_PENALTY_PER_TEAMMATE := 30.0
const CROWD_RADIUS := 50.0
const STICKY_BONUS := 15.0
const STICKY_RADIUS := 20.0
## Distance to the nearest opponent beyond which a candidate is simply "open"
## — extra separation past this stops adding score. Without a cap, raw
## distance is unbounded while progression/lose-mark differences between
## nearby candidates are only tens of units, so space swamps everything else
## and every off-ball player drifts toward whichever pocket is emptiest —
## usually the touchlines/corners, away from the crowded middle where passes
## actually happen — instead of a useful supporting or passing position.
const SPACE_SATURATION_RADIUS := 120.0

## Openness and forward progress alone can park a candidate somewhere with a
## great gap of space but a useless angle on goal — tight to the byline, or
## square behind a defender who's standing right in the shooting/passing
## lane. W_GOAL_ANGLE rewards a wide, central view of the goal mouth (mirrors
## OnBallUtility._shot_quality's angle term); GOAL_LANE_* penalizes a
## candidate whose sightline to goal is blocked, the same way pass lanes are
## penalized for opponents.
const W_GOAL_ANGLE := 0.35
const GOAL_LANE_CLEAR_RADIUS := 45.0
const GOAL_LANE_PENALTY := 60.0

static func nearest_opponent_distance(point: Vector2, opponents: Array[Player]) -> float:
	var best := INF
	for o in opponents:
		var d := point.distance_to(o.position)
		if d < best:
			best = d
	return minf(best if best != INF else 9999.0, SPACE_SATURATION_RADIUS)

static func count_teammates_near(point: Vector2, teammates: Array[Player], radius: float) -> int:
	var count := 0
	for t in teammates:
		if point.distance_to(t.position) < radius:
			count += 1
	return count

## 0..100 — how wide a slice of the goal mouth is visible from [param point],
## regardless of distance. A spot square behind the keeper on the byline can
## be wide open and still be a useless place to receive the ball; this is
## what tells the scorer that isn't a good candidate on its own.
static func _goal_angle_score(point: Vector2, target_goal: Goal) -> float:
	var to_top := (target_goal.get_top_target_position() - point).normalized()
	var to_bottom := (target_goal.get_bottom_target_position() - point).normalized()
	return (absf(to_top.angle_to(to_bottom)) / PI) * 100.0

## Opponents standing between [param point] and the goal cost score the same
## way a defender sitting in a pass lane does — the run isn't useful if
## receiving there still leaves no sight of goal to shoot through.
static func _goal_lane_penalty(point: Vector2, opponents: Array[Player], target_goal: Goal) -> float:
	var goal_pos := target_goal.get_center_target_position()
	var penalty := 0.0
	for o in opponents:
		var d := GeometryUtils.distance_point_to_segment(o.position, point, goal_pos)
		if d < GOAL_LANE_CLEAR_RADIUS:
			penalty += GOAL_LANE_PENALTY * (1.0 - d / GOAL_LANE_CLEAR_RADIUS)
	return penalty

## Reward for a defending candidate that sits close to the nearest opponent
## instead of far from it — see the is_defending branch of
## score_off_ball_candidate.
const W_PRESSURE := 0.4

## Higher is better. [param marker] is the opponent currently assigned to
## shadow [param player] (Player.marked_by), or null if unmarked.
## [param want_to_lose_marker] should only be true when a teammate has (or is
## about to receive) the ball — an off-ball run to shake a marker only makes
## sense as a realistic receiving option, not on every single tick.
## [param is_defending] — true whenever a teammate isn't carrying the ball
## (opponent has it, or it's loose). Every other term here (space, goal
## progression, goal angle/lane) is an attacking heuristic: "open" and
## "advanced" are good things to be when you might receive a pass, but for an
## unmarked defender covering a zone they mean "far from the opponent in my
## area, angled upfield" — i.e. exactly the shape of a defender sidestepping
## a run they could just step into instead of engaging it. Swap the whole
## attacking bundle for a single pressure term (closer to the nearest
## opponent is better) rather than trying to net it out against the rest.
static func score_off_ball_candidate(
		point: Vector2,
		player: Player,
		opponents: Array[Player],
		teammates: Array[Player],
		target_goal: Goal,
		marker: Player,
		want_to_lose_marker: bool,
		last_target: Vector2,
		is_defending: bool = false
) -> float:
	var crowd := count_teammates_near(point, teammates, CROWD_RADIUS) * CROWD_PENALTY_PER_TEAMMATE
	var sticky := STICKY_BONUS if point.distance_to(last_target) < STICKY_RADIUS else 0.0

	if is_defending:
		var pressure := SPACE_SATURATION_RADIUS - nearest_opponent_distance(point, opponents)
		return W_PRESSURE * pressure - crowd + sticky

	var space := nearest_opponent_distance(point, opponents)
	var goal_pos := target_goal.get_center_target_position()
	var progression := player.position.distance_to(goal_pos) - point.distance_to(goal_pos)

	var lose_mark_gain := 0.0
	if want_to_lose_marker and marker != null:
		lose_mark_gain = point.distance_to(marker.position) - player.position.distance_to(marker.position)

	var goal_angle := _goal_angle_score(point, target_goal)
	var goal_lane := _goal_lane_penalty(point, opponents, target_goal)

	return W_SPACE * space + W_PROGRESSION * progression + W_LOSE_MARK * lose_mark_gain \
		+ W_GOAL_ANGLE * goal_angle - goal_lane - crowd + sticky
