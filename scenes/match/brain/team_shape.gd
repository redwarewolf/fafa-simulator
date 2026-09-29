class_name TeamShape
extends RefCounted

## Formation-as-a-function-of-the-ball (Phase 4) — the Situation Based
## Strategic Positioning idea from RoboCup (Reis & Lau): each player's slot is
## their formation anchor, re-scaled and translated as a BLOCK every tick by
## where the ball is and which phase the team is in. This replaces v1's
## snapping to 18 hand-drawn FieldZones polygons with a continuous shape.
##
## Everything is computed in the team's own normalised frame (x: 0 own goal
## line → 1 goal attacked; PitchSpace.normalised), so the perspective-slanted
## pitch is handled for free and the same numbers work for both sides.
##
## - The block's depth: out of possession, the defensive line holds
##   LINE_GAP behind the ball, clamped between a deep and a high limit set by
##   the press height; in possession, the back line steps up behind the ball.
## - The block's length/width: compact out of possession (~30m long,
##   ~65% of the width), stretched in possession (~45m, full width).
## - Lateral shift: the whole block slides toward the ball's side, much more
##   when defending (to deny the ball side) than when attacking.

## Team shape parameters for one tick (from TeamBrain instructions + phase).
class Params:
	var back_x := 0.2       # depth of the deepest outfield slot
	var length := 0.32      # depth span from deepest to highest slot
	## In possession only: depth of the highest slot, pinned against the
	## opponents' defensive line (so length = front_x - back_x); < 0 = unused.
	var front_x := -1.0
	var width := 0.65       # fraction of the pitch width the anchors span
	var shift_y := 0.35     # how strongly the block slides toward the ball's side

var team_left := true
## Per outfield player: [anchor_x, anchor_y] in the team frame, and the
## normalised rank of anchor_x within the formation (0 deepest, 1 highest).
var _anchor := {}
var _rank := {}

func _init(p_team_left: bool, outfield: Array) -> void:
	team_left = p_team_left
	var min_x := INF
	var max_x := -INF
	for p: Player in outfield:
		var a := PitchSpace.normalised(p.anchor_position, team_left)
		_anchor[p] = a
		min_x = minf(min_x, a.x)
		max_x = maxf(max_x, a.x)
	var span := maxf(max_x - min_x, 0.01)
	for p in outfield:
		_rank[p] = (_anchor[p].x - min_x) / span

## Defensive line limits (team frame) at press_intensity 0 → 1.
## First cut (0.09-0.16 min, 0.28-0.46 max, 0.30-0.20 gap) measured a 20m
## average line height out of possession — a deep low block even for a
## neutral side. Real mid-blocks hold ~30-40m.
const LINE_MIN_LOW := 0.14
const LINE_MIN_HIGH := 0.22
const LINE_MAX_LOW := 0.36
const LINE_MAX_HIGH := 0.52
## Out-of-possession block length multiplier and the counter-press line
## step — Phase 7 re-tune knobs. The block measured ~49m at realistic speed;
## a 3x64-match sweep picked (0.75, +0.1): 46.5m, completion 76%, forward
## 59%, progressive 20-23%, 28/43 metrics in band (vs 24/43).
const DEF_LENGTH_SCALE := 0.75
const COUNTERPRESS_LINE_STEP := 0.1

## How far behind the ball the defensive line sits (fraction of pitch length).
const LINE_GAP_LOW := 0.26
const LINE_GAP_HIGH := 0.17

## Builds this tick's block parameters.
## [param mentality] -1..1, [param press] 0..1 (TacticPreset), [param ball_n]
## the ball in the team frame, [param line_adjust] the ball-pressure step
## (negative = drop, positive = step up), [param phase] TacticalBrain.Phase.
## In possession, the front of the block is pinned just onside of the
## opponents' last line (their offside depth, in our frame), so the team
## stretches the opposition instead of stopping at a ball-relative length —
## the first harness runs showed forwards parked at ~0.52 while a deep block's
## line sat at ~0.85, leaving a 30m hole nobody could pass into.
const ATTACK_FRONT_MARGIN := 0.03
const ATTACK_LENGTH_MIN := 0.38
const ATTACK_LENGTH_MAX := 0.62

static func params_for(phase: int, mentality: float, press: float, ball_n: Vector2, line_adjust: float, offside: float = -1.0) -> Params:
	var p := Params.new()
	var m01 := (mentality + 1.0) * 0.5
	match phase:
		TacticalBrain.Phase.ATTACK, TacticalBrain.Phase.TRANSITION_ATTACK:
			p.back_x = clampf(ball_n.x - lerpf(0.22, 0.15, m01), 0.08, 0.55)
			p.length = lerpf(0.40, 0.52, m01)
			if offside > 0.0:
				p.front_x = clampf(offside - ATTACK_FRONT_MARGIN, p.back_x + ATTACK_LENGTH_MIN, p.back_x + ATTACK_LENGTH_MAX)
				p.length = p.front_x - p.back_x
			p.width = 0.92
			p.shift_y = 0.12
		_:
			p.length = lerpf(0.34, 0.28, press) * Tuning.f("def_length_scale", DEF_LENGTH_SCALE)
			var gap := lerpf(LINE_GAP_LOW, LINE_GAP_HIGH, press)
			var line_max := lerpf(LINE_MAX_LOW, LINE_MAX_HIGH, press)
			# Counter-pressing high up the pitch: the back line steps up behind
			# the pressers instead of leaving a 50m gap.
			if phase == TacticalBrain.Phase.TRANSITION_DEFENCE and ball_n.x > 0.5:
				line_max += Tuning.f("counterpress_line_step", COUNTERPRESS_LINE_STEP)
			p.back_x = clampf(ball_n.x - gap + line_adjust,
				lerpf(LINE_MIN_LOW, LINE_MIN_HIGH, press), line_max)
			p.width = 0.64
			p.shift_y = 0.38
	return p

## World-space slot for [param player] under [param params], ball at
## team-frame [param ball_n]. Out-of-possession slots may not be deeper than
## just in front of our own goal line; in possession, no slot goes past
## [param max_depth] (the opponents' offside line, for non-runners).
func slot(player: Player, params: Params, ball_n: Vector2, max_depth: float = 0.97) -> Vector2:
	if not _anchor.has(player):
		return player.anchor_position
	var a : Vector2 = _anchor[player]
	var x := params.back_x + float(_rank[player]) * params.length
	var y := 0.5 + (a.y - 0.5) * params.width + (ball_n.y - 0.5) * params.shift_y
	# Callers cap depth relative to the ball; near our own goal that cap can
	# fall below the pitch, so never let it pull a slot behind our own line.
	x = clampf(x, 0.04, maxf(max_depth, 0.06))
	y = clampf(y, 0.05, 0.95)
	return PitchSpace.from_normalised(Vector2(x, y), team_left)

func has_player(p: Player) -> bool:
	return _anchor.has(p)

## The formation rank (0 deepest … 1 highest) — used for role affinities.
func rank_of(p: Player) -> float:
	return _rank.get(p, 0.5)
