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

## Last [param count] league results of [param club], oldest first, as
## "W"/"D"/"L" — read off SeasonManager.fixtures (friendlies excluded).
static func form(club: ClubResource, count: int = 5) -> Array:
	var played := SeasonManager.fixtures.filter(func(f: Dictionary) -> bool:
		return f["type"] == "league" and f["played"] \
			and (f["home_id"] == club.id or f["away_id"] == club.id))
	played.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [a["year"], a["month"], a["day"]] < [b["year"], b["month"], b["day"]])
	var out : Array = []
	for f in played.slice(maxi(0, played.size() - count)):
		var own : int = f["home_score"] if f["home_id"] == club.id else f["away_score"]
		var opp : int = f["away_score"] if f["home_id"] == club.id else f["home_score"]
		out.append("W" if own > opp else ("L" if own < opp else "D"))
	return out

## Club id → 1-based table position before the most recent played league
## round of [param division], so the table can show ▲▼ movement. Rebuilt by
## taking that round's results back off each club's totals — club stats are
## stored as running totals, not recomputed from fixtures. Empty until at
## least two rounds are played (nothing to compare against before that).
static func previous_positions(division: String) -> Dictionary:
	var league := SeasonManager.fixtures.filter(func(f: Dictionary) -> bool:
		return f["type"] == "league" and f["division"] == division and f["played"])
	if league.is_empty():
		return {}
	var last_key := func(f: Dictionary) -> Array: return [f.get("leg", 1), f["matchday"]]
	var latest : Array = last_key.call(league[0])
	for f in league:
		if last_key.call(f) > latest:
			latest = last_key.call(f)
	var earlier := league.filter(func(f: Dictionary) -> bool: return last_key.call(f) != latest)
	if earlier.is_empty():
		return {}

	var rows : Array = []
	for club : ClubResource in DataLoader.get_clubs_in_division(division):
		var row := {"id": club.id, "pts": club.tournament_points,
			"gd": club.goals_for - club.goals_against, "gf": club.goals_for}
		for f in league:
			if last_key.call(f) != latest:
				continue
			var is_home : bool = f["home_id"] == club.id
			if not is_home and f["away_id"] != club.id:
				continue
			var own : int = f["home_score"] if is_home else f["away_score"]
			var opp : int = f["away_score"] if is_home else f["home_score"]
			row["gf"] -= own
			row["gd"] -= own - opp
			row["pts"] -= 3 if own > opp else (1 if own == opp else 0)
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["pts"] != b["pts"]:
			return a["pts"] > b["pts"]
		if a["gd"] != b["gd"]:
			return a["gd"] > b["gd"]
		return a["gf"] > b["gf"])
	var out := {}
	for i in rows.size():
		out[rows[i]["id"]] = i + 1
	return out
