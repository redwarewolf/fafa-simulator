extends Node

## Generates a double round-robin fixture list per division and resolves
## matchdays as the calendar advances. Matches not involving the player's
## club are simulated instantly; the player's own matchday is left pending
## for the Hub to route into a real match (see hub.gd / world.gd).
##
## The yearly cycle has four phases:
##   pre-season (fixed-length, friendlies + transfer window)
##   -> first half (one round-robin leg, transfers locked)
##   -> mid-season break (fixed-length, transfer window reopens)
##   -> second half (the reverse leg, transfers locked)
##   -> season end (promotion check, stats reset) -> back to pre-season.
## See start_pre_season() / _start_first_half() / _start_mid_season_break()
## / _start_second_half() / _end_season().

enum Phase { PRE_SEASON, FIRST_HALF, MID_SEASON_BREAK, SECOND_HALF }

const DAYS_BETWEEN_MATCHDAYS := 7
## Pre-season and the mid-season break are fixed-length windows, counted in
## "Next Date" presses (i.e. calendar days), regardless of how many fixtures
## land inside them. The first and second halves instead run until every
## fixture in that leg is played — their real length follows from the
## division's club count via the round-robin schedule (_round_robin_rounds()).
const PRE_SEASON_LENGTH := 6
const MID_SEASON_BREAK_LENGTH := 3
const PRE_SEASON_FRIENDLY_COUNT := 3
const FRIENDLY_DAYS_BETWEEN := 2

## Emitted once the second half's final matchday is resolved, after
## standings/division have already been updated and a new pre-season has started.
signal season_ended(promoted: bool, new_division: String, position: int)

var phase : int = Phase.PRE_SEASON

## Counts down "Next Date" presses during PRE_SEASON / MID_SEASON_BREAK.
## Unused (and meaningless) during FIRST_HALF / SECOND_HALF, which instead
## end when their fixtures are all played — see _leg_fully_played().
var phase_dates_remaining : int = 0

## Flat list of fixture dictionaries:
## {type, division, matchday, home_id, away_id, day, month, year, played, home_score, away_score}
## type is "league" or "friendly" — friendlies don't affect standings. League
## fixtures also carry "leg" (1 or 2) to tell the halves apart. Accumulates
## for the whole year (pre-season through second half) so the calendar keeps
## a full history; only start_pre_season() clears it, for the next year.
var fixtures : Array[Dictionary] = []

## Set when it's the player's turn to play a scheduled match; cleared once
## world.gd reports the result via report_player_match_result().
var pending_player_fixture : Dictionary = {}


## Starts a new pre-season: clears the schedule and generates a handful of
## friendly fixtures for the player's club. Called at new-career creation and
## again every time a season ends (see _end_season()).
func start_pre_season() -> void:
	phase = Phase.PRE_SEASON
	phase_dates_remaining = PRE_SEASON_LENGTH
	fixtures.clear()
	pending_player_fixture = {}
	_generate_pre_season_friendlies()
	if GameState.player_club != null:
		GameState.refresh_youth_pool()


## Restores a previously-generated schedule from a save file, instead of
## rebuilding one. Clears any stale pending match.
func load_fixtures(data: Array[Dictionary]) -> void:
	fixtures = data
	pending_player_fixture = {}


static func phase_name(p: int) -> String:
	match p:
		Phase.PRE_SEASON: return "pre_season"
		Phase.FIRST_HALF: return "first_half"
		Phase.MID_SEASON_BREAK: return "mid_season_break"
		Phase.SECOND_HALF: return "second_half"
	return "first_half"


## Legacy saves predate this phase system entirely; "first_half" is the
## safest default since it already has a live league schedule in `fixtures`
## and won't spuriously reopen the transfer window or regenerate friendlies.
static func phase_from_name(s: String) -> int:
	match s:
		"pre_season": return Phase.PRE_SEASON
		"first_half": return Phase.FIRST_HALF
		"mid_season_break": return Phase.MID_SEASON_BREAK
		"second_half": return Phase.SECOND_HALF
	return Phase.FIRST_HALF


