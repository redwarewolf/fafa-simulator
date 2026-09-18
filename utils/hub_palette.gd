class_name HubPalette

## Accent colours shared by the Hub screens. Single source of truth — the gold
## "this is you / this is next" highlight and the result colours used to live as
## raw Color literals inside calendar_section.gd and tournament_section.gd.

const HIGHLIGHT := Color(1.0, 0.85, 0.2, 1.0)   ## Player's own club, next fixture
const WIN       := Color(0.4, 0.9, 0.4, 1.0)
const LOSS      := Color(0.9, 0.4, 0.4, 1.0)
const DRAW      := Color(0.85, 0.85, 0.85, 1.0)
const MUTED     := Color(0.62, 0.72, 0.78, 1.0)  ## Secondary//label text

## Colour for a result from the point of view of `own_score`.
static func result_color(own_score: int, opp_score: int) -> Color:
	if own_score > opp_score:
		return WIN
	if own_score < opp_score:
		return LOSS
	return DRAW
