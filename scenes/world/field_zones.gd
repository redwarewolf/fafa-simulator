class_name FieldZones
extends Node2D

enum Zone {
	NONE,
	# Left half — ordered from own goal outward
	GOALIE_LEFT,
	LEFT_DEFENSE_TOP,
	LEFT_DEFENSE_BOT,
	LEFT_MID_TOP,
	LEFT_MID_MID,
	LEFT_MID_BOT,
	LEFT_CENTER_TOP,
	LEFT_CENTER_MID,
	LEFT_CENTER_BOT,
	# Right half — mirror of left, ordered from own goal outward
	GOALIE_RIGHT,
	RIGHT_DEFENSE_TOP,
	RIGHT_DEFENSE_BOT,
	RIGHT_MID_TOP,
	RIGHT_MID_MID,
	RIGHT_MID_BOT,
	RIGHT_CENTER_TOP,
	RIGHT_CENTER_MID,
	RIGHT_CENTER_BOT,
}

const LEFT_ZONES: Array = [
	Zone.GOALIE_LEFT,
	Zone.LEFT_DEFENSE_TOP, Zone.LEFT_DEFENSE_BOT,
	Zone.LEFT_MID_TOP, Zone.LEFT_MID_MID, Zone.LEFT_MID_BOT,
	Zone.LEFT_CENTER_TOP, Zone.LEFT_CENTER_MID, Zone.LEFT_CENTER_BOT,
]

const RIGHT_ZONES: Array = [
	Zone.GOALIE_RIGHT,
	Zone.RIGHT_DEFENSE_TOP, Zone.RIGHT_DEFENSE_BOT,
	Zone.RIGHT_MID_TOP, Zone.RIGHT_MID_MID, Zone.RIGHT_MID_BOT,
	Zone.RIGHT_CENTER_TOP, Zone.RIGHT_CENTER_MID, Zone.RIGHT_CENTER_BOT,
]

# Maps a zone to its Area2D node name
const ZONE_NODE_NAMES: Dictionary = {
	Zone.GOALIE_LEFT:       "GoalieLeft",
	Zone.LEFT_DEFENSE_TOP:  "LeftFieldTopLeft",
	Zone.LEFT_DEFENSE_BOT:  "LeftFieldBottomLeft",
	Zone.LEFT_MID_TOP:      "LeftFieldMidTop",
	Zone.LEFT_MID_MID:      "LeftFieldMid",
	Zone.LEFT_MID_BOT:      "LeftFieldMidBottom",
	Zone.LEFT_CENTER_TOP:   "LeftFieldMidTopRight",
	Zone.LEFT_CENTER_MID:   "LeftFieldMidRight",
	Zone.LEFT_CENTER_BOT:   "LeftFieldMidRight2",
	Zone.GOALIE_RIGHT:      "GoalieRight",
	Zone.RIGHT_DEFENSE_TOP: "RightFieldTopRight",
	Zone.RIGHT_DEFENSE_BOT: "RightFieldBottomRight",
	Zone.RIGHT_MID_TOP:     "RightFieldMidTop",
	Zone.RIGHT_MID_MID:     "RightFieldMid",
	Zone.RIGHT_MID_BOT:     "RightFieldMidBottom",
	Zone.RIGHT_CENTER_TOP:  "RightFieldMidTopLeft",
	Zone.RIGHT_CENTER_MID:  "RightFieldMidLeft",
	Zone.RIGHT_CENTER_BOT:  "RightFieldMidLeft2",
}

## Vertical row per zone: -1=top, 0=mid, 1=bot
const ZONE_ROW: Dictionary = {
	Zone.NONE: 0,
	Zone.GOALIE_LEFT: 0,
	Zone.LEFT_DEFENSE_TOP: -1,  Zone.LEFT_DEFENSE_BOT: 1,
	Zone.LEFT_MID_TOP: -1,      Zone.LEFT_MID_MID: 0,      Zone.LEFT_MID_BOT: 1,
	Zone.LEFT_CENTER_TOP: -1,   Zone.LEFT_CENTER_MID: 0,   Zone.LEFT_CENTER_BOT: 1,
	Zone.GOALIE_RIGHT: 0,
	Zone.RIGHT_DEFENSE_TOP: -1, Zone.RIGHT_DEFENSE_BOT: 1,
	Zone.RIGHT_MID_TOP: -1,     Zone.RIGHT_MID_MID: 0,     Zone.RIGHT_MID_BOT: 1,
	Zone.RIGHT_CENTER_TOP: -1,  Zone.RIGHT_CENTER_MID: 0,  Zone.RIGHT_CENTER_BOT: 1,
}

