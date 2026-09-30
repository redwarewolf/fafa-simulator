class_name Substitutions
extends Node

## In-match substitutions, FM-style: a change can be queued at any moment
## (MatchHUD's CAMBIOS panel for the human side, a simple fatigue rule for the
## AI side) and is made at the next stoppage — MatchWorld calls
## apply_pending() on RESET (after a goal, and after half time) and on RESTART
## (fouls, throw-ins, corners...). Never mid-play, and never inside the
## physics step a foul is detected in (MatchWorld defers the RESTART call).
##
## Off in the headless harness (no queue, no AI subs), so match-engine
## baselines stay comparable.

const MAX_PER_SIDE := 3
## The AI side looks at its most tired outfield player at these fractions of
## the match (60' and 75'), plus at half time (see on_half_time()), and
## brings someone on if he's below AI_TIRED_STAMINA.
const AI_CHECKS := [0.667, 0.833]
const AI_TIRED_STAMINA := 70.0

## The queue or the counts changed — MatchHUD refreshes its panel.
signal changed

var _world : MatchWorld = null
var _actors : ActorsContainer = null
## Made so far, per side (true = left).
var _used := {true: 0, false: 0}
## Queued changes: {"out": Player, "in": PlayerResource, "left": bool}.
var pending : Array[Dictionary] = []
## Everyone who has left the pitch this match — for stamina write-back and
## for morale (they took part).
var subbed_off : Array[Player] = []
var _ai_check_index := 0

func setup(world: MatchWorld) -> void:
	_world = world
	_actors = world.actors_container

func enabled() -> bool:
	return not MatchConfig.headless

## Changes [param left]'s side can still queue.
func remaining(left: bool) -> int:
	var queued := pending.filter(func(s: Dictionary) -> bool: return s["left"] == left).size()
	return MAX_PER_SIDE - int(_used[left]) - queued

func used(left: bool) -> int:
	return _used[left]

## On-pitch players of [param left]'s side, in slot order.
func on_pitch(left: bool) -> Array[Player]:
	return _actors.left_team if left else _actors.right_team

## Who [param left]'s side could bring on: its club's squad minus whoever is
## on the pitch, already went off, is queued to come on, or is suspended.
func bench(left: bool) -> Array[PlayerResource]:
	var out : Array[PlayerResource] = []
	var club := DataLoader.get_club_by_team_key(_actors.team_left if left else _actors.team_right)
	if club == null:
		return out
	var taken := {}
	for p in on_pitch(left) + subbed_off:
		taken[p.player_data] = true
	for s in pending:
		taken[s["in"]] = true
	for p : PlayerResource in club.players:
		if not taken.has(p) and p.unavailable_matches <= 0:
			out.append(p)
	return out

func is_pending_out(p: Player) -> bool:
	return pending.any(func(s: Dictionary) -> bool: return s["out"] == p)

## Queues [param incoming] on for [param outgoing]. False if that side has no
## changes left, [param outgoing] is already going off or [param incoming]
## isn't on the bench.
func queue(outgoing: Player, incoming: PlayerResource) -> bool:
	if not enabled() or outgoing == null or incoming == null:
		return false
	var left := outgoing.is_left_team
	if remaining(left) <= 0 or is_pending_out(outgoing) or not incoming in bench(left) \
			or not outgoing in on_pitch(left):
		return false
	pending.append({"out": outgoing, "in": incoming, "left": left})
	changed.emit()
	return true

func cancel(index: int) -> void:
	if index >= 0 and index < pending.size():
		pending.remove_at(index)
		changed.emit()

## Makes every queued change it safely can: not the restart/kickoff taker or
## the ball carrier — those wait for the next stoppage.
func apply_pending() -> void:
	if pending.is_empty():
		return
	var ball := _actors.ball
	var keep : Array[Dictionary] = []
	for s in pending:
		var outgoing : Player = s["out"]
		if outgoing == _world.restart_taker or outgoing == ball.carrier or outgoing.is_restart_taker:
			keep.append(s)
			continue
		var incoming := _actors.substitute(outgoing, s["in"])
		if incoming == null:
			continue
		_used[s["left"]] += 1
		subbed_off.append(outgoing)
		GameEvents.substitution_made.emit(outgoing.team, outgoing.full_name, incoming.full_name)
	pending = keep
	changed.emit()

## Polled by MatchWorld every IN_PLAY frame.
func process_ai(time_fraction: float) -> void:
	if not enabled() or _ai_check_index >= AI_CHECKS.size() or time_fraction < AI_CHECKS[_ai_check_index]:
		return
	_ai_check_index += 1
	_ai_consider(not _actors.is_player_team_left)

func on_half_time() -> void:
	if enabled():
		_ai_consider(not _actors.is_player_team_left)

## The AI side's rule: the most tired outfield player, if he's tired enough,
## for the best bench player in his position (or his line, or anyone).
func _ai_consider(left: bool) -> void:
	if remaining(left) <= 0:
		return
	var tired : Player = null
	for p in on_pitch(left):
		if p.role == Positions.Role.GK or not SpecialPlayerTypes.movable(p.special_type) or is_pending_out(p):
			continue
		if p.stamina < AI_TIRED_STAMINA and (tired == null or p.stamina < tired.stamina):
			tired = p
	if tired == null:
		return
	var best := best_replacement(tired, bench(left))
	if best != null:
		queue(tired, best)

## Best bench option for [param outgoing]'s slot: same position first, then
## same line, then any outfield player — highest overall within the tier.
## Null when the bench has nobody who fits at all.
static func best_replacement(outgoing: Player, candidates: Array[PlayerResource]) -> PlayerResource:
	var tiers := [
		func(p: PlayerResource) -> bool: return p.role == outgoing.role,
		func(p: PlayerResource) -> bool: return Positions.group(p.role) == Positions.group(outgoing.role),
		func(p: PlayerResource) -> bool: return p.role != Positions.Role.GK,
	]
	for fits : Callable in tiers:
		var best : PlayerResource = null
		for p in candidates:
			if fits.call(p) and (best == null or p.overall() > best.overall()):
				best = p
		if best != null:
			return best
	return null
