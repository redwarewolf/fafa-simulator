class_name Player
extends CharacterBody2D

const DURATION_TACKLE := 200
const GRAVITY := 8.0
const BALL_CONTROL_HEIGHT_MAX := 10.0
## Reuses the celebration jump's height/height_velocity mechanic for a quick
## "dodge" hop when a tackle whiffs — smaller than PlayerStateCelebrating's
## JUMP_HEIGHT (2.0) so it reads as a dodge, not a goal celebration.
const DODGE_HOP_HEIGHT := 1.0
## Of tackles the tackler wins, the fraction the referee calls as a foul
## (HURT + a free kick) rather than a clean strip (DISPOSSESSED). See
## on_tackle_player().
const FOUL_CHANCE_ON_TACKLE_WIN := 0.20
const WALK_ANIM_THRESHOLD := 0.6
## Physics layer 5 ("Obstacle" in project.godot) — opted into by body types the
## ball should physically bounce off (see SpecialPlayerTypes.bounces_ball()).
const OBSTACLE_COLLISION_BIT := 1 << 4

## Fraction of full running speed (see `speed`) a carrier still moves at while
## controlling the ball, scaled by `dribbling` — a 0-rated dribbler barely
## keeps the ball at their feet and a 100-rated one is close to a flat sprint.
## Always strictly below 1.0: a defender running at full `speed` must be able
## to run down any dribbler in a straight foot race, or a pure chase (the
## presser/marker leading the carrier by its current velocity — see
## AIBehavior._press_target and RoleAI._marking_target_position) never
## converges and the defender just trails at a fixed distance forever.
const DRIBBLE_SPEED_MIN_FRACTION := 0.55
const DRIBBLE_SPEED_MAX_FRACTION := 0.92

enum State { MOVING, TACKLING, RECOVERING, PREPPING_SHOT, SHOOTING,
	PASSING, HEADER, VOLLEY_KICK, BICYCLE_KICK, CHEST_CONTROL, HURT, DIVING, HOLDING_BALL,
	CELEBRATING, MOURNING, DISPOSSESSED }

enum SkinColor { LIGHT, MEDIUM, DARK, RADIOACTIVE, DEMONIC, ALIEN, ROBOT }
enum HairColor { BLONDE, LIGHT_RED, GREEN, PURPLE, LIGHT_BROWN, DARK_BROWN, GRAY, DARK_RED, BLACK, DARK_BLUE, LIGHT_BLUE }
const TEAMS := [ "DEFAULT", "SACA CHISPAS", "LOS FULBOS FC", "CLUB ATLETICO PIÑATA", "DEPORTIVO LADRILLO", "UNION PATADURAS", "ATLÉTICO GAMBETA", "SAN LORENZO DE NADA", "RACING DE LA ESQUINA" ]

var ai_behavior : AIBehavior = AIBehavior.new()

@export var own_goal : Goal
@export var target_goal : Goal

# STATS
var full_name : String = ""
var role : Positions.Role
## True when this player defends the LEFT goal. Comes from the goals they were
## handed, never from where they happen to stand: RoleAI used to infer it
## from the zone containing spawn_position, so a forward anchored in the
## opponent half read as playing for the other team and had its whole depth
## logic mirrored.
var is_left_team : bool = true
## Where the tactic wants this player once the shape is settled, in world space.
## Distinct from spawn_position, which is the compressed kickoff spot: an anchor
## in the opponent half is a legitimate instruction, a kickoff there is not.
## Defaults to the spawn point for the non-tactic spawn path.
var anchor_position : Vector2 = Vector2.ZERO
var skin : Player.SkinColor
var hair : Player.HairColor
var team : String = ""
## Which spritesheet to render — see BodyTypes.
var body_type : String = "default"
## Which behavioural archetype this player is — see SpecialPlayerTypes. ""
## means an ordinary player.
var special_type : String = ""
@export var speed : float = 80
@export var power : float = 70
@export var defense : float = 50
@export var dribbling : float = 50
@export var passing : float = 50
@export var physicality : float = 50
## Personality trait copied from PlayerResource.teamplay — see there.
var teamplay : float = 50

