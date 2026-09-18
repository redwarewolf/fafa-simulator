class_name OnBallUtility
extends RefCounted

## Unified on-ball decision scoring — replaces the three per-role if/else
## cascades that used to live in DefenderBehavior/MidfielderBehavior/
## ForwardBehavior, which disagreed with each other for no documented reason
## (e.g. only the midfielder required no-opponents-nearby to shoot). Every
## role now scores the same four actions on one comparable scale and picks
## the highest; roles differ only by the weight multipliers RoleAI.role_weights()
## supplies, not by separate decision code.

enum ActionKind { SHOOT, PASS, DRIBBLE, HOLD }

class Action:
	var kind: int
	var pass_target: Player
	func _init(p_kind: int, p_pass_target: Player = null) -> void:
		kind = p_kind
		pass_target = p_pass_target

# ─── Passing — kept from the old RoleBehavior._pass_score/_pass_lane_penalty,
# extended with receiver openness and the passer's `pas` stat, which was
# previously dead (copied nowhere, read nowhere). ─────────────────────────

const PASS_LANE_CLEAR_RADIUS := 45.0
const PASS_LANE_PENALTY := 250.0
const PASS_MIN_DISTANCE := 20.0
## Field is ~2200px end to end (see ActorsContainer.FIELD_LEFT/RIGHT); 650
## only reaches about a third of it, so an attacker who has actually made a
## forward run — the exact player a progressive pass should target — was
## routinely just out of range and silently dropped from consideration,
## leaving dribble/hold as the only options the carrier ever saw.
const PASS_MAX_DISTANCE := 1100.0
const PROGRESSIVE_PASS_MIN_ADVANCEMENT := 150.0
## An opponent standing this close to the receiver costs as much score as
## PASS_LANE_PENALTY does at zero distance on the lane itself.
const RECEIVER_OPENNESS_RADIUS := 80.0
const RECEIVER_OPENNESS_PENALTY := 200.0

# ─── Charge — a pass beyond a player's power-gated natural range is still
# allowed, but costs a wind-up: PlayerStatePassing holds them in prep_kick for
# charge_ms_for_pass() before releasing. Mirrors effective_shot_range()'s
# power gating below, just for passing instead of shooting. ─────────────────

## Weakest passer (power=0) still reaches this fraction of PASS_MAX_DISTANCE
## with no charge — mirrors MIN_SHOT_RANGE_FACTOR below.
const PASS_MIN_RANGE_FACTOR := 0.5
## ms of charge per full extra multiple of the passer's own natural range
## needed to reach the target — e.g. a 0-power passer reaching all the way to
## PASS_MAX_DISTANCE needs a 2x multiplier (1/PASS_MIN_RANGE_FACTOR), i.e. one
## full extra multiple, i.e. one CHARGE_MS_PER_EXTRA_RANGE of charge.
const CHARGE_MS_PER_EXTRA_RANGE := 1600.0

## How far this player can pass with no charge at all. Same shape as
## effective_shot_range() — full power reaches PASS_MAX_DISTANCE for free,
## same as today; weaker power now needs to charge to get there.
static func effective_pass_range(player: Player) -> float:
	return PASS_MAX_DISTANCE * lerpf(PASS_MIN_RANGE_FACTOR, 1.0, player.power / 100.0)

## 0 within the player's natural range. Beyond it, scales with how many
## multiples of that natural range the target distance needs — capped
## implicitly at PASS_MAX_DISTANCE since callers never pass a longer distance
## (see find_best_pass_target's distance bound, unchanged).
static func charge_ms_for_pass(player: Player, distance: float) -> float:
	var natural_range := effective_pass_range(player)
	if distance <= natural_range:
		return 0.0
	var extra_multiplier := distance / natural_range - 1.0
	return extra_multiplier * CHARGE_MS_PER_EXTRA_RANGE

