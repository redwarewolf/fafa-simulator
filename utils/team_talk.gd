class_name TeamTalk

## The half-time team talk (MatchHUD's ENTRETIEMPO panel, watched matches
## only). Each tone moves every player on the pitch's morale by an amount
## that depends on the score — and for the loud ones, on who he is — then
## MatchWorld re-reads their stats for the second half (Player.refresh_stats()).
##
##   ELOGIAR       pays off when winning, sours a losing dressing room
##   TRANQUILIZAR  small and safe whatever the score
##   EXIGIR        works when the result isn't enough; grates when winning
##   PATEAR        all or nothing — rolled per player, team players (high
##                 PlayerResource.teamplay) take it better

enum Tone { PRAISE, CALM, DEMAND, RAGE }

const LABELS := ["ELOGIAR", "TRANQUILIZAR", "EXIGIR", "PATEAR EL VESTUARIO"]
const TIPS := [
	"Felicitarlos. Ideal si vienen ganando; si van perdiendo, no se lo creen.",
	"Bajar un cambio. Mueve poco, para bien o para mal.",
	"Pedir más. Funciona cuando el resultado no alcanza; ganando, molesta.",
	"Tirar la heladera. Todo o nada: a unos los prende fuego, a otros los hunde.",
]
## Short name for the morale log ("Charla: Exigir").
const REASONS := ["Elogiar", "Tranquilizar", "Exigir", "Patear el vestuario"]

## Flat deltas by tone and score (index 0 losing, 1 drawing, 2 winning).
## RAGE isn't here — see _rage().
const FLAT := {
	Tone.PRAISE: [-4.0, 2.0, 6.0],
	Tone.CALM:   [1.0, 2.0, 2.0],
	Tone.DEMAND: [5.0, 4.0, -3.0],
}
## Patear el vestuario: chance it lands well = BASE + teamplay/100 * TEAMPLAY,
## per score; the swing is +RAGE_UP or RAGE_DOWN. Winning it never helps.
const RAGE_BASE := [0.35, 0.25, 0.0]
const RAGE_TEAMPLAY := [0.5, 0.4, 0.0]
const RAGE_UP := 10.0
const RAGE_DOWN := -8.0
## ± noise on every reaction, so no two dressing rooms read the same.
const NOISE := 2.0

static func score_index(score_diff: int) -> int:
	return 0 if score_diff < 0 else (1 if score_diff == 0 else 2)

## How much [param p]'s morale moves for [param tone] at [param score_diff]
## (own goals minus theirs).
static func reaction(p: PlayerResource, tone: int, score_diff: int, rng: RandomNumberGenerator) -> float:
	var i := score_index(score_diff)
	var base : float
	if tone == Tone.RAGE:
		var p_up : float = RAGE_BASE[i] + p.teamplay / 100.0 * RAGE_TEAMPLAY[i]
		base = RAGE_UP if rng.randf() < p_up else RAGE_DOWN
	else:
		base = FLAT[tone][i]
	return base + rng.randf_range(-NOISE, NOISE)

## Applies [param tone] to [param players] (PlayerMorale.adjust, logged as
## "Charla: <tone>"). Returns {"up": int, "down": int, "best": PlayerResource,
## "worst": PlayerResource, "worst_delta": float} for the narration.
static func deliver(players: Array, tone: int, score_diff: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"up": 0, "down": 0, "best": null, "worst": null, "best_delta": -INF, "worst_delta": INF}
	var reason := "Charla: %s" % REASONS[tone]
	for p : PlayerResource in players:
		if not PlayerMorale.has_morale(p):
			continue
		var d := reaction(p, tone, score_diff, rng)
		PlayerMorale.adjust(p, d, reason)
		if d > 0.5:
			out["up"] += 1
		elif d < -0.5:
			out["down"] += 1
		if d > out["best_delta"]:
			out["best_delta"] = d
			out["best"] = p
		if d < out["worst_delta"]:
			out["worst_delta"] = d
			out["worst"] = p
	return out

## Pepito's line about how it went.
static func narration(result: Dictionary) -> String:
	var up : int = result["up"]
	var down : int = result["down"]
	var worst : PlayerResource = result["worst"]
	var best : PlayerResource = result["best"]
	if up == 0 and down == 0:
		return "Ni fu ni fa. Salieron del vestuario igual que entraron."
	if down == 0:
		return "¡Salieron prendidos fuego! %s ya está pidiendo la pelota." % best.full_name
	if up == 0:
		return "Uh... se lo tomaron re mal. %s ni te mira a la cara." % worst.full_name
	if up >= down:
		return "A la mayoría le llegó. Eso sí, %s salió con cara de pocos amigos." % worst.full_name
	return "Se armó un lío bárbaro. %s se prendió, pero a varios no les cayó nada bien." % best.full_name
