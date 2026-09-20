class_name YouthEvents

## Rolls/builds narrated youth-academy sign-up events — mirrors
## utils/random_events.gd's split from its own data pool, but returns a built
## kid (PlayerResource) rather than just a line, since the caller
## (scenes/ui/youth_signup_flow.gd) needs the actual player to show a card and
## possibly add to the roster. Stateless static utility, same calling
## convention as RandomEvents/StaffData — no autoload needed.
##
## Picking an event is two-stage: first a CATEGORY (YouthEventPool.CATEGORIES,
## weighted 45/45/10 for cash/free/prodigy), then a line within that category
## (YouthEventPool.SIGNUP_EVENTS, weighted per entry) — see _pick_category()/
## _pick_weighted(). The category also decides the kid's quality band
## (relative to the club's own division "tier"), whether accepting reserves
## his spot, and which side pays the fee — see YouthEventPool's own doc
## comment for the exact mechanics.

const DAILY_SIGNUP_CHANCE := 0.8

## Always the guaranteed free_signup entry, no roll — for the guaranteed
## first event fired the moment the academy is first hired (see
## staff_panel.gd).
static func first_signup_event(club: ClubResource) -> Dictionary:
	for e in YouthEventPool.SIGNUP_EVENTS:
		if e["id"] == YouthEventPool.FIRST_EVENT_ID:
			return _build(e, _tier_index_for(club))
	return {}

## Rolled once per day advanced, gated on the academy actually being hired.
static func maybe_daily_signup(club: ClubResource) -> Dictionary:
	if club == null or int(club.upgrades.get("academy", 0)) <= 0:
		return {}
	if randf() > DAILY_SIGNUP_CHANCE:
		return {}
	var category := _pick_category()
	var pool : Array = YouthEventPool.SIGNUP_EVENTS.filter(
		func(e: Dictionary) -> bool: return e["category"] == category)
	return _build(_pick_weighted(pool), _tier_index_for(club))

static func _pick_category() -> String:
	var total := 0.0
	for c : Dictionary in YouthEventPool.CATEGORIES.values():
		total += float(c["weight"])
	var roll := randf() * total
	for key in YouthEventPool.CATEGORIES:
		roll -= float(YouthEventPool.CATEGORIES[key]["weight"])
		if roll <= 0.0:
			return key
	return YouthEventPool.CATEGORIES.keys()[-1]

static func _pick_weighted(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	for e in pool:
		total += float(e["weight"])
	var roll := randf() * total
	for e in pool:
		roll -= float(e["weight"])
		if roll <= 0.0:
			return e
	return pool[pool.size() - 1]

## The club's own division mapped onto PlayerResource.Quality by index —
## ClubFactory.DIVISION_ORDER runs lowest-to-highest ("E".."A") the same way
## Quality runs COMMON..LEGENDARY, so a club's division slots directly onto a
## baseline quality tier (clamped to [COMMON, LEGENDARY]; an unrecognized/
## below-"E" division — used in examples as a hypothetical "F" — clamps down
## to COMMON, same as being in the lowest real division).
static func _tier_index_for(club: ClubResource) -> int:
	return clampi(ClubFactory.DIVISION_ORDER.find(club.division), 0, PlayerResource.Quality.LEGENDARY)

## Returns {kid: PlayerResource, line: String, fee_amount: int, fee_direction:
## String, reserved: bool}.
static func _build(event: Dictionary, tier: int) -> Dictionary:
	var cat : Dictionary = YouthEventPool.CATEGORIES[event["category"]]

	var kid : PlayerResource
	if event["kid"] == "special":
		kid = _build_special_kid(event)
	else:
		var span : Array = cat["quality_span"]
		var lo := clampi(tier + int(span[0]), 0, PlayerResource.Quality.LEGENDARY)
		var hi := clampi(tier + int(span[1]), 0, PlayerResource.Quality.LEGENDARY)
		var quality : PlayerResource.Quality = randi_range(lo, hi) as PlayerResource.Quality
		kid = YouthAcademy.generate_youth_player_with_quality(quality)

	var fee_amount := 0
	if event.get("fee") != null:
		var f : Dictionary = event["fee"]
		fee_amount = randi_range(int(f["min"]), int(f["max"]))

	var line : String = event["line_template"]
	line = line.replace("{player}", kid.full_name).replace("{amount}", str(fee_amount))
	return {
		"kid": kid, "line": line, "fee_amount": fee_amount,
		"fee_direction": cat["fee_direction"], "reserved": cat["reserved"],
	}

## Special-type "kids" (currently only the joke "cone" archetype) skip
## PlayerFactory entirely — PlayerResource._init applies
## SpecialPlayerTypes.DATA's overrides for quality/stats/role/body_type
## automatically once special_type is set, so no extra plumbing is needed here
## beyond flagging him as a youth prospect like any other academy kid.
static func _build_special_kid(event: Dictionary) -> PlayerResource:
	var age := randi_range(YouthAcademy.MIN_AGE, YouthAcademy.MAX_AGE)
	var p := PlayerResource.new(
		event.get("special_name", "???"),
		Player.SkinColor.LIGHT, Player.HairColor.BLACK,
		Positions.Role.CB, age, PlayerResource.Quality.COMMON,
		0, 0, 0, 0, 0, 0, "default", event["special_type"])
	p.is_youth_prospect = true
	return p
