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
## every action — no per-action hand-tuned pixel sums (the retired v1 AI).
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
	var lofted := false
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
const SHOT_BIAS := {Positions.Group.OFFENSE: 1.4, Positions.Group.MIDFIELD: 1.2, Positions.Group.DEFENSE: 0.95}
const SHOT_RANGE_PX := 600.0
## Goal tuning (user's choice: more goals over strict realism) — shooting a
## bit more readily. With PlayerBrain.SHOT_ERROR_SCALE 0.5 and the keeper's
## SAVE_BIAS -0.1: 1.3 → 1.7 goals per 480s match (64 matches).
const SHOT_BIAS_SCALE := 1.6
## One-step shot lookahead: carrying or passing to a spot is also worth the
## shot that could FOLLOW from it (discounted — it happens later, defenders
## close in), not just the spot's possession value. Without it v2 shot
## first-time on receipt from ~20m (0.6m carried, 0.08 xG/shot) while v1
## drove 12m closer before shooting (0.23 xG/shot) — carrying toward a better
## shot looked worthless to a value function that only knew xT.
## DISABLED by default (0): a 64-match A/B against v1 showed no benefit
## (xG diff -0.125±0.070 with it vs -0.063±0.056 without). Kept behind the
## `shot_followup` Tuning knob for re-testing once movement/dribbling change.
const SHOT_FOLLOWUP := 0.0
## Through balls: how far ahead of a runner the ball is played into space.
const THROUGH_LEADS := [140.0, 230.0]
## Crosses: from beyond this depth and this far off-centre (team frame), to
## teammates inside this area around the box.
const CROSS_MIN_DEPTH := 0.72
const CROSS_MIN_WIDTH := 0.2
const BOX_TARGET_DEPTH := 0.8
const BOX_TARGET_HALF_WIDTH := 0.3
## Verticality — a tactical instruction, value per unit of pitch depth gained
## (normalised; 1.0 = the full 105m), from cautious (mentality -1) to direct
## (+1). xT and the potential grid are nearly flat in a team's own half
## (≈0.004-0.01), so without this the EPV comparison had almost no gradient
## toward progress there and harness runs saw sides dribble around their own
## box. First tried 0.02-0.07: overshot (82% of passes forward, completion
## fell from 81% to 63%). ~0.02 per pitch length at neutral mentality.
const VERTICALITY_CAUTIOUS := 0.008
const VERTICALITY_DIRECT := 0.035

static func decide(player: Player, ctx: MatchContext, team: TeamBrain, mental: MentalAttributes, restart: bool) -> Option:
	var options := enumerate(player, ctx, team, restart)
	if options.is_empty():
		var hold := Option.new()
		hold.destination = player.position
		return hold
	var pick := _softmax_pick(options, mental.decision_temperature())
	_record(player, options, pick)
	return pick

const KIND_NAMES := ["shoot", "pass", "carry", "hold"]

