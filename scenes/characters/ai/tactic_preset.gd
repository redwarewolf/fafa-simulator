class_name TacticPreset
extends RefCounted

## A team's tactical lean, derived automatically from its roster's role
## composition (no tactics-board UI work in this scope — see
## docs/ai-overhaul.md Phase 2). Computed once per team per match by
## TeamTacticalState and cached, since a roster's role composition doesn't
## change mid-match.

## -1 (fully defensive-shaped) .. +1 (fully attacking-shaped), from the
## relative count of OFFENSE vs DEFENSE group roles among outfield players.
var mentality: float = 0.0
## 0 (passive) .. 1 (aggressive) — how eagerly this team contests the ball;
## derived from mentality for now (a more attacking-shaped side presses
## harder), not an independent knob yet.
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
		preset.mentality = clampf(float(offense - defense) / float(outfield) * 2.0, -1.0, 1.0)
	preset.press_intensity = clampf(0.5 + preset.mentality * 0.3, 0.0, 1.0)
	return preset
