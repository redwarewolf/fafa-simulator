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
const LINE_MIN_LOW := 0.09
const LINE_MIN_HIGH := 0.16
const LINE_MAX_LOW := 0.28
const LINE_MAX_HIGH := 0.46
## How far behind the ball the defensive line sits (fraction of pitch length).
const LINE_GAP_LOW := 0.30
const LINE_GAP_HIGH := 0.20

## Builds this tick's block parameters.
## [param mentality] -1..1, [param press] 0..1 (TacticPreset), [param ball_n]
## the ball in the team frame, [param line_adjust] the ball-pressure step
## (negative = drop, positive = step up), [param phase] TacticalBrain.Phase.
static func params_for(phase: int, mentality: float, press: float, ball_n: Vector2, line_adjust: float) -> Params:
	var p := Params.new()
	var m01 := (mentality + 1.0) * 0.5
	match phase:
		TacticalBrain.Phase.ATTACK, TacticalBrain.Phase.TRANSITION_ATTACK:
			p.length = lerpf(0.40, 0.52, m01)
			p.back_x = clampf(ball_n.x - lerpf(0.30, 0.22, m01), 0.10, 0.50)
			p.width = 0.92
			p.shift_y = 0.12
		_:
			p.length = lerpf(0.34, 0.28, press)
			var gap := lerpf(LINE_GAP_LOW, LINE_GAP_HIGH, press)
			p.back_x = clampf(ball_n.x - gap + line_adjust,
				lerpf(LINE_MIN_LOW, LINE_MIN_HIGH, press), lerpf(LINE_MAX_LOW, LINE_MAX_HIGH, press))
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
	x = clampf(x, 0.04, max_depth)
	y = clampf(y, 0.05, 0.95)
	return PitchSpace.from_normalised(Vector2(x, y), team_left)

func has_player(p: Player) -> bool:
	return _anchor.has(p)

## The formation rank (0 deepest … 1 highest) — used for role affinities.
func rank_of(p: Player) -> float:
	return _rank.get(p, 0.5)
