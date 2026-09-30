class_name BarraBrava

## La barra brava and its capo, Barroni Flaquito. Its state lives in
## GameState.barra (saved in career.json; see new_state() for the keys):
##
##   relacion  0-100  how happy they are with you (see BANDS)
##   poder     0-100  how much they can do, for or against you — grows with
##                    the fans, and with everything you give them
##
## What you give them each week is up to you (Club > La Barra): free tickets
## for home matches, a cash "colaboración", buses to away matches — plus
## whatever you took on from Barroni's demands (people on the payroll).
## Every payday (GameState._run_payday()) weekly() charges it and moves the
## meters; results move relacion too (on_match_result()). Barroni shows up
## in person the first payday, and some paydays after that with a demand
## (hub.gd plays run_visit() after the day advance).

const LEADER := "Barroni Flaquito"
const PORTRAIT := preload("res://assets/art/club/barra-lider.png")
## The art is a landscape scene; the dialogue box wants a portrait, so it
## gets this crop of the figure (hat to belly).
const PORTRAIT_REGION := Rect2(260, 0, 1016, 1024)

const BANDS := ["Enemistados", "Tensos", "Tranquilos", "Contentos", "Incondicionales"]
const BAND_MIN := [0.0, 20.0, 40.0, 60.0, 80.0]
const BAND_COLORS := [
	Color(0.95, 0.3, 0.3), Color(0.95, 0.6, 0.3), Color(0.85, 0.85, 0.85),
	Color(0.55, 0.85, 0.45), Color(0.3, 0.95, 0.6),
]

## They always want more: relacion loses this every week before what you give.
const WEEKLY_GRUDGE := -4.0

## Entradas de favor: share of each home match's crowd that gets in free.
const ENTRADAS_SHARE := [0.0, 0.10, 0.25]
const ENTRADAS_RELACION := [0.0, 3.0, 6.0]
## Colaboración: weekly cash at División E (scaled by division — see cost()).
const COLAB_COST_E := [0, 500, 1200, 2500]
const COLAB_RELACION := [0.0, 3.0, 6.0, 10.0]
## Micros para las visitas: weekly, División E.
const MICROS_COST_E := 400
const MICROS_RELACION := 3.0
## One barra guy on the club payroll (a demand), weekly, División E.
const PUESTO_COST_E := 300

## poder heads toward a target each week — POWER_BASE, plus the fans, plus
## everything you feed them — closing POWER_PULL of the gap.
const POWER_BASE := 10.0
const POWER_PER_FAN := 1.0 / 40.0
const POWER_FROM_FANS_MAX := 40.0
const POWER_PER_COLAB := 8.0
const POWER_PER_ENTRADAS := 5.0
const POWER_PER_PUESTO := 4.0
const POWER_MICROS := 4.0
const POWER_PULL := 0.2

## League results (on_match_result()).
const RESULT_RELACION := {"win": 2.0, "draw": 0.0, "loss": -3.0}
## From this many league defeats in a row, each one costs this much more.
const LOSS_STREAK_HOT := 3
const LOSS_STREAK_EXTRA := -3.0

## A demand visit: chance per payday, and weeks of quiet after one.
const DEMAND_CHANCE := 0.35
const DEMAND_COOLDOWN_WEEKS := 3

## Barroni's demands. cost_e is at División E (see cost()); a "puesto" adds a
## weekly cost instead of a one-off.
const DEMANDS := [
	{
		"id": "bandera",
		"ask": "Escuchame bien, jefe. Los muchachos quieren un trapo nuevo para la tribuna. Son ${cost}. Es por el bien del club, vos entendés.",
		"cost_e": 2000, "accept": 10.0, "decline": -8.0, "poder": 2.0,
	},
	{
		"id": "puesto",
		"ask": "Tengo un sobrino que necesita laburo. Ponelo en el club, de lo que sea. Son ${cost} por semana, una pavada.",
		"cost_e": PUESTO_COST_E, "accept": 12.0, "decline": -6.0, "poder": 3.0, "weekly": true,
	},
	{
		"id": "asado",
		"ask": "El domingo hacemos un asado en la sede con los pibes. Poné la carne: ${cost}. Y venite, que queda feo si no.",
		"cost_e": 800, "accept": 6.0, "decline": -4.0, "poder": 0.0,
	},
]
const ACCEPT_REPLIES := [
	"Así me gusta. Sos de los nuestros.",
	"Bien ahí. La tribuna no se olvida.",
	"Eso, jefe. Así se hacen las cosas.",
]
const DECLINE_REPLIES := [
	"Mirá vos... Me lo voy a acordar.",
	"Ah, ¿así estamos? Bueno. Después no te quejes.",
	"Qué lástima. Los muchachos se van a poner tristes. Y cuando se ponen tristes...",
]
const INTRO_LINES := [
	"Así que vos sos el nuevo. Yo soy Barroni Flaquito. La tribuna es mía.",
	"Acá las cosas funcionan así: vos nos cuidás a nosotros, nosotros te cuidamos a vos. Entradas, una colaboración, los micros para las visitas... lo que te parezca.",
	"Si nos tenés contentos, la cancha es una caldera. Si no... mejor que no. Pasate por el club, en La Barra, y arreglamos.",
]


