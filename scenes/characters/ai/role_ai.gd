class_name RoleAI
extends Node

## Replaces RoleBehavior. Off-ball target position comes from candidate-point
## scoring (CandidatePointScorer) around a role-appropriate base point,
## instead of summing steering forces — a sum can only average multiple pulls
## into a blended (sometimes directionless) middle; scoring a handful of
## discrete alternatives can actually pick the best one, including a "lose my
## marker" option when TeamTacticalState has assigned one (player.marked_by).
##
## On-ball decisions (pass/shoot/dribble/hold) are unified across every role
## via OnBallUtility.decide() — subclasses only supply weight multipliers via
## role_weights(), not separate if/else cascades.

var player: Player = null
var ball: Ball = null
var teammate_detection_area: Area2D = null
var ball_detection_area: Area2D = null
var opponent_detection_area: Area2D = null
var own_goal: Goal = null
var target_goal: Goal = null
var field_zones: FieldZones = null

var _is_left_team: bool = false
var _anchor_depth: int = 0
var _roam_back: int = 0
var _roam_forward: int = 0
var _holds_flank: bool = false
var _anchor_y: float = 0.0
var _last_off_ball_target: Vector2 = Vector2.ZERO

## BallStateCarried offsets the ball ~10-14px ahead of the carrier in their
## heading direction (see OFFSET_FROM_PLAYER), so a defender who is genuinely
## right next to the carrier can still measure more than a few px to the ball
## itself. 20 left almost no margin for that plus normal steering imprecision
## — a marker or presser that looked "right there" on screen would still just
## keep running alongside instead of ever committing to the tackle.
const TACKLE_DISTANCE := 32.0

func setup(context_player: Player, context_ball: Ball, context_teammate_detection: Area2D, context_ball_detection: Area2D, context_opponent_detection: Area2D, context_own_goal: Goal, context_target_goal: Goal) -> void:
	player = context_player
	ball = context_ball
	teammate_detection_area = context_teammate_detection
	ball_detection_area = context_ball_detection
	opponent_detection_area = context_opponent_detection
	own_goal = context_own_goal
	target_goal = context_target_goal

func _ready() -> void:
	_is_left_team = player.is_left_team
	var roam := Positions.roam(player.role)
	_roam_back = roam.x
	_roam_forward = roam.y
	_holds_flank = Positions.holds_flank(player.role)
	_anchor_y = player.anchor_position.y
	field_zones = get_tree().get_first_node_in_group("field_zones") as FieldZones
	if field_zones:
		_anchor_depth = field_zones.get_zone_depth(field_zones.get_zone(player.anchor_position), _is_left_team)
	_last_off_ball_target = player.anchor_position

# ─── Overridable per-role knobs ─────────────────────────────────────────────

## How this role sits relative to the ball's depth when off the ball.
## Defenders hold a line one band behind it; everyone else tracks it.
func depth_offset() -> int:
	return 0

## Bicircular pull toward target_goal used while carrying the ball:
## [inner_radius, inner_weight, outer_radius, outer_weight].
func carrier_pull_radii() -> Array:
	return [100.0, 0.5, 200.0, 0.9]

## How closely this role mirrors the ball carrier's formation shift when a
## teammate has the ball (0 = stay put, 1 = mirror fully).
func support_shape_factor() -> float:
	return 0.8

## How eagerly this role makes a supporting forward run (overlap/underlap/
## third-man — see _apply_run_support) once a teammate is carrying the ball
## with pace. 0 disables it, holding the mirrored shape point instead — the
## safe default for roles that shouldn't abandon their base shape.
func run_support_weight() -> float:
	return 0.0

## How far ahead of the mirrored shape point a triggered run reaches.
func run_support_distance() -> float:
	return 200.0

## Weight multipliers for OnBallUtility.decide() — lets a striker favor SHOOT
## and a defender favor PASS without separate decision code per role.
func role_weights() -> Dictionary:
	return {"shoot": 1.0, "pass": 1.0, "dribble": 1.0, "shot_range": 360.0}

## Override to draw role-specific debug ranges (shot/tackle/catch circles).
func draw_debug() -> void:
	pass

# ─── Top-level API called by AIBehavior ─────────────────────────────────────

func get_target_position() -> Vector2:
	if is_opponent_keeper_holding():
		return player.anchor_position.lerp(own_goal.get_center_target_position(), 0.3)
	if is_own_keeper_holding():
		return player.anchor_position
	if player_has_ball():
		return _carrier_target_position()
	return _choose_off_ball_target()

func make_decisions() -> void:
	if is_opponent_keeper_holding() or is_own_keeper_holding():
		return
	if player_has_ball():
		_decide_on_ball()
	_try_tackle()

# ─── On-ball ─────────────────────────────────────────────────────────────

func _carrier_target_position() -> Vector2:
	var target := target_goal.get_center_target_position()
	var radii := carrier_pull_radii()
	var weight := get_bicircular_weight(player.position, target, radii[0], radii[1], radii[2], radii[3])
	return player.position.lerp(target, weight)

