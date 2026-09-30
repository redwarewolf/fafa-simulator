extends Node

## Club economy simulator: plays out whole careers of money (no matches on
## screen, just results rolled from a win rate) under a set of economy RULES,
## for several spending STRATEGIES and team strengths, and prints how the
## budget behaves. Used to tune the economy the same way batch_match tunes the
## match engine — try numbers in EXPERIMENT, rerun, compare, then move the
## winners into the game's constants.
##
##   "$G" --path . --headless res://tools/economy_sim.tscn -- [--careers 400] [--seasons 3] [--seed 1] [--out user://econ.json]
##
## "game" is built from the live constants (FanEconomy, PlayerWage,
## StaffData, ClubDebt, the stadium panel's UPGRADES, ClubFactory budgets,
## RandomEventPool, GameState.PAY_PERIOD_DAYS), so it reports what the game
## does today. "experiment" is the same with EXPERIMENT's overrides.
## Strategies let staff go (StaffData.DISMISS_SEVERANCE_WEEKS severance) when
## cash runs short, and Tapir seizes assets on a second missed payday, as in
## ClubDebt.
##
## Squads come from the real SquadGenerator/PlayerFactory. Simplifications:
## results are rolled from a fixed win rate per team strength (one tier
## weaker after each promotion, since the squad doesn't improve); a trainer
## adds TRAINER_WIN_PER_LEVEL to it; scout/academy/butcher are costs only
## (their payoff — better players — isn't modelled); the other seven clubs'
## league results are random. Season calendar mirrors SeasonManager: 7-day
## pre-season with 3 friendlies, two 7-matchday legs a week apart, 4-day break.

const StadiumPanel := preload("res://scenes/hub/sections/club/stadium_panel.gd")

const DIVS : Array[String] = ["E", "D", "C", "B", "A"]
const TRAINER_WIN_PER_LEVEL := 0.02
## Base win/draw rates per team strength (the rest are losses).
const STRENGTHS := {
	"weak":   [0.22, 0.26],
	"mid":    [0.36, 0.28],
	"strong": [0.55, 0.25],
}
## After each promotion the same squad faces a tougher league.
const PROMOTION_WIN_DROP := 0.14
## Other clubs' league results (win, draw).
const OTHERS_WD := [0.37, 0.26]

## Purchase priority per strategy — "stand:<key>" or "staff:<key>", bought
## in order (next level of each) whenever cash stays above the reserve.
const STRATEGIES := {
	"frugal": [],
	"starter": ["stand:food_sales", "stand:merchandise_sales", "stand:tribune", "stand:tribune"],
	"stands": ["stand:food_sales", "stand:merchandise_sales", "stand:tribune", "stand:tribune",
		"stand:building", "stand:food_sales", "stand:merchandise_sales", "stand:tribune",
		"stand:food_sales", "stand:merchandise_sales", "stand:building"],
	"staff": ["staff:trainer", "staff:scout", "staff:academy", "staff:trainer", "staff:scout",
		"staff:academy", "staff:butcher", "staff:trainer"],
	"balanced": ["stand:food_sales", "stand:merchandise_sales", "stand:tribune", "staff:trainer",
		"stand:tribune", "stand:building", "stand:food_sales", "stand:merchandise_sales",
		"staff:scout", "staff:trainer", "stand:tribune", "staff:academy"],
}
## Cash kept back when buying: this many weeks of running costs.
const RESERVE_WEEKS := 4.0
## Strategies dismiss staff (one level a week) once cash drops below this
## many weeks of running costs, when the rules allow dismissals.
const DISMISS_BELOW_WEEKS := 2.0
const SEIZED_PLAYER_WIN_DROP := 0.03

