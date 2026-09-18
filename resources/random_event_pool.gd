class_name RandomEventPool

## Static data tables of random events that can fire on the Hub (between
## matches) or mid-match — see RandomEvents (utils/random_events.gd), which
## rolls whether one fires and picks from these, and RandomEventEffects,
## which applies whatever effect_id names. Same plain-Dictionary static-table
## shape as StaffData/SpecialPlayerTypes, so no custom Resource class is
## needed just to hold this data.
##
## Keys per entry:
##   id            - stable slug, not currently read anywhere but useful for
##                    debugging/logging.
##   polarity      - "positive"/"negative", metadata for future filtering/UI.
##   weight        - relative odds within its own pool (HUB_EVENTS vs
##                    MATCH_EVENTS are rolled separately, never against each other).
##   line_template - Pepito Perinola's line; {player}/{amount}/{matches}
##                    placeholders get filled from whatever RandomEventEffects
##                    returns for this effect_id.
##   effect_id / effect_params - see RandomEventEffects.apply().

const HUB_EVENTS := [
	{
		"id": "wild_night_out",
		"polarity": "negative",
		"weight": 1.0,
		"line_template": "{player} se mandó una noche de joda de novela. Va a jugar igual, pero viene arrastrando la resaca: -{pct}% en todo durante los próximos {matches} partidos.",
		"effect_id": "apply_stat_debuff",
		"effect_params": {"min_pct": 5, "max_pct": 15, "min_matches": 1, "max_matches": 3},
	},
	{
		"id": "board_skims_the_till",
		"polarity": "negative",
		"weight": 1.0,
		"line_template": "Un directivo \"reasignó\" unos mangos del club al puesto de empanadas de un primo. Perdimos ${amount}.",
		"effect_id": "budget_delta",
		"effect_params": {"min": -12000, "max": -4000},
	},
	{
		"id": "mystery_benefactor",
		"polarity": "positive",
		"weight": 1.0,
		"line_template": "Un benefactor misterioso nos giró ${amount}, sin hacer preguntas. Seguro que no hay nada raro ahí.",
		"effect_id": "budget_delta",
		"effect_params": {"min": 6000, "max": 18000},
	},
]

const MATCH_EVENTS := [
	{
		"id": "pitch_invader",
		"polarity": "negative",
		"weight": 1.0,
		"line_template": "Un loquito se metió a la cancha y dio toda una vuelta corriendo. Papelón. Perdimos {amount} hinchas por la vergüenza.",
		"effect_id": "fans_delta",
		"effect_params": {"min": -40, "max": -10},
	},
	{
		"id": "home_crowd_surge",
		"polarity": "positive",
		"weight": 1.0,
		"line_template": "La gente está a full y se vació el puesto de comida. Son ${amount} extra en la caja.",
		"effect_id": "budget_delta",
		"effect_params": {"min": 1000, "max": 4000},
	},
]
