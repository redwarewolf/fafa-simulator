class_name TeamBrain
extends RefCounted

## One per v2 team — the top two layers of the hierarchy (Phases 4-5):
##
##   TacticalBrain  reads the game state (phase, with hysteresis)
##   TeamShape      turns the formation into this tick's block of slots
##   coordinators   build the special jobs for the phase (press / cover /
##                  mark / lane-cut / chase / intercept, or support / run /
##                  receive / rest-defence) and hand ALL jobs out in one
##                  optimal assignment (Hungarian), so no two players do the
##                  same job and nobody's job is decided by "who's nearest first".
##
## Ticked by ActorsContainer at TICK_S. The resulting Job lands on each
## player's PlayerBrain, which turns it into movement and decisions.

const TICK_S := 0.2

# ─── Assignment costs (seconds of travel-time equivalent) ───────────────────
## Special jobs carry a negative priority far larger than any travel time, so
## they are ALWAYS filled (in priority order if there are more specials than
## players) — the optimisation then only decides WHO takes each one. The first
## cut used -3..-12, comparable to travel times: a RUN point 8s away "cost"
## more than leaving it empty, so no runner was ever assigned and v2 sides
## never got anyone in behind (docs/match-engine-v2.md, tuning round 2).
const PRIORITY := {
	Job.Kind.RECEIVE: -120.0, Job.Kind.CHASE: -100.0, Job.Kind.INTERCEPT: -100.0,
	Job.Kind.PRESS: -90.0, Job.Kind.COVER: -60.0, Job.Kind.MARK: -50.0,
	Job.Kind.SUPPORT: -40.0, Job.Kind.LANE_CUT: -35.0, Job.Kind.RUN: -30.0,
	Job.Kind.SET_PIECE: -45.0,
}
## Keeping the same job as last tick (assignment hysteresis).
const STICKY_BONUS := 0.6
## Taking a teammate's shape slot instead of your own.
const SLOT_SWAP_PENALTY := 1.2
const SLOT_RANK_PENALTY := 3.0
const FORBIDDEN := 1.0e6

# ─── Defensive coordinator constants ────────────────────────────────────────
const COVER_DIST := 95.0
const CONTAIN_DIST := 70.0
const MAX_MARKS := 4
## Opponents less threatening than this (xT at their spot, run-adjusted) are
## left to the zonal shape rather than man-marked.
const MARK_DANGER_MIN := 0.012
const TIGHT_MARK_PX := 22.0
const LOOSE_MARK_PX := 48.0
## Carrier this close to one of ours counts as pressured (ball-pressure rule).
const PRESSURED_PX := 120.0

# ─── Attacking coordinator constants ────────────────────────────────────────
const SUPPORT_RADII := [190.0, 300.0]
const SUPPORT_MIN_SEPARATION := 150.0
## Runners wait "on the shoulder": just onside of the line.
const ONSIDE_MARGIN := 0.012

var team_left := true
var tactical : TacticalBrain = null
var shape : TeamShape = null
var preset : TacticPreset = null
var ctx : MatchContext = null
var players : Array[Player] = []  # outfield players driven by v2
## Last tick's jobs (for stickiness + telemetry).
var jobs := {}  # Player -> Job
var _next_tick := 0.0
## Harness telemetry: how many ticks each job kind was held, summed over players.
var job_ticks := {}

func _init(p_team_left: bool, team: Array[Player], p_ctx: MatchContext) -> void:
	team_left = p_team_left
	ctx = p_ctx
	for p in team:
		if p.role != Positions.Role.GK and SpecialPlayerTypes.movable(p.special_type):
			players.append(p)
	tactical = TacticalBrain.new(team_left)
	shape = TeamShape.new(team_left, players)
	preset = TacticPreset.from_roster(team)

## Called every frame by ActorsContainer; thinks at TICK_S.
func maybe_update(manual_mode: int, score_diff: int, time_fraction_remaining: float) -> void:
	var now := MatchClock.now()
	if now < _next_tick:
		return
	_next_tick = now + TICK_S
	var t0 := AIProfile.begin()
	_update(manual_mode, score_diff, time_fraction_remaining, now)
	AIProfile.end("team_brain", t0)

