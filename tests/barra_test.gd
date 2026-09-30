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

func test_save_round_trip_restores_types() -> void:
	var s := BarraBrava.new_state()
	s["entradas"] = 2
	s["micros"] = true
	var json : Dictionary = JSON.parse_string(JSON.stringify(s))
	var back := BarraBrava.from_save(json)
	assert_eq(back["entradas"], 2)
	assert_true(back["entradas"] is int)
	assert_eq(back["micros"], true)
