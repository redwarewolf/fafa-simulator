class_name BallPredictor
extends RefCounted

## Forward-simulates the ball's flight using the engine's own physics rules,
## step for step at the physics tick — BallStateFreeform's friction switch
## (air vs ground), BallState.process_gravity's un-delta-scaled height
## integration and bounce, and BallStateShot's friction-free "hot" phase.
## A closed form would drift from the real thing on exactly those quirks
## (see the long comments on Ball.pass_to/long_kick about them), so this
## replays the same arithmetic instead. Walls/goals and player contact are
## not modelled: the path is where the ball goes if nobody touches it.
##
## Used by PassModel (interception race along a pass path), by the loose-ball
## chaser choice, and by the goalkeeper (where/when a shot crosses the line).

const DT := 1.0 / 60.0
## Samples are recorded every SAMPLE_STEPS physics steps (0.1s).
const SAMPLE_STEPS := 6
## Below this speed the ball counts as stopped.
const STOP_SPEED := 2.0

## A predicted path: parallel arrays of sample times (s), positions and
## heights, plus when the ball stops (INF if it's still moving at max_time).
class BallPath:
	var times := PackedFloat32Array()
	var positions := PackedVector2Array()
	var heights := PackedFloat32Array()
	var stop_time := INF

	func size() -> int:
		return times.size()

	func end_position() -> Vector2:
		return positions[positions.size() - 1] if positions.size() > 0 else Vector2.ZERO

	## Position at time [param t] (linear between samples, clamped to the ends).
	func position_at(t: float) -> Vector2:
		if positions.is_empty():
			return Vector2.ZERO
		if t <= times[0]:
			return positions[0]
		for i in range(1, times.size()):
			if t <= times[i]:
				var f := (t - times[i - 1]) / maxf(times[i] - times[i - 1], 0.0001)
				return positions[i - 1].lerp(positions[i], f)
		return positions[positions.size() - 1]

## Simulates from an explicit state. [param shot_hot_time] > 0 reproduces
## BallStateShot: that many seconds of friction-free straight flight at a fixed
## height before handing off to freeform (with height/height_velocity zeroed,
## exactly as BallStateShot does).
static func simulate(pos: Vector2, vel: Vector2, height: float, height_vel: float,
		max_time: float, shot_hot_time: float = 0.0) -> BallPath:
	var path := BallPath.new()
	path.times.append(0.0)
	path.positions.append(pos)
	path.heights.append(height)
	var t := 0.0
	var step := 0
	var hot := shot_hot_time
	while t < max_time:
		if hot > 0.0:
			hot -= DT
			pos += vel * DT
			if hot <= 0.0:
				height = 0.0
				height_vel = 0.0
		else:
			var friction := Ball.FRICTION_AIR if height > 0.0 else Ball.FRICTION_GROUND
			vel = vel.move_toward(Vector2.ZERO, friction * DT)
			if height > 0.0 or height_vel > 0.0:
				height_vel -= BallState.GRAVITY * DT
				height += height_vel
				if height <= 0.0:
					height = 0.0
					if height_vel < 0.0:
						height_vel = -height_vel * Ball.BOUNCINESS
						vel *= Ball.BOUNCINESS
			pos += vel * DT
		t += DT
		step += 1
		var stopped := hot <= 0.0 and vel.length() < STOP_SPEED and height <= 0.0 and height_vel <= 0.0
		if step % SAMPLE_STEPS == 0 or stopped:
			path.times.append(t)
			path.positions.append(pos)
			path.heights.append(height)
		if stopped:
			path.stop_time = t
			break
	return path

## The path a pass_to([param destination]) kick from [param from] would take.
static func for_pass(from: Vector2, destination: Vector2, max_time: float = 4.0) -> BallPath:
	var launch := Ball.pass_launch(from, destination)
	return simulate(from, launch["velocity"], 0.0, launch["height_velocity"], max_time)

## The live ball's path from its current state (carried → a single point).
static func for_ball(ball: Ball, max_time: float = 3.0) -> BallPath:
	if ball.carrier != null:
		return simulate(ball.position, Vector2.ZERO, 0.0, 0.0, 0.0)
	var hot := 0.0
	if ball.current_state is BallStateShot:
		var shot := ball.current_state as BallStateShot
		hot = maxf(0.0, (BallStateShot.DURATION - (MatchClock.now_ms() - shot.time_since_shot)) / 1000.0)
	return simulate(ball.position, ball.velocity, ball.height, ball.height_velocity, max_time, hot)

## Earliest sample time at which [param player] could be at the ball
## (PitchControl.time_to_reach ≤ ball time), or INF if they never can within
## the path. Once the ball has stopped, arriving any time later still counts.
static func earliest_intercept(path: BallPath, player: Player) -> float:
	for i in path.size():
		if PitchControl.time_to_reach(path.positions[i], player) <= path.times[i]:
			return path.times[i]
	if path.stop_time != INF:
		return maxf(path.stop_time, PitchControl.time_to_reach(path.end_position(), player))
	return INF

## The player in [param candidates] who gets to the ball first, and when:
## {"player": Player, "time": float} (player null if nobody can).
static func first_to_ball(path: BallPath, candidates: Array) -> Dictionary:
	var best : Player = null
	var best_t := INF
	for p in candidates:
		var t := earliest_intercept(path, p)
		if t < best_t:
			best_t = t
			best = p
	return {"player": best, "time": best_t}