func _update(manual_mode: int, score_diff: int, time_fraction_remaining: float, now: float) -> void:
	preset.update(manual_mode, score_diff, time_fraction_remaining)
	tactical.update(ctx, now)
	var active : Array = players.filter(func(p): return p.process_mode != Node.PROCESS_MODE_DISABLED)
	if active.is_empty():
		return
	var ball_n := PitchSpace.normalised(ctx.ball.position, team_left)
	var specials : Array = []
	var zone := {}
	if ctx.restart_active():
		# The taker is driven by his own PlayerBrain (waits, then plays it).
		active = active.filter(func(p): return p != ctx.set_piece_taker)
		if active.is_empty():
			return
		_set_piece_jobs(active, specials, zone)
	elif _attacking():
		_attacking_jobs(active, ball_n, specials, zone)
	else:
		_defensive_jobs(active, ball_n, specials, zone)
	_assign(active, specials, zone)

func _attacking() -> bool:
	return tactical.in_possession() or (tactical.phase == TacticalBrain.Phase.LOOSE_BALL and tactical.owner == TacticalBrain.US)

# ═══ Defensive coordinator ══════════════════════════════════════════════════

## [param restart]: organising for an opponents' set piece — no pressing or
## chasing the placed ball (Law: retreat distance), just shape and marks.
func _defensive_jobs(active: Array, ball_n: Vector2, specials: Array, zone: Dictionary, restart: bool = false) -> void:
	var ball := ctx.ball
	var carrier := ball.carrier
	var own_goal := _own_goal_centre(active)
	var opponents := active[0].get_opponents() as Array
	var phase := TacticalBrain.Phase.DEFENCE if restart else tactical.phase
	var params := TeamShape.params_for(phase, preset.mentality, preset.press_intensity, ball_n, 0.0 if restart else _line_adjust(active, ball_n))
	for p in active:
		zone[p] = Job.make(Job.Kind.ZONE, shape.slot(p, params, ball_n), null, lerpf(0.9, 0.6, shape.rank_of(p)))

	var marked := {}
	if carrier != null and carrier.is_left_team != team_left:
		var press := Job.make(Job.Kind.PRESS, carrier.position + carrier.velocity * 0.3, carrier, 1.0)
		press.engage = _should_engage(carrier, ball_n)
		specials.append(press)
		if tactical.phase == TacticalBrain.Phase.TRANSITION_DEFENCE:
			# Counter-press: a second player closes the carrier from another
			# angle during the transition window.
			var press2 := Job.make(Job.Kind.PRESS, carrier.position, carrier, 1.0)
			press2.engage = true
			specials.append(press2)
		specials.append(Job.make(Job.Kind.COVER, carrier.position + carrier.position.direction_to(own_goal) * COVER_DIST, carrier, 1.0))
		marked[carrier] = true
	elif not restart:
		_loose_ball_jobs(specials, false)
		var r := _press_on_pass(specials, own_goal)
		if r != null:
			marked[r] = true

	# Marks: the most dangerous opponents off the ball.
	var threats := []
	for o: Player in opponents:
		if o == carrier or o.role == Positions.Role.GK or o.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var danger := XtGrid.at(o.position, o.is_left_team)
		var to_goal := o.position.direction_to(own_goal)
		danger *= 1.0 + maxf(0.0, o.velocity.dot(to_goal)) / 100.0
		if danger >= Tuning.f("mark_danger_min", MARK_DANGER_MIN):
			threats.append([danger, o])
	threats.sort_custom(func(a, b): return a[0] > b[0])
	var max_danger : float = threats[0][0] if not threats.is_empty() else 1.0
	for i in mini(threats.size(), int(Tuning.f("max_marks", MAX_MARKS))):
		var o : Player = threats[i][1]
		var tight := clampf(threats[i][0] / max_danger, 0.0, 1.0)
		var dist := lerpf(LOOSE_MARK_PX, TIGHT_MARK_PX, tight)
		var lead := o.position + o.velocity * 0.25
		specials.append(Job.make(Job.Kind.MARK, lead + lead.direction_to(own_goal) * dist, o, 1.0))
		marked[o] = true

	# Lane cut: the carrier's most valuable unmarked outlet.
	if carrier != null and carrier.is_left_team != team_left:
		var best : Player = null
		var best_v := -INF
		for o: Player in opponents:
			if marked.has(o) or o.role == Positions.Role.GK:
				continue
			var v := XtGrid.at(o.position, o.is_left_team) * OffBallPositioner.lane_clear(carrier.position, o.position, active)
			if v > best_v:
				best_v = v
				best = o
		if best != null:
			specials.append(Job.make(Job.Kind.LANE_CUT, carrier.position.lerp(best.position, 0.42), best, 1.0))

