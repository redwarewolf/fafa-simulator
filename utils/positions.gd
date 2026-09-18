class_name Positions

## Single source of truth for playing positions.
##
## `const ROLE_NAMES := ["GK", "DEF", "MID", "FWD"]` used to be copy-pasted in
## market_section.gd, tournament_section.gd and player_card.gd, plus a fourth
## copy as a dictionary inside player.gd — every one of them indexing by raw
## enum ordinal, so widening the four roles into ten would have broken in four
## places at once. Anything position-related belongs in this table instead.

## Playing position. Ordered back-to-front and left-to-right within a line, so
## sorting a roster by role already groups it the way the pitch reads.
enum Role { GK, LB, CB, RB, CDM, LM, CM, RM, CAM, LW, ST, RW }

## Which RoleAI subclass drives a position. The AI implements four
## behaviours; the ten positions map onto them and differ by anchor, roam and
## stat weighting — not by class.
enum Group { GOALIE, DEFENSE, MIDFIELD, OFFENSE }

## How well a player fits the slot they were dropped into.
enum Aptitude { NATURAL, SECONDARY, OUT_OF_POSITION }

## Per-position data.
##   key      — stable identifier used in the club JSON and in save files.
##              Never serialise the enum ordinal: that is exactly what made
##              widening the roles a breaking change.
##   label    — badge text
##   title    — full name
##   group    — behaviour class
##   color    — badge and pitch-disc colour
##   weights  — overall() weighting: [pac, sho, pas, dri, def, phy].
##              Still one set per GROUP, so no player's rating moves; they are
##              per-position rows so they can diverge later without a refactor.
##   roam     — depth bands this position ranges behind / ahead of its tactic
##              anchor. A full back covers ground no other outfielder does:
##              one band back to defend, four forward to overlap.
##   flank    — holds its own touchline instead of drifting to the ball's row.
##   also     — positions this player fills without being out of position
const DATA : Dictionary = {
	Role.GK: {
		"key": "GK", "label": "GK", "title": "Goalkeeper",
		"group": Group.GOALIE, "color": Color("f2c94c"),
		"weights": [0.10, 0.05, 0.10, 0.10, 0.40, 0.25],
		"roam": Vector2i(0, 0), "flank": false, "also": [],
	},
	Role.LB: {
		"key": "LB", "label": "LB", "title": "Left Back",
		"group": Group.DEFENSE, "color": Color("4a9be8"),
		"weights": [0.15, 0.05, 0.15, 0.10, 0.35, 0.20],
		"roam": Vector2i(1, 4), "flank": true, "also": [Role.CB, Role.LW],
	},
	Role.CB: {
		"key": "CB", "label": "CB", "title": "Centre Back",
		"group": Group.DEFENSE, "color": Color("4a9be8"),
		"weights": [0.15, 0.05, 0.15, 0.10, 0.35, 0.20],
		"roam": Vector2i(1, 1), "flank": false, "also": [Role.LB, Role.RB],
	},
	Role.RB: {
		"key": "RB", "label": "RB", "title": "Right Back",
		"group": Group.DEFENSE, "color": Color("4a9be8"),
		"weights": [0.15, 0.05, 0.15, 0.10, 0.35, 0.20],
		"roam": Vector2i(1, 4), "flank": true, "also": [Role.CB, Role.RW],
	},
	Role.CDM: {
		"key": "CDM", "label": "CDM", "title": "Defensive Midfielder",
		"group": Group.MIDFIELD, "color": Color("5fcf6b"),
		"weights": [0.15, 0.15, 0.25, 0.20, 0.15, 0.10],
		"roam": Vector2i(1, 2), "flank": false, "also": [Role.CM, Role.CB],
	},
	Role.LM: {
		"key": "LM", "label": "LM", "title": "Left Midfielder",
		"group": Group.MIDFIELD, "color": Color("5fcf6b"),
		"weights": [0.15, 0.15, 0.25, 0.20, 0.15, 0.10],
		"roam": Vector2i(2, 3), "flank": true, "also": [Role.CM, Role.LW, Role.LB],
	},
	Role.CM: {
		"key": "CM", "label": "CM", "title": "Centre Midfielder",
		"group": Group.MIDFIELD, "color": Color("5fcf6b"),
		"weights": [0.15, 0.15, 0.25, 0.20, 0.15, 0.10],
		"roam": Vector2i(2, 2), "flank": false, "also": [Role.CDM, Role.CAM, Role.LM, Role.RM],
	},
	Role.RM: {
		"key": "RM", "label": "RM", "title": "Right Midfielder",
		"group": Group.MIDFIELD, "color": Color("5fcf6b"),
		"weights": [0.15, 0.15, 0.25, 0.20, 0.15, 0.10],
		"roam": Vector2i(2, 3), "flank": true, "also": [Role.CM, Role.RW, Role.RB],
	},
	Role.CAM: {
		"key": "CAM", "label": "CAM", "title": "Attacking Midfielder",
		"group": Group.MIDFIELD, "color": Color("5fcf6b"),
		"weights": [0.15, 0.15, 0.25, 0.20, 0.15, 0.10],
		"roam": Vector2i(2, 2), "flank": false, "also": [Role.CM, Role.LW, Role.RW],
	},
	Role.LW: {
		"key": "LW", "label": "LW", "title": "Left Winger",
		"group": Group.OFFENSE, "color": Color("e8544a"),
		"weights": [0.25, 0.30, 0.15, 0.20, 0.05, 0.05],
		"roam": Vector2i(3, 2), "flank": true, "also": [Role.ST, Role.CAM, Role.LM],
	},
	Role.ST: {
		"key": "ST", "label": "ST", "title": "Striker",
		"group": Group.OFFENSE, "color": Color("e8544a"),
		"weights": [0.25, 0.30, 0.15, 0.20, 0.05, 0.05],
		"roam": Vector2i(2, 2), "flank": false, "also": [Role.LW, Role.RW],
	},
	Role.RW: {
		"key": "RW", "label": "RW", "title": "Right Winger",
		"group": Group.OFFENSE, "color": Color("e8544a"),
		"weights": [0.25, 0.30, 0.15, 0.20, 0.05, 0.05],
		"roam": Vector2i(3, 2), "flank": true, "also": [Role.ST, Role.CAM, Role.RM],
	},
}

