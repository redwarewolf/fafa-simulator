class_name OffBallPositioner
extends RefCounted

## Where exactly to stand, for an off-ball player in possession (Phase 6) —
## the "positioning map" layer. The coordinator's job gives an anchor and a
## rigidity; this scores candidate spots around the anchor on the live space
## model and picks the best:
##
##   + value     xT × our pitch control at the spot (a place worth having the ball)
##   + open      control × a clear lane from the ball (I can actually be found there)
##   - leash     distance from the anchor, scaled by rigidity (defenders hold shape,
##               forwards roam — the video's "defenders hold their position")
##   - crowd     teammates already near the spot
##   - offside   anything beyond the offside line (runners excepted)
##   + sticky    near last tick's choice (no dithering)
##
## Search radius comes from the player's vision/off-ball attributes.

const W_VALUE := 12.0
const W_OPEN := 0.8
const W_LEASH := 0.006
const W_CROWD := 0.35
const CROWD_RADIUS := 90.0
const OFFSIDE_PENALTY := 2.0
const STICKY_BONUS := 0.08
const STICKY_RADIUS := 25.0

## Clearness of the straight lane a→b against [param opponents], 0..1: the
## closest opponent to the segment (between its ends) squeezes it, as a
## Gaussian of their perpendicular distance. Cheap stand-in for a full
## PassModel evaluation where many candidates must be scored per tick.
const LANE_SIGMA := 38.0
static func lane_clear(a: Vector2, b: Vector2, opponents: Array) -> float:
	var worst := 0.0
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1.0)
	for o: Player in opponents:
		var t := clampf((o.position - a).dot(ab) / len2, 0.0, 1.0)
		if t <= 0.02 or t >= 0.98:
			continue
		var d := o.position.distance_to(a + ab * t)
		worst = maxf(worst, exp(-(d * d) / (2.0 * LANE_SIGMA * LANE_SIGMA)))
	return 1.0 - worst

static func best_point(player: Player, job: Job, ctx: MatchContext, mental: MentalAttributes, last_target: Vector2) -> Vector2:
	var radius := mental.search_radius() * (1.0 - job.rigidity)
	if radius < 8.0:
		return job.point
	var left := player.is_left_team
	var ball := ctx.ball
	var from := ball.carrier.position if ball.carrier != null else ball.position
	var offside := ctx.offside_depth(left)
	var teammates := player.get_teammates()
	var opponents := player.get_opponents()
	var best := job.point
	var best_s := -INF
	var candidates := [job.point]
	for ring in [0.5, 1.0]:
		for k in 8:
			candidates.append(job.point + Vector2.RIGHT.rotated(k * TAU / 8.0 + ring) * radius * ring)
	for c: Vector2 in candidates:
		var n := PitchSpace.normalised(c, left)
		if n.x < 0.02 or n.x > 0.98 or n.y < 0.04 or n.y > 0.96:
			continue
		var control := ctx.control_at(c, left)
		var s := W_VALUE * XtGrid.at(c, left) * control
		s += W_OPEN * control * lane_clear(from, c, opponents)
		s -= W_LEASH * c.distance_to(job.point) * (0.5 + job.rigidity)
		var crowd := 0
		for t: Player in teammates:
			if t != player and t.position.distance_to(c) < CROWD_RADIUS:
				crowd += 1
		s -= W_CROWD * crowd
		if job.kind != Job.Kind.RUN and n.x > offside:
			s -= OFFSIDE_PENALTY
		if c.distance_to(last_target) < STICKY_RADIUS:
			s += STICKY_BONUS
		if s > best_s:
			best_s = s
			best = c
	return best