## Press on the pass: while their pass travels, one of ours runs at where the
## receiver will take it, arriving goal-side, so the receiver is pressured on
## the first touch instead of later. Without it receivers had the nearest
## defender 12m away (8% pressured) though carriers were pressured on release
## about as often as in real football (22%). Returns the receiver, or null.
## Tuning knob `press_on_pass`.
const PRESS_ON_PASS_GOALSIDE_PX := 30.0

func _press_on_pass(specials: Array, own_goal: Vector2) -> Player:
	if not Tuning.b("press_on_pass", false) or ctx.last_pass.is_empty() or ctx.ball_path == null:
		return null
	if ctx.last_pass["left"] == team_left:
		return null
	var r : Player = ctx.last_pass["receiver"]
	if r == null or r.role == Positions.Role.GK or r.process_mode == Node.PROCESS_MODE_DISABLED:
		return null
	# Only when they'll get there first — otherwise it's our interception.
	var t_r := BallPredictor.earliest_intercept(ctx.ball_path, r)
	if t_r == INF or t_r > ctx.first_to_ball(team_left)["time"]:
		return null
	var pt := ctx.ball_path.position_at(t_r)
	var job := Job.make(Job.Kind.PRESS, clamp_to_pitch(pt + pt.direction_to(own_goal) * PRESS_ON_PASS_GOALSIDE_PX), r, 1.0)
	job.engage = _should_engage(r, PitchSpace.normalised(pt, team_left))
	AIProfile.count("press_on_pass", 1.0 if job.engage else 0.0)
	specials.append(job)
	return r

## Ball-pressure rule for the defensive line: drop off when their carrier is
## free and running at us, step up when the ball goes backwards.
func _line_adjust(active: Array, _ball_n: Vector2) -> float:
	var carrier := ctx.ball.carrier
	if carrier == null or carrier.is_left_team == team_left:
		return 0.0
	var nearest := INF
	for p: Player in active:
		nearest = minf(nearest, p.position.distance_to(carrier.position))
	var toward_us := carrier.velocity.dot(PitchSpace.from_normalised(Vector2(0.0, 0.5), team_left) - carrier.position)
	if nearest > PRESSURED_PX and toward_us > 0.0:
		return -0.04
	if toward_us < 0.0 and carrier.velocity.length() > 30.0:
		return 0.03
	return 0.0

## Engage (go and win it) vs contain (shadow goal-side). High-press sides
## engage further up the pitch; everyone engages in their own third, in the
## counter-press window, and on the classic pressing triggers.
const PRESS_TRIGGER_SHIFT := 0.0

func _should_engage(carrier: Player, ball_n: Vector2) -> bool:
	if tactical.phase == TacticalBrain.Phase.TRANSITION_DEFENCE or ball_n.x < 0.35:
		return true
	# press_trigger_shift < 0 = engage only further back (Phase 7 re-tune: at
	# realistic speed the press strangled possessions, PPDA ~3 vs real 8-15).
	var trigger := lerpf(0.5, 1.01, preset.press_intensity) + Tuning.f("press_trigger_shift", PRESS_TRIGGER_SHIFT)
	if ball_n.x <= trigger:
		return true
	# Pressing triggers: carrier running back toward his own goal, or
	# pinned against a touchline.
	var their_goal := PitchSpace.from_normalised(Vector2(1.0, 0.5), team_left)
	if carrier.velocity.dot(their_goal - carrier.position) > 20.0:
		return true
	return absf(ball_n.y - 0.5) > 0.4

# ═══ Loose ball / passes in flight ══════════════════════════════════════════

## One chaser per side: our fastest to the ball (BallPredictor), aiming at
## where they'll meet it. A pass we played in flight gets a RECEIVE for its
## intended receiver instead.
func _loose_ball_jobs(specials: Array, attacking: bool) -> void:
	if ctx.ball.carrier != null or ctx.ball_path == null:
		return
	if attacking and not ctx.last_pass.is_empty() and ctx.last_pass["left"] == team_left:
		var r : Player = ctx.last_pass["receiver"]
		if r != null and r in players and r.process_mode != Node.PROCESS_MODE_DISABLED:
			var t := BallPredictor.earliest_intercept(ctx.ball_path, r)
			var pt := ctx.ball_path.position_at(t) if t != INF else ctx.ball_path.end_position()
			specials.append(Job.make(Job.Kind.RECEIVE, clamp_to_pitch(pt), r, 1.0))
			return
	var first : Dictionary = ctx.first_to_ball(team_left)
	var chaser : Player = first["player"]
	if chaser == null or chaser.role == Positions.Role.GK:
		return
	var kind := Job.Kind.CHASE if ctx.last_pass.is_empty() or ctx.last_pass["left"] == team_left else Job.Kind.INTERCEPT
	specials.append(Job.make(kind, clamp_to_pitch(ctx.ball_path.position_at(first["time"])), null, 1.0))

