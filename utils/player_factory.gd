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

const MIN_AGE := 16
const MAX_AGE := 33

## quality_odds: weights per PlayerResource.Quality tier [Common, Uncommon,
## Rare, Epic, Legendary] — pass QUALITY_ODDS[scout_level - 1] for scouting,
## or a division-based table (see ClubFactory) for squad generation.
## forced_role: assigns this role instead of rolling a random one — used by
## SquadGenerator so a generated squad can fill specific position slots.
static func generate_player(quality_odds: Array, forced_role: Positions.Role = -1) -> PlayerResource:
	var quality : PlayerResource.Quality = _roll_quality(quality_odds)
	var role : Positions.Role = forced_role if forced_role >= 0 else Positions.DATA.keys().pick_random()
	var age := randi_range(MIN_AGE, MAX_AGE)
	var band : Array = STAT_RANGE[quality]
	var stats : Array = []
	for i in 6:
		stats.append(clampi(randi_range(band[0], band[1]), 1, 100))
	var full_name := "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()]
	return PlayerResource.new(
		full_name,
		Player.SkinColor.values().pick_random(),
		Player.HairColor.values().pick_random(),
		role, age, quality,
		stats[0], stats[1], stats[2], stats[3], stats[4], stats[5],
		BodyTypes.roll_body_type(quality)
	)

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