static func new_state() -> Dictionary:
	return {
		"met": false, "relacion": 50.0, "poder": 15.0,
		"entradas": 0, "colaboracion": 0, "micros": false, "puestos": 0,
		"cooldown": 0, "loss_streak": 0, "visit_pending": false,
	}

## A saved state (JSON: every number a float) merged over the defaults.
static func from_save(saved: Dictionary) -> Dictionary:
	var s := new_state()
	for k in s:
		if not saved.has(k):
			continue
		var d = s[k]
		if d is bool:
			s[k] = bool(saved[k])
		elif d is int:
			s[k] = int(saved[k])
		else:
			s[k] = float(saved[k])
	return s

static func band(relacion: float) -> int:
	var b := 0
	for i in BAND_MIN.size():
		if relacion >= BAND_MIN[i]:
			b = i
	return b

static func band_label(relacion: float) -> String:
	return TranslationServer.translate(BANDS[band(relacion)])

## [param cost_e] scaled to [param division] — the same multiplier fan swings use.
static func cost(cost_e: int, division: String) -> int:
	return roundi(cost_e * float(FanEconomy.DIVISION_FAN_MULTIPLIER.get(division, 1.0)))

## What [param s] costs a week at [param division].
static func weekly_cost(s: Dictionary, division: String) -> int:
	var total : int = cost(COLAB_COST_E[s["colaboracion"]], division)
	if s["micros"]:
		total += cost(MICROS_COST_E, division)
	total += int(s["puestos"]) * cost(PUESTO_COST_E, division)
	return total

## Relación change a week from what [param s] gives (before results).
static func weekly_relacion(s: Dictionary) -> float:
	var d : float = WEEKLY_GRUDGE + ENTRADAS_RELACION[s["entradas"]] + COLAB_RELACION[s["colaboracion"]]
	if s["micros"]:
		d += MICROS_RELACION
	return d

static func power_target(s: Dictionary, fans: int) -> float:
	var t := POWER_BASE + minf(fans * POWER_PER_FAN, POWER_FROM_FANS_MAX)
	t += int(s["colaboracion"]) * POWER_PER_COLAB + int(s["entradas"]) * POWER_PER_ENTRADAS
	t += int(s["puestos"]) * POWER_PER_PUESTO
	if s["micros"]:
		t += POWER_MICROS
	return clampf(t, 0.0, 100.0)

## Payday: charges the week and moves the meters. Returns the cost (for the
## ledger). Also decides whether Barroni comes by (visit_pending).
static func weekly(s: Dictionary, club: ClubResource) -> int:
	var charged := weekly_cost(s, club.division)
	club.budget -= charged
	s["relacion"] = clampf(s["relacion"] + weekly_relacion(s), 0.0, 100.0)
	s["poder"] = clampf(s["poder"] + (power_target(s, club.fans) - s["poder"]) * POWER_PULL, 0.0, 100.0)
	if not s["met"]:
		s["visit_pending"] = true
	elif s["cooldown"] > 0:
		s["cooldown"] -= 1
	elif randf() < DEMAND_CHANCE:
		s["visit_pending"] = true
	return charged

## A league result: they like winning, and a losing run makes them hot.
static func on_match_result(s: Dictionary, outcome: String) -> void:
	s["loss_streak"] = s["loss_streak"] + 1 if outcome == "loss" else 0
	var d : float = RESULT_RELACION.get(outcome, 0.0)
	if s["loss_streak"] >= LOSS_STREAK_HOT:
		d += LOSS_STREAK_EXTRA
	s["relacion"] = clampf(s["relacion"] + d, 0.0, 100.0)

## Share of a home crowd let in free — ticket revenue is charged on the rest.
static func free_ticket_share(s: Dictionary) -> float:
	return ENTRADAS_SHARE[s["entradas"]]

## Accepting [param demand]: pays it (or puts someone on the payroll) and
## pleases them. Declining just annoys them. Either way, quiet for a while.
static func resolve_demand(s: Dictionary, club: ClubResource, demand: Dictionary, accepted: bool) -> void:
	s["cooldown"] = DEMAND_COOLDOWN_WEEKS
	if not accepted:
		s["relacion"] = clampf(s["relacion"] + demand["decline"], 0.0, 100.0)
		return
	if demand.get("weekly", false):
		s["puestos"] += 1
	else:
		club.budget -= cost(demand["cost_e"], club.division)
	s["relacion"] = clampf(s["relacion"] + demand["accept"], 0.0, 100.0)
	s["poder"] = clampf(s["poder"] + demand["poder"], 0.0, 100.0)

