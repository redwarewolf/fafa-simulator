class_name MentalAttributes
extends RefCounted

## Hidden mental attributes (0-100) derived at match time from a player's
## existing stats, personality (teamplay) and age — no save-format, generation
## or UI change (user decision, docs/match-engine-v2.md). They're what makes
## stat differences VISIBLE in behaviour instead of only in dice rolls:
## a low-`decisions` player picks worse options more often, a low-`composure`
## one takes longer to act on the ball, a low-`positioning` defender stands
## a few metres off where the shape wants him, and so on.
##
## Experience (age) adds up to ±EXPERIENCE_SPREAD to the "reading the game"
## attributes, peaking around 29 — teenagers are rash, veterans read play.

const EXPERIENCE_SPREAD := 8.0

var vision := 50.0
var decisions := 50.0
var anticipation := 50.0
var positioning := 50.0
var composure := 50.0
var work_rate := 50.0
var aggression := 50.0
var off_ball := 50.0

static func derive(p: Player) -> MentalAttributes:
	var m := MentalAttributes.new()
	var age := 25
	if p.player_data != null:
		age = p.player_data.age
	var exp := (clampf((age - 17.0) / 12.0, 0.0, 1.0) * 2.0 - 1.0) * EXPERIENCE_SPREAD
	m.vision = _c(0.7 * p.passing + 0.15 * p.dribbling + 0.15 * p.power + exp * 0.5)
	m.decisions = _c(0.4 * p.passing + 0.3 * p.defense + 0.3 * p.dribbling + exp)
	m.anticipation = _c(0.5 * p.defense + 0.25 * p.pace + 0.25 * p.passing + exp)
	m.positioning = _c(0.7 * p.defense + 0.3 * p.physicality + exp)
	m.composure = _c(0.35 * p.dribbling + 0.35 * p.passing + 0.3 * p.power + exp)
	m.work_rate = _c(0.5 * p.physicality + 0.3 * p.teamplay + 0.2 * p.pace)
	m.aggression = _c(0.6 * p.defense + 0.4 * p.physicality)
	m.off_ball = _c(0.4 * p.pace + 0.3 * p.power + 0.3 * p.dribbling + exp * 0.5)
	return m

static func _c(v: float) -> float:
	return clampf(v, 1.0, 99.0)

static func _f(v: float) -> float:
	return v / 100.0

# ─── Behavioural parameters ─────────────────────────────────────────────────

## Softmax temperature for on-ball choices, RELATIVE to the best option's
## value (see OnBallEvaluator._softmax_pick): 0.05 means options within ~5%
## of the best are real contenders — a sharp decision-maker; 0.35 means even
## clearly worse options get picked fairly often.
func decision_temperature() -> float:
	return lerpf(0.35, 0.05, _f(decisions))

## Seconds between gaining the ball and the first on-ball decision (the
## "first touch" window — a composed player releases a one-touch pass).
func first_touch_delay() -> float:
	return lerpf(0.4, 0.1, _f(composure))

## Standard deviation (px) of the error in where this player takes up a
## position — shape-keeping precision.
func position_noise_px() -> float:
	return lerpf(30.0, 3.0, _f(positioning))

## Multiplier on how readily the player commits to a tackle when in range.
func tackle_eagerness() -> float:
	return lerpf(0.5, 1.2, _f(aggression))

## Seconds added to how early this player reads a loose ball / pass —
## better anticipation starts moving sooner.
func reaction_time() -> float:
	return lerpf(0.3, 0.08, _f(anticipation))

## How far (px) an off-ball player will search from their job anchor for a
## better spot — vision/off-ball movement finds more of the pitch.
func search_radius() -> float:
	return lerpf(40.0, 110.0, _f((vision + off_ball) * 0.5))
