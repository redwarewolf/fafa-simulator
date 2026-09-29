class_name Player
extends CharacterBody2D

const DURATION_TACKLE := 200
## A defender within this distance of the ball can commit to a tackle. It has
## to cover the tackler's own lunge plus normal steering imprecision — at 20 a
## presser that looked "right there" kept running alongside without ever
## committing.
const TACKLE_DISTANCE := 32.0
const GRAVITY := 8.0
const BALL_CONTROL_HEIGHT_MAX := 10.0
## Highest ball (height px) a standing outfield player can collect — about
## chest/head reach. A lofted ball above this flies OVER players instead of
## sticking to whoever it passes above: the ball's pickup Area2D is flat 2D,
## so before this check anyone under the flight path "caught" it mid-air —
## 28-38% of lofted passes ended that way in the pass tracer, the real cause
## of the recurring "long passes fall short" bug. See docs/match-engine-v2.md
## Findings #5.
const MAX_COLLECT_HEIGHT := 20.0

## First touch. Controlling a fast or dropping ball is harder than a slow
## ground pass; a failed touch knocks the ball loose instead of sticking to
## the player's feet. Before this, every ball within reach stuck instantly, so
## a 40m lofted pass was as safe as a 5m roll — which made hoofing long from
## the back the rational choice for the v2 AI (94-96% of its passes from its
## own third went forward, averaging 32-36m). See docs/match-engine-v2.md
## Findings #6. Difficulty rises with arrival speed above
## TOUCH_EASY_SPEED and with height above BALL_CONTROL_HEIGHT_MAX; skill
## (dribbling, then passing) cancels up to TOUCH_SKILL_MITIGATION of it.
const TOUCH_EASY_SPEED := 160.0
const TOUCH_SPEED_RANGE := 380.0
const TOUCH_SPEED_WEIGHT := 0.55
const TOUCH_HEIGHT_WEIGHT := 0.25
const TOUCH_SKILL_MITIGATION := 0.75

## Probability this player cleanly controls a ball arriving at [param speed]
## (px/s) and [param ball_height].
func control_chance(speed: float, ball_height: float) -> float:
	return control_chance_for(dribbling, passing, speed, ball_height)

static func control_chance_for(dri: float, pas: float, speed: float, ball_height: float) -> float:
	var difficulty := clampf((speed - TOUCH_EASY_SPEED) / TOUCH_SPEED_RANGE, 0.0, 1.0) * TOUCH_SPEED_WEIGHT
	if ball_height > BALL_CONTROL_HEIGHT_MAX:
		difficulty += TOUCH_HEIGHT_WEIGHT
	var skill := (0.7 * dri + 0.3 * pas) / 100.0
	return clampf(1.0 - difficulty * (1.0 - TOUCH_SKILL_MITIGATION * skill), 0.05, 1.0)
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
## presser leading the carrier by its current velocity — see PlayerBrain's
## PRESS job) never converges and the defender just trails at a fixed
## distance forever.
const DRIBBLE_SPEED_MIN_FRACTION := 0.55
const DRIBBLE_SPEED_MAX_FRACTION := 0.92

enum State { MOVING, TACKLING, RECOVERING, PREPPING_SHOT, SHOOTING,
	PASSING, HEADER, VOLLEY_KICK, BICYCLE_KICK, CHEST_CONTROL, HURT, DIVING, HOLDING_BALL,
	CELEBRATING, MOURNING, DISPOSSESSED }

