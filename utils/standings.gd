class_name Standings

## League-table helpers. The sort rule (points, then goal difference, then goals
## scored) lives here so the tournament table and the calendar's match preview
## can't drift apart.

static func sort_clubs(clubs: Array) -> Array:
	var sorted := clubs.duplicate()
	sorted.sort_custom(func(a: ClubResource, b: ClubResource) -> bool:
		if a.tournament_points != b.tournament_points:
			return a.tournament_points > b.tournament_points
		var gd_a := a.goals_for - a.goals_against
		var gd_b := b.goals_for - b.goals_against
		if gd_a != gd_b:
			return gd_a > gd_b
		return a.goals_for > b.goals_for)
	return sorted

## Ranked clubs of a single division.
static func for_division(division: String) -> Array:
	var clubs : Array = DataLoader.clubs.values().filter(
		func(c: ClubResource) -> bool: return c.division == division)
	return sort_clubs(clubs)

## 1-based table position of `club` within its own division, or 0 if unknown.
static func position_of(club: ClubResource) -> int:
	if club == null:
		return 0
	var table := for_division(club.division)
	for i in table.size():
		if table[i].id == club.id:
			return i + 1
	return 0

static func record_string(club: ClubResource) -> String:
	if club == null:
		return "-"
	return "%d-%d-%d" % [club.wins, club.draws, club.losses]