static func find_best_pass_target(player: Player, teammates: Array[Player], opponents: Array[Player], target_goal: Goal) -> Player:
	var best: Player = null
	var best_score := -INF
	for teammate in teammates:
		if teammate == player or not SpecialPlayerTypes.can_receive_pass(teammate.special_type):
			continue
		var distance := player.position.distance_to(teammate.position)
		if distance < PASS_MIN_DISTANCE or distance > PASS_MAX_DISTANCE:
			continue
		var score := pass_score(player, teammate, opponents, target_goal)
		if score > best_score:
			best_score = score
			best = teammate
	return best

## How much weight a passer puts on a teammate's shot quality being clearly
## better than their own, before the personality (teamplay) scaling below.
const W_SHOT_QUALITY_GAP := 0.5

## Opponent within this range of the passer while they charge is close enough
## to realistically close down and dispossess them before release.
const CHARGE_RISK_PRESSURE_RADIUS := 150.0
## Cost per full second of charge, at maximum pressure (an opponent right on
## top of the passer). Scaled down to 0 as the nearest opponent leaves
## CHARGE_RISK_PRESSURE_RADIUS, so charging in space is free.
const CHARGE_RISK_PENALTY_PER_SEC := 60.0

static func pass_score(player: Player, teammate: Player, opponents: Array[Player], target_goal: Goal) -> float:
	var my_dist_to_goal := player.position.distance_to(target_goal.get_center_target_position())
	var their_dist_to_goal := teammate.position.distance_to(target_goal.get_center_target_position())
	var advancement := my_dist_to_goal - their_dist_to_goal
	# A good passer threads tighter lanes and picks out a marked runner more
	# readily — dial both penalties down as `pas` rises.
	var pass_skill_factor := lerpf(1.3, 0.6, player.passing / 100.0)
	var lane_penalty := _pass_lane_penalty(player.position, teammate.position, opponents) * pass_skill_factor
	var openness_penalty := _receiver_openness_penalty(teammate.position, opponents) * pass_skill_factor

	# advancement alone rewards a pass for pure distance gained, so a square
	# ball to a teammate standing in a wide-open, dead-central sight of goal
	# never outscores a marginal forward pass. Comparing shot quality directly
	# catches that case: a teammate who could clearly finish better than the
	# passer themselves is worth the pass even with little/no advancement.
	# Scaled by `teamplay` — a more team-oriented player weighs an unselfish
	# ball to the better-placed teammate more heavily; a more individualistic
	# one discounts it and leans on their own chance instead.
	var my_shot_quality := _shot_quality_clamped(player.position, effective_shot_range(player, _role_shot_range(player.role)), target_goal, opponents)
	var their_shot_quality := _teammate_shot_quality(teammate, target_goal, opponents)
	var quality_gap := maxf(0.0, their_shot_quality - my_shot_quality)
	var teamplay_factor := lerpf(0.5, 1.5, player.teamplay / 100.0)
	var shot_quality_bonus := quality_gap * W_SHOT_QUALITY_GAP * teamplay_factor

	# A pass beyond the passer's natural range costs charge time — risky if an
	# opponent is close enough to close them down before release.
	var distance := player.position.distance_to(teammate.position)
	var charge_ms := charge_ms_for_pass(player, distance)
	var charge_risk_penalty := 0.0
	if charge_ms > 0.0:
		var nearest_opponent := CandidatePointScorer.nearest_opponent_distance(player.position, opponents)
		var pressure_factor := clampf(1.0 - nearest_opponent / CHARGE_RISK_PRESSURE_RADIUS, 0.0, 1.0)
		charge_risk_penalty = (charge_ms / 1000.0) * CHARGE_RISK_PENALTY_PER_SEC * pressure_factor

	return advancement - lane_penalty - openness_penalty + shot_quality_bonus - charge_risk_penalty

static func is_progressive_pass(player: Player, teammate: Player, opponents: Array[Player], target_goal: Goal) -> bool:
	return pass_score(player, teammate, opponents, target_goal) > PROGRESSIVE_PASS_MIN_ADVANCEMENT