## Ball-path points can lie outside the lines (a ball heading out of play);
## nobody should be sent off the pitch to meet it.
static func clamp_to_pitch(p: Vector2) -> Vector2:
	var n := PitchSpace.absolute_normalised(p)
	return PitchSpace.from_absolute_normalised(Vector2(clampf(n.x, 0.01, 0.99), clampf(n.y, 0.02, 0.98)))

# ═══ Attacking coordinator ══════════════════════════════════════════════════

## [param restart]: organising around our own set piece — the ball is placed,
## nobody chases it, and the taker (excluded from [param active]) will play it.
func _attacking_jobs(active: Array, ball_n: Vector2, specials: Array, zone: Dictionary, restart: bool = false) -> void:
	var offside := ctx.offside_depth(team_left)
	var phase := TacticalBrain.Phase.ATTACK if restart else tactical.phase
	var params := TeamShape.params_for(phase, preset.mentality, preset.press_intensity, ball_n, 0.0, offside)
	var rest_n := clampi(roundi(3.0 - preset.mentality * 1.5), 2, 4)
	var by_rank := active.duplicate()
	by_rank.sort_custom(func(a, b): return shape.rank_of(a) < shape.rank_of(b))
	var rest := {}
	for i in mini(rest_n, by_rank.size()):
		rest[by_rank[i]] = true
	for p in active:
		if rest.has(p):
			var slot := shape.slot(p, params, ball_n, minf(ball_n.x - 0.12, offside - ONSIDE_MARGIN))
			zone[p] = Job.make(Job.Kind.REST_DEFENCE, slot, null, 0.85)
		else:
			zone[p] = Job.make(Job.Kind.ZONE, shape.slot(p, params, ball_n, offside - ONSIDE_MARGIN), null, lerpf(0.6, 0.25, shape.rank_of(p)))

	var carrier := ctx.ball.carrier
	if not restart:
		_loose_ball_jobs(specials, true)
	var ref : Vector2 = ctx.ball.position
	if carrier != null:
		ref = carrier.position
	elif not specials.is_empty():
		ref = specials[0].point

	# Support: two short passing angles around the (future) carrier.
	for pt in _support_points(ref, active, carrier):
		specials.append(Job.make(Job.Kind.SUPPORT, pt, null, 0.35))

	# Runs: wait on the shoulder of the last defender, in the most promising channel.
	var runs := 1 + (1 if preset.mentality > 0.3 or tactical.phase == TacticalBrain.Phase.TRANSITION_ATTACK else 0)
	var lanes := [0.3, 0.5, 0.7]
	lanes.sort_custom(func(a, b): return _lane_value(a, offside) > _lane_value(b, offside))
	for i in runs:
		var pt := PitchSpace.from_normalised(Vector2(clampf(offside - ONSIDE_MARGIN, 0.3, 0.95), lanes[i]), team_left)
		specials.append(Job.make(Job.Kind.RUN, pt, null, 0.5))

func _lane_value(y: float, offside: float) -> float:
	var behind := PitchSpace.from_normalised(Vector2(minf(offside + 0.08, 0.95), y), team_left)
	return ctx.value_at(behind, team_left)

func _support_points(ref: Vector2, active: Array, carrier: Player) -> Array:
	var attack_dir := PitchSpace.from_normalised(Vector2(1.0, 0.5), team_left) - PitchSpace.from_normalised(Vector2(0.0, 0.5), team_left)
	attack_dir = attack_dir.normalized()
	var scored := []
	for radius in SUPPORT_RADII:
		for deg in [-150, -110, -70, -35, 0, 35, 70, 110, 150]:
			var p : Vector2 = ref + attack_dir.rotated(deg_to_rad(deg)) * radius
			var n := PitchSpace.normalised(p, team_left)
			if n.x < 0.03 or n.x > 0.97 or n.y < 0.05 or n.y > 0.95:
				continue
			var s : float = ctx.control_at(p, team_left) * OffBallPositioner.lane_clear(ref, p, active[0].get_opponents()) \
				* (0.5 + XtGrid.at(p, team_left) * 10.0)
			scored.append([s, p])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var picked := []
	for e in scored:
		var ok := true
		for q in picked:
			if q.distance_to(e[1]) < SUPPORT_MIN_SEPARATION:
				ok = false
				break
		if ok:
			picked.append(e[1])
		if picked.size() == 2:
			break
	return picked

