class_name YouthEventPool

## Static data table of narrated youth-academy sign-up events, rolled/built by
## utils/youth_events.gd — same plain-Dictionary static-table shape as
## RandomEventPool, but each entry describes a KID to offer rather than a
## mechanical effect, since the player accepts/declines rather than the event
## just happening.
##
## Events are grouped into three CATEGORIES (see below), matching the game
## design's three kinds of sign-up: a mom paying to reserve her kid a spot
## (cash_signup), a mom signing her kid up for free (free_signup), and a rare
## contested prodigy the club has to pay to sign (prodigy_signup). Which
## category rolls is decided first (by CATEGORIES' own weights), then which
## flavor of line within that category (by each entry's own weight) — this
## lets a category have multiple narrated variants (see coney_mccone_signup)
## without skewing how often the category itself comes up.
##
## Category mechanics:
##   weight        - relative odds this category is picked by
##                    YouthEvents.maybe_daily_signup() (45/45/10 split, per
##                    the 80%-chance-per-day-then-10%-of-those-are-a-prodigy
##                    design).
##   quality_span  - [low, high] offset added to the club's own tier index
##                    (see YouthEvents._tier_index_for(), itself derived from
##                    ClubFactory.DIVISION_ORDER) and clamped to
##                    PlayerResource.Quality's range, giving the inclusive
##                    band the kid's quality is rolled uniformly from.
##   reserved      - once accepted, can the kid be released from the academy
##                    before he graduates? (see PlayerResource.reserved).
##   fee_direction - who fee_amount (if the entry rolls one) is paid by:
##                    "to_us" (the family pays the club), "to_family" (the
##                    club pays the family), or "none".
const CATEGORIES := {
	"cash_signup": {
		"weight": 45.0, "quality_span": [-99, 0],
		"reserved": true, "fee_direction": "to_us",
	},
	"free_signup": {
		"weight": 45.0, "quality_span": [0, 1],
		"reserved": false, "fee_direction": "none",
	},
	"prodigy_signup": {
		"weight": 10.0, "quality_span": [1, 2],
		"reserved": false, "fee_direction": "to_family",
	},
}

## Stable id of the guaranteed, no-roll event fired the moment the academy is
## first hired (see YouthEvents.first_signup_event()) — must name an entry
## below. A plain free sign-up, so the player's first prospect never costs
## anything or comes with strings attached.
const FIRST_EVENT_ID := "free_generic"

## Keys per entry:
##   id            - stable slug, for debugging/logging (and FIRST_EVENT_ID).
##   category      - key into CATEGORIES above; drives quality/reserved/fee
##                    mechanics for this entry.
##   weight        - relative odds when rolled within its own category.
##   line_template - Pepito Perinola's pitch; {player}/{amount} placeholders
##                    get filled from the built kid/fee.
##   kid           - "random" (a rolled kid, quality per its category's
##                    quality_span) or "special" (a fixed SpecialPlayerTypes
##                    archetype, quality forced by that archetype instead).
##   special_type / special_name - only for kid == "special".
##   fee           - null, or {min, max} — a one-time amount rolled if
##                    accepted, moved per its category's fee_direction.
const SIGNUP_EVENTS := [
	{
		"id": "free_generic",
		"category": "free_signup",
		"weight": 6.0,
		"line_template": "La mamá de {player} quiere anotarlo en la Academia Juvenil, sin vueltas de por medio. ¿Le damos una oportunidad?",
		"kid": "random",
		"fee": null,
	},
	{
		"id": "cash_generic",
		"category": "cash_signup",
		"weight": 6.0,
		"line_template": "La mamá de {player} nos ofrece ${amount} para anotarlo en la Academia. Eso sí: hasta que cumpla 18 el pibe es intocable, nada de liberarlo antes.",
		"kid": "random",
		"fee": {"min": 300, "max": 900},
	},
	{
		"id": "coney_mccone_signup",
		"category": "cash_signup",
		"weight": 1.0,
		"line_template": "La mamá de Coney McCone quiere anotarlo en la Academia... y nos va a pagar ${amount} para que lo dejemos entrar. Es un cono de tránsito, pero plata es plata. Eso sí, hasta los 18 no se toca.",
		"kid": "special",
		"special_type": "cone",
		"special_name": "Coney McCone",
		"fee": {"min": 600, "max": 800},
	},
	{
		"id": "prodigy_generic",
		"category": "prodigy_signup",
		"weight": 6.0,
		"line_template": "Se corre la bola de un pibe prodigio, {player}... pero está muy peleado. Si lo queremos en la Academia, hay que pagarle ${amount} a la familia.",
		"kid": "random",
		"fee": {"min": 1500, "max": 4000},
	},
]
