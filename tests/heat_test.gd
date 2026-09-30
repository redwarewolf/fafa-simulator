extends TestCase

## ClubHeat: the lines heat crosses, payday, bribes and scandals. Inbox posts
## are rolled back after each test.

func _club(budget: int = 100000) -> ClubResource:
	var club := ClubResource.new("test", "Test", "test", "E")
	club.budget = budget
	club.fans = 1000
	club.tournament_points = 10
	return club

func _quiet(body: Callable) -> void:
	var saved_inbox := GameState.inbox.duplicate()
	body.call()
	GameState.inbox = saved_inbox

func test_lines_trigger_once_each() -> void:
	_quiet(func() -> void:
		var s := ClubHeat.new_state()
		var club := _club()
		ClubHeat.add(s, 45.0, club)
		assert_true(s["investigation"], "investigation at 40")
		assert_true(not s["closed_doors"])
		ClubHeat.add(s, 40.0, club)
		assert_true(s["closed_doors"], "closed doors at 80")
		assert_eq(club.tournament_points, 10, "no deduction yet")
		ClubHeat.add(s, 30.0, club)
		assert_eq(club.tournament_points, 10 - ClubHeat.DEDUCTION_POINTS, "deduction at 100")
		assert_eq(s["heat"], ClubHeat.HEAT_AFTER_DEDUCTION))

func test_payday_cools_fines_and_closes_investigation() -> void:
	_quiet(func() -> void:
		var s := ClubHeat.new_state()
		var club := _club()
		var barra := BarraBrava.new_state()
		ClubHeat.add(s, 65.0, club)
		var fine := ClubHeat.weekly(s, club, barra)
		assert_eq(fine, ClubHeat.WEEKLY_FINE_E, "fined above 60")
		assert_eq(s["heat"], 65.0 - ClubHeat.WEEKLY_COOLING)
		s["heat"] = 41.0
		assert_eq(ClubHeat.weekly(s, club, barra), 0)
		assert_true(not s["investigation"], "closes below 40"))

func test_feeding_the_barra_adds_heat() -> void:
	_quiet(func() -> void:
		var s := ClubHeat.new_state()
		s["heat"] = 20.0
		var barra := BarraBrava.new_state()
		barra["colaboracion"] = 3
		barra["puestos"] = 4
		ClubHeat.weekly(s, _club(), barra)
		assert_near(s["heat"], 20.0 + 3 * ClubHeat.HEAT_PER_COLAB_TIER + 4 * ClubHeat.HEAT_PER_PUESTO - ClubHeat.WEEKLY_COOLING, 0.001))

func test_bribes_are_paid_once_and_spent_after_the_match() -> void:
	_quiet(func() -> void:
		var s := ClubHeat.new_state()
		var club := _club()
		s["bribes"]["referee"] = true
		assert_near(ClubHeat.bribe_edge(s), ClubHeat.BRIBES["referee"]["edge"], 0.001)
		ClubHeat.commit_bribes(s, club)
		ClubHeat.commit_bribes(s, club)
		assert_eq(club.budget, 100000 - ClubHeat.BRIBES["referee"]["cost_e"], "paid once")
		assert_eq(s["heat"], ClubHeat.BRIBES["referee"]["heat"])
		var rng := RandomNumberGenerator.new()
		ClubHeat.after_match(s, club, rng)
		assert_true(not ClubHeat.any_bribe(s) and not s["bribes_paid"], "spent"))

func test_scandals_get_likelier_with_heat() -> void:
	var cold := ClubHeat.new_state()
	var hot := ClubHeat.new_state()
	hot["heat"] = 90.0
	assert_true(ClubHeat.scandal_chance(hot) > ClubHeat.scandal_chance(cold))
	assert_near(ClubHeat.scandal_chance(cold), ClubHeat.SCANDAL_BASE, 0.001)

func test_save_round_trip() -> void:
	var s := ClubHeat.new_state()
	s["heat"] = 33.0
	s["closed_doors"] = true
	s["bribes"]["keeper"] = true
	var back := ClubHeat.from_save(JSON.parse_string(JSON.stringify(s)))
	assert_eq(back["heat"], 33.0)
	assert_true(back["closed_doors"] and back["bribes"]["keeper"] and not back["bribes"]["referee"])