## Decision telemetry by pitch third: what was chosen, and — when a shot was
## available — its value vs. the chosen option's (why aren't we shooting?).
static func _record(player: Player, options: Array, pick: Option) -> void:
	var nx := PitchSpace.normalised(player.position, player.is_left_team).x
	var third := "def" if nx < 1.0 / 3.0 else ("mid" if nx < 2.0 / 3.0 else "att")
	AIProfile.count("choice_%s_%s" % [third, KIND_NAMES[pick.kind]], pick.value)
	_record_pressure(player, options, pick, nx)
	if pick.kind == Kind.SHOOT:
		var best := {Kind.PASS: null, Kind.CARRY: null}
		for o in options:
			if best.has(o.kind) and (best[o.kind] == null or o.value > best[o.kind].value):
				best[o.kind] = o
		AIProfile.count("shot_pick_value", pick.value)
		AIProfile.count("shot_pick_xg", pick.p_success)
		AIProfile.count("shot_pick_dist_m", PitchSpace.distance_m(player.position, player.target_goal.get_center_target_position()))
		if best[Kind.CARRY] != null:
			AIProfile.count("shot_pick_best_carry_value", best[Kind.CARRY].value)
			AIProfile.count("shot_pick_best_carry_p", best[Kind.CARRY].p_success)
		if best[Kind.PASS] != null:
			AIProfile.count("shot_pick_best_pass_value", best[Kind.PASS].value)
			AIProfile.count("shot_pick_best_pass_p", best[Kind.PASS].p_success)
	var best_through : Option = null
	for o in options:
		if o.kind == Kind.SHOOT:
			AIProfile.count("shot_available_%s" % third, o.value)
			AIProfile.count("shot_available_chosen_value_%s" % third, pick.value)
		if o.kind == Kind.PASS and not o.to_feet:
			if best_through == null or o.value > best_through.value:
				best_through = o
	if best_through != null:
		var dn := PitchSpace.normalised(best_through.destination, player.is_left_team)
		AIProfile.count("through_dest_x_%s" % third, dn.x)
		AIProfile.count("through_dest_offcentre_%s" % third, absf(dn.y - 0.5))
		AIProfile.count("through_receiver_is_runner_%s" % third,
			1.0 if best_through.receiver.brain != null and best_through.receiver.brain.job != null \
				and best_through.receiver.brain.job.kind == Job.Kind.RUN else 0.0)
		AIProfile.count("through_available_p_%s" % third, best_through.p_success)
		AIProfile.count("through_available_value_%s" % third, best_through.value)
		AIProfile.count("through_available_vs_chosen_%s" % third, pick.value)
		if pick.kind == Kind.PASS and not pick.to_feet:
			AIProfile.count("through_chosen_%s" % third, pick.p_success)

## Pressure band of [param player]: "p" = an opponent within 3m, "n" = 3-6m,
## "f" = free. Shared by the decision and pass telemetry.
static func pressure_band(player: Player) -> String:
	var near := INF
	for o: Player in player.get_opponents():
		if o.role != Positions.Role.GK:
			near = minf(near, PitchSpace.distance_m(o.position, player.position))
	return "p" if near < 3.0 else ("n" if near < 6.0 else "f")

## Decision telemetry split by pressure (dec_<band>_...): what was chosen and
## its predicted success, pass direction/length, the best pass on offer, and
## how soon the nearest opponent could reach the carrier.
static func _record_pressure(player: Player, options: Array, pick: Option, nx: float) -> void:
	var band := pressure_band(player)
	AIProfile.count("dec_%s_%s" % [band, KIND_NAMES[pick.kind]], pick.p_success)
	AIProfile.count("dec_%s_all" % band, pick.p_success)
	var t_press := INF
	for o: Player in player.get_opponents():
		if o.role != Positions.Role.GK:
			t_press = minf(t_press, PitchControl.time_to_reach(player.position, o))
	AIProfile.count("dec_%s_t_presser" % band, minf(t_press, 5.0))
	var best_p := 0.0
	for o in options:
		if o.kind == Kind.PASS:
			best_p = maxf(best_p, o.p_success)
	AIProfile.count("dec_%s_best_pass_p" % band, best_p)
	if pick.kind == Kind.PASS:
		var dx := (PitchSpace.normalised(pick.destination, player.is_left_team).x - nx) * 105.0
		AIProfile.count("dec_%s_pass_fwd_m" % band, dx)
		AIProfile.count("dec_%s_pass_backward" % band, 1.0 if dx < -2.0 else 0.0)
		AIProfile.count("dec_%s_pass_len_m" % band, PitchSpace.distance_m(player.position, pick.destination))