func _decide_on_ball() -> void:
	var action := OnBallUtility.decide(player, ball, player.get_teammates(), player.get_opponents(), target_goal, role_weights())
	match action.kind:
		OnBallUtility.ActionKind.SHOOT:
			player.face_towards_target_goal()
			var shot_direction := player.position.direction_to(target_goal.get_random_target_position())
			var data := PlayerStateData.build().set_shot_power(player.power).set_shot_direction(shot_direction)
			player.switch_state(Player.State.SHOOTING, data)
		OnBallUtility.ActionKind.PASS:
			player.switch_state(Player.State.PASSING)
		_:
			pass  # DRIBBLE/HOLD — keep moving toward the carrier target, no state change

func _try_tackle() -> void:
	if carrier_is_tackleable() and player_is_on_tackle_distance(TACKLE_DISTANCE):
		player.switch_state(Player.State.TACKLING)

# ─── Off-ball: candidate-point scoring ──────────────────────────────────────

func _choose_off_ball_target() -> Vector2:
	# Man-marking bypasses candidate scoring entirely. CandidatePointScorer
	# rewards distance from the nearest opponent (openness) and progress
	# toward target_goal — both are attacking heuristics. Run a marker's tight
	# goal-side shadow point (25-90px away, by design) through that scorer and
	# every one of the 60/120px-out alternatives scores higher on "openness"
	# than the tight mark itself, since they're all farther from the marked
	# opponent — so the defender was scored straight off their assignment and
	# out toward open grass, tracking nobody. This was the direct cause of
	# "no one intercepts the carrier": the covering defender's computed
	# goal-side block point never survived contact with the scorer.
	if player.mark_target != null:
		var mark_point := _marking_target_position(player.mark_target)
		_last_off_ball_target = mark_point
		return mark_point

	var base := _off_ball_base_position()
	var candidates: Array[Vector2] = [base]
	var radii := [60.0, 120.0]
	if is_ball_carried_by_teammate():
		# A real attacking run needs more reach than local jostling — let an
		# off-ball attacker consider a point well beyond a marker/defender,
		# not just a 60-120px shuffle, so runs in behind become an option the
		# carrier can actually see and hit with a forward pass.
		radii.append(220.0)
	for angle_deg in [-60, -30, 30, 60, 90, -90, 150, -150]:
		for radius in radii:
			candidates.append(base + Vector2.RIGHT.rotated(deg_to_rad(angle_deg)) * radius)

	var teammate_carrying := is_ball_carried_by_teammate()
	var marker := player.marked_by
	var opponents := player.get_opponents()
	var teammates := player.get_teammates()

	var best := base
	var best_score := -INF
	for c in candidates:
		var score := CandidatePointScorer.score_off_ball_candidate(
			c, player, opponents, teammates, target_goal, marker, teammate_carrying, _last_off_ball_target,
			not teammate_carrying
		)
		if score > best_score:
			best_score = score
			best = c

	_last_off_ball_target = best
	return best

## Base point the candidates are generated around.
## - A teammate is carrying: shift this role's formation shape relative to
##   the carrier (same idea as the old support/attacking-run positioning) so
##   the whole team's shape slides with the ball.
## - Otherwise: track the ball's depth, clamped to this role's roam window.
## (An assigned mark is handled earlier in _choose_off_ball_target, before
## candidate scoring ever runs — see the comment there.)
func _off_ball_base_position() -> Vector2:
	if is_ball_carried_by_teammate():
		var shape_offset := ball.carrier.anchor_position - player.anchor_position
		var mirrored := ball.carrier.position - shape_offset * support_shape_factor()
		return _apply_run_support(mirrored)
	return _ball_depth_base_position()

## Generalizes what used to be ForwardAI's own run-ahead-of-the-shape
## trigger to any role with a nonzero run_support_weight() — an overlapping
## full-back or an underlapping/third-man central midfielder is the same
## idea as a forward's run in behind: bias the shape-mirrored support point
## toward goal (and, for flank-holders, back out toward their own touchline)
## once the carrier is genuinely moving with the ball, not just shuffling.
## See docs/ai-overhaul.md Phase 3 — added because pass_score's advancement
## term was going negative for nearly every teammate whenever nobody but
## forwards ever got ahead of/level with the carrier, so passing almost
## never beat dribbling.
const RUN_TRIGGER_SPEED := 20.0

func _apply_run_support(mirrored: Vector2) -> Vector2:
	var weight := run_support_weight()
	if weight <= 0.0:
		return mirrored
	var carrier := ball.carrier
	if carrier.velocity.length() < RUN_TRIGGER_SPEED:
		return mirrored
	var run_point := mirrored + carrier.position.direction_to(target_goal.get_center_target_position()) * run_support_distance()
	if _holds_flank:
		run_point.y = lerpf(run_point.y, _anchor_y, 0.5)
	return mirrored.lerp(run_point, weight)

