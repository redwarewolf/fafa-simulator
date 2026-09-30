class_name PlayerMorale

## Per-player morale: PlayerResource.morale, 0-100, persisted. Moved by
## results, playing time and unpaid wages (apply_match(), unpaid_wages()),
## drifts back toward BASELINE a little every day (drift()), and feeds the
## match as a small stat percent (stat_pct()) — added on top of positional
## aptitude in Player.initialize() and, as a squad-overall bonus
## (overall_bonus()), into the simulated/preview odds. Deliberately kept out
## of PlayerResource.modifiers so it never moves the card's stats, overall(),
## wage or market value.
##
## Special types (a cone) have no feelings: has_morale() is false, stat_pct()
## is 0 and nothing ever changes their morale.

const BASELINE := 60.0
## Points per day toward BASELINE — see SeasonManager.resolve_day().
const DAILY_DRIFT := 2.0
## How many recent reasons PlayerResource.morale_log keeps.
const LOG_SIZE := 3

enum Band { FURIOSO, MOLESTO, NORMAL, CONTENTO, ENCHUFADO }
## Lower bound of each Band, index-matched.
const BAND_MIN := [0.0, 20.0, 40.0, 65.0, 85.0]
const BAND_LABELS := ["Furioso", "Molesto", "Normal", "Contento", "Enchufado"]
const BAND_COLORS := [
	Color(0.95, 0.3, 0.3), Color(0.95, 0.6, 0.3), Color(0.85, 0.85, 0.85),
	Color(0.55, 0.85, 0.45), Color(0.3, 0.95, 0.6),
]

## Match stat percent at morale 0 and 100 (linear through 0 at BASELINE).
const STAT_PCT_MIN := -6.0
const STAT_PCT_MAX := 4.0

## Per-match deltas for players who took part (apply_match()).
const WIN := 4.0
const DRAW := 0.0
const LOSS := -3.0
const STARTED := 2.0
const PER_GOAL := 3.0
## Players left out: nothing for the first BENCH_GRACE matches in a row, then
## BENCHED per match — doubled for the better half of the squad, who expect
## to play.
const BENCH_GRACE := 2
const BENCHED := -3.0
const STAR_BENCH_MULT := 2.0
## Whole squad, on a payday that leaves the budget in the red.
const UNPAID_WAGES := -8.0
## Matches in a row at FURIOSO before the player asks to leave (a news item).
const FURIOUS_MATCHES_TO_ASK_OUT := 3


static func has_morale(p: PlayerResource) -> bool:
	return p != null and p.special_type == ""

## Changes [param p]'s morale by [param delta] and records [param reason] in
## its log (newest first). A zero delta is ignored.
static func adjust(p: PlayerResource, delta: float, reason: String) -> void:
	if not has_morale(p) or is_zero_approx(delta):
		return
	p.morale = clampf(p.morale + delta, 0.0, 100.0)
	p.morale_log.push_front({"text": reason, "delta": roundi(delta)})
	while p.morale_log.size() > LOG_SIZE:
		p.morale_log.pop_back()

static func band(p: PlayerResource) -> int:
	var b := 0
	for i in BAND_MIN.size():
		if p.morale >= BAND_MIN[i]:
			b = i
	return b

## Band name, translated.
static func label(p: PlayerResource) -> String:
	return TranslationServer.translate(BAND_LABELS[band(p)])

static func color(p: PlayerResource) -> Color:
	return BAND_COLORS[band(p)]

## "Contento (72)\n+4  Victoria ante X\n..." — card/list tooltip.
static func tooltip(p: PlayerResource) -> String:
	if not has_morale(p):
		return ""
	var lines := [TranslationServer.translate("Ánimo: %s (%d)") % [label(p), roundi(p.morale)]]
	for e : Dictionary in p.morale_log:
		var d : int = e["delta"]
		lines.append("%s%d  %s" % ["+" if d > 0 else "", d, e["text"]])
	return "\n".join(lines)

## Signed stat percent this player's morale is worth in a match.
static func stat_pct(p: PlayerResource) -> float:
	if not has_morale(p):
		return 0.0
	if p.morale >= BASELINE:
		return (p.morale - BASELINE) / (100.0 - BASELINE) * STAT_PCT_MAX
	return (BASELINE - p.morale) / BASELINE * STAT_PCT_MIN

