class_name RandomEventEffects

## Applies a random event's mechanical effect (see RandomEventPool) and
## returns the values needed to fill in its line_template's {placeholders}.
## One static function per effect_id.

static func apply(effect_id: String, club: ClubResource, params: Dictionary) -> Dictionary:
	match effect_id:
		"budget_delta":
			return _budget_delta(club, params)
		"fans_delta":
			return _fans_delta(club, params)
		"suspend_random_player":
			return _suspend_random_player(club, params)
		"remove_random_player":
			return _remove_random_player(club, params)
		"apply_stat_debuff":
			return _apply_stat_debuff(club, params)
	return {}

static func _budget_delta(club: ClubResource, params: Dictionary) -> Dictionary:
	var amount := randi_range(int(params.get("min", 0)), int(params.get("max", 0)))
	club.budget += amount
	return {"amount": MoneyFormat.format(absi(amount))}

static func _fans_delta(club: ClubResource, params: Dictionary) -> Dictionary:
	var amount := randi_range(int(params.get("min", 0)), int(params.get("max", 0)))
	club.fans = maxi(FanEconomy.MIN_FANS, club.fans + amount)
	return {"amount": str(absi(amount))}

## Benches the player immediately (clears any tactic slot they hold) and
## keeps them unavailable for a random number of matches within params'
## min/max — see PlayerResource.unavailable_matches.
static func _suspend_random_player(club: ClubResource, params: Dictionary) -> Dictionary:
	if club.players.is_empty():
		return {"player": "Alguien", "matches": "1"}
	var p : PlayerResource = club.players[randi() % club.players.size()]
	var matches := randi_range(int(params.get("min", 1)), int(params.get("max", 1)))
	p.unavailable_matches += matches
	GameState.clear_player_from_tactics(p)
	return {"player": p.full_name, "matches": str(matches)}

## Applies a temporary all-stats percentage debuff to a random player for a
## random number of matches — unlike _suspend_random_player(), the player
## stays fielded/in their tactic slot the whole time. See
## PlayerResource.add_temporary_modifier()/tick_temporary_modifiers().
static func _apply_stat_debuff(club: ClubResource, params: Dictionary) -> Dictionary:
	if club.players.is_empty():
		return {"player": "Alguien", "pct": "0", "matches": "1"}
	var p : PlayerResource = club.players[randi() % club.players.size()]
	var pct := randi_range(int(params.get("min_pct", 5)), int(params.get("max_pct", 15)))
	var matches := randi_range(int(params.get("min_matches", 1)), int(params.get("max_matches", 1)))
	p.add_temporary_modifier("event_wild_night_out", "Resaca", "all", -float(pct), matches)
	return {"player": p.full_name, "pct": str(pct), "matches": str(matches)}

## Permanently removes a random player from the squad (e.g. an "elected King
## of a small country" departure) — clears them from tactics first so no
## slot keeps a dangling reference, same as a sale/retirement.
static func _remove_random_player(club: ClubResource, _params: Dictionary) -> Dictionary:
	if club.players.is_empty():
		return {"player": "Alguien"}
	var p : PlayerResource = club.players[randi() % club.players.size()]
	GameState.clear_player_from_tactics(p)
	club.players.erase(p)
	return {"player": p.full_name}
