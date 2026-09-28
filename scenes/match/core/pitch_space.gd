class_name PitchSpace
extends RefCounted

## Coordinate conversions between world pixels, a team-relative normalised
## pitch, and real-world metres.
##
## The pitch is drawn in PERSPECTIVE: the touchlines are horizontal, but the
## two goal lines are slanted walls (the pitch is a trapezoid, wider at the
## bottom of the screen). A point's depth up the pitch therefore isn't just its
## x: two points on the same "equal-depth" line (e.g. an offside line) have
## different x at different y. normalised() maps the trapezoid onto the unit
## square so depth comparisons, the offside line, out-of-play detection and
## every metric work in true pitch coordinates. Movement and steering stay
## in raw pixels.
##
## Line positions are the INNER edges of the wall colliders in world.tscn
## (TopWall/BottomWall/LeftWall/RightWall), i.e. where the ball physically
## stops. See docs/match-engine-v2.md Findings #1.

const LENGTH_M := 105.0
const WIDTH_M := 68.0

## Fitted to the inner edges of the end-wall collision polygons (TopWall's
## corner pieces + LeftWall/RightWall + their StaticBody2D2 lower segments),
## accurate to within ~5px along each goal line. The ball stops against these,
## so OutOfPlay's margin must be measured from them, not from the sprites.
const TOP_Y := 180.0
const BOTTOM_Y := 1045.0
const LEFT_TOP_X := 144.0
const LEFT_BOTTOM_X := 36.0
const RIGHT_TOP_X := 2204.0
const RIGHT_BOTTOM_X := 2311.0

## Bounding box of the playable trapezoid.
static func field_rect() -> Rect2:
	return Rect2(LEFT_BOTTOM_X, TOP_Y, RIGHT_BOTTOM_X - LEFT_BOTTOM_X, BOTTOM_Y - TOP_Y)

static func _t(y: float) -> float:
	return (y - TOP_Y) / (BOTTOM_Y - TOP_Y)

## x of the left (right) goal line at screen height [param y] — extrapolated
## linearly outside the touchlines.
static func left_line_x(y: float) -> float:
	return lerpf(LEFT_TOP_X, LEFT_BOTTOM_X, _t(y))

static func right_line_x(y: float) -> float:
	return lerpf(RIGHT_TOP_X, RIGHT_BOTTOM_X, _t(y))

## Pitch-absolute normalised coords: x=0 left goal line, x=1 right goal line,
## y=0 top touchline, y=1 bottom touchline. Not clamped — outside the pitch
## gives values outside [0,1].
static func absolute_normalised(world: Vector2) -> Vector2:
	var lx := left_line_x(world.y)
	var rx := right_line_x(world.y)
	return Vector2((world.x - lx) / (rx - lx), _t(world.y))

static func from_absolute_normalised(n: Vector2) -> Vector2:
	var y := lerpf(TOP_Y, BOTTOM_Y, n.y)
	return Vector2(lerpf(left_line_x(y), right_line_x(y), n.x), y)

## Team-relative normalised coords: x=0 is that team's own goal line, x=1 the
## goal they attack; y=0 top touchline.
static func normalised(world: Vector2, is_left_team: bool) -> Vector2:
	var n := absolute_normalised(world)
	if not is_left_team:
		n.x = 1.0 - n.x
	return n

## Inverse of normalised().
static func from_normalised(n: Vector2, is_left_team: bool) -> Vector2:
	return from_absolute_normalised(Vector2(n.x if is_left_team else 1.0 - n.x, n.y))

## World px → metres from the top-left corner of the pitch (pitch-absolute).
static func to_metres(world: Vector2) -> Vector2:
	return absolute_normalised(world) * Vector2(LENGTH_M, WIDTH_M)

static func distance_m(a: Vector2, b: Vector2) -> float:
	return to_metres(a).distance_to(to_metres(b))

## Approximate metres per pixel along each axis at the pitch's centre — for
## converting speeds and radii, where an exact perspective mapping isn't needed.
static func metres_per_px() -> Vector2:
	var mid_width := right_line_x((TOP_Y + BOTTOM_Y) * 0.5) - left_line_x((TOP_Y + BOTTOM_Y) * 0.5)
	return Vector2(LENGTH_M / mid_width, WIDTH_M / (BOTTOM_Y - TOP_Y))
