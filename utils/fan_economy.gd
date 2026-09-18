class_name FanEconomy

## Formulas for the club's fan count and the matchday/merchandise income it
## drives. All numbers live here so tuning the economy never means hunting
## through season_manager.gd/game_state.gd for a stray magic number.

## Fan swing scales up with division prestige.
const DIVISION_FAN_MULTIPLIER := {"E": 1.0, "D": 1.5, "C": 2.0, "B": 3.0, "A": 4.5}

const WIN_FANS_MIN  := 40
const WIN_FANS_MAX  := 120
const DRAW_FANS_MIN := -20
const DRAW_FANS_MAX := 30
const LOSS_FANS_MIN := -90
const LOSS_FANS_MAX := -20

## A club never drops below this many fans — there's always a small core
## fanbase left, no matter how badly the season goes.
const MIN_FANS := 75

## Fan losses are dampened the closer the club already is to MIN_FANS, and
## applied in full once the fanbase is healthy (at/above this size).
const FAN_LOSS_NORMAL_AT := 200
const FAN_LOSS_MIN_DAMPEN := 0.15

## Starting fan count for a brand-new career (see team_creation.gd).
const STARTING_FANS := 100

## Flat per-ticket price, scaled by the player's own division.
const TICKET_PRICE_PER_DIVISION := {"E": 30, "D": 50, "C": 70, "B": 100, "A": 150}
const ATTENDANCE_RATE_MIN := 0.50
const ATTENDANCE_RATE_MAX := 0.75

## Per-item merch price scales with the "merchandise_sales" upgrade level.
const MERCH_PRICE_BY_LEVEL := {1: 3, 2: 5, 3: 8}
const MERCH_RATE_MIN := 0.02
const MERCH_RATE_MAX := 0.08

## Per-item food/drink price scales with the "food_sales" upgrade level.
const FOOD_PRICE_BY_LEVEL := {1: 4, 2: 7, 3: 12}
const FOOD_RATE_MIN := 0.03
const FOOD_RATE_MAX := 0.10


## Random fan swing for one player match. `result` is "win" / "draw" / "loss".
## `current_fans` (pass the club's fan count before this match) dampens fan
## losses the closer the club already is to MIN_FANS; pass -1 (default) to
## skip dampening and apply the roll in full.
static func roll_fan_delta(division: String, result: String, current_fans: int = -1) -> int:
	var mult : float = DIVISION_FAN_MULTIPLIER.get(division, 1.0)
	var lo : int
	var hi : int
	match result:
		"win":
			lo = WIN_FANS_MIN
			hi = WIN_FANS_MAX
		"loss":
			lo = LOSS_FANS_MIN
			hi = LOSS_FANS_MAX
		_:
			lo = DRAW_FANS_MIN
			hi = DRAW_FANS_MAX
	var delta := int(round(randi_range(lo, hi) * mult))
	if delta < 0 and current_fans >= 0:
		delta = int(round(delta * _loss_dampen_multiplier(current_fans)))
	return delta


## How much of a fan loss actually lands: barely anything right at MIN_FANS,
## scaling up to a full loss once the club has FAN_LOSS_NORMAL_AT fans or more.
static func _loss_dampen_multiplier(current_fans: int) -> float:
	if current_fans >= FAN_LOSS_NORMAL_AT:
		return 1.0
	if current_fans <= MIN_FANS:
		return FAN_LOSS_MIN_DAMPEN
	var t := float(current_fans - MIN_FANS) / float(FAN_LOSS_NORMAL_AT - MIN_FANS)
	return lerpf(FAN_LOSS_MIN_DAMPEN, 1.0, t)


## Matchday attendance for a home fixture, rolled once at kickoff so the
## tribunes can be filled to match. A random 50-75% of current fans, capped
## by the tribune's stadium capacity. Reuse the same number for
## ticket_revenue_for() rather than rolling attendance twice.
static func roll_attendance(club: ClubResource) -> int:
	var rate := randf_range(ATTENDANCE_RATE_MIN, ATTENDANCE_RATE_MAX)
	var wanted := int(round(club.fans * rate))
	return mini(wanted, club.get_stadium_capacity())


## Gate revenue for a given attendance figure (see roll_attendance()).
static func ticket_revenue_for(club: ClubResource, attendance: int) -> int:
	var price : int = TICKET_PRICE_PER_DIVISION.get(club.division, TICKET_PRICE_PER_DIVISION["E"])
	return attendance * price


## Passive merchandise income, rolled once per calendar day-advance.
## Returns 0 if the club has no "merchandise_sales" upgrade.
static func roll_merchandise_revenue(club: ClubResource) -> int:
	var level : int = club.upgrades.get("merchandise_sales", 0)
	if level <= 0:
		return 0
	var rate := randf_range(MERCH_RATE_MIN, MERCH_RATE_MAX)
	var buyers := int(round(club.fans * rate))
	var price : int = MERCH_PRICE_BY_LEVEL.get(level, MERCH_PRICE_BY_LEVEL[1])
	return buyers * price


## Passive food/drink income, rolled once per calendar day-advance.
## Returns 0 if the club has no "food_sales" upgrade.
static func roll_food_revenue(club: ClubResource) -> int:
	var level : int = club.upgrades.get("food_sales", 0)
	if level <= 0:
		return 0
	var rate := randf_range(FOOD_RATE_MIN, FOOD_RATE_MAX)
	var buyers := int(round(club.fans * rate))
	var price : int = FOOD_PRICE_BY_LEVEL.get(level, FOOD_PRICE_BY_LEVEL[1])
	return buyers * price
