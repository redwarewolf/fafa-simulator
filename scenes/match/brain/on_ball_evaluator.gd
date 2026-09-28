class_name OnBallEvaluator
extends RefCounted

## On-ball decisions as expected possession value (Phase 6) — the EPV idea of
## Fernández, Bornn & Cervone: every option is worth
##
##     P(success) · V(what we get)  −  P(failure) · risk · V_opp(what they get)
##
## with V = expected threat (XtGrid) of the resulting ball position (weighted
## by how securely we'd control it there), V_opp the threat the OPPONENT would
## have from where they'd win it, and P from the physical models: PassModel's
## interception/reception race for passes (to feet AND into space), a
## time-to-reach race for carries, ShotModel.xg for shots. One scale for
## every action — no per-action hand-tuned pixel sums (v1's OnBallUtility).
##
## The choice is a softmax over the values with a temperature from the
## player's `decisions` attribute (MentalAttributes) and MatchRng, so good
## decision-makers nearly always take the best option and poor ones make
## realistic near-miss choices — deterministically for a given seed.

enum Kind { SHOOT, PASS, CARRY, HOLD }

class Option:
	var kind : int = Kind.HOLD
	var value := 0.0
	var receiver : Player = null
	var destination := Vector2.ZERO
	var to_feet := true
	var p_success := 1.0

const PASS_MIN_PX := 45.0
const PASS_MAX_PX := 1100.0
## Carry probe: how far ahead a carry option looks (seconds of dribbling).
const CARRY_HORIZON_S := 0.9
const CARRY_ANGLES := [0, 35, -35, 70, -70, 110, -110]
## Seconds a carrier needs to shield / turn when holding.
const HOLD_EXPOSURE_S := 0.45
## Where along a failed pass the opponent is assumed to win it.
const LOSS_POINT := 0.55
## How much a receiver's control of the landing spot scales the pass value.
const RECEIVE_SECURITY := 0.4
## Shot appetite by formation group, and max shooting range (px).
const SHOT_BIAS := {Positions.Group.OFFENSE: 1.35, Positions.Group.MIDFIELD: 1.15, Positions.Group.DEFENSE: 0.9}
const SHOT_RANGE_PX := 520.0
## Through balls: how far ahead of a runner the ball is played into space.
const THROUGH_LEADS := [140.0, 230.0]

static func decide(player: Player, ctx: MatchContext, team: TeamBrain, mental: MentalAttributes, restart: bool) -> Option:
	var options := enumerate(player, ctx, team, restart)
	if options.is_empty():
		var hold := Option.new()
		hold.destination = player.position
		return hold
	return _softmax_pick(options, mental.decision_temperature())

static func enumerate(player: Player, ctx: MatchContext, team: TeamBrain, restart: bool) -> Array:
	var left := player.is_left_team
	var from := player.position
	var teammates := player.get_teammates()
	var opponents := MatchContext.active(player.get_opponents())
	var risk := _risk(team)
	var out := []

	# ── Passes to feet ──
	for tm: Player in teammates:
		if tm == player or tm.process_mode == Node.PROCESS_MODE_DISABLED \
				or not SpecialPlayerTypes.can_receive_pass(tm.special_type):
			continue
		var dest := ctx.ball.estimate_pass_lead_destination(from, tm.position, tm.velocity)
		var d := from.distance_to(dest)
		if d < PASS_MIN_PX or d > PASS_MAX_PX or not _on_pitch(dest, left):
			continue
		out.append(_pass_option(player, tm, dest, true, teammates, opponents, ctx, risk))

	# ── Passes into space: ahead of runners ──
	var attack_dir := (PitchSpace.from_normalised(Vector2(1, 0.5), left) - PitchSpace.from_normalised(Vector2(0, 0.5), left)).normalized()
	for tm: Player in teammates:
		if tm == player or tm.brain == null or tm.brain.job == null:
			continue
		if tm.brain.job.kind != Job.Kind.RUN and tm.velocity.dot(attack_dir) < 50.0:
			continue
		for lead in THROUGH_LEADS:
			var dest : Vector2 = tm.position + (attack_dir * 0.75 + tm.velocity.normalized() * 0.25).normalized() * lead
			var d := from.distance_to(dest)
			if d < PASS_MIN_PX or d > PASS_MAX_PX or not _on_pitch(dest, left):
				continue
			out.append(_pass_option(player, tm, dest, false, teammates, opponents, ctx, risk))

	# ── Shot ──
	var goal := player.target_goal
	if from.distance_to(goal.get_center_target_position()) < SHOT_RANGE_PX:
		var shot := Option.new()
		shot.kind = Kind.SHOOT
		var xg := ShotModel.xg(from, goal, opponents)
		shot.p_success = xg
		shot.value = xg * float(SHOT_BIAS.get(Positions.group(player.role), 1.0))
		out.append(shot)

	if restart and _has_kind(out, Kind.PASS):
		return out.filter(func(o): return o.kind != Kind.CARRY and o.kind != Kind.HOLD)

	# ── Carries ──
	var speed := player.get_dribble_speed() * player.get_stamina_factor()
	var reach := speed * CARRY_HORIZON_S
	for deg in CARRY_ANGLES:
		var q : Vector2 = from + attack_dir.rotated(deg_to_rad(deg)) * reach
		if not _on_pitch(q, left):
			continue
		var carry := Option.new()
		carry.kind = Kind.CARRY
		carry.destination = q
		var t_opp := _best_time(q, opponents) + _skill_edge(player, q, opponents)
		carry.p_success = PassModel.p_first(CARRY_HORIZON_S, t_opp)
		carry.value = carry.p_success * XtGrid.at(q, left) \
			- (1.0 - carry.p_success) * risk * XtGrid.at(from.lerp(q, 0.5), not left)
		out.append(carry)

	# ── Hold / shield ──
	var hold := Option.new()
	hold.kind = Kind.HOLD
	hold.destination = from
	hold.p_success = PassModel.p_first(HOLD_EXPOSURE_S, _best_time(from, opponents) + _skill_edge(player, from, opponents))
	hold.value = hold.p_success * XtGrid.at(from, left) - (1.0 - hold.p_success) * risk * XtGrid.at(from, not left)
	out.append(hold)
	return out