## Overrides merged over the game's own rules for an A/B comparison — same
## keys as _game_rules() (money per payday unless named otherwise). Leave
## empty to report only the game as it is; e.g. {"debt_weekly": 4000}.
const EXPERIMENT := {}

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var careers := int(args.get("careers", "400"))
	var seasons := int(args.get("seasons", "3"))
	var base_seed := int(args.get("seed", "1"))
	var out_path : String = args.get("out", "user://econ.json")

	var all_rules := [_game_rules()]
	if not EXPERIMENT.is_empty():
		var experiment := _game_rules()
		experiment.merge(EXPERIMENT, true)
		experiment["name"] = "experiment"
		all_rules.append(experiment)
	var report := {"careers": careers, "seasons": seasons, "results": []}
	for rules : Dictionary in all_rules:
		print("\n══════ RULES: %s  (%d careers × %d seasons each) ══════" % [rules["name"], careers, seasons])
		for strength in STRENGTHS:
			print("\n  team: %s" % strength)
			print("    %-9s %12s %12s %12s  %7s %7s %6s %9s %8s %8s" % ["strategy", "S1 end", "S2 end", "S3 end", "broke%", "wk<0", "promo", "debt S3", "seized", "dismiss"])
			for strategy in STRATEGIES:
				var agg := _run_batch(rules, strength, strategy, careers, seasons, base_seed)
				report["results"].append(agg)
				var ends : Array = agg["season_end_median"]
				print("    %-9s %12s %12s %12s  %6.0f%% %7s %6.2f %9s %8.2f %8.2f" % [strategy,
					_money(ends[0]), _money(ends[1]) if seasons > 1 else "-", _money(ends[2]) if seasons > 2 else "-",
					agg["broke_share"] * 100.0, str(agg["first_broke_week_median"]) if agg["broke_share"] > 0.0 else "-",
					agg["promotions_mean"], _money(agg["debt_left_median"]), agg["seizures_mean"], agg["dismissals_mean"]])
		_print_breakdown(rules, base_seed)

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report))
		f.close()
		print("\nresults written to %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Season-1 money flows (per-career means) for a mid-table team, per strategy.
func _print_breakdown(rules: Dictionary, base_seed: int) -> void:
	print("\n  season 1 money flows, mid team (mean per career):")
	var keys := ["gate", "merch", "food", "sponsor", "tv", "prize", "events", "wages", "staff", "debt", "upgrades", "seized", "severance"]
	var header := "    %-9s" % "strategy"
	for k in keys:
		header += " %9s" % k
	print(header)
	for strategy in STRATEGIES:
		var agg := _run_batch(rules, "mid", strategy, 200, 1, base_seed)
		var line := "    %-9s" % strategy
		for k in keys:
			line += " %9s" % _money(agg["flows_s1"].get(k, 0.0))
		print(line)

func _run_batch(rules: Dictionary, strength: String, strategy: String, careers: int, seasons: int, base_seed: int) -> Dictionary:
	var season_ends : Array = []  # [season] -> Array of cash
	for s in seasons:
		season_ends.append([])
	var weekly : Array = []  # [week] -> Array of cash
	var broke := 0
	var broke_weeks : Array = []
	var promos := 0.0
	var seizures := 0.0
	var dismissals := 0.0
	var debts : Array = []
	var flows_sum := {}
	for c in careers:
		var r := _run_career(rules, strength, strategy, seasons, base_seed + c)
		for s in seasons:
			season_ends[s].append(r["season_end"][s])
		for w in r["weekly"].size():
			if weekly.size() <= w:
				weekly.append([])
			weekly[w].append(r["weekly"][w])
		if r["first_broke_week"] >= 0:
			broke += 1
			broke_weeks.append(r["first_broke_week"])
		promos += r["promotions"]
		seizures += r["seizures"]
		dismissals += r["dismissals"]
		debts.append(r["debt_left"])
		for k in r["flows_s1"]:
			flows_sum[k] = flows_sum.get(k, 0.0) + r["flows_s1"][k]
	var flows := {}
	for k in flows_sum:
		flows[k] = flows_sum[k] / careers
	var season_end_median : Array = []
	for s in seasons:
		season_end_median.append(_pct(season_ends[s], 0.5))
	var weekly_p : Array = []
	for w in weekly.size():
		weekly_p.append([_pct(weekly[w], 0.1), _pct(weekly[w], 0.5), _pct(weekly[w], 0.9)])
	return {
		"rules": rules["name"], "strength": strength, "strategy": strategy,
		"season_end_median": season_end_median,
		"broke_share": float(broke) / careers,
		"first_broke_week_median": int(_pct(broke_weeks, 0.5)) if not broke_weeks.is_empty() else -1,
		"promotions_mean": promos / careers,
		"seizures_mean": seizures / careers,
		"dismissals_mean": dismissals / careers,
		"debt_left_median": _pct(debts, 0.5),
		"weekly_p10_p50_p90": weekly_p,
		"flows_s1": flows,
	}

func _run_career(rules: Dictionary, strength: String, strategy: String, seasons: int, career_seed: int) -> Dictionary:
	_rng.seed = career_seed
	seed(career_seed)  # PlayerFactory rolls on the global RNG
	var div := "E"
	var squad := SquadGenerator.generate_squad(ClubFactory.own_odds_for(div), true)
	var cash : float = rules["start_cash"][div]
	var debt : float = rules.get("debt", 0)
	var fans := FanEconomy.STARTING_FANS
	var levels := {}  # upgrade/staff key -> level
	var plan : Array = STRATEGIES[strategy].duplicate()
	var period : int = rules["period_days"]
	var day := 0
	var promotions := 0
	var weekly : Array = []
	var season_end : Array = []
	var first_broke_week := -1
	var flows := {}
	var base_wd : Array = STRENGTHS[strength]
	var arrears := 0.0
	var strikes := 0
	var seizures := 0
	var dismissals := 0
	var start_squad := squad.size()

	for season in seasons:
		var calendar := _season_calendar()
		var points := 0
		var win_p_base : float = maxf(0.08, base_wd[0] - PROMOTION_WIN_DROP * promotions + TRAINER_WIN_PER_LEVEL * levels.get("trainer", 0))
		var win_p := win_p_base
		var draw_p : float = base_wd[1]
		for entry : String in calendar:
			day += 1
			var f := flows if season == 0 else {}
			# Payday: running costs and passive income for the period.
			if day % period == 0:
				var wages := 0.0
				for p in squad:
					wages += _wage(rules, p)
				cash -= _add(f, "wages", wages)
				var staff := 0.0
				for key in ["trainer", "scout", "academy", "butcher"]:
					var lvl : int = levels.get(key, 0)
					if lvl > 0:
						staff += _staff_upkeep(rules, key, lvl)
				cash -= _add(f, "staff", staff)
				if debt > 0.0 or arrears > 0.0:
					var part : float = minf(debt, rules.get("debt_weekly", 0))
					if cash >= arrears + part:
						cash -= _add(f, "debt", arrears + part)
						debt -= part
						arrears = 0.0
						strikes = 0
					else:
						# Missed: this week's payment joins the arrears plus the
						# late fee. Still behind a week later, Tapir takes an asset.
						debt -= part
						arrears = (arrears + part) * (1.0 + rules.get("late_fee", 0.0))
						strikes += 1
						if strikes >= 2:
							arrears = _seize(arrears, squad, levels, f)
							seizures += 1
							if arrears <= 0.0:
								arrears = 0.0
								strikes = 0
				cash += _add(f, "merch", _passive(rules, "merch", levels.get("merchandise_sales", 0), fans))
				cash += _add(f, "food", _passive(rules, "food", levels.get("food_sales", 0), fans))
				if rules.has("sponsor_base"):
					cash += _add(f, "sponsor", rules["sponsor_base"][div] + rules["sponsor_per_fan"] * fans)
					cash += _add(f, "tv", rules["tv"][div])
			# Hub event, rolled every day.
			cash += _add(f, "events", _hub_event(rules))
			# Match.
			if entry != "":
				# Every player Tapir took leaves a weaker XI.
				win_p = maxf(0.05, win_p_base - SEIZED_PLAYER_WIN_DROP * (start_squad - squad.size()))
				var roll := _rng.randf()
				var outcome := "win" if roll < win_p else ("draw" if roll < win_p + draw_p else "loss")
				if entry.begins_with("league"):
					points += 3 if outcome == "win" else (1 if outcome == "draw" else 0)
				var delta := _fan_delta(div, outcome, fans)
				fans = maxi(FanEconomy.MIN_FANS, fans + delta)
				if entry.ends_with("home"):
					var attendance := mini(int(round(fans * _rng.randf_range(FanEconomy.ATTENDANCE_RATE_MIN, FanEconomy.ATTENDANCE_RATE_MAX))),
						(levels.get("tribune", 0) + 1) * ClubResource.TRIBUNE_CAPACITY_PER_LEVEL)
					cash += _add(f, "gate", attendance * rules["ticket_price"][div])
				# Match event (10%): half pitch invader (fans), half crowd surge (money).
				if _rng.randf() < RandomEvents.MATCH_TRIGGER_CHANCE:
					if _rng.randf() < 0.5:
						fans = maxi(FanEconomy.MIN_FANS, fans - _rng.randi_range(10, 40))
					else:
						cash += _add(f, "events", _rng.randi_range(1000, 4000))
			# Spending decisions once a week.
			if day % 7 == 0:
				var weekly_cost := _weekly_costs(rules, squad, levels)
				var reserve := RESERVE_WEEKS * weekly_cost
				# Short on cash: let the priciest staff member go one level.
				if rules.has("severance_weeks") and cash < DISMISS_BELOW_WEEKS * weekly_cost:
					var worst := ""
					var worst_upkeep := 0.0
					for key in ["trainer", "scout", "academy", "butcher"]:
						if levels.get(key, 0) > 0 and _staff_upkeep(rules, key, levels[key]) > worst_upkeep:
							worst = key
							worst_upkeep = _staff_upkeep(rules, key, levels[key])
					if worst != "":
						cash -= _add(f, "severance", worst_upkeep * rules["severance_weeks"])
						levels[worst] -= 1
						dismissals += 1
				while not plan.is_empty():
					var item : String = plan[0]
					var cost := _next_cost(item, levels)
					if cost < 0:
						plan.pop_front()  # maxed or not buyable
						continue
					if cash - cost < reserve:
						break
					cash -= _add(f, "upgrades", cost)
					var key := item.get_slice(":", 1)
					levels[key] = levels.get(key, 0) + 1
					plan.pop_front()
				weekly.append(cash)
				if cash < 0.0 and first_broke_week < 0:
					first_broke_week = weekly.size()
		# Season end: league position, prize, promotion.
		var position := _league_position(points)
		if rules.has("prize"):
			cash += _add(flows if season == 0 else {}, "prize", rules["prize"][div][position - 1])
		if position == 1 and DIVS.find(div) < DIVS.size() - 1:
			if rules.has("promotion_bonus"):
				cash += _add(flows if season == 0 else {}, "prize", rules["promotion_bonus"][div])
			div = DIVS[DIVS.find(div) + 1]
			promotions += 1
		season_end.append(cash)
	return {"season_end": season_end, "weekly": weekly, "first_broke_week": first_broke_week,
		"promotions": promotions, "debt_left": debt + arrears, "flows_s1": flows,
		"seizures": seizures, "dismissals": dismissals}

## Tapir collects [param owed] like ClubDebt._seize(): the cheapest asset
## worth at least that much — a player (PlayerValue) or the top level of a stadium
## upgrade or staff hire (its purchase price) — keeping the change. If
## nothing covers it, he takes the most valuable asset and the rest stays
## owed. Returns what's still owed.
func _seize(owed: float, squad: Array, levels: Dictionary, f: Dictionary) -> float:
	var candidates : Array = []
	if squad.size() > ClubDebt.MIN_SQUAD_AFTER_SEIZURE:
		for p in squad:
			candidates.append(["player", p, float(PlayerValue.estimate(p))])
	for key in levels:
		var lvl : int = levels[key]
		if lvl <= 0:
			continue
		var table : Array = StadiumPanel.UPGRADES[key]["levels"] if StadiumPanel.UPGRADES.has(key) else StaffData.STAFF[key]["levels"]
		candidates.append(["level", key, float(table[lvl - 1]["cost"])])
	if candidates.is_empty():
		return owed  # nothing left to take
	var covering := candidates.filter(func(c: Array) -> bool: return c[2] >= owed)
	var pick : Array
	if covering.is_empty():
		pick = candidates[0]
		for c in candidates:
			if c[2] > pick[2]:
				pick = c
	else:
		pick = covering[0]
		for c in covering:
			if c[2] < pick[2]:
				pick = c
	_add(f, "seized", pick[2])
	if pick[0] == "player":
		squad.erase(pick[1])
	else:
		levels[pick[1]] -= 1
	return owed - pick[2]

## One entry per day: "" or friendly_/league_ + home/away.
func _season_calendar() -> Array[String]:
	var cal : Array[String] = []
	# Pre-season: 7 days, friendlies every 2 days, alternating home/away.
	for d in 7:
		if d in [1, 3, 5]:
			cal.append("friendly_home" if (d / 2) % 2 == 0 else "friendly_away")
		else:
			cal.append("")
	var home := true
	for leg in 2:
		for round_i in 7:
			cal.append("league_home" if home else "league_away")
			home = not home
			if round_i < 6:
				for d in SeasonManager.DAYS_BETWEEN_MATCHDAYS - 1:
					cal.append("")
		if leg == 0:
			for d in SeasonManager.MID_SEASON_BREAK_LENGTH + 1:
				cal.append("")
	return cal

func _league_position(points: int) -> int:
	var above := 0
	for c in 7:
		var pts := 0
		for m in 14:
			var r := _rng.randf()
			pts += 3 if r < OTHERS_WD[0] else (1 if r < OTHERS_WD[0] + OTHERS_WD[1] else 0)
		if pts > points or (pts == points and _rng.randf() < 0.5):
			above += 1
	return above + 1

func _fan_delta(div: String, outcome: String, fans: int) -> int:
	# Same as FanEconomy.roll_fan_delta, on this sim's RNG.
	var mult : float = FanEconomy.DIVISION_FAN_MULTIPLIER.get(div, 1.0)
	var lo := FanEconomy.DRAW_FANS_MIN
	var hi := FanEconomy.DRAW_FANS_MAX
	if outcome == "win":
		lo = FanEconomy.WIN_FANS_MIN
		hi = FanEconomy.WIN_FANS_MAX
	elif outcome == "loss":
		lo = FanEconomy.LOSS_FANS_MIN
		hi = FanEconomy.LOSS_FANS_MAX
	var delta := int(round(_rng.randi_range(lo, hi) * mult))
	if delta < 0:
		delta = int(round(delta * FanEconomy._loss_dampen_multiplier(fans)))
	return delta

func _wage(rules: Dictionary, p: PlayerResource) -> float:
	if rules.has("wage_base"):
		return rules["wage_base"][p.quality] * (p.overall() / 60.0)
	return PlayerWage.estimate(p)

func _staff_upkeep(rules: Dictionary, key: String, lvl: int) -> float:
	if rules.has("staff_upkeep"):
		return rules["staff_upkeep"][key][lvl - 1]
	return StaffData.STAFF[key]["levels"][lvl - 1]["weekly"]

func _passive(rules: Dictionary, kind: String, lvl: int, fans: int) -> float:
	if lvl <= 0:
		return 0.0
	var rate := 0.0
	if kind == "merch":
		rate = _rng.randf_range(FanEconomy.MERCH_RATE_MIN, FanEconomy.MERCH_RATE_MAX)
		var prices : Dictionary = rules.get("merch_price", FanEconomy.MERCH_PRICE_BY_LEVEL)
		return round(fans * rate) * prices[lvl]
	rate = _rng.randf_range(FanEconomy.FOOD_RATE_MIN, FanEconomy.FOOD_RATE_MAX)
	var fprices : Dictionary = rules.get("food_price", FanEconomy.FOOD_PRICE_BY_LEVEL)
	return round(fans * rate) * fprices[lvl]

func _hub_event(rules: Dictionary) -> float:
	if _rng.randf() > rules["hub_event_chance"]:
		return 0.0
	var events : Array = rules["hub_money_events"]
	var total : float = rules["hub_other_weight"]
	for e in events:
		total += e[0]
	var roll := _rng.randf() * total
	for e in events:
		roll -= e[0]
		if roll <= 0.0:
			return _rng.randi_range(e[1], e[2])
	return 0.0  # a non-money event (e.g. the night-out debuff)

func _weekly_costs(rules: Dictionary, squad: Array, levels: Dictionary) -> float:
	var per_period := 0.0
	for p in squad:
		per_period += _wage(rules, p)
	for key in ["trainer", "scout", "academy", "butcher"]:
		if levels.get(key, 0) > 0:
			per_period += _staff_upkeep(rules, key, levels[key])
	per_period += rules.get("debt_weekly", 0)
	return per_period * 7.0 / rules["period_days"]

## Price of the next level of a "stand:key"/"staff:key" item, or -1 if maxed
## or its requirement (Edificio level 1 for the upper stand levels) isn't met.
func _next_cost(item: String, levels: Dictionary) -> int:
	var kind := item.get_slice(":", 0)
	var key := item.get_slice(":", 1)
	var lvl : int = levels.get(key, 0)
	var table : Array = StadiumPanel.UPGRADES[key]["levels"] if kind == "stand" else StaffData.STAFF[key]["levels"]
	if lvl >= table.size():
		return -1
	var entry : Dictionary = table[lvl]
	for req in entry.get("requires", {}):
		if levels.get(req, 0) < entry["requires"][req]:
			return -1
	return entry["cost"]

## The economy exactly as the game runs it, read from the live constants.
func _game_rules() -> Dictionary:
	var hub_money := []
	var other := 0.0
	for e in RandomEventPool.HUB_EVENTS:
		if e["effect_id"] == "budget_delta":
			hub_money.append([e["weight"], e["effect_params"]["min"], e["effect_params"]["max"]])
		else:
			other += e["weight"]
	return {
		"name": "game",
		"period_days": GameState.PAY_PERIOD_DAYS,
		"start_cash": ClubFactory.STARTING_BUDGET,
		"debt": ClubDebt.STARTING_DEBT,
		"debt_weekly": ClubDebt.WEEKLY_PAYMENT,
		"late_fee": ClubDebt.LATE_FEE,
		"severance_weeks": StaffData.DISMISS_SEVERANCE_WEEKS,
		"ticket_price": FanEconomy.TICKET_PRICE_PER_DIVISION,
		"sponsor_base": FanEconomy.SPONSOR_BASE_PER_DIVISION,
		"sponsor_per_fan": FanEconomy.SPONSOR_PER_FAN,
		"tv": FanEconomy.TV_PER_DIVISION,
		"prize": FanEconomy.PRIZE_BY_POSITION,
		"promotion_bonus": FanEconomy.PROMOTION_BONUS,
		"hub_event_chance": RandomEvents.HUB_TRIGGER_CHANCE,
		"hub_money_events": hub_money,
		"hub_other_weight": other,
	}

func _add(flows: Dictionary, key: String, amount: float) -> float:
	flows[key] = flows.get(key, 0.0) + amount
	return amount

func _pct(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return v[clampi(int(q * (v.size() - 1)), 0, v.size() - 1)]

func _money(v: float) -> String:
	var sign := "-" if v < 0 else ""
	var a := absf(v)
	if a >= 1_000_000:
		return "%s$%.2fM" % [sign, a / 1_000_000.0]
	if a >= 1000:
		return "%s$%.0fk" % [sign, a / 1000.0]
	return "%s$%.0f" % [sign, a]

func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		if args[i].begins_with("--") and i + 1 < args.size():
			out[args[i].substr(2)] = args[i + 1]
			i += 2
		else:
			i += 1
	return out
