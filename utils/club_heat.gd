class_name ClubHeat

## Heat: how much the AFA and the press smell. 0-100, mostly hidden — the
## player sees its consequences (Inbox, the match preview's warnings), not
## the number. Lives in GameState.afa with the sanctions it has triggered and
## this match's bribes (see new_state()); saved in career.json.
##
## Goes up with anything shady — barra incidents (BarraBrava.apply_incident()),
## feeding the barra (weekly()), bribes (commit_bribes()) and the scandals
## they can blow up into (after_match()) — and cools a little every payday.
## Crossing a line has consequences (_check_lines()):
##
##   40   the AFA opens an investigation (closes again below it)
##   60   a fine every payday while you stay up there
##   80   your next home match is played behind closed doors
##   100  points deducted; heat drops back to HEAT_AFTER_DEDUCTION

const WEEKLY_COOLING := 3.0
const INVESTIGATION_AT := 40.0
const FINES_AT := 60.0
const CLOSED_DOORS_AT := 80.0
const DEDUCTION_AT := 100.0
const HEAT_AFTER_DEDUCTION := 70.0
const DEDUCTION_POINTS := 3
## Payday fine above FINES_AT, at División E (scaled by division).
const WEEKLY_FINE_E := 3000

## Feeding the barra is noticed: weekly heat per colaboración tier and per
## barra guy on the payroll.
const HEAT_PER_COLAB_TIER := 0.5
const HEAT_PER_PUESTO := 0.5

## The bribes on offer before a match. cost_e at División E; edge is squad-
## overall points in the odds (simulated matches and the preview) — a watched
## match gets the real thing (ActorsContainer._apply_bribes()).
const BRIBES := {
	"referee": {
		"label": "Arreglar al árbitro",
		"tip": "Los fallos finos van a ir para tu lado: te cobran menos faltas y al rival más.",
		"cost_e": 3000, "heat": 15.0, "edge": 3.0,
		"scandal": "Se filtró un audio de alguien del club arreglando con el árbitro.",
	},
	"keeper": {
		"label": "Comprar al arquero rival",
		"tip": "El arquero de ellos va a tener una tarde... rara.",
		"cost_e": 5000, "heat": 20.0, "edge": 4.0,
		"scandal": "El arquero rival se fue de boca en un bar y contó cuánto le pagamos.",
	},
}
## Referee bribe in a watched match: share of our fouls still called, and of
## theirs (more free kicks for us).
const REFEREE_OWN_FOULS := 0.5
const REFEREE_RIVAL_FOULS := 1.5
## Keeper bribe: the rival keeper's stat percent this match.
const KEEPER_STAT_PCT := -25.0

## After the match, per bribe: chance it blows up = BASE + heat × PER_HEAT.
const SCANDAL_BASE := 0.15
const SCANDAL_PER_HEAT := 0.004
const SCANDAL_FINE_MULT := 2.0
const SCANDAL_FANS_E := [20, 60]
const SCANDAL_HEAT := 15.0

static func new_state() -> Dictionary:
	return {
		"heat": 0.0, "investigation": false, "closed_doors": false,
		"bribes": {"referee": false, "keeper": false}, "bribes_paid": false, "bribes_spent": 0,
	}

static func from_save(saved: Dictionary) -> Dictionary:
	var s := new_state()
	s["heat"] = float(saved.get("heat", 0.0))
	s["investigation"] = bool(saved.get("investigation", false))
	s["closed_doors"] = bool(saved.get("closed_doors", false))
	s["bribes_paid"] = bool(saved.get("bribes_paid", false))
	s["bribes_spent"] = int(saved.get("bribes_spent", 0))
	var b : Dictionary = saved.get("bribes", {})
	for k in s["bribes"]:
		s["bribes"][k] = bool(b.get(k, false))
	return s

## Adds heat and applies whatever line it crosses. [param club] takes the
## points deduction.
static func add(s: Dictionary, amount: float, club: ClubResource) -> void:
	s["heat"] = clampf(float(s["heat"]) + amount, 0.0, DEDUCTION_AT)
	_check_lines(s, club)

static func _check_lines(s: Dictionary, club: ClubResource) -> void:
	var heat : float = s["heat"]
	if heat >= DEDUCTION_AT and club != null:
		club.tournament_points = maxi(0, club.tournament_points - DEDUCTION_POINTS)
		s["heat"] = HEAT_AFTER_DEDUCTION
		GameState.post_news("La AFA nos descontó %d puntos" % DEDUCTION_POINTS,
			"Se juntaron demasiadas cosas: la barra, los arreglos, los escándalos. El Tribunal de Disciplina nos sacó %d puntos de la tabla." % DEDUCTION_POINTS,
			"afa")
		return
	if heat >= CLOSED_DOORS_AT and not s["closed_doors"]:
		s["closed_doors"] = true
		GameState.post_news("Sanción: puertas cerradas",
			"La AFA nos sancionó: el próximo partido de local se juega sin público. Sin entradas y sin barra.",
			"afa")
	if heat >= INVESTIGATION_AT and not s["investigation"]:
		s["investigation"] = true
		GameState.post_news("La AFA abrió una investigación",
			"Nos están mirando. Si seguimos así, van a llegar las multas... y cosas peores.",
			"afa")

