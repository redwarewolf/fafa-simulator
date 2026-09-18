class_name AIBehavior
extends Node

const DURATION_AI_TICK_FREQUENCY := 200

var ball: Ball = null
var player: Player = null
var time_since_last_ai_tick := Time.get_ticks_msec()
var opponent_detection_area: Area2D = null

var role_ai: RoleAI = null
var role_ai_factory: AIBehaviorFactory = AIBehaviorFactory.new()

## Cached each perform_ai_movement tick purely for SHOW_INTENT_LINES — what
## point this player is currently steering toward, and why (press/mark/role),
## so debug draw can show it every frame without recomputing.
var _debug_intent_target: Vector2 = Vector2.ZERO
var _debug_intent_kind: String = ""

func _ready() -> void:
	time_since_last_ai_tick = Time.get_ticks_msec() + randi_range(0, DURATION_AI_TICK_FREQUENCY)

func setup(context_player: Player, context_ball: Ball, context_opponent_detection_area: Area2D) -> void:
	player = context_player
	ball = context_ball
	opponent_detection_area = context_opponent_detection_area
	setup_role_ai()

func setup_role_ai() -> void:
	role_ai = role_ai_factory.get_role_ai(player.role)
	role_ai.name = "RoleAI"
	add_child(role_ai)
	role_ai.setup(
		player,
		ball,
		player.teammate_detection_area,
		player.ball_detection_area,
		opponent_detection_area,
		player.own_goal,
		player.target_goal
	)

func process_ai() -> void:
	if not SpecialPlayerTypes.movable(player.special_type):
		return
	if Time.get_ticks_msec() - time_since_last_ai_tick > DURATION_AI_TICK_FREQUENCY:
		time_since_last_ai_tick = Time.get_ticks_msec()
		perform_ai_movement()
		perform_ai_decisions()

## player.pressing_rank/mark_target/mark_tightness/marked_by are written once
## per team, per tick, by TeamTacticalState (see scenes/world/actors_container.gd)
## — not recomputed independently here the way the old per-player pressing
## rank was, which had no memory and could flip every tick.
func perform_ai_movement() -> void:
	# Reset every tick before any branch runs, so a stale sprint flag from a
	# tick where this player was making a run can't survive into a tick
	# where they've become a presser/cover-presser instead — only
	# RoleAI._apply_run_support sets it back to true, and only that same
	# tick, if it's still actually triggered.
	player.is_making_run = false
	# Restart taker (see Player.is_restart_taker): the only unfrozen player
	# during a FOUL/KICKOFF, so pressing_rank/mark_target — team-wide state
	# that ignores frozen players — can't be trusted to point them at the
	# ball. Go straight there, unconditionally.
	if player.is_restart_taker:
		var restart_target := _press_target()
		_debug_intent_target = restart_target
		_debug_intent_kind = "press"
		player.velocity = player.position.direction_to(restart_target) * player.speed * player.get_stamina_factor()
		return
	# Primary presser: close down the carrier/ball, bypassing formation and
	# marking. Any outfield player can be the presser — role doesn't matter,
	# only distance (and commitment — see TeamTacticalState).
	if player.pressing_rank == 0:
		var press_target := _press_target()
		_debug_intent_target = press_target
		_debug_intent_kind = "press"
		player.velocity = player.position.direction_to(press_target) * player.speed * player.get_stamina_factor()
		return
	# Cover presser: interpose between the carrier and the opponents' next
	# most dangerous option instead of running the normal role/marking
	# target — see TeamTacticalState._recompute_cover_presser.
	if player.is_cover_presser:
		var cover_target := player.cover_shadow_point
		_debug_intent_target = cover_target
		_debug_intent_kind = "cover"
		player.velocity = Locomotion.compute_velocity(player, cover_target, ball, opponent_detection_area)
		return

	var target := role_ai.get_target_position() if role_ai else player.position
	_debug_intent_target = target
	_debug_intent_kind = "mark" if player.mark_target != null else "role"
	player.velocity = Locomotion.compute_velocity(player, target, ball, opponent_detection_area)

## Leads the carrier by their current velocity instead of aiming at their
## current position. A pure "chase the current position" presser can never
## close the gap on a carrier moving away at comparable speed — it just
## trails a fixed distance behind forever, which reads as "no one is even
## trying to intercept." Aiming ahead lets the presser cut the angle instead.
func _press_target() -> Vector2:
	if ball.carrier == null:
		return ball.position
	var carrier := ball.carrier
	var lead_time := clampf(player.position.distance_to(carrier.position) / maxf(player.speed, 1.0), 0.0, 1.0)
	return carrier.position + carrier.velocity * lead_time

func perform_ai_decisions() -> void:
	if player.pressing_rank == 0:
		# Only tackle when there is an opponent carrier to dispossess. For a
		# loose ball, just reach it — the carry mechanic picks it up
		# automatically. Triggering TACKLING on a loose ball causes an
		# infinite loop (tackle → recover → repeat).
		if ball.carrier != null and ball.carrier.team != player.team \
				and not (ball.carrier.role == Positions.Role.GK \
					and ball.carrier.current_state != null \
					and ball.carrier.current_state.is_holding_ball()) \
				and player.position.distance_to(ball.position) < RoleAI.TACKLE_DISTANCE:
			player.switch_state(Player.State.TACKLING)
		return  # Skip normal role decisions while pressing

	if role_ai:
		role_ai.make_decisions()

func _process(_delta: float) -> void:
	if not DebugDraw.ENABLED:
		return
	if role_ai:
		role_ai.draw_debug()
	if DebugDraw.SHOW_PRESSING_LINES and player.pressing_rank == 0 and ball.carrier != null:
		DebugDraw.line(player.position, ball.carrier.position, Color(1, 0, 0, 0.9))  # red — primary presser
	if DebugDraw.SHOW_PRESSING_LINES and player.is_cover_presser:
		DebugDraw.line(player.position, player.cover_shadow_point, Color(1, 0.6, 0, 0.9))  # orange — cover presser
	if DebugDraw.SHOW_MARKING_LINES and player.mark_target != null:
		DebugDraw.line(player.position, player.mark_target.position, Color(1, 1, 0, 0.7))  # yellow — marking assignment
	if DebugDraw.SHOW_INTENT_LINES and _debug_intent_kind != "":
		var color := Color.WHITE
		match _debug_intent_kind:
			"press": color = Color(1, 0, 0, 0.9)     # red — closing the carrier
			"cover": color = Color(1, 0.6, 0, 0.9)    # orange — cover-shadowing a passing lane
			"mark": color = Color(1, 1, 0, 0.9)       # yellow — tracking an assigned mark
			"role": color = Color(0.2, 1, 0.4, 0.9)   # green — formation/off-ball positioning
		DebugDraw.line(player.position, _debug_intent_target, color)
		DebugDraw.cross(_debug_intent_target, color, 6.0)
