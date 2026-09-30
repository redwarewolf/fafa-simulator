class_name MatchSummaryData

## Builds the Dictionary MatchSummaryPopup.show_result() expects, shared by
## hub.gd's "Simular" flow and world.gd's played-match GAMEOVER so both pull
## that date's cost/income breakdown from GameState.last_day_ledger the same
## way instead of duplicating the lookup.

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
	data["merch_revenue"] = GameState.last_day_ledger.get("merchandise_revenue", 0)
	data["food_revenue"] = GameState.last_day_ledger.get("food_revenue", 0)
	data["wage_cost"] = GameState.last_day_ledger.get("wage_cost", 0)
	data["staff_cost"] = GameState.last_day_ledger.get("staff_upkeep_cost", 0)
	return data