# ═══ Set-piece coordinator ══════════════════════════════════════════════════
# While play is stopped for a set piece (MatchContext.restart_active), both
# sides take up positions during Restart.setup_time before the taker plays it.
# Corners use fixed templates in the team's own frame; free kicks in shooting
# range get a wall; everything else (throw-ins, deep free kicks, offside
# kicks) is ordinary shape + support/marking around the placed ball. All
# points are SET_PIECE jobs, assigned with the rest by the Hungarian solve.

## Attacking corner posts (team frame; y is mirrored to the corner's side,
## `s` = +1 for the bottom corner, -1 for the top).
const CORNER_ATTACK := [
	Vector2(0.955, 0.07),   # near post   (y = 0.5 + s*0.07)
	Vector2(0.955, -0.07),  # far post
	Vector2(0.94, 0.0),     # six-yard box centre
	Vector2(0.895, 0.0),    # penalty spot
	Vector2(0.83, -0.08),   # edge of the box, far side
	Vector2(0.83, 0.08),    # edge of the box, near side
]
## Defending corner posts (defenders' frame, same `s` mirroring).
const CORNER_DEFENCE := [
	Vector2(0.02, 0.065),   # near post
	Vector2(0.05, 0.06),    # zonal, six-yard line
	Vector2(0.05, 0.0),
	Vector2(0.05, -0.06),
	Vector2(0.19, 0.0),     # edge of the box — second balls
	Vector2(0.42, -0.2),    # counter-attack outlet
]
const CORNER_MAX_MARKS := 3
## Free kicks: build a wall when the spot is at least this dangerous (xG).
const WALL_MIN_XG := 0.025
const WALL_BIG_XG := 0.06
const WALL_SPACING := 14.0

func _set_piece_jobs(active: Array, specials: Array, zone: Dictionary) -> void:
	var w := ctx.world
	var spot := w.restart_spot
	var ours := w.restart_team_left == team_left
	var spot_n := PitchSpace.normalised(spot, team_left)
	if ours:
		_attacking_jobs(active, spot_n, specials, zone, true)
	else:
		_defensive_jobs(active, spot_n, specials, zone, true)
	var s := 1.0 if spot_n.y > 0.5 else -1.0
	if w.restart_kind == Restart.Kind.CORNER:
		specials.clear()
		var template : Array = CORNER_ATTACK if ours else CORNER_DEFENCE
		for off: Vector2 in template:
			var n := Vector2(off.x, 0.5 + off.y * s)
			specials.append(Job.make(Job.Kind.SET_PIECE, PitchSpace.from_normalised(n, team_left), null, 1.0))
		if ours:
			# Short option for a quick corner, beside the taker.
			var centre := PitchSpace.from_normalised(Vector2(0.5, 0.5), team_left)
			specials.append(Job.make(Job.Kind.SUPPORT, spot + spot.direction_to(centre) * 150.0, null, 0.6))
		else:
			_mark_box_attackers(active, specials)
	elif w.restart_kind == Restart.Kind.FREE_KICK and not ours:
		_build_wall(active, spot, specials)

## Posts within this distance count as manned — loose enough for teammates'
## separation steering, which keeps players ~45px apart, around posts ~50px
## apart.
const SET_PIECE_READY_PX := 55.0

## Every SET_PIECE post around the penalty areas (box spots, zonal cover) is
## manned. Far posts like the counter-attack outlet, marks and ordinary shape
## jobs don't hold the restart up.
func set_piece_ready() -> bool:
	for p in jobs:
		var j : Job = jobs[p]
		if j.kind != Job.Kind.SET_PIECE:
			continue
		var depth := PitchSpace.normalised(j.point, team_left).x
		if (depth > 0.75 or depth < 0.25) and p.position.distance_to(j.point) > SET_PIECE_READY_PX:
			return false
	return true