## Depth from OWN goal (0=own goal … 7=opponent goal) for the LEFT team.
## Right team depths are automatically mirrored (7 - depth).
const ZONE_DEPTH_LEFT: Dictionary = {
	Zone.NONE: -1,
	Zone.GOALIE_LEFT: 0,
	Zone.LEFT_DEFENSE_TOP: 1,  Zone.LEFT_DEFENSE_BOT: 1,
	Zone.LEFT_MID_TOP: 2,      Zone.LEFT_MID_MID: 2,      Zone.LEFT_MID_BOT: 2,
	Zone.LEFT_CENTER_TOP: 3,   Zone.LEFT_CENTER_MID: 3,   Zone.LEFT_CENTER_BOT: 3,
	Zone.RIGHT_CENTER_TOP: 4,  Zone.RIGHT_CENTER_MID: 4,  Zone.RIGHT_CENTER_BOT: 4,
	Zone.RIGHT_MID_TOP: 5,     Zone.RIGHT_MID_MID: 5,     Zone.RIGHT_MID_BOT: 5,
	Zone.RIGHT_DEFENSE_TOP: 6, Zone.RIGHT_DEFENSE_BOT: 6,
	Zone.GOALIE_RIGHT: 7,
}

## Zone lookup table by [depth][row_index] for LEFT team.
## row_index: 0=top, 1=mid, 2=bot
const ZONE_TABLE_LEFT: Array = [
	# depth 0 — own goal
	[Zone.GOALIE_LEFT,      Zone.GOALIE_LEFT,      Zone.GOALIE_LEFT],
	# depth 1 — own defense (no mid zone)
	[Zone.LEFT_DEFENSE_TOP, Zone.LEFT_DEFENSE_TOP,  Zone.LEFT_DEFENSE_BOT],
	# depth 2 — own mid
	[Zone.LEFT_MID_TOP,     Zone.LEFT_MID_MID,      Zone.LEFT_MID_BOT],
	# depth 3 — own center
	[Zone.LEFT_CENTER_TOP,  Zone.LEFT_CENTER_MID,   Zone.LEFT_CENTER_BOT],
	# depth 4 — opponent center
	[Zone.RIGHT_CENTER_TOP, Zone.RIGHT_CENTER_MID,  Zone.RIGHT_CENTER_BOT],
	# depth 5 — opponent mid
	[Zone.RIGHT_MID_TOP,    Zone.RIGHT_MID_MID,     Zone.RIGHT_MID_BOT],
	# depth 6 — opponent defense (no mid zone)
	[Zone.RIGHT_DEFENSE_TOP, Zone.RIGHT_DEFENSE_TOP, Zone.RIGHT_DEFENSE_BOT],
	# depth 7 — opponent goal
	[Zone.GOALIE_RIGHT,     Zone.GOALIE_RIGHT,      Zone.GOALIE_RIGHT],
]

# Approximate vertical center of the field in world space
const FIELD_CENTER_Y := 608.0

# Cached world-space polygons built once in _ready — keyed by Zone
var _polygon_cache: Dictionary = {}
# Cached zone centers — keyed by Zone
var _center_cache: Dictionary = {}

## Registered on ENTER, not on ready. Every RoleAI looks this node up by
## group from its own _ready(), and _ready() runs bottom-up: because FieldZones
## sits after ActorsContainer in world.tscn, the group was still empty when the
## players asked for it, so every player ran the whole match with field_zones
## null — no zones, no navigation, no anchor depth. _enter_tree() happens before
## any _ready() in the scene, so the lookup can no longer lose the race.
func _enter_tree() -> void:
	add_to_group("field_zones")

func _ready() -> void:
	_build_cache()

## Cached lazily as well as on ready: a player asking for a zone from its own
## _ready() can arrive before ours. By then the whole subtree has entered the
## tree, so the polygons' global transforms are already valid.
func _build_cache() -> void:
	if not _polygon_cache.is_empty():
		return
	for zone: Zone in ZONE_NODE_NAMES:
		var area := get_node(ZONE_NODE_NAMES[zone]) as Area2D
		if area == null:
			push_error("FieldZones: missing Area2D node '%s'" % ZONE_NODE_NAMES[zone])
			continue
		var cpoly := area.get_child(0) as CollisionPolygon2D
		if cpoly == null:
			push_error("FieldZones: Area2D '%s' has no CollisionPolygon2D child" % ZONE_NODE_NAMES[zone])
			continue
		var world_poly := PackedVector2Array()
		var center := Vector2.ZERO
		for v: Vector2 in cpoly.polygon:
			var world_v := cpoly.to_global(v)
			world_poly.append(world_v)
			center += world_v
		_polygon_cache[zone] = world_poly
		_center_cache[zone] = center / cpoly.polygon.size()