# ── At matches ────────────────────────────────────────────────────────────────
#
# Aguante: how hard the barra pushes, −1 (furious and strong) to +1 (devoted
# and strong). They're at every home match, and away only with the micros —
# at half the weight. match_effect() turns that into what the match reads:
# a per-match stat percent for each side (Player.crowd_pct), how often your
# players' fouls get called (Player.foul_call_scale), the crowd's mood in the
# stands, and whether something happens (roll_incident()).

## Poder always counts for something — a weak barra still makes noise.
const AGUANTE_POWER_FLOOR := 0.3
const AWAY_PRESENCE := 0.5
## Your players' stat percent at aguante ±1 (negative: they whistle their own).
const CROWD_STAT_PCT := 5.0
## The rival's stat percent at aguante +1 (only a happy barra intimidates).
const RIVAL_STAT_PCT := -3.0
## At aguante +1 the referee calls this share fewer of your fouls.
const REFEREE_LENIENCY := 0.4
## Crowd mood shows from this |aguante| up.
const MOOD_THRESHOLD := 0.1

## Incidents: chance per match = |aguante| × this, for an angry barra (the
## bad ones) or a happy one (the good one), capped at INCIDENT_CHANCE_MAX.
const ANGRY_INCIDENT_SCALE := 1.5
const HAPPY_INCIDENT_SCALE := 0.8
const INCIDENT_CHANCE_MAX := 0.8

## Pepito narrates. {player}/{amount}/{fans} filled by apply_incident(); money
## and fans are at División E and scale by division (cost()).
const ANGRY_INCIDENTS := [
	{
		"id": "banderazo",
		"line": "La barra colgó un trapo gigante: \"COMISIÓN DIRECTIVA: SE VAN TODOS\". Se armó un escándalo y perdimos {fans} hinchas.",
		"fans_e": [10, 30], "heat": 4.0,
	},
	{
		"id": "insultos",
		"line": "La barra la agarró con {player} y lo insultó los noventa minutos. El pibe está destruido.",
		"morale": -12.0, "heat": 2.0,
	},
	{
		"id": "bengalas",
		"line": "Volaron bengalas desde la tribuna y el árbitro paró el partido un rato. La liga nos multó con ${amount}.",
		"fine_e": [2000, 5000], "heat": 8.0,
	},
	{
		"id": "invasion",
		"line": "Un barra saltó el alambrado para increpar a los jugadores. Multa de ${amount} y {fans} hinchas que no vuelven.",
		"fine_e": [1500, 3500], "fans_e": [5, 20], "heat": 10.0,
	},
]
const HAPPY_INCIDENT := {
	"id": "recibimiento",
	"line": "¡Recibimiento de locura! Papelitos, bombos y humo por todos lados. El plantel salió a la cancha enchufado.",
	"team_morale": 4.0,
}

static func aguante(s: Dictionary) -> float:
	var mood := clampf((float(s["relacion"]) - 50.0) / 50.0, -1.0, 1.0)
	return mood * lerpf(AGUANTE_POWER_FLOOR, 1.0, float(s["poder"]) / 100.0)

## 1 at home, AWAY_PRESENCE away with the micros, 0 otherwise — and 0 at a
## home match the AFA closed to the public (ClubHeat).
static func presence(s: Dictionary, is_home: bool) -> float:
	if is_home:
		return 0.0 if ClubHeat.closed_doors_now(GameState.afa, true) else 1.0
	return AWAY_PRESENCE if s["micros"] else 0.0

## {"own_pct", "rival_pct", "own_foul_scale", "mood": Tribune row (0 neutral,
## 1 angry, 2 happy), "mood_share": 0-1 of the crowd showing it}. All neutral
## when the barra isn't there.
static func match_effect(s: Dictionary, is_home: bool) -> Dictionary:
	var a := aguante(s) * presence(s, is_home)
	var fx := {
		"own_pct": a * CROWD_STAT_PCT,
		"rival_pct": maxf(a, 0.0) * RIVAL_STAT_PCT,
		"own_foul_scale": 1.0 - maxf(a, 0.0) * REFEREE_LENIENCY,
		"mood": 0, "mood_share": 0.0,
	}
	if a >= MOOD_THRESHOLD:
		fx["mood"] = 2
	elif a <= -MOOD_THRESHOLD:
		fx["mood"] = 1
	fx["mood_share"] = clampf(absf(a) * 1.5, 0.0, 1.0) if fx["mood"] != 0 else 0.0
	return fx

