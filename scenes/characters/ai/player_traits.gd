class_name PlayerTraits
extends RefCounted

## Small per-player personality layer on top of role-level weights — the
## FC-IQ-style idea that two players in the same position shouldn't play
## identically (a Poacher striker vs. a Target Man). Purely additive data:
## a Kind derived deterministically from a player's own existing stats (no
## new persisted field, no roster-generation changes needed), and a lookup
## of multipliers RoleAI applies on top of its existing role_weights() /
## run_support_weight() — no new architecture. See docs/ai-overhaul.md
## Phase 4.

enum Kind { NONE, POACHER, TARGET_MAN, WIDE_OUTLET, PLAYMAKER, BOX_TO_BOX, FULL_BACK, STOPPER }

## Deterministic from the player's own effective stats and role, so the
## same player always gets the same trait — no randomness or save-data
## migration needed. Trait pool is role-group-appropriate. DEFENSE used to
## fall through to NONE unconditionally (a marauding overlapping full-back
## and a stay-at-home centre-back had identical on-ball tendencies) even
## though OFFENSE already splits by the same holds_flank check for
## WIDE_OUTLET — same bug shape as the wing-back positioning fix, just in
## the trait layer instead of positioning. See docs/ai-overhaul.md Phase 6.
static func derive(player: Player) -> Kind:
	match Positions.group(player.role):
		Positions.Group.OFFENSE:
			if player.physicality >= player.speed and player.physicality >= player.dribbling:
				return Kind.TARGET_MAN
			if Positions.holds_flank(player.role) and player.speed >= player.dribbling:
				return Kind.WIDE_OUTLET
			return Kind.POACHER
		Positions.Group.MIDFIELD:
			return Kind.PLAYMAKER if player.passing >= player.dribbling else Kind.BOX_TO_BOX
		Positions.Group.DEFENSE:
			return Kind.FULL_BACK if Positions.holds_flank(player.role) else Kind.STOPPER
		_:
			return Kind.NONE

const WEIGHT_MULTIPLIERS := {
	Kind.NONE:        {"shoot": 1.0,  "pass": 1.0,  "dribble": 1.0},
	Kind.POACHER:     {"shoot": 1.25, "pass": 0.85, "dribble": 0.9},
	Kind.TARGET_MAN:  {"shoot": 1.05, "pass": 0.9,  "dribble": 0.75},
	Kind.WIDE_OUTLET: {"shoot": 0.85, "pass": 1.1,  "dribble": 1.2},
	Kind.PLAYMAKER:   {"shoot": 0.8,  "pass": 1.25, "dribble": 0.9},
	Kind.BOX_TO_BOX:  {"shoot": 1.0,  "pass": 1.0,  "dribble": 1.1},
	Kind.FULL_BACK:   {"shoot": 1.0,  "pass": 1.0,  "dribble": 1.3},
	Kind.STOPPER:     {"shoot": 0.7,  "pass": 1.1,  "dribble": 0.6},
}

## Added to RoleAI.run_support_weight() — how much more/less eagerly this
## personality breaks beyond the ball carrier. A Target Man holds the focal
## point instead of sprinting into channels; a Box-to-Box midfielder's whole
## signature is bursting forward.
const RUN_SUPPORT_DELTA := {
	Kind.NONE: 0.0,
	Kind.POACHER: 0.1,
	Kind.TARGET_MAN: -0.2,
	Kind.WIDE_OUTLET: 0.15,
	Kind.PLAYMAKER: -0.1,
	Kind.BOX_TO_BOX: 0.2,
	Kind.FULL_BACK: 0.15,
	Kind.STOPPER: -0.1,
}

## Applies this trait's multipliers on top of [param base_weights] (a
## role_weights()-shaped dict) without mutating it.
static func apply_weights(kind: Kind, base_weights: Dictionary) -> Dictionary:
	var mult : Dictionary = WEIGHT_MULTIPLIERS.get(kind, WEIGHT_MULTIPLIERS[Kind.NONE])
	var out := base_weights.duplicate()
	for key in ["shoot", "pass", "dribble"]:
		out[key] = float(out.get(key, 1.0)) * float(mult.get(key, 1.0))
	return out

static func run_support_delta(kind: Kind) -> float:
	return RUN_SUPPORT_DELTA.get(kind, 0.0)
