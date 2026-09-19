class_name TeamTacticalState
extends RefCounted

## Computes, once per team per tick, the two pieces of tactical state every
## player on the team needs but that used to be either recomputed
## independently by each player with no shared memory (pressing rank — see
## the old AIBehavior._compute_pressing_rank, which could flip every 200ms
## tick as relative distances changed by a few px) or didn't exist at all
## (marking — off-ball positioning used to never look at opponent positions,
## so nobody tracked a specific opponent and nobody tried to lose one).
##
## Written directly onto Player fields (pressing_rank, mark_target,
## mark_tightness, marked_by) — same convention ActorsContainer already used
## for weight_on_duty_steering before this replaced it.

## How long the current presser keeps the job before a closer teammate can
## take over — stops the assignment thrashing on marginal distance noise.
const MIN_PRESS_COMMITMENT_MS := 900
## A challenger must be this much closer than the current presser to take over.
const PRESS_TAKEOVER_MARGIN := 60.0

## Bonus (same units as -distance) applied to a defender's score against the
## opponent they marked last tick, so marks don't flip between two similarly
## distant opponents every recompute.
const MARK_STICKY_BONUS := 40.0
## A defender won't be pulled further than this from their own position to
## take on a mark — beyond it the opponent is left to zonal coverage instead.
const MAX_MARK_RANGE := 500.0

## Marking distance (goal-side of the marked player) at max danger (ball on
## top of our own goal) vs. minimum danger (ball deep in the opponent half).
## LOOSE used to be 90 — comfortably outside RoleAI.TACKLE_DISTANCE at every
## danger level except deep in our own box, so a marker chasing a counter-
## attack in open midfield would shadow goal-side forever without ever being
## close enough to actually challenge for the ball, no matter how long the
## run went on.
const TIGHT_MARK_DISTANCE := 25.0
const LOOSE_MARK_DISTANCE := 45.0
## Ball depth band (FieldZones depth 0-7, own goal to opponent goal) between
## which marking tightness scales — nearer than this is fully tight, farther
## than this is fully loose.
const DANGER_NEAR_DEPTH := 1.0
const DANGER_FAR_DEPTH := 5.0

var current_presser: Player = null
var _presser_committed_since_ms := 0
var _prev_marks: Dictionary = {}  # Player (defender) -> Player (marked opponent)
## Cached on first recompute() — a roster's role composition doesn't change
## mid-match, so there's no reason to recompute this every tick. See
## TacticPreset and docs/ai-overhaul.md Phase 2.
var preset: TacticPreset = null

## own_team is defending (marks/presses opposing_team); is_left_team is
## own_team's side, used for ball-depth-based mark tightness.
## [param manual_mentality_mode]/[param score_diff]/[param
## time_fraction_remaining] feed TacticPreset.update() — see
## docs/ai-overhaul.md Phase 8. manual_mentality_mode is AUTO for every
## team except the human player's, which MatchHUD's mentality button can
## pin to a fixed mode live.
func recompute(own_team: Array[Player], opposing_team: Array[Player], ball: Ball, field_zones: FieldZones, is_left_team: bool,
		manual_mentality_mode: int = TacticPreset.ManualMode.AUTO, score_diff: int = 0, time_fraction_remaining: float = 1.0) -> void:
	if preset == null:
		preset = TacticPreset.from_roster(own_team)
	preset.update(manual_mentality_mode, score_diff, time_fraction_remaining)
	_recompute_pressing(own_team, ball)
	_recompute_marking(own_team, opposing_team, ball, field_zones, is_left_team)
	_recompute_cover_presser(own_team, opposing_team, ball)
	_recompute_line_bias(own_team, ball, field_zones, is_left_team)

# ─── Pressing ───────────────────────────────────────────────────────────────

