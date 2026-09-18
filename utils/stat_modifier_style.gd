class_name StatModifierStyle

## Stat-modifier delta → display color. Single source of truth — same shape as
## QualityStyle, so player_card.gd and stat_radar.gd render deltas identically.

const POSITIVE_COLOR := Color("4caf50")  # green — matches QualityStyle's Uncommon green
const NEGATIVE_COLOR := Color("e8544a")  # red
const NEUTRAL_COLOR  := Color(1, 1, 1, 1)  # white — no modifier

static func color_for_delta(delta_value: int) -> Color:
	if delta_value > 0:
		return POSITIVE_COLOR
	if delta_value < 0:
		return NEGATIVE_COLOR
	return NEUTRAL_COLOR
