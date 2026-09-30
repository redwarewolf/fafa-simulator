extends TestCase

## BarraBrava's weekly rules, results and demands, on throwaway state/clubs.

func _club(division: String = "E", fans: int = 100) -> ClubResource:
	var club := ClubResource.new("test", "Test", "test", division)
	club.budget = 10000
	club.fans = fans
	return club

func test_giving_nothing_sours_them() -> void:
	var s := BarraBrava.new_state()
	var club := _club()
	var charged := BarraBrava.weekly(s, club)
	assert_eq(charged, 0)
	assert_eq(s["relacion"], 50.0 + BarraBrava.WEEKLY_GRUDGE)

func test_paying_costs_scale_with_division_and_win_them_over() -> void:
	var s := BarraBrava.new_state()
	s["colaboracion"] = 2
	s["micros"] = true
	var e := BarraBrava.weekly_cost(s, "E")
	assert_eq(e, BarraBrava.COLAB_COST_E[2] + BarraBrava.MICROS_COST_E)
	assert_eq(BarraBrava.weekly_cost(s, "A"), roundi(BarraBrava.COLAB_COST_E[2] * 4.5) + roundi(BarraBrava.MICROS_COST_E * 4.5))
	assert_true(BarraBrava.weekly_relacion(s) > 0.0)
	var club := _club()
	BarraBrava.weekly(s, club)
	assert_eq(club.budget, 10000 - e)

func test_power_grows_toward_what_you_feed_them() -> void:
	var s := BarraBrava.new_state()
	s["colaboracion"] = 3
	var club := _club("E", 2000)
	var before : float = s["poder"]
	for i in 20:
		BarraBrava.weekly(s, club)
	assert_true(s["poder"] > before + 20.0)
	assert_true(s["poder"] <= BarraBrava.power_target(s, club.fans) + 0.001)

func test_losing_run_gets_hot() -> void:
	var s := BarraBrava.new_state()
	for i in BarraBrava.LOSS_STREAK_HOT:
		BarraBrava.on_match_result(s, "loss")
	var expected := 50.0 + BarraBrava.RESULT_RELACION["loss"] * BarraBrava.LOSS_STREAK_HOT + BarraBrava.LOSS_STREAK_EXTRA
	assert_near(s["relacion"], expected, 0.001)
	BarraBrava.on_match_result(s, "win")
	assert_eq(s["loss_streak"], 0)

func test_first_payday_brings_barroni_then_cooldown_after_demand() -> void:
	var s := BarraBrava.new_state()
	BarraBrava.weekly(s, _club())
	assert_true(s["visit_pending"], "introduction")
	s["met"] = true
	s["visit_pending"] = false
	BarraBrava.resolve_demand(s, _club(), BarraBrava.DEMANDS[0], false)
	for i in BarraBrava.DEMAND_COOLDOWN_WEEKS:
		BarraBrava.weekly(s, _club())
		assert_true(not s["visit_pending"], "quiet week %d" % i)

func test_puesto_demand_adds_a_weekly_cost() -> void:
	var s := BarraBrava.new_state()
	var club := _club()
	var puesto : Dictionary = BarraBrava.DEMANDS.filter(func(d): return d["id"] == "puesto")[0]
	BarraBrava.resolve_demand(s, club, puesto, true)
	assert_eq(s["puestos"], 1)
	assert_eq(club.budget, 10000, "no one-off charge")
	assert_eq(BarraBrava.weekly_cost(s, "E"), BarraBrava.PUESTO_COST_E)

func _state(relacion: float, poder: float, micros: bool = false) -> Dictionary:
	var s := BarraBrava.new_state()
	s["relacion"] = relacion
	s["poder"] = poder
	s["micros"] = micros
	return s

func test_aguante_signs_and_power() -> void:
	assert_near(BarraBrava.aguante(_state(50, 80)), 0.0, 0.001, "neutral")
	assert_true(BarraBrava.aguante(_state(100, 100)) > BarraBrava.aguante(_state(100, 10)), "power")
	assert_near(BarraBrava.aguante(_state(100, 100)), 1.0, 0.001)
	assert_near(BarraBrava.aguante(_state(0, 100)), -1.0, 0.001)

func test_away_needs_micros() -> void:
	var fx := BarraBrava.match_effect(_state(100, 100), false)
	assert_near(fx["own_pct"], 0.0, 0.001, "no micros")
	fx = BarraBrava.match_effect(_state(100, 100, true), false)
	assert_near(fx["own_pct"], BarraBrava.CROWD_STAT_PCT * BarraBrava.AWAY_PRESENCE, 0.001, "micros")

func test_happy_barra_helps_and_angry_one_whistles_its_own() -> void:
	var happy := BarraBrava.match_effect(_state(100, 100), true)
	assert_true(happy["own_pct"] > 0.0 and happy["rival_pct"] < 0.0 and happy["own_foul_scale"] < 1.0)
	assert_eq(happy["mood"], 2)
	var angry := BarraBrava.match_effect(_state(0, 100), true)
	assert_true(angry["own_pct"] < 0.0)
	assert_near(angry["rival_pct"], 0.0, 0.001, "an angry barra doesn't scare the rival")
	assert_near(angry["own_foul_scale"], 1.0, 0.001)
	assert_eq(angry["mood"], 1)

func test_incidents_follow_the_mood() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var angry_ids := BarraBrava.ANGRY_INCIDENTS.map(func(i): return i["id"])
	var angry := 0
	var happy := 0
	for i in 200:
		var inc := BarraBrava.roll_incident(_state(0, 100), true, rng)
		if not inc.is_empty():
			assert_true(inc["id"] in angry_ids)
			angry += 1
		inc = BarraBrava.roll_incident(_state(100, 100), true, rng)
		if not inc.is_empty():
			assert_eq(inc["id"], "recibimiento")
			happy += 1
		assert_true(BarraBrava.roll_incident(_state(50, 100), true, rng).is_empty(), "neutral: nothing")
	assert_between(angry / 200.0, 0.7, 0.9, "angry rate ~cap")
	assert_between(happy / 200.0, 0.7, 0.9, "happy rate ~cap")

func test_fine_and_fans_scale_with_division() -> void:
	var club := _club("A", 5000)
	var rng := RandomNumberGenerator.new()
	var invasion : Dictionary = BarraBrava.ANGRY_INCIDENTS.filter(func(i): return i["id"] == "invasion")[0]
	var saved_inbox := GameState.inbox.duplicate()
	var text := BarraBrava.apply_incident(invasion, club, [], rng)
	GameState.inbox = saved_inbox
	assert_true(club.budget <= 10000 - roundi(1500 * 4.5), "fine scaled")
	assert_true(club.fans < 5000)
	assert_true(not "{" in text, "placeholders filled")

func test_save_round_trip_restores_types() -> void:
	var s := BarraBrava.new_state()
	s["entradas"] = 2
	s["micros"] = true
	var json : Dictionary = JSON.parse_string(JSON.stringify(s))
	var back := BarraBrava.from_save(json)
	assert_eq(back["entradas"], 2)
	assert_true(back["entradas"] is int)
	assert_eq(back["micros"], true)