# ─── Public API ────────────────────────────────────────────────────────────────

## Returns which Zone contains [param world_position], or NONE if outside all zones.
func get_zone(world_position: Vector2) -> Zone:
	_build_cache()
	for zone: Zone in _polygon_cache:
		if Geometry2D.is_point_in_polygon(world_position, _polygon_cache[zone]):
			return zone
	return Zone.NONE

## Returns the world-space centroid of the zone polygon.
func get_zone_center(zone: Zone) -> Vector2:
	_build_cache()
	return _center_cache.get(zone, Vector2.ZERO)

## Returns the vertical row of a zone: -1=top, 0=mid/goalie, 1=bot.
func get_zone_row(zone: Zone) -> int:
	return ZONE_ROW.get(zone, 0)

## Returns depth from own goal (0=own, 7=opponent) for a given team side.
func get_zone_depth(zone: Zone, is_left_team: bool) -> int:
	var d: int = ZONE_DEPTH_LEFT.get(zone, -1)
	return d if is_left_team else (7 - d)

## Returns the zone at [param target_depth] matching the ball's row/Y.
## [param ball_world_pos] is used to determine top vs bot when no mid exists (depth 1, 6).
func get_zone_at_depth(target_depth: int, ball_world_pos: Vector2, is_left_team: bool) -> Zone:
	var clamped_depth := clampi(target_depth, 0, 7)
	# For depths 1 and 6 (defense, no mid zone) decide top vs bot by field Y
	var row_index: int
	var ball_zone_row := get_zone_row(get_zone(ball_world_pos))
	if ball_zone_row == -1:
		row_index = 0  # top
	elif ball_zone_row == 1:
		row_index = 2  # bot
	else:
		# mid row — use Y position to decide at defense depth
		row_index = 0 if ball_world_pos.y < FIELD_CENTER_Y else 2

	var table: Array = ZONE_TABLE_LEFT if is_left_team else _get_zone_table_right()
	return table[clamped_depth][row_index]

## Returns the cached world-space polygon for a zone.
func get_zone_polygon(zone: Zone) -> PackedVector2Array:
	_build_cache()
	return _polygon_cache.get(zone, PackedVector2Array())

## Returns the Area2D node for a zone.
func get_zone_area(zone: Zone) -> Area2D:
	return get_node_or_null(ZONE_NODE_NAMES.get(zone, "")) as Area2D

func is_left_zone(zone: Zone) -> bool:
	return zone in LEFT_ZONES

func is_right_zone(zone: Zone) -> bool:
	return zone in RIGHT_ZONES

# ─── Private ───────────────────────────────────────────────────────────────────

func _get_zone_table_right() -> Array:
	# Mirror of ZONE_TABLE_LEFT — depth 0 = GOALIE_RIGHT for right team
	return [
		[Zone.GOALIE_RIGHT,      Zone.GOALIE_RIGHT,      Zone.GOALIE_RIGHT],
		[Zone.RIGHT_DEFENSE_TOP, Zone.RIGHT_DEFENSE_TOP, Zone.RIGHT_DEFENSE_BOT],
		[Zone.RIGHT_MID_TOP,     Zone.RIGHT_MID_MID,     Zone.RIGHT_MID_BOT],
		[Zone.RIGHT_CENTER_TOP,  Zone.RIGHT_CENTER_MID,  Zone.RIGHT_CENTER_BOT],
		[Zone.LEFT_CENTER_TOP,   Zone.LEFT_CENTER_MID,   Zone.LEFT_CENTER_BOT],
		[Zone.LEFT_MID_TOP,      Zone.LEFT_MID_MID,      Zone.LEFT_MID_BOT],
		[Zone.LEFT_DEFENSE_TOP,  Zone.LEFT_DEFENSE_TOP,  Zone.LEFT_DEFENSE_BOT],
		[Zone.GOALIE_LEFT,       Zone.GOALIE_LEFT,       Zone.GOALIE_LEFT],
	]