## Corner defence: man-mark the most dangerous attackers in our box on top of
## the zonal posts.
func _mark_box_attackers(active: Array, specials: Array) -> void:
	var own_goal := _own_goal_centre(active)
	var in_box := []
	for o: Player in active[0].get_opponents():
		if o == ctx.set_piece_taker or o.role == Positions.Role.GK:
			continue
		var n := PitchSpace.normalised(o.position, team_left)
		if n.x < 0.2 and absf(n.y - 0.5) < 0.32:
			in_box.append([n.x, o])
	in_box.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(in_box.size(), CORNER_MAX_MARKS):
		var o : Player = in_box[i][1]
		specials.append(Job.make(Job.Kind.MARK, o.position + o.position.direction_to(own_goal) * TIGHT_MARK_PX, o, 1.0))

## A wall 9.15m (Restart.retreat_distance) from the ball on the line to the
## goal centre: 3 players for a dangerous spot, 2 for a speculative one.
func _build_wall(active: Array, spot: Vector2, specials: Array) -> void:
	var goal := _own_goal_centre(active)
	var danger := ShotModel.xg_for_goal(spot, active[0].own_goal)
	if danger < WALL_MIN_XG:
		return
	var n := 3 if danger >= WALL_BIG_XG else 2
	var dir := spot.direction_to(goal)
	var centre := spot + dir * (Restart.retreat_distance(Restart.Kind.FREE_KICK) + 2.0)
	var perp := Vector2(-dir.y, dir.x)
	for i in n:
		var off := (i - (n - 1) * 0.5) * WALL_SPACING
		specials.append(Job.make(Job.Kind.SET_PIECE, centre + perp * off, null, 1.0))

# ═══ Assignment ═════════════════════════════════════════════════════════════

func _assign(active: Array, specials: Array, zone: Dictionary) -> void:
	var cols : Array = specials.duplicate()
	var zone_owner := []
	for p in active:
		cols.append(zone[p])
		zone_owner.append(p)
	var n_special := specials.size()
	var cost := []
	for p: Player in active:
		var row := PackedFloat32Array()
		row.resize(cols.size())
		for j in cols.size():
			var job : Job = cols[j]
			var c := PitchControl.time_to_reach(job.point, p)
			if j < n_special:
				c += PRIORITY.get(job.kind, -2.0) + _affinity(p, job)
			else:
				var owner : Player = zone_owner[j - n_special]
				if owner != p:
					c += SLOT_SWAP_PENALTY + absf(shape.rank_of(owner) - shape.rank_of(p)) * SLOT_RANK_PENALTY
			var prev : Job = jobs.get(p)
			if prev != null and prev.same_role_as(job):
				c -= STICKY_BONUS
			row[j] = c
		cost.append(row)
	var assignment := Hungarian.solve(cost)
	var new_jobs := {}
	for i in active.size():
		var p : Player = active[i]
		var job : Job = cols[assignment[i]]
		new_jobs[p] = job
		job_ticks[job.kind] = job_ticks.get(job.kind, 0) + 1
		if p.brain != null:
			p.brain.job = job
	jobs = new_jobs

## Role fit for a special job — keeps centre-backs from pressing high up the
## pitch, forwards from marking in our own box, and runs to the front line.
func _affinity(p: Player, job: Job) -> float:
	var rank := shape.rank_of(p)
	var depth := PitchSpace.normalised(job.point, team_left).x
	match job.kind:
		Job.Kind.RECEIVE:
			return 0.0 if job.subject == p else FORBIDDEN
		Job.Kind.PRESS:
			return 1.5 if rank < 0.3 and depth > 0.55 else 0.0
		Job.Kind.MARK:
			return 2.0 if rank > 0.75 and depth < 0.4 else 0.0
		Job.Kind.RUN:
			return 0.0 if rank > 0.6 else 3.0
		Job.Kind.SUPPORT:
			return 1.5 if rank < 0.2 else 0.0
		Job.Kind.SET_PIECE:
			# Box posts go to the strongest players (aerial duels); a
			# defensive wall or the counter outlet doesn't care.
			return (1.0 - p.physicality / 100.0) * 1.2 if depth > 0.75 or depth < 0.1 else 0.0
	return 0.0

func _own_goal_centre(active: Array) -> Vector2:
	var g : Goal = active[0].own_goal
	return g.get_center_target_position() if g != null else PitchSpace.from_normalised(Vector2(0.0, 0.5), team_left)