static func _pass_lane_penalty(from_pos: Vector2, target_pos: Vector2, opponents: Array[Player]) -> float:
	var penalty := 0.0
	for opponent in opponents:
		var d := GeometryUtils.distance_point_to_segment(opponent.position, from_pos, target_pos)
		if d < PASS_LANE_CLEAR_RADIUS:
			penalty += PASS_LANE_PENALTY * (1.0 - d / PASS_LANE_CLEAR_RADIUS)
	return penalty

## Direct wiring between the marking system and pass decisions: a receiver
## being closely shadowed scores worse as a pass target than an open one.
## Uses PitchControl's time-to-reach (via opponent_reach_space) rather than
## raw distance, so a defender already closing down the receiver counts as
## tighter marking than their current distance alone would suggest, and one
## drifting away counts as more open — see docs/ai-overhaul.md Phase 1.
static func _receiver_openness_penalty(receiver_pos: Vector2, opponents: Array[Player]) -> float:
	var nearest := CandidatePointScorer.opponent_reach_space(receiver_pos, opponents)
	if nearest >= RECEIVER_OPENNESS_RADIUS:
		return 0.0
	return RECEIVER_OPENNESS_PENALTY * (1.0 - nearest / RECEIVER_OPENNESS_RADIUS)

# ─── Shooting ───────────────────────────────────────────────────────────────

## Weakest shooter (power=0) still gets this fraction of a role's max shot range.
const MIN_SHOT_RANGE_FACTOR := 0.45

static func effective_shot_range(player: Player, max_range: float) -> float:
	var power_factor := lerpf(MIN_SHOT_RANGE_FACTOR, 1.0, player.power / 100.0)
	return max_range * power_factor

## A role's shot range absent a specific RoleAI instance to ask — used to
## estimate a teammate's shot quality from over in pass_score, where only
## RoleAI.role_weights() for the *passer's* role is in scope. Mirrors the
## SHOT_RANGE constants on ForwardAI/MidfielderAI/DefenderAI; approximate is
## fine here since this only ever feeds a pass-vs-shoot comparison, not an
## actual shot.
static func _role_shot_range(role: Positions.Role) -> float:
	match Positions.group(role):
		Positions.Group.OFFENSE:
			return 420.0
		Positions.Group.MIDFIELD:
			return 340.0
		Positions.Group.DEFENSE:
			return 360.0
		_:
			return 300.0

## Distance, shot angle (a tight angle on the byline is a worse shot than the
## same distance dead center — the old system never modeled this), and
## continuous defensive pressure (a discount, not the binary in/out-of-range
## gate every role used to apply identically). Takes a bare position/range so
## it can score a teammate's hypothetical shot from where they're standing,
## not just the actual carrier's.
static func _shot_quality(position: Vector2, range: float, target_goal: Goal, opponents: Array[Player]) -> float:
	var goal_center := target_goal.get_center_target_position()
	var dist := position.distance_to(goal_center)
	if dist > range:
		return -INF
	var distance_score := (1.0 - dist / range) * 60.0

	var top := target_goal.get_top_target_position()
	var bottom := target_goal.get_bottom_target_position()
	var to_top := (top - position).normalized()
	var to_bottom := (bottom - position).normalized()
	var angle := to_top.angle_to(to_bottom)
	var angle_score := (absf(angle) / PI) * 40.0

	var pressure := 0.0
	for o in opponents:
		var d := position.distance_to(o.position)
		if d < 60.0:
			pressure += (60.0 - d)
	var pressure_penalty := pressure * 0.4

	return distance_score + angle_score - pressure_penalty

## _shot_quality returns -INF out of range, which reads fine as "worse than
## anything in range" but poisons a subtraction (INF - INF = NaN) when both
## sides of a comparison can be out of range — pass_score's quality_gap only
## ever wants "no realistic shot from here" to mean neutral, not -infinity.
static func _shot_quality_clamped(position: Vector2, range: float, target_goal: Goal, opponents: Array[Player]) -> float:
	var q := _shot_quality(position, range, target_goal, opponents)
	return q if q != -INF else 0.0

