class_name ClubDebt

## Grandi Tapir's loan. Every career starts owing STARTING_DEBT, repaid
## WEEKLY_PAYMENT on each payday (GameState._run_payday()). The balance lives
## in GameState (debt, debt_arrears, debt_strikes) and is saved in
## career.json.
##
## A payday the budget can't cover is missed: that week's payment moves into
## the arrears plus LATE_FEE, and Tapir warns you. Still behind the next
## payday, he takes the cheapest asset worth at least what's owed — a player,
## or a level of a stadium upgrade or staff hire — and keeps the change. (He
## used to pick any covering asset at random, which could take a $290k star
## over a $7k debt.) Paying the
## arrears in full clears the warning. Tuned with tools/economy_sim.tscn.

const StadiumPanel := preload("res://scenes/hub/sections/club/stadium_panel.gd")

const STARTING_DEBT := 200000
const WEEKLY_PAYMENT := 3000
const LATE_FEE := 0.10
## Tapir never strips the squad below this many players.
const MIN_SQUAD_AFTER_SEIZURE := 9

const TAPIR := "Grandi Tapir"

## Collects this payday's instalment from [param club]. Returns what was paid
## (0 if the payment was missed) and appends Tapir's lines, if he has
## anything to say, to [param lines].
static func collect(club: ClubResource, lines: Array[String]) -> int:
	if GameState.debt <= 0 and GameState.debt_arrears <= 0:
		return 0
	var part := mini(GameState.debt, WEEKLY_PAYMENT)
	var due := GameState.debt_arrears + part
	if club.budget >= due:
		club.budget -= due
		GameState.debt -= part
		var was_behind := GameState.debt_arrears > 0
		GameState.debt_arrears = 0
		GameState.debt_strikes = 0
		if GameState.debt <= 0:
			lines.append("Bueno, bueno... pagaste hasta el último peso. Se terminó la deuda. No te acostumbres a que sea tan bueno.")
			GameState.post_news("Deuda saldada", "Le pagaste la última cuota a Grandi Tapir. El club ya no le debe nada.", "debt")
		elif was_behind:
			lines.append("Llegó la plata atrasada. Estamos al día... por ahora.")
		return due

	# Missed: this week's instalment joins the arrears, plus the late fee.
	GameState.debt -= part
	GameState.debt_arrears = roundi((GameState.debt_arrears + part) * (1.0 + LATE_FEE))
	GameState.debt_strikes += 1
	if GameState.debt_strikes == 1:
		lines.append("Che, esta semana no me llegó la cuota. Te la anoto con un %d%% de recargo: me debés $%s. La semana que viene quiero todo, o me cobro con lo que encuentre." %
			[roundi(LATE_FEE * 100.0), MoneyFormat.format(GameState.debt_arrears)])
		GameState.post_news("Cuota impaga", "No alcanzó la plata para la cuota de Grandi Tapir. Deuda atrasada: $%s. Si la semana que viene seguimos sin pagar, se va a cobrar con algo del club." %
			MoneyFormat.format(GameState.debt_arrears), "debt")
		return 0
	_seize(club, lines)
	return 0

## Tapir takes the cheapest asset worth at least the arrears — a random one of
## them on a tie — or, if nothing is worth that much, the most valuable one,
## and the rest stays owed.
static func _seize(club: ClubResource, lines: Array[String]) -> void:
	var owed := GameState.debt_arrears
	var candidates := seizable_assets(club)
	if candidates.is_empty():
		lines.append("No tenés nada que valga la pena llevarme. Me seguís debiendo $%s, y el recargo sigue corriendo." % MoneyFormat.format(owed))
		GameState.post_news("Tapir no encontró qué llevarse", "Seguimos debiendo $%s de cuotas atrasadas." % MoneyFormat.format(owed), "debt")
		return
	var covering := candidates.filter(func(a: Dictionary) -> bool: return a["value"] >= owed)
	var asset : Dictionary
	if covering.is_empty():
		asset = candidates[0]
		for a in candidates:
			if a["value"] > asset["value"]:
				asset = a
	else:
		var cheapest : int = covering.map(func(a: Dictionary) -> int: return a["value"]).min()
		asset = covering.filter(func(a: Dictionary) -> bool: return a["value"] == cheapest).pick_random()

	if asset["kind"] == "player":
		var p : PlayerResource = asset["player"]
		club.players.erase(p)
		GameState.clear_player_from_tactics(p)
	else:
		club.upgrades[asset["key"]] = int(club.upgrades.get(asset["key"], 0)) - 1

	var value : int = asset["value"]
	GameState.debt_arrears = maxi(0, owed - value)
	if GameState.debt_arrears == 0:
		GameState.debt_strikes = 0
		lines.append("Te avisé. Como no pagaste, me llevo %s. Vale $%s, así que quedamos a mano con los $%s que me debías. Y no, no hay vuelto." %
			[asset["label"], MoneyFormat.format(value), MoneyFormat.format(owed)])
	else:
		lines.append("Me llevo %s ($%s) a cuenta. Todavía me debés $%s de atrasos." %
			[asset["label"], MoneyFormat.format(value), MoneyFormat.format(GameState.debt_arrears)])
	GameState.post_news("Tapir se llevó %s" % asset["label"],
		"Por las cuotas impagas ($%s), Grandi Tapir se cobró con %s, valuado en $%s." %
		[MoneyFormat.format(owed), asset["label"], MoneyFormat.format(value)], "debt")

## Everything Tapir could take: {kind: "player"|"level", label, value, and
## player or key}. A level is valued at what that level cost to buy. The
## Edificio is only takeable while no other upgrade's current level needs it.
static func seizable_assets(club: ClubResource) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	if club.players.size() > MIN_SQUAD_AFTER_SEIZURE:
		for p in club.players:
			out.append({"kind": "player", "player": p, "value": PlayerValue.estimate(p),
				"label": "a %s" % p.full_name})
	for key in StadiumPanel.UPGRADES:
		var lvl : int = club.upgrades.get(key, 0)
		if lvl <= 0 or (key == "building" and _building_needed(club, lvl)):
			continue
		var data : Dictionary = StadiumPanel.UPGRADES[key]
		out.append({"kind": "level", "key": key, "value": int(data["levels"][lvl - 1]["cost"]),
			"label": "un nivel de %s" % data["label"]})
	for key in StaffData.STAFF:
		var lvl : int = club.upgrades.get(key, 0)
		if lvl <= 0:
			continue
		var data : Dictionary = StaffData.STAFF[key]
		out.append({"kind": "level", "key": key, "value": int(data["levels"][lvl - 1]["cost"]),
			"label": "un nivel de %s" % data["label"]})
	return out

static func _building_needed(club: ClubResource, building_lvl: int) -> bool:
	for key in StadiumPanel.UPGRADES:
		var lvl : int = club.upgrades.get(key, 0)
		if key == "building" or lvl <= 0:
			continue
		var req : Dictionary = StadiumPanel.UPGRADES[key]["levels"][lvl - 1].get("requires", {})
		if int(req.get("building", 0)) >= building_lvl:
			return true
	return false
