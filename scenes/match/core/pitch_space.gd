class_name PitchSpace
extends RefCounted

## Coordinate conversions between world pixels, a team-relative normalised
## pitch, and real-world metres.
##
## The playable area (ActorsContainer.FIELD_*) is 2197×888px, far wider than
## a real 105×68m pitch's proportions, so the metres mapping is deliberately
## anisotropic (x and y scale differently). It exists for analytics only
## (xG, shape metrics comparable to real-football figures). Movement and
## steering stay in pixels.

const LENGTH_M := 105.0
const WIDTH_M := 68.0

static func field_rect() -> Rect2:
	return Rect2(
		ActorsContainer.FIELD_LEFT, ActorsContainer.FIELD_TOP,
		ActorsContainer.FIELD_RIGHT - ActorsContainer.FIELD_LEFT,
		ActorsContainer.FIELD_BOTTOM - ActorsContainer.FIELD_TOP
	)

## Metres per pixel along each axis.
static func metres_per_px() -> Vector2:
	var r := field_rect()
	return Vector2(LENGTH_M / r.size.x, WIDTH_M / r.size.y)

## World px → metres from the field's top-left corner.
static func to_metres(world: Vector2) -> Vector2:
	var r := field_rect()
	return (world - r.position) * metres_per_px()

## A world-space displacement → metres (e.g. a pass length or team length).
static func delta_to_metres(delta: Vector2) -> Vector2:
	return delta * metres_per_px()

static func distance_m(a: Vector2, b: Vector2) -> float:
	return delta_to_metres(b - a).length()

## World px → normalised [0,1]² relative to a team: x=0 is that team's own
## goal line, x=1 the goal they attack; y=0 is the top touchline.
static func normalised(world: Vector2, is_left_team: bool) -> Vector2:
	var r := field_rect()
	var n := (world - r.position) / r.size
	if not is_left_team:
		n.x = 1.0 - n.x
	return n

## Inverse of normalised().
static func from_normalised(n: Vector2, is_left_team: bool) -> Vector2:
	var r := field_rect()
	var nx := n.x if is_left_team else 1.0 - n.x
	return r.position + Vector2(nx, n.y) * r.size
