class_name RandomEvents

## Rolls whether a random event fires (Hub between matches, or mid-match),
## applies its mechanical effect via RandomEventEffects, and returns Pepito
## Perinola's narrated line — or "" if nothing fired. Callers (hub.gd /
## world.gd) hand the result straight to ClubTrainer.say(). Stateless static
## utility, same calling convention as MoneyFormat/StaffData — no autoload
## needed.

const HUB_TRIGGER_CHANCE := 0.60
const MATCH_TRIGGER_CHANCE := 0.10

static func maybe_trigger_hub_event(club: ClubResource) -> String:
	if club == null or randf() > HUB_TRIGGER_CHANCE:
		return ""
	return _resolve(_pick_weighted(RandomEventPool.HUB_EVENTS), club)

static func maybe_trigger_match_event(club: ClubResource) -> String:
	if club == null or randf() > MATCH_TRIGGER_CHANCE:
		return ""
	return _resolve(_pick_weighted(RandomEventPool.MATCH_EVENTS), club)

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

static func _resolve(event: Dictionary, club: ClubResource) -> String:
	if event.is_empty():
		return ""
	var values := RandomEventEffects.apply(event["effect_id"], club, event.get("effect_params", {}))
	var text : String = event["line_template"]
	for key in values:
		text = text.replace("{%s}" % key, str(values[key]))
	return text
