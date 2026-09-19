class_name TacticPreset
extends RefCounted

## A team's tactical lean. Two layers, matching how Football Manager's own
## mentality system works: a BASE derived automatically from the roster's
## role composition (no tactics-board UI work in this scope — see
## docs/ai-overhaul.md Phase 2), computed once per team per match and
## cached (a roster's composition doesn't change mid-match); and an
## EFFECTIVE value recomputed every tactical tick via update(), which is
## either a fixed manual mode the player picked live via MatchHUD's
## mentality button, or (in AUTO) the base adjusted for live game state
## (losing late pushes it up, protecting a lead late pulls it down) — see
## docs/ai-overhaul.md Phase 8.

enum ManualMode { AUTO, DEFENSIVE, NEUTRAL, AGGRESSIVE }

const MANUAL_MENTALITY := {
	ManualMode.DEFENSIVE: -1.0,
	ManualMode.NEUTRAL: 0.0,
	ManualMode.AGGRESSIVE: 1.0,
}
const MANUAL_PRESS_INTENSITY := {
	ManualMode.DEFENSIVE: 0.2,
	ManualMode.NEUTRAL: 0.5,
	ManualMode.AGGRESSIVE: 0.8,
}

## -1 (fully defensive-shaped) .. +1 (fully attacking-shaped), from the
## relative count of OFFENSE vs DEFENSE group roles among outfield players.
## Computed once in from_roster() and never changed afterward — the AUTO
## baseline update() adjusts from.
var base_mentality: float = 0.0

## Effective values every consumer (TeamTacticalState's line bias/press
## margin, eventually OnBallUtility's risk balance) actually reads —
## recomputed every tick by update(), either pinned to a manual mode or
## the base adjusted for game state.
var mentality: float = 0.0
var press_intensity: float = 0.5

static func from_roster(team: Array[Player]) -> TacticPreset:
	var preset := TacticPreset.new()
	var offense := 0
	var defense := 0
	var outfield := 0
	for p in team:
		if p.role == Positions.Role.GK:
			continue
		outfield += 1
		match Positions.group(p.role):
			Positions.Group.OFFENSE:
				offense += 1
			Positions.Group.DEFENSE:
				defense += 1
	if outfield > 0:
		preset.base_mentality = clampf(float(offense - defense) / float(outfield) * 2.0, -1.0, 1.0)
	preset.mentality = preset.base_mentality
	preset.press_intensity = clampf(0.5 + preset.mentality * 0.3, 0.0, 1.0)
	return preset

## [param manual_mode] — AUTO to use game-state reactivity, or a fixed mode
## the player picked live (overrides everything below while active).
## [param score_diff] — this team's goals minus the opponent's; negative
## means losing. [param time_fraction_remaining] — 1.0 at kickoff, 0.0 at
## full time; game state only matters once there's little time left to
## fix it, so the push scales with how late it is, not just the scoreline.
func update(manual_mode: int, score_diff: int, time_fraction_remaining: float) -> void:
	if manual_mode != ManualMode.AUTO:
		mentality = MANUAL_MENTALITY[manual_mode]
		press_intensity = MANUAL_PRESS_INTENSITY[manual_mode]
		return
	var urgency := 1.0 - clampf(time_fraction_remaining, 0.0, 1.0)
	var game_state_push := clampf(-float(score_diff), -1.0, 1.0) * urgency
	mentality = clampf(base_mentality + game_state_push, -1.0, 1.0)
	press_intensity = clampf(0.5 + mentality * 0.3, 0.0, 1.0)