func _generate_pre_season_friendlies() -> void:
	var player_club := GameState.player_club
	if player_club == null:
		return
	var division := player_club.division
	var opponents : Array = DataLoader.clubs.values().filter(
		func(c: ClubResource) -> bool: return c.division == division and c.id != player_club.id)
	opponents.shuffle()

	var count := mini(PRE_SEASON_FRIENDLY_COUNT, opponents.size())
	for i in count:
		var opponent : ClubResource = opponents[i]
		var date := GameState.advance_date(GameState.day, GameState.month, GameState.year,
			FRIENDLY_DAYS_BETWEEN * (i + 1))
		var is_home := i % 2 == 0
		fixtures.append({
			"type": "friendly",
			"division": division,
			"matchday": -1,
			"home_id": player_club.id if is_home else opponent.id,
			"away_id": opponent.id if is_home else player_club.id,
			"day": date[0],
			"month": date[1],
			"year": date[2],
			"played": false,
			"home_score": 0,
			"away_score": 0,
		})


## The round-robin pairing for the player's current division, recomputed
## fresh from DataLoader each time rather than cached — the club list for a
## division doesn't change mid-year, so leg 1 and leg 2 always derive the
## identical pairing, and nothing needs to survive a save/load in between.
func _current_division_rounds() -> Array:
	var player_club := GameState.player_club
	if player_club == null:
		return []
	var clubs := DataLoader.get_clubs_in_division(player_club.division)
	if clubs.size() < 2:
		return []
	return _round_robin_rounds(clubs)


func _generate_first_half_fixtures() -> void:
	var rounds := _current_division_rounds()
	if rounds.is_empty():
		return
	_append_leg_fixtures(GameState.player_club.division, rounds, 1, 0)


func _generate_second_half_fixtures() -> void:
	var rounds := _current_division_rounds()
	if rounds.is_empty():
		return
	_append_leg_fixtures(GameState.player_club.division, rounds, 2, rounds.size())


## Appends one leg's fixtures (matchday numbers starting at matchday_offset)
## dated starting tomorrow, DAYS_BETWEEN_MATCHDAYS apart. leg 2 reverses
## home/away from the pairing leg 1 would produce from the same rounds.
func _append_leg_fixtures(division: String, rounds: Array, leg: int, matchday_offset: int) -> void:
	var matchday := matchday_offset
	for round_pairs in rounds:
		# Start tomorrow: resolve_day() only ever checks dates *after*
		# GameState.advance_day() has moved forward, so a fixture dated
		# "today" would be permanently skipped.
		var date := GameState.advance_date(GameState.day, GameState.month, GameState.year,
			1 + (matchday - matchday_offset) * DAYS_BETWEEN_MATCHDAYS)
		for pair in round_pairs:
			var home : ClubResource = pair[0] if leg == 1 else pair[1]
			var away : ClubResource = pair[1] if leg == 1 else pair[0]
			fixtures.append({
				"type": "league",
				"leg": leg,
				"division": division,
				"matchday": matchday,
				"home_id": home.id,
				"away_id": away.id,
				"day": date[0],
				"month": date[1],
				"year": date[2],
				"played": false,
				"home_score": 0,
				"away_score": 0,
			})
		matchday += 1


## Circle-method round robin. Returns an Array of rounds; each round is an
## Array of [club_a, club_b] pairs. Adds a bye (null) if the count is odd.
func _round_robin_rounds(clubs: Array) -> Array:
	var teams := clubs.duplicate()
	if teams.size() % 2 == 1:
		teams.append(null)
	var n := teams.size()
	var rounds : Array = []
	for r in range(n - 1):
		var round_pairs : Array = []
		for i in range(n / 2):
			var home = teams[i]
			var away = teams[n - 1 - i]
			if home != null and away != null:
				round_pairs.append([home, away])
		rounds.append(round_pairs)
		teams.insert(1, teams.pop_back())
	return rounds


## Resolves any fixtures scheduled for today. Non-player matches are
## simulated instantly; a player fixture (if any) is left pending. Once the
## current phase is done, transitions to the next one — see _check_phase_transition().
func resolve_day() -> void:
	if not pending_player_fixture.is_empty():
		return  # player still owes a match — don't advance further

	if phase == Phase.PRE_SEASON or phase == Phase.MID_SEASON_BREAK:
		phase_dates_remaining -= 1

	var player_id := GameState.player_club.id if GameState.player_club != null else ""
	for f in fixtures:
		if f["played"]:
			continue
		if f["day"] != GameState.day or f["month"] != GameState.month or f["year"] != GameState.year:
			continue
		if f["home_id"] == player_id or f["away_id"] == player_id:
			pending_player_fixture = f
		else:
			_simulate_fixture(f)

	if pending_player_fixture.is_empty():
		_check_phase_transition()