## Squad-overall points the crowd is worth to each side of a simulated match
## (see SeasonManager._overall_diff_with_morale()): [own, rival].
static func overall_bonus(s: Dictionary, is_home: bool, own_overall: int, rival_overall: int) -> Array:
	var fx := match_effect(s, is_home)
	return [fx["own_pct"] / 100.0 * own_overall, fx["rival_pct"] / 100.0 * rival_overall]

## The incident for this match, or {} — rolled once per match.
static func roll_incident(s: Dictionary, is_home: bool, rng: RandomNumberGenerator) -> Dictionary:
	var a := aguante(s) * presence(s, is_home)
	if a < 0.0 and rng.randf() < minf(-a * ANGRY_INCIDENT_SCALE, INCIDENT_CHANCE_MAX):
		return ANGRY_INCIDENTS[rng.randi() % ANGRY_INCIDENTS.size()]
	if a > 0.0 and rng.randf() < minf(a * HAPPY_INCIDENT_SCALE, INCIDENT_CHANCE_MAX):
		return HAPPY_INCIDENT
	return {}

## Applies [param incident] to [param club] ([param xi]: its players in this
## match, for the targeted ones) and returns Pepito's line. Also posts it to
## the Inbox.
static func apply_incident(incident: Dictionary, club: ClubResource, xi: Array, rng: RandomNumberGenerator) -> String:
	var text : String = incident["line"]
	if incident.has("fans_e"):
		var r : Array = incident["fans_e"]
		var lost := cost(rng.randi_range(r[0], r[1]), club.division)
		club.fans = maxi(FanEconomy.MIN_FANS, club.fans - lost)
		text = text.replace("{fans}", str(lost))
	if incident.has("fine_e"):
		var r : Array = incident["fine_e"]
		var fine := cost(rng.randi_range(r[0], r[1]), club.division)
		club.budget -= fine
		text = text.replace("{amount}", MoneyFormat.format(fine))
	if incident.has("morale") and not xi.is_empty():
		var target : PlayerResource = xi[rng.randi() % xi.size()]
		PlayerMorale.adjust(target, incident["morale"], "La barra lo insultó")
		text = text.replace("{player}", target.full_name)
	if incident.has("team_morale"):
		for p : PlayerResource in xi:
			PlayerMorale.adjust(p, incident["team_morale"], "Recibimiento de la barra")
	GameState.post_news("La barra", text, "barra")
	if incident.has("heat"):
		ClubHeat.add(GameState.afa, incident["heat"], club)
	GameState.budget_changed.emit()
	return text

## A DialogueLine spoken by Barroni.
static func line(text: String) -> DialogueLine:
	var atlas := AtlasTexture.new()
	atlas.atlas = PORTRAIT
	atlas.region = PORTRAIT_REGION
	return DialogueLine.new(LEADER, atlas, null, text)

## The payday visit, if one is due: the introduction the first time, a
## demand after that. Awaited by hub.gd after the day advance, so it never
## overlaps another dialogue.
static func run_visit() -> void:
	var s : Dictionary = GameState.barra
	var club := GameState.player_club
	if not s["visit_pending"] or club == null:
		return
	s["visit_pending"] = false
	if not s["met"]:
		s["met"] = true
		var lines : Array[DialogueLine] = []
		for t in INTRO_LINES:
			lines.append(line(t))
		ClubTrainer.speak(lines)
		await ClubTrainer.finished
		return
	var demand : Dictionary = DEMANDS[randi() % DEMANDS.size()]
	var amount := cost(demand["cost_e"], club.division)
	var ask : String = demand["ask"].replace("{cost}", MoneyFormat.format(amount))
	var accepted : bool = await ClubTrainer.speak_with_choice(line(ask), _demand_card(demand, amount))
	resolve_demand(s, club, demand, accepted)
	GameState.budget_changed.emit()
	var replies := ACCEPT_REPLIES if accepted else DECLINE_REPLIES
	var reply : Array[DialogueLine] = [line(replies[randi() % replies.size()])]
	ClubTrainer.speak(reply)
	await ClubTrainer.finished

## Right side of the demand dialogue: what saying yes costs and buys.
static func _demand_card(demand: Dictionary, amount: int) -> Control:
	var center := CenterContainer.new()
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.11, 0.92)
	style.set_content_margin_all(16)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var price := Label.new()
	var per_week : String = TranslationServer.translate(" por semana") if demand.get("weekly", false) else ""
	price.text = "$%s%s" % [MoneyFormat.format(amount), per_week]
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_color_override("font_color", HubPalette.LOSS)
	box.add_child(price)
	for row in [[TranslationServer.translate("Si aceptás: relación +%d") % roundi(demand["accept"]), HubPalette.WIN],
			[TranslationServer.translate("Si rechazás: relación %d") % roundi(demand["decline"]), HubPalette.LOSS]]:
		var l := Label.new()
		l.text = row[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", row[1])
		box.add_child(l)
	return center
