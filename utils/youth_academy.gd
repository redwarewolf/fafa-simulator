class_name YouthAcademy

## Generates youth-academy prospects: unproven kids well below the normal
## PlayerFactory age band, who graduate into the senior squad once they hit
## GRADUATION_AGE (or are promoted early by hand) — see
## utils/youth_events.gd (narrated sign-up events, the only way prospects are
## added via the academy) and GameState.refresh_scout_pool() (the talent
## scout's own chance to turn up a kid instead of an adult player), plus
## SeasonManager._end_season() (aging/graduation).

const MIN_AGE := 14
const MAX_AGE := 17
const GRADUATION_AGE := 18

## quality_odds: weights per PlayerResource.Quality tier, same convention as
## PlayerFactory.generate_player() — pass a scout-level table for a scouted
## kid find, or use generate_youth_player_with_quality() for a sign-up
## event's tier-relative single quality instead of a weighted roll.
static func generate_youth_player(quality_odds: Array = PlayerFactory.QUALITY_ODDS[0]) -> PlayerResource:
	# Always the player's own academy, so kept to normal skin tones like the
	# rest of the player's roster.
	var p := PlayerFactory.generate_player(quality_odds, -1, true)
	p.age = randi_range(MIN_AGE, MAX_AGE)
	p.is_youth_prospect = true
	return p

## Forces an exact [param quality] rather than rolling weighted odds — used
## by utils/youth_events.gd, whose sign-up categories describe a kid's
## quality as a tier-relative RANGE (e.g. "our tier or worse"), not a rarity
## curve. The caller picks one quality out of that range and this just builds
## the kid at it.
static func generate_youth_player_with_quality(quality: PlayerResource.Quality) -> PlayerResource:
	var odds : Array = [0, 0, 0, 0, 0]
	odds[quality] = 1
	return generate_youth_player(odds)
