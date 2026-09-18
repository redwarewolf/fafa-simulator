class_name PlayerAging

## Retirement odds by age: a logistic curve that stays flat and near-zero
## through a player's prime, then climbs steeply through their mid-30s.
## Rolled once per player per season-end, right after their age increments —
## see SeasonManager._end_season().

const MIDPOINT_AGE := 34.0    ## age at which retirement chance hits 50%
const STEEPNESS := 2.2        ## smaller = steeper/more dramatic climb
const MAX_CHANCE := 0.95      ## never a guaranteed retirement below the hard cap
const HARD_RETIRE_AGE := 41   ## always retires at/after this age, roll or not

## Higher-quality players play a little longer — indexed by PlayerResource.Quality.
const QUALITY_AGE_BONUS : Array[float] = [0.0, 0.5, 1.0, 1.5, 2.0]

static func retirement_chance(p: PlayerResource) -> float:
	if p.age >= HARD_RETIRE_AGE:
		return 1.0
	var midpoint := MIDPOINT_AGE + QUALITY_AGE_BONUS[p.quality]
	var chance := 1.0 / (1.0 + exp(-(p.age - midpoint) / STEEPNESS))
	return minf(chance, MAX_CHANCE)

static func should_retire(p: PlayerResource) -> bool:
	return randf() < retirement_chance(p)
