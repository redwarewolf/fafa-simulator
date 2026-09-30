extends TestCase

## TeamTalk: which tone pays off at which score, and the narration summary.

func _player(teamplay: int = 50) -> PlayerResource:
	var p := PlayerResource.new("P", 0 as Player.SkinColor, 0 as Player.HairColor, Positions.Role.CM, 25,
		PlayerResource.Quality.COMMON, 50, 50, 50, 50, 50, 50)
	p.teamplay = teamplay
	return p

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng

func _avg(tone: int, score_diff: int, teamplay: int = 50) -> float:
	var rng := _rng()
	var total := 0.0
	for i in 400:
		total += TeamTalk.reaction(_player(teamplay), tone, score_diff, rng)
	return total / 400.0

func test_praise_pays_when_winning_and_backfires_when_losing() -> void:
	assert_true(_avg(TeamTalk.Tone.PRAISE, 1) > 4.0, "winning")
	assert_true(_avg(TeamTalk.Tone.PRAISE, -1) < -2.0, "losing")

func test_demand_pays_when_losing_and_grates_when_winning() -> void:
	assert_true(_avg(TeamTalk.Tone.DEMAND, -2) > 3.0, "losing")
	assert_true(_avg(TeamTalk.Tone.DEMAND, 2) < -1.0, "winning")

func test_calm_is_small_and_never_bad_on_average() -> void:
	for diff in [-1, 0, 1]:
		assert_between(_avg(TeamTalk.Tone.CALM, diff), 0.0, 3.0, "diff %d" % diff)

func test_rage_favours_team_players_and_never_helps_a_winning_side() -> void:
	assert_true(_avg(TeamTalk.Tone.RAGE, -1, 95) > _avg(TeamTalk.Tone.RAGE, -1, 5), "teamplay")
	assert_true(_avg(TeamTalk.Tone.RAGE, 1, 95) < -6.0, "winning")

func test_deliver_logs_and_counts() -> void:
	var a := _player()
	var b := _player()
	var result := TeamTalk.deliver([a, b], TeamTalk.Tone.PRAISE, 1, _rng())
	assert_eq(result["up"], 2)
	assert_eq(a.morale_log[0]["text"], "Charla: Elogiar")
	assert_true(TeamTalk.narration(result).begins_with("¡Salieron prendidos fuego!"))
