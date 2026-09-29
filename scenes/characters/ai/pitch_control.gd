class_name PitchControl
extends RefCounted

## Approximate pitch-control: which team could reach a given point first,
## factoring in each player's current position AND velocity (time-to-reach),
## not just static distance — the actual Voronoi/pitch-control idea from
## football analytics (see docs/ai-overhaul.md Phase 1). Deliberately cheap:
## called on a handful of candidate points per player per AI tick (or a
## coarse debug-heatmap grid), never integrated continuously over the pitch.

## Assumed reaction delay before a player starts moving toward a contested
## point — without this a dead-even race (equal distance, equal speed) reads
## as a tie at t=0 rather than "nobody's there yet," which matters once this
## feeds a comparison rather than an absolute score.
const REACTION_TIME := 0.15

## How much of a player's current speed counts as a head start/penalty when
## their velocity is already aligned/opposed with the direction to the point,
## on top of their base top speed. Approximates "already running the right
## way arrives sooner, already running the wrong way needs to turn around
## first" without modeling deceleration explicitly.
const VELOCITY_BIAS_WEIGHT := 0.5
const MIN_EFFECTIVE_SPEED_FACTOR := 0.4
const MAX_EFFECTIVE_SPEED_FACTOR := 1.5

## Estimated seconds for [param player] to reach [param point].
static func time_to_reach(point: Vector2, player: Player) -> float:
	var to_point := point - player.position
	var distance := to_point.length()
	if distance < 1.0:
		return REACTION_TIME
	if player.max_accel > 0.0:
		# Engine-v2 movement: real acceleration, so use kinematics.
		var along := player.velocity.dot(to_point / distance)
		return REACTION_TIME + kinematic_time(distance, along, player.speed * Locomotion.SPRINT_MULTIPLIER, player.max_accel)
	var speed := maxf(player.speed, 1.0)
	var current_speed := player.velocity.length()
	var alignment := 0.0
	if current_speed > 1.0:
		alignment = player.velocity.normalized().dot(to_point / distance)
	var effective_speed := clampf(
		speed + alignment * current_speed * VELOCITY_BIAS_WEIGHT,
		speed * MIN_EFFECTIVE_SPEED_FACTOR, speed * MAX_EFFECTIVE_SPEED_FACTOR
	)
	return REACTION_TIME + distance / effective_speed

## Seconds to cover [param distance] starting at speed [param v_along] along
## the way (negative = currently moving away), accelerating at [param accel]
## up to [param vmax]. Moving away first costs the time to brake to zero
## (at Player.BRAKE_FACTOR × accel).
static func kinematic_time(distance: float, v_along: float, vmax: float, accel: float) -> float:
	var t := 0.0
	var v0 := v_along
	if v0 < 0.0:
		t += -v0 / (accel * Player.BRAKE_FACTOR)
		v0 = 0.0
	v0 = minf(v0, vmax)
	var t_acc := (vmax - v0) / accel
	var d_acc := (v0 + vmax) * 0.5 * t_acc
	if distance <= d_acc:
		return t + (-v0 + sqrt(v0 * v0 + 2.0 * accel * distance)) / accel
	return t + t_acc + (distance - d_acc) / vmax

## Fastest (lowest) time_to_reach among [param team] — goalkeepers included,
## same as the flat-distance nearest_opponent_distance() this augments. 99.0
## for an empty team is an arbitrary "effectively never" sentinel, not a
## real bound.
static func _best_time(point: Vector2, team: Array[Player]) -> float:
	var best := INF
	for p in team:
		var t := time_to_reach(point, p)
		if t < best:
			best = t
	return best if best != INF else 99.0

## Signed control value at [param point]: positive favors [param team_a],
## negative favors [param team_b]. /1.5s soft-scales a realistic worst-case
## time gap onto roughly [-1, 1] without a hard clamp discontinuity mattering
## much in practice — this is a debug-visualization convenience, not
## consumed numerically by any decision yet.
static func control(point: Vector2, team_a: Array[Player], team_b: Array[Player]) -> float:
	var diff := _best_time(point, team_b) - _best_time(point, team_a)
	return clampf(diff / 1.5, -1.0, 1.0)

## Capped at SPACE_SATURATION_TIME so one player stranded far away can't
## make a point read as infinitely safe (space swamping every other scoring
## term).
const SPACE_SATURATION_TIME := 1.2
static func opponent_reach_time(point: Vector2, opponents: Array[Player]) -> float:
	return minf(_best_time(point, opponents), SPACE_SATURATION_TIME)