enum SkinColor { LIGHT, MEDIUM, DARK, RADIOACTIVE, DEMONIC, ALIEN, ROBOT }
## The ordinary human tones — every player PlayerFactory rolls for the player's
## own club (initial roster, scouting pool, youth academy) is restricted to
## these. The rest (RADIOACTIVE, DEMONIC, ALIEN, ROBOT) are reserved for
## special types like the lab's zombies (see ZombieFactory) and are otherwise
## free to appear on AI-controlled clubs.
const NORMAL_SKIN_COLORS : Array = [SkinColor.LIGHT, SkinColor.MEDIUM, SkinColor.DARK]
enum HairColor { BLONDE, LIGHT_RED, GREEN, PURPLE, LIGHT_BROWN, DARK_BROWN, GRAY, DARK_RED, BLACK, DARK_BLUE, LIGHT_BLUE }
const TEAMS := [ "DEFAULT", "SACA CHISPAS", "LOS FULBOS FC", "CLUB ATLETICO PIÑATA", "DEPORTIVO LADRILLO", "UNION PATADURAS", "ATLÉTICO GAMBETA", "SAN LORENZO DE NADA", "RACING DE LA ESQUINA" ]

var ai_behavior : AIBehavior = AIBehavior.new()
## The player's match AI (docs/match-engine-v2.md), set by ActorsContainer:
## a PlayerBrain for movable outfield players, a GoalkeeperBrain for a
## movable keeper. AIBehavior hands each frame to whichever is set.
var brain : PlayerBrain = null
var keeper_brain : GoalkeeperBrain = null

@export var own_goal : Goal
@export var target_goal : Goal

# STATS
var full_name : String = ""
var role : Positions.Role
## True when this player defends the LEFT goal. Comes from the goals they were
## handed, never from where they happen to stand: inferring it from the zone
## containing spawn_position made a forward anchored in the opponent half
## read as playing for the other team.
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
## The PAC stat (0-100). `speed` above is the MOVEMENT speed in px/s: for v1
## players it's the raw stat (as it always was); engine-v2 players get a
## realistic speed from it (apply_realistic_movement). Stat-based formulas
## (mental attributes, keeper reflexes) read `pace`.
var pace : float = 80

# ─── Engine-v2 movement (docs/match-engine-v2.md Phase 7, Findings #9) ──────
## Top (sprint) speed range, m/s, from PAC 0 → 100. Real footballers sprint
## at ~7-9.5 m/s; the raw-stat speed gave only ~2.4-4.8 m/s.
const TOP_SPEED_MIN_MS := 6.4
const TOP_SPEED_MAX_MS := 9.4
## Acceleration range, m/s², from the pace/physicality blend; braking is
## BRAKE_FACTOR times quicker. Real players reach ~5 m/s in about a second.
const ACCEL_MIN_MS2 := 3.2
const ACCEL_MAX_MS2 := 5.5
const BRAKE_FACTOR := 1.8
## Acceleration limit in px/s² (0 = instantaneous, the v1 behaviour).
var max_accel : float = 0.0

## Engine-v2 players: movement speed and acceleration in real units. `speed`
## stays the RUNNING speed the codebase has always multiplied by
## Locomotion.SPRINT_MULTIPLIER for a sprint, so top speed = speed × 1.25.
func apply_realistic_movement() -> void:
	var px_per_m := 1.0 / PitchSpace.metres_per_px().x
	var top := lerpf(TOP_SPEED_MIN_MS, TOP_SPEED_MAX_MS, pace / 100.0) * px_per_m
	speed = top / Locomotion.SPRINT_MULTIPLIER
	var agility := (0.6 * pace + 0.4 * physicality) / 100.0
	max_accel = lerpf(ACCEL_MIN_MS2, ACCEL_MAX_MS2, agility) * px_per_m

