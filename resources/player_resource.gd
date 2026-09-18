class_name PlayerResource
extends Resource

enum Quality { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

# Identity
@export var full_name : String
@export var skin_color : Player.SkinColor
@export var hair_color : Player.HairColor
@export var role : Positions.Role
@export var age : int
@export var quality : Quality

# Base stats (1-100)
@export var pac : int  # Pace
@export var sho : int  # Shooting
@export var pas : int  # Passing
@export var dri : int  # Dribbling
@export var def : int  # Defending
@export var phy : int  # Physicality

# Special-case cosmetics/behaviour. "" / "default" mean an ordinary player —
# see SpecialPlayerTypes and BodyTypes for the registries these key into.
@export var body_type : String = "default"
@export var special_type : String = ""

## Frame index into this player's body-type portrait_frames (see BodyTypes) —
## rolled once and cached via get_portrait_frame() so the same player always
## shows the same pose instead of reshuffling every time their card is drawn.
## -1 means "not rolled yet".
var portrait_frame : int = -1

# Hidden runtime attributes (not saved to JSON, managed at runtime)
var stamina : float = 100.0
var morale : float = 100.0
## Personality trait, not a scoutable stat: how willing this player is to pass
## to a better-placed teammate rather than shoot/dribble themselves. 1-100,
## rolled once per instance so otherwise-identical players still vary — see
## OnBallUtility.pass_score/decide, the only readers of this field.
var teamplay : int = randi_range(20, 80)

## Matches left before this player can be fielded again — set by random
## events (e.g. a suspension), decremented once per played match in
## SeasonManager.report_player_match_result(). Unlike stamina/morale, this
## IS persisted (see to_dict/from_dict) since a suspension must survive a
## save/reload. Enforced in field_overlay.gd/squad_section.gd, which refuse
## to field a player while this is > 0.
var unavailable_matches : int = 0

## General-purpose stat modifiers — permanent boosts (youth academy tenure,
## Training Facility sessions) and temporary debuffs (random events). Each
## entry: {"id": String, "label": String, "stat": String, "pct": float,
## "permanent": bool, "matches_remaining": int}, where "stat" is "all" or one
## of pac/sho/pas/dri/def/phy. Persisted — see to_dict/from_dict. Use
## add_permanent_modifier()/add_temporary_modifier() to add entries rather
## than appending directly, so repeated permanent grants from the same source
## accumulate into one entry instead of piling up duplicates.
var modifiers : Array[Dictionary] = []

## Lifetime count of Training Facility sessions spent on this player, capped
## by StaffData.STAFF["trainer"]["levels"][lvl-1]["max_sessions"]. Kept
## separate from `modifiers` so the session-cap check doesn't need to
## interpret the modifier list.
var training_sessions_used : int = 0

func _init(
	p_name: String,
	p_skin: Player.SkinColor,
	p_hair: Player.HairColor,
	p_role: Positions.Role,
	p_age: int,
	p_quality: Quality,
	p_pac: int, p_sho: int, p_pas: int,
	p_dri: int, p_def: int, p_phy: int,
	p_body_type: String = "default",
	p_special_type: String = "",
	p_portrait_frame: int = -1
) -> void:
	full_name = p_name
	skin_color = p_skin
	hair_color = p_hair
	role = p_role
	age = p_age
	quality = p_quality
	pac = p_pac
	sho = p_sho
	pas = p_pas
	dri = p_dri
	def = p_def
	phy = p_phy
	body_type = p_body_type
	special_type = p_special_type
	portrait_frame = p_portrait_frame
	if special_type != "" and SpecialPlayerTypes.DATA.has(special_type):
		_apply_special_type_overrides()

## Special types are the source of truth for their own stats/quality/role/body
## — this way ANY construction path (JSON, factory, a future generator) that
## sets special_type gets a consistent player without having to also remember
## to zero every stat by hand.
func _apply_special_type_overrides() -> void:
	var d : Dictionary = SpecialPlayerTypes.DATA[special_type]
	quality = d.get("forced_quality", quality)
	if d.has("forced_stats"):
		var s : int = d["forced_stats"]
		pac = s; sho = s; pas = s; dri = s; def = s; phy = s
	role = d.get("forced_role", role)
	body_type = d.get("body_type", body_type)

## Weighted by the player POSITION, not by their behaviour group — the weights
## table lives in Positions so a centre back and a full back can be rated
## differently later without touching this file. Uses effective (modified)
## stats, not raw fields, so a boosted/debuffed player's OVR — and anything
## derived from it (wage, market value, squad overall, AI matchmaking) —
## reflects modifiers automatically.
func overall() -> int:
	var w : Array = Positions.weights(role)
	return int(
		get_effective_stat("pac") * w[0] + get_effective_stat("sho") * w[1] +
		get_effective_stat("pas") * w[2] + get_effective_stat("dri") * w[3] +
		get_effective_stat("def") * w[4] + get_effective_stat("phy") * w[5]
	)

## Sums every modifier that applies to [param stat_key] (scoped "all" or that
## exact stat) into one signed percent.
func get_modifier_pct(stat_key: String) -> float:
	var total := 0.0
	for m : Dictionary in modifiers:
		if m["stat"] == "all" or m["stat"] == stat_key:
			total += float(m["pct"])
	return total

## The stat actually used in gameplay/display: base stat plus every modifier's
## percent applied ONCE, additively — three +6% modifiers make +18%, not a
## compounding 1.06^3. Clamped 1-99 to match the UI's bar scale.
func get_effective_stat(stat_key: String) -> int:
	var base : int = int(get(stat_key))
	return clampi(roundi(base * (1.0 + get_modifier_pct(stat_key) / 100.0)), 1, 99)

## Same as get_effective_stat(), plus one more additive percent on top — the
## positional aptitude buff/debuff for whatever slot this player was actually
## fielded in (see Positions.aptitude_stat_pct). Kept out of get_modifier_pct/
## modifiers since it's not a persisted trait of the player, just a per-match
## consequence of where the manager put them this time.
func get_effective_stat_for_role(stat_key: String, role_aptitude_pct: float) -> int:
	var base : int = int(get(stat_key))
	var pct := get_modifier_pct(stat_key) + role_aptitude_pct
	return clampi(roundi(base * (1.0 + pct / 100.0)), 1, 99)

## Grants a PERMANENT modifier from [param id] — if this source already has an
## entry, its percent is bumped (so e.g. a 2nd year in the academy or a 2nd
## training session on the same stat accumulates into one badge) rather than
## piling up duplicate entries.
func add_permanent_modifier(id: String, label: String, stat: String, pct: float) -> void:
	for m : Dictionary in modifiers:
		if m["permanent"] and m["id"] == id:
			m["pct"] = float(m["pct"]) + pct
			m["label"] = label
			return
	modifiers.append({
		"id": id, "label": label, "stat": stat, "pct": pct,
		"permanent": true, "matches_remaining": 0,
	})

## Adds a TEMPORARY modifier that expires after [param matches] played
## matches (see tick_temporary_modifiers()). Always appended as a new entry —
## unlike permanent grants, simultaneous debuffs from separate event rolls
## should expire independently rather than merging.
func add_temporary_modifier(id: String, label: String, stat: String, pct: float, matches: int) -> void:
	modifiers.append({
		"id": id, "label": label, "stat": stat, "pct": pct,
		"permanent": false, "matches_remaining": matches,
	})

## Decrements every temporary modifier's remaining-match count by one and
## prunes any that just expired. Called once per played match — see
## SeasonManager.report_player_match_result(), same cadence as
## unavailable_matches.
func tick_temporary_modifiers() -> void:
	for i in range(modifiers.size() - 1, -1, -1):
		var m : Dictionary = modifiers[i]
		if m["permanent"]:
			continue
		m["matches_remaining"] = int(m["matches_remaining"]) - 1
		if m["matches_remaining"] <= 0:
			modifiers.remove_at(i)

func quality_label() -> String:
	match quality:
		Quality.COMMON:    return "Común"
		Quality.UNCOMMON:  return "Poco Común"
		Quality.RARE:      return "Raro"
		Quality.EPIC:      return "Épico"
		Quality.LEGENDARY: return "Legendario"
		_:                 return "Desconocido"

## Rolls this player's portrait pose on first call and caches it, so every
## later call (a different screen, a redraw) returns the same frame.
func get_portrait_frame() -> int:
	if portrait_frame < 0:
		portrait_frame = BodyTypes.roll_portrait_frame(body_type)
	return portrait_frame

## Serializes every field save files persist. portrait_frame is included so
## a reloaded player keeps the same rolled pose instead of reshuffling.
func to_dict() -> Dictionary:
	return {
		"full_name": full_name,
		"skin_color": skin_color,
		"hair_color": hair_color,
		"role": Positions.key(role),
		"age": age,
		"quality": quality,
		"pac": pac, "sho": sho, "pas": pas,
		"dri": dri, "def": def, "phy": phy,
		"body_type": body_type, "special_type": special_type,
		"portrait_frame": portrait_frame,
		"unavailable_matches": unavailable_matches,
		"modifiers": modifiers,
		"training_sessions_used": training_sessions_used,
	}

static func from_dict(d: Dictionary) -> PlayerResource:
	var p := PlayerResource.new(
		d["full_name"],
		d["skin_color"] as Player.SkinColor,
		d.get("hair_color", 0) as Player.HairColor,
		Positions.parse(d["role"]),
		d["age"],
		d["quality"] as Quality,
		d["pac"], d["sho"], d["pas"],
		d["dri"], d["def"], d["phy"],
		d.get("body_type", "default"),
		d.get("special_type", ""),
		int(d.get("portrait_frame", -1))
	)
	p.unavailable_matches = int(d.get("unavailable_matches", 0))
	for m : Dictionary in d.get("modifiers", []) as Array:
		p.modifiers.append(m)
	p.training_sessions_used = int(d.get("training_sessions_used", 0))
	return p