func _recompute_pressing(team: Array[Player], ball: Ball) -> void:
	var team_key := _team_key(team)
	var teammate_has_ball := ball.carrier != null and ball.carrier.team == team_key
	var opponent_keeper_holding := ball.carrier != null and ball.carrier.role == Positions.Role.GK \
		and ball.carrier.team != team_key and ball.carrier.current_state != null \
		and ball.carrier.current_state.is_holding_ball()

	if teammate_has_ball or opponent_keeper_holding:
		for p in team:
			p.pressing_rank = -1
		current_presser = null
		return

	var reference := ball.carrier.position if ball.carrier != null else ball.position
	# Frozen players (FOUL/KICKOFF restarts — see MatchWorld) can't act on
	# pressing duty even if geometrically closest, since their process_mode
	# is disabled and AIBehavior never ticks for them — excluding them here
	# stops the job going to someone who is physically unable to do it.
	var candidates : Array[Player] = team.filter(func(p): return p.role != Positions.Role.GK \
		and p.process_mode != Node.PROCESS_MODE_DISABLED)
	for p in team:
		p.pressing_rank = -1
	if candidates.is_empty():
		current_presser = null
		return

	candidates.sort_custom(func(a, b): return a.position.distance_squared_to(reference) < b.position.distance_squared_to(reference))
	var closest: Player = candidates[0]
	var now := Time.get_ticks_msec()

	if current_presser == null or not (current_presser in candidates):
		current_presser = closest
		_presser_committed_since_ms = now
	elif now - _presser_committed_since_ms > MIN_PRESS_COMMITMENT_MS and closest != current_presser:
		var closest_dist := closest.position.distance_to(reference)
		var current_dist := current_presser.position.distance_to(reference)
		# A higher-press_intensity side takes over sooner (smaller margin to
		# beat) — a more attacking-shaped team contests the ball more eagerly.
		var margin := PRESS_TAKEOVER_MARGIN * lerpf(1.4, 0.6, preset.press_intensity)
		if closest_dist + margin < current_dist:
			current_presser = closest
			_presser_committed_since_ms = now

	for i in candidates.size():
		candidates[i].pressing_rank = 0 if candidates[i] == current_presser else i

func _team_key(team: Array[Player]) -> String:
	return team[0].team if not team.is_empty() else ""

# ─── Marking ────────────────────────────────────────────────────────────────

func _recompute_marking(own_team: Array[Player], opposing_team: Array[Player], ball: Ball, field_zones: FieldZones, is_left_team: bool) -> void:
	for p in opposing_team:
		p.marked_by = null

	var team_key := _team_key(own_team)
	var own_team_has_ball := ball.carrier != null and ball.carrier.team == team_key
	var carrier := ball.carrier

	# Forwards are excluded from marking duty: without this, the nearest-distance
	# assignment below happily hands a striker the mark on whichever opponent is
	# closest to them, which drags them all the way back to shadow that player
	# instead of holding an advanced position as a counter-attack outlet. Only
	# defenders/midfielders track back.
	var defenders : Array[Player] = own_team.filter(func(p): return p.role != Positions.Role.GK \
		and p.pressing_rank != 0 and Positions.group(p.role) != Positions.Group.OFFENSE)
	var targets : Array[Player] = []
	# The carrier is deliberately included here, not left to the presser alone:
	# the presser closes down the ball itself, but with the carrier scoring as
	# the single most dangerous target (highest ball_prox), the nearest free
	# defender now shadows them goal-side too — a covering second defender
	# between the carrier and the goal, instead of nobody but the trailing
	# presser standing between a broken-through run and the net.
	if not own_team_has_ball:
		targets = opposing_team.filter(func(p): return p.role != Positions.Role.GK)

	if defenders.is_empty() or targets.is_empty():
		for d in own_team:
			d.mark_target = null
			d.mark_tightness = 0.0
		return

	var own_goal_center := _own_goal_center(own_team)
	var danger := {}
	for o in targets:
		var goal_prox := 1.0 - clampf(o.position.distance_to(own_goal_center) / 1500.0, 0.0, 1.0)
		var ball_prox := 1.0 - clampf(o.position.distance_to(ball.position) / 650.0, 0.0, 1.0)
		danger[o] = goal_prox * 0.6 + ball_prox * 0.4
	targets.sort_custom(func(a, b): return danger[a] > danger[b])

	var new_marks: Dictionary = {}
	var used: Dictionary = {}
	for o in targets:
		var best: Player = null
		var best_score := -INF
		for d in defenders:
			if used.has(d):
				continue
			var score := -d.position.distance_to(o.position)
			if _prev_marks.get(d) == o:
				score += MARK_STICKY_BONUS
			if score > best_score:
				best_score = score
				best = d
		if best != null and best.position.distance_to(o.position) < MAX_MARK_RANGE:
			new_marks[best] = o
			used[best] = true

	var ball_depth := 3.5
	if field_zones != null:
		ball_depth = float(field_zones.get_zone_depth(field_zones.get_zone(ball.position), is_left_team))
	var danger_falloff := clampf((ball_depth - DANGER_NEAR_DEPTH) / (DANGER_FAR_DEPTH - DANGER_NEAR_DEPTH), 0.0, 1.0)
	var tightness := 1.0 - danger_falloff

	for d in own_team:
		if new_marks.has(d):
			var marked: Player = new_marks[d]
			d.mark_target = marked
			marked.marked_by = d
			d.mark_tightness = tightness
		else:
			d.mark_target = null
			d.mark_tightness = 0.0

	_prev_marks = new_marks