## Moves velocity toward [param desired] within the acceleration limits —
## turning and stopping take time, so runs curve and a player committed one
## way can't instantly reverse.
##
## Works in true distance (PitchSpace iso space): [param desired] gives the
## DIRECTION on screen, and its length is read as a real speed in along-pitch
## px/s — the units every brain already uses (`speed`, `max_accel`). Moving
## up/down the screen therefore covers the same metres per second as moving
## along it (it used to be 1.62× faster; see PitchSpace.ISO_Y).
func steer_velocity(desired: Vector2, delta: float) -> void:
	var d_iso := PitchSpace.iso(desired)
	if d_iso != Vector2.ZERO:
		d_iso = d_iso.normalized() * desired.length()
	if max_accel <= 0.0 or delta <= 0.0:
		velocity = PitchSpace.from_iso(d_iso)
		return
	var v_iso := PitchSpace.iso(velocity)
	# Braking/turning (the desired vector doesn't extend the current one)
	# uses the stronger braking limit.
	var extending := d_iso.length() >= v_iso.length() and d_iso.dot(v_iso) >= 0.0
	var limit := max_accel * (1.0 if extending else BRAKE_FACTOR) * delta
	velocity = PitchSpace.from_iso(v_iso.move_toward(d_iso, limit))

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
## ends up noticeably but not crushingly tired; flagged as a Phase 6 tuning
## candidate. Originally 0.11 / 0.09 for a 360s match; scaled by 360/480 when
## matches became two 240s halves, so end-of-match fatigue is unchanged.
const STAMINA_DECAY_PER_SEC := 0.0825
const STAMINA_DECAY_ACTIVITY_SCALE := 0.0675
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
## Opponent this player is marking (PlayerBrain, from a TeamBrain MARK job),
## or null. Locomotion's avoidance ignores them so the marker can stay tight.
var mark_target: Player = null
## True for the player MatchWorld designates to take a kickoff or set piece
## (MatchWorld._restart_taker/_kickoff_taker): PlayerBrain holds them behind
## the ball until the restart is ready, then sends them onto it.
var is_restart_taker: bool = false
## Set by MatchWorld when play resumes from a set piece this player took:
## their next on-ball decision is a pass (a throw-in/corner/free kick is
## played, not dribbled off with). Consumed by PlayerBrain._act_on_ball().
var restart_pass_pending: bool = false
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
		pace = speed
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
			GameEvents.tackle_resolved.emit(self, player_hit, false, false)
			player_hit.dodge_hop()  # Tackle whiffs — carrier hops away and keeps the ball
			return
		ball.play_kick_sound()  # Won the duel — the ball changes feet, same as any other kick
		ball.last_touch = self
		if MatchRng.randf() < _foul_chance(player_hit):
			GameEvents.tackle_resolved.emit(self, player_hit, true, true)
			var incident_position := player_hit.position
			player_hit.get_hurt(position.direction_to(player_hit.position))
			GameEvents.foul_called.emit(player_hit, incident_position)
		else:
			GameEvents.tackle_resolved.emit(self, player_hit, true, false)
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
	var p := tackle_win_chance(defense, carrier.dribbling)
	if brain != null:
		p -= BEHIND_WIN_PENALTY * _behind_factor(carrier)
	return MatchRng.randf() < p

# ─── Engine-v2 tackle angle (Phase 7) ───────────────────────────────────────
## A tackle from behind the carrier (relative to where he's running) is less
## likely to win the ball cleanly and much more likely to be a foul; more
## aggressive players foul more. v1 tacklers keep the flat
## FOUL_CHANCE_ON_TACKLE_WIN.
const BEHIND_WIN_PENALTY := 0.12
const FOUL_BASE := 0.06
const FOUL_FROM_BEHIND := 0.35
const FOUL_AGGRESSION := 0.12

## 0 = tackling from in front or the side, 1 = straight from behind.
func _behind_factor(carrier: Player) -> float:
	if carrier.velocity.length() < 10.0:
		return 0.0
	var run := carrier.velocity.normalized()
	var to_tackler := carrier.position.direction_to(position)
	return maxf(0.0, -run.dot(to_tackler))

func _foul_chance(carrier: Player) -> float:
	if brain == null:
		return FOUL_CHANCE_ON_TACKLE_WIN
	var aggression := brain.mental.aggression / 100.0
	return clampf(FOUL_BASE + FOUL_FROM_BEHIND * _behind_factor(carrier) + FOUL_AGGRESSION * aggression, 0.02, 0.6)

## Shared with the v2 AI's tackle decision (PlayerBrain) so it judges the
## duel by the exact odds the engine will roll.
static func tackle_win_chance(tackler_defense: float, carrier_dribbling: float) -> float:
	return clampf(0.5 + (tackler_defense - carrier_dribbling) / 200.0, 0.1, 0.9)

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
