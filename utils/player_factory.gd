class_name PlayerFactory

## Generates random hireable players for the talent scout. Quality (rarity)
## odds and stat spread both scale with scout level — a level-1 scout finds
## almost nothing but Commons, a maxed-out one has a real shot at a Legendary.

const FIRST_NAMES : Array[String] = [
	"Lionel", "Angel", "Sergio", "Paulo", "Rodrigo", "Emiliano", "Nicolas",
	"Cristian", "Facundo", "Gonzalo", "Leandro", "Marcos", "Mateo", "Franco",
	"Bruno", "Ezequiel", "Diego", "Lautaro", "Thiago", "Joaquin", "Agustin",
	"Ivan", "Ramiro", "Tomas", "Julian",
]

const LAST_NAMES : Array[String] = [
	"Fernandez", "Gonzalez", "Rodriguez", "Lopez", "Martinez", "Garcia",
	"Perez", "Sanchez", "Romero", "Alvarez", "Torres", "Ruiz", "Ramirez",
	"Flores", "Acosta", "Benitez", "Medina", "Herrera", "Aguirre", "Ibanez",
	"Molina", "Silva", "Cabrera", "Ortiz", "Vega",
]

## odds[scout_level - 1] = weight per PlayerResource.Quality tier
## [Common, Uncommon, Rare, Epic, Legendary]. Weights don't need to sum to 100.
const QUALITY_ODDS : Array = [
	[90, 8, 2, 0, 0],
	[75, 18, 6, 1, 0],
	[55, 28, 12, 4, 1],
]

## [min, max] band each of the 6 stats is independently sampled from, per quality tier.
const STAT_RANGE : Array = [
	[30, 48],  # Common
	[45, 62],  # Uncommon
	[58, 74],  # Rare
	[70, 85],  # Epic
	[82, 96],  # Legendary
]

## Band the 1-2 "boosted" stats every player rolls (see _roll_boosted_indices)
## sample from instead of their own tier's STAT_RANGE — one tier up, so e.g. a
## Common can flash 1-2 Uncommon-grade stats while staying grey overall.
## Legendary has no tier above it, so its boosted band overshoots the normal
## 100 cap instead — this is how a Legendary ends up with 1-2 stats over 100.
const BOOST_STAT_RANGE : Array = [
	[45, 62],   # Common boosted stat rolls like an Uncommon
	[58, 74],   # Uncommon boosted stat rolls like a Rare
	[70, 85],   # Rare boosted stat rolls like an Epic
	[82, 96],   # Epic boosted stat rolls like a Legendary
	[95, 108],  # Legendary boosted stat — overflows past the 100 cap
]

const MIN_BOOSTED_STATS := 1
const MAX_BOOSTED_STATS := 2

const MIN_AGE := 16
const MAX_AGE := 33

## quality_odds: weights per PlayerResource.Quality tier [Common, Uncommon,
## Rare, Epic, Legendary] — pass QUALITY_ODDS[scout_level - 1] for scouting,
## or a division-based table (see ClubFactory) for squad generation.
## forced_role: assigns this role instead of rolling a random one — used by
## SquadGenerator so a generated squad can fill specific position slots.
## normal_skin_only: restricts the skin roll to Player.NORMAL_SKIN_COLORS —
## pass true for anyone destined for the player's own club (initial roster,
## scouting pool, youth academy); AI clubs leave it false and can roll any
## skin, special tones included.
static func generate_player(quality_odds: Array, forced_role: Positions.Role = -1, normal_skin_only: bool = false) -> PlayerResource:
	var quality : PlayerResource.Quality = _roll_quality(quality_odds)
	var role : Positions.Role = forced_role if forced_role >= 0 else Positions.DATA.keys().pick_random()
	var age := randi_range(MIN_AGE, MAX_AGE)
	var band : Array = STAT_RANGE[quality]
	var boost_band : Array = BOOST_STAT_RANGE[quality]
	var boosted_indices := _roll_boosted_indices()
	var stats : Array = []
	for i in 6:
		var stat_band : Array = boost_band if i in boosted_indices else band
		stats.append(clampi(randi_range(stat_band[0], stat_band[1]), 1, maxi(100, stat_band[1])))
	var full_name := "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()]
	var skin_pool : Array = Player.NORMAL_SKIN_COLORS if normal_skin_only else Player.SkinColor.values()
	return PlayerResource.new(
		full_name,
		skin_pool.pick_random(),
		Player.HairColor.values().pick_random(),
		role, age, quality,
		stats[0], stats[1], stats[2], stats[3], stats[4], stats[5],
		BodyTypes.roll_body_type(quality)
	)

## Picks 1-2 distinct stat indices (out of pac/sho/pas/dri/def/phy, 0-5) to
## sample from BOOST_STAT_RANGE instead of the player's own quality band.
static func _roll_boosted_indices() -> Array:
	var indices := range(6)
	indices.shuffle()
	return indices.slice(0, randi_range(MIN_BOOSTED_STATS, MAX_BOOSTED_STATS))

static func _roll_quality(weights: Array) -> PlayerResource.Quality:
	var total := 0
	for w in weights:
		total += w
	var roll := randi_range(1, total)
	var acc := 0
	for i in weights.size():
		acc += weights[i]
		if roll <= acc:
			return i as PlayerResource.Quality
	return PlayerResource.Quality.COMMON