## Kept for stamina read/write-back only (see stamina below) — everything
## else about this player already got copied into plain fields above.
var player_data : PlayerResource = null
## Live in-match value, seeded from PlayerResource.stamina and depleted over
## the match by _process() — PlayerResource.stamina itself is a runtime-only,
## not-persisted attribute (see there), so this is the only place a match
## actually experiences fatigue; MatchWorld writes the end-of-match value
## back to player_data.stamina (see MatchWorld._transition's GAMEOVER
## branch) and SeasonManager.resolve_day() recovers it on a rest day. See
## docs/ai-overhaul.md Phase 5.
var stamina : float = 100.0
## Baseline depletion per second, plus an activity-scaled extra term so
## sprinting drains faster than jogging/standing — see get_stamina_factor().
## Tuned so a mostly-active outfield player over MatchWorld.MATCH_DURATION
## (360s, representing 90 minutes) ends up noticeably but not crushingly
## tired; flagged as a Phase 6 tuning candidate.
const STAMINA_DECAY_PER_SEC := 0.11
const STAMINA_DECAY_ACTIVITY_SCALE := 0.09
## Speed multiplier at 0 stamina — never below this, so fatigue is felt
## without a fully-drained player becoming unable to function.
const STAMINA_FACTOR_MIN := 0.7

## Effective move-speed multiplier from current fatigue — Locomotion applies
## this on top of `speed`/get_dribble_speed().
func get_stamina_factor() -> float:
	return lerpf(STAMINA_FACTOR_MIN, 1.0, stamina / 100.0)

## Effective move speed while this player is the one controlling the ball —
## see DRIBBLE_SPEED_MIN/MAX_FRACTION. Locomotion.compute_velocity picks this
## over `speed` whenever ball.carrier == player.
func get_dribble_speed() -> float:
	var skill_fraction := lerpf(DRIBBLE_SPEED_MIN_FRACTION, DRIBBLE_SPEED_MAX_FRACTION, dribbling / 100.0)
	return speed * skill_fraction

var current_state: PlayerState = null
var state_factory := PlayerStateFactory.new()
var _current_state_type : State = State.MOVING  # Tracked for debug label

var spawn_position := Vector2.ZERO
## Opponent this player is currently shadowing goal-side, or null for pure
## ball-depth positioning. Written once per team tick by TeamTacticalState —
## see scenes/characters/ai/team_tactical_state.gd.
var mark_target: Player = null
## 0 = tight man-marking, 1 = fully loose (danger-based falloff from own goal).
var mark_tightness: float = 0.0
## Reverse lookup: who is marking ME. Read by off-ball attacking logic to
## decide whether making a run to lose a marker is worthwhile.
var marked_by: Player = null
## 0 = primary presser (closest to the ball/carrier), -1 = not pressing.
## Written once per team tick by TeamTacticalState.
var pressing_rank: int = -1
## True for the single next-closest teammate to a pressed opponent carrier —
## interposes between the carrier and the opponents' most dangerous other
## option (cover_shadow_point) instead of also converging on the ball like
## pressing_rank==0 does. Written once per team tick by TeamTacticalState.
var is_cover_presser: bool = false
var cover_shadow_point: Vector2 = Vector2.ZERO
## Shared per-team adjustment every player's ball-depth positioning is
## nudged by — the piece of team shape that isn't already implied by same-
## role players independently computing the same depth formula off the same
## ball position. Written once per team tick by TeamTacticalState.
var team_line_bias: float = 0.0
## True only for the single player MatchWorld leaves unfrozen during a FOUL
## or KICKOFF restart (see MatchWorld._free_kick_taker/_kickoff_taker). Makes
## AIBehavior steer straight at the ball regardless of pressing_rank/marking,
## since those are computed team-wide and can hand "go get it" duty to a
## frozen teammate who has no way to act on it — see AIBehavior.perform_ai_movement().
var is_restart_taker: bool = false
var heading := Vector2.RIGHT
var height := 0.0
var height_velocity := 0.0
var ball : Ball

