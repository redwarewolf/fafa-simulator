class_name AIBehavior
extends Node

const DURATION_AI_TICK_FREQUENCY := 200

var ball: Ball = null
var player: Player = null
var time_since_last_ai_tick := Time.get_ticks_msec()
var opponent_detection_area: Area2D = null

var role_behavior: RoleBehavior = null
var role_behavior_factory: AIBehaviorFactory = AIBehaviorFactory.new()

func _ready() -> void:
	time_since_last_ai_tick = Time.get_ticks_msec() + randi_range(0, DURATION_AI_TICK_FREQUENCY)

func setup(context_player: Player, context_ball: Ball, context_opponent_detection_area: Area2D) -> void:
	player = context_player
	ball = context_ball
	opponent_detection_area = context_opponent_detection_area
	setup_role_behavior()

func setup_role_behavior() -> void:
	role_behavior = role_behavior_factory.get_role_behavior(player.role)
	role_behavior.name = "RoleBehavior"
	add_child(role_behavior)
	role_behavior.setup(
		player,
		ball,
		player.teammate_detection_area,
		player.ball_detection_area,
		opponent_detection_area,
		player.own_goal,
		player.target_goal
	)

func process_ai() -> void:
	if Time.get_ticks_msec() - time_since_last_ai_tick > DURATION_AI_TICK_FREQUENCY:
		time_since_last_ai_tick = Time.get_ticks_msec()
		if role_behavior:
			role_behavior.update_zone_state()
		perform_ai_movement()
		perform_ai_decisions()
	
func perform_ai_movement() -> void:
	var total_steering_force := Vector2.ZERO

	# 1. Role-specific positioning (Delegated)
	if role_behavior:
		total_steering_force += role_behavior.get_positioning_force()

	# 2. Universal behaviors (Applies to all roles)
	total_steering_force += get_teammate_repulsion_force()

	# 3. Carrier avoids nearby opponents so they don't walk straight into them
	if player.has_ball():
		total_steering_force += get_opponent_avoidance_force()

	total_steering_force = total_steering_force.limit_length(1.0)

	player.velocity = total_steering_force * player.speed

func get_opponent_avoidance_force() -> Vector2:
	var avoidance := Vector2.ZERO
	# Use heading as the approximate travel direction
	var travel_dir := player.heading

	for body in opponent_detection_area.get_overlapping_bodies():
		if body is Player:
			var to_opponent := body.position - player.position
			var dist := to_opponent.length()
			if dist < 1.0 or dist >= 60.0:
				continue
			var to_opp_norm := to_opponent / dist
			# Only react to opponents that are roughly ahead of us
			var ahead_dot := travel_dir.dot(to_opp_norm)
			if ahead_dot < 0.2:
				continue
			# Push perpendicular (90°) to our travel direction — steer around, not backward.
			# Determine which side: if opponent is to our left (cross > 0) go right, else go left.
			var perp := Vector2(-travel_dir.y, travel_dir.x)  # 90° left of travel
			var cross := travel_dir.cross(to_opp_norm)
			if cross > 0:
				perp = -perp  # opponent is left of us, go right instead
			var weight := (60.0 - dist) / 60.0
			avoidance += perp * weight * 2.5  # Strong enough to meaningfully steer around

	return avoidance

func get_teammate_repulsion_force() -> Vector2:
	var repulsion := Vector2.ZERO

	for other in player.get_teammates():
		if other == player:
			continue

		var dist := player.position.distance_to(other.position)

		if dist < 60:
			var push := (player.position - other.position).normalized() * (60 - dist)
			repulsion += push

	return repulsion

	
func perform_ai_decisions() -> void:
	# Delegate decision making to role behavior
	if role_behavior:
		role_behavior.make_decisions()

func _process(_delta: float) -> void:
	if not DebugDraw.ENABLED:
		return
	# Gray circle — fine-behavior activation radius (when zone proximity overrides zone navigation)
	DebugDraw.circle(player.position, RoleBehavior.PROXIMITY_RADIUS, Color(0.7, 0.7, 0.7))

## Reads the radius of the first CircleShape2D or CapsuleShape2D found on an Area2D.
func _get_area_radius(area: Area2D) -> float:
	if area == null:
		return 0.0
	for child in area.get_children():
		if child is CollisionShape2D:
			var s: Shape2D = child.shape
			if s is CircleShape2D:
				return s.radius
			elif s is CapsuleShape2D:
				return s.radius
	return 0.0