func _own_goal_center(team: Array[Player]) -> Vector2:
	for p in team:
		if p.own_goal != null:
			return p.own_goal.get_center_target_position()
	return Vector2.ZERO

# ─── Cover presser ──────────────────────────────────────────────────────────

## The next-closest teammate to a pressed opponent carrier (after
## current_presser) interposes — Craig Reynolds' term for standing between
## two moving entities — between the carrier and the opponent team's most
## dangerous OTHER option, cutting that passing lane instead of also
## converging on the ball the primary presser is already closing down. See
## docs/ai-overhaul.md Phase 2.
func _recompute_cover_presser(own_team: Array[Player], opposing_team: Array[Player], ball: Ball) -> void:
	for p in own_team:
		p.is_cover_presser = false
	var carrier := ball.carrier
	if carrier == null or carrier.team == _team_key(own_team):
		return  # Only relevant while we're pressing an opponent carrier.

	var candidates : Array[Player] = own_team.filter(func(p): return p.role != Positions.Role.GK \
		and p.pressing_rank > 0 and p.process_mode != Node.PROCESS_MODE_DISABLED)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a.pressing_rank < b.pressing_rank)
	var cover: Player = candidates[0]

	var own_goal_center := _own_goal_center(own_team)
	var danger_target: Player = null
	var best_danger := -INF
	for o in opposing_team:
		if o == carrier or o.role == Positions.Role.GK:
			continue
		var goal_prox := 1.0 - clampf(o.position.distance_to(own_goal_center) / 1500.0, 0.0, 1.0)
		if goal_prox > best_danger:
			best_danger = goal_prox
			danger_target = o
	if danger_target == null:
		return  # e.g. a lone-attacker breakaway with no supporting option to shadow.

	cover.is_cover_presser = true
	# Roughly midway between carrier and the receiver they'd most dangerously
	# pass to — a first approximation of a cover shadow, not a full predicted-
	# interception-point model; see this file's Phase 2 entry in
	# docs/ai-overhaul.md for why that's deferred to tuning.
	cover.cover_shadow_point = carrier.position.lerp(danger_target.position, 0.5)

# ─── Shared line bias ───────────────────────────────────────────────────────

## Every player's ball-depth positioning (RoleAI._ball_depth_base_position)
## gets nudged by this, on top of their own depth_offset() — same-role
## players already land on the same band from that formula alone (it's a
## deterministic function of the same ball depth), so this is specifically
## the team-wide shape shift that formula can't express: holding a higher
## line when there's no immediate threat, or dropping deeper under sustained
## pressure near our own goal. A coarse, reactive stand-in for a real
## mentality/line-height tactic slider — see docs/ai-overhaul.md Phase 2.
func _recompute_line_bias(own_team: Array[Player], ball: Ball, field_zones: FieldZones, is_left_team: bool) -> void:
	var bias := preset.mentality
	if field_zones != null:
		var ball_depth := field_zones.get_zone_depth(field_zones.get_zone(ball.position), is_left_team)
		if ball_depth >= 5:
			bias += 1.0
		elif ball_depth <= 2:
			bias -= 1.0
	bias = clampf(bias, -1.5, 1.5)
	for p in own_team:
		p.team_line_bias = bias
