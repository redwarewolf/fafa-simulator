class_name MatchSummaryData

## Builds the Dictionary MatchSummaryPopup.show_result() expects, shared by
## hub.gd's "Simular" flow and world.gd's played-match GAMEOVER. Adds the
## weekly payday's lines (GameState.last_payday_ledger) only when that payday
## ran on this match day — otherwise the summary shows just the gate.

static func build(own_name: String, opp_name: String, own_score: int, opp_score: int,
		scorers: Array, simulated: bool, match_result: Dictionary) -> Dictionary:
	var data := {
		"own_name": own_name,
		"opp_name": opp_name,
		"own_score": own_score,
		"opp_score": opp_score,
		"scorers": scorers,
		"simulated": simulated,
	}
	if match_result.is_empty():
		data["show_finance"] = false
		return data
	data["show_finance"] = true
	for key in ["position_before", "position_after", "other_results"]:
		if match_result.has(key):
			data[key] = match_result[key]
	data["fans_delta"] = match_result.get("fans_delta", 0)
	data["fans_now"] = GameState.player_club.fans if GameState.player_club != null else 0
	data["ticket_revenue"] = match_result.get("ticket_revenue", 0)
	data["attendance"] = match_result.get("attendance", 0)
	data["bribe_cost"] = match_result.get("bribe_cost", 0)
	data["scandal_fine"] = match_result.get("scandal_fine", 0)
	if GameState.payday_today:
		var ledger := GameState.last_payday_ledger
		data["merch_revenue"] = ledger.get("merchandise_revenue", 0)
		data["food_revenue"] = ledger.get("food_revenue", 0)
		data["sponsor_revenue"] = ledger.get("sponsor_revenue", 0)
		data["tv_revenue"] = ledger.get("tv_revenue", 0)
		data["wage_cost"] = ledger.get("wage_cost", 0)
		data["staff_cost"] = ledger.get("staff_upkeep_cost", 0)
		data["debt_payment"] = ledger.get("debt_payment", 0)
		data["barra_cost"] = ledger.get("barra_cost", 0)
		data["afa_fine"] = ledger.get("afa_fine", 0)
	return data