## Every league fixture tagged with the given leg has been played.
func _leg_fully_played(leg: int) -> bool:
	var relevant := fixtures.filter(
		func(f: Dictionary) -> bool: return f["type"] == "league" and f.get("leg", 0) == leg)
	return not relevant.is_empty() and relevant.all(func(f: Dictionary) -> bool: return f["played"])


func _check_phase_transition() -> void:
	match phase:
		Phase.PRE_SEASON:
			if phase_dates_remaining <= 0:
				_start_first_half()
		Phase.MID_SEASON_BREAK:
			if phase_dates_remaining <= 0:
				_start_second_half()
		Phase.FIRST_HALF:
			if _leg_fully_played(1):
				_start_mid_season_break()
		Phase.SECOND_HALF:
			if _leg_fully_played(2):
				_end_season()


func _start_first_half() -> void:
	phase = Phase.FIRST_HALF
	_generate_first_half_fixtures()


func _start_mid_season_break() -> void:
	phase = Phase.MID_SEASON_BREAK
	phase_dates_remaining = MID_SEASON_BREAK_LENGTH


func _start_second_half() -> void:
	phase = Phase.SECOND_HALF
	_generate_second_half_fixtures()


## Checks the player's final standing, promotes their club a division if they
## finished first, resets every club's season stats, and starts the next
## pre-season. Only the player's own club can be promoted — since just one
## division is populated at runtime, moving up spins a fresh set of AI
## opponents for the new division (same as career start).
func _end_season() -> void:
	var player_club := GameState.player_club
	var position := Standings.position_of(player_club)
	var old_division := player_club.division
	var new_division := old_division
	var promoted := false

	if position == 1:
		var idx := ClubFactory.DIVISION_ORDER.find(old_division)
		if idx >= 0 and idx < ClubFactory.DIVISION_ORDER.size() - 1:
			new_division = ClubFactory.DIVISION_ORDER[idx + 1]
			promoted = true

	if promoted:
		var taken_ids : Array = []
		for c : ClubResource in DataLoader.clubs.values():
			taken_ids.append(c.id)
		var ai_clubs := ClubFactory.generate_ai_clubs(new_division, 7, [player_club.display_name], taken_ids)
		player_club.division = new_division
		var new_roster : Array[ClubResource] = [player_club]
		new_roster.append_array(ai_clubs)
		var empty_roster : Array[ClubResource] = []
		GameState.replace_division(old_division, empty_roster)  # abandon the old division
		GameState.replace_division(new_division, new_roster)

	for c : ClubResource in DataLoader.get_clubs_in_division(player_club.division):
		c.tournament_points = 0
		c.matches_played = 0
		c.wins = 0
		c.draws = 0
		c.losses = 0
		c.goals_for = 0
		c.goals_against = 0

	_age_and_retire_players()

	season_ended.emit(promoted, new_division, position)
	start_pre_season()


## Ages every player a year and rolls retirement. The player's own retirees
## are left for the manager to replace (via the transfer market or their
## academy) — clearing them from any tactic slot they held. AI clubs have no
## such recourse, so they're silently backfilled with a fresh same-role
## player so their squads never dwindle. The player's youth academy prospects
## (if any) age too and graduate into the senior squad at YouthAcademy.GRADUATION_AGE.
func _age_and_retire_players() -> void:
	var player_club := GameState.player_club
	for club : ClubResource in DataLoader.clubs.values():
		var retirees : Array[PlayerResource] = []
		for p : PlayerResource in club.players:
			p.age += 1
			if PlayerAging.should_retire(p):
				retirees.append(p)
		for p in retirees:
			club.players.erase(p)
			if club == player_club:
				GameState.clear_player_from_tactics(p)
			else:
				club.players.append(PlayerFactory.generate_player(ClubFactory.ai_odds_for(club.division), p.role))

	if player_club == null:
		return
	var graduates : Array[PlayerResource] = []
	for y : PlayerResource in player_club.youth_players:
		y.age += 1
		# A full year spent in the pool, whether or not they graduate this same
		# tick — see PlayerResource.add_permanent_modifier().
		y.add_permanent_modifier("youth_academy", "Academia Juvenil", "all", 3.0)
		if y.age >= YouthAcademy.GRADUATION_AGE:
			graduates.append(y)
	for y in graduates:
		player_club.youth_players.erase(y)
		player_club.players.append(y)


func _simulate_fixture(f: Dictionary) -> void:
	var home := DataLoader.get_club(f["home_id"])
	var away := DataLoader.get_club(f["away_id"])
	if home == null or away == null:
		return
	var home_score := _simulate_goals(home, away, true)
	var away_score := _simulate_goals(away, home, false)
	f["played"] = true
	f["home_score"] = home_score
	f["away_score"] = away_score
	if f["type"] == "league":
		_apply_result(home, away, home_score, away_score)