## Payday: cooling, the barra's cost in heat, the fine above FINES_AT.
## Returns the fine charged (for the ledger).
static func weekly(s: Dictionary, club: ClubResource, barra: Dictionary) -> int:
	var fed := int(barra["colaboracion"]) * HEAT_PER_COLAB_TIER + int(barra["puestos"]) * HEAT_PER_PUESTO
	add(s, fed - WEEKLY_COOLING, club)
	var fine := 0
	if float(s["heat"]) >= FINES_AT:
		fine = BarraBrava.cost(WEEKLY_FINE_E, club.division)
		club.budget -= fine
	if s["investigation"] and float(s["heat"]) < INVESTIGATION_AT:
		s["investigation"] = false
		GameState.post_news("La AFA cerró la investigación",
			"No encontraron nada. O no quisieron encontrar. Por ahora, estamos tranquilos.", "afa")
	return fine

static func bribe_cost(key: String, division: String) -> int:
	return BarraBrava.cost(BRIBES[key]["cost_e"], division)

static func any_bribe(s: Dictionary) -> bool:
	return s["bribes"].values().has(true)

## Squad-overall points this match's bribes are worth to us in the odds.
static func bribe_edge(s: Dictionary) -> float:
	var edge := 0.0
	for k in BRIBES:
		if s["bribes"][k]:
			edge += BRIBES[k]["edge"]
	return edge

## Chance one bribe blows up after the match, at the current heat.
static func scandal_chance(s: Dictionary) -> float:
	return clampf(SCANDAL_BASE + float(s["heat"]) * SCANDAL_PER_HEAT, 0.0, 1.0)

## Kickoff (Jugar or Simular): pays the chosen bribes and takes their heat.
static func commit_bribes(s: Dictionary, club: ClubResource) -> void:
	if not any_bribe(s) or s["bribes_paid"]:
		return
	var spent := 0
	for k in BRIBES:
		if s["bribes"][k]:
			spent += bribe_cost(k, club.division)
			add(s, BRIBES[k]["heat"], club)
	club.budget -= spent
	s["bribes_paid"] = true
	s["bribes_spent"] = spent
	GameState.budget_changed.emit()

## Full time: each bribe may leak (a fine, lost fans, more heat); then
## they're spent. Returns {"bribe_cost", "scandal_fine"} — what this match's
## dealings cost, for the post-match summary.
static func after_match(s: Dictionary, club: ClubResource, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"bribe_cost": 0, "scandal_fine": 0}
	if s["bribes_paid"]:
		out["bribe_cost"] = s["bribes_spent"]
		for k in BRIBES:
			if s["bribes"][k] and rng.randf() < scandal_chance(s):
				out["scandal_fine"] += _scandal(s, club, k, rng)
	for k in s["bribes"]:
		s["bribes"][k] = false
	s["bribes_paid"] = false
	s["bribes_spent"] = 0
	return out

## Returns the fine.
static func _scandal(s: Dictionary, club: ClubResource, key: String, rng: RandomNumberGenerator) -> int:
	var fine := roundi(bribe_cost(key, club.division) * SCANDAL_FINE_MULT)
	var fans := BarraBrava.cost(rng.randi_range(SCANDAL_FANS_E[0], SCANDAL_FANS_E[1]), club.division)
	club.budget -= fine
	club.fans = maxi(FanEconomy.MIN_FANS, club.fans - fans)
	GameState.post_news("Escándalo", "%s Multa de $%s, %d hinchas menos, y la AFA toma nota." % [
		BRIBES[key]["scandal"], MoneyFormat.format(fine), fans], "afa")
	add(s, SCANDAL_HEAT, club)
	GameState.budget_changed.emit()
	return fine

## True when this home match is the one played behind closed doors.
static func closed_doors_now(s: Dictionary, is_home: bool) -> bool:
	return is_home and s["closed_doors"]

## A vague read of the heat for the match preview.
static func warning(s: Dictionary) -> String:
	var heat : float = s["heat"]
	if heat >= CLOSED_DOORS_AT:
		return TranslationServer.translate("La AFA está a un paso de sacarnos puntos.")
	if heat >= FINES_AT:
		return TranslationServer.translate("La AFA nos está multando todas las semanas.")
	if s["investigation"]:
		return TranslationServer.translate("La AFA nos está investigando.")
	if heat >= INVESTIGATION_AT * 0.5:
		return TranslationServer.translate("Hay periodistas preguntando cosas raras.")
	return ""
