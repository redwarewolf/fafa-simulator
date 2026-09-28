class_name TacticalBrain
extends RefCounted

## Team-level game-state reader (Phase 4): which phase of play the team is in,
## with hysteresis so a scrappy 50/50 doesn't flip the whole team between
## attacking and defending shape every tick.
##
## Ownership is what's OBSERVED (who has the ball, or whose pass is in flight
## and will reach a teammate, or who'll win the loose ball); it only becomes
## the COMMITTED owner once it has held for CONFIRM_S (shorter when a player
## has the ball at their feet — that's unambiguous). A change of committed
## owner opens a TRANSITION window (counter-attack / counter-press), which
## decays into the settled phase after the window.

enum Phase { ATTACK, DEFENCE, TRANSITION_ATTACK, TRANSITION_DEFENCE, LOOSE_BALL }

const PHASE_NAMES := {
	Phase.ATTACK: "attack", Phase.DEFENCE: "defence", Phase.TRANSITION_ATTACK: "transition_attack",
	Phase.TRANSITION_DEFENCE: "transition_defence", Phase.LOOSE_BALL: "loose_ball",
}

## Owner values.
const US := 1
const THEM := -1
const NOBODY := 0

const CONFIRM_CARRIED_S := 0.15
const CONFIRM_LOOSE_S := 0.5
## Transition windows: the classic "5-second" counter-press, and a shorter
## counter-attack window before the team settles into its build-up shape.
const TRANSITION_DEFENCE_S := 5.0
const TRANSITION_ATTACK_S := 4.0
## A loose ball "belongs" to whichever side will clearly reach it first.
const LOOSE_MARGIN_S := 0.35

var team_left := true
var phase : int = Phase.DEFENCE
var owner : int = NOBODY
var owner_since := 0.0
var _candidate : int = NOBODY
var _candidate_since := 0.0
## Counts of committed phase changes — harness telemetry for "flip-flopping".
var phase_changes := 0

func _init(p_team_left: bool) -> void:
	team_left = p_team_left

func update(ctx: MatchContext, now: float) -> void:
	var observed := _observe(ctx)
	var confirm := CONFIRM_CARRIED_S if ctx.ball.carrier != null else CONFIRM_LOOSE_S
	if observed == owner:
		_candidate = observed
		_candidate_since = now
	elif observed != _candidate:
		_candidate = observed
		_candidate_since = now
	elif now - _candidate_since >= confirm:
		var previous := owner
		owner = observed
		owner_since = now
		_set_phase(_phase_for_new_owner(previous, owner))
	# Transitions decay into settled phases.
	if phase == Phase.TRANSITION_ATTACK and now - owner_since > TRANSITION_ATTACK_S:
		_set_phase(Phase.ATTACK)
	elif phase == Phase.TRANSITION_DEFENCE and now - owner_since > TRANSITION_DEFENCE_S:
		_set_phase(Phase.DEFENCE)

func _set_phase(p: int) -> void:
	if p != phase:
		phase = p
		phase_changes += 1

func _phase_for_new_owner(previous: int, now_owner: int) -> int:
	match now_owner:
		US:
			return Phase.TRANSITION_ATTACK if previous == THEM else Phase.ATTACK
		THEM:
			return Phase.TRANSITION_DEFENCE if previous == US else Phase.DEFENCE
		_:
			return Phase.LOOSE_BALL

func _observe(ctx: MatchContext) -> int:
	var carrier := ctx.ball.carrier
	if carrier != null:
		return US if carrier.is_left_team == team_left else THEM
	# A pass in flight still belongs to the passing side if one of theirs
	# gets there first.
	var ours : Dictionary = ctx.first_to_ball(team_left)
	var theirs : Dictionary = ctx.first_to_ball(not team_left)
	if not ctx.last_pass.is_empty():
		var passing_side := US if ctx.last_pass["left"] == team_left else THEM
		var passer_first : bool = (ours["time"] <= theirs["time"]) if passing_side == US else (theirs["time"] <= ours["time"])
		if passer_first:
			return passing_side
	if ours["time"] + LOOSE_MARGIN_S < theirs["time"]:
		return US
	if theirs["time"] + LOOSE_MARGIN_S < ours["time"]:
		return THEM
	return NOBODY

func in_possession() -> bool:
	return phase == Phase.ATTACK or phase == Phase.TRANSITION_ATTACK

func out_of_possession() -> bool:
	return phase == Phase.DEFENCE or phase == Phase.TRANSITION_DEFENCE
