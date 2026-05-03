class_name RoleBehavior
extends Node

# ─── Context references ────────────────────────────────────────────────────────
var player: Player = null
var ball: Ball = null
var teammate_detection_area: Area2D = null
var ball_detection_area: Area2D = null
var opponent_detection_area: Area2D = null
var own_goal: Goal = null
var target_goal: Goal = null
var field_zones: FieldZones = null

# ─── Zone state ────────────────────────────────────────────────────────────────
## Radius within which the player activates fine behavior regardless of zone.
const PROXIMITY_RADIUS := 150.0

var home_zone: FieldZones.Zone = FieldZones.Zone.NONE
var current_zone: FieldZones.Zone = FieldZones.Zone.NONE
var target_zone: FieldZones.Zone = FieldZones.Zone.NONE
var _last_ball_zone: FieldZones.Zone = FieldZones.Zone.NONE
var _is_left_team: bool = false
## Cached result of is_fine_behavior_active() — updated once per tick.
var _fine_active: bool = true

func setup(context_player: Player, context_ball: Ball, context_teammate_detection: Area2D, context_ball_detection: Area2D, context_opponent_detection: Area2D, context_own_goal: Goal, context_target_goal: Goal) -> void:
	player = context_player
	ball = context_ball
	teammate_detection_area = context_teammate_detection
	ball_detection_area = context_ball_detection
	opponent_detection_area = context_opponent_detection
	own_goal = context_own_goal
	target_goal = context_target_goal
	# field_zones lookup is deferred to _ready() — get_tree() is null here

func _ready() -> void:
	field_zones = get_tree().get_first_node_in_group("field_zones") as FieldZones
	if field_zones:
		home_zone = field_zones.get_zone(player.spawn_position)
		_is_left_team = field_zones.is_left_zone(home_zone)
		target_zone = home_zone

# ─── Zone system — called once per AI tick by AIBehavior ──────────────────────

## Updates current_zone, recalculates target_zone if ball changed zones,
## and caches whether fine behavior should be active this tick.
func update_zone_state() -> void:
	if field_zones == null:
		_fine_active = true
		return
	var ball_zone := field_zones.get_zone(ball.position)
	if ball_zone != _last_ball_zone:
		_last_ball_zone = ball_zone
		target_zone = calculate_target_zone(ball_zone)
	current_zone = field_zones.get_zone(player.position)
	var in_target := current_zone == target_zone or target_zone == FieldZones.Zone.NONE
	var ball_nearby := player.position.distance_to(ball.position) < PROXIMITY_RADIUS
	_fine_active = in_target or ball_nearby

# ─── Overridable hooks ─────────────────────────────────────────────────────────

## Override in subclasses: target zone given the ball's current zone.
func calculate_target_zone(_ball_zone: FieldZones.Zone) -> FieldZones.Zone:
	return home_zone

## Override in subclasses: fine-grained steering when in target zone or close to ball.
func get_fine_positioning_force() -> Vector2:
	return Vector2.ZERO

## Override in subclasses: tactical decisions when in target zone or close to ball.
func make_fine_decisions() -> void:
	pass

# ─── Top-level API called by AIBehavior ───────────────────────────────────────

func get_positioning_force() -> Vector2:
	if _fine_active:
		return get_fine_positioning_force()
	return _get_navigate_force()

func make_decisions() -> void:
	if _fine_active:
		make_fine_decisions()

# ─── Navigation ───────────────────────────────────────────────────────────────

func _get_navigate_force() -> Vector2:
	if field_zones == null or target_zone == FieldZones.Zone.NONE:
		return Vector2.ZERO
	var next := field_zones.get_next_zone_toward(current_zone, target_zone)
	var destination := field_zones.get_zone_center(next)
	var direction := player.position.direction_to(destination)
	var dist := player.position.distance_to(destination)
	# Ease out as we approach the zone center
	var weight := clampf(dist / 80.0, 0.1, 1.0)
	return direction * weight

## Helper: get target zone from depth + ball position for this player's team side.
func _zone_from_depth(target_depth: int) -> FieldZones.Zone:
	return field_zones.get_zone_at_depth(target_depth, ball.position, _is_left_team)

# ─── Utility functions ────────────────────────────────────────────────────────

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
