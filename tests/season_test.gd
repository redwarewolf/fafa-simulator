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