# ── Lookups ───────────────────────────────────────────────────────────────────

static func label(role: Role) -> String:
	return DATA[role]["label"]

static func title(role: Role) -> String:
	return DATA[role]["title"]

static func group(role: Role) -> Group:
	return DATA[role]["group"]

static func color(role: Role) -> Color:
	return DATA[role]["color"]

## Text colour that stays readable on top of this position's badge colour.
static func ink_on(role: Role) -> Color:
	return Color("0c1b20") if color(role).get_luminance() > 0.5 else Color.WHITE

static func weights(role: Role) -> Array:
	return DATA[role]["weights"]

## x = depth bands the player drops behind their anchor, y = bands they push
## ahead of it. Consumed by RoleAI once anchors replace spawn positions.
static func roam(role: Role) -> Vector2i:
	return DATA[role]["roam"]

## True when the player should hold their touchline rather than follow the
## ball's row across the pitch.
static func holds_flank(role: Role) -> bool:
	return DATA[role]["flank"]

## How well [param player_role] covers a slot asking for [param slot_role].
static func aptitude(player_role: Role, slot_role: Role) -> Aptitude:
	if player_role == slot_role:
		return Aptitude.NATURAL
	if slot_role in DATA[player_role]["also"]:
		return Aptitude.SECONDARY
	return Aptitude.OUT_OF_POSITION

## Signed percent applied to a fielded player's match stats for how well their
## own position covers the slot they were dropped into — a natural fit is
## rewarded, a covered-but-not-ideal slot is neutral, and a genuine
## out-of-position deployment (e.g. an outfielder filling in for a missing
## keeper) costs a bit. Deliberately small (±5%) since this represents a
## manager's emergency reshuffle, not a wall a squad can't work around.
static func aptitude_stat_pct(apt: Aptitude) -> float:
	match apt:
		Aptitude.NATURAL:    return 5.0
		Aptitude.SECONDARY:  return 0.0
		Aptitude.OUT_OF_POSITION: return -5.0
	return 0.0

# ── Serialisation ─────────────────────────────────────────────────────────────

static func key(role: Role) -> String:
	return DATA[role]["key"]

static func from_key(k: String) -> Role:
	var wanted := k.strip_edges().to_upper()
	for role in DATA:
		if DATA[role]["key"] == wanted:
			return role
	push_warning("Positions: unknown position key '%s', falling back to CM" % k)
	return Role.CM

## Reads a role out of JSON. Accepts the current string key, and the raw
## ordinal that club files and tactic saves used before the split.
static func parse(value: Variant) -> Role:
	if value is String:
		return from_key(value)
	# Club files and tactic saves written before the split stored the four old
	# roles as raw enum ordinals: 0 goalie, 1 defence, 2 midfield, 3 attack.
	match int(value):
		0: return Role.GK
		1: return Role.CB
		2: return Role.CM
		3: return Role.ST
	push_warning("Positions: unreadable role %s, falling back to CM" % [value])
	return Role.CM
