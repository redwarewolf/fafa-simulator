class_name XtGrid
extends RefCounted

## Expected Threat (Singh, 2019): the probability that possession of the ball
## at a location ends in a goal within the next few actions. It's what makes
## "moving the ball to a better place" worth something before any shot exists,
## which is the currency on-ball decisions (OnBallEvaluator) trade in.
##
## First version is an ANALYTIC surface, not a fitted Markov table: a slow
## progression term (threat rises steeply only in the final third, and with
## centrality) plus part of the shot value of the location itself. Singh's
## xT at a spot is P(shoot)·xG + P(move)·(onward value), and P(shoot) near
## the box is only ~0.3-0.5 — the first cut used 0.8·xG, which made simply
## HOLDING the ball near goal worth more than shooting from it, so v2 sides
## dominated possession but almost never shot (1.2 shots / 180s in the first
## harness run). Coefficients hit the published 12×8 surface's landmarks —
## ~0.01 at halfway, ~0.08 at the edge of the box centrally, ~0.15 at the
## penalty spot, ~0.04 wide on the byline, ~0.005 in our own box. Phase 10
## re-fits it from harness data by value iteration (Singh's method).
##
## Cached as a RES_X × RES_Y table over team-relative normalised space
## (x = 0 own goal line → 1 opponent goal line) and sampled bilinearly.

const RES_X := 48
const RES_Y := 20
const BASE := 0.005
const PROGRESSION := 0.06
const SHOT_WEIGHT := 0.45

static var _table := PackedFloat32Array()

static func _ensure() -> void:
	if not _table.is_empty():
		return
	_table.resize(RES_X * RES_Y)
	# Reference goal: the right-hand goal mouth (±2.5m around the centre of the
	# right goal line), matching ShotModel's calibration.
	var cy := (PitchSpace.TOP_Y + PitchSpace.BOTTOM_Y) * 0.5
	var half_px := 2.5 / PitchSpace.metres_per_px().y
	var post_a := Vector2(PitchSpace.right_line_x(cy - half_px), cy - half_px)
	var post_b := Vector2(PitchSpace.right_line_x(cy + half_px), cy + half_px)
	for j in RES_Y:
		for i in RES_X:
			var n := Vector2((i + 0.5) / RES_X, (j + 0.5) / RES_Y)
			var centrality := 1.0 - 0.5 * pow(2.0 * absf(n.y - 0.5), 2.0)
			var progression := PROGRESSION * pow(n.x, 4.0) * centrality
			var world := PitchSpace.from_absolute_normalised(n)
			_table[j * RES_X + i] = BASE + progression + SHOT_WEIGHT * ShotModel.xg_basic(world, post_a, post_b)

## xT at team-relative normalised [param n] (bilinear, clamped to the pitch).
static func at_normalised(n: Vector2) -> float:
	_ensure()
	var fx := clampf(n.x * RES_X - 0.5, 0.0, RES_X - 1.001)
	var fy := clampf(n.y * RES_Y - 0.5, 0.0, RES_Y - 1.001)
	var i := int(fx)
	var j := int(fy)
	var tx := fx - i
	var ty := fy - j
	var a := lerpf(_table[j * RES_X + i], _table[j * RES_X + i + 1], tx)
	var b := lerpf(_table[(j + 1) * RES_X + i], _table[(j + 1) * RES_X + i + 1], tx)
	return lerpf(a, b, ty)

## xT of world point [param p] for a team attacking the right goal if
## [param is_left_team] (left teams attack right).
static func at(p: Vector2, is_left_team: bool) -> float:
	return at_normalised(PitchSpace.normalised(p, is_left_team))