static func enumerate(player: Player, ctx: MatchContext, team: TeamBrain, restart: bool) -> Array:
	var left := player.is_left_team
	var from := player.position
	var teammates := player.get_teammates()
	var opponents := MatchContext.active(player.get_opponents())
	var risk := _risk(team)
	var vertical := lerpf(VERTICALITY_CAUTIOUS, VERTICALITY_DIRECT, (team.preset.mentality + 1.0) * 0.5)
	var from_depth := PitchSpace.normalised(from, left).x
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

	# ── Crosses: lofted balls to teammates in or around the box — from a
	# corner, or from a wide attacking position in open play. A ground ball
	# from there has to go through the whole defence; a cross goes over it. ──
	var here := PitchSpace.normalised(from, left)
	var corner := restart and ctx.world != null and ctx.world.restart_kind == Restart.Kind.CORNER
	if corner or (here.x > CROSS_MIN_DEPTH and absf(here.y - 0.5) > CROSS_MIN_WIDTH):
		for tm: Player in teammates:
			if tm == player or tm.process_mode == Node.PROCESS_MODE_DISABLED:
				continue
			var tn := PitchSpace.normalised(tm.position, left)
			if tn.x < BOX_TARGET_DEPTH or absf(tn.y - 0.5) > BOX_TARGET_HALF_WIDTH:
				continue
			var dest := ctx.ball.estimate_pass_lead_destination(from, tm.position, tm.velocity, true)
			if from.distance_to(dest) >= PASS_MIN_PX and _on_pitch(dest, left):
				out.append(_pass_option(player, tm, dest, true, teammates, opponents, ctx, risk, true))

	# ── Shot ──
	var goal := player.target_goal
	var direct_ok := not restart or ctx.world == null or Restart.allows_direct_shot(ctx.world.restart_kind)
	if direct_ok and from.distance_to(goal.get_center_target_position()) < SHOT_RANGE_PX:
		var shot := Option.new()
		shot.kind = Kind.SHOOT
		var xg := ShotModel.xg(from, goal, opponents)
		shot.p_success = xg
		shot.value = xg * float(SHOT_BIAS.get(Positions.group(player.role), 1.0)) * Tuning.f("shot_bias_scale", SHOT_BIAS_SCALE)
		out.append(shot)

	if restart and _has_kind(out, Kind.PASS):
		return out.filter(func(o): return o.kind != Kind.CARRY and o.kind != Kind.HOLD)

	# ── Carries ──
	var speed := player.get_dribble_speed() * player.get_stamina_factor()
	var reach := speed * CARRY_HORIZON_S
	for deg in CARRY_ANGLES:
		# reach is a real distance: lay it out in iso space (PitchSpace.ISO_Y).
		var q : Vector2 = from + PitchSpace.from_iso(PitchSpace.iso(attack_dir).normalized().rotated(deg_to_rad(deg)) * reach)
		if not _carry_safe(q):
			continue
		var carry := Option.new()
		carry.kind = Kind.CARRY
		carry.destination = q
		var t_opp := _best_time(q, opponents) + _skill_edge(player, q, opponents)
		carry.p_success = PassModel.p_first(CARRY_HORIZON_S, t_opp)
		carry.value = carry.p_success * _future_value(ctx, q, player, opponents) \
			- (1.0 - carry.p_success) * risk * ctx.possession_value(from.lerp(q, 0.5), not left)
		out.append(carry)

	# ── Hold / shield ──
	var hold := Option.new()
	hold.kind = Kind.HOLD
	hold.destination = from
	hold.p_success = PassModel.p_first(HOLD_EXPOSURE_S, _best_time(from, opponents) + _skill_edge(player, from, opponents))
	hold.value = hold.p_success * ctx.possession_value(from, left) \
		- (1.0 - hold.p_success) * risk * ctx.possession_value(from, not left)
	out.append(hold)

	# Verticality: reward the depth an option gains (only if it succeeds).
	for o in out:
		if o.kind == Kind.PASS or o.kind == Kind.CARRY:
			o.value += o.p_success * vertical * (PitchSpace.normalised(o.destination, left).x - from_depth)
	return out

static func _pass_option(player: Player, receiver: Player, dest: Vector2, to_feet: bool,
		teammates: Array, opponents: Array, ctx: MatchContext, risk: float, lofted: bool = false) -> Option:
	var left := player.is_left_team
	var e := PassModel.evaluate(player.position, dest, player, receiver, teammates, opponents, lofted)
	var o := Option.new()
	o.kind = Kind.PASS
	o.receiver = receiver
	o.destination = dest
	o.to_feet = to_feet
	o.lofted = lofted
	o.p_success = e.p_success
	var loss := player.position.lerp(dest, LOSS_POINT)
	o.value = e.p_success * _future_value(ctx, dest, player, opponents) \
		- (1.0 - e.p_success) * risk * ctx.possession_value(loss, not left)
	return o