## Expected goals driven by squad-quality difference, with a small home
## advantage, sampled from a Poisson distribution for a natural score spread.
func _simulate_goals(club: ClubResource, opponent: ClubResource, is_home: bool) -> int:
	var diff := club.get_squad_overall() - opponent.get_squad_overall()
	var expected := 1.3 + diff / 25.0 + (0.2 if is_home else 0.0)
	expected = clampf(expected, 0.2, 4.0)
	return _poisson_sample(expected)


func _poisson_sample(lambda: float) -> int:
	var l := exp(-lambda)
	var k := 0
	var p := 1.0
	while true:
		k += 1
		p *= randf()
		if p <= l:
			break
	return k - 1


func _apply_result(home: ClubResource, away: ClubResource, home_score: int, away_score: int) -> void:
	home.matches_played += 1
	away.matches_played += 1
	home.goals_for += home_score
	home.goals_against += away_score
	away.goals_for += away_score
	away.goals_against += home_score

	if home_score > away_score:
		home.wins += 1
		home.tournament_points += 3
		away.losses += 1
	elif away_score > home_score:
		away.wins += 1
		away.tournament_points += 3
		home.losses += 1
	else:
		home.draws += 1
		away.draws += 1
		home.tournament_points += 1
		away.tournament_points += 1

	GameState.budget_changed.emit()


## Called by world.gd when the player's scheduled match ends. Returns the
## fan/revenue deltas for that match ({fans_delta, ticket_revenue, attendance})
## so world.gd can show them on the game-over summary screen — empty
## Dictionary if there was no pending player fixture (e.g. a dev test match).
func report_player_match_result(home_score: int, away_score: int) -> Dictionary:
	if pending_player_fixture.is_empty():
		return {}
	# A suspension (PlayerResource.unavailable_matches, set by random events)
	# counts down once per played match, regardless of league/friendly type.
	if GameState.player_club != null:
		for p : PlayerResource in GameState.player_club.players:
			if p.unavailable_matches > 0:
				p.unavailable_matches -= 1
			p.tick_temporary_modifiers()
	var f := pending_player_fixture
	var home := DataLoader.get_club(f["home_id"])
	var away := DataLoader.get_club(f["away_id"])
	f["played"] = true
	f["home_score"] = home_score
	f["away_score"] = away_score
	if home != null and away != null and f["type"] == "league":
		_apply_result(home, away, home_score, away_score)

	var result := {"fans_delta": 0, "ticket_revenue": 0, "attendance": 0}
	var player_club := GameState.player_club
	if player_club != null and home != null and away != null:
		var is_home := player_club.id == home.id
		var own_score : int = home_score if is_home else away_score
		var opp_score : int = away_score if is_home else home_score
		var outcome := "draw"
		if own_score > opp_score:
			outcome = "win"
		elif own_score < opp_score:
			outcome = "loss"

		var fans_delta := FanEconomy.roll_fan_delta(player_club.division, outcome, player_club.fans)
		player_club.fans = maxi(FanEconomy.MIN_FANS, player_club.fans + fans_delta)
		result["fans_delta"] = fans_delta

		# Gate revenue only at the player's own stadium — league or friendly,
		# fans still show up and pay for a friendly at home. Reuse the
		# attendance world.gd rolled at kickoff (to fill the tribunes) rather
		# than rolling a second, inconsistent number here.
		if is_home:
			var attendance : int = f.get("attendance", -1)
			if attendance < 0:
				attendance = FanEconomy.roll_attendance(player_club)  # fallback; shouldn't normally trigger
			var revenue := FanEconomy.ticket_revenue_for(player_club, attendance)
			player_club.budget += revenue
			result["ticket_revenue"] = revenue
			result["attendance"] = attendance

		GameState.budget_changed.emit()

	pending_player_fixture = {}
	_check_phase_transition()
	return result


## Fixtures involving the given club id, sorted chronologically.
func get_fixtures_for_club(id: String) -> Array:
	var result := fixtures.filter(
		func(f: Dictionary) -> bool: return f["home_id"] == id or f["away_id"] == id
	)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["year"] != b["year"]:
			return a["year"] < b["year"]
		if a["month"] != b["month"]:
			return a["month"] < b["month"]
		return a["day"] < b["day"]
	)
	return result
