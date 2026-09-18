class_name Locomotion
extends RefCounted

## Steering/potential-field locomotion — kept from the old AIBehavior. An open
## pitch with only dynamic obstacles (other players, no static geometry)
## doesn't call for navmesh pathfinding, just a seek force blended with local
## separation/avoidance, matching how competitive football agents (e.g.
## RoboCup 2D sim teams) move: "sub-targets + potential fields," not a path.
##
## The seek-to-target is now the dominant term rather than one-among-equals
## in an unweighted sum, since the target itself already encodes tactical
## intent (marking point, candidate-scored space, carrier pull — see RoleAI)
## instead of being just one more vote alongside repulsion/avoidance.

const TEAMMATE_REPULSION_RADIUS_LOOSE := 45.0
const TEAMMATE_REPULSION_RADIUS_CARRIED := 80.0
const OPPONENT_AVOID_RADIUS := 60.0
const OPPONENT_AVOID_STRENGTH := 2.5
const OPPONENT_AVOID_AHEAD_DOT := 0.2
## Speed multiplier while Player.is_making_run is set (see
## RoleAI._apply_run_support) — a supporting run needs to be a genuine
## sprint, not just a forward-aimed point at the same pace as everyone
## else, or a runner can never actually get ahead of/level with a carrier
## dribbling at a fraction of full speed before the moment passes. Also
## feeds Player's stamina decay automatically, since that already scales
## with velocity-vs-speed — no extra bookkeeping needed for "sprinting
## tires you out faster." See docs/ai-overhaul.md Phase 6.
const SPRINT_MULTIPLIER := 1.25

static func compute_velocity(player: Player, target: Vector2, ball: Ball, opponent_detection_area: Area2D) -> Vector2:
	var dist := player.position.distance_to(target)
	var seek := player.position.direction_to(target) * clampf(dist / 30.0, 0.2, 1.0)

	var total := seek
	total += _teammate_repulsion(player, ball) * 0.5
	total += _opponent_avoidance(player, opponent_detection_area) * 0.5

	total = total.limit_length(1.0)
	# Carrying the ball is slower than running free (see
	# Player.get_dribble_speed) — a chasing defender running at full `speed`
	# needs to actually be faster than the carrier to ever close the gap.
	var move_speed := player.get_dribble_speed() if ball.carrier == player else player.speed
	if player.is_making_run and ball.carrier != player:
		move_speed *= SPRINT_MULTIPLIER
	# Fatigue (see Player.stamina/get_stamina_factor) scales both cases down
	# together, so the relative chase dynamic above still holds late in a
	# match — a tired carrier and a tired chaser both slow down, not just one.
	move_speed *= player.get_stamina_factor()
	return total * move_speed

static func _teammate_repulsion(player: Player, ball: Ball) -> Vector2:
	var repulsion := Vector2.ZERO
	# Shrink the personal-space bubble when chasing a loose ball so players
	# can actually converge and reach it — avoids infinite mutual repulsion
	# at the carried-ball radius.
	var effective_radius := TEAMMATE_REPULSION_RADIUS_LOOSE if ball.carrier == null else TEAMMATE_REPULSION_RADIUS_CARRIED
	for other in player.get_teammates():
		if other == player:
			continue
		var d := player.position.distance_to(other.position)
		if d < effective_radius:
			repulsion += (player.position - other.position).normalized() * (effective_radius - d)
	return repulsion.limit_length(1.0)

## Steers around any nearby opponent roughly ahead of travel. Extended from
## carrier-only (the old AIBehavior.get_opponent_avoidance_force only ran for
## whoever had the ball) since any player chasing a target can walk straight
## into an opponent standing in the way.
##
## Excludes player.mark_target: a marker's target position is already the
## goal-side shadow point right next to that same opponent (see
## RoleAI._marking_target_position), so without this exclusion the marker
## gets steered away from the one player they're trying to close down the
## moment they get close enough to matter — reading as ducking the attacker
## instead of tracking them.
static func _opponent_avoidance(player: Player, opponent_detection_area: Area2D) -> Vector2:
	var avoidance := Vector2.ZERO
	var travel_dir := player.heading
	for body in opponent_detection_area.get_overlapping_bodies():
		if not (body is Player) or body == player.mark_target:
			continue
		var to_opponent: Vector2 = body.position - player.position
		var d := to_opponent.length()
		if d < 1.0 or d >= OPPONENT_AVOID_RADIUS:
			continue
		var to_opp_norm := to_opponent / d
		var ahead_dot := travel_dir.dot(to_opp_norm)
		if ahead_dot < OPPONENT_AVOID_AHEAD_DOT:
			continue
		var perp := Vector2(-travel_dir.y, travel_dir.x)
		var cross := travel_dir.cross(to_opp_norm)
		if cross > 0:
			perp = -perp
		var weight := (OPPONENT_AVOID_RADIUS - d) / OPPONENT_AVOID_RADIUS
		avoidance += perp * weight
	return avoidance.limit_length(1.0) * OPPONENT_AVOID_STRENGTH