static func _pass_option(player: Player, receiver: Player, dest: Vector2, to_feet: bool,
		teammates: Array, opponents: Array, ctx: MatchContext, risk: float) -> Option:
	var left := player.is_left_team
	var e := PassModel.evaluate(player.position, dest, player, receiver, teammates, opponents)
	var o := Option.new()
	o.kind = Kind.PASS
	o.receiver = receiver
	o.destination = dest
	o.to_feet = to_feet
	o.p_success = e.p_success
	var security := 1.0 - RECEIVE_SECURITY + RECEIVE_SECURITY * ctx.control_at(dest, left)
	var loss := player.position.lerp(dest, LOSS_POINT)
	o.value = e.p_success * XtGrid.at(dest, left) * security \
		- (1.0 - e.p_success) * risk * XtGrid.at(loss, not left)
	return o

## How much losing the ball hurts relative to gaining threat: protecting a
## lead late (low mentality) is more cautious, chasing a game more reckless.
static func _risk(team: TeamBrain) -> float:
	var r := lerpf(1.4, 0.7, (team.preset.mentality + 1.0) * 0.5)
	if team.tactical.phase == TacticalBrain.Phase.TRANSITION_ATTACK:
		r *= 0.85
	return r

## Dribbling vs. the nearest defender's defending, as a head start in seconds.
static func _skill_edge(player: Player, at: Vector2, opponents: Array) -> float:
	var nearest : Player = null
	var nd := INF
	for o: Player in opponents:
		var d := o.position.distance_squared_to(at)
		if d < nd:
			nd = d
			nearest = o
	if nearest == null:
		return 0.0
	return (player.dribbling - nearest.defense) / 100.0 * 0.25

static func _best_time(p: Vector2, team: Array) -> float:
	var best := 99.0
	for o: Player in team:
		best = minf(best, PitchControl.time_to_reach(p, o))
	return best

static func _on_pitch(p: Vector2, left: bool) -> bool:
	var n := PitchSpace.normalised(p, left)
	return n.x > 0.02 and n.x < 0.98 and n.y > 0.04 and n.y < 0.96

static func _has_kind(options: Array, kind: int) -> bool:
	for o in options:
		if o.kind == kind:
			return true
	return false

static func _softmax_pick(options: Array, temperature: float) -> Option:
	var best := -INF
	for o in options:
		best = maxf(best, o.value)
	var weights := []
	var total := 0.0
	for o in options:
		var w := exp((o.value - best) / maxf(temperature, 0.0001))
		weights.append(w)
		total += w
	var r := MatchRng.randf() * total
	for i in options.size():
		r -= weights[i]
		if r <= 0.0:
			return options[i]
	return options[options.size() - 1]
