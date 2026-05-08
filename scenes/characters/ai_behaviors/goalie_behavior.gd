class_name GoalieBehavior
extends RoleBehavior

const PROXIMITY_CONCERN := 10.0
const CATCH_DISTANCE := 22.0
const MAX_CATCHABLE_SPEED := 200.0  # won't catch a hard shot
const HOLD_DECISION_DELAY := 2500   # ms before keeper decides to release
const CATCH_COOLDOWN := 1500        # ms after releasing before keeper can catch again
const INTERCEPT_DISTANCE := 80.0    # within this range, run at ball instead of diving
const LONG_KICK_MIN_DISTANCE := 150.0  # don't long-kick to someone standing right next to you
const MAX_HOLD_RETRIES := 3         # how many times to wait before forcing a release

var _hold_start_time := 0
var _catch_cooldown_end := 0
var _hold_retry_count := 0

func draw_debug() -> void:
	DebugDraw.circle(player.position, CATCH_DISTANCE, Color(1, 1, 0))        # Yellow — catch range
	DebugDraw.circle(player.position, INTERCEPT_DISTANCE, Color(1, 0.5, 0))  # Orange — intercept vs dive

func calculate_target_zone(_ball_zone: FieldZones.Zone) -> FieldZones.Zone:
	return home_zone  # Goalie never leaves their zone

func get_fine_positioning_force() -> Vector2:
	# Stay still while holding — ball.position follows us, tracking it causes oscillation
	if player.current_state != null and player.current_state.is_holding_ball():
		return Vector2.ZERO

	var top := own_goal.get_top_target_position()
	var bottom := own_goal.get_bottom_target_position()

	# Ball incoming and close enough to intercept by running — rush at it
	if ball.carrier == null and ball.is_headed_for_scoring_area(top, bottom):
		var dist := player.position.distance_to(ball.position)
		if dist < INTERCEPT_DISTANCE:
			return player.position.direction_to(ball.position)

	# Normal goal-line tracking: stay at spawn X, mirror ball's Y
	var center := player.spawn_position
	var target_y := clampf(ball.position.y, top.y, bottom.y)
	var destination := Vector2(center.x, target_y)
	var direction := player.position.direction_to(destination)
	var distance_to_destination := player.position.distance_to(destination)
	var weight := clampf(distance_to_destination / PROXIMITY_CONCERN, 0.0, 1.0)
	return weight * direction

func make_fine_decisions() -> void:
	# While holding the ball — decide when/how to release it
	if player.current_state != null and player.current_state.is_holding_ball():
		_make_holding_decisions()
		return

	# Try to catch a loose ball that's slow, nearby, and not in cooldown
	if ball.carrier == null and Time.get_ticks_msec() > _catch_cooldown_end:
		var dist := player.position.distance_to(ball.position)
		if dist < CATCH_DISTANCE and ball.velocity.length() < MAX_CATCHABLE_SPEED:
			print("[%s] 🧤 CATCH — ball dist=%.1f vel=%.1f h=%.1f hvel=%.1f" % [
				player.full_name, dist, ball.velocity.length(), ball.height, ball.height_velocity])
			player.switch_state(Player.State.HOLDING_BALL)
			return

	# Ball headed for goal: intercept by running if close, dive if far
	if ball.is_headed_for_scoring_area(
		own_goal.get_top_target_position(),
		own_goal.get_bottom_target_position()
	):
		var dist := player.position.distance_to(ball.position)
		if dist >= INTERCEPT_DISTANCE:
			player.switch_state(Player.State.DIVING)

