class_name Formations

## Formation position templates — FULL-FIELD normalised space:
##   x=0 → own goal line,  x=0.5 → halfway line,  x=1 → opponent goal line
##   y=0 → top touchline,  y=1 → bottom touchline
##
## These used to be half-field (x=1 meant the halfway line), which made a
## forward's anchor literally inexpressible past the centre circle. They are
## ANCHORS — where a player wants to be when the shape is settled — not kickoff
## spots: ActorsContainer compresses them into the own half for the restart.
##
## Attacking direction is left-to-right, so y=0 is the player's RIGHT.
##
## Single source of truth — GameState.add_tactic() builds TacticResource slots
## from ALL + ROLES, and field_overlay.gd renders/drags those slots.

## Every template lists the goalkeeper first. The tactics board pins that slot
## and GoalieAI positions itself off its spawn point, so the keeper must
## stay where the preset put it — on the goal line.
const GOALKEEPER_SLOT := 0

const ALL : Dictionary = {
	"4-3-3": [
		Vector2(0.03, 0.50),                                                                 # GK
		Vector2(0.22, 0.12), Vector2(0.15, 0.37), Vector2(0.15, 0.63), Vector2(0.22, 0.88),  # back four
		Vector2(0.46, 0.28), Vector2(0.34, 0.50), Vector2(0.46, 0.72),                       # midfield
		Vector2(0.66, 0.12), Vector2(0.76, 0.50), Vector2(0.66, 0.88),                       # front three
	],
	"4-4-2": [
		Vector2(0.03, 0.50),
		Vector2(0.22, 0.12), Vector2(0.15, 0.37), Vector2(0.15, 0.63), Vector2(0.22, 0.88),
		Vector2(0.48, 0.12), Vector2(0.42, 0.37), Vector2(0.42, 0.63), Vector2(0.48, 0.88),
		Vector2(0.72, 0.35), Vector2(0.72, 0.65),
	],
	"3-5-2": [
		Vector2(0.03, 0.50),
		Vector2(0.16, 0.25), Vector2(0.15, 0.50), Vector2(0.16, 0.75),
		Vector2(0.42, 0.08), Vector2(0.40, 0.30), Vector2(0.32, 0.50), Vector2(0.40, 0.70), Vector2(0.42, 0.92),
		Vector2(0.74, 0.38), Vector2(0.74, 0.62),
	],
	"4-2-3-1": [
		Vector2(0.03, 0.50),
		Vector2(0.22, 0.12), Vector2(0.15, 0.37), Vector2(0.15, 0.63), Vector2(0.22, 0.88),
		Vector2(0.32, 0.38), Vector2(0.32, 0.62),
		Vector2(0.62, 0.14), Vector2(0.58, 0.50), Vector2(0.62, 0.86),
		Vector2(0.78, 0.50),
	],
	"5-3-2": [
		Vector2(0.03, 0.50),
		Vector2(0.24, 0.08), Vector2(0.14, 0.30), Vector2(0.13, 0.50), Vector2(0.14, 0.70), Vector2(0.24, 0.92),
		Vector2(0.42, 0.28), Vector2(0.34, 0.50), Vector2(0.42, 0.72),
		Vector2(0.72, 0.38), Vector2(0.72, 0.62),
	],
	"3-4-3": [
		Vector2(0.03, 0.50),
		Vector2(0.16, 0.25), Vector2(0.15, 0.50), Vector2(0.16, 0.75),
		Vector2(0.46, 0.10), Vector2(0.40, 0.36), Vector2(0.40, 0.64), Vector2(0.46, 0.90),
		Vector2(0.68, 0.14), Vector2(0.78, 0.50), Vector2(0.68, 0.86),
	],
}

## The position each slot asks for, index-matched to ALL. Drop a player whose
## own position differs and Positions.aptitude() reports how badly they fit.
## Wide slots deliberately use the flank-holding positions (LB/RB as wing backs
## in 3-5-2 and 3-4-3, LM/RM rather than narrow CMs in 4-4-2), because holding
## a touchline is a property of the position, not of the anchor.
const ROLES : Dictionary = {
	"4-3-3": [
		Positions.Role.GK,
		Positions.Role.RB, Positions.Role.CB, Positions.Role.CB, Positions.Role.LB,
		Positions.Role.CM, Positions.Role.CDM, Positions.Role.CM,
		Positions.Role.RW, Positions.Role.ST, Positions.Role.LW,
	],
	"4-4-2": [
		Positions.Role.GK,
		Positions.Role.RB, Positions.Role.CB, Positions.Role.CB, Positions.Role.LB,
		Positions.Role.RM, Positions.Role.CM, Positions.Role.CM, Positions.Role.LM,
		Positions.Role.ST, Positions.Role.ST,
	],
	"3-5-2": [
		Positions.Role.GK,
		Positions.Role.CB, Positions.Role.CB, Positions.Role.CB,
		Positions.Role.RB, Positions.Role.CM, Positions.Role.CDM, Positions.Role.CM, Positions.Role.LB,
		Positions.Role.ST, Positions.Role.ST,
	],
	"4-2-3-1": [
		Positions.Role.GK,
		Positions.Role.RB, Positions.Role.CB, Positions.Role.CB, Positions.Role.LB,
		Positions.Role.CDM, Positions.Role.CDM,
		Positions.Role.RW, Positions.Role.CAM, Positions.Role.LW,
		Positions.Role.ST,
	],
	"5-3-2": [
		Positions.Role.GK,
		Positions.Role.RB, Positions.Role.CB, Positions.Role.CB, Positions.Role.CB, Positions.Role.LB,
		Positions.Role.CM, Positions.Role.CDM, Positions.Role.CM,
		Positions.Role.ST, Positions.Role.ST,
	],
	"3-4-3": [
		Positions.Role.GK,
		Positions.Role.CB, Positions.Role.CB, Positions.Role.CB,
		Positions.Role.RM, Positions.Role.CM, Positions.Role.CM, Positions.Role.LM,
		Positions.Role.RW, Positions.Role.ST, Positions.Role.LW,
	],
}

const DEFAULT_TEMPLATE := "4-3-3"

## Anchors for [param template], falling back to the default template.
static func positions_for(template: String) -> Array:
	return ALL.get(template, ALL[DEFAULT_TEMPLATE])

## Slot positions for [param template], index-matched to positions_for().
## Falls back to the default template, and pads with CM if a template's two
## lists ever drift out of step rather than spawning a short eleven.
static func roles_for(template: String) -> Array:
	var anchors : Array = positions_for(template)
	var roles : Array = ROLES.get(template, ROLES[DEFAULT_TEMPLATE]).duplicate()
	if roles.size() != anchors.size():
		push_error("Formations: '%s' has %d anchors but %d roles" % [template, anchors.size(), roles.size()])
		while roles.size() < anchors.size():
			roles.append(Positions.Role.CM)
		roles.resize(anchors.size())
	return roles