var teammates : Array[Player] = []
## The other eleven. Set alongside teammates by ActorsContainer — several
## behaviours need to ask "how crowded is that spot" and had no way to see the
## opposition except through their own small detection area.
var opponents : Array[Player] = []

@onready var animation_player : AnimationPlayer = %AnimationPlayer
@onready var player_sprite : Sprite2D = %PlayerSprite
@onready var teammate_detection_area : Area2D = %TeammateDetectionArea
@onready var ball_detection_area : Area2D = %BallDetectionArea
@onready var tackle_damage_emitter_area : Area2D = %TackleDamageEmitterArea
@onready var opponent_detection_area : Area2D = %OpponentDetectionArea
@onready var goalie_hands_collider : CollisionShape2D = %GoalieHandsCollider
@onready var team_indicator : Sprite2D = %TeamIndicator

const _INDICATOR_1P := preload("res://assets/art/characters/1p.png")
const _INDICATOR_2P := preload("res://assets/art/characters/2p.png")

## [param context_slot_role] is the position this player was actually fielded
## in (the tactic slot), which may differ from their own best position. AI
## behaviour, roaming and stat weighting all follow the SLOT so a manager can
## plug any body into a gap (e.g. an outfielder deputising in goal) and have
## them actually play that role, not their card's. Positions.aptitude() then
## grades how well their own position covers it and applies a small stat
## buff/debuff (see get_effective_stat_for_role) so the trade-off is felt
## without making an emergency reshuffle unplayable.
func initialize(context_position : Vector2, context_ball : Ball, context_own_goal: Goal, context_target_goal: Goal, context_player_data : PlayerResource, context_team: String, context_slot_role : Positions.Role) -> Player:
		position = context_position
		ball = context_ball
		own_goal = context_own_goal
		target_goal = context_target_goal
		is_left_team = own_goal.position.x < target_goal.position.x
		anchor_position = context_position
		role = context_slot_role
		var apt_pct := Positions.aptitude_stat_pct(Positions.aptitude(context_player_data.role, role))
		power = context_player_data.get_effective_stat_for_role("sho", apt_pct)
		speed = context_player_data.get_effective_stat_for_role("pac", apt_pct)
		defense = context_player_data.get_effective_stat_for_role("def", apt_pct)
		dribbling = context_player_data.get_effective_stat_for_role("dri", apt_pct)
		passing = context_player_data.get_effective_stat_for_role("pas", apt_pct)
		physicality = context_player_data.get_effective_stat_for_role("phy", apt_pct)
		teamplay = context_player_data.teamplay
		player_data = context_player_data
		stamina = context_player_data.stamina
		full_name = context_player_data.full_name
		skin = context_player_data.skin_color
		hair = context_player_data.hair_color
		body_type = context_player_data.body_type
		special_type = context_player_data.special_type
		heading = Vector2.LEFT if target_goal.position.x < position.x else Vector2.RIGHT
		team = context_team
		return self

func _ready() -> void:
	spawn_position = position
	setup_ai_behavior()
	apply_body_type()
	set_shader_properties()
	team_indicator.texture = _INDICATOR_1P if is_left_team else _INDICATOR_2P
	switch_state(State.MOVING)
	tackle_damage_emitter_area.body_entered.connect(on_tackle_player.bind())
	# Enable GoalieHands physics collider only for a moving goalkeeper — a
	# special type stuck in goal (e.g. a cone) shouldn't get functioning hands.
	goalie_hands_collider.disabled = (role != Positions.Role.GK) or not SpecialPlayerTypes.movable(special_type)
	if DebugDraw.ENABLED:
		_setup_debug_label()