## What having the ball at [param p] is worth to [param player]'s side: its
## possession value, or the shot that could follow from there, whichever is
## better (see SHOT_FOLLOWUP).
static func _future_value(ctx: MatchContext, p: Vector2, player: Player, opponents: Array) -> float:
	var v := ctx.possession_value(p, player.is_left_team)
	var goal := player.target_goal
	if p.distance_to(goal.get_center_target_position()) < SHOT_RANGE_PX:
		v = maxf(v, ShotModel.xg(p, goal, opponents) * Tuning.f("shot_followup", SHOT_FOLLOWUP))
	return v

## How much losing the ball hurts relative to gaining threat: protecting a
## lead late (low mentality) is more cautious, chasing a game more reckless.
static func _risk(team: TeamBrain) -> float:
	var r := lerpf(1.4, 0.7, (team.preset.mentality + 1.0) * 0.5)
	if team.tactical.phase == TacticalBrain.Phase.TRANSITION_ATTACK:
		r *= 0.85
	# A turnover costs more than the opponent's static threat at the loss
	# point: at realistic speed they counter into the space our committed
	# players left. Scale tuned in the harness (Phase 7 re-tune).
	return r * Tuning.f("risk_scale", RISK_SCALE)

## Sweep (64 matches each, v2 vs v2, uncalibrated pass model): ×1 → 69%
## completion; ×2 → 71%, 65% forward, 30% progressive; ×3.5 → 72-74%, 61-64%
## forward, 27-28% progressive, 25m average pass.
const RISK_SCALE := 3.5

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

## A carry has to end well inside the lines: at realistic speed a carrier
## can't stop on a dime and the ball runs ahead of his feet, and with the old
## 4% margin 29-35% of all balls out of play were players dribbling it out
## (MatchStats out_share_carry).
const CARRY_MARGIN_X := 0.05
const CARRY_MARGIN_Y := 0.09
## Same for pass destinations near the touchlines (0.04 before): a pass led
## toward the line overruns it. 64-match A/B: throw-ins 2.2 → 1.6 per side.
const PASS_MARGIN_Y := 0.08

static func _carry_safe(p: Vector2) -> bool:
	var n := PitchSpace.absolute_normalised(p)
	var mx := Tuning.f("carry_margin_x", CARRY_MARGIN_X)
	var my := Tuning.f("carry_margin_y", CARRY_MARGIN_Y)
	return n.x > mx and n.x < 1.0 - mx and n.y > my and n.y < 1.0 - my

static func _on_pitch(p: Vector2, left: bool) -> bool:
	var n := PitchSpace.normalised(p, left)
	var my := Tuning.f("pass_margin_y", PASS_MARGIN_Y)
	return n.x > 0.02 and n.x < 0.98 and n.y > my and n.y < 1.0 - my

static func _has_kind(options: Array, kind: int) -> bool:
	for o in options:
		if o.kind == kind:
			return true
	return false

## [param temperature] is RELATIVE (MentalAttributes.decision_temperature):
## it's scaled by the size of the best value on offer, so "a poor decision-
## maker picks a near-miss option" means the same thing in build-up (values
## ≈0.005) as in the box (≈0.2). An absolute temperature was larger than every
## difference between build-up options, making those choices near-random.
const TEMPERATURE_FLOOR := 0.0015

static func _softmax_pick(options: Array, temperature: float) -> Option:
	var best := -INF
	for o in options:
		best = maxf(best, o.value)
	var tau := maxf(temperature * absf(best), TEMPERATURE_FLOOR * temperature)
	var weights := []
	var total := 0.0
	for o in options:
		var w := exp((o.value - best) / maxf(tau, 0.000001))
		weights.append(w)
		total += w
	var r := MatchRng.randf() * total
	for i in options.size():
		r -= weights[i]
		if r <= 0.0:
			return options[i]
	return options[options.size() - 1]
