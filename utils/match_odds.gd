class_name MatchOdds

## Win/draw/loss probability model shared by SeasonManager's AI-vs-AI results
## and the player's own match-preview popup / "Simular" flow. Both express a
## matchup as two independent Poisson-distributed scorelines (home/away
## expected goals from squad-overall difference, same formula either way) —
## SeasonManager just samples one scoreline from it, while the preview/
## simulate flow also needs the actual win/draw/loss probabilities, which
## means summing the Poisson joint distribution instead of only sampling it.

## Same tuning as the old SeasonManager._simulate_goals(): a squad-overall
## point is worth 1/25th of an expected goal, plus a small home-field bump.
const BASE_EXPECTED  := 1.3
const DIFF_SCALE      := 25.0
const HOME_ADVANTAGE  := 0.2
const MIN_EXPECTED    := 0.2
const MAX_EXPECTED    := 4.0

## Truncation bound for the win/draw/loss convolution — Poisson's tail past
## this many goals is negligible for any expected value MAX_EXPECTED allows.
const MAX_GOALS_FOR_PROBABILITY := 10

## Flat probability-point penalty subtracted from the player's win odds when
## they choose to simulate instead of play a match out. E.g. a 27% win
## chance becomes 17% — see apply_simulate_penalty().
const SIMULATE_PENALTY := 0.10

## Rejection-sampling cap for sample_scoreline_for_outcome() — see its doc.
const MAX_SCORELINE_ATTEMPTS := 400


## Expected goals for one side, from the squad-overall difference (that
## side's overall minus the opponent's) and whether they're playing at home.
static func expected_goals(overall_diff: float, is_home: bool) -> float:
	var expected := BASE_EXPECTED + overall_diff / DIFF_SCALE + (HOME_ADVANTAGE if is_home else 0.0)
	return clampf(expected, MIN_EXPECTED, MAX_EXPECTED)


static func poisson_pmf(k: int, lambda: float) -> float:
	if lambda <= 0.0:
		return 1.0 if k == 0 else 0.0
	# Computed in log-space to avoid overflow from lambda^k for larger k.
	var log_pmf := -lambda + k * log(lambda) - _log_factorial(k)
	return exp(log_pmf)


static func _log_factorial(n: int) -> float:
	var total := 0.0
	for i in range(2, n + 1):
		total += log(float(i))
	return total


## Knuth's algorithm — same sampler SeasonManager._simulate_fixture() used to
## have inline, now shared so both AI-vs-AI results and the player's own
## simulated matches draw from the identical distribution.
static func poisson_sample(lambda: float) -> int:
	var l := exp(-lambda)
	var k := 0
	var p := 1.0
	while true:
		k += 1
		p *= randf()
		if p <= l:
			break
	return k - 1


## Win/draw/loss probabilities for the HOME side, by summing the joint
## Poisson distribution of (home_goals, away_goals) over every scoreline up
## to MAX_GOALS_FOR_PROBABILITY. {"win": float, "draw": float, "loss": float},
## normalized to sum to 1.0.
static func win_draw_loss(home_expected: float, away_expected: float) -> Dictionary:
	var win := 0.0
	var draw := 0.0
	var loss := 0.0
	for h in range(MAX_GOALS_FOR_PROBABILITY + 1):
		var ph := poisson_pmf(h, home_expected)
		for a in range(MAX_GOALS_FOR_PROBABILITY + 1):
			var p := ph * poisson_pmf(a, away_expected)
			if h > a:
				win += p
			elif h == a:
				draw += p
			else:
				loss += p
	var total := win + draw + loss
	if total > 0.0:
		win /= total
		draw /= total
		loss /= total
	return {"win": win, "draw": draw, "loss": loss}


## Mirrors a {"win", "draw", "loss"} dict to the other side's perspective.
static func flip_odds(odds: Dictionary) -> Dictionary:
	return {"win": odds["loss"], "draw": odds["draw"], "loss": odds["win"]}


static func flip_outcome(outcome: String) -> String:
	match outcome:
		"win": return "loss"
		"loss": return "win"
		_: return "draw"


## Subtracts SIMULATE_PENALTY from the win probability (floored at 0 rather
## than going negative for a near-certain underdog) and hands whatever was
## actually subtracted to the loss probability — simulating instead of
## playing costs you some of your best outcomes, never your draws.
static func apply_simulate_penalty(odds: Dictionary) -> Dictionary:
	var win : float = odds["win"]
	var penalized_win := maxf(0.0, win - SIMULATE_PENALTY)
	var subtracted := win - penalized_win
	return {"win": penalized_win, "draw": odds["draw"], "loss": odds["loss"] + subtracted}


## Rolls "win"/"draw"/"loss" from a {"win","draw","loss"} probability dict.
static func pick_outcome(odds: Dictionary) -> String:
	var r := randf()
	var win : float = odds["win"]
	if r < win:
		return "win"
	if r < win + odds["draw"]:
		return "draw"
	return "loss"


## Draws a (home_score, away_score) pair from the same Poisson model
## win_draw_loss() summed, but conditioned on a specific outcome for the
## home side — via rejection sampling: keep drawing ordinary scorelines
## until one actually matches the wanted outcome. This is what makes a
## simulated result feel earned rather than arbitrary: a huge underdog
## "winning" has a low expected-goals draw, so the accepted sample is
## almost always a narrow 1-0-style scoreline (the most probable point
## satisfying the outcome), while a heavy favorite's win samples tend to
## land with a wider margin, since its expected goals are higher to begin
## with. Falls back to a minimal scoreline for that outcome if no sample
## converges within MAX_SCORELINE_ATTEMPTS (only possible for extreme,
## near-zero-probability outcomes).
static func sample_scoreline_for_outcome(home_expected: float, away_expected: float, outcome_for_home: String) -> Array:
	for i in MAX_SCORELINE_ATTEMPTS:
		var h := poisson_sample(home_expected)
		var a := poisson_sample(away_expected)
		var actual := "win" if h > a else ("loss" if h < a else "draw")
		if actual == outcome_for_home:
			return [h, a]
	match outcome_for_home:
		"win": return [1, 0]
		"loss": return [0, 1]
		_: return [1, 1]
