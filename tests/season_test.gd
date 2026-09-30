extends TestCase

## SeasonManager save/load behaviour. Touches the GameState/SeasonManager
## autoloads, so every test restores what it changed.

func _fixture(home: String, away: String, d, m, y, played: bool) -> Dictionary:
	return {"type": "league", "division": "E", "matchday": 0, "home_id": home, "away_id": away,
		"day": d, "month": m, "year": y, "played": played, "home_score": 0, "away_score": 0}

func _with_career(body: Callable) -> void:
	var saved_club = GameState.player_club
	var saved_date := [GameState.day, GameState.month, GameState.year]
	var saved_fixtures := SeasonManager.fixtures
	var saved_pending := SeasonManager.pending_player_fixture
	var club := ClubResource.new()
	club.id = "me"
	GameState.player_club = club
	GameState.day = 9
	GameState.month = 4
	GameState.year = 2026
	body.call()
	GameState.player_club = saved_club
	GameState.day = saved_date[0]
	GameState.month = saved_date[1]
	GameState.year = saved_date[2]
	SeasonManager.fixtures = saved_fixtures
	SeasonManager.pending_player_fixture = saved_pending

## A career saved on a match day must still owe that match after loading —
## it used to be dropped, and resolve_day() never picks up a past fixture.
func test_load_restores_todays_pending_match() -> void:
	_with_career(func() -> void:
		# JSON hands numbers back as floats, exactly like a real save.
		var today := _fixture("me", "rival", 9.0, 4.0, 2026.0, false)
		var data : Array[Dictionary] = [
			_fixture("a", "b", 9.0, 4.0, 2026.0, false),
			today,
			_fixture("me", "other", 16.0, 4.0, 2026.0, false),
		]
		SeasonManager.load_fixtures(data)
		assert_eq(SeasonManager.pending_player_fixture, today, "pending"))

func test_load_ignores_played_or_other_days() -> void:
	_with_career(func() -> void:
		var data : Array[Dictionary] = [
			_fixture("me", "rival", 9.0, 4.0, 2026.0, true),
			_fixture("me", "other", 16.0, 4.0, 2026.0, false),
		]
		SeasonManager.load_fixtures(data)
		assert_true(SeasonManager.pending_player_fixture.is_empty(), "no pending match expected"))

## Table movement: positions before the latest round are rebuilt by taking
## that round's results back off each club's running totals.
func test_previous_positions_undo_latest_round() -> void:
	var saved_fixtures := SeasonManager.fixtures
	var a := ClubResource.new()
	a.id = "zz_a"
	a.division = "Z"
	var b := ClubResource.new()
	b.id = "zz_b"
	b.division = "Z"
	# Round 1: A beat B 1-0. Round 2: B beat A 3-0 — B now leads on goal difference.
	a.tournament_points = 3
	a.goals_for = 1
	a.goals_against = 3
	b.tournament_points = 3
	b.goals_for = 3
	b.goals_against = 1
	DataLoader.clubs[a.id] = a
	DataLoader.clubs[b.id] = b
	var r1 := _fixture("zz_a", "zz_b", 1, 4, 2026, true)
	r1["division"] = "Z"
	r1["home_score"] = 1
	var r2 := _fixture("zz_b", "zz_a", 8, 4, 2026, true)
	r2["division"] = "Z"
	r2["matchday"] = 1
	r2["home_score"] = 3
	SeasonManager.fixtures = [r1, r2]
	var prev := Standings.previous_positions("Z")
	assert_eq(prev.get("zz_a", -1), 1, "A was first before round 2")
	assert_eq(prev.get("zz_b", -1), 2, "B was second before round 2")
	assert_eq(Standings.form(a), ["W", "L"], "A form")
	DataLoader.clubs.erase(a.id)
	DataLoader.clubs.erase(b.id)
	SeasonManager.fixtures = saved_fixtures