## Squad-overall points [param players]' morale is worth, to add to the
## overall difference MatchOdds.expected_goals() takes: the average stat
## percent applied to [param club_overall].
static func overall_bonus(players: Array, club_overall: int) -> float:
	var total := 0.0
	var n := 0
	for p : PlayerResource in players:
		if has_morale(p):
			total += stat_pct(p)
			n += 1
	if n == 0:
		return 0.0
	return total / n / 100.0 * club_overall

## One day's pull toward BASELINE. Doesn't log — it's not an event.
static func drift(p: PlayerResource) -> void:
	if not has_morale(p):
		return
	if p.morale > BASELINE:
		p.morale = maxf(BASELINE, p.morale - DAILY_DRIFT)
	elif p.morale < BASELINE:
		p.morale = minf(BASELINE, p.morale + DAILY_DRIFT)

## Applies one played match to [param club]'s squad. [param appearances]:
## everyone who took part; [param goals]: full_name → goals scored for this
## club; [param outcome]: "win"/"draw"/"loss"; [param opponent_name] for the
## log text; [param excused]: players who couldn't have played (suspended),
## so they don't count as left out. Returns the players who just reached
## FURIOUS_MATCHES_TO_ASK_OUT matches in a row at FURIOSO, so the caller can
## post the news.
static func apply_match(club: ClubResource, appearances: Array, goals: Dictionary,
		outcome: String, opponent_name: String, excused: Array = []) -> Array[PlayerResource]:
	var result_delta : float = {"win": WIN, "draw": DRAW, "loss": LOSS}.get(outcome, 0.0)
	var result_text : String = {"win": "Victoria", "draw": "Empate", "loss": "Derrota"}.get(outcome, "Partido")
	result_text += " ante %s" % opponent_name
	var stars := _better_half(club)
	var asking_out : Array[PlayerResource] = []
	for p : PlayerResource in club.players:
		if not has_morale(p):
			continue
		if p in appearances:
			p.benched_streak = 0
			adjust(p, result_delta + STARTED, result_text)
			var g : int = goals.get(p.full_name, 0)
			if g > 0:
				adjust(p, PER_GOAL * g, "Gol ante %s" % opponent_name if g == 1 else "%d goles ante %s" % [g, opponent_name])
		elif not p in excused:
			p.benched_streak += 1
			if p.benched_streak > BENCH_GRACE:
				var mult := STAR_BENCH_MULT if p in stars else 1.0
				adjust(p, BENCHED * mult, "%d partidos sin jugar" % p.benched_streak)
		if band(p) == Band.FURIOSO:
			p.furious_streak += 1
			if p.furious_streak == FURIOUS_MATCHES_TO_ASK_OUT:
				asking_out.append(p)
		else:
			p.furious_streak = 0
	return asking_out

## The whole squad, on a payday that leaves the club in the red.
static func unpaid_wages(club: ClubResource) -> void:
	for p : PlayerResource in club.players:
		adjust(p, UNPAID_WAGES, "Sueldos atrasados")

## A random player from [param players], unhappy ones likelier — who a
## misbehaviour event (a wild night out) lands on. Weight 1 at morale 100 up
## to 1 + UNHAPPY_PICK_WEIGHT at 0.
const UNHAPPY_PICK_WEIGHT := 4.0

static func pick_unhappy(players: Array) -> PlayerResource:
	if players.is_empty():
		return null
	var weights : Array[float] = []
	var total := 0.0
	for p : PlayerResource in players:
		var w := 1.0 + (UNHAPPY_PICK_WEIGHT * (100.0 - p.morale) / 100.0 if has_morale(p) else 0.0)
		weights.append(w)
		total += w
	var r := randf() * total
	for i in players.size():
		r -= weights[i]
		if r <= 0.0:
			return players[i]
	return players[-1]

## The better half of [param club]'s squad by overall — who minds the bench most.
static func _better_half(club: ClubResource) -> Array:
	var sorted := club.players.duplicate()
	sorted.sort_custom(func(a: PlayerResource, b: PlayerResource) -> bool: return a.overall() > b.overall())
	return sorted.slice(0, ceili(sorted.size() / 2.0))
