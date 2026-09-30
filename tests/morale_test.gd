extends TestCase

## PlayerMorale: bands, match percent, drift, and the per-match rules. Works
## on throwaway players/clubs — nothing touches GameState.

func _player(name: String, ovr: int = 50, special: String = "") -> PlayerResource:
	return PlayerResource.new(name, 0 as Player.SkinColor, 0 as Player.HairColor, Positions.Role.CM, 25,
		PlayerResource.Quality.COMMON, ovr, ovr, ovr, ovr, ovr, ovr, "default", special)

func _club(players: Array) -> ClubResource:
	var club := ClubResource.new("test", "Test", "test", "E")
	for p : PlayerResource in players:
		club.players.append(p)
	return club

func test_new_player_starts_at_baseline() -> void:
	var p := _player("A")
	assert_eq(p.morale, PlayerMorale.BASELINE)
	assert_eq(PlayerMorale.band(p), PlayerMorale.Band.NORMAL)
	assert_near(PlayerMorale.stat_pct(p), 0.0, 0.001)

func test_stat_pct_endpoints() -> void:
	var p := _player("A")
	p.morale = 100.0
	assert_near(PlayerMorale.stat_pct(p), PlayerMorale.STAT_PCT_MAX, 0.001, "at 100")
	p.morale = 0.0
	assert_near(PlayerMorale.stat_pct(p), PlayerMorale.STAT_PCT_MIN, 0.001, "at 0")
	assert_eq(PlayerMorale.band(p), PlayerMorale.Band.FURIOSO)

func test_adjust_clamps_and_logs_newest_first() -> void:
	var p := _player("A")
	for i in 5:
		PlayerMorale.adjust(p, 20.0, "r%d" % i)
	assert_eq(p.morale, 100.0)
	assert_eq(p.morale_log.size(), PlayerMorale.LOG_SIZE)
	assert_eq(p.morale_log[0]["text"], "r4")

func test_cone_has_no_morale() -> void:
	var cone := _player("Cono", 1, "cone")
	PlayerMorale.adjust(cone, -50.0, "x")
	assert_eq(cone.morale, PlayerMorale.BASELINE)
	assert_near(PlayerMorale.stat_pct(cone), 0.0, 0.001)

func test_drift_stops_at_baseline() -> void:
	var p := _player("A")
	p.morale = PlayerMorale.BASELINE + 1.0
	PlayerMorale.drift(p)
	assert_eq(p.morale, PlayerMorale.BASELINE)
	p.morale = 10.0
	PlayerMorale.drift(p)
	assert_eq(p.morale, 10.0 + PlayerMorale.DAILY_DRIFT)

func test_win_lifts_players_who_played_and_scorer_more() -> void:
	var a := _player("A")
	var b := _player("B")
	var club := _club([a, b])
	PlayerMorale.apply_match(club, [a, b], {"A": 1}, "win", "Rival")
	var base := PlayerMorale.BASELINE + PlayerMorale.WIN + PlayerMorale.STARTED
	assert_eq(b.morale, base)
	assert_eq(a.morale, base + PlayerMorale.PER_GOAL)

func test_bench_grace_then_star_penalty_doubled() -> void:
	var star := _player("Star", 80)
	var scrub := _player("Scrub", 30)
	var starter := _player("Starter", 50)
	var starter2 := _player("Starter2", 40)
	var club := _club([star, scrub, starter, starter2])
	for i in PlayerMorale.BENCH_GRACE:
		PlayerMorale.apply_match(club, [starter, starter2], {}, "draw", "Rival")
	assert_eq(star.morale, PlayerMorale.BASELINE, "no penalty inside the grace")
	PlayerMorale.apply_match(club, [starter, starter2], {}, "draw", "Rival")
	assert_eq(star.morale, PlayerMorale.BASELINE + PlayerMorale.BENCHED * PlayerMorale.STAR_BENCH_MULT)
	assert_eq(scrub.morale, PlayerMorale.BASELINE + PlayerMorale.BENCHED)
	PlayerMorale.apply_match(club, [star, starter], {}, "draw", "Rival")
	assert_eq(star.benched_streak, 0, "playing resets the streak")

func test_suspended_player_is_not_left_out() -> void:
	var s := _player("S")
	var club := _club([s])
	for i in PlayerMorale.BENCH_GRACE + 2:
		PlayerMorale.apply_match(club, [], {}, "draw", "Rival", [s])
	assert_eq(s.benched_streak, 0)
	assert_eq(s.morale, PlayerMorale.BASELINE)

func test_furious_player_asks_out_once() -> void:
	var p := _player("P")
	p.morale = 0.0
	var club := _club([p])
	var asked := 0
	for i in PlayerMorale.FURIOUS_MATCHES_TO_ASK_OUT + 2:
		asked += PlayerMorale.apply_match(club, [p], {}, "loss", "Rival").size()
	assert_eq(asked, 1)

func test_overall_bonus_zero_at_baseline_and_signed() -> void:
	var a := _player("A")
	var b := _player("B")
	assert_near(PlayerMorale.overall_bonus([a, b], 60), 0.0, 0.001)
	a.morale = 100.0
	b.morale = 100.0
	assert_near(PlayerMorale.overall_bonus([a, b], 50), PlayerMorale.STAT_PCT_MAX / 100.0 * 50, 0.001)

func test_morale_survives_save_round_trip() -> void:
	var p := _player("A")
	PlayerMorale.adjust(p, -30.0, "Sueldos atrasados")
	p.benched_streak = 2
	var q := PlayerResource.from_dict(p.to_dict())
	assert_eq(q.morale, p.morale)
	assert_eq(q.benched_streak, 2)
	assert_eq(q.morale_log.size(), 1)