## Swaps the sprite to this player's body type's spritesheet/grid, and opts
## the instance into physical ball collision if that body type calls for it
## (see BodyTypes / SpecialPlayerTypes.bounces_ball()).
func apply_body_type() -> void:
	var body_def : Dictionary = BodyTypes.DATA.get(body_type, BodyTypes.DATA["default"])
	player_sprite.texture = body_def["texture"]
	player_sprite.hframes = body_def["hframes"]
	player_sprite.vframes = body_def["vframes"]
	if SpecialPlayerTypes.bounces_ball(special_type):
		collision_layer |= OBSTACLE_COLLISION_BIT

## Plays [param name] from this player's body type's own AnimationLibrary when
## it declares one and has that animation, otherwise falls back to the shared
## default library — lets a body type with a divergent frame layout (e.g. the
## cone's narrower grid) override only the animations it actually needs.
func play_anim(name: String) -> void:
	var body_def : Dictionary = BodyTypes.DATA.get(body_type, {})
	var lib : String = body_def.get("animation_library", "")
	var qualified := "%s/%s" % [lib, name]
	if lib != "" and animation_player.has_animation(qualified):
		animation_player.play(qualified)
	else:
		animation_player.play(name)

func _process(delta: float) -> void:
	set_heading()
	flip_sprites()
	process_gravity(delta)
	move_and_slide()
	_process_stamina(delta)

## Only depletes while this node is actually processing — frozen restart/
## kickoff/foul players (PROCESS_MODE_DISABLED) and a paused EVENT/GAMEOVER
## match correctly don't tire, since Godot simply never calls this. Activity
## is read off how much of top speed the player is currently using, not
## whether they're the ball carrier — a presser sprinting to close down the
## ball tires the same as a carrier sprinting away from one.
func _process_stamina(delta: float) -> void:
	var activity := velocity.length() / maxf(speed, 1.0)
	var decay := STAMINA_DECAY_PER_SEC + activity * STAMINA_DECAY_ACTIVITY_SCALE
	stamina = clampf(stamina - decay * delta, 0.0, 100.0)
	# Keep GoalieHands AnimatableBody2D synced to our world position so
	# the physics engine sees it at the correct location every frame.
	if role == Positions.Role.GK:
		goalie_hands_collider.get_parent().global_position = global_position
	if DebugDraw.ENABLED:
		_update_debug_label()
	
func process_gravity(delta: float) -> void:
	if height > 0:
		height_velocity -= GRAVITY * delta
		height += height_velocity
		height = max(0, height)
	player_sprite.position = Vector2.UP * height

func switch_state(state: State, state_data: PlayerStateData = PlayerStateData.new()) -> void:
	if DebugDraw.ENABLED:
		var from_name: String = State.keys()[_current_state_type] if current_state != null else "START"
		print("[%s] %s → %s" % [full_name if full_name != "" else "Player", from_name, State.keys()[state]])
	_current_state_type = state
	if current_state != null:
		current_state.queue_free()
	current_state = state_factory.get_fresh_state(state)
	current_state.setup(self, state_data, animation_player, ball, teammate_detection_area, ball_detection_area, own_goal, target_goal, tackle_damage_emitter_area,ai_behavior)
	current_state.state_transition_requested.connect(switch_state.bind())
	current_state.name = "PlayerStateMachine: " + str(state)
	call_deferred("add_child", current_state)


func set_heading() -> void:
	if velocity.x > 0:
		heading = Vector2.RIGHT
	elif velocity.x < 0:
		heading = Vector2.LEFT

func flip_sprites() -> void:
	if heading == Vector2.RIGHT:
		player_sprite.flip_h = false
		tackle_damage_emitter_area.scale.x = 1
		opponent_detection_area.scale.x = 1
		teammate_detection_area.scale.x = 1
	elif heading == Vector2.LEFT:
		player_sprite.flip_h = true
		tackle_damage_emitter_area.scale.x = -1
		opponent_detection_area.scale.x = -1
		teammate_detection_area.scale.x = -1
		