## Leads the marked opponent by their current velocity, same as
## AIBehavior._press_target does for the ball carrier — a shadow point pinned
## to only their current position always sits one mark_distance behind
## wherever they just were, so against any real run the marker reads as
## chasing rather than cutting off the run's direction.
func _marking_target_position(marked: Player) -> Vector2:
	var mark_distance := lerpf(TeamTacticalState.LOOSE_MARK_DISTANCE, TeamTacticalState.TIGHT_MARK_DISTANCE, player.mark_tightness)
	var lead_time := clampf(player.position.distance_to(marked.position) / maxf(player.speed, 1.0), 0.0, 1.0)
	var marked_lead_position := marked.position + marked.velocity * lead_time
	var to_goal := marked_lead_position.direction_to(own_goal.get_center_target_position())
	return marked_lead_position + to_goal * mark_distance

func _ball_depth_base_position() -> Vector2:
	if field_zones == null:
		return player.anchor_position
	var ball_zone := field_zones.get_zone(ball.position)
	var ball_depth := field_zones.get_zone_depth(ball_zone, _is_left_team)
	# team_line_bias (TeamTacticalState) shifts the whole team's shape
	# together — same-role players already agree on a band from ball_depth +
	# depth_offset() alone, so this is the part that formula can't express.
	var target_depth := clampi(ball_depth + depth_offset() + roundi(player.team_line_bias), _anchor_depth - _roam_back, _anchor_depth + _roam_forward)
	var zone := _zone_from_depth(target_depth)
	return field_zones.get_zone_center(zone)

## Row (top/mid/bottom) normally follows the ball; a flank player reads it
## off their own anchor so a full back overlapping stays on the touchline
## instead of sliding into the middle behind the ball.
func _zone_from_depth(target_depth: int) -> FieldZones.Zone:
	var row_hint := ball.position
	if _holds_flank:
		row_hint.y = _anchor_y
	return field_zones.get_zone_at_depth(target_depth, row_hint, _is_left_team)

# ─── Utility functions (kept from RoleBehavior) ─────────────────────────────

func player_has_ball() -> bool:
	return ball.carrier == player

func is_ball_carried() -> bool:
	return ball.carrier != null and ball.carrier != player

func is_ball_carried_by_teammate() -> bool:
	return is_ball_carried() and ball.carrier.team == player.team

func is_ball_carried_by_opponent() -> bool:
	return is_ball_carried() and ball.carrier.team != player.team

func player_is_on_tackle_distance(distance: float = 15.0) -> bool:
	return player.position.distance_to(ball.position) < distance

## Returns true when an opponent is carrying the ball AND is tackleable. A
## goalkeeper holding the ball in their hands is immune to tackles.
func carrier_is_tackleable() -> bool:
	return is_ball_carried_by_opponent() \
		and not (ball.carrier.role == Positions.Role.GK \
			and ball.carrier.current_state != null \
			and ball.carrier.current_state.is_holding_ball())

func has_opponents_nearby() -> bool:
	var players := opponent_detection_area.get_overlapping_bodies()
	return players.any(func(p: Player): return p.team != player.team)

func get_closest_teammate_in_view() -> Player:
	var players_in_view := teammate_detection_area.get_overlapping_bodies()
	var teammates_in_view := players_in_view.filter(
		func(p: Player): return p != player and p.team == player.team
	)
	teammates_in_view.sort_custom(
		func(p1: Player, p2: Player): return p1.position.distance_squared_to(player.position) < p2.position.distance_squared_to(player.position)
	)
	if teammates_in_view.size() > 0:
		return teammates_in_view[0]
	return null

func get_bicircular_weight(position: Vector2, center_target: Vector2, inner_circle_radius: float, inner_circle_weight: float, outer_circle_radius: float, outer_circle_weight: float) -> float:
	var distance_to_center := position.distance_to(center_target)
	if distance_to_center > outer_circle_radius:
		return outer_circle_weight
	elif distance_to_center < inner_circle_radius:
		return inner_circle_weight
	else:
		var distance_to_inner_radius := distance_to_center - inner_circle_radius
		var close_range_distance := outer_circle_radius - inner_circle_radius
		return lerpf(inner_circle_weight, outer_circle_weight, distance_to_inner_radius / close_range_distance)

## Picks the actual pass receiver at the moment PlayerStatePassing enters —
## kept here (delegating to OnBallUtility, the same scoring make_decisions
## uses to decide WHETHER to pass) so the state can lead the pass toward
## wherever that specific player is heading.
func get_best_pass_target() -> Player:
	return OnBallUtility.find_best_pass_target(player, player.get_teammates(), player.get_opponents(), target_goal)

func is_opponent_keeper_holding() -> bool:
	return ball.carrier != null \
		and ball.carrier.role == Positions.Role.GK \
		and ball.carrier.team != player.team \
		and ball.carrier.current_state != null \
		and ball.carrier.current_state.is_holding_ball()

func is_own_keeper_holding() -> bool:
	return ball.carrier != null \
		and ball.carrier.role == Positions.Role.GK \
		and ball.carrier.team == player.team \
		and ball.carrier.current_state != null \
		and ball.carrier.current_state.is_holding_ball()
