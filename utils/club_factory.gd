class_name ClubFactory

## Generates full AI-controlled clubs (identity + crest + squad) to fill a
## division procedurally, plus the shared division-quality-odds table and
## naming/slug helpers also used by the player's own club creation
## (see scenes/menu/team_creation.gd).

## Weights per PlayerResource.Quality tier [Common, Uncommon, Rare, Epic,
## Legendary], one row per division. Only "E" is wired up to a real screen
## today — the rest are extrapolated on the same curve as PlayerFactory's
## existing scout-level table, ready for when other divisions go procedural.
const DIVISION_QUALITY_ODDS : Dictionary = {
	"E": [95, 4, 1, 0, 0],
	"D": [80, 15, 4, 1, 0],
	"C": [65, 22, 10, 3, 0],
	"B": [45, 28, 18, 7, 2],
	"A": [25, 30, 25, 15, 5],
}

## Lowest to highest division.
const DIVISION_ORDER : Array[String] = ["E", "D", "C", "B", "A"]

const STARTING_BUDGET : Dictionary = {
	"E": 300000,
	"D": 90000,
	"C": 150000,
	"B": 250000,
	"A": 400000,
}

const NAME_PREFIXES : Array[String] = [
	"Deportivo", "Racing", "Atlético", "Unión", "Real", "Sporting",
	"Club Atlético", "San", "Los",
]
const NAME_NOUNS : Array[String] = [
	"Gambeta", "Ladrillo", "Pataduras", "Chispas", "Piñata", "Fulbos",
	"Chanchito", "Pelotazo", "Rebote", "Bochinche", "Alambre", "Trapito",
	"Zapatilla", "Barrio", "Esquina", "Potrero",
]
const NAME_SUFFIXES : Array[String] = ["FC", "United", "de la Esquina", "del Barrio"]

const MAX_NAME_TRIES := 50


## The quality odds a new club in this division generates its OWN squad with.
static func own_odds_for(division: String) -> Array:
	return DIVISION_QUALITY_ODDS.get(division, DIVISION_QUALITY_ODDS["E"])

## AI's "slight edge": AI-controlled clubs roll against the next division
## up's odds table (clamped at the top), rather than a separate bonus knob.
static func ai_odds_for(division: String) -> Array:
	var idx := DIVISION_ORDER.find(division)
	if idx < 0:
		idx = 0
	var next_idx : int = mini(idx + 1, DIVISION_ORDER.size() - 1)
	return DIVISION_QUALITY_ODDS[DIVISION_ORDER[next_idx]]

static func starting_budget(division: String) -> int:
	return STARTING_BUDGET.get(division, STARTING_BUDGET["E"])

## Stable slug for a club id / save lookup key: lowercase, non-alnum runs
## collapsed to single hyphens, trimmed. Shared by AI generation and the
## player's own Team Creation screen so ids always look the same.
static func slugify(display_name: String) -> String:
	var slug := display_name.to_lower().strip_edges()
	var out := ""
	var last_was_hyphen := true  # swallow any leading hyphen
	for c in slug:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			last_was_hyphen = false
		elif not last_was_hyphen:
			out += "-"
			last_was_hyphen = true
	return out.rstrip("-") if not out.is_empty() else "club"

## Resolves a slug that doesn't collide with any id in `taken`, appending
## "-2", "-3", ... as needed.
static func unique_slug(display_name: String, taken: Array) -> String:
	var base := slugify(display_name)
	var slug := base
	var n := 2
	while taken.has(slug):
		slug = "%s-%d" % [base, n]
		n += 1
	return slug

static func team_key_for(display_name: String) -> String:
	return display_name.to_upper()

## Every random pick in this file goes through here so an optional seeded
## RandomNumberGenerator (a future "world seed" field on Team Creation) can
## make a whole generation pass reproducible; null falls back to the engine's
## global RNG, same as everywhere else in the codebase.
static func _ri(rng: RandomNumberGenerator, from: int, to: int) -> int:
	return rng.randi_range(from, to) if rng else randi_range(from, to)

static func _rf(rng: RandomNumberGenerator, from: float, to: float) -> float:
	return rng.randf_range(from, to) if rng else randf_range(from, to)

static func _pick(arr: Array, rng: RandomNumberGenerator):
	return arr[_ri(rng, 0, arr.size() - 1)]

static func _random_kit_color(rng: RandomNumberGenerator = null) -> Color:
	return Color.from_hsv(_rf(rng, 0.0, 1.0), _rf(rng, 0.55, 0.9), _rf(rng, 0.6, 0.95))

static func _random_name(rng: RandomNumberGenerator = null) -> String:
	var prefix : String = _pick(NAME_PREFIXES, rng)
	var noun : String = _pick(NAME_NOUNS, rng)
	var suffix : String = _pick(NAME_SUFFIXES, rng)
	match _ri(rng, 0, 2):
		0: return "%s %s" % [prefix, noun]
		1: return "%s %s" % [noun, suffix]
		_: return "%s de %s" % [prefix, noun]

## Generates one fully-formed AI club for `division`. `taken_names`/`taken_ids`
## should include every name/id already used this generation pass (other AI
## clubs, plus the player's own club) so this one doesn't collide.
static func generate_ai_club(division: String, taken_names: Array, taken_ids: Array, rng: RandomNumberGenerator = null) -> ClubResource:
	var display_name := _random_name(rng)
	var tries := 0
	while taken_names.has(display_name) and tries < MAX_NAME_TRIES:
		display_name = _random_name(rng)
		tries += 1

	var id := unique_slug(display_name, taken_ids)
	var team_key := team_key_for(display_name)
	var logo_template := _ri(rng, 1, 2)
	var primary := _random_kit_color(rng)
	var secondary := _random_kit_color(rng)

	var club := ClubResource.new(
		id, display_name, team_key, division,
		primary, secondary, "", logo_template,
		starting_budget(division), 0
	)
	club.players = SquadGenerator.generate_squad(ai_odds_for(division))
	return club

## Generates `count` AI clubs at once, threading name/id collision-avoidance
## through the whole batch. `taken_names`/`taken_ids` are extended in place
## with each new club as it's generated (Arrays are references in GDScript),
## so a caller building a mixed player+AI batch can keep passing the same
## lists in — see scenes/menu/team_creation.gd and hub.gd's dev fallback.
static func generate_ai_clubs(division: String, count: int, taken_names: Array, taken_ids: Array, rng: RandomNumberGenerator = null) -> Array[ClubResource]:
	var clubs : Array[ClubResource] = []
	for i in count:
		var club := generate_ai_club(division, taken_names, taken_ids, rng)
		taken_names.append(club.display_name)
		taken_ids.append(club.id)
		clubs.append(club)
	return clubs