func _make_holding_decisions() -> void:
	# Start the decision timer on first tick
	if _hold_start_time == 0:
		_hold_start_time = Time.get_ticks_msec()
		return

	if Time.get_ticks_msec() - _hold_start_time < HOLD_DECISION_DELAY:
		return

	_hold_start_time = 0  # Reset — either we release, or we restart the wait

	# Option 1: Long kick to a teammate in a clear (enemy-free) zone
	var long_target := _find_long_kick_target()
	if long_target != null:
		print("[%s] 👟 LONG KICK → %s (dist=%.1f) ball h=%.1f hvel=%.1f" % [
			player.full_name, long_target.full_name,
			player.position.distance_to(long_target.position),
			ball.height, ball.height_velocity])
		DebugDraw.line(player.position, long_target.position, Color.YELLOW, 2.0)
		DebugDraw.cross(long_target.position, Color.YELLOW, 5.0, 2.0)
		_release_long_kick(long_target.position)
		return

	# Option 2: Short pass to the nearest visible teammate
	var short_target := get_closest_teammate_in_view()
	if short_target != null:
		print("[%s] 🦵 SHORT PASS → %s (dist=%.1f) ball h=%.1f hvel=%.1f" % [
			player.full_name, short_target.full_name,
			player.position.distance_to(short_target.position),
			ball.height, ball.height_velocity])
		DebugDraw.line(player.position, short_target.position, Color.CYAN, 2.0)
		DebugDraw.cross(short_target.position, Color.CYAN, 5.0, 2.0)
		_face_toward(short_target.position)
		_catch_cooldown_end = Time.get_ticks_msec() + CATCH_COOLDOWN
		_hold_retry_count = 0
		player.switch_state(Player.State.PASSING)
		return

	# No target found — wait for the field to clear, up to MAX_HOLD_RETRIES times
	_hold_retry_count += 1
	print("[%s] 🤔 No targets, waiting for field to clear... (attempt %d/%d)" % [
		player.full_name, _hold_retry_count, MAX_HOLD_RETRIES])
	if _hold_retry_count < MAX_HOLD_RETRIES:
		# Restart the countdown — don't release yet
		return

	# All retries exhausted: force a long kick to ANY teammate, clear zone or not
	_hold_retry_count = 0
	var forced_target := _get_any_teammate()
	if forced_target != null:
		print("[%s] ⚠️ FORCED LONG KICK → %s (field not clearing)" % [
			player.full_name, forced_target.full_name])
		DebugDraw.line(player.position, forced_target.position, Color.ORANGE, 2.0)
		_release_long_kick(forced_target.position)
	else:
		# Absolute last resort — punt to midfield, not the opposing goal
		var midfield := Vector2(
			(player.position.x + target_goal.get_center_target_position().x) * 0.5,
			player.position.y
		)
		print("[%s] ⚠️ ABSOLUTE LAST RESORT — punting to midfield" % player.full_name)
		_release_long_kick(midfield)

func _release_long_kick(destination: Vector2) -> void:
	_face_toward(destination)
	_catch_cooldown_end = Time.get_ticks_msec() + CATCH_COOLDOWN
	ball.long_kick(destination)
	player.switch_state(Player.State.MOVING)

## Scans own-side zones from furthest forward (depth 3) to closest (depth 1).
## Returns the first teammate found in a zone with no opponents, or null.
func _find_long_kick_target() -> Player:
	if field_zones == null:
		return null
	# Three Y-hints to cover top/mid/bot rows at each depth
	var row_hints := [
		FieldZones.FIELD_CENTER_Y - 200.0,
		FieldZones.FIELD_CENTER_Y,
		FieldZones.FIELD_CENTER_Y + 200.0,
	]
	for depth in [3, 2, 1]:
		var checked: Array[FieldZones.Zone] = []
		for hint_y in row_hints:
			var zone := field_zones.get_zone_at_depth(depth, Vector2(ball.position.x, hint_y), _is_left_team)
			if zone == FieldZones.Zone.NONE or zone in checked:
				continue
			checked.append(zone)
			if _is_zone_clear_of_opponents(zone):
				var teammate := _get_teammate_in_zone(zone)
				if teammate != null and player.position.distance_to(teammate.position) >= LONG_KICK_MIN_DISTANCE:
					return teammate
	return null

func _is_zone_clear_of_opponents(zone: FieldZones.Zone) -> bool:
	var area := field_zones.get_zone_area(zone)
	if area == null:
		return false
	for body in area.get_overlapping_bodies():
		if body is Player and body.team != player.team:
			return false  # Enemy found — not clear
	return true

## Finds a teammate whose current position is inside [param zone].
## Uses field_zones polygon math — does not rely on Area2D collision layers.
func _get_teammate_in_zone(zone: FieldZones.Zone) -> Player:
	for teammate in player.get_teammates():
		if teammate == player:
			continue
		if field_zones.get_zone(teammate.position) == zone:
			return teammate
	return null

## Flips the keeper's heading toward a world-space destination before an action.
func _face_toward(destination: Vector2) -> void:
	player.heading = Vector2.LEFT if destination.x < player.position.x else Vector2.RIGHT

## Returns any available teammate regardless of zone or pressure — last resort.
func _get_any_teammate() -> Player:
	for teammate in player.get_teammates():
		if teammate != player and teammate.team == player.team:
			return teammate
	return null