static func _teammate_shot_quality(teammate: Player, target_goal: Goal, opponents: Array[Player]) -> float:
	var range := effective_shot_range(teammate, _role_shot_range(teammate.role))
	return _shot_quality_clamped(teammate.position, range, target_goal, opponents)

static func _shoot_score(player: Player, target_goal: Goal, opponents: Array[Player], max_range: float) -> float:
	return _shot_quality(player.position, effective_shot_range(player, max_range), target_goal, opponents)

# ─── Dribbling — didn't exist as a scored choice before; it was just
# whatever happened when pass/shoot both failed to fire. Also where `phy`
# (previously dead) finally gets used. ──────────────────────────────────────

static func _dribble_score(player: Player, opponents: Array[Player]) -> float:
	var travel_dir := player.heading
	var space := 300.0
	var nearest_defender: Player = null
	for o in opponents:
		var to_opp := o.position - player.position
		var d := to_opp.length()
		if d < 1.0:
			continue
		var ahead := travel_dir.dot(to_opp / d)
		if ahead > 0.3 and d < space:
			space = d
			nearest_defender = o
	var space_score := clampf(space, 0.0, 300.0) / 300.0 * 50.0
	var skill_score := player.dribbling * 0.3
	var resistance := 0.0
	if nearest_defender != null:
		# A physically strong carrier shrugs off nearby pressure more easily.
		var phy_factor := lerpf(1.3, 0.7, player.physicality / 100.0)
		resistance = (nearest_defender.defense * 0.25) * phy_factor
	return space_score + skill_score - resistance

# ─── Decision ───────────────────────────────────────────────────────────────

const MIN_ACT_THRESHOLD := 20.0
const HOLD_BASELINE := 10.0

## Personality spread applied to the raw shoot score: a low-teamplay (more
## individualistic) player takes on chances a more team-oriented player at
## the same skill/position would rather have squared off to someone else —
## see pass_score's shot_quality_bonus for that other half of the trait.
const TEAMPLAY_SHOOT_BIAS_MIN := 0.85  # highly team-oriented (teamplay -> 100)
const TEAMPLAY_SHOOT_BIAS_MAX := 1.2   # highly individualistic (teamplay -> 0)

static func decide(player: Player, ball: Ball, teammates: Array[Player], opponents: Array[Player], target_goal: Goal, weights: Dictionary) -> Action:
	var teamplay_shoot_bias := lerpf(TEAMPLAY_SHOOT_BIAS_MAX, TEAMPLAY_SHOOT_BIAS_MIN, player.teamplay / 100.0)
	var shoot_score := _shoot_score(player, target_goal, opponents, weights.get("shot_range", 360.0)) \
		* float(weights.get("shoot", 1.0)) * teamplay_shoot_bias

	var pass_target := find_best_pass_target(player, teammates, opponents, target_goal)
	var pass_val := -INF
	if pass_target != null:
		pass_val = pass_score(player, pass_target, opponents, target_goal) * float(weights.get("pass", 1.0))

	var dribble_score := _dribble_score(player, opponents) * float(weights.get("dribble", 1.0))
	var hold_score := HOLD_BASELINE

	var best_kind := ActionKind.HOLD
	var best_val := hold_score
	if shoot_score > best_val and shoot_score > MIN_ACT_THRESHOLD:
		best_val = shoot_score
		best_kind = ActionKind.SHOOT
	if pass_val > best_val and pass_val > MIN_ACT_THRESHOLD:
		best_val = pass_val
		best_kind = ActionKind.PASS
	if dribble_score > best_val:
		best_val = dribble_score
		best_kind = ActionKind.DRIBBLE

	return Action.new(best_kind, pass_target if best_kind == ActionKind.PASS else null)