func has_ball() -> bool:
	return ball.carrier == self

func can_carry_ball() -> bool:
	if not SpecialPlayerTypes.can_hold_ball(special_type):
		return false
	return current_state != null and current_state.can_carry_ball()
	
func on_animation_complete() -> void:
	if current_state != null:
		current_state.on_animation_complete()
		
func control_ball() -> void:
	if ball.height > BALL_CONTROL_HEIGHT_MAX:
		switch_state(Player.State.CHEST_CONTROL)

func set_shader_properties() -> void:
	player_sprite.material.set_shader_parameter("skin_color", skin)
	player_sprite.material.set_shader_parameter("hair_color", hair)
	var team_color := TEAMS.find(team)
	team_color = clampi(team_color,0, TEAMS.size()-1)
	player_sprite.material.set_shader_parameter("team_color", team_color)

func setup_ai_behavior() -> void:
	ai_behavior.setup(self, ball, opponent_detection_area)
	ai_behavior.name = 'AI Behavior'
	add_child(ai_behavior)
	
func is_facing_target_goal() -> bool:
	var direction_to_target_goal := position.direction_to(target_goal.position)
	return heading.dot(direction_to_target_goal) > 0

func face_towards_target_goal() -> void:
	if not is_facing_target_goal():
		heading = -heading

func get_teammates() -> Array[Player]:
	return teammates

func get_opponents() -> Array[Player]:
	return opponents
	
func get_hurt(hurt_origin : Vector2) -> void:
	switch_state(Player.State.HURT, PlayerStateData.build().set_hurt_direction(hurt_origin))

## Clean dispossession — tackle won, but not called as a foul. See on_tackle_player().
func get_dispossessed(hurt_origin : Vector2) -> void:
	switch_state(Player.State.DISPOSSESSED, PlayerStateData.build().set_hurt_direction(hurt_origin))

func on_tackle_player(player_hit : Player) -> void:
	if player_hit != self and player_hit.team != team and player_hit == ball.carrier:
		if player_hit.current_state != null and player_hit.current_state.is_holding_ball():
			return  # Keeper holding the ball is immune to tackles
		if not _wins_tackle_duel(player_hit):
			player_hit.dodge_hop()  # Tackle whiffs — carrier hops away and keeps the ball
			return
		if randf() < FOUL_CHANCE_ON_TACKLE_WIN:
			var incident_position := player_hit.position
			player_hit.get_hurt(position.direction_to(player_hit.position))
			GameEvents.foul_called.emit(player_hit, incident_position)
		else:
			player_hit.get_dispossessed(position.direction_to(player_hit.position))

## Small vertical hop that visually reads as dodging a failed tackle, without
## touching state/animation — the ball carrier keeps full control.
func dodge_hop() -> void:
	if height <= 0.0:
		height = 0.1
		height_velocity = DODGE_HOP_HEIGHT

## Tackle success is a contest between the tackler's DEF and the carrier's DRI.
## Equal stats → 50/50. Clamped so no stat gap makes the outcome a certainty.
func _wins_tackle_duel(carrier: Player) -> bool:
	var win_chance := clampf(0.5 + (defense - carrier.dribbling) / 200.0, 0.1, 0.9)
	return randf() < win_chance

# ─── Debug helpers ────────────────────────────────────────────────────────────

func _setup_debug_label() -> void:
	var label := Label.new()
	label.name = "DebugLabel"
	label.add_theme_font_size_override("font_size", 9)
	label.position = Vector2(-20, -50)
	label.z_index = 100
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 0, 0)  # Red for readability against grass
	add_child(label)

func _update_debug_label() -> void:
	var label := get_node_or_null("DebugLabel") as Label
	if label == null:
		return
	var display_name := full_name.substr(0, 10) if full_name != "" else team
	var role_str := Positions.label(role)
	var state_str: String = State.keys()[_current_state_type]
	label.text = display_name + " - " + role_str + "\n" + state_str
