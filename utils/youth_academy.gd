class_name YouthAcademy

## Generates youth-academy prospects: unproven kids well below the normal
## PlayerFactory age band, who graduate into the senior squad once they hit
## GRADUATION_AGE (or are promoted early by hand) — see
## GameState.refresh_youth_pool() and SeasonManager._end_season().

const MIN_AGE := 14
const MAX_AGE := 17
const GRADUATION_AGE := 18

static func generate_youth_player() -> PlayerResource:
	var p := PlayerFactory.generate_player(PlayerFactory.QUALITY_ODDS[0])  # rawest tier — unproven kids
	p.age = randi_range(MIN_AGE, MAX_AGE)
	return p
